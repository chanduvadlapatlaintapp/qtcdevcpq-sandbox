/**
 * @description Overview tab for the Customer 360 detail view.
 *              Combines health summary, KPI cards, recent timeline activity,
 *              CTA summary, renewal countdown, and product badges.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { generateHealthScore, generateTimeline, generateCtas } from 'c/customer360MockData';
import { formatCurrency, formatDate, getHealthColor } from 'c/customer360Utils';
import { CTA_TYPES } from 'c/customer360Constants';

export default class Customer360Overview extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {string} Salesforce Account ID */
    @api accountId;

    /** @type {Object} Account data object with arr, nps, daysSinceContact, renewalDate, products, etc. */
    @api account;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /** @type {Object} Generated health score data */
    healthData;

    /** @type {Array<Object>} Recent timeline events (top 5) */
    timelineData = [];

    /** @type {Array<Object>} Generated CTA records */
    ctaData = [];

    /**********************************************************************************************
     *
     * Lifecycle Hooks
     *
     ***********************************************************************************************/

    /**
     * @description Generates mock data when the component is inserted into the DOM.
     */
    connectedCallback() {
        this._loadData();
    }

    /**********************************************************************************************
     *
     * Getters — Health KPI
     *
     ***********************************************************************************************/

    /**
     * @description Health score displayed as a string.
     * @returns {string}
     */
    get healthScoreStr() {
        return this.healthData ? String(this.healthData.overall) : '—';
    }

    /**
     * @description Health score trend direction ('up', 'down', 'stable').
     * @returns {string}
     */
    get healthTrend() {
        return this.healthData ? this.healthData.trend : 'stable';
    }

    /**
     * @description KPI card variant based on health score value.
     * @returns {string}
     */
    get healthVariant() {
        if (!this.healthData) return 'default';
        const score = this.healthData.overall;
        if (score >= 75) return 'success';
        if (score >= 60) return 'warning';
        return 'error';
    }

    /**********************************************************************************************
     *
     * Getters — ARR KPI
     *
     ***********************************************************************************************/

    /**
     * @description Formatted ARR value in compact notation (e.g. $1.2M).
     * @returns {string}
     */
    get formattedArr() {
        if (!this.account || this.account.arr == null) return '$0';
        return formatCurrency(this.account.arr, true);
    }

    /**********************************************************************************************
     *
     * Getters — NPS KPI
     *
     ***********************************************************************************************/

    /**
     * @description NPS value as a string.
     * @returns {string}
     */
    get npsStr() {
        if (!this.account || this.account.nps == null) return '—';
        return String(this.account.nps);
    }

    /**
     * @description KPI card variant for NPS (success >= 8, warning >= 6, error otherwise).
     * @returns {string}
     */
    get npsVariant() {
        if (!this.account || this.account.nps == null) return 'default';
        if (this.account.nps >= 8) return 'success';
        if (this.account.nps >= 6) return 'warning';
        return 'error';
    }

    /**********************************************************************************************
     *
     * Getters — Days Since Contact KPI
     *
     ***********************************************************************************************/

    /**
     * @description Days since last contact as a string.
     * @returns {string}
     */
    get contactDaysStr() {
        if (!this.account || this.account.daysSinceContact == null) return '—';
        return String(this.account.daysSinceContact);
    }

    /**
     * @description KPI card variant for contact recency (success <= 14, warning <= 30, error otherwise).
     * @returns {string}
     */
    get contactVariant() {
        if (!this.account || this.account.daysSinceContact == null) return 'default';
        if (this.account.daysSinceContact <= 14) return 'success';
        if (this.account.daysSinceContact <= 30) return 'warning';
        return 'error';
    }

    /**********************************************************************************************
     *
     * Getters — Health Factors
     *
     ***********************************************************************************************/

    /**
     * @description Top 3 health factors sorted by weighted score, enriched with bar and score styles.
     * @returns {Array<Object>}
     */
    get topFactors() {
        if (!this.healthData || !this.healthData.factors) return [];
        const sorted = [...this.healthData.factors].sort((a, b) => b.weightedScore - a.weightedScore);
        return sorted.slice(0, 3).map(factor => {
            const color = getHealthColor(factor.score);
            return {
                ...factor,
                barStyle: `width: ${factor.score}%; background: ${color}`,
                scoreStyle: `color: ${color}`
            };
        });
    }

    /**********************************************************************************************
     *
     * Getters — Timeline
     *
     ***********************************************************************************************/

    /**
     * @description Recent 5 timeline events with relative time and icon background style.
     * @returns {Array<Object>}
     */
    get recentTimeline() {
        if (!this.timelineData || !this.timelineData.length) return [];
        return this.timelineData.map(event => ({
            ...event,
            relativeTime: formatDate(event.date, 'relative'),
            iconBgStyle: `background: ${event.color}20`
        }));
    }

    /**********************************************************************************************
     *
     * Getters — CTAs
     *
     ***********************************************************************************************/

    /**
     * @description CTA counts grouped by type with dot color and label.
     * @returns {Array<Object>}
     */
    get ctaSummary() {
        const typeCounts = {};
        if (this.ctaData && this.ctaData.length) {
            this.ctaData.forEach(cta => {
                typeCounts[cta.type] = (typeCounts[cta.type] || 0) + 1;
            });
        }
        return Object.keys(CTA_TYPES).map(type => ({
            type,
            label: CTA_TYPES[type].label,
            count: typeCounts[type] || 0,
            dotStyle: `background: ${CTA_TYPES[type].color}`
        }));
    }

    /**
     * @description Total number of active CTAs.
     * @returns {number}
     */
    get totalCtas() {
        return this.ctaData ? this.ctaData.length : 0;
    }

    /**********************************************************************************************
     *
     * Getters — Renewal
     *
     ***********************************************************************************************/

    /**
     * @description Number of days until the next renewal date.
     * @returns {number|string}
     */
    get daysToRenewal() {
        if (!this.account || !this.account.renewalDate) return '—';
        const now = new Date();
        const renewal = new Date(this.account.renewalDate);
        const diffMs = renewal - now;
        return Math.max(0, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));
    }

    /**
     * @description Inline color style for renewal countdown (red < 60, yellow < 90, green otherwise).
     * @returns {string}
     */
    get renewalStyle() {
        const days = this.daysToRenewal;
        if (typeof days !== 'number') return '';
        if (days < 60) return 'color: #EA001E';
        if (days < 90) return 'color: #FFB75D';
        return 'color: #04844B';
    }

    /**
     * @description Formatted renewal date string.
     * @returns {string}
     */
    get formattedRenewalDate() {
        if (!this.account || !this.account.renewalDate) return '';
        return formatDate(this.account.renewalDate);
    }

    /**********************************************************************************************
     *
     * Getters — Products
     *
     ***********************************************************************************************/

    /**
     * @description List of product names from the account.
     * @returns {Array<string>}
     */
    get productList() {
        if (!this.account || !this.account.products) return [];
        return this.account.products;
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Loads mock data for health score, timeline, and CTAs based on the accountId.
     */
    _loadData() {
        if (!this.accountId) return;
        this.healthData = generateHealthScore(this.accountId);
        this.timelineData = generateTimeline(this.accountId).slice(0, 5);
        this.ctaData = generateCtas(this.accountId);
    }
}