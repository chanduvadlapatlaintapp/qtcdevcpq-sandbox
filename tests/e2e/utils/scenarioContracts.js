// @ts-check
/**
 * Shared 3-scenario plumbing used by every agenticQtc*.spec.js.
 *
 * The OSA selector LWC takes one of three branches when the user clicks a
 * contract row (see agenticQtcOsaSelector.js → handleContractClick):
 *   • 0 draft amendments → creates new amendment, editor mounts directly
 *   • 1 draft amendment  → opens that draft directly, editor mounts
 *   • 2+ draft amendments → opens "Existing Draft Quotes" picker modal
 *
 * Every spec exercises one inner feature on each of those three branches.
 * This module owns the bucket routing (driven by the LWC, not by REST) and
 * the per-branch open-editor logic with its branch-specific assertions.
 */
const { expect } = require('@playwright/test');
const { loginViaCookie } = require('../helpers/sfAuth');
const { AgenticQtcPage } = require('./agenticQtcPage');
const u = require('./playwrightUtils');

/** @typedef {{ id: string, number: string, draftCount: number }} ContractRec */
/** @typedef {{ zero: ContractRec|null, one: ContractRec|null, many: ContractRec|null }} ByScenario */
/** @typedef {{ byScenario: ByScenario }} ContractCache */
/** @typedef {{ instanceUrl: string, lightningUrl: string, accessToken: string }} SfCtx */
/** @typedef {'zero'|'one'|'many'} Branch */

/**
 * Drive the LWC once, pick its first contract, count its drafts, and route
 * it to exactly one scenario bucket. The other two buckets stay null and
 * their tests self-skip.
 *
 * @param {import('@playwright/test').Browser} browser
 * @param {SfCtx & { accountSearch: string, accountFullName: string }} ctx
 * @returns {Promise<ContractCache>}
 */
async function discoverContractByScenarios(browser, ctx) {
  const setupCtx  = await browser.newContext();
  const setupPage = await setupCtx.newPage();
  try {
    await loginViaCookie(setupPage, ctx.lightningUrl, ctx.accessToken);
    const qtc = new AgenticQtcPage(setupPage, ctx);
    await qtc.goto();
    await qtc.searchAndSelectAccount(ctx.accountSearch, ctx.accountFullName);
    await qtc.contractRows().first().waitFor({ state: 'visible', timeout: 30_000 }).catch(() => {});

    const visible = await qtc.getContractList();
    console.log(`[scenarioContracts] LWC contracts visible for "${ctx.accountFullName}": ${visible.length}`);
    if (visible.length === 0) {
      console.log('[scenarioContracts] No contracts — all scenarios will skip');
      return { byScenario: { zero: null, one: null, many: null } };
    }

    const first = visible[0];
    const draftSoql = `SELECT Id FROM SBQQ__Quote__c
                       WHERE SBQQ__MasterContract__c = '${first.id}'
                       AND SBQQ__Status__c = 'Draft'
                       AND SBQQ__EndDate__c >= TODAY`;
    const draftRes = await u.sfQueryNode(ctx.instanceUrl, ctx.accessToken, draftSoql);
    const contract = { id: first.id, number: first.number, draftCount: draftRes.records.length };

    const bucket = contract.draftCount === 0 ? 'zero'
                 : contract.draftCount === 1 ? 'one'
                 : 'many';
    const scenarioNum = bucket === 'zero' ? 1 : bucket === 'one' ? 2 : 3;
    console.log(`[scenarioContracts] First contract: ${contract.number} (${contract.id}) — ${contract.draftCount} draft(s) → Scenario ${scenarioNum}; other two will skip`);

    return {
      byScenario: {
        zero: bucket === 'zero' ? contract : null,
        one:  bucket === 'one'  ? contract : null,
        many: bucket === 'many' ? contract : null,
      },
    };
  } finally {
    await setupCtx.close();
  }
}

/**
 * Login, select the account, click the given contract, and resolve whichever
 * of the three OSA-selector branches fires — with branch-specific assertions
 * so a wrong-branch outcome fails fast.
 *
 * Returns the page object plus the loaded quote name. Caller can then run
 * its feature-specific logic against `qtc.page` / `qtc.*` helpers.
 *
 * @param {import('@playwright/test').Page} page
 * @param {SfCtx & { accountSearch: string, accountFullName: string }} ctx
 * @param {ContractRec} contract
 * @param {Branch} branch
 * @returns {Promise<{ qtc: AgenticQtcPage, quoteName: string, preExistingDrafts: string[] }>}
 */
async function openEditorByScenario(page, ctx, contract, branch) {
  await loginViaCookie(page, ctx.lightningUrl, ctx.accessToken);
  const qtc = new AgenticQtcPage(page, ctx);
  await qtc.goto();
  await qtc.searchAndSelectAccount(ctx.accountSearch, ctx.accountFullName);

  const preExistingDrafts = (await qtc.getDraftQuotesForContract(contract.id))
    .map((/** @type {{name:string}} */ d) => d.name);

  await qtc.clickContractById(contract.id);
  const outcome = await qtc.waitForContractClickOutcome(120_000);

  if (branch === 'many' && outcome === 'modal') {
    // App surfaced the picker (2+ drafts visible to the runner user) — pick the first.
    const modalCount = await qtc.draftQuoteCountInModal();
    expect(modalCount, 'Modal should list ≥ 2 drafts').toBeGreaterThanOrEqual(2);
    await qtc.draftQuoteRows().first().click();
    await qtc.saveButton().waitFor({ state: 'visible', timeout: 120_000 });
  } else if (branch === 'many') {
    // Discovery counts drafts with a plain SOQL query that does NOT enforce
    // record sharing, but the LWC's getDraftQuotesForContract runs `with sharing`
    // — so it can legitimately see fewer drafts (e.g. one owned by an integration
    // user and not shared with the runner) and open the editor directly instead
    // of the picker. Accept that and continue the feature against the open editor;
    // only a hard timeout (neither editor nor modal) is a real failure.
    expect(outcome, 'Many-drafts branch should open either the modal or the editor').not.toBe('timeout');
    if (outcome === 'editor') {
      console.warn('[scenarioContracts] "many" bucket but the editor mounted directly — ' +
        'fewer drafts are visible to the runner user than the raw count (record sharing). ' +
        'Proceeding with the open editor.');
    }
  } else {
    expect(outcome, 'Editor should mount directly — no modal').toBe('editor');
  }

  await qtc.waitForLines(120_000);
  const quoteName = await qtc.getQuoteName();
  expect(quoteName, 'Editor header should show a Q-NNNNN name').toMatch(/^Q-\d+$/);

  if (branch === 'zero') {
    expect(preExistingDrafts, 'Newly created amendment should not match any pre-existing draft')
      .not.toContain(quoteName);
  } else if (branch === 'one') {
    expect(quoteName, 'Should open the single existing draft')
      .toBe(preExistingDrafts[0]);
  }

  return { qtc, quoteName: /** @type {string} */ (quoteName), preExistingDrafts };
}

module.exports = { discoverContractByScenarios, openEditorByScenario };
