// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'previewSendOsa';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');

test.use({ viewport: null });

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
 * Walks the Preview & Send OSA wizard from Step 1 → Step 2, then closes it.
 * Step 3 + the Conga roundtrip are out of scope (external tab, too flaky for headless E2E).
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} runDir
 */
async function walkPreviewSendWizard(page, runDir) {
  const result = { wizardOpened: false, step1Verified: false, step2Verified: false, closedCleanly: false };

  await page.getByRole('button', { name: 'Preview and Send OSA' }).click();
  const modal = page.locator('section.modal-overlay');
  await expect(modal).toBeVisible({ timeout: 15_000 });
  await expect(modal.locator('.modal-header h3')).toHaveText(/Preview\s*&\s*Send OSA/);
  result.wizardOpened = true;
  await u.screenshot(page, runDir, '02-wizard-step1');

  await expect(modal).toContainText('Additional Documents');
  await expect(modal).toContainText('Generate OSA');
  await expect(modal).toContainText('Review & Send');
  await expect(modal.locator('.section-title')).toHaveText('Additional Documents');
  await expect(modal.locator('lightning-file-upload')).toBeVisible();
  result.step1Verified = true;

  await modal.getByRole('button', { name: 'Next' }).click();

  await expect(modal.getByRole('button', { name: 'Open Conga to Generate OSA' })).toBeVisible({ timeout: 10_000 });
  await expect(
    modal.getByRole('button', { name: 'Next' }),
    'Step 2 Next stays disabled until OSA is generated',
  ).toBeDisabled();
  await expect(modal.getByRole('button', { name: 'Back' })).toBeVisible();
  result.step2Verified = true;
  await u.screenshot(page, runDir, '03-wizard-step2');

  await modal.getByRole('button', { name: 'Close' }).first().click();
  await expect(modal).toBeHidden({ timeout: 5_000 });
  result.closedCleanly = true;
  await u.screenshot(page, runDir, '04-after-close');
  return result;
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
  const { quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[Scenario ${scenarioNumber}] Editor open on quote ${quoteName}`);

  const hasApproval = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn  = await u.isVisibleSafe(page.getByRole('button', { name: 'Preview and Send OSA' }), 3_000);
  console.log(`[Scenario ${scenarioNumber}] hasApproval=${hasApproval}  hasSendBtn=${hasSendBtn}`);

  if (!hasSendBtn) {
    console.log(`[Scenario ${scenarioNumber}] SKIP — wizard button not rendered`);
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_FULL_NAME,
      scenarioNumber, scenarioLabel,
      contract: contract.number, quoteName,
      hasApproval, hasSendBtn,
      passed: true,
      extra: { skipped: true, reason: '"Preview and Send OSA" button not rendered on quote' },
    });
    test.skip(true, `"Preview and Send OSA" button not rendered on ${quoteName}`);
    return;
  }

  const wizard  = await walkPreviewSendWizard(page, runDir);
  const allPass = wizard.wizardOpened && wizard.step1Verified && wizard.step2Verified && wizard.closedCleanly;

  // No DB data for a UI-only wizard test — emit step-verification rows in the
  // standard shape so the dashboard's DB Lines + UI-DB tabs surface the wizard
  // step outcomes (expected ✓ vs actual ✓) instead of rendering empty.
  const steps = [
    { name: 'Wizard opened',        expected: true, actual: wizard.wizardOpened },
    { name: 'Step 1 verified',      expected: true, actual: wizard.step1Verified },
    { name: 'Step 2 verified',      expected: true, actual: wizard.step2Verified },
    { name: 'Closed cleanly',       expected: true, actual: wizard.closedCleanly },
  ];
  const dbComparison = steps.map((s, i) => ({
    index:    i + 1,
    product:  s.name,
    segKey:   s.actual ? '✓' : '✗',
    segIndex: null,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
    dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
    isBundle: false,
    startDate: null, endDate: null,
    pricingMethod: null, term: null, regularPrice: null,
  }));
  const uiDbCrossCheck = steps.map((s, i) => ({
    uiIndex:  i + 1,
    product:  s.name,
    segOcc:   null,
    uiBefore: '—',
    uiAfter:  String(s.expected),
    dbPrior:  '—',
    dbAfter:  String(s.actual),
    match:    s.expected === s.actual,
    hasData:  true,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number, quoteName,
    hasApproval, hasSendBtn,
    pdfSkipped: true,
    dbLineCount: dbComparison.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: { wizard },
  });
  expect(allPass, 'Wizard should open, advance Step 1 → Step 2, and close').toBe(true);
}

test('Scenario 1: contract with 0 amendments — fresh amendment, OSA wizard walks Step 1→2', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — opens existing draft, OSA wizard walks Step 1→2', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — picks from modal, OSA wizard walks Step 1→2', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
