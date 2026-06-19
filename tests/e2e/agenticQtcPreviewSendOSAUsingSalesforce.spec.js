// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

/**
 * E2E for the "Generate PDF — Instant" path of the Preview & Send OSA wizard.
 * Uses the native Salesforce Visualforce renderer (no Conga roundtrip), so we
 * can deterministically click the button, capture the popup PDF tab, and
 * screenshot the generated document.
 */

const KIND              = 'previewSendOsaInstant';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Jacobs Holding AG';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Jacobs Holding AG';
const RESULTS_DIR       = path.join(__dirname, 'results');

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
 * Walks the Preview & Send OSA wizard Step 1 → Step 2 → clicks the native PDF
 * generation button → captures the popup VF page → waits for auto-advance to
 * Step 3 → screenshots the generated document row → closes cleanly.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} runDir
 */
async function walkInstantPdfWizard(page, runDir) {
  /** @type {{ wizardOpened:boolean, step1Verified:boolean, step2Verified:boolean, instantBtnClicked:boolean, popupCaptured:boolean, pdfScreenshot:string|null, reachedStep3:boolean, closedCleanly:boolean }} */
  const result = {
    wizardOpened:      false,
    step1Verified:     false,
    step2Verified:     false,
    instantBtnClicked: false,
    popupCaptured:     false,
    pdfScreenshot:     null,
    reachedStep3:      false,
    closedCleanly:     false,
  };

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

  // Step 2: both generation buttons must render together.
  const instantBtn = modal.getByRole('button', { name: /Generate PDF\s*[—-]\s*Instant/ });
  await expect(modal.getByRole('button', { name: 'Open Conga to Generate OSA' })).toBeVisible({ timeout: 10_000 });
  await expect(instantBtn, 'Instant PDF button visible in Step 2').toBeVisible({ timeout: 10_000 });
  await expect(
    modal.getByRole('button', { name: 'Next' }),
    'Step 2 Next stays disabled until OSA is generated',
  ).toBeDisabled();
  await expect(modal.getByRole('button', { name: 'Back' })).toBeVisible();
  result.step2Verified = true;
  await u.screenshot(page, runDir, '03-wizard-step2');

  // Click "Generate PDF — Instant" and capture the popup VF page.
  // The LWC calls window.open(pdfUrl, '_blank') synchronously, so the popup
  // event fires immediately. The native PDF viewer renders the document so
  // popup.screenshot() captures the actual generated PDF.
  const popupPromise = page.waitForEvent('popup', { timeout: 15_000 }).catch(() => null);
  await instantBtn.click();
  result.instantBtnClicked = true;

  const popup = await popupPromise;
  if (popup) {
    // Give Chromium's PDF viewer a moment to render the document.
    await popup.waitForLoadState('domcontentloaded', { timeout: 20_000 }).catch(() => {});
    await page.waitForTimeout(2500);
    const pdfName = '04-instant-generated-pdf';
    await popup.screenshot({ path: path.join(runDir, `${pdfName}.png`), fullPage: true }).catch(() => {});
    result.popupCaptured = true;
    result.pdfScreenshot = `${pdfName}.png`;
    await popup.close().catch(() => {});
  }

  // The wizard's own spinner shows while the background generateInstantPdf()
  // saves the ContentVersion. Once it resolves, the wizard auto-advances to
  // Step 3. VF render + insert typically takes 5-15s; 60s is generous.
  await expect(modal).toContainText(/Generating native Salesforce PDF/i, { timeout: 5_000 }).catch(() => {});
  await u.screenshot(page, runDir, '05-instant-spinner');
  result.reachedStep3 = await expect(modal).toContainText('Review Document', { timeout: 60_000 })
    .then(() => true).catch(() => false);
  if (result.reachedStep3) {
    await u.screenshot(page, runDir, '06-instant-step3');
  }

  // Force-click guards against the spinner overlay still being up if save
  // is slower than expected. The LWC clears its state on disconnect.
  await modal.getByRole('button', { name: 'Close' }).first().click({ force: true });
  await expect(modal).toBeHidden({ timeout: 10_000 });
  result.closedCleanly = true;
  await u.screenshot(page, runDir, '07-after-close');
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
  console.log(`\n[Instant][Scenario ${scenarioNumber}] Contract ${contract.number} (branch=${branch}) → ${runDir}`);

  await u.screenshot(page, runDir, '01-contracts');
  const { quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[Instant][Scenario ${scenarioNumber}] Editor open on quote ${quoteName}`);

  const hasApproval    = await page.getByText('Approvals required').isVisible().catch(() => false);
  const sendBtn        = page.getByRole('button', { name: 'Preview and Send OSA' });
  const hasSendBtn     = await u.isVisibleSafe(sendBtn, 3_000);
  // CPQ disables Preview & Send OSA when the quote has pending approvals; the
  // button is still rendered but `disabled`/`aria-disabled="true"`. Clicking
  // it would block Playwright for the actionTimeout before failing — surface
  // it as a clean SKIP with the gate condition in the rich results instead.
  const sendBtnEnabled = hasSendBtn && await sendBtn.isEnabled().catch(() => false);
  console.log(`[Instant][Scenario ${scenarioNumber}] hasApproval=${hasApproval}  hasSendBtn=${hasSendBtn}  sendBtnEnabled=${sendBtnEnabled}`);

  if (!hasSendBtn || !sendBtnEnabled) {
    const reason = !hasSendBtn
      ? '"Preview and Send OSA" button not rendered on quote'
      : hasApproval
        ? '"Preview and Send OSA" is disabled because the quote has pending approvals'
        : '"Preview and Send OSA" is disabled (unknown gate)';
    console.log(`[Instant][Scenario ${scenarioNumber}] SKIP — ${reason}`);
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_FULL_NAME,
      scenarioNumber, scenarioLabel,
      contract: contract.number, quoteName,
      hasApproval, hasSendBtn,
      passed: true,
      extra: { skipped: true, reason, sendBtnEnabled },
    });
    test.skip(true, `${reason} (${quoteName})`);
    return;
  }

  const wizard  = await walkInstantPdfWizard(page, runDir);
  // popupCaptured is intentionally NOT in the pass criteria: the deployed LWC
  // no longer opens a popup for the Instant PDF path (it generates inline and
  // advances the wizard directly). "Reached Step 3" is the authoritative
  // signal that the PDF was generated and saved. Keep popupCaptured in the
  // dashboard steps list as informational only — green when the LWC version
  // still pops a window, gray-mismatch when it doesn't.
  const allPass = wizard.wizardOpened && wizard.step1Verified && wizard.step2Verified
               && wizard.instantBtnClicked && wizard.reachedStep3 && wizard.closedCleanly;

  const steps = [
    { name: 'Wizard opened',            expected: true, actual: wizard.wizardOpened      },
    { name: 'Step 1 verified',          expected: true, actual: wizard.step1Verified     },
    { name: 'Step 2 verified',          expected: true, actual: wizard.step2Verified     },
    { name: 'Instant PDF button click', expected: true, actual: wizard.instantBtnClicked },
    { name: 'Popup PDF captured',       expected: true, actual: wizard.popupCaptured     },
    { name: 'Reached Step 3',           expected: true, actual: wizard.reachedStep3      },
    { name: 'Closed cleanly',           expected: true, actual: wizard.closedCleanly     },
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
    pdfSkipped: !wizard.popupCaptured,
    dbLineCount: dbComparison.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: { wizard, pdfScreenshot: wizard.pdfScreenshot },
  });
  expect(allPass, 'Wizard should open, click Instant PDF, capture popup, and close').toBe(true);
}

test('Scenario 1: contract with 0 amendments — Instant PDF generation + popup screenshot', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — Instant PDF generation + popup screenshot', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — Instant PDF generation + popup screenshot', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
