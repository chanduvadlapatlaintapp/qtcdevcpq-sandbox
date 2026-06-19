/**
 * @description Publish Changes component for the SKU Management App.
 *              Allows users to view, create, and submit change sets for review.
 *              Business-friendly UI — no GitHub/versioning jargon.
 *
 * @author  Sahal Mohamed
 * @date    2026-03-10
 * @jira    BIZ-80418
 */
import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChangeSets from '@salesforce/apex/SkuPublishController.getChangeSets';
import createChangeSet from '@salesforce/apex/SkuPublishController.createChangeSet';
import getChangeSetDetail from '@salesforce/apex/SkuPublishController.getChangeSetDetail';
import submitForReview from '@salesforce/apex/SkuPublishController.submitForReview';
import getChangeSetStatus from '@salesforce/apex/SkuPublishController.getChangeSetStatus';

// ─── Constants ──────────────────────────────────────────────────────────

const STATUS_MAP = {
    Open: { label: 'Draft', variant: 'default', icon: 'utility:edit' },
    Pending: { label: 'Processing', variant: 'warning', icon: 'utility:spinner' },
    Committed: { label: 'Published', variant: 'success', icon: 'utility:check' },
    Failed: { label: 'Error', variant: 'error', icon: 'utility:error' }
};

const POLL_INTERVAL_MS = 5000;

// ─── Component ──────────────────────────────────────────────────────────

export default class SkuPublishChanges extends LightningElement {

    // ─── Private Properties ─────────────────────────────────────────────

    @track activeView = 'list'; // 'list' | 'detail'
    @track selectedSessionId;
    @track sessionDetail;
    @track isSubmitting = false;
    @track isCreating = false;

    _wiredChangeSets;
    _changeSets = [];
    _pollTimer;
    _isPolling = false;

    // ─── Lifecycle Hooks ────────────────────────────────────────────────

    @wire(getChangeSets)
    wiredChangeSets(result) {
        this._wiredChangeSets = result;
        if (result.data) {
            this._changeSets = result.data.map(cs => ({
                ...cs,
                displayStatus: STATUS_MAP[cs.status]?.label || cs.status,
                badgeVariant: STATUS_MAP[cs.status]?.variant || 'default',
                statusIcon: STATUS_MAP[cs.status]?.icon || 'utility:info',
                isProcessing: cs.status === 'Pending',
                isPublished: cs.status === 'Committed',
                isFailed: cs.status === 'Failed',
                isDraft: cs.status === 'Open',
                formattedDate: this.formatDate(cs.createdDate),
                entryLabel: cs.entryCount === 1 ? '1 change' : cs.entryCount + ' changes'
            }));
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // ─── Getters ────────────────────────────────────────────────────────

    get isListView() {
        return this.activeView === 'list';
    }

    get isDetailView() {
        return this.activeView === 'detail';
    }

    get changeSets() {
        return this._changeSets;
    }

    get hasChangeSets() {
        return this._changeSets.length > 0;
    }

    get detailDisplayStatus() {
        if (!this.sessionDetail) return '';
        return STATUS_MAP[this.sessionDetail.status]?.label || this.sessionDetail.status;
    }

    get detailBadgeVariant() {
        if (!this.sessionDetail) return 'default';
        return STATUS_MAP[this.sessionDetail.status]?.variant || 'default';
    }

    get detailIsDraft() {
        return this.sessionDetail?.status === 'Open';
    }

    get detailIsProcessing() {
        return this.sessionDetail?.status === 'Pending';
    }

    get detailIsPublished() {
        return this.sessionDetail?.status === 'Committed';
    }

    get detailIsFailed() {
        return this.sessionDetail?.status === 'Failed';
    }

    get detailHasEntries() {
        return this.sessionDetail?.entries?.length > 0;
    }

    get canSubmit() {
        return this.detailIsDraft && this.detailHasEntries && !this.isSubmitting;
    }

    get groupedEntries() {
        if (!this.sessionDetail?.entries) return [];
        const groups = {};
        for (const entry of this.sessionDetail.entries) {
            const obj = entry.objectApiName;
            if (!groups[obj]) {
                groups[obj] = { objectName: obj, entries: [], key: obj };
            }
            groups[obj].entries.push({
                ...entry,
                opBadgeVariant: entry.operationType === 'Create' ? 'success'
                    : entry.operationType === 'Delete' ? 'error' : 'default'
            });
        }
        return Object.values(groups);
    }

    get detailFormattedDate() {
        return this.sessionDetail ? this.formatDate(this.sessionDetail.createdDate) : '';
    }

    get submitButtonLabel() {
        return this.isSubmitting ? 'Submitting...' : 'Submit for Review';
    }

    get isSubmitDisabled() {
        return !this.canSubmit;
    }

    // ─── Event Handlers ─────────────────────────────────────────────────

    handleNewChangeSet() {
        this.isCreating = true;
        createChangeSet()
            .then(sessionId => {
                this.showToast('Success', 'New change set created', 'success');
                return refreshApex(this._wiredChangeSets).then(() => {
                    this.selectedSessionId = sessionId;
                    this.loadDetail(sessionId);
                });
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            })
            .finally(() => {
                this.isCreating = false;
            });
    }

    handleRowClick(event) {
        const sessionId = event.currentTarget.dataset.id;
        this.selectedSessionId = sessionId;
        this.loadDetail(sessionId);
    }

    handleBackToList() {
        this.activeView = 'list';
        this.selectedSessionId = null;
        this.sessionDetail = null;
        this.stopPolling();
        refreshApex(this._wiredChangeSets);
    }

    handleSubmit() {
        this.isSubmitting = true;
        submitForReview({ sessionId: this.selectedSessionId })
            .then(() => {
                this.showToast('Submitted', 'Your changes are being processed', 'success');
                this.sessionDetail = { ...this.sessionDetail, status: 'Pending' };
                this.startPolling();
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    // ─── Private Methods ────────────────────────────────────────────────

    loadDetail(sessionId) {
        getChangeSetDetail({ sessionId })
            .then(detail => {
                this.sessionDetail = detail;
                this.activeView = 'detail';
                if (detail.status === 'Pending') {
                    this.startPolling();
                }
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            });
    }

    startPolling() {
        if (this._isPolling) return;
        this._isPolling = true;
        this._pollTimer = setInterval(() => {
            this.pollStatus();
        }, POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
        this._isPolling = false;
    }

    pollStatus() {
        if (!this.selectedSessionId) {
            this.stopPolling();
            return;
        }

        getChangeSetStatus({ sessionId: this.selectedSessionId })
            .then(result => {
                if (result.status === 'Committed') {
                    this.sessionDetail = { ...this.sessionDetail, status: 'Committed' };
                    this.stopPolling();
                    this.showToast('Published', 'Your changes have been published successfully!', 'success');
                } else if (result.status === 'Failed') {
                    this.sessionDetail = {
                        ...this.sessionDetail,
                        status: 'Failed',
                        errorMessage: result.errorMessage
                    };
                    this.stopPolling();
                    this.showToast('Error', 'Publishing failed. See details below.', 'error');
                }
            })
            .catch(() => {
                this.stopPolling();
            });
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr);
        return d.toLocaleDateString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: 'numeric', minute: '2-digit'
        });
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}