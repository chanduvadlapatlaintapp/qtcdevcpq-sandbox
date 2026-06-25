// @ts-check
/**
 * Amendment Quote Field Comparison — UI-Driven.
 *
 * Exercises both amendment creation flows end-to-end through the browser:
 *
 *   • SF Standard CPQ flow  — Contract record page → "Amend" action button
 *   • AgenticQTC custom flow — agenticQtcApp LWC → select account → contract → new amendment
 *
 * After both quotes are created through the UI, fetches every queryable field on
 * SBQQ__Quote__c and SBQQ__QuoteLine__c (via describe API + chunked SOQL) and
 * compares them across six focused angles, one Playwright test each.
 *
 * Results are written to a single results.json in the canonical shape the
 * agenticQtcTestDashboard LWC consumes.
 *
 * Suite name: 'amendmentUIComparison'
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { AgenticQtcPage } = require('./utils/agenticQtcPage');

const KIND            = 'amendmentUIComparison';
const ACCOUNT_NAME    = process.env.QTC_ACCOUNT_NAME   || 'Bates White';
const ACCOUNT_SEARCH  = process.env.QTC_ACCOUNT_SEARCH || 'Bates';
const RESULTS_DIR     = path.join(__dirname, 'results');
const SF_API_VER      = 'v62.0';

// Optional scoping params passed from the dashboard.
// CONTRACT_ID: SF Contract Id — if set, both flows use this contract (skips SOQL discovery).
// QUOTE_NAME:  existing QTC draft quote name — if set, triggers Mode 2:
//   Mode 1 (no QUOTE_NAME): QTC creates NEW amendment + updates qty inline;
//                           SF Standard creates NEW amendment + updates qty inline.
//   Mode 2 (QUOTE_NAME set): QTC opens EXISTING draft + updates qty inline;
//                            SF Standard creates NEW amendment + updates same qty inline.
const CONTRACT_ID  = process.env.QTC_CONTRACT_ID  || '';
const QUOTE_NAME   = process.env.QTC_QUOTE_NAME   || '';

// ── Fields naturally different between any two distinct records ───────────────
const ALWAYS_SKIP_FIELDS = new Set([
  'attributes',
  'Id', 'Name',
  'CreatedById', 'CreatedDate',
  'LastModifiedById', 'LastModifiedDate',
  'LastActivityDate', 'LastViewedDate', 'LastReferencedDate',
  'SystemModstamp',
  'OwnerId',
  'IsDeleted',
  'SBQQ__Quote__c', 'SBQQ__Number__c',
  'SBQQ__Key__c',
]);

const PRICING_FIELDS = [
  'SBQQ__NetAmount__c', 'SBQQ__CustomerAmount__c', 'SBQQ__ListAmount__c',
  'SBQQ__Subtotal__c',  'SBQQ__RegularAmount__c',
  'SBQQ__NetPrice__c',  'SBQQ__NetTotal__c',
  'SBQQ__ListPrice__c', 'SBQQ__CustomerPrice__c',
  'SBQQ__RegularPrice__c', 'SBQQ__RegularTotal__c',
  'SBQQ__Discount__c',  'SBQQ__AdditionalDiscount__c',
  'SBQQ__PriorQuantity__c',
];

const DATE_TERM_FIELDS = [
  'SBQQ__StartDate__c', 'SBQQ__EndDate__c',
  'SBQQ__SubscriptionTerm__c',
  'SBQQ__EffectiveStartDate__c', 'SBQQ__EffectiveEndDate__c',
];

const SUBSCRIPTION_LINKAGE_FIELDS = [
  'SBQQ__UpgradedSubscription__c',
  'SBQQ__RenewedSubscription__c',
  'SBQQ__Product__c',
];

// ── Shared state ──────────────────────────────────────────────────────────────
/** @type {{instanceUrl: string, lightningUrl: string, accessToken: string}} */
let sfCtx;
let testStartMs = 0;
/** @type {string} */ let runDir = '';
/** @type {string} */ let runTs  = '';

/** @type {{Id: string, ContractNumber: string} | null} */
let sharedContract = null;
/** @type {string | null} */ let sharedStdQuoteId = null;   // SF Standard CPQ UI
/** @type {string | null} */ let sharedQtcQuoteId = null;   // AgenticQTC UI
/** @type {Record<string, any>} */ let sharedStdQuote  = {};
/** @type {Record<string, any>} */ let sharedQtcQuote  = {};
/** @type {Array<Record<string, any>>} */ let sharedStdLines  = [];
/** @type {Array<Record<string, any>>} */ let sharedQtcLines  = [];

/** @type {string | null} */ let stdFlowSkipReason = null;

// ── Quantity-update shared state ──────────────────────────────────────────────
/** @type {string | null} */ let qtyUpdateProductId   = null;
/** @type {string | null} */ let qtyUpdateProductName = null;
/** @type {number | null} */ let qtyUpdateOldQty      = null;
/** @type {number | null} */ let qtyUpdateNewQty      = null;
/** @type {Array<Record<string, any>>} */ let stdLinesAfterQtyUpdate = [];
/** @type {Array<Record<string, any>>} */ let qtcLinesAfterQtyUpdate = [];
let qtyUpdateDone = false;

/** @type {Array<{severity: 'HIGH'|'MEDIUM'|'LOW', type: string, detail: string}>} */
let anomalies = [];
/** @type {Array<{testName: string, passed: boolean, diffCount: number}>} */
let testFindings = [];

/** @type {Record<string, string[]>} */
const describeCache = {};

// ── beforeAll ─────────────────────────────────────────────────────────────────
test.beforeAll(async ({ browser }) => {
  testStartMs = Date.now();
  const creds = getSfCredentials();
  sfCtx = {
    instanceUrl:  creds.instanceUrl,
    lightningUrl: creds.lightningUrl,
    accessToken:  creds.accessToken,
  };

  ({ runTs, runDir } = u.createRunFolder(RESULTS_DIR));
  console.log(`\n[${KIND}] runDir=${runDir}`);
  console.log(`[${KIND}] Mode: ${QUOTE_NAME ? `2 — open existing QTC draft "${QUOTE_NAME}"` : '1 — create new amendment in both flows'}`);

  // ── Resolve the contract to use ───────────────────────────────────────────
  // CONTRACT_ID is passed from the dashboard and is always set when the user
  // selected a contract before running. If absent (local dev without runner),
  // fall back to the first activated contract for the account.
  if (CONTRACT_ID) {
    const res = await u.sfQueryNode(
      sfCtx.instanceUrl, sfCtx.accessToken,
      `SELECT Id, ContractNumber FROM Contract WHERE Id = '${CONTRACT_ID}' LIMIT 1`,
      SF_API_VER
    );
    sharedContract = res.records?.[0] ?? null;
    if (!sharedContract) {
      console.log(`\n⚠️  Contract ${CONTRACT_ID} not found in Salesforce. Tests will skip.`);
      return;
    }
    // Remove any leftover draft amendments so QTC always auto-creates fresh
    // (the LWC shows a picker modal with no "Create New" when drafts exist).
    await deleteDraftAmendments(sharedContract.Id);
  } else {
    const candidates = await getActivatedContracts();
    if (!candidates.length) {
      console.log(`\n⚠️  No activated contracts found for "${ACCOUNT_NAME}". Tests will skip.`);
      return;
    }
    // No CONTRACT_ID → Mode 1 only; QTC will pick the first contract in its list
    // and sharedContract is resolved below from the created quote.
  }

  if (QUOTE_NAME && !CONTRACT_ID) {
    console.log(`\n⚠️  QUOTE_NAME requires CONTRACT_ID (Mode 2). Tests will skip.`);
    return;
  }

  // ── QTC flow — runs first ─────────────────────────────────────────────────
  const qtcCtx  = await browser.newContext();
  const qtcPage = await qtcCtx.newPage();
  try {
    if (QUOTE_NAME) {
      // Mode 2: open existing draft, update qty
      sharedQtcQuoteId = await openExistingQtcQuoteAndUpdateQty(
        qtcPage,
        /** @type {{Id: string, ContractNumber: string}} */ (sharedContract),
        QUOTE_NAME
      );
    } else {
      // Mode 1: create new amendment, update qty inline, save
      sharedQtcQuoteId = await createQtcAmendmentAndUpdateQty(qtcPage, sharedContract);
      // If no CONTRACT_ID, resolve sharedContract from the quote's master contract
      if (!sharedContract && sharedQtcQuoteId) {
        const quoteRes = await u.sfQueryNode(
          sfCtx.instanceUrl, sfCtx.accessToken,
          `SELECT SBQQ__MasterContract__c FROM SBQQ__Quote__c WHERE Id = '${sharedQtcQuoteId}' LIMIT 1`,
          SF_API_VER
        );
        const masterContractId = quoteRes.records?.[0]?.SBQQ__MasterContract__c;
        if (masterContractId) {
          const contractRes = await u.sfQueryNode(
            sfCtx.instanceUrl, sfCtx.accessToken,
            `SELECT Id, ContractNumber FROM Contract WHERE Id = '${masterContractId}' LIMIT 1`,
            SF_API_VER
          );
          sharedContract = contractRes.records?.[0] ?? null;
        }
      }
    }
    if (sharedQtcQuoteId && sharedContract) {
      console.log(
        `[${KIND}] QTC quote: ${sharedQtcQuoteId} via contract ${sharedContract.ContractNumber}` +
        (QUOTE_NAME ? ' (existing draft)' : ' (new amendment)')
      );
    }
  } catch (/** @type {any} */ err) {
    console.log(`[${KIND}] QTC flow failed: ${err?.message || String(err)}`);
    anomalies.push({ severity: 'HIGH', type: 'qtc-flow-error', detail: String(err?.message || err) });
  } finally {
    await qtcCtx.close();
  }

  if (!sharedQtcQuoteId || !sharedContract) {
    console.log(`\n⚠️  QTC flow failed or no contract resolved. Tests will skip.`);
    return;
  }
  console.log(`[${KIND}] Contract: ${sharedContract.ContractNumber} (${sharedContract.Id})`);

  // ── SF Standard flow — always creates a fresh amendment ──────────────────
  const stdCtx  = await browser.newContext();
  const stdPage = await stdCtx.newPage();
  try {
    sharedStdQuoteId = await createStdAmendmentViaUI(stdPage, sharedContract);
    if (sharedStdQuoteId) {
      console.log(`[${KIND}] SF Std quote: ${sharedStdQuoteId}`);
    } else if (stdFlowSkipReason) {
      console.log(`[${KIND}] SF Std blocked: ${stdFlowSkipReason}`);
      anomalies.push({ severity: 'HIGH', type: 'std-ui-flow-blocked', detail: stdFlowSkipReason || '' });
    }
  } catch (/** @type {any} */ err) {
    console.log(`[${KIND}] SF Std flow failed: ${err?.message || String(err)}`);
    anomalies.push({ severity: 'HIGH', type: 'std-ui-flow-error', detail: String(err?.message || err) });
  } finally {
    await stdCtx.close();
  }

  if (!sharedStdQuoteId) {
    console.log(`\n⚠️  SF Standard flow failed. Tests will skip.`);
    return;
  }

  // ── Fetch every queryable field for both quotes ───────────────────────────
  sharedStdQuote = await getQuoteRecord(sharedStdQuoteId);
  sharedQtcQuote = await getQuoteRecord(sharedQtcQuoteId);

  // CPQ computes header pricing fields (SBQQ__NetAmount__c etc.) asynchronously
  // after Save & Forecast. Poll until the value is non-zero so the pricing parity
  // test doesn't compare a fully-calculated QTC quote against an unpopulated one.
  {
    const POLL_INTERVAL_MS = 3_000;
    const POLL_TIMEOUT_MS  = 60_000;
    const deadline = Date.now() + POLL_TIMEOUT_MS;
    while (
      !sharedStdQuote['SBQQ__NetAmount__c'] &&
      Date.now() < deadline
    ) {
      await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
      sharedStdQuote = await getQuoteRecord(sharedStdQuoteId);
    }
    if (!sharedStdQuote['SBQQ__NetAmount__c']) {
      console.log(`[${KIND}] ⚠️  SF Std quote SBQQ__NetAmount__c still 0 after ${POLL_TIMEOUT_MS / 1000}s — CPQ may not have finished calculating`);
    }
  }

  sharedStdLines = await getQuoteLines(sharedStdQuoteId);
  sharedQtcLines = await getQuoteLines(sharedQtcQuoteId);
  console.log(`[${KIND}] SF Std:  ${Object.keys(sharedStdQuote).length} fields, ${sharedStdLines.length} lines`);
  console.log(`[${KIND}] QTC:     ${Object.keys(sharedQtcQuote).length} fields, ${sharedQtcLines.length} lines`);

  // ── Qty update tracking ────────────────────────────────────────────────────
  // Both flows set qtyUpdateOldQty / qtyUpdateNewQty as side effects (SF Standard
  // runs last so its value is canonical). Resolve the product by matching the new
  // qty in the SF Standard lines.
  if (qtyUpdateNewQty != null) {
    const _newQty = qtyUpdateNewQty;
    const targetLine =
      sharedStdLines.find(l => l.SBQQ__Product__c && Math.abs(Number(l.SBQQ__Quantity__c) - _newQty) < 0.001) ||
      sharedStdLines.find(l => l.SBQQ__Product__c && Number(l.SBQQ__Quantity__c) > 0);
    if (targetLine) {
      qtyUpdateProductId = targetLine.SBQQ__Product__c;
      const prodRes = await u.sfQueryNode(
        sfCtx.instanceUrl, sfCtx.accessToken,
        `SELECT Name FROM Product2 WHERE Id = '${qtyUpdateProductId}' LIMIT 1`,
        SF_API_VER
      );
      qtyUpdateProductName = prodRes.records?.[0]?.Name ?? qtyUpdateProductId;
      qtyUpdateDone = true;
      console.log(`[${KIND}] Qty update: "${qtyUpdateProductName}" ${qtyUpdateOldQty} → ${qtyUpdateNewQty}`);
    }
  }

  stdLinesAfterQtyUpdate = await getQuoteLines(sharedStdQuoteId);
  qtcLinesAfterQtyUpdate = await getQuoteLines(sharedQtcQuoteId);
  console.log(`[${KIND}] Lines after qty update — SF Std=${stdLinesAfterQtyUpdate.length}, QTC=${qtcLinesAfterQtyUpdate.length}`);
});

// ── afterAll ──────────────────────────────────────────────────────────────────
test.afterAll(async () => {
  if (!runDir) return;

  const stdQuoteName = sharedStdQuote?.Name || null;
  const qtcQuoteName = sharedQtcQuote?.Name || null;

  // Header field rows for the UI↔DB cross-check tab
  const headerKeys = Array.from(new Set([
    ...Object.keys(sharedStdQuote || {}),
    ...Object.keys(sharedQtcQuote || {}),
  ]));
  /** @type {any[]} */
  const uiDbCrossCheck = [];
  let idx = 0;
  for (const key of headerKeys) {
    if (ALWAYS_SKIP_FIELDS.has(key)) continue;
    const stdVal = sharedStdQuote?.[key];
    const qtcVal = sharedQtcQuote?.[key];
    if ((stdVal == null || stdVal === '') && (qtcVal == null || qtcVal === '')) continue;
    const match = fieldsEqual(stdVal, qtcVal);
    idx += 1;
    uiDbCrossCheck.push({
      uiIndex:  idx,
      product:  key,
      segOcc:   null,
      uiBefore: null,
      uiAfter:  stdVal != null ? String(stdVal) : null,
      dbPrior:  null,
      dbAfter:  qtcVal != null ? String(qtcVal) : null,
      match, hasData: true,
    });
  }

  // Line-level rows
  for (let i = 0; i < Math.max(sharedStdLines.length, sharedQtcLines.length); i++) {
    const stdLine = sharedStdLines[i] || {};
    const qtcLine = sharedQtcLines[i] || {};
    const stdPrice = stdLine.SBQQ__NetPrice__c ?? null;
    const qtcPrice = qtcLine.SBQQ__NetPrice__c ?? null;
    const match    = stdPrice != null && qtcPrice != null &&
                     Math.abs(Number(stdPrice) - Number(qtcPrice)) < 0.01;
    idx += 1;
    uiDbCrossCheck.push({
      uiIndex:  idx,
      product:  `line[${i}] ${stdLine.SBQQ__Product__c || qtcLine.SBQQ__Product__c || ''}`.trim(),
      segOcc:   null,
      uiBefore: null,
      uiAfter:  stdPrice != null ? String(stdPrice) : null,
      dbPrior:  null,
      dbAfter:  qtcPrice != null ? String(qtcPrice) : null,
      match, hasData: stdPrice != null || qtcPrice != null,
    });
  }
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;

  const dbComparison = buildSideBySideRows(sharedStdLines, sharedQtcLines);

  const passed = anomalies.filter(a => a.severity === 'HIGH').length === 0 &&
                 testFindings.every(t => t.passed);

  buildRichResults({
    kind:           KIND,
    runTs, runDir, testStartMs,
    accountName:    ACCOUNT_NAME,
    scenarioNumber: 1,
    scenarioLabel:  'SF Standard CPQ UI vs AgenticQTC UI — full-field amendment parity',
    contract:       sharedContract?.ContractNumber || null,
    quoteName:      stdQuoteName,
    quoteId:        sharedStdQuoteId,
    dbLineCount:    sharedStdLines.length,
    dbComparison,
    dbAnomalies:    anomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed,
    extra: {
      stdQuoteId:             sharedStdQuoteId,
      qtcQuoteId:             sharedQtcQuoteId,
      stdQuoteName,
      qtcQuoteName,
      stdLineCount:           sharedStdLines.length,
      qtcLineCount:           sharedQtcLines.length,
      fieldsComparedPerQuote: Object.keys(sharedStdQuote).length,
      testFindings,
      qtyUpdate: {
        productId:          qtyUpdateProductId,
        productName:        qtyUpdateProductName,
        oldQty:             qtyUpdateOldQty,
        newQty:             qtyUpdateNewQty,
        done:               qtyUpdateDone,
        stdLinesAfterCount: stdLinesAfterQtyUpdate.length,
        qtcLinesAfterCount: qtcLinesAfterQtyUpdate.length,
      },
    },
  });

  console.log(`\n[${KIND}] Wrote ${path.join(runDir, 'results.json')}`);
});

// ── UI flows ──────────────────────────────────────────────────────────────────

/**
 * Drive the full Salesforce standard CPQ amendment flow through the browser UI:
 *
 *   1. Contract record page → click "Amend" action button
 *   2. "Contract: Amend" modal → verify Amendment Start Date is populated → click "Next"
 *   3. Subscription-selection page ("Amend Contract") → click "Amend"
 *   4. CPQ opens new amendment quote → click "Save & Forecast" to complete the amendment
 *   5. Extract the finalized quote ID from the URL or SOQL
 *
 * @param {import('@playwright/test').Page} page
 * @param {{Id: string, ContractNumber: string}} contract
 * @returns {Promise<string | null>}
 */
async function createStdAmendmentViaUI(page, contract) {
  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken);

  // Navigate to the Contract record — 'commit' survives Lightning's redirect chains
  await page.goto(`${sfCtx.lightningUrl}/lightning/r/Contract/${contract.Id}/view`,
    { waitUntil: 'commit' }
  ).catch(() => {});

  // Wait until the "Amend" action button is visible (record page has fully rendered)
  await page.locator('[title="Amend"]').waitFor({ state: 'visible', timeout: 60000 });
  await u.screenshot(page, runDir, 'std-01-contract-page');

  const beforeTs = new Date().toISOString();

  // ── Step 1: click "Amend" on the Contract record ─────────────────────────
  await page.locator('[title="Amend"]').click();
  await u.screenshot(page, runDir, 'std-02-amend-clicked');

  // ── Step 2: "Contract: Amend" modal ──────────────────────────────────────
  // Wait for the modal title to appear — this is the reliable signal the modal
  // has fully rendered. ".modal-container" / "[role=dialog]" are unreliable in
  // Salesforce Lightning; the heading text is unique and always present.
  await page.getByText('Contract: Amend').waitFor({ state: 'visible', timeout: 15000 });
  await u.screenshot(page, runDir, 'std-02-modal-open');

  // The modal body shows one of two things:
  //   A) Amendment Start Date field + "Next" button  →  proceed
  //   B) "Services Only Contracts cannot be Amended." error  →  skip entire suite
  // Modal is open — synchronous isVisible() check is enough (no extra wait needed).
  const blockerVisible = await page.getByText('Services Only', { exact: false }).isVisible().catch(() => false);
  if (blockerVisible) {
    stdFlowSkipReason =
      `Contract ${contract.ContractNumber} (${contract.Id}): ` +
      `"Services Only Contracts cannot be Amended."`;
    console.log(`\n[${KIND}] ⚠️  SKIP — ${stdFlowSkipReason}`);
    await u.screenshot(page, runDir, `std-02-amend-blocked-${contract.ContractNumber}`);

    // Dismiss the modal so the browser is in a clean state for the next attempt.
    const cancelBtn = page.getByRole('button', { name: /cancel/i }).first();
    const closeBtn  = page.locator('[title="Close"], button.slds-modal__close').first();
    if (await u.isVisibleSafe(cancelBtn, 2_000)) {
      await cancelBtn.click();
    } else if (await u.isVisibleSafe(closeBtn, 2_000)) {
      await closeBtn.click();
    }
    return null;
  }

  // Modal has the date form — "Next" button should already be visible
  const nextBtn = page.getByRole('button', { name: 'Next' });
  await nextBtn.waitFor({ state: 'visible', timeout: 10000 });

  const startDateInput = page.locator('input[name="amendmentStartDate"], lightning-input[data-id="amendmentStartDate"] input, .modal-container input').first();
  const startDateValue = await startDateInput.inputValue().catch(() => '');
  if (!startDateValue) {
    // Field is empty — fill with today's date in the format Salesforce expects
    await u.fillAndTab(startDateInput, u.formatDateUS(new Date()));
  }
  await u.screenshot(page, runDir, 'std-03-amend-modal');
  await nextBtn.click();

  // ── Step 3: Subscription-selection page ("Amend Contract") ───────────────
  // After "Next", Lightning navigates to one.app which hosts the CPQ AmendContract
  // Visualforce page (served from *.vf.force.com) inside an <iframe>.
  // Every element on that page — heading, subscription table, buttons — lives inside
  // the iframe. page.getByText() / page.locator() on the main document won't find
  // them. frameLocator() pierces the iframe boundary (works cross-origin too).
  const vfFrame = page.frameLocator('iframe');
  await vfFrame.locator('input.sbBtn[value="Amend"]').waitFor({ state: 'visible', timeout: 60000 });
  await u.screenshot(page, runDir, 'std-04-subscription-page');

  // Listen for a new tab before clicking (CPQ sometimes opens the quote in a new tab)
  const newTabPromise = page.context().waitForEvent('page', { timeout: 30000 });

  await vfFrame.locator('input.sbBtn[value="Amend"]').click();
  await u.screenshot(page, runDir, 'std-05-subscription-amend-clicked');

  // ── Step 4: Update quantity then Save & Forecast ─────────────────────────
  // CPQ may open the QLE in a new tab (standalone VF page) or embedded inside
  // the Lightning shell as iframe[name^="vfFrameId_"]. Race both contexts for
  // the "Save & Forecast" button so we handle whichever variant loads.
  const newTab = await newTabPromise.catch(() => null);
  /** @type {import('@playwright/test').Page} */
  const editorPage = newTab || page;

  if (newTab) {
    await newTab.waitForLoadState('domcontentloaded', { timeout: 90_000 }).catch(() => {});
    await u.screenshot(newTab, runDir, 'std-06-editor-newtab');
  } else {
    await u.screenshot(page, runDir, 'std-06-editor-sametab');
  }

  // Race: VF iframe (Lightning-embedded) vs main frame (standalone VF page).
  const vfCtx       = editorPage.frameLocator('iframe[name^="vfFrameId_"]');
  const vfSaveBtn   = vfCtx.getByRole('button', { name: /save\s*[&and]+\s*forecast/i });
  const mainSaveBtn = editorPage.getByRole('button', { name: /save\s*[&and]+\s*forecast/i });
  const whichSave   = await u.waitForAny([vfSaveBtn, mainSaveBtn], 60_000);
  const inIframe    = whichSave === 0;
  const editorRoot  = inIframe ? vfCtx : editorPage;
  const saveAndForecastBtn = whichSave === 0 ? vfSaveBtn : (whichSave === 1 ? mainSaveBtn : null);

  if (saveAndForecastBtn) {
    await u.screenshot(editorPage, runDir, 'std-07-editor-ready');

    // ── Update a product quantity BEFORE Save & Forecast ──────────────────
    // Strategy: try MDQ path first (sf-le-table-row + expand), then fall back
    // to non-MDQ path (direct editable cell click). Both paths write to the
    // same #myinput / textbox once the cell is in edit mode.
    try {
      let qtyInputFound = false;

      // ── Path A: MDQ product (sf-le-table-row with expand icon) ───────────
      const firstRow = editorRoot.locator('sf-le-table-row').first();
      if (await u.isVisibleSafe(firstRow, 5_000)) {
        await firstRow.locator('#expandCollapseIcon').click();
        await editorPage.waitForTimeout(1_000);

        // sb-le-table-cell is the MDQ cell component; .editable.numericField is the
        // fallback for non-component VF cells.
        const qtyCell    = editorRoot.locator('sb-le-table-cell').filter({ hasText: /^Quantity$/i }).locator('#formatted').first();
        const editableNf = editorRoot.locator('.editable.numericField').first();

        if (await u.isVisibleSafe(qtyCell, 3_000)) {
          await qtyCell.click();
          await editorPage.waitForTimeout(500);
        } else if (await u.isVisibleSafe(editableNf, 3_000)) {
          await editableNf.click();
          await editorPage.waitForTimeout(500);
        }

        const qtyInput = editorRoot.locator('#tableContainer #myinput')
          .or(editorRoot.locator('#tableContainer').getByRole('textbox'))
          .or(editorRoot.locator('#tableContainer input[type="text"]'));
        if (await u.isVisibleSafe(qtyInput, 5_000)) {
          const raw = await qtyInput.inputValue().catch(() => '1');
          qtyUpdateOldQty = parseFloat(raw) || 1;
          qtyUpdateNewQty = qtyUpdateOldQty + 5;
          await qtyInput.fill(String(qtyUpdateNewQty));
          await editorRoot.locator('#mainPanel').click();
          await editorPage.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {});
          await editorPage.waitForTimeout(800);
          qtyInputFound = true;
          console.log(`[${KIND}] CPQ qty (MDQ path): ${qtyUpdateOldQty} → ${qtyUpdateNewQty}`);
          await u.screenshot(editorPage, runDir, 'std-08-qty-updated');
        }
      }

      // ── Path B: Non-MDQ product (direct editable cell, no expand needed) ─
      if (!qtyInputFound) {
        console.log(`[${KIND}] MDQ path skipped — trying non-MDQ editable cell`);
        const directCell = editorRoot.locator('td.editable').first();
        if (await u.isVisibleSafe(directCell, 3_000)) {
          await directCell.click();
          await editorPage.waitForTimeout(500);
        }
        const qtyInput2 = editorRoot.locator('#myinput')
          .or(editorRoot.getByRole('textbox').first());
        if (await u.isVisibleSafe(qtyInput2, 5_000)) {
          const raw2 = await qtyInput2.inputValue().catch(() => '1');
          qtyUpdateOldQty = parseFloat(raw2) || 1;
          qtyUpdateNewQty = qtyUpdateOldQty + 5;
          await qtyInput2.fill(String(qtyUpdateNewQty));
          const mainPanel = editorRoot.locator('#mainPanel, #container, .container').first();
          await u.clickIfVisible(mainPanel, 2_000);
          await editorPage.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {});
          await editorPage.waitForTimeout(800);
          qtyInputFound = true;
          console.log(`[${KIND}] CPQ qty (non-MDQ path): ${qtyUpdateOldQty} → ${qtyUpdateNewQty}`);
          await u.screenshot(editorPage, runDir, 'std-08-qty-updated');
        }
      }

      if (!qtyInputFound) {
        console.log(`[${KIND}] qty input not found in MDQ or non-MDQ path — proceeding to Save & Forecast`);
      }
    } catch (/** @type {any} */ qtyErr) {
      console.log(`[${KIND}] Pre-save qty update error (will still save): ${qtyErr?.message || qtyErr}`);
    }

    // ── Save & Forecast ────────────────────────────────────────────────────
    await saveAndForecastBtn.click();
    await u.screenshot(editorPage, runDir, 'std-09-save-forecast-clicked');
    await editorPage.waitForLoadState('domcontentloaded', { timeout: 30_000 }).catch(() => {});
    await u.screenshot(editorPage, runDir, 'std-10-save-complete');
  } else {
    console.log(`[${KIND}] "Save & Forecast" button not found in VF iframe or main frame`);
    await u.screenshot(editorPage, runDir, 'std-07-no-save-btn');
  }

  // ── Step 5: extract the finalized quote ID ────────────────────────────────

  // Try the editor page URL first
  const idFromUrl = extractQuoteIdFromUrl(editorPage.url());
  if (idFromUrl) return idFromUrl;

  // SOQL fallback — reliable regardless of URL structure
  console.log(`[${KIND}] URL parse yielded no quote ID — falling back to SOQL`);
  const res = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id, Name FROM SBQQ__Quote__c
       WHERE SBQQ__MasterContract__c = '${contract.Id}'
         AND SBQQ__Type__c = 'Amendment'
         AND CreatedDate > ${beforeTs}
       ORDER BY CreatedDate DESC LIMIT 1`,
    SF_API_VER
  );
  const fallbackId = res.records?.[0]?.Id ?? null;
  if (!fallbackId) {
    anomalies.push({
      severity: 'HIGH',
      type: 'std-amendment-not-found',
      detail: `SF standard UI amendment for contract ${contract.Id} produced no detectable quote (SOQL also returned 0 rows).`,
    });
  }
  return fallbackId;
}

/**
 * Extract a Salesforce record ID from a URL string.
 * Handles: VF CPQ editor (?id=…), Lightning record pages, hash-based routing.
 *
 * @param {string} url
 * @returns {string | null}
 */
function extractQuoteIdFromUrl(url) {
  if (!url) return null;
  try {
    const u2 = new URL(url);
    // VF CPQ editor: /apex/SBQQ__sb?scontrolCaching=1&id=0Q0XXXXXX
    const vfId = u2.searchParams.get('id');
    if (vfId && vfId.length >= 15) return vfId;
    // Lightning record page: /lightning/r/SBQQ__Quote__c/0Q0XXX/view
    const lMatch = url.match(/SBQQ__Quote__c\/([0-9A-Za-z]{15,18})/);
    if (lMatch) return lMatch[1];
    // Hash-based CPQ routing: #quote/0Q0XXXXX or #Amendment/0Q0XXXXX
    const hash = u2.hash;
    if (hash) {
      const hMatch = hash.match(/\/([0-9A-Za-z]{15,18})/);
      if (hMatch) return hMatch[1];
    }
    // Generic quoteId query param
    const qId = u2.searchParams.get('quoteId');
    if (qId && qId.length >= 15) return qId;
  } catch (_) { /* invalid URL */ }
  return null;
}

/**
 * Mode 1: Navigate to QTC, create a NEW amendment quote for the given contract
 * (or the first contract in QTC's own list when contract is null), update the
 * first product's quantity by +5 inline, save, and return the new quote ID.
 *
 * Sets `qtyUpdateOldQty` and `qtyUpdateNewQty` as side effects.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{Id: string, ContractNumber: string} | null} contract
 * @returns {Promise<string | null>}
 */
async function createQtcAmendmentAndUpdateQty(page, contract) {
  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken).catch(() => {});
  const qtc = new AgenticQtcPage(page, sfCtx);
  await qtc.goto();
  await u.screenshot(page, runDir, 'qtc-01-home');

  await qtc.searchAndSelectAccount(ACCOUNT_SEARCH, ACCOUNT_NAME);
  await u.screenshot(page, runDir, 'qtc-02-account-selected');

  // If a specific contract ID was provided, click it by ID; otherwise let QTC
  // pick the first contract from its own "Active Contracts" list.
  if (contract && CONTRACT_ID) {
    await qtc.clickContractById(contract.Id, 60_000);
  } else {
    await qtc.clickContractByIndex(0, 60_000);
  }
  const outcome = await qtc.waitForContractClickOutcome(60_000);
  console.log(`[${KIND}] QTC contract click outcome: ${outcome}`);
  await u.screenshot(page, runDir, 'qtc-03-after-contract-click');

  if (outcome === 'timeout') {
    anomalies.push({
      severity: 'HIGH',
      type: 'qtc-contract-click-timeout',
      detail: 'QTC did not open an editor or modal after clicking the contract',
    });
    return null;
  }

  if (outcome === 'modal') {
    // The pre-flight cleanup in beforeAll should have deleted all stale drafts so
    // QTC never reaches this branch in normal operation. If we land here anyway
    // (e.g. another process created a draft after cleanup), abort rather than
    // silently opening a stale draft — that would bake the wrong qty into the
    // comparison and produce a misleading failure.
    anomalies.push({
      severity: 'HIGH',
      type: 'qtc-modal-stale-drafts',
      detail: 'Draft picker modal appeared despite pre-flight cleanup — stale draft amendments still present on contract',
    });
    console.log(`[${KIND}] ⚠️  Draft picker modal appeared unexpectedly — aborting QTC flow`);
    return null;
  }

  // Wait for lines (spinbuttons) to appear in the editor
  const lineCount = await qtc.waitForLines(90_000);
  await u.screenshot(page, runDir, 'qtc-05-editor-ready');
  if (lineCount === 0) {
    anomalies.push({
      severity: 'HIGH',
      type: 'qtc-no-lines',
      detail: 'QTC editor opened but no quantity spinbuttons were found within 90s',
    });
    return null;
  }

  // Read the first spinbutton qty, add 5, fill and commit
  const sb = page.getByRole('spinbutton').first();
  const rawQty = await sb.inputValue().catch(() => '1');
  qtyUpdateOldQty = parseFloat(rawQty) || 1;
  qtyUpdateNewQty = qtyUpdateOldQty + 5;
  await sb.click({ clickCount: 3 });
  await sb.fill(String(qtyUpdateNewQty));
  await sb.press('Tab');
  await page.waitForTimeout(1_500);
  console.log(`[${KIND}] QTC qty update: ${qtyUpdateOldQty} → ${qtyUpdateNewQty}`);
  await u.screenshot(page, runDir, 'qtc-06-qty-updated');

  await qtc.save(90_000, 2_000);
  await u.screenshot(page, runDir, 'qtc-07-saved');

  const quoteName = await qtc.getQuoteName(30_000);
  if (!quoteName) {
    anomalies.push({
      severity: 'HIGH',
      type: 'qtc-quote-name-not-found',
      detail: 'QTC editor saved but the quote name was not found in the header within 30s',
    });
    return null;
  }
  console.log(`[${KIND}] QTC new quote name: ${quoteName}`);

  const res = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id FROM SBQQ__Quote__c WHERE Name = '${escapeSoql(quoteName)}' LIMIT 1`,
    SF_API_VER
  );
  const quoteId = res.records?.[0]?.Id ?? null;
  if (!quoteId) {
    anomalies.push({
      severity: 'HIGH',
      type: 'qtc-quote-id-not-found',
      detail: `SOQL found no SBQQ__Quote__c with Name = '${quoteName}'`,
    });
  }
  return quoteId;
}

/**
 * Mode 2: Navigate to QTC, open the EXISTING draft quote identified by
 * `quoteName` for the given contract, update the first product's quantity
 * by +5 inline, save, and return the quote ID.
 *
 * Sets `qtyUpdateOldQty` and `qtyUpdateNewQty` as side effects.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{Id: string, ContractNumber: string}} contract
 * @param {string} quoteName  Q-NNNNN label of the existing draft quote to open.
 * @returns {Promise<string | null>}
 */
async function openExistingQtcQuoteAndUpdateQty(page, contract, quoteName) {
  await loginViaCookie(page, sfCtx.lightningUrl, sfCtx.accessToken).catch(() => {});
  const qtc = new AgenticQtcPage(page, sfCtx);
  await qtc.goto();
  await u.screenshot(page, runDir, 'qtc-01-home');

  await qtc.searchAndSelectAccount(ACCOUNT_SEARCH, ACCOUNT_NAME);
  await u.screenshot(page, runDir, 'qtc-02-account-selected');

  await qtc.clickContractById(contract.Id, 60_000);
  const outcome = await qtc.waitForContractClickOutcome(60_000);
  console.log(`[${KIND}] QTC contract click outcome: ${outcome}`);
  await u.screenshot(page, runDir, 'qtc-03-after-contract-click');

  if (outcome === 'timeout') {
    throw new Error(
      `QTC did not open an editor or modal after clicking contract ${contract.ContractNumber}`
    );
  }

  if (outcome === 'modal') {
    // DOM confirmed: tr.quote-row > td.quote-name-cell (lwc synthetic shadow, flat DOM).
    // Wait for at least one row to appear, then find the named one by its name cell.
    await page.locator('tr.quote-row').first().waitFor({ state: 'visible', timeout: 20_000 });
    const targetRow = page.locator('tr.quote-row').filter({
      has: page.locator('td.quote-name-cell').filter({ hasText: quoteName }),
    }).first();
    await targetRow.waitFor({ state: 'visible', timeout: 10_000 }).catch(async () => {
      const allNames = await page.locator('td.quote-name-cell').allTextContents().catch(() => []);
      throw new Error(
        `Draft quote "${quoteName}" not found in modal. Available: ${JSON.stringify(allNames)}`
      );
    });
    await targetRow.click();
    await u.screenshot(page, runDir, 'qtc-04-modal-actioned');
  }

  if (outcome === 'editor') {
    const openedName = await qtc.getQuoteName(15_000);
    if (openedName && openedName !== quoteName) {
      throw new Error(
        `QTC opened quote "${openedName}" but expected "${quoteName}".`
      );
    }
  }

  const lineCount = await qtc.waitForLines(90_000);
  await u.screenshot(page, runDir, 'qtc-05-editor-ready');
  if (lineCount === 0) {
    throw new Error('QTC editor opened but no quantity spinbuttons were found within 90s');
  }

  // Read the first spinbutton qty, add 5, fill and commit
  const sb = page.getByRole('spinbutton').first();
  const rawQty = await sb.inputValue().catch(() => '1');
  qtyUpdateOldQty = parseFloat(rawQty) || 1;
  qtyUpdateNewQty = qtyUpdateOldQty + 5;
  await sb.click({ clickCount: 3 });
  await sb.fill(String(qtyUpdateNewQty));
  await sb.press('Tab');
  await page.waitForTimeout(1_500);
  console.log(`[${KIND}] QTC qty update: ${qtyUpdateOldQty} → ${qtyUpdateNewQty}`);
  await u.screenshot(page, runDir, 'qtc-06-qty-updated');

  await qtc.save(90_000, 2_000);
  await u.screenshot(page, runDir, 'qtc-07-saved');

  // Resolve the quote ID by name (name is already known)
  const res = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id FROM SBQQ__Quote__c WHERE Name = '${escapeSoql(quoteName)}' LIMIT 1`,
    SF_API_VER
  );
  const quoteId = res.records?.[0]?.Id ?? null;
  if (!quoteId) {
    throw new Error(`SOQL found no SBQQ__Quote__c with Name = '${quoteName}'`);
  }
  console.log(`[${KIND}] QTC existing quote ID: ${quoteId}`);
  return quoteId;
}

// ── Discovery + SOQL helpers ──────────────────────────────────────────────────

/**
 * Return all Activated / In-Force contracts for the configured account,
 * ordered newest-first so callers can iterate and pick the first one that
 * the SF Standard CPQ "Amend" flow accepts (some contracts are Services-Only
 * and cannot be amended via the standard UI).
 *
 * @returns {Promise<Array<{Id: string, ContractNumber: string}>>}
 */
async function getActivatedContracts() {
  const accRes = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id FROM Account WHERE Name = '${escapeSoql(ACCOUNT_NAME)}' LIMIT 1`,
    SF_API_VER
  );
  const accountId = accRes.records?.[0]?.Id;
  if (!accountId) throw new Error(`Account "${ACCOUNT_NAME}" not found`);

  const contractRes = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id, ContractNumber, Status, StartDate, EndDate
       FROM Contract
       WHERE AccountId = '${accountId}'
       ORDER BY StartDate DESC LIMIT 10`,
    SF_API_VER
  );
  const all = contractRes.records || [];
  return all.filter(/** @param {any} c */ c => ['Activated', 'In Force'].includes(c.Status));
}

/**
 * Delete all draft amendment quotes for a contract so the QTC flow always
 * starts clean. The LWC shows a picker modal (no "Create New" option) when
 * drafts exist — deleting them beforehand ensures outcome is always 'editor'.
 * @param {string} contractId
 */
async function deleteDraftAmendments(contractId) {
  const res = await u.sfQueryNode(
    sfCtx.instanceUrl, sfCtx.accessToken,
    `SELECT Id, Name FROM SBQQ__Quote__c
       WHERE SBQQ__MasterContract__c = '${contractId}'
         AND SBQQ__Type__c = 'Amendment'
         AND SBQQ__Status__c = 'Draft'`,
    SF_API_VER
  );
  for (const rec of res.records ?? []) {
    const resp = await fetch(
      `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/sobjects/SBQQ__Quote__c/${rec.Id}`,
      { method: 'DELETE', headers: { Authorization: `Bearer ${sfCtx.accessToken}` } }
    );
    if (resp.status === 204) {
      console.log(`[${KIND}] Deleted stale draft amendment ${rec.Name} (${rec.Id})`);
    } else {
      console.log(`[${KIND}] ⚠️  Could not delete draft ${rec.Id} — HTTP ${resp.status}`);
    }
  }
}

/** @param {string} objectName */
async function describeQueryableFields(objectName) {
  if (describeCache[objectName]) return describeCache[objectName];
  const response = await fetch(
    `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/sobjects/${objectName}/describe`,
    { headers: { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' } }
  );
  if (!response.ok) throw new Error(`Describe ${objectName} failed: ${response.statusText}`);
  const data = await response.json();
  /** @type {string[]} */
  const fields = (data.fields || [])
    .filter(/** @param {any} f */ f => f.type !== 'address' && f.type !== 'location')
    .map(/** @param {any} f */ f => f.name);
  describeCache[objectName] = fields;
  return fields;
}

/**
 * Fetch all fields in 40-field chunks and merge by Id.
 * Needed because SBQQ__Quote__c has 200+ fields — a single SELECT blows the URL limit.
 *
 * @param {string} objectName
 * @param {string[]} fields
 * @param {string} whereClause
 * @param {string} [orderBy]
 */
async function fetchAllFieldsChunked(objectName, fields, whereClause, orderBy) {
  const CHUNK_SIZE = 40;
  /** @type {Map<string, Record<string, any>>} */
  const merged = new Map();
  for (let i = 0; i < fields.length; i += CHUNK_SIZE) {
    const chunk = fields.slice(i, i + CHUNK_SIZE);
    if (!chunk.includes('Id')) chunk.unshift('Id');
    const orderClause = orderBy ? ` ORDER BY ${orderBy}` : '';
    const soql = `SELECT ${chunk.join(', ')} FROM ${objectName} WHERE ${whereClause}${orderClause}`;
    const res = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql, SF_API_VER);
    if (res.error) throw new Error(`SOQL chunk failed (${objectName}): ${res.error}`);
    for (const rec of res.records) {
      merged.set(rec.Id, { ...(merged.get(rec.Id) || {}), ...rec });
    }
  }
  return Array.from(merged.values());
}

/** @param {string} quoteId */
async function getQuoteRecord(quoteId) {
  const fields = await describeQueryableFields('SBQQ__Quote__c');
  const records = await fetchAllFieldsChunked('SBQQ__Quote__c', fields, `Id = '${quoteId}'`);
  return records[0] || {};
}

/** @param {string} quoteId */
async function getQuoteLines(quoteId) {
  const fields = await describeQueryableFields('SBQQ__QuoteLine__c');
  const records = await fetchAllFieldsChunked(
    'SBQQ__QuoteLine__c', fields,
    `SBQQ__Quote__c = '${quoteId}'`,
    'SBQQ__Number__c ASC NULLS LAST'
  );
  records.sort((a, b) => (a.SBQQ__Number__c ?? 0) - (b.SBQQ__Number__c ?? 0));
  return records;
}

// ── Field comparison ──────────────────────────────────────────────────────────

/**
 * @typedef {Object} FieldDiff
 * @property {string} field
 * @property {any} std
 * @property {any} qtc
 * @property {'structural'|'valueDiff'} kind
 */

/**
 * @param {Record<string, any>} std
 * @param {Record<string, any>} qtc
 * @param {{ onlyFields?: string[] }} [opts]
 * @returns {FieldDiff[]}
 */
function compareFields(std, qtc, opts = {}) {
  /** @type {FieldDiff[]} */
  const diffs = [];
  const keys = opts.onlyFields
    ? opts.onlyFields
    : Array.from(new Set([...Object.keys(std || {}), ...Object.keys(qtc || {})]));

  for (const key of keys) {
    if (ALWAYS_SKIP_FIELDS.has(key)) continue;
    const stdVal = std?.[key];
    const qtcVal = qtc?.[key];
    if (fieldsEqual(stdVal, qtcVal)) continue;
    const stdHas = stdVal != null && stdVal !== '';
    const qtcHas = qtcVal != null && qtcVal !== '';
    const kind = (stdHas && !qtcHas) ? 'structural' : 'valueDiff';
    diffs.push({ field: key, std: stdVal, qtc: qtcVal, kind });
  }
  return diffs;
}

/** @param {any} a @param {any} b */
function fieldsEqual(a, b) {
  if (a == null && b == null) return true;
  if ((a == null) !== (b == null)) return false;
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 0.01;
  return a === b;
}

/** @param {any} v */
function formatVal(v) {
  if (v == null) return '(null)';
  if (typeof v === 'string') return `"${v}"`;
  if (typeof v === 'number') return v.toFixed(2);
  return String(v);
}

/** @param {string} s */
function escapeSoql(s) { return s.replace(/'/g, "\\'"); }

/**
 * @template T
 * @param {T[]} arr
 * @param {(item: T) => string | null | undefined} keyFn
 */
function indexBy(arr, keyFn) {
  /** @type {Record<string, T>} */
  const out = {};
  for (const item of arr) {
    const k = keyFn(item);
    if (k) out[k] = item;
  }
  return out;
}

/**
 * @param {Array<Record<string, any>>} std
 * @param {Array<Record<string, any>>} qtc
 */
function buildSideBySideRows(std, qtc) {
  const max = Math.max(std.length, qtc.length);
  /** @type {any[]} */
  const rows = [];
  for (let i = 0; i < max; i++) {
    const s = std[i] || {};
    const q = qtc[i] || {};
    rows.push({
      index:        i + 1,
      product:      s.SBQQ__Product__c || q.SBQQ__Product__c || '—',
      segKey:       '—',
      segIndex:     null,
      priorQty:     s.SBQQ__Quantity__c ?? null,
      dbQty:        q.SBQQ__Quantity__c ?? null,
      dbPrice:      s.SBQQ__NetPrice__c ?? null,
      dbListPrice:  s.SBQQ__ListPrice__c ?? null,
      dbDiscount:   s.SBQQ__Discount__c ?? null,
      dbNetTotal:   q.SBQQ__NetTotal__c ?? null,
      dbAcv:        null, dbTcv: null,
      isBundle:     false,
      startDate:    s.SBQQ__EffectiveStartDate__c ?? null,
      endDate:      s.SBQQ__EffectiveEndDate__c ?? null,
      pricingMethod: null, term: null, regularPrice: null,
    });
  }
  return rows;
}

/**
 * @param {string} testName
 * @param {FieldDiff[]} diffs
 * @param {{ structuralSeverity?: 'HIGH'|'MEDIUM'|'LOW', valueSeverity?: 'HIGH'|'MEDIUM'|'LOW' }} [opts]
 */
function recordDiffs(testName, diffs, opts = {}) {
  const structuralSev = opts.structuralSeverity || 'HIGH';
  const valueSev      = opts.valueSeverity      || 'MEDIUM';
  for (const d of diffs) {
    anomalies.push({
      severity: d.kind === 'structural' ? structuralSev : valueSev,
      type:     `${testName} · ${d.kind}`,
      detail:   `${d.field} — SF Std=${formatVal(d.std)} AgenticQTC=${formatVal(d.qtc)}`,
    });
  }
}

/** @returns {boolean} */
function fixtureReady() {
  return !!(sharedContract && sharedStdQuoteId && sharedQtcQuoteId);
}

/** @returns {boolean} */
function qtyUpdateReady() {
  return fixtureReady() && qtyUpdateDone && qtyUpdateProductId != null;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test('Setup: account, contract, and SF Std / AgenticQTC quote pair via UI', async () => {
  if (!sharedContract) {
    test.skip(true, `No activated contracts found for "${ACCOUNT_NAME}".`);
    return;
  }

  console.log(`✓ Account:          ${ACCOUNT_NAME}`);
  console.log(`✓ Contract:         ${sharedContract.ContractNumber} (${sharedContract.Id})`);
  console.log(`✓ SF Std Quote:     ${sharedStdQuoteId}`);
  console.log(`✓ AgenticQTC Quote: ${sharedQtcQuoteId}`);
  console.log(`✓ Lines: SF Std=${sharedStdLines.length}, AgenticQTC=${sharedQtcLines.length}`);

  // If either flow could not produce a quote (blocked contract, navigation failure, etc.)
  // skip all comparison tests — this is an environment/data issue, not a test failure.
  if (!sharedStdQuoteId || !sharedQtcQuoteId) {
    const reason = stdFlowSkipReason ||
      `One or both UI amendment flows did not produce a quote. ` +
      `SF Std=${sharedStdQuoteId ?? 'null'}, AgenticQTC=${sharedQtcQuoteId ?? 'null'}. ` +
      `Check the run screenshots in ${runDir} for details.`;
    test.skip(true, reason);
    return;
  }

  testFindings.push({ testName: 'Setup', passed: true, diffCount: 0 });
});

test('Quote header — full field parity (all queryable fields)', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');
  test.slow();

  const diffs      = compareFields(sharedStdQuote, sharedQtcQuote);
  const structural = diffs.filter(d => d.kind === 'structural');

  console.log(
    `Quote header — ${Object.keys(sharedStdQuote).length} fields compared, ` +
    `${structural.length} structural, ${diffs.length - structural.length} valueDiffs`
  );
  recordDiffs('quote header', diffs);

  testFindings.push({
    testName:  'Quote header — full field parity',
    passed:    structural.length === 0,
    diffCount: diffs.length,
  });
  expect(
    structural,
    `AgenticQTC quote is missing values that the SF Standard baseline populated:\n` +
    structural.map(d => `  ${d.field}: SF Std=${formatVal(d.std)}`).join('\n')
  ).toHaveLength(0);
});

test('Quote lines — full field parity (all queryable fields)', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');
  test.slow();

  /** @type {FieldDiff[]} */
  const allStructural = [];
  /** @type {FieldDiff[]} */
  const allDiffs = [];

  const maxLen = Math.max(sharedStdLines.length, sharedQtcLines.length);
  for (let i = 0; i < maxLen; i++) {
    const diffs      = compareFields(sharedStdLines[i] || {}, sharedQtcLines[i] || {});
    const structural = diffs.filter(d => d.kind === 'structural');
    for (const d of structural) allStructural.push({ ...d, field: `line[${i}].${d.field}` });
    for (const d of diffs)      allDiffs.push({ ...d, field: `line[${i}].${d.field}` });
  }
  recordDiffs('quote line', allDiffs);

  console.log(
    `Quote lines — ${maxLen} line(s), ${allStructural.length} structural, ` +
    `${allDiffs.length - allStructural.length} valueDiffs`
  );

  testFindings.push({
    testName:  'Quote lines — full field parity',
    passed:    allStructural.length === 0,
    diffCount: allDiffs.length,
  });
  expect(
    allStructural,
    `AgenticQTC lines are missing values the SF Standard baseline populated:\n` +
    allStructural.map(d => `  ${d.field}: SF Std=${formatVal(d.std)}`).join('\n')
  ).toHaveLength(0);
});

test('Line count & product ordering parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const stdProducts = sharedStdLines.map(l => l.SBQQ__Product__c);
  const qtcProducts = sharedQtcLines.map(l => l.SBQQ__Product__c);
  /** @type {string[]} */
  const issues = [];

  if (sharedStdLines.length !== sharedQtcLines.length) {
    issues.push(`Line count mismatch: SF Std=${sharedStdLines.length}, AgenticQTC=${sharedQtcLines.length}`);
  }
  const stdSorted = [...stdProducts].sort();
  const qtcSorted = [...qtcProducts].sort();
  for (let i = 0; i < Math.max(stdSorted.length, qtcSorted.length); i++) {
    if (stdSorted[i] !== qtcSorted[i]) {
      issues.push(`Product set differs at sorted index ${i}: SF Std=${stdSorted[i]} AgenticQTC=${qtcSorted[i]}`);
    }
  }

  for (const issue of issues) {
    anomalies.push({ severity: 'HIGH', type: 'line-parity', detail: issue });
  }

  console.log(`Line count & ordering — SF Std=${sharedStdLines.length}, AgenticQTC=${sharedQtcLines.length}, ${issues.length} issue(s)`);
  testFindings.push({
    testName:  'Line count & product ordering parity',
    passed:    issues.length === 0,
    diffCount: issues.length,
  });
  expect(issues, issues.join('\n')).toHaveLength(0);
});

test('Pricing & totals parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const headerDiffs = compareFields(sharedStdQuote, sharedQtcQuote, { onlyFields: PRICING_FIELDS });

  /** @type {FieldDiff[]} */
  const lineDiffs = [];
  const stdByProduct = indexBy(sharedStdLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  const qtcByProduct = indexBy(sharedQtcLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(stdByProduct)) {
    const qtcLine = qtcByProduct[productId];
    if (!qtcLine) continue;
    const diffs = compareFields(stdByProduct[productId], qtcLine, { onlyFields: PRICING_FIELDS });
    for (const d of diffs) lineDiffs.push({ ...d, field: `[product ${productId}].${d.field}` });
  }

  const all = [...headerDiffs, ...lineDiffs];
  recordDiffs('pricing', all, { structuralSeverity: 'HIGH', valueSeverity: 'HIGH' });

  console.log(`Pricing parity — header diffs=${headerDiffs.length}, line diffs=${lineDiffs.length}`);

  testFindings.push({
    testName:  'Pricing & totals parity',
    passed:    all.length === 0,
    diffCount: all.length,
  });
  expect(
    all,
    `Pricing differs between SF Standard and AgenticQTC:\n` +
    all.map(d => `  ${d.field}: SF Std=${formatVal(d.std)} AgenticQTC=${formatVal(d.qtc)}`).join('\n')
  ).toHaveLength(0);
});

test('Dates & subscription term parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  const headerDiffs = compareFields(sharedStdQuote, sharedQtcQuote, { onlyFields: DATE_TERM_FIELDS });

  /** @type {FieldDiff[]} */
  const lineDiffs = [];
  const stdByProduct = indexBy(sharedStdLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  const qtcByProduct = indexBy(sharedQtcLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(stdByProduct)) {
    const qtcLine = qtcByProduct[productId];
    if (!qtcLine) continue;
    const diffs = compareFields(stdByProduct[productId], qtcLine, { onlyFields: DATE_TERM_FIELDS });
    for (const d of diffs) lineDiffs.push({ ...d, field: `[product ${productId}].${d.field}` });
  }

  const all = [...headerDiffs, ...lineDiffs];
  recordDiffs('dates & term', all, { structuralSeverity: 'HIGH', valueSeverity: 'HIGH' });

  console.log(`Dates & term parity — ${all.length} diff(s)`);

  testFindings.push({
    testName:  'Dates & subscription term parity',
    passed:    all.length === 0,
    diffCount: all.length,
  });
  expect(
    all,
    `Dates / term differ between SF Standard and AgenticQTC:\n` +
    all.map(d => `  ${d.field}: SF Std=${formatVal(d.std)} AgenticQTC=${formatVal(d.qtc)}`).join('\n')
  ).toHaveLength(0);
});

test('Subscription linkage parity', async () => {
  test.skip(!fixtureReady(), 'fixture unavailable');

  /** @type {string[]} */
  const issues = [];

  for (const line of sharedQtcLines) {
    if (!line.SBQQ__UpgradedSubscription__c) {
      issues.push(`AgenticQTC line ${line.Id} (product ${line.SBQQ__Product__c}) missing SBQQ__UpgradedSubscription__c`);
    }
  }
  for (const line of sharedStdLines) {
    if (!line.SBQQ__UpgradedSubscription__c) {
      issues.push(`SF Std line ${line.Id} (product ${line.SBQQ__Product__c}) missing SBQQ__UpgradedSubscription__c — unexpected baseline`);
    }
  }

  const stdByProduct = indexBy(sharedStdLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  const qtcByProduct = indexBy(sharedQtcLines, /** @param {any} l */ l => l.SBQQ__Product__c);
  for (const productId of Object.keys(stdByProduct)) {
    const qtcLine = qtcByProduct[productId];
    if (!qtcLine) continue;
    const diffs = compareFields(stdByProduct[productId], qtcLine, { onlyFields: SUBSCRIPTION_LINKAGE_FIELDS });
    for (const d of diffs) {
      issues.push(`Product ${productId}: ${d.field} — SF Std=${formatVal(d.std)} AgenticQTC=${formatVal(d.qtc)}`);
    }
  }

  for (const issue of issues) {
    anomalies.push({ severity: 'HIGH', type: 'subscription-linkage', detail: issue });
  }

  console.log(`Subscription linkage — ${issues.length} issue(s)`);
  testFindings.push({
    testName:  'Subscription linkage parity',
    passed:    issues.length === 0,
    diffCount: issues.length,
  });
  expect(issues, issues.join('\n')).toHaveLength(0);
});

test('Quantity update parity — SF Standard CPQ vs AgenticQTC', async () => {
  test.skip(!qtyUpdateReady(), 'quantity update fixture unavailable');
  test.slow();

  /** @type {string[]} */
  const issues = [];

  // Locate the updated line by product ID in both result sets.
  const stdLine = stdLinesAfterQtyUpdate.find(l => l.SBQQ__Product__c === qtyUpdateProductId);
  const qtcLine = qtcLinesAfterQtyUpdate.find(l => l.SBQQ__Product__c === qtyUpdateProductId);

  if (!stdLine) {
    issues.push(`SF Std: no line found for product "${qtyUpdateProductName}" after quantity update`);
  }
  if (!qtcLine) {
    issues.push(`AgenticQTC: no line found for product "${qtyUpdateProductName}" after quantity update`);
  }

  if (stdLine && qtcLine) {
    const stdQty = stdLine.SBQQ__Quantity__c;
    const qtcQty = qtcLine.SBQQ__Quantity__c;

    console.log(
      `Qty update — product: "${qtyUpdateProductName}" | ` +
      `old=${qtyUpdateOldQty}, target=${qtyUpdateNewQty} | ` +
      `SF Std qty=${stdQty}, AgenticQTC qty=${qtcQty}`
    );

    // Both should reflect the new quantity that was entered in each UI.
    if (stdQty == null || Math.abs(Number(stdQty) - (qtyUpdateNewQty || 0)) > 0.001) {
      issues.push(`SF Std quantity: expected ${qtyUpdateNewQty}, got ${stdQty ?? '(null)'}`);
    }
    if (qtcQty == null || Math.abs(Number(qtcQty) - (qtyUpdateNewQty || 0)) > 0.001) {
      issues.push(`AgenticQTC quantity: expected ${qtyUpdateNewQty}, got ${qtcQty ?? '(null)'}`);
    }
    if (stdQty != null && qtcQty != null && Math.abs(Number(stdQty) - Number(qtcQty)) > 0.001) {
      issues.push(`Quantity mismatch after update: SF Std=${stdQty}, AgenticQTC=${qtcQty}`);
    }

    // Compare pricing fields on the updated line between the two systems.
    const priceDiffs = compareFields(stdLine, qtcLine, { onlyFields: PRICING_FIELDS });
    recordDiffs('qty-update pricing', priceDiffs, { structuralSeverity: 'HIGH', valueSeverity: 'HIGH' });
    for (const d of priceDiffs) {
      issues.push(`${d.field}: SF Std=${formatVal(d.std)}, AgenticQTC=${formatVal(d.qtc)}`);
    }
  }

  for (const issue of issues) {
    anomalies.push({ severity: 'HIGH', type: 'qty-update-parity', detail: issue });
  }

  console.log(`Quantity update parity — ${issues.length} issue(s)`);
  testFindings.push({
    testName:  'Quantity update parity — SF Standard CPQ vs AgenticQTC',
    passed:    issues.length === 0,
    diffCount: issues.length,
  });
  expect(issues, issues.join('\n')).toHaveLength(0);
});
