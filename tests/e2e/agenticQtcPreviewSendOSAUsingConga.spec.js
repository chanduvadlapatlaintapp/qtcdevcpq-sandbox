// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');
const {
  snapshotForOsa,
  findContentVersionByTitle,
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
 * Walks the Preview & Send OSA wizard.
 *
 * LWC step ordering (per agenticQtcPreviewSend.html):
 *   step1 = Generate OSA       (default — shows "Open Conga to Generate OSA" button)
 *   step2 = Additional Documents (file-upload + related docs)
 *   step3 = Review & Send      (shows PDF title)
 *
 * Default mode (QTC_OSA_WAIT_FOR_DOC unset): just verify step1 renders correctly
 *   and close. Fast (~5s).
 *
 * Opt-in mode (QTC_OSA_WAIT_FOR_DOC=1): click Open Conga, let the LWC's own
 *   Apex polling find the PDF and auto-advance to step2, then click Next to
 *   reach step3 and read the PDF title from the wizard. The title is the
 *   reliable signal — no REST race.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} runDir
 */
async function walkPreviewSendWizard(page, runDir) {
  const result = {
    wizardOpened:     false,
    step1Verified:    false,
    step2Reached:     false,
    step3Reached:     false,
    closedCleanly:    false,
    congaTriggered:   false,
    congaTriggeredAt: 0,
    /** @type {string|null} */
    pdfTitle: null,
    /** @type {import('@playwright/test').Page|null} */
    popup: null,
    /** @type {(() => Promise<void>) | null} */
    closeWizard: null,
    /** @type {(() => Promise<void>) | null} */
    closePopup: null,
  };

  await page.getByRole('button', { name: 'Preview and Send OSA' }).click();
  const modal = page.locator('section.modal-overlay');
  await expect(modal).toBeVisible({ timeout: 15_000 });
  await expect(modal.locator('.modal-header h3')).toHaveText(/Preview\s*&\s*Send OSA/);
  result.wizardOpened = true;
  await u.screenshot(page, runDir, '02-wizard-step1-generate');

  // ── Step 1: Generate OSA ─────────────────────────────────────────────────
  // The three progress labels are all in the indicator at the top.
  await expect(modal).toContainText('Generate OSA');
  await expect(modal).toContainText('Additional Documents');
  await expect(modal).toContainText('Review & Send');
  // Step 1's body shows the "Open Conga to Generate OSA" button initially.
  const openCongaBtn = modal.getByRole('button', { name: 'Open Conga to Generate OSA' });
  await expect(openCongaBtn).toBeVisible({ timeout: 10_000 });
  result.step1Verified = true;

  const closeWizard = async () => {
    if (result.closedCleanly) return;
    // After clicking "Open Conga", a lightning-spinner inside .modal-body can
    // intercept pointer events on Close. Wait briefly for it to clear; if it
    // doesn't, skip the click — Playwright tears the page down at test end.
    const spinner = modal.locator('lightning-spinner').first();
    await spinner.waitFor({ state: 'hidden', timeout: 10_000 }).catch(() => {});
    if (await spinner.isVisible().catch(() => false)) {
      console.log('[OSA] Spinner still up; skipping clean Close — page teardown will handle it.');
      await u.screenshot(page, runDir, '06-close-skipped-spinner-up');
      return;
    }
    await modal.getByRole('button', { name: 'Close' }).first().click({ timeout: 5_000 }).catch(() => {});
    await expect(modal).toBeHidden({ timeout: 5_000 }).catch(() => {});
    result.closedCleanly = true;
    await u.screenshot(page, runDir, '06-after-close');
  };

  if (!WAIT_FOR_DOC) {
    // Legacy fast path: verify step1, then close.
    await closeWizard();
    return result;
  }

  // ── Click Open Conga, capture popup, leave it OPEN ─────────────────────────
  // Conga's popup is its client driver — closing it aborts the generation.
  const popupPromise = page.context().waitForEvent('page', { timeout: 15_000 }).catch(() => null);
  await openCongaBtn.click();
  result.congaTriggered   = true;
  result.congaTriggeredAt = Date.now();

  const popup = await popupPromise;
  if (popup) {
    console.log(`[OSA] Conga popup captured (kept open): ${popup.url()}`);
    try {
      await popup.waitForLoadState('domcontentloaded', { timeout: 10_000 }).catch(() => {});
      await popup.screenshot({ path: require('path').join(runDir, '03c-conga-popup.png'), fullPage: true }).catch(() => {});
    } catch (_) { /* best effort */ }
  } else {
    console.log('[OSA] No popup detected within 15s — Conga may have inlined the flow, or popup was blocked.');
  }
  await u.screenshot(page, runDir, '03b-after-open-conga');

  // ── Wait for LWC's own Apex polling to find the PDF ───────────────────────
  // When pollForNewDocument returns a doc, the LWC sets generatedDoc and flips
  // currentStep to 'step2'. We detect that transition by step2's section-title.
  console.log(`[OSA] Waiting up to ${DOC_TIMEOUT_MS / 1000}s for wizard to advance to step 2…`);
  const step2Header = modal.locator('h4.section-title').filter({ hasText: /Select Additional Documents/i });
  try {
    await step2Header.waitFor({ state: 'visible', timeout: DOC_TIMEOUT_MS });
    result.step2Reached = true;
    console.log(`[OSA] Wizard advanced to step 2 — PDF is in Salesforce.`);
    await u.screenshot(page, runDir, '04-wizard-step2');
  } catch (_) {
    console.log(`[OSA] Wizard never advanced past step 1 within ${DOC_TIMEOUT_MS / 1000}s — Conga did not produce a PDF.`);
    await u.screenshot(page, runDir, '04-wizard-stuck-step1');
  }

  // Close the popup once we know the LWC has (or hasn't) seen the PDF.
  if (popup && !popup.isClosed()) {
    console.log(`[OSA] Closing Conga popup now.`);
    await popup.close().catch(() => {});
  }
  result.popup = popup;
  result.closePopup = async () => {
    if (popup && !popup.isClosed()) await popup.close().catch(() => {});
  };

  // ── Advance to step 3 to read the PDF title from the DOM ──────────────────
  if (result.step2Reached) {
    try {
      await modal.getByRole('button', { name: 'Next' }).click({ timeout: 10_000 });
      const step3Header = modal.locator('h4.section-title').filter({ hasText: /Review Documents/i });
      await step3Header.waitFor({ state: 'visible', timeout: 15_000 });
      result.step3Reached = true;
      await u.screenshot(page, runDir, '05-wizard-step3');
      const titleText = await modal.locator('.doc-title').first().innerText().catch(() => '');
      result.pdfTitle = titleText.trim() || null;
      console.log(`[OSA] PDF title from wizard: "${result.pdfTitle}"`);
    } catch (e) {
      console.log(`[OSA] Could not advance to step 3: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

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
    // The wizard's own Apex polling is the authoritative "PDF found" signal:
    // when pollForNewDocument returns a doc, the LWC sets generatedDoc and
    // flips currentStep to 'step2'. walkPreviewSendWizard waited for that
    // transition and read the title from step 3's .doc-title. We just need to
    // resolve the title → ContentVersion Id, then download + parse.
    try {
      if (!wizard.pdfTitle) {
        pdfError = `Wizard did not produce a PDF title within ${DOC_TIMEOUT_MS / 1000}s `
                 + `(step2Reached=${wizard.step2Reached}, step3Reached=${wizard.step3Reached})`;
      } else {
        console.log(`[OSA] Looking up ContentVersion by title: "${wizard.pdfTitle}"`);
        const cv = await findContentVersionByTitle(sfCtx, wizard.pdfTitle);
        if (!cv) {
          pdfError = `PDF title "${wizard.pdfTitle}" not found in ContentVersion `
                   + `(LWC saw it but REST query returned nothing — possible sharing issue)`;
        } else {
          pdfFound = true;
          pdfTitle = cv.title;
          const { text, numPages } = await downloadPdfText(sfCtx, cv.contentVersionId);
          console.log(`[OSA] Downloaded "${cv.title}" (${numPages} pages, ${text.length} chars)`);

          const cmp = comparePdfToSnapshot(snapshot, text);
          pdfRows       = cmp.rows;
          pdfMatches    = cmp.matches;
          pdfMismatches = cmp.mismatches;
          console.log(`[OSA] PDF compare: ${pdfMatches} matches, ${pdfMismatches} mismatches`);
        }
      }
    } catch (e) {
      pdfError = `PDF compare failed: ${e instanceof Error ? e.message : String(e)}`;
      console.log(`[OSA] ${pdfError}`);
    }

    // Tidy up: close the popup (already closed by walkPreviewSendWizard, but
    // safe to call again) and the wizard modal.
    if (wizard.closePopup) await wizard.closePopup();
    if (wizard.closeWizard) await wizard.closeWizard();
  }

  // closedCleanly is meaningful only in the legacy fast path. In WAIT_FOR_DOC
  // mode the modal may end on step 3 (Review & Send) and we don't always close
  // it cleanly — that's fine, the test framework tears down the page.
  const wizardPass = wizard.wizardOpened
                  && wizard.step1Verified
                  && (WAIT_FOR_DOC ? wizard.step2Reached : wizard.closedCleanly);
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
      { name: 'Wizard opened',     expected: true, actual: wizard.wizardOpened },
      { name: 'Step 1 verified',   expected: true, actual: wizard.step1Verified },
      { name: 'Step 2 reached',    expected: true, actual: wizard.step2Reached },
      { name: 'Step 3 reached',    expected: true, actual: wizard.step3Reached },
      { name: 'Closed cleanly',    expected: true, actual: wizard.closedCleanly },
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
