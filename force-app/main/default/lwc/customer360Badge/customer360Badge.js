/**
 * @description Reusable colored badge/pill component for displaying status indicators,
 *              labels, and categorization tags with variant-based color schemes.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360Badge extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {String} Badge display text */
    @api label;

    /** @type {String} Color variant: 'success', 'warning', 'error', 'info', 'purple', 'default' */
    @api variant = 'default';

    /** @type {String} Size variant: 'small' or 'default' */
    @api size = 'default';

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Computes the CSS class string based on the current variant and size.
     * @returns {String} Space-separated CSS class names for the badge element.
     */
    get badgeClass() {
        return `badge badge-${this.variant} badge-${this.size}`;
    }
}