import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/SheetJS';
import validateNewSkuLaunch from '@salesforce/apex/SkuNewLaunchController.validateNewSkuLaunch';
import processNewSkuLaunch from '@salesforce/apex/SkuNewLaunchController.processNewSkuLaunch';
import checkProductLineAndRollup from '@salesforce/apex/SkuNewLaunchController.checkProductLineAndRollup';
import createProductLineRecord from '@salesforce/apex/SkuNewLaunchController.createProductLineRecord';
import createProductRollupRecord from '@salesforce/apex/SkuNewLaunchController.createProductRollupRecord';
import generateMissingProductCodes from '@salesforce/apex/SkuNewLaunchController.generateMissingProductCodes';

// =========================================================================
// Column Header Mapping — SKU Details Tab
// =========================================================================

/** Maps normalized (lowercase) Excel header text to SkuDetailRow field names. */
const SKU_COLUMN_MAP = {
    'product code': 'productCode',
    'item master number': 'productCode',
    'product code / item master number': 'productCode',
    'item master name': 'itemMasterName',           // preserved separately for cross-tab code resolution
    'product name': 'productName',
    'item name': 'productName',
    'product name (col f)': 'productName',
    'product description': 'description',
    'description': 'description',
    'product line': 'productLine',
    'revenue type': 'revenueType',
    'product group': 'productGroup',
    'product type': 'productType',
    'includes assist': 'includesAssist',
    'includes ai': 'includesAssist',
    'eligible for premium': 'eligibleForPremium',
    'pricing basis': 'pricingBasis',
    'pricing basis (software)': 'pricingBasis',
    'percentage of acv': 'percentageOfAcv',
    '% of acv': 'percentageOfAcv',
    'services product type': 'servicesProductType',
    'software license term': 'softwareLicenseTerm',
    'subscription type': 'subscriptionType',
    'bundle': 'isBundle',
    'bundle?': 'isBundle',
    'bundle? (t/f)': 'isBundle',
    'deployment type': 'deploymentType',
    'product family': 'productFamily',
    'business unit': 'businessUnit',
    'line of business': 'lineOfBusinessProduct',
    'line of business (product)': 'lineOfBusinessProduct',
    'product rollup': 'productRollup',
    'sfdc pricebook': 'sfdcPricebook',
    'op4i pricebook': 'op4iPricebook',
    'op4i pricebook(s)': 'op4iPricebook',
    'subscription pricing': 'subscriptionPricing',
    // Sub-verticals
    'is legal': 'isLegal',
    'legal': 'isLegal',
    'is accounting': 'isAccounting',
    'accounting': 'isAccounting',
    'is consulting': 'isConsulting',
    'consulting': 'isConsulting',
    'is iba': 'isIBA',
    'iba': 'isIBA',
    'is pcm': 'isPCM',
    'pcm': 'isPCM',
    'is real assets': 'isRealAssets',
    'real assets': 'isRealAssets',
    'is corporate': 'isCorporate',
    'corporate': 'isCorporate',
    // NetSuite fields
    'netsuite income account': 'netsuiteIncomeAccount',
    'income account': 'netsuiteIncomeAccount',
    'netsuite deferred revenue account': 'netsuiteDeferredRevenueAccount',
    'deferred revenue account': 'netsuiteDeferredRevenueAccount',
    'netsuite item revenue category': 'netsuiteItemRevenueCategory',
    'item revenue category': 'netsuiteItemRevenueCategory',
    'netsuite revenue recognition rule': 'netsuiteRevRecognitionRule',
    'revenue recognition rule': 'netsuiteRevRecognitionRule',
    'netsuite rev rec forecast rule': 'netsuiteRevRecForecastRule',
    'rev rec forecast rule': 'netsuiteRevRecForecastRule',
    'netsuite revenue allocation group': 'netsuiteRevenueAllocationGroup',
    'revenue allocation group': 'netsuiteRevenueAllocationGroup',
    'netsuite create revenue plans on': 'netsuiteCreateRevenuePlansOn',
    'create revenue plans on': 'netsuiteCreateRevenuePlansOn',
    'netsuite item type for invoicing': 'netsuiteItemTypeForInvoicing',
    'item type for invoicing': 'netsuiteItemTypeForInvoicing',
    'netsuite revenue recognition template': 'netsuiteRevRecTemplate',
    'revenue recognition template': 'netsuiteRevRecTemplate',
    'netsuite include children': 'netsuiteIncludeChildren',
    'include children': 'netsuiteIncludeChildren',
    'openair billing rule': 'openAirBillingRule',
    'netsuite export to openair': 'netsuiteExportToOpenAir',
    'export to openair': 'netsuiteExportToOpenAir',
    'avalara tax code': 'avalaraTaxCode',
    'tax code': 'avalaraTaxCode',
    'netsuite tax schedule': 'netsuiteTaxSchedule',
    'tax schedule': 'netsuiteTaxSchedule',
    'trigger to netsuite': 'triggerToNetsuite',
    'trigger to ns': 'triggerToNetsuite',
    // NetSuite fields added for FY26 questionnaire
    'netsuite type': 'netsuiteType',
    'type': 'netsuiteType',
    'netsuite subtype': 'netsuiteSubType',
    'subtype': 'netsuiteSubType',
    'netsuite can be fulfilled': 'netsuiteCanBeFulfilled',
    'can be fulfilled': 'netsuiteCanBeFulfilled',
    'netsuite billing schedule': 'netsuiteBillingSchedule',
    'billing schedule': 'netsuiteBillingSchedule',
    'exempt from magic script': 'exemptFromMagicScript',
    'netsuite direct revenue posting': 'netsuiteDirectRevenuePosting',
    'direct revenue posting': 'netsuiteDirectRevenuePosting',
    'netsuite allocation type': 'netsuiteAllocationType',
    'allocation type': 'netsuiteAllocationType',
    'sync netsuite': 'syncNetsuite',
    // Read-only / system-populated fields (parsed for display, not sent to Apex)
    'netsuite internal id': 'netsuiteInternalId',
    'netsuite description': 'netsuiteDescription',
    'netsuite product line id': 'netsuiteProductLineId',
    'ns error': 'nsError'
};

// =========================================================================
// Column Header Mapping — Quote Terms Tab
// =========================================================================

/** Maps normalized (lowercase) Excel header text to QuoteTermRow field names. */
const QUOTE_TERM_COLUMN_MAP = {
    'im number': 'productCode',
    'item master number': 'productCode',
    'product code': 'productCode',
    'product name': 'productName',
    'quote term needed?': 'quoteTermNeeded',
    'quote term needed': 'quoteTermNeeded',
    'quote term': 'body',
    'quote term body': 'body',
    'body': 'body',
    'quote term #': 'termNumber',
    'term number': 'termNumber',
    '#': 'termNumber',
    'quote description': 'quoteDescription',
    'description': 'quoteDescription'
};

/** Boolean-like values from Excel. */
const TRUTHY = new Set(['true', 'yes', '1', 'y', 't']);

/** Valid currencies for price columns. */
const CURRENCIES = ['USD', 'GBP', 'EUR', 'AUD'];

/** Valid tiers for price columns. */
const TIER_NAMES = ['EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'];

// =========================================================================
// Component
// =========================================================================

export default class SkuNewLaunch extends LightningElement {

    // =========================================================================
    // State
    // =========================================================================

    @track currentStep = '1';
    @track isLoading = false;

    // Step 1 — Upload
    sheetJsLoaded = false;
    @track uploadFileName = '';
    @track parsedSkuDetails = [];
    @track parsedPricing = [];
    @track parsedBundles = [];
    @track parsedQuoteTerms = [];
    @track parseError = '';
    @track isParsed = false;

    // Step 2 — SKU Details Review
    @track expandedProductIndex = -1;

    // Step 3 — Pricing Review
    @track selectedPricingProduct = 'all';

    // Step 6 — Launch Summary Expand/Collapse
    _expandedLaunchSections = new Set();

    // Product Line / Product Rollup Resolution
    @track showProductLineModal = false;
    @track showProductRollupModal = false;
    @track missingProductLines = [];
    @track missingProductRollups = [];
    @track currentMissingPLIndex = 0;
    @track currentMissingPRIndex = 0;
    // Product Line creation form fields
    @track newPLName = '';
    @track newPLProductFamily = '';
    @track newPLDeployment = '';
    @track newPLBusinessUnit = '';
    @track newPLImpPrefix = '';
    @track newPLCloudAddendum = false;
    // Product Rollup creation form fields
    @track newPRName = '';
    @track newPRProductLine = '';
    @track productLineOptionsForRollup = [];

    // Step 6 — Launch & Results
    @track validationResult = null;
    @track launchResult = null;
    @track isProcessing = false;
    @track hasLaunched = false;

    // =========================================================================
    // Lifecycle
    // =========================================================================

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

    // =========================================================================
    // Step Navigation Getters
    // =========================================================================

    get steps() {
        return [
            { value: '1', label: 'Upload' },
            { value: '2', label: 'SKU Details' },
            { value: '3', label: 'Pricing Review' },
            { value: '4', label: 'Bundles Review' },
            { value: '5', label: 'Quote Terms Review' },
            { value: '6', label: 'Launch & Results' }
        ];
    }

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }
    get isStep5() { return this.currentStep === '5'; }
    get isStep6() { return this.currentStep === '6'; }

    get canGoNext() {
        if (this.currentStep === '1') return this.isParsed;
        if (this.currentStep === '6') return false;
        return true;
    }

    /** Hide nav buttons only after launch has been executed (results showing) */
    get hideNavButtons() {
        return this.isStep6 && this.hasLaunched;
    }

    /** Show the Launch button in the nav bar (bottom right) on Step 6 pre-launch */
    get showLaunchInNav() {
        return this.isStep6 && !this.hasLaunched && !this.isProcessing;
    }

    get canGoPrevious() {
        return this.currentStep !== '1';
    }

    get isLastReviewStep() {
        const step = parseInt(this.currentStep, 10);
        if (step === 5) return true;
        if (step === 4 && !this.hasQuoteTerms) return true;
        if (step === 3 && !this.hasBundles && !this.hasQuoteTerms) return true;
        return false;
    }

    get nextButtonLabel() {
        if (this.isLastReviewStep) return 'Proceed to Launch';
        return 'Next';
    }

    // =========================================================================
    // Step 1 Getters — Upload & Parse Summary
    // =========================================================================

    get hasBundles() {
        // Only true when there are actual bundle parents (isBundle == true in SKU Details)
        return this.bundleGroups.length > 0;
    }

    get hasQuoteTerms() {
        return this.parsedQuoteTerms && this.parsedQuoteTerms.length > 0;
    }

    get skuCount() {
        return this.parsedSkuDetails.length;
    }

    get pricingRowCount() {
        return this.parsedPricing.length;
    }

    get bundleRowCount() {
        return this.parsedBundles.length;
    }

    get quoteTermCount() {
        return this.parsedQuoteTerms.length;
    }

    get totalPriceEntries() {
        let count = 0;
        for (const row of this.parsedPricing) {
            if (row.prices) count += row.prices.length;
        }
        return count;
    }

    // =========================================================================
    // Step 2 Getters — SKU Detail Cards
    // =========================================================================

    get skuDetailCards() {
        return this.parsedSkuDetails.map((row, idx) => {
            const isExpanded = this.expandedProductIndex === idx;
            return {
                index: idx,
                key: row.productCode || `sku-${idx}`,
                productCode: row.productCode || '—',
                productName: row.productName || '—',
                productType: row.productType || '—',
                pricingBasis: row.pricingBasis || '—',
                revenueType: row.revenueType || '—',
                isBundle: row.isBundle === true,
                isExpanded,
                expandLabel: isExpanded ? 'Hide Details' : 'Show Details',
                expandIcon: isExpanded ? 'utility:chevronup' : 'utility:chevrondown',
                // Field groups for detail view
                itemMasterFields: this.buildFieldGroup('Item Master', {
                    'Item Name': row.productName,
                    'Description': row.description,
                    'Product Line': row.productLine,
                    'Revenue Type': row.revenueType
                }),
                productFields: this.buildFieldGroup('Product', {
                    'Product Name': row.productName,
                    'Product Type': row.productType,
                    'Includes AI': row.includesAssist ? 'Yes' : 'No',
                    'Eligible for Premium': row.eligibleForPremium ? 'Yes' : 'No',
                    'Pricing Basis': row.pricingBasis,
                    'Percentage of ACV': row.percentageOfAcv != null ? row.percentageOfAcv : null,
                    'Services Product Type': row.servicesProductType,
                    'License Term': row.softwareLicenseTerm,
                    'Subscription Type': row.subscriptionType,
                    'Bundle?': row.isBundle ? 'Yes' : 'No',
                    'Deployment Type': row.deploymentType,
                    'Product Family': row.productFamily,
                    'Business Unit': row.businessUnit,
                    'Product Rollup': row.productRollup,
                    'SFDC Pricebook': row.sfdcPricebook,
                    'OP4I Pricebook(s)': row.op4iPricebook,
                    'Subscription Pricing': row.subscriptionPricing
                }),
                subVerticalFields: this.buildFieldGroup('Sub-Verticals', {
                    'Legal': row.isLegal,
                    'Accounting': row.isAccounting,
                    'Consulting': row.isConsulting,
                    'IBA': row.isIBA,
                    'PCM': row.isPCM,
                    'Real Assets': row.isRealAssets,
                    'Corporate': row.isCorporate
                }),
                netsuiteFields: this.buildFieldGroup('NetSuite', {
                    'Type': row.netsuiteType,
                    'SubType': row.netsuiteSubType,
                    'Item Type For Invoicing': row.netsuiteItemTypeForInvoicing,
                    'Include Children': row.netsuiteIncludeChildren != null ? (row.netsuiteIncludeChildren ? 'Yes' : 'No') : null,
                    'Can be Fulfilled': row.netsuiteCanBeFulfilled != null ? (row.netsuiteCanBeFulfilled ? 'Yes' : 'No') : null,
                    'OpenAir Billing Rule': row.openAirBillingRule,
                    'Billing Schedule': row.netsuiteBillingSchedule,
                    'Export to OpenAir': row.netsuiteExportToOpenAir != null ? (row.netsuiteExportToOpenAir ? 'Yes' : 'No') : null,
                    'Revenue Allocation Group': row.netsuiteRevenueAllocationGroup,
                    'Exempt from Magic Script': row.exemptFromMagicScript != null ? (row.exemptFromMagicScript ? 'Yes' : 'No') : null,
                    'Revenue Category': row.netsuiteItemRevenueCategory,
                    'Income Account': row.netsuiteIncomeAccount,
                    'Direct Revenue Posting': row.netsuiteDirectRevenuePosting != null ? (row.netsuiteDirectRevenuePosting ? 'Yes' : 'No') : null,
                    'Deferred Revenue Account': row.netsuiteDeferredRevenueAccount,
                    'Rev Rec Rule': row.netsuiteRevRecognitionRule,
                    'Rev Rec Forecast': row.netsuiteRevRecForecastRule,
                    'Rev Rec Template': row.netsuiteRevRecTemplate,
                    'Create Revenue Plans On': row.netsuiteCreateRevenuePlansOn,
                    'Allocation Type': row.netsuiteAllocationType,
                    'Tax Code': row.avalaraTaxCode,
                    'Tax Schedule': row.netsuiteTaxSchedule,
                    'Sync NetSuite': row.syncNetsuite != null ? (row.syncNetsuite ? 'Yes' : 'No') : null,
                    'Trigger to NetSuite': row.triggerToNetsuite != null ? (row.triggerToNetsuite ? 'Yes' : 'No') : null
                })
            };
        });
    }

    buildFieldGroup(groupName, fieldMap) {
        const fields = [];
        for (const [label, value] of Object.entries(fieldMap)) {
            fields.push({
                key: `${groupName}-${label}`,
                label,
                value: (value != null && value !== '' && value !== undefined) ? String(value) : '—'
            });
        }
        return fields;
    }

    // =========================================================================
    // Step 3 Getters — Pricing Review
    // =========================================================================

    get pricingProductOptions() {
        const options = [{ label: 'All Products', value: 'all' }];
        const seen = new Set();
        for (const row of this.parsedPricing) {
            if (row.productCode && !seen.has(row.productCode)) {
                seen.add(row.productCode);
                options.push({
                    label: `${row.productCode} — ${row.productName || ''}`,
                    value: row.productCode
                });
            }
        }
        return options;
    }

    get filteredPricingRows() {
        if (this.selectedPricingProduct === 'all') return this.pricingDisplayRows;
        return this.pricingDisplayRows.filter(r => r.productCode === this.selectedPricingProduct);
    }

    get pricingDisplayRows() {
        return this.parsedPricing.map((row, idx) => {
            // Build currency-grouped price summaries
            const pricesByCurrency = {};
            if (row.prices) {
                for (const pe of row.prices) {
                    if (!pricesByCurrency[pe.currencyCode]) {
                        pricesByCurrency[pe.currencyCode] = [];
                    }
                    pricesByCurrency[pe.currencyCode].push({
                        key: `${pe.currencyCode}-${pe.tier}`,
                        tier: pe.tier,
                        price: pe.price != null ? `$${Number(pe.price).toFixed(2)}` : '—'
                    });
                }
            }

            const currencyGroups = CURRENCIES
                .filter(c => pricesByCurrency[c])
                .map(c => ({
                    key: c,
                    currency: c,
                    prices: pricesByCurrency[c]
                }));

            const skuRow = this.parsedSkuDetails.find(s => s.productCode === row.productCode);
            const eligibleForPremium = skuRow ? (skuRow.eligibleForPremium ? 'Yes' : 'No') : '—';

            return {
                key: `pricing-${idx}`,
                productCode: row.productCode,
                productName: row.productName,
                meterType: row.meterType,
                eligibleForPremium,
                legalSales: row.legalSales,
                acSales: row.acSales,
                fsSales: row.fsSales,
                corporateSales: row.corporateSales,
                opsOnly: row.opsOnly,
                currencyGroups,
                priceCount: row.prices ? row.prices.length : 0
            };
        });
    }

    // =========================================================================
    // Step 4 Getters — Bundles Review
    // =========================================================================

    get bundleGroups() {
        // Build a set of product codes that are actually bundles (isBundle == true in SKU Details)
        const bundleProductCodes = new Set();
        for (const sku of this.parsedSkuDetails) {
            if (sku.isBundle === true && sku.productCode) {
                bundleProductCodes.add(sku.productCode);
            }
        }

        const groups = {};
        for (const row of this.parsedBundles) {
            const parentCode = row.role === 'BUNDLE' ? row.imNumber : row.parentProductCode;
            if (!parentCode) continue;

            // Only include groups where the parent is actually marked as a bundle
            if (!bundleProductCodes.has(parentCode)) continue;

            if (!groups[parentCode]) {
                groups[parentCode] = { parentCode, parentName: '', components: [] };
            }
            if (row.role === 'BUNDLE') {
                groups[parentCode].parentName = row.productName;
            } else {
                groups[parentCode].components.push({
                    key: `${parentCode}-${row.imNumber}`,
                    productName: row.productName,
                    imNumber: row.imNumber,
                    acvPercent: row.acvPercent != null
                        ? (row.acvPercent <= 1 ? `${(row.acvPercent * 100).toFixed(0)}%` : `${row.acvPercent}%`)
                        : '—'
                });
            }
        }

        return Object.keys(groups).map(code => ({
            key: code,
            ...groups[code],
            componentCount: groups[code].components.length,
            acvTotal: groups[code].components.reduce((sum, c) => {
                const pct = this.parsedBundles.find(b => b.imNumber === c.imNumber)?.acvPercent || 0;
                return sum + pct;
            }, 0)
        }));
    }

    // =========================================================================
    // Step 5 Getters — Quote Terms Review
    // =========================================================================

    get quoteTermDisplayRows() {
        return this.parsedQuoteTerms.map((row, idx) => ({
            key: `qt-${idx}`,
            productCode: row.productCode,
            productName: row.productName,
            termNumber: row.termNumber,
            quoteDescription: row.quoteDescription || '',
            body: row.body || '—'
        }));
    }

    // =========================================================================
    // Step 6 Getters — Launch & Results
    // =========================================================================

    get preLaunchStats() {
        const stats = [
            { key: 'products', label: 'Products', value: this.skuCount, icon: 'utility:package' },
            { key: 'pricing', label: 'Pricing Rows', value: this.pricingRowCount, icon: 'utility:money' },
            { key: 'prices', label: 'Price Entries', value: this.totalPriceEntries, icon: 'utility:number_input' }
        ];
        if (this.hasBundles) {
            stats.push({ key: 'bundles', label: 'Bundle Rows', value: this.bundleRowCount, icon: 'utility:bundle_config' });
        }
        if (this.hasQuoteTerms) {
            stats.push({ key: 'quoteTerms', label: 'Quote Terms', value: this.quoteTermCount, icon: 'utility:contract' });
        }
        return stats;
    }

    get canLaunch() {
        return !this.isProcessing && !this.hasLaunched;
    }

    get hasLaunchResult() {
        return this.launchResult != null;
    }

    /** @description List of successfully created products for post-launch navigation */
    get createdProducts() {
        if (!this.launchResult || !this.launchResult.createdProducts) return [];
        return this.launchResult.createdProducts.map(p => ({
            ...p,
            key: p.productId,
            label: `${p.productName} (${p.productCode})`
        }));
    }

    get hasCreatedProducts() {
        return this.createdProducts.length > 0;
    }

    get isSingleProduct() {
        return this.createdProducts.length === 1;
    }

    get singleProductLabel() {
        if (!this.isSingleProduct) return '';
        const p = this.createdProducts[0];
        return `View ${p.productName} (${p.productCode})`;
    }

    get singleProductId() {
        if (!this.isSingleProduct) return '';
        return this.createdProducts[0].productId;
    }

    get launchStepResults() {
        if (!this.launchResult || !this.launchResult.steps) return [];
        return this.launchResult.steps.map((step, idx) => ({
            key: `step-${idx}`,
            objectName: step.objectName,
            successCount: step.successCount,
            errorCount: step.errorCount,
            totalCount: step.totalCount,
            hasErrors: step.errorCount > 0,
            statusClass: step.errorCount > 0 ? 'step-status step-status--error' : 'step-status step-status--success',
            statusIcon: step.errorCount > 0 ? 'utility:warning' : 'utility:check',
            errors: step.errors || []
        }));
    }

    get hasValidationErrors() {
        return this.validationResult && !this.validationResult.isValid;
    }

    get validationErrors() {
        return this.validationResult ? (this.validationResult.errors || []) : [];
    }

    get validationWarnings() {
        return this.validationResult ? (this.validationResult.warnings || []) : [];
    }

    // Launch Summary data getters
    get skuSummaryRows() {
        return this.parsedSkuDetails.map((sku, idx) => ({
            key: sku.productCode || `sku-sum-${idx}`,
            productCode: sku.productCode,
            productName: sku.productName,
            productType: sku.productType,
            revenueType: sku.revenueType,
            isBundle: sku.isBundle === true,
            productLine: sku.productLine,
            productFamily: sku.productFamily,
            pricingBasis: sku.pricingBasis,
            sfdcPricebook: sku.sfdcPricebook,
            deploymentType: sku.deploymentType,
            subscriptionType: sku.subscriptionType
        }));
    }

    get pricingSummaryRows() {
        return this.parsedPricing.map((pr, idx) => {
            const currencies = pr.prices ? [...new Set(pr.prices.map(p => p.currencyCode))].join(', ') : '';
            const skuRow = this.parsedSkuDetails.find(s => s.productCode === pr.productCode);
            const eligibleForPremium = skuRow ? (skuRow.eligibleForPremium ? 'Yes' : 'No') : '—';
            return {
                key: `pr-sum-${idx}`,
                productCode: pr.productCode,
                productName: pr.productName,
                meterType: pr.meterType,
                eligibleForPremium,
                priceCount: pr.prices ? pr.prices.length : 0,
                legalSales: pr.legalSales,
                acSales: pr.acSales,
                fsSales: pr.fsSales,
                corporateSales: pr.corporateSales,
                opsOnly: pr.opsOnly,
                currencySummary: currencies ? `Currencies: ${currencies}` : ''
            };
        });
    }

    get quoteTermSummaryRows() {
        return this.parsedQuoteTerms.map((qt, idx) => ({
            key: `qt-sum-${idx}`,
            productCode: qt.productCode,
            productName: qt.productName,
            termNumber: qt.termNumber,
            quoteDescription: qt.quoteDescription || '',
            body: qt.body || ''
        }));
    }

    // Launch Summary expand/collapse getters
    get isSkuSummaryExpanded() { return this._expandedLaunchSections.has('skuDetails'); }
    get isPricingSummaryExpanded() { return this._expandedLaunchSections.has('pricing'); }
    get isBundlesSummaryExpanded() { return this._expandedLaunchSections.has('bundles'); }
    get isQuoteTermsSummaryExpanded() { return this._expandedLaunchSections.has('quoteTerms'); }
    get skuSummaryIcon() { return this.isSkuSummaryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get pricingSummaryIcon() { return this.isPricingSummaryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get bundlesSummaryIcon() { return this.isBundlesSummaryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }
    get quoteTermsSummaryIcon() { return this.isQuoteTermsSummaryExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    handleToggleLaunchSection(event) {
        const section = event.currentTarget.dataset.section;
        const updated = new Set(this._expandedLaunchSections);
        if (updated.has(section)) {
            updated.delete(section);
        } else {
            updated.add(section);
        }
        this._expandedLaunchSections = updated;
    }

    // =========================================================================
    // Handlers — Step Navigation
    // =========================================================================

    handleNext() {
        const step = parseInt(this.currentStep, 10);
        let next = step + 1;
        // Skip Bundles (4) if no bundles
        if (next === 4 && !this.hasBundles) next++;
        // Skip Quote Terms (5) if no quote terms
        if (next === 5 && !this.hasQuoteTerms) next++;
        if (next <= 6) this.currentStep = String(next);
    }

    handlePrevious() {
        const step = parseInt(this.currentStep, 10);
        let prev = step - 1;
        // Skip Quote Terms (5) if no quote terms
        if (prev === 5 && !this.hasQuoteTerms) prev--;
        // Skip Bundles (4) if no bundles
        if (prev === 4 && !this.hasBundles) prev--;
        if (prev >= 1) this.currentStep = String(prev);
    }

    // =========================================================================
    // Handlers — Step 1: File Upload
    // =========================================================================

    _isDragOver = false;

    get uploadZoneClass() {
        return 'upload-zone' + (this._isDragOver ? ' upload-zone--dragover' : '');
    }

    handleUploadZoneClick() {
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) fileInput.click();
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        this._isDragOver = true;
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        this._isDragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        this._isDragOver = false;

        const files = event.dataTransfer.files;
        if (files && files.length > 0) {
            this._processFile(files[0]);
        }
    }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        this._processFile(file);
    }

    _processFile(file) {
        this.uploadFileName = file.name;
        this.parseError = '';
        this.isParsed = false;
        this.isLoading = true;

        const reader = new FileReader();
        reader.onload = async (e) => {
            try {
                /* global XLSX */
                const data = new Uint8Array(e.target.result);
                const workbook = XLSX.read(data, { type: 'array' });

                // Find tabs by name (flexible matching)
                const skuSheet = this.findSheet(workbook, ['SKU Details', 'SKU_Details', 'Details', 'SKU']);
                const pricingSheet = this.findSheet(workbook, ['Pricing', 'Price', 'Prices']);
                const bundleSheet = this.findSheet(workbook, [
                    'Bundles Allocations', 'Bundle Allocations', 'Bundles', 'Bundle'
                ]);
                const quoteTermSheet = this.findSheet(workbook, [
                    'Quote Terms', 'Quote_Terms', 'QuoteTerms', 'Quote Term'
                ]);

                if (!skuSheet) {
                    throw new Error('Could not find "SKU Details" tab in the workbook. Available tabs: ' +
                        workbook.SheetNames.join(', '));
                }
                if (!pricingSheet) {
                    throw new Error('Could not find "Pricing" tab in the workbook. Available tabs: ' +
                        workbook.SheetNames.join(', '));
                }

                // Parse each tab
                this.parsedSkuDetails = this.parseSkuDetailsTab(skuSheet);
                this.parsedPricing = this.parsePricingTab(pricingSheet);
                this.parsedBundles = bundleSheet ? this.parseBundlesTab(bundleSheet) : [];
                this.parsedQuoteTerms = quoteTermSheet ? this.parseQuoteTermsTab(quoteTermSheet) : [];

                // Auto-generate Product Codes for any SKU rows where the column was left blank
                // or contains a questionnaire placeholder such as "leave blank, system created."
                // Queries the last created Item Master Product in the org to determine the next
                // incremental number, then combines it with the Product Line's IMP prefix.
                this.parsedSkuDetails = this.parsedSkuDetails.map(r => {
                    const code = r.productCode ? r.productCode.trim().toLowerCase() : '';
                    if (code.includes('leave blank') || code.includes('system created')) {
                        return { ...r, productCode: '' };
                    }
                    return r;
                });
                const blankCodeRows = this.parsedSkuDetails.filter(r => !r.productCode);
                if (blankCodeRows.length > 0) {
                    try {
                        const codeResult = await generateMissingProductCodes({
                            skuDetailsJson: JSON.stringify(this.parsedSkuDetails)
                        });
                        if (codeResult.generatedCount > 0) {
                            this.parsedSkuDetails = codeResult.updatedSkuDetails;
                            this._propagateGeneratedCodes(codeResult.generatedCodes);
                            const codeList = codeResult.generatedCodes
                                .map(g => `${g.productName}: ${g.impCode || g.generatedCode}`)
                                .join(', ');
                            this.showToast(
                                'Product Codes Auto-Generated',
                                `${codeResult.generatedCount} code(s) generated — ${codeList}`,
                                'info'
                            );
                        }
                    } catch (genErr) {
                        // Non-fatal: validation will surface missing codes if generation failed
                        this.showToast(
                            'Warning',
                            'Could not auto-generate product codes. Please populate them manually before launching.',
                            'warning'
                        );
                    }
                }

                // Resolve blank/instructional BUNDLE IM Numbers by matching product name to SKU Details
                if (this.parsedBundles.length > 0 && this.parsedSkuDetails.length > 0) {
                    const skuByName = new Map(
                        this.parsedSkuDetails
                            .filter(s => s.productCode && s.productName)
                            .map(s => [s.productName.trim().toLowerCase(), s.productCode])
                    );
                    let resolvedParent = '';
                    for (const row of this.parsedBundles) {
                        if (row.role === 'BUNDLE') {
                            const isBlankOrInstructional = !row.imNumber ||
                                row.imNumber.toLowerCase().includes('leave blank') ||
                                row.imNumber.toLowerCase().includes('system created');
                            if (isBlankOrInstructional) {
                                const matched = skuByName.get(row.productName.trim().toLowerCase());
                                if (matched) {
                                    row.imNumber = matched;
                                    row.parentProductCode = matched;
                                }
                            }
                            resolvedParent = row.imNumber;
                        } else if (!row.parentProductCode ||
                                   row.parentProductCode.toLowerCase().includes('leave blank') ||
                                   row.parentProductCode.toLowerCase().includes('system created')) {
                            row.parentProductCode = resolvedParent;
                        }
                    }
                }

                // Filter bundle rows to only include entries for products actually marked as bundles
                if (this.parsedBundles.length > 0) {
                    const bundleCodes = new Set(
                        this.parsedSkuDetails.filter(s => s.isBundle === true).map(s => s.productCode)
                    );
                    this.parsedBundles = this.parsedBundles.filter(row => {
                        const parentCode = row.role === 'BUNDLE' ? row.imNumber : row.parentProductCode;
                        return parentCode && bundleCodes.has(parentCode);
                    });
                }

                // Derive meter type mappings from pricing data
                this.deriveMeterTypeMappings();

                this.isParsed = true;
                let toastMsg = `Parsed ${this.skuCount} products, ${this.pricingRowCount} pricing rows`;
                if (this.hasBundles) toastMsg += `, ${this.bundleRowCount} bundle rows`;
                if (this.hasQuoteTerms) toastMsg += `, ${this.quoteTermCount} quote terms`;
                this.showToast('Success', toastMsg, 'success');

                // Check Product Line and Product Rollup existence in org
                // eslint-disable-next-line no-unused-expressions
                this.checkProductLineAndRollupInOrg();

            } catch (err) {
                this.parseError = err.message || 'Unknown parse error';
                this.showToast('Parse Error', this.parseError, 'error');
            } finally {
                this.isLoading = false;
            }
        };

        reader.onerror = () => {
            this.parseError = 'Failed to read file.';
            this.isLoading = false;
        };

        reader.readAsArrayBuffer(file);
    }

    handleRemoveFile() {
        this.uploadFileName = '';
        this.isParsed = false;
        this.parsedSkuDetails = [];
        this.parsedPricing = [];
        this.parsedBundles = [];
        this.parsedQuoteTerms = [];
        this.parseError = '';
    }

    // =========================================================================
    // Handlers — Step 2: Product Detail Toggle
    // =========================================================================

    handleToggleProduct(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.expandedProductIndex = this.expandedProductIndex === idx ? -1 : idx;
    }

    // =========================================================================
    // Handlers — Step 3: Pricing Filter
    // =========================================================================

    handlePricingProductChange(event) {
        this.selectedPricingProduct = event.detail.value;
    }

    // =========================================================================
    // Handlers — Step 6: Launch
    // =========================================================================

    async handleLaunch() {
        this.isProcessing = true;
        this.validationResult = null;
        this.launchResult = null;

        const skuDetailsJson = JSON.stringify(this.parsedSkuDetails);
        const pricingJson = JSON.stringify(this.parsedPricing);
        const bundlesJson = this.hasBundles ? JSON.stringify(this.parsedBundles) : null;
        const quoteTermsJson = this.hasQuoteTerms ? JSON.stringify(this.parsedQuoteTerms) : null;

        try {
            // Step A: Server-side validation
            const validation = await validateNewSkuLaunch({
                skuDetailsJson,
                pricingJson,
                bundlesJson,
                quoteTermsJson
            });

            this.validationResult = validation;

            if (!validation.isValid) {
                this.showToast('Validation Failed', 'Please fix the errors before launching.', 'error');
                this.isProcessing = false;
                return;
            }

            // Step B: Process (create all records)
            const launchResult = await processNewSkuLaunch({
                skuDetailsJson,
                pricingJson,
                bundlesJson,
                quoteTermsJson
            });

            this.launchResult = launchResult;
            this.hasLaunched = true;

            if (launchResult.totalErrors > 0) {
                this.showToast('Launch Complete (with errors)',
                    `${launchResult.totalSuccess} records created, ${launchResult.totalErrors} errors.`, 'warning');
            } else {
                this.showToast('Launch Successful',
                    `${launchResult.totalSuccess} records created successfully!`, 'success');
            }

        } catch (error) {
            this.showToast('Launch Failed', this.extractError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    handleStartOver() {
        this.currentStep = '1';
        this.uploadFileName = '';
        this.isParsed = false;
        this.parsedSkuDetails = [];
        this.parsedPricing = [];
        this.parsedBundles = [];
        this.parsedQuoteTerms = [];
        this.parseError = '';
        this.validationResult = null;
        this.launchResult = null;
        this.isProcessing = false;
        this.hasLaunched = false;
        this.expandedProductIndex = -1;
        this.selectedPricingProduct = 'all';
        this.missingProductLines = [];
        this.missingProductRollups = [];
        this.showProductLineModal = false;
        this.showProductRollupModal = false;
    }

    /**
     * @description Navigate to Update Product page for a specific product.
     *              Fires a custom event that the parent skuManagementApp handles.
     */
    handleViewProduct(event) {
        const productId = event.currentTarget.dataset.productId;
        this.dispatchEvent(new CustomEvent('navigatetotab', {
            detail: { tabName: 'unifiedUpdate', productId },
            bubbles: true,
            composed: true
        }));
    }

    // =========================================================================
    // Handlers — Product Line & Product Rollup Resolution
    // =========================================================================

    /**
     * After parsing, checks if Product Lines and Product Rollups exist in the org.
     * Opens modal dialogs for any that are missing, prompting the user to create them.
     */
    async checkProductLineAndRollupInOrg() {
        this.isLoading = true;
        try {
            // Collect unique Product Line and Product Rollup names from parsed data
            const productLineNames = [...new Set(
                this.parsedSkuDetails
                    .map(d => d.productLine)
                    .filter(name => name != null && name.trim() !== '')
            )];
            const productRollupNames = [...new Set(
                this.parsedSkuDetails
                    .map(d => d.productRollup)
                    .filter(name => name != null && name.trim() !== '')
            )];

            if (productLineNames.length === 0 && productRollupNames.length === 0) {
                return; // Nothing to check
            }

            // Call Apex to check existence
            const result = await checkProductLineAndRollup({
                productLineNames: productLineNames,
                productRollupNames: productRollupNames
            });

            this.missingProductLines = result.missingProductLines || [];
            this.missingProductRollups = result.missingProductRollups || [];

            // Store existing product lines for dropdown in rollup creation
            this.productLineOptionsForRollup = (result.existingProductLines || []).map(pl => ({
                label: pl.name,
                value: pl.name
            }));

            // If there are missing Product Lines, show modal for first one
            if (this.missingProductLines.length > 0) {
                this.currentMissingPLIndex = 0;
                this.resetProductLineForm(this.missingProductLines[0]);
                this.showProductLineModal = true;
            }
            // If no missing PLs but missing PRs, show PR modal
            else if (this.missingProductRollups.length > 0) {
                this.currentMissingPRIndex = 0;
                this.resetProductRollupForm(this.missingProductRollups[0]);
                this.showProductRollupModal = true;
            }

        } catch (error) {
            this.showToast('Warning', 'Could not verify Product Lines/Rollups: ' + this.extractError(error), 'warning');
        } finally {
            this.isLoading = false;
        }
    }

    // --- Product Line Modal ---

    get currentMissingPLName() {
        return this.missingProductLines[this.currentMissingPLIndex] || '';
    }

    get productLineModalTitle() {
        return `Create Product Line: ${this.currentMissingPLName}`;
    }

    get productLineProgress() {
        return `${this.currentMissingPLIndex + 1} of ${this.missingProductLines.length}`;
    }

    get productFamilyOptions() {
        return [
            { label: '-- Select --', value: '' },
            { label: 'CRM', value: 'CRM' },
            { label: 'Conflicts', value: 'Conflicts' },
            { label: 'Experience', value: 'Experience' },
            { label: 'Intake', value: 'Intake' },
            { label: 'Integrate', value: 'Integrate' },
            { label: 'Pricing', value: 'Pricing' },
            { label: 'Relationships', value: 'Relationships' },
            { label: 'Terms', value: 'Terms' },
            { label: 'Content', value: 'Content' },
            { label: 'Time', value: 'Time' },
            { label: 'Walls', value: 'Walls' },
            { label: 'Flow', value: 'Flow' },
            { label: 'DealCloud', value: 'DealCloud' },
            { label: 'Small Firms', value: 'Small Firms' },
            { label: 'Collaboration & Content', value: 'Collaboration & Content' },
            { label: 'Documents', value: 'Documents' },
            { label: 'Workspaces', value: 'Workspaces' },
            { label: 'Employee Compliance', value: 'Employee Compliance' },
            { label: 'Celeste', value: 'Celeste' },
            { label: 'Other', value: 'Other' },
            { label: 'Multiple Products', value: 'Multiple Products' }
        ];
    }

    get deploymentOptions() {
        return [
            { label: '-- Select --', value: '' },
            { label: 'Cloud', value: 'Cloud' },
            { label: 'On-Premise', value: 'On-Premise' },
            { label: 'Multiple', value: 'Multiple' }
        ];
    }

    get businessUnitOptions() {
        return [
            { label: '-- Select --', value: '' },
            { label: 'DealCloud', value: 'DealCloud' },
            { label: 'Compliance', value: 'Compliance' },
            { label: 'Tech', value: 'Tech' },
            { label: 'OnePlace', value: 'OnePlace' },
            { label: 'Collaborations & Content', value: 'Collaborations & Content' },
            { label: 'Knowledge & Content', value: 'Knowledge & Content' },
            { label: 'Leaders & Professionals', value: 'Leaders & Professionals' },
            { label: 'Marketing & BD', value: 'Marketing & BD' },
            { label: 'Multiple Products', value: 'Multiple Products' },
            { label: 'Operations & Finance', value: 'Operations & Finance' }
        ];
    }

    resetProductLineForm(plName) {
        this.newPLName = plName || '';
        this.newPLProductFamily = '';
        this.newPLDeployment = '';
        this.newPLBusinessUnit = '';
        this.newPLImpPrefix = '';
        this.newPLCloudAddendum = false;
    }

    handlePLFieldChange(event) {
        const field = event.target.dataset.field;
        if (field === 'productFamily') this.newPLProductFamily = event.detail.value;
        else if (field === 'deployment') this.newPLDeployment = event.detail.value;
        else if (field === 'businessUnit') this.newPLBusinessUnit = event.detail.value;
        else if (field === 'impPrefix') this.newPLImpPrefix = event.detail.value;
        else if (field === 'cloudAddendum') this.newPLCloudAddendum = event.target.checked;
    }

    async handleCreateProductLine() {
        this.isLoading = true;
        try {
            const createdPL = await createProductLineRecord({
                name: this.currentMissingPLName,
                productFamily: this.newPLProductFamily,
                deployment: this.newPLDeployment,
                businessUnit: this.newPLBusinessUnit,
                impPrefix: this.newPLImpPrefix,
                cloudAddendumRequired: this.newPLCloudAddendum
            });

            this.showToast('Success', `Product Line "${this.currentMissingPLName}" created.`, 'success');

            // Add to the rollup dropdown options
            this.productLineOptionsForRollup = [
                ...this.productLineOptionsForRollup,
                { label: this.currentMissingPLName, value: this.currentMissingPLName }
            ];

            // Move to next missing Product Line
            this.currentMissingPLIndex++;
            if (this.currentMissingPLIndex < this.missingProductLines.length) {
                this.resetProductLineForm(this.missingProductLines[this.currentMissingPLIndex]);
            } else {
                // Done with Product Lines — check Product Rollups
                this.showProductLineModal = false;
                if (this.missingProductRollups.length > 0) {
                    this.currentMissingPRIndex = 0;
                    this.resetProductRollupForm(this.missingProductRollups[0]);
                    this.showProductRollupModal = true;
                }
            }

        } catch (error) {
            this.showToast('Error', 'Failed to create Product Line: ' + this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSkipProductLine() {
        this.currentMissingPLIndex++;
        if (this.currentMissingPLIndex < this.missingProductLines.length) {
            this.resetProductLineForm(this.missingProductLines[this.currentMissingPLIndex]);
        } else {
            this.showProductLineModal = false;
            if (this.missingProductRollups.length > 0) {
                this.currentMissingPRIndex = 0;
                this.resetProductRollupForm(this.missingProductRollups[0]);
                this.showProductRollupModal = true;
            }
        }
    }

    handleCloseProductLineModal() {
        this.showProductLineModal = false;
        // Continue to Product Rollup check if needed
        if (this.missingProductRollups.length > 0) {
            this.currentMissingPRIndex = 0;
            this.resetProductRollupForm(this.missingProductRollups[0]);
            this.showProductRollupModal = true;
        }
    }

    // --- Product Rollup Modal ---

    get currentMissingPRName() {
        return this.missingProductRollups[this.currentMissingPRIndex] || '';
    }

    get productRollupModalTitle() {
        return `Create Product Rollup: ${this.currentMissingPRName}`;
    }

    get productRollupProgress() {
        return `${this.currentMissingPRIndex + 1} of ${this.missingProductRollups.length}`;
    }

    resetProductRollupForm(prName) {
        this.newPRName = prName || '';
        this.newPRProductLine = '';
    }

    handlePRFieldChange(event) {
        const field = event.target.dataset.field;
        if (field === 'productLine') this.newPRProductLine = event.detail.value;
    }

    async handleCreateProductRollup() {
        if (!this.newPRProductLine) {
            this.showToast('Error', 'Please select a Product Line for this Product Rollup.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await createProductRollupRecord({
                name: this.currentMissingPRName,
                productLineName: this.newPRProductLine
            });

            this.showToast('Success', `Product Rollup "${this.currentMissingPRName}" created.`, 'success');

            // Move to next missing Product Rollup
            this.currentMissingPRIndex++;
            if (this.currentMissingPRIndex < this.missingProductRollups.length) {
                this.resetProductRollupForm(this.missingProductRollups[this.currentMissingPRIndex]);
            } else {
                this.showProductRollupModal = false;
            }

        } catch (error) {
            this.showToast('Error', 'Failed to create Product Rollup: ' + this.extractError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSkipProductRollup() {
        this.currentMissingPRIndex++;
        if (this.currentMissingPRIndex < this.missingProductRollups.length) {
            this.resetProductRollupForm(this.missingProductRollups[this.currentMissingPRIndex]);
        } else {
            this.showProductRollupModal = false;
        }
    }

    handleCloseProductRollupModal() {
        this.showProductRollupModal = false;
    }

    // =========================================================================
    // Excel Parsing — Utilities
    // =========================================================================

    /**
     * Strips invisible Unicode characters (zero-width spaces, BOM, non-breaking
     * spaces, etc.) that Excel sometimes embeds in cells, then trims whitespace.
     * Standard .trim() does NOT remove these characters.
     */
    // eslint-disable-next-line class-methods-use-this
    cleanCode(raw) {
        if (raw == null) return '';
        return String(raw)
            // eslint-disable-next-line no-control-regex
            .replace(/[\u0000-\u001F\u007F\u00A0\u200B-\u200F\u2028\u2029\uFEFF]/g, '')
            .trim();
    }

    // =========================================================================
    // Excel Parsing — SKU Details Tab
    // =========================================================================

    parseSkuDetailsTab(worksheet) {
        const rows = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });
        if (rows.length < 2) {
            throw new Error('SKU Details tab must have at least a header row and one data row.');
        }

        // Build column index -> field name map from header row
        const headerRow = rows[0];
        const columnMap = this.buildColumnMap(headerRow, SKU_COLUMN_MAP);

        if (!Object.values(columnMap).includes('productCode')) {
            throw new Error('SKU Details tab: Could not find "Product Code" column in headers: ' +
                headerRow.filter(h => h).join(', '));
        }

        const result = [];
        for (let i = 1; i < rows.length; i++) {
            const row = rows[i];
            // Skip empty rows
            if (!row || row.every(cell => cell === '' || cell == null)) continue;

            const detail = {};
            for (const [colIdx, fieldName] of Object.entries(columnMap)) {
                let value = row[colIdx];
                if (value === '' || value == null) {
                    value = null;
                } else {
                    // Use cleanCode for productCode fields to strip invisible Unicode chars
                    value = fieldName === 'productCode' ? this.cleanCode(value) : String(value).trim();
                }

                // Handle boolean fields
                if (fieldName === 'isBundle' || fieldName === 'includesAssist' ||
                    fieldName === 'eligibleForPremium' || fieldName === 'triggerToNetsuite' ||
                    fieldName === 'netsuiteIncludeChildren' || fieldName === 'netsuiteExportToOpenAir' ||
                    fieldName === 'netsuiteCanBeFulfilled' || fieldName === 'exemptFromMagicScript' ||
                    fieldName === 'netsuiteDirectRevenuePosting' || fieldName === 'syncNetsuite') {
                    detail[fieldName] = value != null && TRUTHY.has(value.toLowerCase());
                } else if (fieldName === 'percentageOfAcv') {
                    detail[fieldName] = value != null ? parseFloat(value) : null;
                } else {
                    detail[fieldName] = value;
                }
            }

            // Only add if productCode is present
            if (detail.productCode) {
                result.push(detail);
            }
        }

        return result;
    }

    // =========================================================================
    // Excel Parsing — Pricing Tab (Pivoted Matrix)
    // =========================================================================

    parsePricingTab(worksheet) {
        const rows = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });
        if (rows.length < 3) {
            throw new Error('Pricing tab must have at least a currency row, header row, and one data row.');
        }

        // Row 0: Currency headers — scan for USD, GBP, EUR, AUD
        const currencyRow = rows[0].map(c => String(c || '').trim().toUpperCase());

        // Row 1: Column headers
        const headerRow = rows[1].map(c => String(c || '').trim());

        // Identify non-price columns (left side)
        // Find the index where price columns start (first column under a known currency)
        let firstPriceCol = -1;
        for (let c = 0; c < currencyRow.length; c++) {
            if (CURRENCIES.includes(currencyRow[c])) {
                firstPriceCol = c;
                break;
            }
        }

        if (firstPriceCol === -1) {
            throw new Error('Pricing tab: Could not find currency headers (USD/GBP/EUR/AUD) in row 1.');
        }

        // Map left-side columns
        const leftHeaders = {};
        for (let c = 0; c < firstPriceCol; c++) {
            const h = headerRow[c].toLowerCase();
            if (h.includes('item master name') || (h.includes('product name') && !h.includes('im')) || h === 'product') leftHeaders.productName = c;
            else if (h.includes('im number') || h.includes('product code') || h.includes('item master') || h === 'im#') leftHeaders.productCode = c;
            else if (h.includes('meter type') || h === 'meter') leftHeaders.meterType = c;
            else if (h.includes('legal') && h.includes('sales')) leftHeaders.legalSales = c;
            else if ((h.includes('a&c') || h.includes('a & c') || h.includes('ac')) && h.includes('sales')) leftHeaders.acSales = c;
            else if (h.includes('fs') && h.includes('sales')) leftHeaders.fsSales = c;
            else if (h.includes('corporate') && h.includes('sales')) leftHeaders.corporateSales = c;
            else if (h.includes('ops')) leftHeaders.opsOnly = c;
            else if (h.includes('premium')) leftHeaders.premiumSupport = c;
        }

        // Map price columns: [colIndex] -> { currency, tier }
        const priceColumns = [];
        let currentCurrency = '';
        for (let c = firstPriceCol; c < currencyRow.length; c++) {
            if (CURRENCIES.includes(currencyRow[c])) {
                currentCurrency = currencyRow[c];
            }
            const tierName = String(headerRow[c] || '').trim();
            if (currentCurrency && tierName && TIER_NAMES.includes(tierName)) {
                priceColumns.push({ colIndex: c, currency: currentCurrency, tier: tierName });
            }
        }

        if (priceColumns.length === 0) {
            throw new Error('Pricing tab: Could not identify any price columns. Expected tier names (EM1-EM5, None) under currency headers.');
        }

        // Parse data rows (row 2+)
        const result = [];
        for (let i = 2; i < rows.length; i++) {
            const row = rows[i];
            if (!row || row.every(cell => cell === '' || cell == null)) continue;

            const productCode = leftHeaders.productCode != null ? this.cleanCode(row[leftHeaders.productCode]) : '';
            if (!productCode) continue;

            const pricingRow = {
                productCode,
                productName: leftHeaders.productName != null ? String(row[leftHeaders.productName] || '').trim() : '',
                meterType: leftHeaders.meterType != null ? String(row[leftHeaders.meterType] || '').trim() : '',
                legalSales: leftHeaders.legalSales != null && this.isTruthy(row[leftHeaders.legalSales]),
                acSales: leftHeaders.acSales != null && this.isTruthy(row[leftHeaders.acSales]),
                fsSales: leftHeaders.fsSales != null && this.isTruthy(row[leftHeaders.fsSales]),
                corporateSales: leftHeaders.corporateSales != null && this.isTruthy(row[leftHeaders.corporateSales]),
                opsOnly: leftHeaders.opsOnly != null && this.isTruthy(row[leftHeaders.opsOnly]),
                premiumSupport: leftHeaders.premiumSupport != null && this.isTruthy(row[leftHeaders.premiumSupport]),
                prices: []
            };

            // Extract price entries
            for (const pc of priceColumns) {
                const rawPrice = row[pc.colIndex];
                if (rawPrice != null && rawPrice !== '' && !isNaN(Number(rawPrice))) {
                    pricingRow.prices.push({
                        currencyCode: pc.currency,
                        tier: pc.tier,
                        price: Number(rawPrice)
                    });
                }
            }

            result.push(pricingRow);
        }

        return result;
    }

    // =========================================================================
    // Excel Parsing — Bundles Allocations Tab
    // =========================================================================

    parseBundlesTab(worksheet) {
        const rows = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });
        if (rows.length < 2) return [];

        // Scan for the actual header row — look for a row with 'Product Name' and 'IM Number' headers
        let headerRowIdx = 0;
        for (let r = 0; r < Math.min(rows.length, 5); r++) {
            const candidateRow = rows[r].map(c => String(c || '').trim().toLowerCase());
            const hasName = candidateRow.some(h => h === 'product name' || h === 'name');
            const hasIM = candidateRow.some(h => h.includes('im number') || h.includes('product code'));
            if (hasName && hasIM) {
                headerRowIdx = r;
                break;
            }
        }

        const headerRow = rows[headerRowIdx].map(c => String(c || '').trim().toLowerCase());

        // Find columns
        const colMap = {
            role: headerRow.findIndex(h => h.includes('role') || h.includes('bundle')),
            productName: headerRow.findIndex(h => h.includes('product name') || h === 'name'),
            imNumber: headerRow.findIndex(h => h.includes('im') || h.includes('product code') || h.includes('item master')),
            acvPercent: headerRow.findIndex(h => h.includes('acv') || h.includes('%'))
        };

        // If no explicit role column found, auto-detect from first data row
        if (colMap.role < 0) {
            const firstDataRow = rows[headerRowIdx + 1];
            if (firstDataRow) {
                for (let c = 0; c < firstDataRow.length; c++) {
                    const cellVal = String(firstDataRow[c] || '').trim().toUpperCase();
                    if (cellVal === 'BUNDLE' || cellVal === 'COMPONENT PRODUCT') {
                        colMap.role = c;
                        break;
                    }
                }
            }
        }

        const result = [];
        let currentParentCode = '';

        for (let i = headerRowIdx + 1; i < rows.length; i++) {
            const row = rows[i];
            if (!row || row.every(cell => cell === '' || cell == null)) continue;

            const role = colMap.role >= 0 ? String(row[colMap.role] || '').trim().toUpperCase() : '';
            const productName = colMap.productName >= 0 ? String(row[colMap.productName] || '').trim() : '';
            const imNumber = colMap.imNumber >= 0 ? this.cleanCode(row[colMap.imNumber]) : '';
            const acvRaw = colMap.acvPercent >= 0 ? row[colMap.acvPercent] : null;
            const acvPercent = acvRaw != null && acvRaw !== '' ? Number(acvRaw) : null;

            if (role === 'BUNDLE') {
                currentParentCode = imNumber;
            }

            // Skip placeholder component rows (XX-XXXX pattern with no product name)
            if (role !== 'BUNDLE' && /^X{2,}-X{3,}$/i.test(imNumber) && !productName.trim()) {
                continue;
            }

            result.push({
                role: role === 'BUNDLE' ? 'BUNDLE' : 'Component Product',
                productName,
                imNumber,
                acvPercent,
                parentProductCode: role === 'BUNDLE' ? imNumber : currentParentCode
            });
        }

        return result;
    }

    // =========================================================================
    // Excel Parsing — Quote Terms Tab
    // =========================================================================

    /**
     * Parses the "Quote Terms" worksheet into an array of quote term objects.
     * Filters to rows where "Quote Term Needed?" is truthy.
     * Auto-assigns sequential term numbers per product code if not provided.
     */
    parseQuoteTermsTab(worksheet) {
        const rows = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });
        if (rows.length < 2) return [];

        // Scan for the actual header row (may not be row 0 due to instruction text)
        let headerRowIdx = -1;
        let columnMap = {};
        for (let r = 0; r < Math.min(rows.length, 5); r++) {
            const candidateRow = rows[r].map(c => String(c || '').trim().toLowerCase());
            const candidateMap = this.buildColumnMap(candidateRow, QUOTE_TERM_COLUMN_MAP);
            const mapped = Object.values(candidateMap);
            if (mapped.includes('productCode') && mapped.includes('body')) {
                headerRowIdx = r;
                columnMap = candidateMap;
                break;
            }
        }

        if (headerRowIdx === -1) {
            return []; // Could not find valid header row
        }

        const result = [];
        const termCountByProduct = {}; // Track term number per product code

        for (let i = headerRowIdx + 1; i < rows.length; i++) {
            const row = rows[i];
            if (!row || row.every(cell => cell === '' || cell == null)) continue;

            // Build row object from column map
            const rowObj = {};
            for (const [colIdx, fieldName] of Object.entries(columnMap)) {
                rowObj[fieldName] = row[parseInt(colIdx, 10)];
            }

            // Skip rows where quote term is not needed
            if (rowObj.quoteTermNeeded !== undefined) {
                if (!this.isTruthy(rowObj.quoteTermNeeded)) continue;
            }

            const productCode = this.cleanCode(rowObj.productCode);
            const productName = String(rowObj.productName || '').trim();
            const body = String(rowObj.body || '').trim();

            // Skip rows without product code or body
            if (!productCode || !body) continue;

            // Auto-assign term number if not provided
            let termNumber = rowObj.termNumber != null && rowObj.termNumber !== ''
                ? parseInt(String(rowObj.termNumber), 10)
                : null;

            if (termNumber == null || isNaN(termNumber)) {
                termCountByProduct[productCode] = (termCountByProduct[productCode] || 0) + 1;
                termNumber = termCountByProduct[productCode];
            } else {
                // Track the max for this product so auto-increment stays consistent
                termCountByProduct[productCode] = Math.max(
                    termCountByProduct[productCode] || 0,
                    termNumber
                );
            }

            result.push({
                productCode,
                productName,
                body,
                termNumber,
                quoteDescription: String(rowObj.quoteDescription || '').trim()
            });
        }

        return result;
    }

    // =========================================================================
    // Parsing Helpers
    // =========================================================================

    /**
     * Finds a worksheet by trying multiple possible tab names (case-insensitive).
     */
    findSheet(workbook, possibleNames) {
        for (const name of possibleNames) {
            // Exact match first
            if (workbook.Sheets[name]) return workbook.Sheets[name];
            // Case-insensitive match
            const found = workbook.SheetNames.find(
                sn => sn.toLowerCase() === name.toLowerCase()
            );
            if (found) return workbook.Sheets[found];
        }
        return null;
    }

    /**
     * Builds a map of column index -> field name from header row using a header mapping.
     */
    buildColumnMap(headerRow, headerMapping) {
        const columnMap = {};
        for (let i = 0; i < headerRow.length; i++) {
            const rawHeader = String(headerRow[i] || '').trim();
            if (!rawHeader) continue;
            const normalized = rawHeader.toLowerCase();

            // Try exact match first, then partial match
            if (headerMapping[normalized]) {
                columnMap[i] = headerMapping[normalized];
            } else {
                // Try matching as substring
                for (const [mapKey, fieldName] of Object.entries(headerMapping)) {
                    if (normalized.includes(mapKey) || mapKey.includes(normalized)) {
                        if (!Object.values(columnMap).includes(fieldName)) {
                            columnMap[i] = fieldName;
                            break;
                        }
                    }
                }
            }
        }
        return columnMap;
    }

    isTruthy(value) {
        if (value == null || value === '') return false;
        const str = String(value).trim().toLowerCase();
        return TRUTHY.has(str) || str === 'x';
    }

    /**
     * Derives meter type mappings from pricing data and sets them on SkuDetailRows.
     * For each product, the first meter type found in pricing rows is assigned to
     * all active sub-verticals.
     */
    deriveMeterTypeMappings() {
        const meterTypesByProduct = {};
        for (const pr of this.parsedPricing) {
            if (!meterTypesByProduct[pr.productCode]) {
                meterTypesByProduct[pr.productCode] = [];
            }
            if (pr.meterType && !meterTypesByProduct[pr.productCode].includes(pr.meterType)) {
                meterTypesByProduct[pr.productCode].push(pr.meterType);
            }
        }

        for (const detail of this.parsedSkuDetails) {
            const meterTypes = meterTypesByProduct[detail.productCode] || [];
            const defaultMeter = meterTypes[0] || '';

            // Assign meter type to each active sub-vertical
            const subVerticals = [
                { field: 'isAccounting', meterField: 'meterTypeAccounting' },
                { field: 'isConsulting', meterField: 'meterTypeConsulting' },
                { field: 'isCorporate', meterField: 'meterTypeCorporate' },
                { field: 'isIBA', meterField: 'meterTypeIBA' },
                { field: 'isPCM', meterField: 'meterTypePCM' },
                { field: 'isRealAssets', meterField: 'meterTypeRealAssets' },
                { field: 'isLegal', meterField: 'meterTypeLegal' }
            ];

            for (const sv of subVerticals) {
                if (detail[sv.field] && detail[sv.field] !== 'Unavailable') {
                    detail[sv.meterField] = defaultMeter;
                }
            }

            // Legal USD/AUD specific meter type
            if (detail.isLegal && detail.isLegal !== 'Unavailable') {
                detail.meterTypeLegalUsdAud = defaultMeter;
            }
        }
    }

    // =========================================================================
    // Private Methods — Product Code Propagation
    // =========================================================================

    /**
     * @description After auto-generating product codes for blank SKU detail rows, back-fills
     *              the same codes into Pricing, Bundles, and Quote Terms rows that reference
     *              the same product by name but have a blank productCode.
     * @param {Array} generatedCodes Array of { productName, generatedCode } objects returned
     *                               by generateMissingProductCodes
     */
    _propagateGeneratedCodes(generatedCodes) {
        if (!generatedCodes || generatedCodes.length === 0) return;

        // Build a name → IMP code lookup (case-insensitive) from generated codes.
        // Use impCode (e.g., CO-02136) so all review sections show the prefix-based code.
        const codeByGeneratedName = new Map(
            generatedCodes
                .filter(g => g.productName)
                .map(g => [g.productName.trim().toLowerCase(), g.impCode || g.generatedCode])
        );

        // Build two additional exact-match lookups from parsedSkuDetails (after code generation).
        // itemMasterName is the shared key across all tabs — Pricing/QuoteTerms use it as their
        // productName, so it gives us a reliable exact match without fragile prefix logic.
        // productName is a fallback for questionnaires that omit the Item Master Name column.
        const isResolvedCode = (code) => {
            if (!code) return false;
            const lower = code.trim().toLowerCase();
            return !lower.includes('leave blank') && !lower.includes('system created');
        };

        const codeByItemMasterName = new Map(
            (this.parsedSkuDetails || [])
                .filter(s => isResolvedCode(s.productCode) && s.itemMasterName)
                .map(s => [s.itemMasterName.trim().toLowerCase(), s.productCode])
        );
        const codeBySkuProductName = new Map(
            (this.parsedSkuDetails || [])
                .filter(s => isResolvedCode(s.productCode) && s.productName)
                .map(s => [s.productName.trim().toLowerCase(), s.productCode])
        );

        /**
         * Resolve a product code from a name using three exact-match strategies in order:
         * 1. generatedCodes map (keyed by SkuDetailRow.productName)
         * 2. itemMasterName map — exact match against the shared "Item Master Name" column
         * 3. productName map — fallback for questionnaires without a separate Item Master Name column
         */
        const resolveCode = (productName) => {
            if (!productName) return null;
            const name = productName.trim().toLowerCase();
            return codeByGeneratedName.get(name) ??
                   codeByItemMasterName.get(name) ??
                   codeBySkuProductName.get(name) ??
                   null;
        };

        // Treat blank OR questionnaire placeholder text as a missing code
        const needsCode = (code) => {
            if (!code) return true;
            const lower = code.trim().toLowerCase();
            return lower.includes('leave blank') || lower.includes('system created');
        };

        for (const row of this.parsedPricing) {
            if (needsCode(row.productCode) && row.productName) {
                const code = resolveCode(row.productName);
                if (code) row.productCode = code;
            }
        }
        for (const row of this.parsedBundles) {
            if (needsCode(row.productCode) && row.productName) {
                const code = resolveCode(row.productName);
                if (code) row.productCode = code;
            }
        }
        for (const row of this.parsedQuoteTerms) {
            if (needsCode(row.productCode) && row.productName) {
                const code = resolveCode(row.productName);
                if (code) row.productCode = code;
            }
        }
    }

    // =========================================================================
    // Utility
    // =========================================================================

    extractError(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}