/**
 * @description Dropdown notification panel that appears below the header bell icon.
 *              Shows recent alerts with dismiss and click-to-navigate functionality.
 * @author  Yousef A
 * @date    03/06/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { formatDate } from 'c/customer360Utils';

export default class Customer360NotificationPanel extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array<Object>} Alert objects with id, type, message, accountId, accountName, date, dismissed */
    @api alerts = [];

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns active (non-dismissed) alerts, enriched for display.
     * @returns {Array<Object>}
     */
    get activeAlerts() {
        if (!this.alerts || !this.alerts.length) return [];
        return this.alerts
            .filter(a => !a.dismissed)
            .slice(0, 10)
            .map(alert => ({
                ...alert,
                key: alert.id,
                formattedDate: formatDate(alert.date, 'short'),
                iconName: this._getAlertIcon(alert.type),
                iconVariant: this._getAlertIconVariant(alert.type)
            }));
    }

    /**
     * @description Whether there are any active alerts.
     * @returns {boolean}
     */
    get hasAlerts() {
        return this.activeAlerts.length > 0;
    }

    /**
     * @description Count of active alerts.
     * @returns {number}
     */
    get alertCount() {
        return this.activeAlerts.length;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles clicking an alert row. Navigates to the associated account.
     * @param {Event} event
     */
    handleAlertClick(event) {
        const alertId = event.currentTarget.dataset.alertId;
        const alert = this.alerts.find(a => a.id === alertId);
        if (alert && alert.accountId) {
            this.dispatchEvent(new CustomEvent('alertclick', {
                detail: { accountId: alert.accountId, alertId }
            }));
        }
    }

    /**
     * @description Handles dismissing an alert.
     * @param {Event} event
     */
    handleDismiss(event) {
        event.stopPropagation();
        const alertId = event.currentTarget.dataset.alertId;
        this.dispatchEvent(new CustomEvent('alertdismiss', {
            detail: { alertId }
        }));
    }

    /**
     * @description Handles closing the entire notification panel.
     */
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Returns the appropriate SLDS icon name for an alert type.
     * @param {string} type - Alert type
     * @returns {string}
     */
    _getAlertIcon(type) {
        const iconMap = {
            health_drop: 'utility:warning',
            renewal_upcoming: 'utility:date_input',
            no_contact: 'utility:clock',
            cta_overdue: 'utility:task',
            usage_decline: 'utility:trending_down',
            support_spike: 'utility:cases'
        };
        return iconMap[type] || 'utility:notification';
    }

    /**
     * @description Returns the appropriate icon variant for an alert type.
     * @param {string} type - Alert type
     * @returns {string}
     */
    _getAlertIconVariant(type) {
        const variantMap = {
            health_drop: 'warning',
            renewal_upcoming: '',
            no_contact: 'warning',
            cta_overdue: 'error',
            usage_decline: 'error',
            support_spike: 'warning'
        };
        return variantMap[type] || '';
    }
}