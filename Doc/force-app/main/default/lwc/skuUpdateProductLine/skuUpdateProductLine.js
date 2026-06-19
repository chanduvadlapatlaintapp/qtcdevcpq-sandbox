/**
 * @description Update Product Line tab — search and update Product_Line__c records.
 * @author Yousef Alamin
 * @date 2026-03-28
 * @jira BIZ-80750
 */
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProductLines from '@salesforce/apex/SkuLookupController.searchProductLines';
import getProductLineDetails from '@salesforce/apex/SkuProductLineController.getProductLineDetails';
import getProductLinePicklists from '@salesforce/apex/SkuProductLineController.getProductLinePicklists';
import updateProductLine from '@salesforce/apex/SkuProductLineController.updateProductLine';

export default class SkuUpdateProductLine extends LightningElement {

    // =========================================================================
    // Private Properties
    // =========================================================================

    @track isLoading = false;
    @track selectedId = null;
    @track record = {};
    @track changes = {};
    @track picklists = {};
    @track activeSections = ['basicDetails', 'classification', 'settings'];

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadPicklists();
    }

    loadPicklists() {
        getProductLinePicklists()
            .then(result => {
                this.picklists = result || {};
            })
            .catch(() => {});
    }

    // =========================================================================
    // Getters
    // =========================================================================

    get isNotMultiEntry() { return false; }
    get isRecordSelected() { return !!this.selectedId; }
    get hasChanges() { return Object.keys(this.changes).length > 0; }

    get activeBadgeClass() {
        return this.record.Active__c ? 'product-banner__badge badge-active' : 'product-banner__badge badge-inactive';
    }

    get activeBadgeLabel() {
        return this.record.Active__c ? 'Active' : 'Inactive';
    }

    _buildOptions(fieldName) {
        const vals = (this.picklists[fieldName] || []);
        return [{ label: '--None--', value: '' }, ...vals.map(v => ({ label: v.label, value: v.value }))];
    }

    get practiceOptions() { return this._buildOptions('Practice__c'); }
    get simpleProductLineOptions() { return this._buildOptions('Simple_Product_Line__c'); }
    get deploymentOptions() { return this._buildOptions('Deployment__c'); }

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
        searchProductLines({ searchTerm: term })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="productLineLookup"]');
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
        getProductLineDetails({ recordId: this.selectedId })
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
        updateProductLine({ recordId: this.selectedId, fields: this.changes })
            .then(() => {
                this.showToast('Success', 'Product Line updated successfully!', 'success');
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