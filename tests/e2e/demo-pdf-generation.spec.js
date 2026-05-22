// @ts-check
/**
 * DEMO: PDF Generation via "Preview and Send OSA"
 *
 * Focused demo test — navigates to Bates White, opens the first
 * contract with editable lines, then exercises the full PDF flow:
 *   1. Click "Preview and Send OSA"
 *   2. Click "Generate OSA Document"  →  Apex renders Visualforce → ContentVersion
 *   3. Capture the new tab (ContentDocument viewer)
 *   4. Verify PDF preview iframe
 *   5. Click "Send for Signature" → DocuSign confirmation
 */

const { test, expect } = require('@playwright/test');
const fs   = require('fs');
const path = require('path');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');

const ACCOUNT_FULL_NAME = 'Bates White';
const APP_PATH          = '/lightning/n/Agentic_QTC';
const RESULTS_DIR       = path.join(__dirname, 'results');
const DEMO_DIR          = path.join(RESULTS_DIR, 'demo-pdf');

let instanceUrl, lightningUrl, accessToken;

test.beforeAll(() => {
  fs.mkdirSync(DEMO_DIR, { recursive: true });
  const creds  = getSfCredentials();
  instanceUrl  = creds.instanceUrl;
  lightningUrl = creds.lightningUrl;
  accessToken  = creds.accessToken;
});

// ─── Slow-mo pause helper (makes the demo easy to follow visually) ────────────
const DEMO_PAUSE = 1500; // ms between demo steps
async function pause(page, ms = DEMO_PAUSE) { await page.waitForTimeout(ms); }

// ─────────────────────────────────────────────────────────────────────────────

test('DEMO — PDF generation via Preview & Send OSA', async ({ page }) => {

  // ── Step 1: Login & navigate to AgenticQTC ──────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║   AgenticQTC  PDF Generation  DEMO          ║');
  console.log('╚══════════════════════════════════════════════╝\n');
  console.log('► Step 1 — Logging in...');

  await loginViaCookie(page, lightningUrl, accessToken);
  await page.goto(`${lightningUrl}${APP_PATH}`, { waitUntil: 'domcontentloaded' });
  await page.getByPlaceholder('Start typing an account name...').waitFor({ state: 'visible', timeout: 60_000 });

  await page.screenshot({ path: `${DEMO_DIR}/01-app-ready.png`, fullPage: true });
  console.log('  ✅ App loaded\n');
  await pause(page);

  // ── Step 2: Search & select Bates White ──────────────────────────────
  console.log('► Step 2 — Searching for Bates White...');

  const input = page.getByPlaceholder('Start typing an account name...');
  await input.fill('Bates White');
  await page.getByText(ACCOUNT_FULL_NAME).first().waitFor({ state: 'visible', timeout: 20_000 });
  await page.screenshot({ path: `${DEMO_DIR}/02-search-results.png`, fullPage: true });
  await pause(page);

  await page.getByText(ACCOUNT_FULL_NAME).first().click();
  await page.getByRole('heading', { name: /Active Contracts/i }).waitFor({ state: 'visible', timeout: 30_000 });
  await page.screenshot({ path: `${DEMO_DIR}/03-contracts-list.png`, fullPage: true });
  console.log('  ✅ Bates White selected — contracts loaded\n');
  await pause(page);

  // ── Step 3: Find a contract with editable lines ──────────────────────────────
  console.log('► Step 3 — Opening a contract...');

  /**
   * When a contract row is clicked, one of two things happens:
   *   A) Quote editor opens directly (Save button visible) — use it
   *   B) A quotes-selector modal appears (.quotes-modal-backdrop) showing existing
   *      amendment quotes — click the FIRST quote row to open the editor
   *
   * Returns true if Save button is now visible, false otherwise.
   */
  async function openContractEditor(contractRow) {
    await contractRow.click();

    // Handle "Existing Draft Quotes" modal — appears when contract has >1 draft amendment quotes.
    // When exactly 1 draft exists the JS navigates directly (no modal shown).
    const backdrop = page.locator('.quotes-modal-backdrop');
    const modalAppeared = await backdrop.waitFor({ state: 'visible', timeout: 8_000 })
      .then(() => true).catch(() => false);

    if (modalAppeared) {
      console.log('    📋 Draft-quotes modal detected — selecting first quote row...');
      await page.screenshot({ path: `${DEMO_DIR}/debug-quotes-modal.png`, fullPage: true });

      // tr.quote-row are the data rows in the modal table (consistent with OSA selector JS)
      const firstQuoteRow = page.locator('tr.quote-row').first();
      await firstQuoteRow.waitFor({ state: 'visible', timeout: 5_000 });
      await firstQuoteRow.click();
      console.log('    ✅ Clicked first draft quote row');

      // Wait for modal to dismiss
      await backdrop.waitFor({ state: 'hidden', timeout: 10_000 }).catch(() => {});
    }

    // Wait for quote editor Save button
    return await page.getByRole('button', { name: 'Save' })
      .waitFor({ state: 'visible', timeout: 40_000 }).then(() => true).catch(() => false);
  }

  /** Return to the contracts list cleanly (handles being in editor or modal state) */
  async function returnToContractsList() {
    // Close any open modal first (press Escape if visible)
    const backdrop = page.locator('.quotes-modal-backdrop');
    if (await backdrop.isVisible({ timeout: 1_000 }).catch(() => false)) {
      await page.keyboard.press('Escape').catch(() => {});
      await backdrop.waitFor({ state: 'hidden', timeout: 3_000 }).catch(() => {});
    }

    // The quote editor uses a lightning-button-icon (icon-only, no text label).
    // LWC synthetic shadow exposes inner <button> to the DOM directly.
    const backBtn = page.locator('lightning-button-icon button').first();
    if (await backBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await backBtn.click();
      await page.getByRole('heading', { name: /Active Contracts/i })
        .waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
      return;
    }

    // Fallback: full fresh navigation
    await page.goto(`${lightningUrl}${APP_PATH}`, { waitUntil: 'domcontentloaded' });
    await page.getByPlaceholder('Start typing an account name...').waitFor({ state: 'visible', timeout: 60_000 });
    await page.getByPlaceholder('Start typing an account name...').fill('Bates White');
    await page.getByText(ACCOUNT_FULL_NAME).first().waitFor({ state: 'visible', timeout: 20_000 });
    await page.getByText(ACCOUNT_FULL_NAME).first().click();
    await page.getByRole('heading', { name: /Active Contracts/i }).waitFor({ state: 'visible', timeout: 30_000 });
  }

  // Use tr.contract-row so we never accidentally match thead rows or modal quote rows
  const contractRows = page.locator('tr.contract-row');
  const contractRowCount = await contractRows.count().catch(() => 0);
  console.log(`  Found ${contractRowCount} contract row(s)`);

  let foundLines = false;
  for (let r = 0; r < Math.min(contractRowCount, 8); r++) {
    const row = contractRows.nth(r);
    if (!await row.isVisible({ timeout: 3_000 }).catch(() => false)) continue;

    const label = (await row.innerText().catch(() => '')).split('\n').slice(0, 2).join(' | ').trim();
    console.log(`  Trying row ${r + 1}: ${label}`);

    const saveVisible = await openContractEditor(row);
    if (!saveVisible) {
      console.log(`    → Save button not found — skipping`);
      await returnToContractsList();
      continue;
    }

    // Set today's date to trigger line loading
    const today = new Date();
    const dateStr = `${String(today.getMonth() + 1).padStart(2, '0')}/${String(today.getDate()).padStart(2, '0')}/${today.getFullYear()}`;
    const dateInput = page.locator('input[type="date"]').first();
    if (await dateInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await dateInput.fill(dateStr);
      await dateInput.press('Tab');
    }

    const hasLines = await page.getByRole('spinbutton').first()
      .waitFor({ state: 'visible', timeout: 90_000 }).then(() => true).catch(() => false);

    if (hasLines) {
      const count = await page.getByRole('spinbutton').count();
      console.log(`  ✅ Contract opened — ${count} editable line(s)\n`);
      foundLines = true;
      break;
    }

    console.log(`    → No spinbuttons after 90s — skipping`);
    await returnToContractsList();
  }

  expect(foundLines, 'No contract with editable lines found — check screenshots for state').toBe(true);
  await page.screenshot({ path: `${DEMO_DIR}/04-quote-editor.png`, fullPage: true });
  await pause(page);

  // ── Step 4: Save the quote (needed to surface the PDF button) ────────────────
  console.log('► Step 4 — Saving quote (triggers CPQ recalc + surfaces PDF button)...');

  const saveBtn = page.getByRole('button', { name: 'Save' });
  await expect(saveBtn).toBeVisible();
  await saveBtn.click();
  await page.waitForTimeout(10_000);  // CPQ async recalc

  await page.screenshot({ path: `${DEMO_DIR}/05-after-save.png`, fullPage: true });
  console.log('  ✅ Save complete\n');
  await pause(page);

  // ── Step 5: Check for approval gate ─────────────────────────────────────────
  const hasApproval = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn  = await page.getByRole('button', { name: 'Preview and Send OSA' }).isVisible().catch(() => false);

  console.log(`  Approvals required:       ${hasApproval}`);
  console.log(`  "Preview and Send OSA":   ${hasSendBtn ? '✅ VISIBLE' : '❌ not visible'}\n`);

  if (!hasSendBtn) {
    console.log('⚠️  Approvals are required on this quote — "Preview and Send OSA" is hidden.');
    console.log('   The PDF button only appears when no approvals are pending.');
    console.log('   Try a different contract row or submit/bypass the approval in Salesforce.');
    await page.screenshot({ path: `${DEMO_DIR}/05-approval-required.png`, fullPage: true });
    test.skip();
    return;
  }

  // ── Step 6: Open the Preview & Send OSA modal ────────────────────────────────
  console.log('► Step 5 — Clicking "Preview and Send OSA" button...');

  await page.getByRole('button', { name: 'Preview and Send OSA' }).click();

  const modalVisible = await page.getByText('Preview & Send OSA').first()
    .waitFor({ state: 'visible', timeout: 15_000 }).then(() => true).catch(() => false);

  expect(modalVisible, '"Preview & Send OSA" modal must appear').toBe(true);
  await page.screenshot({ path: `${DEMO_DIR}/06-modal-opened.png`, fullPage: true });
  console.log('  ✅ Modal opened\n');
  await pause(page, 2000);

  // Check for previously generated docs
  const hadExistingDocs = await page.getByText('Previously Generated Documents')
    .isVisible({ timeout: 3_000 }).catch(() => false);
  if (hadExistingDocs) {
    console.log('  ℹ️  Previously generated docs found in modal');
  }

  // ── Step 7: Click "Generate OSA Document" ───────────────────────────────────
  console.log('► Step 6 — Clicking "Generate OSA Document"...');
  console.log('   (Apex → Page.AgenticQTC_OsaTemplate → ContentVersion → PDF)');

  const generateBtn = page.getByRole('button', { name: 'Generate OSA Document' });
  await expect(generateBtn, '"Generate OSA Document" button must be visible').toBeVisible({ timeout: 5_000 });

  // Arm the popup listener before clicking
  const popupPromise = page.context().waitForEvent('page', { timeout: 120_000 }).catch(() => null);

  await generateBtn.click();

  // "Generating PDF..." spinner
  const spinnerSeen = await page.getByText('Generating PDF...').first()
    .isVisible({ timeout: 5_000 }).catch(() => false);
  if (spinnerSeen) console.log('  ⏳ "Generating PDF..." spinner visible — Apex in progress...');

  await page.screenshot({ path: `${DEMO_DIR}/07-generating.png`, fullPage: true });

  // Wait for popup (new tab with ContentDocument viewer)
  const popup = await popupPromise;
  let pdfDocId = null;
  if (popup) {
    const popupUrl = popup.url();
    const m = popupUrl.match(/ContentDocument\/([a-zA-Z0-9]{15,18})\/view/);
    if (m) pdfDocId = m[1];
    console.log(`  ✅ New tab opened → ${popupUrl}`);
    await popup.waitForLoadState('domcontentloaded').catch(() => {});
    await popup.screenshot({ path: `${DEMO_DIR}/07b-contentdocument-viewer.png`, fullPage: true }).catch(() => {});
    console.log('  📸 ContentDocument viewer screenshot saved');
    await popup.close().catch(() => {});
  } else {
    console.log('  ℹ️  No popup detected');
  }

  // ── Step 8: Verify Document Preview section ──────────────────────────────────
  console.log('\n► Step 7 — Verifying Document Preview...');

  const previewSection = await page.getByText('Document Preview').first()
    .waitFor({ state: 'visible', timeout: 30_000 }).then(() => true).catch(() => false);

  expect(previewSection, '"Document Preview" section must appear after generation').toBe(true);

  // Capture doc title
  let pdfDocTitle = null;
  try {
    pdfDocTitle = await page.evaluate(() => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
      let node;
      while ((node = walker.nextNode())) {
        if (node.className && String(node.className).includes('doc-ready')) {
          const spans = node.querySelectorAll('span');
          for (const s of spans) {
            if (s.textContent && s.textContent.trim().endsWith('.pdf')) return s.textContent.trim();
          }
        }
      }
      return null;
    });
  } catch { /* skip */ }

  // Verify PDF iframe
  const previewIframe = page.getByTitle('OSA Document Preview');
  const iframeSrc = await previewIframe.getAttribute('src', { timeout: 5_000 }).catch(() => null);

  console.log(`  ✅ Document Preview section visible`);
  console.log(`  📄 Document title:     ${pdfDocTitle || '(check screenshot)'}`);
  console.log(`  🆔 ContentDocument ID: ${pdfDocId    || '(check popup URL)'}`);
  console.log(`  🔗 PDF iframe src:     ${iframeSrc   || '(not captured)'}`);

  // "Open in New Tab" button
  const openTabBtn = await page.getByRole('button', { name: 'Open in New Tab' }).isVisible({ timeout: 3_000 }).catch(() => false);
  console.log(`  "Open in New Tab" visible: ${openTabBtn ? '✅ Yes' : '—'}`);

  await page.screenshot({ path: `${DEMO_DIR}/08-pdf-preview.png`, fullPage: true });
  await pause(page, 2500);

  // ── Step 9: Send for Signature ────────────────────────────────────────────────
  console.log('\n► Step 8 — Clicking "Send for Signature" (DocuSign simulation)...');

  const sendBtn = page.getByRole('button', { name: 'Send for Signature' });
  await expect(sendBtn, '"Send for Signature" button must be visible').toBeVisible({ timeout: 5_000 });
  await sendBtn.click();

  console.log('  ⏳ DocuSign simulation running (2s)...');

  const sentConfirm = await page.getByText('OSA sent successfully via DocuSign!').first()
    .waitFor({ state: 'visible', timeout: 10_000 }).then(() => true).catch(() => false);

  expect(sentConfirm, '"OSA sent successfully via DocuSign!" confirmation must appear').toBe(true);
  console.log('  ✅ "OSA sent successfully via DocuSign!" confirmed');

  await page.screenshot({ path: `${DEMO_DIR}/09-osa-sent.png`, fullPage: true });
  await pause(page, 2000);

  // ── Close modal ───────────────────────────────────────────────────────────────
  const closeBtn = page.getByRole('button', { name: 'Close' });
  if (await closeBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await closeBtn.click();
    await pause(page, 1000);
  }

  // ── Summary ───────────────────────────────────────────────────────────────────
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║   DEMO COMPLETE ✅                           ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  PDF document:  ${(pdfDocTitle || '(see screenshot)').padEnd(28)}║`);
  console.log(`║  Doc ID:        ${(pdfDocId    || 'n/a').padEnd(28)}║`);
  console.log(`║  OSA sent:      ✅ confirmed                 ║`);
  console.log('╠══════════════════════════════════════════════╣');
  console.log('║  Screenshots saved to:                       ║');
  console.log('║  tests/e2e/results/demo-pdf/                 ║');
  console.log('╚══════════════════════════════════════════════╝\n');
});
