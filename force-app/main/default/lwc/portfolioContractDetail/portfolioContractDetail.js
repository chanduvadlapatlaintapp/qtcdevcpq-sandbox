/**
 * @description Contracts tab for Portfolio Analysis. Renders a sortable, filterable,
 *              grouped-by-OSA data table of subscription lines with invoice matching,
 *              deployment/support filters, expand/collapse per group, draggable column
 *              resize, and current-period / expiring-soon row highlighting.
 * @author      Vignesh Prabhudoss
 * @date        Mar-02-2026
 * @jira        BIZ-80262, BIZ-80292
 */
import { LightningElement, api, track } from 'lwc';

/**
 * @description Formats a numeric value as a locale-aware currency string.
 * @param {number} val      - Value to format.
 * @param {string} currency - ISO 4217 currency code (default 'USD').
 * @returns {string} Formatted currency or em-dash for null/NaN.
 */
function formatCurrency(val, currency = 'USD') {
    if (val == null || isNaN(val)) return '\u2014';
    return new Intl.NumberFormat('en-US', { style: 'currency', currency, maximumFractionDigits: 2 }).format(val);
}

/**
 * @description Formats an ISO date string as a short US date (e.g. "Mar 6, 2026").
 * @param {string} dateStr - ISO date string.
 * @returns {string} Formatted date or em-dash.
 */
function formatDate(dateStr) {
    if (!dateStr) return '\u2014';
    return new Date(dateStr).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

/**
 * @description Calculates the number of calendar days between two date strings.
 * @param {string} startStr - Start date (ISO).
 * @param {string} endStr   - End date (ISO).
 * @returns {number|null} Day count or null if inputs are missing.
 */
function daysBetween(startStr, endStr) {
    if (!startStr || !endStr) return null;
    const diff = new Date(endStr) - new Date(startStr);
    return Math.round(diff / (1000 * 60 * 60 * 24));
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

/**
 * @description Annualizes a revenue amount based on the contract term length.
 * @param {number} netPrice - Total contract value for the segment.
 * @param {string} startStr - Subscription start date (ISO).
 * @param {string} endStr   - Subscription end date (ISO).
 * @returns {number|null} Annualized revenue or null.
 */
function annualize(netPrice, startStr, endStr) {
    const months = monthsBetween(startStr, endStr);
    if (!months || months <= 0 || netPrice == null) return null;
    return (netPrice / months) * 12;
}

const ALL_COLUMNS = [
    { key: 'osa', label: 'OSA #', internal: false },
    { key: 'contractNum', label: 'Contract #', internal: false },
    { key: 'cpi', label: 'Uplift Cap', internal: true },
    { key: 'sfa', label: 'SFA %', internal: true },
    { key: 'productName', label: 'Product', internal: false },
    { key: 'productCode', label: 'Product Code', internal: false },
    { key: 'deployment', label: 'Deployment Type', internal: false },
    { key: 'currency', label: 'Currency', internal: false },
    { key: 'meterType', label: 'Meter Type', internal: false },
    { key: 'quantity', label: 'Qty', internal: false, align: 'right' },
    { key: 'revenue', label: 'Contract Value', internal: false, align: 'right' },
    { key: 'salePriceMonth', label: 'Sales Price / Month', internal: false, align: 'right' },
    { key: 'supportLevel', label: 'Support Level', internal: false },
    { key: 'startDate', label: 'Start Date', internal: false },
    { key: 'endDate', label: 'End Date', internal: false },
    { key: 'status', label: 'Status', internal: false },
    { key: 'invoiceTotal', label: 'Invoice Total', internal: true, align: 'right' },
    { key: 'invoiceNumber', label: 'Invoice #', internal: false, isLink: true },
    { key: 'paymentStatus', label: 'Payment Status', internal: false },
    { key: 'acv', label: 'ACV', internal: true, align: 'right' },
    { key: 'acvChange', label: 'ACV Chg', internal: true, align: 'right' },
    { key: 'bundle', label: 'Bundle', internal: false },
    { key: 'days', label: 'Days', internal: false, align: 'right' },
    { key: 'annualized', label: 'Annualized', internal: false, align: 'right' }
];

export default class PortfolioContractDetail extends LightningElement {
    /** @api {Array} subscriptions - SBQQ__Subscription__c records from parent. */
    @api subscriptions = [];
    /** @api {boolean} clientFacing - When true, hides internal-only columns and bundled pricing. */
    @api clientFacing = false;
    /** @api {string} currencyCode - ISO 4217 code for formatting. */
    @api currencyCode = 'USD';
    /** @api {Object} invoiceMap - Invoice lookup map keyed by osa|startDate|endDate. */
    @api invoiceMap = {};
    /** @api {boolean} isLoadingInvoices - True while NetSuite invoice fetch is in progress. */
    @api isLoadingInvoices = false;
    /** @api {string} invoiceError - Error message from NetSuite invoice fetch, or null. */
    @api invoiceError = null;

    sortCol = 'startDate';
    sortDir = 'desc';
    filterDeployment = 'all';
    filterSupport = 'all';
    @track expandedGroups = {};
    allExpanded = true;
    _initialized = false;
    _resizeCol = null;
    _resizeStartX = 0;
    _resizeStartWidth = 0;
    _boundResizeMove = null;
    _boundResizeEnd = null;

    // ========== Getters — Columns ==========
    get visibleColumns() {
        return ALL_COLUMNS.filter(c => !this.clientFacing || !c.internal);
    }

    get colSpanFull() {
        return this.visibleColumns.length;
    }

    // ========== Getters — Filters ==========
    get deploymentOptions() {
        const set = new Set();
        if (this.subscriptions) {
            this.subscriptions.forEach(s => {
                if (s.SBQQ__Product__r?.Deployment__c) set.add(s.SBQQ__Product__r.Deployment__c);
            });
        }
        const opts = [{ label: 'All Deployments', value: 'all' }];
        [...set].sort().forEach(d => opts.push({ label: d, value: d }));
        return opts;
    }

    get supportOptions() {
        const set = new Set();
        if (this.subscriptions) {
            this.subscriptions.forEach(s => {
                if (s.Support_Level__c) set.add(s.Support_Level__c);
            });
        }
        const opts = [{ label: 'All Support Levels', value: 'all' }];
        [...set].sort().forEach(d => opts.push({ label: d, value: d }));
        return opts;
    }

    get expandCollapseLabel() {
        return this.allExpanded ? 'Collapse All' : 'Expand All';
    }

    // ========== Getters — Processed Data ==========
    get rows() {
        if (!this.subscriptions) return [];

        let data = this.subscriptions.map(s => {
            const netPrice = s.SBQQ__NetPrice__c || 0;
            const qty = s.SBQQ__SegmentQuantity__c || 0;
            const segMonths = s.Segment_Months__c || 0;
            const revenue = netPrice * qty;

            // Invoice matching: first by composite key (header), then by product code + quantity (line)
            const osa = s.SBQQ__Contract__r?.OSA_Number__c || '';
            const segStart = s.SBQQ__SegmentStartDate__c || '';
            const segEnd = s.SBQQ__SegmentEndDate__c || '';
            const invoiceKey = `${osa}|${segStart}|${segEnd}`;
            const matchedLines = this.invoiceMap[invoiceKey] || [];

            const productCode = s.SBQQ__Product__r?.ProductCode || '';
            const matchedLine = matchedLines.find(line => {
                if (!line.itemCode) return false;
                return line.itemCode === productCode &&
                       Math.abs(Number(line.lineQuantity)) === Math.abs(qty);
            });
            const invoice = matchedLine || (matchedLines.length > 0 ? matchedLines[0] : null);

            return {
                id: s.Id,
                osa: osa || '\u2014',
                contractNum: s.SBQQ__ContractNumber__c || '\u2014',
                bundle: s.SBQQ__Contract__r?.Hide_Pricing__c,
                productName: s.SBQQ__Product__r?.Name || s.Name || '\u2014',
                productCode: productCode || '\u2014',
                deployment: s.SBQQ__Product__r?.Deployment__c || '\u2014',
                currency: s.CurrencyIsoCode || 'USD',
                meterType: s.Per_Integrations__c || '\u2014',
                quantity: qty,
                netPrice: netPrice,
                revenue: revenue,
                salePriceMonth: segMonths > 0 ? netPrice / segMonths : null,
                supportLevel: s.Support_Level__c || '\u2014',
                startDate: s.SBQQ__SegmentStartDate__c,
                endDate: s.SBQQ__SegmentEndDate__c,
                status: s.Contract_Status__c || '\u2014',
                invoiceTotal: matchedLine ? Math.abs(matchedLine.lineAmount) : null,
                invoiceNumber: invoice ? invoice.invoiceNumber : null,
                invoiceUrl: invoice ? invoice.sharePointUrl : null,
                paymentStatus: invoice ? invoice.paymentStatus : null,
                acv: segMonths > 0 ? (netPrice / segMonths) * 12 * qty : null,
                acvChange: s.ACV_Change__c,
                cpi: s.SBQQ__Contract__r?.CPI__c,
                sfa: s.SBQQ__Contract__r?.SBQQ__RenewalUpliftRate__c,
                days: daysBetween(s.SBQQ__SegmentStartDate__c, s.SBQQ__SegmentEndDate__c),
                annualized: annualize(revenue, s.SBQQ__StartDate__c, s.SBQQ__EndDate__c),
                isPreviousContract: s._isPreviousContract || false
            };
        });

        // Apply filters
        if (this.filterDeployment !== 'all') {
            data = data.filter(r => r.deployment === this.filterDeployment);
        }
        if (this.filterSupport !== 'all') {
            data = data.filter(r => r.supportLevel === this.filterSupport);
        }

        // Sort
        data.sort((a, b) => {
            let va = a[this.sortCol], vb = b[this.sortCol];
            if (va == null) va = '';
            if (vb == null) vb = '';
            if (typeof va === 'number' && typeof vb === 'number') {
                return this.sortDir === 'asc' ? va - vb : vb - va;
            }
            const sa = String(va).toLowerCase(), sb = String(vb).toLowerCase();
            return this.sortDir === 'asc' ? sa.localeCompare(sb) : sb.localeCompare(sa);
        });

        return data;
    }

    get groups() {
        const map = {};
        this.rows.forEach(r => {
            const key = r.osa;
            if (!map[key]) {
                map[key] = { osa: key, rows: [], totalContractValue: 0, totalAcv: 0, totalAcvChange: 0, totalAnnualized: 0 };
            }
            map[key].rows.push(r);
            map[key].totalContractValue += r.revenue || 0;
            map[key].totalAcv += r.acv || 0;
            map[key].totalAcvChange += r.acvChange || 0;
            map[key].totalAnnualized += r.annualized || 0;
        });

        const today = new Date();
        const ninetyDays = new Date(today);
        ninetyDays.setDate(ninetyDays.getDate() + 90);

        return Object.values(map).map(g => {
            const isExpanded = this.expandedGroups[g.osa] === true;
            const lineCountLabel = `${g.rows.length} line${g.rows.length !== 1 ? 's' : ''}`;
            const groupSummary = this.buildGroupSummary(g);
            const expandIcon = isExpanded ? '\u25BC' : '\u25B6';

            const processedRows = g.rows.map(r => ({
                ...r,
                cells: this.buildCells(r),
                rowClass: this.getRowClass(r, today, ninetyDays)
            }));

            return {
                ...g,
                isExpanded,
                lineCountLabel,
                groupSummary,
                expandIcon,
                processedRows
            };
        });
    }

    get lineCountSummary() {
        const rowCount = this.rows.length;
        const groupCount = this.groups.length;
        return `${rowCount} line${rowCount !== 1 ? 's' : ''} across ${groupCount} contract${groupCount !== 1 ? 's' : ''}`;
    }

    // ========== Lifecycle ==========
    renderedCallback() {
        if (!this._initialized && this.subscriptions && this.subscriptions.length > 0) {
            this._initialized = true;
            this.expandAllGroups();
        }
    }

    // ========== Event Handlers ==========
    handleDeploymentFilter(event) {
        this.filterDeployment = event.target.value;
    }

    handleSupportFilter(event) {
        this.filterSupport = event.target.value;
    }

    handleToggleAll() {
        if (this.allExpanded) {
            this.expandedGroups = {};
            this.allExpanded = false;
        } else {
            this.expandAllGroups();
        }
    }

    handleToggleGroup(event) {
        const osa = event.currentTarget.dataset.osa;
        const updated = { ...this.expandedGroups };
        if (updated[osa]) {
            delete updated[osa];
        } else {
            updated[osa] = true;
        }
        this.expandedGroups = updated;
    }

    handleSort(event) {
        // Don't sort if we just finished resizing
        if (this._justResized) {
            this._justResized = false;
            return;
        }
        const col = event.currentTarget.dataset.col;
        if (this.sortCol === col) {
            this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortCol = col;
            this.sortDir = 'asc';
        }
    }

    handleResizeStart(event) {
        event.stopPropagation();
        event.preventDefault();
        const th = event.target.closest('th');
        if (!th) return;

        this._resizeCol = th;
        this._resizeStartX = event.clientX;
        this._resizeStartWidth = th.offsetWidth;

        // Highlight the active handle
        event.target.classList.add('th-resize-active');

        this._boundResizeMove = (e) => this._handleResizeMove(e);
        this._boundResizeEnd = (e) => this._handleResizeEnd(e, event.target);
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.addEventListener('mousemove', this._boundResizeMove);
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.addEventListener('mouseup', this._boundResizeEnd);
    }

    _handleResizeMove(event) {
        if (!this._resizeCol) return;
        const diff = event.clientX - this._resizeStartX;
        const newWidth = Math.max(40, this._resizeStartWidth + diff);
        this._resizeCol.style.width = newWidth + 'px';
        this._resizeCol.style.minWidth = newWidth + 'px';
    }

    _handleResizeEnd(event, handle) {
        if (handle) {
            handle.classList.remove('th-resize-active');
        }
        this._resizeCol = null;
        this._justResized = true;
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.removeEventListener('mousemove', this._boundResizeMove);
        // eslint-disable-next-line @lwc/lwc/no-document-query
        document.removeEventListener('mouseup', this._boundResizeEnd);
    }

    // ========== Helpers ==========

    /** @description Expands all OSA groups in the table. */
    expandAllGroups() {
        const expanded = {};
        if (this.subscriptions) {
            const osaSet = new Set();
            this.subscriptions.forEach(s => {
                const osa = s.SBQQ__Contract__r?.OSA_Number__c || '\u2014';
                osaSet.add(osa);
            });
            osaSet.forEach(osa => { expanded[osa] = true; });
        }
        this.expandedGroups = expanded;
        this.allExpanded = true;
    }

    /**
     * @description Builds the inline summary string for an OSA group header.
     * @param {Object} group - Grouped data with totalContractValue, totalAcv, etc.
     * @returns {string} Formatted summary text.
     */
    buildGroupSummary(group) {
        let summary = `Contract Value: ${formatCurrency(group.totalContractValue, this.currencyCode)}`;
        if (!this.clientFacing) {
            summary += `  |  ACV: ${formatCurrency(group.totalAcv, this.currencyCode)}`;
            summary += `  |  ACV Chg: ${formatCurrency(group.totalAcvChange, this.currencyCode)}`;
        }
        summary += `  |  Ann: ${formatCurrency(group.totalAnnualized, this.currencyCode)}`;
        return summary;
    }

    /**
     * @description Transforms a subscription row into an array of renderable cell objects
     *              for the template, applying formatting, status badges, and visibility rules.
     * @param {Object} row - Processed subscription row.
     * @returns {Array} Cell descriptors with value, class, badge, and link metadata.
     */
    buildCells(row) {
        return this.visibleColumns.map(col => {
            let display;
            let cellClass = col.align === 'right' ? 'td-cell text-right' : 'td-cell';
            let isStatusBadge = false;
            let statusClass = '';

            switch (col.key) {
                case 'revenue':
                case 'salePriceMonth':
                case 'annualized':
                case 'invoiceTotal':
                    display = (this.clientFacing && row.bundle) ? '\u2014' : formatCurrency(row[col.key], row.currency);
                    break;
                case 'acv':
                case 'acvChange':
                    display = formatCurrency(row[col.key], row.currency);
                    break;
                case 'startDate':
                case 'endDate':
                    display = formatDate(row[col.key]);
                    break;
                case 'bundle':
                    display = row.bundle != null ? (typeof row.bundle === 'boolean' ? (row.bundle ? 'Yes' : 'No') : String(row.bundle)) : '\u2014';
                    break;
                case 'cpi':
                    display = row.cpi != null ? (typeof row.cpi === 'boolean' ? (row.cpi ? 'Yes' : 'No') : String(row.cpi)) : '\u2014';
                    break;
                case 'sfa':
                    display = row.sfa != null ? `${row.sfa}%` : '\u2014';
                    break;
                case 'quantity':
                case 'days':
                    display = row[col.key] != null ? row[col.key].toLocaleString() : '\u2014';
                    break;
                case 'status':
                    display = row.status;
                    isStatusBadge = true;
                    statusClass = row.status === 'In Force' ? 'status-badge status-active' : 'status-badge status-partial';
                    break;
                case 'invoiceNumber':
                    display = row.invoiceNumber || '\u2014';
                    break;
                case 'paymentStatus':
                    if (row.paymentStatus) {
                        display = row.paymentStatus;
                        isStatusBadge = true;
                        const paid = row.paymentStatus.toLowerCase() === 'paid in full';
                        statusClass = paid ? 'status-badge status-paid' : 'status-badge status-unpaid';
                    } else {
                        display = '\u2014';
                    }
                    break;
                default:
                    display = row[col.key] ?? '\u2014';
            }

            return {
                key: col.key,
                value: display,
                cellClass,
                isStatusBadge,
                statusClass,
                isLink: col.key === 'invoiceNumber' && row.invoiceUrl,
                linkUrl: col.key === 'invoiceNumber' ? row.invoiceUrl : null
            };
        });
    }

    /**
     * @description Returns the CSS class for a subscription row based on its temporal state
     *              (current period, expiring within 90 days, or previous-contract exception).
     * @param {Object} row        - Processed subscription row.
     * @param {Date}   today      - Current date.
     * @param {Date}   ninetyDays - Date 90 days from today.
     * @returns {string} CSS class string.
     */
    getRowClass(row, today, ninetyDays) {
        if (row.isPreviousContract) {
            return 'tr-row tr-previous-contract';
        }
        // Highlight current period (today falls between segment start and end)
        if (row.startDate && row.endDate) {
            const start = new Date(row.startDate);
            const end = new Date(row.endDate);
            if (start <= today && end >= today) {
                return 'tr-row tr-current-period';
            }
            if (end >= today && end <= ninetyDays) {
                return 'tr-row tr-expiring';
            }
        }
        return 'tr-row';
    }

    get headerColumns() {
        return this.visibleColumns.map(col => ({
            ...col,
            thClass: `th-cell ${col.align === 'right' ? 'text-right' : ''}`,
            sortIndicator: this.sortCol === col.key ? (this.sortDir === 'asc' ? ' \u2191' : ' \u2193') : ''
        }));
    }
}