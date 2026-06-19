import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class AgenticQtcApp extends LightningElement {
    @track currentPage = 'accountSearch';
    @track selectedAccountId;
    @track selectedAccountName;
    @track selectedContractId;
    @track selectedContractNumber;
    @track currentQuoteId;
    /** When set, the quote editor reads this existing draft via pure SOQL and renders
     *  it instead of starting the amendment creation flow. */
    @track selectedExistingQuoteId;
    /** Σ NetPrice × Quantity of the contract's latest-in-chain subscriptions — passed
     *  from the OSA selector so the editor can render it as the initial TCV on a
     *  fresh amendment (before any quantity edits). Null when navigating from chat. */
    @track selectedSubscriptionTcv;
    /** Contract.CurrencyIsoCode forwarded from the OSA selector — drives the currency
     *  display in every monetary cell across the editor and its MDQ term group child.
     *  Null when navigating from chat (editor will fall back to USD). */
    @track selectedCurrencyIsoCode;

    /** true = dark mode (default), false = light mode */
    @track isDarkMode = true;

    /** Hide QTC Assistant sidebar (re-enable when ready) */
    showChatSidebar = false;

    get isAccountSearchPage() { return this.currentPage === 'accountSearch'; }
    get isOsaSelectorPage() { return this.currentPage === 'osaSelector'; }
    get isQuoteEditorPage() { return this.currentPage === 'quoteEditor'; }

    get appContainerClass() {
        return this.isDarkMode ? 'app-container dark-theme' : 'app-container light-theme';
    }

    get themeLabel() {
        return this.isDarkMode ? 'Light Mode' : 'Dark Mode';
    }

    /**
     * Deep-link entry point. When the app is opened from the "Simplified Quote Editor"
     * quote action, the tab URL carries ?c__quoteId=<id> plus the account/contract
     * context, and jumps straight into the quote editor for that existing draft (loaded
     * via SOQL, no amend flow) with the header + breadcrumb populated.
     *
     * Lightning caches this tab's component instance, so connectedCallback does not re-run
     * on a second navigation — this wire is the only thing that re-fires. We therefore key
     * off the inbound quote Id (never a one-shot flag): a different id always re-opens, and
     * when the editor is already mounted we force a remount so it reloads the new quote.
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const state = pageRef && pageRef.state ? pageRef.state : null;
        const quoteId = state ? state.c__quoteId : null;
        if (!quoteId) return;
        // Already showing exactly this quote — nothing to do.
        if (quoteId === this.selectedExistingQuoteId && this.currentPage === 'quoteEditor') return;
        this.openExistingQuoteFromState(quoteId, state);
    }

    openExistingQuoteFromState(quoteId, state) {
        this.selectedExistingQuoteId = quoteId;
        this.selectedAccountId = state.c__accountId || null;
        this.selectedAccountName = state.c__accountName || null;
        this.selectedContractId = state.c__contractId || null;
        this.selectedContractNumber = state.c__contractNumber || null;
        this.selectedCurrencyIsoCode = state.c__currencyIsoCode || null;
        if (this.currentPage === 'quoteEditor') {
            // Editor is already mounted for another quote; its connectedCallback won't
            // re-run on an @api change, so blank the page and re-show it next tick to
            // force a fresh editor instance that loads the new quote.
            this.currentPage = '';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.currentPage = 'quoteEditor'; }, 0);
        } else {
            this.currentPage = 'quoteEditor';
        }
    }

    connectedCallback() {
        try {
            const savedTheme = localStorage.getItem('agenticqtc_dark_mode');
            if (savedTheme === 'false') {
                this.isDarkMode = false;
            }
        } catch (e) {
            /* localStorage unavailable */
        }
    }

    handleToggleTheme() {
        this.isDarkMode = !this.isDarkMode;
        try {
            localStorage.setItem('agenticqtc_dark_mode', String(this.isDarkMode));
        } catch (e) {
            /* localStorage unavailable */
        }
    }

    handleAccountSelected(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.selectedAccountId = detail.accountId;
        this.selectedAccountName = detail.accountName;
        this.currentPage = 'osaSelector';
    }

    handleContractSelected(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.selectedContractId = detail.contractId;
        this.selectedContractNumber = detail.contractNumber;
        this.selectedExistingQuoteId = detail.existingQuoteId || null;
        this.selectedSubscriptionTcv = detail.subscriptionTcv != null ? detail.subscriptionTcv : null;
        this.selectedCurrencyIsoCode = detail.currencyIsoCode || null;
        this.currentPage = 'quoteEditor';
    }

    handleQuoteLoaded(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.currentQuoteId = detail.quoteId;
    }

    handleBackToAccounts() {
        this.selectedAccountId = null;
        this.selectedAccountName = null;
        this.selectedContractId = null;
        this.selectedContractNumber = null;
        this.currentQuoteId = null;
        this.selectedExistingQuoteId = null;
        this.selectedSubscriptionTcv = null;
        this.selectedCurrencyIsoCode = null;
        this.currentPage = 'accountSearch';
    }

    handleBackToContracts() {
        this.selectedContractId = null;
        this.selectedContractNumber = null;
        this.currentQuoteId = null;
        this.selectedExistingQuoteId = null;
        this.selectedSubscriptionTcv = null;
        this.selectedCurrencyIsoCode = null;
        // Deep-linked sessions have no account context, so the OSA selector would be
        // empty — send the user back to account search instead.
        this.currentPage = this.selectedAccountId ? 'osaSelector' : 'accountSearch';
    }

    handleChatAccountNav(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.selectedAccountId = detail.accountId;
        this.selectedAccountName = detail.accountName;
        this.selectedExistingQuoteId = null;
        this.currentPage = 'osaSelector';
    }

    handleChatContractNav(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.selectedContractId = detail.contractId;
        this.selectedContractNumber = detail.contractNumber;
        this.selectedExistingQuoteId = null;
        this.currentPage = 'quoteEditor';
    }

    handleRefreshLines() {
        const editor = this.template.querySelector('c-agentic-qtc-quote-editor');
        if (editor) {
            editor.refreshLines();
        }
    }
}