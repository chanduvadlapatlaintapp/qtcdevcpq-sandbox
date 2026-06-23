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

// ── OSA datatable helpers (shared with fullRegressionE2E) ─────────────────────

/** Mirror the LWC's formatDate(). @param {string|null|undefined} s */
function fmtDate(s) {
  if (!s) return '—';
  return new Date(s + 'T00:00:00').toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

/** Mirror the LWC's formatCurrency(). @param {number|null|undefined} val @param {string|null|undefined} code */
function fmtCurrency(val, code) {
  if (val == null) return '—';
  const n = Number(val);
  if (!Number.isFinite(n)) return '—';
  const c = code || 'USD';
  if (Math.abs(n) >= 1_000_000) return `${c} ${(n / 1_000_000).toFixed(2)}M`;
  return `${c} ${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

// ── REST API helpers — replicate getActiveContracts without Aura interception ──
// Aura network interception (request+response correlation) was unreliable across
// runs — the browser sometimes batched/reused the Aura action before our listener
// was ready.  Direct REST API calls from Node are synchronous-style and always work.

/**
 * Look up an Account Id by its exact Name.
 * @param {string} instanceUrl
 * @param {string} accessToken
 * @param {string} accountName
 * @returns {Promise<string|null>}
 */
async function fetchAccountIdFromName(instanceUrl, accessToken, accountName) {
  const soql = `SELECT Id FROM Account WHERE Name = '${accountName.replace(/'/g, "\\'")}' LIMIT 1`;
  try {
    const result = await u.sfQueryNode(instanceUrl, accessToken, soql);
    return result.records[0]?.Id || null;
  } catch { return null; }
}

/** Replicates AgenticQTC_ContractService.isMoreCurrent(). @param {any} candidate @param {any} incumbent */
function _isMoreCurrent(candidate, incumbent) {
  const cStart = candidate.SBQQ__SegmentStartDate__c;
  const iStart = incumbent.SBQQ__SegmentStartDate__c;
  if (cStart !== iStart) {
    if (cStart == null) return false;
    if (iStart == null) return true;
    return cStart > iStart;
  }
  return (candidate.SBQQ__SegmentQuantity__c || 0) > (incumbent.SBQQ__SegmentQuantity__c || 0);
}

/** Replicates AgenticQTC_ContractService.formatQuantity(). @param {number|null} qty */
function _formatQty(qty) {
  if (qty == null) return '0';
  return qty === Math.floor(qty) ? String(Math.floor(qty)) : String(qty);
}

/**
 * Fetch active contracts for an account via the Salesforce REST API, replicating
 * the exact logic of AgenticQTC_ContractService.getActiveContracts().
 *
 * Contract filters: Status IN ('In Force', 'Partially Cancelled or superseded'),
 * EndDate >= TODAY, has at least one Software subscription.
 * ACV: per product, use the current-segment line with the latest SegmentStartDate
 * (tie-broken by highest SegmentQuantity), compute (NetPrice/ProrateMultiplier)*12*SegmentQty.
 * productNames: sorted "{qty}x {name}" for all current-year Software segments.
 *
 * @param {string} instanceUrl
 * @param {string} accessToken
 * @param {string} accountId
 * @returns {Promise<any[]>}  Array of ContractResult-shaped objects
 */
async function fetchActiveContractsFromApi(instanceUrl, accessToken, accountId) {
  const contractSoql = [
    'SELECT Id, Name, ContractNumber, OSA_Number__c, Status, StartDate, EndDate,',
    'CurrencyIsoCode, Account.Name, Owner.Name',
    'FROM Contract',
    `WHERE AccountId = '${accountId}'`,
    "AND Status IN ('In Force', 'Partially Cancelled or superseded')",
    'AND EndDate >= TODAY',
    'AND Id IN (',
    '  SELECT SBQQ__Contract__c FROM SBQQ__Subscription__c',
    '  WHERE SBQQ__Contract__c != null',
    "  AND SBQQ__Product__r.Product_Type__c = 'Software'",
    ')',
    'ORDER BY ContractNumber ASC NULLS LAST',
    'LIMIT 100',
  ].join(' ');

  const contractResult = await u.sfQueryNode(instanceUrl, accessToken, contractSoql);
  const contracts = contractResult.records || [];
  if (contracts.length === 0) return [];

  const idList = contracts.map(c => `'${c.Id}'`).join(', ');
  const subSoql = [
    'SELECT Id, SBQQ__Contract__c, SBQQ__Product__c, SBQQ__ProductName__c,',
    'SBQQ__Quantity__c, SBQQ__SegmentQuantity__c,',
    'SBQQ__NetPrice__c, SBQQ__ProrateMultiplier__c,',
    'SBQQ__SegmentStartDate__c, SBQQ__SegmentEndDate__c',
    'FROM SBQQ__Subscription__c',
    `WHERE SBQQ__Contract__c IN (${idList})`,
    "AND SBQQ__Product__r.Product_Type__c = 'Software'",
  ].join(' ');

  const subResult = await u.sfQueryNode(instanceUrl, accessToken, subSoql);
  const subs = subResult.records || [];

  // Initialise per-contract aggregates
  /** @type {Record<string, {lineCount:number, pnq:Record<string,number>, currentYearAcv:number|null, acvBest:Record<string,any>}>} */
  const agg = {};
  for (const c of contracts) {
    agg[c.Id] = { lineCount: 0, pnq: {}, currentYearAcv: null, acvBest: {} };
  }

  const today = new Date().toISOString().slice(0, 10); // 'YYYY-MM-DD'
  for (const sub of subs) {
    const a = agg[sub.SBQQ__Contract__c];
    if (!a) continue;
    a.lineCount++;

    const segStart = sub.SBQQ__SegmentStartDate__c;
    const segEnd   = sub.SBQQ__SegmentEndDate__c;
    const isCurrent = (segStart == null || segStart <= today) && (segEnd == null || segEnd >= today);

    if (isCurrent && sub.SBQQ__ProductName__c) {
      const qty = sub.SBQQ__Quantity__c ?? 0;
      a.pnq[sub.SBQQ__ProductName__c] = (a.pnq[sub.SBQQ__ProductName__c] || 0) + qty;
    }

    if (isCurrent && sub.SBQQ__Product__c) {
      const key = sub.SBQQ__Contract__c + '|' + sub.SBQQ__Product__c;
      if (!a.acvBest[key] || _isMoreCurrent(sub, a.acvBest[key])) {
        a.acvBest[key] = sub;
      }
    }
  }

  // Compute ACV from best current-segment lines (same formula as Apex)
  for (const a of Object.values(agg)) {
    for (const line of Object.values(a.acvBest)) {
      const segQty = line.SBQQ__SegmentQuantity__c ?? line.SBQQ__Quantity__c;
      if (line.SBQQ__NetPrice__c == null || segQty == null) continue;
      const pm = line.SBQQ__ProrateMultiplier__c;
      const annual = (pm != null && pm !== 0) ? (line.SBQQ__NetPrice__c / pm) * 12 : line.SBQQ__NetPrice__c;
      a.currentYearAcv = (a.currentYearAcv ?? 0) + annual * segQty;
    }
  }

  return contracts.map(c => {
    const a = agg[c.Id];
    const productNames = Object.keys(a.pnq).sort()
      .map(name => `${_formatQty(a.pnq[name])}x ${name}`);
    return {
      id:              c.Id,
      contractName:    c.Name,
      contractNumber:  c.ContractNumber,
      osaNumber:       c.OSA_Number__c,
      status:          c.Status,
      startDate:       c.StartDate,
      endDate:         c.EndDate,
      currencyIsoCode: c.CurrencyIsoCode,
      accountName:     c.Account?.Name ?? null,
      currentYearAcv:  a.currentYearAcv,
      productNames,
      productSummary:  productNames.length > 0
        ? productNames.slice(0, 3).join(', ') + (productNames.length > 3 ? ` (+${productNames.length - 3} more)` : '')
        : '',
    };
  });
}

/**
 * Read every visible contract row from the OSA datatable.
 * Products cell: reads the .product-names-text span and .product-more-btn button separately.
 * @param {import('@playwright/test').Page} page
 */
async function readOsaDatatableRows(page) {
  const rows  = page.locator('tr.contract-row');
  const count = await rows.count();
  const out   = [];
  for (let i = 0; i < count; i++) {
    const row   = rows.nth(i);
    const cells = row.locator('td');
    const id    = await row.getAttribute('data-id');
    const [osaNbr, contractName, contractNum, startDate, endDate, acv] = await Promise.all(
      [0, 1, 2, 3, 4, 5].map(j => cells.nth(j).innerText().then(t => t.trim()).catch(() => ''))
    );
    const productNames = await cells.nth(6).locator('.product-names-text').innerText()
      .then(t => t.trim()).catch(() => '');
    const moreBtnVisible = await cells.nth(6).locator('.product-more-btn').isVisible().catch(() => false);
    const moreBtn = moreBtnVisible
      ? await cells.nth(6).locator('.product-more-btn').innerText().then(t => t.trim()).catch(() => null)
      : null;
    out.push({ id, osaNbr, contractName, contractNum, startDate, endDate, acv, productNames, moreBtn });
  }
  return out;
}

/**
 * Build a full field-by-field comparison table (ALL rows, ALL fields, match=true/false).
 * Returned rows are the canonical shape for richResults.osaComparison consumed by the dashboard.
 * @param {any[]} uiRows  from readOsaDatatableRows()
 * @param {any[]} backend from captureGetActiveContracts()
 * @returns {Array<{keyId:string, row:number, contractNum:string, field:string, ui:string, expected:string, match:boolean, rowClass:string}>}
 */
function compareOsaRows(uiRows, backend) {
  const rows = [];
  for (let i = 0; i < uiRows.length; i++) {
    const ui = uiRows[i];
    const be = backend.find(b => b.id === ui.id) || backend.find(b => b.contractNumber === ui.contractNum);
    if (!be) {
      rows.push({ keyId: `osa-${i}-match`, row: i + 1, contractNum: ui.contractNum, field: '(row match)', ui: ui.id || '?', expected: '(not in Apex response)', match: false, rowClass: 'osa-row-fail' });
      continue;
    }
    const allNames    = Array.isArray(be.productNames) ? be.productNames : [];
    const expProdText = allNames.length > 0 ? allNames.slice(0, 3).join(', ') : (be.productSummary || '—');
    const expMoreBtn  = allNames.length > 3 ? `+${allNames.length - 3} more` : null;
    const checks = [
      { field: 'OSA Number',      ui: ui.osaNbr,       expected: be.osaNumber      || '—' },
      { field: 'Contract Name',   ui: ui.contractName, expected: be.contractName   || '—' },
      { field: 'Contract Number', ui: ui.contractNum,  expected: be.contractNumber || '—' },
      { field: 'Start Date',      ui: ui.startDate,    expected: fmtDate(be.startDate) },
      { field: 'End Date',        ui: ui.endDate,      expected: fmtDate(be.endDate) },
      { field: 'ACV',             ui: ui.acv,          expected: fmtCurrency(be.currentYearAcv, be.currencyIsoCode) },
      { field: 'Products',        ui: ui.productNames, expected: expProdText },
      ...(expMoreBtn || ui.moreBtn
        ? [{ field: '+N more', ui: ui.moreBtn || '(none)', expected: expMoreBtn || '(none)' }]
        : []),
    ];
    checks.forEach((c, j) => {
      const match = c.ui === c.expected;
      rows.push({ keyId: `osa-${i}-${j}`, row: i + 1, contractNum: ui.contractNum, field: c.field, ui: c.ui, expected: c.expected, match, rowClass: match ? 'osa-row-ok' : 'osa-row-fail' });
    });
  }
  return rows;
}
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

test('Contracts grid — UI datatable fields match Apex backend data', async ({ page }) => {
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);

  // Navigate first — the REST API fetch runs in parallel without needing the page.
  await openContracts(page);
  await u.screenshot(page, runDir, '01-datatable');

  // Fetch backend data directly via REST API — no Aura interception needed.
  let backendContracts = null;
  try {
    const accountId = await fetchAccountIdFromName(sfCtx.instanceUrl, sfCtx.accessToken, sfCtx.accountFullName);
    if (accountId) {
      backendContracts = await fetchActiveContractsFromApi(sfCtx.instanceUrl, sfCtx.accessToken, accountId);
    } else {
      console.warn(`[${KIND}] Account "${sfCtx.accountFullName}" not found via REST API`);
    }
  } catch (err) {
    console.warn(`[${KIND}] REST API fetch failed: ${err instanceof Error ? err.message : String(err)}`);
  }

  if (!backendContracts || backendContracts.length === 0) {
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_FULL_NAME,
      scenarioNumber: 5,
      scenarioLabel: 'OSA datatable UI↔Backend — backend fetch returned no contracts',
      dbLineCount: 0,
      passed: false,
      osaComparison: [],
    });
    test.skip(true, `No contracts returned from REST API for "${ACCOUNT_FULL_NAME}"`);
    return;
  }

  const uiRows = await readOsaDatatableRows(page);
  expect(uiRows.length, `Account "${ACCOUNT_FULL_NAME}" should have at least one row`).toBeGreaterThan(0);

  const osaComparison = compareOsaRows(uiRows, backendContracts);
  const diffs         = osaComparison.filter(r => !r.match);

  await u.screenshot(page, runDir, '02-check-done');

  const passed = diffs.length === 0;

  if (!passed) {
    console.log(`[${KIND}] Datatable mismatches:\n` +
      diffs.map(d => `  Row ${d.row} [${d.contractNum}] ${d.field}:\n    UI:      "${d.ui}"\n    Backend: "${d.expected}"`).join('\n'));
  }

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber: 5,
    scenarioLabel: `OSA datatable UI↔Backend — ${uiRows.length} row(s) · ${diffs.length} diff(s)`,
    dbLineCount: uiRows.length,
    passed,
    osaComparison,
  });

  expect(
    diffs.length,
    diffs.length > 0
      ? `Datatable mismatches:\n${diffs.map(d => `Row ${d.row} [${d.contractNum}] ${d.field}: UI="${d.ui}" ≠ Backend="${d.expected}"`).join('\n')}`
      : 'All datatable fields match backend data'
  ).toBe(0);
});
