// @ts-check
/**
 * App Navigation & Theme — QTC Test Runner suite ('agenticQtcAppNavigation').
 *
 * A UI smoke test for the agenticQtcApp shell, walked in sequence:
 *
 *   1. Account search page  → dark/light toggle flips the theme.
 *   2. Contract (OSA) page   → dark/light toggle flips the theme.
 *   3. Quote editor page     → dark/light toggle flips the theme.
 *   4. Quote editor header   → the two record links (account + quote) each open
 *                              the Salesforce record page in a NEW browser tab.
 *   5. Breadcrumb back-nav   → the contract crumb returns to the OSA/contract page,
 *                              then the account crumb returns to account search.
 *
 * Theme is read from the root container class (.app-container dark-theme|light-theme),
 * toggled by button.dark-mode-toggle in the app header. Breadcrumb items are
 * span.breadcrumb-item.clickable (account first, contract second).
 *
 * Non-destructive: no Save, no quantity edits — pure navigation/UI checks.
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');
const { AgenticQtcPage } = require('./utils/agenticQtcPage');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');

const KIND              = 'appNavigation';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');

/** @type {{instanceUrl:string, lightningUrl:string, accessToken:string, accountSearch:string, accountFullName:string}} */
let sfCtx;

test.beforeAll(() => {
  const creds = getSfCredentials();
  sfCtx = {
    instanceUrl:     creds.instanceUrl,
    lightningUrl:    creds.lightningUrl,
    accessToken:     creds.accessToken,
    accountSearch:   ACCOUNT_SEARCH,
    accountFullName: ACCOUNT_FULL_NAME,
  };
});

/**
 * Click the dark/light toggle and assert the theme flips, then flip it back.
 * @param {import('@playwright/test').Page} page
 * @param {AgenticQtcPage} qtc
 * @param {string} label
 * @returns {Promise<{label:string, before:string, after:string, pass:boolean}>}
 */
async function checkThemeToggle(page, qtc, label) {
  const toggle = qtc.themeToggleButton();
  await toggle.waitFor({ state: 'visible', timeout: 15_000 });
  const before = await qtc.currentTheme();
  await toggle.click();
  await page.waitForTimeout(400);
  const after = await qtc.currentTheme();
  // Restore the original theme so later pages start from a known state.
  await toggle.click();
  await page.waitForTimeout(300);
  const pass = before !== 'unknown' && after !== 'unknown' && after !== before;
  console.log(`[appNav] theme @ ${label}: ${before} → ${after} (${pass ? 'OK' : 'FAIL'})`);
  return { label, before, after, pass };
}

/**
 * @param {{
 *   page: import('@playwright/test').Page,
 *   qtc:  AgenticQtcPage,
 *   runDir: string, runTs: string, testStartMs: number,
 * }} ctx
 */
async function runAppNavigation(ctx) {
  const { page, qtc, runDir, runTs, testStartMs } = ctx;

  /** @type {Array<{step:string, detail:string, pass:boolean}>} */
  const steps = [];
  const record = (step, detail, pass) => { steps.push({ step, detail, pass }); };

  // ── 1. Account search page ──────────────────────────────────────────────
  await qtc.accountSearchInput().waitFor({ state: 'visible', timeout: 60_000 });
  await u.screenshot(page, runDir, '01-account-search');
  const t1 = await checkThemeToggle(page, qtc, 'Account search');
  record('Theme · Account search', `${t1.before} → ${t1.after}`, t1.pass);

  // ── 2. Contract (OSA) selector page ─────────────────────────────────────
  await qtc.searchAndSelectAccount(sfCtx.accountSearch, sfCtx.accountFullName);
  await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
  await u.screenshot(page, runDir, '02-contracts');
  const t2 = await checkThemeToggle(page, qtc, 'Contract selector');
  record('Theme · Contract selector', `${t2.before} → ${t2.after}`, t2.pass);

  // ── 3. Quote editor page ─────────────────────────────────────────────────
  const editorMounted = await qtc.openContractByIndex(0, 120_000);
  expect(editorMounted, 'Quote editor should mount after opening the first contract').toBe(true);
  await qtc.waitForLines(120_000);
  const quoteName = await qtc.getQuoteName();
  await u.screenshot(page, runDir, '03-editor');
  const t3 = await checkThemeToggle(page, qtc, 'Quote editor');
  record('Theme · Quote editor', `${t3.before} → ${t3.after}`, t3.pass);

  // ── 3b. Product dropdown reveals extra details (ACV) ─────────────────────
  // Each MDQ product row has a chevron toggle (.product-toggle) that expands a
  // .detail-row showing extra metrics like ACV (agenticQtcMdqTermGroup). Only
  // run when the editor actually has product rows.
  /** @type {boolean|null} */ let dropdownPass = null;   // null = N/A (no products)
  let dropdownDetail = 'no product rows on this quote';
  const productToggle = page.locator('.product-toggle').first();
  if (await u.isVisibleSafe(productToggle, 5_000)) {
    const acvDetail = page.locator('.detail-row .detail-label').filter({ hasText: /ACV/i }).first();
    const visBefore = await u.isVisibleSafe(acvDetail, 1_500);
    await productToggle.click();
    await page.waitForTimeout(600);
    const visAfter = await u.isVisibleSafe(acvDetail, 3_000);
    dropdownPass   = visBefore !== visAfter;   // clicking toggles the ACV detail row
    dropdownDetail = `ACV detail ${visBefore ? 'shown' : 'hidden'} → ${visAfter ? 'shown' : 'hidden'}`;
    await u.screenshot(page, runDir, '03b-product-dropdown');
    console.log(`[appNav] product dropdown: ${dropdownDetail} (${dropdownPass ? 'OK' : 'FAIL'})`);
    record('Product dropdown · ACV detail', dropdownDetail, dropdownPass);
    // Re-open it so a screenshot of the editor shows the expanded detail.
    if (!visAfter) { await productToggle.click().catch(() => {}); }
  } else {
    console.log('[appNav] product dropdown: no product rows — skipped');
  }

  // ── 4. Editor header record links open a record page in a NEW tab ────────
  const links = page.locator('a.header-title-link');
  const linkCount = await links.count();
  /** @type {Array<{label:string, url:string, ok:boolean}>} */
  const linkResults = [];
  for (let i = 0; i < linkCount; i++) {
    const link  = links.nth(i);
    const label = (await link.innerText().catch(() => `link ${i + 1}`)).trim() || `link ${i + 1}`;
    let url = '';
    let ok  = false;
    try {
      const [popup] = await Promise.all([
        page.context().waitForEvent('page', { timeout: 20_000 }),
        link.click(),
      ]);
      await popup.waitForURL(/\/lightning\/r\//, { timeout: 30_000, waitUntil: 'commit' }).catch(() => {});
      url = popup.url();
      ok  = /\/lightning\/r\//.test(url);   // landed on a Salesforce record page
      await popup.close();
    } catch (e) {
      url = `(no new tab opened: ${e instanceof Error ? e.message : String(e)})`;
    }
    linkResults.push({ label, url, ok });
    console.log(`[appNav] record link "${label}" → ${ok ? 'opened record page' : 'FAILED'}: ${url}`);
    record(`Record link · ${label}`, url, ok);
  }
  expect(linkCount, 'Editor header should expose the account + quote record links').toBeGreaterThan(0);
  await u.screenshot(page, runDir, '04-after-links');

  // Editor is still the active page (links opened in separate tabs).
  await qtc.saveButton().waitFor({ state: 'visible', timeout: 15_000 });

  // ── 5. Breadcrumb back-navigation ────────────────────────────────────────
  // Contract crumb (2nd) → OSA/contract page.
  const crumbs = qtc.breadcrumbItems();
  const crumbCount = await crumbs.count();
  let contractCrumbPass = false;
  if (crumbCount >= 2) {
    await crumbs.nth(1).click();
    contractCrumbPass = await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 })
      .then(() => true).catch(() => false);
  }
  record('Breadcrumb · Contract → contract page', `crumbs=${crumbCount}`, contractCrumbPass);
  await u.screenshot(page, runDir, '05-back-to-contracts');

  // Account crumb (now the only/first crumb) → account search page.
  await qtc.breadcrumbItems().first().click();
  const accountCrumbPass = await qtc.accountSearchInput().waitFor({ state: 'visible', timeout: 30_000 })
    .then(() => true).catch(() => false);
  record('Breadcrumb · Account → account search', '', accountCrumbPass);
  await u.screenshot(page, runDir, '06-back-to-accounts');

  // ── Build dashboard payload (UI↔DB tab repurposed as a step checklist) ───
  /** @type {any[]} */
  const uiDbCrossCheck = steps.map((s, idx) => ({
    uiIndex: idx + 1,
    product: s.step,
    segOcc: null,
    uiBefore: null,
    uiAfter: s.detail || (s.pass ? 'OK' : 'FAIL'),
    dbPrior: null,
    dbAfter: s.pass ? 'pass' : 'fail',
    match: s.pass, hasData: true,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;
  /** @type {Array<{type:string,severity:string,detail:string}>} */
  const dbAnomalies = steps.filter(s => !s.pass)
    .map(s => ({ type: s.step, severity: 'HIGH', detail: `${s.step} failed — ${s.detail}` }));
  const allPass = steps.every(s => s.pass);

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber: 1,
    scenarioLabel: 'App shell — theme toggles, record links, breadcrumb navigation',
    quoteName: quoteName || null,
    uiDbCrossCheck, crossCheckMismatches,
    dbAnomalies,
    passed: allPass,
    extra: { steps, linkResults },
  });

  // ── Assertions ──
  expect(t1.pass, 'Theme toggle should work on the Account search page').toBe(true);
  expect(t2.pass, 'Theme toggle should work on the Contract selector page').toBe(true);
  expect(t3.pass, 'Theme toggle should work on the Quote editor page').toBe(true);
  if (dropdownPass !== null) {
    expect(dropdownPass, 'Product dropdown should toggle the ACV detail row').toBe(true);
  }
  for (const lr of linkResults) {
    expect(lr.ok, `Header link "${lr.label}" should open a record page in a new tab (got: ${lr.url})`).toBe(true);
  }
  expect(contractCrumbPass, 'Contract breadcrumb should return to the contract page').toBe(true);
  expect(accountCrumbPass, 'Account breadcrumb should return to the account search page').toBe(true);
}

test('App navigation & theme: toggles per page, record links open new tabs, breadcrumb nav', async ({ page }) => {
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);
  console.log(`\n[appNavigation] account="${ACCOUNT_FULL_NAME}" → ${runDir}`);

  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken);
  const qtc = new AgenticQtcPage(page, sfCtx);
  await qtc.goto();

  await runAppNavigation({ page, qtc, runDir, runTs, testStartMs });
});
