/**
 * @description Customer 360 - Health Override component.
 *              Provides a manual health score override form with slider input,
 *              comment field, and override history display.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { formatDate, getHealthColor } from 'c/customer360Utils';

export default class Customer360HealthOverride extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    @api currentScore;
    @api overrideHistory;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    @track overrideScore;
    @track overrideComment = '';

    /** Tracks whether the slider has been initialized from currentScore */
    _initialized = false;

    /**********************************************************************************************
     *
     * Lifecycle Hooks
     *
     ***********************************************************************************************/

    renderedCallback() {
        if (!this._initialized && this.currentScore != null) {
            this.overrideScore = this.currentScore;
            this._initialized = true;
        }
    }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * Inline style for the score display element.
     * @returns {string} CSS color style based on current override score
     */
    get scoreDisplayStyle() {
        return `color: ${getHealthColor(this.overrideScore)}`;
    }

    /**
     * Inline style for the override score in the comparison row.
     * @returns {string} CSS color style based on current override score
     */
    get overrideScoreStyle() {
        return `color: ${getHealthColor(this.overrideScore)}`;
    }

    /**
     * Determines if the submit button should be disabled.
     * Disabled when comment is empty or score has not changed.
     * @returns {boolean}
     */
    get isSubmitDisabled() {
        const commentEmpty = !this.overrideComment || this.overrideComment.trim() === '';
        const scoreUnchanged = Number(this.overrideScore) === Number(this.currentScore);
        return commentEmpty || scoreUnchanged;
    }

    /**
     * Checks if there is override history to display.
     * @returns {boolean}
     */
    get hasHistory() {
        return this.overrideHistory?.length > 0;
    }

    /**
     * Maps override history entries with formatted date and score color.
     * @returns {Array<Object>} Enriched history entries for template rendering
     */
    get historyEntries() {
        if (!this.overrideHistory) {
            return [];
        }
        return this.overrideHistory.map(entry => ({
            ...entry,
            formattedDate: formatDate(entry.date),
            scoreStyle: `color: ${getHealthColor(entry.score)}`
        }));
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * Handles slider input changes.
     * @param {Event} event - Input event from the range slider
     */
    handleSliderChange(event) {
        this.overrideScore = Number(event.target.value);
    }

    /**
     * Handles comment textarea changes.
     * @param {Event} event - Change event from the textarea
     */
    handleCommentChange(event) {
        this.overrideComment = event.target.value;
    }

    /**
     * Handles submit button click. Dispatches healthoverride event
     * with score and comment, then resets the comment field.
     */
    handleSubmit() {
        this.dispatchEvent(new CustomEvent('healthoverride', {
            detail: {
                score: Number(this.overrideScore),
                comment: this.overrideComment
            }
        }));
        this.overrideComment = '';
    }
}