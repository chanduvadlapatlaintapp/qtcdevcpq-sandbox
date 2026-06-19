/**
 * @description Reusable KPI metric card component for the Customer 360 application.
 *              Displays a formatted value with label, icon, and optional trend indicator
 *              (up, down, or stable) with color-coded variants.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360KpiCard extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {string} Metric label (e.g., "Total Clients") */
    @api label;

    /** @type {string} Formatted value to display (e.g., "$1.2M") */
    @api value;

    /** @type {string} SLDS icon name (e.g., "utility:people") */
    @api icon;

    /** @type {string} Trend direction: 'up', 'down', or 'stable' */
    @api trend;

    /** @type {string} Trend text (e.g., "+5%") */
    @api trendValue;

    /** @type {string} Color variant: 'default', 'success', 'warning', 'error' */
    @api variant = 'default';

    /** @type {string} Unique key identifying this KPI (used in kpiclick event detail) */
    @api kpiKey;

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Whether the trend is pointing upward.
     * @returns {boolean}
     */
    get isUp() {
        return this.trend === 'up';
    }

    /**
     * @description Whether the trend is pointing downward.
     * @returns {boolean}
     */
    get isDown() {
        return this.trend === 'down';
    }

    /**
     * @description Computes the CSS class for the trend indicator based on direction.
     * @returns {string}
     */
    get trendClass() {
        const base = 'kpi-trend';
        if (this.trend === 'up') {
            return `${base} kpi-trend--up`;
        }
        if (this.trend === 'down') {
            return `${base} kpi-trend--down`;
        }
        return `${base} kpi-trend--stable`;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles clicks on the KPI card. Dispatches kpiclick event.
     */
    handleCardClick() {
        this.dispatchEvent(new CustomEvent('kpiclick', {
            detail: {
                key: this.kpiKey,
                label: this.label,
                value: this.value
            }
        }));
    }
}