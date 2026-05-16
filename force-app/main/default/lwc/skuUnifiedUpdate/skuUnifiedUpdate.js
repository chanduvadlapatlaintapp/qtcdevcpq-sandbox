import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/SkuLookupController.searchProducts';
import getSkuDetails from '@salesforce/apex/SkuProductController.getSkuDetails';
import updateSku from '@salesforce/apex/SkuProductController.updateSku';
import getProductPicklistValues from '@salesforce/apex/SkuProductController.getProductPicklistValues';
import getItemMasterPicklistValues from '@salesforce/apex/SkuProductController.getItemMasterPicklistValues';
import getProductLineOptions from '@salesforce/apex/SkuProductController.getProductLineOptions';
import getProductRollupOptions from '@salesforce/apex/SkuProductController.getProductRollupOptions';
import getFieldHelpText from '@salesforce/apex/SkuProductController.getFieldHelpText';
import getMeterTypeRecord from '@salesforce/apex/SkuBlockPricingController.getMeterTypeRecord';
import saveMeterTypeRecords from '@salesforce/apex/SkuBlockPricingController.saveMeterTypeRecords';
import getBlockPricingPicklists from '@salesforce/apex/SkuBlockPricingController.getBlockPricingPicklists';

export default class SkuUnifiedUpdate extends LightningElement {
    // =========================================================================
    // Public API
    // =========================================================================

    _preselectedProductId;
    @api
    get preselectedProductId() {
        return this._preselectedProductId;
    }
    set preselectedProductId(value) {
        this._preselectedProductId = value;
        if (value && value !== this.selectedProductId) {
            this.selectedProductId = value;
            this.loadProductData();
        }
    }


    // =========================================================================
    // State
    // =========================================================================

    @track selectedProductId;
    @track productCode;
    @track isLoading = false;

    // Data
    @track product = {};
    @track itemMaster = {};
    @track meterTypeRecord = null;

    // Change tracking
    @track productChanges = {};
    @track itemMasterChanges = {};
    @track meterTypeChanges = {};

    // Picklists
    @track productPicklists = {};
    @track itemMasterPicklists = {};
    @track productLineOpts = [];
    @track productRollupOpts = [];
    @track blockPricingPicklists = {};

    // Field help text
    @track productHelpText = {};
    @track itemMasterHelpText = {};

    // Accordion
    @track activeSections = [];

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadPicklistValues();
    }

    loadPicklistValues() {
        Promise.all([
            getProductPicklistValues(),
            getItemMasterPicklistValues(),
            getProductLineOptions(),
            getProductRollupOptions(),
            getBlockPricingPicklists(),
            getFieldHelpText()
        ])
            .then(([prodPicklists, impPicklists, plOptions, prOptions, bpPicklists, helpText]) => {
                this.productPicklists = prodPicklists;
                this.itemMasterPicklists = impPicklists;
                this.productLineOpts = plOptions;
                this.productRollupOpts = prOptions;
                this.blockPricingPicklists = bpPicklists;
                this.productHelpText = helpText.product || {};
                this.itemMasterHelpText = helpText.itemMaster || {};
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
                const lookup = this.template.querySelector('c-lookup[data-id="unifiedProductLookup"]');
                if (lookup) lookup.setSearchResults(results);
            })
            .catch(error => {
                this.showToast('Error', 'Search failed: ' + this.extractError(error), 'error');
            });
    }

    handleProductSelected(event) {
        const productId = event.detail && event.detail.value;
        if (productId) {
            if (this.hasProductChanges) {
                // eslint-disable-next-line no-alert
                if (!confirm('You have unsaved changes. Switch product and discard changes?')) {
                    return;
                }
            }
            this.selectedProductId = productId;
            this.loadProductData();
        } else {
            this.selectedProductId = null;
            this.product = {};
            this.itemMaster = {};
            this.meterTypeRecord = null;
            this.productCode = null;
            this.productChanges = {};
            this.itemMasterChanges = {};
            this.meterTypeChanges = {};
        }
    }

    loadProductData() {
        if (!this.selectedProductId) return;
        this.isLoading = true;

        Promise.all([
            getSkuDetails({ productId: this.selectedProductId }),
            getMeterTypeRecord({ productId: this.selectedProductId })
        ])
            .then(([wrapper, mtRecord]) => {
                this.product = wrapper.product ? { ...wrapper.product } : {};
                this.itemMaster = wrapper.itemMaster ? { ...wrapper.itemMaster } : {};
                this.productCode = this.product.ProductCode || null;
                this.meterTypeRecord = mtRecord ? { ...mtRecord } : null;
                this.productChanges = {};
                this.itemMasterChanges = {};
                this.meterTypeChanges = {};

            })
            .catch(error => {
                this.showToast('Error', 'Failed to load product: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Computed Properties
    // =========================================================================

    get isProductSelected() { return !!this.selectedProductId; }
    get isNotMultiEntry() { return false; }
    get isQuantityBased() { return this.product && this.product.Pricing_Basis__c === 'Quantity based'; }

    get hasItemMaster() {
        return this.itemMaster && this.itemMaster.Id;
    }

    get hasProductChanges() {
        return Object.keys(this.productChanges).length > 0 ||
            Object.keys(this.itemMasterChanges).length > 0 ||
            Object.keys(this.meterTypeChanges).length > 0;
    }

    get hasMeterTypeRecord() {
        return !!this.meterTypeRecord;
    }

    get productBannerStatusClass() {
        return this.product.IsActive ? 'product-banner__badge badge-active' : 'product-banner__badge badge-inactive';
    }

    get productBannerStatusLabel() {
        return this.product.IsActive ? 'Active' : 'Inactive';
    }

    get productLineName() {
        return this.product.Product_LineNew__r ? this.product.Product_LineNew__r.Name : '';
    }

    get imProductLineName() {
        return this.itemMaster && this.itemMaster.Product_LineNew__r
            ? this.itemMaster.Product_LineNew__r.Name : '';
    }

    // =========================================================================
    // Picklist Options (mirrored from skuUpdate.js)
    // =========================================================================

    buildFieldOptions(picklistMap, fieldName) {
        const values = picklistMap[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get productLineOptions() {
        const opts = (this.productLineOpts || []).map(o => ({ label: o.label, value: o.value }));
        return [{ label: '--None--', value: '' }, ...opts];
    }

    // Product2 field picklists
    get productRollupOptions() {
        const opts = (this.productRollupOpts || []).map(o => ({ label: o.label, value: o.value }));
        return [{ label: '--None--', value: '' }, ...opts];
    }
    get productGroupOptions() { return this.buildFieldOptions(this.productPicklists, 'Product_Group__c'); }
    get productTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Product_Type__c'); }
    get productLicenseTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Product_License_Type__c'); }
    get pricingBasisOptions() { return this.buildFieldOptions(this.productPicklists, 'Pricing_Basis__c'); }
    get servicesProductTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Services_Product_Type__c'); }
    get guidedSellingTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Guided_Selling_Type__c'); }
    get billingTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__BillingType__c'); }
    get chargeTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ChargeType__c'); }
    get subPricingOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__SubscriptionPricing__c'); }
    get subTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__SubscriptionType__c'); }
    get revenueTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Revenue_Type__c'); }
    get configEventOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ConfigurationEvent__c'); }
    get configTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ConfigurationType__c'); }

    // System field getters (relationship fields need JS access, not template dot-notation)
    get productCreatedByName() { return this.product?.CreatedBy?.Name || ''; }
    get productLastModifiedByName() { return this.product?.LastModifiedBy?.Name || ''; }
    get productCreatedDate() { return this._formatDate(this.product?.CreatedDate); }
    get productLastModifiedDate() { return this._formatDate(this.product?.LastModifiedDate); }

    // Item Master system field getters
    get imCreatedByName() { return this.itemMaster?.CreatedBy?.Name || ''; }
    get imLastModifiedByName() { return this.itemMaster?.LastModifiedBy?.Name || ''; }
    get imCreatedDate() { return this._formatDate(this.itemMaster?.CreatedDate); }
    get imLastModifiedDate() { return this._formatDate(this.itemMaster?.LastModifiedDate); }

    _formatDate(isoString) {
        if (!isoString) return '';
        try {
            const d = new Date(isoString);
            return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
                + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        } catch (e) { return isoString; }
    }

    // Vertical flags
    get legalOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Legal__c'); }
    get accountingOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Accounting__c'); }
    get consultingOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Consulting__c'); }
    get ibaOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_IBA__c'); }
    get pcmOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_PCM__c'); }
    get realAssetsOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Real_Assets__c'); }
    get corporateOptions() { return this.buildFieldOptions(this.productPicklists, 'Iss_Corporate__c'); }

    // Vertical card classes (color-coded by flag value)
    _verticalCardClass(fieldValue) {
        if (fieldValue === 'Active') return 'v-card v-card--active';
        if (fieldValue === 'Restricted') return 'v-card v-card--restricted';
        if (fieldValue === 'Unavailable') return 'v-card v-card--unavailable';
        return 'v-card';
    }
    get legalCardClass() { return this._verticalCardClass(this.product.Is_Legal__c); }
    get accountingCardClass() { return this._verticalCardClass(this.product.Is_Accounting__c); }
    get consultingCardClass() { return this._verticalCardClass(this.product.Is_Consulting__c); }
    get ibaCardClass() { return this._verticalCardClass(this.product.Is_IBA__c); }
    get pcmCardClass() { return this._verticalCardClass(this.product.Is_PCM__c); }
    get realAssetsCardClass() { return this._verticalCardClass(this.product.Is_Real_Assets__c); }
    get corporateCardClass() { return this._verticalCardClass(this.product.Iss_Corporate__c); }

    // Meter type picklists (from Block_Pricing__c)
    buildMtOptions(fieldName) {
        const values = this.blockPricingPicklists[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }
    get mtLegalGbpEurOptions()  { return this.buildMtOptions('Legal__c'); }
    get mtLegalUsdAudOptions()  { return this.buildMtOptions('Legal_meter_type_USD_AUD__c'); }
    get mtAccountingOptions()   { return this.buildMtOptions('meter_type_Accounting__c'); }
    get mtConsultingOptions()   { return this.buildMtOptions('meter_type_Consulting__c'); }
    get mtCorporateOptions()    { return this.buildMtOptions('meter_type_Corporate__c'); }
    get mtIbaOptions()          { return this.buildMtOptions('meter_type_IBA__c'); }
    get mtPcmOptions()          { return this.buildMtOptions('meter_type_PCM__c'); }
    get mtRealAssetsOptions()   { return this.buildMtOptions('meter_type_RealAssets__c'); }

    // Item Master field picklists
    get imRevenueTypeOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Revenue_Type__c'); }
    get imItemRevCategoryOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Item_Revenue_Category__c'); }
    get imNsTypeOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Type__c'); }
    get imNsSubTypeOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_SubType__c'); }
    get imCreateRevPlansOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Create_Revenue_Plans_On__c'); }
    get imNsAllocTypeOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Allocation_Type__c'); }
    get imNsBillingSchedOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Billing_Schedule__c'); }
    get imNsItemTypeInvOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Item_Type_For_Invoicing__c'); }
    get imNsRevRecTmplOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Revenue_Recognition_Template__c'); }
    get imNsTaxSchedOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'NetSuite_Tax_Schedule__c'); }
    get imOaBillingRuleOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'OpenAir_Billing_Rule__c'); }
    get imRevRecForecastOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Rev_Rec_Forecast_Rule__c'); }
    get imRevAllocGroupOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Revenue_Allocation_Group__c'); }
    get imRevRecRuleOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Revenue_Recognition_Rule__c'); }
    get imIncomeAccountOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Income_Account__c'); }
    get imDeferredRevAccountOptions() { return this.buildFieldOptions(this.itemMasterPicklists, 'Deferred_Revenue_Account__c'); }

    // =========================================================================
    // Product Field Change Handler
    // =========================================================================

    handleProductFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.product = { ...this.product, [field]: value };
        this.productChanges = { ...this.productChanges, [field]: value };

        // Keep SBQQ__TaxCode__c in sync with AVA_SFCPQ__TaxCode__c
        if (field === 'AVA_SFCPQ__TaxCode__c') {
            this.product = { ...this.product, SBQQ__TaxCode__c: value };
            this.productChanges = { ...this.productChanges, SBQQ__TaxCode__c: value };
        }
    }

    // =========================================================================
    // Item Master Field Change Handler
    // =========================================================================

    handleItemMasterFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.itemMaster = { ...this.itemMaster, [field]: value };
        this.itemMasterChanges = { ...this.itemMasterChanges, [field]: value };
    }

    // =========================================================================
    // Meter Type Field Change Handler
    // =========================================================================

    handleMeterTypeFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;

        this.meterTypeRecord = { ...this.meterTypeRecord, [field]: value };
        this.meterTypeChanges = { ...this.meterTypeChanges, [field]: value };
    }

    // =========================================================================
    // Save & Discard
    // =========================================================================

    handleSaveProductFields() {
        if (!this.hasProductChanges) {
            this.showToast('Info', 'No changes to save.', 'info');
            return;
        }

        this.isLoading = true;

        // Build save promises
        const promises = [];

        // Product + Item Master save
        const hasSkuChanges = Object.keys(this.productChanges).length > 0 ||
            Object.keys(this.itemMasterChanges).length > 0;
        if (hasSkuChanges) {
            promises.push(updateSku({
                productFields: Object.keys(this.productChanges).length > 0 ? this.productChanges : null,
                itemMasterFields: Object.keys(this.itemMasterChanges).length > 0 ? this.itemMasterChanges : null,
                productId: this.product.Id,
                itemMasterId: this.hasItemMaster ? this.itemMaster.Id : null
            }));
        }

        // Meter type save
        if (Object.keys(this.meterTypeChanges).length > 0 && this.meterTypeRecord && this.meterTypeRecord.Id) {
            const saveable = {
                Id: this.meterTypeRecord.Id,
                Legal__c: this.meterTypeRecord.Legal__c,
                Legal_meter_type_USD_AUD__c: this.meterTypeRecord.Legal_meter_type_USD_AUD__c,
                meter_type_Accounting__c: this.meterTypeRecord.meter_type_Accounting__c,
                meter_type_Consulting__c: this.meterTypeRecord.meter_type_Consulting__c,
                meter_type_Corporate__c: this.meterTypeRecord.meter_type_Corporate__c,
                meter_type_IBA__c: this.meterTypeRecord.meter_type_IBA__c,
                meter_type_PCM__c: this.meterTypeRecord.meter_type_PCM__c,
                meter_type_RealAssets__c: this.meterTypeRecord.meter_type_RealAssets__c
            };
            promises.push(saveMeterTypeRecords({
                recordsJson: JSON.stringify([saveable]),
                productId: this.selectedProductId
            }));
        }

        Promise.all(promises)
            .then(() => {
                this.showToast('Success', 'Product updated successfully!', 'success');
                this.loadProductData();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDiscardChanges() {
        this.loadProductData();
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