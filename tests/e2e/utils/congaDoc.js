// @ts-check
/**
 * congaDoc.js — utilities for waiting on a Conga-generated PDF and comparing
 * its contents against the UI/DB data captured before generation.
 *
 * Gated behind QTC_OSA_WAIT_FOR_DOC=1 by the caller — adds ~2-3 min per run.
 *
 * Flow:
 *   1. snapshotForOsa()  — capture lines + header + account/contract metadata.
 *   2. (caller clicks "Open Conga to Generate OSA" in the UI)
 *   3. waitForGeneratedPdf() — poll ContentDocumentLink REST until the PDF appears.
 *   4. downloadPdfText() — fetch VersionData and run pdf-parse.
 *   5. comparePdfToSnapshot() — tolerant value matching, returns match/mismatch rows.
 */

const SF_API_VER = process.env.QTC_SF_API_VERSION || 'v62.0';

/**
 * @typedef {Object} OsaSnapshot
 * @property {string}                 accountName
 * @property {string|null}            contractNumber
 * @property {string}                 quoteName
 * @property {string}                 quoteId
 * @property {string|null}            accountId       — for ContentDocumentLink polling
 * @property {string|null}            opportunityId   — for ContentDocumentLink polling
 * @property {string|null}            startDate     YYYY-MM-DD
 * @property {string|null}            endDate       YYYY-MM-DD
 * @property {number|null}            netAmount
 * @property {number|null}            subscriptionTerm
 * @property {Array<SnapshotLine>}    lines
 * @property {number}                 snapshotTs    epoch ms — used to filter ContentDocuments by createdDate
 */

/**
 * @typedef {Object} SnapshotLine
 * @property {string}      product
 * @property {number|null} quantity
 * @property {number|null} customerPrice
 * @property {number|null} netTotal
 * @property {boolean}     isBundle
 */

/**
 * Capture the UI/DB state that should be reflected in the generated OSA PDF.
 * Reads from DB rather than DOM because Conga generates from DB — the PDF
 * cannot diverge from the DB at the moment of generation, but the DOM can
 * lag DB writes by a render tick.
 *
 * @param {{instanceUrl:string, accessToken:string}} sfCtx
 * @param {{quoteName:string, accountName:string, contractNumber?:string|null}} info
 * @returns {Promise<OsaSnapshot>}
 */
async function snapshotForOsa(sfCtx, info) {
  const apiBase = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}`;
  const headers = { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' };

  // Header
  const headerSoql = `SELECT Id, Name, SBQQ__Status__c, SBQQ__NetAmount__c,
                             SBQQ__SubscriptionTerm__c, SBQQ__StartDate__c, SBQQ__EndDate__c,
                             SBQQ__Account__c, SBQQ__Account__r.Name,
                             SBQQ__Opportunity2__c
                      FROM SBQQ__Quote__c WHERE Name = '${info.quoteName}' LIMIT 1`;
  const headerJson = await fetch(`${apiBase}/query?q=${encodeURIComponent(headerSoql)}`, { headers }).then(r => r.json());
  const header = headerJson.records?.[0];
  if (!header) throw new Error(`snapshotForOsa: quote ${info.quoteName} not found`);

  // Lines
  const linesSoql = `SELECT Id, SBQQ__ProductName__c, SBQQ__Quantity__c,
                            SBQQ__CustomerPrice__c, SBQQ__NetTotal__c
                     FROM SBQQ__QuoteLine__c
                     WHERE SBQQ__Quote__c = '${header.Id}'
                     ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS LAST`;
  const linesJson = await fetch(`${apiBase}/query?q=${encodeURIComponent(linesSoql)}`, { headers }).then(r => r.json());

  const isBundleParent = (/** @type {string|null|undefined} */ name) => {
    const n = (name || '').toLowerCase();
    return n.includes('bundle') || n.includes(': sandbox');
  };

  const lines = (linesJson.records || []).map((/** @type {any} */ r) => ({
    product:       r.SBQQ__ProductName__c    || '',
    quantity:      r.SBQQ__Quantity__c       ?? null,
    customerPrice: r.SBQQ__CustomerPrice__c  ?? null,
    netTotal:      r.SBQQ__NetTotal__c       ?? null,
    isBundle:      isBundleParent(r.SBQQ__ProductName__c),
  }));

  return {
    accountName:      info.accountName,
    contractNumber:   info.contractNumber ?? null,
    quoteName:        info.quoteName,
    quoteId:          header.Id,
    accountId:        header.SBQQ__Account__c     ?? null,
    opportunityId:    header.SBQQ__Opportunity2__c ?? null,
    startDate:        header.SBQQ__StartDate__c ?? null,
    endDate:          header.SBQQ__EndDate__c   ?? null,
    netAmount:        header.SBQQ__NetAmount__c ?? null,
    subscriptionTerm: header.SBQQ__SubscriptionTerm__c ?? null,
    lines,
    snapshotTs:       Date.now(),
  };
}

/**
 * Poll Salesforce for the new PDF attached to any of the given linked entity IDs.
 * Returns the first PDF whose ContentDocument.CreatedDate is after `sinceTs`.
 *
 * @param {{instanceUrl:string, accessToken:string}} sfCtx
 * @param {string[]} linkedEntityIds   typically [quoteId, contractId]
 * @param {number}   sinceTs           epoch ms — only return docs created after this
 * @param {{timeoutMs?:number, pollMs?:number, logger?:(msg:string)=>void}} [opts]
 * @returns {Promise<{contentVersionId:string, title:string, linkedEntityId:string} | null>}
 */
async function waitForGeneratedPdf(sfCtx, linkedEntityIds, sinceTs, opts = {}) {
  const timeoutMs = opts.timeoutMs ?? 180_000;
  const pollMs    = opts.pollMs    ?? 5_000;
  const log       = opts.logger    ?? (() => {});
  const apiBase   = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}`;
  const headers   = { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' };

  const inClause   = linkedEntityIds.filter(Boolean).map(id => `'${id}'`).join(',');
  const sinceIso   = new Date(sinceTs - 5_000).toISOString(); // 5s buffer for clock skew
  const deadline   = Date.now() + timeoutMs;
  let   pollCount  = 0;

  const soql = `SELECT ContentDocumentId, LinkedEntityId,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocument.Title,
                       ContentDocument.FileType,
                       ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN (${inClause})
                AND ContentDocument.CreatedDate > ${sinceIso}
                ORDER BY ContentDocument.CreatedDate DESC`;

  while (Date.now() < deadline) {
    pollCount++;
    try {
      const json = await fetch(`${apiBase}/query?q=${encodeURIComponent(soql)}`, { headers }).then(r => r.json());
      const records = json.records || [];
      const pdf = records.find((/** @type {any} */ r) => {
        const ft = (r.ContentDocument?.FileType || '').toUpperCase();
        const title = r.ContentDocument?.Title || '';
        return ft === 'PDF' || /\.pdf$/i.test(title);
      });
      if (pdf) {
        log(`[congaDoc] PDF found after ${pollCount} polls: "${pdf.ContentDocument.Title}" (linked to ${pdf.LinkedEntityId})`);
        return {
          contentVersionId: pdf.ContentDocument.LatestPublishedVersionId,
          title:            pdf.ContentDocument.Title,
          linkedEntityId:   pdf.LinkedEntityId,
        };
      }
      if (pollCount % 6 === 0) {
        log(`[congaDoc] Still waiting for PDF… (${pollCount * pollMs / 1000}s elapsed, ${records.length} non-PDF doc(s) so far)`);
      }
    } catch (e) {
      log(`[congaDoc] Poll error (will retry): ${e instanceof Error ? e.message : String(e)}`);
    }
    await new Promise(r => setTimeout(r, pollMs));
  }

  log(`[congaDoc] Timed out waiting for PDF after ${timeoutMs}ms (${pollCount} polls)`);

  // Diagnostic dump: what files did appear, on what entities, in this window?
  // Helps distinguish "Conga never ran" from "PDF went somewhere we're not polling".
  try {
    const diagSoql = `SELECT ContentDocumentId, LinkedEntityId,
                             ContentDocument.Title,
                             ContentDocument.FileType,
                             ContentDocument.CreatedDate,
                             ContentDocument.CreatedBy.Name
                      FROM ContentDocumentLink
                      WHERE ContentDocument.CreatedDate > ${sinceIso}
                      ORDER BY ContentDocument.CreatedDate DESC
                      LIMIT 20`;
    const diag = await fetch(`${apiBase}/query?q=${encodeURIComponent(diagSoql)}`, { headers }).then(r => r.json());
    const rows = diag.records || [];
    if (rows.length === 0) {
      log(`[congaDoc] DIAG: zero ContentDocuments created in this window — Conga likely never ran.`);
    } else {
      log(`[congaDoc] DIAG: ${rows.length} recent ContentDocument(s) (showing newest first):`);
      for (const r of rows) {
        log(`           - "${r.ContentDocument?.Title}" (${r.ContentDocument?.FileType}) linked→${r.LinkedEntityId} by ${r.ContentDocument?.CreatedBy?.Name} @ ${r.ContentDocument?.CreatedDate}`);
      }
      log(`[congaDoc] DIAG: was polling on LinkedEntityId IN (${inClause}) — if the PDF above shows a different entity, widen the poll list.`);
    }
  } catch (e) {
    log(`[congaDoc] DIAG query failed: ${e instanceof Error ? e.message : String(e)}`);
  }

  return null;
}

/**
 * Download a ContentVersion's binary data and extract plain text via pdf-parse.
 *
 * @param {{instanceUrl:string, accessToken:string}} sfCtx
 * @param {string} contentVersionId
 * @returns {Promise<{text:string, numPages:number}>}
 */
async function downloadPdfText(sfCtx, contentVersionId) {
  const url  = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/sobjects/ContentVersion/${contentVersionId}/VersionData`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${sfCtx.accessToken}` } });
  if (!resp.ok) {
    throw new Error(`downloadPdfText: ${resp.status} ${resp.statusText}`);
  }
  const arrayBuf = await resp.arrayBuffer();
  const buf      = Buffer.from(arrayBuf);

  // pdf-parse is loaded lazily so users who never set QTC_OSA_WAIT_FOR_DOC=1
  // don't pay the install cost. No @types/pdf-parse published — cast through any.
  // @ts-ignore — pdf-parse has no type definitions
  const pdfParse = /** @type {(b:Buffer) => Promise<{text:string, numpages:number}>} */ (require('pdf-parse'));
  const parsed   = await pdfParse(buf);
  return { text: parsed.text || '', numPages: parsed.numpages || 0 };
}

/** @param {number|null|undefined} n */
function _fmt(n) { return n == null ? '—' : String(n); }

/**
 * Build a flat set of (field, expected, regex/predicate) checks from a snapshot.
 * Each check tries to locate the expected value in the PDF text.
 *
 * Tolerance:
 *  - Currency: PDF "$1,234.56" / "1234.56 USD" / "1,234.56" — strip commas/$/USD, abs(diff) < 0.01.
 *  - Integers: exact match.
 *  - Strings:  case-insensitive substring.
 *
 * @param {OsaSnapshot} snap
 * @param {string} pdfText
 * @returns {{rows: Array<any>, matches:number, mismatches:number}}
 */
function comparePdfToSnapshot(snap, pdfText) {
  // Pre-extract all numbers from the PDF for tolerant currency matching.
  // Captures e.g. "1,234.56" / "1234" / "0.50" — strips commas.
  const pdfNumbers = (pdfText.match(/-?\d{1,3}(?:,\d{3})*(?:\.\d+)?|-?\d+(?:\.\d+)?/g) || [])
    .map(s => parseFloat(s.replace(/,/g, '')))
    .filter(n => !isNaN(n));

  const lowerText = pdfText.toLowerCase();

  /**
   * @param {number|null} expected
   * @param {number}      [tol=0.01]
   */
  const findNumber = (expected, tol = 0.01) => {
    if (expected == null) return false;
    return pdfNumbers.some(n => Math.abs(n - expected) < tol);
  };

  /** @param {string|null} expected */
  const findString = (expected) => {
    if (!expected) return false;
    return lowerText.includes(String(expected).toLowerCase());
  };

  /** @type {Array<{field:string, expected:string, inPdf:string, match:boolean}>} */
  const rows = [];
  let matches = 0, mismatches = 0;
  const pushRow = (/** @type {string} */ field, /** @type {any} */ expected, /** @type {boolean} */ found) => {
    rows.push({ field, expected: _fmt(expected), inPdf: found ? '✓' : '✗', match: found });
    if (found) matches++; else mismatches++;
  };

  // ── Metadata ───────────────────────────────────────────────────────────
  pushRow('Account name',     snap.accountName,    findString(snap.accountName));
  if (snap.contractNumber) pushRow('Contract number', snap.contractNumber, findString(snap.contractNumber));
  pushRow('Quote name',       snap.quoteName,      findString(snap.quoteName));

  // Dates: SF returns YYYY-MM-DD; PDFs commonly show "Jan 15, 2026" or "1/15/2026" or "15-Jan-2026".
  // Check several formats.
  if (snap.startDate) pushRow('Start date', snap.startDate, _dateAnyFormat(snap.startDate, pdfText));
  if (snap.endDate)   pushRow('End date',   snap.endDate,   _dateAnyFormat(snap.endDate,   pdfText));

  // ── Header amounts ─────────────────────────────────────────────────────
  if (snap.netAmount != null)        pushRow('Net amount (header)', snap.netAmount, findNumber(snap.netAmount));
  if (snap.subscriptionTerm != null) pushRow('Subscription term',   snap.subscriptionTerm, findNumber(snap.subscriptionTerm, 0.001));

  // ── Lines ──────────────────────────────────────────────────────────────
  for (let i = 0; i < snap.lines.length; i++) {
    const line = snap.lines[i];
    if (line.isBundle) continue; // bundle parents have no qty/price of their own
    const prefix = `Line ${i + 1} (${line.product})`;
    pushRow(`${prefix} — product`, line.product, findString(line.product));
    if (line.quantity != null)      pushRow(`${prefix} — qty`,       line.quantity,      findNumber(line.quantity, 0.001));
    if (line.customerPrice != null) pushRow(`${prefix} — cust price`,line.customerPrice, findNumber(line.customerPrice));
    if (line.netTotal != null)      pushRow(`${prefix} — net total`, line.netTotal,      findNumber(line.netTotal));
  }

  return { rows, matches, mismatches };
}

/**
 * Returns true if `iso` (YYYY-MM-DD) appears in `text` under any of:
 *   YYYY-MM-DD, M/D/YYYY, MM/DD/YYYY, Mon D, YYYY, Month D, YYYY, D-Mon-YYYY.
 * @param {string} iso
 * @param {string} text
 */
function _dateAnyFormat(iso, text) {
  const [y, m, d] = iso.split('-').map(Number);
  if (!y || !m || !d) return false;
  const monthShort = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
  const monthLong  = ['January','February','March','April','May','June','July','August','September','October','November','December'][m - 1];
  const candidates = [
    iso,
    `${m}/${d}/${y}`,
    `${String(m).padStart(2,'0')}/${String(d).padStart(2,'0')}/${y}`,
    `${monthShort} ${d}, ${y}`,
    `${monthLong} ${d}, ${y}`,
    `${d}-${monthShort}-${y}`,
    `${d} ${monthShort} ${y}`,
    `${d} ${monthLong} ${y}`,
  ];
  return candidates.some(c => text.includes(c));
}

module.exports = {
  snapshotForOsa,
  waitForGeneratedPdf,
  downloadPdfText,
  comparePdfToSnapshot,
};
