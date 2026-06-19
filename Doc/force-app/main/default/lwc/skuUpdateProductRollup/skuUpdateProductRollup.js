/**
 * @description Update Product Rollup tab — search and update Product_Rollup__c records.
 * @author Yousef Alamin
 * @date 2026-03-28
 * @jira BIZ-80750
 */
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProductRollups from '@salesforce/apex/SkuLookupController.searchProductRollups';
import getProductRollupDetails from '@salesforce/apex/SkuProductRollupController.getProductRollupDetails';
import getProductLineOptions from '@salesforce/apex/SkuProductRollupController.getProductLineOptions';
import updateProductRollup from '@salesforce/apex/SkuProductRollupController.updateProductRollup';

export default class SkuUpdateProductRollup extends LightningElement {

    // =========================================================================
    // Private Properties
    // =========================================================================

    @track isLoading = false;
    @track selectedId = null;
    @track record = {};
    @track changes = {};
    @track productLineOpts = [];
    @track activeSections = ['basicDetails', 'classification', 'settings'];

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadProductLineOptions();
    }

    loadProductLineOptions() {
        getProductLineOptions()
            .then(result => {
                this.productLineOpts = result || [];
            })
            .catch(() => {});
    }

    // =========================================================================
    // Getters
    // =========================================================================

    get isNotMultiEntry() { return false; }
    get isRecordSelected() { return !!this.selectedId; }
    get hasChanges() { return Object.keys(this.changes).length > 0; }

    get productLineName() {
        return this.record.Product_Line__r ? this.record.Product_Line__r.Name : '';
    }

    get productLineOptions() {
        const opts = (this.productLineOpts || []).map(o => ({ label: o.label, value: o.value }));
        return [{ label: '--None--', value: '' }, ...opts];
    }

    get createdByName() { return this.record.CreatedBy ? this.record.CreatedBy.Name : ''; }
    get lastModifiedByName() { return this.record.LastModifiedBy ? this.record.LastModifiedBy.Name : ''; }
    get createdDate() { return this._formatDate(this.record.CreatedDate); }
    get lastModifiedDate() { return this._formatDate(this.record.LastModifiedDate); }

    _formatDate(isoString) {
        if (!isoString) return '';
        try {
            const d = new Date(isoString);
            return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
                + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        } catch (e) { return isoString; }
    }

    // =========================================================================
    // Event Handlers
    // =========================================================================

    handleSearch(event) {
        const term = event.detail.searchTerm || event.detail.rawSearchTerm || '';
        searchProductRollups({ searchTerm: term })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="productRollupLookup"]');
                if (lookup) lookup.setSearchResults(results);
            })
            .catch(() => {});
    }

    handleSelected(event) {
        const id = event.detail && event.detail.value;
        if (id) {
            if (this.hasChanges) {
                // eslint-disable-next-line no-alert
                if (!confirm('You have unsaved changes. Switch record and discard changes?')) return;
            }
            this.selectedId = id;
            this.loadRecord();
        } else {
            this.selectedId = null;
            this.record = {};
            this.changes = {};
        }
    }

    loadRecord() {
        if (!this.selectedId) return;
        this.isLoading = true;
        getProductRollupDetails({ recordId: this.selectedId })
            .then(result => {
                this.record = result ? { ...result } : {};
                this.changes = {};
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load record: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.record = { ...this.record, [field]: value };
        this.changes = { ...this.changes, [field]: value };
    }

    handleSave() {
        if (!this.hasChanges) {
            this.showToast('Info', 'No changes to save.', 'info');
            return;
        }
        this.isLoading = true;
        updateProductRollup({ recordId: this.selectedId, fields: this.changes })
            .then(() => {
                this.showToast('Success', 'Product Rollup updated successfully!', 'success');
                this.loadRecord();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDiscard() {
        this.loadRecord();
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