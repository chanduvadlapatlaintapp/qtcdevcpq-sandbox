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
 * @property {Array<Object>}       [dbAnomalies]
 * @property {Array<Object>}       [uiDbCrossCheck]
 * @property {number}              [crossCheckMismatches]
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
    extra:          input.extra || null,
  };

  fs.writeFileSync(
    path.join(input.runDir, 'results.json'),
    JSON.stringify(payload, null, 2),
  );
  return payload;
}

module.exports = { buildRichResults };
