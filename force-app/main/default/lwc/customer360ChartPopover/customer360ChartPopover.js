/**
 * @description Lightweight positioned popover component for chart drill-down details.
 *              Displays a title, data breakdown list, and a close button.
 *              Used by the dashboard to show segment/category details when
 *              a chart segment or bar is clicked.
 * @author  Yousef A
 * @date    03/06/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360ChartPopover extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {string} Title text displayed at the top of the popover */
    @api title;

    /** @type {Array<{label: string, value: string, color: string}>} Data items to display */
    @api items = [];

    /** @type {boolean} Whether the popover is visible */
    @api isVisible = false;

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns enriched items with index keys for iteration.
     * @returns {Array<Object>}
     */
    get displayItems() {
        if (!this.items || !this.items.length) {
            return [];
        }
        return this.items.map((item, index) => ({
            ...item,
            key: `popover-item-${index}`,
            dotStyle: item.color ? `background-color: ${item.color}` : 'background-color: #1589EE'
        }));
    }

    /**
     * @description Whether there are items to display.
     * @returns {boolean}
     */
    get hasItems() {
        return this.displayItems.length > 0;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles close button click. Dispatches close event.
     */
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}