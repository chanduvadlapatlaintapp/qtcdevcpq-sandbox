/**
 * @description 3-step wizard for generating and reviewing the OSA document.
 *
 *   Step 1 — Additional Documents
 *     User uploads supplemental PDFs (creates SBQQ__RelatedContent__c rows).
 *     Each row shows its order number and can be removed via the X icon.
 *
 *   Step 2 — Generate OSA (two paths)
 *     A) Open Conga to Generate OSA
 *        Opens the Conga Composer URL (DS7=11 background mode) in a new tab.
 *        LWC polls Apex every 3 s until Conga saves the combined PDF.
 *     B) Generate PDF — Instant
 *        Opens the AgenticQTC_OsaDocument Visualforce page immediately and runs
 *        generateInstantPdf in parallel to persist the ContentVersion + QuoteDoc.
 *
 *   Step 3 — Review & Send
 *     Preview and download the generated OSA; DocuSign send is a future feature.
 *
 * @author  AgenticQTC Team
 * @date    2026-05-26
 * @jira    BIZ-81419
 */

import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';

import buildCongaUrlForSave   from '@salesforce/apex/AgenticQTC_OsaDocumentService.buildCongaUrlForSave';
import pollForNewDocument     from '@salesforce/apex/AgenticQTC_OsaDocumentService.pollForNewDocument';
import finalizeOsaDocument    from '@salesforce/apex/AgenticQTC_OsaDocumentService.finalizeOsaDocument';

import renderInstantPdfBytes   from '@salesforce/apex/AgenticQTC_OsaDocumentService.renderInstantPdfBytes';
import saveMergedInstantPdf    from '@salesforce/apex/AgenticQTC_OsaDocumentService.saveMergedInstantPdf';
import getContentVersionBase64 from '@salesforce/apex/AgenticQTC_OsaDocumentService.getContentVersionBase64';
import renderCoverPdfBytes        from '@salesforce/apex/AgenticQTC_OsaDocumentService.renderCoverPdfBytes';
import replaceCongaWithMergedPdf  from '@salesforce/apex/AgenticQTC_OsaDocumentService.replaceCongaWithMergedPdf';

import getRelatedContent      from '@salesforce/apex/AgenticQTC_OsaDocumentService.getRelatedContent';
import createRelatedContent   from '@salesforce/apex/AgenticQTC_OsaDocumentService.createRelatedContent';
import deleteRelatedContent   from '@salesforce/apex/AgenticQTC_OsaDocumentService.deleteRelatedContent';
import reorderRelatedContent  from '@salesforce/apex/AgenticQTC_OsaDocumentService.reorderRelatedContent';

// Static resource — pdf-lib UMD build. Single-file resource: pdfLib.js sits next to
// pdfLib.resource-meta.xml in unpackaged/main/default/staticresources/.
import PDF_LIB from '@salesforce/resourceUrl/pdfLib';

const POLL_INTERVAL_MS = 3000;

export default class AgenticQtcPreviewSend extends NavigationMixin(LightningElement) {

    @api quoteId;
    @api contractNumber;
    @api accountId;

    @track currentStep            = 'step1';
    @track isWaitingForDoc        = false;
    @track isGeneratingInstantPdf = false;
    @track instantPdfStatus       = '';
    @track generatedDoc           = null;
    @track errorMessage           = null;
    @track relatedContentDocs     = [];
    @track isLoadingDocs          = false;

    _pollInterval    = null;
    _beforeTimestamp = null;
    _congaWindow     = null;

    // Drag state — id of the row currently being dragged, or null when idle.
    _dragSourceId = null;

    // Memoised pdf-lib load promise — keeps subsequent merges from re-fetching the script.
    _pdfLibLoadPromise = null;

    /**********************************************************************************************
     * Getters
     **********************************************************************************************/

    get isStep1() { return this.currentStep === 'step1'; }
    get isStep2() { return this.currentStep === 'step2'; }
    get isStep3() { return this.currentStep === 'step3'; }

    // Feature flag — the "Generate PDF — Instant" path is hidden for now so users only
    // use the Conga flow (Conga regenerates Quote Terms, so the T&C section is always
    // present — BIZ-81419). The Instant PDF button and all its handlers are intentionally
    // left in place; flip this to true to re-enable it without re-building the UI.
    get showInstantPdf() { return false; }

    get hasError() { return !!this.errorMessage; }
    get hasRelatedDocs() { return this.relatedContentDocs.length > 0; }

    get step2NextDisabled() {
        return this.isWaitingForDoc || this.isGeneratingInstantPdf || !this.generatedDoc;
    }

    /** Adds the "1.", "2.", "3." prefix shown in the doc list. Index-based so the labels
     *  always match what the user sees, even if SBQQ__DisplayOrder__c values have gaps.
     *  isFirst / isLast disable the up/down arrows at the list boundaries. */
    get relatedDocsDisplay() {
        const total = this.relatedContentDocs.length;
        return this.relatedContentDocs.map((doc, idx) => ({
            ...doc,
            key:        doc.id,
            orderLabel: `${idx + 1}.`,
            isFirst:    idx === 0,
            isLast:     idx === total - 1
        }));
    }

    /**********************************************************************************************
     * Lifecycle
     **********************************************************************************************/

    async connectedCallback() {
        await this._loadRelatedContent();
    }

    disconnectedCallback() {
        this._clearPolling();
    }

    /**********************************************************************************************
     * Step navigation
     **********************************************************************************************/

    handleNextToStep2()  { this.currentStep = 'step2'; }
    handleNextToStep3()  { this.currentStep = 'step3'; }
    handleBackToStep1()  { this.currentStep = 'step1'; }
    handleBackToStep2()  { this.currentStep = 'step2'; }

    handleClose() {
        this._clearPolling();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOverlayClick() { this.handleClose(); }
    stopPropagation(event) { if (event) event.stopPropagation(); }

    /**********************************************************************************************
     * Path A — Conga
     **********************************************************************************************/

    async handleOpenConga() {
        this.errorMessage     = null;
        this.generatedDoc     = null;
        this.isWaitingForDoc  = true;
        this._beforeTimestamp = new Date().toISOString();

        try {
            const congaUrl = await buildCongaUrlForSave({ quoteId: this.quoteId });
            this._congaWindow = window.open(congaUrl, '_blank');
            this._startPolling();
        } catch (error) {
            this.isWaitingForDoc = false;
            this.errorMessage = this._extractMessage(error, 'Failed to build Conga URL');
        }
    }

    /**********************************************************************************************
     * Path B — Instant native PDF with browser-side merge (pdf-lib)
     **********************************************************************************************/

    async handleGenerateInstantPdf() {
        this.errorMessage           = null;
        this.generatedDoc           = null;
        this.isGeneratingInstantPdf = true;
        this.instantPdfStatus       = 'Loading PDF engine…';

        // Tracks which stage is in flight so an error can point at the actual failure
        // ("Failed to fetch" alone is useless — knowing it failed during merge vs save matters).
        let stage = 'load PDF engine';
        try {
            await this._ensurePdfLib();

            stage = 'render OSA';
            this.instantPdfStatus = 'Rendering OSA…';
            const render = await renderInstantPdfBytes({ quoteId: this.quoteId });

            stage = 'merge uploaded documents';
            const uploads = this.relatedContentDocs;
            this.instantPdfStatus = uploads.length > 0
                ? `Merging ${uploads.length} uploaded document${uploads.length === 1 ? '' : 's'}…`
                : 'Finalizing PDF…';
            const mergedBase64 = await this._mergePdfs(render.base64Pdf, uploads);

            stage = 'save merged PDF';
            this.instantPdfStatus = 'Saving to Salesforce Files…';
            const doc = await saveMergedInstantPdf({
                quoteId:       this.quoteId,
                base64Pdf:     mergedBase64,
                fileName:      render.fileName,
                versionNumber: render.nextVersion
            });

            this.generatedDoc = doc;
            this.currentStep  = 'step3';
        } catch (error) {
            const detail = this._extractMessage(error, 'unknown error');
            this.errorMessage = `Failed to ${stage}: ${detail}`;
            // eslint-disable-next-line no-console
            console.error(`Instant PDF failed during "${stage}":`, error);
        } finally {
            this.isGeneratingInstantPdf = false;
            this.instantPdfStatus       = '';
        }
    }

    /**
     * Lazy-loads pdf-lib from the static resource. The UMD build attaches `PDFLib` to
     * window. Subsequent calls reuse the resolved promise so the script never loads twice.
     */
    _ensurePdfLib() {
        if (window.PDFLib) return Promise.resolve();
        if (!this._pdfLibLoadPromise) {
            this._pdfLibLoadPromise = loadScript(this, PDF_LIB);
        }
        return this._pdfLibLoadPromise;
    }

    /**
     * Merges the OSA PDF (base64) with each uploaded ContentVersion's PDF in the order
     * provided. Returns the merged document as a base64 string ready to ship to Apex.
     * Uploads without a resolvable contentVersionId or that fail to parse are skipped —
     * a single bad attachment shouldn't fail the whole merge.
     */
    async _mergePdfs(osaBase64, uploads) {
        const { PDFDocument } = window.PDFLib;
        const merged = await PDFDocument.create();

        const osaDoc   = await PDFDocument.load(this._base64ToUint8(osaBase64), { ignoreEncryption: true });
        const osaPages = await merged.copyPages(osaDoc, osaDoc.getPageIndices());
        osaPages.forEach(p => merged.addPage(p));

        for (const upload of uploads) {
            if (!upload.contentVersionId) continue;
            const bytes = await this._fetchPdfBytes(upload.contentVersionId);
            if (!bytes) continue;
            try {
                const doc   = await PDFDocument.load(bytes, { ignoreEncryption: true });
                const pages = await merged.copyPages(doc, doc.getPageIndices());
                pages.forEach(p => merged.addPage(p));
            } catch (err) {
                // eslint-disable-next-line no-console
                console.warn(`Skipping unmergeable upload "${upload.name}":`, err);
            }
        }

        const mergedBytes = await merged.save();
        return this._uint8ToBase64(mergedBytes);
    }

    /**
     * Builds the final Conga-path PDF browser-side: [cover] + [Conga OSA] + [uploaded
     * attachments], using pdf-lib (same engine Instant PDF uses). Conga itself only
     * renders the OSA template — the LWC owns the merge for both paths so the two
     * outputs stay symmetric. Publishes the result as a new ContentVersion on the
     * existing ContentDocument via replaceCongaWithMergedPdf. Returns the updated
     * GeneratedDocInfo on success or the original doc unchanged on any failure —
     * a missing cover is strictly better than failing the whole generation here.
     */
    async _prependCoverToCongaDoc(finalDoc) {
        if (!finalDoc?.contentVersionId || !finalDoc?.contentDocumentId) return finalDoc;
        try {
            await this._ensurePdfLib();

            const [coverBase64, congaBase64] = await Promise.all([
                renderCoverPdfBytes({ quoteId: this.quoteId }),
                getContentVersionBase64({ contentVersionId: finalDoc.contentVersionId })
            ]);
            if (!coverBase64 || !congaBase64) return finalDoc;

            const { PDFDocument } = window.PDFLib;
            const merged = await PDFDocument.create();

            // 1. Cover (from SBQQ "OSA First Page" template)
            const cover  = await PDFDocument.load(this._base64ToUint8(coverBase64), { ignoreEncryption: true });
            const coverPages = await merged.copyPages(cover, cover.getPageIndices());
            coverPages.forEach(p => merged.addPage(p));

            // 2. Conga's OSA body
            const conga  = await PDFDocument.load(this._base64ToUint8(congaBase64), { ignoreEncryption: true });
            const congaPages = await merged.copyPages(conga, conga.getPageIndices());
            congaPages.forEach(p => merged.addPage(p));

            // 3. Uploaded attachments in display order (mirrors the Instant PDF path).
            // An unmergeable attachment is skipped with a console warning — one bad
            // upload shouldn't fail the whole generation.
            for (const upload of (this.relatedContentDocs || [])) {
                if (!upload.contentVersionId) continue;
                const bytes = await this._fetchPdfBytes(upload.contentVersionId);
                if (!bytes) continue;
                try {
                    const doc   = await PDFDocument.load(bytes, { ignoreEncryption: true });
                    const pages = await merged.copyPages(doc, doc.getPageIndices());
                    pages.forEach(p => merged.addPage(p));
                } catch (err) {
                    // eslint-disable-next-line no-console
                    console.warn(`Skipping unmergeable upload "${upload.name}":`, err);
                }
            }

            const mergedBytes = await merged.save();
            return await replaceCongaWithMergedPdf({
                contentDocumentId: finalDoc.contentDocumentId,
                base64Pdf:         this._uint8ToBase64(mergedBytes)
            });
        } catch (err) {
            // eslint-disable-next-line no-console
            console.warn('Cover prepend failed — returning raw Conga PDF:', err);
            return finalDoc;
        }
    }

    // Routes upload-byte retrieval through Apex (`getContentVersionBase64`) instead of a
    // browser fetch of `/sfc/servlet.shepherd/version/download/...`. The Shepherd URL
    // sometimes redirects to a separate content domain, which can fail CORS depending on
    // the org's My Domain / content-domain configuration. Apex round-trips avoid the issue
    // entirely. Each call lives in its own 6 MB heap so per-upload size, not total, matters.
    async _fetchPdfBytes(contentVersionId) {
        const b64 = await getContentVersionBase64({ contentVersionId });
        if (!b64) return null;
        return this._base64ToUint8(b64);
    }

    _base64ToUint8(b64) {
        const binary = atob(b64);
        const out = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
        return out;
    }

    // atob/btoa on the raw bytes string blows up on large PDFs; chunk through
    // String.fromCharCode in 32 KB slices then base64-encode the assembled string once.
    _uint8ToBase64(bytes) {
        const CHUNK = 0x8000;
        let binary = '';
        for (let i = 0; i < bytes.length; i += CHUNK) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
        }
        return btoa(binary);
    }

    /**********************************************************************************************
     * Step 1 — upload / delete
     **********************************************************************************************/

    async handleUploadFinished(event) {
        const files = event.detail.files || [];
        for (const file of files) {
            try {
                await createRelatedContent({
                    quoteId:           this.quoteId,
                    contentDocumentId: file.documentId,
                    fileName:          file.name
                });
            } catch (error) {
                console.error('Error creating related content for ' + file.name + ':', error);
            }
        }
        await this._loadRelatedContent();
    }

    async handleRemoveDoc(event) {
        const relatedContentId = event.currentTarget.dataset.id;
        if (!relatedContentId) return;
        // Optimistic update so the click feels responsive — the reload at the end is the
        // source of truth if the server call fails.
        this.relatedContentDocs = this.relatedContentDocs.filter(d => d.id !== relatedContentId);
        try {
            await deleteRelatedContent({ quoteId: this.quoteId, relatedContentId });
        } catch (error) {
            console.error('Error deleting related content:', error);
        }
        await this._loadRelatedContent();
    }

    // ─── Drag-and-drop reordering ──────────────────────────────────────────────
    // The source row sets _dragSourceId on dragstart. As the cursor moves over
    // other rows, we rearrange `relatedContentDocs` so the row physically slides
    // under the cursor — the user sees a live reorder rather than a separate drop
    // indicator. On drop we persist the new order; on dragend we just clear state.

    handleDragStart(event) {
        this._dragSourceId = event.currentTarget.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
        // Firefox requires data on the transfer object to actually start the drag.
        event.dataTransfer.setData('text/plain', this._dragSourceId);
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        const targetId = event.currentTarget.dataset.id;
        if (!this._dragSourceId || !targetId || this._dragSourceId === targetId) return;

        const docs    = [...this.relatedContentDocs];
        const fromIdx = docs.findIndex(d => d.id === this._dragSourceId);
        const toIdx   = docs.findIndex(d => d.id === targetId);
        if (fromIdx === -1 || toIdx === -1) return;

        const [moved] = docs.splice(fromIdx, 1);
        docs.splice(toIdx, 0, moved);
        this.relatedContentDocs = docs;
    }

    async handleDrop(event) {
        event.preventDefault();
        this._dragSourceId = null;
        await this._persistOrder();
    }

    handleDragEnd() {
        this._dragSourceId = null;
    }

    // ─── Up / Down arrow fallback ──────────────────────────────────────────────

    handleMoveUp(event) {
        const id = event.currentTarget.dataset.id;
        this._swap(id, -1);
    }

    handleMoveDown(event) {
        const id = event.currentTarget.dataset.id;
        this._swap(id, +1);
    }

    /**
     * Swaps the row with the given id with its neighbor `direction` positions away
     * (-1 = up, +1 = down). Bails out at list boundaries. Persists the new order to
     * Apex; the optimistic UI update means the user sees the swap before the round
     * trip completes.
     */
    async _swap(id, direction) {
        const docs = [...this.relatedContentDocs];
        const idx  = docs.findIndex(d => d.id === id);
        const tgt  = idx + direction;
        if (idx === -1 || tgt < 0 || tgt >= docs.length) return;

        [docs[idx], docs[tgt]] = [docs[tgt], docs[idx]];
        this.relatedContentDocs = docs;
        await this._persistOrder();
    }

    async _persistOrder() {
        try {
            await reorderRelatedContent({
                quoteId:    this.quoteId,
                orderedIds: this.relatedContentDocs.map(d => d.id)
            });
        } catch (error) {
            console.error('Error reordering related content:', error);
            // Server is the source of truth — reload to undo the optimistic swap.
            await this._loadRelatedContent();
        }
    }

    /**********************************************************************************************
     * Step 3 — preview / download
     **********************************************************************************************/

    handlePreviewOsa() {
        if (this.generatedDoc?.contentDocumentId) {
            this[NavigationMixin.Navigate]({
                type:       'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state:      { selectedRecordId: this.generatedDoc.contentDocumentId }
            });
        }
    }

    handleDownloadOsa() {
        if (this.generatedDoc?.downloadUrl) {
            window.open(this.generatedDoc.downloadUrl, '_blank');
        }
    }

    /**********************************************************************************************
     * Conga polling helpers
     **********************************************************************************************/

    _startPolling() {
        this._pollInterval = setInterval(() => { this._pollForDoc(); }, POLL_INTERVAL_MS);
    }

    async _pollForDoc() {
        try {
            const doc = await pollForNewDocument({
                quoteId:         this.quoteId,
                beforeTimestamp: this._beforeTimestamp
            });

            if (doc) {
                this._clearPolling();

                const finalDoc = await finalizeOsaDocument({
                    quoteId:           this.quoteId,
                    contentDocumentId: doc.contentDocumentId
                });

                // Prepend the SBQQ "OSA First Page" cover to Conga's output via
                // pdf-lib so the Conga path produces the same first-page content
                // the Instant PDF path already includes. Falls back silently to
                // the raw Conga PDF if the prepend fails — a missing cover is
                // strictly better than a failed generation here.
                this.generatedDoc    = await this._prependCoverToCongaDoc(finalDoc);
                this.isWaitingForDoc = false;

                if (this._congaWindow && !this._congaWindow.closed) {
                    this._congaWindow.close();
                }
                this.currentStep = 'step3';
            }
        } catch (error) {
            this._clearPolling();
            this.isWaitingForDoc = false;
            this.errorMessage = this._extractMessage(error, 'Error checking for generated document');
        }
    }

    _clearPolling() {
        if (this._pollInterval) {
            clearInterval(this._pollInterval);
            this._pollInterval = null;
        }
    }

    /**********************************************************************************************
     * Helpers
     **********************************************************************************************/

    async _loadRelatedContent() {
        this.isLoadingDocs = true;
        try {
            const docs = await getRelatedContent({ quoteId: this.quoteId });
            this.relatedContentDocs = (docs || []).map(doc => ({ ...doc, key: doc.id }));
        } catch (error) {
            console.error('Error loading related content:', error);
            this.relatedContentDocs = [];
        } finally {
            this.isLoadingDocs = false;
        }
    }

    _extractMessage(error, fallback) {
        return error?.body?.message || error?.message || fallback;
    }
}