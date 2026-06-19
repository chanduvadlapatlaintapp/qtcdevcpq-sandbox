/**
 * @description Reusable SVG donut/ring chart component for the Customer 360 application.
 *              Renders segments as concentric circle strokes using stroke-dasharray/offset
 *              math. Supports configurable center labels and an optional color legend.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

/** Ratio of the donut radius to half the chart size, leaving room for the stroke */
const RADIUS_RATIO = 0.35;

/** Ratio of the stroke width to the chart size */
const STROKE_RATIO = 0.12;

/** Vertical offset between center value and center label text */
const CENTER_TEXT_GAP = 10;

export default class Customer360ChartDonut extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array<{label: string, value: number, color: string}>} Segment data for the donut */
    @api segments = [];

    /** @type {string} Label text displayed in the center of the donut (e.g., "Total") */
    @api centerLabel;

    /** @type {string} Value text displayed in the center of the donut (e.g., "28") */
    @api centerValue;

    /** @type {number} Diameter of the donut chart in pixels */
    @api chartSize = 200;

    /** @type {boolean} Whether to render the color legend below the chart */
    _showLegend = true;
    @api get showLegend() { return this._showLegend; }
    set showLegend(value) { this._showLegend = value; }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns true when segments contain at least one item with a positive value.
     * @returns {boolean}
     */
    get hasData() {
        return this.segments && this.segments.length > 0;
    }

    /**
     * @description Builds the SVG viewBox attribute string based on chartSize.
     * @returns {string} viewBox in "0 0 size size" format
     */
    get viewBox() {
        return `0 0 ${this.chartSize} ${this.chartSize}`;
    }

    /**
     * @description Computes the center coordinate (cx, cy) of the SVG.
     * @returns {number}
     */
    get center() {
        return this.chartSize / 2;
    }

    /**
     * @description Computes the donut ring radius based on chart size.
     * @returns {number}
     */
    get radius() {
        return this.chartSize * RADIUS_RATIO;
    }

    /**
     * @description Computes the stroke width of the donut ring based on chart size.
     * @returns {number}
     */
    get strokeWidth() {
        return this.chartSize * STROKE_RATIO;
    }

    /**
     * @description Returns the SVG transform to rotate arcs so they start from the top (12 o'clock).
     * @returns {string} SVG rotate transform string
     */
    get rotateTransform() {
        return `rotate(-90, ${this.center}, ${this.center})`;
    }

    /**
     * @description Computes the Y position for the center value text,
     *              shifted slightly above center to make room for the label below.
     * @returns {number}
     */
    get centerValueY() {
        if (this.centerLabel) {
            return this.center - CENTER_TEXT_GAP / 2;
        }
        return this.center;
    }

    /**
     * @description Computes the Y position for the center label text,
     *              shifted below the center value.
     * @returns {number}
     */
    get centerLabelY() {
        return this.center + CENTER_TEXT_GAP + CENTER_TEXT_GAP / 2;
    }

    /**
     * @description Computes the total of all segment values.
     * @returns {number}
     */
    get totalValue() {
        if (!this.hasData) {
            return 0;
        }
        return this.segments.reduce((sum, segment) => sum + (segment.value || 0), 0);
    }

    /**
     * @description Builds an array of arc descriptor objects used by the template.
     *              Each arc is a circle element whose stroke-dasharray and stroke-dashoffset
     *              control the visible arc length and starting position.
     * @returns {Array<Object>} Arc descriptors with key, color, dashArray, and dashOffset.
     */
    get arcs() {
        if (!this.hasData || this.totalValue === 0) {
            return [];
        }

        const circumference = 2 * Math.PI * this.radius;
        const total = this.totalValue;
        let cumulativeOffset = 0;

        return this.segments.map((segment, index) => {
            const arcLength = ((segment.value || 0) / total) * circumference;
            const dashOffset = -cumulativeOffset;
            cumulativeOffset += arcLength;

            return {
                key: `arc-${index}`,
                index: String(index),
                label: segment.label || '',
                value: segment.value || 0,
                color: segment.color || '#1589EE',
                dashArray: `${arcLength} ${circumference}`,
                dashOffset: String(dashOffset)
            };
        });
    }

    /**
     * @description Builds legend item descriptors from segment data.
     *              Each item includes a colored dot style, label, and formatted value.
     * @returns {Array<Object>} Legend item descriptors.
     */
    get legendItems() {
        if (!this.hasData) {
            return [];
        }

        return this.segments.map((segment, index) => ({
            key: `legend-${index}`,
            index: String(index),
            label: segment.label || '',
            displayValue: this._formatValue(segment.value),
            dotStyle: `background-color: ${segment.color || '#1589EE'}`
        }));
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles clicks on donut segments. Dispatches segmentclick event.
     * @param {Event} event - click event with data-index attribute
     */
    handleSegmentClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (this.segments && this.segments[index]) {
            const segment = this.segments[index];
            this.dispatchEvent(new CustomEvent('segmentclick', {
                detail: { label: segment.label, value: segment.value, index }
            }));
        }
    }

    /**
     * @description Handles clicks on legend items. Dispatches segmentclick event.
     * @param {Event} event - click event with data-index attribute
     */
    handleLegendClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (this.segments && this.segments[index]) {
            const segment = this.segments[index];
            this.dispatchEvent(new CustomEvent('segmentclick', {
                detail: { label: segment.label, value: segment.value, index }
            }));
        }
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Formats a numeric value for display in the legend.
     *              Returns an empty string for null/undefined values.
     * @param {number} value - The raw numeric value.
     * @returns {string} Formatted display string.
     */
    _formatValue(value) {
        if (value == null) {
            return '';
        }
        return String(value);
    }
}