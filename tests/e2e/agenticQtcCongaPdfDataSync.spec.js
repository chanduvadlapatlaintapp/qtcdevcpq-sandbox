// @ts-check
/**
 * agenticQtcCongaPdfDataSync.spec.js
 *
 * Verifies that the most-recent Conga-generated OSA PDF on an amendment quote
 * stays in sync with the current Salesforce-side quote data.
 *
 * Flow (API-only — no browser interaction required):
 *   1. Find the latest amendment quote on the target account (or honour
 *      QTC_QUOTE_NAME override).
 *   2. Locate the most recent PDF in ContentDocumentLink across quote /
 *      contract / opportunity / account.
 *   3. Snapshot current Salesforce quote + line data via REST.
 *   4. Download the PDF, extract text via pdf-parse.
 *   5. Field-by-field tolerant compare (currency tolerance, multi-format
 *      date matching, case-insensitive strings).
 *   6. Emit per-field rows to the dashboard's UI↔DB tab and assert zero
 *      mismatches.
 *
 * NOTE: this verifies that what Conga last rendered matches what SF holds
 *       *now*. If the SF data changed since the PDF was generated, the
 *       diff reflects drift rather than a Conga bug. Run shortly after
 *       generation for the strictest interpretation.
 */
const fs   = require('fs');
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const {
  snapshotForOsa,
  findLatestPdfOnEntities,
  downloadPdfText,
  comparePdfToSnapshot,
} = require('./utils/congaDoc');

const KIND              = 'congaPdfDataSync';
const ACCOUNT_NAME      = process.env.QTC_ACCOUNT_FULL_NAME || process.env.QTC_ACCOUNT_NAME || 'Jacobs Holding AG';
const QUOTE_NAME_OVR    = process.env.QTC_QUOTE_NAME || null;   // optional pin to a specific quote
const SF_API_VER        = 'v62.0';
const RESULTS_DIR       = path.join(__dirname, 'results');

/** @type {{instanceUrl: string, lightningUrl: string, accessToken: string}} */
let sfCtx;

test.beforeAll(async () => {
  const creds = getSfCredentials();
  sfCtx = {
    instanceUrl:  creds.instanceUrl,
    lightningUrl: creds.lightningUrl,
    accessToken:  creds.accessToken,
  };
});

/**
 * @param {string} soql
 * @returns {Promise<any>}
 */
async function sfQuery(soql) {
  const response = await fetch(
    `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/query?q=${encodeURIComponent(soql.replace(/\s+/g, ' ').trim())}`,
    { headers: { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' } }
  );
  if (!response.ok) throw new Error(`SOQL failed: ${response.status} ${await response.text()}`);
  return response.json();
}

/** @param {string} s */
const escSoql = (s) => s.replace(/'/g, "\\'");

/**
 * Pick the most recently-modified amendment quote on the target account.
 * If QTC_QUOTE_NAME is set, use that quote instead. Returns null when no
 * matching quote exists.
 *
 * @returns {Promise<{Id: string, Name: string, contractNumber: string|null, accountId: string|null, opportunityId: string|null} | null>}
 */
async function findTargetQuote() {
  let soql;
  if (QUOTE_NAME_OVR) {
    soql = `SELECT Id, Name, SBQQ__MasterContract__c, SBQQ__MasterContract__r.ContractNumber,
                   SBQQ__Account__c, SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE Name = '${escSoql(QUOTE_NAME_OVR)}'
            LIMIT 1`;
  } else {
    // Newest amendment quote on the account (any status). We prefer ones that
    // have actually been edited / had PDFs generated against them; pure draft
    // empties usually have no PDFs and would just SKIP.
    soql = `SELECT Id, Name, SBQQ__MasterContract__c, SBQQ__MasterContract__r.ContractNumber,
                   SBQQ__Account__c, SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE SBQQ__Account__r.Name = '${escSoql(ACCOUNT_NAME)}'
            AND SBQQ__Type__c = 'Amendment'
            ORDER BY LastModifiedDate DESC
            LIMIT 1`;
  }
  const res = await sfQuery(soql);
  const rec = res.records?.[0];
  if (!rec) return null;
  return {
    Id:             rec.Id,
    Name:           rec.Name,
    contractNumber: rec.SBQQ__MasterContract__r?.ContractNumber ?? null,
    accountId:      rec.SBQQ__Account__c ?? null,
    opportunityId:  rec.SBQQ__Opportunity2__c ?? null,
  };
}

test('Conga PDF ↔ Salesforce data sync (latest PDF on amendment quote)', async () => {
  test.slow();
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);
  console.log(`\n[${KIND}] runDir=${runDir}`);
  console.log(`[${KIND}] Account: "${ACCOUNT_NAME}"${QUOTE_NAME_OVR ? ` · quote override: ${QUOTE_NAME_OVR}` : ''}`);

  // 1. Find target quote ────────────────────────────────────────────────
  const quote = await findTargetQuote();
  if (!quote) {
    const reason = QUOTE_NAME_OVR
      ? `Quote "${QUOTE_NAME_OVR}" not found`
      : `No amendment quote found on account "${ACCOUNT_NAME}"`;
    console.log(`[${KIND}] SKIP — ${reason}`);
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_NAME,
      scenarioNumber: 1,
      scenarioLabel:  'Conga PDF ↔ SF data sync',
      contract: null, quoteName: null, quoteId: null,
      passed: true,
      extra: { skipped: true, reason },
    });
    test.skip(true, reason);
    return;
  }
  console.log(`[${KIND}] Quote: ${quote.Name} (${quote.Id}) · contract=${quote.contractNumber}`);

  // 2. Locate the latest PDF ────────────────────────────────────────────
  /** @type {string[]} */
  const linkedIds = [quote.Id, quote.opportunityId, quote.accountId]
    .filter(/** @returns {x is string} */ (x) => typeof x === 'string' && x.length > 0);
  // Also pull in the contract Id for completeness (some Conga templates link to contract).
  if (quote.contractNumber) {
    const cRes = await sfQuery(
      `SELECT Id FROM Contract WHERE ContractNumber = '${escSoql(quote.contractNumber)}' LIMIT 1`
    );
    const cid = cRes.records?.[0]?.Id;
    if (cid) linkedIds.push(cid);
  }
  console.log(`[${KIND}] Searching for PDFs linked to ${linkedIds.length} entit(ies)…`);
  const pdf = await findLatestPdfOnEntities(sfCtx, linkedIds);
  if (!pdf) {
    const reason = `No PDF found on quote/contract/opportunity/account — generate one via the OSA wizard first, then re-run`;
    console.log(`[${KIND}] SKIP — ${reason}`);
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_NAME,
      scenarioNumber: 1,
      scenarioLabel:  'Conga PDF ↔ SF data sync',
      contract: quote.contractNumber, quoteName: quote.Name, quoteId: quote.Id,
      passed: true,
      extra: { skipped: true, reason, quote },
    });
    test.skip(true, reason);
    return;
  }
  console.log(`[${KIND}] PDF: "${pdf.title}" created ${pdf.createdDate} linked to ${pdf.linkedEntityId}`);

  // 3. Snapshot current SF data ────────────────────────────────────────
  const snapshot = await snapshotForOsa(sfCtx, {
    quoteName:      quote.Name,
    accountName:    ACCOUNT_NAME,
    contractNumber: quote.contractNumber,
  });
  console.log(`[${KIND}] Snapshot taken: ${snapshot.lines.length} line(s), net=${snapshot.netAmount}`);

  // 4. Download + parse the PDF ─────────────────────────────────────────
  const { text, numPages } = await downloadPdfText(sfCtx, pdf.contentVersionId);
  console.log(`[${KIND}] Downloaded "${pdf.title}" (${numPages} page(s), ${text.length} char(s))`);

  // 5. Compare ─────────────────────────────────────────────────────────
  const cmp = comparePdfToSnapshot(snapshot, text);
  console.log(`[${KIND}] PDF compare: ${cmp.matches} match(es), ${cmp.mismatches} mismatch(es)`);

  // Dump the raw PDF text + extracted numbers next to the rich results so
  // template-vs-SF drift can be diagnosed at a glance (the rendered PDF can
  // omit fields that are present in SF, or format numbers/dates differently).
  // Captured numbers help explain numeric mismatches when the regex misses
  // a value that's "visually" in the PDF (split spans, non-breaking spaces, etc.).
  fs.writeFileSync(path.join(runDir, 'pdf-text.txt'), text, 'utf8');
  fs.writeFileSync(
    path.join(runDir, 'pdf-numbers.json'),
    JSON.stringify({ count: cmp.pdfNumbers.length, numbers: cmp.pdfNumbers }, null, 2),
    'utf8'
  );
  console.log(`[${KIND}] Dumped PDF text → ${path.join(runDir, 'pdf-text.txt')} (${cmp.pdfNumbers.length} numeric token(s) extracted)`);

  // 6. Build dashboard rows (UI↔DB tab is the comparison view) ─────────
  const uiDbCrossCheck = cmp.rows.map((r, i) => ({
    uiIndex:  i + 1,
    product:  r.field,                            // field name (e.g. "Line 1 (Foo) — qty")
    segOcc:   null,
    uiBefore: null,
    uiAfter:  r.expected,                         // value Salesforce holds
    dbPrior:  null,
    dbAfter:  r.inPdf,                            // ✓ if found in PDF, ✗ if missing
    match:    r.match,
    hasData:  true,
  }));
  const dbComparison = cmp.rows.map((r, i) => ({
    index:    i + 1,
    product:  r.field,
    segKey:   r.match ? '✓' : '✗',
    segIndex: null,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
    dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
    isBundle: false,
    startDate: null, endDate: null,
    pricingMethod: null, term: null, regularPrice: null,
  }));
  const dbAnomalies = cmp.rows
    .filter(r => !r.match)
    .map(r => ({
      severity: 'HIGH',
      type: 'pdf-sf-mismatch',
      detail: `${r.field}: SF=${r.expected} | PDF=${r.inPdf}`,
    }));

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_NAME,
    scenarioNumber: 1,
    scenarioLabel:  'Conga PDF ↔ SF data sync',
    contract: quote.contractNumber, quoteName: quote.Name, quoteId: quote.Id,
    pdfGenerated: true,
    pdfSkipped: false,
    dbLineCount: dbComparison.length,
    dbComparison, uiDbCrossCheck,
    crossCheckMismatches: cmp.mismatches,
    dbAnomalies,
    passed: cmp.mismatches === 0,
    extra: {
      pdfTitle:        pdf.title,
      pdfCreatedDate:  pdf.createdDate,
      pdfNumPages:     numPages,
      pdfLinkedTo:     pdf.linkedEntityId,
      snapshotLines:   snapshot.lines.length,
      pdfMatches:      cmp.matches,
      pdfMismatches:   cmp.mismatches,
    },
  });

  // 7. Assert ──────────────────────────────────────────────────────────
  expect(
    cmp.mismatches,
    `Conga PDF should match current SF data (${cmp.matches}✓ / ${cmp.mismatches}✗):\n` +
    cmp.rows.filter(r => !r.match).map(r => `  ${r.field}: SF=${r.expected} | PDF=${r.inPdf}`).join('\n')
  ).toBe(0);
});
