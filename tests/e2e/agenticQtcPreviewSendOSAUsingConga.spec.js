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
 * Deployed runtime step ordering (verified by observing the actual qtcmock org —
 * differs from what the LWC source on the default branch shows; the deployed
 * version pre-dates a recent refactor):
 *   step1 = Additional Documents (file-upload + related docs) — INITIAL view
 *   step2 = Generate OSA         (shows "Open Conga to Generate OSA" button)
 *   step3 = Review & Send        (shows PDF title in .doc-title)
 *
 * Default mode (QTC_OSA_WAIT_FOR_DOC unset): walks step1 → step2 and closes.
 * Fast (~5s).
 *
 * Opt-in mode (QTC_OSA_WAIT_FOR_DOC=1): on step2, clicks Open Conga and waits
 * for the wizard to advance — which it does once the LWC's own Apex polling
 * finds the saved PDF. We then read .doc-title (whichever step the wizard
 * ended on) — that's our PDF filename, no REST race.
 *
 * @param {import('@playwright/test').Page} page
 * @param {string} runDir
 */
async function walkPreviewSendWizard(page, runDir) {
  const result = {
    wizardOpened:     false,
    step1Verified:    false,
    step2Verified:    false,
    pdfAppearedInUi:  false,
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
  await u.screenshot(page, runDir, '02-wizard-step1');

  // ── Step 1: Additional Documents (initial view in deployed runtime) ───────
  await expect(modal).toContainText('Additional Documents');
  await expect(modal).toContainText('Generate OSA');
  await expect(modal).toContainText('Review & Send');
  await expect(modal.locator('.section-title')).toHaveText('Additional Documents');
  await expect(modal.locator('lightning-file-upload')).toBeVisible();
  result.step1Verified = true;

  // ── Step 2: Generate OSA ──────────────────────────────────────────────────
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
    // After Open Conga, a lightning-spinner inside .modal-body can intercept
    // pointer events on Close. Wait briefly for it to clear; if it doesn't,
    // skip the click — Playwright tears the page down at test end.
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
    // Legacy fast path: verify steps 1 + 2, close, return.
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

  // ── Wait for .doc-title to appear anywhere in the modal ───────────────────
  // The wizard's own Apex polling (pollForNewDocument) finds the saved PDF and
  // updates `generatedDoc`. Once that happens the title appears in the DOM —
  // step varies by deployed-LWC version (could be on Generate OSA's success
  // box, or on Review & Send). Watch the DOM directly for the title element.
  console.log(`[OSA] Waiting up to ${DOC_TIMEOUT_MS / 1000}s for PDF title to appear in the wizard…`);
  const docTitleLoc = modal.locator('.doc-title');
  try {
    await docTitleLoc.first().waitFor({ state: 'visible', timeout: DOC_TIMEOUT_MS });
    result.pdfAppearedInUi = true;
    const title = await docTitleLoc.first().innerText().catch(() => '');
    result.pdfTitle = title.trim() || null;
    console.log(`[OSA] PDF title from wizard: "${result.pdfTitle}"`);
    await u.screenshot(page, runDir, '04-wizard-pdf-visible');
  } catch (_) {
    // Fallback: try the success-box variant ("OSA generated successfully: <title>")
    const successBox = modal.locator('.status-box.status-success').filter({ hasText: /OSA generated successfully/i });
    if (await successBox.isVisible().catch(() => false)) {
      const txt = await successBox.innerText().catch(() => '');
      const m = txt.match(/OSA generated successfully:\s*(.+?)\s*$/);
      if (m) {
        result.pdfAppearedInUi = true;
        result.pdfTitle = m[1].trim();
        console.log(`[OSA] PDF title from success box: "${result.pdfTitle}"`);
        await u.screenshot(page, runDir, '04-wizard-success-box');
      }
    }
    if (!result.pdfTitle) {
      console.log(`[OSA] No PDF title appeared in the wizard within ${DOC_TIMEOUT_MS / 1000}s.`);
      await u.screenshot(page, runDir, '04-wizard-no-pdf');
    }
  }

  // Close the popup now that we have (or don't have) the PDF title.
  if (popup && !popup.isClosed()) {
    console.log(`[OSA] Closing Conga popup now.`);
    await popup.close().catch(() => {});
  }
  result.popup = popup;
  result.closePopup = async () => {
    if (popup && !popup.isClosed()) await popup.close().catch(() => {});
  };

  // ── If we're not already on step 3, try to advance there for a final screenshot ─
  if (result.pdfTitle) {
    const reviewHdr = modal.locator('h4.section-title').filter({ hasText: /Review Documents/i });
    if (await reviewHdr.isVisible().catch(() => false)) {
      result.step3Reached = true;
    } else {
      // Try clicking Next once or twice to reach Review & Send
      for (let i = 0; i < 2 && !result.step3Reached; i++) {
        const nextBtn = modal.getByRole('button', { name: 'Next' });
        if (await nextBtn.isVisible().catch(() => false) && await nextBtn.isEnabled().catch(() => false)) {
          await nextBtn.click({ timeout: 5_000 }).catch(() => {});
          if (await reviewHdr.waitFor({ state: 'visible', timeout: 5_000 }).then(() => true).catch(() => false)) {
            result.step3Reached = true;
            await u.screenshot(page, runDir, '05-wizard-step3');
          }
        } else {
          break;
        }
      }
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
                 + `(pdfAppearedInUi=${wizard.pdfAppearedInUi}, step3Reached=${wizard.step3Reached})`;
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
                  && wizard.step2Verified
                  && (WAIT_FOR_DOC ? wizard.pdfAppearedInUi : wizard.closedCleanly);
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
      { name: 'Step 2 verified',   expected: true, actual: wizard.step2Verified },
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
