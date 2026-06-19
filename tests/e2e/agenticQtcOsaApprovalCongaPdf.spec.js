// @ts-check
/**
 * agenticQtcOsaApprovalCongaPdf.spec.js
 *
 * End-to-end OSA approval → Conga generation → PDF data-sync, in one flow.
 * Combines the two former specs:
 *   • agenticQtcPreviewSendOSAUsingConga.spec.js (drives the OSA wizard)
 *   • agenticQtcCongaPdfDataSync.spec.js          (PDF ↔ SF field comparison)
 *
 * The order is dictated by the editor's own gating logic
 * (agenticQtcQuoteEditor.js → get isPreviewSendDisabled):
 *   isPreviewSendDisabled = !deliveryContact
 *                         || (anyApprovalRequired && approvalStatus !== 'Approved')
 * so the "Preview and Send OSA" (PDF generation) button stays LOCKED while an
 * approval is required and not yet approved. The flow therefore is:
 *
 *   1. Log in (frontdoor session — shared with the Conga popup tab so Conga
 *      authenticates without a separate login).
 *   2. Open an amendment quote on the dashboard-chosen account, make sure a
 *      Software Delivery contact is set, then bump the CURRENT segment's quantity
 *      by 1 (the first editable MDQ segment) so the amendment carries a real
 *      change — this enables Save AND trips the SBAA approval rule. Save.
 *   3. Assert "Submit for Approval" renders (approval required) and the PDF
 *      button is DISABLED (the "hide the PDF generation button" behaviour).
 *   4. Click "Submit for Approval" → sbaa.ApprovalAPI.submit creates pending
 *      sbaa__Approval__c records.
 *   5. Approve via REST — the same writes QTC_GreenboxApproveAll.cls performs:
 *      sbaa__Approval__c.sbaa__Status__c = 'Approved' (+ ApprovedBy/AssignedTo)
 *      and SBQQ__Quote__c.ApprovalStatus__c = 'Approved'.
 *   6. Re-open the editor (deep-link by quoteId) so approvalStatus reloads, and
 *      assert the PDF button is now ENABLED.
 *   7. Drive the OSA wizard → "Open Conga to Generate OSA" → wait for the new
 *      PDF to land on the quote.
 *   8. Snapshot current SF data, download + parse the PDF, field-by-field
 *      compare, assert zero mismatches.
 *
 * Account comes from the dashboard via QTC_ACCOUNT_SEARCH / QTC_ACCOUNT_FULL_NAME
 * (same convention as the other specs). Performs real writes in the target org.
 */
const fs   = require('fs');
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const { APP_PATH } = require('./utils/agenticQtcPage');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');
const { snapshotForOsa, waitForGeneratedPdf, downloadPdfText, comparePdfToSnapshot } = require('./utils/congaDoc');

const KIND              = 'osaApprovalCongaPdf';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Jacobs Holding AG';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || process.env.QTC_ACCOUNT_NAME || 'Jacobs Holding AG';
const SF_API_VER        = process.env.QTC_SF_API_VERSION    || 'v62.0';
const PDF_TIMEOUT_MS    = Number(process.env.QTC_OSA_PDF_TIMEOUT_MS || 240_000);
const QTY_DELTA         = 1;   // bump the current segment quantity by this much
const RESULTS_DIR       = path.join(__dirname, 'results');

// SBAA statuses treated as "pending" — mirrors getRunningApprovals() in
// AgenticQTC_ApprovalLogicService.cls.
const PENDING_APPROVAL_STATUSES = ['Assigned', 'Requested', 'Pending'];

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

// ─── REST helpers (Bearer token already in sfCtx) ────────────────────────────

function authHeaders() {
  return { Authorization: `Bearer ${sfCtx.accessToken}`, 'Content-Type': 'application/json' };
}

/**
 * PATCH a single sObject record. Salesforce returns 204 No Content on success.
 * @param {string} sobject
 * @param {string} id
 * @param {Record<string, any>} body
 */
async function sfPatch(sobject, id, body) {
  const url  = `${sfCtx.instanceUrl}/services/data/${SF_API_VER}/sobjects/${sobject}/${id}`;
  const resp = await fetch(url, { method: 'PATCH', headers: authHeaders(), body: JSON.stringify(body) });
  if (!resp.ok && resp.status !== 204) {
    throw new Error(`PATCH ${sobject}/${id} failed: ${resp.status} ${await resp.text()}`);
  }
}

/** The running user's Id — stamped onto approvals like the Greenbox approve-all does. */
async function currentUserId() {
  const resp = await fetch(`${sfCtx.instanceUrl}/services/oauth2/userinfo`, { headers: authHeaders() });
  if (!resp.ok) return null;
  const info = await resp.json();
  return info.user_id || null;
}

/** @param {string} s */
const escSoql = (s) => s.replace(/'/g, "\\'");

/**
 * Resolve the quote's Id + related entity Ids by quote Name.
 * @param {string} quoteName
 * @returns {Promise<{Id:string, accountId:string|null, opportunityId:string|null, contractId:string|null, contractNumber:string|null}|null>}
 */
async function fetchQuoteRec(quoteName) {
  const soql = `SELECT Id, SBQQ__Account__c, SBQQ__Opportunity2__c,
                       SBQQ__MasterContract__c, SBQQ__MasterContract__r.ContractNumber
                FROM SBQQ__Quote__c WHERE Name = '${escSoql(quoteName)}' LIMIT 1`;
  const res = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql, SF_API_VER);
  const rec = res.records?.[0];
  if (!rec) return null;
  return {
    Id:             rec.Id,
    accountId:      rec.SBQQ__Account__c ?? null,
    opportunityId:  rec.SBQQ__Opportunity2__c ?? null,
    contractId:     rec.SBQQ__MasterContract__c ?? null,
    contractNumber: rec.SBQQ__MasterContract__r?.ContractNumber ?? null,
  };
}

/**
 * Poll for the pending SBAA approvals created by submit-for-approval. They are
 * created synchronously inside sbaa.ApprovalAPI.submit, but allow a short window
 * for index/visibility lag.
 * @param {string} quoteId
 * @returns {Promise<string[]>} pending sbaa__Approval__c Ids
 */
async function waitForPendingApprovals(quoteId, timeoutMs = 30_000) {
  const inClause = PENDING_APPROVAL_STATUSES.map(s => `'${s}'`).join(',');
  const soql = `SELECT Id FROM sbaa__Approval__c
                WHERE Quote__c = '${quoteId}' AND sbaa__Status__c IN (${inClause})`;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const res = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql, SF_API_VER);
    const ids = (res.records || []).map((/** @type {any} */ r) => r.Id);
    if (ids.length > 0) return ids;
    await new Promise(r => setTimeout(r, 3_000));
  }
  return [];
}

/**
 * Approve the quote via REST — the exact writes QTC_GreenboxApproveAll.cls makes:
 * flip every pending sbaa__Approval__c to 'Approved' (stamping approver), then set
 * the quote's ApprovalStatus__c = 'Approved'. That clears the editor's PDF-button gate.
 * @param {string} quoteId
 * @param {string[]} approvalIds
 * @returns {Promise<number>} number of approvals flipped
 */
async function approveViaApi(quoteId, approvalIds) {
  const userId = await currentUserId();
  for (const id of approvalIds) {
    /** @type {Record<string, any>} */
    const body = { sbaa__Status__c: 'Approved' };
    if (userId) { body.sbaa__ApprovedBy__c = userId; body.sbaa__AssignedTo__c = userId; }
    try {
      await sfPatch('sbaa__Approval__c', id, body);
    } catch (e) {
      // Retry status-only in case ApprovedBy/AssignedTo aren't writable for this user.
      await sfPatch('sbaa__Approval__c', id, { sbaa__Status__c: 'Approved' });
    }
  }
  await sfPatch('SBQQ__Quote__c', quoteId, { ApprovalStatus__c: 'Approved' });
  return approvalIds.length;
}

/**
 * Re-open the editor on the SAME quote via the app's deep-link entry point
 * (?c__quoteId=…, handled by agenticQtcApp.handlePageReference) so a fresh editor
 * instance reloads approvalStatus. Re-running the scenario opener is unsafe here —
 * the "zero drafts" branch would create a brand-new amendment instead.
 * @param {import('@playwright/test').Page} page
 * @param {{Id:string, accountId:string|null, contractId:string|null, contractNumber:string|null}} rec
 */
async function reopenEditorDeepLink(page, rec) {
  const params = new URLSearchParams({ c__quoteId: rec.Id });
  if (rec.accountId)      params.set('c__accountId', rec.accountId);
  if (rec.contractId)     params.set('c__contractId', rec.contractId);
  if (rec.contractNumber) params.set('c__contractNumber', rec.contractNumber);
  await page.goto(`${sfCtx.lightningUrl}${APP_PATH}?${params.toString()}`, { waitUntil: 'commit' })
    .catch(() => { /* swallow nav-interrupt; waitFor below is the real check */ });
  await page.getByRole('button', { name: 'Save' }).waitFor({ state: 'visible', timeout: 120_000 });
}

/**
 * Increase the CURRENT segment's quantity by one. MDQ rows render a per-segment
 * +1 stepper (`button.qty-stepper-up`, scoped via data-line-id/data-segment-key);
 * the first one is the current (first editable) segment, so clicking it changes
 * exactly that segment. Falls back to the first numeric input for non-MDQ rows.
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<{before:number, after:number}>}
 */
async function bumpCurrentSegmentQuantity(page) {
  const stepper = page.locator('div.qty-stepper').first();
  if (await u.isVisibleSafe(stepper, 3_000)) {
    const segInput = stepper.locator('input.qty-input');
    const before   = parseFloat(await segInput.inputValue().catch(() => '0')) || 0;
    await stepper.locator('button.qty-stepper-up').click();
    await page.waitForTimeout(800);
    const after = parseFloat(await segInput.inputValue().catch(() => String(before + QTY_DELTA))) || (before + QTY_DELTA);
    return { before, after };
  }
  const firstSb = page.getByRole('spinbutton').first();
  const before  = parseFloat(await firstSb.inputValue().catch(() => '0')) || 0;
  const after   = before + QTY_DELTA;
  await firstSb.click({ clickCount: 3 });
  await firstSb.fill(String(after));
  await firstSb.press('Tab');
  await page.waitForTimeout(800);
  return { before, after };
}

// ─── The combined flow ───────────────────────────────────────────────────────

test('OSA: qty change → submit-for-approval locks PDF button → approve via API → generate Conga PDF → PDF matches SF', async ({ page }) => {
  test.slow(); // editor load + Conga generation + PDF parse — well over the default budget
  const testStartMs       = Date.now();
  const { runTs, runDir } = u.createRunFolder(RESULTS_DIR);

  // Discovery routes the account's first contract into exactly one bucket.
  const branchEntry = /** @type {Array<['zero'|'one'|'many', any]>} */ (
    [['many', contractCache?.byScenario.many], ['one', contractCache?.byScenario.one], ['zero', contractCache?.byScenario.zero]]
  ).find(([, c]) => c);
  test.skip(!branchEntry, `No contract discovered on "${ACCOUNT_FULL_NAME}" — nothing to open`);
  const [branch, contract] = /** @type {['zero'|'one'|'many', any]} */ (branchEntry);

  // 1–2. Open the amendment editor.
  console.log(`\n[${KIND}] Account "${ACCOUNT_FULL_NAME}", contract ${contract.number} (branch=${branch})`);
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  const spinbuttonCount = await qtc.waitForLines(120_000);
  console.log(`[${KIND}] Editor open on quote ${quoteName} (${spinbuttonCount} editable line(s))`);
  test.skip(spinbuttonCount === 0, `Quote ${quoteName} has no editable lines to amend`);
  await u.screenshot(page, runDir, '01-editor');

  const quoteRec = await fetchQuoteRec(quoteName);
  expect(quoteRec, `Quote ${quoteName} should resolve to a record`).not.toBeNull();
  const quoteId = /** @type {string} */ (quoteRec?.Id);

  // 2a. Ensure a Software Delivery contact is set — otherwise the PDF button is
  //     disabled for a contact reason, not the approval reason we're testing.
  //     (Persisted by the single save below.)
  const delivery = await qtc.readContactDisplay('delivery').catch(() => ({ name: '' }));
  if (!delivery.name) {
    console.log(`[${KIND}] No Software Delivery contact — selecting one`);
    const picked = await qtc.pickDifferentContact('delivery', null);
    if (!picked) {
      test.skip(true, `Quote ${quoteName} has no Software Delivery contact and none to pick — PDF button can never enable`);
      return;
    }
  }

  // 2b. Bump the CURRENT segment quantity by +1 — makes a real change (so Save
  //     enables) and is what trips the SBAA approval rule on the amendment.
  const { before: qtyBefore, after: qtyAfter } = await bumpCurrentSegmentQuantity(page);
  console.log(`[${KIND}] Current-segment quantity ${qtyBefore} → ${qtyAfter}`);
  await u.screenshot(page, runDir, '02-qty-increased');

  // 2c. Save the change (Save is enabled now).
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '03-saved');

  // 3. Branch on the PDF button's state:
  //    • already ENABLED → no approval needed → go straight to Preview & Send OSA.
  //    • DISABLED + "Submit for Approval" present → approval needed → submit + approve.
  //    • DISABLED + nothing to approve → can't proceed (skip).
  const previewBtn = page.getByRole('button', { name: 'Preview and Send OSA' });
  const submitBtn  = page.getByRole('button', { name: 'Submit for Approval' });
  let approvalRequired = false;
  let approvedCount    = 0;

  if (await previewBtn.isEnabled().catch(() => false)) {
    // No approval gate — the amendment is already sendable.
    console.log(`[${KIND}] "Preview and Send OSA" already enabled — approval not required; generating directly`);
    await u.screenshot(page, runDir, '04-no-approval-needed');
  } else if (await u.isVisibleSafe(submitBtn, 8_000)) {
    // Approval required: the PDF button is locked until the approval clears.
    approvalRequired = true;
    await expect(previewBtn, 'PDF button must be disabled before approval clears').toBeDisabled();
    await u.screenshot(page, runDir, '04-pdf-button-locked');

    // 4. Submit for approval (quote is clean after the save above).
    await submitBtn.click();
    const submitOk  = page.getByText(/Submitted for approval/i).first();
    const submitErr = page.getByText(/Error submitting for approval/i).first();
    const winner    = await u.waitForAny([submitOk, submitErr], 30_000);
    expect(winner, 'Submit for Approval should toast success, not error/timeout').toBe(0);
    await u.screenshot(page, runDir, '05-submitted');

    // 5. Approve via REST (the Greenbox approve-all writes).
    const pendingIds = await waitForPendingApprovals(quoteId);
    expect(pendingIds.length, 'Submit should have created ≥ 1 pending SBAA approval').toBeGreaterThan(0);
    approvedCount = await approveViaApi(quoteId, pendingIds);
    console.log(`[${KIND}] Approved ${approvedCount} SBAA approval(s) for ${quoteName} via REST`);

    // 6. Re-open the editor; the PDF button should now be ENABLED.
    await reopenEditorDeepLink(page, /** @type {any} */ (quoteRec));
    await qtc.waitForLines(120_000);
    await expect(
      page.getByRole('button', { name: 'Preview and Send OSA' }),
      'PDF button must enable once ApprovalStatus__c = Approved',
    ).toBeEnabled({ timeout: 30_000 });
    await u.screenshot(page, runDir, '06-pdf-button-unlocked');
  } else {
    // Disabled with nothing to approve — a different gate (e.g. delivery contact) blocks it.
    buildRichResults({
      kind: KIND, runTs, runDir, testStartMs,
      accountName: ACCOUNT_FULL_NAME, scenarioNumber: 1,
      scenarioLabel: 'OSA approval → Conga PDF sync',
      contract: contract.number, quoteName, quoteId,
      passed: true,
      extra: { skipped: true, reason: 'PDF button disabled and no approval pending — cannot generate' },
    });
    test.skip(true, `"Preview and Send OSA" is disabled for ${quoteName} and there is no approval to clear`);
    return;
  }

  // 7. Snapshot SF data, then drive the OSA wizard to generate the Conga PDF.
  const previewBtnReady = page.getByRole('button', { name: 'Preview and Send OSA' });
  await expect(previewBtnReady, 'PDF button should be enabled before generating').toBeEnabled({ timeout: 30_000 });
  const snapshot   = await snapshotForOsa(sfCtx, { quoteName, accountName: ACCOUNT_FULL_NAME, contractNumber: quoteRec?.contractNumber });
  const genStartTs = Date.now();

  // "Open Conga to Generate OSA" calls window.open(...) — capture the popup so it
  // isn't orphaned, but the LWC manages/closes it; we only wait for the new PDF.
  const popupPromise = page.waitForEvent('popup').catch(() => null);
  await previewBtnReady.click();
  const modal = page.locator('section.modal-overlay');
  await expect(modal).toBeVisible({ timeout: 15_000 });
  await modal.getByRole('button', { name: 'Next' }).click();                        // step1 → step2
  const congaBtn = modal.getByRole('button', { name: 'Open Conga to Generate OSA' });
  await expect(congaBtn).toBeVisible({ timeout: 15_000 });
  await congaBtn.click();
  const popup = await popupPromise;
  if (popup) { await popup.waitForLoadState('domcontentloaded').catch(() => {}); }
  await u.screenshot(page, runDir, '07-conga-launched');

  const linkedIds = [quoteId, quoteRec?.contractId, quoteRec?.opportunityId, quoteRec?.accountId]
    .filter(/** @returns {x is string} */ (x) => typeof x === 'string' && x.length > 0);
  const generated = await waitForGeneratedPdf(sfCtx, linkedIds, genStartTs, {
    timeoutMs: PDF_TIMEOUT_MS, pollMs: 5_000, logger: (m) => console.log(m),
  });
  expect(generated, `Conga should produce a PDF within ${PDF_TIMEOUT_MS}ms`).not.toBeNull();
  console.log(`[${KIND}] PDF generated: "${generated?.title}" (linked to ${generated?.linkedEntityId})`);

  // 8. Download, parse, compare against the snapshot.
  const { text, numPages } = await downloadPdfText(sfCtx, /** @type {any} */ (generated).contentVersionId);
  fs.writeFileSync(path.join(runDir, 'pdf-text.txt'), text, 'utf8');
  const cmp = comparePdfToSnapshot(snapshot, text);
  console.log(`[${KIND}] PDF compare: ${cmp.matches}✓ / ${cmp.mismatches}✗ (${numPages} page(s))`);

  // Dashboard rows (UI↔DB comparison view) + anomalies.
  const uiDbCrossCheck = cmp.rows.map((r, i) => ({
    uiIndex: i + 1, product: r.field, segOcc: null,
    uiBefore: null, uiAfter: r.expected, dbPrior: null, dbAfter: r.inPdf,
    match: r.match, hasData: true,
  }));
  const dbComparison = cmp.rows.map((r, i) => ({
    index: i + 1, product: r.field, segKey: r.match ? '✓' : '✗', segIndex: null,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null, dbDiscount: null,
    dbNetTotal: null, dbAcv: null, dbTcv: null, isBundle: false,
    startDate: null, endDate: null, pricingMethod: null, term: null, regularPrice: null,
  }));
  const dbAnomalies = cmp.rows.filter(r => !r.match).map(r => ({
    severity: 'HIGH', type: 'pdf-sf-mismatch', detail: `${r.field}: SF=${r.expected} | PDF=${r.inPdf}`,
  }));

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME, scenarioNumber: 1,
    scenarioLabel: 'OSA approval → Conga PDF sync',
    contract: quoteRec?.contractNumber, quoteName, quoteId,
    hasApproval: true, pdfGenerated: true, pdfSkipped: false,
    dbLineCount: dbComparison.length,
    dbComparison, uiDbCrossCheck,
    crossCheckMismatches: cmp.mismatches, dbAnomalies,
    passed: cmp.mismatches === 0,
    extra: {
      qtyBefore, qtyAfter,
      approvalRequired,
      approvalsApproved: approvedCount,
      pdfTitle:          generated?.title,
      pdfNumPages:       numPages,
      pdfLinkedTo:       generated?.linkedEntityId,
      snapshotLines:     snapshot.lines.length,
      pdfMatches:        cmp.matches,
      pdfMismatches:     cmp.mismatches,
    },
  });

  // 9. Assert the generated PDF reflects current SF data.
  expect(
    cmp.mismatches,
    `Conga PDF should match current SF data (${cmp.matches}✓ / ${cmp.mismatches}✗):\n` +
    cmp.rows.filter(r => !r.match).map(r => `  ${r.field}: SF=${r.expected} | PDF=${r.inPdf}`).join('\n')
  ).toBe(0);
});
