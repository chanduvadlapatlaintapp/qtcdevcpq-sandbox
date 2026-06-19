/**
 * @description Customer 360 - Health Trend component.
 *              Renders an SVG line chart showing health score trend over 12 months
 *              with color-coded zones, data points, and month labels.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';

/** Chart area constants */
const CHART_X_MIN = 40;
const CHART_X_MAX = 480;
const CHART_WIDTH = CHART_X_MAX - CHART_X_MIN;
const CHART_Y_MIN = 0;
const CHART_Y_MAX = 220;
const MAX_SCORE = 100;

export default class Customer360HealthTrend extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    @api history;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /** @type {Object|null} Currently hovered data point for custom tooltip */
    @track _hoveredPoint = null;

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * Computes SVG polyline points string from history data.
     * Maps each data point to "x,y" pairs separated by spaces.
     * @returns {string} Space-separated "x,y" coordinate pairs
     */
    get linePoints() {
        if (!this.history || this.history.length === 0) {
            return '';
        }
        const points = this.history.map((entry, index) => {
            const x = this._calculateX(index, this.history.length);
            const y = this._calculateY(entry.score);
            return `${x},${y}`;
        });
        return points.join(' ');
    }

    /**
     * Computes data point objects for SVG rendering.
     * Each point includes coordinates, label, and tooltip text.
     * @returns {Array<Object>} Array of point objects for template iteration
     */
    get dataPoints() {
        if (!this.history || this.history.length === 0) {
            return [];
        }
        return this.history.map((entry, index) => {
            const x = this._calculateX(index, this.history.length);
            const y = this._calculateY(entry.score);
            return {
                key: `${entry.month}-${entry.year}`,
                index: String(index),
                x: String(x),
                y: String(y),
                score: entry.score,
                monthLabel: entry.monthLabel,
                tooltip: `${entry.monthLabel} ${entry.year}: ${entry.score}`
            };
        });
    }

    /**
     * @description Whether a tooltip should be shown (a point is hovered).
     * @returns {boolean}
     */
    get showTooltip() {
        return this._hoveredPoint != null;
    }

    /**
     * @description Returns the tooltip text for the hovered point.
     * @returns {string}
     */
    get tooltipText() {
        return this._hoveredPoint?.tooltip || '';
    }

    /**
     * @description Returns SVG x attribute for tooltip positioning.
     * @returns {string}
     */
    get tooltipX() {
        return this._hoveredPoint?.x || '0';
    }

    /**
     * @description Returns SVG y attribute for tooltip positioning (above the point).
     * @returns {string}
     */
    get tooltipY() {
        const y = parseFloat(this._hoveredPoint?.y || '0');
        return String(y - 16);
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles mouse enter on a data point. Shows the custom tooltip.
     * @param {Event} event
     */
    handlePointHover(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const points = this.dataPoints;
        if (points[index]) {
            this._hoveredPoint = points[index];
        }
    }

    /**
     * @description Handles mouse leave on a data point. Hides the custom tooltip.
     */
    handlePointLeave() {
        this._hoveredPoint = null;
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * Calculate X coordinate for a data point.
     * @param {number} index - Index of the point in the array
     * @param {number} total - Total number of data points
     * @returns {number} X coordinate within the chart area
     */
    _calculateX(index, total) {
        if (total <= 1) {
            return CHART_X_MIN + CHART_WIDTH / 2;
        }
        return CHART_X_MIN + (index / (total - 1)) * CHART_WIDTH;
    }

    /**
     * Calculate Y coordinate for a score value.
     * Y is inverted: higher scores are at the top (lower Y values).
     * @param {number} score - Health score (0-100)
     * @returns {number} Y coordinate within the chart area
     */
    _calculateY(score) {
        return CHART_Y_MAX - (score / MAX_SCORE * (CHART_Y_MAX - CHART_Y_MIN));
    }
}