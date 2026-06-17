// @ts-check
/**
 * Page object for the Agentic_QTC Lightning app.
 *
 * Selectors are anchored to the actual LWC class names so they don't
 * depend on locale, accessibility-name heuristics, or row index.
 *
 * Component map:
 *   agenticQtcAccountSearch  → .native-search-input, .account-card
 *   agenticQtcOsaSelector    → .contracts-table, tr.contract-row,
 *                              .quotes-modal, tr.quote-row,
 *                              .quotes-modal-create-btn
 *   agenticQtcQuoteEditor    → lightning-input.date-input,
 *                              .header-title-link (quote name),
 *                              <lightning-button label="Save">
 */
const u = require('./playwrightUtils');
const { expect } = require('@playwright/test');

/** @typedef {import('@playwright/test').Page} Page */
/** @typedef {import('@playwright/test').Locator} Locator */

const APP_PATH = '/lightning/n/Agentic_QTC';

class AgenticQtcPage {
  /**
   * @param {Page} page
   * @param {{lightningUrl: string, instanceUrl: string, accessToken: string}} ctx
   */
  constructor(page, ctx) {
    this.page         = page;
    this.lightningUrl = ctx.lightningUrl;
    this.instanceUrl  = ctx.instanceUrl;
    this.accessToken  = ctx.accessToken;
  }

  // ─── Navigation ────────────────────────────────────────────────────────────

  async goto() {
    // Salesforce sometimes redirects mid-navigation through /secur/contentDoor
    // for session-cookie handshake, which throws "Navigation interrupted" if we
    // wait for 'domcontentloaded'. Use 'commit' (fires as soon as the request
    // commits to a URL) and let accountSearchInput().waitFor() confirm the
    // final landing page — handles arbitrary redirect chains.
    await this.page.goto(`${this.lightningUrl}${APP_PATH}`, { waitUntil: 'commit' })
      .catch(() => { /* swallow nav-interrupt; the waitFor below is the real check */ });
    await this.accountSearchInput().waitFor({ state: 'visible', timeout: 60_000 });
  }

  // ─── Account search ────────────────────────────────────────────────────────

  accountSearchInput() {
    return this.page.locator('input.native-search-input');
  }

  /** All account-result cards currently shown in the search dropdown. */
  accountCards() {
    return this.page.locator('div.account-card');
  }

  /** The "No accounts found for …" empty-state dropdown. */
  noResultsDropdown() {
    return this.page.locator('.no-results-dropdown');
  }

  /**
   * Type a term into the account search box WITHOUT selecting anything.
   * Mirrors the LWC's 300ms input debounce by settling briefly after the
   * keystrokes so the Apex round-trip has fired by the time the caller reads
   * the dropdown. Use this for behavior assertions; use searchAndSelectAccount
   * when the goal is to drill into a contract.
   * @param {string} term
   * @param {number} [settleMs=1200]
   */
  async typeAccountSearch(term, settleMs = 1_200) {
    await this.accountSearchInput().fill(term);
    if (settleMs > 0) await this.page.waitForTimeout(settleMs);
  }

  /**
   * Read every account card in the open dropdown:
   *   [{ id, name, location }]
   * Single page.evaluate so a full dropdown costs one CDP round-trip.
   */
  async readAccountCards() {
    return this.accountCards().evaluateAll((els) =>
      els.map((el) => ({
        id:       el.getAttribute('data-id'),
        name:     (el.querySelector('.account-name')?.textContent || '').trim(),
        location: (el.querySelector('.account-location')?.textContent || '').trim(),
      }))
    );
  }

  /**
   * Count eligible contracts for an account using the SAME semi-join the
   * account search Apex applies (see AgenticQTC_AccountSearchService.cls):
   *   Status IN ('In Force','Partially Cancelled or superseded')
   *   AND EndDate >= today
   *   AND has ≥1 Software subscription line.
   * Any account returned by the search must satisfy this (count >= 1).
   * @param {string} accountId
   * @returns {Promise<number>}
   */
  async countEligibleContracts(accountId) {
    const soql = `SELECT COUNT() FROM Contract
                  WHERE AccountId = '${accountId}'
                  AND Status IN ('In Force', 'Partially Cancelled or superseded')
                  AND EndDate >= TODAY
                  AND Id IN (
                    SELECT SBQQ__Contract__c FROM SBQQ__Subscription__c
                    WHERE SBQQ__Contract__c != null
                    AND SBQQ__Product__r.Product_Type__c = 'Software'
                  )`;
    const result = await u.sfQuery(this.page, this.instanceUrl, this.accessToken, soql);
    return result.totalSize ?? 0;
  }

  /**
   * Click the account-card whose data-name attribute (or visible name)
   * matches `fullName`.
   * @param {string} fullName
   */
  accountCard(fullName) {
    return this.page.locator(`div.account-card[data-name="${fullName}"]`);
  }

  /**
   * Type into the search box, then click the result that best matches.
   *
   * Selection order (most → least specific):
   *   1. Card whose data-name attribute matches `fullName` exactly
   *   2. Card whose visible text contains `fullName` (handles casing/spacing drift)
   *   3. The first card in the dropdown (after the search filter, this is the
   *      best candidate — works even when the caller only supplied a search
   *      term and left fullName blank)
   *
   * @param {string} searchTerm
   * @param {string} fullName
   */
  async searchAndSelectAccount(searchTerm, fullName) {
    await this.accountSearchInput().fill(searchTerm);

    // Wait for at least one search result to appear before deciding which to click
    const anyCard = this.page.locator('div.account-card').first();
    await anyCard.waitFor({ state: 'visible', timeout: 20_000 });

    const exactCard   = fullName ? this.accountCard(fullName)                                       : null;
    const textCard    = fullName ? this.page.locator('div.account-card').filter({ hasText: fullName }).first() : null;

    let target = anyCard;
    if (exactCard && (await u.isVisibleSafe(exactCard, 1_500))) {
      target = exactCard;
    } else if (textCard && (await u.isVisibleSafe(textCard, 1_500))) {
      target = textCard;
    }

    await target.click();
    await this.activeContractsHeading().waitFor({ state: 'visible', timeout: 30_000 });
  }

  // ─── Contracts list ────────────────────────────────────────────────────────

  activeContractsHeading() {
    return this.page.getByRole('heading', { name: /Active Contracts/i });
  }

  contractRows() {
    return this.page.locator('tr.contract-row');
  }

  /** The "N active contract(s)" count badge shown beside the section header. */
  contractCountBadge() {
    return this.page.locator('.contract-count-badge');
  }

  /** The "No active contracts found" empty-state inside the contracts section. */
  noContractsState() {
    return this.page.locator('.contracts-section .no-results');
  }

  /** "Clear" pill that returns from the contracts list to account search. */
  accountPillClear() {
    return this.page.locator('button.account-pill-clear');
  }

  /** All "+N more" product-expand buttons across the visible contract rows. */
  productMoreButtons() {
    return this.page.locator('button.product-more-btn');
  }

  /** The single "Show less" button visible inside an expanded products cell. */
  productShowLessButton() {
    return this.page.locator('button.product-toggle-btn', { hasText: /Show less/i });
  }

  /**
   * Read all visible contract rows and return their { id, number, index }
   * pairs. `id` comes from data-id (the SF Contract Id), `number` from
   * data-number. Use to look up scenarios via REST API.
   */
  async getContractList() {
    const rows  = this.contractRows();
    const count = await rows.count();
    const out   = [];
    for (let i = 0; i < count; i++) {
      const id     = await rows.nth(i).getAttribute('data-id');
      const number = await rows.nth(i).getAttribute('data-number');
      if (id) out.push({ id, number: number ?? '', index: i });
    }
    return out;
  }

  /**
   * Count draft amendment quotes for a contract using the EXACT SOQL filter
   * the LWC's picker uses (see AgenticQTC_QuoteAmendmentService.cls
   * getDraftQuotesForContract, lines 817-828). The OSA selector branches on
   * this count: 0 → new amendment, 1 → opens that draft, ≥2 → picker modal.
   * The filter is stricter than "Draft + future end date": it also requires
   * Type='Amendment', Deal_Type='Add-On', and an open opportunity stage.
   * @param {string} contractId
   * @returns {Promise<number>}
   */
  async countDraftQuotes(contractId) {
    const soql = `SELECT COUNT() FROM SBQQ__Quote__c
                  WHERE SBQQ__MasterContract__c = '${contractId}'
                  AND SBQQ__Status__c = 'Draft'
                  AND SBQQ__Type__c = 'Amendment'
                  AND Deal_Type__c = 'Add-On'
                  AND (NOT Opportunity_Stage__c LIKE '%Closed%')
                  AND SBQQ__EndDate__c >= TODAY`;
    const result = await u.sfQuery(this.page, this.instanceUrl, this.accessToken, soql);
    return result.totalSize ?? 0;
  }

  /**
   * List draft amendment quotes for a contract. Mirrors what the OSA
   * selector's getDraftQuotesForContract Apex call returns.
   * @param {string} contractId
   * @returns {Promise<Array<{id:string, name:string, startDate:string|null, endDate:string|null}>>}
   */
  async getDraftQuotesForContract(contractId) {
    const soql = `SELECT Id, Name, SBQQ__StartDate__c, SBQQ__EndDate__c
                  FROM SBQQ__Quote__c
                  WHERE SBQQ__MasterContract__c = '${contractId}'
                  AND SBQQ__Status__c = 'Draft'
                  AND SBQQ__Type__c = 'Amendment'
                  AND Deal_Type__c = 'Add-On'
                  AND (NOT Opportunity_Stage__c LIKE '%Closed%')
                  AND SBQQ__EndDate__c >= TODAY
                  ORDER BY CreatedDate DESC`;
    const result = await u.sfQuery(this.page, this.instanceUrl, this.accessToken, soql);
    return result.records.map(r => ({
      id:        r.Id,
      name:      r.Name,
      startDate: r.SBQQ__StartDate__c ?? null,
      endDate:   r.SBQQ__EndDate__c   ?? null,
    }));
  }

  /**
   * Click a contract row identified by its SF Contract Id (data-id).
   * Does NOT branch on what happens afterwards — caller decides.
   * @param {string} contractId
   */
  async clickContractById(contractId) {
    const row = this.contractRows().filter({ has: this.page.locator(`[data-id="${contractId}"]`) }).first();
    // Fallback to attribute selector on the row itself if filter didn't match
    const fallback = this.page.locator(`tr.contract-row[data-id="${contractId}"]`).first();
    const candidate = (await row.count().catch(() => 0)) > 0 ? row : fallback;
    await candidate.waitFor({ state: 'visible', timeout: 10_000 });
    await candidate.click();
  }

  /**
   * After clicking a contract, race the three possible outcomes and
   * report which one fired:
   *   - 'editor'  → Save button appeared (direct mount: 0 or 1 drafts)
   *   - 'modal'   → "Existing Draft Quotes" modal appeared (>1 drafts)
   *   - 'timeout' → neither appeared within `timeout` ms
   * @param {number} [timeout=60000]
   */
  async waitForContractClickOutcome(timeout = 60_000) {
    const saveBtn = this.saveButton();
    const modal   = this.draftQuotesModal();
    const winner  = await u.waitForAny([saveBtn, modal], timeout);
    if (winner === 0) return 'editor';
    if (winner === 1) return 'modal';
    return 'timeout';
  }

  /** Count Q-NNNNN rows currently shown in the draft-quotes modal. */
  async draftQuoteCountInModal() {
    return this.draftQuoteRows().count();
  }

  /**
   * Click the Nth contract row (0-based). Handles the post-click branching:
   *   - editor mounts directly → Save button appears
   *   - "Existing Draft Quotes" modal appears → pick first draft, or
   *     fall back to "Create new Amendment Quote"
   * Returns whether the editor mounted within `timeout`.
   *
   * Contract scoping: when the dashboard supplied a specific contract
   * (QTC_CONTRACT_ID, or QTC_CONTRACT_NUMBER as a fallback), the requested
   * `index` is overridden so the run targets that exact contract instead of
   * whatever sits at position `index`. This lets navigation-style specs (which
   * default to index 0) honor the operator's contract selection without any
   * per-spec changes. Falls back to `index` when no scope is set or the scoped
   * contract isn't visible.
   *
   * @param {number} index   0-based row index
   * @param {number} [timeout=60000]
   */
  async openContractByIndex(index, timeout = 60_000) {
    const targetIndex = await this._resolveScopedIndex(index);
    const row = this.contractRows().nth(targetIndex);
    await row.waitFor({ state: 'visible', timeout: 10_000 });
    await row.click();
    return this._afterContractClick(timeout);
  }

  /**
   * Resolve which contract-row index to open given an optional dashboard scope.
   * Matches QTC_CONTRACT_ID against data-id first (unambiguous), then
   * QTC_CONTRACT_NUMBER against data-number, else returns the fallback index.
   * @param {number} fallbackIndex
   * @returns {Promise<number>}
   */
  async _resolveScopedIndex(fallbackIndex) {
    const targetId     = process.env.QTC_CONTRACT_ID     || '';
    const targetNumber = process.env.QTC_CONTRACT_NUMBER || '';
    if (!targetId && !targetNumber) return fallbackIndex;

    const visible = await this.getContractList();
    if (visible.length === 0) return fallbackIndex;

    if (targetId) {
      const match = visible.find(c => c.id === targetId);
      if (match) {
        console.log(`[agenticQtcPage] Scoped to contract by ID: ${match.number} (${match.id}) → row ${match.index}`);
        return match.index;
      }
      console.warn(`[agenticQtcPage] QTC_CONTRACT_ID="${targetId}" not visible — trying number match`);
    }
    if (targetNumber) {
      const numMatch = visible.find(c => c.number === targetNumber);
      if (numMatch) {
        console.log(`[agenticQtcPage] Scoped to contract by number: ${numMatch.number} (${numMatch.id}) → row ${numMatch.index}`);
        return numMatch.index;
      }
      console.warn(`[agenticQtcPage] QTC_CONTRACT_NUMBER="${targetNumber}" not visible — falling back to row ${fallbackIndex}`);
    }
    return fallbackIndex;
  }

  /**
   * Click the contract row whose contract number cell contains `number`.
   * Same post-click handling as openContractByIndex.
   * @param {string|number} number
   * @param {number} [timeout=60000]
   */
  async openContractByNumber(number, timeout = 60_000) {
    const row = this.contractRows().filter({ hasText: String(number) }).first();
    await row.waitFor({ state: 'visible', timeout: 10_000 });
    await row.click();
    return this._afterContractClick(timeout);
  }

  /** @param {number} timeout */
  async _afterContractClick(timeout) {
    const saveBtn = this.saveButton();
    const modal   = this.draftQuotesModal();

    const winner = await u.waitForAny([saveBtn, modal], timeout);
    if (winner === -1) return false;
    if (winner === 0)  return true;

    const opened = await this.openDraftQuoteFromModal();
    if (!opened) return false;
    return saveBtn.waitFor({ state: 'visible', timeout })
      .then(() => true).catch(() => false);
  }

  // ─── Existing Draft Quotes modal ───────────────────────────────────────────

  draftQuotesModal() {
    return this.page.locator('.quotes-modal');
  }

  /** The semi-transparent backdrop behind the draft-quotes modal. */
  draftModalBackdrop() {
    return this.page.locator('.quotes-modal-backdrop');
  }

  /** The X / close button in the draft-quotes modal header. */
  draftModalClose() {
    return this.page.locator('button.quotes-modal-close');
  }

  /** The draft-quotes modal title ("Existing Draft Quotes") — a safe in-panel
   *  click target for the "clicking inside doesn't dismiss" assertion. */
  draftModalTitle() {
    return this.page.locator('.quotes-modal-title');
  }

  draftQuoteRows() {
    return this.page.locator('tr.quote-row');
  }

  /**
   * Click the draft quote row in the modal whose visible text matches `name`.
   * Falls back to the first row if no match is found.
   * @param {string} name  e.g. "Q-00123"
   */
  async clickDraftQuoteByName(name) {
    const target = this.draftQuoteRows().filter({ hasText: name }).first();
    const matched = await target.count().catch(() => 0);
    if (matched > 0) {
      await target.click();
    } else {
      console.warn(`[agenticQtcPage] clickDraftQuoteByName: "${name}" not found in modal — clicking first row`);
      await this.draftQuoteRows().first().click();
    }
  }

  createNewAmendmentButton() {
    return this.page.locator('button.quotes-modal-create-btn');
  }

  /**
   * Click the first existing draft quote in the modal. Falls back to
   * "Create new Amendment Quote" if no drafts are listed. Returns true
   * if anything was clicked.
   */
  async openDraftQuoteFromModal() {
    const rows = this.draftQuoteRows();
    if ((await rows.count()) > 0) {
      await rows.first().click();
      return true;
    }
    const createBtn = this.createNewAmendmentButton();
    if (await u.isVisibleSafe(createBtn, 5_000)) {
      await createBtn.click();
      return true;
    }
    return false;
  }

  // ─── Quote editor ──────────────────────────────────────────────────────────

  saveButton() {
    return this.page.getByRole('button', { name: 'Save' });
  }

  /**
   * Wait for the Save button to be both visible AND enabled. The LWC binds
   * the button's `disabled` attribute to `isSaveDisabled`, which flips
   * after the user makes a change.
   * @param {number} [timeout=30000]
   */
  async waitForSaveEnabled(timeout = 30_000) {
    const btn = this.saveButton();
    await btn.waitFor({ state: 'visible', timeout });
    // Use Playwright's locator-based check — it pierces shadow DOM, while
    // a plain document.querySelectorAll('button') inside page.waitForFunction
    // does not, so it can't see Save when it sits inside a shadow root.
    await expect(btn).toBeEnabled({ timeout });
  }

  /**
   * Click Save once it's enabled, then wait for the LWC's success toast
   * ("Quote saved & prices calculated") or error toast ("Error saving").
   *
   * Throws if the error toast appears so the underlying CPQ failure is
   * surfaced in the test output instead of silently failing the
   * subsequent value assertion.
   *
   * @param {number} [timeout=90000]
   * @param {number} [settleMs=2000]  Post-toast wait so the LWC's re-render
   *                                  finishes before the caller reads UI/DB.
   *                                  Contact-only updates don't recompute
   *                                  lines, so callers can pass a much
   *                                  smaller value (e.g. 300ms).
   */
  async save(timeout = 90_000, settleMs = 2_000, _retries = 1) {
    await this.waitForSaveEnabled();
    await this.saveButton().click();

    const successToast = this.page.getByText(/Quote saved.*prices calculated/i).first();
    const errorToast   = this.page.getByText(/Error saving/i).first();

    const winner = await u.waitForAny([successToast, errorToast], timeout);

    if (winner === -1) {
      throw new Error(`Save did not produce a toast within ${timeout}ms`);
    }
    if (winner === 1) {
      const errText = await errorToast.innerText().catch(() => '(unable to read toast text)');
      // Transient row-lock: CPQ's post-insert async flow hasn't released the lock yet.
      // Wait for the org to settle, then retry once before failing.
      if (_retries > 0 && /Please try again|UNABLE_TO_LOCK_ROW/i.test(errText)) {
        await this.page.waitForTimeout(8_000);
        return this.save(timeout, settleMs, _retries - 1);
      }
      throw new Error(`Quote save failed: ${errText.trim()}`);
    }

    // Success — let the UI settle (toast auto-dismisses, lines re-render)
    if (settleMs > 0) await this.page.waitForTimeout(settleMs);
  }

  /**
   * The native <input type="date"> rendered inside lightning-input.date-input.
   * Native date inputs accept and return values in ISO format (YYYY-MM-DD)
   * regardless of the user-facing display format.
   */
  startDateInput() {
    return this.page.locator('lightning-input.date-input input').first();
  }

  /** ISO (YYYY-MM-DD) value of the Start Date input. '' if empty. */
  async getStartDate() {
    return this.startDateInput().inputValue().catch(() => '');
  }

  /**
   * Set the Quote Start Date by typing into the input.
   *
   * Critical detail: clicking the input auto-opens the SLDS calendar
   * popup, which intercepts keystrokes (arrow keys for navigation, etc.)
   * — so we use focus() + selectText() instead of click(). These don't
   * trip the calendar's open-on-click handler.
   *
   * Format: abbreviated "Mmm D, YYYY" matches what lightning-input type=date
   * displays in en-US locale (the hint under the field reads
   * "Format: Dec 31, 2024").
   *
   * @param {Date|string} dateOrISO   ISO "YYYY-MM-DD" or Date
   * @returns {Promise<string>}       ISO that was set
   */
  async setStartDate(dateOrISO) {
    const iso     = dateOrISO instanceof Date ? u.formatDateISO(dateOrISO) : dateOrISO;
    const date    = dateOrISO instanceof Date ? dateOrISO : new Date(`${iso}T00:00:00`);
    const display = u.formatDateShort(date);   // e.g. "Jun 12, 2026"

    const innerInput = this.page.locator('lightning-input.date-input input').first();
    await innerInput.waitFor({ state: 'visible', timeout: 10_000 });

    // Diagnostics: what's in the input before we touch it?
    const beforeType  = await innerInput.getAttribute('type');
    const beforeValue = await innerInput.inputValue().catch(() => '');
    console.log(`[setStartDate] BEFORE — type="${beforeType}", value="${beforeValue}", typing "${display}"`);

    // Focus the input WITHOUT clicking (avoids auto-opening the calendar)
    await innerInput.focus();
    await innerInput.selectText();           // select existing text in input
    await this.page.keyboard.press('Delete'); // clear
    await this.page.keyboard.type(display, { delay: 30 });

    // Typing populated the input but Tab alone doesn't always bubble a
    // composed `change` event past Lightning Web Security's shadow root.
    // Explicitly fire change + blur events with composed:true so
    // lightning-input's internal listener picks up the new value and
    // re-emits its own change event to handleStartDateChange.
    await innerInput.evaluate((el) => {
      el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
      el.dispatchEvent(new Event('blur',   { bubbles: true, composed: true }));
      /** @type {HTMLInputElement} */ (el).blur();
    });

    // Settle briefly so the LWC's render cycle finishes
    await this.page.waitForTimeout(500);

    const afterValue = await innerInput.inputValue().catch(() => '');
    console.log(`[setStartDate] AFTER  — value="${afterValue}"`);

    return iso;
  }

  /**
   * Alternative date-set path via the SLDS calendar popup. Kept as a
   * fallback; the typing path in setStartDate is the primary approach
   * because it reliably fires the LWC's onchange handler.
   *
   * @param {{ monthsAhead?: number, day?: number }} [opts]
   */
  async setStartDateByDayClick(opts = {}) {
    const monthsAhead = opts.monthsAhead ?? 1;
    const day         = opts.day         ?? 15;
    const before      = await this.getStartDate();

    await this.startDateInput().click();

    const picker = this.page.locator('.slds-datepicker, lightning-datepicker').first();
    await picker.waitFor({ state: 'visible', timeout: 10_000 });

    const nextBtn = this.page.locator(
      'button[name="next"], button[title*="Next" i], button[aria-label*="Next" i]'
    ).first();
    for (let i = 0; i < monthsAhead; i++) {
      if (!(await u.isVisibleSafe(nextBtn, 2_000))) break;
      await nextBtn.click();
      await this.page.waitForTimeout(200);
    }

    const dayBtn = this.page.getByRole('button', { name: String(day), exact: true }).first();
    await dayBtn.waitFor({ state: 'visible', timeout: 5_000 });
    await dayBtn.click();

    const after = await this.getStartDate();
    return after && after !== before ? after : null;
  }


  /**
   * Extract the Quote name from the editor header
   * (`<a class="header-title-link">Q-NNNNN</a>`).
   *
   * The Save button can become visible BEFORE the header's quote-name link
   * is populated (the LWC renders that link asynchronously after the quote
   * details load). The header may also briefly contain ONLY the account
   * link, so we poll until a header-title-link with a Q-NNNNN value appears.
   *
   * Two robustness choices:
   *   - state: 'attached' (not 'visible') — visibility checks fail under the
   *     dashboard's 0.6 page zoom for small inline elements.
   *   - hasText: /Q-\d+/ (no ^$ anchors) — innerText may carry stray whitespace.
   *
   * @param {number} [timeout=30000]
   * @returns {Promise<string|null>}
   */
  async getQuoteName(timeout = 30_000) {
    const deadline = Date.now() + timeout;

    while (Date.now() < deadline) {
      const links = this.page.locator('a.header-title-link');
      const count = await links.count().catch(() => 0);
      for (let i = 0; i < count; i++) {
        const text = (await links.nth(i).innerText().catch(() => '')).trim();
        const m = text.match(/Q-\d+/);
        if (m) return m[0];
      }
      await this.page.waitForTimeout(250);
    }
    return null;
  }

  /**
   * Read the editor header title links (`a.header-title-link`) as
   * [{ text, href }]. The account link comes first, the quote (Q-NNNNN) link
   * second; callers match on the href path rather than position.
   */
  async readHeaderLinks() {
    return this.page.locator('a.header-title-link').evaluateAll((els) =>
      els.map((el) => ({
        text: (el.textContent || '').trim(),
        href: el.getAttribute('href') || '',
      }))
    );
  }

  /**
   * Read the metric tiles in the editor's metrics bar as [{ label, value }].
   * Each `.metric-item` carries a `.metric-label` and a trailing value span
   * (ACV / TCV / YoY Uplift / Deal Quality Score).
   */
  async readMetricTiles() {
    return this.page.locator('.metric-item').evaluateAll((els) =>
      els.map((el) => ({
        label: (el.querySelector('.metric-label')?.textContent || '').trim(),
        value: (el.lastElementChild?.textContent || '').trim(),
      }))
    );
  }

  /** True when the Save button is present AND disabled (the dirty-state gate). */
  async isSaveDisabled() {
    const btn = this.saveButton();
    await btn.waitFor({ state: 'visible', timeout: 30_000 });
    return btn.isDisabled();
  }

  /**
   * Navigate back from the quote editor to the contracts list using the
   * back button in the editor header. It's an icon-only
   * `lightning-button-icon` (utility:back) with no visible text, so we anchor
   * on its position as the first button-icon in the editor header rather than
   * an accessible name.
   */
  async backToContracts() {
    const backBtn = this.page.locator('.editor-header lightning-button-icon').first();
    await backBtn.waitFor({ state: 'visible', timeout: 10_000 });
    await backBtn.click();
    await this.activeContractsHeading().waitFor({ state: 'visible', timeout: 20_000 });
  }

  /**
   * Wait for at least one quote-line spinbutton (quantity input) to render.
   * Returns the count, or 0 if none appeared.
   * @param {number} [timeout=90000]
   */
  async waitForLines(timeout = 90_000) {
    const spinbuttons = this.page.getByRole('spinbutton');
    const ok = await spinbuttons.first().waitFor({ state: 'visible', timeout })
      .then(() => true).catch(() => false);
    return ok ? spinbuttons.count() : 0;
  }

  /**
   * Read the rendered "Cost" cell (SBQQ__NetTotal__c, formatted by the term
   * group's _fmtCurrency) for the MDQ quote-line row that owns a given quantity
   * spinbutton. In agenticQtcMdqTermGroup each editable year cell is four
   * columns — Quantity | Eff. Qty | Monthly Sale Price | Cost — so the Cost
   * cell is the 3rd <td> sibling after the quantity input's <td>.
   *
   * Returns the raw display string (e.g. 'USD 1,234.00' / 'USD 1.20M') or ''
   * when it can't be read (e.g. a non-term-group layout). The value is shown as
   * informational before/after context on the dashboard, never asserted.
   *
   * @param {Locator} spinbutton  a quantity input from getByRole('spinbutton')
   * @returns {Promise<string>}
   */
  async readLineCost(spinbutton) {
    const costCell = spinbutton.locator('xpath=ancestor::td[1]/following-sibling::td[3]');
    return (await costCell.innerText({ timeout: 1_000 }).catch(() => '')).trim();
  }

  // ─── App shell: theme + breadcrumb ───────────────────────────────────────────

  /** The dark/light toggle button in the app header (present on every page). */
  themeToggleButton() {
    return this.page.locator('button.dark-mode-toggle');
  }

  /**
   * Current app theme, read from the root container class
   * (agenticQtcApp.appContainerClass → 'app-container dark-theme' | 'light-theme').
   * @returns {Promise<'dark'|'light'|'unknown'>}
   */
  async currentTheme() {
    const cls = (await this.page.locator('.app-container').first().getAttribute('class').catch(() => '')) || '';
    if (cls.includes('dark-theme'))  return 'dark';
    if (cls.includes('light-theme')) return 'light';
    return 'unknown';
  }

  /** Breadcrumb items in the app header (account = first, contract = second). */
  breadcrumbItems() {
    return this.page.locator('.breadcrumb-item.clickable');
  }

  // ─── Header metric tiles ─────────────────────────────────────────────────────

  /**
   * Read the four header metric tiles (ACV, TCV, YoY Uplift, Deal Quality Score)
   * from the quote editor's metrics bar and return their raw display strings
   * keyed by the visible label, e.g.
   *   { 'ACV': '$1,234.00', 'TCV': '$10,000.00',
   *     'YoY Uplift': '+5.00%', 'Deal Quality Score': '95' }
   *
   * Anchored to `.metrics-bar .metric-item` (label span + value span) so it
   * survives tile reordering and doesn't depend on column position. Single
   * page.locator().evaluateAll() call — one CDP round-trip for all tiles. The
   * locator pierces the editor's shadow root to resolve the matching elements.
   *
   * @param {number} [timeout=15000]
   * @returns {Promise<Record<string,string>>}
   */
  async readHeaderMetrics(timeout = 15_000) {
    await this.page.locator('.metrics-bar').waitFor({ state: 'visible', timeout });
    const items = await this.page.locator('.metrics-bar .metric-item').evaluateAll((els) =>
      els.map((el) => ({
        label: (el.querySelector('.metric-label')?.textContent || '').trim(),
        value: (el.querySelector('.metric-value')?.textContent || '').trim(),
      }))
    );
    /** @type {Record<string,string>} */
    const map = {};
    for (const it of items) if (it.label) map[it.label] = it.value;
    return map;
  }

  // ─── DB verification ───────────────────────────────────────────────────────

  /**
   * Query SBQQ__Quote__c by Name and return the single header record (or null).
   * @param {string} quoteName
   */
  async fetchQuoteFromDb(quoteName) {
    const soql = `SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c, SBQQ__EndDate__c,
                         SBQQ__SubscriptionTerm__c, SBQQ__NetAmount__c
                  FROM SBQQ__Quote__c
                  WHERE Name = '${quoteName}'
                  LIMIT 1`;
    const result = await u.sfQuery(this.page, this.instanceUrl, this.accessToken, soql);
    return result.records[0] || null;
  }

  // ─── Contacts (Invoicing / Software Delivery) ──────────────────────────────

  /**
   * Card section for one of the two contact slots on the editor header.
   * Selector is anchored to the card that contains the matching contact
   * search button (which carries data-type="invoicing" | "delivery").
   * @param {'invoicing'|'delivery'} type
   */
  contactCard(type) {
    return this.page.locator('div.contact-card-section')
      .filter({ has: this.page.locator(`button.contact-search-btn[data-type="${type}"]`) })
      .first();
  }

  /**
   * Read current contact display from the editor header:
   *   { name, email, title } — any of which may be '' if the LWC hasn't
   *   populated it (e.g. no contact selected, or no Title on the Contact).
   * Default waitFor timeout is short — the cards are already in the DOM by
   * the time the editor's Save button is visible, so the caller's flow
   * should never genuinely block here.
   *
   * All three field reads happen inside a single page.evaluate call so the
   * whole method is one CDP round-trip instead of three.
   * @param {'invoicing'|'delivery'} type
   * @param {number} [timeout=5000]
   */
  async readContactDisplay(type, timeout = 5_000) {
    const card = this.contactCard(type);
    await card.waitFor({ state: 'visible', timeout });

    return card.evaluate((el) => {
      /** @param {string} sel */
      const text = (sel) => {
        const n = el.querySelector(sel);
        return n ? (n.textContent || '').trim() : '';
      };
      return {
        name:  text('span.contact-name'),
        email: text('span.contact-detail'),
        title: text('span.contact-title'),
      };
    });
  }

  /**
   * Open the "Select Contact" modal for the given slot by clicking its
   * search-icon button. The modal renders inside .contact-picker-backdrop.
   * @param {'invoicing'|'delivery'} type
   */
  async openContactPicker(type) {
    const btn = this.page.locator(`button.contact-search-btn[data-type="${type}"]`).first();
    await btn.waitFor({ state: 'visible', timeout: 15_000 });
    await btn.click();
    await this.page.locator('.contact-picker-modal').waitFor({ state: 'visible', timeout: 10_000 });
    // Wait for at least one contact row OR an empty-state to render so the
    // list has populated before the caller reads it.
    const anyItem  = this.page.locator('.contact-picker-item').first();
    const emptyMsg = this.page.locator('.contact-picker-empty').first();
    await u.waitForAny([anyItem, emptyMsg], 15_000);
  }

  /**
   * Read every contact currently shown in the open picker modal:
   *   [{ id, name, isSelected }]
   *
   * Single page.evaluate call so a 500-row picker doesn't cost 1500+ CDP
   * round-trips (id + name + class per row). The locator pierces shadow DOM
   * to resolve the matching elements, then evaluateAll runs the mapper in
   * browser context.
   */
  async readPickerContacts() {
    return this.page.locator('.contact-picker-item').evaluateAll((els) =>
      els.map((el) => ({
        id:         el.getAttribute('data-id'),
        name:       (el.querySelector('.contact-picker-name')?.textContent || '').trim(),
        isSelected: (el.className || '').includes('contact-picker-item--selected'),
      }))
    );
  }

  /**
   * Click a row in the open picker by Contact Id. The LWC closes the modal
   * automatically when the row is selected; we don't wait for the close
   * event because the caller either opens the next picker (which re-uses
   * the same modal slot) or finishes the test.
   * @param {string} contactId
   */
  async selectPickerContact(contactId) {
    const row = this.page.locator(`.contact-picker-item[data-id="${contactId}"]`).first();
    await row.waitFor({ state: 'visible', timeout: 10_000 });
    await row.click();
  }

  /**
   * Open the picker, choose a contact at random:
   *   - if `currentContactId` is null (no contact selected yet) → pick any row
   *   - otherwise → pick a random row whose id is NOT `currentContactId`
   *
   * Returns the chosen row, or null if the modal had no usable rows (or only
   * the currently-selected contact, in which case there is nothing to switch
   * to).
   *
   * @param {'invoicing'|'delivery'} type
   * @param {string|null} currentContactId
   */
  async pickDifferentContact(type, currentContactId) {
    await this.openContactPicker(type);
    const rows = await this.readPickerContacts();
    const candidates = rows.filter(r => r.id && r.id !== currentContactId);
    if (candidates.length === 0) {
      await this.page.locator('.contact-picker-close').first().click().catch(() => {});
      return null;
    }
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    await this.selectPickerContact(/** @type {string} */ (pick.id));
    return pick;
  }

  /**
   * Query SBQQ__Quote__c for the persisted Invoicing / Software Delivery
   * contact ids + their referenced contact name/email/title.
   * @param {string} quoteName
   */
  async fetchContactsFromDb(quoteName) {
    const soql = `SELECT Id, Name,
                         Invoicing_Contact__c,
                         Invoicing_Contact__r.Name, Invoicing_Contact__r.Email, Invoicing_Contact__r.Title,
                         Software_Delivery_Contact__c,
                         Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email, Software_Delivery_Contact__r.Title
                  FROM SBQQ__Quote__c
                  WHERE Name = '${quoteName}'
                  LIMIT 1`;
    const result = await u.sfQuery(this.page, this.instanceUrl, this.accessToken, soql);
    const row = result.records[0];
    if (!row) return null;
    return {
      quoteId: row.Id,
      invoicing: {
        id:    row.Invoicing_Contact__c ?? null,
        name:  row.Invoicing_Contact__r?.Name  ?? null,
        email: row.Invoicing_Contact__r?.Email ?? null,
        title: row.Invoicing_Contact__r?.Title ?? null,
      },
      delivery: {
        id:    row.Software_Delivery_Contact__c ?? null,
        name:  row.Software_Delivery_Contact__r?.Name  ?? null,
        email: row.Software_Delivery_Contact__r?.Email ?? null,
        title: row.Software_Delivery_Contact__r?.Title ?? null,
      },
    };
  }
}

module.exports = { AgenticQtcPage, APP_PATH };
