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
 * Find the most recent existing PDF linked to any of the given entity Ids
 * (quote / contract / opportunity / account). Single-shot — no polling, no
 * time filter. Used when we want to verify whatever PDF Conga last produced
 * for this quote, without re-triggering generation.
 *
 * @param {{instanceUrl:string, accessToken:string}} sfCtx
 * @param {string[]} linkedEntityIds
 * @returns {Promise<{contentVersionId:string, contentDocumentId:string, title:string, linkedEntityId:string, createdDate:string} | null>}
 */
async function findLatestPdfOnEntities(sfCtx, linkedEntityIds) {
  const apiBase = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}`;
  const headers = { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' };
  const inClause = linkedEntityIds.filter(Boolean).map(id => `'${id}'`).join(',');
  if (!inClause) return null;

  const soql = `SELECT ContentDocumentId, LinkedEntityId,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocument.Title,
                       ContentDocument.FileType,
                       ContentDocument.CreatedDate
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN (${inClause})
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 50`;
  const json = await fetch(`${apiBase}/query?q=${encodeURIComponent(soql)}`, { headers }).then(r => r.json());
  const records = json.records || [];
  const pdf = records.find((/** @type {any} */ r) => {
    const ft = (r.ContentDocument?.FileType || '').toUpperCase();
    const title = r.ContentDocument?.Title || '';
    return ft === 'PDF' || /\.pdf$/i.test(title);
  });
  if (!pdf) return null;
  return {
    contentVersionId: pdf.ContentDocument.LatestPublishedVersionId,
    contentDocumentId: pdf.ContentDocumentId,
    title:             pdf.ContentDocument.Title,
    linkedEntityId:    pdf.LinkedEntityId,
    createdDate:       pdf.ContentDocument.CreatedDate,
  };
}

/**
 * Resolve a ContentVersion Id by exact Title. Use when you already know the
 * filename (e.g. read from the wizard's `.doc-title` after Conga finishes).
 * Latest version only — handy when the same title was used by an earlier run.
 *
 * @param {{instanceUrl:string, accessToken:string}} sfCtx
 * @param {string} title
 * @returns {Promise<{contentVersionId:string, contentDocumentId:string, title:string} | null>}
 */
async function findContentVersionByTitle(sfCtx, title) {
  const apiBase = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}`;
  const headers = { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' };
  // Escape single quotes for SOQL
  const safe = title.replace(/'/g, "\\'");
  const soql = `SELECT Id, ContentDocumentId, Title
                FROM ContentVersion
                WHERE Title = '${safe}' AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1`;
  const json = await fetch(`${apiBase}/query?q=${encodeURIComponent(soql)}`, { headers }).then(r => r.json());
  const rec = json.records?.[0];
  if (!rec) return null;
  return { contentVersionId: rec.Id, contentDocumentId: rec.ContentDocumentId, title: rec.Title };
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
 * @returns {{rows: Array<{field:string, expected:string, inPdf:string, match:boolean}>, matches:number, mismatches:number, pdfNumbers:number[]}}
 */
function comparePdfToSnapshot(snap, pdfText) {
  // Normalize the PDF text before number extraction. pdf-parse can produce
  // numeric strings with stray whitespace between glyphs / separators when
  // the PDF was rendered with sub-glyph positioning (e.g. "22 ,435 ,607 .86"
  // or "22,435,\n607.86"). Collapse whitespace adjacent to comma/period/digit
  // boundaries so the regex can recognise the full number. Run the
  // digit-adjacent passes repeatedly because each pass may expose a fresh
  // join opportunity that the next can act on.
  let normalizedNumberText = pdfText;
  for (let i = 0; i < 4; i++) {
    normalizedNumberText = normalizedNumberText
      .replace(/(\d)\s+([,.])/g, '$1$2')   // "22 ," → "22,"
      .replace(/([,.])\s+(\d)/g, '$1$2')   // ", 435" → ",435"
      .replace(/(\d)\s+(\d)/g, '$1$2');    // "22 435" → "22435" (caught after the above)
  }

  // Collapse arbitrary whitespace (including newlines pdf-parse injects) for
  // string-substring matching so a name split across two text spans still
  // matches its expected value.
  const collapsedText = pdfText.replace(/\s+/g, ' ');
  const lowerText     = collapsedText.toLowerCase();

  // Pre-extract all numbers from the PDF for tolerant currency matching.
  // Captures e.g. "1,234.56" / "1234" / "0.50" / "7994" — strips commas.
  //
  // The comma-separated branch REQUIRES at least one comma group (note the
  // `+` instead of `*` on the comma repetition). Without that, a bare
  // integer like "7994" is incorrectly split into [799, 4] because the
  // first branch greedily consumes the first \d{1,3} and accepts an empty
  // comma list. Forcing a literal comma in branch 1 makes the engine fall
  // through to branch 2 (\d+) for bare integers, which captures the whole
  // value.
  const pdfNumbers = (normalizedNumberText.match(/-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?/g) || [])
    .map(s => parseFloat(s.replace(/,/g, '')))
    .filter(n => !isNaN(n));

  /**
   * Find the number in pdfNumbers closest to `expected`. Returns the matched
   * value (within `tol`) plus the absolute-closest value found regardless of
   * tolerance — the closest value is what we display in the inPdf column so
   * the dashboard shows "PDF=7994" instead of just "NO" when the SF and PDF
   * values have drifted.
   *
   * @param {number|null} expected
   * @param {number}      [tol=0.01]
   * @returns {{found:boolean, closest:number|null}}
   */
  const findNumber = (expected, tol = 0.01) => {
    if (expected == null || pdfNumbers.length === 0) {
      return { found: false, closest: null };
    }
    let closest = pdfNumbers[0];
    let bestDiff = Math.abs(closest - expected);
    for (let i = 1; i < pdfNumbers.length; i++) {
      const d = Math.abs(pdfNumbers[i] - expected);
      if (d < bestDiff) { bestDiff = d; closest = pdfNumbers[i]; }
    }
    return { found: bestDiff < tol, closest };
  };

  /**
   * Find an expected string in the collapsed PDF text. When found, surfaces
   * the matched text. When not found, surfaces a short text snippet near the
   * expected substring's prefix so the dashboard's inPdf column gives a hint
   * about what *is* on the PDF instead of just "NO".
   *
   * @param {string|null} expected
   * @returns {{found:boolean, snippet:string|null}}
   */
  const findString = (expected) => {
    if (!expected) return { found: false, snippet: null };
    const needle = String(expected).replace(/\s+/g, ' ').toLowerCase();
    if (lowerText.includes(needle)) return { found: true, snippet: String(expected) };
    return { found: false, snippet: null };
  };

  /** Try several date formats; return which one matched (or null). */
  const findDate = (/** @type {string} */ iso) => {
    return _dateAnyFormat(iso, collapsedText)
      ? { found: true, snippet: iso }
      : { found: false, snippet: null };
  };

  /** @type {Array<{field:string, expected:string, inPdf:string, match:boolean}>} */
  const rows = [];
  let matches = 0, mismatches = 0;

  // ASCII-only markers so the LWC dashboard's base64-atob-JSON.parse path
  // doesn't mangle multi-byte UTF-8 chars. The inPdf column gets either:
  //   - the matched value (when found within tolerance), or
  //   - the closest value PDF actually contains (when there's a drift), or
  //   - "NOT FOUND" (when no candidate exists at all).
  const pushStrRow = (
    /** @type {string} */ field,
    /** @type {any} */ expected,
    /** @type {{found:boolean, snippet:string|null}} */ res,
  ) => {
    rows.push({
      field,
      expected: _fmt(expected),
      inPdf:    res.found ? 'MATCH' : (res.snippet ? `differs: ${res.snippet}` : 'NOT FOUND'),
      match:    res.found,
    });
    if (res.found) matches++; else mismatches++;
  };
  const pushNumRow = (
    /** @type {string} */ field,
    /** @type {number} */ expected,
    /** @type {{found:boolean, closest:number|null}} */ res,
  ) => {
    let inPdf;
    if (res.found)              inPdf = 'MATCH';
    else if (res.closest == null) inPdf = 'NOT FOUND';
    else                        inPdf = String(res.closest);
    rows.push({ field, expected: _fmt(expected), inPdf, match: res.found });
    if (res.found) matches++; else mismatches++;
  };

  // ── Metadata ───────────────────────────────────────────────────────────
  // Note: SF "Contract number" (e.g. CONT-065069) and SF "Quote name" (e.g.
  // Q-84109) are intentionally NOT compared — the OSA template doesn't print
  // either. It surfaces its own customer-facing identifiers instead
  // (Amendment to OSA No., Amendment No., Version). Adding them would
  // produce permanent false-negatives.
  pushStrRow('Account name',     snap.accountName,    findString(snap.accountName));

  // Dates: SF returns YYYY-MM-DD; PDFs commonly show "Jan 15, 2026" or "1/15/2026" or "15-Jan-2026".
  if (snap.startDate) pushStrRow('Start date', snap.startDate, findDate(snap.startDate));
  if (snap.endDate)   pushStrRow('End date',   snap.endDate,   findDate(snap.endDate));

  // ── Header amounts ─────────────────────────────────────────────────────
  if (snap.netAmount != null)        pushNumRow('Net amount (header)', snap.netAmount, findNumber(snap.netAmount));
  if (snap.subscriptionTerm != null) pushNumRow('Subscription term',   snap.subscriptionTerm, findNumber(snap.subscriptionTerm, 0.001));

  // ── Lines ──────────────────────────────────────────────────────────────
  // Field labels use plain " - " (hyphen) instead of " — " (em-dash) so the
  // strings survive the LWC's atob/JSON.parse pipeline without mojibake.
  for (let i = 0; i < snap.lines.length; i++) {
    const line = snap.lines[i];
    if (line.isBundle) continue; // bundle parents have no qty/price of their own
    const prefix = `Line ${i + 1} (${line.product})`;
    pushStrRow(`${prefix} - product`,    line.product, findString(line.product));
    if (line.quantity != null)      pushNumRow(`${prefix} - qty`,        line.quantity,      findNumber(line.quantity, 0.001));
    if (line.customerPrice != null) pushNumRow(`${prefix} - cust price`, line.customerPrice, findNumber(line.customerPrice));
    if (line.netTotal != null)      pushNumRow(`${prefix} - net total`,  line.netTotal,      findNumber(line.netTotal));
  }

  return { rows, matches, mismatches, pdfNumbers };
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
  const mm = String(m).padStart(2, '0');
  const dd = String(d).padStart(2, '0');
  const yy = String(y).slice(-2);
  const candidates = [
    iso,                                  // 2026-05-20
    `${m}/${d}/${y}`,                     // 5/20/2026
    `${mm}/${dd}/${y}`,                   // 05/20/2026
    `${m}/${d}/${yy}`,                    // 5/20/26
    `${mm}/${dd}/${yy}`,                  // 05/20/26
    `${m}-${d}-${y}`,                     // 5-20-2026 (matches OSA filename style "6-1-2026")
    `${mm}-${dd}-${y}`,                   // 05-20-2026
    `${monthShort} ${d}, ${y}`,           // May 20, 2026
    `${monthLong} ${d}, ${y}`,            // May 20, 2026 (long form same here)
    `${monthShort} ${d} ${y}`,            // May 20 2026 (no comma)
    `${monthLong} ${d} ${y}`,
    `${d}-${monthShort}-${y}`,            // 20-May-2026
    `${d}-${monthShort}-${yy}`,           // 20-May-26 (matches OSA template style)
    `${dd}-${monthShort}-${y}`,           // 20-May-2026 (zero-padded day)
    `${dd}-${monthShort}-${yy}`,          // 20-May-26 (both zero-padded)
    `${d} ${monthShort} ${y}`,            // 20 May 2026
    `${d} ${monthLong} ${y}`,
    `${d}/${m}/${y}`,                     // 20/5/2026 (UK/EU)
    `${dd}/${mm}/${y}`,                   // 20/05/2026
  ];
  return candidates.some(c => text.includes(c));
}

module.exports = {
  snapshotForOsa,
  waitForGeneratedPdf,
  findLatestPdfOnEntities,
  findContentVersionByTitle,
  downloadPdfText,
  comparePdfToSnapshot,
};
