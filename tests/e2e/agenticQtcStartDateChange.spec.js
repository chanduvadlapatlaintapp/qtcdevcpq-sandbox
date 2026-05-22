// @ts-check
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'startDateChange';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const DATE_DELTA_DAYS   = 5;

/** @type {import('./utils/scenarioContracts').SfCtx & { accountSearch:string, accountFullName:string }} */
let sfCtx;
/** @type {import('./utils/scenarioContracts').ContractCache|null} */
let contractCache = null;

test.beforeAll(async ({ browser }) => {
  const creds = getSfCredentials();
  sfCtx = {
    instanceUrl:     creds.instanceUrl,
    lightningUrl:    creds.lightningUrl,
    accessToken:     creds.accessToken,
    accountSearch:   ACCOUNT_SEARCH,
    accountFullName: ACCOUNT_FULL_NAME,
  };
  contractCache = await discoverContractByScenarios(browser, sfCtx);
});

/**
 * Inner feature: bump Start Date by N days, save, verify UI ↔ Quote header ↔
 * Year-1 QuoteLine anchors. CPQ regenerates segments asynchronously so we
 * poll the DB until all Year-1 anchors catch up (or the timeout fires, in
 * which case the rich-results report shows which lines lagged).
 *
 * @param {{
 *   page: import('@playwright/test').Page,
 *   qtc:  import('./utils/agenticQtcPage').AgenticQtcPage,
 *   runDir: string, runTs: string, testStartMs: number,
 *   contract: import('./utils/scenarioContracts').ContractRec,
 *   scenarioNumber: 1|2|3, scenarioLabel: string,
 *   quoteName: string,
 * }} ctx
 */
async function runStartDateChange(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  const initialDisplay = await qtc.getStartDate();
  const initialISO     = u.parseLongDateToISO(initialDisplay);
  expect(initialISO, 'Quote should have a valid initial Start Date').not.toBeNull();

  const baseDate  = new Date(`${initialISO}T00:00:00`);
  const targetISO = u.formatDateISO(u.addDays(baseDate, DATE_DELTA_DAYS));
  await qtc.setStartDate(targetISO);
  await u.screenshot(page, runDir, '03-after-date-set');

  await qtc.save();
  await u.screenshot(page, runDir, '04-after-save');

  const uiDisplayAfter = await qtc.getStartDate();
  const uiISOAfter     = u.parseLongDateToISO(uiDisplayAfter);

  const dbHeader = await qtc.fetchQuoteFromDb(quoteName);
  expect(dbHeader, `SBQQ__Quote__c '${quoteName}' should be queryable via REST`).not.toBeNull();
  const dbStartDate = dbHeader?.SBQQ__StartDate__c ?? null;

  // Poll until Year-1 anchors catch up — CPQ regenerates segments async after
  // header save commits.
  const lineSoql = `SELECT Id, Name, SBQQ__ProductName__c,
                           SBQQ__StartDate__c, SBQQ__EndDate__c,
                           SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c
                    FROM SBQQ__QuoteLine__c
                    WHERE SBQQ__Quote__r.Name = '${quoteName}'
                    ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS FIRST`;
  /** @type {any[]} */ let dbLines = [];
  /** @type {string|null} */ let dbError = null;
  const POLL_MAX_MS = 60_000, POLL_INTERVAL = 3_000;
  const pollStart = Date.now();
  let attempts = 0;
  while (Date.now() - pollStart < POLL_MAX_MS) {
    attempts++;
    try {
      const res = await u.sfQuery(page, sfCtx.instanceUrl, sfCtx.accessToken, lineSoql);
      dbLines = res.records || [];
    } catch (e) {
      dbError = String(e);
      break;
    }
    const yearOneOk = dbLines
      .filter(d => d.SBQQ__SegmentIndex__c == null || d.SBQQ__SegmentIndex__c === 1)
      .every(d => d.SBQQ__StartDate__c === uiISOAfter);
    if (yearOneOk) break;
    await page.waitForTimeout(POLL_INTERVAL);
  }
  console.log(`[${KIND}] DB poll: ${attempts} attempt(s), ${dbLines.length} line(s), ${Math.round((Date.now()-pollStart)/1000)}s`);

  const lineComparison = dbLines.map((db, i) => {
    const segIndex   = db.SBQQ__SegmentIndex__c ?? null;
    const isSegmented = segIndex !== null;
    const isYearOne  = !isSegmented || segIndex === 1;
    const lineStart  = db.SBQQ__StartDate__c ?? null;
    return {
      index:             i + 1,
      product:           db.SBQQ__ProductName__c || '—',
      segmentIndex:      segIndex,
      segmentKey:        db.SBQQ__SegmentKey__c ?? null,
      isSegmented, isYearOne,
      dbStartDate:       lineStart,
      dbEndDate:         db.SBQQ__EndDate__c ?? null,
      expectedStartDate: isYearOne ? uiISOAfter : null,
      match:             isYearOne && lineStart === uiISOAfter,
    };
  });

  expect(uiISOAfter, 'UI Start Date should have changed from the initial value').not.toBe(initialISO);
  expect(dbStartDate, 'SBQQ__Quote__c.SBQQ__StartDate__c should match new UI Start Date').toBe(uiISOAfter);

  const yearOneRows = lineComparison.filter(r => r.isYearOne);
  const yearOneBad  = yearOneRows.filter(r => !r.match);
  const allYearOnePass = yearOneBad.length === 0;

  // Populate dbComparison so the dashboard's DB Lines tab renders. For a date
  // change we don't have qty/price data — the meaningful DB fields are
  // start/end dates per line.
  const dbComparison = lineComparison.map(r => ({
    index:    r.index,
    product:  r.product,
    segKey:   r.segmentKey || '—',
    segIndex: r.segmentIndex,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
    dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
    isBundle: false,
    startDate: r.dbStartDate, endDate: r.dbEndDate,
    pricingMethod: null, term: null, regularPrice: null,
  }));

  // UI ↔ DB cross-check shows, for every Year-1 anchor, the UI's intended
  // new Start Date vs the DB's actual persisted Start Date. Other segments
  // are non-anchors (their startDate is intentionally != quote startDate) so
  // we mark them hasData:false to render as informational rows.
  const uiDbCrossCheck = lineComparison.map(r => ({
    uiIndex:  r.index,
    product:  r.product + (r.segmentIndex != null ? ` · Y${r.segmentIndex}` : ''),
    segOcc:   r.segmentIndex,
    uiBefore: initialISO,
    uiAfter:  r.isYearOne ? uiISOAfter : '(not anchor)',
    dbPrior:  initialISO,
    dbAfter:  r.dbStartDate,
    match:    r.isYearOne ? r.match : true,
    hasData:  r.isYearOne,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: dbHeader?.Id || null,
    dbLineCount: dbLines.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: allYearOnePass && crossCheckMismatches === 0,
    extra: {
      daysDelta: DATE_DELTA_DAYS,
      oldUIDateDisplay: initialDisplay,
      oldUIDateISO:     initialISO,
      newUIDateDisplay: uiDisplayAfter,
      newUIDateISO:     uiISOAfter,
      dbQuoteStartDate: dbStartDate,
      pollAttempts:     attempts,
      yearOneLagged:    yearOneBad.length,
      yearOneTotal:     yearOneRows.length,
      lineComparison, dbError,
    },
  });
}

/**
 * @param {import('@playwright/test').Page} page
 * @param {import('./utils/scenarioContracts').ContractRec} contract
 * @param {import('./utils/scenarioContracts').Branch} branch
 * @param {1|2|3} scenarioNumber
 * @param {string} scenarioLabel
 */
async function runScenario(page, contract, branch, scenarioNumber, scenarioLabel) {
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);
  console.log(`\n[Scenario ${scenarioNumber}] Contract ${contract.number} (branch=${branch}) → ${runDir}`);

  await u.screenshot(page, runDir, '01-contracts');
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[Scenario ${scenarioNumber}] Editor open on quote ${quoteName}`);

  await runStartDateChange({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — creates new amendment, then start date change', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — opens existing draft, then start date change', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — picks from modal, then start date change', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
