import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchProducts from '@salesforce/apex/SkuLookupController.searchProducts';
import getPricingData from '@salesforce/apex/SkuPricingViewController.getPricingData';
import savePricingData from '@salesforce/apex/SkuPricingViewController.savePricingData';
import createPricingRows from '@salesforce/apex/SkuPricingViewController.createPricingRows';
import deletePricingByMeterType from '@salesforce/apex/SkuPricingViewController.deletePricingByMeterType';
import getIntappPricingPicklists from '@salesforce/apex/SkuIntappPricingController.getIntappPricingPicklists';

const CURRENCIES = ['USD', 'GBP', 'EUR', 'AUD'];
const TIERS = ['EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'];

export default class PricingManager extends LightningElement {
    @api preselectedProductId;
    @api hideLookup = false;

    @track selectedProductId;
    @track isLoading = false;
    @track isDirty = false;
    @track rows = [];
    @track meterTypeOptions = [];
    @track showDeleteConfirm = false;
    @track deleteTargetMeterType = '';

    productCode;
    newRowCounter = 0;

    connectedCallback() {
        this.loadMeterTypePicklist();
        if (this.preselectedProductId) {
            this.selectedProductId = this.preselectedProductId;
            this.loadPricingData();
        }
    }

    get isProductSelected() { return !!this.selectedProductId; }
    get isNotMultiEntry()   { return false; }
    get hasRows()           { return this.rows.length > 0; }
    get hasNewRows()        { return this.rows.some(r => r.isNew); }

    // =========================================================================
    // Picklist Loading
    // =========================================================================

    loadMeterTypePicklist() {
        getIntappPricingPicklists()
            .then(result => {
                const mtValues = result['Meter_Type__c'] || [];
                this.meterTypeOptions = [
                    { label: '--Select Meter Type--', value: '' },
                    ...mtValues
                ];
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
                const lookup = this.template.querySelector('c-lookup[data-id="pricingProductLookup"]');
                if (lookup) lookup.setSearchResults(results);
            })
            .catch(error => {
                this.showToast('Error', 'Search failed: ' + this.extractError(error), 'error');
            });
    }

    handleProductSelected(event) {
        const productId = event.detail && event.detail.value;
        if (productId) {
            this.selectedProductId = productId;
            this.isDirty = false;
            this.loadPricingData();
        } else {
            this.selectedProductId = null;
            this.rows = [];
            this.isDirty = false;
        }
    }

    // =========================================================================
    // Data Loading
    // =========================================================================

    loadPricingData() {
        this.isLoading = true;
        this.newRowCounter = 0;
        getPricingData({ productId: this.selectedProductId })
            .then(result => {
                this.productCode = result.productCode;
                this.rows = (result.rows || []).map((row, ri) => ({
                    ...row,
                    isNew:          false,
                    tempId:         null,
                    rowKey:         row.meterType,
                    rowIndex:       ri,
                    legalSales:     row.legalSales     || false,
                    acSales:        row.acSales        || false,
                    fsSales:        row.fsSales        || false,
                    corporateSales: row.corporateSales || false,
                    opsOnly:        row.opsOnly        || false,
                    cells: (row.cells || []).map((cell, ci) => ({
                        ...cell,
                        cellIndex: ci,
                        cellKey:   `${cell.currencyCode}_${cell.tier}`,
                        price:     cell.price != null ? cell.price : null
                    }))
                }));
                this.isDirty = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load pricing: ' + this.extractError(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    // =========================================================================
    // Add / Remove Row
    // =========================================================================

    handleAddRow() {
        this.newRowCounter++;
        const tempId = `new_${this.newRowCounter}`;
        const cells = [];
        let cellIdx = 0;
        for (const curr of CURRENCIES) {
            for (const tier of TIERS) {
                cells.push({
                    currencyCode: curr,
                    tier,
                    price: null,
                    intappId: null,
                    blockId: null,
                    cellIndex: cellIdx,
                    cellKey: `${curr}_${tier}`
                });
                cellIdx++;
            }
        }
        const newRow = {
            meterType: '',
            isNew: true,
            tempId,
            rowKey: tempId,
            rowIndex: this.rows.length,
            legalSales: false,
            acSales: false,
            fsSales: false,
            corporateSales: false,
            opsOnly: false,
            cells
        };
        this.rows = [...this.rows, newRow];
        this.isDirty = true;
    }

    handleRemoveRow(event) {
        const tempId = event.currentTarget.dataset.tempid;
        this.rows = this.rows.filter(r => r.tempId !== tempId);
        // Recalculate dirty: still dirty if there are new rows or if existing rows were changed
        if (!this.rows.some(r => r.isNew)) {
            this.isDirty = false;
        }
    }

    handleDeleteMeterTypeRow(event) {
        event.stopPropagation();
        this.deleteTargetMeterType = event.currentTarget.dataset.rowkey;
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
        this.deleteTargetMeterType = '';
    }

    handleDeleteConfirm() {
        this.showDeleteConfirm = false;
        this.isLoading = true;
        const meterType = this.deleteTargetMeterType;

        deletePricingByMeterType({
            productId: this.selectedProductId,
            meterType
        })
            .then(() => {
                this.showToast('Success',
                    'All pricing records for "' + meterType + '" have been deleted.',
                    'success');
                this.deleteTargetMeterType = '';
                this.loadPricingData();
            })
            .catch(error => {
                this.showToast('Error',
                    'Delete failed: ' + this.extractError(error),
                    'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleMeterTypeChange(event) {
        const tempId = event.target.dataset.tempid;
        const value = event.target.value;
        this.rows = this.rows.map(row => {
            if (row.tempId === tempId) {
                return { ...row, meterType: value, rowKey: value || tempId };
            }
            return row;
        });
        this.isDirty = true;
    }

    // =========================================================================
    // Checkbox & Price Change Handlers
    // =========================================================================

    handleCheckboxChange(event) {
        const rowKey = event.target.dataset.rowkey;
        const field  = event.target.dataset.field;
        const checked = event.target.checked;
        this.rows = this.rows.map(row => {
            if (row.rowKey === rowKey) return { ...row, [field]: checked };
            return row;
        });
        this.isDirty = true;
    }

    handlePriceInput() {
        if (!this.isDirty) {
            this.isDirty = true;
        }
    }

    handlePriceChange(event) {
        const rowKey    = event.target.dataset.rowkey;
        const cellIndex = parseInt(event.target.dataset.idx, 10);
        const rawValue  = event.target.value;
        const price     = (rawValue !== '' && rawValue != null) ? parseFloat(rawValue) : null;
        this.rows = this.rows.map(row => {
            if (row.rowKey === rowKey) {
                const cells = row.cells.map(cell => {
                    if (cell.cellIndex === cellIndex) {
                        return { ...cell, price: (price != null && !isNaN(price)) ? price : null };
                    }
                    return cell;
                });
                return { ...row, cells };
            }
            return row;
        });
        this.isDirty = true;
    }

    /**
     * Handle Excel-like paste into price cells.
     * Parses tab-separated (columns) and newline-separated (rows) clipboard data
     * and fills cells left-to-right, then top-to-bottom from the focused cell.
     */
    handlePricePaste(event) {
        event.preventDefault();
        const clipboardData = event.clipboardData || window.clipboardData;
        if (!clipboardData) return;

        const pastedText = clipboardData.getData('text/plain') || clipboardData.getData('text');
        if (!pastedText || !pastedText.trim()) return;

        // Parse tab-separated columns and newline-separated rows
        const pastedRows = pastedText.split(/\r?\n/).filter(line => line.trim() !== '');
        const pastedGrid = pastedRows.map(line => line.split('\t'));

        // Determine starting position
        const startRowKey  = event.target.dataset.rowkey;
        const startCellIdx = parseInt(event.target.dataset.idx, 10);
        const startRowIndex = this.rows.findIndex(r => r.rowKey === startRowKey);
        if (startRowIndex === -1) return;

        const cellsPerRow = this.rows[0] ? this.rows[0].cells.length : 0;
        if (cellsPerRow === 0) return;

        // Deep clone rows for immutable update
        const updatedRows = this.rows.map(r => ({
            ...r,
            cells: r.cells.map(c => ({ ...c }))
        }));

        let pastedCount = 0;

        for (let pasteRowIdx = 0; pasteRowIdx < pastedGrid.length; pasteRowIdx++) {
            const targetRowIdx = startRowIndex + pasteRowIdx;
            if (targetRowIdx >= updatedRows.length) break;

            const pastedCols = pastedGrid[pasteRowIdx];
            for (let pasteColIdx = 0; pasteColIdx < pastedCols.length; pasteColIdx++) {
                const targetCellIdx = startCellIdx + pasteColIdx;
                if (targetCellIdx >= cellsPerRow) break;

                const rawValue = pastedCols[pasteColIdx].trim();
                if (rawValue === '') continue;

                // Remove currency symbols, commas, spaces for flexible paste
                const cleaned = rawValue.replace(/[$£€,\s]/g, '');
                const numValue = parseFloat(cleaned);

                updatedRows[targetRowIdx].cells[targetCellIdx].price =
                    (!isNaN(numValue) && numValue >= 0) ? Math.round(numValue * 100) / 100 : null;
                pastedCount++;
            }
        }

        this.rows = updatedRows;
        this.isDirty = true;

        if (pastedCount > 0) {
            this.showToast('Success', `Pasted ${pastedCount} value(s) into pricing cells.`, 'success');
        }
    }

    // =========================================================================
    // Save
    // =========================================================================

    handleSave() {
        const existingRows = this.rows.filter(r => !r.isNew);
        const newRows      = this.rows.filter(r => r.isNew);

        // Validate: new rows must have a meter type
        const invalidNew = newRows.filter(r => !r.meterType);
        if (invalidNew.length > 0) {
            this.showToast('Error', 'All new rows must have a Meter Type selected.', 'error');
            return;
        }

        // Validate: no duplicate meter types among new rows
        const newMeterTypes = newRows.map(r => r.meterType);
        const uniqueNew = new Set(newMeterTypes);
        if (uniqueNew.size !== newMeterTypes.length) {
            this.showToast('Error', 'Duplicate Meter Types found in new rows.', 'error');
            return;
        }

        // Validate: new meter types don't conflict with existing rows
        const existingMeterTypes = new Set(existingRows.map(r => r.meterType));
        const duplicates = newMeterTypes.filter(mt => existingMeterTypes.has(mt));
        if (duplicates.length > 0) {
            this.showToast('Error', 'Meter Type "' + duplicates[0] + '" already exists. Update the existing row instead.', 'error');
            return;
        }

        this.isLoading = true;
        const promises = [];

        // Save existing rows (unchanged logic)
        if (existingRows.length > 0) {
            const rowsToSave = existingRows.map(row => ({
                meterType:      row.meterType,
                legalSales:     row.legalSales,
                acSales:        row.acSales,
                fsSales:        row.fsSales,
                corporateSales: row.corporateSales,
                opsOnly:        row.opsOnly,
                cells: row.cells.map(cell => ({
                    currencyCode: cell.currencyCode,
                    tier:         cell.tier,
                    intappId:     cell.intappId || null,
                    blockId:      cell.blockId  || null,
                    price:        cell.price
                }))
            }));
            promises.push(savePricingData({
                productId: this.selectedProductId,
                rowsJson:  JSON.stringify(rowsToSave)
            }));
        }

        // Create new rows
        if (newRows.length > 0) {
            const newRowsPayload = newRows.map(row => ({
                meterType:      row.meterType,
                legalSales:     row.legalSales,
                acSales:        row.acSales,
                fsSales:        row.fsSales,
                corporateSales: row.corporateSales,
                opsOnly:        row.opsOnly,
                cells: row.cells.map(cell => ({
                    currencyCode: cell.currencyCode,
                    tier:         cell.tier,
                    price:        cell.price
                }))
            }));
            promises.push(createPricingRows({
                productId:   this.selectedProductId,
                newRowsJson: JSON.stringify(newRowsPayload)
            }));
        }

        Promise.all(promises)
            .then(() => {
                this.showToast('Success', 'Pricing saved successfully!', 'success');
                this.isDirty = false;
                this.loadPricingData();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
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