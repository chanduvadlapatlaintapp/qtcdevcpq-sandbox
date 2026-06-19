/**
 * @description Activity Timeline for Customer 360.
 *              Vertical feed of activities with type filters and search.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { generateTimeline } from 'c/customer360MockData';
import { formatDate } from 'c/customer360Utils';

const TYPE_FILTERS = [
    { label: 'All', value: 'all', icon: 'utility:list' },
    { label: 'Meetings', value: 'meeting', icon: 'standard:event' },
    { label: 'Emails', value: 'email', icon: 'standard:email' },
    { label: 'Calls', value: 'call', icon: 'standard:log_a_call' },
    { label: 'Notes', value: 'note', icon: 'standard:note' },
    { label: 'Milestones', value: 'milestone', icon: 'standard:task2' },
    { label: 'CTAs', value: 'cta', icon: 'standard:custom_notification' },
    { label: 'Escalations', value: 'escalation', icon: 'standard:case' }
];

export default class Customer360Timeline extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _events = [];
    @track _activeFilter = 'all';
    @track _searchTerm = '';
    _isLoaded = false;
    _showCount = 20;

    typeFilters = TYPE_FILTERS;

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    // ─── Getters ──────────────────────────────────────────────────────────────
    get filteredEvents() {
        let events = this._events;

        if (this._activeFilter !== 'all') {
            events = events.filter(e => e.type === this._activeFilter);
        }

        if (this._searchTerm) {
            const term = this._searchTerm.toLowerCase();
            events = events.filter(e =>
                e.title.toLowerCase().includes(term) ||
                e.description.toLowerCase().includes(term) ||
                e.user.toLowerCase().includes(term)
            );
        }

        return events.slice(0, this._showCount).map(e => ({
            ...e,
            formattedDate: formatDate(e.date, 'relative'),
            fullDate: formatDate(e.date, 'long'),
            iconStyle: `background-color: ${e.color}`,
            typeLabel: this._getTypeLabel(e.type)
        }));
    }

    get totalFilteredCount() {
        let events = this._events;
        if (this._activeFilter !== 'all') {
            events = events.filter(e => e.type === this._activeFilter);
        }
        if (this._searchTerm) {
            const term = this._searchTerm.toLowerCase();
            events = events.filter(e =>
                e.title.toLowerCase().includes(term) ||
                e.description.toLowerCase().includes(term) ||
                e.user.toLowerCase().includes(term)
            );
        }
        return events.length;
    }

    get hasEvents() {
        return this.filteredEvents.length > 0;
    }

    get showEmpty() {
        return this._isLoaded && !this.hasEvents;
    }

    get hasMore() {
        return this._showCount < this.totalFilteredCount;
    }

    get eventCount() {
        return this._events.length;
    }

    get filterButtons() {
        return this.typeFilters.map(f => ({
            ...f,
            cssClass: f.value === this._activeFilter
                ? 'c360-tl__filter-btn c360-tl__filter-btn--active'
                : 'c360-tl__filter-btn'
        }));
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleFilterClick(event) {
        this._activeFilter = event.currentTarget.dataset.filter;
        this._showCount = 20;
    }

    handleSearch(event) {
        this._searchTerm = event.target.value;
        this._showCount = 20;
    }

    handleShowMore() {
        this._showCount += 20;
    }

    // ─── Private Methods ──────────────────────────────────────────────────────
    _loadData() {
        try {
            this._events = generateTimeline(this.accountId);
        } catch (e) {
            this._events = [];
        }
        this._isLoaded = true;
    }

    _getTypeLabel(type) {
        const filter = this.typeFilters.find(f => f.value === type);
        return filter ? filter.label.replace(/s$/, '') : type;
    }
}