/**
 * @description Invoices & Billing tab for Customer 360.
 *              Spec-aligned custom grid table with status pills, summary row,
 *              and 3 summary cards. Data sourced from NetSuite.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import getInvoices from '@salesforce/apex/Customer360Controller.getInvoices';
import { generateInvoicesV2 } from 'c/customer360MockData';
import { formatCurrency, isSalesforceId } from 'c/customer360Utils';
import { INVOICE_STATUS_CONFIG, SOURCE_BADGES } from 'c/customer360Constants';

export default class Customer360Invoices extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _rawData = [];
    @track _filterStatus = '';
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
        return SOURCE_BADGES.netsuite;
    }

    get filteredData() {
        if (!this._filterStatus) return [...this._rawData];
        return this._rawData.filter(inv => inv.status === this._filterStatus);
    }

    get displayData() {
        return this.filteredData.map(inv => ({
            ...inv,
            amountFormatted: this._fmtCurrency(inv.amount),
            dateFormatted: this._formatDate(inv.date),
            dueDateFormatted: this._formatDate(inv.dueDate),
            paymentDateFormatted: inv.paymentDate ? this._formatDate(inv.paymentDate) : '—',
            statusPillStyle: this._statusPillStyle(inv.status)
        }));
    }

    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Paid', value: 'Paid' },
            { label: 'Overdue', value: 'Overdue' },
            { label: 'Pending', value: 'Pending' },
            { label: 'Partial', value: 'Partial' }
        ];
    }

    get hasActiveFilter() {
        return !!this._filterStatus;
    }

    // Summary cards
    get totalBilled() {
        return formatCurrency(this._rawData.reduce((s, inv) => s + (inv.amount || 0), 0), true);
    }

    get totalPaid() {
        return formatCurrency(this._rawData.reduce((s, inv) => s + (inv.paidAmount || 0), 0), true);
    }

    get totalOutstanding() {
        const total = this._rawData.reduce((s, inv) => s + ((inv.amount || 0) - (inv.paidAmount || 0)), 0);
        return formatCurrency(Math.max(total, 0), true);
    }

    get outstandingIsZero() {
        const total = this._rawData.reduce((s, inv) => s + ((inv.amount || 0) - (inv.paidAmount || 0)), 0);
        return total <= 0;
    }

    get outstandingCardClass() {
        return this.outstandingIsZero
            ? 'c360-inv__summary-card c360-inv__summary-card--good'
            : 'c360-inv__summary-card c360-inv__summary-card--warn';
    }

    // Summary row total
    get summaryTotalBilled() {
        return this._fmtCurrency(this.filteredData.reduce((s, inv) => s + (inv.amount || 0), 0));
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleRefresh() {
        this._loadData();
    }

    handleStatusFilter(event) {
        this._filterStatus = event.detail.value;
    }

    handleClearFilter() {
        this._filterStatus = '';
    }

    handleExportCsv() {
        const data = this.filteredData;
        if (!data.length) return;
        const headers = ['Invoice #', 'Date', 'Due Date', 'Amount', 'Status', 'Payment Date'];
        const rows = data.map(inv => [
            inv.invoiceNumber, this._formatDate(inv.date), this._formatDate(inv.dueDate),
            inv.amount, inv.status, inv.paymentDate || ''
        ]);
        const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'invoices.csv';
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
            const result = await getInvoices({ accountId: this.accountId });
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
            this._rawData = generateInvoicesV2(this.accountId);
            this._isMockData = true;
        } catch (mockError) {
            this.errorMessage = 'Failed to load invoices.';
            this._rawData = [];
        }
        this.isLoading = false;
    }

    _statusPillStyle(status) {
        const cfg = INVOICE_STATUS_CONFIG[status] || {};
        return `background: ${cfg.bg || '#94a3b815'}; color: ${cfg.color || '#94a3b8'}`;
    }

    _fmtCurrency(val) {
        if (val == null) return '$0';
        return '$' + val.toLocaleString('en-US');
    }

    _formatDate(isoStr) {
        if (!isoStr) return '—';
        const d = new Date(isoStr);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    }
}