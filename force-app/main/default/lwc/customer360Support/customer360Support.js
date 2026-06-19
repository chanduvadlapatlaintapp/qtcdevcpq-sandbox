/**
 * @description Support Tickets tab for Customer 360.
 *              Spec-aligned custom grid table with priority dots, status pills,
 *              pagination, and filter bar. Data sourced from Zendesk.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSupportTickets from '@salesforce/apex/Customer360Controller.getSupportTickets';
import { generateTicketsV2 } from 'c/customer360MockData';
import { isSalesforceId } from 'c/customer360Utils';
import {
    TICKET_STATUS_CONFIG, TICKET_PRIORITY_CONFIG,
    SUPPORT_ASSIGNEES, SOURCE_BADGES
} from 'c/customer360Constants';

const PAGE_SIZE = 8;

export default class Customer360Support extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _rawData = [];
    @track _filterPriority = '';
    @track _filterStatus = '';
    @track _filterAssignee = '';
    @track _showAll = false;
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
        return SOURCE_BADGES.zendesk;
    }

    get filteredData() {
        let data = [...this._rawData];
        if (this._filterPriority) {
            data = data.filter(t => t.priority === this._filterPriority);
        }
        if (this._filterStatus) {
            data = data.filter(t => t.status === this._filterStatus);
        }
        if (this._filterAssignee) {
            data = data.filter(t => t.assignee === this._filterAssignee);
        }
        return data;
    }

    get displayData() {
        const data = this.filteredData;
        const sliced = this._showAll ? data : data.slice(0, PAGE_SIZE);
        return sliced.map(ticket => ({
            ...ticket,
            priorityDotStyle: `background: ${(TICKET_PRIORITY_CONFIG[ticket.priority] || {}).dot || '#94a3b8'}`,
            priorityDotColor: (TICKET_PRIORITY_CONFIG[ticket.priority] || {}).color || '#94a3b8',
            statusPillStyle: `background: ${(TICKET_STATUS_CONFIG[ticket.status] || {}).bg || '#94a3b815'}; color: ${(TICKET_STATUS_CONFIG[ticket.status] || {}).color || '#94a3b8'}`,
            createdFormatted: this._formatDate(ticket.createdAt),
            isClickable: true
        }));
    }

    get filteredCount() {
        return this.filteredData.length;
    }

    get showPagination() {
        return !this._showAll && this.filteredData.length > PAGE_SIZE;
    }

    get showAllLabel() {
        return `Show all ${this.filteredCount} tickets`;
    }

    get hasActiveFilters() {
        return this._filterPriority || this._filterStatus || this._filterAssignee;
    }

    get activeFilterCount() {
        let count = 0;
        if (this._filterPriority) count++;
        if (this._filterStatus) count++;
        if (this._filterAssignee) count++;
        return count;
    }

    // Filter options
    get priorityOptions() {
        return [
            { label: 'All Priorities', value: '' },
            { label: 'Critical', value: 'Critical' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'All Statuses', value: '' },
            { label: 'Open', value: 'Open' },
            { label: 'Pending', value: 'Pending' },
            { label: 'Solved', value: 'Solved' },
            { label: 'Closed', value: 'Closed' }
        ];
    }

    get assigneeOptions() {
        const options = [{ label: 'All Assignees', value: '' }];
        if (this._isMockData) {
            SUPPORT_ASSIGNEES.forEach(a => options.push({ label: a, value: a }));
        } else {
            const uniqueAssignees = [...new Set(
                this._rawData.map(t => t.assignee).filter(Boolean)
            )].sort();
            uniqueAssignees.forEach(a => options.push({ label: a, value: a }));
        }
        return options;
    }

    // Stats
    get openCount() {
        return this._rawData.filter(t => t.status === 'Open' || t.status === 'Pending').length;
    }

    get resolvedCount() {
        return this._rawData.filter(t => t.status === 'Solved' || t.status === 'Closed').length;
    }

    get avgResolution() {
        const resolved = this._rawData.filter(t => t.resolvedAt && t.createdAt);
        if (!resolved.length) return 'N/A';
        const totalDays = resolved.reduce((sum, t) => {
            const diff = (new Date(t.resolvedAt) - new Date(t.createdAt)) / (1000 * 60 * 60 * 24);
            return sum + Math.max(diff, 0);
        }, 0);
        return (totalDays / resolved.length).toFixed(1) + 'd';
    }

    get critHighCount() {
        return this._rawData.filter(t =>
            ['Critical', 'High'].includes(t.priority) &&
            ['Open', 'Pending'].includes(t.status)
        ).length;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleRefresh() {
        this._showAll = false;
        this._loadData();
    }

    handlePriorityFilter(event) {
        this._filterPriority = event.detail.value;
        this._showAll = false;
    }

    handleStatusFilter(event) {
        this._filterStatus = event.detail.value;
        this._showAll = false;
    }

    handleAssigneeFilter(event) {
        this._filterAssignee = event.detail.value;
        this._showAll = false;
    }

    handleClearFilters() {
        this._filterPriority = '';
        this._filterStatus = '';
        this._filterAssignee = '';
        this._showAll = false;
    }

    handleShowAll() {
        this._showAll = true;
    }

    handleTicketClick(event) {
        const ticketId = event.currentTarget.dataset.id;
        const ticket = this._rawData.find(t => t.id === ticketId);
        if (ticket) {
            this.dispatchEvent(new ShowToastEvent({
                title: ticket.ticketNumber,
                message: ticket.subject,
                variant: 'info'
            }));
        }
    }

    handleExportCsv() {
        const data = this.filteredData;
        if (!data.length) return;
        const headers = ['Ticket Number', 'Subject', 'Priority', 'Status', 'Assignee', 'Created'];
        const rows = data.map(t => [
            t.ticketNumber, `"${t.subject}"`, t.priority, t.status, t.assignee, this._formatDate(t.createdAt)
        ]);
        const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'support_tickets.csv';
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
            const result = await getSupportTickets({ accountId: this.accountId });
            this._rawData = this._normalizeTickets(result || []);
            this._isMockData = false;
        } catch (error) {
            this._loadMockData();
        } finally {
            this.isLoading = false;
        }
    }

    _loadMockData() {
        try {
            this._rawData = generateTicketsV2(this.accountId);
            this._isMockData = true;
        } catch (mockError) {
            this.errorMessage = 'Failed to load support tickets.';
            this._rawData = [];
        }
        this.isLoading = false;
    }

    _normalizeTickets(rawTickets) {
        return rawTickets.map(t => ({
            id: t.id,
            ticketNumber: t.ticketNumber,
            subject: t.subject,
            status: t.status,
            priority: t.priority,
            assignee: t.assignee || 'Unassigned',
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
            resolvedAt: t.resolvedAt,
            ticketUrl: t.ticketUrl,
            type: t.type
        }));
    }

    _formatDate(isoStr) {
        if (!isoStr) return '—';
        const d = new Date(isoStr);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    }
}