import { LightningElement, api, track } from 'lwc';
import getBusinessUnits from '@salesforce/apex/PricebookViewController.getBusinessUnits';
import getVerticals from '@salesforce/apex/PricebookViewController.getVerticals';
import getFilterPicklistValues from '@salesforce/apex/PricebookViewController.getFilterPicklistValues';
import getPricebookViewData from '@salesforce/apex/PricebookViewController.getPricebookViewData';
import getProductDetails from '@salesforce/apex/PricebookViewController.getProductDetails';

// =========================================================================
// Constants
// =========================================================================

const CURRENCY_SYMBOLS = { USD: '$', GBP: '\u00A3', EUR: '\u20AC', AUD: 'A$' };
const CURRENCIES = ['USD', 'GBP', 'EUR', 'AUD'];
const TIERS = ['EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'];

// Pre-built tier header objects (24 headers: 4 currencies × 6 tiers)
const TIER_HEADERS = [];
for (const curr of CURRENCIES) {
    for (const tier of TIERS) {
        TIER_HEADERS.push({ key: `${curr}_${tier}`, label: tier });
    }
}

// =========================================================================
// Component
// =========================================================================

export default class PricebookView extends LightningElement {
    // Restore context — passed from parent when navigating back from Update Product
    _restoreContext = null;

    @api
    get restoreContext() {
        return this._restoreContext;
    }
    set restoreContext(value) {
        this._restoreContext = value;
        if (value && this._optionsLoaded) {
            this._applyRestoredContext(value);
        }
    }

    // Filter state
    @track filterMode = 'vertical';
    @track selectedFilterValue = '';
    @track selectedProductStatus = 'Active';

    // Product Type and Pricing Basis filters
    @track selectedProductType = 'Software';
    @track selectedPricingBasis = '';
    @track productTypeOptions = [{ label: 'All', value: '' }];
    @track pricingBasisOptions = [{ label: 'All', value: '' }];

    // Data state
    @track isLoading = false;
    @track result = null;
    @track error = null;

    // Dropdown options
    @track businessUnitOptions = [];
    @track verticalOptions = [];

    // Accordion state — object where keys = groupKey, values = boolean
    @track _expandedGroupKeys = {};

    // Radio selection state
    @track selectedRowProductId = null;

    // Product info drawer state
    @track isDrawerOpen = false;
    @track isDrawerLoading = false;
    @track drawerData = null;

    // Tracks whether initial load has been done
    _optionsLoaded = false;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadFilterOptions();
    }

    async loadFilterOptions() {
        try {
            const [bus, verticals, picklists] = await Promise.all([
                getBusinessUnits(),
                getVerticals(),
                getFilterPicklistValues()
            ]);

            this.businessUnitOptions = bus.map(bu => ({ label: bu, value: bu }));
            this.verticalOptions = verticals.map(v => ({ label: v, value: v }));

            // Build Product Type and Pricing Basis dropdown options from system data
            if (picklists.productTypes) {
                this.productTypeOptions = [
                    { label: 'All', value: '' },
                    ...picklists.productTypes.map(v => ({ label: v, value: v }))
                ];
            }
            if (picklists.pricingBases) {
                const basisOrder = ['Tier based', '% of ACV', 'Quantity based', 'Free'];
                const ordered = basisOrder.filter(b => picklists.pricingBases.includes(b));
                const remaining = picklists.pricingBases.filter(b => !basisOrder.includes(b));
                this.pricingBasisOptions = [
                    { label: 'All', value: '' },
                    ...ordered.map(v => ({ label: v, value: v })),
                    ...remaining.map(v => ({ label: v, value: v }))
                ];
            }

            this._optionsLoaded = true;

            // Apply restored context if pending, otherwise set default
            if (this._restoreContext) {
                this._applyRestoredContext(this._restoreContext);
            } else {
                // Default to first option in the active filter mode
                // (vertical mode → 'Legal' is first; BU mode → first BU)
                const options = this.filterOptions;
                this.selectedFilterValue = options.length > 0 ? options[0].value : '';
            }
        } catch (err) {
            this.error = this._extractErrorMessage(err);
        }
    }

    // =========================================================================
    // Getters — Filter Mode
    // =========================================================================

    get isBusinessUnitMode() {
        return this.filterMode === 'businessUnit';
    }

    get isVerticalMode() {
        return this.filterMode === 'vertical';
    }

    get filterLabel() {
        return this.isBusinessUnitMode ? 'Business Unit' : 'Vertical';
    }

    get filterOptions() {
        return this.isBusinessUnitMode ? this.businessUnitOptions : this.verticalOptions;
    }

    get productStatusOptions() {
        return [
            { label: 'Active', value: 'Active' },
            { label: 'Restricted', value: 'Restricted' },
            { label: 'All', value: 'All' }
        ];
    }

    get buTabClass() {
        return 'filter-tab' + (this.isBusinessUnitMode ? ' filter-tab--active' : '');
    }

    get verticalTabClass() {
        return 'filter-tab' + (this.isVerticalMode ? ' filter-tab--active' : '');
    }

    // =========================================================================
    // Getters — Results
    // =========================================================================

    get hasResults() {
        return this.result && this.result.groups && this.result.groups.length > 0;
    }

    get showNoResults() {
        return !this.isLoading && this.result && this.result.totalProducts === 0;
    }

    get totalProductCount() {
        return this.result ? this.result.totalProducts : 0;
    }

    get tierHeaders() {
        return TIER_HEADERS;
    }

    get hasSelectedProduct() {
        return !!this.selectedRowProductId;
    }

    get isEditDisabled() {
        return !this.selectedRowProductId;
    }

    /**
     * Transforms the raw Apex result into display-ready group objects
     * with formatted prices, CSS classes, and expand/collapse state.
     */
    get displayGroups() {
        if (!this.result || !this.result.groups) return [];

        return this.result.groups.map(group => ({
            ...group,
            isExpanded: !!this._expandedGroupKeys[group.groupKey],
            chevronClass: 'group-header__chevron'
                + (this._expandedGroupKeys[group.groupKey] ? '' : ' group-header__chevron--collapsed'),
            subGroups: group.subGroups.map(sg => ({
                ...sg,
                statusClass: 'sub-group-header sub-group-header--' + sg.status.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, ''),
                rows: sg.rows.map(row => ({
                    ...row,
                    isSelected: row.productId === this.selectedRowProductId,
                    rowClass: 'data-row'
                        + (row.productId === this.selectedRowProductId ? ' data-row--selected' : '')
                        + (row.verticalStatus === 'Restricted' ? ' data-row--restricted' : ' data-row--active'),
                    formattedPrices: row.prices.map(cell => ({
                        ...cell,
                        formatted: this._formatPrice(cell.price, cell.currencyCode),
                        cellClass: 'price-cell'
                            + (cell.price == null || cell.price === 0 ? ' price-cell--zero' : '')
                    }))
                }))
            }))
        }));
    }

    // =========================================================================
    // Handlers — Filter Controls
    // =========================================================================

    handleFilterModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode === this.filterMode) return;

        this.filterMode = mode;
        this.result = null;
        this.error = null;
        this.selectedRowProductId = null;
        this.selectedProductStatus = 'Active';
        this.selectedProductType = 'Software';
        this.selectedPricingBasis = '';

        // Reset selected value to first option in the new mode
        const options = this.filterOptions;
        this.selectedFilterValue = options.length > 0 ? options[0].value : '';
    }

    handleFilterValueChange(event) {
        this.selectedFilterValue = event.detail.value;
    }

    handleProductStatusChange(event) {
        this.selectedProductStatus = event.detail.value;
    }

    handleProductTypeChange(event) {
        this.selectedProductType = event.detail.value;
        this.selectedRowProductId = null;
    }

    handlePricingBasisChange(event) {
        this.selectedPricingBasis = event.detail.value;
        this.selectedRowProductId = null;
    }

    async handleApplyFilters() {
        if (!this.selectedFilterValue) return;

        this.isLoading = true;
        this.error = null;
        this._expandedGroupKeys = {};
        this.selectedRowProductId = null;

        try {
            const data = await getPricebookViewData({
                filterMode: this.filterMode,
                filterValue: this.selectedFilterValue,
                productStatus: this.selectedProductStatus,
                productType: this.selectedProductType,
                pricingBasis: this.selectedPricingBasis
            });

            this.result = data;

            // Expand all accordion groups by default
            if (data && data.groups) {
                const expanded = {};
                data.groups.forEach(g => { expanded[g.groupKey] = true; });
                this._expandedGroupKeys = expanded;
            }
        } catch (err) {
            this.error = this._extractErrorMessage(err);
            this.result = null;
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // Handlers — Accordion
    // =========================================================================

    handleGroupToggle(event) {
        const groupKey = event.currentTarget.dataset.groupKey;
        this._expandedGroupKeys = {
            ...this._expandedGroupKeys,
            [groupKey]: !this._expandedGroupKeys[groupKey]
        };
    }

    // =========================================================================
    // Handlers — Row Selection & Edit
    // =========================================================================

    handleRadioSelect(event) {
        this.selectedRowProductId = event.currentTarget.dataset.productId;
        this.openDrawer(this.selectedRowProductId);
    }

    // =========================================================================
    // Product Info Drawer
    // =========================================================================

    async openDrawer(productId) {
        this.isDrawerOpen = true;
        this.isDrawerLoading = true;
        this.drawerData = null;
        try {
            this.drawerData = await getProductDetails({ productId });
        } catch (err) {
            this.drawerData = null;
        } finally {
            this.isDrawerLoading = false;
        }
    }

    handleCloseDrawer() {
        this.isDrawerOpen = false;
        this.drawerData = null;
    }

    get drawerProductCode() {
        return this.drawerData ? this.drawerData.productCode : '';
    }

    get drawerProductName() {
        return this.drawerData ? this.drawerData.productName : '';
    }

    get drawerVerticals() {
        return this.drawerData ? this.drawerData.verticals : [];
    }

    get drawerItemMasterFields() {
        if (!this.drawerData || !this.drawerData.itemMasterFields) return [];
        return this.drawerData.itemMasterFields.filter(f => f.value !== '—');
    }

    get hasItemMaster() {
        return this.drawerItemMasterFields.length > 0;
    }

    handleEditProduct() {
        if (!this.selectedRowProductId) return;

        this.dispatchEvent(new CustomEvent('navigatetotab', {
            detail: {
                tabName: 'unifiedUpdate',
                productId: this.selectedRowProductId,
                pricebookContext: {
                    filterMode: this.filterMode,
                    selectedFilterValue: this.selectedFilterValue,
                    selectedProductStatus: this.selectedProductStatus,
                    selectedProductType: this.selectedProductType,
                    selectedPricingBasis: this.selectedPricingBasis
                }
            },
            bubbles: true,
            composed: true
        }));
    }

    // =========================================================================
    // Handlers — Export
    // =========================================================================

    handleExportCsv() {
        const priceHeaders = [];
        for (const curr of CURRENCIES) {
            for (const tier of TIERS) {
                priceHeaders.push(`${curr} ${tier}`);
            }
        }

        const headers = [
            'Group', 'Status',
            'Product Code', 'Product Name', 'Product Line',
            'Product Type', 'Pricing Basis', 'Default Meter Type',
            ...priceHeaders
        ];

        const rows = [headers];

        for (const group of this.displayGroups) {
            for (const sg of group.subGroups) {
                for (const row of sg.rows) {
                    rows.push([
                        group.groupName,
                        sg.status || '',
                        row.productCode,
                        row.productName,
                        row.productLine,
                        row.productType,
                        row.pricingBasis,
                        row.meterType,
                        ...row.formattedPrices.map(c => c.formatted)
                    ]);
                }
            }
        }

        const csvContent = rows
            .map(r => r.map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(','))
            .join('\r\n');

        const url = 'data:text/plain;charset=utf-8,' + encodeURIComponent('\uFEFF' + csvContent);
        const a = document.createElement('a');
        a.href = url;
        a.download = `pricebook-export-${new Date().toISOString().slice(0, 10)}.csv`;
        a.click();
    }

    // =========================================================================
    // Private Helpers
    // =========================================================================

    /**
     * Formats a price value with currency symbol and comma separators.
     * Returns '—' for null/undefined prices, symbol + '0' for zero.
     */
    _formatPrice(price, currencyCode) {
        if (price == null) return '\u2014'; // em-dash

        const symbol = CURRENCY_SYMBOLS[currencyCode] || '';
        if (price === 0) return symbol + '0';

        // Format with commas, strip unnecessary decimals
        const isWhole = price % 1 === 0;
        const parts = price.toFixed(isWhole ? 0 : 2).split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return symbol + parts.join('.');
    }

    /**
     * Extracts a user-friendly error message from an Apex error response.
     */
    _extractErrorMessage(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred.';
    }

    /**
     * Applies restored filter context from a previous Pricebook View session.
     * Restores filter mode, filter value, product status, then auto-fetches data.
     */
    _applyRestoredContext(ctx) {
        if (!ctx) return;
        this.filterMode = ctx.filterMode || 'businessUnit';
        this.selectedFilterValue = ctx.selectedFilterValue || '';
        this.selectedProductStatus = ctx.selectedProductStatus || 'Active';
        this.selectedProductType = ctx.selectedProductType || '';
        this.selectedPricingBasis = ctx.selectedPricingBasis || '';
        this._restoreContext = null; // Clear to prevent re-application
        this.handleApplyFilters();
    }
}