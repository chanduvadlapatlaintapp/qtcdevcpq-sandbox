/**
 * @description Notification and alerts sidebar panel for the Customer 360 application.
 *              Displays a filterable list of alert cards with dismiss and click-through
 *              capabilities. Each alert shows type, title, description, and relative
 *              timestamp. Dismissed alerts are hidden from view.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { formatDate } from 'c/customer360Utils';

export default class Customer360AlertsPanel extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /**
     * @type {Array<Object>} Array of alert objects.
     * Each alert: { id, type, label, icon, color, bgColor, title, description,
     *               timestamp, accountId, accountName, dismissed }
     */
    @api alerts = [];

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns alerts that have not been dismissed, enriched with computed
     *              style properties and relative timestamp for display.
     * @returns {Array<Object>} Mapped array of visible alert objects.
     */
    get visibleAlerts() {
        if (!this.alerts || !this.alerts.length) {
            return [];
        }
        return this.alerts
            .filter(alert => !alert.dismissed)
            .map(alert => ({
                ...alert,
                relativeTime: formatDate(alert.timestamp, 'relative'),
                cardStyle: `background-color: ${alert.bgColor}; border-left-color: ${alert.color};`,
                iconStyle: `--sds-c-icon-color-foreground-default: ${alert.color};`,
                typeStyle: `color: ${alert.color};`
            }));
    }

    /**
     * @description Returns the count of non-dismissed alerts.
     * @returns {number}
     */
    get activeAlertCount() {
        if (!this.alerts || !this.alerts.length) {
            return 0;
        }
        return this.alerts.filter(alert => !alert.dismissed).length;
    }

    /**
     * @description Determines if there are any visible (non-dismissed) alerts to display.
     * @returns {boolean}
     */
    get hasAlerts() {
        return this.activeAlertCount > 0;
    }

    /**
     * @description Inverse of hasAlerts. Used to conditionally render the empty state.
     * @returns {boolean}
     */
    get noAlerts() {
        return !this.hasAlerts;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles the dismiss button click on an alert card. Stops event
     *              propagation to prevent the card click handler from firing, then
     *              dispatches an alertdismiss event with the alert's ID.
     * @param {Event} event - Click event from the dismiss button.
     */
    handleDismiss(event) {
        event.stopPropagation();
        const alertId = event.currentTarget.dataset.alertId;
        this.dispatchEvent(new CustomEvent('alertdismiss', {
            detail: { alertId }
        }));
    }

    /**
     * @description Handles click on an alert card body. Dispatches an alertclick
     *              event with the associated account ID for navigation.
     * @param {Event} event - Click event from the alert card.
     */
    handleAlertClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.dispatchEvent(new CustomEvent('alertclick', {
            detail: { accountId }
        }));
    }
}