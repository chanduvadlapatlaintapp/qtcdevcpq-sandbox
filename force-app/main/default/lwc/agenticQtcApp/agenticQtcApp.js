import { LightningElement, track } from 'lwc';

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
        this.currentPage = 'accountSearch';
    }

    handleBackToContracts() {
        this.selectedContractId = null;
        this.selectedContractNumber = null;
        this.currentQuoteId = null;
        this.selectedExistingQuoteId = null;
        this.currentPage = 'osaSelector';
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