/**
 * @description Filterable, sortable account list for the portfolio dashboard.
 *              Shows all CSM accounts with health indicators, risk levels, and key metrics.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { formatCurrency, formatDate, getHealthColor } from 'c/customer360Utils';
import { SEGMENTS, RISK_LEVELS, HEALTH_THRESHOLDS } from 'c/customer360Constants';

/** @type {Array<{label: String, value: String}>} Sort combobox options */
const SORT_OPTIONS = [
    { label: 'Health Score', value: 'healthScore' },
    { label: 'ARR', value: 'arr' },
    { label: 'Renewal Date', value: 'renewalDate' },
    { label: 'Last Contact', value: 'daysSinceContact' },
    { label: 'Name', value: 'name' }
];

/** @type {Array<String>} Risk filter button labels */
const RISK_FILTER_VALUES = ['All', 'Healthy', 'At Risk', 'Critical'];

/** @type {number} Days-since-contact threshold for warning styling */
const CONTACT_WARNING_DAYS = 30;

export default class Customer360PortfolioList extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array<Object>} Account objects with id, name, healthScore, healthTrend, riskLevel, arr, renewalDate, daysSinceContact, segment, products, openCtas */
    @api accounts = [];

    /** @type {Object|null} External filter from dashboard chart/KPI interactions. Shape: { type: string, label: string } */
    @api externalFilter;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /** @type {String} Current search input value */
    @track searchTerm = '';

    /** @type {String} Active segment filter value */
    @track activeSegment = 'All';

    /** @type {String} Active risk filter value */
    @track activeRisk = 'All';

    /** @type {String} Field to sort by */
    @track sortField = 'healthScore';

    /** @type {String} Sort direction: 'asc' or 'desc' */
    @track sortDirection = 'asc';

    /**********************************************************************************************
     *
     * Getters — Filter Buttons
     *
     ***********************************************************************************************/

    /**
     * @description Builds segment filter button descriptors with active state styling.
     * @returns {Array<{label: String, value: String, className: String}>}
     */
    get segmentButtons() {
        const values = ['All', ...SEGMENTS];
        return values.map((seg) => ({
            label: seg,
            value: seg,
            className: seg === this.activeSegment
                ? 'filter-btn filter-btn--active'
                : 'filter-btn'
        }));
    }

    /**
     * @description Builds risk filter button descriptors with active state styling.
     * @returns {Array<{label: String, value: String, className: String}>}
     */
    get riskButtons() {
        return RISK_FILTER_VALUES.map((risk) => ({
            label: risk,
            value: risk,
            className: risk === this.activeRisk
                ? 'filter-btn filter-btn--active'
                : 'filter-btn'
        }));
    }

    /**
     * @description Returns sort combobox options.
     * @returns {Array<{label: String, value: String}>}
     */
    get sortOptions() {
        return SORT_OPTIONS;
    }

    /**********************************************************************************************
     *
     * Getters — Filtered & Sorted Accounts
     *
     ***********************************************************************************************/

    /**
     * @description Filters accounts by search term, segment, and risk level, then sorts and
     *              enriches each record with display-formatted values and variant mappings.
     * @returns {Array<Object>} Enriched account objects ready for template rendering.
     */
    get filteredAccounts() {
        let result = this.accounts ? [...this.accounts] : [];

        // Filter by search term (case-insensitive name match)
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            result = result.filter((acct) => acct.name && acct.name.toLowerCase().includes(term));
        }

        // Filter by segment
        if (this.activeSegment !== 'All') {
            result = result.filter((acct) => acct.segment === this.activeSegment);
        }

        // Filter by risk level
        if (this.activeRisk !== 'All') {
            result = result.filter((acct) => {
                const riskLabel = this._getRiskLabel(acct.riskLevel);
                return riskLabel === this.activeRisk;
            });
        }

        // Apply external filter from chart/KPI interactions
        if (this.externalFilter) {
            result = this._applyExternalFilter(result);
        }

        // Sort
        result = this._sortAccounts(result);

        // Enrich with display values
        return result.map((acct) => this._enrichAccount(acct));
    }

    /**
     * @description Returns the count of currently visible (filtered) accounts.
     * @returns {Number}
     */
    get filteredCount() {
        return this.filteredAccounts.length;
    }

    /**
     * @description Indicates whether the filtered list is empty (for empty-state display).
     * @returns {Boolean}
     */
    get noResults() {
        return this.filteredCount === 0;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles search input changes.
     * @param {Event} event - lightning-input change event
     */
    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    /**
     * @description Handles segment filter button clicks.
     * @param {Event} event - button click event with data-segment attribute
     */
    handleSegmentFilter(event) {
        this.activeSegment = event.currentTarget.dataset.segment;
    }

    /**
     * @description Handles risk filter button clicks.
     * @param {Event} event - button click event with data-risk attribute
     */
    handleRiskFilter(event) {
        this.activeRisk = event.currentTarget.dataset.risk;
    }

    /**
     * @description Handles sort combobox changes and toggles direction when the same field
     *              is selected again.
     * @param {Event} event - lightning-combobox change event
     */
    handleSort(event) {
        const newField = event.detail.value;
        if (newField === this.sortField) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = newField;
            this.sortDirection = 'asc';
        }
    }

    /**
     * @description Handles account row clicks and dispatches the accountselect custom event.
     * @param {Event} event - row click event with data-account-id attribute
     */
    handleAccountClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.dispatchEvent(
            new CustomEvent('accountselect', {
                detail: { accountId },
                bubbles: true,
                composed: false
            })
        );
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Sorts the account array by the active sort field and direction.
     * @param {Array<Object>} data - Accounts to sort
     * @returns {Array<Object>} Sorted copy of the array
     */
    _sortAccounts(data) {
        if (!data || !data.length) {
            return [];
        }
        const multiplier = this.sortDirection === 'asc' ? 1 : -1;
        const field = this.sortField;

        return [...data].sort((a, b) => {
            const valA = a[field] != null ? a[field] : '';
            const valB = b[field] != null ? b[field] : '';
            if (typeof valA === 'string') {
                return multiplier * valA.localeCompare(valB);
            }
            return multiplier * (valA - valB);
        });
    }

    /**
     * @description Enriches an account object with formatted display values, variant mappings,
     *              and conditional styling classes for the template.
     * @param {Object} acct - Raw account object
     * @returns {Object} Account with additional display properties
     */
    _enrichAccount(acct) {
        const riskLabel = this._getRiskLabel(acct.riskLevel);
        const riskVariant = this._getRiskVariant(acct.riskLevel);
        const segmentVariant = this._getSegmentVariant(acct.segment);
        const healthColor = getHealthColor(acct.healthScore);
        const isContactWarning = acct.daysSinceContact > CONTACT_WARNING_DAYS;

        return {
            ...acct,
            formattedArr: formatCurrency(acct.arr, true),
            formattedRenewal: formatDate(acct.renewalDate),
            segmentVariant,
            healthStyle: `color: ${healthColor};`,
            riskLabel,
            riskVariant,
            contactClass: isContactWarning
                ? 'metric-value metric-value--warning'
                : 'metric-value'
        };
    }

    /**
     * @description Maps a risk level key to its human-readable label from RISK_LEVELS.
     * @param {String} riskLevel - Risk level key (e.g., 'low', 'medium', 'high', 'critical')
     * @returns {String} Display label (e.g., 'Healthy', 'At Risk', 'Critical')
     */
    _getRiskLabel(riskLevel) {
        const key = (riskLevel || '').toUpperCase();
        if (key === 'LOW') return 'Healthy';
        if (key === 'MEDIUM') return 'At Risk';
        if (RISK_LEVELS[key]) return RISK_LEVELS[key].label;
        return 'Unknown';
    }

    /**
     * @description Maps a risk level key to a badge variant string.
     * @param {String} riskLevel - Risk level key
     * @returns {String} Badge variant ('success', 'warning', 'error')
     */
    _getRiskVariant(riskLevel) {
        const key = (riskLevel || '').toUpperCase();
        if (key === 'LOW') return 'success';
        if (key === 'MEDIUM') return 'warning';
        if (RISK_LEVELS[key]) return RISK_LEVELS[key].variant;
        return 'default';
    }

    get hideLabel() {
        return false;
    }

    /**
     * @description Maps a segment name to a badge variant string.
     * @param {String} segment - Segment name ('Enterprise', 'Mid-Market', 'SMB')
     * @returns {String} Badge variant
     */
    _getSegmentVariant(segment) {
        const mapping = {
            Enterprise: 'info',
            'Mid-Market': 'purple',
            SMB: 'success'
        };
        return mapping[segment] || 'default';
    }

    /**
     * @description Applies an external filter (from chart/KPI clicks) to the account list.
     *              Supports filtering by health category, segment, or open CTAs.
     * @param {Array<Object>} data - Pre-filtered accounts
     * @returns {Array<Object>} Further-filtered accounts
     */
    _applyExternalFilter(data) {
        const filter = this.externalFilter;
        if (!filter || !filter.type) return data;

        switch (filter.type) {
            case 'health':
                return data.filter((acct) => {
                    const score = acct.healthScore || 0;
                    switch (filter.label) {
                        case 'Healthy':
                            return score >= HEALTH_THRESHOLDS.GOOD;
                        case 'Fair':
                            return score >= HEALTH_THRESHOLDS.FAIR && score < HEALTH_THRESHOLDS.GOOD;
                        case 'At Risk':
                            return score >= HEALTH_THRESHOLDS.POOR && score < HEALTH_THRESHOLDS.FAIR;
                        case 'Critical':
                            return score < HEALTH_THRESHOLDS.POOR;
                        default:
                            return true;
                    }
                });
            case 'segment':
                return data.filter((acct) => (acct.segment || 'Other') === filter.label);
            case 'hasCtas':
                return data.filter((acct) => (acct.openCtas || 0) > 0);
            default:
                return data;
        }
    }
}