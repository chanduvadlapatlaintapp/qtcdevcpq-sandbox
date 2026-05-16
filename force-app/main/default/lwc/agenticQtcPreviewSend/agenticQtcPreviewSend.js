import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import buildCongaUrlForSave from '@salesforce/apex/AgenticQTC_OsaDocumentService.buildCongaUrlForSave';
import pollForNewDocument from '@salesforce/apex/AgenticQTC_OsaDocumentService.pollForNewDocument';
import finalizeOsaDocument from '@salesforce/apex/AgenticQTC_OsaDocumentService.finalizeOsaDocument';
import getRelatedContent from '@salesforce/apex/AgenticQTC_OsaDocumentService.getRelatedContent';
import createRelatedContent from '@salesforce/apex/AgenticQTC_OsaDocumentService.createRelatedContent';

/**
 * @description 3-step wizard for generating and reviewing the OSA document.
 *              Step 1 — User clicks "Open Conga"; LWC opens the Conga URL in a new tab
 *                       (DS7=11 background mode + SC1=SalesforceFile). Wizard polls Apex
 *                       every 3s until Conga saves the ContentVersion, then finalizes.
 *              Step 2 — Select additional documents from SBQQ__RelatedContent__c.
 *              Step 3 — Review all docs; download OSA or close.
 * @author AgenticQTC Team
 * @date 2026-05-12
 * @jira BIZ-81419
 */

const POLL_INTERVAL_MS = 3000;
// No timeout — poll until document is found or an error occurs

export default class AgenticQtcPreviewSend extends NavigationMixin(LightningElement) {

    /**********************************************************************************************
     * Public API
     **********************************************************************************************/

    /** @type {string} The Salesforce Quote ID to generate documents for. */
    @api quoteId;

    /** @type {string} Contract number used for display context. */
    @api contractNumber;

    /** @type {string} Salesforce Account ID associated with the quote. */
    @api accountId;

    /**********************************************************************************************
     * Private Properties
     **********************************************************************************************/

    @track currentStep = 'step1';
    @track isWaitingForDoc = false;
    @track generatedDoc = null;
    @track errorMessage = null;
    @track relatedContentDocs = [];
    @track selectedDocIds = [];
    @track isLoadingDocs = false;

    _pollInterval = null;
    _beforeTimestamp = null;
    _congaWindow = null;

    /**********************************************************************************************
     * Getters
     **********************************************************************************************/

    get isStep1() { return this.currentStep === 'step1'; }
    get isStep2() { return this.currentStep === 'step2'; }
    get isStep3() { return this.currentStep === 'step3'; }

    get hasError() { return !!this.errorMessage; }

    get hasRelatedDocs() { return this.relatedContentDocs.length > 0; }

    get step1NextDisabled() { return this.isWaitingForDoc || !this.generatedDoc; }

    get selectedDocs() {
        return this.relatedContentDocs
            .filter(doc => this.selectedDocIds.includes(doc.id))
            .map(doc => ({ ...doc, key: doc.id }));
    }

    get relatedDocsWithSelection() {
        return this.relatedContentDocs.map(doc => ({
            ...doc,
            key: doc.id,
            isSelected: this.selectedDocIds.includes(doc.id)
        }));
    }

    /**********************************************************************************************
     * Lifecycle Hooks
     **********************************************************************************************/

    disconnectedCallback() {
        this._clearPolling();
    }

    /**********************************************************************************************
     * Event Handlers
     **********************************************************************************************/

    async handleOpenConga() {
        this.errorMessage = null;
        this.generatedDoc = null;
        this.isWaitingForDoc = true;
        this._beforeTimestamp = new Date().toISOString();
        try {
            const congaUrl = await buildCongaUrlForSave({ quoteId: this.quoteId });
            this._congaWindow = window.open(congaUrl, '_blank');
            this._startPolling();
        } catch (error) {
            this.isWaitingForDoc = false;
            this.errorMessage = error?.body?.message || error?.message || 'Failed to build Conga URL';
        }
    }

    async handleNextToStep2() {
        this.currentStep = 'step2';
        await this._loadRelatedContent();
    }

    handleNextToStep3() {
        this.currentStep = 'step3';
    }

    handleBackToStep1() {
        this.currentStep = 'step1';
    }

    handleBackToStep2() {
        this.currentStep = 'step2';
    }

    handleDocToggle(event) {
        const docId = event.currentTarget.dataset.id;
        if (!docId) return;
        if (this.selectedDocIds.includes(docId)) {
            this.selectedDocIds = this.selectedDocIds.filter(id => id !== docId);
        } else {
            this.selectedDocIds = [...this.selectedDocIds, docId];
        }
    }

    async handleUploadFinished(event) {
        const files = event.detail.files || [];
        for (const file of files) {
            try {
                await createRelatedContent({
                    quoteId: this.quoteId,
                    contentDocumentId: file.documentId,
                    fileName: file.name
                });
            } catch (error) {
                console.error('Error creating related content for ' + file.name + ':', error);
            }
        }
        this._loadRelatedContent();
    }

    handlePreviewOsa() {
        if (this.generatedDoc && this.generatedDoc.contentDocumentId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: this.generatedDoc.contentDocumentId }
            });
        }
    }

    handleDownloadOsa() {
        if (this.generatedDoc && this.generatedDoc.downloadUrl) {
            window.open(this.generatedDoc.downloadUrl, '_blank');
        }
    }

    handleClose() {
        this._clearPolling();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOverlayClick() {
        this.handleClose();
    }

    stopPropagation(event) {
        if (event) event.stopPropagation();
    }

    /**********************************************************************************************
     * Private Methods
     **********************************************************************************************/

    _startPolling() {
        this._pollInterval = setInterval(() => { this._pollForDoc(); }, POLL_INTERVAL_MS);
    }

    async _pollForDoc() {
        try {
            const doc = await pollForNewDocument({
                quoteId: this.quoteId,
                beforeTimestamp: this._beforeTimestamp
            });
            if (doc) {
                this._clearPolling();
                const finalDoc = await finalizeOsaDocument({
                    quoteId: this.quoteId,
                    contentDocumentId: doc.contentDocumentId
                });
                this.generatedDoc = finalDoc;
                this.isWaitingForDoc = false;
                // Close the Conga tab — it stays on "Redirecting..." otherwise
                if (this._congaWindow && !this._congaWindow.closed) {
                    this._congaWindow.close();
                }
                // Auto-advance to Step 2
                this.currentStep = 'step2';
                await this._loadRelatedContent();
            }
        } catch (error) {
            this._clearPolling();
            this.isWaitingForDoc = false;
            this.errorMessage = error?.body?.message || error?.message || 'Error checking for generated document';
        }
    }

    _clearPolling() {
        if (this._pollInterval) {
            clearInterval(this._pollInterval);
            this._pollInterval = null;
        }
    }

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
}