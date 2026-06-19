import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProductsFiltered from '@salesforce/apex/SkuProductController.searchProductsFiltered';
import bulkUpdateSkus from '@salesforce/apex/SkuProductController.bulkUpdateSkus';
import getProductPicklistValues from '@salesforce/apex/SkuProductController.getProductPicklistValues';
import getItemMasterPicklistValues from '@salesforce/apex/SkuProductController.getItemMasterPicklistValues';
import getProductLineOptions from '@salesforce/apex/SkuProductController.getProductLineOptions';
import getProductRollupOptions from '@salesforce/apex/SkuProductController.getProductRollupOptions';

export default class SkuUpdate extends LightningElement {
    // Filter state
    @track filterName = '';
    @track filterCode = '';
    @track filterType = '';
    @track filterActive = '';

    // Data state
    @track records = [];
    @track isLoading = false;
    @track searchPerformed = false;

    // Picklist values
    @track productPicklists = {};
    @track itemMasterPicklists = {};
    @track productLineOpts = [];
    @track productRollupOpts = [];

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
            getProductRollupOptions()
        ])
            .then(([prodPicklists, impPicklists, plOptions, prOptions]) => {
                this.productPicklists = prodPicklists;
                this.itemMasterPicklists = impPicklists;
                this.productLineOpts = plOptions;
                this.productRollupOpts = prOptions;
            })
            .catch(() => { /* silently handle */ });
    }

    // =========================================================================
    // Picklist Options
    // =========================================================================

    buildFilterOptions(picklistMap, fieldName) {
        const values = picklistMap[fieldName] || [];
        return [{ label: 'All', value: '' }, ...values];
    }

    buildFieldOptions(picklistMap, fieldName) {
        const values = picklistMap[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get productTypeFilterOptions() {
        return this.buildFilterOptions(this.productPicklists, 'Product_Type__c');
    }

    get activeFilterOptions() {
        return [
            { label: 'All', value: '' },
            { label: 'Yes', value: 'true' },
            { label: 'No', value: 'false' }
        ];
    }

    // Product Line lookup options (shared by Product2 and Item Master)
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
    get revenueTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'Revenue_Type__c'); }
    get billingTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__BillingType__c'); }
    get chargeTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ChargeType__c'); }
    get subPricingOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__SubscriptionPricing__c'); }
    get subTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__SubscriptionType__c'); }
    get configEventOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ConfigurationEvent__c'); }
    get configTypeOptions() { return this.buildFieldOptions(this.productPicklists, 'SBQQ__ConfigurationType__c'); }

    // Product2 vertical flag picklists
    get legalOptions()      { return this.buildFieldOptions(this.productPicklists, 'Is_Legal__c'); }
    get accountingOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Accounting__c'); }
    get consultingOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Consulting__c'); }
    get ibaOptions()        { return this.buildFieldOptions(this.productPicklists, 'Is_IBA__c'); }
    get pcmOptions()        { return this.buildFieldOptions(this.productPicklists, 'Is_PCM__c'); }
    get realAssetsOptions() { return this.buildFieldOptions(this.productPicklists, 'Is_Real_Assets__c'); }
    get corporateOptions()  { return this.buildFieldOptions(this.productPicklists, 'Iss_Corporate__c'); }

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
    // Computed Properties
    // =========================================================================

    get isSearchDisabled() {
        return this.isLoading;
    }

    get isExportDisabled() {
        return this.records.length === 0;
    }

    get hasRecords() {
        return this.records.length > 0;
    }

    get recordCountLabel() {
        const n = this.records.length;
        return n + ' record' + (n !== 1 ? 's' : '');
    }

    get noResultsFound() {
        return this.searchPerformed && this.records.length === 0;
    }

    get showInitialMessage() {
        return !this.searchPerformed;
    }

    get hasChanges() {
        return this.totalChanges > 0;
    }

    get totalChanges() {
        let count = 0;
        for (const rec of this.records) {
            if (Object.keys(rec.changes.product).length > 0 ||
                Object.keys(rec.changes.itemMaster).length > 0) {
                count++;
            }
        }
        return count;
    }

    get totalChangesLabel() {
        const n = this.totalChanges;
        return n + ' unsaved change' + (n !== 1 ? 's' : '');
    }

    // =========================================================================
    // Filter Handlers
    // =========================================================================

    handleFilterNameChange(event) { this.filterName = event.target.value; }
    handleFilterCodeChange(event) { this.filterCode = event.target.value; }
    handleFilterTypeChange(event) { this.filterType = event.target.value; }
    handleFilterActiveChange(event) { this.filterActive = event.target.value; }

    handleFilterKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    // =========================================================================
    // Search
    // =========================================================================

    handleSearch() {
        this.isLoading = true;
        searchProductsFiltered({
            productName: this.filterName || null,
            productCode: this.filterCode || null,
            productType: this.filterType || null,
            isActive: this.filterActive || null
        })
            .then(results => {
                this.records = results.map((wrapper, index) => this.buildRow(wrapper, index));
                this.searchPerformed = true;
            })
            .catch(error => {
                this.showToast('Error', 'Search failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    buildRow(wrapper, index) {
        const product = wrapper.product ? { ...wrapper.product } : {};
        const itemMaster = wrapper.itemMaster ? { ...wrapper.itemMaster } : null;

        return {
            rowIndex: index,
            product: product,
            itemMaster: itemMaster,
            // Flat display properties for synced IM fields (ensures LWC reactivity)
            imItemName: itemMaster ? (itemMaster.Item_Name__c || '') : '',
            imDesc: itemMaster ? (itemMaster.Description__c || '') : '',
            changes: {
                product: {},
                itemMaster: {}
            },
            // Product2 core CSS classes
            nameClass: '',
            codeClass: '',
            descClass: '',
            activeClass: 'cell-checkbox',
            productLineClass: '',
            groupClass: '',
            ptypeClass: '',
            revenueTypeClass: '',
            rollupClass: '',
            // Product2 config CSS classes
            licenseClass: '',
            pricingClass: '',
            servicesClass: '',
            guidedClass: '',
            cloudAddendumClass: 'cell-checkbox',
            eligiblePremiumClass: 'cell-checkbox',
            includesAssistClass: 'cell-checkbox',
            parentBundleClass: 'cell-checkbox',
            pctAcvClass: '',
            // Product2 CPQ CSS classes
            billingTypeClass: '',
            chargeTypeClass: '',
            componentClass: 'cell-checkbox',
            configEventClass: '',
            configTypeClass: '',
            defaultPricingTableClass: '',
            optionalClass: 'cell-checkbox',
            priceEditableClass: 'cell-checkbox',
            subPricingClass: '',
            subTermClass: '',
            subTypeClass: '',
            // Product2 vertical flags CSS classes
            legalClass: '',
            accountingClass: '',
            consultingClass: '',
            ibaClass: '',
            pcmClass: '',
            primeClass: 'cell-checkbox',
            realAssetsClass: '',
            corporateClass: '',
            avaTaxCodeClass: '',
            // Item Master CSS classes
            imItemNameClass: '',
            imActiveClass: 'cell-checkbox',
            imDescClass: '',
            imImpNumberClass: '',
            imRevenueTypeClass: '',
            imItemRevCategoryClass: '',
            imProductLineClass: '',
            imNsTypeClass: '',
            imNsSubTypeClass: '',
            imNsInternalIdClass: '',
            imNsProductLineClass: '',
            imCreateRevPlansClass: '',
            imDeferredRevAcctClass: '',
            imIncomeAcctClass: '',
            imNsAllocTypeClass: '',
            imNsBillingSchedClass: '',
            imNsCanFulfillClass: 'cell-checkbox',
            imNsDirectRevPostClass: 'cell-checkbox',
            imNsExportOaClass: 'cell-checkbox',
            imNsInclChildrenClass: 'cell-checkbox',
            imNsItemTypeInvClass: '',
            imNsRevRecTmplClass: '',
            imNsTaxSchedClass: '',
            imNsErrorClass: '',
            imOaBillingRuleClass: '',
            imRevRecForecastClass: '',
            imRevAllocGroupClass: '',
            imRevRecRuleClass: '',
            imSyncNsClass: 'cell-checkbox',
            imTaxCodeClass: ''
        };
    }

    // =========================================================================
    // Field Change Handling
    // =========================================================================

    handleFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const objectType = event.target.dataset.object;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.records = this.records.map((rec, i) => {
            if (i === index) {
                const updatedRec = { ...rec };

                if (objectType === 'product') {
                    updatedRec.product = { ...rec.product, [field]: value };
                    updatedRec.changes = {
                        ...rec.changes,
                        product: { ...rec.changes.product, [field]: value }
                    };
                    // Keep SBQQ__TaxCode__c in sync with AVA_SFCPQ__TaxCode__c
                    if (field === 'AVA_SFCPQ__TaxCode__c') {
                        updatedRec.product = { ...updatedRec.product, SBQQ__TaxCode__c: value };
                        updatedRec.changes = {
                            ...updatedRec.changes,
                            product: { ...updatedRec.changes.product, SBQQ__TaxCode__c: value }
                        };
                    }
                    // Sync Product Name → IM Item Name, and Description → IM Description
                    if ((field === 'Name' || field === 'Description') && rec.itemMaster) {
                        const imField = field === 'Name' ? 'Item_Name__c' : 'Description__c';
                        updatedRec.itemMaster = { ...updatedRec.itemMaster, [imField]: value };
                        updatedRec.changes = {
                            ...updatedRec.changes,
                            itemMaster: { ...updatedRec.changes.itemMaster, [imField]: value }
                        };
                        // Update flat display props so LWC reactivity fires reliably
                        if (field === 'Name') updatedRec.imItemName = value;
                        else updatedRec.imDesc = value;
                    }
                } else if (objectType === 'itemMaster' && rec.itemMaster) {
                    updatedRec.itemMaster = { ...rec.itemMaster, [field]: value };
                    updatedRec.changes = {
                        ...rec.changes,
                        itemMaster: { ...rec.changes.itemMaster, [field]: value }
                    };
                    // Keep flat display props in sync with direct IM edits
                    if (field === 'Item_Name__c') updatedRec.imItemName = value;
                    if (field === 'Description__c') updatedRec.imDesc = value;
                }

                this.recomputeCellClasses(updatedRec);
                return updatedRec;
            }
            return rec;
        });
    }

    recomputeCellClasses(rec) {
        const pc = rec.changes.product;
        const ic = rec.changes.itemMaster;
        const changed = 'cell-changed';
        const cb = 'cell-checkbox';
        const cbChanged = 'cell-checkbox cell-changed';

        // Product2 core fields
        rec.nameClass = pc.Name !== undefined ? changed : '';
        rec.codeClass = pc.ProductCode !== undefined ? changed : '';
        rec.descClass = pc.Description !== undefined ? changed : '';
        rec.activeClass = pc.IsActive !== undefined ? cbChanged : cb;
        rec.productLineClass = pc.Product_LineNew__c !== undefined ? changed : '';
        rec.groupClass = pc.Product_Group__c !== undefined ? changed : '';
        rec.ptypeClass = pc.Product_Type__c !== undefined ? changed : '';
        rec.revenueTypeClass = pc.Revenue_Type__c !== undefined ? changed : '';
        rec.rollupClass = pc.ProductRollup__c !== undefined ? changed : '';

        // Product2 config fields
        rec.licenseClass = pc.Product_License_Type__c !== undefined ? changed : '';
        rec.pricingClass = pc.Pricing_Basis__c !== undefined ? changed : '';
        rec.servicesClass = pc.Services_Product_Type__c !== undefined ? changed : '';
        rec.guidedClass = pc.Guided_Selling_Type__c !== undefined ? changed : '';
        rec.cloudAddendumClass = pc.Cloud_Addendum_Required__c !== undefined ? cbChanged : cb;
        rec.eligiblePremiumClass = pc.Eligible_For_Premium__c !== undefined ? cbChanged : cb;
        rec.includesAssistClass = pc.Includes_Assist__c !== undefined ? cbChanged : cb;
        rec.parentBundleClass = pc.Parent_Of_Bundle__c !== undefined ? cbChanged : cb;
        rec.pctAcvClass = pc.Percentage_of_ACV__c !== undefined ? changed : '';

        // Product2 CPQ fields
        rec.billingTypeClass = pc.SBQQ__BillingType__c !== undefined ? changed : '';
        rec.chargeTypeClass = pc.SBQQ__ChargeType__c !== undefined ? changed : '';
        rec.componentClass = pc.SBQQ__Component__c !== undefined ? cbChanged : cb;
        rec.configEventClass = pc.SBQQ__ConfigurationEvent__c !== undefined ? changed : '';
        rec.configTypeClass = pc.SBQQ__ConfigurationType__c !== undefined ? changed : '';
        rec.defaultPricingTableClass = pc.SBQQ__DefaultPricingTable__c !== undefined ? changed : '';
        rec.optionalClass = pc.SBQQ__Optional__c !== undefined ? cbChanged : cb;
        rec.priceEditableClass = pc.SBQQ__PriceEditable__c !== undefined ? cbChanged : cb;
        rec.subPricingClass = pc.SBQQ__SubscriptionPricing__c !== undefined ? changed : '';
        rec.subTermClass = pc.SBQQ__SubscriptionTerm__c !== undefined ? changed : '';
        rec.subTypeClass = pc.SBQQ__SubscriptionType__c !== undefined ? changed : '';

        // Product2 vertical flags
        rec.legalClass = pc.Is_Legal__c !== undefined ? changed : '';
        rec.accountingClass = pc.Is_Accounting__c !== undefined ? changed : '';
        rec.consultingClass = pc.Is_Consulting__c !== undefined ? changed : '';
        rec.ibaClass = pc.Is_IBA__c !== undefined ? changed : '';
        rec.pcmClass = pc.Is_PCM__c !== undefined ? changed : '';
        rec.primeClass = pc.Is_Prime__c !== undefined ? cbChanged : cb;
        rec.realAssetsClass = pc.Is_Real_Assets__c !== undefined ? changed : '';
        rec.corporateClass = pc.Iss_Corporate__c !== undefined ? changed : '';
        rec.avaTaxCodeClass = pc.AVA_SFCPQ__TaxCode__c !== undefined ? changed : '';

        // Item Master fields
        rec.imItemNameClass = ic.Item_Name__c !== undefined ? changed : '';
        rec.imActiveClass = ic.Active__c !== undefined ? cbChanged : cb;
        rec.imDescClass = ic.Description__c !== undefined ? changed : '';
        rec.imImpNumberClass = ic.Intapp_Item_Master_Number_Text__c !== undefined ? changed : '';
        rec.imRevenueTypeClass = ic.Revenue_Type__c !== undefined ? changed : '';
        rec.imItemRevCategoryClass = ic.Item_Revenue_Category__c !== undefined ? changed : '';
        rec.imProductLineClass = ic.Product_LineNew__c !== undefined ? changed : '';
        rec.imNsTypeClass = ic.NetSuite_Type__c !== undefined ? changed : '';
        rec.imNsSubTypeClass = ic.NetSuite_SubType__c !== undefined ? changed : '';
        rec.imNsInternalIdClass = ic.NetSuite_Internal_Id__c !== undefined ? changed : '';
        rec.imNsProductLineClass = ic.NetSuite_Product_Line_no_hierarchy__c !== undefined ? changed : '';
        rec.imCreateRevPlansClass = ic.Create_Revenue_Plans_On__c !== undefined ? changed : '';
        rec.imDeferredRevAcctClass = ic.Deferred_Revenue_Account__c !== undefined ? changed : '';
        rec.imIncomeAcctClass = ic.Income_Account__c !== undefined ? changed : '';
        rec.imNsAllocTypeClass = ic.NetSuite_Allocation_Type__c !== undefined ? changed : '';
        rec.imNsBillingSchedClass = ic.NetSuite_Billing_Schedule__c !== undefined ? changed : '';
        rec.imNsCanFulfillClass = ic.NetSuite_Can_be_fulfilled__c !== undefined ? cbChanged : cb;
        rec.imNsDirectRevPostClass = ic.NetSuite_Direct_Revenue_Posting__c !== undefined ? cbChanged : cb;
        rec.imNsExportOaClass = ic.NetSuite_Export_to_OpenAir__c !== undefined ? cbChanged : cb;
        rec.imNsInclChildrenClass = ic.NetSuite_Include_Children__c !== undefined ? cbChanged : cb;
        rec.imNsItemTypeInvClass = ic.NetSuite_Item_Type_For_Invoicing__c !== undefined ? changed : '';
        rec.imNsRevRecTmplClass = ic.NetSuite_Revenue_Recognition_Template__c !== undefined ? changed : '';
        rec.imNsTaxSchedClass = ic.NetSuite_Tax_Schedule__c !== undefined ? changed : '';
        rec.imNsErrorClass = ic.NS_Error__c !== undefined ? changed : '';
        rec.imOaBillingRuleClass = ic.OpenAir_Billing_Rule__c !== undefined ? changed : '';
        rec.imRevRecForecastClass = ic.Rev_Rec_Forecast_Rule__c !== undefined ? changed : '';
        rec.imRevAllocGroupClass = ic.Revenue_Allocation_Group__c !== undefined ? changed : '';
        rec.imRevRecRuleClass = ic.Revenue_Recognition_Rule__c !== undefined ? changed : '';
        rec.imSyncNsClass = ic.Sync_NetSuite__c !== undefined ? cbChanged : cb;
        rec.imTaxCodeClass = ic.TaxCode__c !== undefined ? changed : '';
    }

    // =========================================================================
    // Save & Discard
    // =========================================================================

    handleSave() {
        const changedRows = this.records
            .filter(r =>
                Object.keys(r.changes.product).length > 0 ||
                Object.keys(r.changes.itemMaster).length > 0
            )
            .map(r => ({
                productId: r.product.Id,
                itemMasterId: r.itemMaster ? r.itemMaster.Id : null,
                productFields: Object.keys(r.changes.product).length > 0 ? r.changes.product : null,
                itemMasterFields: Object.keys(r.changes.itemMaster).length > 0 ? r.changes.itemMaster : null
            }));

        if (changedRows.length === 0) {
            this.showToast('Info', 'No changes to save.', 'info');
            return;
        }

        this.isLoading = true;
        bulkUpdateSkus({ recordsJson: JSON.stringify(changedRows) })
            .then(() => {
                this.showToast('Success', changedRows.length + ' SKU record(s) updated successfully!', 'success');
                this.handleSearch();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
                this.isLoading = false;
            });
    }

    handleDiscardChanges() {
        this.handleSearch();
    }

    handleExport() {
        if (this.records.length === 0) {
            this.showToast('Info', 'No records to export.', 'info');
            return;
        }

        const columns = [
            // Product2 Core Fields
            { header: 'Product Name', section: 'product', getValue: r => r.product.Name || '' },
            { header: 'Product Code', section: 'product', getValue: r => r.product.ProductCode || '' },
            { header: 'Description', section: 'product', getValue: r => r.product.Description || '' },
            { header: 'Active', section: 'product', getValue: r => this.fmtBool(r.product.IsActive) },
            { header: 'Product Line', section: 'product', getValue: r => (r.product.Product_LineNew__r ? r.product.Product_LineNew__r.Name : '') || '' },
            { header: 'Product Group', section: 'product', getValue: r => r.product.Product_Group__c || '' },
            { header: 'Product Type', section: 'product', getValue: r => r.product.Product_Type__c || '' },
            { header: 'Revenue Type', section: 'product', getValue: r => r.product.Revenue_Type__c || '' },
            { header: 'Product Rollup', section: 'product', getValue: r => (r.product.ProductRollup__r ? r.product.ProductRollup__r.Name : '') || '' },
            // Product2 Config Fields
            { header: 'License Type', section: 'product', getValue: r => r.product.Product_License_Type__c || '' },
            { header: 'Pricing Basis', section: 'product', getValue: r => r.product.Pricing_Basis__c || '' },
            { header: 'Services Type', section: 'product', getValue: r => r.product.Services_Product_Type__c || '' },
            { header: 'Guided Selling', section: 'product', getValue: r => r.product.Guided_Selling_Type__c || '' },
            { header: 'Cloud Addendum Req', section: 'product', getValue: r => this.fmtBool(r.product.Cloud_Addendum_Required__c) },
            { header: 'Eligible Premium', section: 'product', getValue: r => this.fmtBool(r.product.Eligible_For_Premium__c) },
            { header: 'Includes Assist', section: 'product', getValue: r => this.fmtBool(r.product.Includes_Assist__c) },
            { header: 'Parent Of Bundle', section: 'product', getValue: r => this.fmtBool(r.product.Parent_Of_Bundle__c) },
            { header: 'Prime', section: 'product', getValue: r => this.fmtBool(r.product.Is_Prime__c) },
            { header: '% of ACV', section: 'product', type: 'Number', getValue: r => r.product.Percentage_of_ACV__c },
            // Product2 CPQ Fields
            { header: 'Billing Type', section: 'product', getValue: r => r.product.SBQQ__BillingType__c || '' },
            { header: 'Charge Type', section: 'product', getValue: r => r.product.SBQQ__ChargeType__c || '' },
            { header: 'Component', section: 'product', getValue: r => this.fmtBool(r.product.SBQQ__Component__c) },
            { header: 'Config Event', section: 'product', getValue: r => r.product.SBQQ__ConfigurationEvent__c || '' },
            { header: 'Config Type', section: 'product', getValue: r => r.product.SBQQ__ConfigurationType__c || '' },
            { header: 'Default Pricing Tbl', section: 'product', getValue: r => r.product.SBQQ__DefaultPricingTable__c || '' },
            { header: 'Optional', section: 'product', getValue: r => this.fmtBool(r.product.SBQQ__Optional__c) },
            { header: 'Price Editable', section: 'product', getValue: r => this.fmtBool(r.product.SBQQ__PriceEditable__c) },
            { header: 'Sub Pricing', section: 'product', getValue: r => r.product.SBQQ__SubscriptionPricing__c || '' },
            { header: 'Sub Term', section: 'product', type: 'Number', getValue: r => r.product.SBQQ__SubscriptionTerm__c },
            { header: 'Sub Type', section: 'product', getValue: r => r.product.SBQQ__SubscriptionType__c || '' },
            // Product2 Vertical Flags
            { header: 'Legal', section: 'product', getValue: r => r.product.Is_Legal__c || '' },
            { header: 'Accounting', section: 'product', getValue: r => r.product.Is_Accounting__c || '' },
            { header: 'Consulting', section: 'product', getValue: r => r.product.Is_Consulting__c || '' },
            { header: 'IBA', section: 'product', getValue: r => r.product.Is_IBA__c || '' },
            { header: 'PCM', section: 'product', getValue: r => r.product.Is_PCM__c || '' },
            { header: 'Real Assets', section: 'product', getValue: r => r.product.Is_Real_Assets__c || '' },
            { header: 'Corporate', section: 'product', getValue: r => r.product.Iss_Corporate__c || '' },
            { header: 'Avalara Tax Code', section: 'product', getValue: r => r.product.AVA_SFCPQ__TaxCode__c || '' },
            // Item Master Core Fields
            { header: 'IM: Product Item Name', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Name || '') : '' },
            { header: 'IM: Item Name', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Item_Name__c || '') : '' },
            { header: 'IM: Active', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.Active__c) : '' },
            { header: 'IM: Description', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Description__c || '') : '' },
            { header: 'IM: IMP Number', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Intapp_Item_Master_Number_Text__c || '') : '' },
            // Item Master Revenue Fields
            { header: 'IM: Revenue Type', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Revenue_Type__c || '') : '' },
            { header: 'IM: Item Rev Category', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Item_Revenue_Category__c || '') : '' },
            { header: 'IM: Product Line', section: 'im', getValue: r => r.itemMaster && r.itemMaster.Product_LineNew__r ? (r.itemMaster.Product_LineNew__r.Name || '') : '' },
            // Item Master NetSuite Fields
            { header: 'IM: NS Type', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Type__c || '') : '' },
            { header: 'IM: NS SubType', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_SubType__c || '') : '' },
            { header: 'IM: NS Internal Id', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Internal_Id__c || '') : '' },
            { header: 'IM: NS Product Line', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Product_Line_no_hierarchy__c || '') : '' },
            { header: 'IM: Create Rev Plans On', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Create_Revenue_Plans_On__c || '') : '' },
            { header: 'IM: Deferred Rev Acct', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Deferred_Revenue_Account__c || '') : '' },
            { header: 'IM: Income Account', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Income_Account__c || '') : '' },
            { header: 'IM: NS Allocation Type', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Allocation_Type__c || '') : '' },
            { header: 'IM: NS Billing Sched', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Billing_Schedule__c || '') : '' },
            { header: 'IM: NS Can Fulfill', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.NetSuite_Can_be_fulfilled__c) : '' },
            { header: 'IM: NS Direct Rev Post', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.NetSuite_Direct_Revenue_Posting__c) : '' },
            { header: 'IM: NS Export OpenAir', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.NetSuite_Export_to_OpenAir__c) : '' },
            { header: 'IM: NS Incl Children', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.NetSuite_Include_Children__c) : '' },
            { header: 'IM: NS Item Type Inv', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Item_Type_For_Invoicing__c || '') : '' },
            { header: 'IM: NS Rev Rec Tmpl', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Revenue_Recognition_Template__c || '') : '' },
            { header: 'IM: NS Tax Schedule', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NetSuite_Tax_Schedule__c || '') : '' },
            { header: 'IM: NS Error', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.NS_Error__c || '') : '' },
            // Item Master Other Fields
            { header: 'IM: OA Billing Rule', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.OpenAir_Billing_Rule__c || '') : '' },
            { header: 'IM: Rev Rec Forecast', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Rev_Rec_Forecast_Rule__c || '') : '' },
            { header: 'IM: Rev Alloc Group', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Revenue_Allocation_Group__c || '') : '' },
            { header: 'IM: Rev Rec Rule', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.Revenue_Recognition_Rule__c || '') : '' },
            { header: 'IM: Sync NetSuite', section: 'im', getValue: r => r.itemMaster ? this.fmtBool(r.itemMaster.Sync_NetSuite__c) : '' },
            { header: 'IM: Tax Code', section: 'im', getValue: r => r.itemMaster ? (r.itemMaster.TaxCode__c || '') : '' }
        ];

        // Build XML Spreadsheet (Excel 2003 XML) and trigger download
        const xml = this.buildExcelXml(columns);
        const encoded = encodeURIComponent(xml);
        const link = document.createElement('a');
        link.setAttribute('href', 'data:application/vnd.ms-excel;charset=utf-8,' + encoded);
        link.setAttribute('download', 'SKU_Export_' + new Date().toISOString().slice(0, 10) + '.xls');
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        this.showToast('Success', this.records.length + ' record(s) exported to Excel.', 'success');
    }

    // =========================================================================
    // Excel Export Helpers
    // =========================================================================

    buildExcelXml(columns) {
        const colWidths = columns.map(c => {
            const w = c.header.length * 8;
            return w < 80 ? 80 : (w > 200 ? 200 : w);
        });

        let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<?mso-application progid="Excel.Sheet"?>\n';
        xml += '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"';
        xml += ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">\n';

        // Styles
        xml += '<Styles>\n';
        xml += '<Style ss:ID="Default" ss:Name="Normal"><Font ss:Size="10"/></Style>\n';
        // Product header — teal
        xml += '<Style ss:ID="hdrP">';
        xml += '<Font ss:Bold="1" ss:Color="#FFFFFF" ss:Size="10"/>';
        xml += '<Interior ss:Color="#0B7B6D" ss:Pattern="Solid"/>';
        xml += '<Alignment ss:Horizontal="Center" ss:WrapText="1"/>';
        xml += '<Borders>';
        xml += '<Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#085A4E"/>';
        xml += '<Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#085A4E"/>';
        xml += '</Borders>';
        xml += '</Style>\n';
        // Item Master header — darker teal
        xml += '<Style ss:ID="hdrIM">';
        xml += '<Font ss:Bold="1" ss:Color="#FFFFFF" ss:Size="10"/>';
        xml += '<Interior ss:Color="#096558" ss:Pattern="Solid"/>';
        xml += '<Alignment ss:Horizontal="Center" ss:WrapText="1"/>';
        xml += '<Borders>';
        xml += '<Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#074E43"/>';
        xml += '<Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#074E43"/>';
        xml += '</Borders>';
        xml += '</Style>\n';
        // Data cell
        xml += '<Style ss:ID="data"><Alignment ss:Vertical="Top" ss:WrapText="1"/></Style>\n';
        // Striped row
        xml += '<Style ss:ID="dataAlt">';
        xml += '<Interior ss:Color="#F5F5F5" ss:Pattern="Solid"/>';
        xml += '<Alignment ss:Vertical="Top" ss:WrapText="1"/>';
        xml += '</Style>\n';
        // Number
        xml += '<Style ss:ID="num"><NumberFormat ss:Format="0.00"/><Alignment ss:Vertical="Top"/></Style>\n';
        xml += '<Style ss:ID="numAlt"><NumberFormat ss:Format="0.00"/>';
        xml += '<Interior ss:Color="#F5F5F5" ss:Pattern="Solid"/>';
        xml += '<Alignment ss:Vertical="Top"/></Style>\n';
        xml += '</Styles>\n';

        // Worksheet
        xml += '<Worksheet ss:Name="SKU Export">\n';
        xml += '<Table ss:DefaultRowHeight="15">\n';

        // Column widths
        for (const w of colWidths) {
            xml += '<Column ss:Width="' + w + '"/>\n';
        }

        // Header row
        xml += '<Row ss:Height="30">\n';
        for (const col of columns) {
            const style = col.section === 'im' ? 'hdrIM' : 'hdrP';
            xml += '<Cell ss:StyleID="' + style + '">';
            xml += '<Data ss:Type="String">' + this.escXml(col.header) + '</Data></Cell>\n';
        }
        xml += '</Row>\n';

        // Data rows
        this.records.forEach((rec, idx) => {
            const isAlt = idx % 2 === 1;
            const dStyle = isAlt ? 'dataAlt' : 'data';
            const nStyle = isAlt ? 'numAlt' : 'num';
            xml += '<Row>\n';
            for (const col of columns) {
                const val = col.getValue(rec);
                if (col.type === 'Number' && val != null && val !== '') {
                    xml += '<Cell ss:StyleID="' + nStyle + '">';
                    xml += '<Data ss:Type="Number">' + val + '</Data></Cell>\n';
                } else {
                    xml += '<Cell ss:StyleID="' + dStyle + '">';
                    xml += '<Data ss:Type="String">' + this.escXml(val == null ? '' : String(val)) + '</Data></Cell>\n';
                }
            }
            xml += '</Row>\n';
        });

        xml += '</Table>\n';

        // Auto-filter
        xml += '<AutoFilter xmlns="urn:schemas-microsoft-com:office:excel"';
        xml += ' x:Range="R1C1:R1C' + columns.length + '"';
        xml += ' xmlns:x="urn:schemas-microsoft-com:office:excel"/>\n';

        // Freeze top row
        xml += '<WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">';
        xml += '<FreezePanes/><FrozenNoSplit/>';
        xml += '<SplitHorizontal>1</SplitHorizontal>';
        xml += '<TopRowBottomPane>1</TopRowBottomPane>';
        xml += '</WorksheetOptions>\n';

        xml += '</Worksheet>\n</Workbook>';
        return xml;
    }

    escXml(str) {
        if (!str) return '';
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    fmtBool(value) {
        if (value === true) return 'Yes';
        if (value === false) return 'No';
        return '';
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