import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/SkuLookupController.searchProducts';
import getMeterTypeRecord from '@salesforce/apex/SkuBlockPricingController.getMeterTypeRecord';
import saveMeterTypeRecords from '@salesforce/apex/SkuBlockPricingController.saveMeterTypeRecords';
import getBlockPricingPicklists from '@salesforce/apex/SkuBlockPricingController.getBlockPricingPicklists';

export default class MeterTypeManager extends LightningElement {
    @api preselectedProductId;
    @api hideLookup = false;
    @track selectedProductId;
    @track record = null;
    @track isLoading = false;
    @track picklists = {};

    connectedCallback() {
        this.loadPicklists();
        if (this.preselectedProductId) {
            this.selectedProductId = this.preselectedProductId;
            this.loadRecord();
        }
    }

    loadPicklists() {
        getBlockPricingPicklists()
            .then(result => {
                this.picklists = result;
            })
            .catch(() => { /* silently handle */ });
    }

    // =========================================================================
    // Product Lookup
    // =========================================================================

    handleProductSearch(event) {
        const searchTerm = event.detail.searchTerm;
        searchProducts({ searchTerm })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="productLookup"]');
                if (lookup) {
                    lookup.setSearchResults(results);
                }
            })
            .catch(error => {
                this.showToast('Error', 'Product search failed: ' + this.extractError(error), 'error');
            });
    }

    handleProductSelected(event) {
        const productId = event.detail && event.detail.value;
        if (productId) {
            this.selectedProductId = productId;
            this.loadRecord();
        } else {
            this.selectedProductId = null;
            this.record = null;
        }
    }

    // =========================================================================
    // Data
    // =========================================================================

    loadRecord() {
        if (!this.selectedProductId) return;
        this.isLoading = true;

        getMeterTypeRecord({ productId: this.selectedProductId })
            .then(result => {
                this.record = result ? { ...result } : null;
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
        this.record = { ...this.record, [field]: event.detail.value };
    }

    handleSave() {
        if (!this.record || !this.record.Id) {
            this.showToast('Error', 'No Meter Type record to save.', 'error');
            return;
        }

        const saveable = {
            Id: this.record.Id,
            Legal__c: this.record.Legal__c,
            Legal_meter_type_USD_AUD__c: this.record.Legal_meter_type_USD_AUD__c,
            meter_type_Accounting__c: this.record.meter_type_Accounting__c,
            meter_type_Consulting__c: this.record.meter_type_Consulting__c,
            meter_type_Corporate__c: this.record.meter_type_Corporate__c,
            meter_type_IBA__c: this.record.meter_type_IBA__c,
            meter_type_PCM__c: this.record.meter_type_PCM__c,
            meter_type_RealAssets__c: this.record.meter_type_RealAssets__c
        };

        this.isLoading = true;

        saveMeterTypeRecords({
            recordsJson: JSON.stringify([saveable]),
            productId: this.selectedProductId
        })
            .then(() => {
                this.showToast('Success', 'Meter Type record saved successfully!', 'success');
                this.loadRecord();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Picklist getters
    // =========================================================================

    buildOptions(fieldName) {
        const values = this.picklists[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get legalGbpEurOptions()  { return this.buildOptions('Legal__c'); }
    get legalUsdAudOptions()  { return this.buildOptions('Legal_meter_type_USD_AUD__c'); }
    get accountingOptions()   { return this.buildOptions('meter_type_Accounting__c'); }
    get consultingOptions()   { return this.buildOptions('meter_type_Consulting__c'); }
    get corporateOptions()    { return this.buildOptions('meter_type_Corporate__c'); }
    get ibaOptions()          { return this.buildOptions('meter_type_IBA__c'); }
    get pcmOptions()          { return this.buildOptions('meter_type_PCM__c'); }
    get realAssetsOptions()   { return this.buildOptions('meter_type_RealAssets__c'); }

    // =========================================================================
    // Computed state
    // =========================================================================

    get isProductSelected() {
        return !!this.selectedProductId;
    }

    get hasRecord() {
        return !!this.record;
    }

    get isNotMultiEntry() { return false; }

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