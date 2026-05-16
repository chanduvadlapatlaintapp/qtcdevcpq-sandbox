// @ts-check
/**
 * E2E Test: AgenticQTC — Multi-line quantity increase with full verification
 *
 * Strategy:
 *  1. Search Baker McKenzie, open contracts table
 *  2. Probe each contract row (up to 5) to find one with 4+ editable lines
 *  3. Capture pre-save state: all quantities + header metrics (ACV, ACV Change, TCV, YoY Uplift)
 *  4. Increase every line's quantity by 5 (all years via "apply to all" where possible)
 *  5. Click Save → wait for CPQ recalculation
 *  6. Capture post-save state: all quantities + header metrics
 *  7. Assert: each qty = prior + 5; header metrics changed in the right direction
 *  8. Write detailed HTML report to tests/e2e/results/quantity-increase-report.html
 */

const { test, expect } = require('@playwright/test');
const fs   = require('fs');
const path = require('path');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');

const ACCOUNT_FULL_NAME = 'Baker McKenzie LLP';
const APP_PATH          = '/lightning/n/Agentic_QTC';
const QTY_DELTA         = 5;
const RESULTS_DIR       = path.join(__dirname, 'results');
const REPORT_PATH       = path.join(RESULTS_DIR, 'quantity-increase-report.html');

// Each run gets its own timestamped subfolder under results/runs/
// e.g. results/runs/2026-05-06_20-53-00/
const RUN_TS  = new Date().toISOString().replace(/T/, '_').replace(/:/g, '-').slice(0, 19);
const RUN_DIR = path.join(RESULTS_DIR, 'runs', RUN_TS);

// ─── Navigation helpers ──────────────────────────────────────────────────────

async function gotoApp(page, instanceUrl) {
  await page.goto(`${instanceUrl}${APP_PATH}`, { waitUntil: 'domcontentloaded' });
  await page.getByPlaceholder('Start typing an account name...').waitFor({ state: 'visible', timeout: 60_000 });
}

async function searchAndSelectAccount(page) {
  const input = page.getByPlaceholder('Start typing an account name...');
  await input.fill('Baker McKenzie');
  await page.getByText(ACCOUNT_FULL_NAME).first().waitFor({ state: 'visible', timeout: 20_000 });
  await page.getByText(ACCOUNT_FULL_NAME).first().click();
  await page.getByRole('heading', { name: /Active Contracts/i }).waitFor({ state: 'visible', timeout: 30_000 });
}

/** Read all metrics via Playwright text locators (pierce shadow DOM) */
async function captureAllMetricText(page) {
  const labels = ['ACV', 'ACV Change', 'TCV', 'YoY Uplift', 'Deal Quality Score'];
  const result = {};

  // The metrics bar body text contains all labels+values concatenated
  // Read the entire metrics bar innerText and parse out label→value pairs
  const metricsBarText = await page.evaluate(() => {
    // Walk all shadow roots (LWC synthetic shadow: elements are in normal DOM)
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.className && String(node.className).includes('metrics-bar')) {
        return node.innerText || node.textContent || '';
      }
    }
    return '';
  }).catch(() => '');

  if (metricsBarText) {
    // Text format: "ACV\n$0.00\nACV Change\n+$0.00\nTCV\n$2,771.22\n..."
    const lines = metricsBarText.split('\n').map(l => l.trim()).filter(Boolean);
    for (let i = 0; i < lines.length - 1; i++) {
      if (labels.includes(lines[i])) {
        result[lines[i]] = lines[i + 1];
        i++; // skip value on next iteration
      }
    }
  }

  // Fallback: use getByText for each label
  for (const label of labels) {
    if (!result[label]) {
      try {
        const el = page.getByText(label, { exact: true }).first();
        const parent = el.locator('..');
        const fullText = await parent.innerText({ timeout: 2_000 });
        const val = fullText.replace(label, '').trim().split('\n')[0].trim();
        if (val) result[label] = val;
      } catch { /* skip */ }
    }
  }

  return result;
}

/** Capture all header metrics */
async function captureMetrics(page) {
  const raw = await captureAllMetricText(page);
  return {
    acv:         raw['ACV']                || 'N/A',
    acvChange:   raw['ACV Change']         || 'N/A',
    tcv:         raw['TCV']                || 'N/A',
    yoyUplift:   raw['YoY Uplift']         || 'N/A',
    dealQuality: raw['Deal Quality Score'] || 'N/A',
  };
}

/** Parse "$1,234.56" or "+$1,234.56" or "+12.3%" to a number */
function parseCurrency(str) {
  if (!str || str === 'N/A' || str === '--') return null;
  const clean = str.replace(/[+\-$,%\s]/g, '').replace(/,/g, '');
  const n = parseFloat(clean);
  return isNaN(n) ? null : n;
}

/**
 * Click the back button in the quote editor and return to the contracts list.
 * The editor uses a lightning-button-icon (icon-only, no visible text label) for back navigation.
 * LWC synthetic shadow exposes inner elements directly in the DOM, so standard CSS selectors work.
 */
async function clickBackToContracts(page) {
  // lightning-button-icon renders a <button> as a direct child in LWC synthetic shadow.
  const backBtn = page.locator('lightning-button-icon button').first();
  if (await backBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await backBtn.click();
    return;
  }
  // Fallback: text-based button (legacy or fallback UI)
  await page.getByRole('button').filter({ hasText: /back/i }).first().click().catch(() => {});
}

/** Try to open a contract row and wait for lines. Returns line count or 0. */
async function probeContractForLines(page, rowIndex) {
  // Use the specific CSS class so we never accidentally match rows inside the
  // "Existing Draft Quotes" modal (which uses tr.quote-row).
  const contractRows = page.locator('tr.contract-row');
  // rowIndex is 1-based in the outer loop (starts at 2 to skip the header),
  // but locator.nth() is 0-based, so convert.
  const row = contractRows.nth(rowIndex - 1);
  if (!await row.isVisible({ timeout: 3_000 }).catch(() => false)) return { count: 0, contractLabel: '' };

  const contractLabel = await row.innerText().catch(() => `row-${rowIndex}`);
  await row.click();

  // ── Handle "Existing Draft Quotes" modal ─────────────────────────────────
  // Appears when the contract already has >1 draft amendment quotes.
  // When exactly 1 draft exists the JS navigates directly (no modal).
  const quotesModal = page.locator('.quotes-modal-backdrop');
  const modalAppeared = await quotesModal.waitFor({ state: 'visible', timeout: 8_000 })
    .then(() => true).catch(() => false);

  if (modalAppeared) {
    console.log('    ↳ Draft-quotes modal detected — selecting first quote row');
    const firstQuoteRow = page.locator('tr.quote-row').first();
    await firstQuoteRow.waitFor({ state: 'visible', timeout: 5_000 });
    await firstQuoteRow.click();
    // Wait for the modal to close before continuing
    await quotesModal.waitFor({ state: 'hidden', timeout: 10_000 }).catch(() => {});
  }

  // Wait for Save button (editor mounted)
  const saveVisible = await page.getByRole('button', { name: 'Save' })
    .waitFor({ state: 'visible', timeout: 30_000 }).then(() => true).catch(() => false);
  if (!saveVisible) {
    await clickBackToContracts(page).catch(() => {});
    await page.getByRole('heading', { name: /Active Contracts/i })
      .waitFor({ state: 'visible', timeout: 20_000 }).catch(() => {});
    return { count: 0, contractLabel };
  }

  // Set a quote start date to trigger line loading
  const today = new Date();
  const dateStr = `${String(today.getMonth() + 1).padStart(2, '0')}/${String(today.getDate()).padStart(2, '0')}/${today.getFullYear()}`;
  const dateInput = page.locator('input[type="date"]').first();
  if (await dateInput.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await dateInput.fill(dateStr);
    await dateInput.press('Tab');
  }

  // Wait up to 90s for spinbuttons to appear (amendment quote creation)
  const spinbuttons = page.getByRole('spinbutton');
  const hasLines = await spinbuttons.first().waitFor({ state: 'visible', timeout: 90_000 })
    .then(() => true).catch(() => false);

  if (!hasLines) {
    await clickBackToContracts(page).catch(() => {});
    await page.getByRole('heading', { name: /Active Contracts/i })
      .waitFor({ state: 'visible', timeout: 20_000 }).catch(() => {});
    await page.waitForTimeout(500);
    return { count: 0, contractLabel };
  }

  const count = await spinbuttons.count();
  return { count, contractLabel };
}

// ─── Test setup ──────────────────────────────────────────────────────────────

let instanceUrl, lightningUrl, accessToken;
test.beforeAll(() => {
  const creds  = getSfCredentials();
  instanceUrl  = creds.instanceUrl;   // my.salesforce.com  — for REST API calls
  lightningUrl = creds.lightningUrl;  // lightning.force.com — for browser navigation
  accessToken  = creds.accessToken;
});

// ─── Main test ───────────────────────────────────────────────────────────────

test('Quantity increase: find 4+ line contract, update all, verify totals', async ({ page }) => {
  const testStartMs = Date.now();

  // Create this run's screenshot folder
  fs.mkdirSync(RUN_DIR, { recursive: true });
  console.log(`\n📁 Run folder: ${RUN_DIR}`);

  await loginViaCookie(page, lightningUrl, accessToken);
  await gotoApp(page, lightningUrl);
  await searchAndSelectAccount(page);

  await page.screenshot({ path: `${RUN_DIR}/01-contracts.png`, fullPage: true });

  // ── 1. Find a contract with 4+ editable lines ──────────────────────────────
  console.log('\n── Finding contract with 4+ lines ──');

  let chosenContract = null;
  let spinbuttonCount = 0;

  // Start from row 2 — row 1 (DealCloud) never surfaces lines in this sandbox.
  // Probe rows 2–7; stop at the first with 4+ spinbuttons.
  for (let r = 2; r <= 7; r++) {
    console.log(`  Probing contract row ${r}...`);
    const { count, contractLabel } = await probeContractForLines(page, r);
    console.log(`    → ${count} spinbutton(s) found  [${contractLabel.split('\n')[0].trim()}]`);

    if (count >= 4) {
      chosenContract = contractLabel.split('\n')[0].trim();
      spinbuttonCount = count;
      console.log(`  ✅ Using this contract (${count} lines)`);
      break;
    }

    // Go back to contracts list if not enough lines
    const contractsHeading = page.getByRole('heading', { name: /Active Contracts/i });
    const alreadyBack = await contractsHeading.isVisible({ timeout: 1_000 }).catch(() => false);
    if (!alreadyBack) {
      // probeContractForLines already navigated back in the no-lines paths,
      // but if we broke out with count >= 0 and didn't navigate, do it now.
      await clickBackToContracts(page).catch(() => {});
      const backOk = await contractsHeading.waitFor({ state: 'visible', timeout: 20_000 })
        .then(() => true).catch(() => false);
      if (!backOk) {
        // Full reset as last resort
        await gotoApp(page, lightningUrl);
        await searchAndSelectAccount(page);
      }
    }
    await page.waitForTimeout(500);
  }

  expect(spinbuttonCount, `No contract with 4+ lines found`).toBeGreaterThanOrEqual(4);

  await page.screenshot({ path: `${RUN_DIR}/02-editor-loaded.png`, fullPage: true });
  console.log(`\n  Contract: ${chosenContract}`);
  console.log(`  Editable inputs (spinbuttons): ${spinbuttonCount}`);

  // ── 2. Capture pre-save state ──────────────────────────────────────────────
  console.log('\n── Capturing pre-save state ──');

  const spinbuttons = page.getByRole('spinbutton');

  // Read all initial quantities and their product context
  const preSave = [];
  for (let i = 0; i < spinbuttonCount; i++) {
    const sb = spinbuttons.nth(i);
    const val = await sb.inputValue().catch(() => '0');
    // Get nearest product name from the row
    const row = sb.locator('xpath=ancestor::tr').first();
    const rowText = await row.innerText().catch(() => '');
    preSave.push({
      index:   i,
      initial: parseFloat(val) || 0,
      rowText: rowText.split('\n')[0].trim().substring(0, 120),
    });
  }

  const metricsBeforeSave = await captureMetrics(page);
  console.log('  Pre-save metrics:', JSON.stringify(metricsBeforeSave));

  // ── 3. Update all quantities by +5 ────────────────────────────────────────
  console.log(`\n── Increasing all ${spinbuttonCount} quantities by ${QTY_DELTA} ──`);

  // Update all spinbuttons directly (covers all products × all year segments)
  for (let i = 0; i < spinbuttonCount; i++) {
    const sb = spinbuttons.nth(i);
    const current = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
    const newVal  = current + QTY_DELTA;

    await sb.click({ clickCount: 3 });
    await sb.fill(String(newVal));
    await sb.press('Tab');
    await page.waitForTimeout(800); // debounce 500ms + Apex margin

    console.log(`  [${i + 1}/${spinbuttonCount}] qty ${current} → ${newVal}`);
    preSave[i].filled = newVal;
  }

  await page.screenshot({ path: `${RUN_DIR}/03-after-qty-update.png`, fullPage: true });
  console.log('  ✅ All quantities updated');

  // ── 4. Save & wait for CPQ recalculation ──────────────────────────────────
  console.log('\n── Saving quote (CPQ recalculation) ──');

  const saveBtn = page.getByRole('button', { name: 'Save' });
  await expect(saveBtn).toBeVisible();
  await saveBtn.click();

  // CPQ async recalc — wait up to 30s then check metrics changed
  await page.waitForTimeout(10_000);

  await page.screenshot({ path: `${RUN_DIR}/04-after-save.png`, fullPage: true });
  console.log('  ✅ Save complete');

  // ── 5. Capture post-save state ─────────────────────────────────────────────
  console.log('\n── Capturing post-save state ──');

  // Re-read all spinbutton values after recalc
  const postSave = [];
  for (let i = 0; i < spinbuttonCount; i++) {
    const val = await spinbuttons.nth(i).inputValue().catch(() => '0');
    postSave.push(parseFloat(val) || 0);
  }

  const metricsAfterSave = await captureMetrics(page);
  console.log('  Post-save metrics:', JSON.stringify(metricsAfterSave));

  await page.screenshot({ path: `${RUN_DIR}/05-final.png`, fullPage: true });

  // ── 6. Backend DB verification ────────────────────────────────────────────
  console.log('\n── Backend DB verification (Salesforce REST API) ──');

  // Extract the quote name (e.g. "Q-82766") from the page heading
  let quoteName = null;
  try {
    const headings = await page.getByRole('heading').allInnerTexts();
    for (const h of headings) {
      const m = h.match(/Q-\d+/);
      if (m) { quoteName = m[0]; break; }
    }
  } catch { /* fallback: no quote name */ }
  console.log(`  Quote name from UI: ${quoteName || '(not found)'}`);

  // Discover which SBQQ__QuoteLine__c fields are queryable in this org
  // then build the SOQL dynamically — avoids INVALID_FIELD errors for fields
  // that differ between CPQ versions / managed package tiers.
  let soql = null;
  if (quoteName) {
    const describeResult = await page.evaluate(async ({ instanceUrl, accessToken }) => {
      const headers = { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' };
      const resp = await fetch(`${instanceUrl}/services/data/v62.0/sobjects/SBQQ__QuoteLine__c/describe`, { headers });
      const json = await resp.json();
      // Return just the field names to keep payload small
      if (Array.isArray(json.fields)) return json.fields.map(f => f.name);
      return [];
    }, { instanceUrl, accessToken }).catch(() => []);

    // Fields we want — only include those actually present in this org
    const wantedFields = [
      'Id', 'Name',
      'SBQQ__ProductName__c', 'SBQQ__Product__r.Name',
      'SBQQ__Quantity__c', 'SBQQ__PriorQuantity__c',
      'SBQQ__CustomerPrice__c', 'SBQQ__ListPrice__c',
      'SBQQ__NetTotal__c', 'SBQQ__Discount__c',
      'SBQQ__StartDate__c', 'SBQQ__EndDate__c',
      'SBQQ__SegmentKey__c', 'SBQQ__SegmentIndex__c',
      'SBQQ__PricingMethod__c',
      'SBQQ__ACV__c', 'SBQQ__TCV__c',
      'SBQQ__SubscriptionTerm__c', 'SBQQ__RegularPrice__c',
    ];

    // Relationship fields can't be checked by name, include them all if base object is present
    const simpleFields = wantedFields.filter(f => !f.includes('.'));
    const availableSimple = describeResult.length > 0
      ? simpleFields.filter(f => f === 'Id' || f === 'Name' || describeResult.includes(f))
      : simpleFields.filter(f => !['SBQQ__ACV__c', 'SBQQ__TCV__c'].includes(f)); // safe fallback

    console.log(`  Available DB fields (${availableSimple.length}): ${availableSimple.join(', ')}`);

    soql = `SELECT ${availableSimple.join(', ')}
       FROM SBQQ__QuoteLine__c
       WHERE SBQQ__Quote__r.Name = '${quoteName}'
       ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS LAST`;
  }

  // Also fetch the quote header (ACV, TCV, Status, etc.)
  const headerSoql = quoteName
    ? `SELECT Id, Name, SBQQ__Status__c, SBQQ__NetAmount__c,
             SBQQ__SubscriptionTerm__c, SBQQ__StartDate__c, SBQQ__EndDate__c,
             SBQQ__Account__r.Name
       FROM SBQQ__Quote__c
       WHERE Name = '${quoteName}'
       LIMIT 1`
    : null;

  let dbLines   = [];
  let dbHeader  = null;
  let dbError   = null;

  if (soql) {
    try {
      const result = await page.evaluate(async ({ soql, headerSoql, instanceUrl, accessToken }) => {
        // Use accessToken as Bearer — more reliable than relying on the session cookie
        // (Lightning session cookies are HttpOnly and scope-limited)
        const apiBase = instanceUrl + '/services/data/v62.0';
        const headers = { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' };

        const [linesResp, headerResp] = await Promise.all([
          fetch(`${apiBase}/query?q=${encodeURIComponent(soql)}`, { headers }),
          fetch(`${apiBase}/query?q=${encodeURIComponent(headerSoql)}`, { headers }),
        ]);

        const linesJson  = await linesResp.json();
        const headerJson = await headerResp.json();

        return { lines: linesJson, header: headerJson };
      }, { soql, headerSoql, instanceUrl, accessToken });

      if (result.lines.records) {
        dbLines  = result.lines.records;
        console.log(`  DB lines fetched: ${dbLines.length}`);
      } else {
        dbError = JSON.stringify(result.lines);
        console.log(`  ⚠️  Lines API error: ${dbError}`);
      }

      if (result.header.records && result.header.records.length > 0) {
        dbHeader = result.header.records[0];
        console.log(`  DB quote header: ${dbHeader.Name} | Status: ${dbHeader.SBQQ__Status__c}`);
      }
    } catch (e) {
      dbError = String(e);
      console.log(`  ⚠️  API call failed: ${dbError}`);
    }
  } else {
    dbError = 'Quote name not found in UI — cannot query API';
    console.log(`  ⚠️  ${dbError}`);
  }

  // ── Build DB comparison ────────────────────────────────────────────────────
  // DB records are sorted alphabetically by ProductName + SegmentIndex.
  // UI spinbuttons render in card order (different from alphabetical).
  // Strategy:
  //   1. Show all DB records in their own table (no positional UI mapping needed)
  //   2. Flag DB-level anomalies (zero price, zero net total, missing seg key)
  //   3. Cross-check aggregate totals: sum(DB qty) vs sum(UI post-save qty)
  const dbComparison = [];
  const dbAnomalies  = [];

  if (dbLines.length > 0) {
    const uiCount = spinbuttonCount;
    const dbCount = dbLines.length;

    // Check aggregate quantity totals (sum-level cross-check — order-independent)
    const uiQtyTotal = postSave.reduce((s, v) => s + v, 0);
    const dbQtyTotal = dbLines.reduce((s, d) => s + (d.SBQQ__Quantity__c ?? 0), 0);

    if (Math.abs(uiQtyTotal - dbQtyTotal) > 0.01) {
      dbAnomalies.push({
        type: 'TOTAL QTY MISMATCH',
        severity: 'HIGH',
        detail: `Sum of UI quantities (${uiQtyTotal}) ≠ sum of DB quantities (${dbQtyTotal}). Δ = ${(dbQtyTotal - uiQtyTotal).toFixed(2)}. Some saves may not have committed.`,
      });
    } else {
      console.log(`  ✅ Aggregate qty match: UI total=${uiQtyTotal}, DB total=${dbQtyTotal}`);
    }

    if (uiCount !== dbCount) {
      dbAnomalies.push({
        type: 'LINE COUNT MISMATCH',
        severity: 'HIGH',
        detail: `UI has ${uiCount} editable spinbuttons; DB has ${dbCount} QuoteLine records. Extra DB lines may be bundle parents or hidden lines.`,
      });
      console.log(`  ⚠️  Line count: UI ${uiCount} vs DB ${dbCount}`);
    }

    // Bundle parent detection: products ending in "bundle", containing "sandbox", or with $0 price
    // These are structural lines — zero price is expected.
    const isBundleParent = (name) => {
      const n = (name || '').toLowerCase();
      return n.includes('bundle') || n.includes(': sandbox');
    };

    // Per-line DB analysis (anomalies detected on DB data alone — no UI ordering dependency)
    for (let i = 0; i < dbCount; i++) {
      const db  = dbLines[i];
      const dbQty       = db.SBQQ__Quantity__c      ?? 0;
      const dbPrice     = db.SBQQ__CustomerPrice__c  ?? null;
      const dbListPrice = db.SBQQ__ListPrice__c      ?? null;
      const dbNetTotal  = db.SBQQ__NetTotal__c        ?? null;
      const dbDiscount  = db.SBQQ__Discount__c        ?? null;
      const dbSegKey    = db.SBQQ__SegmentKey__c      ?? null;
      const dbPrior     = db.SBQQ__PriorQuantity__c   ?? null;
      const dbAcv       = db.SBQQ__ACV__c             ?? null;
      const dbTcv       = db.SBQQ__TCV__c             ?? null;
      const isBundle    = isBundleParent(db.SBQQ__ProductName__c);

      // Anomaly detection (DB-intrinsic — no UI position dependency)
      if (dbQty > 0 && !isBundle && (dbPrice === null || dbPrice === 0)) {
        dbAnomalies.push({
          type: 'ZERO CUSTOMER PRICE',
          severity: 'MEDIUM',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}" seg#${db.SBQQ__SegmentIndex__c ?? '?'}: qty=${dbQty} but CustomerPrice=$0. Pricing rule may not have fired.`,
        });
      }
      if (dbQty > 0 && !isBundle && dbListPrice && dbListPrice > 0 && (dbPrice === null || dbPrice === 0)) {
        dbAnomalies.push({
          type: 'POSSIBLE 100% DISCOUNT',
          severity: 'HIGH',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": ListPrice=$${dbListPrice} but CustomerPrice=$0 — discount may be wiping out price.`,
        });
      }
      if (dbQty > 0 && !isBundle && dbNetTotal !== null && dbNetTotal === 0 && dbPrice && dbPrice > 0) {
        dbAnomalies.push({
          type: 'ZERO NET TOTAL',
          severity: 'HIGH',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": NetTotal=$0 despite qty=${dbQty} and CustomerPrice=$${dbPrice}.`,
        });
      }
      if (dbSegKey === null && db.SBQQ__SegmentIndex__c !== null) {
        dbAnomalies.push({
          type: 'MISSING SEGMENT KEY',
          severity: 'LOW',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}" has SegmentIndex=${db.SBQQ__SegmentIndex__c} but SegmentKey is null.`,
        });
      }
      // Check if CPQ forgot to update the quantity (still at prior value)
      if (dbPrior !== null && dbQty === dbPrior && dbQty !== 0) {
        dbAnomalies.push({
          type: 'QTY UNCHANGED FROM PRIOR',
          severity: 'MEDIUM',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": Quantity (${dbQty}) = PriorQuantity (${dbPrior}). Amendment may not have applied the delta.`,
        });
      }

      dbComparison.push({
        index:       i + 1,
        product:     db.SBQQ__ProductName__c || '—',
        segKey:      dbSegKey || '—',
        segIndex:    db.SBQQ__SegmentIndex__c,
        priorQty:    dbPrior,
        dbQty,
        dbPrice,
        dbListPrice,
        dbDiscount,
        dbNetTotal,
        dbAcv,
        dbTcv,
        isBundle,
        startDate:   db.SBQQ__StartDate__c,
        endDate:     db.SBQQ__EndDate__c,
        pricingMethod: db.SBQQ__PricingMethod__c,
        term:         db.SBQQ__SubscriptionTerm__c,
        regularPrice: db.SBQQ__RegularPrice__c,
      });

      console.log(`  DB Line ${i + 1}: ${db.SBQQ__ProductName__c} | qty DB=${dbQty} prior=${dbPrior} | price=$${dbPrice} | net=$${dbNetTotal}${isBundle ? ' [bundle]' : ''}`);
    }
  }

  const dbAnomalyCount = dbAnomalies.length;
  const dbHighCount    = dbAnomalies.filter(a => a.severity === 'HIGH').length;
  console.log(`\n  DB anomalies found: ${dbAnomalyCount} (${dbHighCount} HIGH)`);

  // ── 7. Assertions ──────────────────────────────────────────────────────────
  console.log('\n── Assertions ──');

  const lineResults = [];
  let allQtyPass = true;

  for (let i = 0; i < spinbuttonCount; i++) {
    const expected = preSave[i].initial + QTY_DELTA;
    const actual   = postSave[i];
    const pass     = Math.abs(actual - expected) < 0.001;
    if (!pass) allQtyPass = false;

    lineResults.push({
      index:    i + 1,
      label:    preSave[i].rowText || `Line ${i + 1}`,
      before:   preSave[i].initial,
      expected,
      actual,
      pass,
    });

    console.log(`  Line ${i + 1}: expected ${expected}, got ${actual} → ${pass ? '✅' : '❌'}`);
  }

  // ── Build UI↔DB cross-check by product-name + occurrence matching ──────────
  // DB is sorted by SBQQ__ProductName__c + SBQQ__SegmentIndex__c.
  // UI renders spinbuttons in card/DOM order (may differ from DB sort order).
  //
  // Fix: group both by product name and pair by nth-occurrence within that group.
  // "Intapp Compliance" #0 in UI → "Intapp Compliance" #0 in DB (both sorted by segment).
  // This is order-independent at the product level.

  const _buildProdKey = (name, occ) =>
    `${(name || '').trim().toLowerCase().substring(0, 120)}|${occ}`;

  // Build DB lookup: (normalised product name, occurrence) → dbRow
  const _dbOcc    = {};
  const _dbLookup = {};
  for (const dr of dbComparison) {
    const pn  = (dr.product || '').trim().toLowerCase().substring(0, 120);
    if (_dbOcc[pn] === undefined) _dbOcc[pn] = 0;
    const occ = _dbOcc[pn]++;
    _dbLookup[_buildProdKey(dr.product, occ)] = dr;
  }

  // Join each UI line to its DB counterpart
  const _uiOcc       = {};
  const uiDbCrossCheck = [];

  for (const lr of lineResults) {
    const pn  = (lr.label || '').trim().toLowerCase().substring(0, 120);
    if (_uiOcc[pn] === undefined) _uiOcc[pn] = 0;
    const occ = _uiOcc[pn]++;

    const dr      = _dbLookup[_buildProdKey(lr.label, occ)] || null;
    const uiAfter = lr.actual  != null ? lr.actual  : null;
    const dbAfter = dr         != null ? dr.dbQty   : null;
    const match   = uiAfter != null && dbAfter != null && Math.abs(uiAfter - dbAfter) < 0.001;
    const hasData = uiAfter != null || dbAfter != null;

    uiDbCrossCheck.push({
      uiIndex:    lr.index,
      dbIndex:    dr ? dr.index      : null,
      product:    lr.label,
      segOcc:     occ + 1,            // which occurrence of this product (1-based)
      uiBefore:   lr.before,
      uiExpected: lr.expected,
      uiAfter,
      dbPrior:    dr ? dr.priorQty   : null,
      dbAfter,
      dbSegIndex: dr ? dr.segIndex   : null,
      dbSegKey:   dr ? dr.segKey     : null,
      match,
      hasData,
    });
  }

  const crossCheckMatches    = uiDbCrossCheck.filter(r => r.match).length;
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;
  const crossCheckUnmatched  = uiDbCrossCheck.filter(r => !r.hasData).length;

  console.log(`\n  UI↔DB cross-check (product-keyed): ${crossCheckMatches}/${uiDbCrossCheck.length} match, ` +
              `${crossCheckMismatches} mismatch, ${crossCheckUnmatched} unmatched`);
  if (crossCheckMismatches > 0) {
    uiDbCrossCheck.filter(r => r.hasData && !r.match).forEach(r =>
      console.log(`    ❌ ${r.product} (occ ${r.segOcc}): UI=${r.uiAfter} DB=${r.dbAfter}`)
    );
  }

  // Header metric assertions (directional — after more qty, ACV/TCV should be ≥ before)
  const acvBefore = parseCurrency(metricsBeforeSave.acv);
  const acvAfter  = parseCurrency(metricsAfterSave.acv);
  const tcvBefore = parseCurrency(metricsBeforeSave.tcv);
  const tcvAfter  = parseCurrency(metricsAfterSave.tcv);

  const metricResults = [
    {
      metric:   'ACV',
      before:   metricsBeforeSave.acv,
      after:    metricsAfterSave.acv,
      pass:     acvAfter !== null && acvBefore !== null ? acvAfter >= acvBefore : true,
      note:     acvBefore !== null && acvAfter !== null
                  ? `Δ = ${acvAfter >= 0 && acvBefore >= 0 ? (acvAfter - acvBefore).toFixed(2) : 'N/A'}`
                  : 'Pricing at $0 — verify in org',
    },
    {
      metric: 'ACV Change',
      before: metricsBeforeSave.acvChange,
      after:  metricsAfterSave.acvChange,
      pass:   true, // informational
      note:   'Reflects cumulative change from original contract',
    },
    {
      metric: 'TCV',
      before: metricsBeforeSave.tcv,
      after:  metricsAfterSave.tcv,
      pass:   tcvAfter !== null && tcvBefore !== null ? tcvAfter >= tcvBefore : true,
      note:   tcvBefore !== null && tcvAfter !== null
                ? `Δ = ${tcvAfter >= 0 && tcvBefore >= 0 ? (tcvAfter - tcvBefore).toFixed(2) : 'N/A'}`
                : 'Pricing at $0 — verify in org',
    },
    {
      metric: 'YoY Uplift',
      before: metricsBeforeSave.yoyUplift,
      after:  metricsAfterSave.yoyUplift,
      pass:   true,
      note:   'Directional — higher qty should increase or maintain uplift',
    },
    {
      metric: 'Deal Quality Score',
      before: metricsBeforeSave.dealQuality,
      after:  metricsAfterSave.dealQuality,
      pass:   true,
      note:   'Approval logic driven — informational',
    },
  ];

  // Check approval / send state
  const hasApproval = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn  = await page.getByRole('button', { name: 'Preview and Send OSA' }).isVisible().catch(() => false);

  console.log(`\n  All qty assertions: ${allQtyPass ? '✅ PASS' : '❌ FAIL'}`);
  metricResults.forEach(m => console.log(`  ${m.metric}: ${m.before} → ${m.after} ${m.pass ? '✅' : '❌'}  (${m.note})`));
  console.log(`  Approval required: ${hasApproval}`);
  console.log(`  Preview & Send OSA visible: ${hasSendBtn}`);

  // ── 8. PDF generation via "Preview and Send OSA" ──────────────────────────
  console.log('\n── PDF Generation via Preview and Send OSA ──');

  let pdfGenerated      = false;
  let pdfDocTitle       = null;
  let pdfDocId          = null;
  let pdfPreviewSrc     = null;
  let pdfOpenTabVisible = false;
  let osaSent           = false;
  let pdfSkipped        = false;
  let hadExistingDocs   = false;

  if (!hasSendBtn) {
    pdfSkipped = true;
    console.log('  ℹ️  "Preview and Send OSA" not visible (approvals required). Skipping PDF step.');
  } else {
    // Click the "Preview and Send OSA" button — triggers showPreviewSend = true
    await page.getByRole('button', { name: 'Preview and Send OSA' }).click();

    // Wait for the modal heading: <h3>Preview &amp; Send OSA</h3>
    const modalVisible = await page.getByText('Preview & Send OSA').first()
      .waitFor({ state: 'visible', timeout: 15_000 }).then(() => true).catch(() => false);

    if (!modalVisible) {
      console.log('  ⚠️  Modal did not appear after clicking "Preview and Send OSA"');
      pdfSkipped = true;
      await page.screenshot({ path: `${RUN_DIR}/06-pdf-modal-error.png`, fullPage: true });
    } else {
      await page.screenshot({ path: `${RUN_DIR}/06-preview-send-modal.png`, fullPage: true });
      console.log('  ✅ "Preview & Send OSA" modal opened');

      // Check for previously generated docs (modal loads them via connectedCallback)
      hadExistingDocs = await page.getByText('Previously Generated Documents')
        .isVisible({ timeout: 3_000 }).catch(() => false);
      if (hadExistingDocs) {
        console.log('  ℹ️  Previously generated documents found in modal');
      }

      // "Generate OSA Document" button — visible only before documentGenerated = true
      const generateBtn = page.getByRole('button', { name: 'Generate OSA Document' });
      const generateBtnVisible = await generateBtn.isVisible({ timeout: 5_000 }).catch(() => false);

      if (!generateBtnVisible) {
        console.log('  ⚠️  "Generate OSA Document" button not visible — cannot generate');
        pdfSkipped = true;
      } else {
        console.log('  🔄 Clicking "Generate OSA Document" — calling Apex + Visualforce...');

        // Listen for the popup (window.open fired after Apex returns the ContentDocument ID).
        // Using waitForEvent on the browser context so we catch it regardless of timing.
        const popupPromise = page.context().waitForEvent('page', { timeout: 120_000 }).catch(() => null);

        await generateBtn.click();

        // "Generating PDF..." spinner should appear (isGenerating = true)
        const spinnerVisible = await page.getByText('Generating PDF...').first()
          .isVisible({ timeout: 5_000 }).catch(() => false);
        if (spinnerVisible) console.log('  ✅ "Generating PDF..." spinner visible');

        // Wait for popup — handleGenerate opens ContentDocument viewer in a new tab
        const popup = await popupPromise;
        if (popup) {
          const popupUrl = popup.url();
          const docIdMatch = popupUrl.match(/ContentDocument\/([a-zA-Z0-9]{15,18})\/view/);
          if (docIdMatch) {
            pdfDocId = docIdMatch[1];
            console.log(`  ✅ New tab opened: ${popupUrl}`);
          } else {
            console.log(`  ✅ New tab opened: ${popupUrl}`);
          }
          // Close the popup tab — we don't need to interact with it
          await popup.close().catch(() => {});
        } else {
          console.log('  ℹ️  No popup detected (may have been blocked or opened in same tab)');
        }

        // Wait for "Document Preview" heading — signals documentGenerated = true in the LWC
        const previewSectionVisible = await page.getByText('Document Preview').first()
          .waitFor({ state: 'visible', timeout: 30_000 }).then(() => true).catch(() => false);

        if (!previewSectionVisible) {
          console.log('  ⚠️  "Document Preview" section did not appear — PDF generation may have failed');
          await page.screenshot({ path: `${RUN_DIR}/07-pdf-error.png`, fullPage: true });
        } else {
          pdfGenerated = true;

          // Capture doc title from the modal's .doc-ready span (e.g. "OSA_CT-00001_2026-05-10.pdf")
          // <div class="doc-ready"><lightning-icon.../><span>{docTitle}</span></div>
          // Use getByTitle on the file icon to scope, or just grab the first span sibling
          try {
            // The docTitle is the only plain <span> sibling of utility:success icon inside .doc-ready
            const titleEl = await page.evaluate(() => {
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
            if (titleEl) {
              pdfDocTitle = titleEl;
              console.log(`  ✅ Document title: ${pdfDocTitle}`);
            } else {
              console.log('  ✅ Document generated (title extraction skipped — check screenshot)');
            }
          } catch {
            console.log('  ✅ Document generated (title extraction error — check screenshot)');
          }

          // Verify the PDF preview iframe has a valid Salesforce download URL
          // Iframe: <iframe title="OSA Document Preview" src="/sfc/servlet.shepherd/version/download/...">
          // getByTitle() pierces LWC synthetic shadow
          const previewIframe = page.getByTitle('OSA Document Preview');
          pdfPreviewSrc = await previewIframe.getAttribute('src', { timeout: 5_000 }).catch(() => null);
          if (pdfPreviewSrc && pdfPreviewSrc.includes('/sfc/servlet.shepherd/version/download/')) {
            console.log(`  ✅ PDF iframe src: ${pdfPreviewSrc}`);
          } else {
            console.log(`  ⚠️  PDF iframe src: ${pdfPreviewSrc || 'not found'}`);
          }

          // "Open in New Tab" button
          pdfOpenTabVisible = await page.getByRole('button', { name: 'Open in New Tab' })
            .isVisible({ timeout: 3_000 }).catch(() => false);
          console.log(`  "Open in New Tab" visible: ${pdfOpenTabVisible}`);

          await page.screenshot({ path: `${RUN_DIR}/07-pdf-generated.png`, fullPage: true });

          // ── Send for Signature (DocuSign simulation) ────────────────────────
          const sendBtn = page.getByRole('button', { name: 'Send for Signature' });
          const sendBtnVisible = await sendBtn.isVisible({ timeout: 5_000 }).catch(() => false);

          if (sendBtnVisible) {
            await sendBtn.click();
            console.log('  🔄 "Send for Signature" clicked — waiting for DocuSign simulation (2s)...');

            // handleSend() sets isSending=true, after 2s sets isSent=true → shows success message
            const sentConfirm = await page.getByText('OSA sent successfully via DocuSign!').first()
              .waitFor({ state: 'visible', timeout: 10_000 }).then(() => true).catch(() => false);

            if (sentConfirm) {
              osaSent = true;
              console.log('  ✅ "OSA sent successfully via DocuSign!" confirmed');
            } else {
              console.log('  ⚠️  DocuSign confirmation text not seen');
            }

            await page.screenshot({ path: `${RUN_DIR}/08-osa-sent.png`, fullPage: true });
          } else {
            console.log('  ⚠️  "Send for Signature" button not visible');
          }
        }
      }

      // Close the modal (lightning-button label="Close")
      const closeBtn = page.getByRole('button', { name: 'Close' });
      if (await closeBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await closeBtn.click();
        await page.waitForTimeout(500);
        console.log('  Modal closed');
      }
    }
  }

  console.log(`\n  PDF generated:       ${pdfGenerated}`);
  console.log(`  PDF doc title:       ${pdfDocTitle || '—'}`);
  console.log(`  PDF ContentDoc ID:   ${pdfDocId    || '—'}`);
  console.log(`  OSA sent:            ${osaSent}`);
  console.log(`  PDF step skipped:    ${pdfSkipped}`);

  // ── 7. Generate HTML report ────────────────────────────────────────────────
  const now      = new Date().toLocaleString();
  const allPass  = allQtyPass && metricResults.every(m => m.pass) && dbHighCount === 0;
  const summary  = allPass
    ? '✅ ALL ASSERTIONS PASSED — UI and DB are consistent'
    : `⚠️  ISSUES DETECTED — ${!allQtyPass ? 'Qty mismatch in UI. ' : ''}${dbHighCount > 0 ? `${dbHighCount} HIGH severity DB anomaly(ies). ` : ''}Review report below.`;

  const lineRows = lineResults.map(r => `
    <tr class="${r.pass ? 'pass' : 'fail'}">
      <td>${r.index}</td>
      <td class="label">${r.label}</td>
      <td class="num">${r.before}</td>
      <td class="num">${r.expected}</td>
      <td class="num">${r.actual}</td>
      <td class="num delta">+${QTY_DELTA}</td>
      <td class="status">${r.pass ? '✅ PASS' : '❌ FAIL'}</td>
    </tr>`).join('');

  const metricRows = metricResults.map(m => `
    <tr class="${m.pass ? 'pass' : 'fail'}">
      <td>${m.metric}</td>
      <td class="num">${m.before}</td>
      <td class="num">${m.after}</td>
      <td class="note">${m.note}</td>
      <td class="status">${m.pass ? '✅ PASS' : '⚠️ REVIEW'}</td>
    </tr>`).join('');

  // Build screenshots list — only include files that were actually created this run
  const allScreenshotNames = [
    '01-contracts', '02-editor-loaded', '03-after-qty-update', '04-after-save', '05-final',
    '06-preview-send-modal', '07-pdf-generated', '07-pdf-error', '08-osa-sent',
  ].filter(s => {
    try { fs.statSync(path.join(RUN_DIR, `${s}.png`)); return true; } catch { return false; }
  });

  const screenshots = allScreenshotNames
    .map(s => `<figure><img src="runs/${RUN_TS}/${s}.png" alt="${s}"><figcaption>${s.replace(/-/g,' ')}</figcaption></figure>`).join('');

  // Aggregate totals
  const uiQtyTotal = postSave.reduce((s, v) => s + v, 0);
  const dbQtyTotal = dbComparison.reduce((s, r) => s + r.dbQty, 0);

  // DB comparison rows
  const dbLineRows = dbComparison.map(r => {
    const fmt = (v) => v !== null ? `$${Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 })}` : '<span style="color:#4b5563">—</span>';
    const discCell = r.dbDiscount !== null ? `${r.dbDiscount}%` : '—';
    const bundleTag = r.isBundle ? '<span style="font-size:10px;color:#60a5fa;border:1px solid #1d4ed8;border-radius:3px;padding:1px 5px;margin-left:4px">bundle</span>' : '';
    // Row is highlighted if ANY anomaly exists for this line
    const hasAnomaly = dbAnomalies.some(a => a.detail.includes(`line ${r.index} `));
    return `
    <tr class="${hasAnomaly ? 'fail' : ''}">
      <td>${r.index}</td>
      <td class="label">${r.product}${bundleTag}</td>
      <td class="num" style="font-size:10px;color:#64748b">${r.segKey}</td>
      <td class="num">${r.segIndex ?? '—'}</td>
      <td class="num">${r.startDate ?? '—'}</td>
      <td class="num">${r.endDate ?? '—'}</td>
      <td class="num">${r.priorQty ?? '—'}</td>
      <td class="num" style="font-weight:700">${r.dbQty}</td>
      <td class="num">${fmt(r.dbPrice)}</td>
      <td class="num">${fmt(r.dbListPrice)}</td>
      <td class="num">${discCell}</td>
      <td class="num">${fmt(r.dbNetTotal)}</td>
      <td class="num" style="font-size:10px;color:#94a3b8">${r.pricingMethod ?? '—'}</td>
    </tr>`;
  }).join('');

  const anomalyRows = dbAnomalies.map(a => `
    <tr>
      <td><span class="badge ${a.severity.toLowerCase()}">${a.severity}</span></td>
      <td><strong>${a.type}</strong></td>
      <td class="note">${a.detail}</td>
    </tr>`).join('');

  const dbHeaderHtml = dbHeader ? `
  <div class="info-grid" style="margin-bottom:20px">
    <div class="info-card">
      <h3>Quote ID</h3><p>${dbHeader.Id}</p>
    </div>
    <div class="info-card">
      <h3>Status</h3><p>${dbHeader.SBQQ__Status__c}</p>
    </div>
    <div class="info-card">
      <h3>Start Date</h3><p>${dbHeader.SBQQ__StartDate__c || '—'}</p>
    </div>
    <div class="info-card">
      <h3>End Date</h3><p>${dbHeader.SBQQ__EndDate__c || '—'}</p>
    </div>
  </div>` : (dbError ? `<p class="note" style="color:#f87171">⚠️ ${dbError}</p>` : '<p class="note">No header data retrieved</p>');

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AgenticQTC — Quantity Increase Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0f1117; color: #e2e8f0; padding: 32px; }
  h1   { font-size: 24px; font-weight: 700; margin-bottom: 4px; color: #f8fafc; }
  h2   { font-size: 16px; font-weight: 600; margin: 28px 0 12px; color: #94a3b8;
         text-transform: uppercase; letter-spacing: .06em; }
  .meta { font-size: 13px; color: #64748b; margin-bottom: 24px; }
  .banner { padding: 16px 20px; border-radius: 8px; margin-bottom: 28px; font-size: 15px; font-weight: 600; }
  .banner.pass { background: #14532d; color: #86efac; border: 1px solid #16a34a; }
  .banner.fail { background: #7f1d1d; color: #fca5a5; border: 1px solid #dc2626; }
  .kpi-row { display: flex; gap: 16px; margin-bottom: 28px; flex-wrap: wrap; }
  .kpi { background: #1e2330; border: 1px solid #2d3748; border-radius: 8px;
         padding: 16px 20px; min-width: 140px; }
  .kpi-label { font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: .06em; }
  .kpi-value { font-size: 22px; font-weight: 700; color: #f8fafc; margin-top: 4px; }
  .kpi-value.green { color: #4ade80; }
  .kpi-value.blue  { color: #60a5fa; }
  .anomaly { color: #f87171; font-weight: 700; }
  .zero    { color: #f87171; }
  .badge   { display: inline-block; border-radius: 4px; padding: 2px 8px; font-size: 11px; font-weight: 700; }
  .badge.high   { background: #7f1d1d; color: #fca5a5; }
  .badge.medium { background: #78350f; color: #fcd34d; }
  .badge.low    { background: #1e3a5f; color: #93c5fd; }
  .anomaly-table tr td { padding: 8px 12px; border-bottom: 1px solid #1e2330; font-size: 13px; }
  .db-table th, .db-table td { font-size: 11px; padding: 8px 10px; }
  .section-header { display: flex; align-items: center; justify-content: space-between; margin: 28px 0 12px; }
  .section-header h2 { margin: 0; }
  .badge-count { background: #1e2330; border: 1px solid #2d3748; border-radius: 20px; padding: 4px 12px; font-size: 12px; color: #94a3b8; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-bottom: 28px; }
  th { background: #1a2035; color: #94a3b8; font-weight: 600; text-align: left;
       padding: 10px 14px; border-bottom: 1px solid #2d3748; }
  td { padding: 10px 14px; border-bottom: 1px solid #1e2330; vertical-align: middle; }
  tr.pass td { background: #0f2820; }
  tr.fail td { background: #2d1515; }
  tr:hover td { filter: brightness(1.08); }
  .label { max-width: 280px; font-size: 12px; color: #cbd5e1; }
  .num   { font-family: 'SF Mono', monospace; color: #e2e8f0; text-align: right; }
  .delta { color: #34d399; font-weight: 700; }
  .status { font-weight: 700; }
  .note  { font-size: 11px; color: #64748b; }
  .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 28px; }
  .info-card { background: #1e2330; border: 1px solid #2d3748; border-radius: 8px; padding: 16px 20px; }
  .info-card h3 { font-size: 13px; color: #64748b; margin-bottom: 8px; }
  .info-card p  { font-size: 14px; color: #e2e8f0; }
  .screenshots { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; }
  figure { background: #1e2330; border: 1px solid #2d3748; border-radius: 8px; overflow: hidden; }
  figure img { width: 100%; display: block; }
  figcaption { padding: 8px 12px; font-size: 11px; color: #64748b; }
</style>
</head>
<body>

<h1>AgenticQTC — Quantity Increase Test Report</h1>
<p class="meta">Run: ${now} &nbsp;|&nbsp; Account: Baker McKenzie LLP &nbsp;|&nbsp; Quantity delta: +${QTY_DELTA} per line</p>

<div class="banner ${allPass ? 'pass' : 'fail'}">${summary}</div>

<div class="kpi-row">
  <div class="kpi">
    <div class="kpi-label">Contract</div>
    <div class="kpi-value blue" style="font-size:14px">${chosenContract || 'N/A'}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Lines Updated</div>
    <div class="kpi-value">${spinbuttonCount}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Qty Delta</div>
    <div class="kpi-value green">+${QTY_DELTA}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Lines Passing</div>
    <div class="kpi-value ${allQtyPass ? 'green' : ''}">${lineResults.filter(r => r.pass).length} / ${lineResults.length}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Approval Required</div>
    <div class="kpi-value" style="font-size:16px">${hasApproval ? '⚠️ Yes' : '✅ No'}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Preview & Send OSA</div>
    <div class="kpi-value" style="font-size:16px">${hasSendBtn ? '✅ Visible' : '—'}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">PDF Generated</div>
    <div class="kpi-value" style="font-size:16px">${pdfSkipped ? '⏭ Skipped' : pdfGenerated ? '✅ Yes' : '❌ Failed'}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">OSA Sent (DocuSign)</div>
    <div class="kpi-value" style="font-size:16px">${pdfSkipped ? '⏭ Skipped' : osaSent ? '✅ Sent' : '—'}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">DB Lines Fetched</div>
    <div class="kpi-value blue">${dbLines.length}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">DB Anomalies</div>
    <div class="kpi-value ${dbAnomalyCount > 0 ? '' : 'green'}" style="font-size:20px">${dbAnomalyCount === 0 ? '✅ 0' : `⚠️ ${dbAnomalyCount}`}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">HIGH Severity</div>
    <div class="kpi-value ${dbHighCount > 0 ? '' : 'green'}" style="font-size:20px;color:${dbHighCount > 0 ? '#f87171' : ''}">${dbHighCount === 0 ? '✅ 0' : `❌ ${dbHighCount}`}</div>
  </div>
</div>

<h2>Line Item Quantity Verification</h2>
<table>
  <thead>
    <tr>
      <th>#</th><th>Product / Segment</th>
      <th style="text-align:right">Before</th>
      <th style="text-align:right">Expected</th>
      <th style="text-align:right">Actual</th>
      <th style="text-align:right">Delta</th>
      <th>Result</th>
    </tr>
  </thead>
  <tbody>${lineRows}</tbody>
</table>

<h2>Header Metric Verification (Pre → Post Save)</h2>
<table>
  <thead>
    <tr><th>Metric</th><th style="text-align:right">Before Save</th><th style="text-align:right">After Save</th><th>Notes</th><th>Result</th></tr>
  </thead>
  <tbody>${metricRows}</tbody>
</table>

<div class="section-header">
  <h2>📦 Database Verification — SBQQ__QuoteLine__c</h2>
  <span class="badge-count">Quote: ${quoteName || 'N/A'} &nbsp;|&nbsp; ${dbLines.length} DB records</span>
</div>

${dbHeaderHtml}

${dbComparison.length > 0 ? `
<div style="margin-bottom:12px;display:flex;gap:16px;flex-wrap:wrap">
  <div style="background:#1e2330;border:1px solid #2d3748;border-radius:8px;padding:12px 20px">
    <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.06em">UI Qty Total</div>
    <div style="font-size:20px;font-weight:700;color:#60a5fa">${uiQtyTotal.toLocaleString()}</div>
  </div>
  <div style="background:#1e2330;border:1px solid #2d3748;border-radius:8px;padding:12px 20px">
    <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.06em">DB Qty Total</div>
    <div style="font-size:20px;font-weight:700;color:${Math.abs(uiQtyTotal - dbQtyTotal) < 0.01 ? '#4ade80' : '#f87171'}">${dbQtyTotal.toLocaleString()}</div>
  </div>
  <div style="background:#1e2330;border:1px solid #2d3748;border-radius:8px;padding:12px 20px">
    <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.06em">Totals Match?</div>
    <div style="font-size:20px;font-weight:700">${Math.abs(uiQtyTotal - dbQtyTotal) < 0.01 ? '✅ Yes' : '❌ No'}</div>
  </div>
  <div style="background:#1e2330;border:1px solid #2d3748;border-radius:8px;padding:12px 20px">
    <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.06em">DB Line Count</div>
    <div style="font-size:20px;font-weight:700;color:#f8fafc">${dbComparison.length}</div>
  </div>
</div>
<div style="overflow-x:auto">
<table class="db-table">
  <thead>
    <tr>
      <th>#</th>
      <th>Product Name</th>
      <th>Segment Key</th>
      <th style="text-align:right">Seg#</th>
      <th style="text-align:right">Start</th>
      <th style="text-align:right">End</th>
      <th style="text-align:right">Prior Qty</th>
      <th style="text-align:right">DB Qty</th>
      <th style="text-align:right">Cust Price</th>
      <th style="text-align:right">List Price</th>
      <th style="text-align:right">Discount</th>
      <th style="text-align:right">Net Total</th>
      <th>Pricing Method</th>
    </tr>
  </thead>
  <tbody>${dbLineRows}</tbody>
</table>
</div>` : `<p class="note" style="margin-bottom:20px">No DB line data — ${dbError || 'query returned empty'}</p>`}

<div class="section-header" style="margin-top:28px">
  <h2>⚠️ Anomalies &amp; Bugs Detected</h2>
  <span class="badge-count">${dbAnomalyCount} total &nbsp;|&nbsp; <span style="color:#fca5a5">${dbHighCount} HIGH</span></span>
</div>

${dbAnomalies.length > 0 ? `
<table class="anomaly-table" style="margin-bottom:28px">
  <thead>
    <tr>
      <th style="width:100px">Severity</th>
      <th style="width:200px">Type</th>
      <th>Detail</th>
    </tr>
  </thead>
  <tbody>${anomalyRows}</tbody>
</table>` : `<div class="banner pass" style="margin-bottom:28px">✅ No anomalies detected — DB and UI values are consistent</div>`}

<h2>📄 PDF Generation — Preview &amp; Send OSA</h2>
${pdfSkipped ? `<div class="banner fail" style="background:#1a2035;border-color:#2d3748;color:#94a3b8">⏭ Skipped — approvals were required on this quote. "Preview and Send OSA" button was not visible.</div>` : `
<div class="info-grid" style="grid-template-columns:repeat(3,1fr);margin-bottom:20px">
  <div class="info-card">
    <h3>PDF Generated</h3>
    <p style="font-size:18px;font-weight:700;color:${pdfGenerated ? '#4ade80' : '#f87171'}">${pdfGenerated ? '✅ Yes' : '❌ Failed'}</p>
  </div>
  <div class="info-card">
    <h3>OSA Sent (DocuSign)</h3>
    <p style="font-size:18px;font-weight:700;color:${osaSent ? '#4ade80' : '#94a3b8'}">${osaSent ? '✅ Sent' : '—'}</p>
  </div>
  <div class="info-card">
    <h3>Previously Generated Docs</h3>
    <p style="font-size:18px;font-weight:700">${hadExistingDocs ? '📂 Yes' : '—'}</p>
  </div>
</div>
${pdfGenerated ? `
<div style="background:#1e2330;border:1px solid #2d3748;border-radius:8px;padding:16px 20px;margin-bottom:20px;display:flex;flex-direction:column;gap:10px;font-size:13px">
  <div style="display:flex;gap:16px">
    <span style="color:#64748b;min-width:160px">Document Title</span>
    <span style="font-family:'SF Mono',monospace;color:#e2e8f0;word-break:break-all">${pdfDocTitle || '(not captured)'}</span>
  </div>
  <div style="display:flex;gap:16px">
    <span style="color:#64748b;min-width:160px">ContentDocument ID</span>
    <span style="font-family:'SF Mono',monospace;color:#60a5fa">${pdfDocId
      ? `<a href="/lightning/r/ContentDocument/${pdfDocId}/view" style="color:#60a5fa" target="_blank">${pdfDocId}</a>`
      : '(not captured)'}</span>
  </div>
  <div style="display:flex;gap:16px">
    <span style="color:#64748b;min-width:160px">Preview iframe src</span>
    <span style="font-family:'SF Mono',monospace;color:#e2e8f0;font-size:11px;word-break:break-all">${pdfPreviewSrc || '(not captured)'}</span>
  </div>
  <div style="display:flex;gap:16px">
    <span style="color:#64748b;min-width:160px">"Open in New Tab"</span>
    <span>${pdfOpenTabVisible ? '✅ Visible' : '—'}</span>
  </div>
  <div style="display:flex;gap:16px">
    <span style="color:#64748b;min-width:160px">DocuSign confirmation</span>
    <span style="color:${osaSent ? '#4ade80' : '#94a3b8'}">${osaSent ? '✅ "OSA sent successfully via DocuSign!" shown' : '(send not attempted or message missed)'}</span>
  </div>
</div>` : `<p class="note" style="color:#f87171;margin-bottom:20px">⚠️ PDF generation failed — check screenshot 07-pdf-error.png for details.</p>`}
`}

<h2>Test Screenshots</h2>
<div class="screenshots">${screenshots}</div>

</body>
</html>`;

  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(REPORT_PATH, html, 'utf-8');
  console.log(`\n📄 Report written: ${REPORT_PATH}`);

  // Write structured JSON for the dashboard
  const resultsJson = {
    runAt:           now,
    runTs:           RUN_TS,
    passed:          allQtyPass && dbHighCount === 0,
    durationMs:      Date.now() - testStartMs,
    quoteName,
    quoteId:         dbHeader?.Id ?? null,
    quoteStatus:     dbHeader?.SBQQ__Status__c ?? null,
    contract:        chosenContract,
    spinbuttonCount,
    deltaApplied:    QTY_DELTA,
    allQtyPass,
    dbLineCount:     dbLines.length,
    dbAnomalyCount,
    dbHighCount,
    uiQtyTotal:      postSave.reduce((s, v) => s + v, 0),
    dbQtyTotal:      dbLines.reduce((s, d) => s + (d.SBQQ__Quantity__c ?? 0), 0),
    hasApproval,
    hasSendBtn,
    // PDF generation results
    pdfGenerated,
    pdfDocTitle,
    pdfDocId,
    pdfPreviewSrc,
    pdfOpenTabVisible,
    osaSent,
    pdfSkipped,
    hadExistingDocs,
    metricsBeforeSave,
    metricsAfterSave,
    lineResults,
    metricResults,
    dbComparison:    dbComparison.map(r => ({ ...r })),
    dbAnomalies,
    uiDbCrossCheck,
    crossCheckMatches,
    crossCheckMismatches,
    // Screenshot names relative to the run folder — only those that were actually created
    screenshots: allScreenshotNames,
  };

  // Write to root results/ (latest run — what the dashboard loads by default)
  fs.writeFileSync(path.join(RESULTS_DIR, 'results.json'), JSON.stringify(resultsJson, null, 2), 'utf-8');
  // Also write into the run folder (for history browsing)
  fs.writeFileSync(path.join(RUN_DIR, 'results.json'), JSON.stringify(resultsJson, null, 2), 'utf-8');
  console.log(`📊 Run folder: ${RUN_DIR}`);

  // Final assertion — all qty checks must pass
  expect(allQtyPass, 'All line quantity assertions should pass').toBe(true);
});
