// @ts-check
const path = require('path');
const { test, expect } = require('@playwright/test');
const { getSfCredentials } = require('./helpers/sfAuth');
const u = require('./utils/playwrightUtils');
const { buildRichResults } = require('./utils/richResults');
const { discoverContractByScenarios, openEditorByScenario } = require('./utils/scenarioContracts');

const KIND              = 'contactUpdate';
const ACCOUNT_SEARCH    = process.env.QTC_ACCOUNT_SEARCH    || 'Bates White';
const ACCOUNT_FULL_NAME = process.env.QTC_ACCOUNT_FULL_NAME || 'Bates White';
const RESULTS_DIR       = path.join(__dirname, 'results');

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
 * Inner feature: pick different Invoicing + Software Delivery contacts, save,
 * verify both UI and SBQQ__Quote__c columns match the picked Contact Ids.
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
async function runContactUpdate(ctx) {
  const { page, qtc, runDir, runTs, testStartMs, contract, scenarioNumber, scenarioLabel, quoteName } = ctx;
  await u.screenshot(page, runDir, '02-editor-loaded');

  const uiBeforeInv = await qtc.readContactDisplay('invoicing');
  const uiBeforeDel = await qtc.readContactDisplay('delivery');
  const dbBefore    = await qtc.fetchContactsFromDb(quoteName);
  expect(dbBefore, `Quote '${quoteName}' should be queryable via REST API`).not.toBeNull();

  const newInv = await qtc.pickDifferentContact('invoicing', dbBefore?.invoicing.id ?? null);
  expect(newInv, 'Account should expose at least one Contact for invoicing').not.toBeNull();
  const newDel = await qtc.pickDifferentContact('delivery', dbBefore?.delivery.id ?? null);
  expect(newDel, 'Account should expose at least one Contact for delivery').not.toBeNull();
  await u.screenshot(page, runDir, '03-contacts-picked');

  // Contact-only edits don't recompute lines — short settle window suffices.
  await qtc.save(90_000, 300);
  await u.screenshot(page, runDir, '04-after-save');

  const uiAfterInv = await qtc.readContactDisplay('invoicing', 3_000);
  const uiAfterDel = await qtc.readContactDisplay('delivery',  3_000);
  const dbAfter    = await qtc.fetchContactsFromDb(quoteName);
  expect(dbAfter, `Quote '${quoteName}' should still be queryable after save`).not.toBeNull();

  const slots = [
    {
      slot: 'Invoicing Contact', type: 'invoicing',
      expectedId: newInv?.id, expectedName: newInv?.name,
      uiBefore: uiBeforeInv, uiAfter: uiAfterInv,
      dbBefore: dbBefore?.invoicing, dbAfter: dbAfter?.invoicing,
    },
    {
      slot: 'Software Delivery Contact', type: 'delivery',
      expectedId: newDel?.id, expectedName: newDel?.name,
      uiBefore: uiBeforeDel, uiAfter: uiAfterDel,
      dbBefore: dbBefore?.delivery, dbAfter: dbAfter?.delivery,
    },
  ];
  const comparison = slots.map(s => ({
    slot: s.slot, type: s.type,
    expectedContactId: s.expectedId || null,
    expectedContactName: s.expectedName || null,
    uiBeforeName: s.uiBefore.name || null, uiBeforeEmail: s.uiBefore.email || null,
    uiAfterName:  s.uiAfter.name  || null, uiAfterEmail:  s.uiAfter.email  || null,
    dbBeforeId:   s.dbBefore?.id   || null, dbBeforeName: s.dbBefore?.name || null,
    dbAfterId:    s.dbAfter?.id    || null, dbAfterName:  s.dbAfter?.name  || null,
    uiMatch: (s.uiAfter.name || '') === (s.expectedName || ''),
    dbMatch: (s.dbAfter?.id  || null) === (s.expectedId  || null),
    changed: (s.dbBefore?.id || null) !== (s.dbAfter?.id || null),
  }));

  for (const c of comparison) {
    expect(c.dbAfterId,   `${c.slot}: DB id should equal picked Contact Id`).toBe(c.expectedContactId);
    expect(c.uiAfterName, `${c.slot}: UI should display picked Contact name`).toBe(c.expectedContactName);
    expect(c.changed,     `${c.slot}: DB id should differ from pre-save baseline`).toBe(true);
  }

  // Surface the per-slot comparison via the standard dbComparison + uiDbCrossCheck
  // shape so the dashboard's DB Lines + UI-DB tabs render meaningful rows even
  // though this suite is contact-slot based, not line-based.
  const dbComparison = comparison.map((c, i) => ({
    index:    i + 1,
    product:  c.slot,
    segKey:   c.dbAfterId || '—',
    segIndex: null,
    priorQty: null, dbQty: null, dbPrice: null, dbListPrice: null,
    dbDiscount: null, dbNetTotal: null, dbAcv: null, dbTcv: null,
    isBundle: false,
    startDate: null, endDate: null,
    pricingMethod: null, term: null, regularPrice: null,
  }));
  const uiDbCrossCheck = comparison.map((c, i) => ({
    uiIndex:  i + 1,
    product:  c.slot,
    segOcc:   null,
    uiBefore: c.uiBeforeName,
    uiAfter:  c.uiAfterName,
    dbPrior:  c.dbBeforeName,
    dbAfter:  c.dbAfterName,
    match:    c.uiMatch && c.dbMatch,
    hasData:  true,
  }));
  const crossCheckMismatches = uiDbCrossCheck.filter(r => !r.match).length;

  buildRichResults({
    kind: KIND, runTs, runDir, testStartMs,
    accountName: ACCOUNT_FULL_NAME,
    scenarioNumber, scenarioLabel,
    contract: contract.number,
    quoteName, quoteId: dbAfter?.quoteId || null,
    dbLineCount: dbComparison.length,
    dbComparison, uiDbCrossCheck, crossCheckMismatches,
    passed: crossCheckMismatches === 0,
    extra: { comparison },
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

  await runContactUpdate({
    page, qtc, runDir, runTs, testStartMs,
    contract, scenarioNumber, scenarioLabel, quoteName,
  });
}

test('Scenario 1: contract with 0 amendments — creates new amendment, then contact update', async ({ page }) => {
  const c = contractCache?.byScenario.zero;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 0 draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'zero', 1, 'Contract with 0 amendments → new amendment');
});

test('Scenario 2: contract with 1 amendment — opens existing draft, then contact update', async ({ page }) => {
  const c = contractCache?.byScenario.one;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has exactly 1 draft amendment`);
  await runScenario(page, /** @type {any} */ (c), 'one', 2, 'Contract with 1 amendment → existing draft');
});

test('Scenario 3: contract with multiple amendments — picks from modal, then contact update', async ({ page }) => {
  const c = contractCache?.byScenario.many;
  test.skip(!c, `No contract on ${ACCOUNT_FULL_NAME} currently has 2+ draft amendments`);
  await runScenario(page, /** @type {any} */ (c), 'many', 3, 'Contract with 2+ amendments → modal pick');
});
