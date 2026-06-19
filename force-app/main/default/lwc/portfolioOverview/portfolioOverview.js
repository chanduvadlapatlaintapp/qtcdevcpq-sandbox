/**
 * @description Overview dashboard tab for Portfolio Analysis. Displays account metadata
 *              (GTM tier, MSSA, Cloud Addendum), KPI summary cards (total contract
 *              value, ACV change, active contracts, renewing soon), a Cloud vs On-Prem
 *              donut chart, and a horizontal product-mix bar chart.
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

const COLORS = ['#207CEC', '#501AFF', '#6BA8FF', '#22ECCF', '#F3B400', '#E5225E', '#D2794D', '#A4B9D7', '#003C80', '#073C7D'];

export default class PortfolioOverview extends LightningElement {
    @api subscriptions = [];
    @api accountName = '';
    @api currencyCode = 'USD';
    @api accountDetails;

    // ========== Icon Constants ==========
    iconMoney = '\u{1F4B5}';
    iconChart = '\u{1F4C8}';
    iconContracts = '\u{1F4D1}';
    iconClock = '\u{23F0}';

    // ========== Account Metadata ==========
    get gtmTier() {
        return this.accountDetails?.GTM_Motion_Tier__c || '\u2014';
    }

    get clientSince() {
        return this.accountDetails?.Customer_Since__c || '\u2014';
    }

    get mssaNumber() {
        return this.accountDetails?.Master_Terms_Contract_Number__r?.ContractNumber || '\u2014';
    }

    get mssaVersion() {
        return this.accountDetails?.Contract_Term_Version__c || '\u2014';
    }

    get mssaUpliftCap() {
        return this.accountDetails?.Master_Terms_CPI__c || '\u2014';
    }

    get cloudAddendum() {
        return this.accountDetails?.Cloud_Addendum__r?.ContractNumber || 'No';
    }

    // ========== Computed Stats ==========
    get stats() {
        if (!this.subscriptions || !this.subscriptions.length) return null;

        let totalNetPrice = 0;
        let totalAcvChange = 0;
        let cloudNetPrice = 0;
        let onPremNetPrice = 0;
        const osasSet = new Set();
        const productMap = {};
        const currencySet = new Set();
        let renewingSoon = 0;
        const today = new Date();
        const ninetyDays = new Date(today);
        ninetyDays.setDate(ninetyDays.getDate() + 90);

        this.subscriptions.forEach(s => {
            const netPrice = s.SBQQ__NetPrice__c || 0;
            const qty = s.SBQQ__SegmentQuantity__c || 0;
            const revenue = netPrice * qty;
            const acvChange = s.ACV_Change__c || 0;
            const deployment = s.SBQQ__Product__r?.Deployment__c || 'Other';
            const productCode = s.SBQQ__Product__r?.ProductCode || 'Unknown';
            const productName = s.SBQQ__Product__r?.Name || productCode;
            const osa = s.SBQQ__Contract__r?.OSA_Number__c;
            const segEnd = s.SBQQ__SegmentEndDate__c ? new Date(s.SBQQ__SegmentEndDate__c) : null;

            totalNetPrice += revenue;
            totalAcvChange += acvChange;
            currencySet.add(s.CurrencyIsoCode || 'USD');

            if (deployment === 'Cloud') cloudNetPrice += revenue;
            else onPremNetPrice += revenue;

            if (osa) osasSet.add(osa);

            if (!productMap[productCode]) {
                productMap[productCode] = { name: productName, total: 0, count: 0 };
            }
            productMap[productCode].total += revenue;
            productMap[productCode].count += 1;

            if (segEnd && segEnd <= ninetyDays && segEnd >= today) {
                renewingSoon++;
            }
        });

        const productBreakdown = Object.entries(productMap)
            .map(([code, data]) => ({ code, ...data }))
            .sort((a, b) => b.total - a.total);
        const maxProductValue = productBreakdown.length > 0 ? productBreakdown[0].total : 0;

        return {
            totalNetPrice,
            totalAcvChange,
            cloudNetPrice,
            onPremNetPrice,
            contractCount: osasSet.size,
            subscriptionCount: this.subscriptions.length,
            productBreakdown,
            maxProductValue,
            currencies: [...currencySet],
            renewingSoon
        };
    }

    get hasStats() {
        return this.stats != null;
    }

    // ========== Banner Info ==========
    get currenciesLabel() {
        const s = this.stats;
        if (!s) return '';
        return s.currencies.join(', ') + ' ' + (s.currencies.length > 1 ? 'currencies' : 'currency');
    }

    get subscriptionLabel() {
        const s = this.stats;
        return s ? `${s.subscriptionCount} subscriptions` : '';
    }

    get contractLabel() {
        const s = this.stats;
        return s ? `${s.contractCount} contracts` : '';
    }

    // ========== Summary Cards ==========
    get totalContractValue() {
        return this.stats ? formatCurrency(this.stats.totalNetPrice, this.currencyCode) : '\u2014';
    }

    get totalAcvChange() {
        return this.stats ? formatCurrency(this.stats.totalAcvChange, this.currencyCode) : '\u2014';
    }

    get activeContractsCount() {
        return this.stats ? this.stats.contractCount : 0;
    }

    get subscriptionLinesLabel() {
        return this.stats ? `${this.stats.subscriptionCount} subscription lines` : '';
    }

    get renewingSoonCount() {
        return this.stats ? this.stats.renewingSoon : 0;
    }

    get renewingSoonSubtitle() {
        const count = this.stats ? this.stats.renewingSoon : 0;
        return count > 0 ? 'Subscriptions ending soon' : 'No imminent renewals';
    }

    get renewingSoonColorClass() {
        return this.stats && this.stats.renewingSoon > 0 ? 'card-icon card-icon-amber' : 'card-icon card-icon-gray';
    }

    // ========== Deployment Split ==========
    get cloudPct() {
        if (!this.stats || this.stats.totalNetPrice === 0) return 0;
        return Math.round((this.stats.cloudNetPrice / this.stats.totalNetPrice) * 100);
    }

    get onPremPct() {
        return 100 - this.cloudPct;
    }

    get cloudValue() {
        return this.stats ? formatCurrency(this.stats.cloudNetPrice, this.currencyCode) : '\u2014';
    }

    get onPremValue() {
        return this.stats ? formatCurrency(this.stats.onPremNetPrice, this.currencyCode) : '\u2014';
    }

    get cloudLabel() {
        return `${this.cloudValue} (${this.cloudPct}%)`;
    }

    get onPremLabel() {
        return `${this.onPremValue} (${this.onPremPct}%)`;
    }

    // SVG donut chart stroke calculations
    get cloudStrokeDasharray() {
        const val = this.cloudPct * 0.88;
        return `${val} ${88 - val}`;
    }

    get onPremStrokeDasharray() {
        const val = this.onPremPct * 0.88;
        return `${val} ${88 - val}`;
    }

    get onPremStrokeDashoffset() {
        return 22 - this.cloudPct * 0.88;
    }

    // ========== Product Mix ==========
    get productBars() {
        if (!this.stats) return [];
        return this.stats.productBreakdown.slice(0, 10).map((p, i) => {
            const pct = this.stats.maxProductValue > 0
                ? (p.total / this.stats.maxProductValue) * 100 : 0;
            return {
                key: p.code,
                label: `${p.name} (${p.count})`,
                value: formatCurrency(p.total, this.currencyCode),
                barStyle: `width:${Math.min(pct, 100)}%;background:${COLORS[i % COLORS.length]}`
            };
        });
    }
}