// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quantityDecreaseBundleSegments';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
const DELTA             = 5;
// Preferred isolation segment (1-based). Capped at the product's last segment.
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

/**
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
 * Find MDQ rows whose line IDs have CPQ_Option_Type__c = 'Static Bundle' in DB.
 *
 * @param {import('@playwright/test').Page} page
 * @returns {Promise<Array<{row:import('@playwright/test').Locator, productName:string, segmentCount:number, rowIndex:number, lineIds:string[]}>>}
 */
async function findBundleRows(page) {
  const allRows = await pickProductRows(page, 2);
  if (allRows.length === 0) return [];

  /** @type {Array<typeof allRows[number] & {lineIds:string[]}>} */
  const rowsWithIds = [];
  for (const r of allRows) {
    const lineIds = await readSegmentLineIds(r.row);
    if (lineIds.length > 0) rowsWithIds.push({ ...r, lineIds });
  }
  if (rowsWithIds.length === 0) return [];

  const allIds = rowsWithIds.flatMap(r => r.lineIds);
  const soql   = `SELECT Id, CPQ_Option_Type__c FROM SBQQ__QuoteLine__c WHERE Id IN (${allIds.map(id => `'${id}'`).join(',')})`;
  const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);

  const bundleIdSet = new Set(
    (result.records || [])
      .filter(/** @param {any} r */ r => r.CPQ_Option_Type__c === 'Static Bundle')
      .map(/** @param {any} r */ r => /** @type {string} */ (r.Id))
  );
  if (bundleIdSet.size === 0) return [];

  return rowsWithIds.filter(r => r.lineIds.some(id => bundleIdSet.has(id)));
}

/**
 * After save, find all Static Component lines for the quote and assert:
 *   1. Each component segment's qty matches the bundle's expected qty at that segment.
 *   2. Revenue_Allocation__c is non-zero (allocation ratio is not touched by qty changes).
 *   3. Every component qty is ≥ its SBQQ__PriorQuantity__c (Eff. Qty ≥ 0).
 *
 * @param {string} quoteId
 * @param {number[]} expectedBySegIdx  0-based
 * @param {number} scenarioNumber
 * @returns {Promise<any[]>}
 */
async function verifyComponentLines(quoteId, expectedBySegIdx, scenarioNumber) {
  const soql = `SELECT Id, SBQQ__Quantity__c, SBQQ__PriorQuantity__c,
                       SBQQ__ProductCode__c, SBQQ__ProductName__c, CPQ_Option_Type__c,
                       Segment_Index_Custom__c, Revenue_Allocation__c, Revenue_Allocated__c
                FROM SBQQ__QuoteLine__c
                WHERE SBQQ__Quote__c = '${quoteId}'
                AND CPQ_Option_Type__c = 'Static Component'
                AND Segment_Index_Custom__c != null
                ORDER BY SBQQ__ProductCode__c, Segment_Index_Custom__c`;
  const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  const comps  = result.records || [];

  if (comps.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] No Static Component lines found — skipping component verification`);
    return [];
  }
  console.log(`[Scenario ${scenarioNumber}] Verifying ${comps.length} Static Component lines`);

  for (const c of comps) {
    const i     = parseInt(c.Segment_Index_Custom__c || '1', 10) - 1;
    const qty   = Number(c.SBQQ__Quantity__c);
    const prior = Number(c.SBQQ__PriorQuantity__c) || 0;

    if (i >= 0 && i < expectedBySegIdx.length) {
      expect(qty, `Component ${c.SBQQ__ProductCode__c} seg ${c.Segment_Index_Custom__c}: qty must match bundle qty ${expectedBySegIdx[i]}`).toBe(expectedBySegIdx[i]);
    }
    expect(qty, `Component ${c.SBQQ__ProductCode__c} seg ${c.Segment_Index_Custom__c}: qty must be ≥ priorQuantity ${prior}`).toBeGreaterThanOrEqual(prior);
    expect(
      Number(c.Revenue_Allocation__c) || 0,
      `Component ${c.SBQQ__ProductCode__c} seg ${c.Segment_Index_Custom__c}: Revenue_Allocation__c must be > 0`
    ).toBeGreaterThan(0);
  }
  return comps;
}

/**
 * Bundle quantity decrease test.
 *
 * Effective-quantity rule: a segment cannot be decreased below its priorQuantity
 * (Eff. Qty ≥ 0 is the hard floor). The same floor applies to component lines.
 *
 * Steps:
 *   1. Find Static Bundle MDQ row — skip if none.
 *   2. Compute headroom (Eff. Qty) per segment; skip if all are 0.
 *   3. Year-1 decrease → all segments propagate (with per-segment floor when needed).
 *   4. Year-N isolated decrease → only that segment changes.
 *   5. Floor clamp: typing below priorQty must be rejected by the LWC.
 *   6. Save → DB verify bundle lines + component lines.
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
async function runBundleDecrease(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  const bundleRows = await findBundleRows(page);
  if (bundleRows.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName}: no Static Bundle MDQ products — skipping`);
    test.skip(true, `Quote ${quoteName}: no Static Bundle MDQ products found`);
    return;
  }

  const bundle = bundleRows[0];
  const qs     = await readSegmentQuantities(bundle.row);
  let   effs   = await readSegmentEffQuantities(bundle.row);

  // If eff-qty cells are not rendered in the DOM, query DB for PriorQuantity.
  /** @type {number[]} */ let prior;
  if (effs.length === qs.length) {
    prior = qs.map((q, i) => q - effs[i]);
  } else {
    const lineIds = bundle.lineIds;
    const priorSoql = `SELECT Id, SBQQ__PriorQuantity__c FROM SBQQ__QuoteLine__c WHERE Id IN (${lineIds.map(id => `'${id}'`).join(',')})`;
    const priorRes  = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, priorSoql);
    const priorById = new Map((priorRes.records || []).map(/** @param {any} r */ r => [r.Id, Number(r.SBQQ__PriorQuantity__c) || 0]));
    prior = lineIds.map(id => priorById.get(id) ?? 0);
    effs  = qs.map((q, i) => q - prior[i]);
  }

  const headroom    = qs.map((q, i) => q - prior[i]); // = effs
  const minHeadroom = Math.min(...headroom);

  console.log(`[Scenario ${scenarioNumber}] Bundle: "${bundle.productName}" (${bundle.segmentCount} segs) qs=${JSON.stringify(qs)} prior=${JSON.stringify(prior)} headroom=${JSON.stringify(headroom)}`);

  if (minHeadroom <= 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName}: all bundle segments at priorQuantity (Eff. Qty = 0) — cannot decrease`);
    test.skip(true, `Quote ${quoteName}: Static Bundle has no positive effective quantity — cannot decrease`);
    return;
  }

  const idxB   = Math.min(TARGET_SEGMENT - 1, bundle.segmentCount - 1);
  const deltaA = Math.min(DELTA, minHeadroom);

  // deltaB is applied AFTER Year-1 already consumed deltaA from each segment,
  // so remaining headroom at idxB = headroom[idxB] - deltaA.
  const remainingIdxB = headroom[idxB] - deltaA;
  if (remainingIdxB <= 0) {
    test.skip(true,
      `Bundle Year ${idxB + 1} effective qty (${headroom[idxB]}) would be exhausted by Year-1 delta (${deltaA}) — cannot test Year-${idxB + 1} isolation`);
    return;
  }
  const deltaB = Math.min(DELTA, remainingIdxB);

  console.log(`[Scenario ${scenarioNumber}] deltaA=${deltaA} deltaB=${deltaB} isolation=Year ${idxB + 1}`);
  expect(bundle.lineIds.length, 'One line ID per segment input').toBe(bundle.segmentCount);

  // ── Step 1: Year-1 decrease propagates to ALL segments ───────────────────
  const beforeA   = await readSegmentQuantities(bundle.row);
  const expectedA = beforeA.map(v => v - deltaA);

  await setSegmentQuantity(bundle.row, 0, beforeA[0] - deltaA);
  await expect.poll(() => readSegmentQuantities(bundle.row), {
    message: `Bundle: all ${bundle.segmentCount} segments should reflect -${deltaA} after Year 1 edit`,
    timeout: 10_000,
    intervals: [200, 400, 600, 800, 1000],
  }).toEqual(expectedA);
  await u.screenshot(page, runDir, '03-after-year1-propagation');

  // ── Step 2: Floor-aware propagation check (optional) ─────────────────────
  // If a non-Y1 segment would hit its floor before Y1 does, the LWC should
  // pin that segment at priorQty while Y1 continues to decrease.
  /** @type {number[]} */ let finalExpectedA = expectedA;
  const headroomAfterStep1 = expectedA.map((v, i) => v - prior[i]);
  let floorIdxA = -1, minRemainingA = Infinity;
  for (let i = 1; i < expectedA.length; i++) {
    if (prior[i] > 0 && headroomAfterStep1[i] >= 0 && headroomAfterStep1[i] < minRemainingA) {
      minRemainingA = headroomAfterStep1[i];
      floorIdxA = i;
    }
  }
  if (floorIdxA !== -1) {
    const addDelta   = minRemainingA + 1;
    const newY1Floor = expectedA[0] - addDelta;
    if (newY1Floor > prior[0]) {
      const expectedStep2 = expectedA.map((v, i) => {
        if (i === 0) return v - addDelta;
        return headroomAfterStep1[i] < addDelta ? prior[i] : v - addDelta;
      });
      await setSegmentQuantity(bundle.row, 0, newY1Floor);
      await page.waitForTimeout(QUIESCE_MS);
      await u.screenshot(page, runDir, '03b-floor-aware-propagation');
      expect(
        await readSegmentQuantities(bundle.row),
        `Bundle: segment ${floorIdxA + 1} should pin at priorQuantity ${prior[floorIdxA]} while others continue`
      ).toEqual(expectedStep2);
      finalExpectedA = expectedStep2;
    }
  }

  // ── Step 3: Year-N decrease is isolated ──────────────────────────────────
  const beforeB   = await readSegmentQuantities(bundle.row); // post-step-1/2 state
  // Guard: segment idxB must still have headroom before we edit it.
  const effIdxB = beforeB[idxB] - prior[idxB];
  expect(effIdxB, `Bundle Year ${idxB + 1}: effective qty must be > 0 before isolation edit (got ${effIdxB})`).toBeGreaterThan(0);

  const expectedB  = beforeB.slice();
  expectedB[idxB]  = beforeB[idxB] - deltaB;

  await setSegmentQuantity(bundle.row, idxB, beforeB[idxB] - deltaB);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '04-after-yearN-isolation');

  expect(
    await readSegmentQuantities(bundle.row),
    `Bundle: only Year ${idxB + 1} should change during isolation edit`,
  ).toEqual(expectedB);

  // ── Step 4: Floor clamp — can't decrease below priorQty ──────────────────
  const priorYearN = prior[idxB];
  await setSegmentQuantity(bundle.row, idxB, priorYearN);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '05-at-prior-quantity');

  const expectedAtPrior  = expectedB.slice();
  expectedAtPrior[idxB]  = priorYearN;
  expect(
    await readSegmentQuantities(bundle.row),
    `Bundle Year ${idxB + 1} should land at priorQuantity ${priorYearN}`,
  ).toEqual(expectedAtPrior);

  // Attempt to go 1 below priorQty — must be rejected (clamped at prior).
  await setSegmentQuantity(bundle.row, idxB, priorYearN - 1);
  await page.waitForTimeout(QUIESCE_MS);
  await u.screenshot(page, runDir, '06-after-floor-attempt');

  expect(
    await readSegmentQuantities(bundle.row),
    `Bundle Year ${idxB + 1} must not go below priorQuantity ${priorYearN} — Eff. Qty cannot be negative`,
  ).toEqual(expectedAtPrior);

  const expectedFinal = expectedAtPrior;

  // ── Save ─────────────────────────────────────────────────────────────────
  await qtc.save(120_000);
  await u.screenshot(page, runDir, '07-after-save');
  expect(await readSegmentQuantities(bundle.row), 'Post-save: bundle reflects decrease + floor').toEqual(expectedFinal);

  // ── DB: bundle segment lines ──────────────────────────────────────────────
  const idList     = bundle.lineIds.map(id => `'${id}'`).join(',');
  const bundleSoql = `SELECT Id, SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__Quote__c
                      FROM SBQQ__QuoteLine__c WHERE Id IN (${idList})`;
  const bundleRes  = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, bundleSoql);
  const byId       = new Map((bundleRes.records || []).map(/** @param {any} r */ r => [r.Id, r]));
  const quoteId    = /** @type {string|undefined} */ (bundleRes.records?.[0]?.SBQQ__Quote__c);

  const dbQtys = bundle.lineIds.map(id => Number(byId.get(id)?.SBQQ__Quantity__c) || 0);
  for (let i = 0; i < expectedFinal.length; i++) {
    expect(dbQtys[i], `Bundle DB segment ${i + 1} (line ${bundle.lineIds[i]})`).toBe(expectedFinal[i]);
    expect(dbQtys[i], `Bundle DB segment ${i + 1}: qty must be ≥ priorQuantity ${prior[i]}`).toBeGreaterThanOrEqual(prior[i]);
  }
  await u.screenshot(page, runDir, '08-db-bundle-verified');

  // ── DB: component lines must mirror bundle qty per segment + respect floor ─
  const components = quoteId ? await verifyComponentLines(quoteId, expectedFinal, scenarioNumber) : [];

  // ── Rich results ─────────────────────────────────────────────────────────
  const lineResults = bundle.lineIds.map((_id, i) => ({
    index: i + 1, label: `${bundle.productName} · Y${i + 1}`,
    before: beforeA[i], expected: expectedFinal[i], actual: dbQtys[i],
    pass: dbQtys[i] === expectedFinal[i],
  }));
  const dbComparison = /** @type {any[]} */ (bundle.lineIds.map((_id, i) => ({
    index: i + 1, product: bundle.productName,
    segIndex: i + 1, segKey: bundle.lineIds[i],
    priorQty: prior[i], dbQty: dbQtys[i],
    dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
    dbAcv: null, dbTcv: null, isBundle: true,
    startDate: null, endDate: null,
  })));
  for (const c of components) {
    const segIdx = parseInt(c.Segment_Index_Custom__c || '1', 10);
    dbComparison.push({
      index: dbComparison.length + 1,
      product: `${c.SBQQ__ProductName__c || c.SBQQ__ProductCode__c} (${c.CPQ_Option_Type__c})`,
      segIndex: segIdx, segKey: c.Id,
      priorQty: Number(c.SBQQ__PriorQuantity__c) || null,
      dbQty: Number(c.SBQQ__Quantity__c),
      dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
      dbAcv: null, dbTcv: null, isBundle: false,
      startDate: null, endDate: null,
      revenueAllocation: Number(c.Revenue_Allocation__c) || null,
      revenueAllocated:  Number(c.Revenue_Allocated__c)  || null,
    });
  }
  const uiDbCrossCheck = lineResults.map((line, i) => ({
    uiIndex: line.index, product: bundle.productName, segOcc: i + 1,
    uiBefore: line.before, uiAfter: line.actual, dbPrior: prior[i], dbAfter: dbQtys[i],
    match: Math.abs(line.actual - dbQtys[i]) < 0.001, hasData: true,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME, scenarioNumber, scenarioLabel,
    contract: contract.number, quoteName,
    spinbuttonCount: lineResults.length,
    uiQtyTotal: expectedFinal.reduce((s, v) => s + v, 0),
    dbQtyTotal:  dbQtys.reduce((s, v) => s + v, 0),
    dbLineCount: dbComparison.length,
    deltaApplied: -deltaA, lineResults, dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: lineResults.every(r => r.pass) && crossCheckMismatches === 0,
    extra: {
      bundleProduct: bundle.productName, segmentCount: bundle.segmentCount,
      propagation: { rule: 'Year 1 decrease propagates + per-segment floor at priorQuantity', before: beforeA, expected: finalExpectedA },
      isolation:   { rule: `Year ${idxB + 1} decrease isolated`, before: beforeB, expected: expectedB },
      floor:       { segment: idxB + 1, priorYearN },
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

  await runBundleDecrease({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — fresh amendment, bundle Year-1 decrease + Year-N isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, bundle Year-1 decrease + Year-N isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, bundle Year-1 decrease + Year-N isolated + floor', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
