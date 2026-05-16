import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import getActivePricebooks from '@salesforce/apex/PricebookWizardController.getActivePricebooks';
import deactivatePricebook from '@salesforce/apex/PricebookWizardController.deactivatePricebook';
import createPricebook from '@salesforce/apex/PricebookWizardController.createPricebook';
import startPricebookSetup from '@salesforce/apex/PricebookWizardController.startPricebookSetup';
import getSetupStatus from '@salesforce/apex/PricebookWizardController.getSetupStatus';
import validateCsvUpload from '@salesforce/apex/PricebookWizardController.validateCsvUpload';
import processPricingUpload from '@salesforce/apex/PricebookWizardController.processPricingUpload';
import validateExcelUpload from '@salesforce/apex/PricebookWizardController.validateExcelUpload';
import processExcelUpload from '@salesforce/apex/PricebookWizardController.processExcelUpload';
import validateQuantityExcelUpload from '@salesforce/apex/PricebookWizardController.validateQuantityExcelUpload';
import processQuantityExcelUpload from '@salesforce/apex/PricebookWizardController.processQuantityExcelUpload';
import getUploadResultView from '@salesforce/apex/PricebookWizardController.getUploadResultView';

const POLL_INTERVAL_MS = 3000;

/** Constants for View Results table — mirrored from pricebookView.js */
const CURRENCY_SYMBOLS = { USD: '$', GBP: '\u00A3', EUR: '\u20AC', AUD: 'A$' };
const VR_CURRENCIES = ['USD', 'GBP', 'EUR', 'AUD'];
const VR_TIERS = ['EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'];

const TIER_HEADERS = [];
for (const curr of VR_CURRENCIES) {
    for (const tier of VR_TIERS) {
        TIER_HEADERS.push({ key: `${curr}_${tier}`, label: tier });
    }
}

/** Maps Excel "Pricebook" column values to sales channel boolean field names. */
const SALES_CHANNEL_MAP = {
    'legal': 'legalSales',
    'a&c': 'acSales',
    'ac': 'acSales',
    'fs': 'fsSales',
    'corporate': 'corporateSales',
    'ops': 'opsOnly',
    'ops only': 'opsOnly'
};

export default class PricebookWizard extends LightningElement {
    // =========================================================================
    // State
    // =========================================================================

    @track currentStep = '1';
    @track isLoading = false;

    // Phase 1
    @track pricebooks = [];
    @track selectedPricebookId = null;
    @track pricebookChoice = 'existing'; // 'existing' | 'new'
    @track newPricebookName = '';
    @track isNewPricebook = false;

    // Phase 2
    @track setupJobId = null;
    @track setupStatus = '';
    @track setupMessage = '';
    @track _pollingInterval = null;

    // Phase 3 (Excel)
    sheetJsLoaded = false;
    @track uploadType = 'tier'; // 'tier' or 'quantity'
    @track excelFileName = '';
    @track excelParsedRows = null;  // Array of ExcelUploadRow objects
    @track excelValidationResult = null;
    // Quantity pricing upload
    @track quantityParsedRows = null;  // Array of QuantityUploadRow objects
    @track quantityValidationResult = null;
    // Legacy CSV (kept for backward compatibility)
    @track csvContent = null;
    @track csvFileName = '';
    @track validationResult = null;

    // Phase 4
    @track processingResult = null;

    // Phase 5
    @track resultViewData = null;
    @track resultViewError = null;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadPricebooks();
    }

    renderedCallback() {
        if (!this.sheetJsLoaded) {
            this.sheetJsLoaded = true;
            loadScript(this, SHEETJS)
                .then(() => { /* SheetJS loaded */ })
                .catch(error => {
                    this.showToast('Error', 'Failed to load SheetJS library: ' + this.extractError(error), 'error');
                    this.sheetJsLoaded = false;
                });
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // =========================================================================
    // Step Navigation Getters
    // =========================================================================

    get steps() {
        return [
            { value: '1', label: 'Select Pricebook' },
            { value: '2', label: 'One-Time Setup' },
            { value: '3', label: 'Upload Pricing Excel' },
            { value: '4', label: 'Processing Results' },
            { value: '5', label: 'View Results' }
        ];
    }

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }
    get isStep5() { return this.currentStep === '5'; }

    get showBackButton() {
        return this.currentStep === '3';
    }

    get showNextButton() {
        return this.currentStep === '1';
    }

    get nextButtonLabel() {
        if (this.currentStep === '1') {
            return this.pricebookChoice === 'new' ? 'Create & Continue' : 'Continue to Upload';
        }
        return 'Next';
    }

    get isNextDisabled() {
        if (this.currentStep === '1') {
            if (this.pricebookChoice === 'existing') {
                return !this.selectedPricebookId;
            }
            return !this.newPricebookName || this.newPricebookName.trim().length === 0;
        }
        return true;
    }

    // =========================================================================
    // Phase 1 Getters
    // =========================================================================

    get pricebookChoiceOptions() {
        return [
            { label: 'Use Existing Pricebook', value: 'existing' },
            { label: 'Create New Pricebook', value: 'new' }
        ];
    }

    get isExistingChoice() {
        return this.pricebookChoice === 'existing';
    }

    get isNewChoice() {
        return this.pricebookChoice === 'new';
    }

    get hasPricebooks() {
        return this.pricebooks.length > 0;
    }

    get pricebookRows() {
        return this.pricebooks.map(pb => ({
            ...pb,
            isSelected: pb.id === this.selectedPricebookId,
            rowClass: pb.id === this.selectedPricebookId ? 'selected-row' : ''
        }));
    }

    // =========================================================================
    // Phase 2 Getters
    // =========================================================================

    get isSetupRunning() {
        return this.setupStatus === 'Queued' || this.setupStatus === 'Preparing'
            || this.setupStatus === 'Processing' || this.setupStatus === 'Holding';
    }

    get isSetupComplete() {
        return this.setupStatus === 'Completed';
    }

    get isSetupFailed() {
        return this.setupStatus === 'Failed';
    }

    get setupBadgeClass() {
        let cls = 'status-badge ';
        if (this.isSetupComplete) cls += 'badge-complete';
        else if (this.isSetupFailed) cls += 'badge-failed';
        else cls += 'badge-running';
        return cls;
    }

    // =========================================================================
    // Upload Type Getters
    // =========================================================================

    get uploadTypeOptions() {
        return [
            { label: 'Tier Pricing', value: 'tier' },
            { label: 'Quantity Pricing', value: 'quantity' }
        ];
    }

    get isTierUpload() { return this.uploadType === 'tier'; }
    get isQuantityUpload() { return this.uploadType === 'quantity'; }

    // =========================================================================
    // Phase 3 Getters (Excel — unified across upload types)
    // =========================================================================

    /** Returns the active validation result based on upload type. */
    get activeValidationResult() {
        return this.isQuantityUpload ? this.quantityValidationResult : this.excelValidationResult;
    }

    get hasExcelFile() {
        if (this.isQuantityUpload) return this.quantityParsedRows !== null;
        return this.excelParsedRows !== null;
    }

    get hasExcelValidation() {
        return this.activeValidationResult !== null;
    }

    get isExcelValidationPassed() {
        return this.activeValidationResult && this.activeValidationResult.isValid;
    }

    get hasExcelValidationErrors() {
        return this.activeValidationResult && this.activeValidationResult.errors &&
            this.activeValidationResult.errors.length > 0;
    }

    get hasExcelValidationWarnings() {
        return this.activeValidationResult && this.activeValidationResult.warnings &&
            this.activeValidationResult.warnings.length > 0;
    }

    get excelValidationErrors() {
        if (!this.activeValidationResult || !this.activeValidationResult.errors) return [];
        return this.activeValidationResult.errors.map((msg, i) => ({ key: 'err-' + i, message: msg }));
    }

    get excelValidationWarnings() {
        if (!this.activeValidationResult || !this.activeValidationResult.warnings) return [];
        return this.activeValidationResult.warnings.map((msg, i) => ({ key: 'warn-' + i, message: msg }));
    }

    get excelPreviewRows() {
        if (!this.activeValidationResult || !this.activeValidationResult.previewRows) return [];
        return this.activeValidationResult.previewRows.map((row, i) => ({
            key: 'row-' + i,
            productCode: row.productCode,
            productId: row.productId,
            meterType: row.meterType,
            salesChannel: row.salesChannel,
            priceCount: row.priceCount,
            samplePrice: row.samplePrice
        }));
    }

    get hasExcelPreviewRows() {
        return this.excelPreviewRows.length > 0;
    }

    get isExcelProcessDisabled() {
        return !this.isExcelValidationPassed || this.isLoading;
    }

    /** Preview column header for the 4th column: "Sales Channel" for tier, "Band" for quantity. */
    get previewCol4Label() {
        return this.isQuantityUpload ? 'Band' : 'Sales Channel';
    }

    /** Preview column header for the 6th column sample price label. */
    get previewCol6Label() {
        return this.isQuantityUpload ? 'Sample (USD)' : 'Sample (USD EM1)';
    }

    /** Phase 3 description text. */
    get phase3Description() {
        if (this.isQuantityUpload) {
            return 'Upload a Quantity Pricing Excel file (.xlsx): rows are Product \u00D7 Meter Type \u00D7 Quantity Band, with 4 price columns (USD, GBP, EUR, AUD).';
        }
        return 'Upload a pivoted Excel file (.xlsx) with the FY pricing format: rows are Product x Meter Type, with 24 price columns (4 currencies x 6 tiers) and a Pricebook (sales channel) column.';
    }

    // Legacy CSV getters (kept for backward compatibility)
    get hasCsvFile() {
        return this.csvContent !== null;
    }

    get hasValidation() {
        return this.validationResult !== null;
    }

    get isValidationPassed() {
        return this.validationResult && this.validationResult.isValid;
    }

    get hasValidationErrors() {
        return this.validationResult && this.validationResult.errors && this.validationResult.errors.length > 0;
    }

    get hasValidationWarnings() {
        return this.validationResult && this.validationResult.warnings && this.validationResult.warnings.length > 0;
    }

    get validationErrors() {
        if (!this.validationResult || !this.validationResult.errors) return [];
        return this.validationResult.errors.map((msg, i) => ({ key: 'err-' + i, message: msg }));
    }

    get validationWarnings() {
        if (!this.validationResult || !this.validationResult.warnings) return [];
        return this.validationResult.warnings.map((msg, i) => ({ key: 'warn-' + i, message: msg }));
    }

    get previewRows() {
        if (!this.validationResult || !this.validationResult.previewRows) return [];
        return this.validationResult.previewRows.map((cols, i) => ({
            key: 'row-' + i,
            productId: cols[0],
            productCode: cols[1],
            meterType: cols[2],
            currency: cols[3],
            tier: cols[4],
            price: cols[5],
            legalSales: cols[6],
            acSales: cols[7],
            fsSales: cols[8],
            opsOnly: cols[9]
        }));
    }

    get hasPreviewRows() {
        return this.previewRows.length > 0;
    }

    get isProcessDisabled() {
        return !this.isValidationPassed || this.isLoading;
    }

    // =========================================================================
    // Phase 4 Getters
    // =========================================================================

    get hasProcessingResult() {
        return this.processingResult !== null;
    }

    get intappResult() {
        return this.processingResult ? this.processingResult.intappResult : null;
    }

    get blockResult() {
        return this.processingResult ? this.processingResult.blockResult : null;
    }

    get blockSkippedCount() {
        return this.processingResult ? this.processingResult.blockSkippedCount : 0;
    }

    get hasIntappErrors() {
        return this.intappResult && this.intappResult.errors && this.intappResult.errors.length > 0;
    }

    get hasBlockErrors() {
        return this.blockResult && this.blockResult.errors && this.blockResult.errors.length > 0;
    }

    get intappErrors() {
        if (!this.hasIntappErrors) return [];
        return this.intappResult.errors.map((msg, i) => ({ key: 'ie-' + i, message: msg }));
    }

    get blockErrors() {
        if (!this.hasBlockErrors) return [];
        return this.blockResult.errors.map((msg, i) => ({ key: 'be-' + i, message: msg }));
    }

    // =========================================================================
    // Phase 5 Getters (View Results)
    // =========================================================================

    get hasResultViewData() {
        return this.resultViewData !== null;
    }

    /**
     * Builds a Set of "productId|meterType" keys from the uploaded rows
     * to identify which result rows are newly uploaded vs pre-existing.
     */
    get _uploadedRowKeys() {
        const keys = new Set();
        const parsedRows = this.uploadType === 'quantity'
            ? this.quantityParsedRows
            : this.excelParsedRows;
        if (parsedRows) {
            parsedRows.forEach(row => {
                if (row.productId && row.meterType) {
                    keys.add(row.productId + '|' + row.meterType);
                }
            });
        }
        return keys;
    }

    get resultViewTierRows() {
        if (!this.resultViewData || !this.resultViewData.tierRows) return [];
        const uploadedKeys = this._uploadedRowKeys;
        return this.resultViewData.tierRows.map(row => {
            const isNew = uploadedKeys.has(row.productId + '|' + row.meterType);
            return {
                ...row,
                isNew,
                rowClass: isNew ? 'vr-row vr-row--new' : 'vr-row',
                formattedPrices: row.prices.map(cell => ({
                    ...cell,
                    formatted: this._formatPrice(cell.price, cell.currencyCode),
                    cellClass: 'price-cell' + (cell.price == null || cell.price === 0 ? ' price-cell--zero' : '')
                }))
            };
        });
    }

    get resultViewQuantityRows() {
        if (!this.resultViewData || !this.resultViewData.quantityRows) return [];
        const uploadedKeys = this._uploadedRowKeys;
        return this.resultViewData.quantityRows.map(row => {
            const isNew = uploadedKeys.has(row.productId + '|' + row.meterType);
            return {
                ...row,
                isNew,
                rowClass: isNew ? 'vr-row vr-row--new' : 'vr-row',
                formattedUsd: this._formatPrice(row.usdPrice, 'USD'),
                formattedGbp: this._formatPrice(row.gbpPrice, 'GBP'),
                formattedEur: this._formatPrice(row.eurPrice, 'EUR'),
                formattedAud: this._formatPrice(row.audPrice, 'AUD'),
                usdCellClass: 'price-cell' + (row.usdPrice == null || row.usdPrice === 0 ? ' price-cell--zero' : ''),
                gbpCellClass: 'price-cell' + (row.gbpPrice == null || row.gbpPrice === 0 ? ' price-cell--zero' : ''),
                eurCellClass: 'price-cell' + (row.eurPrice == null || row.eurPrice === 0 ? ' price-cell--zero' : ''),
                audCellClass: 'price-cell' + (row.audPrice == null || row.audPrice === 0 ? ' price-cell--zero' : '')
            };
        });
    }

    get resultViewTotalRows() {
        return this.resultViewData ? this.resultViewData.totalRows : 0;
    }

    get tierHeaders() {
        return TIER_HEADERS;
    }

    // =========================================================================
    // Phase 1 Handlers
    // =========================================================================

    loadPricebooks() {
        this.isLoading = true;
        getActivePricebooks()
            .then(result => {
                this.pricebooks = result;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load pricebooks: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleChoiceChange(event) {
        this.pricebookChoice = event.detail.value;
        this.selectedPricebookId = null;
        this.newPricebookName = '';
    }

    handlePricebookSelect(event) {
        this.selectedPricebookId = event.currentTarget.dataset.id;
    }

    handleNewNameChange(event) {
        this.newPricebookName = event.target.value;
    }

    handleDeactivatePricebook(event) {
        event.stopPropagation(); // Prevent row selection
        const pbId = event.currentTarget.dataset.id;
        const pbName = this.pricebooks.find(p => p.id === pbId)?.name || '';

        this.isLoading = true;
        deactivatePricebook({ pricebookId: pbId })
            .then(() => {
                this.showToast('Success', 'Pricebook "' + pbName + '" has been deactivated.', 'success');
                if (this.selectedPricebookId === pbId) {
                    this.selectedPricebookId = null;
                }
                this.loadPricebooks();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to deactivate: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleNext() {
        if (this.currentStep === '1') {
            if (this.pricebookChoice === 'new') {
                this.createNewPricebook();
            } else {
                // Existing pricebook — skip Phase 2, go to Phase 3
                this.currentStep = '3';
            }
        }
    }

    handleBack() {
        if (this.currentStep === '3') {
            this.csvContent = null;
            this.csvFileName = '';
            this.validationResult = null;
            this.excelFileName = '';
            this.excelParsedRows = null;
            this.excelValidationResult = null;
            this.currentStep = '1';
        }
    }

    createNewPricebook() {
        this.isLoading = true;
        createPricebook({ name: this.newPricebookName.trim() })
            .then(result => {
                this.selectedPricebookId = result;
                this.isNewPricebook = true;
                this.showToast('Success', 'Pricebook created successfully!', 'success');
                // Move to Phase 2 for one-time setup
                this.currentStep = '2';
                this.startSetup();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to create pricebook: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Phase 2 Handlers
    // =========================================================================

    startSetup() {
        this.isLoading = true;
        this.setupStatus = 'Queued';
        this.setupMessage = 'Starting setup...';

        startPricebookSetup({ pricebookId: this.selectedPricebookId })
            .then(jobId => {
                this.setupJobId = jobId;
                this.startPolling();
            })
            .catch(error => {
                this.setupStatus = 'Failed';
                this.setupMessage = 'Failed to start setup: ' + this.extractError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    startPolling() {
        this.stopPolling();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollingInterval = setInterval(() => {
            this.pollSetupStatus();
        }, POLL_INTERVAL_MS);
    }

    stopPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
        }
    }

    pollSetupStatus() {
        const jobId = this.setupJobId;
        getSetupStatus({ jobId })
            .then(result => {
                this.setupStatus = result.status;
                this.setupMessage = result.message;

                // Track chained job
                if (result.chainedJobId) {
                    this.setupJobId = result.chainedJobId;
                }

                if (result.status === 'Completed') {
                    this.stopPolling();
                    this.showToast('Success', 'Pricebook setup completed!', 'success');
                    // Auto-advance to Phase 3
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => {
                        this.currentStep = '3';
                    }, 1500);
                } else if (result.status === 'Failed') {
                    this.stopPolling();
                    this.showToast('Error', 'Setup failed: ' + result.message, 'error');
                }
            })
            .catch(error => {
                this.setupMessage = 'Error polling status: ' + this.extractError(error);
            });
    }

    handleSkipSetup() {
        this.stopPolling();
        this.currentStep = '3';
    }

    // =========================================================================
    // Phase 3 Handlers (Excel .xlsx upload)
    // =========================================================================

    handleUploadTypeChange(event) {
        this.uploadType = event.detail.value;
        // Clear file/validation state for both upload types
        this.handleClearExcelFile();
        this.quantityParsedRows = null;
        this.quantityValidationResult = null;
    }

    handleExcelUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        // Validate file size (4MB max)
        if (file.size > 4 * 1024 * 1024) {
            this.showToast('Error', 'File size exceeds 4MB limit.', 'error');
            return;
        }

        // Validate extension
        const ext = file.name.split('.').pop().toLowerCase();
        if (ext !== 'xlsx' && ext !== 'xls') {
            this.showToast('Error', 'Please upload an Excel file (.xlsx or .xls).', 'error');
            return;
        }

        this.excelFileName = file.name;
        this.excelValidationResult = null;
        this.excelParsedRows = null;
        this.quantityParsedRows = null;
        this.quantityValidationResult = null;
        this.isLoading = true;

        const reader = new FileReader();
        reader.onload = () => {
            try {
                // eslint-disable-next-line no-undef
                const workbook = XLSX.read(new Uint8Array(reader.result), { type: 'array' });
                const firstSheet = workbook.Sheets[workbook.SheetNames[0]];
                // eslint-disable-next-line no-undef
                const sheetData = XLSX.utils.sheet_to_json(firstSheet, { header: 1, defval: '' });

                if (this.isQuantityUpload) {
                    const parseResult = this.parseQuantityExcelSheet(sheetData);
                    if (parseResult.errors.length > 0) {
                        this.showToast('Error', 'Parse errors: ' + parseResult.errors[0], 'error');
                        this.isLoading = false;
                        return;
                    }
                    this.quantityParsedRows = parseResult.rows;
                    this.validateQuantityExcel();
                } else {
                    const parseResult = this.parseExcelSheet(sheetData);
                    if (parseResult.errors.length > 0) {
                        this.showToast('Error', 'Parse errors: ' + parseResult.errors[0], 'error');
                        this.isLoading = false;
                        return;
                    }
                    this.excelParsedRows = parseResult.rows;
                    this.validateExcel();
                }
            } catch (error) {
                this.showToast('Error', 'Failed to parse Excel file: ' + (error.message || error), 'error');
                this.isLoading = false;
            }
        };
        reader.onerror = () => {
            this.showToast('Error', 'Failed to read file.', 'error');
            this.isLoading = false;
        };
        reader.readAsArrayBuffer(file);
    }

    /**
     * Parses the pivoted Excel sheet into ExcelUploadRow objects.
     * Row 0: Currency group headers (merged → forward-fill)
     * Row 1: Tier sub-headers (EM1-EM5, None)
     * Row 2: Column header labels
     * Row 3+: Data rows
     */
    parseExcelSheet(sheetData) {
        const errors = [];
        const rows = [];

        if (!sheetData || sheetData.length < 4) {
            errors.push('Excel file must have at least 4 rows (2 header rows + column labels + data).');
            return { rows, errors };
        }

        const row0 = sheetData[0]; // Currency groups
        const row1 = sheetData[1]; // Tier sub-headers
        const row2 = sheetData[2]; // Column labels

        // Build column map
        const colMap = this.buildColumnMap(row0, row1, row2);
        if (colMap.errors.length > 0) {
            return { rows, errors: colMap.errors };
        }

        // Parse data rows (row 3+)
        for (let r = 3; r < sheetData.length; r++) {
            const dataRow = sheetData[r];
            if (!dataRow || dataRow.length === 0) continue;

            // Skip completely empty rows
            const hasContent = dataRow.some(cell => cell !== '' && cell != null);
            if (!hasContent) continue;

            const productCode = String(dataRow[colMap.productCodeIdx] || '').trim();
            const productId = String(dataRow[colMap.productIdIdx] || '').trim();
            const productName = String(dataRow[colMap.productNameIdx] || '').trim();
            const pricingBasis = String(dataRow[colMap.pricingBasisIdx] || '').trim();
            const meterType = String(dataRow[colMap.meterTypeIdx] || '').trim();

            // Sales channel from Pricebook column
            const rawChannel = colMap.pricebookIdx >= 0
                ? String(dataRow[colMap.pricebookIdx] || '').trim()
                : '';
            const channelKey = rawChannel.toLowerCase();
            const channelField = SALES_CHANNEL_MAP[channelKey] || null;

            const excelRow = {
                rowNumber: r + 1,
                productId,
                productCode,
                productName,
                pricingBasis,
                meterType,
                salesChannel: rawChannel,
                legalSales: channelField === 'legalSales',
                acSales: channelField === 'acSales',
                fsSales: channelField === 'fsSales',
                corporateSales: channelField === 'corporateSales',
                opsOnly: channelField === 'opsOnly',
                prices: []
            };

            // Extract prices from mapped columns
            for (const pc of colMap.priceColumns) {
                const rawVal = dataRow[pc.colIndex];
                if (rawVal === '' || rawVal == null) continue;
                const numVal = Number(rawVal);
                if (isNaN(numVal)) continue;

                excelRow.prices.push({
                    currencyCode: pc.currency,
                    tier: pc.tier,
                    price: numVal
                });
            }

            rows.push(excelRow);
        }

        if (rows.length === 0) {
            errors.push('No data rows found in the Excel file (data starts at row 4).');
        }

        return { rows, errors };
    }

    /**
     * Builds a column mapping from the 3 header rows.
     * Identifies info column indices and price column indices with their currency/tier.
     */
    buildColumnMap(row0, row1, row2) {
        const errors = [];
        const colMap = {
            productCodeIdx: -1,
            productIdIdx: -1,
            productNameIdx: -1,
            pricingBasisIdx: -1,
            meterTypeIdx: -1,
            pricebookIdx: -1,
            priceColumns: [],
            errors: []
        };

        // Identify fixed columns from row2 (column labels)
        for (let c = 0; c < row2.length; c++) {
            const label = String(row2[c] || '').trim().toLowerCase();
            if (label === 'product' || label === 'product code') {
                colMap.productCodeIdx = c;
            } else if (label === 'sfdc id' || label === 'sfdc_id' || label === 'product id') {
                colMap.productIdIdx = c;
            } else if (label === 'name' || label === 'product name') {
                colMap.productNameIdx = c;
            } else if (label === 'pricing' || label === 'pricing basis') {
                colMap.pricingBasisIdx = c;
            } else if (label === 'meter type' || label === 'meter_type') {
                colMap.meterTypeIdx = c;
            } else if (label === 'pricebook' || label === 'price book' || label === 'sales channel') {
                colMap.pricebookIdx = c;
            }
        }

        if (colMap.productIdIdx < 0) {
            errors.push('Could not find "SFDC ID" column in header row (row 3).');
        }
        if (colMap.meterTypeIdx < 0) {
            errors.push('Could not find "Meter Type" column in header row (row 3).');
        }
        if (colMap.productCodeIdx < 0) {
            errors.push('Could not find "Product" column in header row (row 3).');
        }

        if (errors.length > 0) {
            colMap.errors = errors;
            return colMap;
        }

        // Forward-fill currency from row0 (merged cells appear as empty after first)
        const validCurrencies = new Set(['USD', 'GBP', 'EUR', 'AUD']);
        const currencyRow = [];
        let lastCurrency = '';
        for (let c = 0; c < row0.length; c++) {
            const val = String(row0[c] || '').trim().toUpperCase();
            if (validCurrencies.has(val)) {
                lastCurrency = val;
            }
            currencyRow[c] = lastCurrency;
        }

        // Identify price columns: currency from row0 (forward-filled), tier from row1
        const validTiers = new Set(['EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None', 'NONE']);

        // Determine where price columns start (after the fixed info columns)
        const fixedIdxs = [
            colMap.productCodeIdx, colMap.productIdIdx, colMap.productNameIdx,
            colMap.pricingBasisIdx, colMap.meterTypeIdx, colMap.pricebookIdx
        ].filter(idx => idx >= 0);
        const infoEnd = Math.max(...fixedIdxs) + 1;

        for (let c = 0; c < row1.length; c++) {
            // Skip columns that are info columns
            if (fixedIdxs.includes(c)) continue;

            const tierVal = String(row1[c] || '').trim();
            const tierUpper = tierVal.toUpperCase();
            const currency = currencyRow[c] || '';

            // Must have both a valid currency and a valid tier
            if (currency && (validTiers.has(tierVal) || validTiers.has(tierUpper))) {
                colMap.priceColumns.push({
                    colIndex: c,
                    currency: currency,
                    tier: tierUpper === 'NONE' ? 'None' : tierVal
                });
            }
        }

        if (colMap.priceColumns.length === 0) {
            errors.push('Could not identify any price columns. Expected currency headers in row 1 and tier headers (EM1-EM5, None) in row 2.');
        }

        colMap.errors = errors;
        return colMap;
    }

    // =========================================================================
    // Phase 3: Quantity Pricing Excel Parsing
    // =========================================================================

    /**
     * Parses a Quantity Pricing Excel sheet (1 header row + data rows).
     * Header: Product Code | SFDC ID | Product Name | Meter Type | Lower Bound | Upper Bound | USD | GBP | EUR | AUD
     */
    parseQuantityExcelSheet(sheetData) {
        const errors = [];
        const rows = [];

        if (!sheetData || sheetData.length < 2) {
            errors.push('Excel file must have at least 2 rows (header + data).');
            return { rows, errors };
        }

        const headerRow = sheetData[0];
        const colMap = this.buildQuantityColumnMap(headerRow);
        if (colMap.errors.length > 0) {
            return { rows, errors: colMap.errors };
        }

        // Parse data rows (row 1+)
        for (let r = 1; r < sheetData.length; r++) {
            const dataRow = sheetData[r];
            if (!dataRow || dataRow.length === 0) continue;

            // Skip completely empty rows
            const hasContent = dataRow.some(cell => cell !== '' && cell != null);
            if (!hasContent) continue;

            const productCode = String(dataRow[colMap.productCodeIdx] || '').trim();
            const productId = String(dataRow[colMap.productIdIdx] || '').trim();
            const productName = colMap.productNameIdx >= 0
                ? String(dataRow[colMap.productNameIdx] || '').trim() : '';
            const meterType = String(dataRow[colMap.meterTypeIdx] || '').trim();
            const pricebook = colMap.pricebookIdx >= 0
                ? String(dataRow[colMap.pricebookIdx] || '').trim() : '';

            // Parse bounds
            const rawLower = dataRow[colMap.lowerBoundIdx];
            const rawUpper = dataRow[colMap.upperBoundIdx];
            const lowerBound = (rawLower !== '' && rawLower != null) ? Number(rawLower) : null;
            const upperBound = (rawUpper !== '' && rawUpper != null) ? Number(rawUpper) : null;

            const qtyRow = {
                rowNumber: r + 1,
                productId,
                productCode,
                productName,
                meterType,
                pricebook,
                lowerBound: (lowerBound != null && !isNaN(lowerBound)) ? lowerBound : null,
                upperBound: (upperBound != null && !isNaN(upperBound)) ? upperBound : null,
                prices: []
            };

            // Extract currency prices
            for (const pc of colMap.priceColumns) {
                const rawVal = dataRow[pc.colIndex];
                if (rawVal === '' || rawVal == null) continue;
                const numVal = Number(rawVal);
                if (isNaN(numVal)) continue;

                qtyRow.prices.push({
                    currencyCode: pc.currency,
                    price: numVal
                });
            }

            rows.push(qtyRow);
        }

        if (rows.length === 0) {
            errors.push('No data rows found in the Excel file (data starts at row 2).');
        }

        return { rows, errors };
    }

    /**
     * Builds column mapping for the Quantity Pricing template.
     * Identifies info columns and currency price columns from a single header row.
     */
    buildQuantityColumnMap(headerRow) {
        const errors = [];
        const colMap = {
            productCodeIdx: -1,
            productIdIdx: -1,
            productNameIdx: -1,
            meterTypeIdx: -1,
            lowerBoundIdx: -1,
            upperBoundIdx: -1,
            pricebookIdx: -1,
            priceColumns: [],
            errors: []
        };

        const validCurrencies = new Set(['USD', 'GBP', 'EUR', 'AUD']);

        for (let c = 0; c < headerRow.length; c++) {
            const label = String(headerRow[c] || '').trim().toLowerCase();
            if (label === 'product' || label === 'product code') {
                colMap.productCodeIdx = c;
            } else if (label === 'sfdc id' || label === 'sfdc_id' || label === 'product id') {
                colMap.productIdIdx = c;
            } else if (label === 'name' || label === 'product name') {
                colMap.productNameIdx = c;
            } else if (label === 'meter type' || label === 'meter_type') {
                colMap.meterTypeIdx = c;
            } else if (label === 'lower bound' || label === 'lower_bound') {
                colMap.lowerBoundIdx = c;
            } else if (label === 'upper bound' || label === 'upper_bound') {
                colMap.upperBoundIdx = c;
            } else if (label === 'pricebook') {
                colMap.pricebookIdx = c;
            } else {
                // Check if it's a currency column
                const upperLabel = String(headerRow[c] || '').trim().toUpperCase();
                if (validCurrencies.has(upperLabel)) {
                    colMap.priceColumns.push({ colIndex: c, currency: upperLabel });
                }
            }
        }

        // Validate required columns
        if (colMap.productIdIdx < 0) {
            errors.push('Could not find "SFDC ID" column in header row.');
        }
        if (colMap.productCodeIdx < 0) {
            errors.push('Could not find "Product Code" column in header row.');
        }
        if (colMap.meterTypeIdx < 0) {
            errors.push('Could not find "Meter Type" column in header row.');
        }
        if (colMap.lowerBoundIdx < 0) {
            errors.push('Could not find "Lower Bound" column in header row.');
        }
        if (colMap.upperBoundIdx < 0) {
            errors.push('Could not find "Upper Bound" column in header row.');
        }
        if (colMap.priceColumns.length === 0) {
            errors.push('Could not find any currency columns (USD, GBP, EUR, AUD) in header row.');
        }

        colMap.errors = errors;
        return colMap;
    }

    // =========================================================================
    // Phase 3: Quantity Pricing Validation & Processing
    // =========================================================================

    validateQuantityExcel() {
        this.isLoading = true;
        const uploadJson = JSON.stringify(this.quantityParsedRows);

        validateQuantityExcelUpload({ uploadJson })
            .then(result => {
                this.quantityValidationResult = result;
                if (result.isValid) {
                    this.showToast('Success',
                        result.rowCount + ' rows, ' + result.priceEntryCount + ' price entries validated successfully.',
                        'success');
                } else {
                    this.showToast('Warning', 'Validation found errors. Please review.', 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Validation failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleQuantityProcess() {
        this.isLoading = true;
        this.currentStep = '4';
        const uploadJson = JSON.stringify(this.quantityParsedRows);

        processQuantityExcelUpload({
            uploadJson,
            pricebookId: this.selectedPricebookId
        })
            .then(result => {
                this.processingResult = result;
                this.showToast('Success', 'Quantity pricing data processed successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Processing failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Phase 3: Tier Pricing Validation & Processing
    // =========================================================================

    validateExcel() {
        this.isLoading = true;
        const uploadJson = JSON.stringify(this.excelParsedRows);

        validateExcelUpload({ uploadJson })
            .then(result => {
                this.excelValidationResult = result;
                if (result.isValid) {
                    this.showToast('Success',
                        result.rowCount + ' rows, ' + result.priceEntryCount + ' price entries validated successfully.',
                        'success');
                } else {
                    this.showToast('Warning', 'Validation found errors. Please review.', 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Validation failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClearExcelFile() {
        this.excelFileName = '';
        this.excelParsedRows = null;
        this.excelValidationResult = null;
        this.quantityParsedRows = null;
        this.quantityValidationResult = null;
    }

    handleExcelProcess() {
        if (this.isQuantityUpload) {
            this.handleQuantityProcess();
            return;
        }

        this.isLoading = true;
        this.currentStep = '4';
        const uploadJson = JSON.stringify(this.excelParsedRows);

        processExcelUpload({
            uploadJson,
            pricebookId: this.selectedPricebookId
        })
            .then(result => {
                this.processingResult = result;
                this.showToast('Success', 'Pricing data processed successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Processing failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Legacy CSV handlers (kept for backward compatibility)
    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (file.size > 4 * 1024 * 1024) {
            this.showToast('Error', 'File size exceeds 4MB limit.', 'error');
            return;
        }

        this.csvFileName = file.name;
        this.validationResult = null;

        const reader = new FileReader();
        reader.onload = () => {
            this.csvContent = reader.result;
            this.validateCsv();
        };
        reader.onerror = () => {
            this.showToast('Error', 'Failed to read file.', 'error');
        };
        reader.readAsText(file);
    }

    validateCsv() {
        this.isLoading = true;
        validateCsvUpload({ csvContent: this.csvContent })
            .then(result => {
                this.validationResult = result;
                if (result.isValid) {
                    this.showToast('Success', result.rowCount + ' rows validated successfully.', 'success');
                } else {
                    this.showToast('Warning', 'Validation found errors. Please review.', 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Validation failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleClearFile() {
        this.csvContent = null;
        this.csvFileName = '';
        this.validationResult = null;
    }

    handleProcess() {
        this.isLoading = true;
        this.currentStep = '4';

        processPricingUpload({
            csvContent: this.csvContent,
            pricebookId: this.selectedPricebookId
        })
            .then(result => {
                this.processingResult = result;
                this.showToast('Success', 'Pricing data processed successfully!', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Processing failed: ' + this.extractError(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Phase 4 Handlers
    // =========================================================================

    handleViewResults() {
        this.isLoading = true;
        this.resultViewError = null;
        this.currentStep = '5';

        // Collect unique product IDs from the uploaded rows
        const productIdSet = new Set();
        const parsedRows = this.uploadType === 'quantity'
            ? this.quantityParsedRows
            : this.excelParsedRows;
        if (parsedRows) {
            parsedRows.forEach(row => {
                if (row.productId) {
                    productIdSet.add(row.productId);
                }
            });
        }

        getUploadResultView({
            pricebookId: this.selectedPricebookId,
            uploadType: this.uploadType,
            productIdsJson: JSON.stringify([...productIdSet])
        })
            .then(result => {
                this.resultViewData = result;
            })
            .catch(error => {
                this.resultViewError = this.extractError(error);
                this.showToast('Error', 'Failed to load results: ' + this.resultViewError, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleStartOver() {
        this.currentStep = '1';
        this.selectedPricebookId = null;
        this.pricebookChoice = 'existing';
        this.newPricebookName = '';
        this.isNewPricebook = false;
        this.setupJobId = null;
        this.setupStatus = '';
        this.setupMessage = '';
        this.csvContent = null;
        this.csvFileName = '';
        this.validationResult = null;
        this.uploadType = 'tier';
        this.excelFileName = '';
        this.excelParsedRows = null;
        this.excelValidationResult = null;
        this.quantityParsedRows = null;
        this.quantityValidationResult = null;
        this.processingResult = null;
        this.resultViewData = null;
        this.resultViewError = null;
        this.stopPolling();
        this.loadPricebooks();
    }

    // =========================================================================
    // Utility Methods
    // =========================================================================

    extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'Unknown error';
    }

    /**
     * Formats a price value with currency symbol and comma separators.
     * Mirrors pricebookView._formatPrice.
     */
    _formatPrice(price, currencyCode) {
        if (price == null) return '\u2014'; // em-dash
        const symbol = CURRENCY_SYMBOLS[currencyCode] || '';
        if (price === 0) return symbol + '0';
        const isWhole = price % 1 === 0;
        const parts = price.toFixed(isWhole ? 0 : 2).split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return symbol + parts.join('.');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}