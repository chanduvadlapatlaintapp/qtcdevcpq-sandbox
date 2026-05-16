import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteTerms from '@salesforce/apex/SkuQuoteTermController.getQuoteTerms';
import saveQuoteTerms from '@salesforce/apex/SkuQuoteTermController.saveQuoteTerms';
import getQuoteTermPicklists from '@salesforce/apex/SkuQuoteTermController.getQuoteTermPicklists';

export default class QuoteTermManager extends LightningElement {
    @track records = [];
    @track isLoading = false;
    @track picklists = {};
    @track filterType = 'Standard';
    @track filterStatus = '';
    @track filterActive = 'true';
    @track searchTerm = '';
    @track filterCategory = 'Product';
    @track filterDesc = '';

    // Confirmation modal state
    @track showConfirmModal = false;
    @track _pendingToggleIndex = null;

    connectedCallback() {
        this.loadPicklists();
    }

    loadPicklists() {
        getQuoteTermPicklists()
            .then(result => {
                this.picklists = result;
            })
            .catch(() => { /* silently handle */ });
    }

    loadRecords() {
        this.isLoading = true;

        getQuoteTerms({
            filterType: this.filterType || null,
            filterStatus: this.filterStatus || null,
            searchTerm: this.searchTerm || null,
            filterActive: this.filterActive || null,
            filterCategory: this.filterCategory || null,
            filterDesc: this.filterDesc || null
        })
            .then(result => {
                this.records = result.map((rec, i) => ({
                    ...rec,
                    rowIndex: i,
                    rowClass: rec.SBQQ__Active__c === false ? 'row-inactive' : ''
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load quote terms: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Picklist options
    buildOptions(fieldName) {
        const values = this.picklists[fieldName] || [];
        return [{ label: 'All', value: '' }, ...values];
    }

    buildFieldOptions(fieldName) {
        const values = this.picklists[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get typeFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Standard', value: 'Standard' },
            { label: 'Custom', value: 'Custom' },
            { label: 'Modified', value: 'Modified' }
        ];
    }
    get statusFilterOptions() { return this.buildOptions('SBQQ__Status__c'); }
    get statusFieldOptions() { return this.buildFieldOptions('SBQQ__Status__c'); }
    get categoryOptions() { return this.buildFieldOptions('Term_Category__c'); }
    get categoryFilterOptions() { return this.buildOptions('Term_Category__c'); }
    get activeFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Active', value: 'true' },
            { label: 'Inactive', value: 'false' }
        ];
    }

    get hasRecords() { return this.records.length > 0; }

    get recordCountLabel() {
        const count = this.records.length;
        return count === 1 ? '1 Quote Term' : `${count} Quote Terms`;
    }
    // Filter handlers
    handleFilterTypeChange(event) {
        this.filterType = event.target.value;
        this.loadRecords();
    }

    handleFilterStatusChange(event) {
        this.filterStatus = event.target.value;
        this.loadRecords();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleSearchKeyUp(event) {
        if (event.key === 'Enter') {
            this.loadRecords();
        }
    }

    handleFilterActiveChange(event) {
        this.filterActive = event.target.value;
        this.loadRecords();
    }

    handleFilterCategoryChange(event) {
        this.filterCategory = event.target.value;
        this.loadRecords();
    }

    handleFilterDescChange(event) {
        this.filterDesc = event.target.value;
    }

    handleFilterDescKeyUp(event) {
        if (event.key === 'Enter') {
            this.loadRecords();
        }
    }

    handleFilterSearch() {
        this.loadRecords();
    }

    // =========================================================================
    // Activate / Inactivate Toggle with Confirmation
    // =========================================================================

    get _pendingRecord() {
        if (this._pendingToggleIndex == null) return null;
        return this.records[this._pendingToggleIndex];
    }

    get _isActivating() {
        const rec = this._pendingRecord;
        return rec ? rec.SBQQ__Active__c === false : false;
    }

    get confirmTitle() {
        return this._isActivating ? 'Activate Quote Term' : 'Inactivate Quote Term';
    }

    get confirmMessage() {
        const rec = this._pendingRecord;
        if (!rec) return '';
        return this._isActivating
            ? `Are you sure you want to activate "${rec.Name}"?`
            : `Are you sure you want to inactivate "${rec.Name}"? This quote term will no longer appear in quotes.`;
    }

    get confirmButtonLabel() {
        return this._isActivating ? 'Activate' : 'Inactivate';
    }

    get confirmButtonVariant() {
        return this._isActivating ? 'brand' : 'destructive';
    }

    handleToggleActive(event) {
        this._pendingToggleIndex = parseInt(event.target.dataset.index, 10);
        this.showConfirmModal = true;
    }

    handleCancelToggle() {
        this.showConfirmModal = false;
        this._pendingToggleIndex = null;
    }

    handleConfirmToggle() {
        const index = this._pendingToggleIndex;
        const rec = this.records[index];
        const newActive = !rec.SBQQ__Active__c;

        // Close modal
        this.showConfirmModal = false;
        this._pendingToggleIndex = null;

        // Save the single record toggle immediately
        this.isLoading = true;
        const saveable = {
            Id: rec.Id,
            SBQQ__Active__c: newActive
        };

        saveQuoteTerms({ recordsJson: JSON.stringify([saveable]) })
            .then(() => {
                const actionLabel = newActive ? 'activated' : 'inactivated';
                this.showToast('Success', `"${rec.Name}" has been ${actionLabel}.`, 'success');
                this.loadRecords();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to update: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.records = this.records.map((rec, i) => {
            if (i === index) return { ...rec, [field]: value };
            return rec;
        });
    }

    handleSave() {
        const recordsToSave = this.records.map(rec => {
            const saveable = {};
            if (rec.Id) saveable.Id = rec.Id;
            saveable.SBQQ__Body__c = rec.SBQQ__Body__c;
            saveable.SBQQ__Active__c = rec.SBQQ__Active__c;
            saveable.SBQQ__PrintOrder__c = rec.SBQQ__PrintOrder__c;
            saveable.SBQQ__Status__c = rec.SBQQ__Status__c;
            saveable.Term_Category__c = rec.Term_Category__c;
            saveable.Description__c = rec.Description__c;
            return saveable;
        });

        this.isLoading = true;

        saveQuoteTerms({ recordsJson: JSON.stringify(recordsToSave) })
            .then(() => {
                this.showToast('Success', 'Quote terms saved successfully!', 'success');
                this.loadRecords();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}