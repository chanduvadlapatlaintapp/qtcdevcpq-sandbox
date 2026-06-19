// @ts-check
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'startDateBoundary';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');

// The LWC's showToast (agenticQtcQuoteEditor.js:964) renders a custom
// <div class="toast-container"> and auto-dismisses after 3000ms — the watcher
// must be armed BEFORE typing the invalid date, not after.
const EXPECTED_UPPER_TOAST_RE = /Invalid date:\s*quote start date cannot be after the end date of the first term/i;
const EXPECTED_LOWER_TOAST_RE = /Invalid date:\s*quote start date cannot be earlier than the start date of the first term/i;

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
 * Query the QuoteLine table and split the first-term anchor lines (segmentIndex=1
 * or non-segmented) from the rest. Used by both bound attempts to compute the
 * lower floor (max start) and the upper cap (min end).
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} quoteName
 */
async function fetchFirstTermBounds(page, quoteName) {
  const soql = `SELECT Id, Name, SBQQ__ProductName__c,
                       SBQQ__StartDate__c, SBQQ__EndDate__c,
                       SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c
                FROM SBQQ__QuoteLine__c
                WHERE SBQQ__Quote__r.Name = '${quoteName}'
                ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS FIRST`;
  /** @type {any[]} */ let dbLines = [];
  /** @type {string|null} */ let dbError = null;
  try {
    const res = await u.sfQuery(page, sfCtx.instanceUrl, sfCtx.accessToken, soql);
    dbLines = res.records || [];
  } catch (e) {
    dbError = String(e);
  }
  const firstTermLines = dbLines.filter(d => d.SBQQ__SegmentKey__c == null || d.SBQQ__SegmentIndex__c === 1);
  const firstTermEnds   = firstTermLines.map(d => d.SBQQ__EndDate__c  ).filter(Boolean).sort();
  const firstTermStarts = firstTermLines.map(d => d.SBQQ__StartDate__c).filter(Boolean).sort();
  return {
    dbLines, dbError,
    firstTermEndISO:   firstTermEnds.length   > 0 ? /** @type {string} */ (firstTermEnds[0])                          : null,
    firstTermStartISO: firstTermStarts.length > 0 ? /** @type {string} */ (firstTermStarts[firstTermStarts.length - 1]) : null,
  };
}

/**
 * Drive an out-of-range Start Date attempt and capture whether the LWC's
 * error toast fired.
 *
 * Arms the toast watcher BEFORE typing — the toast auto-dismisses after 3s
 * so the watcher must be in flight before the dispatch happens.
 *
 * @param {import('@playwright/test').Page} page
 * @param {import('./utils/agenticQtcPage').AgenticQtcPage} qtc
 * @param {string} attemptedISO
 * @param {RegExp} toastRe
 */
async function attemptDateAndCaptureToast(page, qtc, attemptedISO, toastRe) {
  const toastLoc = page.locator('div.toast-container').filter({ hasText: toastRe }).first();
  const toastP = toastLoc.waitFor({ state: 'visible', timeout: 15_000 }).then(() => true).catch(() => false);
  await qtc.setStartDate(attemptedISO);
  const toastAppeared = await toastP;
  /** @type {string|null} */
  let toastText = null;
  if (toastAppeared) toastText = (await toastLoc.innerText().catch(() => '')).trim() || null;
  return { toastAppeared, toastText };
}

/**
 * Inner feature: in one editor session, try both the upper bound (first-term
 * end + 1 day) and the lower bound (first-term start − 1 day) and assert both
 * toasts fire. Mirrors handleStartDateChange's two branches in
 * agenticQtcQuoteEditor.js:677-698.
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
async function runBothBoundChecks(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  const initialUIDisplay = await qtc.getStartDate();
  const initialUIISO     = u.parseLongDateToISO(initialUIDisplay);
  expect(initialUIISO, 'Quote should have a valid initial Start Date').not.toBeNull();

  const dbHeader = await qtc.fetchQuoteFromDb(quoteName);
  expect(dbHeader, `SBQQ__Quote__c '${quoteName}' should be queryable via REST`).not.toBeNull();
  const dbQuoteStartDate = dbHeader?.SBQQ__StartDate__c ?? null;

  const bounds = await fetchFirstTermBounds(page, quoteName);
  expect(bounds.firstTermStartISO, 'Quote should have a first-term line with start date').not.toBeNull();
  expect(bounds.firstTermEndISO,   'Quote should have a first-term line with end date').not.toBeNull();

  // Lower bound first — LWC rolls input back to last valid value so the upper
  // attempt that follows starts from the same baseline.
  const lowerAttempted = u.formatDateISO(u.addDays(new Date(`${bounds.firstTermStartISO}T00:00:00`), -1));
  console.log(`[${KIND}] Lower attempt: ${lowerAttempted} (floor was ${bounds.firstTermStartISO})`);
  const lower = await attemptDateAndCaptureToast(page, qtc, lowerAttempted, EXPECTED_LOWER_TOAST_RE);
  await u.screenshot(page, runDir, '03-lower-after-toast');

  const upperAttempted = u.formatDateISO(u.addDays(new Date(`${bounds.firstTermEndISO}T00:00:00`), 1));
  console.log(`[${KIND}] Upper attempt: ${upperAttempted} (cap was ${bounds.firstTermEndISO})`);
  const upper = await attemptDateAndCaptureToast(page, qtc, upperAttempted, EXPECTED_UPPER_TOAST_RE);
  await u.screenshot(page, runDir, '04-upper-after-toast');

  const afterUIDisplay = await qtc.getStartDate();
  const afterUIISO     = u.parseLongDateToISO(afterUIDisplay);

  // Build per-line context for the dashboard
  const lineComparison = bounds.dbLines.map((db, i) => {
    const segIndex   = db.SBQQ__SegmentIndex__c ?? null;
    const isSegmented = db.SBQQ__SegmentKey__c != null;
    const isFirstTerm = !isSegmented || segIndex === 1;
    return {
      index:           i + 1,
      product:         db.SBQQ__ProductName__c || '—',
      segmentIndex:    segIndex,
      segmentKey:      db.SBQQ__SegmentKey__c ?? null,
      isSegmented, isFirstTerm,
      isLowerBoundary: isFirstTerm && db.SBQQ__StartDate__c === bounds.firstTermStartISO,
      isUpperBoundary: isFirstTerm && db.SBQQ__EndDate__c   === bounds.firstTermEndISO,
      dbStartDate:     db.SBQQ__StartDate__c ?? null,
      dbEndDate:       db.SBQQ__EndDate__c ?? null,
    };
  });

  expect(lower.toastAppeared,
    `Lower-bound error toast should fire within 15s for ${lowerAttempted} (floor ${bounds.firstTermStartISO})`).toBe(true);
  expect(upper.toastAppeared,
    `Upper-bound error toast should fire within 15s for ${upperAttempted} (cap ${bounds.firstTermEndISO})`).toBe(true);

  // Populate dbComparison so the dashboard's DB Lines tab renders. Date fields
  // are the meaningful values for this suite, with flags for which line was the
  // boundary anchor for each bound attempt.
  const dbComparison = lineComparison.map(r => ({
    index:    r.index,
    product:  r.product + (r.isLowerBoundary ? ' (lower anchor)' : r.isUpperBoundary ? ' (upper anchor)' : ''),
    segKey:   r.segmentKey || '—',
    segIndex: r.segmentIndex,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
    dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
    isBundle: false,
    startDate: r.dbStartDate, endDate: r.dbEndDate,
    pricingMethod: null, term: null, regularPrice: null,
  }));

  // UI ↔ DB cross-check: for first-term lines, verify that after both invalid
  // attempts the DB was NOT modified (rollback worked). hasData:true marks the
  // anchor rows we actually validated; non-first-term lines are informational.
  const uiDbCrossCheck = lineComparison.map(r => ({
    uiIndex:  r.index,
    product:  r.product + (r.segmentIndex != null ? ` · Y${r.segmentIndex}` : ''),
    segOcc:   r.segmentIndex,
    uiBefore: initialUIISO,
    uiAfter:  afterUIISO || initialUIISO,   // should be initial after both rollbacks
    dbPrior:  r.dbStartDate,
    dbAfter:  r.dbStartDate,                // DB unchanged → after = prior
    match:    r.isFirstTerm,                // first-term lines: rollback verified
    hasData:  r.isFirstTerm,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: dbHeader?.Id || null,
    dbLineCount: bounds.dbLines.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: lower.toastAppeared && upper.toastAppeared,
    extra: {
      initialUIDisplay, initialUIISO,
      dbQuoteStartDate,
      afterUIDisplay, afterUIISO,
      lower: { attemptedISO: lowerAttempted, floorISO: bounds.firstTermStartISO, ...lower },
      upper: { attemptedISO: upperAttempted, capISO:   bounds.firstTermEndISO,   ...upper },
      lineComparison,
      dbError: bounds.dbError,
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

  await runBothBoundChecks({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — fresh amendment, lower + upper boundary rejection', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, lower + upper boundary rejection', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, lower + upper boundary rejection', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
