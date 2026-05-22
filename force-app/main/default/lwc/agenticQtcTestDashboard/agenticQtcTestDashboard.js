import { LightningElement, track } from 'lwc';
import createTestRun        from '@salesforce/apex/AgenticQTC_TestRunnerController.createTestRun';
import getTestRun           from '@salesforce/apex/AgenticQTC_TestRunnerController.getTestRun';
import getRecentTestRuns    from '@salesforce/apex/AgenticQTC_TestRunnerController.getRecentTestRuns';
import cancelTestRun        from '@salesforce/apex/AgenticQTC_TestRunnerController.cancelTestRun';
import getTestRunFiles      from '@salesforce/apex/AgenticQTC_TestRunnerController.getTestRunFiles';
import { ShowToastEvent }   from 'lightning/platformShowToastEvent';

const POLL_INTERVAL_MS        = 1500;   // fast poll while a run is active
const IDLE_POLL_INTERVAL_MS   = 3000;   // slower when nothing is running
const IN_PROGRESS_STATUSES    = new Set(['PENDING', 'CLAIMED', 'RUNNING']);
const MAX_POLL_MS             = 22 * 60 * 1000;

const SUITE_OPTIONS = [
    { label: 'Quantity Increase (Full Flow)',         value: 'agenticQtcQuantityIncrease' },
    { label: 'Quantity Decrease (Full Flow)',         value: 'agenticQtcQuantityDecrease' },
    { label: 'Quantity Increase — MDQ Segments',      value: 'agenticQtcQuantityIncreaseSegments' },
    { label: 'Quantity Decrease — MDQ Segments',      value: 'agenticQtcQuantityDecreaseSegments' },
    { label: 'Start Date Change',                     value: 'agenticQtcStartDateChange' },
    { label: 'Start Date Boundary Rejection',         value: 'agenticQtcStartDateBoundary' },
    { label: 'Contact Update (Invoicing & Delivery)', value: 'agenticQtcContactUpdate' },
    { label: 'Preview & Send OSA Wizard',             value: 'agenticQtcPreviewSendOsa' },
    { label: 'PDF Generation Demo',                   value: 'demoPdfGeneration' },
];

const RUNNER_OPTIONS = [
    { label: '☁️ GitHub', value: 'github', title: 'Run on GitHub Actions (cloud, headless)' },
    { label: '🖥 Local',  value: 'local',  title: 'Run on local agent (this machine)' },
];

export default class AgenticQtcTestDashboard extends LightningElement {

    // ── reactive state ──────────────────────────────────────────────────────

    @track selectedSuite      = SUITE_OPTIONS[0].value;
    @track selectedRunner     = 'github';
    @track activeRunId        = null;
    @track activeRun          = null;
    @track recentRuns         = [];
    @track isLoadingHistory   = false;
    @track isCreating         = false;      // true between click and createTestRun resolving
    @track isStuck            = false;
    @track isDarkMode         = true;
    @track activeRunFiles       = [];       // AttachmentWrapper[]
    @track parsedRichResults    = null;     // parsed richResults JSON
    @track _logFromFile         = null;     // log text fetched from log-output.txt ContentVersion
    @track showLogOutput        = false;
    @track lightboxIndex        = null;     // null = closed, number = open
    @track activeTab            = 'screenshots';
    @track activeSidebarRunId   = null;

    // placeholder row id used while createTestRun is in-flight
    _placeholderId = '__creating__';

    _pollTimer     = null;
    _pollStartTime = null;

    // ── lifecycle ───────────────────────────────────────────────────────────

    connectedCallback() {
        try {
            const saved = localStorage.getItem('agenticqtc_dark_mode');
            if (saved === 'false') this.isDarkMode = false;
        } catch (e) { /* localStorage unavailable */ }
        this._loadHistory();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ── computed getters: layout ────────────────────────────────────────────

    get suiteOptions()       { return SUITE_OPTIONS; }

    get runnerOptions() {
        return RUNNER_OPTIONS.map(r => ({
            ...r,
            btnClass: this.selectedRunner === r.value ? 'runner-btn runner-btn-active' : 'runner-btn',
        }));
    }
    get isGitHubRunner() { return this.selectedRunner === 'github'; }
    get isLocalRunner()  { return this.selectedRunner === 'local'; }

    get containerClass() {
        return `runner-container ${this.isDarkMode ? 'dark-theme' : 'light-theme'}`;
    }

    get themeLabel()         { return this.isDarkMode ? 'Light Mode' : 'Dark Mode'; }

    get isRunning() {
        return this.activeRunId &&
               this.activeRun &&
               IN_PROGRESS_STATUSES.has(this.activeRun.status);
    }

    get runBtnClass()        { return (this.isRunning || this.isCreating) ? 'btn btn-run running' : 'btn btn-run'; }
    get runButtonLabel() {
        if (this.isCreating) return 'Creating…';
        if (this.isRunning)  return 'Running…';
        return this.selectedRunner === 'github' ? 'Run on GitHub' : 'Run Local';
    }
    get runButtonDisabled()  { return this.isRunning || this.isCreating || !this.selectedSuite; }

    get cancelButtonDisabled() {
        return !this.activeRun || this.activeRun.status !== 'PENDING';
    }

    get waitingForAgent() {
        return this.activeRun && this.activeRun.status === 'PENDING' && !this.isStuck;
    }

    get showStuckWarning()   { return this.isStuck; }

    get hasTestResults() {
        return this.activeRun &&
               this.activeRun.testResults &&
               this.activeRun.testResults.length > 0;
    }

    get hasHistory()         { return this.recentRuns.length > 0; }

    get durationDisplay() {
        return this.activeRun ? _fmtMs(this.activeRun.durationMs) : '—';
    }

    get activeRunCardClass() {
        const base = 'active-run-card';
        if (!this.activeRun) return base;
        if (this.activeRun.status === 'PASSED')  return base + ' card-passed';
        if (this.activeRun.status === 'FAILED')  return base + ' card-failed';
        if (this.activeRun.status === 'ERROR')   return base + ' card-error';
        return base + ' card-running';
    }

    get statusBadgeClass()   { return _statusBadgeClass(this.activeRun?.status); }

    // ── computed getters: screenshots ───────────────────────────────────────

    get activeRunImages() {
        return this.activeRunFiles
            .filter(f => /^(PNG|JPG|JPEG)$/i.test(f.fileType || ''))
            .sort((a, b) => (a.title || '').localeCompare(b.title || ''));
    }

    get hasImages()          { return this.activeRunImages.length > 0; }

    // ── computed getters: video ─────────────────────────────────────────────

    get activeRunVideo() {
        // Salesforce assigns FileType='UNKNOWN' for .webm — use fileExtension first
        // (now exposed by Apex), then fall back to title scan
        return this.activeRunFiles.find(f =>
            /^(webm|mp4)$/i.test(f.fileExtension || '') ||
            /^(WEBM|MP4)$/i.test(f.fileType     || '') ||
            /\.(webm|mp4)$/i.test(f.title        || '')
        ) || null;
    }

    get hasVideo() { return this.activeRunVideo !== null; }

    get videoSrc() {
        return this.activeRunVideo ? this.activeRunVideo.downloadUrl : '';
    }

    get videoSizeMb() {
        // title is "video-<runId>.webm" — size not stored, just label it
        return this.activeRunVideo ? this.activeRunVideo.title : '';
    }

    // ── computed getters: lightbox ──────────────────────────────────────────

    get lightboxOpen()    { return this.lightboxIndex !== null; }
    get lightboxImage()   {
        if (this.lightboxIndex === null) return null;
        return this.activeRunImages[this.lightboxIndex] || null;
    }
    get lightboxSrc()     { return this.lightboxImage ? this.lightboxImage.downloadUrl : ''; }
    get lightboxTitle()   { return this.lightboxImage ? this.lightboxImage.title : ''; }
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

    get hasRichResults()     { return this.parsedRichResults != null; }
    get hasRichLineRows()    { return this.richLineRows.length > 0; }
    get hasRichDbRows()      { return this.richDbRows.length > 0; }
    get hasRichAnomalies()   { return this.richAnomalyRows.length > 0; }
    get hasRichMetrics()     { return !!(this.parsedRichResults && this.parsedRichResults.metricsBeforeSave); }

    get richSummaryKpis() {
        if (!this.parsedRichResults) return [];
        const r = this.parsedRichResults;
        const qtyMatch = r.uiQtyTotal != null && r.dbQtyTotal != null &&
                         Math.abs(r.uiQtyTotal - r.dbQtyTotal) < 0.01;
        return [
            { id: 'contract',  label: 'Contract',     value: r.contract  || '—',                      valClass: 'rich-kpi-val rich-kpi-blue' },
            { id: 'quote',     label: 'Quote',        value: r.quoteName || '—',                      valClass: 'rich-kpi-val rich-kpi-mono' },
            { id: 'lines',     label: 'Lines',        value: String(r.spinbuttonCount || 0),           valClass: 'rich-kpi-val' },
            { id: 'dblines',   label: 'DB Lines',     value: String(r.dbLineCount    || 0),           valClass: 'rich-kpi-val' },
            { id: 'uiqty',     label: 'UI Qty Total', value: r.uiQtyTotal != null ? String(r.uiQtyTotal) : '—', valClass: 'rich-kpi-val' },
            { id: 'dbqty',     label: 'DB Qty Total', value: r.dbQtyTotal != null ? String(r.dbQtyTotal) : '—', valClass: qtyMatch ? 'rich-kpi-val rich-kpi-green' : 'rich-kpi-val rich-kpi-red' },
            { id: 'anomalies', label: 'Anomalies',    value: String(r.dbAnomalyCount || 0),           valClass: (r.dbAnomalyCount || 0) > 0 ? 'rich-kpi-val rich-kpi-warn' : 'rich-kpi-val rich-kpi-green' },
            { id: 'high',      label: 'HIGH Sev.',    value: String(r.dbHighCount    || 0),           valClass: (r.dbHighCount    || 0) > 0 ? 'rich-kpi-val rich-kpi-red'  : 'rich-kpi-val rich-kpi-green' },
            { id: 'approval',  label: 'Approval Req', value: r.hasApproval ? '⚠️ Yes' : '✅ No',      valClass: 'rich-kpi-val' },
            { id: 'pdf',       label: 'PDF',          value: r.pdfSkipped ? 'Skipped' : (r.pdfGenerated ? '✅ Yes' : '❌ No'), valClass: 'rich-kpi-val' },
        ];
    }

    get richMetrics() {
        if (!this.parsedRichResults) return [];
        const b = this.parsedRichResults.metricsBeforeSave || {};
        const a = this.parsedRichResults.metricsAfterSave  || {};
        return [
            { id: 'ACV',   label: 'ACV',          before: b.acv         || '—', after: a.acv         || '—' },
            { id: 'ACVCh', label: 'ACV Change',   before: b.acvChange   || '—', after: a.acvChange   || '—' },
            { id: 'TCV',   label: 'TCV',          before: b.tcv         || '—', after: a.tcv         || '—' },
            { id: 'YoY',   label: 'YoY Uplift',   before: b.yoyUplift   || '—', after: a.yoyUplift   || '—' },
            { id: 'DQS',   label: 'Deal Quality', before: b.dealQuality || '—', after: a.dealQuality || '—' },
        ];
    }

    get richLineRows() {
        if (!this.parsedRichResults || !this.parsedRichResults.lineResults) return [];
        const delta = this.parsedRichResults.deltaApplied || 5;
        return this.parsedRichResults.lineResults.map(r => ({
            ...r,
            keyId:      'line-' + r.index,
            rowClass:   r.pass ? '' : 'rich-row-fail',
            statusText: r.pass ? '✅' : '❌',
            deltaStr:   '+' + delta,
        }));
    }

    get richDbRows() {
        if (!this.parsedRichResults || !this.parsedRichResults.dbComparison) return [];
        return this.parsedRichResults.dbComparison.map(r => ({
            ...r,
            keyId:        'db-'  + r.index,
            custPriceFmt: _fmtCurrency(r.dbPrice),
            netTotalFmt:  _fmtCurrency(r.dbNetTotal),
            discountFmt:  r.dbDiscount != null ? (r.dbDiscount + '%') : '—',
            priorQtyFmt:  r.priorQty   != null ? String(r.priorQty)  : '—',
            segIndexFmt:  r.segIndex   != null ? String(r.segIndex)  : '—',
            isBundleBool: !!r.isBundle,
        }));
    }

    get richAnomalyRows() {
        if (!this.parsedRichResults || !this.parsedRichResults.dbAnomalies) return [];
        return this.parsedRichResults.dbAnomalies.map((a, i) => ({
            ...a,
            keyId:      'anom-' + i,
            badgeClass: 'severity-badge severity-' + (a.severity || 'low').toLowerCase(),
        }));
    }

    // ── UI ↔ DB cross-check ─────────────────────────────────────────────────
    // Prefer the pre-built uiDbCrossCheck (product-keyed join from spec).
    // Falls back to the old sequential-index join only if the field is absent
    // (e.g. results produced by an older spec run).

    get richMismatchRows() {
        if (!this.parsedRichResults) return [];

        // ── New path: product-keyed cross-check (correct) ──────────────────
        const prebuilt = this.parsedRichResults.uiDbCrossCheck;
        if (prebuilt && prebuilt.length > 0) {
            return prebuilt.map(r => ({
                keyId:      'mx-' + r.uiIndex,
                idx:        r.uiIndex,
                product:    r.product || '—',
                segOcc:     r.segOcc  != null ? r.segOcc : '',
                uiBefore:   r.uiBefore  != null ? r.uiBefore  : '—',
                uiAfter:    r.uiAfter   != null ? r.uiAfter   : '—',
                dbPrior:    r.dbPrior   != null ? r.dbPrior   : '—',
                dbAfter:    r.dbAfter   != null ? r.dbAfter   : '—',
                match:      r.match,
                hasData:    r.hasData,
                rowClass:   !r.hasData ? '' : r.match ? 'mx-row-ok' : 'mx-row-fail',
                statusIcon: !r.hasData ? '—' : r.match ? '✅' : '❌ MISMATCH',
            }));
        }

        // ── Legacy fallback: sequential index join ──────────────────────────
        const lines = this.parsedRichResults.lineResults   || [];
        const dbs   = this.parsedRichResults.dbComparison || [];
        const dbMap = {};
        dbs.forEach(d => { dbMap[d.index] = d; });
        return lines.map(l => {
            const db      = dbMap[l.index] || {};
            const uiQty   = l.actual  != null ? l.actual  : null;
            const dbQty   = db.dbQty  != null ? db.dbQty  : null;
            const match   = uiQty != null && dbQty != null && uiQty === dbQty;
            const hasData = uiQty != null || dbQty != null;
            return {
                keyId:      'mx-' + l.index,
                idx:        l.index,
                product:    db.product || l.label || '—',
                segOcc:     '',
                uiBefore:   l.before != null ? l.before : '—',
                uiAfter:    uiQty    != null ? uiQty    : '—',
                dbPrior:    db.priorQty != null ? db.priorQty : '—',
                dbAfter:    dbQty    != null ? dbQty    : '—',
                match, hasData,
                rowClass:   !hasData ? '' : match ? 'mx-row-ok' : 'mx-row-fail',
                statusIcon: !hasData ? '—' : match ? '✅' : '❌ MISMATCH',
            };
        });
    }

    get hasMismatchRows()  { return this.richMismatchRows.length > 0; }
    get mismatchCount() {
        // Use pre-computed count from spec when available (product-keyed, accurate)
        if (this.parsedRichResults && this.parsedRichResults.crossCheckMismatches != null) {
            return this.parsedRichResults.crossCheckMismatches;
        }
        return this.richMismatchRows.filter(r => !r.match && r.hasData).length;
    }
    get allMismatchMatch() { return this.mismatchCount === 0 && this.richMismatchRows.length > 0; }

    // ── Qty assertion summary (from lineResults, separate from Playwright spec count) ──
    get richQtySummary() {
        if (!this.parsedRichResults || !this.parsedRichResults.lineResults) return null;
        const lines   = this.parsedRichResults.lineResults;
        const pass    = lines.filter(l => l.pass).length;
        const fail    = lines.filter(l => !l.pass).length;
        return { pass, fail, total: lines.length, allPass: fail === 0 };
    }
    get hasRichQtySummary() { return this.richQtySummary !== null; }

    // ── Tab bar ─────────────────────────────────────────────────────────────

    get tabs() {
        const images    = this.activeRunImages.length;
        const mismatch  = this.mismatchCount;
        const allMatch  = this.allMismatchMatch;
        const dbCount   = this.richDbRows.length;
        const anomCount = this.richAnomalyRows.length;
        const def = (id, label, icon, badge, badgeOk) => ({
            id, label, icon,
            badge: badge != null ? String(badge) : null,
            badgeClass: badgeOk === false ? 'tab-badge tab-badge-fail'
                      : badgeOk === true  ? 'tab-badge tab-badge-ok'
                      : 'tab-badge',
            btnClass: this.activeTab === id ? 'tab-btn tab-btn-active' : 'tab-btn',
        });
        return [
            def('screenshots', 'Screenshots', '📸', images || null, null),
            def('crosscheck',  'UI↔DB',       '🔀',
                this.hasMismatchRows ? (allMatch ? '✅' : mismatch + '❌') : null,
                this.hasMismatchRows ? allMatch : null),
            def('db',        'DB Lines',  '🗄',  dbCount   || null, null),
            def('metrics',   'Metrics',   '💰',  null, null),
            def('anomalies', 'Anomalies', '⚠️', anomCount || null, anomCount === 0 ? true : false),
            def('spec',      'Spec',      '🎭',  null, null),
            def('log',       'Log',       '📋',  null, null),
        ];
    }

    get activeTabIsScreenshots() { return this.activeTab === 'screenshots'; }
    get activeTabIsCrosscheck()  { return this.activeTab === 'crosscheck'; }
    get activeTabIsDb()          { return this.activeTab === 'db'; }
    get activeTabIsMetrics()     { return this.activeTab === 'metrics'; }
    get activeTabIsAnomalies()   { return this.activeTab === 'anomalies'; }
    get activeTabIsSpec()        { return this.activeTab === 'spec'; }
    get activeTabIsLog()         { return this.activeTab === 'log'; }

    get runPassRate() {
        const done = (this.recentRuns || [])
            .filter(r => r.status === 'PASSED' || r.status === 'FAILED').slice(0, 10);
        if (!done.length) return { percent: 0, passed: 0, total: 0, label: '—' };
        const passed  = done.filter(r => r.status === 'PASSED').length;
        const percent = Math.round((passed / done.length) * 100);
        return { percent, passed, total: done.length, label: `${passed}/${done.length}` };
    }
    get passRateBarStyle() { return `width: ${this.runPassRate.percent}%`; }
    get passRateClass() {
        const p = this.runPassRate.percent;
        return p >= 80 ? 'pass-rate-fill pass-rate-green'
             : p >= 50 ? 'pass-rate-fill pass-rate-yellow'
             : 'pass-rate-fill pass-rate-red';
    }

    get sidebarRuns() {
        const dotMap = {
            PASSED:  'hi-dot hi-dot-pass',
            FAILED:  'hi-dot hi-dot-fail',
            ERROR:   'hi-dot hi-dot-fail',
            RUNNING: 'hi-dot hi-dot-running',
            PENDING: 'hi-dot hi-dot-pending',
            CLAIMED: 'hi-dot hi-dot-running',
        };
        return (this.recentRuns || []).map(r => ({
            ...r,
            dotClass: dotMap[r.status] || 'hi-dot',
            historyItemClass: [
                'history-item',
                r.id === this.activeSidebarRunId ? 'history-item-active' : '',
                (r.status === 'FAILED' || r.status === 'ERROR') ? 'history-item-fail' : '',
                r.status === 'PASSED' ? 'history-item-pass' : '',
                (r.status === 'PENDING' || r.status === 'RUNNING' || r.status === 'CLAIMED')
                    ? 'history-item-live' : '',
            ].filter(Boolean).join(' '),
        }));
    }

    get metricStripItems() {
        const r  = this.parsedRichResults;
        const ar = this.activeRun;
        if (!ar) return [];
        const items = [];
        if (r && r.lineResults && r.lineResults.length > 0) {
            const qs = this.richQtySummary;
            items.push({ id: 'qty', label: 'Qty Checks',
                value: `${qs.pass}✅${qs.fail > 0 ? '  ' + qs.fail + '❌' : ''}`,
                valueClass: qs.fail > 0 ? 'ms-val ms-val-fail' : 'ms-val ms-val-ok' });
        }
        items.push({ id: 'spec', label: 'Spec Result',
            value: ar.testsPassed != null
                ? `${ar.testsPassed}✅  ${ar.testsFailed || 0}❌`
                : (ar.status || '—'),
            valueClass: (ar.testsFailed > 0) ? 'ms-val ms-val-fail' : 'ms-val ms-val-ok' });
        items.push({ id: 'dur', label: 'Duration',
            value: this.durationDisplay, valueClass: 'ms-val ms-val-mono' });
        if (!r) return items;
        if (r.dbAnomalyCount != null)
            items.push({ id: 'anom', label: 'Anomalies',
                value: String(r.dbAnomalyCount),
                valueClass: r.dbAnomalyCount > 0 ? 'ms-val ms-val-warn' : 'ms-val ms-val-ok' });
        if (r.dbLineCount != null)
            items.push({ id: 'db',  label: 'DB Lines',  value: String(r.dbLineCount), valueClass: 'ms-val' });
        if (r.quoteName)
            items.push({ id: 'q',   label: 'Quote',     value: r.quoteName, valueClass: 'ms-val ms-val-mono' });
        if (r.contract)
            items.push({ id: 'ct',  label: 'Contract',  value: r.contract,  valueClass: 'ms-val' });
        return items;
    }
    get hasMetricStrip() { return this.metricStripItems.length > 0; }

    // Timestamps for the active run card
    get activeRunStartedAt()   { return this.activeRun ? (this.activeRun.startedAtDisplay   || '—') : '—'; }
    get activeRunCompletedAt() { return this.activeRun ? (this.activeRun.completedAtDisplay || '—') : '—'; }
    get activeRunCreatedAt()   { return this.activeRun ? (this.activeRun.createdDateDisplay || '—') : '—'; }

    get hasLogOutput()  { return !!(this.activeRun && (this.activeRun.logOutput || this._logFromFile)); }
    get logOutputText() { return (this.activeRun && this.activeRun.logOutput) || this._logFromFile || ''; }
    get showLogLabel()  { return this.showLogOutput ? 'Hide Log' : 'Show Log'; }

    // ── event handlers ──────────────────────────────────────────────────────

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab) this.activeTab = tab;
    }

    handleSuiteChange(event) {
        this.selectedSuite = event.target.value;
    }

    handleRunnerChange(event) {
        const runner = event.currentTarget.dataset.runner;
        if (runner && !this.isRunning) this.selectedRunner = runner;
    }

    handleToggleTheme() {
        this.isDarkMode = !this.isDarkMode;
        try {
            localStorage.setItem('agenticqtc_dark_mode', String(this.isDarkMode));
        } catch (e) { /* localStorage unavailable */ }
    }

    handleToggleLog() {
        this.showLogOutput = !this.showLogOutput;
    }

    // ── lightbox handlers ────────────────────────────────────────────────────

    handleImageClick(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.lightboxIndex = isNaN(idx) ? 0 : idx;
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
    }

    handleOverlayClick(event) {
        // close only when clicking the backdrop (not the image itself)
        if (event.target === event.currentTarget) this.lightboxIndex = null;
    }

    async handleRunTests() {
        if (this.isRunning || this.isCreating) return;

        // ── Step 1: instant feedback — spinner on button + placeholder row ──
        this.isCreating        = true;
        this.activeRunFiles    = [];
        this.parsedRichResults = null;
        this._logFromFile      = null;
        this.showLogOutput     = false;
        this.lightboxIndex     = null;

        const suiteLabel = (SUITE_OPTIONS.find(s => s.value === this.selectedSuite) || {}).label || this.selectedSuite;
        const placeholder = {
            id:             this._placeholderId,
            name:           '…',
            status:         this.selectedRunner === 'github' ? 'CLAIMED' : 'PENDING',
            testSuite:      suiteLabel,
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
            const runId = await createTestRun({ testSuite: this.selectedSuite, runner: this.selectedRunner });
            this.activeRunId        = runId;
            this.activeSidebarRunId = runId;
            this.isCreating  = false;

            // ── Step 3: fetch real record, swap out placeholder ─────────────
            getTestRun({ testRunId: runId })
                .then(run => {
                    const decorated = _decorateRun(run);
                    this.activeRun  = decorated;
                    // Replace placeholder row with the real record
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
            this._showToast('Error', _errMsg(err), 'error');
        }
    }

    async handleCancel() {
        if (!this.activeRunId) return;
        try {
            await cancelTestRun({ testRunId: this.activeRunId });
            this._showToast('Cancelled', 'Test run cancelled.', 'info');
            this._stopPolling();
            this._loadHistory();
        } catch (err) {
            this._showToast('Error', _errMsg(err), 'error');
        }
    }

    handleRefreshHistory() {
        this._loadHistory();
    }

    handleHistoryRowClick(event) {
        const runId = event.currentTarget.dataset.id;
        this.activeSidebarRunId = runId;
        this.activeRunFiles    = [];
        this.parsedRichResults = null;
        this._logFromFile      = null;
        this.showLogOutput     = false;
        getTestRun({ testRunId: runId })
            .then(run => {
                this.activeRunId = run.id;
                this.activeRun   = _decorateRun(run);
                this._parseRichResults(run);
                this._loadRunFiles(run.id);
                if (IN_PROGRESS_STATUSES.has(run.status)) {
                    this._startPolling();
                }
            })
            .catch(err => this._showToast('Error', _errMsg(err), 'error'));
    }

    // ── private helpers ─────────────────────────────────────────────────────

    _startPolling() {
        this._stopPolling();
        this._pollStartTime = Date.now();
        this.isStuck = false;
        this._pollTimer = setInterval(() => this._pollActiveRun(), POLL_INTERVAL_MS);
        this._pollActiveRun();
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async _pollActiveRun() {
        if (!this.activeRunId) { this._stopPolling(); return; }

        if (this._pollStartTime && (Date.now() - this._pollStartTime) > MAX_POLL_MS) {
            this._stopPolling();
            this.isStuck = true;
            return;
        }

        try {
            const run      = await getTestRun({ testRunId: this.activeRunId });
            const decorated = _decorateRun(run);
            this.activeRun  = decorated;
            this._parseRichResults(run);
            this.isStuck    = false;

            // Sync status into the history row in real-time on every tick
            this.recentRuns = this.recentRuns.map(r =>
                r.id === run.id ? decorated : r
            );

            if (!IN_PROGRESS_STATUSES.has(run.status)) {
                this._stopPolling();
                // Load files immediately; refresh full history in background (non-blocking)
                this._loadRunFiles(this.activeRunId);
                this._loadHistory();

                const variant = run.status === 'PASSED' ? 'success' : 'error';
                const msg     = run.status === 'PASSED'
                    ? `${run.testsPassed || 0} passed · ${run.testsFailed || 0} failed`
                    : run.errorMessage || 'Run ended with status: ' + run.status;
                this._showToast('Tests complete', msg, variant);
            }
        } catch (err) {
            console.error('Poll error:', err);
        }
    }

    async _loadHistory() {
        this.isLoadingHistory = true;
        try {
            const runs = await getRecentTestRuns({ limitCount: 20 });
            this.recentRuns = runs.map(_decorateRun);

            // Auto-load the most recent run on initial page load (when no active run is set)
            if (!this.activeRunId && this.recentRuns.length > 0) {
                const latest = this.recentRuns[0];
                this.activeRunId        = latest.id;
                this.activeSidebarRunId = latest.id;
                this.activeRun          = latest;
                this.activeRunFiles    = [];
                this.parsedRichResults = null;
                // Reload full detail (includes richResults) and files
                getTestRun({ testRunId: latest.id })
                    .then(run => {
                        this.activeRun = _decorateRun(run);
                        this._parseRichResults(run);
                        this._loadRunFiles(run.id);
                        if (IN_PROGRESS_STATUSES.has(run.status)) {
                            this._startPolling();
                        }
                    })
                    .catch(err => console.error('Auto-load latest run error:', err));
            }
        } catch (err) {
            this._showToast('Error loading history', _errMsg(err), 'error');
        } finally {
            this.isLoadingHistory = false;
        }
    }

    _loadRunFiles(runId) {
        getTestRunFiles({ testRunId: runId })
            .then(files => {
                this.activeRunFiles = files || [];
                if (this.activeRunImages.length > 0) this.activeTab = 'screenshots';

                // ── Fallback for orgs where Rich_Results__c / Log_Output__c fields
                //    don't exist: read textContentB64 returned inline by Apex (base64-encoded).
                //    This avoids CSP/fetch issues — Apex serves the content directly.
                const richFile = (files || []).find(f => f.title === 'rich-results.json');
                const logFile  = (files || []).find(f => f.title === 'log-output.txt');

                if (richFile && richFile.textContentB64 && !this.parsedRichResults) {
                    try {
                        const json = JSON.parse(atob(richFile.textContentB64));
                        this.parsedRichResults = json;
                        // Re-run tab auto-select now that rich results are available
                        if (this.activeRunImages.length > 0)                    { this.activeTab = 'screenshots'; }
                        else if (this.hasMismatchRows)                          { this.activeTab = 'crosscheck'; }
                        else if (this.hasRichDbRows)                            { this.activeTab = 'db'; }
                        else if (this.hasRichMetrics || this.hasRichLineRows)   { this.activeTab = 'metrics'; }
                        else if (this.hasRichAnomalies)                         { this.activeTab = 'anomalies'; }
                        else if (this.hasTestResults)                           { this.activeTab = 'spec'; }
                        else if (this.hasLogOutput)                             { this.activeTab = 'log'; }
                    } catch (e) {
                        console.warn('[agenticQtcTestDashboard] rich-results.json parse failed:', e);
                    }
                }

                if (logFile && logFile.textContentB64 && !this._logFromFile) {
                    try {
                        this._logFromFile = atob(logFile.textContentB64);
                    } catch (e) {
                        console.warn('[agenticQtcTestDashboard] log-output.txt decode failed:', e);
                    }
                }
            })
            .catch(err  => console.error('Error loading run files:', err));
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
        // Auto-select the most relevant tab after results load
        if (this.parsedRichResults) {
            if (this.activeRunImages.length > 0)                    { this.activeTab = 'screenshots'; }
            else if (this.hasMismatchRows)                          { this.activeTab = 'crosscheck'; }
            else if (this.hasRichDbRows)                            { this.activeTab = 'db'; }
            else if (this.hasRichMetrics || this.hasRichLineRows)   { this.activeTab = 'metrics'; }
            else if (this.hasRichAnomalies)                         { this.activeTab = 'anomalies'; }
            else if (this.hasTestResults)                           { this.activeTab = 'spec'; }
            else if (this.hasLogOutput)                             { this.activeTab = 'log'; }
        }
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

// ── pure utilities (no `this` dependency) ────────────────────────────────────

function _decorateRun(run) {
    const decorated = Object.assign({}, run);
    decorated.statusClass        = _statusBadgeClass(run.status);
    decorated.durationDisplay    = _fmtMs(run.durationMs);
    decorated.createdDateDisplay = run.createdDate  ? _fmtLocalTs(run.createdDate)  : '—';
    decorated.startedAtDisplay   = run.startedAt    ? _fmtLocalTs(run.startedAt)    : '—';
    decorated.completedAtDisplay = run.completedAt  ? _fmtLocalTs(run.completedAt)  : '—';
    const inProgress = IN_PROGRESS_STATUSES.has(run.status);
    decorated.rowClass = run.status === 'FAILED' || run.status === 'ERROR'
        ? 'slds-has-error row-error'
        : inProgress ? 'row-live' : '';

    if (run.testResults && run.testResults.length) {
        decorated.testResults = run.testResults.map(tr => ({
            ...tr,
            statusClass    : _statusBadgeClass(tr.status),
            durationDisplay: _fmtMs(tr.durationMs),
            rowClass       : tr.status === 'FAILED' ? 'tr-row-failed' : '',
            hasError       : !!(tr.errorMessage),
        }));
    }
    return decorated;
}

function _statusBadgeClass(status) {
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

function _fmtMs(ms) {
    if (ms == null) return '—';
    if (ms < 1000)  return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
}

/**
 * Format a date/datetime string in the browser's local timezone.
 * Shows e.g. "5/14/26, 2:34 PM PDT"
 */
function _fmtLocalTs(iso) {
    if (!iso) return '—';
    try {
        return new Date(iso).toLocaleString(undefined, {
            month   : 'numeric',
            day     : 'numeric',
            year    : '2-digit',
            hour    : 'numeric',
            minute  : '2-digit',
            hour12  : true,
            timeZoneName: 'short',
        });
    } catch (e) {
        return new Date(iso).toLocaleString();
    }
}

function _fmtCurrency(v) {
    if (v == null) return '—';
    return '$' + Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function _errMsg(err) {
    return err?.body?.message || err?.message || 'Unknown error';
}