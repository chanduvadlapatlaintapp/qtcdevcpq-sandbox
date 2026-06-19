// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults, buildUiDbCrossCheck } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quantityDecreaseNonSegment';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
// Target decrease per eligible line. The actual delta applied to each line is
// capped at that line's effective quantity (= currentQty − priorQty) so the
// quantity never goes below priorQty (Eff. Qty 0 is the hard floor).
const QTY_DELTA         = 5;
// Milliseconds to quiesce after entering the floor value so the LWC's debounce
// can fire before we re-read the input.
const QUIESCE_MS        = 1_000;

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

/** @param {import('@playwright/test').Page} page */
async function captureAllMetricText(page) {
  const labels = ['ACV', 'ACV Change', 'TCV', 'YoY Uplift', 'Deal Quality Score'];
  /** @type {Record<string,string>} */ const result = {};

  const metricsBarText = await page.evaluate(() => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    /** @type {Node|null} */ let node;
    while ((node = walker.nextNode())) {
      const el = /** @type {Element} */ (node);
      if (el.className && String(el.className).includes('metrics-bar')) {
        return /** @type {HTMLElement} */ (el).innerText || el.textContent || '';
      }
    }
    return '';
  }).catch(() => '');

  if (metricsBarText) {
    const lines = metricsBarText.split('\n').map((/** @type {string} */ l) => l.trim()).filter(Boolean);
    for (let i = 0; i < lines.length - 1; i++) {
      if (labels.includes(lines[i])) { result[lines[i]] = lines[i + 1]; i++; }
    }
  }
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

/** @param {import('@playwright/test').Page} page */
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

// Decrease: post-save value should be ≤ pre-save value.
const dirCheck = (/** @type {number|null} */ b, /** @type {number|null} */ a) => {
  if (b === null || a === null) return true;
  return a <= b;
};

/**
 * Read the effective quantity shown in the EFF. QTY cell of a product row.
 * Uses the same selector as the MDQ segments test — works for both multi-
 * segment rows and single-segment (non-segment) rows.
 *
 * eff-qty-neutral class means Eff. Qty = 0 (quantity is at priorQuantity).
 *
 * @param {import('@playwright/test').Locator} row
 */
async function readNonSegmentEffQty(row) {
  const cell = row.locator('td.col-eff-qty span.eff-qty').first();
  const cls  = (await cell.getAttribute('class').catch(() => '')) || '';
  if (cls.includes('eff-qty-neutral')) return 0;
  const txt  = (await cell.innerText().catch(() => '0')).trim().replace(/^\+/, '');
  const v    = parseInt(txt, 10);
  return Number.isFinite(v) ? v : 0;
}

/**
 * Find all `tr.product-row` elements with exactly 1 `input.qty-input` (non-
 * segment / single-period products) and return their metadata. Multi-segment
 * MDQ rows (2+ inputs) are intentionally excluded.
 *
 * Also captures spinbuttons outside any `tr.product-row` (non-MDQ layout
 * fallback) so neither layout is missed.
 *
 * @param {import('@playwright/test').Page} page
 * @param {import('./utils/agenticQtcPage').AgenticQtcPage} qtc
 * @returns {Promise<Array<{rowIndex:number, row:import('@playwright/test').Locator, input:import('@playwright/test').Locator, currentQty:number, effectiveQty:number, priorQty:number, rowText:string, costBefore:string}>>}
 */
async function findNonSegmentProductInputs(page, qtc) {
  /** @type {Array<{rowIndex:number, row:import('@playwright/test').Locator, input:import('@playwright/test').Locator, currentQty:number, effectiveQty:number, priorQty:number, rowText:string, costBefore:string}>} */
  const results = [];

  // Primary: MDQ grid rows with exactly 1 qty input = single-period (non-segment)
  const productRows = page.locator('tr.product-row');
  const rowCount    = await productRows.count().catch(() => 0);

  for (let i = 0; i < rowCount; i++) {
    const row    = productRows.nth(i);
    const inputs = row.locator('input.qty-input');
    if ((await inputs.count()) !== 1) continue;   // skip multi-segment rows

    const input        = inputs.first();
    const currentQty   = parseFloat(await input.inputValue().catch(() => '0')) || 0;
    const effectiveQty = await readNonSegmentEffQty(row);
    const priorQty     = currentQty - effectiveQty;
    const productName  = await row.locator('.product-label').first()
      .innerText({ timeout: 1_000 }).catch(() => '');
    const rowText      = productName.trim()
      || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
    const costBefore   = await qtc.readLineCost(input);

    results.push({ rowIndex: i, row, input, currentQty, effectiveQty, priorQty, rowText, costBefore });
  }

  // Secondary: spinbuttons outside any tr.product-row (non-MDQ layout fallback)
  const spinbuttons = page.getByRole('spinbutton');
  const sbCount     = await spinbuttons.count();
  for (let i = 0; i < sbCount; i++) {
    const sb          = spinbuttons.nth(i);
    const inProductRow = (await sb.locator('xpath=ancestor::tr[contains(@class,"product-row")]').count()) > 0;
    if (inProductRow) continue;

    const currentQty   = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
    const row          = sb.locator('xpath=ancestor::tr').first();
    const effectiveQty = await readNonSegmentEffQty(row);
    const priorQty     = currentQty - effectiveQty;
    const productName  = await row.locator('.product-label').first()
      .innerText({ timeout: 1_000 }).catch(() => '');
    const rowText      = productName.trim()
      || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
    const costBefore   = await qtc.readLineCost(sb);

    results.push({ rowIndex: -1, row, input: sb, currentQty, effectiveQty, priorQty, rowText, costBefore });
  }

  return results;
}

/**
 * Inner feature: find non-segment products, skip the test when all have zero
 * effective quantity, apply an adaptive decrease (capped at each line's
 * effective quantity so quantity never drops below priorQty), verify the
 * floor clamp when typing below priorQty, save, and cross-check DB.
 *
 * @param {{
 *   page: import('@playwright/test').Page,
 *   qtc:  import('./utils/agenticQtcPage').AgenticQtcPage,
 *   runDir: string, runTs: string, testStartMs: number,
 *   contract: import('./utils/scenarioContracts').ContractRec,
 *   scenarioNumber: 1|2|3, scenarioLabel: string,
 *   quoteName: string,
 * }} ctx
 */
async function runQuantityDecreaseNonSegment(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;

  await qtc.waitForLines(120_000);
  await u.screenshot(page, runDir, '02-editor-loaded');

  const allNonSegment = await findNonSegmentProductInputs(page, qtc);

  if (allNonSegment.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName} has no non-segment products — skipping test`);
    test.skip(true, `Quote ${quoteName} has no non-segment products`);
    return;
  }

  // Lines with effectiveQty == 0 are already at priorQuantity; they cannot be
  // decreased further. Log each one and only proceed with the eligible subset.
  const eligible = allNonSegment.filter(l => {
    if (l.effectiveQty <= 0) {
      console.log(`[Scenario ${scenarioNumber}] Skipping line "${l.rowText}" — Eff. Qty is 0 (qty already at priorQuantity ${l.priorQty})`);
      return false;
    }
    return true;
  });

  if (eligible.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName} has no non-segment products — skipping test`);
    test.skip(true, `Quote ${quoteName}: all ${allNonSegment.length} non-segment product(s) have Eff. Qty = 0 — cannot decrease`);
    return;
  }

  console.log(`[Scenario ${scenarioNumber}] ${eligible.length} of ${allNonSegment.length} non-segment product(s) eligible for decrease in quote ${quoteName}`);

  const metricsBeforeSave = await captureMetrics(page);

  /**
   * @type {Array<{
   *   rowIndex:number, row:import('@playwright/test').Locator,
   *   input:import('@playwright/test').Locator,
   *   rowText:string, costBefore:string,
   *   currentQty:number, priorQty:number, effectiveQty:number,
   *   delta:number, newQty:number
   * }>}
   */
  const preSave = [];

  for (const line of eligible) {
    // Re-read current qty just before editing — CPQ cascade rules can shift
    // adjacent lines as earlier edits are committed.
    const current = parseFloat(await line.input.inputValue().catch(() => '0')) || 0;
    const effQty  = await readNonSegmentEffQty(line.row);
    // Adaptive delta: never exceed the current effective quantity so we stay
    // above or at priorQty. Also floor at 1 to satisfy CPQ validation.
    const delta   = Math.min(QTY_DELTA, effQty);
    const priorQty = current - effQty;
    // Ensure newQty >= max(priorQty, 1) to avoid CPQ zero-qty rejection.
    const newQty  = Math.max(Math.max(priorQty, 1), current - delta);

    await line.input.click({ clickCount: 3 });
    await line.input.fill(String(newQty));
    await line.input.press('Tab');
    await page.waitForTimeout(800);

    preSave.push({ ...line, currentQty: current, priorQty, effectiveQty: effQty, delta, newQty });
  }
  await u.screenshot(page, runDir, '03-after-qty-decrease');

  // Floor clamp verification: attempt to type priorQty − 1 on each line and
  // confirm the UI rejects or clamps back to priorQty. This exercises the
  // business rule that Eff. Qty cannot go negative.
  for (const line of preSave) {
    const belowFloor = line.priorQty - 1;
    // Only test the floor clamp when priorQty > 0, otherwise priorQty - 1 = -1
    // which CPQ rejects for a different reason (negative qty).
    if (line.priorQty <= 0) continue;

    await line.input.click({ clickCount: 3 });
    await line.input.fill(String(belowFloor));
    await line.input.press('Tab');
    await page.waitForTimeout(QUIESCE_MS);

    const afterFloor = parseFloat(await line.input.inputValue().catch(() => '0')) || 0;
    expect(
      afterFloor,
      `"${line.rowText}": typing ${belowFloor} (below priorQty ${line.priorQty}) must be clamped to at least priorQty`,
    ).toBeGreaterThanOrEqual(line.priorQty);

    const effAfterFloor = await readNonSegmentEffQty(line.row);
    expect(
      effAfterFloor,
      `"${line.rowText}": Eff. Qty must be ≥ 0 after floor attempt`,
    ).toBeGreaterThanOrEqual(0);
  }
  await u.screenshot(page, runDir, '04-after-floor-check');

  await qtc.save(120_000);
  await u.screenshot(page, runDir, '05-after-save');

  /** @type {number[]} */ const postSave = [];
  /** @type {string[]} */ const costAfter = [];
  for (const line of preSave) {
    const val = await line.input.inputValue().catch(() => '0');
    postSave.push(parseFloat(val) || 0);
    costAfter.push(await qtc.readLineCost(line.input));
  }
  const metricsAfterSave = await captureMetrics(page);
  await u.screenshot(page, runDir, '06-final');

  // DB verification — fetch only non-segment QuoteLines (SegmentIndex = NULL).
  /** @type {string|null} */ let soql = null;
  /** @type {string|null} */ let headerSoql = null;
  if (quoteName) {
    const describe = await page.evaluate(async (/** @type {{instanceUrl:string, accessToken:string}} */ args) => {
      const headers = { 'Authorization': `Bearer ${args.accessToken}`, 'Content-Type': 'application/json' };
      const resp = await fetch(`${args.instanceUrl}/services/data/v62.0/sobjects/SBQQ__QuoteLine__c/describe`, { headers });
      const json = await resp.json();
      return Array.isArray(json.fields) ? json.fields.map((/** @type {any} */ f) => f.name) : [];
    }, { instanceUrl: sfCtx.instanceUrl, accessToken: sfCtx.accessToken }).catch(() => []);

    const wanted = [
      'Id', 'Name', 'SBQQ__ProductName__c',
      'SBQQ__Quantity__c', 'SBQQ__PriorQuantity__c',
      'SBQQ__CustomerPrice__c', 'SBQQ__ListPrice__c',
      'SBQQ__NetTotal__c', 'SBQQ__Discount__c',
      'SBQQ__StartDate__c', 'SBQQ__EndDate__c',
      'SBQQ__SegmentKey__c', 'SBQQ__SegmentIndex__c',
      'SBQQ__PricingMethod__c', 'SBQQ__ACV__c', 'SBQQ__TCV__c',
      'SBQQ__SubscriptionTerm__c', 'SBQQ__RegularPrice__c',
    ];
    const available = describe.length > 0
      ? wanted.filter(f => f === 'Id' || f === 'Name' || describe.includes(f))
      : wanted.filter(f => !['SBQQ__ACV__c', 'SBQQ__TCV__c'].includes(f));

    soql = `SELECT ${available.join(', ')}
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__r.Name = '${quoteName}'
              AND SBQQ__SegmentIndex__c = NULL
            ORDER BY SBQQ__ProductName__c NULLS LAST`;
    headerSoql = `SELECT Id, Name, SBQQ__Status__c, SBQQ__NetAmount__c,
                         SBQQ__SubscriptionTerm__c, SBQQ__StartDate__c, SBQQ__EndDate__c,
                         SBQQ__Account__r.Name
                  FROM SBQQ__Quote__c WHERE Name = '${quoteName}' LIMIT 1`;
  }

  /** @type {any[]} */ let dbLines = [];
  /** @type {any} */   let dbHeader = null;
  /** @type {string|null} */ let dbError = null;
  if (soql && headerSoql) {
    try {
      const result = await page.evaluate(async (/** @type {{soql:string, headerSoql:string, instanceUrl:string, accessToken:string}} */ args) => {
        const apiBase = args.instanceUrl + '/services/data/v62.0';
        const headers = { 'Authorization': `Bearer ${args.accessToken}`, 'Content-Type': 'application/json' };
        const [linesResp, headerResp] = await Promise.all([
          fetch(`${apiBase}/query?q=${encodeURIComponent(args.soql)}`, { headers }),
          fetch(`${apiBase}/query?q=${encodeURIComponent(args.headerSoql)}`, { headers }),
        ]);
        return { lines: await linesResp.json(), header: await headerResp.json() };
      }, { soql, headerSoql, instanceUrl: sfCtx.instanceUrl, accessToken: sfCtx.accessToken });
      if (result.lines.records) dbLines = result.lines.records;
      if (result.header.records?.[0]) dbHeader = result.header.records[0];
    } catch (e) {
      dbError = String(e);
    }
  } else {
    dbError = 'Quote name not found in UI — cannot query API';
  }

  // Anomaly detection
  /** @type {Array<{type:string,severity:string,detail:string}>} */ const dbAnomalies = [];
  /** @type {any[]} */ const dbComparison = [];
  if (dbLines.length > 0) {
    const uiQtyTotal = postSave.reduce((s, v) => s + v, 0);
    const dbQtyTotal = dbLines.reduce((s, d) => s + (d.SBQQ__Quantity__c ?? 0), 0);
    if (Math.abs(uiQtyTotal - dbQtyTotal) > 0.01) {
      dbAnomalies.push({ type: 'TOTAL QTY MISMATCH', severity: 'HIGH',
        detail: `UI sum (${uiQtyTotal}) ≠ DB sum (${dbQtyTotal}).` });
    }
    if (preSave.length !== dbLines.length) {
      dbAnomalies.push({ type: 'LINE COUNT MISMATCH', severity: 'HIGH',
        detail: `UI ${preSave.length} eligible non-segment line(s); DB ${dbLines.length} non-segment QuoteLines.` });
    }
    const isBundleParent = (/** @type {string|null|undefined} */ name) => {
      const n = (name || '').toLowerCase();
      return n.includes('bundle') || n.includes(': sandbox');
    };
    for (let i = 0; i < dbLines.length; i++) {
      const db          = dbLines[i];
      const dbQty       = db.SBQQ__Quantity__c       ?? 0;
      const dbPrice     = db.SBQQ__CustomerPrice__c  ?? null;
      const dbListPrice = db.SBQQ__ListPrice__c      ?? null;
      const dbNetTotal  = db.SBQQ__NetTotal__c       ?? null;
      const dbDiscount  = db.SBQQ__Discount__c       ?? null;
      const dbSegKey    = db.SBQQ__SegmentKey__c     ?? null;
      const dbPrior     = db.SBQQ__PriorQuantity__c  ?? null;
      const isBundle    = isBundleParent(db.SBQQ__ProductName__c);

      if (dbPrior !== null && dbQty < dbPrior) {
        dbAnomalies.push({ type: 'BELOW PRIOR QUANTITY', severity: 'HIGH',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": Quantity (${dbQty}) < PriorQuantity (${dbPrior}) — floor violated.` });
      }
      if (dbQty > 0 && !isBundle && (dbPrice === null || dbPrice === 0)) {
        dbAnomalies.push({ type: 'ZERO CUSTOMER PRICE', severity: 'MEDIUM',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": qty=${dbQty} but CustomerPrice=$0.` });
      }
      if (dbQty > 0 && !isBundle && dbListPrice && dbListPrice > 0 && (dbPrice === null || dbPrice === 0)) {
        dbAnomalies.push({ type: 'POSSIBLE 100% DISCOUNT', severity: 'HIGH',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": ListPrice=$${dbListPrice} but CustomerPrice=$0.` });
      }
      if (dbQty > 0 && !isBundle && dbNetTotal !== null && dbNetTotal === 0 && dbPrice && dbPrice > 0) {
        dbAnomalies.push({ type: 'ZERO NET TOTAL', severity: 'HIGH',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": NetTotal=$0 despite qty=${dbQty}.` });
      }
      if (dbSegKey === null && db.SBQQ__SegmentIndex__c !== null) {
        dbAnomalies.push({ type: 'MISSING SEGMENT KEY', severity: 'LOW',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}" has SegmentIndex=${db.SBQQ__SegmentIndex__c} but SegmentKey is null.` });
      }
      if (dbPrior !== null && dbQty === dbPrior && dbQty !== 0) {
        dbAnomalies.push({ type: 'QTY UNCHANGED FROM PRIOR', severity: 'MEDIUM',
          detail: `DB line ${i + 1} "${db.SBQQ__ProductName__c}": Quantity (${dbQty}) = PriorQuantity (${dbPrior}).` });
      }

      dbComparison.push({
        index: i + 1,
        product:  db.SBQQ__ProductName__c || '—',
        segKey:   dbSegKey || '—',
        segIndex: db.SBQQ__SegmentIndex__c,
        priorQty: dbPrior, dbQty, dbPrice, dbListPrice, dbDiscount, dbNetTotal,
        dbAcv: db.SBQQ__ACV__c ?? null, dbTcv: db.SBQQ__TCV__c ?? null,
        isBundle,
        startDate: db.SBQQ__StartDate__c, endDate: db.SBQQ__EndDate__c,
        pricingMethod: db.SBQQ__PricingMethod__c,
        term: db.SBQQ__SubscriptionTerm__c,
        regularPrice: db.SBQQ__RegularPrice__c,
      });
    }
  }

  /** @type {Array<{index:number,label:string,before:number,expected:number,actual:number,pass:boolean,costBefore:string,costAfter:string}>} */
  const lineResults = [];
  let allQtyPass = true;
  for (let i = 0; i < preSave.length; i++) {
    const expected = preSave[i].newQty;
    const actual   = postSave[i];
    const pass     = Math.abs(actual - expected) < 0.001;
    if (!pass) allQtyPass = false;
    lineResults.push({
      index: i + 1, label: preSave[i].rowText || `Line ${i + 1}`,
      before: preSave[i].currentQty, expected, actual, pass,
      costBefore: preSave[i].costBefore, costAfter: costAfter[i],
    });
  }

  // Per-line floor assertion: every persisted quantity must be >= its priorQty.
  for (let i = 0; i < preSave.length; i++) {
    expect(
      postSave[i],
      `"${preSave[i].rowText}": post-save qty (${postSave[i]}) must be ≥ priorQty (${preSave[i].priorQty})`,
    ).toBeGreaterThanOrEqual(preSave[i].priorQty);
  }

  const acvBefore = u.parseCurrency(metricsBeforeSave.acv);
  const acvAfter  = u.parseCurrency(metricsAfterSave.acv);
  const tcvBefore = u.parseCurrency(metricsBeforeSave.tcv);
  const tcvAfter  = u.parseCurrency(metricsAfterSave.tcv);

  const metricResults = [
    { metric: 'ACV',         before: metricsBeforeSave.acv,       after: metricsAfterSave.acv,       pass: dirCheck(acvBefore, acvAfter),
      note: (acvBefore !== null && acvAfter !== null) ? `Δ = ${(acvAfter - acvBefore).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'ACV Change',  before: metricsBeforeSave.acvChange, after: metricsAfterSave.acvChange, pass: true, note: 'Reflects cumulative change from original contract' },
    { metric: 'TCV',         before: metricsBeforeSave.tcv,       after: metricsAfterSave.tcv,       pass: dirCheck(tcvBefore, tcvAfter),
      note: (tcvBefore !== null && tcvAfter !== null) ? `Δ = ${(tcvAfter - tcvBefore).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'YoY Uplift',  before: metricsBeforeSave.yoyUplift, after: metricsAfterSave.yoyUplift, pass: true, note: 'Directional — informational' },
    { metric: 'Deal Quality Score', before: metricsBeforeSave.dealQuality, after: metricsAfterSave.dealQuality, pass: true, note: 'Approval logic driven — informational' },
  ];

  const hasApproval = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn  = await page.getByRole('button', { name: 'Preview and Send OSA' }).isVisible().catch(() => false);

  const dbHighCount        = dbAnomalies.filter(a => a.severity === 'HIGH').length;
  const uiDbCrossCheck     = buildUiDbCrossCheck(lineResults, dbComparison);
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;
  const allPass = allQtyPass && metricResults.every(m => m.pass) && dbHighCount === 0 && crossCheckMismatches === 0;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: dbHeader?.Id || null,
    hasApproval, hasSendBtn,
    spinbuttonCount: preSave.length,
    uiQtyTotal: postSave.reduce((s, v) => s + v, 0),
    dbQtyTotal: dbLines.reduce((s, d) => s + (d.SBQQ__Quantity__c ?? 0), 0),
    dbLineCount: dbLines.length,
    deltaApplied: -QTY_DELTA,
    metricsBeforeSave, metricsAfterSave,
    lineResults, metricResults,
    dbComparison, dbAnomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: {
      dbHeader, dbError,
      nonSegmentLineCount: allNonSegment.length,
      eligibleLineCount:   preSave.length,
      skippedLines: allNonSegment
        .filter(l => l.effectiveQty <= 0)
        .map(l => ({ product: l.rowText, effectiveQty: l.effectiveQty, priorQty: l.priorQty })),
    },
  });

  expect(allQtyPass, 'All eligible non-segment line quantity assertions should pass').toBe(true);
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
  const { qtc, quoteName } = await openEditorByScenario(page, sfCtx, contract, branch);
  console.log(`[Scenario ${scenarioNumber}] Editor open on quote ${quoteName}`);

  await runQuantityDecreaseNonSegment({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — creates new amendment, then non-segment qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — opens existing amendment, then non-segment qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — picks from modal, then non-segment qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
