import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuantityPricingData from '@salesforce/apex/SkuPricingViewController.getQuantityPricingData';
import saveQuantityPricingData from '@salesforce/apex/SkuPricingViewController.saveQuantityPricingData';
import deleteQuantityPricingByMeterType from '@salesforce/apex/SkuPricingViewController.deleteQuantityPricingByMeterType';

export default class QuantityPricingManager extends LightningElement {
    @api preselectedProductId;
    @api hideLookup = false;

    @track selectedProductId;
    @track isLoading = false;
    @track isDirty = false;
    @track meterTypeGroups = [];
    @track showDeleteConfirm = false;
    @track deleteTargetMeterType = '';

    productCode;

    connectedCallback() {
        if (this.preselectedProductId) {
            this.selectedProductId = this.preselectedProductId;
            this.loadData();
        }
    }

    get hasGroups() { return this.meterTypeGroups.length > 0; }

    // =========================================================================
    // Data Loading
    // =========================================================================

    loadData() {
        this.isLoading = true;
        getQuantityPricingData({ productId: this.selectedProductId })
            .then(result => {
                this.productCode = result.productCode;
                this.meterTypeGroups = (result.meterTypes || []).map((grp, gi) => ({
                    ...grp,
                    groupKey: grp.meterType,
                    groupIndex: gi,
                    bands: (grp.bands || []).map((band, bi) => ({
                        ...band,
                        bandKey: `${grp.meterType}_${band.lowerBound}_${band.upperBound}`,
                        bandIndex: bi,
                        cells: (band.cells || []).map((cell, ci) => ({
                            ...cell,
                            cellKey: `${grp.meterType}_${band.lowerBound}_${cell.currencyCode}`,
                            cellIndex: ci,
                            price: cell.price != null ? cell.price : null
                        }))
                    }))
                }));
                this.isDirty = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load quantity pricing: ' + this.extractError(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    // =========================================================================
    // Price Change Handler
    // =========================================================================

    handlePriceInput() {
        if (!this.isDirty) {
            this.isDirty = true;
        }
    }

    handlePriceChange(event) {
        const groupKey = event.target.dataset.groupkey;
        const bandKey  = event.target.dataset.bandkey;
        const cellIdx  = parseInt(event.target.dataset.cellidx, 10);
        const rawValue = event.target.value;
        const price    = (rawValue !== '' && rawValue != null) ? parseFloat(rawValue) : null;

        this.meterTypeGroups = this.meterTypeGroups.map(grp => {
            if (grp.groupKey === groupKey) {
                return {
                    ...grp,
                    bands: grp.bands.map(band => {
                        if (band.bandKey === bandKey) {
                            return {
                                ...band,
                                cells: band.cells.map(cell => {
                                    if (cell.cellIndex === cellIdx) {
                                        return { ...cell, price: (price != null && !isNaN(price)) ? price : null };
                                    }
                                    return cell;
                                })
                            };
                        }
                        return band;
                    })
                };
            }
            return grp;
        });
        this.isDirty = true;
    }

    /**
     * Handle Excel-like paste into price cells.
     * Parses tab-separated (columns) and newline-separated (rows) clipboard data
     * and fills cells left-to-right across currencies, then top-to-bottom across
     * quantity bands (spanning across meter type groups if needed).
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
        const startGroupKey = event.target.dataset.groupkey;
        const startBandKey  = event.target.dataset.bandkey;
        const startCellIdx  = parseInt(event.target.dataset.cellidx, 10);

        // Build flat list of all band rows across all meter type groups
        const flatBands = [];
        this.meterTypeGroups.forEach((grp, gi) => {
            grp.bands.forEach((band, bi) => {
                flatBands.push({
                    groupIndex: gi,
                    bandIndex: bi,
                    groupKey: grp.groupKey,
                    bandKey: band.bandKey
                });
            });
        });

        // Find starting band in the flat list
        const startFlatIdx = flatBands.findIndex(
            fb => fb.groupKey === startGroupKey && fb.bandKey === startBandKey
        );
        if (startFlatIdx === -1) return;

        const cellsPerBand = 4; // USD, GBP, EUR, AUD

        // Deep clone for immutable update
        const updatedGroups = this.meterTypeGroups.map(grp => ({
            ...grp,
            bands: grp.bands.map(band => ({
                ...band,
                cells: band.cells.map(cell => ({ ...cell }))
            }))
        }));

        let pastedCount = 0;

        for (let pasteRowIdx = 0; pasteRowIdx < pastedGrid.length; pasteRowIdx++) {
            const targetFlatIdx = startFlatIdx + pasteRowIdx;
            if (targetFlatIdx >= flatBands.length) break;

            const { groupIndex, bandIndex } = flatBands[targetFlatIdx];
            const pastedCols = pastedGrid[pasteRowIdx];

            for (let pasteColIdx = 0; pasteColIdx < pastedCols.length; pasteColIdx++) {
                const targetCellIdx = startCellIdx + pasteColIdx;
                if (targetCellIdx >= cellsPerBand) break;

                const rawValue = pastedCols[pasteColIdx].trim();
                if (rawValue === '') continue;

                // Remove currency symbols, commas, spaces for flexible paste
                const cleaned = rawValue.replace(/[$£€,\s]/g, '');
                const numValue = parseFloat(cleaned);

                updatedGroups[groupIndex].bands[bandIndex].cells[targetCellIdx].price =
                    (!isNaN(numValue) && numValue >= 0) ? Math.round(numValue * 100) / 100 : null;
                pastedCount++;
            }
        }

        this.meterTypeGroups = updatedGroups;
        this.isDirty = true;

        if (pastedCount > 0) {
            this.showToast('Success', `Pasted ${pastedCount} value(s) into pricing cells.`, 'success');
        }
    }

    // =========================================================================
    // Save
    // =========================================================================

    handleSave() {
        this.isLoading = true;

        const payload = this.meterTypeGroups.map(grp => ({
            meterType: grp.meterType,
            bands: grp.bands.map(band => ({
                lowerBound: band.lowerBound,
                upperBound: band.upperBound,
                bandLabel: band.bandLabel,
                cells: band.cells.map(cell => ({
                    currencyCode: cell.currencyCode,
                    price: cell.price,
                    blockId: cell.blockId || null
                }))
            }))
        }));

        saveQuantityPricingData({
            productId: this.selectedProductId,
            rowsJson: JSON.stringify(payload)
        })
            .then(() => {
                this.showToast('Success', 'Quantity pricing saved successfully!', 'success');
                this.isDirty = false;
                this.loadData();
            })
            .catch(error => {
                this.showToast('Error', 'Save failed: ' + this.extractError(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    // =========================================================================
    // Delete Meter Type
    // =========================================================================

    handleDeleteMeterType(event) {
        event.stopPropagation();
        this.deleteTargetMeterType = event.currentTarget.dataset.groupkey;
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

        deleteQuantityPricingByMeterType({
            productId: this.selectedProductId,
            meterType
        })
            .then(() => {
                this.showToast('Success',
                    'All quantity pricing records for "' + meterType + '" have been deleted.',
                    'success');
                this.deleteTargetMeterType = '';
                this.loadData();
            })
            .catch(error => {
                this.showToast('Error',
                    'Delete failed: ' + this.extractError(error),
                    'error');
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