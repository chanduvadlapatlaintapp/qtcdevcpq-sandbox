// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults, buildUiDbCrossCheck } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'quantityDecreaseBundleNonSegment';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');
// Adaptive delta: actual decrease per line is min(QTY_DELTA, effectiveQty) so
// the quantity never drops below priorQty (Eff. Qty = 0 is the hard floor).
const QTY_DELTA         = 5;
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

const dirCheck = (/** @type {number|null} */ b, /** @type {number|null} */ a) => {
  if (b === null || a === null) return true;
  return a <= b;
};

/**
 * Read the effective quantity shown in the EFF. QTY cell of a non-segment row.
 * eff-qty-neutral class means Eff. Qty = 0.
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
 * Find non-segment rows (exactly 1 qty input) that are Static Bundle type.
 * Also reads effective quantity and prior quantity for each row.
 *
 * @param {import('@playwright/test').Page} page
 * @param {import('./utils/agenticQtcPage').AgenticQtcPage} qtc
 * @returns {Promise<Array<{rowIndex:number, row:import('@playwright/test').Locator, input:import('@playwright/test').Locator, lineId:string, currentQty:number, effectiveQty:number, priorQty:number, rowText:string, costBefore:string}>>}
 */
async function findNonSegmentBundleInputs(page, qtc) {
  /** @type {Array<{rowIndex:number, row:import('@playwright/test').Locator, input:import('@playwright/test').Locator, lineId:string|null, currentQty:number, effectiveQty:number, priorQty:number, rowText:string, costBefore:string}>} */
  const candidates = [];

  const productRows = page.locator('tr.product-row');
  const rowCount    = await productRows.count().catch(() => 0);
  for (let i = 0; i < rowCount; i++) {
    const row    = productRows.nth(i);
    const inputs = row.locator('input.qty-input');
    if ((await inputs.count()) !== 1) continue;
    const input        = inputs.first();
    const lineId       = await input.getAttribute('data-line-id').catch(() => null);
    const currentQty   = parseFloat(await input.inputValue().catch(() => '0')) || 0;
    const effectiveQty = await readNonSegmentEffQty(row);
    const priorQty     = currentQty - effectiveQty;
    const productName  = await row.locator('.product-label').first().innerText({ timeout: 1_000 }).catch(() => '');
    const rowText      = productName.trim() || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
    const costBefore   = await qtc.readLineCost(input);
    candidates.push({ rowIndex: i, row, input, lineId, currentQty, effectiveQty, priorQty, rowText, costBefore });
  }

  // Secondary: spinbuttons outside tr.product-row
  const spinbuttons = page.getByRole('spinbutton');
  const sbCount     = await spinbuttons.count();
  for (let i = 0; i < sbCount; i++) {
    const sb = spinbuttons.nth(i);
    if ((await sb.locator('xpath=ancestor::tr[contains(@class,"product-row")]').count()) > 0) continue;
    const lineId       = await sb.getAttribute('data-line-id').catch(() => null);
    const currentQty   = parseFloat(await sb.inputValue().catch(() => '0')) || 0;
    const row          = sb.locator('xpath=ancestor::tr').first();
    const effectiveQty = await readNonSegmentEffQty(row);
    const priorQty     = currentQty - effectiveQty;
    const productName  = await row.locator('.product-label').first().innerText({ timeout: 1_000 }).catch(() => '');
    const rowText      = productName.trim() || (await row.innerText().catch(() => '')).split('\n')[0].trim().substring(0, 60);
    const costBefore   = await qtc.readLineCost(sb);
    candidates.push({ rowIndex: -1, row, input: sb, lineId, currentQty, effectiveQty, priorQty, rowText, costBefore });
  }

  if (candidates.length === 0) return [];

  // Filter to Static Bundle lines via DB
  const withId = candidates.filter(c => c.lineId);
  if (withId.length === 0) return [];

  const soql   = `SELECT Id, CPQ_Option_Type__c FROM SBQQ__QuoteLine__c WHERE Id IN (${withId.map(c => `'${c.lineId}'`).join(',')})`;
  const result = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, soql);
  const bundleIdSet = new Set(
    (result.records || [])
      .filter(/** @param {any} r */ r => r.CPQ_Option_Type__c === 'Static Bundle')
      .map(/** @param {any} r */ r => /** @type {string} */ (r.Id))
  );

  return withId
    .filter(c => bundleIdSet.has(/** @type {string} */ (c.lineId)))
    .map(c => ({ ...c, lineId: /** @type {string} */ (c.lineId) }));
}

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
async function runQuantityDecreaseBundleNonSegment(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;

  await qtc.waitForLines(120_000);
  await u.screenshot(page, runDir, '02-editor-loaded');

  const allBundleLines = await findNonSegmentBundleInputs(page, qtc);

  if (allBundleLines.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName}: no non-segment Static Bundle products — skipping`);
    test.skip(true, `Quote ${quoteName}: no non-segment Static Bundle products found`);
    return;
  }

  // Lines with Eff. Qty = 0 cannot be decreased (already at priorQuantity).
  const eligible = allBundleLines.filter(l => {
    if (l.effectiveQty <= 0) {
      console.log(`[Scenario ${scenarioNumber}] Skipping bundle "${l.rowText}" — Eff. Qty is 0 (already at priorQuantity ${l.priorQty})`);
      return false;
    }
    return true;
  });

  if (eligible.length === 0) {
    console.log(`[Scenario ${scenarioNumber}] Quote ${quoteName}: all non-segment bundle(s) have Eff. Qty = 0 — cannot decrease`);
    test.skip(true, `Quote ${quoteName}: all non-segment Static Bundle products have Eff. Qty = 0`);
    return;
  }

  console.log(`[Scenario ${scenarioNumber}] ${eligible.length} of ${allBundleLines.length} non-segment bundle line(s) eligible for decrease in quote ${quoteName}`);

  const metricsBeforeSave = await captureMetrics(page);

  /**
   * @type {Array<{
   *   rowIndex:number, row:import('@playwright/test').Locator,
   *   input:import('@playwright/test').Locator,
   *   lineId:string, rowText:string, costBefore:string,
   *   currentQty:number, priorQty:number, effectiveQty:number,
   *   delta:number, newQty:number
   * }>}
   */
  const preSave = [];

  for (const line of eligible) {
    const current  = parseFloat(await line.input.inputValue().catch(() => '0')) || 0;
    const effQty   = await readNonSegmentEffQty(line.row);
    const priorQty = current - effQty;
    // Adaptive delta: cap at available effective qty.
    const delta    = Math.min(QTY_DELTA, effQty);
    // newQty must be >= max(priorQty, 1) to satisfy CPQ's minimum-qty validation.
    const newQty   = Math.max(Math.max(priorQty, 1), current - delta);

    await line.input.click({ clickCount: 3 });
    await line.input.fill(String(newQty));
    await line.input.press('Tab');
    await page.waitForTimeout(800);

    preSave.push({ ...line, currentQty: current, priorQty, effectiveQty: effQty, delta, newQty });
  }
  await u.screenshot(page, runDir, '03-after-qty-decrease');

  // ── Floor clamp verification ──────────────────────────────────────────────
  // Type priorQty − 1 and confirm the LWC clamps back to ≥ priorQty.
  // This exercises the "Eff. Qty cannot go negative" business rule.
  for (const line of preSave) {
    if (line.priorQty <= 0) continue;
    const belowFloor = line.priorQty - 1;

    await line.input.click({ clickCount: 3 });
    await line.input.fill(String(belowFloor));
    await line.input.press('Tab');
    await page.waitForTimeout(QUIESCE_MS);

    const afterFloor = parseFloat(await line.input.inputValue().catch(() => '0')) || 0;
    expect(
      afterFloor,
      `Bundle "${line.rowText}": typing ${belowFloor} (below priorQty ${line.priorQty}) must be clamped to at least priorQty`,
    ).toBeGreaterThanOrEqual(line.priorQty);

    const effAfterFloor = await readNonSegmentEffQty(line.row);
    expect(
      effAfterFloor,
      `Bundle "${line.rowText}": Eff. Qty must be ≥ 0 after floor attempt`,
    ).toBeGreaterThanOrEqual(0);
  }
  await u.screenshot(page, runDir, '04-after-floor-check');

  await qtc.save(120_000);
  await u.screenshot(page, runDir, '05-after-save');

  /** @type {number[]} */ const postSave  = [];
  /** @type {string[]} */ const costAfter = [];
  for (const line of preSave) {
    const val = await line.input.inputValue().catch(() => '0');
    postSave.push(parseFloat(val) || 0);
    costAfter.push(await qtc.readLineCost(line.input));
  }
  const metricsAfterSave = await captureMetrics(page);
  await u.screenshot(page, runDir, '06-final');

  // Per-line floor assertion: post-save qty must be ≥ priorQty.
  for (let i = 0; i < preSave.length; i++) {
    expect(
      postSave[i],
      `Bundle "${preSave[i].rowText}": post-save qty (${postSave[i]}) must be ≥ priorQty (${preSave[i].priorQty})`,
    ).toBeGreaterThanOrEqual(preSave[i].priorQty);
  }

  // ── DB: bundle lines ──────────────────────────────────────────────────────
  const idList     = preSave.map(l => `'${l.lineId}'`).join(',');
  const bundleSoql = `SELECT Id, SBQQ__Quantity__c, SBQQ__ProductName__c, SBQQ__PriorQuantity__c,
                             SBQQ__CustomerPrice__c, SBQQ__ListPrice__c, SBQQ__NetTotal__c, SBQQ__Discount__c,
                             SBQQ__ACV__c, SBQQ__TCV__c, SBQQ__StartDate__c, SBQQ__EndDate__c
                      FROM SBQQ__QuoteLine__c WHERE Id IN (${idList})`;
  const bundleRes  = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, bundleSoql);
  const dbById     = new Map((bundleRes.records || []).map(/** @param {any} r */ r => [r.Id, r]));

  const dbAnomalies  = /** @type {Array<{type:string,severity:string,detail:string}>} */ ([]);
  const dbComparison = /** @type {any[]} */ ([]);

  for (let i = 0; i < preSave.length; i++) {
    const db       = dbById.get(preSave[i].lineId);
    const dbQty    = Number(db?.SBQQ__Quantity__c) || 0;
    const dbPrior  = db?.SBQQ__PriorQuantity__c ?? null;
    const dbPrice  = db?.SBQQ__CustomerPrice__c  ?? null;
    const dbNetTotal = db?.SBQQ__NetTotal__c ?? null;
    const dbListPrice = db?.SBQQ__ListPrice__c ?? null;
    const dbDiscount  = db?.SBQQ__Discount__c ?? null;

    if (dbPrior !== null && dbQty < dbPrior) {
      dbAnomalies.push({ type: 'BELOW PRIOR QUANTITY', severity: 'HIGH',
        detail: `Bundle "${preSave[i].rowText}": qty (${dbQty}) < priorQuantity (${dbPrior}) — floor violated.` });
    }
    if (dbQty > 0 && dbPrice !== null && dbPrice === 0 && dbListPrice && dbListPrice > 0) {
      dbAnomalies.push({ type: 'POSSIBLE 100% DISCOUNT', severity: 'HIGH',
        detail: `Bundle "${preSave[i].rowText}": ListPrice=$${dbListPrice} but CustomerPrice=$0.` });
    }

    dbComparison.push({
      index: i + 1, product: db?.SBQQ__ProductName__c || preSave[i].rowText,
      segKey: preSave[i].lineId, segIndex: null,
      priorQty: dbPrior, dbQty, dbPrice, dbListPrice, dbDiscount, dbNetTotal,
      dbAcv: db?.SBQQ__ACV__c ?? null, dbTcv: db?.SBQQ__TCV__c ?? null,
      isBundle: true,
      startDate: db?.SBQQ__StartDate__c, endDate: db?.SBQQ__EndDate__c,
    });
  }

  // ── DB: component lines must mirror bundle qty + respect floor ────────────
  if (preSave.length > 0) {
    const expectedQty = preSave[0].newQty;
    const compSoql    = `SELECT Id, SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__ProductCode__c,
                                SBQQ__ProductName__c, CPQ_Option_Type__c,
                                Revenue_Allocation__c, Revenue_Allocated__c
                         FROM SBQQ__QuoteLine__c
                         WHERE SBQQ__Quote__r.Name = '${quoteName}'
                         AND CPQ_Option_Type__c = 'Static Component'
                         AND SBQQ__SegmentIndex__c = NULL
                         ORDER BY SBQQ__ProductCode__c`;
    const compRes     = await u.sfQueryNode(sfCtx.instanceUrl, sfCtx.accessToken, compSoql);
    const comps       = compRes.records || [];

    if (comps.length > 0) {
      console.log(`[Scenario ${scenarioNumber}] Verifying ${comps.length} non-segment component(s) (expected qty=${expectedQty})`);
      for (const c of comps) {
        const compQty   = Number(c.SBQQ__Quantity__c);
        const compPrior = Number(c.SBQQ__PriorQuantity__c) || 0;
        expect(
          compQty,
          `Component ${c.SBQQ__ProductCode__c || c.SBQQ__ProductName__c}: qty should match bundle qty ${expectedQty}`
        ).toBe(expectedQty);
        expect(
          compQty,
          `Component ${c.SBQQ__ProductCode__c || c.SBQQ__ProductName__c}: qty must be ≥ priorQuantity ${compPrior}`
        ).toBeGreaterThanOrEqual(compPrior);
        expect(
          Number(c.Revenue_Allocation__c) || 0,
          `Component ${c.SBQQ__ProductCode__c || c.SBQQ__ProductName__c}: Revenue_Allocation__c must be > 0`
        ).toBeGreaterThan(0);
        dbComparison.push({
          index: dbComparison.length + 1,
          product: `${c.SBQQ__ProductName__c || c.SBQQ__ProductCode__c} (${c.CPQ_Option_Type__c})`,
          segKey: c.Id, segIndex: null,
          priorQty: compPrior || null, dbQty: compQty,
          dbPrice: null, dbListPrice: null, dbDiscount: null, dbNetTotal: null,
          dbAcv: null, dbTcv: null, isBundle: false,
          startDate: null, endDate: null,
          revenueAllocation: Number(c.Revenue_Allocation__c) || null,
          revenueAllocated:  Number(c.Revenue_Allocated__c)  || null,
        });
      }
    } else {
      console.log(`[Scenario ${scenarioNumber}] No non-segment Static Component lines found for quote ${quoteName}`);
    }
  }

  // ── Line results ─────────────────────────────────────────────────────────
  const lineResults = /** @type {Array<{index:number,label:string,before:number,expected:number,actual:number,pass:boolean,costBefore:string,costAfter:string}>} */ ([]);
  let allQtyPass = true;
  for (let i = 0; i < preSave.length; i++) {
    const expected = preSave[i].newQty;
    const actual   = postSave[i];
    const pass     = Math.abs(actual - expected) < 0.001;
    if (!pass) allQtyPass = false;
    lineResults.push({
      index: i + 1, label: preSave[i].rowText || `Bundle line ${i + 1}`,
      before: preSave[i].currentQty, expected, actual, pass,
      costBefore: preSave[i].costBefore, costAfter: costAfter[i],
    });
  }

  const acvBefore = u.parseCurrency(metricsBeforeSave.acv);
  const acvAfter  = u.parseCurrency(metricsAfterSave.acv);
  const tcvBefore = u.parseCurrency(metricsBeforeSave.tcv);
  const tcvAfter  = u.parseCurrency(metricsAfterSave.tcv);

  const metricResults = [
    { metric: 'ACV',         before: metricsBeforeSave.acv,       after: metricsAfterSave.acv,       pass: dirCheck(acvBefore, acvAfter),       note: acvBefore !== null && acvAfter !== null ? `Δ = ${(acvAfter - acvBefore).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'ACV Change',  before: metricsBeforeSave.acvChange, after: metricsAfterSave.acvChange, pass: true,                                note: 'Reflects cumulative change from original contract' },
    { metric: 'TCV',         before: metricsBeforeSave.tcv,       after: metricsAfterSave.tcv,       pass: dirCheck(tcvBefore, tcvAfter),       note: tcvBefore !== null && tcvAfter !== null ? `Δ = ${(tcvAfter - tcvBefore).toFixed(2)}` : 'Pricing at $0 — verify in org' },
    { metric: 'YoY Uplift',  before: metricsBeforeSave.yoyUplift, after: metricsAfterSave.yoyUplift, pass: true, note: 'Directional — informational' },
    { metric: 'Deal Quality Score', before: metricsBeforeSave.dealQuality, after: metricsAfterSave.dealQuality, pass: true, note: 'Approval logic driven — informational' },
  ];

  const hasApproval = await page.getByText('Approvals required').isVisible().catch(() => false);
  const hasSendBtn  = await page.getByRole('button', { name: 'Preview and Send OSA' }).isVisible().catch(() => false);

  const dbHighCount          = dbAnomalies.filter(a => a.severity === 'HIGH').length;
  const uiDbCrossCheck       = buildUiDbCrossCheck(lineResults, dbComparison);
  const crossCheckMismatches = uiDbCrossCheck.filter(r => r.hasData && !r.match).length;
  const allPass              = allQtyPass && metricResults.every(m => m.pass) && dbHighCount === 0 && crossCheckMismatches === 0;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME, scenarioNumber, scenarioLabel,
    contract: contract.number, quoteName,
    quoteId: null, hasApproval, hasSendBtn,
    spinbuttonCount: preSave.length,
    uiQtyTotal: postSave.reduce((s, v) => s + v, 0),
    dbQtyTotal: dbComparison.reduce((s, d) => s + (d.dbQty ?? 0), 0),
    dbLineCount: dbComparison.length,
    deltaApplied: -QTY_DELTA,
    metricsBeforeSave, metricsAfterSave,
    lineResults, metricResults,
    dbComparison, dbAnomalies,
    uiDbCrossCheck, crossCheckMismatches,
    passed: allPass,
    extra: {
      bundleLineCount: allBundleLines.length,
      eligibleLineCount: preSave.length,
      skippedLines: allBundleLines
        .filter(l => l.effectiveQty <= 0)
        .map(l => ({ product: l.rowText, effectiveQty: l.effectiveQty, priorQty: l.priorQty })),
    },
  });

  expect(allQtyPass, 'All non-segment bundle line quantity assertions should pass').toBe(true);
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

  await runQuantityDecreaseBundleNonSegment({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — fresh amendment, non-segment bundle qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — existing draft, non-segment bundle qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — modal pick, non-segment bundle qty decrease', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
