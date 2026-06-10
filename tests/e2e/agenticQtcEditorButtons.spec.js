// @ts-check
/**
 * Editor Action Buttons — QTC Test Runner suite.
 *
 * Dashboard-selectable suite ('agenticQtcEditorButtons'). Verifies the three
 * header action buttons on the amendment quote editor behave per their rules:
 *
 *   ┌────────────────────────┬──────────────────────────────────────────────────┐
 *   │ Button                 │ Expected clickability (from agenticQtcQuoteEditor) │
 *   ├────────────────────────┼──────────────────────────────────────────────────┤
 *   │ Save                   │ isSaveDisabled = loading || !hasUnsavedChanges.    │
 *   │                        │ → disabled on open, CLICKABLE after a qty change.  │
 *   │ Submit for Approval    │ Rendered only when an approval is required         │
 *   │                        │ (approvalItems.length > 0). When present it's      │
 *   │                        │ clickable (saved, not yet submitted).              │
 *   │                        │ → approval present ⇒ present & clickable;          │
 *   │                        │   no approval     ⇒ not rendered.                  │
 *   │ Preview and Send OSA   │ isPreviewSendDisabled = no delivery contact, OR    │
 *   │                        │ (approvalRequired && status != 'Approved').        │
 *   │                        │ → clickable iff delivery contact set AND no        │
 *   │                        │   pending approval.                                │
 *   └────────────────────────┴──────────────────────────────────────────────────┘
 *
 * The test reads the editor on open (no unsaved changes), evaluates the
 * approval-gated buttons, then makes a quantity change and asserts Save becomes
 * clickable. Results are written to results.json in the canonical shape the
 * agenticQtcTestDashboard LWC consumes (UI↔DB tab + Metrics tab).
 *
 * Caveat: the "Approved" state for Preview & Send can't be read from the UI, so
 * a contract whose approvals are already Approved would be treated as "pending"
 * here. Flag that if you hit it.
 */
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'editorButtons';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
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

const yn = (/** @type {boolean} */ b) => (b ? 'clickable' : 'not clickable');

/**
 * @param {{
 *   page: import('@playwright/test').Page,
 *   qtc:  import('./utils/agenticQtcPage').AgenticQtcPage,
 *   runDir: string, runTs: string, testStartMs: number,
 *   contract: import('./utils/scenarioContracts').ContractRec,
 *   scenarioNumber: 1|2|3, scenarioLabel: string,
 *   quoteName: string,
 * }} ctx
 */
async function runEditorButtons(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;

  const spinbuttonCount = await qtc.waitForLines(120_000);
  expect(spinbuttonCount, 'Editor should expose at least one editable line').toBeGreaterThan(0);
  await u.screenshot(page, runDir, '01-editor-loaded');

  const saveBtn    = page.getByRole('button', { name: 'Save' });
  const submitBtn  = page.getByRole('button', { name: 'Submit for Approval' });
  const previewBtn = page.getByRole('button', { name: 'Preview and Send OSA' });

  // ── On-open snapshot (quote has no unsaved changes yet) ──
  // Submit for Approval renders only when an approval is required, so its
  // visibility IS the approval-required signal.
  const approvalPresent     = await u.isVisibleSafe(submitBtn, 5_000);
  const delivery            = await qtc.readContactDisplay('delivery').catch(() => ({ name: '', email: '', title: '' }));
  const deliveryPresent     = !!(delivery.name && delivery.email);
  const saveEnabledOnOpen    = await saveBtn.isEnabled().catch(() => false);
  const submitEnabledOnOpen  = approvalPresent ? await submitBtn.isEnabled().catch(() => false) : false;
  const previewEnabledOnOpen = await previewBtn.isEnabled().catch(() => false);

  // Preview & Send is enabled even with a required approval IF that approval is
  // already Approved (isPreviewSendDisabled only blocks while status != 'Approved').
  // approvalStatus isn't surfaced in the UI, so read it from the quote.
  const approvalStatus = quoteName
    ? await page.evaluate(async (/** @type {any} */ args) => {
        const headers = { Authorization: 'Bearer ' + args.token, 'Content-Type': 'application/json' };
        const soql = `SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Name = '${args.q}' LIMIT 1`;
        const r = await fetch(`${args.base}/services/data/v62.0/query?q=${encodeURIComponent(soql)}`, { headers });
        const j = await r.json();
        return j.records && j.records[0] ? (j.records[0].ApprovalStatus__c ?? null) : null;
      }, { token: sfCtx.accessToken, base: sfCtx.instanceUrl, q: quoteName }).catch(() => null)
    : null;
  const approvalApproved = approvalStatus === 'Approved';

  console.log(`[editorButtons] approvalRequired=${approvalPresent} approvalStatus=${approvalStatus} ` +
    `deliveryContact=${deliveryPresent} saveOnOpen=${saveEnabledOnOpen} submitOnOpen=${submitEnabledOnOpen} previewOnOpen=${previewEnabledOnOpen}`);

  // ── SAVE: change a quantity, then Save must be clickable ──
  const firstSpin = page.getByRole('spinbutton').first();
  const current   = parseFloat(await firstSpin.inputValue().catch(() => '0')) || 0;
  await firstSpin.click({ clickCount: 3 });
  await firstSpin.fill(String(current + 1));
  await firstSpin.press('Tab');
  await page.waitForTimeout(1_000);
  await u.screenshot(page, runDir, '02-after-qty-change');
  const saveClickableAfterChange = await saveBtn.isEnabled().catch(() => false);

  // ── Per-button expected vs actual ──
  // Save: must be clickable after the quantity change.
  const savePass = saveClickableAfterChange === true;

  // Submit for Approval: approval present ⇒ present & clickable (on open);
  //                      no approval ⇒ not rendered.
  const submitPass = approvalPresent ? (submitEnabledOnOpen === true) : (approvalPresent === false);

  // Preview & Send OSA: clickable iff a delivery contact exists AND the quote's
  // ApprovalStatus__c is not blocking (null = no approval ever set, or 'Approved').
  // The LWC checks ApprovalStatus__c directly — even when the Submit for Approval
  // button is not rendered (approvalPresent=false), a status of 'Pending Submission'
  // still disables Preview & Send.
  const approvalBlocking = approvalStatus != null && !approvalApproved;
  const expectedPreviewEnabled = deliveryPresent && !approvalBlocking;
  const previewPass = previewEnabledOnOpen === expectedPreviewEnabled;

  const allPass = savePass && submitPass && previewPass;

  // ── Dashboard payloads (repurpose the UI↔DB tab as a button-state report) ──
  /** @type {any[]} */
  const uiDbCrossCheck = [
    {
      uiIndex: 1, product: 'Save', segOcc: null,
      uiBefore: saveEnabledOnOpen ? 'clickable' : 'disabled (no changes)',
      uiAfter:  yn(saveClickableAfterChange),
      dbPrior: 'should be clickable', dbAfter: 'clickable after qty change',
      match: savePass, hasData: true,
    },
    {
      uiIndex: 2, product: 'Submit for Approval', segOcc: null,
      uiBefore: approvalPresent ? 'approval required' : 'no approval',
      uiAfter:  approvalPresent ? yn(submitEnabledOnOpen) : 'not rendered',
      dbPrior:  approvalPresent ? 'expect clickable' : 'expect not rendered',
      dbAfter:  approvalPresent ? 'clickable' : 'not rendered',
      match: submitPass, hasData: true,
    },
    {
      uiIndex: 3, product: 'Preview and Send OSA', segOcc: null,
      uiBefore: `delivery=${deliveryPresent ? 'set' : 'none'}, approval=${approvalPresent ? (approvalApproved ? 'approved' : 'pending') : 'none'}`,
      uiAfter:  yn(previewEnabledOnOpen),
      dbPrior: 'expected', dbAfter: yn(expectedPreviewEnabled),
      match: previewPass, hasData: true,
    },
  ];
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  /** @type {any[]} */
  const metricResults = [
    { metric: 'Save',                 before: saveEnabledOnOpen ? 'clickable' : 'disabled', after: yn(saveClickableAfterChange), pass: savePass,
      note: 'Should become clickable after a quantity change' },
    { metric: 'Submit for Approval',  before: approvalPresent ? 'approval required' : 'no approval', after: approvalPresent ? yn(submitEnabledOnOpen) : 'not rendered', pass: submitPass,
      note: approvalPresent ? 'Clickable when an approval is required' : 'Hidden when no approval is required' },
    { metric: 'Preview and Send OSA', before: `delivery=${deliveryPresent}, approval=${approvalPresent ? (approvalApproved ? 'approved' : 'pending') : 'none'}`, after: yn(previewEnabledOnOpen), pass: previewPass,
      note: `Expected ${yn(expectedPreviewEnabled)} (clickable only with a delivery contact and no pending approval)` },
  ];

  /** @type {Array<{type:string,severity:string,detail:string}>} */
  const dbAnomalies = [];
  if (!savePass)   dbAnomalies.push({ type: 'SAVE NOT CLICKABLE', severity: 'HIGH', detail: 'Save did not become clickable after a quantity change.' });
  if (!submitPass) dbAnomalies.push({ type: 'SUBMIT-FOR-APPROVAL STATE', severity: 'HIGH', detail: approvalPresent ? 'Approval required but Submit for Approval is not clickable.' : 'Submit for Approval rendered despite no required approval.' });
  if (!previewPass) dbAnomalies.push({ type: 'PREVIEW/SEND OSA STATE', severity: 'HIGH', detail: `Preview & Send OSA clickable=${previewEnabledOnOpen}, expected ${expectedPreviewEnabled} (delivery=${deliveryPresent}, approvalRequired=${approvalPresent}, approvalStatus=${approvalStatus}).` });

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: null,
    hasApproval: approvalPresent,
    spinbuttonCount,
    metricResults,
    dbAnomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: {
      approvalPresent, deliveryPresent,
      saveEnabledOnOpen, saveClickableAfterChange,
      submitEnabledOnOpen, previewEnabledOnOpen, expectedPreviewEnabled,
    },
  });

  // ── Assertions (each named so the Spec tab shows what failed) ──
  expect(savePass, 'Save should be clickable after a quantity change').toBe(true);
  if (approvalPresent) {
    expect(submitEnabledOnOpen, 'Submit for Approval should be clickable when an approval is required').toBe(true);
  } else {
    expect(await u.isVisibleSafe(submitBtn, 500),
      'Submit for Approval should NOT render when no approval is required').toBe(false);
  }
  expect(previewEnabledOnOpen,
    `Preview & Send OSA clickable should be ${expectedPreviewEnabled} ` +
    `(deliveryContact=${deliveryPresent}, approvalRequired=${approvalPresent}, approvalStatus=${approvalStatus})`).toBe(expectedPreviewEnabled);
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
  console.log(`\n[EditorButtons ${scenarioNumber}] Contract ${contract.number} (branch=${branch}) → ${runDir}`);

  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[EditorButtons ${scenarioNumber}] Editor open on quote ${quoteName}`);

  await runEditorButtons({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: 0 amendments — new amendment, verify Save/Approval/OSA buttons', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Editor buttons — 0 amendments → new amendment');
});

test('Scenario 2: 1 amendment — existing draft, verify Save/Approval/OSA buttons', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Editor buttons — 1 amendment → existing draft');
});

test('Scenario 3: 2+ amendments — modal pick, verify Save/Approval/OSA buttons', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Editor buttons — 2+ amendments → modal pick');
});
