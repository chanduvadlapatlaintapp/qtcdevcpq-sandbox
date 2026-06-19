/**
 * @description Reusable empty state / no-data illustration component for displaying
 *              placeholder content when no records or data are available. Supports
 *              a configurable icon, title, message, and an optional action slot.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360EmptyState extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {String} Main heading text (e.g., "No Data Available") */
    @api title;

    /** @type {String} Descriptive message displayed below the title */
    @api message;

    /** @type {String} SLDS icon name (e.g., "utility:info") */
    @api icon;
}