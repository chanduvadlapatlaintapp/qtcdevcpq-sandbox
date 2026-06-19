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

/**
 * Collect up to `maxCount` MDQ product rows that have ≥ minSegments editable
 * qty inputs, in DOM order. Returns whatever was found — callers decide whether
 * enough rows exist to proceed (no throw).
 *
 * @param {import('@playwright/test').Page} page
 * @param {number} minSegments
 * @param {number} [maxCount=8]
 */
async function pickProductRows(page, minSegments, maxCount = 8) {
  const rows = page.locator('tr.product-row');
  await rows.first().waitFor({ state: 'visible', timeout: 60_000 });
  const total = await rows.count();
  /** @type {Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, rowIndex:number}>} */
  const picked = [];
  for (let i = 0; i < total && picked.length < maxCount; i++) {
    const row    = rows.nth(i);
    const inputs = row.locator('input.qty-input');
    const n      = await inputs.count();
    if (n >= minSegments) {
      const name = (await row.locator('.product-label').first().innerText().catch(() => '')).trim();
      picked.push({ row, productName: name, segmentCount: n, rowIndex: i });
    }
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
 * Inner feature: find MDQ products with ≥ TARGET_SEGMENT segments and enough
 * effective quantity (headroom above priorQty), then:
 *
 *   • 0 qualifying rows  → skip
 *   • 1 qualifying row   → use it for both A (Year-1 propagation) and B
 *                          (Year-TARGET_SEGMENT isolation) only if Year-N
 *                          headroom remains positive after A's Year-1 delta
 *   • 2+ qualifying rows → use first for A, best different row for B
 *
 * Effective-quantity rule: a segment's quantity can never decrease below its
 * priorQuantity (Eff. Qty = 0 is the hard floor). This is enforced by:
 *   1. Only selecting candidates whose effective qty is > 0
 *   2. Capping deltaA / deltaB at the available headroom
 *   3. Asserting the LWC rejects an input below priorQty (floor clamp)
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

  // Require only ≥2 segments so 2-segment products qualify. idxB is resolved
  // after productA is selected: last segment of the product, capped at TARGET_SEGMENT-1.
  const picked = await pickProductRows(page, 2);

  if (picked.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName}: no MDQ product with ≥2 segments — skipping`);
    test.skip(true, `Quote ${quoteName}: no MDQ product with ≥2 segments`);
    return;
  }

  // Enrich every candidate: snapshot quantities, derive prior (= qty − effQty)
  // and headroom (= effQty). headroom > 0 means the segment can be decreased.
  /** @type {Array<typeof picked[number] & { qs:number[], prior:number[], headroom:number[], minHeadroom:number }>} */
  const enriched = [];
  for (const c of picked) {
    const qs       = await readSegmentQuantities(c.row);
    const effs     = await readSegmentEffQuantities(c.row);
    const prior    = qs.map((q, i) => q - (effs[i] || 0));
    const headroom = qs.map((q, i) => q - prior[i]);
    enriched.push({ ...c, qs, prior, headroom, minHeadroom: Math.min(...headroom) });
  }

  // ── Product A: needs positive headroom on ALL segments ───────────────────
  const aCandidates = enriched
    .filter(c => c.minHeadroom > 0)
    .sort((a, b) => b.minHeadroom - a.minHeadroom);
  if (aCandidates.length === 0) {
    test.skip(true,
      `No MDQ row has positive min-headroom (every segment already at priorQuantity) — ` +
      `cannot exercise Y1 propagation without crossing the priorQuantity floor.`);
    return;
  }
  const productA = aCandidates[0];
  const priorA   = productA.prior;
  const deltaA   = Math.min(DELTA, productA.minHeadroom);
  // Last segment of the chosen product, capped at TARGET_SEGMENT-1.
  const idxB     = Math.min(TARGET_SEGMENT - 1, productA.segmentCount - 1);

  // ── Product B: prefer a different row; fall back to same row ─────────────
  // For same-product fallback: after A's Year-1 edit all segments drop by
  // deltaA, so remaining headroom at idxB = headroom[idxB] − deltaA.
  let productB, priorB, deltaB, sameProduct;

  const bDifferent = enriched
    .filter(c => c.rowIndex !== productA.rowIndex && c.headroom[idxB] > 0)
    .sort((a, b) => b.headroom[idxB] - a.headroom[idxB]);

  if (bDifferent.length > 0) {
    productB    = bDifferent[0];
    priorB      = productB.prior;
    deltaB      = Math.min(DELTA, productB.headroom[idxB]);
    sameProduct = false;
  } else {
    const remainingIdxB = productA.headroom[idxB] - deltaA;
    if (remainingIdxB <= 0) {
      test.skip(true,
        `Only 1 MDQ product and Year ${idxB + 1} effective qty (${productA.headroom[idxB]}) ` +
        `would be exhausted by the Year-1 delta (${deltaA}) — cannot test Year-${idxB + 1} isolation.`);
      return;
    }
    productB    = productA;
    priorB      = priorA;
    deltaB      = Math.min(DELTA, remainingIdxB);
    sameProduct = true;
  }

  console.log(
    `[adaptive delta] Product A "${productA.productName}" min-headroom=${productA.minHeadroom} → deltaA=${deltaA}; ` +
    `Product B "${productB.productName}" Y${idxB + 1} eff.qty (after A)=${sameProduct ? productA.headroom[idxB] - deltaA : productB.headroom[idxB]} → deltaB=${deltaB}; ` +
    `sameProduct=${sameProduct}`
  );

  // ── Snapshot ─────────────────────────────────────────────────────────────
  const beforeA  = await readSegmentQuantities(productA.row);
  const lineIdsA = await readSegmentLineIds(productA.row);
  const expectedA = beforeA.map(v => v - deltaA);
  expect(lineIdsA.length, 'Product A: one line Id per segment input').toBe(beforeA.length);

  // B's pre-edit snapshot is used for cross-product isolation (different rows)
  // and lineResults.before. When same product we re-read after A's edits.
  const beforeBPreEdit = sameProduct ? null : await readSegmentQuantities(productB.row);
  const lineIdsB       = sameProduct ? lineIdsA : await readSegmentLineIds(productB.row);
  if (!sameProduct) {
    expect(lineIdsB.length, 'Product B: one line Id per segment input').toBe(/** @type {number[]} */ (beforeBPreEdit).length);
  }

  // ── Step 1: Product A Year-1 decrease — propagates to all segments ───────
  await setSegmentQuantity(productA.row, 0, beforeA[0] - deltaA);
  await expect.poll(() => readSegmentQuantities(productA.row), {
    message: `Product A: all ${productA.segmentCount} segments should reflect -${deltaA} after Year 1 edit`,
    timeout: 10_000,
    intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);
  await u.screenshot(page, runDir, '03-after-A-propagation');

  if (!sameProduct) {
    expect(await readSegmentQuantities(productB.row), 'Cross-product isolation: B unchanged after A').toEqual(beforeBPreEdit);
  }

  // ── Step 2 (optional): floor-aware propagation on A ──────────────────────
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
      if (!sameProduct) {
        expect(
          await readSegmentQuantities(productB.row),
          'Cross-product isolation: B still unchanged after A floor-aware edit'
        ).toEqual(beforeBPreEdit);
      }
      finalExpectedA = expectedAStep2;
    } else {
      console.log(`[Floor-aware propagation] Skipped on Product A — additional delta ${additionalDeltaA} would drive Y1 at or below its own prior ${priorA[0]}.`);
    }
  } else {
    console.log('[Floor-aware propagation] Skipped on Product A — no non-Y1 segment has a positive priorQuantity to floor against.');
  }

  // ── Snapshot B after all of A's edits ─────────────────────────────────────
  // When same product the row now reflects A's changes — re-read so B's
  // isolation baseline is the post-A state, not the original.
  const beforeB  = await readSegmentQuantities(productB.row);

  // Guard: B's Year-TARGET_SEGMENT effective qty must be > 0 before the edit.
  // (Verified analytically above via remainingIdxB, but re-confirm from live UI.)
  const effBIdxB = beforeB[idxB] - priorB[idxB];
  expect(
    effBIdxB,
    `Product B Year ${idxB + 1}: effective quantity must be > 0 — cannot decrease when Eff. Qty is 0 (got ${effBIdxB})`,
  ).toBeGreaterThan(0);

  const expectedB  = beforeB.slice();
  expectedB[idxB]  = beforeB[idxB] - deltaB;

  // ── Step 3: Product B Year-TARGET_SEGMENT decrease — isolated ────────────
  await setSegmentQuantity(productB.row, idxB, beforeB[idxB] - deltaB);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '04-after-B-edit');

  expect(
    await readSegmentQuantities(productB.row),
    `Only Year ${idxB + 1} should have changed on B`,
  ).toEqual(expectedB);

  // When same product A's row IS B's row — its state is now expectedB.
  expect(
    await readSegmentQuantities(productA.row),
    sameProduct
      ? `Same-product: non-Year-${idxB + 1} segments unchanged after Year ${idxB + 1} edit`
      : 'A propagation intact after B edit',
  ).toEqual(sameProduct ? expectedB : finalExpectedA);

  // ── Floor test: set B's Year-N to priorQty → Eff. Qty must show 0 ────────
  const priorYearN = priorB[idxB];
  await setSegmentQuantity(productB.row, idxB, priorYearN);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '05-at-prior-quantity');

  const expectedBAtPrior  = expectedB.slice();
  expectedBAtPrior[idxB]  = priorYearN;
  expect(
    await readSegmentQuantities(productB.row),
    `Year ${idxB + 1} should land at priorQuantity ${priorYearN}`,
  ).toEqual(expectedBAtPrior);

  const effsAtPrior = await readSegmentEffQuantities(productB.row);
  expect(effsAtPrior[idxB], `Eff. Qty for Year ${idxB + 1} must be 0 at priorQuantity`).toBe(0);

  // ── Floor clamp: typing below priorQty must be rejected ──────────────────
  await setSegmentQuantity(productB.row, idxB, priorYearN - 1);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '06-after-floor-attempt');

  expect(
    await readSegmentQuantities(productB.row),
    `Year ${idxB + 1} must not go below priorQuantity — Eff. Qty cannot be negative`,
  ).toEqual(expectedBAtPrior);
  const effsAfterFloor = await readSegmentEffQuantities(productB.row);
  expect(effsAfterFloor[idxB], 'Eff. Qty must stay at 0 after floor attempt').toBe(0);

  const expectedBFloor = expectedBAtPrior;
  // A's row final state: when same product it shares the row with B so its
  // final state is expectedBFloor; when different rows finalExpectedA stands.
  const expectedAFinal = sameProduct ? expectedBFloor : finalExpectedA;

  expect(
    await readSegmentQuantities(productA.row),
    'A propagation intact after floor attempt',
  ).toEqual(expectedAFinal);

  // ── Save and verify CPQ persistence ──────────────────────────────────────
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '07-after-save');

  expect(await readSegmentQuantities(productA.row), 'Post-save: A intact').toEqual(expectedAFinal);
  expect(await readSegmentQuantities(productB.row), 'Post-save: B reflects isolated edit + floor').toEqual(expectedBFloor);

  // ── DB verification ───────────────────────────────────────────────────────
  const allLineIds = sameProduct ? [...lineIdsA] : [...lineIdsA, ...lineIdsB];
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
  const dbQtysB = sameProduct ? dbQtysA : lineIdsB.map(id => dbById.get(id) ?? NaN);

  expect(dbQtysA.length, 'DB: one row per Product A segment').toBe(expectedAFinal.length);
  for (let i = 0; i < expectedAFinal.length; i++) {
    expect(dbQtysA[i], `Product A DB segment ${i + 1} (line ${lineIdsA[i]})`).toBe(expectedAFinal[i]);
  }
  if (!sameProduct) {
    expect(dbQtysB.length, 'DB: one row per Product B segment').toBe(expectedBFloor.length);
    for (let i = 0; i < expectedBFloor.length; i++) {
      expect(dbQtysB[i], `Product B DB segment ${i + 1} (line ${lineIdsB[i]})`).toBe(expectedBFloor[i]);
    }
  }

  // Every persisted quantity must be ≥ its priorQuantity (Eff. Qty ≥ 0).
  const allPriors = sameProduct ? [...priorA] : [...priorA, ...priorB];
  for (let i = 0; i < allLineIds.length; i++) {
    const q = dbById.get(allLineIds[i]);
    expect(q ?? 0, `Line ${allLineIds[i]}: persisted qty (${q}) must be ≥ priorQuantity (${allPriors[i]})`).toBeGreaterThanOrEqual(allPriors[i]);
  }

  // ── Rich results ─────────────────────────────────────────────────────────
  const lineResultsA = lineIdsA.map((_id, i) => ({
    index: i + 1, label: `${productA.productName} · Y${i + 1}`,
    before: beforeA[i], expected: expectedAFinal[i], actual: dbQtysA[i],
    pass: dbQtysA[i] === expectedAFinal[i],
  }));
  const lineResultsB = sameProduct ? [] : lineIdsB.map((_id, i) => ({
    index: lineIdsA.length + i + 1, label: `${productB.productName} · Y${i + 1}`,
    before: /** @type {number[]} */ (beforeBPreEdit)[i] ?? 0,
    expected: expectedBFloor[i], actual: dbQtysB[i],
    pass: dbQtysB[i] === expectedBFloor[i],
  }));
  const lineResults = [...lineResultsA, ...lineResultsB];

  const dbComparisonA = lineIdsA.map((id, i) => ({
    index: i + 1, product: productA.productName,
    segIndex: i + 1, segKey: id,
    priorQty: priorA[i], dbQty: dbQtysA[i],
    dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
    dbAcv: null, dbTcv: null, isBundle: false,
    startDate: null, endDate: null,
  }));
  const dbComparisonB = sameProduct ? [] : lineIdsB.map((id, i) => ({
    index: lineIdsA.length + i + 1, product: productB.productName,
    segIndex: i + 1, segKey: id,
    priorQty: priorB[i], dbQty: dbQtysB[i],
    dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
    dbAcv: null, dbTcv: null, isBundle: false,
    startDate: null, endDate: null,
  }));
  const dbComparison = [...dbComparisonA, ...dbComparisonB];

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
    uiQtyTotal:  [...expectedAFinal, ...(sameProduct ? [] : expectedBFloor)].reduce((s, v) => s + v, 0),
    dbQtyTotal:  [...dbQtysA, ...(sameProduct ? [] : dbQtysB)].reduce((s, v) => s + v, 0),
    dbLineCount: lineResults.length,
    deltaApplied: -deltaA,
    lineResults,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: lineResults.every(r => r.pass) && crossCheckMismatches === 0,
    extra: {
      sameProduct,
      productA: { name: productA.productName, prior: priorA, before: beforeA, expected: expectedAFinal, actualDb: dbQtysA, deltaApplied: -deltaA, rule: 'Year 1 propagates + per-segment floor at priorQuantity' },
      productB: { name: productB.productName, prior: priorB, before: beforeB, expected: expectedBFloor, actualDb: dbQtysB, deltaApplied: -deltaB, rule: `Year ${idxB + 1} isolated + floor at priorQuantity` },
      floor:    { segment: idxB + 1, priorYearN },
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
