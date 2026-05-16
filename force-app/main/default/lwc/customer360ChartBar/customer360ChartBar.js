/**
 * @description Reusable SVG bar chart component for the Customer 360 application.
 *              Supports horizontal and vertical orientations with configurable data,
 *              colors, and scaling. Renders bars proportionally based on value/maxValue.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

/** Fixed SVG viewBox width used for proportional scaling */
const SVG_WIDTH = 500;

/** Left margin in pixels reserved for labels in horizontal orientation */
const HORIZONTAL_LABEL_MARGIN = 120;

/** Bottom margin in pixels reserved for labels in vertical orientation */
const VERTICAL_LABEL_MARGIN = 40;

/** Padding around the chart edges */
const CHART_PADDING = 10;

/** Ratio of bar thickness to available slot (0.7 = 70% bar, 30% gap) */
const BAR_THICKNESS_RATIO = 0.7;

/** Offset in pixels between end of bar and value label */
const VALUE_LABEL_OFFSET = 6;

export default class Customer360ChartBar extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array<{label: string, value: number, color: string}>} Data points to render as bars */
    @api chartData = [];

    /** @type {string} Bar orientation — 'horizontal' (left-to-right) or 'vertical' (bottom-to-top) */
    @api orientation = 'horizontal';

    /** @type {number} Optional maximum value for the scale axis; auto-calculated from data if not set */
    @api maxValue;

    /** @type {number} Chart height in pixels */
    @api chartHeight = 200;

    /** @type {boolean} Whether to display numeric value labels on each bar */
    _showValues = true;
    @api get showValues() { return this._showValues; }
    set showValues(value) { this._showValues = value; }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns true when chartData contains at least one item.
     * @returns {boolean}
     */
    get hasData() {
        return this.chartData && this.chartData.length > 0;
    }

    /**
     * @description Returns true when chartData is empty or missing, used to show empty state.
     * @returns {boolean}
     */
    get noData() {
        return !this.hasData;
    }

    /**
     * @description Determines whether the chart renders in horizontal mode.
     * @returns {boolean}
     */
    get isHorizontal() {
        return this.orientation !== 'vertical';
    }

    /**
     * @description Computes the effective maximum value for bar scaling.
     *              Uses the provided maxValue if set, otherwise derives from data.
     * @returns {number}
     */
    get computedMaxValue() {
        if (this.maxValue != null && this.maxValue > 0) {
            return this.maxValue;
        }
        if (!this.hasData) {
            return 1;
        }
        const dataMax = Math.max(...this.chartData.map(item => item.value || 0));
        return dataMax > 0 ? dataMax : 1;
    }

    /**
     * @description Builds the SVG viewBox attribute string.
     * @returns {string} viewBox in "0 0 width height" format
     */
    get viewBox() {
        return `0 0 ${SVG_WIDTH} ${this.chartHeight}`;
    }

    /**
     * @description Computes the array of bar objects with all positioning attributes
     *              needed by the template for rendering.
     * @returns {Array<Object>} Bar descriptor objects with x, y, width, height, label
     *                          positions, colors, and display values.
     */
    get bars() {
        if (!this.hasData) {
            return [];
        }
        return this.isHorizontal ? this._buildHorizontalBars() : this._buildVerticalBars();
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Builds bar descriptors for horizontal (left-to-right) orientation.
     *              Labels appear on the left, bars extend to the right proportionally.
     * @returns {Array<Object>} Array of bar descriptor objects.
     */
    _buildHorizontalBars() {
        const data = this.chartData;
        const dataLength = data.length;
        const availableHeight = this.chartHeight - CHART_PADDING * 2;
        const availableWidth = SVG_WIDTH - HORIZONTAL_LABEL_MARGIN - CHART_PADDING;
        const barFullHeight = availableHeight / dataLength;
        const barHeight = barFullHeight * BAR_THICKNESS_RATIO;
        const maxVal = this.computedMaxValue;

        return data.map((item, index) => {
            const slotY = CHART_PADDING + index * barFullHeight;
            const barY = slotY + (barFullHeight - barHeight) / 2;
            const barWidth = ((item.value || 0) / maxVal) * availableWidth;
            const barCenterY = barY + barHeight / 2;

            return {
                key: `bar-${index}`,
                index: String(index),
                label: item.label || '',
                value: item.value || 0,
                color: item.color || '#1589EE',
                displayValue: this._formatValue(item.value),
                // Label positioning — right-aligned at the left margin
                labelX: HORIZONTAL_LABEL_MARGIN - VALUE_LABEL_OFFSET,
                labelY: barCenterY,
                textAnchor: 'end',
                // Bar positioning
                x: HORIZONTAL_LABEL_MARGIN,
                y: barY,
                width: Math.max(barWidth, 0),
                height: barHeight,
                // Value label — to the right of the bar
                valueX: HORIZONTAL_LABEL_MARGIN + barWidth + VALUE_LABEL_OFFSET,
                valueY: barCenterY
            };
        });
    }

    /**
     * @description Builds bar descriptors for vertical (bottom-to-top) orientation.
     *              Labels appear at the bottom, bars grow upward proportionally.
     * @returns {Array<Object>} Array of bar descriptor objects.
     */
    _buildVerticalBars() {
        const data = this.chartData;
        const dataLength = data.length;
        const availableWidth = SVG_WIDTH - CHART_PADDING * 2;
        const availableHeight = this.chartHeight - VERTICAL_LABEL_MARGIN - CHART_PADDING;
        const barFullWidth = availableWidth / dataLength;
        const barWidth = barFullWidth * BAR_THICKNESS_RATIO;
        const maxVal = this.computedMaxValue;

        return data.map((item, index) => {
            const slotX = CHART_PADDING + index * barFullWidth;
            const barX = slotX + (barFullWidth - barWidth) / 2;
            const barHeight = ((item.value || 0) / maxVal) * availableHeight;
            const barY = CHART_PADDING + availableHeight - barHeight;
            const barCenterX = barX + barWidth / 2;

            return {
                key: `bar-${index}`,
                index: String(index),
                label: item.label || '',
                value: item.value || 0,
                color: item.color || '#1589EE',
                displayValue: this._formatValue(item.value),
                // Label positioning — centered below the bar area
                labelX: barCenterX,
                labelY: this.chartHeight - VERTICAL_LABEL_MARGIN / 2,
                textAnchor: 'middle',
                // Bar positioning
                x: barX,
                y: barY,
                width: barWidth,
                height: Math.max(barHeight, 0),
                // Value label — above the bar
                valueX: barCenterX,
                valueY: barY - VALUE_LABEL_OFFSET
            };
        });
    }

    /**
     * @description Formats a numeric value for display on the bar.
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

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles clicks on bar chart bars. Dispatches barclick event.
     * @param {Event} event - click event with data-index attribute
     */
    handleBarClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (this.chartData && this.chartData[index]) {
            const item = this.chartData[index];
            this.dispatchEvent(new CustomEvent('barclick', {
                detail: { label: item.label, value: item.value, index }
            }));
        }
    }
}