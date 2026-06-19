import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import bulkCreateStandaloneSkus from '@salesforce/apex/SkuProductController.bulkCreateStandaloneSkus';
import getProductPicklistValues from '@salesforce/apex/SkuProductController.getProductPicklistValues';

export default class SkuCreateStandalone extends LightningElement {
    @track rows = [];
    @track isLoading = false;
    @track createdProductIds;
    @track validationErrors;

    // Picklist values
    @track productPicklists = {};

    // Stable row ID counter (monotonic, never resets between adds)
    _nextRowId = 0;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadPicklistValues();
        this.handleAddRow();
    }

    loadPicklistValues() {
        this.isLoading = true;
        getProductPicklistValues()
            .then(prodPicklists => {
                this.productPicklists = prodPicklists;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load picklist values: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Picklist Option Getters
    // =========================================================================

    buildOptions(picklistMap, fieldName) {
        const values = picklistMap[fieldName] || [];
        return [{ label: '--None--', value: '' }, ...values];
    }

    get productGroupOptions() { return this.buildOptions(this.productPicklists, 'Product_Group__c'); }
    get productTypeOptions() { return this.buildOptions(this.productPicklists, 'Product_Type__c'); }
    get productLicenseTypeOptions() { return this.buildOptions(this.productPicklists, 'Product_License_Type__c'); }
    get pricingBasisOptions() { return this.buildOptions(this.productPicklists, 'Pricing_Basis__c'); }
    get servicesProductTypeOptions() { return this.buildOptions(this.productPicklists, 'Services_Product_Type__c'); }
    get guidedSellingTypeOptions() { return this.buildOptions(this.productPicklists, 'Guided_Selling_Type__c'); }

    // =========================================================================
    // Computed Properties
    // =========================================================================

    get hasRows() {
        return this.rows.length > 0;
    }

    get isCreateDisabled() {
        return this.isLoading || this.rows.length === 0;
    }

    get hasValidationErrors() {
        return this.validationErrors && this.validationErrors.length > 0;
    }

    get createdCount() {
        return this.createdProductIds ? this.createdProductIds.length : 0;
    }

    get successMessage() {
        const n = this.createdCount;
        return n + ' SKU' + (n !== 1 ? 's' : '') + ' created successfully!';
    }

    // =========================================================================
    // Row Management
    // =========================================================================

    buildEmptyRow() {
        const id = this._nextRowId++;
        return {
            id: id,
            displayIndex: 0,
            product: { IsActive: true },
            itemMaster: {},
            // Pre-computed CSS classes for validation
            nameClass: '',
            codeClass: '',
            imNameClass: '',
            rowCssClass: ''
        };
    }

    handleAddRow() {
        const newRow = this.buildEmptyRow();
        this.rows = [...this.rows, newRow];
        this.recomputeDisplayIndices();
        this.validationErrors = null;
    }

    handleRemoveRow(event) {
        const rowId = parseInt(event.target.dataset.index || event.currentTarget.dataset.index, 10);
        this.rows = this.rows.filter(r => r.id !== rowId);
        this.recomputeDisplayIndices();
        this.validationErrors = null;
    }

    recomputeDisplayIndices() {
        this.rows = this.rows.map((row, i) => ({
            ...row,
            displayIndex: i + 1
        }));
    }

    // =========================================================================
    // Field Change Handling
    // =========================================================================

    handleFieldChange(event) {
        const rowId = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const objectType = event.target.dataset.object;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        this.rows = this.rows.map(row => {
            if (row.id === rowId) {
                const updated = { ...row };
                if (objectType === 'product') {
                    updated.product = { ...row.product, [field]: value };
                } else if (objectType === 'itemMaster') {
                    updated.itemMaster = { ...row.itemMaster, [field]: value };
                }
                // Clear validation styling on edit
                updated.nameClass = '';
                updated.codeClass = '';
                updated.imNameClass = '';
                updated.rowCssClass = '';
                return updated;
            }
            return row;
        });
    }

    // =========================================================================
    // Validation
    // =========================================================================

    validateAllRows() {
        const errors = [];
        const itemMasterNames = new Set();

        const updatedRows = this.rows.map((row, i) => {
            const rowNum = i + 1;
            const pName = row.product.Name;
            const pCode = row.product.ProductCode;
            const imName = row.itemMaster.Name;
            let nameErr = false;
            let codeErr = false;
            let imErr = false;

            if (!pName || pName.trim() === '') {
                errors.push('Row ' + rowNum + ': Product Name is required.');
                nameErr = true;
            }
            if (!pCode || pCode.trim() === '') {
                errors.push('Row ' + rowNum + ': Product Code is required.');
                codeErr = true;
            }
            if (!imName || imName.trim() === '') {
                errors.push('Row ' + rowNum + ': Item Master Name is required.');
                imErr = true;
            } else if (itemMasterNames.has(imName.trim())) {
                errors.push('Row ' + rowNum + ': Duplicate Item Master Name "' + imName + '" within this batch.');
                imErr = true;
            } else {
                itemMasterNames.add(imName.trim());
            }

            return {
                ...row,
                nameClass: nameErr ? 'cell-error' : '',
                codeClass: codeErr ? 'cell-error' : '',
                imNameClass: imErr ? 'cell-error' : '',
                rowCssClass: (nameErr || codeErr || imErr) ? 'row-error' : ''
            };
        });

        this.rows = updatedRows;
        this.validationErrors = errors.length > 0 ? errors : null;
        return errors.length === 0;
    }

    // =========================================================================
    // Create All
    // =========================================================================

    handleCreateAll() {
        if (!this.validateAllRows()) {
            this.showToast('Validation Error', 'Please fix the highlighted errors.', 'error');
            return;
        }

        this.isLoading = true;
        const payload = this.rows.map(row => ({
            productFields: this.cleanFields(row.product),
            itemMasterFields: this.cleanFields(row.itemMaster)
        }));

        bulkCreateStandaloneSkus({ recordsJson: JSON.stringify(payload) })
            .then(createdIds => {
                this.createdProductIds = createdIds;
                this.showToast('Success', createdIds.length + ' SKU(s) created successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Creation failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Reset & Navigation
    // =========================================================================

    handleReset() {
        this.rows = [];
        this._nextRowId = 0;
        this.createdProductIds = null;
        this.validationErrors = null;
        this.handleAddRow();
    }

    handleNavigateToMeterTypes() {
        if (this.createdProductIds && this.createdProductIds.length > 0) {
            this.dispatchEvent(new CustomEvent('navigatetotab', {
                detail: { tabName: 'meterTypes', productId: this.createdProductIds[0] },
                bubbles: true, composed: true
            }));
        }
    }

    handleNavigateToPricing() {
        if (this.createdProductIds && this.createdProductIds.length > 0) {
            this.dispatchEvent(new CustomEvent('navigatetotab', {
                detail: { tabName: 'pricing', productId: this.createdProductIds[0] },
                bubbles: true, composed: true
            }));
        }
    }

    handleNavigateToUpdate() {
        this.dispatchEvent(new CustomEvent('navigatetotab', {
            detail: { tabName: 'updateSku' },
            bubbles: true, composed: true
        }));
    }

    // =========================================================================
    // Utilities
    // =========================================================================

    cleanFields(fieldMap) {
        const cleaned = {};
        for (const key of Object.keys(fieldMap)) {
            const val = fieldMap[key];
            if (val !== null && val !== undefined && val !== '') {
                cleaned[key] = val;
            }
        }
        return cleaned;
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