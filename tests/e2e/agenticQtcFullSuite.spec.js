// @ts-check
/**
 * agenticQtcFullSuite.spec.js
 *
 * Unified suite — runs all 56 scenarios from the 19 standard specs in a single
 * browser session with ONE shared beforeAll (one login, one contract discovery).
 *
 * Groups: 1 Account Search · 2 OSA Selector · 3 App Nav · 4 Editor Core ·
 *   5 Editor Buttons · 6 Contact Update · 7 Start Date Change · 8 Start Date
 *   Boundary · 9 Qty Increase · 10 Qty Decrease · 11 Qty Increase Segments ·
 *   12 Qty Decrease Segments · 13 Metrics · 14 Qty Increase Non-Segment ·
 *   15 Qty Increase Bundle Segments · 16 Qty Increase Bundle Non-Segment ·
 *   17 Qty Decrease Non-Segment · 18 Qty Decrease Bundle Non-Segment ·
 *   19 Qty Decrease Bundle Segments.
 *
 * Key behaviours:
 *   • runSafe() wraps every scenario: errors are caught and recorded as FAIL;
 *     the Playwright test itself never throws, so ALL scenarios always run.
 *   • If a pre-condition is not met (no contract with the right draft count, no
 *     MDQ/segment product, no bundle, no non-segment product, etc.) the scenario
 *     is recorded as SKIP (via skipScenario) and EXCLUDED from the percentage.
 *     → We never test a product type the quote doesn't contain.
 *   • Pass rate = passed / (passed + failed)  — skipped tests do not count.
 *   • The final SUITE SUMMARY test fails the overall run unless pass rate is 100%
 *     (i.e. any failed scenario fails the whole suite).
 *
 * Excluded:
 *   • agenticQtcCongaPdfDataSync / PreviewSendOSAUsingConga /
 *     PreviewSendOSAUsingSalesforce  — require Conga / Salesforce PDF setup
 *   • agenticQtcAmendmentFieldComparison — OOB REST endpoint throwing 500 (TODO)
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');
const { AgenticQtcPage } = require('./utils/agenticQtcPage');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

// ── Config ────────────────────────────────────────────────────────────────────
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const NONSENSE_TERM     = 'zzqxnomatch';
const RESULTS_DIR       = path.join(__dirname, 'results');
const PASS_THRESHOLD    = 100; // percent — suite passes only when EVERY evaluated scenario passes; any failure fails the suite

// ── Shared state (populated in beforeAll, read by every test) ─────────────────
/** @type {any} */ let sfCtx;
/** @type {any} */ let contractCache = null;

/** @type {Array<{name:string, status:'PASS'|'FAIL'|'SKIP', detail:string}>} */
const SUITE_RESULTS = [];

// ── Real UI↔DB cross-check rows, aggregated across ALL data-bearing scenarios ──
// Each scenario that compares a UI value against the database (quantities,
// contacts, start date, metrics, …) appends real rows here. The SUITE SUMMARY
// feeds this into richResults.uiDbCrossCheck so the dashboard's UI↔DB tab shows
// actual before/after values for every scenario type — not just qty inc/dec.
/** @type {Array<any>} */
const CROSS_CHECK = [];
let crossIdx = 0;
/** Current scenario label, set by runSafe — tags cross-check rows. @type {string} */
let currentLabel = '';

/**
 * Append one UI↔DB comparison row.
 * @param {string} label   scenario label, e.g. '[6.3] Contact Update'
 * @param {string} product field/product name shown in the Product column
 * @param {{uiBefore?:any, uiAfter?:any, dbPrior?:any, dbAfter?:any, segOcc?:any, match?:boolean, hasData?:boolean}} row
 */
function pushCrossRow(label, product, row) {
  crossIdx++;
  const uiAfter = row.uiAfter ?? null;
  const dbAfter = row.dbAfter ?? null;
  const match = row.match != null
    ? row.match
    : (uiAfter != null && dbAfter != null && String(uiAfter).trim() === String(dbAfter).trim());
  CROSS_CHECK.push({
    uiIndex:  crossIdx,
    product:  `${label} · ${product}`,
    segOcc:   row.segOcc   ?? null,
    uiBefore: row.uiBefore ?? null,
    uiAfter,
    dbPrior:  row.dbPrior  ?? null,
    dbAfter,
    match,
    hasData:  row.hasData ?? (uiAfter != null || dbAfter != null),
  });
}

/**
 * Capture per-line UI↔DB quantity rows for a scenario. Queries the DB once for
 * the given line IDs and appends a row per entry.
 * @param {string} label
 * @param {Array<{lineId:string|null, before:number, after:number, product?:string, segOcc?:any}>} entries
 */
async function captureQtyCross(label, entries) {
  const withId = entries.filter(e => e.lineId);
  /** @type {Map<string, any>} */
  let dbById = new Map();
  if (withId.length) {
    const soql = `SELECT Id, SBQQ__ProductName__c, SBQQ__Quantity__c, SBQQ__PriorQuantity__c FROM SBQQ__QuoteLine__c WHERE Id IN (${withId.map(e => `'${e.lineId}'`).join(',')})`;
    const res  = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql).catch(() => ({ records: [] }));
    dbById = new Map((res.records || []).map((/** @type {any} */ r) => [r.Id, r]));
  }
  entries.forEach((e, i) => {
    const db      = e.lineId ? dbById.get(e.lineId) : null;
    const dbAfter = db ? Number(db.SBQQ__Quantity__c) : null;
    const product = e.product || db?.SBQQ__ProductName__c || `Line ${i + 1}`;
    pushCrossRow(label, product, {
      segOcc:   e.segOcc ?? null,
      uiBefore: e.before,
      uiAfter:  e.after,
      dbPrior:  db ? (db.SBQQ__PriorQuantity__c ?? null) : null,
      dbAfter,
      match:    dbAfter != null && Math.abs(dbAfter - e.after) < 0.001,
      hasData:  dbAfter != null,
    });
  });
}

/**
 * Capture per-segment UI↔DB rows for one MDQ product row (each segment input
 * carries its own data-line-id).
 * @param {string} label
 * @param {{row:import('@playwright/test').Locator, productName:string}} mdqRow
 * @param {number[]} before  per-segment UI quantities before the edit
 */
async function captureSegmentCross(label, mdqRow, before) {
  const inputs = mdqRow.row.locator('input.qty-input');
  const n = await inputs.count();
  /** @type {Array<{lineId:string|null, before:number, after:number, product:string, segOcc:number}>} */
  const entries = [];
  for (let i = 0; i < n; i++) {
    const lineId = await inputs.nth(i).getAttribute('data-line-id').catch(() => null);
    const after  = parseFloat(await inputs.nth(i).inputValue().catch(() => '0')) || 0;
    entries.push({ lineId, before: before[i] ?? 0, after, product: `${mdqRow.productName || 'MDQ'} · Y${i + 1}`, segOcc: i + 1 });
  }
  await captureQtyCross(label, entries);
}

// ── Single shared setup ───────────────────────────────────────────────────────
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

// ── Result tracking ───────────────────────────────────────────────────────────
/**
 * @param {string} name
 * @param {'PASS'|'FAIL'|'SKIP'} status
 * @param {string} [detail]
 */
function record(name, status, detail = '') {
  SUITE_RESULTS.push({ name, status, detail });
  const ICONS = { PASS: '✅', FAIL: '❌', SKIP: '⏭' };
  console.log(`[FullSuite] ${ICONS[status]} ${name}${detail ? ' — ' + detail : ''}`);
}

/**
 * Thrown from inside a scenario body when its pre-condition is not met — e.g.
 * the open quote contains no MDQ/segment product, no bundle, or no non-segment
 * product. runSafe() records these as SKIP (excluded from the pass rate) rather
 * than FAIL, so we never penalise the suite for testing a product type the
 * quote simply doesn't contain.
 */
class SkipSignal extends Error {}
/** @param {string} reason */
function skipScenario(reason) { throw new SkipSignal(reason); }

/**
 * Wrap a scenario body, record its outcome into SUITE_RESULTS, AND reflect that
 * outcome in Playwright's own per-test status so the terminal/dashboard counts
 * are honest (no more "everything passed"):
 *   • SkipSignal      → record SKIP + test.skip()  → reported as SKIPPED
 *   • any other throw → record FAIL + re-throw      → reported as FAILED
 *   • success         → record PASS                 → reported as PASSED
 *
 * Every scenario still runs (failures are caught so later scenarios aren't
 * skipped), but the overall gate is now 100%: the SUITE SUMMARY → richResults.passed
 * that upload-results.js uses for the Test_Run status is true ONLY when there are
 * zero failures. Any failed scenario fails the whole suite.
 *
 * @param {string} name
 * @param {() => Promise<void>} fn
 */
async function runSafe(name, fn) {
  currentLabel = name;   // so run* helpers can tag their UI↔DB cross-check rows
  try {
    await fn();
    record(name, 'PASS');
  } catch (e) {
    if (e instanceof SkipSignal) {
      record(name, 'SKIP', e.message);
      test.skip(true, e.message);   // mark this Playwright test as skipped
      return;
    }
    const msg = e instanceof Error ? e.message.split('\n')[0].substring(0, 150) : String(e);
    record(name, 'FAIL', msg);
    throw e;                        // mark this Playwright test as failed (visible)
  }
}

// ── Shared navigation helpers ─────────────────────────────────────────────────
/** @param {import('@playwright/test').Page} page */
async function openApp(page) {
  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken);
  const qtc = new AgenticQtcPage(page, sfCtx);
  await qtc.goto();
  return qtc;
}

/** @param {import('@playwright/test').Page} page */
async function openContracts(page) {
  const qtc = await openApp(page);
  await qtc.searchAndSelectAccount(sfCtx.accountSearch, sfCtx.accountFullName);
  await qtc.contractRows().first().waitFor({ state: 'visible', timeout: 30_000 }).catch(() => {});
  return qtc;
}

// ── MDQ helpers (Groups 11 & 12) ──────────────────────────────────────────────
/** @param {import('@playwright/test').Page} page @param {number} minSeg @param {number} max */
async function pickMdqRows(page, minSeg = 2, max = 4) {
  const rows = page.locator('tr.product-row');
  const total = await rows.count();
  /** @type {Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number}>} */
  const picked = [];
  for (let i = 0; i < total && picked.length < max; i++) {
    const row = rows.nth(i);
    const n = await row.locator('input.qty-input').count();
    if (n >= minSeg) {
      const name = (await row.locator('.product-label').first().innerText().catch(() => '')).trim();
      picked.push({ row, productName: name, segmentCount: n });
    }
  }
  return picked;
}

/** @param {import('@playwright/test').Locator} row */
async function readSegQtys(row) {
  const inputs = row.locator('input.qty-input');
  const n = await inputs.count();
  /** @type {number[]} */ const out = [];
  for (let i = 0; i < n; i++) out.push(parseFloat(await inputs.nth(i).inputValue().catch(() => '0')) || 0);
  return out;
}

/** @param {import('@playwright/test').Locator} row @param {number} idx @param {number} val */
async function setSegQty(row, idx, val) {
  const input = row.locator('input.qty-input').nth(idx);
  await input.click({ clickCount: 3 }); await input.fill(String(val)); await input.press('Tab');
}

// ── Non-segment / bundle detection helpers (Groups 14-19) ─────────────────────
/**
 * Find every editable qty input that belongs to a NON-segment (single-period)
 * product: `tr.product-row` rows with exactly 1 `input.qty-input`, plus any
 * spinbutton outside a product row (legacy layout). MDQ rows (≥2 inputs) are
 * excluded.
 *
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<Array<{input:import('@playwright/test').Locator, lineId:string|null, initial:number}>>}
 */
async function findNonSegmentInputs(page) {
  /** @type {Array<{input:import('@playwright/test').Locator, lineId:string|null, initial:number}>} */
  const out = [];
  const rows = page.locator('tr.product-row');
  const rowCount = await rows.count().catch(() => 0);
  for (let i = 0; i < rowCount; i++) {
    const inputs = rows.nth(i).locator('input.qty-input');
    if ((await inputs.count()) !== 1) continue;  // skip MDQ rows
    const input  = inputs.first();
    const lineId = await input.getAttribute('data-line-id').catch(() => null);
    out.push({ input, lineId, initial: parseFloat(await input.inputValue().catch(() => '0')) || 0 });
  }
  // Fallback: spinbuttons outside any product row
  const sbs = page.getByRole('spinbutton');
  const sbCount = await sbs.count();
  for (let i = 0; i < sbCount; i++) {
    const sb = sbs.nth(i);
    if ((await sb.locator('xpath=ancestor::tr[contains(@class,"product-row")]').count()) > 0) continue;
    const lineId = await sb.getAttribute('data-line-id').catch(() => null);
    out.push({ input: sb, lineId, initial: parseFloat(await sb.inputValue().catch(() => '0')) || 0 });
  }
  return out;
}

/**
 * Given non-segment candidates, keep only those whose QuoteLine is a
 * `Static Bundle` (queried from the DB by data-line-id).
 *
 * @param {Array<{input:import('@playwright/test').Locator, lineId:string|null, initial:number}>} candidates
 */
async function filterStaticBundle(candidates) {
  const withId = candidates.filter(c => c.lineId);
  if (withId.length === 0) return [];
  const soql = `SELECT Id, CPQ_Option_Type__c FROM SBQQ__QuoteLine__c WHERE Id IN (${withId.map(c => `'${c.lineId}'`).join(',')})`;
  const res  = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  const set  = new Set((res.records || [])
    .filter((/** @type {any} */ r) => r.CPQ_Option_Type__c === 'Static Bundle')
    .map((/** @type {any} */ r) => r.Id));
  return withId.filter(c => set.has(c.lineId));
}

/**
 * Find MDQ (≥2-segment) rows whose segments include at least one
 * `Static Bundle` QuoteLine. Returns the row plus its per-segment line IDs.
 *
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, lineIds:string[]}>>}
 */
async function findBundleSegmentRows(page) {
  const rows = await pickMdqRows(page, 2, 8);
  /** @type {Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, lineIds:string[]}>} */
  const withIds = [];
  for (const r of rows) {
    const inputs = r.row.locator('input.qty-input');
    const n = await inputs.count();
    /** @type {string[]} */ const ids = [];
    for (let i = 0; i < n; i++) {
      const id = await inputs.nth(i).getAttribute('data-line-id').catch(() => null);
      if (id) ids.push(id);
    }
    if (ids.length) withIds.push({ ...r, lineIds: ids });
  }
  if (withIds.length === 0) return [];
  const allIds = withIds.flatMap(r => r.lineIds);
  const soql   = `SELECT Id, CPQ_Option_Type__c FROM SBQQ__QuoteLine__c WHERE Id IN (${allIds.map(id => `'${id}'`).join(',')})`;
  const res    = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  const set    = new Set((res.records || [])
    .filter((/** @type {any} */ r) => r.CPQ_Option_Type__c === 'Static Bundle')
    .map((/** @type {any} */ r) => r.Id));
  if (set.size === 0) return [];
  return withIds.filter(r => r.lineIds.some(id => set.has(id)));
}

/**
 * Apply a qty delta (positive = increase, negative = decrease with a floor of 1)
 * to each input, save, then verify the post-save value of each. Returns whether
 * every line matched its expected value.
 *
 * @param {import('@playwright/test').Page} page
 * @param {any} qtc
 * @param {Array<{input:import('@playwright/test').Locator, initial:number, lineId?:string|null}>} lines
 * @param {number} delta
 */
async function editSaveVerifyInputs(page, qtc, lines, delta) {
  /** @type {number[]} */ const initials = [];
  for (let i = 0; i < lines.length; i++) {
    const cur = parseFloat(await lines[i].input.inputValue().catch(() => '0')) || 0;
    initials.push(cur);
    const nv = delta >= 0 ? cur + delta : Math.max(1, cur + delta);
    await lines[i].input.click({ clickCount: 3 });
    await lines[i].input.fill(String(nv));
    await lines[i].input.press('Tab');
    await page.waitForTimeout(800);
  }
  await qtc.save(120_000);
  let allPass = true;
  /** @type {Array<{lineId:string|null, before:number, after:number, product?:string}>} */
  const entries = [];
  for (let i = 0; i < lines.length; i++) {
    const actual   = parseFloat(await lines[i].input.inputValue().catch(() => '0')) || 0;
    const expected = delta >= 0 ? initials[i] + delta : Math.max(1, initials[i] + delta);
    if (Math.abs(actual - expected) >= 0.001) allPass = false;
    const lineId  = lines[i].lineId ?? await lines[i].input.getAttribute('data-line-id').catch(() => null);
    const product = (await lines[i].input.locator('xpath=ancestor::tr').first().locator('.product-label').first().innerText().catch(() => '')).trim();
    entries.push({ lineId, before: initials[i], after: actual, product });
  }
  await captureQtyCross(currentLabel, entries);
  return allPass;
}

// ── Metrics helpers (Groups 13) ───────────────────────────────────────────────
/**
 * @param {import('@playwright/test').Page} page
 * @param {string} quoteName
 * @param {string} contractId
 */
async function computeMetricsFromDb(page, quoteName, contractId) {
  const apiBase    = sfCtx.instanceUrl + '/services/data/v62.0';
  const headerSoql = `SELECT Id, SBQQ__StartDate__c, Deal_Quality_Score__c, Min_year_on_year_committed_spend__c FROM SBQQ__Quote__c WHERE Name = '${quoteName}' LIMIT 1`;
  const lineSoql   = `SELECT ACV__c, SBQQ__NetTotal__c, SBQQ__SegmentKey__c, SBQQ__StartDate__c, SBQQ__EndDate__c, CPQ_Option_Type__c, SBQQ__Bundle__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.Name = '${quoteName}'`;
  const subSoql    = `SELECT SBQQ__NetPrice__c, SBQQ__Quantity__c FROM SBQQ__Subscription__c WHERE SBQQ__Contract__c = '${contractId}' AND SBQQ__Product__r.Product_Type__c = 'Software'`;
  const { header, lines, subs } = await page.evaluate(async (/** @type {any} */ args) => {
    const h = { Authorization: `Bearer ${args.token}`, 'Content-Type': 'application/json' };
    const q = (/** @type {string} */ soql) => fetch(`${args.base}/query?q=${encodeURIComponent(soql)}`, { headers: h }).then(r => r.json());
    const [hd, ln, sb] = await Promise.all([q(args.headerSoql), q(args.lineSoql), q(args.subSoql)]);
    return { header: hd.records?.[0] || null, lines: ln.records || [], subs: sb.records || [] };
  }, { base: apiBase, token: sfCtx.accessToken, headerSoql, lineSoql, subSoql });
  const num = (/** @type {any} */ v) => (v == null ? 0 : Number(v));
  const qs  = header?.SBQQ__StartDate__c || null;
  const real = lines.filter((/** @type {any} */ l) => l.SBQQ__Bundle__c !== true);
  const isCurrentSeg = (/** @type {any} */ l) => {
    if (!qs || !l.SBQQ__SegmentKey__c) return true;
    if (l.SBQQ__StartDate__c && qs < l.SBQQ__StartDate__c) return false;
    if (l.SBQQ__EndDate__c   && qs > l.SBQQ__EndDate__c)   return false;
    return true;
  };
  const isVisible = (/** @type {any} */ l) => {
    if (l.CPQ_Option_Type__c === 'Static Component') return false;
    if (!qs || !l.SBQQ__SegmentKey__c) return true;
    return !l.SBQQ__EndDate__c || l.SBQQ__EndDate__c >= qs;
  };
  return {
    expectedAcv: real.filter(isCurrentSeg).reduce((/** @type {number} */ s, /** @type {any} */ l) => s + num(l.ACV__c), 0),
    expectedTcv: subs.reduce((/** @type {number} */ s, /** @type {any} */ sb) => s + num(sb.SBQQ__NetPrice__c) * num(sb.SBQQ__Quantity__c), 0)
               + real.filter(isVisible).reduce((/** @type {number} */ s, /** @type {any} */ l) => s + num(l.SBQQ__NetTotal__c), 0),
    expectedYoy: header?.Min_year_on_year_committed_spend__c != null ? Number(header.Min_year_on_year_committed_spend__c) : null,
    expectedDqs: header?.Deal_Quality_Score__c != null ? Number(header.Deal_Quality_Score__c) : null,
  };
}

function parseMetric(/** @type {string|undefined} */ str) {
  if (!str) return null;
  const s = String(str).trim();
  if (!s || s === '--' || s === '—' || s === 'N/A') return null;
  const n = parseFloat(s.replace(/[^0-9.\-]/g, ''));
  return Number.isNaN(n) ? null : n;
}

function within(/** @type {number|null} */ a, /** @type {number|null} */ b, /** @type {number} */ tol) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return Math.abs(a - b) <= tol;
}

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 1 — Account Search (3 tests)
// ─────────────────────────────────────────────────────────────────────────────

test('[1.1] Account Search: min-length gate (1 char shows no dropdown)', async ({ page }) => {
  await runSafe('[1.1] Account Search: min-length gate', async () => {
    const qtc = await openApp(page);
    await qtc.typeAccountSearch(ACCOUNT_SEARCH.charAt(0));
    const cardCount = await qtc.accountCards().count();
    const dropdown  = await u.isVisibleSafe(qtc.noResultsDropdown(), 1_000);
    pushCrossRow(currentLabel, 'Cards shown (1-char query)',   { uiAfter: cardCount,        dbAfter: 'expected 0',     match: cardCount === 0 });
    pushCrossRow(currentLabel, 'No-results dropdown shown',    { uiAfter: String(dropdown), dbAfter: 'expected false', match: dropdown === false });
    expect(cardCount).toBe(0);
    expect(dropdown).toBe(false);
  });
});

test('[1.2] Account Search: nonsense term shows empty-state', async ({ page }) => {
  await runSafe('[1.2] Account Search: nonsense term shows empty-state', async () => {
    const qtc = await openApp(page);
    await qtc.typeAccountSearch(NONSENSE_TERM);
    await expect(qtc.noResultsDropdown()).toBeVisible();
    const emptyText = (await qtc.noResultsDropdown().innerText().catch(() => '')).trim();
    const cardCount = await qtc.accountCards().count();
    pushCrossRow(currentLabel, 'Empty-state contains term', { uiAfter: emptyText.includes(NONSENSE_TERM) ? `“${NONSENSE_TERM}” shown` : emptyText, dbAfter: `expected “${NONSENSE_TERM}”`, match: emptyText.includes(NONSENSE_TERM) });
    pushCrossRow(currentLabel, 'Cards shown (nonsense term)', { uiAfter: cardCount, dbAfter: 'expected 0', match: cardCount === 0 });
    await expect(qtc.noResultsDropdown()).toContainText(NONSENSE_TERM);
    expect(cardCount).toBe(0);
  });
});

test('[1.3] Account Search: known term returns cards and navigates to contracts', async ({ page }) => {
  await runSafe('[1.3] Account Search: known term returns cards', async () => {
    const qtc = await openApp(page);
    await qtc.typeAccountSearch(ACCOUNT_SEARCH);
    await qtc.accountCards().first().waitFor({ state: 'visible', timeout: 20_000 });
    const cards = await qtc.readAccountCards();
    const matchByName = cards.some(c => (c.name || '').toLowerCase().includes(ACCOUNT_SEARCH.toLowerCase()));
    pushCrossRow(currentLabel, `Account cards for “${ACCOUNT_SEARCH}”`, { uiAfter: cards.length, dbAfter: 'expected >0', match: cards.length > 0 });
    pushCrossRow(currentLabel, 'Result matches search term', { uiAfter: String(matchByName), dbAfter: 'expected true', match: matchByName });
    expect(cards.length).toBeGreaterThan(0);
    expect(matchByName).toBe(true);
    await qtc.accountCards().first().click();
    await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 2 — OSA Selector (4 tests)
// ─────────────────────────────────────────────────────────────────────────────

test('[2.1] OSA Selector: contracts grid renders with correct count badge', async ({ page }) => {
  await runSafe('[2.1] OSA Selector: contracts grid', async () => {
    const qtc = await openContracts(page);
    const rowCount = await qtc.contractRows().count();
    expect(rowCount).toBeGreaterThan(0);
    await expect(qtc.contractCountBadge()).toBeVisible();
    const badge = (await qtc.contractCountBadge().innerText()).trim();
    const expected = rowCount === 1 ? '1 active contract' : `${rowCount} active contracts`;
    pushCrossRow(currentLabel, 'Contracts rendered', { uiAfter: rowCount, dbAfter: 'expected >0', match: rowCount > 0 });
    pushCrossRow(currentLabel, 'Count badge text', { uiAfter: badge, dbAfter: expected, match: badge === expected });
    expect(badge).toBe(expected);
  });
});

test('[2.2] OSA Selector: products +N more toggle expands without navigating away', async ({ page }) => {
  const qtc = await openContracts(page);
  if ((await qtc.productMoreButtons().count()) === 0) {
    record('[2.2] OSA Selector: +N more toggle', 'SKIP', 'No contract has >3 products');
    test.skip(true, 'No contract has >3 products');
  }
  await runSafe('[2.2] OSA Selector: +N more toggle', async () => {
    await qtc.productMoreButtons().first().click();
    const showLess = await qtc.productShowLessButton().isVisible().catch(() => false);
    const stayed   = await qtc.activeContractsHeading().isVisible().catch(() => false);
    const navigated = await u.isVisibleSafe(qtc.saveButton(), 1_500);
    pushCrossRow(currentLabel, 'Show-less appears on expand', { uiAfter: String(showLess), dbAfter: 'expected true', match: showLess });
    pushCrossRow(currentLabel, 'Stayed on contracts page',    { uiAfter: String(stayed),   dbAfter: 'expected true', match: stayed });
    pushCrossRow(currentLabel, 'Did NOT navigate to editor',  { uiAfter: String(navigated), dbAfter: 'expected false', match: navigated === false });
    await expect(qtc.productShowLessButton()).toBeVisible();
    await expect(qtc.activeContractsHeading()).toBeVisible();
    expect(navigated).toBe(false);
    await qtc.productShowLessButton().first().click();
    await expect(qtc.productMoreButtons().first()).toBeVisible();
  });
});

test('[2.3] OSA Selector: clear pill returns to account search', async ({ page }) => {
  await runSafe('[2.3] OSA Selector: clear pill', async () => {
    const qtc = await openContracts(page);
    await expect(qtc.accountPillClear()).toBeVisible();
    await qtc.accountPillClear().click();
    const backToSearch = await qtc.accountSearchInput().isVisible().catch(() => false);
    pushCrossRow(currentLabel, 'Clear pill → account search', { uiAfter: backToSearch ? 'search shown' : 'not shown', dbAfter: 'expected search shown', match: backToSearch });
    await expect(qtc.accountSearchInput()).toBeVisible();
  });
});

test('[2.4] OSA Selector: draft-quotes modal open / close / pick row', async ({ page }) => {
  const qtc = await openContracts(page);
  /** @type {any} */ let manyDraft = null;
  for (const c of await qtc.getContractList()) {
    if ((await qtc.countDraftQuotes(c.id)) >= 2) { manyDraft = c; break; }
  }
  if (!manyDraft) {
    record('[2.4] OSA Selector: draft-quotes modal', 'SKIP', 'No contract with ≥2 drafts');
    test.skip(true, 'No contract with ≥2 drafts');
  }
  await runSafe('[2.4] OSA Selector: draft-quotes modal', async () => {
    await qtc.clickContractById(manyDraft.id);
    const outcome = await qtc.waitForContractClickOutcome(120_000);
    pushCrossRow(currentLabel, 'Click outcome (≥2 drafts)', { uiAfter: outcome, dbAfter: 'expected modal', match: outcome === 'modal' });
    expect(outcome).toBe('modal');
    await expect(qtc.draftQuotesModal()).toBeVisible();
    const modalDrafts = await qtc.draftQuoteCountInModal();
    pushCrossRow(currentLabel, 'Drafts listed in modal', { uiAfter: modalDrafts, dbAfter: 'expected ≥2', match: modalDrafts >= 2 });
    expect(modalDrafts).toBeGreaterThanOrEqual(2);
    await qtc.draftModalClose().click();
    await expect(qtc.draftQuotesModal()).toBeHidden();
    await qtc.clickContractById(manyDraft.id);
    await expect(qtc.draftQuotesModal()).toBeVisible({ timeout: 120_000 });
    await qtc.draftQuoteRows().first().click();
    await qtc.saveButton().waitFor({ state: 'visible', timeout: 120_000 });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 3 — App Navigation (1 test)
// ─────────────────────────────────────────────────────────────────────────────

test('[3.1] App Navigation: theme toggles + record links + breadcrumb nav', async ({ page }) => {
  await runSafe('[3.1] App Navigation', async () => {
    await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken);
    const qtc = new AgenticQtcPage(page, sfCtx);
    await qtc.goto();
    const toggle = qtc.themeToggleButton();

    // Theme on account-search page
    await toggle.waitFor({ state: 'visible', timeout: 15_000 });
    const b1 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(400);
    const a1 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(300);
    const flip1 = b1 !== 'unknown' && a1 !== 'unknown' && a1 !== b1;
    pushCrossRow(currentLabel, 'Theme flip · account-search', { uiAfter: `${b1} → ${a1}`, dbAfter: 'expected flip', match: flip1 });
    expect(flip1, 'Theme must flip on account-search page').toBe(true);

    // Navigate to contracts, theme there
    await qtc.searchAndSelectAccount(sfCtx.accountSearch, sfCtx.accountFullName);
    await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
    const b2 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(400);
    const a2 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(300);
    const flip2 = b2 !== 'unknown' && a2 !== 'unknown' && a2 !== b2;
    pushCrossRow(currentLabel, 'Theme flip · contracts', { uiAfter: `${b2} → ${a2}`, dbAfter: 'expected flip', match: flip2 });
    expect(flip2, 'Theme must flip on contracts page').toBe(true);

    // Open editor, theme there
    expect(await qtc.openContractByIndex(0, 120_000)).toBe(true);
    await qtc.waitForLines(120_000);
    const b3 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(400);
    const a3 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(300);
    const flip3 = b3 !== 'unknown' && a3 !== 'unknown' && a3 !== b3;
    pushCrossRow(currentLabel, 'Theme flip · editor', { uiAfter: `${b3} → ${a3}`, dbAfter: 'expected flip', match: flip3 });
    expect(flip3, 'Theme must flip on editor page').toBe(true);

    // Breadcrumb: contract → back to contracts, then account → back to search
    const crumbs = qtc.breadcrumbItems();
    if ((await crumbs.count()) >= 2) {
      await crumbs.nth(1).click();
      await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
    }
    await qtc.breadcrumbItems().first().click();
    await qtc.accountSearchInput().waitFor({ state: 'visible', timeout: 30_000 });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 4 — Quote Editor Core (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runEditorCore(page, contract, branch) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  const spinCount = await qtc.waitForLines(120_000);
  pushCrossRow(currentLabel, 'Editable lines in editor', { uiAfter: spinCount, dbAfter: 'expected ≥1', match: spinCount > 0 });
  expect(spinCount, 'Editor must expose ≥1 editable line').toBeGreaterThan(0);
  const links = await qtc.readHeaderLinks();
  const hasAccount = links.some((/** @type {any} */ l) => /\/lightning\/r\/Account\//.test(l.href));
  const hasQuote   = links.some((/** @type {any} */ l) => /\/lightning\/r\/SBQQ__Quote__c\//.test(l.href));
  const saveDisabled = await qtc.isSaveDisabled();
  pushCrossRow(currentLabel, 'Account link in header', { uiAfter: String(hasAccount), dbAfter: 'expected true', match: hasAccount });
  pushCrossRow(currentLabel, 'Quote link in header',   { uiAfter: String(hasQuote),   dbAfter: 'expected true', match: hasQuote });
  pushCrossRow(currentLabel, 'Save disabled on load',  { uiAfter: String(saveDisabled), dbAfter: 'expected true', match: saveDisabled });
  expect(hasAccount, 'Account link in header').toBe(true);
  expect(hasQuote, 'Quote link in header').toBe(true);
  expect(saveDisabled, 'Save must be disabled on fresh load').toBe(true);
  const sb = page.getByRole('spinbutton').first();
  const cur = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
  await sb.click({ clickCount: 3 }); await sb.fill(String(cur + 5)); await sb.press('Tab');
  await qtc.waitForSaveEnabled(30_000);
  await qtc.save(120_000);
  await expect(qtc.saveButton()).toBeDisabled({ timeout: 30_000 });
  await qtc.backToContracts();
  await expect(qtc.activeContractsHeading()).toBeVisible();
}

test('[4.1] Editor Core: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[4.1] Editor Core: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[4.1] Editor Core: 0 amendments', () => runEditorCore(page, c, 'zero'));
});

test('[4.2] Editor Core: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[4.2] Editor Core: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[4.2] Editor Core: 1 amendment', () => runEditorCore(page, c, 'one'));
});

test('[4.3] Editor Core: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[4.3] Editor Core: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[4.3] Editor Core: 2+ amendments', () => runEditorCore(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 5 — Editor Buttons (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runEditorButtons(page, contract, branch) {
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  const saveBtn   = page.getByRole('button', { name: 'Save' });
  const submitBtn = page.getByRole('button', { name: 'Submit for Approval' });
  const prevBtn   = page.getByRole('button', { name: 'Preview and Send OSA' });
  const approvalPresent = await u.isVisibleSafe(submitBtn, 5_000);
  const delivery        = await qtc.readContactDisplay('delivery').catch(() => ({ name: '', email: '' }));
  const deliveryPresent = !!(delivery.name && delivery.email);
  const approvalStatus  = quoteName
    ? await page.evaluate(async (/** @type {any} */ args) => {
        const h = { Authorization: 'Bearer ' + args.token, 'Content-Type': 'application/json' };
        const r = await fetch(`${args.base}/services/data/v62.0/query?q=${encodeURIComponent(`SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Name = '${args.q}' LIMIT 1`)}`, { headers: h });
        return (await r.json()).records?.[0]?.ApprovalStatus__c ?? null;
      }, { token: sfCtx.accessToken, base: sfCtx.instanceUrl, q: quoteName }).catch(() => null)
    : null;
  // Preview & Send (isPreviewSendDisabled): the approval gate was REMOVED — the
  // OSA can be previewed before approval. Enabled iff a Software Delivery Contact
  // (id + email) is present. Approval status is irrelevant now.
  const expectedPreview = deliveryPresent;
  const prevEnabled = await prevBtn.isEnabled().catch(() => false);
  pushCrossRow(currentLabel, 'Preview & Send enabled', {
    uiAfter: String(prevEnabled), dbAfter: `expected ${expectedPreview} (delivery contact present=${deliveryPresent})`,
    match: prevEnabled === expectedPreview,
  });
  expect(prevEnabled, `Preview & Send enabled should be ${expectedPreview} (delivery contact present=${deliveryPresent})`).toBe(expectedPreview);

  // Submit for Approval (isSubmitForApprovalDisabled), checked on the FRESH quote
  // before any edit (no unsaved changes yet): rendered only when an approval is
  // required; enabled iff the quote isn't already Approved.
  if (approvalPresent) {
    const expectedSubmitFresh = approvalStatus !== 'Approved';
    const submitFresh = await submitBtn.isEnabled().catch(() => false);
    pushCrossRow(currentLabel, 'Submit enabled (no unsaved changes)', {
      uiAfter: String(submitFresh), dbAfter: `expected ${expectedSubmitFresh} (approvalStatus=${approvalStatus ?? 'none'})`,
      match: submitFresh === expectedSubmitFresh,
    });
    expect(submitFresh, `Submit for Approval (fresh) should be ${expectedSubmitFresh} (approvalStatus=${approvalStatus ?? 'none'})`).toBe(expectedSubmitFresh);
  }

  // Make an unsaved quantity edit.
  const sb = page.getByRole('spinbutton').first();
  const cur = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
  await sb.click({ clickCount: 3 }); await sb.fill(String(cur + 1)); await sb.press('Tab');
  await page.waitForTimeout(1_000);

  // Save (isSaveDisabled): enabled once the UI differs from the saved state.
  const saveEnabled = await saveBtn.isEnabled().catch(() => false);
  pushCrossRow(currentLabel, 'Save enabled after qty change', { uiAfter: String(saveEnabled), dbAfter: 'expected true', match: saveEnabled });
  expect(saveEnabled, 'Save must be clickable after qty change').toBe(true);

  // Submit must now be BLOCKED while there are unsaved changes (BIZ-83431) — a
  // quote can't be sent for approval until the edit is saved.
  if (approvalPresent) {
    const submitAfterEdit = await submitBtn.isEnabled().catch(() => false);
    pushCrossRow(currentLabel, 'Submit blocked with unsaved changes', {
      uiAfter: String(submitAfterEdit), dbAfter: 'expected false', match: submitAfterEdit === false,
    });
    expect(submitAfterEdit, 'Submit for Approval must be blocked while there are unsaved changes (BIZ-83431)').toBe(false);
  }
}

test('[5.1] Editor Buttons: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[5.1] Editor Buttons: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[5.1] Editor Buttons: 0 amendments', () => runEditorButtons(page, c, 'zero'));
});

test('[5.2] Editor Buttons: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[5.2] Editor Buttons: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[5.2] Editor Buttons: 1 amendment', () => runEditorButtons(page, c, 'one'));
});

test('[5.3] Editor Buttons: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[5.3] Editor Buttons: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[5.3] Editor Buttons: 2+ amendments', () => runEditorButtons(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 6 — Contact Update (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runContactUpdate(page, contract, branch) {
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  const dbBefore = await qtc.fetchContactsFromDb(quoteName);
  expect(dbBefore, 'Quote contacts should be queryable').not.toBeNull();
  const newInv = await qtc.pickDifferentContact('invoicing', dbBefore?.invoicing.id ?? null);
  if (!newInv) throw new Error('No alternative invoicing contact available');
  const newDel = await qtc.pickDifferentContact('delivery',  dbBefore?.delivery.id ?? null);
  if (!newDel) throw new Error('No alternative delivery contact available');
  await qtc.save(90_000, 300);
  const dbAfter = await qtc.fetchContactsFromDb(quoteName);
  pushCrossRow(currentLabel, 'Invoicing Contact', {
    uiBefore: dbBefore?.invoicing.id ?? null, uiAfter: newInv.id,
    dbAfter:  dbAfter?.invoicing.id ?? null, match: (dbAfter?.invoicing.id ?? null) === newInv.id,
  });
  pushCrossRow(currentLabel, 'Delivery Contact', {
    uiBefore: dbBefore?.delivery.id ?? null, uiAfter: newDel.id,
    dbAfter:  dbAfter?.delivery.id ?? null, match: (dbAfter?.delivery.id ?? null) === newDel.id,
  });
  expect(dbAfter?.invoicing.id, 'Invoicing contact should be updated in DB').toBe(newInv.id);
  expect(dbAfter?.delivery.id,  'Delivery contact should be updated in DB').toBe(newDel.id);
}

test('[6.1] Contact Update: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[6.1] Contact Update: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[6.1] Contact Update: 0 amendments', () => runContactUpdate(page, c, 'zero'));
});

test('[6.2] Contact Update: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[6.2] Contact Update: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[6.2] Contact Update: 1 amendment', () => runContactUpdate(page, c, 'one'));
});

test('[6.3] Contact Update: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[6.3] Contact Update: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[6.3] Contact Update: 2+ amendments', () => runContactUpdate(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 7 — Start Date Change (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runStartDateChange(page, contract, branch) {
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  const initialISO = u.parseLongDateToISO(await qtc.getStartDate());
  expect(initialISO, 'Quote must have a valid initial start date').not.toBeNull();
  await qtc.setStartDate(u.formatDateISO(u.addDays(new Date(`${initialISO}T00:00:00`), 5)));
  await qtc.save();
  const uiAfterISO = u.parseLongDateToISO(await qtc.getStartDate());
  expect(uiAfterISO, 'Start date should change after save').not.toBe(initialISO);
  const dbHeader = await qtc.fetchQuoteFromDb(quoteName);
  pushCrossRow(currentLabel, 'Quote Start Date', {
    uiBefore: initialISO, uiAfter: uiAfterISO,
    dbAfter:  dbHeader?.SBQQ__StartDate__c ?? null,
  });
  expect(dbHeader?.SBQQ__StartDate__c, 'DB start date should match UI').toBe(uiAfterISO);
}

test('[7.1] Start Date Change: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[7.1] Start Date Change: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[7.1] Start Date Change: 0 amendments', () => runStartDateChange(page, c, 'zero'));
});

test('[7.2] Start Date Change: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[7.2] Start Date Change: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[7.2] Start Date Change: 1 amendment', () => runStartDateChange(page, c, 'one'));
});

test('[7.3] Start Date Change: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[7.3] Start Date Change: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[7.3] Start Date Change: 2+ amendments', () => runStartDateChange(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 8 — Start Date Boundary (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

const UPPER_TOAST_RE = /Invalid date:\s*quote start date cannot be after the end date of the first term/i;
const LOWER_TOAST_RE = /Invalid date:\s*quote start date cannot be earlier than the start date of the first term/i;

/**
 * @param {import('@playwright/test').Page} page
 * @param {any} qtc
 * @param {string} attemptISO
 * @param {RegExp} re
 */
async function attemptDateAndCaptureToast(page, qtc, attemptISO, re) {
  const loc = page.locator('div.toast-container').filter({ hasText: re }).first();
  const p = loc.waitFor({ state: 'visible', timeout: 15_000 }).then(() => true).catch(() => false);
  await qtc.setStartDate(attemptISO);
  return await p;
}

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runStartDateBoundary(page, contract, branch) {
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  const initialISO = u.parseLongDateToISO(await qtc.getStartDate());
  expect(initialISO).not.toBeNull();
  const lineSoql = `SELECT SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.Name = '${quoteName}' ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS FIRST`;
  const dbLines  = await u.sfQuery(page, sfCtx.instanceUrl, sfCtx.accessToken, lineSoql)
    .then((r) => r.records || []).catch(() => []);
  const first    = dbLines.filter((/** @type {any} */ d) => d.SBQQ__SegmentKey__c == null || d.SBQQ__SegmentIndex__c === 1);
  const ends     = first.map((/** @type {any} */ d) => d.SBQQ__EndDate__c  ).filter(Boolean).sort();
  const capISO   = ends.length   > 0 ? ends[0]                   : null;
  // Lower bound mirrors the editor's _getLowerBoundStartDate(): the start of the
  // upgraded-subscription SEGMENT that contains the quote's current start date.
  // Do NOT derive it from quote-line start dates — those shift forward whenever an
  // earlier scenario ([7.3] Start Date Change) moves the quote start on this shared
  // quote, which would make floor−1 a still-valid date and suppress the toast.
  const curStartISO = u.parseLongDateToISO(await qtc.getStartDate());
  const subSegs = await u.sfQuery(page, sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT SBQQ__SegmentStartDate__c, SBQQ__SegmentEndDate__c FROM SBQQ__Subscription__c WHERE SBQQ__Contract__c = '${contract.id}' AND SBQQ__SegmentStartDate__c != null ORDER BY SBQQ__SegmentStartDate__c`)
    .then((/** @type {any} */ r) => r.records || []).catch(() => []);
  const containingSeg = subSegs.find((/** @type {any} */ s) =>
    (!curStartISO || s.SBQQ__SegmentStartDate__c <= curStartISO) &&
    (!s.SBQQ__SegmentEndDate__c || !curStartISO || curStartISO <= s.SBQQ__SegmentEndDate__c));
  let floorISO = (containingSeg || subSegs[0])?.SBQQ__SegmentStartDate__c || null;
  if (!floorISO) {
    // Non-segmented contract — fall back to the contract term start.
    const contractRows = await u.sfQuery(page, sfCtx.instanceUrl, sfCtx.accessToken,
      `SELECT StartDate FROM Contract WHERE Id = '${contract.id}'`).then((/** @type {any} */ r) => r.records || []).catch(() => []);
    floorISO = contractRows[0]?.StartDate || null;
  }
  if (!capISO || !floorISO) throw new Error('Could not determine first-term bounds');
  const lower = await attemptDateAndCaptureToast(page, qtc, u.formatDateISO(u.addDays(new Date(`${floorISO}T00:00:00`), -1)), LOWER_TOAST_RE);
  const upper = await attemptDateAndCaptureToast(page, qtc, u.formatDateISO(u.addDays(new Date(`${capISO}T00:00:00`), 1)),   UPPER_TOAST_RE);
  pushCrossRow(currentLabel, `Lower-bound toast (before ${floorISO})`, { uiAfter: lower ? 'toast shown' : 'no toast', dbAfter: 'expected toast', match: lower });
  pushCrossRow(currentLabel, `Upper-bound toast (after ${capISO})`,    { uiAfter: upper ? 'toast shown' : 'no toast', dbAfter: 'expected toast', match: upper });
  expect(lower, 'Lower-bound toast should appear').toBe(true);
  expect(upper, 'Upper-bound toast should appear').toBe(true);
}

test('[8.1] Start Date Boundary: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[8.1] Start Date Boundary: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[8.1] Start Date Boundary: 0 amendments', () => runStartDateBoundary(page, c, 'zero'));
});

test('[8.2] Start Date Boundary: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[8.2] Start Date Boundary: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[8.2] Start Date Boundary: 1 amendment', () => runStartDateBoundary(page, c, 'one'));
});

test('[8.3] Start Date Boundary: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[8.3] Start Date Boundary: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[8.3] Start Date Boundary: 2+ amendments', () => runStartDateBoundary(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 9 — Quantity Increase (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

const QTY_INC = 5;

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runQuantityIncrease(page, contract, branch) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  const spinCount = await qtc.waitForLines(120_000);
  expect(spinCount).toBeGreaterThan(0);
  const sbs = page.getByRole('spinbutton');
  const initials = [];
  for (let i = 0; i < spinCount; i++) {
    const cur = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    initials.push(cur);
    await sbs.nth(i).click({ clickCount: 3 }); await sbs.nth(i).fill(String(cur + QTY_INC)); await sbs.nth(i).press('Tab');
    await page.waitForTimeout(800);
  }
  await qtc.save(120_000);
  let allPass = true;
  /** @type {Array<{lineId:string|null, before:number, after:number, product?:string}>} */
  const entries = [];
  for (let i = 0; i < spinCount; i++) {
    const actual = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    if (Math.abs(actual - (initials[i] + QTY_INC)) >= 0.001) allPass = false;
    const lineId  = await sbs.nth(i).getAttribute('data-line-id').catch(() => null);
    const product = (await sbs.nth(i).locator('xpath=ancestor::tr').first().locator('.product-label').first().innerText().catch(() => '')).trim();
    entries.push({ lineId, before: initials[i], after: actual, product });
  }
  await captureQtyCross(currentLabel, entries);
  expect(allPass, `All ${spinCount} quantities should have increased by ${QTY_INC}`).toBe(true);
}

test('[9.1] Qty Increase: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[9.1] Qty Increase: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[9.1] Qty Increase: 0 amendments', () => runQuantityIncrease(page, c, 'zero'));
});

test('[9.2] Qty Increase: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[9.2] Qty Increase: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[9.2] Qty Increase: 1 amendment', () => runQuantityIncrease(page, c, 'one'));
});

test('[9.3] Qty Increase: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[9.3] Qty Increase: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[9.3] Qty Increase: 2+ amendments', () => runQuantityIncrease(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 10 — Quantity Decrease (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

const QTY_DEC = 5;

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runQuantityDecrease(page, contract, branch) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  const spinCount = await qtc.waitForLines(120_000);
  expect(spinCount).toBeGreaterThan(0);
  const sbs = page.getByRole('spinbutton');
  const initials = [];
  for (let i = 0; i < spinCount; i++) {
    const cur = parseFloat(await sbs.nth(i).inputValue().catch(() => '1')) || 1;
    initials.push(cur);
    const newVal = Math.max(1, cur - QTY_DEC);
    await sbs.nth(i).click({ clickCount: 3 }); await sbs.nth(i).fill(String(newVal)); await sbs.nth(i).press('Tab');
    await page.waitForTimeout(800);
  }
  await qtc.save(120_000);
  let allPass = true;
  /** @type {Array<{lineId:string|null, before:number, after:number, product?:string}>} */
  const entries = [];
  for (let i = 0; i < spinCount; i++) {
    const actual   = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    const expected = Math.max(1, initials[i] - QTY_DEC);
    if (Math.abs(actual - expected) >= 0.001) allPass = false;
    const lineId  = await sbs.nth(i).getAttribute('data-line-id').catch(() => null);
    const product = (await sbs.nth(i).locator('xpath=ancestor::tr').first().locator('.product-label').first().innerText().catch(() => '')).trim();
    entries.push({ lineId, before: initials[i], after: actual, product });
  }
  await captureQtyCross(currentLabel, entries);
  expect(allPass, `All ${spinCount} quantities should have decreased by ${QTY_DEC} (floor 1)`).toBe(true);
}

test('[10.1] Qty Decrease: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[10.1] Qty Decrease: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[10.1] Qty Decrease: 0 amendments', () => runQuantityDecrease(page, c, 'zero'));
});

test('[10.2] Qty Decrease: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[10.2] Qty Decrease: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[10.2] Qty Decrease: 1 amendment', () => runQuantityDecrease(page, c, 'one'));
});

test('[10.3] Qty Decrease: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[10.3] Qty Decrease: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[10.3] Qty Decrease: 2+ amendments', () => runQuantityDecrease(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 11 — Qty Increase Segments / MDQ (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

const MDQ_DELTA   = 20;
const MDQ_SEG_IDX = 2; // 0-based = Year 3 (1-based index 3)
const MDQ_QUIESCE = 1_500;

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runQtyIncreaseSegments(page, contract, branch) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  const mdq = await pickMdqRows(page, 2, 4);
  if (mdq.length < 2) skipScenario(`No MDQ product (needs ≥2 segments) in this quote — found ${mdq.length}`);

  // Product A — Year-1 edit propagates to all segments
  const qtysA_before = await readSegQtys(mdq[0].row);
  const newA = qtysA_before[0] + MDQ_DELTA;
  await setSegQty(mdq[0].row, 0, newA);
  await page.waitForTimeout(MDQ_QUIESCE);
  const qtysA_after = await readSegQtys(mdq[0].row);
  expect(qtysA_after.every(q => Math.abs(q - newA) < 0.001), `Year-1 edit (${newA}) should propagate to all segments`).toBe(true);

  // Product B — Year-N edit is isolated (does not touch Year-1)
  const rowB   = mdq[1].segmentCount > MDQ_SEG_IDX ? mdq[1] : mdq[0];
  const segIdx = Math.min(MDQ_SEG_IDX, rowB.segmentCount - 1);
  if (segIdx === 0) skipScenario('MDQ product has only 1 segment — cannot test Year-N isolation');
  const qtysB_before = await readSegQtys(rowB.row);
  const newB = qtysB_before[segIdx] + MDQ_DELTA;
  await setSegQty(rowB.row, segIdx, newB);
  await page.waitForTimeout(MDQ_QUIESCE);
  const qtysB_after = await readSegQtys(rowB.row);
  expect(Math.abs(qtysB_after[0] - qtysB_before[0]) < 0.001, 'Year-1 must NOT change when Year-N is edited').toBe(true);
  expect(Math.abs(qtysB_after[segIdx] - newB) < 0.001, `Year-${segIdx + 1} should equal ${newB}`).toBe(true);

  await qtc.save(120_000);
  await captureSegmentCross(currentLabel, mdq[0], qtysA_before);
}

test('[11.1] Qty Increase Segments (MDQ): 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[11.1] Qty Increase Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[11.1] Qty Increase Segments: 0 amendments', () => runQtyIncreaseSegments(page, c, 'zero'));
});

test('[11.2] Qty Increase Segments (MDQ): 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[11.2] Qty Increase Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[11.2] Qty Increase Segments: 1 amendment', () => runQtyIncreaseSegments(page, c, 'one'));
});

test('[11.3] Qty Increase Segments (MDQ): 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[11.3] Qty Increase Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[11.3] Qty Increase Segments: 2+ amendments', () => runQtyIncreaseSegments(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 12 — Qty Decrease Segments / MDQ (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runQtyDecreaseSegments(page, contract, branch) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  const mdq = await pickMdqRows(page, 2, 4);
  if (mdq.length < 2) skipScenario(`No MDQ product (needs ≥2 segments) in this quote — found ${mdq.length}`);

  // Product A — Year-1 decrease propagates (floor 1)
  const qtysA_before = await readSegQtys(mdq[0].row);
  const newA = Math.max(1, qtysA_before[0] - MDQ_DELTA);
  await setSegQty(mdq[0].row, 0, newA);
  await page.waitForTimeout(MDQ_QUIESCE);
  const qtysA_after = await readSegQtys(mdq[0].row);
  expect(qtysA_after.every(q => Math.abs(q - newA) < 0.001), `Year-1 decrease (${newA}) should propagate to all segments`).toBe(true);

  // Product B — Year-N isolated decrease
  const rowB   = mdq[1].segmentCount > MDQ_SEG_IDX ? mdq[1] : mdq[0];
  const segIdx = Math.min(MDQ_SEG_IDX, rowB.segmentCount - 1);
  if (segIdx === 0) skipScenario('MDQ product has only 1 segment — cannot test Year-N isolation');
  const qtysB_before = await readSegQtys(rowB.row);
  const newB = Math.max(1, qtysB_before[segIdx] - MDQ_DELTA);
  await setSegQty(rowB.row, segIdx, newB);
  await page.waitForTimeout(MDQ_QUIESCE);
  const qtysB_after = await readSegQtys(rowB.row);
  expect(Math.abs(qtysB_after[0] - qtysB_before[0]) < 0.001, 'Year-1 must NOT change when Year-N is decreased').toBe(true);
  expect(Math.abs(qtysB_after[segIdx] - newB) < 0.001, `Year-${segIdx + 1} should equal ${newB} after decrease`).toBe(true);

  await qtc.save(120_000);
  await captureSegmentCross(currentLabel, mdq[0], qtysA_before);
}

test('[12.1] Qty Decrease Segments (MDQ): 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[12.1] Qty Decrease Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[12.1] Qty Decrease Segments: 0 amendments', () => runQtyDecreaseSegments(page, c, 'zero'));
});

test('[12.2] Qty Decrease Segments (MDQ): 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[12.2] Qty Decrease Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[12.2] Qty Decrease Segments: 1 amendment', () => runQtyDecreaseSegments(page, c, 'one'));
});

test('[12.3] Qty Decrease Segments (MDQ): 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[12.3] Qty Decrease Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[12.3] Qty Decrease Segments: 2+ amendments', () => runQtyDecreaseSegments(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 13 — Metrics Verification (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

const CURRENCY_TOL = 1.0;
const PCT_TOL      = 0.01;

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch */
async function runMetricsVerification(page, contract, branch) {
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  const spinCount = await qtc.waitForLines(120_000);
  expect(spinCount).toBeGreaterThan(0);
  const sbs = page.getByRole('spinbutton');
  for (let i = 0; i < spinCount; i++) {
    const cur = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    await sbs.nth(i).click({ clickCount: 3 }); await sbs.nth(i).fill(String(cur + 1)); await sbs.nth(i).press('Tab');
    await page.waitForTimeout(600);
  }
  await qtc.save(120_000);
  const uiAfter = await qtc.readHeaderMetrics();
  const db      = await computeMetricsFromDb(page, quoteName, contract.id);
  const uiAcv   = parseMetric(uiAfter['ACV']);
  const uiTcv   = parseMetric(uiAfter['TCV']);
  const uiYoy   = parseMetric(uiAfter['YoY Uplift']);
  const uiDqs   = parseMetric(uiAfter['Deal Quality Score']);
  const round2  = (/** @type {number|null} */ v) => (v == null ? null : Math.round(v * 100) / 100);
  pushCrossRow(currentLabel, 'ACV', { uiAfter: round2(uiAcv), dbAfter: round2(db.expectedAcv), match: within(uiAcv, db.expectedAcv, CURRENCY_TOL) });
  pushCrossRow(currentLabel, 'TCV', { uiAfter: round2(uiTcv), dbAfter: round2(db.expectedTcv), match: within(uiTcv, db.expectedTcv, CURRENCY_TOL) });
  if (db.expectedYoy != null) pushCrossRow(currentLabel, 'YoY Uplift',         { uiAfter: round2(uiYoy), dbAfter: round2(db.expectedYoy), match: within(uiYoy, db.expectedYoy, PCT_TOL) });
  if (db.expectedDqs != null) pushCrossRow(currentLabel, 'Deal Quality Score', { uiAfter: round2(uiDqs), dbAfter: round2(db.expectedDqs), match: within(uiDqs, db.expectedDqs, PCT_TOL) });
  expect(within(uiAcv, db.expectedAcv, CURRENCY_TOL), `ACV mismatch: UI=${uiAcv} DB=${db.expectedAcv}`).toBe(true);
  expect(within(uiTcv, db.expectedTcv, CURRENCY_TOL), `TCV mismatch: UI=${uiTcv} DB=${db.expectedTcv}`).toBe(true);
  if (db.expectedYoy != null) expect(within(uiYoy, db.expectedYoy, PCT_TOL), `YoY mismatch: UI=${uiYoy} DB=${db.expectedYoy}`).toBe(true);
  if (db.expectedDqs != null) expect(within(uiDqs, db.expectedDqs, PCT_TOL), `DQS mismatch: UI=${uiDqs} DB=${db.expectedDqs}`).toBe(true);
}

test('[13.1] Metrics Verification: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[13.1] Metrics Verification: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[13.1] Metrics Verification: 0 amendments', () => runMetricsVerification(page, c, 'zero'));
});

test('[13.2] Metrics Verification: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[13.2] Metrics Verification: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[13.2] Metrics Verification: 1 amendment', () => runMetricsVerification(page, c, 'one'));
});

test('[13.3] Metrics Verification: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[13.3] Metrics Verification: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[13.3] Metrics Verification: 2+ amendments', () => runMetricsVerification(page, c, 'many'));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 14 — Qty Increase: Non-Segment products (3 scenarios)
//   SKIP when the quote has no single-period (non-segment) products.
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch @param {number} delta */
async function runNonSegmentQty(page, contract, branch, delta) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  let lines = await findNonSegmentInputs(page);
  if (delta < 0) lines = lines.filter(l => l.initial > 1);  // need headroom to decrease
  if (lines.length === 0) {
    skipScenario(delta < 0
      ? 'No decreasable non-segment products (all at minimum qty) in this quote'
      : 'No non-segment products in this quote');
  }
  const allPass = await editSaveVerifyInputs(page, qtc, lines, delta);
  expect(allPass, `All ${lines.length} non-segment quantities should ${delta >= 0 ? 'increase' : 'decrease'} by ${Math.abs(delta)}`).toBe(true);
}

test('[14.1] Qty Increase Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[14.1] Qty Increase Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[14.1] Qty Increase Non-Segment: 0 amendments', () => runNonSegmentQty(page, c, 'zero', QTY_INC));
});

test('[14.2] Qty Increase Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[14.2] Qty Increase Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[14.2] Qty Increase Non-Segment: 1 amendment', () => runNonSegmentQty(page, c, 'one', QTY_INC));
});

test('[14.3] Qty Increase Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[14.3] Qty Increase Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[14.3] Qty Increase Non-Segment: 2+ amendments', () => runNonSegmentQty(page, c, 'many', QTY_INC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 15 — Qty Increase: Bundle Segments / MDQ (3 scenarios)
//   SKIP when the quote has no Static Bundle MDQ product.
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch @param {number} delta */
async function runBundleSegmentQty(page, contract, branch, delta) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  const bundles = await findBundleSegmentRows(page);
  if (bundles.length === 0) skipScenario('No Static Bundle MDQ product in this quote');
  const bundle = bundles[0];

  // Year-1 edit propagates to all segments
  const beforeA = await readSegQtys(bundle.row);
  const newA = delta >= 0 ? beforeA[0] + delta : Math.max(1, beforeA[0] + delta);
  await setSegQty(bundle.row, 0, newA);
  await page.waitForTimeout(MDQ_QUIESCE);
  const afterA = await readSegQtys(bundle.row);
  expect(afterA.every(q => Math.abs(q - newA) < 0.001), `Bundle Year-1 ${delta >= 0 ? 'increase' : 'decrease'} (${newA}) should propagate to all segments`).toBe(true);

  // Year-N edit is isolated
  const segIdx = Math.min(MDQ_SEG_IDX, bundle.segmentCount - 1);
  if (segIdx === 0) skipScenario('Bundle has only 1 segment — cannot test Year-N isolation');
  const beforeB = await readSegQtys(bundle.row);
  const newB = delta >= 0 ? beforeB[segIdx] + delta : Math.max(1, beforeB[segIdx] + delta);
  await setSegQty(bundle.row, segIdx, newB);
  await page.waitForTimeout(MDQ_QUIESCE);
  const afterB = await readSegQtys(bundle.row);
  expect(Math.abs(afterB[0] - beforeB[0]) < 0.001, 'Bundle Year-1 must NOT change when Year-N is edited').toBe(true);
  expect(Math.abs(afterB[segIdx] - newB) < 0.001, `Bundle Year-${segIdx + 1} should equal ${newB}`).toBe(true);

  await qtc.save(120_000);
  await captureSegmentCross(currentLabel, bundle, beforeA);
}

test('[15.1] Qty Increase Bundle Segments: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[15.1] Qty Increase Bundle Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[15.1] Qty Increase Bundle Segments: 0 amendments', () => runBundleSegmentQty(page, c, 'zero', MDQ_DELTA));
});

test('[15.2] Qty Increase Bundle Segments: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[15.2] Qty Increase Bundle Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[15.2] Qty Increase Bundle Segments: 1 amendment', () => runBundleSegmentQty(page, c, 'one', MDQ_DELTA));
});

test('[15.3] Qty Increase Bundle Segments: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[15.3] Qty Increase Bundle Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[15.3] Qty Increase Bundle Segments: 2+ amendments', () => runBundleSegmentQty(page, c, 'many', MDQ_DELTA));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 16 — Qty Increase: Bundle Non-Segment (3 scenarios)
//   SKIP when the quote has no single-period Static Bundle product.
// ─────────────────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {any} contract @param {'zero'|'one'|'many'} branch @param {number} delta */
async function runBundleNonSegmentQty(page, contract, branch, delta) {
  const { qtc } = await openEditorByScenario(page, sfCtx, contract, branch);
  await qtc.waitForLines(120_000);
  let bundles = await filterStaticBundle(await findNonSegmentInputs(page));
  if (delta < 0) bundles = bundles.filter(l => l.initial > 1);
  if (bundles.length === 0) {
    skipScenario(delta < 0
      ? 'No decreasable non-segment Static Bundle products in this quote'
      : 'No non-segment Static Bundle products in this quote');
  }
  const allPass = await editSaveVerifyInputs(page, qtc, bundles, delta);
  expect(allPass, `All ${bundles.length} non-segment bundle quantities should ${delta >= 0 ? 'increase' : 'decrease'} by ${Math.abs(delta)}`).toBe(true);
}

test('[16.1] Qty Increase Bundle Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[16.1] Qty Increase Bundle Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[16.1] Qty Increase Bundle Non-Segment: 0 amendments', () => runBundleNonSegmentQty(page, c, 'zero', QTY_INC));
});

test('[16.2] Qty Increase Bundle Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[16.2] Qty Increase Bundle Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[16.2] Qty Increase Bundle Non-Segment: 1 amendment', () => runBundleNonSegmentQty(page, c, 'one', QTY_INC));
});

test('[16.3] Qty Increase Bundle Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[16.3] Qty Increase Bundle Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[16.3] Qty Increase Bundle Non-Segment: 2+ amendments', () => runBundleNonSegmentQty(page, c, 'many', QTY_INC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 17 — Qty Decrease: Non-Segment products (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[17.1] Qty Decrease Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[17.1] Qty Decrease Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[17.1] Qty Decrease Non-Segment: 0 amendments', () => runNonSegmentQty(page, c, 'zero', -QTY_DEC));
});

test('[17.2] Qty Decrease Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[17.2] Qty Decrease Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[17.2] Qty Decrease Non-Segment: 1 amendment', () => runNonSegmentQty(page, c, 'one', -QTY_DEC));
});

test('[17.3] Qty Decrease Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[17.3] Qty Decrease Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[17.3] Qty Decrease Non-Segment: 2+ amendments', () => runNonSegmentQty(page, c, 'many', -QTY_DEC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 18 — Qty Decrease: Bundle Non-Segment (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[18.1] Qty Decrease Bundle Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[18.1] Qty Decrease Bundle Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[18.1] Qty Decrease Bundle Non-Segment: 0 amendments', () => runBundleNonSegmentQty(page, c, 'zero', -QTY_DEC));
});

test('[18.2] Qty Decrease Bundle Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[18.2] Qty Decrease Bundle Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[18.2] Qty Decrease Bundle Non-Segment: 1 amendment', () => runBundleNonSegmentQty(page, c, 'one', -QTY_DEC));
});

test('[18.3] Qty Decrease Bundle Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[18.3] Qty Decrease Bundle Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[18.3] Qty Decrease Bundle Non-Segment: 2+ amendments', () => runBundleNonSegmentQty(page, c, 'many', -QTY_DEC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 19 — Qty Decrease: Bundle Segments / MDQ (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[19.1] Qty Decrease Bundle Segments: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[19.1] Qty Decrease Bundle Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[19.1] Qty Decrease Bundle Segments: 0 amendments', () => runBundleSegmentQty(page, c, 'zero', -MDQ_DELTA));
});

test('[19.2] Qty Decrease Bundle Segments: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[19.2] Qty Decrease Bundle Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[19.2] Qty Decrease Bundle Segments: 1 amendment', () => runBundleSegmentQty(page, c, 'one', -MDQ_DELTA));
});

test('[19.3] Qty Decrease Bundle Segments: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[19.3] Qty Decrease Bundle Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); test.skip(true, 'Contract precondition not met — see suite report'); }
  await runSafe('[19.3] Qty Decrease Bundle Segments: 2+ amendments', () => runBundleSegmentQty(page, c, 'many', -MDQ_DELTA));
});

// ─────────────────────────────────────────────────────────────────────────────
// SUITE SUMMARY — requires a 100% pass rate (any failure fails the suite)
// ─────────────────────────────────────────────────────────────────────────────

test('SUITE SUMMARY — pass rate must be 100%', async () => {
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);

  const passed    = SUITE_RESULTS.filter(r => r.status === 'PASS').length;
  const failed    = SUITE_RESULTS.filter(r => r.status === 'FAIL').length;
  const skipped   = SUITE_RESULTS.filter(r => r.status === 'SKIP').length;
  const evaluated = passed + failed;
  const pct       = evaluated > 0 ? Math.round((passed / evaluated) * 100) : 100;
  const overall   = pct >= PASS_THRESHOLD;

  const LINE = '═'.repeat(66);
  const DASH = '─'.repeat(66);
  console.log('\n' + LINE);
  console.log('                  FULL SUITE REPORT');
  console.log(LINE);
  console.log(`Account : ${ACCOUNT_FULL_NAME}`);
  console.log(`Scenarios: ${SUITE_RESULTS.length}  |  ✅ ${passed} passed  |  ❌ ${failed} failed  |  ⏭ ${skipped} skipped`);
  console.log(`Pass rate (excl. skipped): ${passed}/${evaluated} = ${pct}%   [threshold: ${PASS_THRESHOLD}%]`);
  console.log(DASH);
  for (const r of SUITE_RESULTS) {
    const icon = { PASS: '✅', FAIL: '❌', SKIP: '⏭' }[r.status];
    console.log(`${icon}  ${r.name}`);
    if (r.detail && r.status !== 'PASS') console.log(`     ↳ ${r.detail}`);
  }
  console.log(LINE);
  const verdict = overall
    ? `✅ SUITE PASSED: ${pct}% (all ${passed} evaluated scenarios passed)`
    : `❌ SUITE FAILED: ${pct}% — ${failed} scenario(s) failed (need ${PASS_THRESHOLD}%)`;
  console.log(verdict);
  console.log(LINE + '\n');

  // UI↔DB comparison: real per-line rows captured across every data-bearing
  // scenario (qty, segments, bundle, non-segment, contact, start date, metrics),
  // followed by a status row for each scenario that has no UI/DB value to compare
  // (account search, OSA, app nav, editor core/buttons, start-date boundary).
  const dataLabels = new Set(CROSS_CHECK.map(r => String(r.product).split(' · ')[0]));
  const statusRows = SUITE_RESULTS
    .filter(r => !dataLabels.has(r.name))
    .map(r => ({
      product: r.name, segOcc: null,
      uiBefore: null, uiAfter: r.status,
      dbPrior: null,  dbAfter: r.detail || (r.status === 'PASS' ? 'OK' : ''),
      match: r.status !== 'FAIL', hasData: r.status !== 'SKIP',
    }));
  const uiDbCrossCheck = [...CROSS_CHECK, ...statusRows].map((r, i) => ({ ...r, uiIndex: i + 1 }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  // Write a summary richResult so the dashboard's Metrics tab shows the numbers
  buildRichResults({
    kind: 'fullSuite', runTs, runDir,
    testStartMs: Date.now(),
    accountName:   ACCOUNT_FULL_NAME,
    scenarioNumber: 1,
    scenarioLabel: `Full suite — ${passed} passed / ${evaluated} evaluated (${pct}%)`,
    passed: overall,
    metricResults: [
      { metric: 'Pass Rate',   before: `0/${evaluated}`, after: `${passed}/${evaluated}`, pass: overall,       note: `${pct}% (threshold ${PASS_THRESHOLD}%)` },
      { metric: 'Passed',      before: '—',              after: String(passed),           pass: true,          note: '' },
      { metric: 'Failed',      before: '—',              after: String(failed),           pass: failed === 0,  note: '' },
      { metric: 'Skipped',     before: '—',              after: String(skipped),          pass: true,          note: 'Pre-condition not met — excluded from rate' },
    ],
    uiDbCrossCheck,
    crossCheckMismatches,
    dbAnomalies: SUITE_RESULTS
      .filter(r => r.status === 'FAIL')
      .map(r => ({ type: r.name, severity: 'HIGH', detail: r.detail })),
  });

  if (!overall) {
    throw new Error(`Suite failed: ${passed}/${evaluated} passed (${pct}%) — ${failed} scenario(s) failed; ${PASS_THRESHOLD}% required`);
  }
});
