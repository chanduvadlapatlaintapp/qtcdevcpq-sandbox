/**
 * @description Portfolio dashboard layout component that composes KPI cards, portfolio list,
 *              alerts panel, and charts. Provides an at-a-glance view of the account portfolio
 *              with health distribution and ARR breakdown visualizations.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { formatCurrency, formatPercent, getHealthColor } from 'c/customer360Utils';
import { HEALTH_THRESHOLDS, SEGMENT_COLORS } from 'c/customer360Constants';

export default class Customer360Dashboard extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array} Array of account objects from mock data */
    @api accounts = [];

    /** @type {Array} Array of alert objects from mock data */
    @api alerts = [];

    /**********************************************************************************************
     *
     * Private Properties — Chart Interaction State
     *
     ***********************************************************************************************/

    /** @type {Object|null} External filter applied from chart/KPI clicks, passed to portfolio list */
    @track _externalFilter = null;

    /** @type {boolean} Whether the chart popover is visible */
    @track _popoverVisible = false;

    /** @type {string} Title for the chart popover */
    @track _popoverTitle = '';

    /** @type {Array} Items to display in the chart popover */
    @track _popoverItems = [];

    /**********************************************************************************************
     *
     * Getters — KPI Values
     *
     ***********************************************************************************************/

    /**
     * @description Total number of client accounts.
     * @returns {string}
     */
    get totalClients() {
        return String(this._safeAccounts.length);
    }

    /**
     * @description Count of accounts with a health score below the FAIR threshold (at risk).
     * @returns {string}
     */
    get atRiskCount() {
        const count = this._safeAccounts.filter(
            (a) => a.healthScore < HEALTH_THRESHOLDS.FAIR
        ).length;
        return String(count);
    }

    /**
     * @description Percentage of accounts considered healthy (score >= GOOD threshold).
     * @returns {string}
     */
    get healthyPercent() {
        const accts = this._safeAccounts;
        if (!accts.length) return formatPercent(0);
        const healthyCount = accts.filter(
            (a) => a.healthScore >= HEALTH_THRESHOLDS.GOOD
        ).length;
        const pct = (healthyCount / accts.length) * 100;
        return formatPercent(pct);
    }

    /**
     * @description Total ARR across all accounts, formatted in compact currency notation.
     * @returns {string}
     */
    get totalArr() {
        const sum = this._safeAccounts.reduce((total, a) => total + (a.arr || 0), 0);
        return formatCurrency(sum, true);
    }

    /**
     * @description Average health score across all accounts, rounded to nearest integer.
     * @returns {string}
     */
    get avgHealth() {
        const accts = this._safeAccounts;
        if (!accts.length) return '0';
        const sum = accts.reduce((total, a) => total + (a.healthScore || 0), 0);
        return String(Math.round(sum / accts.length));
    }

    /**
     * @description Total number of open CTAs across all accounts.
     * @returns {string}
     */
    get openCtaCount() {
        const sum = this._safeAccounts.reduce((total, a) => total + (a.openCtas || 0), 0);
        return String(sum);
    }

    /**********************************************************************************************
     *
     * Getters — Trend Indicators
     *
     ***********************************************************************************************/

    /**
     * @description Trend direction for the client count KPI.
     * @returns {string}
     */
    get clientTrend() {
        return 'stable';
    }

    /**
     * @description Trend value label for the client count KPI.
     * @returns {string}
     */
    get clientTrendValue() {
        return '';
    }

    /**
     * @description Trend value label for the ARR KPI (static mock).
     * @returns {string}
     */
    get arrTrendValue() {
        return '+8% YoY';
    }

    /**
     * @description Trend direction for the average health score KPI.
     *              Determines direction based on the average health relative to the midpoint.
     * @returns {string}
     */
    get healthTrend() {
        const accts = this._safeAccounts;
        if (!accts.length) return 'stable';
        const avg = accts.reduce((total, a) => total + (a.healthScore || 0), 0) / accts.length;
        if (avg >= HEALTH_THRESHOLDS.GOOD) return 'up';
        if (avg < HEALTH_THRESHOLDS.FAIR) return 'down';
        return 'stable';
    }

    /**********************************************************************************************
     *
     * Getters — Chart Data
     *
     ***********************************************************************************************/

    /**
     * @description Groups accounts into health buckets for the donut chart.
     *              Categories: Healthy (>=75), Fair (60-74), At Risk (40-59), Critical (<40).
     * @returns {Array<{label: string, value: number, color: string}>}
     */
    get healthDistribution() {
        const accts = this._safeAccounts;
        const buckets = {
            healthy: { label: 'Healthy', value: 0, color: getHealthColor(HEALTH_THRESHOLDS.GOOD) },
            fair: { label: 'Fair', value: 0, color: getHealthColor(HEALTH_THRESHOLDS.FAIR) },
            atRisk: { label: 'At Risk', value: 0, color: getHealthColor(HEALTH_THRESHOLDS.POOR) },
            critical: { label: 'Critical', value: 0, color: getHealthColor(0) }
        };

        accts.forEach((a) => {
            const score = a.healthScore || 0;
            if (score >= HEALTH_THRESHOLDS.GOOD) {
                buckets.healthy.value++;
            } else if (score >= HEALTH_THRESHOLDS.FAIR) {
                buckets.fair.value++;
            } else if (score >= HEALTH_THRESHOLDS.POOR) {
                buckets.atRisk.value++;
            } else {
                buckets.critical.value++;
            }
        });

        return Object.values(buckets).filter((b) => b.value > 0);
    }

    /**
     * @description Groups accounts by segment and sums ARR per segment for the bar chart.
     *              Values are expressed in thousands (K) for readability.
     * @returns {Array<{label: string, value: number, color: string}>}
     */
    get segmentArrData() {
        const accts = this._safeAccounts;
        const segmentMap = {};

        accts.forEach((a) => {
            const segment = a.segment || 'Other';
            if (!segmentMap[segment]) {
                segmentMap[segment] = 0;
            }
            segmentMap[segment] += a.arr || 0;
        });

        return Object.keys(segmentMap).map((segment) => ({
            label: segment,
            value: Math.round(segmentMap[segment] / 1000),
            color: SEGMENT_COLORS[segment] || '#706E6B'
        }));
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Re-dispatches the accountselect event from the portfolio list child.
     * @param {CustomEvent} event - The accountselect event from c-customer360-portfolio-list.
     */
    handleAccountSelect(event) {
        this.dispatchEvent(new CustomEvent('accountselect', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * @description Re-dispatches the alertdismiss event from the alerts panel child.
     * @param {CustomEvent} event - The alertdismiss event from c-customer360-alerts-panel.
     */
    handleAlertDismiss(event) {
        this.dispatchEvent(new CustomEvent('alertdismiss', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * @description Re-dispatches the alertclick event from the alerts panel child.
     * @param {CustomEvent} event - The alertclick event from c-customer360-alerts-panel.
     */
    handleAlertClick(event) {
        this.dispatchEvent(new CustomEvent('alertclick', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * @description Handles donut chart segment clicks. Filters portfolio to the clicked
     *              health category and shows a popover with account breakdown.
     * @param {CustomEvent} event - segmentclick event with { label, value, index }
     */
    handleHealthSegmentClick(event) {
        const { label, value } = event.detail;

        // Build external filter based on health category label
        this._externalFilter = { type: 'health', label };

        // Build popover items showing accounts in this category
        const accts = this._getAccountsForHealthCategory(label);
        this._popoverTitle = `${label} — ${value} account${value !== 1 ? 's' : ''}`;
        this._popoverItems = accts.slice(0, 8).map((a) => ({
            label: a.name,
            value: String(a.healthScore),
            color: getHealthColor(a.healthScore)
        }));
        this._popoverVisible = true;
    }

    /**
     * @description Handles bar chart clicks. Filters portfolio to the clicked segment
     *              and shows a popover with ARR breakdown.
     * @param {CustomEvent} event - barclick event with { label, value, index }
     */
    handleSegmentBarClick(event) {
        const { label, value } = event.detail;

        // Build external filter based on segment name
        this._externalFilter = { type: 'segment', label };

        // Build popover items showing accounts in this segment
        const accts = this._safeAccounts.filter((a) => (a.segment || 'Other') === label);
        this._popoverTitle = `${label} — $${value}K ARR`;
        this._popoverItems = accts.slice(0, 8).map((a) => ({
            label: a.name,
            value: formatCurrency(a.arr, true),
            color: SEGMENT_COLORS[a.segment] || '#706E6B'
        }));
        this._popoverVisible = true;
    }

    /**
     * @description Handles KPI card clicks. Applies a contextual filter based on which KPI was clicked.
     * @param {CustomEvent} event - kpiclick event with { key, label, value }
     */
    handleKpiClick(event) {
        const { key } = event.detail;

        switch (key) {
            case 'atRisk':
                this._externalFilter = { type: 'health', label: 'At Risk' };
                break;
            case 'healthy':
                this._externalFilter = { type: 'health', label: 'Healthy' };
                break;
            case 'openCtas':
                this._externalFilter = { type: 'hasCtas', label: 'Has Open CTAs' };
                break;
            default:
                // For Total Clients, Total ARR, Avg Health — clear filter
                this._externalFilter = null;
                break;
        }
        this._popoverVisible = false;
    }

    /**
     * @description Handles closing of the chart popover.
     */
    handlePopoverClose() {
        this._popoverVisible = false;
    }

    /**
     * @description Handles clearing the external filter applied from chart interactions.
     */
    handleClearFilter() {
        this._externalFilter = null;
        this._popoverVisible = false;
    }

    /**********************************************************************************************
     *
     * Getters — Chart Interaction
     *
     ***********************************************************************************************/

    /**
     * @description Returns the external filter object for the portfolio list.
     * @returns {Object|null}
     */
    get externalFilter() {
        return this._externalFilter;
    }

    /**
     * @description Whether an external filter is currently active.
     * @returns {boolean}
     */
    get hasExternalFilter() {
        return this._externalFilter != null;
    }

    /**
     * @description Returns a human-readable description of the active filter.
     * @returns {string}
     */
    get filterDescription() {
        if (!this._externalFilter) return '';
        return `Filtered: ${this._externalFilter.label}`;
    }

    /**
     * @description Whether the popover is visible.
     * @returns {boolean}
     */
    get popoverVisible() {
        return this._popoverVisible;
    }

    /**
     * @description Returns the popover title.
     * @returns {string}
     */
    get popoverTitle() {
        return this._popoverTitle;
    }

    /**
     * @description Returns the popover items.
     * @returns {Array}
     */
    get popoverItems() {
        return this._popoverItems;
    }

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /**
     * @description Returns a safe array reference for accounts, defaulting to empty array.
     * @returns {Array}
     */
    get _safeAccounts() {
        return this.accounts || [];
    }

    get donutChartSize() {
        return 180;
    }

    get barChartHeight() {
        return 140;
    }

    /**
     * @description Returns accounts matching a health category label.
     * @param {string} categoryLabel - 'Healthy', 'Fair', 'At Risk', or 'Critical'
     * @returns {Array<Object>}
     */
    _getAccountsForHealthCategory(categoryLabel) {
        const accts = this._safeAccounts;
        return accts.filter((a) => {
            const score = a.healthScore || 0;
            switch (categoryLabel) {
                case 'Healthy':
                    return score >= HEALTH_THRESHOLDS.GOOD;
                case 'Fair':
                    return score >= HEALTH_THRESHOLDS.FAIR && score < HEALTH_THRESHOLDS.GOOD;
                case 'At Risk':
                    return score >= HEALTH_THRESHOLDS.POOR && score < HEALTH_THRESHOLDS.FAIR;
                case 'Critical':
                    return score < HEALTH_THRESHOLDS.POOR;
                default:
                    return false;
            }
        });
    }
}