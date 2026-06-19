import { LightningElement, api, track } from 'lwc';
import AgenticQTCAppFormulas from 'c/agenticQTCAppFormulas';
import createAmendmentQuote from '@salesforce/apex/AgenticQTC_AmendContractController.createAmendmentQuote';
import loadExistingDraftQuote from '@salesforce/apex/AgenticQTC_AmendContractController.loadExistingDraftQuote';
import getQuoteLines from '@salesforce/apex/AgenticQTC_AmendContractController.getQuoteLines';
import getQuoteDetails from '@salesforce/apex/AgenticQTC_AmendContractController.getQuoteDetails';
import updateQuoteLineAcvChange from '@salesforce/apex/AgenticQTC_AmendContractController.updateQuoteLineAcvChange';
import updateQuoteSfa from '@salesforce/apex/AgenticQTC_AmendContractController.updateQuoteSfa';
import saveQuoteChanges from '@salesforce/apex/AgenticQTC_AmendContractController.saveQuoteChanges';
import previewApprovals from '@salesforce/apex/AgenticQTC_ApprovalLogicService.previewApprovals';
import submitForApproval from '@salesforce/apex/AgenticQTC_ApprovalLogicService.submitForApproval';
import getAccountContacts from '@salesforce/apex/AgenticQTC_AmendContractController.getAccountContacts';
import searchContacts from '@salesforce/apex/AgenticQTC_AmendContractController.searchContacts';
import getCurrentSegmentInfo from '@salesforce/apex/AgenticQTC_AmendContractController.getCurrentSegmentInfo';
// import evaluateQuoteApproval from '@salesforce/apex/AgenticQTC_ApprovalLogicService.evaluateQuoteApproval'; // VK - imported but never called
// VK: Contract Ops workflow is out of scope for the current release (approval-required
// quotes aren't being handled in this deploy). Re-enable this import along with
// handleContractOps() and the "Contract Ops" button in the template when the
// approval/ops-case workflow comes back into scope.
// import createContractOpsCase from '@salesforce/apex/AgenticQTC_ContractOpsCaseService.createContractOpsCase';
// VK - old service imports (moved to controller):
// import getQuoteLines from '@salesforce/apex/AgenticQTC_QuoteAmendmentService.getQuoteLines';
// import updateQuoteLineAcvChange from '@salesforce/apex/AgenticQTC_QuoteAmendmentService.updateQuoteLineAcvChange';
// import updateQuoteStartDate from '@salesforce/apex/AgenticQTC_QuoteAmendmentService.updateQuoteStartDate';
// import calculateQuote from '@salesforce/apex/AgenticQTC_QuoteAmendmentService.calculateQuote';

export default class AgenticQtcQuoteEditor extends LightningElement {
    @api contractId;
    @api contractNumber;
    @api accountId;
    @api accountName;
    /** When set, the editor reads this existing draft amendment quote (header + lines)
     *  via pure SOQL and renders it directly — no createAmendmentQuote, no progress
     *  crawl. Populated by the OSA selector when the user picks a draft from the
     *  "Existing Draft Quotes" modal. */
    @api existingQuoteId;
    /** Σ NetPrice × Quantity of the contract's subscriptions, pre-aggregated by the
     *  OSA selector's contract list query. Shown as the initial TCV on a *fresh*
     *  amendment (existingQuoteId is null) until the user edits a quantity — see
     *  the totalTcv getter for the switch. Null on the existing-draft path. */
    @api initialSubscriptionTcv;
    /** ISO 4217 currency code from Contract.CurrencyIsoCode — drives every monetary
     *  display in the editor (metric tiles + MDQ term group cells). Falls back to
     *  "USD" when null. */
    @api currencyIsoCode;

    @track quoteId;
    @track quoteName;
    @track quoteStatus = 'Draft';
    @track quoteStartDate;
    @track quoteLines = [];
    @track isLoading = true;
    @track loadingMessage = 'Creating the amendment quote and line items';
    @track isInitialLoading = false;
    @track progressValue = 0;
    @track progressMessage = 'Creating amendment quote…';
    _progressInterval = null;
    @track showAddProduct = false;
    @track showPreviewSend = false;
    @track anyApprovalRequired = false;
    @track approvalCount = 0;
    @track _submittedForApproval = false;
    @track toastMessage = '';
    @track toastVariant = '';

    _pendingQuantityChanges = new Map(); // lineId -> { type: 'single'|'mdq', quantity, segmentKey, applyToAll }
    _initialAcvByLineId = new Map();     // lineId -> ACV at the moment the editor first loaded
    _acvBaselineCaptured = false;
    _lastValidStartDate = null;          // ISO yyyy-mm-dd of the last successfully saved start date
    _initialInvoicingContactId = null;   // Last persisted invoicing contact Id (baseline for Save dirty check)
    _initialSoftwareDeliveryContactId = null; // Last persisted delivery contact Id (baseline for Save dirty check)
    _currentSegmentInfo = null;          // Cached rows from getCurrentSegmentInfo (upgraded subscription dates)
    _currentSegmentInfoLoaded = false;   // True once getCurrentSegmentInfo has run (even if it returned no rows)

    @track invoicingContactId;
    @track invoicingContactName;
    @track invoicingContactEmail;
    @track invoicingContactTitle;
    @track invoicingContactAccountName;
    @track softwareDeliveryContactId;
    @track softwareDeliveryContactName;
    @track softwareDeliveryContactEmail;
    @track softwareDeliveryContactTitle;
    @track softwareDeliveryContactAccountName;
    @track approvalStatus;
    @track dealQualityScore;
    /** Mirrors SBQQ__Quote__c.Min_year_on_year_committed_spend__c.
     *  Source for the YoY Uplift metric tile — recalculated by CPQ on Save and
     *  refreshed via the saveQuoteChanges → getQuoteDetails round-trip. */
    @track minYoyCommittedSpend;
    @track approvalItems = [];
    @track showReasons = false;

    // ─── Contact picker modal ───
    @track showContactPicker = false;
    @track contactPickerType = null;       // 'invoicing' | 'delivery'
    @track contactSearchTerm = '';
    @track availableContacts = [];          // raw rows from getAccountContacts (cap 1000)
    _contactsLoadedForAccountId = null;     // cache key — reload only if account changes
    @track _serverContacts = [];            // results from searchContacts fallback query
    _serverSearchTerm = null;               // term those server results belong to (lowercased)
    _serverSearchTimer = null;              // debounce handle for the fallback query

    // ─── Quote detail fields (read from contract via getQuoteDetails) ───
    @track totalContractMonths;
    @track firstSegmentMonths;
    @track contractDiscount;
    @track billingFrequency;
    @track paymentTerms;
    @track specialTerms = false;

    get hasLines() { return !this.isLoading && this.quoteLines.length > 0; }

    // True when something on the UI differs from the last persisted state:
    // pending quantity edits, start-date moved off the saved value, or either
    // contact swapped. Single source of truth for both the Save button (enabled
    // while dirty) and the Submit-for-Approval gate (blocked while dirty), so a
    // quote can't be sent for approval with unsaved changes (BIZ-83431).
    get hasUnsavedChanges() {
        if (this._pendingQuantityChanges.size > 0) return true;
        if ((this.quoteStartDate || null) !== (this._lastValidStartDate || null)) return true;
        if ((this.invoicingContactId || null) !== (this._initialInvoicingContactId || null)) return true;
        if ((this.softwareDeliveryContactId || null) !== (this._initialSoftwareDeliveryContactId || null)) return true;
        return false;
    }

    // Save is disabled until something on the UI differs from the last persisted state.
    get isSaveDisabled() {
        if (this.isLoading) return true;
        return !this.hasUnsavedChanges;
    }

    get isRegularLoading() { return this.isLoading && !this.isInitialLoading; }

    get lineCount() { return this.groupedProducts.length; }

    get headerTitle() {
        const parts = [];
        if (this.accountName) parts.push(this.accountName);
        if (this.quoteName) parts.push(this.quoteName);
        return parts.join(' | ') || 'Quote Line Editor';
    }

    get hasAccountLink() { return !!(this.accountName && this.accountId); }
    get hasQuoteLink() { return !!(this.quoteName && this.quoteId); }
    get showHeaderSeparator() { return this.hasAccountLink && this.hasQuoteLink; }
    get showFallbackHeader() { return !this.hasAccountLink && !this.hasQuoteLink; }

    get accountRecordUrl() {
        return this.accountId ? `/lightning/r/Account/${this.accountId}/view` : '#';
    }

    get quoteRecordUrl() {
        return this.quoteId ? `/lightning/r/SBQQ__Quote__c/${this.quoteId}/view` : '#';
    }

    // ─── Metrics computed from line data ───

    // Lines visible after applying the current quoteStartDate filter. Segments
    // whose endDate is before the start date are hidden from the UI and must
    // also be excluded from every header metric (ACV/TCV/YoY/etc.).
    get _visibleQuoteLines() {
        const startDate = this.quoteStartDate || null;
        return this.quoteLines.filter(line => {
            // Static Components live in quoteLines so we can cascade quantity from
            // their Static Bundle sibling, but they are never user-visible — exclude
            // them from every header metric and any display-derived calculation.
            if (line.cpqOptionType === 'Static Component') return false;
            if (!startDate) return true;
            if (!line.segmentKey) return true;
            return !line.endDate || line.endDate >= startDate;
        });
    }

    // Lines belonging to the CURRENTLY ACTIVE segment — i.e. the segment whose
    // start/end date range contains the quote start date. Header ACV reads
    // from this so a 3-year deal at $100K / $110K / $120K shows $110K when the
    // quote start date sits in Year 2 (instead of the summed $330K).
    // Non-MDQ lines (no segmentKey) are their own single term and stay included.
    get _currentSegmentLines() {
        const startDate = this.quoteStartDate || null;
        if (!startDate) return this.quoteLines;
        return this.quoteLines.filter(line => {
            if (!line.segmentKey) return true;
            if (line.startDate && startDate < line.startDate) return false;
            if (line.endDate && startDate > line.endDate) return false;
            return true;
        });
    }

    get totalAcv() {
        return AgenticQTCAppFormulas.totalAcv(this._currentSegmentLines);
    }

    get displayTotalAcv() { return this._fmtCurrency(this.totalAcv); }

    get totalAcvChange() {
        return AgenticQTCAppFormulas.totalAcvChange(this._visibleQuoteLines);
    }

    get displayTotalAcvChange() {
        const val = this.totalAcvChange;
        const prefix = val >= 0 ? '+' : '';
        return prefix + this._fmtCurrency(val);
    }

    get acvChangeClass() {
        return 'metric-value' + (this.totalAcvChange >= 0 ? ' positive' : ' negative');
    }

    // TCV = subscription baseline + live Σ quote-line.netTotal.
    //   • Baseline: Σ SBQQ__NetPrice__c × SBQQ__Quantity__c across the contract's
    //     latest-in-chain subscriptions. Aggregated server-side by
    //     AgenticQTC_ContractService.buildSubscriptionAggregates and forwarded from the
    //     OSA selector as initialSubscriptionTcv. Constant for the life of the editor —
    //     the contract's subscription rows don't change during amendment.
    //   • Quote-line netTotal: each line's optimistic netTotal is recomputed by
    //     AgenticQTCAppFormulas.recalcLineForQuantity on every quantity edit, then
    //     overwritten with the authoritative SBQQ__NetTotal__c after Save. On a fresh
    //     amendment with no edits yet, these are 0 so the header reads as the baseline.
    get totalTcv() {
        const baseline = Number(this.initialSubscriptionTcv) || 0;
        return baseline + AgenticQTCAppFormulas.sumField(this._visibleQuoteLines, 'netTotal');
    }

    get displayTotalTcv() { return this._fmtCurrency(this.totalTcv); }

    // YoY Uplift is sourced directly from SBQQ__Quote__c.Min_year_on_year_committed_spend__c
    // (mapped to minYoyCommittedSpend on the LWC) — CPQ owns the formula. The value
    // refreshes on every Save because saveQuoteChanges re-runs getQuoteDetails in the
    // same round-trip. Older client-side calculation from segment ACVs has been retired.
    get totalYoyUplift() {
        return Number(this.minYoyCommittedSpend) || 0;
    }

    get displayTotalYoyUplift() {
        if (this.minYoyCommittedSpend == null) return '--';
        const val = this.totalYoyUplift;
        const prefix = val >= 0 ? '+' : '';
        return prefix + val.toFixed(2) + '%';
    }

    get yoyUpliftClass() {
        return 'metric-value' + (this.totalYoyUplift >= 0 ? ' positive' : ' negative');
    }

    get displayDealQualityScore() {
        return this.dealQualityScore != null ? String(this.dealQualityScore) : '--';
    }

    get dqScoreClass() {
        const s = this.dealQualityScore;
        if (s == null) return 'metric-value';
        if (s >= 100) return 'metric-value positive';
        if (s >= 90) return 'metric-value';
        return 'metric-value negative';
    }

    // ─── Contacts ───

    get hasInvoicingContact() { return !!this.invoicingContactName; }
    get hasInvoicingContactTitle() { return !!this.invoicingContactTitle; }
    get hasInvoicingContactAccountName() { return !!this.invoicingContactAccountName; }
    get hasDeliveryContact() { return !!this.softwareDeliveryContactName; }
    get hasDeliveryContactTitle() { return !!this.softwareDeliveryContactTitle; }
    get hasDeliveryContactAccountName() { return !!this.softwareDeliveryContactAccountName; }

    // Submit-for-Approval gating: blocked while loading, after a submit this
    // session, or while there are unsaved edits — a quote must be saved before
    // it can be sent for approval (BIZ-83431). Unsaved edits mean "the UI differs
    // from the persisted quote", so reopening an already-saved quote that needs
    // approval still allows submission (nothing differs → not blocked).
    get isSubmitForApprovalDisabled() {
        if (this.isLoading) return true;
        if (this._submittedForApproval) return true;
        if (this.hasUnsavedChanges) return true;
        return false;
    }

    get isPreviewSendDisabled() {
        if (!this.softwareDeliveryContactId || !this.softwareDeliveryContactEmail) return true;
        if (this.anyApprovalRequired && this.approvalStatus !== 'Approved') return true;
        return false;
    }

    // ─── Approvals ───

    // Flattens the shared border with the reasons panel when expanded so the
    // bar + panel read as one connected card. See .is-expanded in the CSS.
    get approvalsBarClass() {
        return 'approvals-bar' + (this.showReasons ? ' is-expanded' : '');
    }

    get approvalChips() {
        return this.approvalItems.map(item => {
            const colorIdx = this._avatarColorIndex(item.approverName);
            return {
                key: item.approverName + item.ruleName,
                label: item.approverName,
                dotClass: 'approver-chip-dot approver-color-' + colorIdx
            };
        });
    }

    // Expanded reasons panel — same avatar color as the matching inline chip
    // so the eye can link "Sarah Johnson chip" to "Sarah Johnson row" at a glance.
    // Each item also carries the rule's Approval_Description__c text so the
    // hover popover on the reason can show a plain-language explanation of
    // why this rule fired (instead of the raw condition table).
    get displayApprovalItems() {
        return this.approvalItems.map(item => {
            const description = (item.description || '').trim();
            const hasDescription = description.length > 0;
            return {
                ...item,
                description,
                hasDescription,
                avatarClass: 'reason-avatar approver-color-' + this._avatarColorIndex(item.approverName),
                reasonTextWrapperClass: 'reason-text-wrapper' + (hasDescription ? ' has-description' : '')
            };
        });
    }

    // Deterministic 1..7 color slot from approver name — same name always gets
    // the same color across chips, expanded rows, and re-renders.
    _avatarColorIndex(name) {
        const s = name || '';
        let hash = 0;
        for (let i = 0; i < s.length; i++) hash = (hash + s.charCodeAt(i)) % 7;
        return hash + 1;
    }

    get showReasonsLabel() { return this.showReasons ? 'Hide reasons' : 'Show reasons'; }

    get showReasonsIcon() { return this.showReasons ? 'utility:chevronup' : 'utility:chevrondown'; }

    handleToggleReasons() { this.showReasons = !this.showReasons; }

    async handleSpecialTermsChange(event) {
        const newValue = event.target.checked;
        this.specialTerms = newValue;
        try {
            await updateQuoteSfa({ quoteId: this.quoteId, sfa: newValue });
        } catch (error) {
            console.error('Error updating special terms:', error);
            this.specialTerms = !newValue;
        }
    }

    // ─── Grouped products ───

    get groupedProducts() {
        const mdqMap = new Map();

        for (const line of this.quoteLines) {
            // Static Components are kept in quoteLines for the cascade but never rendered.
            if (line.cpqOptionType === 'Static Component') continue;
            if (line.segmentKey) {
                if (!mdqMap.has(line.segmentKey)) {
                    mdqMap.set(line.segmentKey, {
                        isMdq: true,
                        key: line.segmentKey,
                        segmentKey: line.segmentKey,
                        productName: line.productName,
                        productId: line.productId,
                        productCode: line.productCode,
                        meterType: line.meterType,
                        segments: [],
                        totalQuantity: 0,
                        totalCost: 0,
                        approvalRequired: 'Not Required'
                    });
                }
                const group = mdqMap.get(line.segmentKey);
                group.segments.push(line);
                group.totalQuantity += (line.quantity || 0);
                group.totalCost += (line.totalCost || line.netPrice || 0);
                if (line.approvalRequired === 'Required') {
                    group.approvalRequired = 'Required';
                }
            }
        }

        for (const group of mdqMap.values()) {
            group.segments.sort((a, b) => (a.segmentIndex || 0) - (b.segmentIndex || 0));
            group.segmentCount = group.segments.length;
        }

        const result = [];
        const mdqKeys = new Set();
        for (const line of this.quoteLines) {
            if (line.cpqOptionType === 'Static Component') continue;
            if (line.segmentKey) {
                if (!mdqKeys.has(line.segmentKey)) {
                    mdqKeys.add(line.segmentKey);
                    result.push(mdqMap.get(line.segmentKey));
                }
            } else {
                result.push({
                    isMdq: true,
                    key: line.id,
                    segmentKey: null,
                    productName: line.productName,
                    productId: line.productId,
                    productCode: line.productCode,
                    meterType: line.meterType,
                    segments: [line],
                    totalQuantity: line.quantity || 0,
                    totalCost: line.totalCost || line.netPrice || 0,
                    segmentCount: 1,
                    approvalRequired: line.approvalRequired || 'Not Required'
                });
            }
        }
        return result;
    }

    // Groups products into term-cards. Two products land in the same card only when
    // they have identical segment counts AND every segment's start/end date matches.
    // Segments whose endDate falls before the current quoteStartDate are filtered out
    // here only — the raw line is preserved in this.quoteLines so moving the start
    // date back restores them with their original values.
    get termGroupedProducts() {
        const startDate = this.quoteStartDate || null;
        const groups = new Map();
        for (const product of this.groupedProducts) {
            const allSegs = product.segments || [];
            const segs = startDate
                ? allSegs.filter(s => !s.endDate || s.endDate >= startDate)
                : allSegs;
            if (segs.length === 0) continue;
            const visibleCount = segs.length;
            const sigParts = segs.map(s => (s.startDate || '') + '|' + (s.endDate || ''));
            const termKey = visibleCount + '::' + sigParts.join('::');
            if (!groups.has(termKey)) {
                const yearHeaders = segs.map((s, idx) => {
                    // First visible segment: always reflect the chosen quoteStartDate
                    // (covers BOTH directions — forward moves into the segment AND
                    // backward moves before the segment's original start). The new
                    // validation already prevents moving the start date past the
                    // first term's end date, so no upper-bound check is needed here.
                    const effectiveStart = (idx === 0 && startDate)
                        ? startDate
                        : s.startDate;
                    const startStr = effectiveStart
                        ? new Date(effectiveStart + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                        : '';
                    const endStr = s.endDate
                        ? new Date(s.endDate + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                        : '';
                    return {
                        key: 'yh-' + idx,
                        dateRange: startStr && endStr ? startStr + ' - ' + endStr : startStr,
                        label: s.segmentLabel || ('Year ' + (idx + 1))
                    };
                });
                groups.set(termKey, {
                    key: termKey,
                    segmentCount: visibleCount,
                    termLabel: 'Proposed ' + visibleCount + '-year term',
                    yearHeaders,
                    products: []
                });
            }
            const visibleProduct = {
                ...product,
                segments: segs,
                segmentCount: visibleCount
            };
            groups.get(termKey).products.push(visibleProduct);
        }
        return [...groups.values()];
    }

    get toastClass() {
        return 'toast-container' + (this.toastVariant ? ' ' + this.toastVariant : '');
    }

    @api
    async refreshLines() {
        await this.loadLines();
    }

    async connectedCallback() {
        // Picked a draft from the OSA selector's modal? Read it via pure SOQL and skip
        // the amendment creation flow entirely. Otherwise run the standard amend init.
        if (this.existingQuoteId) {
            await this.loadExistingQuote();
        } else {
            await this.initQuote();
        }
    }

    /**
     * @description Lightweight "reuse existing draft" loader. Reads the quote header,
     *              lines, and details in parallel via pure-SOQL Apex — no CPQ amend /
     *              calculate / save round-trip, no progress crawl. The editor then
     *              renders exactly as it would after a fresh amendment.
     * @returns {Promise<void>}
     */
    async loadExistingQuote() {
        this.isInitialLoading = false;
        this.loadingMessage = 'Loading quote';
        this.isLoading = true;
        try {
            const [quote, details] = await Promise.all([
                loadExistingDraftQuote({ quoteId: this.existingQuoteId }),
                getQuoteDetails({ quoteId: this.existingQuoteId })
            ]);
            if (!quote) {
                this.showToast('No quote returned from server', 'error');
                return;
            }
            this.quoteId        = quote.id;
            this.quoteName      = quote.name;
            this.quoteStatus    = quote.status;
            // When the quote record has no saved start date, fall back to today
            // so the field is never blank. Baseline mirrors the displayed value
            // so the Save button stays disabled until the user actually edits.
            this.quoteStartDate = quote.startDate || this._todayIso();
            this._lastValidStartDate = this.quoteStartDate;
            this.dispatchEvent(new CustomEvent('quoteloaded', {
                detail: { quoteId: this.quoteId },
                bubbles: true,
                composed: true
            }));

            const lines = this._stripBundleLines(Array.isArray(quote.lines) ? quote.lines : []);
            if (!this._acvBaselineCaptured) {
                this._initialAcvByLineId = AgenticQTCAppFormulas.captureAcvBaseline(lines);
                this._acvBaselineCaptured = true;
            }
            this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(lines, this._initialAcvByLineId);
            await this.loadApprovalPreview();

            if (details) {
                this.totalContractMonths = details.subscriptionTerm != null ? details.subscriptionTerm : 0;
                this.firstSegmentMonths  = details.firstSegmentMonths != null ? details.firstSegmentMonths : 0;
                this.contractDiscount    = details.discount != null ? details.discount : 0;
                this.billingFrequency    = details.billingFrequency || '';
                this.paymentTerms        = details.paymentTerms || '';
                this.specialTerms        = details.sfa || false;
                this._applyContactDetails(details);
            }
        } catch (error) {
            console.error('Error loading existing draft quote:', error);
            this.showToast(this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Slowly crawls progressValue from its current position toward `ceiling` over `durationMs`.
    // Stopped by _stopCrawl() when the real operation completes.
    _startCrawl(ceiling, durationMs) {
        clearInterval(this._progressInterval);
        const ticks = 40;
        const interval = durationMs / ticks;
        const increment = (ceiling - this.progressValue) / ticks;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._progressInterval = setInterval(() => {
            if (this.progressValue >= ceiling) {
                clearInterval(this._progressInterval);
                return;
            }
            this.progressValue = Math.min(+(this.progressValue + increment).toFixed(1), ceiling);
        }, interval);
    }

    _stopCrawl() {
        clearInterval(this._progressInterval);
    }

    _delay(ms) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    async initQuote() {
        this.isInitialLoading = true;
        this.isLoading = true;

        try {
            // ── Step 1: Create amendment quote ──────────────────────────
            this.progressValue = 2;
            this.progressMessage = 'Creating amendment quote…';
            this._startCrawl(50, 25000); // crawl toward 50% — stops when Apex returns

            const quote = await createAmendmentQuote({ contractId: this.contractId });

            this._stopCrawl();
            if (!quote) {
                this.isInitialLoading = false;
                this.isLoading = false;
                this.showToast('No quote returned from server', 'error');
                return;
            }
            this.quoteId = quote.id;
            this.quoteName = quote.name;
            this.quoteStatus = quote.status;
            // Fresh amendments may come back without a server-side start date —
            // fall back to today so the field is never blank. Baseline mirrors
            // the displayed value so Save stays disabled until the user edits.
            this.quoteStartDate = quote.startDate || this._todayIso();
            this._lastValidStartDate = this.quoteStartDate;
            this.dispatchEvent(new CustomEvent('quoteloaded', {
                detail: { quoteId: this.quoteId },
                bubbles: true,
                composed: true
            }));

            // The amender response already carries the quote lines — apply them now and
            // skip the separate getQuoteLines (QuoteReader) round-trip below. Fall back
            // to loadLines() if the server returned no lines (covers the existing-draft
            // reuse path and any unexpected empty response).
            const linesFromCreate = this._stripBundleLines(Array.isArray(quote.lines) ? quote.lines : []);
            if (linesFromCreate.length > 0) {
                if (!this._acvBaselineCaptured) {
                    this._initialAcvByLineId = AgenticQTCAppFormulas.captureAcvBaseline(linesFromCreate);
                    this._acvBaselineCaptured = true;
                }
                this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(linesFromCreate, this._initialAcvByLineId);
                this.recalcApproval();
            }

            // ── Step 2: Load quote lines (fallback only) + details in parallel ───
            this.progressValue = 55;
            this.progressMessage = 'Loading quote details…';
            this._startCrawl(78, 10000);

            const [, details] = await Promise.all([
                linesFromCreate.length > 0 ? Promise.resolve() : this.loadLines(),
                getQuoteDetails({ quoteId: this.quoteId })
            ]);

            if (details) {
                this.totalContractMonths = details.subscriptionTerm != null ? details.subscriptionTerm : 0;
                this.firstSegmentMonths  = details.firstSegmentMonths != null ? details.firstSegmentMonths : 0;
                this.contractDiscount    = details.discount != null ? details.discount : 0;
                this.billingFrequency    = details.billingFrequency || '';
                this.paymentTerms        = details.paymentTerms || '';
                this.specialTerms        = details.sfa || false;
                this._applyContactDetails(details);
            }

            this._stopCrawl();

            // ── Step 3: Evaluate approvals (SBAA preview) ────────────────
            this.progressValue = 85;
            this.progressMessage = 'Evaluating approvals…';
            await this.loadApprovalPreview();

            // ── Step 4: Done ─────────────────────────────────────────────
            this.progressValue = 100;
            this.progressMessage = 'Complete!';
            await this._delay(700);

            this.isInitialLoading = false;
            this.isLoading = false;

        } catch (error) {
            this._stopCrawl();
            console.error('Error initializing quote:', error);
            this.isInitialLoading = false;
            this.isLoading = false;
            this.showToast(this.extractError(error), 'error');
        }
    }

    async loadLines() {
        try {
            const lines = this._stripBundleLines(await getQuoteLines({ quoteId: this.quoteId }));
            if (!this._acvBaselineCaptured) {
                this._initialAcvByLineId = AgenticQTCAppFormulas.captureAcvBaseline(lines);
                this._acvBaselineCaptured = true;
            }
            this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(lines, this._initialAcvByLineId);
            this.recalcApproval();
        } catch (error) {
            console.error('Error loading lines:', error);
        }
    }

    recalcApproval() {
        this.anyApprovalRequired = this.approvalItems.length > 0;
        this.approvalCount = this.approvalItems.length;
    }

    async loadApprovalPreview() {
        if (!this.quoteId) return;
        try {
            this.approvalItems = await previewApprovals({ quoteId: this.quoteId });
        } catch (approvalError) {
            console.error('Could not load approval preview:', approvalError);
            this.approvalItems = [];
        }
        this.recalcApproval();
    }

    async handleStartDateChange(event) {
        const newStartDate = event.target.value;
        const firstTermEndDate = this._getFirstTermEndDate();
        // ISO yyyy-mm-dd strings compare lexicographically, so a plain > works.
        // Past dates are intentionally allowed. The upper bound is the FIRST term's
        // end date — moving the start date past year 1's end would void the entire
        // first segment, which is not allowed. This rule covers both single-year
        // terms (only one segment exists) and multi-year MDQ terms (segment 1 is
        // the first term).
        if (firstTermEndDate && newStartDate && newStartDate > firstTermEndDate) {
            const resetDate = this._lastValidStartDate || this._todayIso();
            this.quoteStartDate = resetDate;
            event.target.value = resetDate;
            this.showToast(
                'Invalid date: quote start date cannot be after the end date of the first term.',
                'error'
            );
            return;
        }
        // Lower bound: prefer the upgraded subscription's segment start date from
        // getCurrentSegmentInfo. If the segment start is null, fall back to the
        // upgraded subscription's start date. If the Apex returns no rows at all,
        // fall back to the locally-computed first term start date.
        const lowerBound = await this._getLowerBoundStartDate();
        if (lowerBound && newStartDate && newStartDate < lowerBound) {
            const resetDate = this._lastValidStartDate || this._todayIso();
            this.quoteStartDate = resetDate;
            event.target.value = resetDate;
            this.showToast(
                'Invalid date: quote start date cannot be earlier than the start date of the first term.',
                'error'
            );
            return;
        }
        // Local-only change — committed to the backend on Save via saveQuoteChanges.
        this.quoteStartDate = newStartDate;
    }

    // Resolves the lower bound for the quote start date. Calls getCurrentSegmentInfo
    // once per session and caches the result; subsequent edits use the cached value.
    // Resolution order:
    //   1) upgraded subscription segment start date (SBQQ__SegmentStartDate__c)
    //   2) upgraded subscription start date         (SBQQ__StartDate__c)
    //   3) locally-computed first-term start date (current logic)
    async _getLowerBoundStartDate() {
        if (!this._currentSegmentInfoLoaded && this.quoteId) {
            try {
                this._currentSegmentInfo = await getCurrentSegmentInfo({ quoteId: this.quoteId });
            } catch (error) {
                console.error('Error fetching current segment info:', error);
                this._currentSegmentInfo = null;
            }
            this._currentSegmentInfoLoaded = true;
        }
        const rows = this._currentSegmentInfo;
        if (Array.isArray(rows) && rows.length > 0) {
            const upgraded = rows[0] && rows[0].SBQQ__UpgradedSubscription__r;
            if (upgraded) {
                return upgraded.SBQQ__SegmentStartDate__c
                    || upgraded.SBQQ__StartDate__c
                    || this._getFirstTermStartDate();
            }
        }
        return this._getFirstTermStartDate();
    }

    _getContractEndDate() {
        let maxEnd = null;
        for (const line of this.quoteLines) {
            if (line.endDate && (!maxEnd || line.endDate > maxEnd)) {
                maxEnd = line.endDate;
            }
        }
        return maxEnd;
    }

    // Returns the earliest "first-term" end date across all quote lines:
    //   • For MDQ products, segment 1 (segmentIndex === 1) is the first term.
    //   • For non-MDQ products, the single line itself is its first (and only) term.
    // Picking the minimum guarantees the validation triggers if ANY product's
    // first term ends before the chosen start date — keeps multi-product quotes
    // safe even when products have differently-shaped terms.
    _getFirstTermEndDate() {
        let minEnd = null;
        for (const line of this.quoteLines) {
            const isFirstTerm = !line.segmentKey || (line.segmentIndex || 1) === 1;
            if (!isFirstTerm) continue;
            if (line.endDate && (!minEnd || line.endDate < minEnd)) {
                minEnd = line.endDate;
            }
        }
        return minEnd;
    }

    // Mirror of _getFirstTermEndDate for the lower bound: returns the LATEST
    // first-term start date across all quote lines. Picking the maximum means
    // the chosen quote start date is on/after every product's first segment
    // start — keeps multi-product quotes safe when first-term starts differ.
    _getFirstTermStartDate() {
        let maxStart = null;
        for (const line of this.quoteLines) {
            const isFirstTerm = !line.segmentKey || (line.segmentIndex || 1) === 1;
            if (!isFirstTerm) continue;
            if (line.startDate && (!maxStart || line.startDate > maxStart)) {
                maxStart = line.startDate;
            }
        }
        return maxStart;
    }

    // Drops bundle parents (SBQQ__Bundle__c = true) — only their components are
    // displayed in the editor. Static Component lines stay in quoteLines (hidden
    // from display in the getters below) because they need to receive cascaded
    // quantity updates when their Static Bundle sibling is edited.
    _stripBundleLines(lines) {
        if (!Array.isArray(lines)) return [];
        return lines.filter(l => l && l.isBundle !== true);
    }

    _todayIso() {
        const d = new Date();
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return y + '-' + m + '-' + day;
    }

    handleQuantityChange(event) {
        const detail = event?.detail;
        if (!detail) return;
        const { lineId, quantity } = detail;
        this._pendingQuantityChanges.set(lineId, { type: 'single', quantity });
        const driver = this.quoteLines.find(l => l.id === lineId);
        this._syncStaticComponentQuantity(driver, quantity, false);
    }

    async handleAcvChange(event) {
        const detail = event?.detail;
        if (!detail) return;
        this.loadingMessage = 'Calculating the updated price';
        this.isLoading = true;
        try {
            const { lineId, acvChange } = detail;
            const updatedLines = this._stripBundleLines(await updateQuoteLineAcvChange({
                quoteId: this.quoteId,
                quoteLineId: lineId,
                acvChange: acvChange
            }));
            this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(updatedLines, this._initialAcvByLineId);
            this.recalcApproval();
            this.showToast('ACV Change updated', 'success');
        } catch (error) {
            console.error('Error updating ACV:', error);
            this.showToast('Error updating ACV: ' + this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleMdqQuantityChange(event) {
        const detail = event?.detail;
        if (!detail) return;
        const { lineId, quantity, segmentKey, applyToAll } = detail;
        this._pendingQuantityChanges.set(lineId, { type: 'mdq', quantity, segmentKey, applyToAll: applyToAll || false });
        this._applyOptimisticQuantity(lineId, quantity, segmentKey, applyToAll || false);
        const driver = this.quoteLines.find(l => l.id === lineId);
        this._syncStaticComponentQuantity(driver, quantity, applyToAll || false);
    }

    handleMdqValidationError(event) {
        const message = event?.detail?.message || 'Invalid quantity';
        this.showToast(message, 'error');
    }

    _applyOptimisticQuantity(lineId, newQty, segmentKey, applyToAll) {
        const updated = this.quoteLines.map(line => {
            const isTarget = applyToAll
                ? line.segmentKey === segmentKey
                : line.id === lineId;
            if (!isTarget) return line;
            return AgenticQTCAppFormulas.recalcLineForQuantity(line, newQty);
        });
        this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(updated, this._initialAcvByLineId);
    }

    // Cascades a quantity edit on a "Static Bundle" line to its hidden "Static
    // Component" sibling(s). Match key is requiredBy + segmentIndex — both lines
    // share the same SBQQ__RequiredBy__c (their bundle parent's line Id) and the
    // same segment. When applyToAll is true, every segment under the same bundle
    // parent is synced, mirroring the Apply-to-All-Years behavior of MDQ edits.
    // Updated Static Component lines are queued in _pendingQuantityChanges so
    // saveQuoteChanges persists them on the next Save.
    _syncStaticComponentQuantity(driverLine, newQty, applyToAll) {
        if (!driverLine || driverLine.cpqOptionType !== 'Static Bundle') return;
        if (!driverLine.requiredBy) return;
        const driverRequiredBy = driverLine.requiredBy;
        const driverSegmentIndex = driverLine.segmentIndex || 0;

        const updated = this.quoteLines.map(line => {
            if (line.cpqOptionType !== 'Static Component') return line;
            if (line.requiredBy !== driverRequiredBy) return line;
            if (!applyToAll && (line.segmentIndex || 0) !== driverSegmentIndex) return line;
            this._pendingQuantityChanges.set(line.id, {
                type: line.segmentKey ? 'mdq' : 'single',
                quantity: newQty,
                segmentKey: line.segmentKey || null,
                applyToAll: false
            });
            return AgenticQTCAppFormulas.recalcLineForQuantity(line, newQty);
        });
        this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(updated, this._initialAcvByLineId);
    }

    handleAddProduct() { this.showAddProduct = true; }
    handleCloseAddProduct() { this.showAddProduct = false; }

    async handleProductAdded() {
        this.showAddProduct = false;
        await this.loadLines();
        this.showToast('Product added successfully', 'success');
    }

    async handleSave() {
        this.loadingMessage = 'Saving and recalculating prices';
        this.isLoading = true;
        try {
            const changes = [];
            for (const [lineId, change] of this._pendingQuantityChanges) {
                changes.push({
                    lineId,
                    quantity: change.quantity,
                    segmentKey: change.segmentKey || null,
                    applyToAll: change.applyToAll || false
                });
            }
            // Combined CPQ save — line quantities + header fields (start date + contacts)
            // travel in a single round-trip via saveQuoteChanges.
            const result = await saveQuoteChanges({
                quoteId: this.quoteId,
                changesJson: JSON.stringify(changes),
                startDate: this.quoteStartDate || null,
                invoicingContactId: this.invoicingContactId || null,
                softwareDeliveryContactId: this.softwareDeliveryContactId || null
            });

            if (result?.lines) {
                this.quoteLines = AgenticQTCAppFormulas.applyAcvChange(this._stripBundleLines(result.lines), this._initialAcvByLineId);
            }
            if (result?.details) {
                this._applyContactDetails(result.details);
                if (result.details.startDate) {
                    this.quoteStartDate = result.details.startDate;
                }
            }
            this._lastValidStartDate = this.quoteStartDate;
            this._pendingQuantityChanges.clear();

            await this.loadApprovalPreview();

            this.showToast('Quote saved & prices calculated', 'success');
        } catch (error) {
            console.error('Error saving quote:', error);
            this.showToast('Error saving: ' + this.extractError(error), 'error');
            await this.loadLines();
        } finally {
            this.isLoading = false;
        }
    }

    // VK: Contract Ops workflow is out of scope for the current release.
    // Re-enable this handler, the createContractOpsCase import above, and the
    // "Contract Ops" button in the template when the approval flow comes back.
    // async handleContractOps() {
    //     try {
    //         await createContractOpsCase({
    //             quoteId: this.quoteId,
    //             accountId: this.accountId,
    //             contractNumber: this.contractNumber
    //         });
    //         this.showToast('Contract Ops case created successfully', 'success');
    //     } catch (error) {
    //         console.error('Error creating Contract Ops case:', error);
    //         this.showToast('Error creating case: ' + this.extractError(error), 'error');
    //     }
    // }

    async handleSubmitForApproval() {
        if (!this.quoteId) return;
        // Defense-in-depth alongside isSubmitForApprovalDisabled: never submit a
        // quote that has unsaved edits — the user must Save first (BIZ-83431).
        if (this.hasUnsavedChanges) {
            this.showToast('Please save your changes before submitting for approval', 'warning');
            return;
        }
        this._submittedForApproval = true;
        try {
            await submitForApproval({ quoteId: this.quoteId });
            this.showToast('Submitted for approval', 'success');
        } catch (error) {
            console.error('Error submitting for approval:', error);
            this._submittedForApproval = false;
            this.showToast('Error submitting for approval: ' + this.extractError(error), 'error');
        }
    }

    handlePreviewSend() { this.showPreviewSend = true; }
    handleClosePreviewSend() { this.showPreviewSend = false; }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    // ─── Contact picker ───

    _applyContactDetails(details) {
        this.invoicingContactId                 = details.invoicingContactId || null;
        this.invoicingContactName               = details.invoicingContactName || null;
        this.invoicingContactEmail              = details.invoicingContactEmail || null;
        this.invoicingContactTitle              = details.invoicingContactTitle || null;
        this.invoicingContactAccountName        = details.invoicingContactAccountName || null;
        this.softwareDeliveryContactId          = details.softwareDeliveryContactId || null;
        this.softwareDeliveryContactName        = details.softwareDeliveryContactName || null;
        this.softwareDeliveryContactEmail       = details.softwareDeliveryContactEmail || null;
        this.softwareDeliveryContactTitle       = details.softwareDeliveryContactTitle || null;
        this.softwareDeliveryContactAccountName = details.softwareDeliveryContactAccountName || null;
        this.approvalStatus                     = details.approvalStatus || null;
        this.dealQualityScore                   = details.dealQualityScore != null
            ? details.dealQualityScore : null;
        // Refreshed by CPQ on every Save (saveQuoteChanges re-runs getQuoteDetails),
        // so the YoY Uplift tile stays in sync without any extra LWC plumbing.
        this.minYoyCommittedSpend               = details.minYoyCommittedSpend != null
            ? details.minYoyCommittedSpend : null;
        // Baseline for dirty-detection — refreshed every time the server gives us details
        // (initial load and after Save), so Save re-disables once nothing differs.
        this._initialInvoicingContactId = this.invoicingContactId;
        this._initialSoftwareDeliveryContactId = this.softwareDeliveryContactId;
    }

    get _selectedContactIdForPicker() {
        return this.contactPickerType === 'delivery'
            ? this.softwareDeliveryContactId
            : this.invoicingContactId;
    }

    get filteredContacts() {
        if (!this.showContactPicker) return [];
        const selectedId = this._selectedContactIdForPicker;
        const term = (this.contactSearchTerm || '').trim().toLowerCase();

        let matches = this.availableContacts.filter(c => {
            if (!term) return true;
            const name = (c.name || '').toLowerCase();
            return name.indexOf(term) !== -1;
        });

        // Local cache (1000 rows) had no hit for this term — fall back to the
        // server-search results, but only when they were fetched for the exact
        // same term. If the user backspaces to a shorter term, the local cache
        // will be tried first again on the next render.
        if (term && matches.length === 0 && this._serverSearchTerm === term) {
            matches = this._serverContacts.slice();
        }

        // Selected contact first (only when no search term is active), then alphabetical.
        matches.sort((a, b) => {
            if (!term) {
                if (a.id === selectedId && b.id !== selectedId) return -1;
                if (b.id === selectedId && a.id !== selectedId) return 1;
            }
            return (a.name || '').localeCompare(b.name || '');
        });

        return matches.map(c => {
            const isSelected = c.id === selectedId;
            // Subtitle order: Account · Title · Email — account name first so the
            // user can disambiguate same-name contacts across firms before scanning
            // role/email.
            const subtitleParts = [];
            if (c.accountName) subtitleParts.push(c.accountName);
            if (c.title)       subtitleParts.push(c.title);
            if (c.email)       subtitleParts.push(c.email);
            return {
                id: c.id,
                name: c.name,
                subtitle: subtitleParts.join(' · '),
                initials: this._initialsFromName(c.name),
                isSelected,
                ariaPressed: isSelected ? 'true' : 'false',
                itemClass: 'contact-picker-item' + (isSelected ? ' contact-picker-item--selected' : '')
            };
        });
    }

    get contactPickerEmpty() {
        return this.showContactPicker
            && this.availableContacts.length > 0
            && this.filteredContacts.length === 0;
    }

    async handleOpenContactPicker(event) {
        const type = event?.currentTarget?.dataset?.type;
        if (type !== 'invoicing' && type !== 'delivery') return;
        this.contactPickerType = type;
        this.contactSearchTerm = '';
        this.showContactPicker = true;
        await this._ensureContactsLoaded();
        this._ensureSelectedContactInList();
    }

    // If the quote's currently-saved contact isn't in the 1000-row cache, inject a
    // synthetic row from the header-level fields so it still appears in the picker.
    // The existing sort in filteredContacts() floats the selected id to the top
    // whenever the search term is empty, so the user sees it first on open.
    _ensureSelectedContactInList() {
        const selectedId = this._selectedContactIdForPicker;
        if (!selectedId) return;
        if (this.availableContacts.some(c => c.id === selectedId)) return;
        const isInvoicing = this.contactPickerType === 'invoicing';
        const row = {
            id: selectedId,
            name:        isInvoicing ? this.invoicingContactName        : this.softwareDeliveryContactName,
            email:       isInvoicing ? this.invoicingContactEmail       : this.softwareDeliveryContactEmail,
            title:       isInvoicing ? this.invoicingContactTitle       : this.softwareDeliveryContactTitle,
            accountName: isInvoicing ? this.invoicingContactAccountName : this.softwareDeliveryContactAccountName
        };
        if (!row.name) return;
        this.availableContacts = [row, ...this.availableContacts];
    }

    handleCloseContactPicker() {
        this.showContactPicker = false;
        this.contactPickerType = null;
        this.contactSearchTerm = '';
        clearTimeout(this._serverSearchTimer);
        this._serverContacts = [];
        this._serverSearchTerm = null;
    }

    handleContactPickerStop(event) {
        event.stopPropagation();
    }

    handleContactSearch(event) {
        this.contactSearchTerm = event.target.value || '';
        this._maybeServerSearch();
    }

    // Fires a debounced server-side LIKE query only when:
    //   1. the term is non-empty,
    //   2. the local 1000-row cache has zero matches, AND
    //   3. we don't already have server results for this exact term.
    // The raw user input is sent to Apex — whitespace trimming happens server-side.
    _maybeServerSearch() {
        clearTimeout(this._serverSearchTimer);
        const rawTerm = this.contactSearchTerm || '';
        const termLower = rawTerm.trim().toLowerCase();
        if (!termLower) return;
        if (this._localMatchCount(termLower) > 0) return;
        if (this._serverSearchTerm === termLower) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._serverSearchTimer = setTimeout(async () => {
            try {
                const rows = await searchContacts({ searchTerm: rawTerm });
                // Discard stale responses if the user kept typing.
                const currentTermLower = (this.contactSearchTerm || '').trim().toLowerCase();
                if (currentTermLower !== termLower) return;
                this._serverContacts = Array.isArray(rows) ? rows : [];
                this._serverSearchTerm = termLower;
            } catch (error) {
                console.error('Server contact search failed:', error);
                this._serverContacts = [];
                this._serverSearchTerm = termLower;
            }
        }, 300);
    }

    _localMatchCount(termLower) {
        let count = 0;
        for (const c of this.availableContacts) {
            const name = (c.name || '').toLowerCase();
            if (name.indexOf(termLower) !== -1) count++;
        }
        return count;
    }

    handleContactSelect(event) {
        const contactId = event.currentTarget.dataset.id;
        if (!contactId) return;
        // Selected contact may live in either pool: the 1000-row local cache OR
        // the server-fallback results returned by searchContacts. Check both.
        const contact = this.availableContacts.find(c => c.id === contactId)
            || this._serverContacts.find(c => c.id === contactId);
        if (!contact) return;

        // Local-only change — committed to the backend on Save via saveQuoteChanges.
        const type = this.contactPickerType;
        if (type === 'invoicing') {
            this.invoicingContactId          = contact.id;
            this.invoicingContactName        = contact.name;
            this.invoicingContactEmail       = contact.email;
            this.invoicingContactTitle       = contact.title;
            this.invoicingContactAccountName = contact.accountName || null;
        } else if (type === 'delivery') {
            this.softwareDeliveryContactId          = contact.id;
            this.softwareDeliveryContactName        = contact.name;
            this.softwareDeliveryContactEmail       = contact.email;
            this.softwareDeliveryContactTitle       = contact.title;
            this.softwareDeliveryContactAccountName = contact.accountName || null;
        }
        this.handleCloseContactPicker();
    }

    async _ensureContactsLoaded() {
        if (!this.accountId) return;
        if (this._contactsLoadedForAccountId === this.accountId
            && this.availableContacts.length > 0) {
            return;
        }
        try {
            const rows = await getAccountContacts({ accountId: this.accountId });
            this.availableContacts = Array.isArray(rows) ? rows : [];
            this._contactsLoadedForAccountId = this.accountId;
        } catch (error) {
            console.error('Error loading contacts:', error);
            this.availableContacts = [];
            this.showToast('Error loading contacts: ' + this.extractError(error), 'error');
        }
    }

    _initialsFromName(name) {
        if (!name) return '';
        const parts = name.trim().split(/\s+/).slice(0, 2);
        return parts.map(p => p.charAt(0).toUpperCase()).join('');
    }

    showToast(message, variant) {
        this.toastMessage = message;
        this.toastVariant = variant;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.toastMessage = ''; }, 3000);
    }

    extractError(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return String(error);
    }

    _fmtCurrency(val) {
        const n = Number(val || 0);
        const code = this.currencyIsoCode || 'USD';
        return code + ' ' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
}