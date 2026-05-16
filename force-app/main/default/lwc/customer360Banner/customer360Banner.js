/**
 * @description Customer 360 Banner - Detail page header banner displaying account info,
 *              health ring, and stat pills. Provides navigation back to portfolio
 *              and quick-action buttons for logging activity and creating CTAs.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

import { LightningElement, api } from 'lwc';
import { formatCurrency, getHealthColor } from 'c/customer360Utils';
import { RISK_LEVELS } from 'c/customer360Constants';

export default class Customer360Banner extends LightningElement {

    // ─── Public API ─────────────────────────────────────────────────────────

    /** @type {Object} Account data object with id, name, industry, segment, healthScore, healthTrend, arr, nps, openCtas, products, daysSinceContact, renewalDate, riskLevel */
    @api account = {};

    // ─── Getters ────────────────────────────────────────────────────────────

    /**
     * Generates initials from the first letter of the first two words in the account name.
     * @returns {string} Up to two character initials (e.g., "MF" for "Morrison & Foerster")
     */
    get initials() {
        if (!this.account?.name) return '';
        const words = this.account.name.split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0) return '';
        if (words.length === 1) return words[0].charAt(0).toUpperCase();
        return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
    }

    /**
     * Formats the ARR value as compact currency (e.g., "$1.2M").
     * @returns {string} Formatted currency string
     */
    get formattedArr() {
        return formatCurrency(this.account?.arr, true);
    }

    /**
     * Returns the number of products as a displayable value.
     * @returns {number|string} Product count or 0
     */
    get productCount() {
        if (!this.account?.products) return 0;
        if (Array.isArray(this.account.products)) {
            return this.account.products.length;
        }
        return this.account.products;
    }

    /**
     * Maps the account segment to a badge variant.
     * @returns {string} Badge variant: 'info' for Enterprise, 'purple' for Mid-Market, 'default' for SMB
     */
    get segmentVariant() {
        const segment = this.account?.segment;
        if (segment === 'Enterprise') return 'info';
        if (segment === 'Mid-Market') return 'purple';
        return 'default';
    }

    /**
     * Returns the human-readable risk label from RISK_LEVELS constant.
     * @returns {string} Risk label (e.g., "Low", "High", "Critical")
     */
    get riskLabel() {
        const level = this.account?.riskLevel?.toUpperCase();
        if (level && RISK_LEVELS[level]) {
            return RISK_LEVELS[level].label;
        }
        return 'Unknown';
    }

    /**
     * Returns the badge variant for the current risk level.
     * @returns {string} Badge variant (e.g., "success", "warning", "error")
     */
    get riskVariant() {
        const level = this.account?.riskLevel?.toUpperCase();
        if (level && RISK_LEVELS[level]) {
            return RISK_LEVELS[level].variant;
        }
        return 'default';
    }

    /**
     * Builds the CSS class for the health trend indicator.
     * @returns {string} CSS class string with trend color modifier
     */
    get trendClass() {
        const trend = this.account?.healthTrend;
        if (trend === 'up') return 'banner__trend banner__trend--up';
        if (trend === 'down') return 'banner__trend banner__trend--down';
        return 'banner__trend banner__trend--stable';
    }

    /**
     * Returns a descriptive label for the health trend direction.
     * @returns {string} Trend label (e.g., "Trending Up", "Trending Down", "Stable")
     */
    get trendLabel() {
        const trend = this.account?.healthTrend;
        if (trend === 'up') return 'Trending Up';
        if (trend === 'down') return 'Trending Down';
        return 'Stable';
    }

    /**
     * Whether the health trend is upward.
     * @returns {boolean}
     */
    get isTrendUp() {
        return this.account?.healthTrend === 'up';
    }

    /**
     * Whether the health trend is downward.
     * @returns {boolean}
     */
    get isTrendDown() {
        return this.account?.healthTrend === 'down';
    }

    /**
     * Builds the CSS class for the "Last Contact" stat value.
     * Turns red if daysSinceContact exceeds 30.
     * @returns {string} CSS class string
     */
    get contactClass() {
        const days = this.account?.daysSinceContact;
        if (days > 30) {
            return 'banner__stat-value banner__stat-value--overdue';
        }
        return 'banner__stat-value';
    }

    // ─── Event Handlers ─────────────────────────────────────────────────────

    /**
     * Dispatches navigate event to return to the portfolio dashboard.
     */
    handleBack() {
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { view: 'dashboard' }
        }));
    }

    /**
     * Dispatches logactivity event when Log Activity button is clicked.
     */
    handleLogActivity() {
        this.dispatchEvent(new CustomEvent('logactivity'));
    }

    /**
     * Dispatches createcta event when Create CTA button is clicked.
     */
    handleCreateCta() {
        this.dispatchEvent(new CustomEvent('createcta'));
    }
}