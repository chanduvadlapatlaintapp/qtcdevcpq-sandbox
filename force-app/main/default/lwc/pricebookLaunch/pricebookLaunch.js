import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProductLines from '@salesforce/apex/SkuLookupController.searchProductLines';
import getActiveProducts from '@salesforce/apex/SkuPricebookLaunchController.getActiveProducts';
import getPricebooks from '@salesforce/apex/SkuPricebookLaunchController.getPricebooks';
import getFiscalYearOptions from '@salesforce/apex/SkuPricebookLaunchController.getFiscalYearOptions';
import launchPricebook from '@salesforce/apex/SkuPricebookLaunchController.launchPricebook';
import copyPricebook from '@salesforce/apex/SkuPricebookLaunchController.copyPricebook';

export default class PricebookLaunch extends LightningElement {
    @track isLoading = false;
    @track mode = 'create'; // 'create' or 'copy'
    @track targetFY = '';
    @track sourceFY = '';
    @track adjustPct = null;
    @track fiscalYearOptions = [];
    @track pricebooks = [];

    @track products = [];
    @track selectedProductIds = new Set();
    @track productLineFilter = null;

    @track launchResult = null;
    @track showResult = false;

    connectedCallback() {
        this.loadInitialData();
    }

    loadInitialData() {
        Promise.all([
            getFiscalYearOptions(),
            getPricebooks()
        ])
            .then(([fyOptions, pbs]) => {
                this.fiscalYearOptions = [
                    { label: '--Select--', value: '' },
                    ...fyOptions
                ];
                this.pricebooks = pbs;
            })
            .catch(() => { /* silently handle */ });
    }

    get modeOptions() {
        return [
            { label: 'Create New Pricing', value: 'create' },
            { label: 'Copy from Existing', value: 'copy' }
        ];
    }

    get isCreateMode() { return this.mode === 'create'; }
    get isCopyMode() { return this.mode === 'copy'; }
    get hasProducts() { return this.products.length > 0; }
    get hasSelectedProducts() { return this.selectedProductIds.size > 0; }
    get selectedCount() { return this.selectedProductIds.size; }

    get isNotMultiEntry() { return false; }

    get isCopyDisabled() {
        return !this.sourceFY || !this.targetFY || this.sourceFY === this.targetFY || this.isLoading;
    }

    handleModeChange(event) {
        this.mode = event.detail.value;
        this.launchResult = null;
        this.showResult = false;
    }

    handleTargetFYChange(event) {
        this.targetFY = event.target.value;
    }

    handleSourceFYChange(event) {
        this.sourceFY = event.target.value;
    }

    handleAdjustPctChange(event) {
        this.adjustPct = event.target.value;
    }

    // Product line filter
    handleProductLineSearch(event) {
        searchProductLines({ searchTerm: event.detail.searchTerm })
            .then(results => {
                const lookup = this.template.querySelector('c-lookup[data-id="plFilter"]');
                if (lookup) lookup.setSearchResults(results);
            })
            .catch(() => { /* silently handle */ });
    }

    handleProductLineSelected(event) {
        const sel = event.detail;
        this.productLineFilter = (sel && sel.length > 0) ? sel[0] : null;
    }

    handleLoadProducts() {
        this.isLoading = true;

        getActiveProducts({ productLineFilter: this.productLineFilter })
            .then(result => {
                this.products = result.map(p => ({
                    ...p,
                    selected: false,
                    Price__c: null,
                    Block_Pricing_Meter_Type__c: 'Named Users',
                    Tier_Name__c: ''
                }));
                this.selectedProductIds = new Set();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load products: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        if (checked) {
            this.selectedProductIds = new Set(this.products.map(p => p.Id));
        } else {
            this.selectedProductIds = new Set();
        }
        this.products = this.products.map(p => ({ ...p, selected: checked }));
    }

    handleProductSelect(event) {
        const productId = event.target.dataset.id;
        const checked = event.target.checked;
        const newSelected = new Set(this.selectedProductIds);

        if (checked) {
            newSelected.add(productId);
        } else {
            newSelected.delete(productId);
        }
        this.selectedProductIds = newSelected;

        this.products = this.products.map(p => {
            if (p.Id === productId) return { ...p, selected: checked };
            return p;
        });
    }

    handleProductFieldChange(event) {
        const productId = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.value;

        this.products = this.products.map(p => {
            if (p.Id === productId) return { ...p, [field]: value };
            return p;
        });
    }

    handleLaunch() {
        if (!this.targetFY) {
            this.showToast('Error', 'Please select a target Fiscal Year.', 'error');
            return;
        }

        const selectedProducts = this.products.filter(p => this.selectedProductIds.has(p.Id));
        if (selectedProducts.length === 0) {
            this.showToast('Error', 'Please select at least one product.', 'error');
            return;
        }

        const records = selectedProducts.map(p => ({
            Product__c: p.Id,
            Fiscal_Year__c: this.targetFY,
            Price__c: p.Price__c || 0,
            Block_Pricing_Meter_Type__c: p.Block_Pricing_Meter_Type__c || 'Users',
            Active__c: true
        }));

        this.isLoading = true;

        launchPricebook({ recordsJson: JSON.stringify(records) })
            .then(result => {
                this.launchResult = result;
                this.showResult = true;
                if (result.errorCount === 0) {
                    this.showToast('Success',
                        `${result.successCount} pricing records created successfully!`, 'success');
                } else {
                    this.showToast('Warning',
                        `${result.successCount} succeeded, ${result.errorCount} failed.`, 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Launch failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCopy() {
        if (this.isCopyDisabled) return;

        this.isLoading = true;

        copyPricebook({
            sourceFY: this.sourceFY,
            targetFY: this.targetFY,
            adjustPct: this.adjustPct ? parseFloat(this.adjustPct) : null
        })
            .then(result => {
                this.launchResult = result;
                this.showResult = true;
                if (result.totalCount === 0) {
                    this.showToast('Info', 'No source records found to copy.', 'info');
                } else if (result.errorCount === 0) {
                    this.showToast('Success',
                        `${result.successCount} records copied successfully!`, 'success');
                } else {
                    this.showToast('Warning',
                        `${result.successCount} copied, ${result.errorCount} failed.`, 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Copy failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleReset() {
        this.launchResult = null;
        this.showResult = false;
        this.products = [];
        this.selectedProductIds = new Set();
        this.targetFY = '';
        this.sourceFY = '';
        this.adjustPct = null;
    }

    get resultErrors() {
        return this.launchResult && this.launchResult.errors
            ? this.launchResult.errors.map((e, i) => ({ key: i, message: e }))
            : [];
    }

    get hasResultErrors() {
        return this.resultErrors.length > 0;
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