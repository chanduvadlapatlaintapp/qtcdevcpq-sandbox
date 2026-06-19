import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteTermsByProductCode from '@salesforce/apex/SkuQuoteTermController.getQuoteTermsByProductCode';
import saveQuoteTerms from '@salesforce/apex/SkuQuoteTermController.saveQuoteTerms';
import getQuoteTermPicklists from '@salesforce/apex/SkuQuoteTermController.getQuoteTermPicklists';

export default class SkuProductQuoteTerms extends LightningElement {
    @api productCode;

    @track records = [];
    @track isLoading = false;
    @track picklists = {};
    @track isDirty = false;

    connectedCallback() {
        this.loadPicklists();
        if (this.productCode) {
            this.loadRecords();
        }
    }

    // =========================================================================
    // Data Loading
    // =========================================================================

    loadPicklists() {
        getQuoteTermPicklists()
            .then(result => {
                this.picklists = result;
            })
            .catch(() => { /* silently handle */ });
    }

    loadRecords() {
        if (!this.productCode) return;
        this.isLoading = true;

        getQuoteTermsByProductCode({ productCode: this.productCode })
            .then(result => {
                this.records = result.map((rec, i) => ({ ...rec, rowIndex: i }));
                this.isDirty = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load quote terms: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Picklist Options
    // =========================================================================

    buildFieldOptions(fieldName) {
        const values = this.picklists[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get statusFieldOptions() { return this.buildFieldOptions('SBQQ__Status__c'); }
    get categoryOptions() { return this.buildFieldOptions('Term_Category__c'); }

    // =========================================================================
    // Computed
    // =========================================================================

    get hasRecords() { return this.records.length > 0; }
    get recordCountLabel() {
        const n = this.records.length;
        return n + ' quote term' + (n !== 1 ? 's' : '') + ' found';
    }

    // =========================================================================
    // Handlers
    // =========================================================================

    handleFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.records = this.records.map((rec, i) => {
            if (i === index) return { ...rec, [field]: value };
            return rec;
        });
        this.isDirty = true;
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
                this.isDirty = false;
                this.loadRecords();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Utilities
    // =========================================================================

    extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}