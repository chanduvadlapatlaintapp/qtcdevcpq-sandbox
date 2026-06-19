// @ts-check
/**
 * Quote Editor — core (agenticQtcQuoteEditor) — load + Save dirty-state gating.
 *
 * Verifies the editor's core, feature-agnostic behavior (the quantity / contact
 * / start-date specs cover the individual edit features):
 *
 *   1. Loads cleanly — the header shows the account link (→ /lightning/r/Account)
 *      and the Q-NNNNN quote link (→ /lightning/r/SBQQ__Quote__c), the four
 *      metric tiles (ACV / TCV / YoY Uplift / Deal Quality Score) render, and at
 *      least one editable quote line appears.
 *   2. Save dirty-state gating (BIZ-83431) — Save is DISABLED on a freshly
 *      loaded quote, ENABLES after a quantity edit, and RE-DISABLES after a
 *      successful Save (hasUnsavedChanges → isSaveDisabled).
 *   3. Back — the header back button returns to the Active Contracts list.
 *
 * Routes through the three OSA-selector branches via scenarioContracts, mirroring
 * every other editor spec:
 *   • Scenario 1 — 0 drafts → clicking the contract creates a new amendment and
 *                  mounts the editor directly.
 *   • Scenario 2 — 1 draft  → opens that existing draft directly (no modal).
 *   • Scenario 3 — ≥2 drafts → the "Existing Draft Quotes" modal opens; the
 *                  first draft is picked.
 * Only the bucket matching the account's first contract runs; the other two
 * self-skip (the suite-wide convention).
 */
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quoteEditorCore';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const QTY_DELTA         = 5;

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
 * Inner feature: from a mounted editor, assert header links + metric tiles +
 * the Save dirty-state gate, then navigate back to the contracts list.
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
async function runEditorCore(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;

  // ── 1a. Lines render ──────────────────────────────────────────────────────
  const spinbuttonCount = await qtc.waitForLines(120_000);
  expect(spinbuttonCount, 'Editor should expose at least one editable line').toBeGreaterThan(0);
  await u.screenshot(page, runDir, '02-editor-loaded');

  // ── 1b. Header links ──────────────────────────────────────────────────────
  const links       = await qtc.readHeaderLinks();
  const accountLink = links.find(l => /\/lightning\/r\/Account\//.test(l.href)) || null;
  const quoteLink   = links.find(l => /\/lightning\/r\/SBQQ__Quote__c\//.test(l.href)) || null;
  expect(accountLink, 'Header should link to the Account record').not.toBeNull();
  expect(accountLink?.href).toMatch(/\/lightning\/r\/Account\/[a-zA-Z0-9]{15,18}\/view/);
  expect(quoteLink, 'Header should link to the Quote record').not.toBeNull();
  expect(quoteLink?.href).toMatch(/\/lightning\/r\/SBQQ__Quote__c\/[a-zA-Z0-9]{15,18}\/view/);
  expect(quoteLink?.text, 'Quote link text should be the Q-NNNNN name').toBe(quoteName);

  // ── 1c. Metric tiles ──────────────────────────────────────────────────────
  const tiles   = await qtc.readMetricTiles();
  const byLabel = Object.fromEntries(tiles.map(t => [t.label, t.value]));
  for (const label of ['ACV', 'TCV', 'YoY Uplift', 'Deal Quality Score']) {
    expect(byLabel[label], `Metric tile "${label}" should render`).toBeDefined();
  }
  expect(byLabel['ACV'], 'ACV tile should show a value').not.toBe('--');
  expect(byLabel['TCV'], 'TCV tile should show a value').not.toBe('--');

  // ── 2. Save dirty-state gating (BIZ-83431) ────────────────────────────────
  // 2a. Disabled on a freshly loaded quote (nothing differs from persisted state).
  const disabledOnLoad = await qtc.isSaveDisabled();
  expect(disabledOnLoad, 'Save should be DISABLED on a freshly loaded quote').toBe(true);

  // 2b. Enables after a quantity edit.
  const firstSb = page.getByRole('spinbutton').first();
  const before  = parseFloat(await firstSb.inputValue().catch(() => '0')) || 0;
  await firstSb.click({ clickCount: 3 });
  await firstSb.fill(String(before + QTY_DELTA));
  await firstSb.press('Tab');
  await qtc.waitForSaveEnabled(30_000);   // throws if it never enables
  const enabledAfterEdit = !(await qtc.isSaveDisabled());
  expect(enabledAfterEdit, 'Save should ENABLE after a quantity edit').toBe(true);
  await u.screenshot(page, runDir, '03-save-enabled');

  // 2c. Re-disables after a successful Save.
  await qtc.save(120_000);
  await expect(qtc.saveButton(), 'Save should RE-DISABLE after a successful save').toBeDisabled({ timeout: 30_000 });
  const disabledAfterSave = await qtc.isSaveDisabled();
  await u.screenshot(page, runDir, '04-after-save');

  // ── 3. Back returns to the contracts list ─────────────────────────────────
  await qtc.backToContracts();
  await expect(qtc.activeContractsHeading(), 'Back should return to the contracts list').toBeVisible();
  await u.screenshot(page, runDir, '05-back-to-contracts');

  const passed = spinbuttonCount > 0 && !!accountLink && !!quoteLink
    && disabledOnLoad && enabledAfterEdit && disabledAfterSave;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName,
    spinbuttonCount,
    passed,
    extra: {
      headerLinks: links,
      metricTiles: tiles,
      saveGate: { disabledOnLoad, enabledAfterEdit, disabledAfterSave },
    },
  });

  expect(passed, 'Editor core: load + Save-gating + back should all hold').toBe(true);
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

  await runEditorCore({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — new amendment, editor core', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, editor core', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, editor core', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
