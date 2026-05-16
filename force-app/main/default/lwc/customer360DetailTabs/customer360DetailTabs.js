/**
 * @description Customer 360 Detail Tabs - Custom tab navigation bar for the detail view.
 *              Renders a horizontal row of tab buttons and dispatches tabchange events
 *              when the user selects a different tab.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

import { LightningElement, api } from 'lwc';

// ─── Tab Definitions ────────────────────────────────────────────────────────

const TAB_DEFINITIONS = [
    { key: 'overview', label: 'Overview', icon: 'utility:home' },
    { key: 'health', label: 'Health', icon: 'utility:heartbeat' },
    { key: 'subscriptions', label: 'Subscriptions', icon: 'utility:contract' },
    { key: 'usage', label: 'Usage & Adoption', icon: 'utility:chart' },
    { key: 'support', label: 'Support', icon: 'utility:case' },
    { key: 'invoices', label: 'Invoices', icon: 'utility:moneybag' },
    { key: 'timeline', label: 'Timeline', icon: 'utility:clock' },
    { key: 'ctas', label: 'CTAs & Playbooks', icon: 'utility:task' },
    { key: 'successplan', label: 'Success Plan', icon: 'utility:target' }
];

export default class Customer360DetailTabs extends LightningElement {

    // ─── Public API ─────────────────────────────────────────────────────────

    /** @type {string} Currently active tab key */
    @api activeTab = 'overview';

    // ─── Getters ────────────────────────────────────────────────────────────

    /**
     * Maps TAB_DEFINITIONS to include computed className based on active state.
     * @returns {Array<Object>} Tab objects with key, label, icon, and className
     */
    get tabs() {
        return TAB_DEFINITIONS.map(tab => ({
            ...tab,
            className: tab.key === this.activeTab
                ? 'detail-tab detail-tab--active'
                : 'detail-tab'
        }));
    }

    // ─── Event Handlers ─────────────────────────────────────────────────────

    /**
     * Handles tab button click and dispatches tabchange event with the selected tab key.
     * @param {Event} event - Click event from tab button
     */
    handleTabClick(event) {
        const tabKey = event.currentTarget.dataset.tab;
        this.dispatchEvent(new CustomEvent('tabchange', {
            detail: { tab: tabKey }
        }));
    }
}