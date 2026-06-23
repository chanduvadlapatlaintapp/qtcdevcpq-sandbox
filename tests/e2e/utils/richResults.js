// @ts-check
const fs   = require('fs');
const path = require('path');

/**
 * Canonical Rich_Results__c shape consumed by agenticQtcTestDashboard LWC.
 * Specs call buildRichResults() with only the fields they actually measured;
 * everything else is filled with safe defaults so the dashboard tabs render
 * empty states instead of throwing.
 *
 * @typedef {Object} RichResultsInput
 * @property {string}              kind              Suite identifier (e.g. 'previewSendOsa')
 * @property {string}              scenarioLabel     Human label shown in run header
 * @property {number}              scenarioNumber    1 | 2 | 3
 * @property {string}              accountName
 * @property {string|null}         [contract]
 * @property {string|null}         [quoteName]
 * @property {string|null}         [quoteId]
 * @property {boolean}             [hasApproval]
 * @property {boolean}             [hasSendBtn]
 * @property {boolean}             [pdfGenerated]
 * @property {boolean}             [pdfSkipped]
 * @property {number}              [spinbuttonCount]
 * @property {number|null}         [uiQtyTotal]
 * @property {number|null}         [dbQtyTotal]
 * @property {number}              [dbLineCount]
 * @property {number}              [deltaApplied]
 * @property {Object}              [metricsBeforeSave]
 * @property {Object}              [metricsAfterSave]
 * @property {Array<Object>}       [lineResults]
 * @property {Array<Object>}       [metricResults]
 * @property {Array<Object>}       [dbComparison]
 * @property {Array<{severity:string, type?:string, detail?:string}>}       [dbAnomalies]
 * @property {Array<Object>}       [uiDbCrossCheck]
 * @property {number}              [crossCheckMismatches]
 * @property {Array<Object>}       [osaComparison]   Field-by-field UI↔Backend rows for the OSA datatable
 * @property {number}              testStartMs
 * @property {boolean}             passed
 * @property {Object}              [extra]           Suite-specific payload not covered above
 */

/**
 * Build the canonical results.json payload and write it to <runDir>/results.json.
 * Returns the payload so callers can also pipe it to console / additional sinks.
 *
 * @param {RichResultsInput & { runDir: string, runTs: string }} input
 */
function buildRichResults(input) {
  const dbAnomalies = input.dbAnomalies || [];
  const payload = {
    kind:           input.kind,
    runTs:          input.runTs,
    runAt:          new Date().toLocaleString(),
    durationMs:     Date.now() - input.testStartMs,
    passed:         input.passed,
    accountName:    input.accountName,
    scenarioNumber: input.scenarioNumber,
    scenarioLabel:  input.scenarioLabel,
    contract:       input.contract       ?? null,
    quoteName:      input.quoteName      ?? null,
    quoteId:        input.quoteId        ?? null,
    hasApproval:    input.hasApproval    ?? false,
    hasSendBtn:     input.hasSendBtn     ?? false,
    pdfGenerated:   input.pdfGenerated   ?? false,
    pdfSkipped:     input.pdfSkipped     ?? false,
    spinbuttonCount: input.spinbuttonCount ?? 0,
    uiQtyTotal:     input.uiQtyTotal     ?? null,
    dbQtyTotal:     input.dbQtyTotal     ?? null,
    dbLineCount:    input.dbLineCount    ?? 0,
    deltaApplied:   input.deltaApplied   ?? 0,
    metricsBeforeSave: input.metricsBeforeSave || null,
    metricsAfterSave:  input.metricsAfterSave  || null,
    lineResults:    input.lineResults    || [],
    metricResults:  input.metricResults  || [],
    dbComparison:   input.dbComparison   || [],
    dbAnomalies,
    dbAnomalyCount: dbAnomalies.length,
    dbHighCount:    dbAnomalies.filter(a => a.severity === 'HIGH').length,
    uiDbCrossCheck:       input.uiDbCrossCheck       || [],
    crossCheckMismatches: input.crossCheckMismatches ?? 0,
    osaComparison:        input.osaComparison        || [],
    extra:          input.extra || null,
  };

  fs.writeFileSync(
    path.join(input.runDir, 'results.json'),
    JSON.stringify(payload, null, 2),
  );
  return payload;
}

/**
 * Build a product-keyed UI ↔ DB cross-check so the dashboard's "UI-DB" tab
 * joins each UI spinbutton to its corresponding QuoteLine by (product name,
 * segment occurrence) — not by sequential index.
 *
 * Why: the UI displays spinbuttons in LWC-render order, while the SOQL DB
 * results come back in (ProductName, SegmentIndex NULLS LAST) order and may
 * include bundle-parent rows the UI never shows. Joining by position is
 * unreliable; joining by (product, occurrence) is robust.
 *
 * Returns rows shaped to match what the LWC's `richMismatchRows` getter
 * expects (lines 263-310 of agenticQtcTestDashboard.js).
 *
 * @param {Array<{index:number, label:string, before:number, actual:number, costBefore?:string|null, costAfter?:string|null}>} lineResults
 * @param {Array<{product:string, segIndex:number|null, priorQty:number|null, dbQty:number|null, isBundle?:boolean}>} dbComparison
 */
function buildUiDbCrossCheck(lineResults, dbComparison) {
  /** @param {string|null|undefined} label */
  const productFromLabel = (label) => (label || '').split('\n')[0].trim();
  /** @param {string|null|undefined} s */
  const norm = (s) => (s || '').toLowerCase().trim();

  // Group non-bundle DB rows by product name, sorted by segment index so the
  // i-th UI occurrence of "Foo" maps to the i-th DB segment of "Foo".
  /** @type {Map<string, Array<any>>} */
  const dbByProduct = new Map();
  for (const d of dbComparison) {
    if (d.isBundle) continue;
    const key = norm(d.product);
    let arr = dbByProduct.get(key);
    if (!arr) { arr = []; dbByProduct.set(key, arr); }
    arr.push(d);
  }
  for (const arr of dbByProduct.values()) {
    arr.sort((a, b) => (a.segIndex ?? 1) - (b.segIndex ?? 1));
  }

  /** @type {Map<string, number>} */
  const seen = new Map();
  return lineResults.map(line => {
    const product = productFromLabel(line.label);
    const key     = norm(product);
    const occ     = (seen.get(key) || 0) + 1;
    seen.set(key, occ);

    const db      = (dbByProduct.get(key) || [])[occ - 1];
    const hasData = db != null;
    const uiAfter = line.actual ?? null;
    const dbAfter = db ? (db.dbQty ?? null) : null;
    const match   = hasData && uiAfter != null && dbAfter != null
                  && Math.abs(uiAfter - dbAfter) < 0.001;

    return {
      uiIndex:  line.index,
      product,
      segOcc:   occ,
      uiBefore: line.before ?? null,
      uiAfter,
      dbPrior:  db ? (db.priorQty ?? null) : null,
      dbAfter,
      // UI "Cost" cell (SBQQ__NetTotal__c) before the edit and after save — raw
      // display strings, carried straight through to the dashboard's UI↔DB tab.
      costBefore: line.costBefore ?? null,
      costAfter:  line.costAfter  ?? null,
      match, hasData,
    };
  });
}

module.exports = { buildRichResults, buildUiDbCrossCheck };
