/**
 * @description App header bar for the Customer 360 application. Dark themed,
 *              fixed at top. Displays user info, current date, and notification bell
 *              with badge count. Dispatches navigation and notification events.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360Header extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {string} CSM name displayed in the header */
    @api userName = '';

    /** @type {number} Badge count shown on the bell icon */
    @api notificationCount = 0;

    /** @type {boolean} Whether the notification dropdown is currently open */
    @api showNotifications = false;

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns today's date formatted as a long readable string (e.g., "March 5, 2026").
     * @returns {string} Formatted date string.
     */
    get currentDate() {
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        }).format(new Date());
    }

    /**
     * @description Determines whether the notification badge should be displayed.
     * @returns {boolean} True if notificationCount is greater than zero.
     */
    get hasNotifications() {
        return this.notificationCount > 0;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles click on the logo/app name. Dispatches a navigate event
     *              to return the user to the dashboard view.
     */
    handleLogoClick() {
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { view: 'dashboard' }
        }));
    }

    /**
     * @description Handles click on the info/about button. Dispatches an
     *              infoclick event for the parent to navigate to the about view.
     */
    handleInfoClick() {
        this.dispatchEvent(new CustomEvent('infoclick'));
    }

    /**
     * @description Handles click on the notification bell icon. Dispatches a
     *              notificationclick event for the parent to toggle the alerts panel.
     */
    handleBellClick() {
        this.dispatchEvent(new CustomEvent('notificationclick'));
    }
}