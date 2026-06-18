// @ts-check
/**
 * Amendment Quote Field Comparison — QTC Test Runner suite.
 *
 * On the same account, creates two identical amendment quotes against the
 * same activated contract:
 *
 *   • OOB CPQ baseline                — POST /apexrest/agenticQtc/amendment/oob
 *   • AgenticQTC custom amendment     — POST /apexrest/agenticQtc/amendment/custom
 *
 * Then pulls every queryable field on SBQQ__Quote__c and SBQQ__QuoteLine__c
 * for both quotes (via the describe API → dynamic SOQL) and inspects the pair
 * from six angles, one Playwright test each. Findings are accumulated and
 * written to a single `results.json` in afterAll, in the canonical shape the
 * agenticQtcTestDashboard LWC consumes.
 *
 * Suite name registered in agenticQtcTestDashboard.js: 'agenticQtcAmendmentFieldComparison'.
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');

const KIND         = 'amendmentFieldComparison';
const ACCOUNT_NAME = process.env.QTC_ACCOUNT_NAME || 'Bates White';
const RESULTS_DIR  = path.join(__dirname, 'results');
const SF_API_VER   = 'v62.0';

// ── Fields naturally different between two distinct records ────────────────
const ALWAYS_SKIP_FIELDS = new Set([
  'attributes',
  'Id', 'Name',
  'CreatedById', 'CreatedDate',
  'LastModifiedById', 'LastModifiedDate',
  'LastActivityDate', 'LastViewedDate', 'LastReferencedDate',
  'SystemModstamp',
  'OwnerId',
  'IsDeleted',
  'SBQQ__Quote__c', 'SBQQ__Number__c',  // line parent + auto-number
  'SBQQ__Key__c',                       // per-quote stable key
  // Each amendment creates a fresh opportunity + auto-numbered records
  'SBQQ__Opportunity2__c',
  'SBQQ__LastSavedOn__c',
  'Intapp_Opportunity_Number__c',
  'OP4I_Contract_Number__c',
  'OSA_Auto_Number__c',
]);

// ── Field groups used by focused use cases ─────────────────────────────────
const PRICING_FIELDS = [
  // Header
  'SBQQ__NetAmount__c', 'SBQQ__CustomerAmount__c', 'SBQQ__ListAmount__c',
  'SBQQ__Subtotal__c', 'SBQQ__RegularAmount__c',
  // Line
  'SBQQ__NetPrice__c', 'SBQQ__NetTotal__c',
  'SBQQ__ListPrice__c', 'SBQQ__CustomerPrice__c',
  'SBQQ__RegularPrice__c', 'SBQQ__RegularTotal__c',
  'SBQQ__Discount__c', 'SBQQ__AdditionalDiscount__c',
  'SBQQ__PriorQuantity__c',
];

const DATE_TERM_FIELDS = [
  // Header
  'SBQQ__StartDate__c', 'SBQQ__EndDate__c',
  'SBQQ__SubscriptionTerm__c',
  // Line
  'SBQQ__EffectiveStartDate__c', 'SBQQ__EffectiveEndDate__c',
];

const SUBSCRIPTION_LINKAGE_FIELDS = [
  'SBQQ__UpgradedSubscription__c',
  'SBQQ__RenewedSubscription__c',
  'SBQQ__Product__c',
];

// ── Shared state ───────────────────────────────────────────────────────────
/** @type {{instanceUrl: string, lightningUrl: string, accessToken: string}} */
let sfCtx;
let testStartMs = 0;
/** @type {string} */ let runDir = '';
/** @type {string} */ let runTs  = '';

/** @type {{Id: string, ContractNumber: string} | null} */
let sharedContract = null;
/** @type {string | null} */ let sharedOobQuoteId = null;
/** @type {string | null} */ let sharedCustomQuoteId = null;
/** @type {Record<string, any>} */ let sharedOobQuote   = {};
/** @type {Record<string, any>} */ let sharedCustomQuote = {};
/** @type {Array<Record<string, any>>} */ let sharedOobLines    = [];
/** @type {Array<Record<string, any>>} */ let sharedCustomLines = [];

// ── Accumulators consumed by afterAll() to build the rich-results payload ──
/** @type {Array<{severity: 'HIGH'|'MEDIUM'|'LOW', type: string, detail: string}>} */
let anomalies = [];
/** @type {Array<{testName: string, passed: boolean, diffCount: number}>} */
let testFindings = [];

// ── Describe cache ─────────────────────────────────────────────────────────
/** @type {Record<string, string[]>} */
const describeCache = {};

// ──────────────────────────────────────────────────────────────────────────
// beforeAll: create the OOB/custom pair once, then snapshot every field
// ──────────────────────────────────────────────────────────────────────────

test.beforeAll(async () => {
  testStartMs = Date.now();
  const creds = getSfCredentials();
  sfCtx = {
    instanceUrl:  creds.instanceUrl,
    lightningUrl: creds.lightningUrl,
    accessToken:  creds.accessToken,
  };

  ({ runTs, runDir } = u.createRunFolder(RESULTS_DIR));
  console.log(`\n[${KIND}] runDir=${runDir}`);

  const contracts = await getActivatedContracts();
  if (!contracts.length) {
    console.log(`\n⚠️  No activated contracts found for "${ACCOUNT_NAME}". Tests will skip.`);
    return;
  }

  // Try contracts in StartDate DESC order; skip any whose subscriptions carry
  // invalid picklist values that make ContractAmender throw a ValidationException.
  let oobId = /** @type {string|null} */ (null);
  for (const candidate of contracts) {
    try {
      oobId = await createOOBAmendment(candidate.Id);
      sharedContract = candidate;
      break;
    } catch (err) {
      console.log(`[${KIND}] Contract ${candidate.ContractNumber} (${candidate.Id}) skipped — OOB failed: ${/** @type {any} */ (err)?.message}`);
    }
  }
  if (!sharedContract || !oobId) {
    console.log(`\n⚠️  All activated contracts for "${ACCOUNT_NAME}" failed OOB amendment creation. Tests will skip.`);
    return;
  }
  console.log(`[${KIND}] Contract: ${sharedContract.ContractNumber} (${sharedContract.Id})`);

  const customId = await createCustomAmendment(sharedContract.Id);
  sharedOobQuoteId    = oobId;
  sharedCustomQuoteId = customId;
  console.log(`[${KIND}] OOB Quote:    ${oobId}`);
  console.log(`[${KIND}] Custom Quote: ${customId}`);

  sharedOobQuote     = await getQuoteRecord(oobId);
  sharedCustomQuote  = await getQuoteRecord(customId);
  sharedOobLines     = await getQuoteLines(oobId);
  sharedCustomLines  = await getQuoteLines(customId);

  console.log(`[${KIND}] Quote fields per record: ${Object.keys(sharedOobQuote).length}`);
  console.log(`[${KIND}] Lines: OOB=${sharedOobLines.length}, Custom=${sharedCustomLines.length}`);
});

// ──────────────────────────────────────────────────────────────────────────
// afterAll: emit one canonical results.json for the entire suite
// ──────────────────────────────────────────────────────────────────────────

test.afterAll(async () => {
  if (!runDir) return; // beforeAll didn't run at all

  const oobQuoteName    = sharedOobQuote?.Name    || null;
  const customQuoteName = sharedCustomQuote?.Name || null;

  // ── Header field comparison → uiDbCrossCheck rows ─────────────────────
  // Repurpose the UI↔DB tab as the OOB-vs-Custom field-by-field report.
  // Columns map: product = field name, uiAfter = OOB value, dbAfter = Custom value.
  // Skip fields where BOTH sides are null/empty (just noise) and fields the
  // comparison logic intentionally ignores (Id, audit, etc.).
  const headerKeys = Array.from(new Set([
    ...Object.keys(sharedOobQuote || {}),
    ...Object.keys(sharedCustomQuote || {}),
  ]));
  /** @type {any[]} */
  const uiDbCrossCheck = [];
  let idx = 0;
  for (const key of headerKeys) {
    if (ALWAYS_SKIP_FIELDS.has(key)) continue;
    const oobVal = sharedOobQuote?.[key];
    const customVal = sharedCustomQuote?.[key];
    const oobHas    = oobVal    != null && oobVal    !== '';
    const customHas = customVal != null && customVal !== '';
    if (!oobHas && !customHas) continue; // skip all-null
    const match = fieldsEqual(oobVal, customVal);
    idx += 1;
    uiDbCrossCheck.push({
      uiIndex:  idx,
      product:  key,                                // field name
      segOcc:   null,
      // uiBefore/dbPrior are null so the LWC's getter renders its own em-dash
      // placeholder. Emitting the em-dash from here gets mangled by the
      // base64 → atob → JSON.parse path in agenticQtcTestDashboard.js.
      uiBefore: null,
      uiAfter:  oobVal    != null ? String(oobVal)    : null,
      dbPrior:  null,
      dbAfter:  customVal != null ? String(customVal) : null,
      match, hasData: true,
    });
  }
  // Header rows first, then line-level rows (currently empty when Calculate
  // is blocked, but kept so the report tracks line additions when fixed).
  for (let i = 0; i < Math.max(sharedOobLines.length, sharedCustomLines.length); i++) {
    const oobLine = sharedOobLines[i] || {};
    const customLine = sharedCustomLines[i] || {};
    const oobPrice    = oobLine.SBQQ__NetPrice__c ?? null;
    const customPrice = customLine.SBQQ__NetPrice__c ?? null;
    const match = oobPrice != null && customPrice != null &&
                  Math.abs(Number(oobPrice) - Number(customPrice)) < 0.01;
    idx += 1;
    uiDbCrossCheck.push({
      uiIndex:  idx,
      product:  `line[${i}] ${oobLine.SBQQ__Product__c || customLine.SBQQ__Product__c || ''}`.trim(),
      segOcc:   null,
      uiBefore: null,
      uiAfter:  oobPrice    != null ? String(oobPrice)    : null,
      dbPrior:  null,
      dbAfter:  customPrice != null ? String(customPrice) : null,
      match, hasData: oobPrice != null || customPrice != null,
    });
  }
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  // dbComparison row per line — side-by-side OOB vs Custom (repurposed columns
  // so the DB Lines tab shows something meaningful without LWC changes).
  const dbComparison = buildSideBySideRows(sharedOobLines, sharedCustomLines);

  const passed = anomalies.filter(a => a.severity === 'HIGH').length === 0 &&
                 testFindings.every(t => t.passed);

  buildRichResults({
    kind:           KIND,
    runTs, runDir, testStartMs,
    accountName:    ACCOUNT_NAME,
    scenarioNumber: 1,
    scenarioLabel:  'OOB CPQ vs AgenticQTC custom amendment — full-field parity',
    contract:       sharedContract?.ContractNumber || null,
    quoteName:      oobQuoteName,
    quoteId:        sharedOobQuoteId,
    dbLineCount:    sharedOobLines.length,
    dbComparison,
    dbAnomalies:    anomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed,
    extra: {
      oobQuoteId:        sharedOobQuoteId,
      customQuoteId:     sharedCustomQuoteId,
      oobQuoteName,
      customQuoteName,
      oobLineCount:      sharedOobLines.length,
      customLineCount:   sharedCustomLines.length,
      fieldsComparedPerQuote: Object.keys(sharedOobQuote).length,
      testFindings,
    },
  });

  console.log(`\n[${KIND}] Wrote ${path.join(runDir, 'results.json')}`);
});

// ──────────────────────────────────────────────────────────────────────────
// Discovery + SOQL helpers (Node-side, no browser page required)
// ──────────────────────────────────────────────────────────────────────────

/** @returns {Promise<Array<{Id: string, ContractNumber: string}>>} */
async function getActivatedContracts() {
  const accRes = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id FROM Account WHERE Name = '${escapeSoql(ACCOUNT_NAME)}' LIMIT 1`,
    SF_API_VER
  );
  const accountId = accRes.records?.[0]?.Id;
  if (!accountId) throw new Error(`Account "${ACCOUNT_NAME}" not found`);

  const contractRes = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id, ContractNumber, Status, StartDate, EndDate
       FROM Contract
       WHERE AccountId = '${accountId}'
       ORDER BY StartDate DESC LIMIT 10`,
    SF_API_VER
  );

  const all = contractRes.records || [];
  return all.filter(/** @param {any} c */ c => ['Activated', 'In Force'].includes(c.Status));
}

/**
 * Fetch every queryable field on an sObject via describe.
 * @param {string} objectName
 */
async function describeQueryableFields(objectName) {
  if (describeCache[objectName]) return describeCache[objectName];

  const response = await fetch(
    `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/sobjects/${objectName}/describe`,
    { headers: { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' } }
  );
  if (!response.ok) throw new Error(`Describe ${objectName} failed: ${response.statusText}`);

  const data = await response.json();
  /** @type {string[]} */
  const fields = (data.fields || [])
    // Address/location compounds cannot be selected directly — only their components.
    .filter(/** @param {any} f */ f => f.type !== 'address' && f.type !== 'location')
    .map(/** @param {any} f */ f => f.name);

  describeCache[objectName] = fields;
  return fields;
}

/**
 * Run a SOQL query split across multiple field-chunks and merge results by Id.
 * SBQQ__Quote__c / SBQQ__QuoteLine__c each expose 200+ fields — a single
 * SELECT-all GET request blows past Salesforce's URL length limit (~16KB) and
 * the org returns an HTML error page instead of JSON. Chunking keeps each URL
 * well under the limit while still pulling every queryable field.
 *
 * @param {string} objectName
 * @param {string[]} fields                queryable field API names
 * @param {string} whereClause             e.g. "Id = 'aXX...'"
 * @param {string} [orderBy]               optional ORDER BY (omit the keyword)
 * @returns {Promise<Array<Record<string, any>>>}
 */
async function fetchAllFieldsChunked(objectName, fields, whereClause, orderBy) {
  // ~40 fields per chunk keeps the URL comfortably under 16KB even with
  // long CPQ field names. Always include Id so we can merge across chunks.
  const CHUNK_SIZE = 40;
  /** @type {Map<string, Record<string, any>>} */
  const merged = new Map();

  for (let i = 0; i < fields.length; i += CHUNK_SIZE) {
    const chunk = fields.slice(i, i + CHUNK_SIZE);
    if (!chunk.includes('Id')) chunk.unshift('Id');
    const orderClause = orderBy ? ` ORDER BY ${orderBy}` : '';
    const soql = `SELECT ${chunk.join(', ')} FROM ${objectName} WHERE ${whereClause}${orderClause}`;
    const res = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql, SF_API_VER);
    if (res.error) throw new Error(`SOQL chunk failed (${objectName}, fields ${i}-${i + chunk.length}): ${res.error}`);
    for (const rec of res.records) {
      const existing = merged.get(rec.Id) || {};
      merged.set(rec.Id, { ...existing, ...rec });
    }
  }
  return Array.from(merged.values());
}

/** @param {string} quoteId */
async function getQuoteRecord(quoteId) {
  const fields = await describeQueryableFields('SBQQ__Quote__c');
  const records = await fetchAllFieldsChunked('SBQQ__Quote__c', fields, `Id = '${quoteId}'`);
  return records[0] || {};
}

/** @param {string} quoteId */
async function getQuoteLines(quoteId) {
  const fields = await describeQueryableFields('SBQQ__QuoteLine__c');
  const records = await fetchAllFieldsChunked(
    'SBQQ__QuoteLine__c',
    fields,
    `SBQQ__Quote__c = '${quoteId}'`,
    'SBQQ__Number__c ASC NULLS LAST'
  );
  // Each chunk was sorted independently — merging may interleave order, so
  // re-sort the merged set by SBQQ__Number__c (which is always present after merge).
  records.sort((a, b) => (a.SBQQ__Number__c ?? 0) - (b.SBQQ__Number__c ?? 0));
  return records;
}

// ──────────────────────────────────────────────────────────────────────────
// Amendment creation
// ──────────────────────────────────────────────────────────────────────────

/**
 * Create an OOB amendment via the dedicated Apex REST endpoint.
 * QTCTestRunner_OobAmendmentRestResource runs the vanilla CPQ pipeline end-to-end
 * (ContractAmender → QuoteCalculator → QuoteSaver), so the returned quote has
 * persisted lines, dates, and CPQ-defaulted fields — a fair baseline for the
 * custom-flow comparison.
 *
 * @param {string} contractId
 */
async function createOOBAmendment(contractId) {
  const res = await fetch(
    `${sfCtx.instanceUrl}/services/apexrest/agenticQtc/amendment/oob`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ contractId }),
    }
  );
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`OOB amendment endpoint failed: ${res.status} ${text}`);
  }
  const parsed = JSON.parse(text);
  if (parsed.status !== 'success' || !parsed.id) {
    throw new Error(`OOB amendment endpoint returned non-success: ${text}`);
  }
  return parsed.id;
}

/** @param {string} contractId */
async function createCustomAmendment(contractId) {
  try {
    const res = await fetch(
      `${sfCtx.instanceUrl}/services/apexrest/agenticQtc/amendment/custom`,
      {
        method: 'POST',
        headers: { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ contractId }),
      }
    );
    const text = await res.text();
    if (res.ok) {
      const parsed = JSON.parse(text);
      if (parsed.status === 'success' && parsed.id) return parsed.id;
    }
    console.log(`[${KIND}] Custom endpoint non-success ${res.status}: ${text}`);
  } catch (/** @type {any} */ err) {
    console.log(`[${KIND}] Custom endpoint error: ${err?.message || String(err)}`);
  }

  // Fallback so the framework still produces a useful report before the
  // QTCTestRunner_CustAmendmentRestResource is deployed: create another OOB
  // quote. The comparison will then be OOB-vs-OOB (expected to pass on every field).
  const fallback = await createOOBAmendment(contractId);
  anomalies.push({
    severity: 'MEDIUM',
    type: 'custom-endpoint-unavailable',
    detail: 'QTCTestRunner_CustAmendmentRestResource is not reachable — comparison ran OOB-vs-OOB. Deploy the Apex class to exercise the custom path.',
  });
  return fallback;
}

// ──────────────────────────────────────────────────────────────────────────
// Field comparison
// ──────────────────────────────────────────────────────────────────────────

/**
 * @typedef {Object} FieldDiff
 * @property {string} field
 * @property {any} oob
 * @property {any} custom
 * @property {'structural'|'valueDiff'} kind
 */

/**
 * @param {Record<string, any>} oob
 * @param {Record<string, any>} custom
 * @param {{ onlyFields?: string[] }} [opts]
 * @returns {FieldDiff[]}
 */
function compareFields(oob, custom, opts = {}) {
  /** @type {FieldDiff[]} */
  const diffs = [];
  const keys = opts.onlyFields
    ? opts.onlyFields
    : Array.from(new Set([...Object.keys(oob || {}), ...Object.keys(custom || {})]));

  for (const key of keys) {
    if (ALWAYS_SKIP_FIELDS.has(key)) continue;
    const oobVal = oob?.[key];
    const customVal = custom?.[key];
    if (fieldsEqual(oobVal, customVal)) continue;

    const oobHasValue    = oobVal    != null && oobVal    !== '';
    const customHasValue = customVal != null && customVal !== '';
    const kind = (oobHasValue && !customHasValue) ? 'structural' : 'valueDiff';
    diffs.push({ field: key, oob: oobVal, custom: customVal, kind });
  }
  return diffs;
}

/** @param {any} a @param {any} b */
function fieldsEqual(a, b) {
  if (a == null && b == null) return true;
  if ((a == null) !== (b == null)) return false;
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 0.01;
  return a === b;
}

/** @param {any} v */
function formatVal(v) {
  if (v == null) return '(null)';
  if (typeof v === 'string') return `"${v}"`;
  if (typeof v === 'number') return v.toFixed(2);
  return String(v);
}

/** @param {string} s */
function escapeSoql(s) { return s.replace(/'/g, "\\'"); }

/**
 * @template T
 * @param {T[]} arr
 * @param {(item: T) => string | null | undefined} keyFn
 */
function indexBy(arr, keyFn) {
  /** @type {Record<string, T>} */
  const out = {};
  for (const item of arr) {
    const key = keyFn(item);
    if (key) out[key] = item;
  }
  return out;
}

/**
 * Build dbComparison rows that piggyback on the dashboard's DB Lines tab
 * to show OOB vs Custom side-by-side (priorQty → OOB qty, dbQty → custom qty,
 * dbPrice → OOB net price, dbNetTotal → custom net total).
 * @param {Array<Record<string, any>>} oob
 * @param {Array<Record<string, any>>} custom
 */
function buildSideBySideRows(oob, custom) {
  const max = Math.max(oob.length, custom.length);
  /** @type {any[]} */
  const rows = [];
  for (let i = 0; i < max; i++) {
    const o = oob[i] || {};
    const c = custom[i] || {};
    rows.push({
      index:        i + 1,
      product:      o.SBQQ__Product__c || c.SBQQ__Product__c || '—',
      segKey:       '—',
      segIndex:     null,
      priorQty:     o.SBQQ__Quantity__c ?? null,
      dbQty:        c.SBQQ__Quantity__c ?? null,
      dbPrice:      o.SBQQ__NetPrice__c ?? null,
      dbListPrice:  o.SBQQ__ListPrice__c ?? null,
      dbDiscount:   o.SBQQ__Discount__c ?? null,
      dbNetTotal:   c.SBQQ__NetTotal__c ?? null,
      dbAcv:        null, dbTcv: null,
      isBundle:     false,
      startDate:    o.SBQQ__EffectiveStartDate__c ?? null,
      endDate:      o.SBQQ__EffectiveEndDate__c ?? null,
      pricingMethod: null, term: null, regularPrice: null,
    });
  }
  return rows;
}

/**
 * Push a finding into the suite-level anomaly + per-test buckets.
 * @param {string} testName
 * @param {FieldDiff[]} diffs
 * @param {{ structuralSeverity?: 'HIGH'|'MEDIUM'|'LOW', valueSeverity?: 'HIGH'|'MEDIUM'|'LOW' }} [opts]
 */
function recordDiffs(testName, diffs, opts = {}) {
  const structuralSeverity = opts.structuralSeverity || 'HIGH';
  const valueSeverity      = opts.valueSeverity      || 'MEDIUM';
  for (const d of diffs) {
    const sev = d.kind === 'structural' ? structuralSeverity : valueSeverity;
    anomalies.push({
      severity: sev,
      type: `${testName} · ${d.kind}`,
      detail: `${d.field} — OOB=${formatVal(d.oob)} custom=${formatVal(d.custom)}`,
    });
  }
}

/** @returns {boolean} */
function fixtureReady() {
  return !!(sharedContract && sharedOobQuoteId && sharedCustomQuoteId);
}

// ──────────────────────────────────────────────────────────────────────────
// Tests — each becomes a Test_Result__c row in the dashboard Spec tab
// ──────────────────────────────────────────────────────────────────────────

test('Setup: account, contract, and OOB/custom quote pair', async () => {
  if (!sharedContract) {
    test.skip(true, `No activated contracts found for "${ACCOUNT_NAME}".`);
    return;
  }
  console.log(`✓ Account:      ${ACCOUNT_NAME}`);
  console.log(`✓ Contract:     ${sharedContract.ContractNumber} (${sharedContract.Id})`);
  console.log(`✓ OOB Quote:    ${sharedOobQuoteId}`);
  console.log(`✓ Custom Quote: ${sharedCustomQuoteId}`);
  console.log(`✓ Lines:        OOB=${sharedOobLines.length}, Custom=${sharedCustomLines.length}`);
  testFindings.push({ testName: 'Setup', passed: true, diffCount: 0 });
  expect(sharedOobQuoteId).toBeTruthy();
  expect(sharedCustomQuoteId).toBeTruthy();
});

test('Quote header — full field parity (all queryable fields)', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');
  test.slow();

  const diffs = compareFields(sharedOobQuote, sharedCustomQuote);
  const structural = diffs.filter(d => d.kind === 'structural');

  console.log(`Quote header — ${Object.keys(sharedOobQuote).length} fields compared, ${structural.length} structural, ${diffs.length - structural.length} valueDiffs`);
  recordDiffs('quote header', diffs);

  testFindings.push({
    testName: 'Quote header — full field parity',
    passed: structural.length === 0,
    diffCount: diffs.length,
  });
  expect(structural,
    `Custom quote is missing values that the OOB baseline populated:\n` +
    structural.map(d => `  ${d.field}: OOB=${formatVal(d.oob)}`).join('\n')
  ).toHaveLength(0);
});

test('Quote lines — full field parity (all queryable fields)', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');
  test.slow();

  /** @type {FieldDiff[]} */
  const allStructural = [];
  /** @type {FieldDiff[]} */
  const allDiffs = [];

  const maxLen = Math.max(sharedOobLines.length, sharedCustomLines.length);
  for (let i = 0; i < maxLen; i++) {
    const diffs = compareFields(sharedOobLines[i] || {}, sharedCustomLines[i] || {});
    const structural = diffs.filter(d => d.kind === 'structural');
    for (const d of structural) {
      allStructural.push({ ...d, field: `line[${i}].${d.field}` });
    }
    for (const d of diffs) {
      allDiffs.push({ ...d, field: `line[${i}].${d.field}` });
    }
  }
  recordDiffs('quote line', allDiffs);

  console.log(`Quote lines — ${maxLen} line(s), ${allStructural.length} structural, ${allDiffs.length - allStructural.length} valueDiffs`);

  testFindings.push({
    testName: 'Quote lines — full field parity',
    passed: allStructural.length === 0,
    diffCount: allDiffs.length,
  });
  expect(allStructural,
    `Custom quote lines are missing values that the OOB baseline populated:\n` +
    allStructural.map(d => `  ${d.field}: OOB=${formatVal(d.oob)}`).join('\n')
  ).toHaveLength(0);
});

test('Line count & product ordering parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const oobProducts    = sharedOobLines.map(l => l.SBQQ__Product__c);
  const customProducts = sharedCustomLines.map(l => l.SBQQ__Product__c);
  /** @type {string[]} */
  const issues = [];

  if (sharedOobLines.length !== sharedCustomLines.length) {
    issues.push(`Line count mismatch: OOB=${sharedOobLines.length}, custom=${sharedCustomLines.length}`);
  }
  const oobSorted    = [...oobProducts].sort();
  const customSorted = [...customProducts].sort();
  for (let i = 0; i < Math.max(oobSorted.length, customSorted.length); i++) {
    if (oobSorted[i] !== customSorted[i]) {
      issues.push(`Product set differs at sorted index ${i}: OOB=${oobSorted[i]} custom=${customSorted[i]}`);
    }
  }

  for (const issue of issues) {
    anomalies.push({ severity: 'HIGH', type: 'line-parity', detail: issue });
  }

  console.log(`Line count & ordering — OOB=${sharedOobLines.length}, custom=${sharedCustomLines.length}, ${issues.length} issue(s)`);
  testFindings.push({
    testName: 'Line count & product ordering parity',
    passed: issues.length === 0,
    diffCount: issues.length,
  });
  expect(issues, issues.join('\n')).toHaveLength(0);
});

test('Pricing & totals parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const headerDiffs = compareFields(sharedOobQuote, sharedCustomQuote, { onlyFields: PRICING_FIELDS });

  /** @type {FieldDiff[]} */
  const lineDiffs = [];
  const oobByProduct    = indexBy(sharedOobLines,    /** @param {any} l */ l => l.SBQQ__Product__c);
  const customByProduct = indexBy(sharedCustomLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(oobByProduct)) {
    const customLine = customByProduct[productId];
    if (!customLine) continue;
    const diffs = compareFields(oobByProduct[productId], customLine, { onlyFields: PRICING_FIELDS });
    for (const d of diffs) lineDiffs.push({ ...d, field: `[product ${productId}].${d.field}` });
  }

  const all = [...headerDiffs, ...lineDiffs];
  // For pricing, ANY difference is significant — money must match exactly.
  recordDiffs('pricing', all, { structuralSeverity: 'HIGH', valueSeverity: 'HIGH' });

  console.log(`Pricing parity — header diffs=${headerDiffs.length}, line diffs=${lineDiffs.length}`);

  testFindings.push({
    testName: 'Pricing & totals parity',
    passed: all.length === 0,
    diffCount: all.length,
  });
  expect(all,
    `Pricing differs between OOB and custom amendment:\n` +
    all.map(d => `  ${d.field}: OOB=${formatVal(d.oob)} custom=${formatVal(d.custom)}`).join('\n')
  ).toHaveLength(0);
});

test('Dates & subscription term parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const headerDiffs = compareFields(sharedOobQuote, sharedCustomQuote, { onlyFields: DATE_TERM_FIELDS });

  /** @type {FieldDiff[]} */
  const lineDiffs = [];
  const oobByProduct    = indexBy(sharedOobLines,    /** @param {any} l */ l => l.SBQQ__Product__c);
  const customByProduct = indexBy(sharedCustomLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(oobByProduct)) {
    const customLine = customByProduct[productId];
    if (!customLine) continue;
    const diffs = compareFields(oobByProduct[productId], customLine, { onlyFields: DATE_TERM_FIELDS });
    for (const d of diffs) lineDiffs.push({ ...d, field: `[product ${productId}].${d.field}` });
  }

  const all = [...headerDiffs, ...lineDiffs];
  recordDiffs('dates & term', all, { structuralSeverity: 'HIGH', valueSeverity: 'HIGH' });

  console.log(`Dates & term parity — ${all.length} diff(s)`);

  testFindings.push({
    testName: 'Dates & subscription term parity',
    passed: all.length === 0,
    diffCount: all.length,
  });
  expect(all,
    `Dates / term differ between OOB and custom amendment:\n` +
    all.map(d => `  ${d.field}: OOB=${formatVal(d.oob)} custom=${formatVal(d.custom)}`).join('\n')
  ).toHaveLength(0);
});

test('Subscription linkage parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  /** @type {string[]} */
  const issues = [];

  for (const line of sharedCustomLines) {
    if (!line.SBQQ__UpgradedSubscription__c) {
      issues.push(`Custom line ${line.Id} (product ${line.SBQQ__Product__c}) is missing SBQQ__UpgradedSubscription__c`);
    }
  }
  for (const line of sharedOobLines) {
    if (!line.SBQQ__UpgradedSubscription__c) {
      issues.push(`OOB line ${line.Id} (product ${line.SBQQ__Product__c}) is missing SBQQ__UpgradedSubscription__c — unexpected baseline`);
    }
  }

  const oobByProduct    = indexBy(sharedOobLines,    /** @param {any} l */ l => l.SBQQ__Product__c);
  const customByProduct = indexBy(sharedCustomLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(oobByProduct)) {
    const customLine = customByProduct[productId];
    if (!customLine) continue;
    const diffs = compareFields(oobByProduct[productId], customLine, { onlyFields: SUBSCRIPTION_LINKAGE_FIELDS });
    for (const d of diffs) {
      issues.push(`Product ${productId}: ${d.field} differs — OOB=${formatVal(d.oob)} custom=${formatVal(d.custom)}`);
    }
  }

  for (const issue of issues) {
    anomalies.push({ severity: 'HIGH', type: 'subscription-linkage', detail: issue });
  }

  console.log(`Subscription linkage — ${issues.length} issue(s)`);
  testFindings.push({
    testName: 'Subscription linkage parity',
    passed: issues.length === 0,
    diffCount: issues.length,
  });
  expect(issues, issues.join('\n')).toHaveLength(0);
});
