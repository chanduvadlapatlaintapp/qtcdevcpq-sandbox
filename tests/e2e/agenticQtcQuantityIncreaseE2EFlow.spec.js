// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const QTY_DELTA         = 5;
const TARGET_SEGMENT    = 3;
const QUIESCE_MS        = 1_500;

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

// ── Metrics ───────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page */
async function captureAllMetricText(page) {
  const labels = ['ACV', 'ACV Change', 'TCV', 'YoY Uplift', 'Deal Quality Score'];
  /** @type {Record<string,string>} */ const result = {};
  const metricsBarText = await page.evaluate(() => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    /** @type {Node|null} */ let node;
    while ((node = walker.nextNode())) {
      const el = /** @type {Element} */ (node);
      if (el.className && String(el.className).includes('metrics-bar'))
        return /** @type {HTMLElement} */ (el).innerText || el.textContent || '';
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
        const fullText = await el.locator('..').innerText({ timeout: 2_000 });
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

/** @param {number|null} b @param {number|null} a */
const dirCheck = (b, a) => b === null || a === null ? true : a >= b;

// ── Segment helpers ────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Locator} row */
async function readSegmentQuantities(row) {
  const inputs = row.locator('input.qty-input');
  const n = await inputs.count();
  /** @type {number[]} */ const out = [];
  for (let i = 0; i < n; i++) out.push(parseFloat(await inputs.nth(i).inputValue().catch(() => '0')) || 0);
  return out;
}

/** @param {import('@playwright/test').Locator} row */
async function readSegmentLineIds(row) {
  const inputs = row.locator('input.qty-input');
  const n = await inputs.count();
  /** @type {string[]} */ const out = [];
  for (let i = 0; i < n; i++) {
    const id = await inputs.nth(i).getAttribute('data-line-id');
    if (id) out.push(id);
  }
  return out;
}

/**
 * @param {import('@playwright/test').Locator} row
 * @param {number} index
 * @param {number} value
 */
async function setSegmentQuantity(row, index, value) {
  const input = row.locator('input.qty-input').nth(index);
  await input.click({ clickCount: 3 });
  await input.fill(String(value));
  await input.press('Tab');
}

// ── Product classification ─────────────────────────────────────────────────────

/**
 * @param {import('@playwright/test').Page} page
 * @param {import('./utils/agenticQtcPage').AgenticQtcPage} qtc
 */
async function classifyAllProducts(page, qtc) {
  const productRows = page.locator('tr.product-row');
  const rowCount    = await productRows.count().catch(() => 0);
  const spinbuttons = page.getByRole('spinbutton');
  const sbCount     = await spinbuttons.count().catch(() => 0);

  /** @type {Array<{rowIndex:number, row:import('@playwright/test').Locator, input:import('@playwright/test').Locator, lineId:string|null, initial:number, rowText:string, costBefore:string}>} */
  const nonSegCandidates = [];
  /** @type {Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, rowIndex:number, lineIds:string[]}>} */
  const mdqCandidates = [];
  const allLineIds = /** @type {string[]} */ ([]);

  for (let i = 0; i < rowCount; i++) {
    const row    = productRows.nth(i);
    const inputs = row.locator('input.qty-input');
    const n      = await inputs.count();
    if (n === 1) {
      const input      = inputs.first();
      const lineId     = await input.getAttribute('data-line-id').catch(() => null);
      const val        = await input.inputValue().catch(() => '0');
      const name       = await row.locator('.product-label').first().innerText({ timeout: 1_000 }).catch(() => '');
      const rowText    = name.trim() || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
      const costBefore = await qtc.readLineCost(input);
      if (lineId) allLineIds.push(lineId);
      nonSegCandidates.push({ rowIndex: i, row, input, lineId, initial: parseFloat(val) || 0, rowText, costBefore });
    } else if (n >= 2) {
      const lineIds = await readSegmentLineIds(row);
      const name    = (await row.locator('.product-label').first().innerText().catch(() => '')).trim();
      allLineIds.push(...lineIds);
      mdqCandidates.push({ row, productName: name, segmentCount: n, rowIndex: i, lineIds });
    }
  }

  for (let i = 0; i < sbCount; i++) {
    const sb = spinbuttons.nth(i);
    if ((await sb.locator('xpath=ancestor::tr[contains(@class,"product-row")]').count()) > 0) continue;
    const lineId     = await sb.getAttribute('data-line-id').catch(() => null);
    const val        = await sb.inputValue().catch(() => '0');
    const row        = sb.locator('xpath=ancestor::tr').first();
    const name       = await row.locator('.product-label').first().innerText({ timeout: 1_000 }).catch(() => '');
    const rowText    = name.trim() || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
    const costBefore = await qtc.readLineCost(sb);
    if (lineId) allLineIds.push(lineId);
    nonSegCandidates.push({ rowIndex: -1, row, input: sb, lineId, initial: parseFloat(val) || 0, rowText, costBefore });
  }

  const bundleIdSet = new Set(/** @type {string[]} */ ([]));
  if (allLineIds.length > 0) {
    const soql   = `SELECT Id, CPQ_Option_Type__c FROM SBQQ__QuoteLine__c WHERE Id IN (${allLineIds.map(id => `'${id}'`).join(',')})`;
    const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
    for (const r of (result.records || [])) {
      if (r.CPQ_Option_Type__c === 'Static Bundle') bundleIdSet.add(r.Id);
    }
  }

  return {
    nonSegRegular: nonSegCandidates.filter(c => !c.lineId || !bundleIdSet.has(c.lineId)),
    nonSegBundle:  nonSegCandidates
      .filter(c => c.lineId && bundleIdSet.has(c.lineId))
      .map(c => ({ ...c, lineId: /** @type {string} */ (c.lineId) })),
    mdqRegular: mdqCandidates.filter(r => !r.lineIds.some(id => bundleIdSet.has(id))),
    mdqBundle:  mdqCandidates.filter(r =>  r.lineIds.some(id => bundleIdSet.has(id))),
  };
}

// ── DB helpers ─────────────────────────────────────────────────────────────────

/** @param {import('@playwright/test').Page} page @param {string} quoteName */
async function queryQuoteLines(page, quoteName) {
  const describe = await page.evaluate(async (/** @type {{instanceUrl:string,accessToken:string}} */ args) => {
    const headers = { 'Authorization': `Bearer ${args.accessToken}`, 'Content-Type': 'application/json' };
    const resp = await fetch(`${args.instanceUrl}/services/data/v62.0/sobjects/SBQQ__QuoteLine__c/describe`, { headers });
    const json = await resp.json();
    return Array.isArray(json.fields) ? json.fields.map((/** @type {any} */ f) => f.name) : [];
  }, { instanceUrl: sfCtx.instanceUrl, accessToken: sfCtx.accessToken }).catch(() => /** @type {string[]} */ ([]));

  const wanted = [
    'Id', 'Name', 'SBQQ__ProductName__c', 'SBQQ__Quantity__c', 'SBQQ__PriorQuantity__c',
    'SBQQ__CustomerPrice__c', 'SBQQ__ListPrice__c', 'SBQQ__NetTotal__c', 'SBQQ__Discount__c',
    'SBQQ__StartDate__c', 'SBQQ__EndDate__c', 'SBQQ__SegmentKey__c', 'SBQQ__SegmentIndex__c',
    'SBQQ__PricingMethod__c', 'SBQQ__ACV__c', 'SBQQ__TCV__c', 'SBQQ__SubscriptionTerm__c',
    'SBQQ__RegularPrice__c', 'CPQ_Option_Type__c', 'Revenue_Allocation__c',
    'Revenue_Allocated__c', 'Segment_Index_Custom__c',
  ];
  const available = describe.length > 0
    ? wanted.filter(f => f === 'Id' || f === 'Name' || describe.includes(f))
    : wanted.filter(f => !['SBQQ__ACV__c', 'SBQQ__TCV__c', 'Revenue_Allocation__c', 'Revenue_Allocated__c', 'Segment_Index_Custom__c', 'CPQ_Option_Type__c'].includes(f));

  const soql       = `SELECT ${available.join(', ')} FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.Name = '${quoteName}' ORDER BY SBQQ__ProductName__c, SBQQ__SegmentIndex__c NULLS LAST`;
  const headerSoql = `SELECT Id, Name, SBQQ__Status__c, SBQQ__NetAmount__c, SBQQ__SubscriptionTerm__c, SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__Account__r.Name FROM SBQQ__Quote__c WHERE Name = '${quoteName}' LIMIT 1`;

  try {
    const result = await page.evaluate(async (/** @type {{soql:string,headerSoql:string,instanceUrl:string,accessToken:string}} */ args) => {
      const apiBase = args.instanceUrl + '/services/data/v62.0';
      const headers = { 'Authorization': `Bearer ${args.accessToken}`, 'Content-Type': 'application/json' };
      const [linesResp, headerResp] = await Promise.all([
        fetch(`${apiBase}/query?q=${encodeURIComponent(args.soql)}`, { headers }),
        fetch(`${apiBase}/query?q=${encodeURIComponent(args.headerSoql)}`, { headers }),
      ]);
      return { lines: await linesResp.json(), header: await headerResp.json() };
    }, { soql, headerSoql, instanceUrl: sfCtx.instanceUrl, accessToken: sfCtx.accessToken });
    return { dbLines: result.lines.records || [], dbHeader: result.header.records?.[0] || null, dbError: null };
  } catch (e) {
    return { dbLines: /** @type {any[]} */ ([]), dbHeader: null, dbError: String(e) };
  }
}

/** @param {any[]} dbLines */
function buildDbComparison(dbLines) {
  /** @type {Array<{type:string,severity:string,detail:string}>} */ const anomalies = [];
  const dbComparison = dbLines.map((db, i) => {
    const optionType  = db.CPQ_Option_Type__c || null;
    const isBundle    = optionType === 'Static Bundle';
    const isComponent = optionType === 'Static Component';
    const dbQty   = db.SBQQ__Quantity__c      ?? 0;
    const dbPrice = db.SBQQ__CustomerPrice__c  ?? null;
    const dbList  = db.SBQQ__ListPrice__c      ?? null;
    const dbNet   = db.SBQQ__NetTotal__c       ?? null;
    const dbPrior = db.SBQQ__PriorQuantity__c  ?? null;
    if (!isBundle && !isComponent) {
      if (dbQty > 0 && (dbPrice === null || dbPrice === 0))
        anomalies.push({ type: 'ZERO CUSTOMER PRICE', severity: 'MEDIUM', detail: `Line ${i+1} "${db.SBQQ__ProductName__c}": qty=${dbQty} CustomerPrice=$0.` });
      if (dbQty > 0 && dbList && dbList > 0 && (dbPrice === null || dbPrice === 0))
        anomalies.push({ type: 'POSSIBLE 100% DISCOUNT', severity: 'HIGH', detail: `Line ${i+1} "${db.SBQQ__ProductName__c}": ListPrice=$${dbList} CustomerPrice=$0.` });
      if (dbQty > 0 && dbNet !== null && dbNet === 0 && dbPrice && dbPrice > 0)
        anomalies.push({ type: 'ZERO NET TOTAL', severity: 'HIGH', detail: `Line ${i+1} "${db.SBQQ__ProductName__c}": NetTotal=$0 qty=${dbQty}.` });
    }
    if (isComponent && (db.Revenue_Allocation__c === null || db.Revenue_Allocation__c === 0))
      anomalies.push({ type: 'ZERO REVENUE ALLOCATION', severity: 'HIGH', detail: `Component "${db.SBQQ__ProductName__c}" segment ${db.Segment_Index_Custom__c ?? 'N/A'}: Revenue_Allocation__c = 0.` });
    if (dbPrior !== null && dbQty === dbPrior && dbQty !== 0)
      anomalies.push({ type: 'QTY UNCHANGED FROM PRIOR', severity: 'MEDIUM', detail: `Line ${i+1} "${db.SBQQ__ProductName__c}": Qty(${dbQty})=Prior.` });
    return {
      index: i + 1, product: db.SBQQ__ProductName__c || '—',
      segKey: db.Id,
      segGroupKey: db.SBQQ__SegmentKey__c || null,
      segIndex: db.SBQQ__SegmentIndex__c ?? null,
      segIndexCustom: db.Segment_Index_Custom__c ?? null,
      priorQty: dbPrior, dbQty, dbPrice, dbListPrice: dbList,
      dbDiscount: db.SBQQ__Discount__c ?? null, dbNetTotal: dbNet,
      dbAcv: db.SBQQ__ACV__c ?? null, dbTcv: db.SBQQ__TCV__c ?? null,
      isBundle, isComponent, optionType,
      startDate: db.SBQQ__StartDate__c, endDate: db.SBQQ__EndDate__c,
      pricingMethod: db.SBQQ__PricingMethod__c, term: db.SBQQ__SubscriptionTerm__c,
      regularPrice: db.SBQQ__RegularPrice__c,
      revenueAllocation: db.Revenue_Allocation__c ?? null,
      revenueAllocated: db.Revenue_Allocated__c ?? null,
    };
  });
  return { dbComparison, dbAnomalies: anomalies };
}

/** @param {any} metricsBeforeSave @param {any} metricsAfterSave */
function buildMetricResults(metricsBeforeSave, metricsAfterSave) {
  const ab = u.parseCurrency(metricsBeforeSave.acv);
  const aa = u.parseCurrency(metricsAfterSave.acv);
  const tb = u.parseCurrency(metricsBeforeSave.tcv);
  const ta = u.parseCurrency(metricsAfterSave.tcv);
  return [
    { metric: 'ACV',               before: metricsBeforeSave.acv,        after: metricsAfterSave.acv,        pass: dirCheck(ab, aa), note: ab !== null && aa !== null ? `Δ = ${(aa - ab).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'ACV Change',        before: metricsBeforeSave.acvChange,  after: metricsAfterSave.acvChange,  pass: true,             note: 'Reflects cumulative change from original contract' },
    { metric: 'TCV',               before: metricsBeforeSave.tcv,        after: metricsAfterSave.tcv,        pass: dirCheck(tb, ta), note: tb !== null && ta !== null ? `Δ = ${(ta - tb).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'YoY Uplift',        before: metricsBeforeSave.yoyUplift,  after: metricsAfterSave.yoyUplift,  pass: true,             note: 'Directional — informational' },
    { metric: 'Deal Quality Score',before: metricsBeforeSave.dealQuality,after: metricsAfterSave.dealQuality,pass: true,             note: 'Approval logic driven — informational' },
  ];
}

// ── Edit-phase helpers (no save, no DB, return state) ─────────────────────────

/**
 * Fill qty + QTY_DELTA for each non-segment input. Reads costBefore upfront.
 * @param {import('@playwright/test').Page} page
 * @param {any[]} products
 */
async function editNonSegInputs(page, products) {
  /** @type {any[]} */ const items = [];
  for (const p of products) {
    const current = parseFloat(await p.input.inputValue().catch(() => '0')) || 0;
    const newVal  = current + QTY_DELTA;
    await p.input.click({ clickCount: 3 });
    await p.input.fill(String(newVal));
    await p.input.press('Tab');
    await page.waitForTimeout(600);
    items.push({ ...p, initial: current, filled: newVal });
  }
  return items;
}

/**
 * Edit MDQ regular segments: Year-1 propagation + Year-N isolation.
 * Verifies propagation in-place; returns state for post-save checks.
 * @param {import('@playwright/test').Page} page
 * @param {any[]} rows
 */
async function editMdqRegularSegments(page, rows) {
  if (rows.length === 0) return null;
  const productA    = rows[0];
  const productB    = rows.length >= 2 ? rows[1] : rows[0];
  const sameProduct = productA.rowIndex === productB.rowIndex;
  const idxB        = Math.min(TARGET_SEGMENT - 1, productB.segmentCount - 1);

  const beforeA   = await readSegmentQuantities(productA.row);
  const lineIdsA  = productA.lineIds;
  const expectedA = beforeA.map(v => v + QTY_DELTA);
  const beforeBPreEdit = sameProduct ? /** @type {number[]|null} */ (null) : await readSegmentQuantities(productB.row);
  const lineIdsB = sameProduct ? lineIdsA : productB.lineIds;

  await setSegmentQuantity(productA.row, 0, beforeA[0] + QTY_DELTA);
  await expect.poll(() => readSegmentQuantities(productA.row), {
    message: `MDQ regular Product A: all ${productA.segmentCount} segments should reflect +${QTY_DELTA}`,
    timeout: 10_000, intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);

  if (!sameProduct)
    expect(await readSegmentQuantities(productB.row), 'Product B unchanged after Product A edit').toEqual(beforeBPreEdit);

  const beforeB   = await readSegmentQuantities(productB.row);
  const expectedB = beforeB.slice();
  expectedB[idxB] = beforeB[idxB] + QTY_DELTA;

  await setSegmentQuantity(productB.row, idxB, beforeB[idxB] + QTY_DELTA);
  await page.waitForTimeout(QUIESCE_MS);

  expect(await readSegmentQuantities(productB.row), `Product B: only Year ${idxB + 1} should change`).toEqual(expectedB);
  const finalExpectedA = sameProduct ? expectedB : expectedA;
  expect(await readSegmentQuantities(productA.row), sameProduct ? 'Same-product final state' : 'Product A unchanged by B edit').toEqual(finalExpectedA);

  return { productA, productB, sameProduct, idxB, lineIdsA, lineIdsB, beforeA, beforeBPreEdit, beforeB, finalExpectedA, expectedB };
}

/**
 * Edit MDQ bundle segments: Year-1 propagation + Year-N isolation.
 * @param {import('@playwright/test').Page} page
 * @param {any[]} rows
 */
async function editMdqBundleSegments(page, rows) {
  if (rows.length === 0) return null;
  const bundle = rows[0];
  const idxB   = Math.min(TARGET_SEGMENT - 1, bundle.segmentCount - 1);

  const beforeA   = await readSegmentQuantities(bundle.row);
  const expectedA = beforeA.map(v => v + QTY_DELTA);

  await setSegmentQuantity(bundle.row, 0, beforeA[0] + QTY_DELTA);
  await expect.poll(() => readSegmentQuantities(bundle.row), {
    message: `MDQ bundle: all ${bundle.segmentCount} segments should reflect +${QTY_DELTA}`,
    timeout: 10_000, intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);

  const beforeB   = await readSegmentQuantities(bundle.row);
  const expectedB = beforeB.slice();
  expectedB[idxB] = beforeB[idxB] + QTY_DELTA;

  await setSegmentQuantity(bundle.row, idxB, beforeB[idxB] + QTY_DELTA);
  await page.waitForTimeout(QUIESCE_MS);

  expect(await readSegmentQuantities(bundle.row), `Bundle: only Year ${idxB + 1} should change`).toEqual(expectedB);

  return { bundle, idxB, lineIdsBundle: bundle.lineIds, beforeA, expectedA, beforeB, expectedB, expectedFinal: expectedB };
}

// ── Main scenario runner ───────────────────────────────────────────────────────

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
  await qtc.waitForLines(120_000);
  await u.screenshot(page, runDir, '02-editor-loaded');

  const { nonSegRegular, nonSegBundle, mdqRegular, mdqBundle } = await classifyAllProducts(page, qtc);
  const total = nonSegRegular.length + nonSegBundle.length + mdqRegular.length + mdqBundle.length;
  if (total === 0) {
    test.skip(true, `Quote ${quoteName}: no editable products found in any category`);
    return;
  }
  console.log(`[Scenario ${scenarioNumber}] non-seg regular: ${nonSegRegular.length}, non-seg bundle: ${nonSegBundle.length}, MDQ regular: ${mdqRegular.length}, MDQ bundle: ${mdqBundle.length}`);

  // ── 1. Metrics before any edit ─────────────────────────────────────────────
  const metricsBeforeSave = await captureMetrics(page);

  // ── 2. Edit all products (no save yet) ────────────────────────────────────
  const nsRegEdits  = await editNonSegInputs(page, nonSegRegular);
  const nsBunEdits  = await editNonSegInputs(page, nonSegBundle);
  const mdqRegState = await editMdqRegularSegments(page, mdqRegular);
  const mdqBunState = await editMdqBundleSegments(page, mdqBundle);
  await u.screenshot(page, runDir, '03-after-all-edits');

  // ── 3. ONE save ────────────────────────────────────────────────────────────
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '04-after-save');

  // ── 4. Read post-save UI values and costs ─────────────────────────────────
  /** @type {Array<{actual:number,costAfter:string}>} */ const nsRegPost = [];
  for (const item of nsRegEdits)
    nsRegPost.push({ actual: parseFloat(await item.input.inputValue().catch(() => '0')) || 0, costAfter: await qtc.readLineCost(item.input) });

  /** @type {Array<{actual:number,costAfter:string}>} */ const nsBunPost = [];
  for (const item of nsBunEdits)
    nsBunPost.push({ actual: parseFloat(await item.input.inputValue().catch(() => '0')) || 0, costAfter: await qtc.readLineCost(item.input) });

  let mdqRegPostA = /** @type {number[]} */ ([]);
  let mdqRegPostB = /** @type {number[]} */ ([]);
  if (mdqRegState) {
    mdqRegPostA = await readSegmentQuantities(mdqRegState.productA.row);
    mdqRegPostB = await readSegmentQuantities(mdqRegState.productB.row);
    expect(mdqRegPostA, 'Post-save: Product A propagation intact').toEqual(mdqRegState.finalExpectedA);
    expect(mdqRegPostB, 'Post-save: Product B isolation intact').toEqual(mdqRegState.expectedB);
  }

  let mdqBunPostFinal = /** @type {number[]} */ ([]);
  if (mdqBunState) {
    mdqBunPostFinal = await readSegmentQuantities(mdqBunState.bundle.row);
    expect(mdqBunPostFinal, 'Post-save: bundle reflects all edits').toEqual(mdqBunState.expectedFinal);
  }

  // ── 5. Metrics after save ──────────────────────────────────────────────────
  const metricsAfterSave = await captureMetrics(page);

  // ── 6. ONE DB query — ALL lines on this quote ─────────────────────────────
  const { dbLines, dbHeader, dbError } = await queryQuoteLines(page, quoteName);
  const { dbComparison, dbAnomalies }  = buildDbComparison(dbLines);
  const dbById = new Map(dbComparison.map(d => [d.segKey, d]));

  // ── 7. Build unified lineResults (all edited UI inputs) ───────────────────
  /** @type {any[]} */ const lineResults = [];
  let idx = 1;

  for (let i = 0; i < nsRegEdits.length; i++) {
    const item     = nsRegEdits[i];
    const { actual, costAfter } = nsRegPost[i];
    const expected = item.initial + QTY_DELTA;
    lineResults.push({ index: idx++, lineId: item.lineId, label: item.rowText, category: 'nonSegRegular', before: item.initial, expected, actual, pass: Math.abs(actual - expected) < 0.001, costBefore: item.costBefore, costAfter });
  }
  for (let i = 0; i < nsBunEdits.length; i++) {
    const item     = nsBunEdits[i];
    const { actual, costAfter } = nsBunPost[i];
    const expected = item.initial + QTY_DELTA;
    lineResults.push({ index: idx++, lineId: item.lineId, label: item.rowText, category: 'nonSegBundle', before: item.initial, expected, actual, pass: Math.abs(actual - expected) < 0.001, costBefore: item.costBefore, costAfter });
  }
  if (mdqRegState) {
    const { productA, productB, sameProduct, lineIdsA, lineIdsB, beforeA, beforeBPreEdit, finalExpectedA, expectedB } = mdqRegState;
    for (let i = 0; i < lineIdsA.length; i++) {
      const actual = mdqRegPostA[i] ?? NaN;
      lineResults.push({ index: idx++, lineId: lineIdsA[i], label: `${productA.productName} · Y${i + 1}`, category: 'mdqRegular', before: beforeA[i], expected: finalExpectedA[i], actual, pass: Math.abs(actual - finalExpectedA[i]) < 0.001, costBefore: null, costAfter: null });
    }
    if (!sameProduct && beforeBPreEdit) {
      for (let i = 0; i < lineIdsB.length; i++) {
        const actual = mdqRegPostB[i] ?? NaN;
        lineResults.push({ index: idx++, lineId: lineIdsB[i], label: `${productB.productName} · Y${i + 1}`, category: 'mdqRegular', before: beforeBPreEdit[i] ?? 0, expected: expectedB[i], actual, pass: Math.abs(actual - expectedB[i]) < 0.001, costBefore: null, costAfter: null });
      }
    }
  }
  if (mdqBunState) {
    const { bundle, lineIdsBundle, beforeA, expectedFinal } = mdqBunState;
    for (let i = 0; i < lineIdsBundle.length; i++) {
      const actual = mdqBunPostFinal[i] ?? NaN;
      lineResults.push({ index: idx++, lineId: lineIdsBundle[i], label: `${bundle.productName} · Y${i + 1}`, category: 'mdqBundle', before: beforeA[i], expected: expectedFinal[i], actual, pass: Math.abs(actual - expectedFinal[i]) < 0.001, costBefore: null, costAfter: null });
    }
  }

  // ── 8. UI–DB cross-check by line ID ───────────────────────────────────────
  const uiDbCrossCheck = lineResults.map((/** @type {any} */ line) => {
    const db      = line.lineId ? dbById.get(line.lineId) : undefined;
    const hasData = db != null;
    const uiAfter = line.actual;
    const dbAfter = db ? (db.dbQty ?? null) : null;
    const match   = hasData && uiAfter != null && dbAfter != null && Math.abs(uiAfter - dbAfter) < 0.001;
    return {
      uiIndex: line.index, product: line.label, category: line.category,
      segOcc: db?.segIndex ?? null, uiBefore: line.before, uiAfter,
      dbPrior: db?.priorQty ?? null, dbAfter,
      costBefore: line.costBefore ?? null, costAfter: line.costAfter ?? null,
      match, hasData,
    };
  });
  const crossCheckMismatches = uiDbCrossCheck.filter((/** @type {any} */ r) => r.hasData && !r.match).length;

  // ── 9. Revenue_Allocation assertions on Static Component lines ─────────────
  for (const d of dbComparison) {
    if (d.isComponent) {
      expect(d.revenueAllocation ?? 0,
        `Component "${d.product}" segment ${d.segIndexCustom ?? d.segIndex ?? 'N/A'}: Revenue_Allocation__c must be > 0`
      ).toBeGreaterThan(0);
    }
  }

  // ── 10. Final assertions & one combined result ─────────────────────────────
  const allQtyPass     = lineResults.every((/** @type {any} */ r) => r.pass);
  const metricResults  = buildMetricResults(metricsBeforeSave, metricsAfterSave);
  const dbHighCount    = dbAnomalies.filter((/** @type {any} */ a) => a.severity === 'HIGH').length;
  const hasApproval    = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn     = await page.getByRole('button', { name: 'Preview and Send OSA' }).isVisible().catch(() => false);

  buildRichResults({
    kind: 'quantityIncreaseE2EFlow', runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME, scenarioNumber, scenarioLabel,
    contract: contract.number, quoteName, quoteId: dbHeader?.Id || null,
    hasApproval, hasSendBtn,
    spinbuttonCount: lineResults.length,
    uiQtyTotal: lineResults.reduce((/** @type {number} */ s, /** @type {any} */ r) => s + (r.actual || 0), 0),
    dbQtyTotal: dbLines.reduce((/** @type {number} */ s, /** @type {any} */ d) => s + (d.SBQQ__Quantity__c ?? 0), 0),
    dbLineCount: dbLines.length, deltaApplied: QTY_DELTA,
    metricsBeforeSave, metricsAfterSave, lineResults, metricResults,
    dbComparison, dbAnomalies, uiDbCrossCheck, crossCheckMismatches,
    passed: allQtyPass && metricResults.every((/** @type {any} */ m) => m.pass) && dbHighCount === 0 && crossCheckMismatches === 0,
    extra: {
      dbHeader, dbError,
      nonSegRegularCount: nsRegEdits.length, nonSegBundleCount: nsBunEdits.length,
      mdqRegularCount: mdqRegular.length, mdqBundleCount: mdqBundle.length,
      mdqRegState: mdqRegState ? {
        productA: { name: mdqRegState.productA.productName, before: mdqRegState.beforeA, expected: mdqRegState.finalExpectedA, rule: 'Year 1 propagates' },
        productB: { name: mdqRegState.productB.productName, before: mdqRegState.beforeB, expected: mdqRegState.expectedB, rule: `Year ${mdqRegState.idxB + 1} isolated` },
      } : null,
      mdqBunState: mdqBunState ? {
        product: mdqBunState.bundle.productName,
        propagation: { before: mdqBunState.beforeA, expected: mdqBunState.expectedA, rule: 'Year 1 propagates' },
        isolation:   { before: mdqBunState.beforeB, expected: mdqBunState.expectedB, rule: `Year ${mdqBunState.idxB + 1} isolated` },
      } : null,
    },
  });

  expect(allQtyPass, 'All quantity assertions should pass').toBe(true);
}

// ── Tests ──────────────────────────────────────────────────────────────────────

test('Scenario 1: contract with 0 amendments — fresh amendment, E2E quantity increase', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, E2E quantity increase', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, E2E quantity increase', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
