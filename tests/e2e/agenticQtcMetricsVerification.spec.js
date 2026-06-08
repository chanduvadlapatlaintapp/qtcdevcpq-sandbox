// @ts-check
/**
 * Header Metrics Verification — QTC Test Runner suite.
 *
 * Standalone, dashboard-selectable suite (registered in agenticQTC_TestSuite__mdt
 * as 'agenticQtcMetricsVerification'). Does NOT auto-run with other specs.
 *
 * Flow: open the amendment editor → bump every editable line's quantity by
 * +QTY_DELTA → Save → read the four header metric tiles from the UI and verify
 * each is correct against the persisted Salesforce data after the save:
 *
 *   ┌────────────────────┬────────────────────────────────────────────────────┐
 *   │ UI metric tile     │ DB source of truth                                  │
 *   ├────────────────────┼────────────────────────────────────────────────────┤
 *   │ ACV                │ Σ SBQQ__QuoteLine__c.ACV__c over the CURRENT-segment │
 *   │                    │ lines (no SegmentKey, or StartDate ≤ quoteStart ≤    │
 *   │                    │ EndDate). Mirrors agenticQtcQuoteEditor              │
 *   │                    │ ._currentSegmentLines → AgenticQTCAppFormulas.totalAcv│
 *   │ TCV                │ subscription baseline + Σ SBQQ__NetTotal__c over the │
 *   │                    │ VISIBLE lines. Baseline = Σ(NetPrice × Quantity) for │
 *   │                    │ the contract's Software SBQQ__Subscription__c rows   │
 *   │                    │ (AgenticQTC_ContractService.buildSubscriptionAggregates),│
 *   │                    │ visible = CPQ_Option_Type__c != 'Static Component'   │
 *   │                    │ and segment in range. Mirrors editor.totalTcv.       │
 *   │ YoY Uplift         │ SBQQ__Quote__c.Min_year_on_year_committed_spend__c   │
 *   │ Deal Quality Score │ SBQQ__Quote__c.Deal_Quality_Score__c                 │
 *   └────────────────────┴────────────────────────────────────────────────────┘
 *
 * After Save the editor re-runs getQuoteDetails, so the tiles render the
 * server-recomputed values — this test asserts the editor surfaces them
 * faithfully. Results are written to results.json in the canonical shape the
 * agenticQtcTestDashboard LWC consumes (Metrics tab + UI↔DB tab).
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'metricsVerification';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const QTY_DELTA         = 1;

// Tolerances: CPQ currency rounding can drift a few cents across the segment
// sum, percentages are stored to 2 dp.
const CURRENCY_TOL = 1.0;   // $1 — absolute, for ACV / TCV
const PCT_TOL      = 0.01;  // for YoY Uplift / Deal Quality Score

const PRODUCT_TYPE_SOFTWARE = 'Software'; // AgenticQTC_ContractService.PRODUCT_TYPE_SOFTWARE

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
 * Parse a metric tile display string to a number. The editor formats currency
 * with the quote's ISO code, not a '$' symbol — e.g. 'USD 5,924,880.35' — and
 * percentages as '+0.00%'. Strip everything except digits, decimal point, and a
 * leading minus so all of 'USD 5,924,880.35', '+5.00%', '95', '95.0' parse.
 * Returns null for empty / '--' / '—' / 'N/A'.
 * @param {string|undefined} str
 */
function parseMetric(str) {
  if (str == null) return null;
  const s = String(str).trim();
  if (!s || s === '--' || s === '—' || s === 'N/A') return null;
  const cleaned = s.replace(/[^0-9.\-]/g, '');
  if (cleaned === '' || cleaned === '-' || cleaned === '.') return null;
  const n = parseFloat(cleaned);
  return Number.isNaN(n) ? null : n;
}

/** @param {number|null} a @param {number|null} b @param {number} tol */
function within(a, b, tol) {
  if (a == null && b == null) return true;          // both absent → match
  if (a == null || b == null) return false;         // one absent → mismatch
  return Math.abs(a - b) <= tol;
}

/** @param {number|null} n */
function fmtCurrency(n) {
  return n == null ? '—' : '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
/** @param {number|null} n */
function fmtPct(n) { return n == null ? '—' : n.toFixed(2) + '%'; }

/**
 * Query Salesforce and compute the expected value for each of the four metrics,
 * replicating the editor's getter logic exactly.
 *
 * The reference start date for the segment filter is the quote's persisted
 * SBQQ__StartDate__c (ISO), NOT the UI input — after save the editor's
 * quoteStartDate equals the saved value, and reading it from the DB avoids the
 * UI's locale-formatted date string breaking lexicographic date comparisons.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} quoteName
 * @param {string} contractId
 */
async function computeExpectedFromDb(page, quoteName, contractId) {
  const apiBase = sfCtx.instanceUrl + '/services/data/v62.0';

  const headerSoql = `SELECT Id, Name, SBQQ__StartDate__c, Deal_Quality_Score__c,
                             Min_year_on_year_committed_spend__c
                      FROM SBQQ__Quote__c WHERE Name = '${quoteName}' LIMIT 1`;
  const lineSoql = `SELECT ACV__c, SBQQ__NetTotal__c, SBQQ__SegmentKey__c,
                           SBQQ__StartDate__c, SBQQ__EndDate__c, CPQ_Option_Type__c,
                           SBQQ__Bundle__c
                    FROM SBQQ__QuoteLine__c
                    WHERE SBQQ__Quote__r.Name = '${quoteName}'`;
  // TCV baseline — same aggregate as AgenticQTC_ContractService.buildSubscriptionAggregates:
  // Σ(NetPrice × Quantity) across every Software subscription segment on the contract.
  const subSoql = `SELECT SBQQ__NetPrice__c, SBQQ__Quantity__c
                   FROM SBQQ__Subscription__c
                   WHERE SBQQ__Contract__c = '${contractId}'
                   AND SBQQ__Product__r.Product_Type__c = '${PRODUCT_TYPE_SOFTWARE}'`;

  const { header, lines, subs } = await page.evaluate(async (/** @type {any} */ args) => {
    const headers = { Authorization: `Bearer ${args.token}`, 'Content-Type': 'application/json' };
    /** @param {string} soql */
    const q = (soql) => fetch(`${args.apiBase}/query?q=${encodeURIComponent(soql)}`, { headers }).then(r => r.json());
    const [h, l, s] = await Promise.all([q(args.headerSoql), q(args.lineSoql), q(args.subSoql)]);
    return { header: h.records?.[0] || null, lines: l.records || [], subs: s.records || [] };
  }, { apiBase, token: sfCtx.accessToken, headerSoql, lineSoql, subSoql });

  /** @param {any} v */
  const num = (v) => (v == null ? 0 : Number(v));

  // Persisted quote start date (ISO). The editor's _currentSegmentLines /
  // _visibleQuoteLines getters key off this; when it's blank they include every
  // line, so mirror that here.
  const quoteStartIso = header && header.SBQQ__StartDate__c ? header.SBQQ__StartDate__c : null;

  // Bundle parents are stripped from the editor's quoteLines (_stripBundleLines →
  // SBQQ__Bundle__c == true), so they never contribute to any header metric.
  const realLines = lines.filter((/** @type {any} */ l) => l.SBQQ__Bundle__c !== true);

  // ── ACV: Σ ACV__c over current-segment lines (editor._currentSegmentLines) ──
  /** @param {any} l */
  const isCurrentSegment = (l) => {
    if (!quoteStartIso) return true;
    if (!l.SBQQ__SegmentKey__c) return true;
    if (l.SBQQ__StartDate__c && quoteStartIso < l.SBQQ__StartDate__c) return false;
    if (l.SBQQ__EndDate__c   && quoteStartIso > l.SBQQ__EndDate__c)   return false;
    return true;
  };
  const expectedAcv = realLines.filter(isCurrentSegment).reduce((/** @type {number} */ sum, /** @type {any} */ l) => sum + num(l.ACV__c), 0);

  // ── TCV: subscription baseline + Σ NetTotal over visible lines (editor._visibleQuoteLines) ──
  /** @param {any} l */
  const isVisible = (l) => {
    if (l.CPQ_Option_Type__c === 'Static Component') return false;
    if (!quoteStartIso) return true;
    if (!l.SBQQ__SegmentKey__c) return true;
    return !l.SBQQ__EndDate__c || l.SBQQ__EndDate__c >= quoteStartIso;
  };
  const baseline   = subs.reduce((/** @type {number} */ sum, /** @type {any} */ s) => sum + num(s.SBQQ__NetPrice__c) * num(s.SBQQ__Quantity__c), 0);
  const sumNetTotal = realLines.filter(isVisible).reduce((/** @type {number} */ sum, /** @type {any} */ l) => sum + num(l.SBQQ__NetTotal__c), 0);
  const expectedTcv = baseline + sumNetTotal;

  // ── YoY Uplift + Deal Quality Score: direct header fields ──
  const expectedYoy = header && header.Min_year_on_year_committed_spend__c != null
    ? Number(header.Min_year_on_year_committed_spend__c) : null;
  const expectedDqs = header && header.Deal_Quality_Score__c != null
    ? Number(header.Deal_Quality_Score__c) : null;

  return {
    expectedAcv, expectedTcv, expectedYoy, expectedDqs,
    baseline, sumNetTotal, quoteStartIso,
    quoteId: header?.Id || null,
    dbLineCount: realLines.length,
  };
}

/**
 * @param {{
 *   page: import('@playwright/test').Page,
 *   qtc:  import('./utils/agenticQtcPage').AgenticQtcPage,
 *   runDir: string, runTs: string, testStartMs: number,
 *   contract: import('./utils/scenarioContracts').ContractRec,
 *   scenarioNumber: 1|2|3, scenarioLabel: string,
 *   quoteName: string,
 * }} ctx
 */
async function runMetricsVerification(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;

  const spinbuttonCount = await qtc.waitForLines(120_000);
  expect(spinbuttonCount, 'Editor should expose at least one editable line').toBeGreaterThan(0);

  await u.screenshot(page, runDir, '01-editor-loaded');

  // Metrics before the edit — UI tiles + the DB-recomputed equivalents — so the
  // dashboard's UI↔DB tab can show Before/After on both sides.
  const uiBefore = await qtc.readHeaderMetrics();
  const dbBefore = await computeExpectedFromDb(page, quoteName, contract.id);

  // ── Update quantities (+QTY_DELTA on every editable line), then Save ──
  const spinbuttons = page.getByRole('spinbutton');
  for (let i = 0; i < spinbuttonCount; i++) {
    const sb      = spinbuttons.nth(i);
    const current = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
    await sb.click({ clickCount: 3 });
    await sb.fill(String(current + QTY_DELTA));
    await sb.press('Tab');
    await page.waitForTimeout(600);
  }
  await u.screenshot(page, runDir, '02-after-qty-update');

  await qtc.save(120_000);
  await u.screenshot(page, runDir, '03-after-save');

  // Metrics after Save (these reflect the server-recomputed values).
  const uiAfter = await qtc.readHeaderMetrics();

  const uiAcv = parseMetric(uiAfter['ACV']);
  const uiTcv = parseMetric(uiAfter['TCV']);
  const uiYoy = parseMetric(uiAfter['YoY Uplift']);
  const uiDqs = parseMetric(uiAfter['Deal Quality Score']);

  // ── DB-derived expected values ──
  const db = await computeExpectedFromDb(page, quoteName, contract.id);

  // Each metric carries its UI + DB value both BEFORE the edit and AFTER save.
  // Pass/fail keys off the AFTER pair (UI must equal the freshly-persisted DB);
  // the BEFORE pair is shown for context (movement after the qty change).
  /** @type {Array<{metric:string, uiBefore:number|null, uiAfter:number|null, dbBefore:number|null, dbAfter:number|null, tol:number, isPct:boolean}>} */
  const checks = [
    { metric: 'ACV',                uiBefore: parseMetric(uiBefore['ACV']),                uiAfter: uiAcv, dbBefore: dbBefore.expectedAcv, dbAfter: db.expectedAcv, tol: CURRENCY_TOL, isPct: false },
    { metric: 'TCV',                uiBefore: parseMetric(uiBefore['TCV']),                uiAfter: uiTcv, dbBefore: dbBefore.expectedTcv, dbAfter: db.expectedTcv, tol: CURRENCY_TOL, isPct: false },
    { metric: 'YoY Uplift',         uiBefore: parseMetric(uiBefore['YoY Uplift']),         uiAfter: uiYoy, dbBefore: dbBefore.expectedYoy, dbAfter: db.expectedYoy, tol: PCT_TOL,      isPct: true  },
    { metric: 'Deal Quality Score', uiBefore: parseMetric(uiBefore['Deal Quality Score']), uiAfter: uiDqs, dbBefore: dbBefore.expectedDqs, dbAfter: db.expectedDqs, tol: PCT_TOL,      isPct: true  },
  ];

  // ── Build dashboard payloads ──
  /** @type {Array<{type:string,severity:string,detail:string}>} */
  const dbAnomalies = [];
  /** @type {any[]} */ const uiDbCrossCheck = [];
  /** @type {any[]} */ const metricResults  = [];
  let allMatch = true;

  checks.forEach((c, idx) => {
    const match = within(c.uiAfter, c.dbAfter, c.tol);
    if (!match) allMatch = false;
    const fmt = c.isPct ? fmtPct : fmtCurrency;
    if (!match) {
      dbAnomalies.push({
        type: `${c.metric} UI≠DB`, severity: 'HIGH',
        detail: `${c.metric}: UI shows ${fmt(c.uiAfter)} but DB computes ${fmt(c.dbAfter)} (tol ±${c.tol}).`,
      });
    }
    uiDbCrossCheck.push({
      uiIndex:  idx + 1,
      product:  c.metric,
      segOcc:   null,
      uiBefore: c.uiBefore != null ? fmt(c.uiBefore) : null,
      uiAfter:  c.uiAfter  != null ? fmt(c.uiAfter)  : null,
      dbPrior:  c.dbBefore != null ? fmt(c.dbBefore) : null,
      dbAfter:  c.dbAfter  != null ? fmt(c.dbAfter)  : null,
      match, hasData: true,
    });
    metricResults.push({
      metric: c.metric,
      before: uiBefore[c.metric] || '—',
      after:  uiAfter[c.metric] || '—',
      pass:   match,
      note:   match ? 'UI matches DB' : `Expected ${fmt(c.dbAfter)} from DB`,
    });
  });

  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: db.quoteId,
    spinbuttonCount,
    dbLineCount: db.dbLineCount,
    deltaApplied: QTY_DELTA,
    metricsBeforeSave: {
      acv:         uiBefore['ACV']                || 'N/A',
      tcv:         uiBefore['TCV']                || 'N/A',
      yoyUplift:   uiBefore['YoY Uplift']         || 'N/A',
      dealQuality: uiBefore['Deal Quality Score'] || 'N/A',
    },
    metricsAfterSave: {
      acv:         uiAfter['ACV']                || 'N/A',
      tcv:         uiAfter['TCV']                || 'N/A',
      yoyUplift:   uiAfter['YoY Uplift']         || 'N/A',
      dealQuality: uiAfter['Deal Quality Score'] || 'N/A',
    },
    metricResults,
    dbAnomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed: allMatch,
    extra: {
      tcvBaseline: db.baseline,
      tcvLineNetTotal: db.sumNetTotal,
      expected: {
        acv: db.expectedAcv, tcv: db.expectedTcv,
        yoyUplift: db.expectedYoy, dealQuality: db.expectedDqs,
      },
    },
  });

  // Per-metric assertions so each mismatch is named in the Playwright output.
  for (const c of checks) {
    const fmt = c.isPct ? fmtPct : fmtCurrency;
    expect(within(c.uiAfter, c.dbAfter, c.tol),
      `${c.metric} mismatch: UI=${fmt(c.uiAfter)} vs DB=${fmt(c.dbAfter)} (tol ±${c.tol})`).toBe(true);
  }
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
  console.log(`\n[Metrics ${scenarioNumber}] Contract ${contract.number} (branch=${branch}) → ${runDir}`);

  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[Metrics ${scenarioNumber}] Editor open on quote ${quoteName}`);

  await runMetricsVerification({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: 0 amendments — new amendment, qty change, verify ACV/TCV/YoY/DQS vs DB', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Metrics verification — 0 amendments → new amendment');
});

test('Scenario 2: 1 amendment — existing draft, qty change, verify ACV/TCV/YoY/DQS vs DB', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Metrics verification — 1 amendment → existing draft');
});

test('Scenario 3: 2+ amendments — modal pick, qty change, verify ACV/TCV/YoY/DQS vs DB', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Metrics verification — 2+ amendments → modal pick');
});
