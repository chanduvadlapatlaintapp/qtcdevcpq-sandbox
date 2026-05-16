import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/SkuLookupController.searchProducts';
import searchProductLines from '@salesforce/apex/SkuLookupController.searchProductLines';
import searchComponentProducts from '@salesforce/apex/SkuBundleController.searchComponentProducts';
import createBundleSku from '@salesforce/apex/SkuBundleController.createBundleSku';
import getProductPicklistValues from '@salesforce/apex/SkuProductController.getProductPicklistValues';
import getItemMasterPicklistValues from '@salesforce/apex/SkuProductController.getItemMasterPicklistValues';
import isItemMasterNameAvailable from '@salesforce/apex/SkuProductController.isItemMasterNameAvailable';

export default class SkuCreateBundle extends LightningElement {
    @track isLoading = false;
    @track productPicklists = {};
    @track itemMasterPicklists = {};
    @track activeSections = ['productIdentity', 'bundleComponents', 'itemMasterProduct'];

    // Product fields
    @track product = {
        Name: '', ProductCode: '', Description: '', IsActive: true,
        Product_Type__c: '', Product_License_Type__c: '', Pricing_Basis__c: '',
        Product_Group__c: '', Services_Product_Type__c: '',
        Is_Legal__c: false, Is_Accounting__c: false, Is_Consulting__c: false,
        Is_IBA__c: false, Is_PCM__c: false, Is_Prime__c: false,
        Is_Real_Assets__c: false, Iss_Corporate__c: false
    };

    // Item Master fields
    @track itemMaster = {
        Name: '', Item_Name__c: '', Active__c: true, Description__c: '',
        Revenue_Type__c: ''
    };

    @track itemMasterNameError = '';

    // Component rows
    @track componentRows = [];
    @track createdBundleId = null;
    @track showSuccessState = false;

    connectedCallback() {
        this.loadPicklists();
    }

    loadPicklists() {
        Promise.all([
            getProductPicklistValues(),
            getItemMasterPicklistValues()
        ])
            .then(([prodPl, imPl]) => {
                this.productPicklists = prodPl;
                this.itemMasterPicklists = imPl;
            })
            .catch(() => { /* silently handle */ });
    }

    // Picklist getters
    buildOptions(picklistMap, fieldName) {
        const values = picklistMap[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get productTypeOptions() { return this.buildOptions(this.productPicklists, 'Product_Type__c'); }
    get productLicenseTypeOptions() { return this.buildOptions(this.productPicklists, 'Product_License_Type__c'); }
    get pricingBasisOptions() { return this.buildOptions(this.productPicklists, 'Pricing_Basis__c'); }
    get productGroupOptions() { return this.buildOptions(this.productPicklists, 'Product_Group__c'); }
    get servicesProductTypeOptions() { return this.buildOptions(this.productPicklists, 'Services_Product_Type__c'); }
    get revenueTypeOptions() { return this.buildOptions(this.itemMasterPicklists, 'Revenue_Type__c'); }

    get hasComponents() { return this.componentRows.length > 0; }
    get isNotMultiEntry() { return false; }

    // Product field changes
    handleProductFieldChange(event) {
        const field = event.target.dataset.field;
        this.product = { ...this.product, [field]: event.target.value };
    }

    handleProductCheckboxChange(event) {
        const field = event.target.dataset.field;
        this.product = { ...this.product, [field]: event.target.checked };
    }

    // Item Master field changes
    handleItemMasterFieldChange(event) {
        const field = event.target.dataset.field;
        this.itemMaster = { ...this.itemMaster, [field]: event.target.value };
    }

    handleItemMasterNameBlur() {
        const name = this.itemMaster.Name;
        if (!name || name.length < 2) {
            this.itemMasterNameError = '';
            return;
        }
        isItemMasterNameAvailable({ name })
            .then(available => {
                this.itemMasterNameError = available ? '' : 'An Item Master Product with this name already exists.';
            })
            .catch(() => {
                this.itemMasterNameError = '';
            });
    }

    // Product Line lookup
    handleProductLineSearch(event) {
        searchProductLines({ searchTerm: event.detail.searchTerm })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="bundleProductLine"]');
                if (lookup) lookup.setSearchResults(results);
            })
            .catch(() => { /* silently handle */ });
    }

    handleProductLineSelected(event) {
        const sel = event.detail;
        this.product = { ...this.product, Product_LineNew__c: (sel && sel.length > 0) ? sel[0] : null };
    }

    // Component search
    handleComponentSearch(event) {
        searchComponentProducts({ searchTerm: event.detail.searchTerm })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="componentSearch"]');
                if (lookup) {
                    lookup.setSearchResults(results.map(p => ({
                        id: p.Id,
                        title: p.Name,
                        subtitle: p.ProductCode || '',
                        icon: 'standard:product'
                    })));
                }
            })
            .catch(() => { /* silently handle */ });
    }

    handleComponentSelected(event) {
        const sel = event.detail;
        if (sel && sel.length > 0) {
            const productId = sel[0];
            // Check if already added
            const exists = this.componentRows.some(r => r.SBQQ__OptionalSKU__c === productId);
            if (!exists) {
                this.componentRows = [...this.componentRows, {
                    rowIndex: this.componentRows.length,
                    SBQQ__OptionalSKU__c: productId,
                    optionalSkuName: '',
                    SBQQ__Number__c: (this.componentRows.length + 1) * 10,
                    SBQQ__Quantity__c: 1,
                    SBQQ__Required__c: true,
                    SBQQ__Selected__c: true,
                    SBQQ__Bundled__c: true,
                    SBQQ__Type__c: 'Component',
                    SBQQ__QuantityEditable__c: false,
                    SBQQ__MinQuantity__c: null,
                    SBQQ__MaxQuantity__c: null
                }];
            }
            // Clear lookup
            const lookup = this.template.querySelector('c-lookup[data-id="componentSearch"]');
            if (lookup) lookup.selection = [];
        }
    }

    handleComponentFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.componentRows = this.componentRows.map((row, i) => {
            if (i === index) return { ...row, [field]: value };
            return row;
        });
    }

    handleRemoveComponent(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.componentRows = this.componentRows.filter((_, i) => i !== index)
            .map((row, i) => ({ ...row, rowIndex: i }));
    }

    handleSave() {
        // Validate required fields
        if (!this.product.Name || !this.product.ProductCode) {
            this.showToast('Error', 'Product Name and Product Code are required.', 'error');
            return;
        }
        if (!this.itemMaster.Name) {
            this.showToast('Error', 'Item Master Name is required.', 'error');
            return;
        }
        if (this.itemMasterNameError) {
            this.showToast('Error', 'Please fix the Item Master Name error before saving.', 'error');
            return;
        }

        this.isLoading = true;

        // Build product fields
        const productFields = {};
        for (const [key, val] of Object.entries(this.product)) {
            if (val !== '' && val !== null && val !== undefined) {
                productFields[key] = val;
            }
        }

        // Build item master fields
        const itemMasterFields = {};
        for (const [key, val] of Object.entries(this.itemMaster)) {
            if (val !== '' && val !== null && val !== undefined) {
                itemMasterFields[key] = val;
            }
        }

        // Build component rows
        const components = this.componentRows.map(row => {
            const comp = {};
            comp.SBQQ__OptionalSKU__c = row.SBQQ__OptionalSKU__c;
            comp.SBQQ__Number__c = row.SBQQ__Number__c;
            comp.SBQQ__Quantity__c = row.SBQQ__Quantity__c;
            comp.SBQQ__Required__c = row.SBQQ__Required__c;
            comp.SBQQ__Selected__c = row.SBQQ__Selected__c;
            comp.SBQQ__Bundled__c = row.SBQQ__Bundled__c;
            comp.SBQQ__Type__c = row.SBQQ__Type__c;
            comp.SBQQ__QuantityEditable__c = row.SBQQ__QuantityEditable__c;
            if (row.SBQQ__MinQuantity__c) comp.SBQQ__MinQuantity__c = row.SBQQ__MinQuantity__c;
            if (row.SBQQ__MaxQuantity__c) comp.SBQQ__MaxQuantity__c = row.SBQQ__MaxQuantity__c;
            return comp;
        });

        createBundleSku({ productFields, itemMasterFields, componentRows: components })
            .then(bundleId => {
                this.createdBundleId = bundleId;
                this.showSuccessState = true;
                this.showToast('Success', 'Bundle SKU created successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Failed to create bundle: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleReset() {
        this.product = {
            Name: '', ProductCode: '', Description: '', IsActive: true,
            Product_Type__c: '', Product_License_Type__c: '', Pricing_Basis__c: '',
            Product_Group__c: '', Services_Product_Type__c: '',
            Is_Legal__c: false, Is_Accounting__c: false, Is_Consulting__c: false,
            Is_IBA__c: false, Is_PCM__c: false, Is_Prime__c: false,
            Is_Real_Assets__c: false, Iss_Corporate__c: false
        };
        this.itemMaster = { Name: '', Item_Name__c: '', Active__c: true, Description__c: '', Revenue_Type__c: '' };
        this.componentRows = [];
        this.createdBundleId = null;
        this.showSuccessState = false;
        this.itemMasterNameError = '';
    }

    handleNavigateToMeterTypes() {
        this.dispatchEvent(new CustomEvent('navigatetotab', {
            detail: { tab: 'meterTypes', productId: this.createdBundleId },
            bubbles: true, composed: true
        }));
    }

    handleNavigateToPricing() {
        this.dispatchEvent(new CustomEvent('navigatetotab', {
            detail: { tab: 'pricing', productId: this.createdBundleId },
            bubbles: true, composed: true
        }));
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