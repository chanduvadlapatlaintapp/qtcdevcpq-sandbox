import { LightningElement, track } from 'lwc';
import createTestRunScoped  from '@salesforce/apex/AgenticQTC_TestRunnerController.createTestRunScoped';
import getTestRun           from '@salesforce/apex/AgenticQTC_TestRunnerController.getTestRun';
import getRecentTestRuns    from '@salesforce/apex/AgenticQTC_TestRunnerController.getRecentTestRuns';
import searchTestRuns       from '@salesforce/apex/AgenticQTC_TestRunnerController.searchTestRuns';
import cancelTestRun        from '@salesforce/apex/AgenticQTC_TestRunnerController.cancelTestRun';
import getTestRunFiles      from '@salesforce/apex/AgenticQTC_TestRunnerController.getTestRunFiles';
import searchAccounts       from '@salesforce/apex/AgenticQTC_TestRunnerController.searchAccounts';
import getSuiteOptions          from '@salesforce/apex/AgenticQTC_TestRunnerController.getSuiteOptions';
import getModuleOptions         from '@salesforce/apex/AgenticQTC_TestRunnerController.getModuleOptions';
import getContractsForAccount   from '@salesforce/apex/AgenticQTC_TestRunnerController.getContractsForAccount';
import getQuotesForContract     from '@salesforce/apex/AgenticQTC_TestRunnerController.getQuotesForContract';
import { ShowToastEvent }   from 'lightning/platformShowToastEvent';
import LightningConfirm     from 'lightning/confirm';

// ── Polling cadence ──────────────────────────────────────────────────────────
const POLL_INTERVAL_MS        = 1500;        // fast poll while a run is actively RUNNING
const IDLE_POLL_INTERVAL_MS   = 3000;        // slower poll while PENDING / CLAIMED
const MAX_POLL_MS             = 22 * 60 * 1000;   // give up (mark stuck) after this long
const HISTORY_REFRESH_MS      = 30 * 1000;   // background refresh of the run list when idle
const IN_PROGRESS_STATUSES    = new Set(['PENDING', 'CLAIMED', 'RUNNING']);

// ── Run history ──────────────────────────────────────────────────────────────
const RECENT_RUNS_LIMIT       = 20;          // rows fetched for the Recent Runs list

// ── Account typeahead ────────────────────────────────────────────────────────
const ACCT_SEARCH_DEBOUNCE_MS = 300;         // debounce before firing the search
const ACCT_MIN_SEARCH_LEN     = 2;           // mirrors AgenticQTC_AccountSearchService
const ACCT_BLUR_CLOSE_MS      = 150;         // delay before closing results on blur

// ── Pass-rate widget ─────────────────────────────────────────────────────────
const PASS_RATE_WINDOW        = 10;          // recent finished runs averaged for pass rate
const PASS_RATE_GREEN_PCT     = 80;          // >= green
const PASS_RATE_WARN_PCT      = 50;          // >= yellow, otherwise red

// ── Rich-results tolerances ──────────────────────────────────────────────────
const QTY_MATCH_TOLERANCE     = 0.01;        // UI vs DB qty treated as equal within this
const DEFAULT_QTY_DELTA       = 5;           // fallback delta when the spec didn't record one

// ── Multi-account selection ──────────────────────────────────────────────────
const MULTI_ACCT_MAX = 5;
const MULTI_ACCT_MIN = 2;

// ── localStorage keys ────────────────────────────────────────────────────────
const LS_DARK_MODE = 'agenticqtc_dark_mode';
const LS_RUNNER    = 'agenticqtc_runner';
const LS_SUITE     = 'agenticqtc_suite';
const LS_MODULE    = 'agenticqtc_module';

// Inline placeholder shown when a screenshot fails to load (#29)
const BROKEN_IMAGE_DATA_URI = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="135">' +
    '<rect width="100%" height="100%" fill="#e2e8f0"/>' +
    '<text x="50%" y="50%" font-family="sans-serif" font-size="11" fill="#64748b" ' +
    'text-anchor="middle" dominant-baseline="middle">image unavailable</text></svg>'
);

const RUNNER_OPTIONS = [
    { label: '☁️ GitHub', value: 'github', title: 'Run on GitHub Actions (cloud, headless)' },
    { label: '🖥 Local',  value: 'local',  title: 'Run on local agent (this machine)' },
];

export default class AgenticQtcTestDashboard extends LightningElement {

    // ── reactive state ──────────────────────────────────────────────────────

    @track _suiteOptions      = [];     // populated from agenticQTC_TestSuite__mdt (label/value/moduleName/description)
    @track _moduleOptions     = [];     // populated from Module__mdt
    @track selectedModule     = null;   // null → the "Select Module" placeholder is shown
    @track selectedSuite      = null;   // null → the "Select Spec" placeholder is shown
    @track selectedRunner     = 'github';
    @track activeRunId        = null;
    @track activeRun          = null;
    @track recentRuns         = [];
    @track isLoadingHistory   = false;
    @track isCreating         = false;      // true between click and createTestRun resolving
    @track isStuck            = false;
    @track isDarkMode         = true;
    @track activeRunFiles     = [];         // AttachmentWrapper[]
    @track parsedRichResults  = null;       // parsed richResults JSON
    @track _logFromFile       = null;       // log text fetched from log-output.txt ContentVersion
    @track lightboxIndex      = null;       // null = closed, number = open
    @track activeTab          = 'screenshots';
    @track activeSidebarRunId = null;
    @track _contractDropdownOpen = false;    // custom Contract picker
    @track _quoteDropdownOpen    = false;    // custom Quote picker
    @track _moduleDropdownOpen  = false;     // custom Module picker
    @track _specDropdownOpen    = false;     // custom Spec picker
    @track showRunDropdown      = false;     // Recent Runs picker in the control bar
    @track _dropdownStyle       = '';        // inline style for the fixed-position dropdown panel
    @track historyFilter        = '';        // text filter for the Recent Runs list
    @track _historySearchResults = null;     // null = show recentRuns; array = server search results
    @track _isSearchingHistory   = false;    // true while server search is in flight
    _historySearchTimeout = null;
    @track videoLoadError     = false;      // true if the run recording fails to load
    @track showVideoModal     = false;      // true while the recording plays in a popup

    // ── account search (typeahead) ──────────────────────────────────────────
    @track accountSearchTerm     = '';
    @track accountResults        = [];      // AccountResult[] from Apex
    @track isSearchingAccounts   = false;
    @track hasSearchedAccounts   = false;
    @track selectedAccountId     = null;
    @track selectedAccountName   = null;
    @track accountHighlightIndex = -1;      // keyboard-highlighted result (#30)

    // ── contract scoping (optional) ─────────────────────────────────────────
    @track _contractOptions      = [];      // ContractOption[] from Apex
    @track selectedContractId    = null;
    @track selectedContractNumber = null;

    // ── quote scoping (optional) ─────────────────────────────────────────────
    @track _quoteOptions         = [];      // QuoteOption[] from Apex
    @track selectedQuoteId       = null;
    @track selectedQuoteName     = null;

    // ── multi-account mode ───────────────────────────────────────────────────
    @track accountMode           = 'single';  // 'single' | 'multi'
    @track selectedAccounts      = [];         // [{id, name}] max 5, min 2
    @track multiAcctSearchTerm   = '';
    @track multiAcctResults      = [];         // AccountResult[] from Apex
    @track isSearchingMultiAcct  = false;
    @track hasSearchedMultiAcct  = false;
    @track multiAcctHighlight    = -1;

    // ── private (non-reactive) fields ────────────────────────────────────────
    _historyTimer           = null;
    _acctSearchTimeout      = null;
    _acctBlurTimeout        = null;
    _multiAcctSearchTimeout = null;
    _multiAcctBlurTimeout   = null;
    _pollTimer         = null;
    _pollStartTime     = null;
    _lightboxFocused   = false;             // focus the lightbox overlay only once per open
    _placeholderId     = '__creating__';    // row id used while createTestRun is in-flight

    // Memo cache for the expensive rich-results-derived arrays (#31). Rebuilt only
    // when the parsedRichResults reference changes (i.e. a new run is loaded/polled).
    _richMemo = { source: undefined, view: null };

    // ── lifecycle ───────────────────────────────────────────────────────────

    // Close all dropdowns on any click not stopped by their own elements.
    _onDocumentClick = () => {
        if (this.showRunDropdown) {
            this.showRunDropdown        = false;
            this.historyFilter          = '';
            this._historySearchResults  = null;
            this._isSearchingHistory    = false;
        }
        if (this._contractDropdownOpen) this._contractDropdownOpen = false;
        if (this._quoteDropdownOpen)    this._quoteDropdownOpen    = false;
        if (this._moduleDropdownOpen)   this._moduleDropdownOpen   = false;
        if (this._specDropdownOpen)     this._specDropdownOpen     = false;
    };

    connectedCallback() {
        try {
            if (localStorage.getItem(LS_DARK_MODE) === 'false') this.isDarkMode = false;
            const savedRunner = localStorage.getItem(LS_RUNNER);
            if (savedRunner === 'github' || savedRunner === 'local') {
                this.selectedRunner = savedRunner;
            }
        } catch (e) { /* localStorage unavailable */ }

        this._loadModuleOptions();
        this._loadSuiteOptions();
        this._loadHistory();
        window.addEventListener('click', this._onDocumentClick);

        // Background history auto-refresh (#23) — only when not actively polling a run
        this._historyTimer = setInterval(() => {
            if (!this._pollTimer && !this.isCreating) this._loadHistory(true);
        }, HISTORY_REFRESH_MS);
    }

    disconnectedCallback() {
        this._stopPolling();
        clearTimeout(this._acctSearchTimeout);
        clearTimeout(this._acctBlurTimeout);
        clearTimeout(this._multiAcctSearchTimeout);
        clearTimeout(this._multiAcctBlurTimeout);
        clearInterval(this._historyTimer);
        window.removeEventListener('click', this._onDocumentClick);
    }

    renderedCallback() {
        // Move keyboard focus into the lightbox when it opens so ←/→/Esc work
        // without an extra click (#28).
        if (this.lightboxOpen && !this._lightboxFocused) {
            const overlay = this.template.querySelector('.lb-overlay');
            if (overlay) {
                overlay.focus();
                this._lightboxFocused = true;
            }
        } else if (!this.lightboxOpen && this._lightboxFocused) {
            this._lightboxFocused = false;
        }
    }

    // ── computed getters: layout ────────────────────────────────────────────

    // Module dropdown options (from Module__mdt).
    get moduleOptions() {
        return this._moduleOptions.map(option => ({
            ...option,
            selected:  option.value === this.selectedModule,
            itemClass: 'custom-dd-item' + (option.value === this.selectedModule ? ' custom-dd-item-sel' : ''),
        }));
    }
    get noModuleSelected() { return !this.selectedModule; }

    get selectedModuleLabel() {
        if (!this.selectedModule) return 'Select Module';
        const match = this._moduleOptions.find(o => o.value === this.selectedModule);
        return match ? match.label : this.selectedModule;
    }

    get moduleDropdownClass() {
        return ['custom-dd-outer',
            this._moduleDropdownOpen ? 'custom-dd-open' : '',
            this.isRunning ? 'custom-dd-disabled' : '',
        ].filter(Boolean).join(' ');
    }

    // Spec dropdown is disabled until a module is chosen.
    get specSelectDisabled() { return this.isRunning || !this.selectedModule; }

    // Spec options filtered to the selected module. With no module selected the
    // list is empty so the user must pick a module first.
    get suiteOptions() {
        if (!this.selectedModule) return [];
        return this._suiteOptions
            .filter(option => option.moduleName === this.selectedModule)
            .map(option => ({
                label:     option.label,
                value:     option.value,
                selected:  option.value === this.selectedSuite,
                itemClass: 'custom-dd-item' + (option.value === this.selectedSuite ? ' custom-dd-item-sel' : ''),
            }));
    }
    get noSpecSelected() { return !this.selectedSuite; }

    get selectedSpecLabel() {
        if (!this.selectedSuite) return 'Select Spec';
        const match = this._suiteOptions.find(o => o.value === this.selectedSuite);
        return match ? match.label : this.selectedSuite;
    }

    get specDropdownClass() {
        return ['custom-dd-outer',
            this._specDropdownOpen ? 'custom-dd-open' : '',
            this.specSelectDisabled ? 'custom-dd-disabled' : '',
        ].filter(Boolean).join(' ');
    }

    // Description of the currently-selected spec (shown beside the Spec dropdown).
    // Empty when no spec is selected → the description block stays hidden.
    get selectedSpecDescription() {
        if (!this.selectedSuite) return '';
        const match = this._suiteOptions.find(o => o.value === this.selectedSuite);
        return (match && match.description) ? match.description : '';
    }
    get hasSelectedSpecDescription() { return !!this.selectedSpecDescription; }

    get runnerOptions() {
        return RUNNER_OPTIONS.map(option => ({
            ...option,
            btnClass: this.selectedRunner === option.value ? 'runner-btn runner-btn-active' : 'runner-btn',
        }));
    }

    get containerClass() {
        return `runner-container ${this.isDarkMode ? 'dark-theme' : 'light-theme'}`;
    }

    get themeLabel() { return this.isDarkMode ? 'Light Mode' : 'Dark Mode'; }

    get isRunning() {
        return this.activeRunId &&
               this.activeRun &&
               IN_PROGRESS_STATUSES.has(this.activeRun.status);
    }

    get runBtnClass() { return (this.isRunning || this.isCreating) ? 'btn btn-run running' : 'btn btn-run'; }
    get runButtonLabel() {
        if (this.isCreating) return 'Creating…';
        if (this.isRunning)  return 'Running…';
        return this.selectedRunner === 'github' ? 'Run on GitHub' : 'Run Local';
    }
    get runButtonDisabled() {
        if (this.isRunning || this.isCreating || !this.selectedSuite) return true;
        if (this.isMultiAccountMode) return this.selectedAccounts.length < MULTI_ACCT_MIN;
        return !this.selectedAccountId;
    }
    get reRunDisabled() {
        if (this.isRunning || this.isCreating || !this.activeRun) return true;
        return !this.activeRun.accountName && !this.activeRun.accountsJson;
    }
    get newRunDisabled() {
        return this.isCreating;
    }

    // ── account search getters ──────────────────────────────────────────────
    get hasSelectedAccount() { return !!this.selectedAccountId; }

    // ── multi-account mode getters ──────────────────────────────────────────

    // The suite metadata entry for the currently-selected spec.
    get selectedSuiteMeta() {
        if (!this.selectedSuite) return null;
        return this._suiteOptions.find(o => o.value === this.selectedSuite) || null;
    }

    // Show the Single / Multi toggle only when the selected spec has Allow_Multiple_Account__c = true.
    get showAccountModeToggle() {
        const suite = this.selectedSuiteMeta;
        return !!(suite && suite.allowMultipleAccount);
    }

    // True when the toggle is set to multi mode.
    get isMultiAccountMode() {
        return this.showAccountModeToggle && this.accountMode === 'multi';
    }

    get singleModeBtnClass() {
        return this.accountMode === 'single' ? 'runner-btn runner-btn-active' : 'runner-btn';
    }
    get multiModeBtnClass() {
        return this.accountMode === 'multi' ? 'runner-btn runner-btn-active' : 'runner-btn';
    }

    // Whether another account can be added (cap not yet reached).
    get canAddMoreAccounts() {
        return !this.isRunning && this.selectedAccounts.length < MULTI_ACCT_MAX;
    }

    // "2 / 5" badge shown next to the label.
    get multiAcctCountLabel() {
        return `${this.selectedAccounts.length} / ${MULTI_ACCT_MAX}`;
    }

    // True when fewer than the minimum accounts are selected.
    get multiAcctMinNotMet() {
        return this.selectedAccounts.length < MULTI_ACCT_MIN;
    }

    // Show the count badge only once at least one account is selected.
    get showMultiAcctCount() {
        return this.selectedAccounts.length > 0;
    }

    // Show the typeahead results list (filters out already-selected accounts).
    get showMultiAcctResults() {
        return this.hasSearchedMultiAcct &&
               !this.isSearchingMultiAcct &&
               this.multiAcctFilteredResults.length > 0;
    }

    // Typeahead results minus already-selected accounts, decorated with highlight class.
    get multiAcctFilteredResults() {
        const selectedIds = new Set(this.selectedAccounts.map(a => a.id));
        return this.multiAcctResults
            .filter(a => !selectedIds.has(a.id))
            .map((a, idx) => ({
                ...a,
                itemClass: idx === this.multiAcctHighlight
                    ? 'acct-result-item acct-result-active'
                    : 'acct-result-item',
            }));
    }

    get showMultiAcctNoResults() {
        const selectedIds = new Set(this.selectedAccounts.map(a => a.id));
        const unselected  = this.multiAcctResults.filter(a => !selectedIds.has(a.id));
        return this.hasSearchedMultiAcct &&
               !this.isSearchingMultiAcct &&
               unselected.length === 0 &&
               this.multiAcctSearchTerm.trim().length >= ACCT_MIN_SEARCH_LEN;
    }

    // ── contract getters ─────────────────────────────────────────────────────
    get contractOptions() {
        return this._contractOptions.map(c => ({
            ...c,
            selected:  c.value === this.selectedContractId,
            itemClass: 'custom-dd-item' + (c.value === this.selectedContractId ? ' custom-dd-item-sel' : ''),
        }));
    }
    get noContractSelected()      { return !this.selectedContractId; }
    get contractSelectDisabled()  { return this.isRunning || !this.selectedAccountId || this._contractOptions.length === 0; }

    get selectedContractLabel() {
        if (!this.selectedContractId) return 'Select Contract';
        const match = this._contractOptions.find(c => c.value === this.selectedContractId);
        return match ? match.label : this.selectedContractId;
    }

    get contractDropdownClass() {
        return ['custom-dd-outer',
            this._contractDropdownOpen ? 'custom-dd-open' : '',
            this.contractSelectDisabled ? 'custom-dd-disabled' : '',
        ].filter(Boolean).join(' ');
    }

    // ── quote getters ────────────────────────────────────────────────────────
    get quoteOptions() {
        return this._quoteOptions.map(q => ({
            ...q,
            selected:  q.value === this.selectedQuoteId,
            itemClass: 'custom-dd-item' + (q.value === this.selectedQuoteId ? ' custom-dd-item-sel' : ''),
        }));
    }
    get noQuoteSelected()      { return !this.selectedQuoteId; }
    get quoteSelectDisabled()  { return this.isRunning || !this.selectedContractId || this._quoteOptions.length === 0; }

    get selectedQuoteLabel() {
        if (!this.selectedQuoteId) return 'Select Quote';
        const match = this._quoteOptions.find(q => q.value === this.selectedQuoteId);
        return match ? match.label : this.selectedQuoteId;
    }

    get quoteDropdownClass() {
        return ['custom-dd-outer',
            this._quoteDropdownOpen ? 'custom-dd-open' : '',
            this.quoteSelectDisabled ? 'custom-dd-disabled' : '',
        ].filter(Boolean).join(' ');
    }

    // Grey out the account control while a run is in progress / being created
    get acctSelectWrapClass() {
        return (this.isRunning || this.isCreating)
            ? 'acct-select-wrap acct-wrap-disabled'
            : 'acct-select-wrap';
    }

    get showAccountResults() {
        return this.hasSearchedAccounts &&
               this.accountResults.length > 0 &&
               !this.isSearchingAccounts;
    }

    // Results decorated with the keyboard-highlight class (#30)
    get accountResultRows() {
        return this.accountResults.map((account, index) => ({
            ...account,
            itemClass: index === this.accountHighlightIndex
                ? 'acct-result-item acct-result-active'
                : 'acct-result-item',
        }));
    }

    get showAccountNoResults() {
        return this.hasSearchedAccounts &&
               this.accountResults.length === 0 &&
               !this.isSearchingAccounts &&
               this.accountSearchTerm.length >= ACCT_MIN_SEARCH_LEN;
    }

    get cancelButtonDisabled() {
        return !this.activeRun || !IN_PROGRESS_STATUSES.has(this.activeRun.status);
    }

    get waitingForAgent() {
        return this.activeRun && this.activeRun.status === 'PENDING' && !this.isStuck;
    }

    get showStuckWarning() { return this.isStuck; }

    get hasTestResults() {
        return this.activeRun &&
               this.activeRun.testResults &&
               this.activeRun.testResults.length > 0;
    }

    get hasHistory()      { return this.recentRuns.length > 0; }
    get hasFilteredRuns() { return this._isSearchingHistory || this.sidebarRuns.length > 0; }
    get noRunsMessage() {
        if (this._isSearchingHistory) return 'Searching…';
        if (this._historySearchResults !== null) return 'No runs matched your search';
        return this.hasHistory ? 'No matching runs' : 'No runs yet';
    }

    get runDropdownLabel() {
        if (this.activeRun && this.activeRun.name) return this.activeRun.name;
        return this.hasHistory ? 'Recent Runs' : 'No runs yet';
    }
    // Secondary text on the dropdown button: duration when finished, else queued time
    get runDropdownSub() {
        const run = this.activeRun;
        if (!run) return '';
        if (run.durationMs != null) return run.durationDisplay;
        return run.createdDateDisplay || '';
    }

    get durationDisplay() {
        return this.activeRun ? formatDurationMs(this.activeRun.durationMs) : '—';
    }

    // ── computed getters: screenshots ───────────────────────────────────────

    get activeRunImages() {
        return this.activeRunFiles
            .filter(file => /^(PNG|JPG|JPEG)$/i.test(file.fileType || ''))
            .sort((a, b) => (a.title || '').localeCompare(b.title || ''));
    }
    get hasImages() { return this.activeRunImages.length > 0; }

    // ── computed getters: video ─────────────────────────────────────────────

    get activeRunVideo() {
        // Salesforce assigns FileType='UNKNOWN' for .webm — use fileExtension first
        // (now exposed by Apex), then fall back to title scan.
        return this.activeRunFiles.find(file =>
            /^(webm|mp4)$/i.test(file.fileExtension || '') ||
            /^(WEBM|MP4)$/i.test(file.fileType     || '') ||
            /\.(webm|mp4)$/i.test(file.title       || '')
        ) || null;
    }
    get hasVideo() { return this.activeRunVideo !== null; }
    get videoSrc() { return this.activeRunVideo ? this.activeRunVideo.downloadUrl : ''; }

    // Screenshots tab: the video tile sits inside the grid alongside screenshots
    get showVideoTile()    { return this.hasVideo && !this.videoLoadError; }
    get hasScreenshotGrid() { return this.hasImages || this.showVideoTile; }

    // ── computed getters: lightbox ──────────────────────────────────────────

    get lightboxOpen() { return this.lightboxIndex !== null; }
    get lightboxImage() {
        if (this.lightboxIndex === null) return null;
        return this.activeRunImages[this.lightboxIndex] || null;
    }
    get lightboxSrc()   { return this.lightboxImage ? this.lightboxImage.downloadUrl : ''; }
    get lightboxTitle() { return this.lightboxImage ? this.lightboxImage.title : ''; }
    get lightboxCounter() {
        if (this.lightboxIndex === null) return '';
        return `${this.lightboxIndex + 1} / ${this.activeRunImages.length}`;
    }
    get lightboxHasPrev() { return this.lightboxIndex !== null && this.lightboxIndex > 0; }
    get lightboxHasNext() {
        return this.lightboxIndex !== null &&
               this.lightboxIndex < this.activeRunImages.length - 1;
    }

    // ── computed getters: rich results ──────────────────────────────────────
    //
    // The heavy array transforms below are built once per run via _richView and
    // cached (#31); these getters are thin reads of that cached view.

    get hasRichResults()   { return this.parsedRichResults != null; }
    get hasRichLineRows()  { return this.richLineRows.length > 0; }
    get hasRichDbRows()    { return this.richDbRows.length > 0; }
    get hasRichAnomalies() { return this.richAnomalyRows.length > 0; }
    // DB Lines tab is only meaningful when at least one row carries a real value
    // (the field-comparison spec emits product-name rows with all-null numerics).
    get hasRichDbValues()  { return this._richView.hasDbValues; }
    get hasRichMetrics()   { return !!(this.parsedRichResults && this.parsedRichResults.metricsBeforeSave); }

    get richDbRows()       { return this._richView.dbRows; }
    get richLineRows()     { return this._richView.lineRows; }
    get richAnomalyRows()  { return this._richView.anomalyRows; }
    get richMismatchRows() { return this._richView.mismatchRows; }
    get mismatchCount()    { return this._richView.mismatchCount; }

    get hasMismatchRows()  { return this.richMismatchRows.length > 0; }
    get allMismatchMatch() { return this.mismatchCount === 0 && this.richMismatchRows.length > 0; }

    // Memoized view of everything derived from parsedRichResults.
    get _richView() {
        if (this._richMemo.source === this.parsedRichResults) return this._richMemo.view;
        const view = this._buildRichView(this.parsedRichResults);
        this._richMemo = { source: this.parsedRichResults, view };
        return view;
    }

    get richSummaryKpis() {
        const rich = this.parsedRichResults;
        if (!rich) return [];
        const qtyMatch = rich.uiQtyTotal != null && rich.dbQtyTotal != null &&
                         Math.abs(rich.uiQtyTotal - rich.dbQtyTotal) < QTY_MATCH_TOLERANCE;
        return [
            { id: 'contract',  label: 'Contract',     value: rich.contract  || '—',                              valClass: 'rich-kpi-val rich-kpi-blue' },
            { id: 'quote',     label: 'Quote',        value: rich.quoteName || '—',                              valClass: 'rich-kpi-val rich-kpi-mono' },
            { id: 'lines',     label: 'Lines',        value: String(rich.spinbuttonCount || 0),                  valClass: 'rich-kpi-val' },
            { id: 'dblines',   label: 'DB Lines',     value: String(rich.dbLineCount    || 0),                   valClass: 'rich-kpi-val' },
            { id: 'uiqty',     label: 'UI Qty Total', value: rich.uiQtyTotal != null ? String(rich.uiQtyTotal) : '—', valClass: 'rich-kpi-val' },
            { id: 'dbqty',     label: 'DB Qty Total', value: rich.dbQtyTotal != null ? String(rich.dbQtyTotal) : '—', valClass: qtyMatch ? 'rich-kpi-val rich-kpi-green' : 'rich-kpi-val rich-kpi-red' },
            { id: 'anomalies', label: 'Anomalies',    value: String(rich.dbAnomalyCount || 0),                   valClass: (rich.dbAnomalyCount || 0) > 0 ? 'rich-kpi-val rich-kpi-warn' : 'rich-kpi-val rich-kpi-green' },
            { id: 'high',      label: 'HIGH Sev.',    value: String(rich.dbHighCount    || 0),                   valClass: (rich.dbHighCount    || 0) > 0 ? 'rich-kpi-val rich-kpi-red'  : 'rich-kpi-val rich-kpi-green' },
            { id: 'approval',  label: 'Approval Req', value: rich.hasApproval ? '⚠️ Yes' : '✅ No',              valClass: 'rich-kpi-val' },
            { id: 'pdf',       label: 'PDF',          value: rich.pdfSkipped ? 'Skipped' : (rich.pdfGenerated ? '✅ Yes' : '❌ No'), valClass: 'rich-kpi-val' },
        ];
    }

    get richMetrics() {
        const rich = this.parsedRichResults;
        if (!rich) return [];
        const before = rich.metricsBeforeSave || {};
        const after  = rich.metricsAfterSave  || {};
        return [
            { id: 'ACV',   label: 'ACV',          before: before.acv         || '—', after: after.acv         || '—' },
            { id: 'ACVCh', label: 'ACV Change',   before: before.acvChange   || '—', after: after.acvChange   || '—' },
            { id: 'TCV',   label: 'TCV',          before: before.tcv         || '—', after: after.tcv         || '—' },
            { id: 'YoY',   label: 'YoY Uplift',   before: before.yoyUplift   || '—', after: after.yoyUplift   || '—' },
            { id: 'DQS',   label: 'Deal Quality', before: before.dealQuality || '—', after: after.dealQuality || '—' },
        ];
    }

    // ── Tab bar ─────────────────────────────────────────────────────────────

    get tabs() {
        const mismatch = this.mismatchCount;
        const allMatch = this.allMismatchMatch;
        const makeTab = (id, label, icon, badge, badgeOk) => ({
            id, label, icon,
            badge: badge != null ? String(badge) : null,
            badgeClass: badgeOk === false ? 'tab-badge tab-badge-fail'
                      : badgeOk === true  ? 'tab-badge tab-badge-ok'
                      : 'tab-badge',
            btnClass: this.activeTab === id ? 'tab-btn tab-btn-active' : 'tab-btn',
        });

        // Only surface tabs that actually have something to show.
        const tabs = [];
        if (this.hasImages || this.hasVideo) {
            tabs.push(makeTab('screenshots', 'Screenshots', '📸', this.activeRunImages.length || null, null));
        }
        if (this.hasMismatchRows) {
            tabs.push(makeTab('crosscheck', 'UI↔DB', '🔀', allMatch ? '✅' : mismatch + '❌', allMatch));
        }
        if (this.hasRichDbValues) {
            tabs.push(makeTab('db', 'DB Lines', '🗄', this.richDbRows.length || null, null));
        }
        if (this.hasRichResults) {
            tabs.push(makeTab('metrics', 'Metrics', '💰', null, null));
        }
        if (this.hasOsaComparison) {
            const osaDiffs = this.richOsaRows.filter(r => !r.match).length;
            tabs.push(makeTab('osa', 'OSA Data', '🗂', osaDiffs === 0 ? '✅' : osaDiffs + '❌', osaDiffs === 0));
        }
        if (this.hasRichAnomalies) {
            tabs.push(makeTab('anomalies', 'Anomalies', '⚠️', this.richAnomalyRows.length, false));
        }
        if (this.hasTestResults) {
            tabs.push(makeTab('spec', 'Spec', '🎭', null, null));
        }
        if (this.hasLogOutput) {
            tabs.push(makeTab('log', 'Log', '📋', null, null));
        }
        return tabs;
    }

    get activeTabIsScreenshots() { return this.activeTab === 'screenshots'; }
    get activeTabIsCrosscheck()  { return this.activeTab === 'crosscheck'; }
    get activeTabIsDb()          { return this.activeTab === 'db'; }
    get activeTabIsMetrics()     { return this.activeTab === 'metrics'; }
    get activeTabIsOsa()         { return this.activeTab === 'osa'; }
    get activeTabIsAnomalies()   { return this.activeTab === 'anomalies'; }
    get activeTabIsSpec()        { return this.activeTab === 'spec'; }
    get activeTabIsLog()         { return this.activeTab === 'log'; }

    get richOsaRows()      { return this._richView.osaRows; }
    get hasOsaComparison() { return this.richOsaRows.length > 0; }

    // ── Pass-rate widget ──────────────────────────────────────────────────────

    get runPassRate() {
        const finished = (this.recentRuns || [])
            .filter(run => run.status === 'PASSED' || run.status === 'FAILED')
            .slice(0, PASS_RATE_WINDOW);
        if (!finished.length) return { percent: 0, passed: 0, total: 0, label: '—' };
        const passed  = finished.filter(run => run.status === 'PASSED').length;
        const percent = Math.round((passed / finished.length) * 100);
        return { percent, passed, total: finished.length, label: `${passed}/${finished.length}` };
    }
    get passRateBarStyle() { return `width: ${this.runPassRate.percent}%`; }
    get passRateClass() {
        const tone = passRateTone(this.runPassRate.percent);
        return `pass-rate-fill pass-rate-${tone === 'green' ? 'green' : tone === 'yellow' ? 'yellow' : 'red'}`;
    }
    // Colored, prominent pass-rate percentage (B1)
    get passRatePctClass() {
        const tone = passRateTone(this.runPassRate.percent);
        return `cb-pr-pct cb-pr-${tone}`;
    }

    // ── Recent Runs list ──────────────────────────────────────────────────────

    get sidebarRuns() {
        const dotByStatus = {
            PASSED:  'hi-dot hi-dot-pass',
            FAILED:  'hi-dot hi-dot-fail',
            ERROR:   'hi-dot hi-dot-fail',
            RUNNING: 'hi-dot hi-dot-running',
            PENDING: 'hi-dot hi-dot-pending',
            CLAIMED: 'hi-dot hi-dot-running',
        };
        const statusTextByStatus = {
            PASSED:  'hi-status hi-status-pass',
            FAILED:  'hi-status hi-status-fail',
            ERROR:   'hi-status hi-status-fail',
            RUNNING: 'hi-status hi-status-run',
            PENDING: 'hi-status hi-status-pend',
            CLAIMED: 'hi-status hi-status-run',
        };

        // Resolve each run's spec value to its friendly label so a filter by the
        // spec's display name (e.g. "Quantity Increase") matches too.
        const specLabelByValue = {};
        this._suiteOptions.forEach(option => { specLabelByValue[option.value] = option.label; });

        // Use server search results when a query is active; fall back to local recent runs.
        const runs = this._historySearchResults !== null
            ? this._historySearchResults
            : (this.recentRuns || []);

        return runs.map(run => ({
            ...run,
            dotClass: dotByStatus[run.status] || 'hi-dot',
            statusTextClass: statusTextByStatus[run.status] || 'hi-status',
            statusLabel: run.status ? run.status.charAt(0) + run.status.slice(1).toLowerCase() : '',
            specLabel: specLabelByValue[run.testSuite] || '',
            historyItemClass: [
                'history-item',
                run.id === this.activeSidebarRunId ? 'history-item-active' : '',
                (run.status === 'FAILED' || run.status === 'ERROR') ? 'history-item-fail' : '',
                run.status === 'PASSED' ? 'history-item-pass' : '',
                IN_PROGRESS_STATUSES.has(run.status) ? 'history-item-live' : '',
            ].filter(Boolean).join(' '),
        }));
    }

    // ── Metric strip ──────────────────────────────────────────────────────────

    get metricStripItems() {
        const run  = this.activeRun;
        const rich = this.parsedRichResults;
        if (!run) return [];
        const items = [];

        // ── 1. Spec result — ✓/✕ split + progress bar ──────────────────────
        const results = run.testResults || [];
        let passed, failed, skipped, total;
        if (results.length) {
            passed  = results.filter(r => r.status === 'PASSED').length;
            failed  = results.filter(r => r.status === 'FAILED').length;
            skipped = results.filter(r => r.status === 'SKIPPED').length;
            total   = results.length;
        } else {
            passed  = run.testsPassed || 0;
            failed  = run.testsFailed || 0;
            skipped = 0;
            total   = passed + failed;
        }
        const passPercent = total > 0 ? Math.round((passed / total) * 100) : 0;
        items.push({
            id: 'spec', label: 'Spec Result',
            cardClass: 'ms-card ms-accent-' + (failed > 0 ? 'fail' : total > 0 ? 'ok' : 'neutral'),
            parts: [
                { id: 'p', text: '✓ ' + passed, cls: 'ms-num ms-num-ok' },
                { id: 'f', text: '✕ ' + failed, cls: failed > 0 ? 'ms-num ms-num-fail' : 'ms-num ms-num-muted' },
            ],
            showProgress:  total > 0,
            progressClass: 'ms-bar-fill ' + (failed > 0 ? 'ms-bar-fail' : 'ms-bar-ok'),
            progressStyle: 'width:' + passPercent + '%',
            subParts: [{ id: 's', text: total + ' total' + (skipped ? ' · ' + skipped + ' skipped' : ''), cls: 'ms-sub-txt' }],
        });

        // ── 2. Duration — with delta vs recent average ──────────────────────
        const durationVsAvg = this._durationVsAverage();
        items.push({
            id: 'dur', label: 'Duration',
            cardClass: 'ms-card ms-accent-neutral',
            parts: [{ id: 'd', text: this.durationDisplay, cls: 'ms-num ms-num-mono' }],
            showProgress: false,
            subParts: durationVsAvg ? [{ id: 'v', text: durationVsAvg.text, cls: durationVsAvg.cls }] : [],
        });

        if (!rich) return items;

        // ── 3. Anomalies — blocking / minor breakdown ───────────────────────
        if (rich.dbAnomalyCount != null) {
            const count = rich.dbAnomalyCount || 0;
            const high  = rich.dbHighCount || 0;
            const minor = count - high;
            const subParts = [];
            if (count > 0) {
                if (high)  subParts.push({ id: 'b', text: high  + ' blocking', cls: 'ms-tag ms-tag-fail' });
                if (minor) subParts.push({ id: 'm', text: minor + ' minor',    cls: 'ms-tag ms-tag-warn' });
            } else {
                subParts.push({ id: 'c', text: 'none detected', cls: 'ms-sub-txt ms-sub-ok' });
            }
            items.push({
                id: 'anom', label: 'Anomalies',
                cardClass: 'ms-card ms-accent-' + (high > 0 ? 'fail' : count > 0 ? 'warn' : 'ok'),
                parts: [{ id: 'a', text: String(count), cls: count > 0 ? 'ms-num ms-num-warn' : 'ms-num ms-num-ok' }],
                showProgress: false,
                subParts,
            });
        }

        // ── 4. DB Lines ──────────────────────────────────────────────────────
        if (rich.dbLineCount != null) {
            const lineCount = rich.dbLineCount || 0;
            items.push({
                id: 'db', label: 'DB Lines',
                cardClass: 'ms-card ms-accent-neutral',
                parts: [{ id: 'n', text: String(lineCount), cls: 'ms-num' }],
                showProgress: false,
                subParts: [{ id: 's', text: lineCount > 0 ? lineCount + ' rows verified' : 'No DB writes captured', cls: 'ms-sub-txt' }],
            });
        }

        // ── 5. Quote — external link when the record id is known ─────────────
        if (rich.quoteName) {
            const quoteId = rich.quoteId || (rich.extra && rich.extra.oobQuoteId) || null;
            items.push({
                id: 'quote', label: 'Quote',
                cardClass: 'ms-card ms-accent-info',
                isLink:  !!quoteId,
                href:    quoteId ? '/' + quoteId : null,
                primary: rich.quoteName,
                parts: [{ id: 'q', text: rich.quoteName, cls: 'ms-num ms-num-link' }],
                showProgress: false,
                subParts: run.accountName ? [{ id: 'ac', text: run.accountName, cls: 'ms-sub-txt' }] : [],
            });
        }

        // ── 6. Contract — number only (no record id available to link) ───────
        if (rich.contract) {
            items.push({
                id: 'ct', label: 'Contract',
                cardClass: 'ms-card ms-accent-info',
                parts: [{ id: 'c', text: rich.contract, cls: 'ms-num ms-num-link' }],
                showProgress: false,
                subParts: [],
            });
        }

        return items;
    }
    get hasMetricStrip() { return !!this.activeRun; }

    /**
     * Compare the active run's duration to the mean of recent completed runs.
     * Returns null until there are at least two finished runs to average.
     */
    _durationVsAverage() {
        const run = this.activeRun;
        if (!run || run.durationMs == null) return null;
        const durations = (this.recentRuns || [])
            .filter(r => r.id !== run.id && r.durationMs != null &&
                         (r.status === 'PASSED' || r.status === 'FAILED'))
            .map(r => r.durationMs);
        if (durations.length < 2) return null;
        const average = durations.reduce((sum, ms) => sum + ms, 0) / durations.length;
        const deltaMs = run.durationMs - average;
        const slower  = deltaMs > 0;
        return {
            text: `${slower ? '↑ +' : '↓ −'}${formatDurationMs(Math.abs(deltaMs))} vs avg (${formatDurationMs(average)})`,
            cls:  'ms-sub-txt ' + (slower ? 'ms-sub-warn' : 'ms-sub-ok'),
        };
    }

    // ── Header status (solid badge with icon + title-case label) ────────────
    get headerStatusLabel() {
        const status = this.activeRun && this.activeRun.status;
        return status ? status.charAt(0) + status.slice(1).toLowerCase() : '';
    }
    get headerStatusIcon() {
        switch (this.activeRun && this.activeRun.status) {
            case 'PASSED':  return '✓';
            case 'FAILED':
            case 'ERROR':   return '✕';
            case 'RUNNING':
            case 'CLAIMED': return '◐';
            case 'PENDING': return '◷';
            default:        return '';
        }
    }
    get headerStatusClass() {
        switch (this.activeRun && this.activeRun.status) {
            case 'PASSED':  return 'rh-status rh-status-pass';
            case 'FAILED':
            case 'ERROR':   return 'rh-status rh-status-fail';
            case 'RUNNING':
            case 'CLAIMED': return 'rh-status rh-status-run';
            case 'PENDING': return 'rh-status rh-status-pend';
            default:        return 'rh-status';
        }
    }

    // Timestamps for the run header
    get activeRunStartedAt()   { return this.activeRun ? (this.activeRun.startedAtDisplay   || '—') : '—'; }
    get activeRunCompletedAt() { return this.activeRun ? (this.activeRun.completedAtDisplay || '—') : '—'; }
    get activeRunCreatedAt()   { return this.activeRun ? (this.activeRun.createdDateDisplay || '—') : '—'; }

    get hasLogOutput()  { return !!(this.activeRun && (this.activeRun.logOutput || this._logFromFile)); }
    get logOutputText() { return (this.activeRun && this.activeRun.logOutput) || this._logFromFile || ''; }

    // Whether the run produced anything worth showing (gates the whole result UI)
    get hasResults() {
        return this.hasImages || this.hasVideo || this.hasRichResults ||
               this.hasTestResults || this.hasLogOutput;
    }

    // Show a spinner in the result area while a run is in progress with nothing yet
    get showRunningSpinner() {
        return (this.isRunning || this.isCreating) && !this.hasResults;
    }
    get runningStateText() {
        const status = this.activeRun && this.activeRun.status;
        if (status === 'RUNNING') return 'Running tests…';
        if (status === 'CLAIMED') return 'Queued on the runner…';
        return 'Waiting for an agent to pick up this run…';
    }

    // ── event handlers ──────────────────────────────────────────────────────

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab) this.activeTab = tab;
    }

    handleToggleRunDropdown(event) {
        event.stopPropagation();
        const opening = !this.showRunDropdown;
        this.showRunDropdown = opening;
        if (opening) {
            const rect = event.currentTarget.getBoundingClientRect();
            // If the button's right edge is less than the panel width from the left edge
            // of the viewport, there isn't enough space to extend left — open rightward.
            this._dropdownStyle = rect.right >= 308 ? '' : 'right:auto;left:0;';
        }
    }

    handleHistoryFilterChange(event) {
        const val = (event.target.value || '').trim();
        this.historyFilter = val;

        clearTimeout(this._historySearchTimeout);

        if (!val) {
            this._historySearchResults = null;
            this._isSearchingHistory   = false;
            return;
        }

        this._isSearchingHistory = true;
        this._historySearchTimeout = setTimeout(() => {
            searchTestRuns({ searchTerm: val, limitCount: 50 })
                .then(runs => {
                    if (this.historyFilter.trim() === val) {
                        this._historySearchResults = runs.map(decorateRun);
                        this._isSearchingHistory   = false;
                    }
                })
                .catch(() => {
                    this._isSearchingHistory = false;
                });
        }, 350);
    }

    // Clicks inside the dropdown panel shouldn't close it (run-item clicks close
    // it explicitly via handleHistoryRowClick).
    handleDropdownPanelClick(event) {
        event.stopPropagation();
    }

    handleModuleChange(event) {
        this.selectedModule = event.target.value || null;
        this.selectedSuite  = null;
        // Changing module clears the suite, so multi mode can no longer be valid — reset.
        this.accountMode = 'single';
        this._resetMultiAccounts();
        try { localStorage.setItem(LS_MODULE, this.selectedModule || ''); } catch (e) { /* no-op */ }
    }

    handleSuiteChange(event) {
        this.selectedSuite = event.target.value;
        // If the new spec doesn't support multi-account, fall back to single.
        const suite = this._suiteOptions.find(o => o.value === this.selectedSuite);
        if (this.accountMode === 'multi' && !(suite && suite.allowMultipleAccount)) {
            this.accountMode = 'single';
            this._resetMultiAccounts();
        } else if (this.accountMode === 'multi') {
            // Suite changed while in multi mode — apply new suite's defaults if list is empty
            this._applyDefaultAccounts();
        }
        try { localStorage.setItem(LS_SUITE, this.selectedSuite); } catch (e) { /* no-op */ }
    }

    // ── custom Module / Spec dropdown handlers ──────────────────────────────

    handleToggleModuleDropdown(event) {
        event.stopPropagation();
        if (this.isRunning) return;
        this._moduleDropdownOpen = !this._moduleDropdownOpen;
        this._specDropdownOpen   = false;
    }

    handleToggleSpecDropdown(event) {
        event.stopPropagation();
        if (this.specSelectDisabled) return;
        this._specDropdownOpen   = !this._specDropdownOpen;
        this._moduleDropdownOpen = false;
    }

    handleModuleItemSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        if (!value || value === this.selectedModule) { this._moduleDropdownOpen = false; return; }
        this.selectedModule      = value;
        this.selectedSuite       = null;
        this.accountMode         = 'single';
        this._moduleDropdownOpen = false;
        this._resetMultiAccounts();
        try { localStorage.setItem(LS_MODULE, value); } catch (e) { /* no-op */ }
    }

    handleSpecItemSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        if (!value) { this._specDropdownOpen = false; return; }
        this.selectedSuite     = value;
        this._specDropdownOpen = false;
        const suite = this._suiteOptions.find(o => o.value === value);
        if (this.accountMode === 'multi' && !(suite && suite.allowMultipleAccount)) {
            this.accountMode = 'single';
            this._resetMultiAccounts();
        } else if (this.accountMode === 'multi') {
            this._applyDefaultAccounts();
        }
        try { localStorage.setItem(LS_SUITE, value); } catch (e) { /* no-op */ }
    }

    // ── account search handlers ─────────────────────────────────────────────

    handleAccountSearchChange(event) {
        this.accountSearchTerm = event.target.value || '';
        clearTimeout(this._acctSearchTimeout);
        if (this.accountSearchTerm.trim().length >= ACCT_MIN_SEARCH_LEN) {
            this._acctSearchTimeout = setTimeout(() => this._doAccountSearch(), ACCT_SEARCH_DEBOUNCE_MS);
        } else {
            this.accountResults      = [];
            this.hasSearchedAccounts = false;
            this.isSearchingAccounts = false;
        }
    }

    async _doAccountSearch() {
        const term = this.accountSearchTerm;
        this.isSearchingAccounts = true;
        try {
            const results = await searchAccounts({ searchTerm: term });
            // Ignore stale responses if the term changed while awaiting.
            if (this.accountSearchTerm === term) {
                this.accountResults        = results || [];
                this.hasSearchedAccounts   = true;
                this.accountHighlightIndex = -1;     // reset keyboard highlight (#30)
            }
        } catch (err) {
            if (this.accountSearchTerm === term) {
                this.accountResults = [];
                this._showToast('Account search failed', toErrorMessage(err), 'error');
            }
        } finally {
            if (this.accountSearchTerm === term) {
                this.isSearchingAccounts = false;
            }
        }
    }

    handleAccountSelect(event) {
        // Fires on mousedown (before the input's blur) so the pick always lands.
        event.preventDefault();
        this._selectAccount(event.currentTarget.dataset.id, event.currentTarget.dataset.name);
    }

    _selectAccount(id, name) {
        if (!id) return;
        this.selectedAccountId      = id;
        this.selectedAccountName    = name;
        this.accountResults         = [];
        this.hasSearchedAccounts    = false;
        this.accountSearchTerm      = '';
        this.accountHighlightIndex  = -1;
        // Reset contract + quote whenever account changes
        this._resetContract();
        this._loadContracts(id);
    }

    // Keyboard navigation for the account typeahead (#30)
    handleAccountKeydown(event) {
        if (event.key === 'Escape') {
            this.accountResults        = [];
            this.hasSearchedAccounts   = false;
            this.accountHighlightIndex = -1;
            return;
        }
        if (!this.showAccountResults) return;
        const count = this.accountResults.length;
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            this.accountHighlightIndex = (this.accountHighlightIndex + 1) % count;
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            this.accountHighlightIndex = (this.accountHighlightIndex - 1 + count) % count;
        } else if (event.key === 'Enter') {
            const index = this.accountHighlightIndex;
            if (index >= 0 && index < count) {
                event.preventDefault();
                this._selectAccount(this.accountResults[index].id, this.accountResults[index].name);
            }
        }
    }

    // Close results when focus leaves the field (covers outside-click) (#30)
    handleAccountBlur() {
        clearTimeout(this._acctBlurTimeout);
        this._acctBlurTimeout = setTimeout(() => {
            this.hasSearchedAccounts   = false;
            this.accountHighlightIndex = -1;
        }, ACCT_BLUR_CLOSE_MS);
    }

    handleAccountFocus() {
        clearTimeout(this._acctBlurTimeout);
        if (this.accountResults.length > 0) this.hasSearchedAccounts = true;
    }

    handleClearAccount() {
        if (this.isRunning) return;
        this.selectedAccountId     = null;
        this.selectedAccountName   = null;
        this.accountSearchTerm     = '';
        this.accountResults        = [];
        this.hasSearchedAccounts   = false;
        this.accountHighlightIndex = -1;
        this._resetContract();
        this._contractOptions      = [];
    }

    handleToggleContractDropdown(event) {
        event.stopPropagation();
        if (this.contractSelectDisabled) return;
        this._contractDropdownOpen = !this._contractDropdownOpen;
        this._quoteDropdownOpen    = false;
    }

    handleToggleQuoteDropdown(event) {
        event.stopPropagation();
        if (this.quoteSelectDisabled) return;
        this._quoteDropdownOpen    = !this._quoteDropdownOpen;
        this._contractDropdownOpen = false;
    }

    handleContractItemSelect(event) {
        event.stopPropagation();
        const contractId           = event.currentTarget.dataset.value || null;
        this._contractDropdownOpen = false;
        const match                = contractId ? this._contractOptions.find(c => c.value === contractId) : null;
        this.selectedContractId     = contractId;
        this.selectedContractNumber = match ? match.contractNumber : null;
        this._resetQuote();
        if (contractId) this._loadQuotes(contractId);
    }

    handleQuoteItemSelect(event) {
        event.stopPropagation();
        const quoteId           = event.currentTarget.dataset.value || null;
        this._quoteDropdownOpen = false;
        const match             = quoteId ? this._quoteOptions.find(q => q.value === quoteId) : null;
        this.selectedQuoteId    = quoteId;
        this.selectedQuoteName  = match ? match.name : null;
    }

    handleContractChange(event) {
        const contractId = event.target.value || null;
        const match      = contractId ? this._contractOptions.find(c => c.value === contractId) : null;
        this.selectedContractId     = contractId;
        this.selectedContractNumber = match ? match.contractNumber : null;
        this._resetQuote();
        if (contractId) this._loadQuotes(contractId);
    }

    handleQuoteChange(event) {
        const quoteId = event.target.value || null;
        const match   = quoteId ? this._quoteOptions.find(q => q.value === quoteId) : null;
        this.selectedQuoteId   = quoteId;
        this.selectedQuoteName = match ? match.name : null;
    }

    handleRunnerChange(event) {
        const runner = event.currentTarget.dataset.runner;
        if (runner && !this.isRunning) {
            this.selectedRunner = runner;
            try { localStorage.setItem(LS_RUNNER, runner); } catch (e) { /* no-op */ }
        }
    }

    handleToggleTheme() {
        this.isDarkMode = !this.isDarkMode;
        try { localStorage.setItem(LS_DARK_MODE, String(this.isDarkMode)); } catch (e) { /* no-op */ }
    }

    // ── lightbox handlers ────────────────────────────────────────────────────

    handleImageClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.lightboxIndex = isNaN(index) ? 0 : index;
    }

    // Media error fallbacks (#29)
    handleImageError(event) {
        const img = event.target;
        if (img.dataset.errored) return;     // guard against the fallback re-erroring
        img.dataset.errored = '1';
        img.src = BROKEN_IMAGE_DATA_URI;
    }
    handleVideoError() {
        this.videoLoadError = true;
    }

    // Play the recording in a popup (concise thumbnail in the result area)
    handleOpenVideo() {
        if (!this.videoLoadError) this.showVideoModal = true;
    }
    handleCloseVideo() {
        this.showVideoModal = false;
    }
    handleVideoOverlayClick(event) {
        // Close only when clicking the backdrop (not the player itself)
        if (event.target === event.currentTarget) this.showVideoModal = false;
    }

    handleCloseLightbox() {
        this.lightboxIndex = null;
    }

    handleLightboxPrev() {
        if (this.lightboxHasPrev) this.lightboxIndex -= 1;
    }

    handleLightboxNext() {
        if (this.lightboxHasNext) this.lightboxIndex += 1;
    }

    handleLightboxKeydown(event) {
        if (event.key === 'Escape')     this.lightboxIndex = null;
        if (event.key === 'ArrowLeft')  { if (this.lightboxHasPrev) this.lightboxIndex -= 1; }
        if (event.key === 'ArrowRight') { if (this.lightboxHasNext) this.lightboxIndex += 1; }
        // Keep focus trapped inside the modal (#28)
        if (event.key === 'Tab') event.preventDefault();
    }

    handleOverlayClick(event) {
        // Close only when clicking the backdrop (not the image itself)
        if (event.target === event.currentTarget) this.lightboxIndex = null;
    }

    async handleRunTests() {
        if (this.isRunning || this.isCreating) return;

        const activeCount = this.recentRuns.filter(r => IN_PROGRESS_STATUSES.has(r.status)).length;
        if (activeCount >= 20) {
            this._showToast(
                'Too many parallel runs',
                `You already have ${activeCount} test runs in progress. Wait for some to complete before starting another.`,
                'error'
            );
            return;
        }

        // Determine account payload (single vs multi mode)
        const isMulti      = this.isMultiAccountMode;
        const accountsJson = isMulti
            ? JSON.stringify(this.selectedAccounts.map(a => ({ id: a.id, search: a.name, fullName: a.name })))
            : null;
        const acctName = isMulti
            ? this.selectedAccounts.map(a => a.name).join(', ')
            : this.selectedAccountName;
        const acctId   = isMulti ? null : this.selectedAccountId;

        // ── Step 1: instant feedback — spinner on button + placeholder row ──
        this.isCreating        = true;
        this.activeRunFiles    = [];
        this.parsedRichResults = null;
        this._logFromFile      = null;
        this.lightboxIndex     = null;

        const suiteLabel = (this._suiteOptions.find(s => s.value === this.selectedSuite) || {}).label || this.selectedSuite;
        const placeholder = {
            id:             this._placeholderId,
            name:           '…',
            status:         this.selectedRunner === 'github' ? 'CLAIMED' : 'PENDING',
            testSuite:      suiteLabel,
            accountName:    acctName,
            testsPassed:    null,
            testsFailed:    null,
            durationMs:     null,
            durationDisplay:'—',
            createdDate:    new Date().toISOString(),
            createdDateDisplay: 'just now',
            statusClass:    'status-badge status-pending',
            rowClass:       'row-live row-creating',
            isPlaceholder:  true,
        };
        // Prepend placeholder immediately — user sees the row before any API call
        this.recentRuns = [placeholder, ...this.recentRuns];
        this.activeRun  = placeholder;

        try {
            // ── Step 2: create the SF record (takes ~1-2s) ──────────────────
            const runId = await createTestRunScoped({
                testSuite:      this.selectedSuite,
                runner:         this.selectedRunner,
                accountId:      acctId,
                accountName:    acctName,
                contractId:     (!isMulti && this.selectedContractId)     ? this.selectedContractId     : null,
                contractNumber: (!isMulti && this.selectedContractNumber) ? this.selectedContractNumber : null,
                quoteId:        (!isMulti && this.selectedQuoteId)         ? this.selectedQuoteId         : null,
                quoteName:      (!isMulti && this.selectedQuoteName)       ? this.selectedQuoteName       : null,
                accountsJson,
            });
            this.activeRunId        = runId;
            this.activeSidebarRunId = runId;
            this.isCreating         = false;

            // ── Step 3: fetch real record, swap out placeholder ─────────────
            getTestRun({ testRunId: runId })
                .then(run => {
                    const decorated = decorateRun(run);
                    this.activeRun  = decorated;
                    this.recentRuns = [
                        decorated,
                        ...this.recentRuns.filter(r => r.id !== this._placeholderId && r.id !== runId),
                    ];
                })
                .catch(() => {});

            this._startPolling();
        } catch (err) {
            // Remove placeholder on failure
            this.recentRuns         = this.recentRuns.filter(r => r.id !== this._placeholderId);
            this.activeRun          = null;
            this.activeSidebarRunId = null;
            this.isCreating         = false;
            this._showToast('Error', toErrorMessage(err), 'error');
        }
    }

    // Export the current run's rich results as a JSON file (#24)
    handleExportJson() {
        if (!this.parsedRichResults) return;
        const name = (this.activeRun && this.activeRun.name) || 'run';
        this._downloadBlob(
            JSON.stringify(this.parsedRichResults, null, 2),
            name + '-results.json',
            'application/json'
        );
    }

    _downloadBlob(content, filename, type) {
        try {
            const blob = new Blob([content], { type });
            const url  = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = filename;
            link.click();
            URL.revokeObjectURL(url);
        } catch (e) {
            this._showToast('Export failed', toErrorMessage(e), 'error');
        }
    }

    // Re-run the currently-viewed run with the same suite + account (#20)
    handleReRun() {
        if (this.isRunning || this.isCreating || !this.activeRun) return;
        const run = this.activeRun;
        if (!run.accountName && !run.accountsJson) {
            this._showToast('Cannot re-run', 'This run has no account on record.', 'warning');
            return;
        }
        const reRunSuite = run.testSuite && this._suiteOptions.find(o => o.value === run.testSuite);
        if (reRunSuite) {
            this.selectedSuite = run.testSuite;
            if (reRunSuite.moduleName) this.selectedModule = reRunSuite.moduleName;
        }
        if (run.accountsJson) {
            this.accountMode = 'multi';
            try {
                const accts = JSON.parse(run.accountsJson);
                this.selectedAccounts = accts.map(a => ({
                    id:   a.id   || a.search || '',
                    name: a.fullName || a.search || a.name || '',
                }));
            } catch { /* ignore corrupt JSON — user can adjust manually */ }
        } else {
            this.accountMode         = 'single';
            this._resetMultiAccounts();
            this.selectedAccountId   = run.accountId   || null;
            this.selectedAccountName = run.accountName || null;
        }
        this.handleRunTests();
    }

    // Deselect the current run so the user can immediately trigger a new parallel run.
    // Form selections (account, spec, contract, quote, runner) are intentionally kept
    // so the user can click Run right away — each dispatch gets a unique test_run_id
    // concurrency group in GitHub Actions and runs independently.
    handleNewRun() {
        if (this.isCreating) return;
        this.activeRunId        = null;
        this.activeRun          = null;
        this.activeSidebarRunId = null;
        this.activeRunFiles     = [];
        this.parsedRichResults  = null;
        this._logFromFile       = null;
        this.lightboxIndex      = null;
    }

    async handleCancel() {
        if (!this.activeRunId) return;

        const confirmed = await LightningConfirm.open({
            message: 'Cancel this test run? It will be marked as ERROR in Salesforce. '
                   + 'A GitHub run already in progress may keep running on the agent.',
            label: 'Cancel test run',
            variant: 'header',
            theme: 'warning',
        });
        if (!confirmed) return;

        try {
            await cancelTestRun({ testRunId: this.activeRunId });
            this._showToast('Cancelled', 'Test run cancelled.', 'info');
            this._stopPolling();
            this._loadHistory();
        } catch (err) {
            this._showToast('Error', toErrorMessage(err), 'error');
        }
    }

    handleRefreshHistory() {
        this._loadHistory();
    }

    handleHistoryRowClick(event) {
        const runId = event.currentTarget.dataset.id;
        this.activeSidebarRunId    = runId;
        this.showRunDropdown       = false;
        this.historyFilter         = '';
        this._historySearchResults = null;
        this._isSearchingHistory   = false;
        this.isStuck               = false;
        this.activeRunFiles     = [];
        this.parsedRichResults  = null;
        this._logFromFile       = null;
        getTestRun({ testRunId: runId })
            .then(run => {
                this.activeRunId = run.id;
                this.activeRun   = decorateRun(run);
                this._syncFormToRun(run);
                this._parseRichResults(run);
                this._loadRunFiles(run.id);
                if (IN_PROGRESS_STATUSES.has(run.status)) {
                    this._startPolling();
                }
            })
            .catch(err => this._showToast('Error', toErrorMessage(err), 'error'));
    }

    // ── private helpers ─────────────────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollStartTime = Date.now();
        this.isStuck = false;
        this._pollActiveRun();          // immediate first tick; it self-reschedules
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearTimeout(this._pollTimer);
            this._pollTimer = null;
        }
    }

    // Adaptive cadence (#19): poll fast while a run is actively RUNNING, slower
    // while it's only PENDING/CLAIMED (waiting for an agent), to cut Apex traffic.
    _scheduleNextPoll(status) {
        const delay = status === 'RUNNING' ? POLL_INTERVAL_MS : IDLE_POLL_INTERVAL_MS;
        this._pollTimer = setTimeout(() => this._pollActiveRun(), delay);
    }

    async _pollActiveRun() {
        if (!this.activeRunId) { this._stopPolling(); return; }

        if (this._pollStartTime && (Date.now() - this._pollStartTime) > MAX_POLL_MS) {
            this._stopPolling();
            this.isStuck = true;
            return;
        }

        try {
            const run       = await getTestRun({ testRunId: this.activeRunId });
            const decorated = decorateRun(run);
            this.activeRun  = decorated;
            this._parseRichResults(run);
            this.isStuck    = false;

            // Sync status into the history row in real-time on every tick
            this.recentRuns = this.recentRuns.map(r => (r.id === run.id ? decorated : r));

            if (!IN_PROGRESS_STATUSES.has(run.status)) {
                this._stopPolling();
                // Load files immediately; refresh full history in background (non-blocking)
                this._loadRunFiles(this.activeRunId);
                this._loadHistory();

                const variant = run.status === 'PASSED' ? 'success' : 'error';
                const message = run.status === 'PASSED'
                    ? `${run.testsPassed || 0} passed · ${run.testsFailed || 0} failed`
                    : run.errorMessage || 'Run ended with status: ' + run.status;
                this._showToast('Tests complete', message, variant);
                return;
            }

            this._scheduleNextPoll(run.status);
        } catch (err) {
            console.error('Poll error:', err);
            // Keep polling through transient errors (slower cadence).
            this._scheduleNextPoll('PENDING');
        }
    }

    // Reflect the opened run's account + spec in the control-bar form so the
    // dashboard shows what was run (and what a Re-run / Run would use).
    _syncFormToRun(run) {
        if (!run) return;
        if (run.testSuite) {
            this.selectedSuite = run.testSuite;
            const su = this._suiteOptions.find(o => o.value === run.testSuite);
            if (su && su.moduleName) this.selectedModule = su.moduleName;
        }
        // Multi-account run: restore chip list, leave single-account fields blank.
        if (run.accountsJson) {
            this.accountMode = 'multi';
            try {
                const accts = JSON.parse(run.accountsJson);
                this.selectedAccounts = accts.map(a => ({
                    id:   a.id   || a.search || '',
                    name: a.fullName || a.search || a.name || '',
                }));
            } catch { /* ignore */ }
            this.selectedAccountId   = null;
            this.selectedAccountName = null;
            return;
        }
        // Single-account run.
        this.accountMode = 'single';
        this._resetMultiAccounts();
        if (run.accountId) {
            this.selectedAccountId   = run.accountId;
            this.selectedAccountName = run.accountName || this.selectedAccountName;
            this._loadContracts(run.accountId);
        }
        if (run.contractId) {
            this.selectedContractId     = run.contractId;
            this.selectedContractNumber = run.contractNumber || null;
            this._loadQuotes(run.contractId);
        }
        if (run.quoteId || run.quoteName) {
            this.selectedQuoteId   = run.quoteId   || null;
            this.selectedQuoteName = run.quoteName || null;
        }
    }

    _resetContract() {
        this.selectedContractId     = null;
        this.selectedContractNumber = null;
        this._contractOptions       = [];
        // A contract reset always invalidates any quote scoped to it.
        this._resetQuote();
    }

    _resetQuote() {
        this.selectedQuoteId   = null;
        this.selectedQuoteName = null;
        this._quoteOptions     = [];
    }

    // Pre-fill the chip picker with the suite's Default_Accounts__c names.
    // Only applied when the list is currently empty (doesn't override manual selections).
    _applyDefaultAccounts() {
        if (this.selectedAccounts.length > 0) return;
        const suite = this.selectedSuiteMeta;
        if (!suite || !suite.defaultAccounts) return;
        const names = suite.defaultAccounts
            .split(/[\n,]/)
            .map(s => s.trim())
            .filter(Boolean)
            .slice(0, MULTI_ACCT_MAX);
        if (names.length > 0) {
            this.selectedAccounts = names.map(name => ({ id: name, name }));
        }
    }

    _resetMultiAccounts() {
        this.selectedAccounts     = [];
        this.multiAcctSearchTerm  = '';
        this.multiAcctResults     = [];
        this.hasSearchedMultiAcct = false;
        this.isSearchingMultiAcct = false;
        this.multiAcctHighlight   = -1;
    }

    // ── Multi-account mode handlers ────────────────────────────────────────────

    handleAccountModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.accountMode) return;
        this.accountMode = mode;
        if (mode === 'single') {
            this._resetMultiAccounts();
        } else {
            // Switching to multi: clear single-account selections, then apply suite defaults
            this.selectedAccountId   = null;
            this.selectedAccountName = null;
            this._resetContract();
            this._contractOptions    = [];
            this._applyDefaultAccounts();
        }
    }

    handleMultiAcctSearchChange(event) {
        this.multiAcctSearchTerm = event.target.value;
        clearTimeout(this._multiAcctSearchTimeout);
        const term = this.multiAcctSearchTerm.trim();
        if (term.length < ACCT_MIN_SEARCH_LEN) {
            this.multiAcctResults     = [];
            this.hasSearchedMultiAcct = false;
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._multiAcctSearchTimeout = setTimeout(() => this._doMultiAcctSearch(term), ACCT_SEARCH_DEBOUNCE_MS);
    }

    handleMultiAcctSelect(event) {
        event.preventDefault();
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        if (!id || this.selectedAccounts.length >= MULTI_ACCT_MAX) return;
        if (this.selectedAccounts.some(a => a.id === id)) return;
        this.selectedAccounts     = [...this.selectedAccounts, { id, name }];
        this.multiAcctSearchTerm  = '';
        this.multiAcctResults     = [];
        this.hasSearchedMultiAcct = false;
        this.multiAcctHighlight   = -1;
    }

    handleRemoveMultiAcct(event) {
        if (this.isRunning) return;
        const id = event.currentTarget.dataset.id;
        this.selectedAccounts = this.selectedAccounts.filter(a => a.id !== id);
    }

    handleMultiAcctFocus() {
        clearTimeout(this._multiAcctBlurTimeout);
        if (this.multiAcctResults.length > 0) this.hasSearchedMultiAcct = true;
    }

    handleMultiAcctBlur() {
        clearTimeout(this._multiAcctBlurTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._multiAcctBlurTimeout = setTimeout(() => {
            this.hasSearchedMultiAcct = false;
            this.multiAcctHighlight   = -1;
        }, ACCT_BLUR_CLOSE_MS);
    }

    async _doMultiAcctSearch(term) {
        this.isSearchingMultiAcct = true;
        try {
            const results = await searchAccounts({ searchTerm: term });
            if (this.multiAcctSearchTerm.trim() === term) {
                this.multiAcctResults     = results || [];
                this.hasSearchedMultiAcct = true;
            }
        } catch {
            if (this.multiAcctSearchTerm.trim() === term) {
                this.multiAcctResults = [];
            }
        } finally {
            if (this.multiAcctSearchTerm.trim() === term) {
                this.isSearchingMultiAcct = false;
            }
        }
    }

    _loadContracts(accountId) {
        if (!accountId) { this._contractOptions = []; return; }
        getContractsForAccount({ accountId })
            .then(opts => {
                this._contractOptions = opts || [];
            })
            .catch(err => {
                console.error('Failed to load contracts:', err);
                this._contractOptions = [];
            });
    }

    _loadQuotes(contractId) {
        if (!contractId) { this._quoteOptions = []; return; }
        getQuotesForContract({ contractId })
            .then(opts => {
                this._quoteOptions = opts || [];
            })
            .catch(err => {
                console.error('Failed to load quotes:', err);
                this._quoteOptions = [];
            });
    }

    _loadSuiteOptions() {
        getSuiteOptions()
            .then(opts => {
                this._suiteOptions = (opts || []).map(o => ({
                    label:                o.label,
                    value:                o.value,
                    moduleName:           o.moduleName || null,
                    description:          o.description || '',
                    allowMultipleAccount: o.allowMultipleAccount ?? false,
                    defaultAccounts:      o.defaultAccounts      || '',
                }));
                // No auto-default: when idle the dropdown shows the "Select Spec"
                // placeholder. selectedSuite is only set when a run is opened/started.
            })
            .catch(err => {
                console.error('Failed to load suite options:', err);
                this._showToast('Error loading suites', toErrorMessage(err), 'error');
            });
    }

    _loadModuleOptions() {
        getModuleOptions()
            .then(opts => {
                this._moduleOptions = (opts || []).map(o => ({
                    label: o.label,
                    value: o.value,
                }));
            })
            .catch(err => {
                console.error('Failed to load module options:', err);
                this._showToast('Error loading modules', toErrorMessage(err), 'error');
            });
    }

    async _loadHistory(silent) {
        if (!silent) this.isLoadingHistory = true;
        try {
            const runs = await getRecentTestRuns({ limitCount: RECENT_RUNS_LIMIT });
            this.recentRuns = runs.map(decorateRun);

            // Auto-load the most recent run on initial page load (when nothing is selected)
            if (!this.activeRunId && this.recentRuns.length > 0) {
                const latest = this.recentRuns[0];
                this.activeRunId        = latest.id;
                this.activeSidebarRunId = latest.id;
                this.activeRun          = latest;
                this._syncFormToRun(latest);
                this.activeRunFiles    = [];
                this.parsedRichResults = null;
                // Reload full detail (includes richResults) and files
                getTestRun({ testRunId: latest.id })
                    .then(run => {
                        this.activeRun = decorateRun(run);
                        this._parseRichResults(run);
                        this._loadRunFiles(run.id);
                        if (IN_PROGRESS_STATUSES.has(run.status)) {
                            this._startPolling();
                        }
                    })
                    .catch(err => console.error('Auto-load latest run error:', err));
            }
        } catch (err) {
            if (!silent) this._showToast('Error loading history', toErrorMessage(err), 'error');
        } finally {
            if (!silent) this.isLoadingHistory = false;
        }
    }

    _loadRunFiles(runId) {
        this.videoLoadError = false;     // reset media error state for the new run (#29)
        this.showVideoModal = false;
        getTestRunFiles({ testRunId: runId })
            .then(files => {
                this.activeRunFiles = files || [];
                if (this.activeRunImages.length > 0) this.activeTab = 'screenshots';

                // ── Fallback for orgs where Rich_Results__c / Log_Output__c fields
                //    don't exist: read textContentB64 returned inline by Apex (base64).
                //    This avoids CSP/fetch issues — Apex serves the content directly.
                const richFile = (files || []).find(f => f.title === 'rich-results.json');
                const logFile  = (files || []).find(f => f.title === 'log-output.txt');

                if (richFile && richFile.textContentB64 && !this.parsedRichResults) {
                    try {
                        this.parsedRichResults = JSON.parse(decodeBase64Utf8(richFile.textContentB64));
                        this._selectMostRelevantTab();
                    } catch (e) {
                        console.warn('[agenticQtcTestDashboard] rich-results.json parse failed:', e);
                    }
                }

                if (logFile && logFile.textContentB64 && !this._logFromFile) {
                    try {
                        this._logFromFile = decodeBase64Utf8(logFile.textContentB64);
                    } catch (e) {
                        console.warn('[agenticQtcTestDashboard] log-output.txt decode failed:', e);
                    }
                }
            })
            .catch(err => console.error('Error loading run files:', err));
    }

    _parseRichResults(run) {
        if (!run || !run.richResults) {
            this.parsedRichResults = null;
            // Don't clear _logFromFile here — it may still be fetching
            return;
        }
        try {
            this.parsedRichResults = JSON.parse(run.richResults);
        } catch (e) {
            console.warn('Could not parse richResults:', e);
            this.parsedRichResults = null;
        }
        if (this.parsedRichResults) this._selectMostRelevantTab();
    }

    // Pick the first tab that actually has content (mirrors the tab-bar order) (#32)
    _selectMostRelevantTab() {
        if (this.activeRunImages.length > 0)                  this.activeTab = 'screenshots';
        else if (this.hasMismatchRows)                        this.activeTab = 'crosscheck';
        else if (this.hasRichDbValues)                        this.activeTab = 'db';
        else if (this.hasRichMetrics || this.hasRichLineRows) this.activeTab = 'metrics';
        else if (this.hasOsaComparison)                       this.activeTab = 'osa';
        else if (this.hasRichAnomalies)                       this.activeTab = 'anomalies';
        else if (this.hasTestResults)                         this.activeTab = 'spec';
        else if (this.hasLogOutput)                           this.activeTab = 'log';
    }

    // Build the memoized view of all parsedRichResults-derived arrays (#31)
    _buildRichView(rich) {
        if (!rich) {
            return { dbRows: [], lineRows: [], anomalyRows: [], mismatchRows: [], mismatchCount: 0, hasDbValues: false, osaRows: [] };
        }

        // DB comparison rows
        const dbRows = (rich.dbComparison || []).map(row => ({
            ...row,
            keyId:        'db-' + row.index,
            custPriceFmt: formatCurrency(row.dbPrice),
            netTotalFmt:  formatCurrency(row.dbNetTotal),
            discountFmt:  row.dbDiscount != null ? row.dbDiscount + '%' : '—',
            priorQtyFmt:  row.priorQty   != null ? String(row.priorQty) : '—',
            segIndexFmt:  row.segIndex   != null ? String(row.segIndex) : '—',
            isBundleBool: !!row.isBundle,
        }));
        const hasDbValues = dbRows.some(row =>
            row.dbQty != null || row.priorQty != null || row.dbPrice != null ||
            row.dbNetTotal != null || row.dbDiscount != null || row.segIndex != null);

        // Line quantity assertions
        const delta = rich.deltaApplied || DEFAULT_QTY_DELTA;
        const lineRows = (rich.lineResults || []).map(line => ({
            ...line,
            keyId:      'line-' + line.index,
            rowClass:   line.pass ? '' : 'rich-row-fail',
            statusText: line.pass ? '✅' : '❌',
            deltaStr:   '+' + delta,
        }));

        // Anomalies
        const anomalyRows = (rich.dbAnomalies || []).map((anomaly, index) => ({
            ...anomaly,
            keyId:      'anom-' + index,
            badgeClass: 'severity-badge severity-' + (anomaly.severity || 'low').toLowerCase(),
        }));

        // UI ↔ DB cross-check (product-keyed preferred, sequential fallback)
        const mismatchRows  = buildMismatchRows(rich);
        const mismatchCount = rich.crossCheckMismatches != null
            ? rich.crossCheckMismatches
            : mismatchRows.filter(row => !row.match && row.hasData).length;

        // OSA datatable UI↔Backend comparison rows
        const osaRows = (rich.osaComparison || []).map(row => ({
            ...row,
            statusIcon: row.match ? '✅' : '❌',
        }));

        return { dbRows, lineRows, anomalyRows, mismatchRows, mismatchCount, hasDbValues, osaRows };
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

// ── pure utilities (no `this` dependency) ────────────────────────────────────

/**
 * Build the UI↔DB cross-check rows. Prefers the pre-built, product-keyed
 * `uiDbCrossCheck` from the spec; falls back to a sequential index join for
 * results produced by an older spec run.
 */
function buildMismatchRows(rich) {
    const prebuilt = rich.uiDbCrossCheck;
    if (prebuilt && prebuilt.length > 0) {
        return prebuilt.map(row => ({
            keyId:      'mx-' + row.uiIndex,
            idx:        row.uiIndex,
            product:    row.product || '—',
            segOcc:     row.segOcc  != null ? row.segOcc : '',
            uiBefore:   row.uiBefore != null ? row.uiBefore : '—',
            uiAfter:    row.uiAfter  != null ? row.uiAfter  : '—',
            dbPrior:    row.dbPrior  != null ? row.dbPrior  : '—',
            dbAfter:    row.dbAfter  != null ? row.dbAfter  : '—',
            costBefore: row.costBefore != null ? row.costBefore : '—',
            costAfter:  row.costAfter  != null ? row.costAfter  : '—',
            match:      row.match,
            hasData:    row.hasData,
            rowClass:   !row.hasData ? '' : row.match ? 'mx-row-ok' : 'mx-row-fail',
            statusIcon: !row.hasData ? '—' : row.match ? '✅' : '❌ MISMATCH',
        }));
    }

    // Legacy fallback: join UI lines to DB rows by sequential index.
    const lines = rich.lineResults  || [];
    const dbs   = rich.dbComparison || [];
    const dbByIndex = {};
    dbs.forEach(db => { dbByIndex[db.index] = db; });
    return lines.map(line => {
        const db      = dbByIndex[line.index] || {};
        const uiQty   = line.actual != null ? line.actual : null;
        const dbQty   = db.dbQty    != null ? db.dbQty    : null;
        const match   = uiQty != null && dbQty != null && uiQty === dbQty;
        const hasData = uiQty != null || dbQty != null;
        return {
            keyId:      'mx-' + line.index,
            idx:        line.index,
            product:    db.product || line.label || '—',
            segOcc:     '',
            uiBefore:   line.before != null ? line.before : '—',
            uiAfter:    uiQty != null ? uiQty : '—',
            dbPrior:    db.priorQty != null ? db.priorQty : '—',
            dbAfter:    dbQty != null ? dbQty : '—',
            costBefore: line.costBefore != null ? line.costBefore : '—',
            costAfter:  line.costAfter  != null ? line.costAfter  : '—',
            match, hasData,
            rowClass:   !hasData ? '' : match ? 'mx-row-ok' : 'mx-row-fail',
            statusIcon: !hasData ? '—' : match ? '✅' : '❌ MISMATCH',
        };
    });
}

function decorateRun(run) {
    const decorated = Object.assign({}, run);
    decorated.statusClass        = statusBadgeCssClass(run.status);
    decorated.durationDisplay    = formatDurationMs(run.durationMs);
    decorated.createdDateDisplay = run.createdDate ? formatLocalTimestamp(run.createdDate) : '—';
    decorated.startedAtDisplay   = run.startedAt   ? formatLocalTimestamp(run.startedAt)   : '—';
    decorated.completedAtDisplay = run.completedAt ? formatLocalTimestamp(run.completedAt) : '—';
    decorated.rowClass = (run.status === 'FAILED' || run.status === 'ERROR')
        ? 'slds-has-error row-error'
        : IN_PROGRESS_STATUSES.has(run.status) ? 'row-live' : '';

    if (run.testResults && run.testResults.length) {
        decorated.testResults = run.testResults.map(result => ({
            ...result,
            statusClass:     statusBadgeCssClass(result.status),
            durationDisplay: formatDurationMs(result.durationMs),
            rowClass:        result.status === 'FAILED' ? 'tr-row-failed' : '',
            hasError:        !!result.errorMessage,
        }));
    }
    return decorated;
}

function statusBadgeCssClass(status) {
    switch (status) {
        case 'PASSED':  return 'status-badge status-passed';
        case 'FAILED':  return 'status-badge status-failed';
        case 'SKIPPED': return 'status-badge status-skipped';
        case 'RUNNING': return 'status-badge status-running';
        case 'PENDING': return 'status-badge status-pending';
        case 'CLAIMED': return 'status-badge status-running';
        case 'ERROR':   return 'status-badge status-error';
        default:        return 'status-badge';
    }
}

// 'green' | 'yellow' | 'red' for a pass-rate percentage
function passRateTone(percent) {
    if (percent >= PASS_RATE_GREEN_PCT) return 'green';
    if (percent >= PASS_RATE_WARN_PCT)  return 'yellow';
    return 'red';
}

function formatDurationMs(ms) {
    if (ms == null) return '—';
    if (ms < 1000)  return `${ms}ms`;
    const totalSec = ms / 1000;
    if (totalSec < 60) return `${totalSec.toFixed(1)}s`;
    const mins = Math.floor(totalSec / 60);
    const secs = Math.round(totalSec % 60);
    return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
}

/**
 * Format a date/datetime string in the browser's local timezone.
 * Shows e.g. "5/14/26, 2:34 PM PDT".
 */
function formatLocalTimestamp(iso) {
    if (!iso) return '—';
    try {
        return new Date(iso).toLocaleString(undefined, {
            month: 'numeric', day: 'numeric', year: '2-digit',
            hour: 'numeric', minute: '2-digit', hour12: true, timeZoneName: 'short',
        });
    } catch (e) {
        return new Date(iso).toLocaleString();
    }
}

function formatCurrency(value) {
    if (value == null) return '—';
    return '$' + Number(value).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function toErrorMessage(err) {
    return err?.body?.message || err?.message || 'Unknown error';
}

/**
 * Decode a base64 string as UTF-8. atob() alone yields a Latin-1 byte string,
 * which mangles multi-byte characters (·, ≠, →, accented letters) into mojibake.
 */
function decodeBase64Utf8(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new TextDecoder('utf-8').decode(bytes);
}