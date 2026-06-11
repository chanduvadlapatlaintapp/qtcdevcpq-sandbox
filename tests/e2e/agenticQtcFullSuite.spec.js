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
 *   • The final SUITE SUMMARY test fails the overall run when pass rate < 75%.
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
const PASS_THRESHOLD    = 75; // percent

// ── Shared state (populated in beforeAll, read by every test) ─────────────────
/** @type {any} */ let sfCtx;
/** @type {any} */ let contractCache = null;

/** @type {Array<{name:string, status:'PASS'|'FAIL'|'SKIP', detail:string}>} */
const SUITE_RESULTS = [];

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
 * Wrap a scenario body: catch all errors (including expect() throws), record
 * PASS / FAIL / SKIP, and NEVER rethrow — so the Playwright test always resolves
 * cleanly. A thrown SkipSignal → SKIP (not applicable). Any other throw → FAIL.
 * Only the SUITE SUMMARY test fails the run via the 75% threshold.
 *
 * @param {string} name
 * @param {() => Promise<void>} fn
 */
async function runSafe(name, fn) {
  try {
    await fn();
    record(name, 'PASS');
  } catch (e) {
    if (e instanceof SkipSignal) {
      record(name, 'SKIP', e.message);
      return;
    }
    const msg = e instanceof Error ? e.message.split('\n')[0].substring(0, 150) : String(e);
    record(name, 'FAIL', msg);
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
 * @param {Array<{input:import('@playwright/test').Locator, initial:number}>} lines
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
  for (let i = 0; i < lines.length; i++) {
    const actual   = parseFloat(await lines[i].input.inputValue().catch(() => '0')) || 0;
    const expected = delta >= 0 ? initials[i] + delta : Math.max(1, initials[i] + delta);
    if (Math.abs(actual - expected) >= 0.001) allPass = false;
  }
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
    expect(await qtc.accountCards().count()).toBe(0);
    expect(await u.isVisibleSafe(qtc.noResultsDropdown(), 1_000)).toBe(false);
  });
});

test('[1.2] Account Search: nonsense term shows empty-state', async ({ page }) => {
  await runSafe('[1.2] Account Search: nonsense term shows empty-state', async () => {
    const qtc = await openApp(page);
    await qtc.typeAccountSearch(NONSENSE_TERM);
    await expect(qtc.noResultsDropdown()).toBeVisible();
    await expect(qtc.noResultsDropdown()).toContainText(NONSENSE_TERM);
    expect(await qtc.accountCards().count()).toBe(0);
  });
});

test('[1.3] Account Search: known term returns cards and navigates to contracts', async ({ page }) => {
  await runSafe('[1.3] Account Search: known term returns cards', async () => {
    const qtc = await openApp(page);
    await qtc.typeAccountSearch(ACCOUNT_SEARCH);
    await qtc.accountCards().first().waitFor({ state: 'visible', timeout: 20_000 });
    const cards = await qtc.readAccountCards();
    expect(cards.length).toBeGreaterThan(0);
    expect(cards.some(c => (c.name || '').toLowerCase().includes(ACCOUNT_SEARCH.toLowerCase()))).toBe(true);
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
    expect(badge).toBe(expected);
  });
});

test('[2.2] OSA Selector: products +N more toggle expands without navigating away', async ({ page }) => {
  const qtc = await openContracts(page);
  if ((await qtc.productMoreButtons().count()) === 0) {
    record('[2.2] OSA Selector: +N more toggle', 'SKIP', 'No contract has >3 products');
    return;
  }
  await runSafe('[2.2] OSA Selector: +N more toggle', async () => {
    await qtc.productMoreButtons().first().click();
    await expect(qtc.productShowLessButton()).toBeVisible();
    await expect(qtc.activeContractsHeading()).toBeVisible();
    expect(await u.isVisibleSafe(qtc.saveButton(), 1_500)).toBe(false);
    await qtc.productShowLessButton().first().click();
    await expect(qtc.productMoreButtons().first()).toBeVisible();
  });
});

test('[2.3] OSA Selector: clear pill returns to account search', async ({ page }) => {
  await runSafe('[2.3] OSA Selector: clear pill', async () => {
    const qtc = await openContracts(page);
    await expect(qtc.accountPillClear()).toBeVisible();
    await qtc.accountPillClear().click();
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
    return;
  }
  await runSafe('[2.4] OSA Selector: draft-quotes modal', async () => {
    await qtc.clickContractById(manyDraft.id);
    expect(await qtc.waitForContractClickOutcome(120_000)).toBe('modal');
    await expect(qtc.draftQuotesModal()).toBeVisible();
    expect(await qtc.draftQuoteCountInModal()).toBeGreaterThanOrEqual(2);
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
    expect(b1 !== 'unknown' && a1 !== 'unknown' && a1 !== b1, 'Theme must flip on account-search page').toBe(true);

    // Navigate to contracts, theme there
    await qtc.searchAndSelectAccount(sfCtx.accountSearch, sfCtx.accountFullName);
    await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
    const b2 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(400);
    const a2 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(300);
    expect(b2 !== 'unknown' && a2 !== 'unknown' && a2 !== b2, 'Theme must flip on contracts page').toBe(true);

    // Open editor, theme there
    expect(await qtc.openContractByIndex(0, 120_000)).toBe(true);
    await qtc.waitForLines(120_000);
    const b3 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(400);
    const a3 = await qtc.currentTheme(); await toggle.click(); await page.waitForTimeout(300);
    expect(b3 !== 'unknown' && a3 !== 'unknown' && a3 !== b3, 'Theme must flip on editor page').toBe(true);

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
  expect(spinCount, 'Editor must expose ≥1 editable line').toBeGreaterThan(0);
  const links = await qtc.readHeaderLinks();
  expect(links.some((/** @type {any} */ l) => /\/lightning\/r\/Account\//.test(l.href)), 'Account link in header').toBe(true);
  expect(links.some((/** @type {any} */ l) => /\/lightning\/r\/SBQQ__Quote__c\//.test(l.href)), 'Quote link in header').toBe(true);
  expect(await qtc.isSaveDisabled(), 'Save must be disabled on fresh load').toBe(true);
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
  if (!c) { record('[4.1] Editor Core: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[4.1] Editor Core: 0 amendments', () => runEditorCore(page, c, 'zero'));
});

test('[4.2] Editor Core: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[4.2] Editor Core: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[4.2] Editor Core: 1 amendment', () => runEditorCore(page, c, 'one'));
});

test('[4.3] Editor Core: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[4.3] Editor Core: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  const approvalBlocking = approvalStatus != null && approvalStatus !== 'Approved';
  const expectedPreview  = deliveryPresent && !approvalBlocking;
  expect(await prevBtn.isEnabled().catch(() => false), `Preview & Send enabled should be ${expectedPreview}`).toBe(expectedPreview);
  const sb = page.getByRole('spinbutton').first();
  const cur = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
  await sb.click({ clickCount: 3 }); await sb.fill(String(cur + 1)); await sb.press('Tab');
  await page.waitForTimeout(1_000);
  expect(await saveBtn.isEnabled().catch(() => false), 'Save must be clickable after qty change').toBe(true);
  if (approvalPresent) {
    expect(await submitBtn.isEnabled().catch(() => false), 'Submit for Approval must be clickable').toBe(true);
  }
}

test('[5.1] Editor Buttons: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[5.1] Editor Buttons: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[5.1] Editor Buttons: 0 amendments', () => runEditorButtons(page, c, 'zero'));
});

test('[5.2] Editor Buttons: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[5.2] Editor Buttons: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[5.2] Editor Buttons: 1 amendment', () => runEditorButtons(page, c, 'one'));
});

test('[5.3] Editor Buttons: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[5.3] Editor Buttons: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  expect(dbAfter?.invoicing.id, 'Invoicing contact should be updated in DB').toBe(newInv.id);
  expect(dbAfter?.delivery.id,  'Delivery contact should be updated in DB').toBe(newDel.id);
}

test('[6.1] Contact Update: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[6.1] Contact Update: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[6.1] Contact Update: 0 amendments', () => runContactUpdate(page, c, 'zero'));
});

test('[6.2] Contact Update: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[6.2] Contact Update: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[6.2] Contact Update: 1 amendment', () => runContactUpdate(page, c, 'one'));
});

test('[6.3] Contact Update: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[6.3] Contact Update: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  expect(dbHeader?.SBQQ__StartDate__c, 'DB start date should match UI').toBe(uiAfterISO);
}

test('[7.1] Start Date Change: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[7.1] Start Date Change: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[7.1] Start Date Change: 0 amendments', () => runStartDateChange(page, c, 'zero'));
});

test('[7.2] Start Date Change: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[7.2] Start Date Change: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[7.2] Start Date Change: 1 amendment', () => runStartDateChange(page, c, 'one'));
});

test('[7.3] Start Date Change: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[7.3] Start Date Change: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  const starts   = first.map((/** @type {any} */ d) => d.SBQQ__StartDate__c).filter(Boolean).sort();
  const capISO   = ends.length   > 0 ? ends[0]                   : null;
  const floorISO = starts.length > 0 ? starts[starts.length - 1] : null;
  if (!capISO || !floorISO) throw new Error('Could not determine first-term bounds');
  const lower = await attemptDateAndCaptureToast(page, qtc, u.formatDateISO(u.addDays(new Date(`${floorISO}T00:00:00`), -1)), LOWER_TOAST_RE);
  const upper = await attemptDateAndCaptureToast(page, qtc, u.formatDateISO(u.addDays(new Date(`${capISO}T00:00:00`), 1)),   UPPER_TOAST_RE);
  expect(lower, 'Lower-bound toast should appear').toBe(true);
  expect(upper, 'Upper-bound toast should appear').toBe(true);
}

test('[8.1] Start Date Boundary: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[8.1] Start Date Boundary: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[8.1] Start Date Boundary: 0 amendments', () => runStartDateBoundary(page, c, 'zero'));
});

test('[8.2] Start Date Boundary: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[8.2] Start Date Boundary: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[8.2] Start Date Boundary: 1 amendment', () => runStartDateBoundary(page, c, 'one'));
});

test('[8.3] Start Date Boundary: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[8.3] Start Date Boundary: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  for (let i = 0; i < spinCount; i++) {
    const actual = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    if (Math.abs(actual - (initials[i] + QTY_INC)) >= 0.001) allPass = false;
  }
  expect(allPass, `All ${spinCount} quantities should have increased by ${QTY_INC}`).toBe(true);
}

test('[9.1] Qty Increase: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[9.1] Qty Increase: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[9.1] Qty Increase: 0 amendments', () => runQuantityIncrease(page, c, 'zero'));
});

test('[9.2] Qty Increase: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[9.2] Qty Increase: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[9.2] Qty Increase: 1 amendment', () => runQuantityIncrease(page, c, 'one'));
});

test('[9.3] Qty Increase: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[9.3] Qty Increase: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  for (let i = 0; i < spinCount; i++) {
    const actual   = parseFloat(await sbs.nth(i).inputValue().catch(() => '0')) || 0;
    const expected = Math.max(1, initials[i] - QTY_DEC);
    if (Math.abs(actual - expected) >= 0.001) allPass = false;
  }
  expect(allPass, `All ${spinCount} quantities should have decreased by ${QTY_DEC} (floor 1)`).toBe(true);
}

test('[10.1] Qty Decrease: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[10.1] Qty Decrease: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[10.1] Qty Decrease: 0 amendments', () => runQuantityDecrease(page, c, 'zero'));
});

test('[10.2] Qty Decrease: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[10.2] Qty Decrease: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[10.2] Qty Decrease: 1 amendment', () => runQuantityDecrease(page, c, 'one'));
});

test('[10.3] Qty Decrease: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[10.3] Qty Decrease: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
}

test('[11.1] Qty Increase Segments (MDQ): 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[11.1] Qty Increase Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[11.1] Qty Increase Segments: 0 amendments', () => runQtyIncreaseSegments(page, c, 'zero'));
});

test('[11.2] Qty Increase Segments (MDQ): 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[11.2] Qty Increase Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[11.2] Qty Increase Segments: 1 amendment', () => runQtyIncreaseSegments(page, c, 'one'));
});

test('[11.3] Qty Increase Segments (MDQ): 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[11.3] Qty Increase Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
}

test('[12.1] Qty Decrease Segments (MDQ): 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[12.1] Qty Decrease Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[12.1] Qty Decrease Segments: 0 amendments', () => runQtyDecreaseSegments(page, c, 'zero'));
});

test('[12.2] Qty Decrease Segments (MDQ): 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[12.2] Qty Decrease Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[12.2] Qty Decrease Segments: 1 amendment', () => runQtyDecreaseSegments(page, c, 'one'));
});

test('[12.3] Qty Decrease Segments (MDQ): 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[12.3] Qty Decrease Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  expect(within(uiAcv, db.expectedAcv, CURRENCY_TOL), `ACV mismatch: UI=${uiAcv} DB=${db.expectedAcv}`).toBe(true);
  expect(within(uiTcv, db.expectedTcv, CURRENCY_TOL), `TCV mismatch: UI=${uiTcv} DB=${db.expectedTcv}`).toBe(true);
  if (db.expectedYoy != null) expect(within(uiYoy, db.expectedYoy, PCT_TOL), `YoY mismatch: UI=${uiYoy} DB=${db.expectedYoy}`).toBe(true);
  if (db.expectedDqs != null) expect(within(uiDqs, db.expectedDqs, PCT_TOL), `DQS mismatch: UI=${uiDqs} DB=${db.expectedDqs}`).toBe(true);
}

test('[13.1] Metrics Verification: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[13.1] Metrics Verification: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[13.1] Metrics Verification: 0 amendments', () => runMetricsVerification(page, c, 'zero'));
});

test('[13.2] Metrics Verification: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[13.2] Metrics Verification: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[13.2] Metrics Verification: 1 amendment', () => runMetricsVerification(page, c, 'one'));
});

test('[13.3] Metrics Verification: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[13.3] Metrics Verification: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  if (!c) { record('[14.1] Qty Increase Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[14.1] Qty Increase Non-Segment: 0 amendments', () => runNonSegmentQty(page, c, 'zero', QTY_INC));
});

test('[14.2] Qty Increase Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[14.2] Qty Increase Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[14.2] Qty Increase Non-Segment: 1 amendment', () => runNonSegmentQty(page, c, 'one', QTY_INC));
});

test('[14.3] Qty Increase Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[14.3] Qty Increase Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
}

test('[15.1] Qty Increase Bundle Segments: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[15.1] Qty Increase Bundle Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[15.1] Qty Increase Bundle Segments: 0 amendments', () => runBundleSegmentQty(page, c, 'zero', MDQ_DELTA));
});

test('[15.2] Qty Increase Bundle Segments: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[15.2] Qty Increase Bundle Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[15.2] Qty Increase Bundle Segments: 1 amendment', () => runBundleSegmentQty(page, c, 'one', MDQ_DELTA));
});

test('[15.3] Qty Increase Bundle Segments: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[15.3] Qty Increase Bundle Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
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
  if (!c) { record('[16.1] Qty Increase Bundle Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[16.1] Qty Increase Bundle Non-Segment: 0 amendments', () => runBundleNonSegmentQty(page, c, 'zero', QTY_INC));
});

test('[16.2] Qty Increase Bundle Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[16.2] Qty Increase Bundle Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[16.2] Qty Increase Bundle Non-Segment: 1 amendment', () => runBundleNonSegmentQty(page, c, 'one', QTY_INC));
});

test('[16.3] Qty Increase Bundle Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[16.3] Qty Increase Bundle Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
  await runSafe('[16.3] Qty Increase Bundle Non-Segment: 2+ amendments', () => runBundleNonSegmentQty(page, c, 'many', QTY_INC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 17 — Qty Decrease: Non-Segment products (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[17.1] Qty Decrease Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[17.1] Qty Decrease Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[17.1] Qty Decrease Non-Segment: 0 amendments', () => runNonSegmentQty(page, c, 'zero', -QTY_DEC));
});

test('[17.2] Qty Decrease Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[17.2] Qty Decrease Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[17.2] Qty Decrease Non-Segment: 1 amendment', () => runNonSegmentQty(page, c, 'one', -QTY_DEC));
});

test('[17.3] Qty Decrease Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[17.3] Qty Decrease Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
  await runSafe('[17.3] Qty Decrease Non-Segment: 2+ amendments', () => runNonSegmentQty(page, c, 'many', -QTY_DEC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 18 — Qty Decrease: Bundle Non-Segment (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[18.1] Qty Decrease Bundle Non-Segment: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[18.1] Qty Decrease Bundle Non-Segment: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[18.1] Qty Decrease Bundle Non-Segment: 0 amendments', () => runBundleNonSegmentQty(page, c, 'zero', -QTY_DEC));
});

test('[18.2] Qty Decrease Bundle Non-Segment: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[18.2] Qty Decrease Bundle Non-Segment: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[18.2] Qty Decrease Bundle Non-Segment: 1 amendment', () => runBundleNonSegmentQty(page, c, 'one', -QTY_DEC));
});

test('[18.3] Qty Decrease Bundle Non-Segment: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[18.3] Qty Decrease Bundle Non-Segment: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
  await runSafe('[18.3] Qty Decrease Bundle Non-Segment: 2+ amendments', () => runBundleNonSegmentQty(page, c, 'many', -QTY_DEC));
});

// ─────────────────────────────────────────────────────────────────────────────
// GROUP 19 — Qty Decrease: Bundle Segments / MDQ (3 scenarios)
// ─────────────────────────────────────────────────────────────────────────────

test('[19.1] Qty Decrease Bundle Segments: 0 draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  if (!c) { record('[19.1] Qty Decrease Bundle Segments: 0 amendments', 'SKIP', 'No 0-draft contract found'); return; }
  await runSafe('[19.1] Qty Decrease Bundle Segments: 0 amendments', () => runBundleSegmentQty(page, c, 'zero', -MDQ_DELTA));
});

test('[19.2] Qty Decrease Bundle Segments: 1 draft amendment', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  if (!c) { record('[19.2] Qty Decrease Bundle Segments: 1 amendment', 'SKIP', 'No 1-draft contract found'); return; }
  await runSafe('[19.2] Qty Decrease Bundle Segments: 1 amendment', () => runBundleSegmentQty(page, c, 'one', -MDQ_DELTA));
});

test('[19.3] Qty Decrease Bundle Segments: 2+ draft amendments', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  if (!c) { record('[19.3] Qty Decrease Bundle Segments: 2+ amendments', 'SKIP', 'No many-draft contract found'); return; }
  await runSafe('[19.3] Qty Decrease Bundle Segments: 2+ amendments', () => runBundleSegmentQty(page, c, 'many', -MDQ_DELTA));
});

// ─────────────────────────────────────────────────────────────────────────────
// SUITE SUMMARY — evaluates the 75% pass threshold
// ─────────────────────────────────────────────────────────────────────────────

test('SUITE SUMMARY — pass rate must be ≥75%', async () => {
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
    ? `✅ SUITE PASSED: ${pct}% ≥ ${PASS_THRESHOLD}%`
    : `❌ SUITE FAILED: ${pct}% < ${PASS_THRESHOLD}%`;
  console.log(verdict);
  console.log(LINE + '\n');

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
    uiDbCrossCheck: SUITE_RESULTS.map((r, i) => ({
      uiIndex: i + 1, product: r.name, segOcc: null,
      uiBefore: null,  uiAfter: r.status,
      dbPrior: null,   dbAfter: r.detail || (r.status === 'PASS' ? 'OK' : ''),
      match: r.status !== 'FAIL', hasData: r.status !== 'SKIP',
    })),
    crossCheckMismatches: failed,
    dbAnomalies: SUITE_RESULTS
      .filter(r => r.status === 'FAIL')
      .map(r => ({ type: r.name, severity: 'HIGH', detail: r.detail })),
  });

  if (!overall) {
    throw new Error(`Suite failed: ${passed}/${evaluated} (${pct}%) — need ≥${PASS_THRESHOLD}% to pass`);
  }
});
