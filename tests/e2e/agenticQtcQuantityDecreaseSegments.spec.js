// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quantityDecreaseSegments';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const DELTA             = 20;
const TARGET_SEGMENT    = 3;       // 1-based: Year 3 (Product B edit point)
// Long enough that the LWC's 500ms debounce and any reactive cycle would have
// fired. Confirms non-first-segment isolation and floor-clamp dispatch.
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

/** @param {import('@playwright/test').Page} page @param {number} minSegments @param {number} count */
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
  if (picked.length < 2) {
    throw new Error(`Needed at least 2 MDQ rows with ≥${minSegments} segments; found ${picked.length}`);
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
async function readSegmentEffQuantities(row) {
  const cells = row.locator('td.col-eff-qty span.eff-qty');
  const n     = await cells.count();
  /** @type {number[]} */ const out = [];
  for (let i = 0; i < n; i++) {
    const cls = (await cells.nth(i).getAttribute('class').catch(() => '')) || '';
    if (cls.includes('eff-qty-neutral')) { out.push(0); continue; }
    const txt = (await cells.nth(i).innerText().catch(() => '0')).trim().replace(/^\+/, '');
    const v   = parseInt(txt, 10);
    out.push(Number.isFinite(v) ? v : 0);
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

/** @param {import('@playwright/test').Locator} row @param {number} index @param {number} value */
async function setSegmentQuantity(row, index, value) {
  const input = row.locator('input.qty-input').nth(index);
  await input.click({ clickCount: 3 });
  await input.fill(String(value));
  await input.press('Tab');
}

/**
 * Inner feature: pick two MDQ products with enough headroom above priorQty,
 * verify Year-1 decrease propagates on A, Year-3 decrease is isolated on B,
 * and decrement below priorQty is floored (still expected to FAIL until the
 * LWC adds the priorQuantity guard — handleQuantityChange only enforces ≥ 0
 * today).
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
async function runSegmentsDecrease(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  // Snapshot every candidate's quantities + priorQuantity + headroom up front,
  // then pick the row with the largest min-headroom as Product A (so Year-1
  // propagation has room to apply uniformly) and a different row with the
  // largest Year-N headroom as Product B (so the isolated edit has room).
  // Each row uses an adaptive delta capped at DELTA — this lets the suite run
  // on tight contracts (first amendment, low headroom) where a hard delta of
  // DELTA would skip the whole flow.
  const idxB       = TARGET_SEGMENT - 1;
  const candidates = await pickProductRows(page, TARGET_SEGMENT, 8);
  /** @type {Array<typeof candidates[number] & { qs:number[], prior:number[], headroom:number[], minHeadroom:number }>} */
  const enriched = [];
  for (const c of candidates) {
    const qs    = await readSegmentQuantities(c.row);
    const effs  = await readSegmentEffQuantities(c.row);
    const prior = qs.map((q, i) => q - (effs[i] || 0));
    const headroom = qs.map((q, i) => q - prior[i]);
    enriched.push({ ...c, qs, prior, headroom, minHeadroom: Math.min(...headroom) });
  }

  const aCandidates = enriched
    .filter(c => c.minHeadroom > 0)
    .sort((a, b) => b.minHeadroom - a.minHeadroom);
  if (aCandidates.length === 0) {
    test.skip(true,
      `No MDQ row has positive min-headroom (every segment ≥ priorQuantity) — ` +
      `cannot exercise Y1 propagation without crossing the priorQuantity floor.`);
    return;
  }
  const productA = aCandidates[0];
  const priorA   = productA.prior;
  const deltaA   = Math.min(DELTA, productA.minHeadroom);

  const bCandidates = enriched
    .filter(c => c.rowIndex !== productA.rowIndex && c.headroom[idxB] > 0)
    .sort((a, b) => b.headroom[idxB] - a.headroom[idxB]);
  if (bCandidates.length === 0) {
    test.skip(true,
      `No second MDQ row has positive Year ${TARGET_SEGMENT} headroom — ` +
      `cannot exercise isolated Year-${TARGET_SEGMENT} decrease for Product B.`);
    return;
  }
  const productB = bCandidates[0];
  const priorB   = productB.prior;
  const deltaB   = Math.min(DELTA, productB.headroom[idxB]);

  console.log(
    `[adaptive delta] Product A "${productA.productName}" min-headroom=${productA.minHeadroom} → deltaA=${deltaA}; ` +
    `Product B "${productB.productName}" Y${TARGET_SEGMENT} headroom=${productB.headroom[idxB]} → deltaB=${deltaB}`
  );

  const beforeA   = await readSegmentQuantities(productA.row);
  const lineIdsA  = await readSegmentLineIds(productA.row);
  const expectedA = beforeA.map(v => v - deltaA);
  expect(lineIdsA.length, 'Product A: one line Id per segment input').toBe(beforeA.length);

  const beforeB   = await readSegmentQuantities(productB.row);
  const lineIdsB  = await readSegmentLineIds(productB.row);
  const expectedB = beforeB.slice();
  expectedB[idxB] = beforeB[idxB] - deltaB;
  expect(lineIdsB.length, 'Product B: one line Id per segment input').toBe(beforeB.length);

  // Product A: Year 1 decrease propagates to all segments
  await setSegmentQuantity(productA.row, 0, beforeA[0] - deltaA);
  await expect.poll(() => readSegmentQuantities(productA.row), {
    message: `Product A: all ${productA.segmentCount} segments should reflect -${deltaA} after Year 1 edit`,
    timeout: 10_000,
    intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);
  await u.screenshot(page, runDir, '03-after-A-propagation');
  expect(await readSegmentQuantities(productB.row), 'Cross-product isolation: B unchanged after A').toEqual(beforeB);

  // Floor-aware Y1 propagation on Product A: push Y1 down by just enough that
  // the non-Y1 segment with the smallest remaining headroom would land 1 below
  // its priorQuantity. Expected behavior — that segment clamps at its prior
  // while segments with headroom continue to decrease in lockstep with Y1.
  // Same caveat as the per-segment floor check on Product B below: not yet
  // enforced in agenticQtcMdqTermGroup.js, so this assertion will FAIL until
  // the LWC consults each segment's priorQuantity during propagation.
  /** @type {number[]} */ let finalExpectedA = expectedA;
  const headroomAfterStep1 = expectedA.map((v, i) => v - priorA[i]);
  let floorIdxA = -1;
  let minRemainingA = Infinity;
  for (let i = 1; i < expectedA.length; i++) {
    if (priorA[i] > 0 && headroomAfterStep1[i] >= 0 && headroomAfterStep1[i] < minRemainingA) {
      minRemainingA = headroomAfterStep1[i];
      floorIdxA = i;
    }
  }
  if (floorIdxA !== -1) {
    const additionalDeltaA = minRemainingA + 1;
    const newY1ForFloor    = expectedA[0] - additionalDeltaA;
    if (newY1ForFloor > priorA[0]) {
      const expectedAStep2 = expectedA.map((v, i) => {
        if (i === 0) return v - additionalDeltaA;
        return headroomAfterStep1[i] < additionalDeltaA ? priorA[i] : v - additionalDeltaA;
      });
      await setSegmentQuantity(productA.row, 0, newY1ForFloor);
      await page.waitForTimeout(QUIESCE_MS);
      await u.screenshot(page, runDir, '03b-A-floor-aware-propagation');
      expect(
        await readSegmentQuantities(productA.row),
        `Product A: Y1 propagation should pin segment ${floorIdxA + 1} at priorQuantity ${priorA[floorIdxA]} while other segments continue to decrease with Y1`
      ).toEqual(expectedAStep2);
      expect(
        await readSegmentQuantities(productB.row),
        'Cross-product isolation: B still unchanged after A floor-aware edit'
      ).toEqual(beforeB);
      finalExpectedA = expectedAStep2;
    } else {
      console.log(
        `[Floor-aware propagation] Skipped on Product A — additional delta ${additionalDeltaA} would drive Y1 (${expectedA[0]}) at or below its own prior ${priorA[0]}.`
      );
    }
  } else {
    console.log('[Floor-aware propagation] Skipped on Product A — no non-Y1 segment has a positive priorQuantity to floor against.');
  }

  // Product B: Year 3 decrease is isolated
  await setSegmentQuantity(productB.row, idxB, beforeB[idxB] - deltaB);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '04-after-B-edit');
  expect(await readSegmentQuantities(productB.row), `Only Year ${TARGET_SEGMENT} should have changed on B`).toEqual(expectedB);
  expect(await readSegmentQuantities(productA.row), 'A propagation intact after B edit').toEqual(finalExpectedA);

  // Floor at priorQuantity (Eff. Qty 0). NOTE: this is the intended business
  // behavior but is NOT yet enforced in agenticQtcMdqTermGroup.js — until the
  // LWC adds a priorQuantity guard the second floor assertion will FAIL.
  const priorYear3 = priorB[idxB];
  await setSegmentQuantity(productB.row, idxB, priorYear3);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '05-at-prior-quantity');

  const expectedBAtPrior = expectedB.slice();
  expectedBAtPrior[idxB] = priorYear3;
  expect(await readSegmentQuantities(productB.row), `Year ${TARGET_SEGMENT} should land at priorQuantity ${priorYear3}`).toEqual(expectedBAtPrior);
  const effsAtPrior = await readSegmentEffQuantities(productB.row);
  expect(effsAtPrior[idxB], `Eff. Qty for Year ${TARGET_SEGMENT} should be 0 at priorQuantity`).toBe(0);

  await setSegmentQuantity(productB.row, idxB, priorYear3 - 1);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '06-after-floor-attempt');
  expect(await readSegmentQuantities(productB.row), `Year ${TARGET_SEGMENT} must not go below priorQuantity`).toEqual(expectedBAtPrior);
  const effsAfterFloor = await readSegmentEffQuantities(productB.row);
  expect(effsAfterFloor[idxB], 'Eff. Qty must stay at 0 after floor attempt').toBe(0);
  expect(await readSegmentQuantities(productA.row), 'A propagation intact after floor attempt').toEqual(finalExpectedA);

  const expectedBFloor = expectedBAtPrior;

  // Save and verify CPQ persistence
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '07-after-save');
  expect(await readSegmentQuantities(productA.row), 'Post-save: A reflects Y1 propagation (with per-segment floor when applied)').toEqual(finalExpectedA);
  expect(await readSegmentQuantities(productB.row), 'Post-save: B reflects isolated edit + floor').toEqual(expectedBFloor);

  // DB verification
  const allLineIds = [...lineIdsA, ...lineIdsB];
  for (const id of allLineIds) {
    expect(id, `Line Id should match Salesforce Id pattern, got ${id}`).toMatch(/^[a-zA-Z0-9]{15,18}$/);
  }
  const idList = allLineIds.map(id => `'${id}'`).join(',');
  const soql = `SELECT Id, SBQQ__Quantity__c, SBQQ__SegmentIndex__c
                FROM SBQQ__QuoteLine__c
                WHERE Id IN (${idList})`;
  const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  /** @type {Map<string, number>} */ const dbById = new Map();
  for (const r of (result.records || [])) dbById.set(r.Id, Number(r.SBQQ__Quantity__c) || 0);

  const dbQtysA = lineIdsA.map(id => dbById.get(id) ?? NaN);
  const dbQtysB = lineIdsB.map(id => dbById.get(id) ?? NaN);

  expect(dbQtysA.length, 'DB: one row per Product A segment').toBe(finalExpectedA.length);
  for (let i = 0; i < finalExpectedA.length; i++) {
    expect(dbQtysA[i], `Product A DB segment ${i + 1} (line ${lineIdsA[i]})`).toBe(finalExpectedA[i]);
  }
  expect(dbQtysB.length, 'DB: one row per Product B segment').toBe(expectedBFloor.length);
  for (let i = 0; i < expectedBFloor.length; i++) {
    expect(dbQtysB[i], `Product B DB segment ${i + 1} (line ${lineIdsB[i]})`).toBe(expectedBFloor[i]);
  }

  const allPriors = [...priorA, ...priorB];
  for (let i = 0; i < allLineIds.length; i++) {
    const q = dbById.get(allLineIds[i]);
    expect(q ?? 0, `Line ${allLineIds[i]}: persisted qty (${q}) must be ≥ priorQuantity (${allPriors[i]})`).toBeGreaterThanOrEqual(allPriors[i]);
  }

  const lineResults = [
    ...lineIdsA.map((_id, i) => ({
      index: i + 1, label: `${productA.productName} · Y${i + 1}`,
      before: beforeA[i], expected: finalExpectedA[i], actual: dbQtysA[i],
      pass: dbQtysA[i] === finalExpectedA[i],
    })),
    ...lineIdsB.map((_id, i) => ({
      index: lineIdsA.length + i + 1, label: `${productB.productName} · Y${i + 1}`,
      before: beforeB[i], expected: expectedBFloor[i], actual: dbQtysB[i],
      pass: dbQtysB[i] === expectedBFloor[i],
    })),
  ];

  // Populate dbComparison + uiDbCrossCheck so the dashboard's DB Lines and UI-DB
  // tabs render. Segment line IDs give us an exact 1:1 UI↔DB mapping, so we can
  // build both directly without the product-name heuristic.
  const dbComparison = [
    ...lineIdsA.map((id, i) => ({
      index: i + 1, product: productA.productName,
      segIndex: i + 1, segKey: id,
      priorQty: priorA[i], dbQty: dbQtysA[i],
      dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
      dbAcv: null, dbTcv: null, isBundle: false,
      startDate: null, endDate: null,
    })),
    ...lineIdsB.map((id, i) => ({
      index: lineIdsA.length + i + 1, product: productB.productName,
      segIndex: i + 1, segKey: id,
      priorQty: priorB[i], dbQty: dbQtysB[i],
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
    uiQtyTotal:  [...finalExpectedA, ...expectedBFloor].reduce((s, v) => s + v, 0),
    dbQtyTotal:  [...dbQtysA,  ...dbQtysB].reduce((s, v) => s + v, 0),
    dbLineCount: lineResults.length,
    deltaApplied: -deltaA,
    lineResults,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: lineResults.every(r => r.pass) && crossCheckMismatches === 0,
    extra: {
      productA: { name: productA.productName, prior: priorA, before: beforeA, expected: finalExpectedA, actualDb: dbQtysA, deltaApplied: -deltaA, rule: 'Year 1 propagates + per-segment floor at priorQuantity' },
      productB: { name: productB.productName, prior: priorB, before: beforeB, expected: expectedBFloor, actualDb: dbQtysB, deltaApplied: -deltaB, rule: `Year ${TARGET_SEGMENT} isolated + floor at priorQuantity` },
      floor:    { segment: TARGET_SEGMENT, priorYear3 },
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

  await runSegmentsDecrease({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — fresh amendment, Year-1 decrease + Year-3 isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, Year-1 decrease + Year-3 isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, Year-1 decrease + Year-3 isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
