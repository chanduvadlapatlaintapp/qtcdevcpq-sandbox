// @ts-check
/**
 * Account Search (agenticQtcAccountSearch) — UI behavior + eligibility cross-check.
 *
 * Unlike the other specs, this one does NOT drill into a contract scenario; it
 * exercises the first page of the app (the account typeahead) directly:
 *
 *   1. Min-length gate — a single character shows no dropdown (results + the
 *      "no results" empty-state both stay hidden). The LWC only searches at
 *      searchTerm.length >= 2 (agenticQtcAccountSearch.js handleSearchChange).
 *   2. Results render — a known account term returns ≥1 card, the matching card
 *      carries the search term, and EVERY returned account is eligible per the
 *      same semi-join the Apex applies (in-force contract + Software sub). The
 *      first card then navigates into the Active Contracts grid.
 *   3. No results — a nonsense term shows the "No accounts found for …" empty
 *      state with the term echoed back, and zero cards.
 *
 * Backed by AgenticQTC_AccountSearchService.searchAccounts (SOSL + contract
 * semi-join). Because SOSL relevance/eventual-consistency makes exact count
 * parity flaky, we assert UI shape + per-account eligibility rather than a
 * UI-count == DB-count equality.
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');
const { AgenticQtcPage } = require('./utils/agenticQtcPage');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');

const KIND              = 'accountSearch';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
// A term that should never match a real account name (≥2 chars so it passes the
// min-length gate and actually fires a search).
const NONSENSE_TERM     = process.env.QTC_NONSENSE_TERM     || 'zzqxnomatch';
const RESULTS_DIR       = path.join(__dirname, 'results');

/** @type {{ instanceUrl:string, lightningUrl:string, accessToken:string }} */
let creds;

test.beforeAll(() => {
  creds = getSfCredentials();
});

/**
 * Fresh login + landing on the account search page.
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<AgenticQtcPage>}
 */
async function openAccountSearch(page) {
  await loginViaCookie(page, creds.lightningUrl, creds.accessToken);
  const qtc = new AgenticQtcPage(page, /** @type {any} */ (creds));
  await qtc.goto();
  return qtc;
}

test('Min-length gate: a single character shows no dropdown', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openAccountSearch(page);

  // One character is below the 2-char minimum — neither results nor the
  // no-results empty-state should appear.
  await qtc.typeAccountSearch(ACCOUNT_SEARCH.charAt(0));
  await u.screenshot(page, runDir, '01-single-char');

  expect(await qtc.accountCards().count(), 'No result cards below the 2-char minimum').toBe(0);
  expect(
    await u.isVisibleSafe(qtc.noResultsDropdown(), 1_000),
    'No "no results" empty-state below the 2-char minimum',
  ).toBe(false);
});

test('No results: a nonsense term shows the empty-state', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openAccountSearch(page);

  await qtc.typeAccountSearch(NONSENSE_TERM);
  await u.screenshot(page, runDir, '01-no-results');

  await expect(qtc.noResultsDropdown(), 'Empty-state dropdown should be visible').toBeVisible();
  await expect(qtc.noResultsDropdown(), 'Empty-state should echo the search term').toContainText(NONSENSE_TERM);
  expect(await qtc.accountCards().count(), 'Zero cards for a nonsense term').toBe(0);
});

test('Special characters: SOSL metacharacter in search term returns no results', async ({ page }) => {
  const { runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openAccountSearch(page);

  // BIZ-84073: Apex rejects any search term containing a SOSL metacharacter
  // (? " ! ^ ~ * : + { } | [ ] \) and returns [] before SOSL ever runs.
  // We inject " into the middle of the known ACCOUNT_SEARCH so the term would
  // otherwise return results — confirming the guard fires on the character, not
  // on a nonsense string that simply has no DB matches.
  const mid = Math.ceil(ACCOUNT_SEARCH.length / 2);
  const metacharTerm = ACCOUNT_SEARCH.slice(0, mid) + '"' + ACCOUNT_SEARCH.slice(mid);
  await qtc.typeAccountSearch(metacharTerm);
  await u.screenshot(page, runDir, '01-metachar-term');

  expect(
    await qtc.accountCards().count(),
    `BIZ-84073: metachar term "${metacharTerm}" must return zero account cards`,
  ).toBe(0);
  await expect(
    qtc.noResultsDropdown(),
    'No-results empty-state should appear when the Apex metacharacter gate fires',
  ).toBeVisible();
});

test('Results: known account returns eligible cards and navigates to contracts', async ({ page }) => {
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);
  const qtc = await openAccountSearch(page);

  await qtc.typeAccountSearch(ACCOUNT_SEARCH);
  await qtc.accountCards().first().waitFor({ state: 'visible', timeout: 20_000 });
  await u.screenshot(page, runDir, '01-results');

  const cards = await qtc.readAccountCards();
  expect(cards.length, `Search "${ACCOUNT_SEARCH}" should return at least one account`).toBeGreaterThan(0);

  // At least one card matches the search term (case-insensitive contains).
  const termLower = ACCOUNT_SEARCH.toLowerCase();
  const matching  = cards.filter(c => (c.name || '').toLowerCase().includes(termLower));
  expect(matching.length, `A returned card should contain "${ACCOUNT_SEARCH}"`).toBeGreaterThan(0);

  // Eligibility cross-check: every returned account must satisfy the same
  // in-force-contract + Software-subscription semi-join the Apex applies.
  const crossCheck = [];
  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];
    const eligibleCount = card.id ? await qtc.countEligibleContracts(card.id) : 0;
    crossCheck.push({
      uiIndex:  i + 1,
      product:  card.name || '—',
      segOcc:   null,
      uiBefore: null,
      uiAfter:  card.location || '—',
      dbPrior:  null,
      dbAfter:  String(eligibleCount),
      match:    eligibleCount >= 1,
      hasData:  true,
    });
    expect(
      eligibleCount,
      `Returned account "${card.name}" (${card.id}) must have ≥1 eligible contract`,
    ).toBeGreaterThanOrEqual(1);
  }

  // Clicking the first card drills into the Active Contracts grid — proves the
  // accountselected event wires through agenticQtcApp to the OSA selector.
  await qtc.accountCards().first().click();
  await qtc.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
  await u.screenshot(page, runDir, '02-contracts');

  const mismatches = crossCheck.filter(r => !r.match).length;
  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber: 1,
    scenarioLabel: `Account search "${ACCOUNT_SEARCH}" → eligible cards → contracts`,
    spinbuttonCount: cards.length,
    dbLineCount: crossCheck.length,
    uiDbCrossCheck: crossCheck,
    crossCheckMismatches: mismatches,
    passed: mismatches === 0 && cards.length > 0,
    extra: { searchTerm: ACCOUNT_SEARCH, cardCount: cards.length, cards },
  });
});
