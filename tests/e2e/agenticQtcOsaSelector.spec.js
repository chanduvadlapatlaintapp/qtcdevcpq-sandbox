// @ts-check
/**
 * OSA / Contract Selector (agenticQtcOsaSelector) — contracts grid + draft-quote
 * picker UI behavior.
 *
 * After an account is chosen the app lands on the "Active Contracts" page. This
 * spec exercises the selector's own behaviors (the downstream quote editor is
 * covered by the other specs):
 *
 *   1. Contracts grid — the table renders ≥1 row and the "N active contract(s)"
 *      count badge matches the visible row count, with correct singular/plural.
 *      Every row exposes a Contract Id (data-id) and number (data-number).
 *   2. Products "+N more" toggle — clicking it expands the products cell to
 *      "Show less" WITHOUT navigating into the editor; clicking "Show less"
 *      collapses it back. (Skips if no row has >3 products.)
 *   3. "Clear" pill — returns from the contracts list to account search.
 *   4. Draft-quotes modal — for a contract with ≥2 draft amendments, clicking
 *      the row opens the picker; clicking inside the panel does NOT dismiss it;
 *      the backdrop and the X both close it; picking a row mounts the editor.
 *      (Skips if no contract on the account has ≥2 drafts.)
 *
 * Backed by AgenticQTC_AmendContractController.getActiveContracts /
 * getDraftQuotesForContract.
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');
const { AgenticQtcPage } = require('./utils/agenticQtcPage');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');

const KIND              = 'osaSelector';
// Default account chosen because it has a grid-visible contract with both >3
// products AND ≥2 add-on amendment drafts, so all four tests actively run on a
// direct `npx playwright test`. Overridden by QTC_ACCOUNT_* when launched from
// the dashboard (the runner passes the account picked there).
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Baker McKenzie';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Baker McKenzie LLP';
const RESULTS_DIR       = path.join(__dirname, 'results');

/** @type {{ instanceUrl:string, lightningUrl:string, accessToken:string, accountSearch:string, accountFullName:string }} */
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
 * Fresh login → account search → land on the Active Contracts grid.
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<AgenticQtcPage>}
 */
async function openContracts(page) {
  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken);
  const qtc = new AgenticQtcPage(page, sfCtx);
  await qtc.goto();
  await qtc.searchAndSelectAccount(sfCtx.accountSearch, sfCtx.accountFullName);
  await qtc.contractRows().first().waitFor({ state: 'visible', timeout: 30_000 }).catch(() => {});
  return qtc;
}

/**
 * Find a contract on the account that has ≥2 draft amendments (the modal
 * branch). Returns its { id, number } or null if none qualify.
 * @param {AgenticQtcPage} qtc
 */
async function findManyDraftContract(qtc) {
  const contracts = await qtc.getContractList();
  for (const c of contracts) {
    const count = await qtc.countDraftQuotes(c.id);
    if (count >= 2) return c;
  }
  return null;
}

test('Contracts grid renders with a matching count badge', async ({ page }) => {
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openContracts(page);
  await u.screenshot(page, runDir, '01-contracts');

  const rowCount = await qtc.contractRows().count();
  expect(rowCount, `Account "${ACCOUNT_FULL_NAME}" should list at least one active contract`).toBeGreaterThan(0);

  // Count badge text matches the row count, with correct singular/plural.
  await expect(qtc.contractCountBadge()).toBeVisible();
  const badgeText = (await qtc.contractCountBadge().innerText()).trim();
  const expectedBadge = rowCount === 1 ? '1 active contract' : `${rowCount} active contracts`;
  expect(badgeText, 'Count badge should match visible row count').toBe(expectedBadge);

  // Every row carries the Contract Id + number the editor needs to open.
  const contracts = await qtc.getContractList();
  expect(contracts.length, 'Each row should expose a data-id').toBe(rowCount);
  for (const c of contracts) {
    expect(c.id, 'Contract row must carry a Salesforce Id').toMatch(/^[a-zA-Z0-9]{15,18}$/);
  }

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber: 1,
    scenarioLabel: `Contracts grid for "${ACCOUNT_FULL_NAME}" — ${rowCount} row(s), badge "${badgeText}"`,
    dbLineCount: contracts.length,
    passed: rowCount > 0 && badgeText === expectedBadge,
    extra: { rowCount, badgeText, expectedBadge, contracts },
  });
});

test('Products "+N more" toggle expands without navigating away', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openContracts(page);

  const moreBtns = qtc.productMoreButtons();
  const moreCount = await moreBtns.count();
  test.skip(moreCount === 0, `No contract on "${ACCOUNT_FULL_NAME}" has >3 products (no "+N more" toggle to test)`);

  await moreBtns.first().click();
  await u.screenshot(page, runDir, '01-expanded');

  // Expanding shows "Show less" and must NOT drill into the editor — we're still
  // on the contracts page (Save button never appears).
  await expect(qtc.productShowLessButton(), '"Show less" should appear after expand').toBeVisible();
  await expect(qtc.activeContractsHeading(), 'Should stay on the contracts list').toBeVisible();
  expect(
    await u.isVisibleSafe(qtc.saveButton(), 1_500),
    'Toggling products must not open the quote editor',
  ).toBe(false);

  // Collapsing restores a "+N more" button.
  await qtc.productShowLessButton().first().click();
  await expect(qtc.productMoreButtons().first(), '"+N more" should return after collapse').toBeVisible();
});

test('"Clear" pill returns to account search', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openContracts(page);

  await expect(qtc.accountPillClear()).toBeVisible();
  await qtc.accountPillClear().click();
  await u.screenshot(page, runDir, '01-back-to-search');

  await expect(qtc.accountSearchInput(), 'Clear should return to the account search page').toBeVisible();
});

test('Draft-quotes modal: open, click-inside keeps it, backdrop/X close, row opens editor', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openContracts(page);

  const many = await findManyDraftContract(qtc);
  test.skip(!many, `No contract on "${ACCOUNT_FULL_NAME}" currently has ≥2 draft amendments`);
  const contract = /** @type {{id:string, number:string}} */ (many);

  // ── Open the picker ──
  await qtc.clickContractById(contract.id);
  const outcome = await qtc.waitForContractClickOutcome(120_000);
  expect(outcome, 'A ≥2-draft contract should open the picker modal').toBe('modal');
  await expect(qtc.draftQuotesModal()).toBeVisible();
  expect(await qtc.draftQuoteCountInModal(), 'Modal should list ≥2 drafts').toBeGreaterThanOrEqual(2);
  await u.screenshot(page, runDir, '01-modal-open');

  // ── Clicking inside the panel does NOT dismiss it (handleModalStop) ──
  await qtc.draftModalTitle().click();
  await expect(qtc.draftQuotesModal(), 'Clicking inside the panel keeps the modal open').toBeVisible();

  // ── Backdrop click closes it (back on the contracts grid) ──
  // Click the backdrop at a corner so the click lands outside the panel.
  await qtc.draftModalBackdrop().click({ position: { x: 8, y: 8 } });
  await expect(qtc.draftQuotesModal(), 'Backdrop click should close the modal').toBeHidden();
  await expect(qtc.activeContractsHeading()).toBeVisible();

  // ── Reopen, then close via the X button ──
  await qtc.clickContractById(contract.id);
  await expect(qtc.draftQuotesModal()).toBeVisible({ timeout: 120_000 });
  await qtc.draftModalClose().click();
  await expect(qtc.draftQuotesModal(), 'X button should close the modal').toBeHidden();

  // ── Reopen and pick the first draft → editor mounts ──
  await qtc.clickContractById(contract.id);
  await expect(qtc.draftQuotesModal()).toBeVisible({ timeout: 120_000 });
  await qtc.draftQuoteRows().first().click();
  await qtc.saveButton().waitFor({ state: 'visible', timeout: 120_000 });
  const quoteName = await qtc.getQuoteName();
  expect(quoteName, 'Picking a draft should open the editor on a Q-NNNNN quote').toMatch(/^Q-\d+$/);
  await u.screenshot(page, runDir, '02-editor-open');
});
