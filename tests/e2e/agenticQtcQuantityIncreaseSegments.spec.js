// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quantityIncreaseSegments';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const DELTA             = 20;
const TARGET_SEGMENT    = 3;       // 1-based: Year 3 (Product B edit point)
// Long enough that the LWC's 500ms debounce and any reactive cycle would have
// fired. If a non-first-segment edit were going to propagate, it would do so
// inside this window; staying past it confirms isolation.
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

/**
 * Pick the first `count` MDQ product rows that have ≥ minSegments editable
 * qty inputs. Returns them in DOM order.
 *
 * @param {import('@playwright/test').Page} page
 * @param {number} minSegments
 * @param {number} count
 */
async function pickProductRows(page, minSegments, count) {
  const rows = page.locator('tr.product-row');
  await rows.first().waitFor({ state: 'visible', timeout: 60_000 });
  const total = await rows.count();
  /** @type {Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, rowIndex:number}>} */
  const picked = [];
  for (let i = 0; i < total && picked.length < count; i++) {
    const row    = rows.nth(i);
    const inputs = row.locator('input.qty-input');
    const n      = await inputs.count();
    if (n >= minSegments) {
      const name = (await row.locator('.product-label').first().innerText().catch(() => '')).trim();
      picked.push({ row, productName: name, segmentCount: n, rowIndex: i });
    }
  }
  if (picked.length < count) {
    throw new Error(`Needed ${count} MDQ rows with ≥${minSegments} segments; found ${picked.length}`);
  }
  return picked;
}

/** @param {import('@playwright/test').Locator} row */
async function readSegmentQuantities(row) {
  const inputs = row.locator('input.qty-input');
  const n      = await inputs.count();
  /** @type {number[]} */ const out = [];
  for (let i = 0; i < n; i++) {
    const v = await inputs.nth(i).inputValue().catch(() => '0');
    out.push(parseFloat(v) || 0);
  }
  return out;
}

/** @param {import('@playwright/test').Locator} row */
async function readSegmentLineIds(row) {
  const inputs = row.locator('input.qty-input');
  const n      = await inputs.count();
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

/**
 * Inner feature: pick two MDQ products, edit Product A's Year 1 (asserts
 * propagation), edit Product B's Year 3 (asserts isolation), save, verify
 * SBQQ__QuoteLine__c quantities.
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
async function runSegmentsIncrease(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  const [productA, productB] = await pickProductRows(page, TARGET_SEGMENT, 2);
  console.log(`Product A (Year 1 edit): "${productA.productName}" (${productA.segmentCount} segments)`);
  console.log(`Product B (Year ${TARGET_SEGMENT} edit): "${productB.productName}" (${productB.segmentCount} segments)`);

  const beforeA   = await readSegmentQuantities(productA.row);
  const lineIdsA  = await readSegmentLineIds(productA.row);
  const expectedA = beforeA.map(v => v + DELTA);
  expect(lineIdsA.length, 'Product A: one line Id per segment input').toBe(beforeA.length);

  const beforeB   = await readSegmentQuantities(productB.row);
  const lineIdsB  = await readSegmentLineIds(productB.row);
  const idxB      = TARGET_SEGMENT - 1;
  const expectedB = beforeB.slice();
  expectedB[idxB] = beforeB[idxB] + DELTA;
  expect(lineIdsB.length, 'Product B: one line Id per segment input').toBe(beforeB.length);

  // Product A: Year 1 edit propagates to every segment
  await setSegmentQuantity(productA.row, 0, beforeA[0] + DELTA);
  await expect.poll(() => readSegmentQuantities(productA.row), {
    message: `Product A: all ${productA.segmentCount} segments should reflect +${DELTA} after Year 1 edit`,
    timeout: 10_000,
    intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);
  await u.screenshot(page, runDir, '03-after-A-propagation');

  expect(
    await readSegmentQuantities(productB.row),
    'Product B should be unchanged after Product A edit (cross-product isolation)',
  ).toEqual(beforeB);

  // Product B: Year 3 edit is isolated
  await setSegmentQuantity(productB.row, idxB, beforeB[idxB] + DELTA);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '04-after-B-edit');

  expect(
    await readSegmentQuantities(productB.row),
    `Product B: only Year ${TARGET_SEGMENT} should have changed`,
  ).toEqual(expectedB);
  expect(
    await readSegmentQuantities(productA.row),
    'Product A should still show full propagation after Product B edit',
  ).toEqual(expectedA);

  // Save and verify CPQ persistence
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '05-after-save');

  expect(await readSegmentQuantities(productA.row), 'Post-save UI: Product A propagation intact').toEqual(expectedA);
  expect(await readSegmentQuantities(productB.row), 'Post-save UI: Product B isolation intact').toEqual(expectedB);

  // DB verification — filter by exact line Ids to avoid overmatching on
  // bundle children or feature lines outside the MDQ grid.
  const allLineIds = [...lineIdsA, ...lineIdsB];
  for (const id of allLineIds) {
    expect(id, `Line Id should match Salesforce Id pattern, got ${id}`).toMatch(/^[a-zA-Z0-9]{15,18}$/);
  }
  const idList = allLineIds.map(id => `'${id}'`).join(',');
  const soql = `SELECT Id, SBQQ__Quantity__c, SBQQ__SegmentIndex__c
                FROM SBQQ__QuoteLine__c
                WHERE Id IN (${idList})`;
  const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  /** @type {Map<string, number>} */
  const dbById = new Map();
  for (const r of (result.records || [])) dbById.set(r.Id, Number(r.SBQQ__Quantity__c) || 0);

  const dbQtysA = lineIdsA.map(id => dbById.get(id) ?? NaN);
  const dbQtysB = lineIdsB.map(id => dbById.get(id) ?? NaN);

  expect(dbQtysA.length, 'DB: one row per Product A segment').toBe(expectedA.length);
  for (let i = 0; i < expectedA.length; i++) {
    expect(dbQtysA[i], `Product A DB segment ${i + 1} (line ${lineIdsA[i]})`).toBe(expectedA[i]);
  }
  expect(dbQtysB.length, 'DB: one row per Product B segment').toBe(expectedB.length);
  for (let i = 0; i < expectedB.length; i++) {
    expect(dbQtysB[i], `Product B DB segment ${i + 1} (line ${lineIdsB[i]})`).toBe(expectedB[i]);
  }

  const lineResults = [
    ...lineIdsA.map((_id, i) => ({
      index: i + 1, label: `${productA.productName} · Y${i + 1}`,
      before: beforeA[i], expected: expectedA[i], actual: dbQtysA[i],
      pass: dbQtysA[i] === expectedA[i],
    })),
    ...lineIdsB.map((_id, i) => ({
      index: lineIdsA.length + i + 1, label: `${productB.productName} · Y${i + 1}`,
      before: beforeB[i], expected: expectedB[i], actual: dbQtysB[i],
      pass: dbQtysB[i] === expectedB[i],
    })),
  ];

  // Populate dbComparison + uiDbCrossCheck so the dashboard's DB Lines and UI-DB
  // tabs render. Segment line IDs give us an exact 1:1 UI↔DB mapping, so we can
  // build both directly without the product-name heuristic.
  const dbComparison = [
    ...lineIdsA.map((id, i) => ({
      index: i + 1, product: productA.productName,
      segIndex: i + 1, segKey: id,
      priorQty: beforeA[i], dbQty: dbQtysA[i],
      dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
      dbAcv: null, dbTcv: null, isBundle: false,
      startDate: null, endDate: null,
    })),
    ...lineIdsB.map((id, i) => ({
      index: lineIdsA.length + i + 1, product: productB.productName,
      segIndex: i + 1, segKey: id,
      priorQty: beforeB[i], dbQty: dbQtysB[i],
      dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
      dbAcv: null, dbTcv: null, isBundle: false,
      startDate: null, endDate: null,
    })),
  ];
  const uiDbCrossCheck = lineResults.map((line, i) => ({
    uiIndex:  line.index,
    product:  dbComparison[i].product,
    segOcc:   dbComparison[i].segIndex,
    uiBefore: line.before,
    uiAfter:  line.actual,
    dbPrior:  dbComparison[i].priorQty,
    dbAfter:  dbComparison[i].dbQty,
    match:    Math.abs(line.actual - dbComparison[i].dbQty) < 0.001,
    hasData:  true,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName,
    spinbuttonCount: lineResults.length,
    uiQtyTotal: [...expectedA, ...expectedB].reduce((s, v) => s + v, 0),
    dbQtyTotal:  [...dbQtysA,  ...dbQtysB].reduce((s, v) => s + v, 0),
    dbLineCount: lineResults.length,
    deltaApplied: DELTA,
    lineResults,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: lineResults.every(r => r.pass) && crossCheckMismatches === 0,
    extra: {
      productA: { name: productA.productName, before: beforeA, expected: expectedA, actualDb: dbQtysA, rule: 'Year 1 propagates' },
      productB: { name: productB.productName, before: beforeB, expected: expectedB, actualDb: dbQtysB, rule: `Year ${TARGET_SEGMENT} isolated` },
    },
  });
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

  await runSegmentsIncrease({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — fresh amendment, Year-1 propagation + Year-3 isolation', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, Year-1 propagation + Year-3 isolation', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, Year-1 propagation + Year-3 isolation', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
