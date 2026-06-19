/**
 * @description Parent orchestrator for the Portfolio Analysis tool. Provides account
 *              search, loads subscription and invoice data across three phases
 *              (Salesforce subscriptions → NetSuite invoices → previous-contract
 *              exception), and delegates display to child components via tabs
 *              (Overview, Contracts, Contract Value).
 * @author      Vignesh Prabhudoss
 * @date        Mar-02-2026
 * @jira        BIZ-80262, BIZ-80292
 */
import { LightningElement, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import xlsxJsStyleLibrary from '@salesforce/resourceUrl/xlsxJsStyleLibrary';
import searchAccounts from '@salesforce/apex/PortfolioAnalysisController.searchAccounts';
import getAccountDetails from '@salesforce/apex/PortfolioAnalysisController.getAccountDetails';
import getSubscriptions from '@salesforce/apex/PortfolioAnalysisController.getSubscriptions';
import getInvoiceData from '@salesforce/apex/PortfolioAnalysisController.getInvoiceData';
import getPreviousContractSubscriptions from '@salesforce/apex/PortfolioAnalysisController.getPreviousContractSubscriptions';
import { exportPortfolioExcel } from './excelExport';

const TABS = [
    { key: 'overview', label: 'Overview', icon: '\u{1F4CA}' },
    { key: 'contracts', label: 'Contracts', icon: '\u{1F4CB}' },
    { key: 'revenue', label: 'Contract Value', icon: '\u{1F4B0}' }
];

export default class PortfolioAnalysis extends LightningElement {
    // ========== State ==========
    activeTab = 'overview';
    @track selectedAccount = null;
    @track subscriptions = [];
    @track accountDetails = null;
    isLoading = false;
    loadError = null;
    clientFacing = false;
    xlsxLibLoaded = false;
    isExportingExcel = false;

    // ========== Invoice State (Phase 2/3) ==========
    @track invoiceMap = {};
    isLoadingInvoices = false;
    invoiceError = null;

    // ========== Icon Constants ==========
    searchIcon = '\u{1F50D}';
    warningIcon = '\u{26A0}\u{FE0F}';

    // ========== Search State ==========
    searchQuery = '';
    @track searchResults = [];
    isSearching = false;
    isDropdownOpen = false;
    _debounceTimer;

    // ========== Lifecycle ==========
    connectedCallback() {
        loadScript(this, xlsxJsStyleLibrary)
            .then(() => {
                this.xlsxLibLoaded = true;
            })
            .catch(error => {
                console.error('Failed to load xlsx-js-style:', error);
            });
    }

    // ========== Getters ==========
    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.key === this.activeTab ? 'tab-btn tab-active' : 'tab-btn'
        }));
    }

    get hasAccount() {
        return this.selectedAccount != null;
    }

    get hasSubscriptions() {
        return this.subscriptions && this.subscriptions.length > 0;
    }

    get showTabs() {
        return this.hasAccount && !this.isLoading && !this.loadError;
    }

    get showEmptyState() {
        return !this.hasAccount && !this.isLoading;
    }

    get showLoadingState() {
        return this.isLoading;
    }

    get showErrorState() {
        return this.loadError && !this.isLoading;
    }

    get showOverview() {
        return this.activeTab === 'overview' && this.hasAccount && !this.isLoading && !this.loadError;
    }

    get showContracts() {
        return this.activeTab === 'contracts' && this.hasAccount && !this.isLoading && !this.loadError;
    }

    get showRevenue() {
        return this.activeTab === 'revenue' && this.hasAccount && !this.isLoading && !this.loadError;
    }

    get clientFacingLabel() {
        return this.clientFacing ? '\u{1F464} Client View' : '\u{1F512} Internal View';
    }

    get clientFacingClass() {
        return this.clientFacing ? 'toggle-btn toggle-active' : 'toggle-btn';
    }

    get subscriptionCountLabel() {
        const count = this.subscriptions ? this.subscriptions.length : 0;
        return `${count} subscription${count !== 1 ? 's' : ''}`;
    }

    get viewModeLabel() {
        return this.clientFacing ? 'Client' : 'Internal';
    }

    get viewModeBadgeClass() {
        return this.clientFacing ? 'badge badge-blue' : 'badge';
    }

    get currency() {
        if (!this.subscriptions || !this.subscriptions.length) return 'USD';
        const counts = {};
        this.subscriptions.forEach(s => {
            const c = s.CurrencyIsoCode || 'USD';
            counts[c] = (counts[c] || 0) + 1;
        });
        return Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0];
    }

    get loadingAccountName() {
        return this.selectedAccount ? this.selectedAccount.name : '';
    }

    get showSearchDropdown() {
        return this.isDropdownOpen && this.searchResults.length > 0;
    }

    get showNoResults() {
        return this.isDropdownOpen && this.searchResults.length === 0 && !this.isSearching && this.searchQuery.length >= 3;
    }

    get showClearButton() {
        return !this.isSearching && this.searchQuery;
    }

    get showExportButtons() {
        return this.hasAccount && this.hasSubscriptions && !this.isLoading && !this.loadError && this.xlsxLibLoaded;
    }

    // ========== Event Handlers — Tabs ==========
    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleToggleClientFacing() {
        this.clientFacing = !this.clientFacing;
    }

    handleExportExcel() {
        if (!this.xlsxLibLoaded || !window.XLSX) {
            console.error('XLSX library not loaded yet');
            return;
        }
        this.isExportingExcel = true;
        try {
            exportPortfolioExcel(
                window.XLSX,
                this.selectedAccount,
                this.subscriptions,
                this.clientFacing,
                this.currency,
                this.accountDetails,
                this.invoiceMap
            );
        } catch (error) {
            console.error('Excel export failed:', error);
        } finally {
            this.isExportingExcel = false;
        }
    }

    // ========== Event Handlers — Search ==========
    handleSearchInput(event) {
        const value = event.target.value;
        this.searchQuery = value;

        clearTimeout(this._debounceTimer);

        if (value.length < 3) {
            this.searchResults = [];
            this.isDropdownOpen = false;
            return;
        }

        this._debounceTimer = setTimeout(() => {
            this.performSearch(value);
        }, 300);
    }

    handleSearchFocus() {
        if (this.searchResults.length > 0) {
            this.isDropdownOpen = true;
        }
    }

    handleClearSearch() {
        this.searchQuery = '';
        this.searchResults = [];
        this.isDropdownOpen = false;
        this.selectedAccount = null;
        this.subscriptions = [];
        this.accountDetails = null;
        this.loadError = null;
        this.activeTab = 'overview';
        this.invoiceMap = {};
        this.isLoadingInvoices = false;
        this.invoiceError = null;
    }

    handleSelectAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        const accountName = event.currentTarget.dataset.name;
        this.searchQuery = accountName;
        this.isDropdownOpen = false;
        this.searchResults = [];
        this.loadAccountData(accountId, accountName);
    }

    handleSearchBlur() {
        // Delay to allow click on dropdown items
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.isDropdownOpen = false;
        }, 200);
    }

    // ========== Data Loading ==========

    /**
     * @description Executes a debounced typeahead account search via Apex.
     * @param {string} text - Search string (minimum 3 chars).
     */
    async performSearch(text) {
        this.isSearching = true;
        try {
            const results = await searchAccounts({ searchText: text });
            this.searchResults = results;
            this.isDropdownOpen = true;
        } catch (error) {
            this.searchResults = [];
            console.error('Search failed:', error);
        } finally {
            this.isSearching = false;
        }
    }

    /**
     * @description Phase 1 – loads account details and active subscriptions from Salesforce
     *              in parallel, then triggers Phase 2 (invoice loading) if subscriptions exist.
     * @param {string} accountId   - Salesforce Account Id.
     * @param {string} accountName - Account Name used for subscription query.
     */
    async loadAccountData(accountId, accountName) {
        this.selectedAccount = { id: accountId, name: accountName };
        this.isLoading = true;
        this.loadError = null;
        this.activeTab = 'overview';
        this.accountDetails = null;
        this.subscriptions = [];
        this.invoiceMap = {};
        this.invoiceError = null;

        try {
            // Phase 1: Load subscriptions + account details from Salesforce
            const [details, subs] = await Promise.all([
                getAccountDetails({ accountId: accountId }),
                getSubscriptions({ accountName: accountName })
            ]);
            this.accountDetails = details;
            this.subscriptions = subs || [];
        } catch (error) {
            this.loadError = error.body ? error.body.message : error.message;
            this.subscriptions = [];
            this.accountDetails = null;
        } finally {
            this.isLoading = false;
        }

        // Phase 2: Load invoice data from NetSuite (non-blocking)
        if (this.subscriptions.length > 0) {
            this.loadInvoiceData(accountName);
        }
    }

    // ========== Phase 2: Invoice Data Loading ==========

    /**
     * @description Phase 2 – fetches invoice data from NetSuite for all unique OSA numbers
     *              in the current subscription set. Non-blocking (runs after Phase 1 completes).
     *              On success, triggers Phase 3 (previous-contract exception check).
     * @param {string} accountName - Account Name for previous-contract lookup.
     */
    async loadInvoiceData(accountName) {
        this.isLoadingInvoices = true;
        this.invoiceError = null;

        try {
            // Extract unique OSA numbers from current subscriptions
            const osaNumbers = [...new Set(
                this.subscriptions
                    .map(s => s.SBQQ__Contract__r?.OSA_Number__c)
                    .filter(Boolean)
            )];

            if (osaNumbers.length === 0) {
                this.isLoadingInvoices = false;
                return;
            }

            const result = await getInvoiceData({ osaNumbers });

            if (result.success) {
                this.buildInvoiceMaps(result.invoices);

                // Phase 3: Check for previous contract exception
                await this.checkPreviousContractException(accountName);
            } else {
                this.invoiceError = result.errorMessage;
                console.error('Invoice data error:', result.errorMessage);
            }
        } catch (error) {
            this.invoiceError = error.body?.message || error.message;
            console.error('Invoice data fetch failed:', error);
        } finally {
            this.isLoadingInvoices = false;
        }
    }

    /**
     * @description Indexes invoices by composite key (osa|startDate|endDate) for O(1)
     *              lookup when matching invoices to subscription segments.
     * @param {Array} invoices - Invoice records from NetSuite.
     */
    buildInvoiceMaps(invoices) {
        const map = {};
        invoices.forEach(inv => {
            const key = `${inv.osaNumber}|${inv.termStartDate}|${inv.termEndDate}`;
            if (!map[key]) {
                map[key] = [];
            }
            map[key].push(inv);
        });
        this.invoiceMap = map;
    }

    // ========== Phase 3: Previous Contract Exception ==========

    /**
     * @description Phase 3 – for each OSA whose current-period invoice is unpaid,
     *              traverses backward to find the most recent paid period and fetches
     *              those subscription lines so the UI can display a "last paid" snapshot.
     * @param {string} accountName - Account Name for the Apex query.
     */
    async checkPreviousContractException(accountName) {
        // 1. Build set of current subscription composite keys (osa|startDate|endDate)
        const currentKeys = new Set();
        this.subscriptions.forEach(s => {
            const osa = s.SBQQ__Contract__r?.OSA_Number__c;
            const start = s.SBQQ__SegmentStartDate__c;
            const end = s.SBQQ__SegmentEndDate__c;
            if (osa && start && end) {
                currentKeys.add(`${osa}|${start}|${end}`);
            }
        });

        // 2. Group all invoices by OSA
        const invoicesByOsa = {};
        Object.values(this.invoiceMap).flat().forEach(inv => {
            if (!invoicesByOsa[inv.osaNumber]) {
                invoicesByOsa[inv.osaNumber] = [];
            }
            invoicesByOsa[inv.osaNumber].push(inv);
        });

        // 3. For each OSA, check if the current period's invoice is unpaid
        //    If so, traverse backward to find the first paid period
        const osasThatNeedPrevious = new Set();

        for (const osa of Object.keys(invoicesByOsa)) {
            const osaInvoices = invoicesByOsa[osa];

            // Find the current period's invoice (matches a current subscription key)
            const currentInvoice = osaInvoices.find(inv => {
                const key = `${inv.osaNumber}|${inv.termStartDate}|${inv.termEndDate}`;
                return currentKeys.has(key);
            });

            // If no current invoice or current invoice is paid, skip this OSA
            if (!currentInvoice || this.isInvoicePaid(currentInvoice)) {
                continue;
            }

            // Current period is unpaid — find the most recent PAID prior period
            const priorInvoices = osaInvoices
                .filter(inv => {
                    const key = `${inv.osaNumber}|${inv.termStartDate}|${inv.termEndDate}`;
                    return !currentKeys.has(key);
                })
                .sort((a, b) => (b.termEndDate || '').localeCompare(a.termEndDate || ''));

            for (const priorInv of priorInvoices) {
                if (this.isInvoicePaid(priorInv)) {
                    // Found a paid prior period — need to fetch its subscription lines
                    osasThatNeedPrevious.add(osa);
                    break;
                }
            }
        }

        if (osasThatNeedPrevious.size === 0) {
            return;
        }

        // 4. Fetch subscription lines from previous contracts
        try {
            const excludeIds = this.subscriptions.map(s => s.Id);
            const prevSubs = await getPreviousContractSubscriptions({
                accountName,
                osaNumbers: [...osasThatNeedPrevious],
                excludeSubscriptionIds: excludeIds
            });

            if (prevSubs && prevSubs.length > 0) {
                // 5. Filter to only the subscription lines whose dates match a paid prior invoice
                const filteredPrevSubs = prevSubs.filter(s => {
                    const osa = s.SBQQ__Contract__r?.OSA_Number__c;
                    const start = s.SBQQ__SegmentStartDate__c;
                    const end = s.SBQQ__SegmentEndDate__c;
                    if (!osa || !start || !end) return false;

                    const key = `${osa}|${start}|${end}`;
                    const matchedInvoices = this.invoiceMap[key] || [];
                    return matchedInvoices.some(inv => this.isInvoicePaid(inv));
                });

                // 6. Mark and append
                filteredPrevSubs.forEach(s => {
                    s._isPreviousContract = true;
                });
                this.subscriptions = [...this.subscriptions, ...filteredPrevSubs];
            }
        } catch (error) {
            console.error('Previous contract fetch failed:', error);
        }
    }

    /**
     * @description Checks whether an invoice's payment status indicates full payment.
     * @param {Object} invoice - Invoice record with paymentStatus field.
     * @returns {boolean} True if the invoice is paid in full.
     */
    isInvoicePaid(invoice) {
        if (!invoice || !invoice.paymentStatus) return false;
        const status = invoice.paymentStatus.toLowerCase();
        return status === 'paid in full' || status === 'paidinfull';
    }
}