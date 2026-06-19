/**
 * @description Contract Value tab for Portfolio Analysis. Breaks down subscription
 *              revenue by product (annualized), monthly sales price, ACV change,
 *              deployment model, and support level using horizontal bar charts.
 * @author      Vignesh Prabhudoss
 * @date        Mar-02-2026
 * @jira        BIZ-80262
 */
import { LightningElement, api } from 'lwc';

/**
 * @description Formats a numeric value as a locale-aware currency string (no decimals).
 * @param {number} val      - Value to format.
 * @param {string} currency - ISO 4217 currency code (default 'USD').
 * @returns {string} Formatted currency or em-dash for null/NaN.
 */
function formatCurrency(val, currency = 'USD') {
    if (val == null || isNaN(val)) return '\u2014';
    return new Intl.NumberFormat('en-US', { style: 'currency', currency, maximumFractionDigits: 0 }).format(val);
}

/**
 * @description Calculates the number of months between two date strings.
 * @param {string} startStr - Start date (ISO).
 * @param {string} endStr   - End date (ISO).
 * @returns {number|null} Month count or null.
 */
function monthsBetween(startStr, endStr) {
    if (!startStr || !endStr) return null;
    const s = new Date(startStr);
    const e = new Date(endStr);
    return (e.getFullYear() - s.getFullYear()) * 12 + (e.getMonth() - s.getMonth());
}

const COLORS = ['#207CEC', '#501AFF', '#6BA8FF', '#22ECCF', '#F3B400', '#E5225E', '#D2794D', '#A4B9D7', '#003C80', '#073C7D'];

export default class PortfolioRevenueAnalysis extends LightningElement {
    @api subscriptions = [];
    @api clientFacing = false;
    @api currencyCode = 'USD';

    // ========== Computed Analysis ==========
    get analysis() {
        if (!this.subscriptions || !this.subscriptions.length) return null;

        const productRevenue = {};
        const productAcvChange = {};
        const productMonthly = {};
        const deploymentRevenue = {};
        const supportRevenue = {};

        this.subscriptions.forEach(s => {
            const productName = s.SBQQ__Product__r?.Name || s.SBQQ__Product__r?.ProductCode || 'Unknown';
            const netPrice = s.SBQQ__NetPrice__c || 0;
            const qty = s.SBQQ__SegmentQuantity__c || 0;
            const revenue = netPrice * qty;
            const acvChange = s.ACV_Change__c || 0;
            const segmentMonths = s.Segment_Months__c || 0;
            const monthlyPrice = segmentMonths > 0 ? netPrice / segmentMonths : 0;
            const deployment = s.SBQQ__Product__r?.Deployment__c || 'Unknown';
            const support = s.Support_Level__c || 'Unknown';
            const months = monthsBetween(s.SBQQ__StartDate__c, s.SBQQ__EndDate__c);
            const annualized = months && months > 0 ? (revenue / months) * 12 : 0;

            if (!productRevenue[productName]) productRevenue[productName] = { annualized: 0, revenue: 0, count: 0 };
            productRevenue[productName].annualized += annualized;
            productRevenue[productName].revenue += revenue;
            productRevenue[productName].count += 1;

            if (!productAcvChange[productName]) productAcvChange[productName] = 0;
            productAcvChange[productName] += acvChange;

            if (!productMonthly[productName]) productMonthly[productName] = 0;
            productMonthly[productName] += monthlyPrice;

            if (!deploymentRevenue[deployment]) deploymentRevenue[deployment] = 0;
            deploymentRevenue[deployment] += revenue;

            if (!supportRevenue[support]) supportRevenue[support] = 0;
            supportRevenue[support] += revenue;
        });

        const toSorted = (obj, valFn) =>
            Object.entries(obj)
                .map(([label, data]) => ({ label, value: typeof data === 'number' ? data : valFn(data) }))
                .sort((a, b) => b.value - a.value);

        return {
            byProduct: toSorted(productRevenue, d => d.annualized).map(p => ({
                ...p,
                subtitle: `${productRevenue[p.label].count} lines, Contract Value: ${formatCurrency(productRevenue[p.label].revenue, this.currencyCode)}`
            })),
            byAcvChange: toSorted(productAcvChange, d => d).filter(p => p.value !== 0),
            byMonthly: toSorted(productMonthly, d => d).filter(p => p.value > 0),
            byDeployment: toSorted(deploymentRevenue, d => d),
            bySupport: toSorted(supportRevenue, d => d)
        };
    }

    get hasAnalysis() {
        return this.analysis != null;
    }

    get showAcvChange() {
        return !this.clientFacing;
    }

    // ========== Bar Chart Data ==========
    get productBars() {
        if (!this.analysis) return [];
        const data = this.analysis.byProduct.slice(0, 15);
        const max = data.length > 0 ? data[0].value : 0;
        return data.map((item, i) => this.buildBar(item, max, COLORS[i % COLORS.length], item.subtitle));
    }

    get hasMonthlyData() {
        return this.analysis && this.analysis.byMonthly.length > 0;
    }

    get monthlyBars() {
        if (!this.analysis) return [];
        const data = this.analysis.byMonthly.slice(0, 15);
        const max = data.length > 0 ? data[0].value : 0;
        return data.map((item, i) => this.buildBar(item, max, COLORS[(i + 2) % COLORS.length]));
    }

    get hasAcvChangeData() {
        return this.analysis && this.analysis.byAcvChange.length > 0;
    }

    get acvChangeBars() {
        if (!this.analysis) return [];
        const data = this.analysis.byAcvChange.slice(0, 10);
        return data.map(item => ({
            key: item.label,
            label: item.label,
            value: (item.value >= 0 ? '+' : '') + formatCurrency(item.value, this.currencyCode),
            valueClass: item.value >= 0 ? 'bar-value bar-value-green' : 'bar-value bar-value-red'
        }));
    }

    get deploymentBars() {
        if (!this.analysis) return [];
        const data = this.analysis.byDeployment;
        const max = data.length > 0 ? data[0].value : 0;
        return data.map((item, i) => this.buildBar(item, max, i === 0 ? '#207CEC' : '#F3B400'));
    }

    get supportBars() {
        if (!this.analysis) return [];
        const data = this.analysis.bySupport;
        const max = data.length > 0 ? data[0].value : 0;
        return data.map((item, i) => this.buildBar(item, max, COLORS[(i + 4) % COLORS.length]));
    }

    // Grid class for bottom row depends on whether ACV Change panel is shown
    get bottomGridClass() {
        return this.showAcvChange ? 'pra-grid-3' : 'pra-grid-2';
    }

    // ========== Helpers ==========

    /**
     * @description Constructs a bar-chart item object for the template.
     * @param {Object} item     - Data item with label and value.
     * @param {number} maxValue - Maximum value in the dataset (for proportional width).
     * @param {string} color    - CSS background color for the bar.
     * @param {string} subtitle - Optional subtitle text beneath the label.
     * @returns {Object} Bar descriptor with key, label, value, barStyle, subtitle.
     */
    buildBar(item, maxValue, color, subtitle) {
        const pct = maxValue > 0 ? (item.value / maxValue) * 100 : 0;
        return {
            key: item.label,
            label: item.label,
            value: formatCurrency(item.value, this.currencyCode),
            barStyle: `width:${Math.min(pct, 100)}%;background:${color}`,
            subtitle: subtitle || null,
            hasSubtitle: !!subtitle
        };
    }
}