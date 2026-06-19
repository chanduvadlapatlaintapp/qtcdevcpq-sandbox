import { LightningElement, api, track } from 'lwc';
import getActiveContracts from '@salesforce/apex/AgenticQTC_AmendContractController.getActiveContracts';
import getDraftQuotesForContract from '@salesforce/apex/AgenticQTC_AmendContractController.getDraftQuotesForContract';

/**
 * Contract selector component that displays active contracts for a given account.
 * Clicking a contract first checks for existing draft amendment quotes — if any are
 * found, a modal lets the user reuse one (or fall through to a fresh amendment).
 * Dispatches a contractselected event with an optional existingQuoteId payload, and a
 * back event for navigation.
 */
export default class AgenticQtcOsaSelector extends LightningElement {
    /** @api @type {string} Salesforce Account ID to load contracts for. */
    @api accountId;

    /** @api @type {string} Display name of the selected account. */
    @api accountName;

    /** @type {Array<Object>} List of active contract records with formatted dates. */
    @track contracts = [];

    /** @type {boolean} Whether contracts are currently being loaded. */
    @track isLoading = true;

    // ─── Draft quote picker modal ───
    @track showQuotesModal = false;
    @track draftQuotes = [];
    @track isLoadingQuotes = false;
    _pendingContractId = null;
    _pendingContractNumber = null;
    _pendingSubscriptionTcv = null;
    _pendingCurrencyIsoCode = null;
    _pendingOsaNumber = null;

    /**
     * @description Whether contracts exist and loading is complete.
     * @returns {boolean}
     */
    get hasContracts() { return !this.isLoading && this.contracts.length > 0; }

    /**
     * @description Whether loading is complete with zero contracts found.
     * @returns {boolean}
     */
    get noContracts() { return !this.isLoading && this.contracts.length === 0; }

    /** @returns {boolean} */
    get showContractStats() {
        return !this.isLoading && this.contracts && this.contracts.length > 0;
    }

    /** @returns {string} */
    get contractCountLabel() {
        const n = this.contracts ? this.contracts.length : 0;
        if (n === 0) {
            return '';
        }
        return n === 1 ? '1 active contract' : `${n} active contracts`;
    }

    /**
     * @description Lifecycle hook that loads contracts when the component is inserted.
     * @returns {Promise<void>}
     */
    async connectedCallback() {
        await this.loadContracts();
    }

    /**
     * @description Fetches active contracts for the current account from Apex and formats dates.
     * @returns {Promise<void>}
     */
    async loadContracts() {
        this.isLoading = true;
        try {
            const results = await getActiveContracts({ accountId: this.accountId });
            this.contracts = (results || []).map(c => {
                const allNames = c.productNames || [];
                const hasMore = allNames.length > 3;
                return {
                    ...c,
                    startDateFormatted: this.formatDate(c.startDate),
                    endDateFormatted: this.formatDate(c.endDate),
                    customerSignedFormatted: this.formatDate(c.customerSignedDate),
                    companySignedFormatted: this.formatDate(c.companySignedDate),
                    currentYearAcvFormatted: this.formatCurrency(c.currentYearAcv, c.currencyIsoCode),
                    productDisplay: allNames.length > 0 ? allNames.slice(0, 3).join(', ') : (c.productSummary || '—'),
                    allProductsDisplay: allNames.length > 0 ? allNames.join(', ') : (c.productSummary || '—'),
                    hasMoreProducts: hasMore,
                    moreCount: hasMore ? allNames.length - 3 : 0,
                    isProductExpanded: false,
                    subscriptionCount: c.subscriptionCount != null ? c.subscriptionCount : 0
                };
            });
        } catch (error) {
            console.error('Error loading contracts:', error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * @description Formats an ISO date string into a human-readable locale string (e.g. "Apr 5, 2026").
     * @param {string|null|undefined} dateStr - ISO date string to format.
     * @returns {string} Formatted date string, or an em-dash if the input is falsy.
     */
    formatDate(dateStr) {
        if (!dateStr) return '—';
        const d = new Date(dateStr + 'T00:00:00');
        return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    /**
     * @description Formats a numeric ACV value for grid display, prefixed with the
     *              row's CurrencyIsoCode (e.g. "USD 1,234.56"). Above 1M switches to
     *              "CODE X.XXM" so the column stays narrow. Falls back to USD when
     *              the contract's currency code is missing.
     * @param {number|null|undefined} val
     * @param {string|null|undefined} currencyIsoCode - ISO 4217 code from Contract.CurrencyIsoCode.
     * @returns {string} Em-dash if value is missing.
     */
    formatCurrency(val, currencyIsoCode) {
        if (val == null) return '—';
        const n = Number(val);
        if (!Number.isFinite(n)) return '—';
        const code = currencyIsoCode || 'USD';
        if (Math.abs(n) >= 1000000) {
            return code + ' ' + (n / 1000000).toFixed(2) + 'M';
        }
        return code + ' ' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    /**
     * @description Handles a click on a contract row. Queries existing draft amendment
     *              quotes for the contract and branches by count:
     *                0 drafts → dispatch contractselected with no existingQuoteId, falling
     *                           through to the standard new-amendment flow.
     *                1 draft  → dispatch contractselected with that draft's Id directly —
     *                           no picker modal, the editor opens the draft straight away.
     *                >1 drafts → open the picker modal so the user can choose which draft
     *                            to reuse.
     * @param {Event} event - Click event from the contract row with data-id and data-number attributes.
     * @returns {Promise<void>}
     */
    async handleContractClick(event) {
        const contractId = event?.currentTarget?.dataset?.id;
        const contractNumber = event?.currentTarget?.dataset?.number;
        if (!contractId) return;

        this._pendingContractId = contractId;
        this._pendingContractNumber = contractNumber;
        // Forwarded to the editor as the initial TCV display value on a fresh
        // amendment (pre-edit). Already aggregated by AgenticQTC_ContractService
        // during the contract-list query — no extra round-trip.
        const clicked = this.contracts.find(c => c.id === contractId);
        this._pendingSubscriptionTcv = clicked && clicked.subscriptionTcv != null
            ? Number(clicked.subscriptionTcv)
            : null;
        // Drives the currency code shown across the editor (header tiles + MDQ term
        // group cells). Sourced from Contract.CurrencyIsoCode on the same list query.
        this._pendingCurrencyIsoCode = clicked && clicked.currencyIsoCode
            ? clicked.currencyIsoCode
            : null;
        this._pendingOsaNumber = clicked?.osaNumber || null;
        this.isLoadingQuotes = true;
        try {
            const drafts = await getDraftQuotesForContract({ contractId });
            const rows = Array.isArray(drafts) ? drafts : [];
            if (rows.length === 0) {
                this._dispatchContractSelected(null);
                return;
            }
            if (rows.length === 1) {
                this._dispatchContractSelected(rows[0].id);
                return;
            }
            this.draftQuotes = rows.map(q => ({
                id: q.id,
                name: q.name || '—',
                startDateFormatted: this.formatDate(q.startDate),
                endDateFormatted: this.formatDate(q.endDate)
            }));
            this.showQuotesModal = true;
        } catch (error) {
            console.error('Error loading draft quotes — falling through to new amendment:', error);
            this._dispatchContractSelected(null);
        } finally {
            this.isLoadingQuotes = false;
        }
    }

    /**
     * @description Reuses the selected draft quote — dispatches contractselected with
     *              an existingQuoteId so the editor loads the draft instead of creating
     *              a new amendment.
     * @param {Event} event - Click event from the quote row (data-id carries the quote Id).
     * @returns {void}
     */
    handleQuoteRowClick(event) {
        const quoteId = event?.currentTarget?.dataset?.id;
        if (!quoteId) return;
        this._dispatchContractSelected(quoteId);
    }

    /**
     * @description Closes the draft-quote picker without selecting anything.
     * @returns {void}
     */
    handleCloseQuotesModal() {
        this.showQuotesModal = false;
        this.draftQuotes = [];
        this._pendingContractId = null;
        this._pendingContractNumber = null;
        this._pendingSubscriptionTcv = null;
        this._pendingCurrencyIsoCode = null;
        this._pendingOsaNumber = null;
    }

    /** Prevents clicks inside the modal panel from bubbling to the backdrop. */
    handleModalStop(event) {
        event.stopPropagation();
    }

    /**
     * @description Dispatches contractselected with the pending contract context and an
     *              optional existing quote Id, then resets the picker state.
     * @param {string|null} existingQuoteId - Existing draft quote Id, or null for a new amendment.
     * @returns {void}
     */
    _dispatchContractSelected(existingQuoteId) {
        const detail = {
            contractId: this._pendingContractId,
            contractNumber: this._pendingContractNumber,
            existingQuoteId: existingQuoteId || null,
            subscriptionTcv: this._pendingSubscriptionTcv,
            currencyIsoCode: this._pendingCurrencyIsoCode,
            osaNumber: this._pendingOsaNumber
        };
        this.showQuotesModal = false;
        this.draftQuotes = [];
        this._pendingContractId = null;
        this._pendingContractNumber = null;
        this._pendingSubscriptionTcv = null;
        this._pendingCurrencyIsoCode = null;
        this._pendingOsaNumber = null;
        this.dispatchEvent(new CustomEvent('contractselected', { detail }));
    }

    handleProductCellClick(event) {
        event.stopPropagation();
    }

    handleProductToggle(event) {
        event.stopPropagation();
        const contractId = event.currentTarget.dataset.id;
        this.contracts = this.contracts.map(c =>
            c.id === contractId ? { ...c, isProductExpanded: !c.isProductExpanded } : c
        );
    }

    /**
     * @description Dispatches a back event to navigate to the previous page.
     * @returns {void}
     */
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}