/**
 * @description Subscriptions tab for Customer 360.
 *              Spec-aligned card grid layout with product info, status badges,
 *              SKU display, filter bar, and drill-down navigation.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import getSubscriptions from '@salesforce/apex/Customer360Controller.getSubscriptions';
import { generateSubscriptionsV2 } from 'c/customer360MockData';
import { formatCurrency, isSalesforceId } from 'c/customer360Utils';
import { SUBSCRIPTION_STATUS_CONFIG, SOURCE_BADGES } from 'c/customer360Constants';

export default class Customer360Subscriptions extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _rawData = [];
    @track _filterStatus = '';
    @track _filterProduct = '';
    isLoading = true;
    errorMessage = '';
    _isMockData = false;

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    // ─── Getters ──────────────────────────────────────────────────────────────
    get hasData() {
        return this._rawData && this._rawData.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.hasData && !this.errorMessage;
    }

    get recordCount() {
        return this._rawData ? this._rawData.length : 0;
    }

    get isMockData() {
        return this._isMockData;
    }

    get sourceBadge() {
        return SOURCE_BADGES.salesforce;
    }

    get filteredData() {
        let data = [...this._rawData];
        if (this._filterStatus) {
            data = data.filter(s => s.status === this._filterStatus);
        }
        if (this._filterProduct) {
            data = data.filter(s => s.product === this._filterProduct);
        }
        return data;
    }

    get displayCards() {
        return this.filteredData.map(sub => {
            const statusCfg = SUBSCRIPTION_STATUS_CONFIG[sub.status] || {};
            return {
                ...sub,
                contractValueFormatted: this._fmtCurrency(sub.contractValue),
                dateRange: `${this._fmtDateShort(sub.startDate)} — ${this._fmtDateShort(sub.endDate)}`,
                statusPillStyle: `background: ${statusCfg.bg || '#94a3b815'}; color: ${statusCfg.color || '#94a3b8'}`,
                isActive: sub.status === 'Active',
                seatsFormatted: sub.seats ? sub.seats.toLocaleString() : '—'
            };
        });
    }

    get hasActiveFilters() {
        return this._filterStatus || this._filterProduct;
    }

    get activeFilterCount() {
        let count = 0;
        if (this._filterStatus) count++;
        if (this._filterProduct) count++;
        return count;
    }

    // Filter options
    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Active', value: 'Active' },
            { label: 'Expired', value: 'Expired' },
            { label: 'Pending', value: 'Pending' }
        ];
    }

    get productOptions() {
        const products = [...new Set(this._rawData.map(s => s.product))].sort();
        const opts = [{ label: 'All Products', value: '' }];
        products.forEach(p => opts.push({ label: p, value: p }));
        return opts;
    }

    // Summary metrics
    get totalAcv() {
        return formatCurrency(this._rawData.reduce((s, sub) => s + (sub.contractValue || 0), 0), true);
    }

    get activeCount() {
        return this._rawData.filter(s => s.status === 'Active').length;
    }

    get totalSeats() {
        return this._rawData.reduce((s, sub) => s + (sub.seats || 0), 0).toLocaleString();
    }

    get expiringSoonCount() {
        const now = new Date();
        const threshold = new Date();
        threshold.setDate(threshold.getDate() + 90);
        return this._rawData.filter(s => {
            if (!s.endDate) return false;
            const end = new Date(s.endDate);
            return end >= now && end <= threshold;
        }).length;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleRefresh() {
        this._loadData();
    }

    handleStatusFilter(event) {
        this._filterStatus = event.detail.value;
    }

    handleProductFilter(event) {
        this._filterProduct = event.detail.value;
    }

    handleClearFilters() {
        this._filterStatus = '';
        this._filterProduct = '';
    }

    handleViewUsage(event) {
        const subId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('viewusage', {
            detail: { subscriptionId: subId },
            bubbles: true,
            composed: true
        }));
    }

    handleExportCsv() {
        const data = this.filteredData;
        if (!data.length) return;
        const headers = ['Product', 'SKU', 'Category', 'Status', 'Seats', 'Contract Value', 'Start', 'End'];
        const rows = data.map(s => [
            s.product, s.sku, s.category, s.status, s.seats,
            s.contractValue, s.startDate, s.endDate
        ]);
        const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'subscriptions.csv';
        a.click();
        URL.revokeObjectURL(url);
    }

    // ─── Private Methods ──────────────────────────────────────────────────────
    async _loadData() {
        this.isLoading = true;
        this.errorMessage = '';

        if (!isSalesforceId(this.accountId)) {
            this._loadMockData();
            return;
        }

        try {
            const result = await getSubscriptions({ accountId: this.accountId });
            this._rawData = result || [];
            this._isMockData = false;
        } catch (error) {
            this._loadMockData();
        } finally {
            this.isLoading = false;
        }
    }

    _loadMockData() {
        try {
            this._rawData = generateSubscriptionsV2(this.accountId);
            this._isMockData = true;
        } catch (mockError) {
            this.errorMessage = 'Failed to load subscriptions.';
            this._rawData = [];
        }
        this.isLoading = false;
    }

    _fmtCurrency(val) {
        if (val == null) return '$0';
        return '$' + val.toLocaleString('en-US');
    }

    _fmtDateShort(isoStr) {
        if (!isoStr) return '—';
        const d = new Date(isoStr);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[d.getMonth()]} ${d.getFullYear()}`;
    }
}