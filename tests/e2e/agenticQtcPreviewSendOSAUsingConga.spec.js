// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');
const {
  snapshotForOsa,
  waitForGeneratedPdf,
  downloadPdfText,
  comparePdfToSnapshot,
} = require('./utils/congaDoc');

const KIND              = 'previewSendOsa';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');

// Opt-in: drive Step 3 (click "Open Conga"), then wait ~2 min for the PDF
// and compare its contents to the UI/DB snapshot. Default off because the
// existing spec deliberately stops at Step 2 (the Conga roundtrip adds 2-3 min).
const WAIT_FOR_DOC      = process.env.QTC_OSA_WAIT_FOR_DOC === '1';
const DOC_TIMEOUT_MS    = parseInt(process.env.QTC_OSA_DOC_TIMEOUT_MS || '180000', 10);

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
 * Walks the Preview & Send OSA wizard from Step 1 → Step 2.
 *
 * Default mode: closes after Step 2 verification (no Conga roundtrip — the
 * external tab + 1-1.5 min generation is too slow for the standard suite).
 *
 * With QTC_OSA_WAIT_FOR_DOC=1: clicks "Open Conga to Generate OSA", swallows
 * the popup, leaves the wizard open so the caller can poll for the PDF, and
 * returns a `congaTriggeredAt` timestamp + a `closeWizard` thunk.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} runDir
 */
async function walkPreviewSendWizard(page, runDir) {
  const result = {
    wizardOpened:    false,
    step1Verified:   false,
    step2Verified:   false,
    closedCleanly:   false,
    congaTriggered:  false,
    congaTriggeredAt: 0,
    /** @type {(() => Promise<void>) | null} */
    closeWizard: null,
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

  const openCongaBtn = modal.getByRole('button', { name: 'Open Conga to Generate OSA' });
  await expect(openCongaBtn).toBeVisible({ timeout: 10_000 });
  await expect(
    modal.getByRole('button', { name: 'Next' }),
    'Step 2 Next stays disabled until OSA is generated',
  ).toBeDisabled();
  await expect(modal.getByRole('button', { name: 'Back' })).toBeVisible();
  result.step2Verified = true;
  await u.screenshot(page, runDir, '03-wizard-step2');

  const closeWizard = async () => {
    if (result.closedCleanly) return;
    await modal.getByRole('button', { name: 'Close' }).first().click();
    await expect(modal).toBeHidden({ timeout: 5_000 });
    result.closedCleanly = true;
    await u.screenshot(page, runDir, '04-after-close');
  };

  if (!WAIT_FOR_DOC) {
    await closeWizard();
    return result;
  }

  // ── Step 3: trigger Conga generation, swallow the popup, leave wizard open ─
  // The Conga popup opens in a new tab. We don't drive it — Conga auto-generates
  // and writes the PDF back to Salesforce. We just need to capture the popup so
  // it doesn't leak, then poll SF for the new ContentDocument.
  const popupPromise = page.context().waitForEvent('page', { timeout: 15_000 }).catch(() => null);
  await openCongaBtn.click();
  result.congaTriggered   = true;
  result.congaTriggeredAt = Date.now();

  const popup = await popupPromise;
  if (popup) {
    console.log(`[OSA] Conga popup captured: ${popup.url()}. Closing — generation continues server-side.`);
    await popup.close().catch(() => {});
  } else {
    console.log('[OSA] No popup detected within 15s — Conga may have inlined the flow. Continuing.');
  }
  await u.screenshot(page, runDir, '03b-after-open-conga');

  result.closeWizard = closeWizard;
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

  // Snapshot UI/DB BEFORE opening the wizard so we have the "expected" values
  // to compare against the PDF that Conga will generate from the same data.
  /** @type {import('./utils/congaDoc').OsaSnapshot | null} */
  let snapshot = null;
  if (WAIT_FOR_DOC) {
    try {
      snapshot = await snapshotForOsa(sfCtx, {
        quoteName,
        accountName:    ACCOUNT_FULL_NAME,
        contractNumber: contract.number,
      });
      console.log(`[OSA] Snapshot taken: ${snapshot.lines.length} lines, net=${snapshot.netAmount}`);
    } catch (e) {
      console.log(`[OSA] Snapshot failed (will skip PDF compare): ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  const wizard  = await walkPreviewSendWizard(page, runDir);

  // ── PDF wait + compare (only when QTC_OSA_WAIT_FOR_DOC=1) ─────────────────
  /** @type {Array<any>} */ let pdfRows = [];
  let pdfMatches = 0, pdfMismatches = 0;
  let pdfFound = false, pdfTitle = null, pdfError = null;

  if (WAIT_FOR_DOC && wizard.congaTriggered && snapshot) {
    console.log(`[OSA] Waiting up to ${DOC_TIMEOUT_MS / 1000}s for Conga PDF…`);
    try {
      const pdfRef = await waitForGeneratedPdf(
        sfCtx,
        [snapshot.quoteId, contract.id],
        wizard.congaTriggeredAt,
        { timeoutMs: DOC_TIMEOUT_MS, pollMs: 5_000, logger: msg => console.log(msg) },
      );

      if (pdfRef) {
        pdfFound = true;
        pdfTitle = pdfRef.title;
        const { text, numPages } = await downloadPdfText(sfCtx, pdfRef.contentVersionId);
        console.log(`[OSA] Downloaded "${pdfRef.title}" (${numPages} pages, ${text.length} chars)`);

        const cmp = comparePdfToSnapshot(snapshot, text);
        pdfRows       = cmp.rows;
        pdfMatches    = cmp.matches;
        pdfMismatches = cmp.mismatches;
        console.log(`[OSA] PDF compare: ${pdfMatches} matches, ${pdfMismatches} mismatches`);
      } else {
        pdfError = `PDF did not appear within ${DOC_TIMEOUT_MS / 1000}s`;
      }
    } catch (e) {
      pdfError = `PDF compare failed: ${e instanceof Error ? e.message : String(e)}`;
      console.log(`[OSA] ${pdfError}`);
    }

    // Close the wizard now that we're done with Conga
    if (wizard.closeWizard) await wizard.closeWizard();
  }

  const wizardPass = wizard.wizardOpened && wizard.step1Verified && wizard.step2Verified && wizard.closedCleanly;
  const pdfPass    = !WAIT_FOR_DOC || (pdfFound && pdfMismatches === 0);
  const allPass    = wizardPass && pdfPass;

  // Build dashboard rows. In WAIT_FOR_DOC mode we emit PDF compare rows; otherwise
  // we emit the legacy step-verification rows so the existing dashboard view stays useful.
  /** @type {Array<any>} */ let dbComparison = [];
  /** @type {Array<any>} */ let uiDbCrossCheck = [];

  if (WAIT_FOR_DOC && pdfRows.length > 0) {
    dbComparison = pdfRows.map((r, i) => ({
      index:    i + 1,
      product:  r.field,
      segKey:   r.match ? '✓' : '✗',
      segIndex: null,
      priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
      dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
      isBundle: false,
      startDate: null, endDate: null,
      pricingMethod: null, term: null, regularPrice: null,
    }));
    uiDbCrossCheck = pdfRows.map((r, i) => ({
      uiIndex:  i + 1,
      product:  r.field,
      segOcc:   null,
      uiBefore: '—',
      uiAfter:  r.expected,
      dbPrior:  '—',
      dbAfter:  r.inPdf,
      match:    r.match,
      hasData:  true,
    }));
  } else {
    const steps = [
      { name: 'Wizard opened',   expected: true, actual: wizard.wizardOpened },
      { name: 'Step 1 verified', expected: true, actual: wizard.step1Verified },
      { name: 'Step 2 verified', expected: true, actual: wizard.step2Verified },
      { name: 'Closed cleanly',  expected: true, actual: wizard.closedCleanly },
    ];
    dbComparison = steps.map((s, i) => ({
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
    uiDbCrossCheck = steps.map((s, i) => ({
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
  }
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number, quoteName,
    hasApproval, hasSendBtn,
    pdfGenerated: pdfFound,
    pdfSkipped:   !WAIT_FOR_DOC,
    dbLineCount:  dbComparison.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: {
      wizard,
      waitForDoc:    WAIT_FOR_DOC,
      pdfTitle,
      pdfMatches,
      pdfMismatches,
      pdfError,
      snapshotLines: snapshot ? snapshot.lines.length : 0,
    },
  });

  expect(wizardPass, 'Wizard should open, advance Step 1 → Step 2, and close').toBe(true);
  if (WAIT_FOR_DOC) {
    expect(pdfFound, pdfError || 'Conga PDF should appear within timeout').toBe(true);
    expect(pdfMismatches, `PDF should match snapshot (${pdfMatches}✓ / ${pdfMismatches}✗)`).toBe(0);
  }
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
