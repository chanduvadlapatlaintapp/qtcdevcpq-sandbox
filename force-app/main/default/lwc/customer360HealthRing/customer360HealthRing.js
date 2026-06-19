/**
 * @description SVG circular progress indicator component for the Customer 360 application.
 *              Renders a ring chart that visually represents a health score (0-100) with
 *              color-coded thresholds and an animated stroke transition on load.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { getHealthColor } from 'c/customer360Utils';

/** Stroke width lookup by size variant */
const STROKE_WIDTHS = {
    small: 4,
    medium: 6,
    large: 8
};

/** Pixel dimensions lookup by size variant */
const SIZE_MAP = {
    small: 48,
    medium: 80,
    large: 120
};

/** Font size lookup by size variant */
const FONT_SIZE_MAP = {
    small: 12,
    medium: 20,
    large: 32
};

export default class Customer360HealthRing extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {number} Health score value between 0 and 100 */
    @api score = 0;

    /** @type {string} Ring size variant: 'small' (48px), 'medium' (80px), 'large' (120px) */
    @api size = 'medium';

    /** @type {boolean} Whether to display the score number in the center of the ring */
    _showLabel = true;
    @api get showLabel() { return this._showLabel; }
    set showLabel(value) { this._showLabel = value; }

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /** @type {boolean} Controls the animated stroke transition after initial render */
    _isAnimated = false;

    /**********************************************************************************************
     *
     * Lifecycle Hooks
     *
     ***********************************************************************************************/

    /**
     * @description Triggers the ring animation after the component renders in the DOM.
     *              Uses a short delay to ensure the initial state (full offset) is painted
     *              before transitioning to the target offset.
     */
    renderedCallback() {
        if (!this._isAnimated) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this._isAnimated = true;
            }, 50);
        }
    }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Pixel dimension of the SVG based on the size prop.
     * @returns {number}
     */
    get ringSize() {
        return SIZE_MAP[this.size] || SIZE_MAP.medium;
    }

    /**
     * @description Stroke width based on the size prop.
     * @returns {number}
     */
    get strokeWidth() {
        return STROKE_WIDTHS[this.size] || STROKE_WIDTHS.medium;
    }

    /**
     * @description Radius of the ring circles, accounting for stroke width.
     * @returns {number}
     */
    get radius() {
        return (this.ringSize - this.strokeWidth) / 2;
    }

    /**
     * @description Full circumference of the ring circle.
     * @returns {number}
     */
    get circumference() {
        return 2 * Math.PI * this.radius;
    }

    /**
     * @description Stroke dash offset that controls how much of the ring is filled.
     *              Before animation starts, returns full circumference (empty ring).
     * @returns {number}
     */
    get dashOffset() {
        if (!this._isAnimated) {
            return this.circumference;
        }
        const clampedScore = Math.min(Math.max(this.score, 0), 100);
        return this.circumference * (1 - clampedScore / 100);
    }

    /**
     * @description Hex color for the ring based on the health score thresholds.
     * @returns {string}
     */
    get ringColor() {
        return getHealthColor(this.score);
    }

    /**
     * @description SVG viewBox attribute string.
     * @returns {string}
     */
    get viewBox() {
        return `0 0 ${this.ringSize} ${this.ringSize}`;
    }

    /**
     * @description Center coordinate for both cx and cy of the SVG circles.
     * @returns {number}
     */
    get center() {
        return this.ringSize / 2;
    }

    /**
     * @description Score text to display in the center, or empty if showLabel is false.
     * @returns {string}
     */
    get scoreDisplay() {
        return this.showLabel ? String(Math.round(this.score)) : '';
    }

    /**
     * @description Font size for the center score text based on the size prop.
     * @returns {number}
     */
    get fontSize() {
        return FONT_SIZE_MAP[this.size] || FONT_SIZE_MAP.medium;
    }

    /**
     * @description Inline style for the outer container to set width and height.
     * @returns {string}
     */
    get containerStyle() {
        return `width: ${this.ringSize}px; height: ${this.ringSize}px;`;
    }

    /**
     * @description Inline style for the background (track) circle.
     * @returns {string}
     */
    get trackStyle() {
        return `fill: none; stroke: #e5e5e5; stroke-width: ${this.strokeWidth};`;
    }

    /**
     * @description Inline style for the foreground (progress) circle with dash array/offset.
     * @returns {string}
     */
    get progressStyle() {
        return [
            'fill: none',
            `stroke: ${this.ringColor}`,
            `stroke-width: ${this.strokeWidth}`,
            `stroke-dasharray: ${this.circumference}`,
            `stroke-dashoffset: ${this.dashOffset}`,
            'stroke-linecap: round',
            `transform: rotate(-90deg)`,
            `transform-origin: ${this.center}px ${this.center}px`
        ].join('; ') + ';';
    }

    /**
     * @description Inline style for the center score text element.
     * @returns {string}
     */
    get textStyle() {
        return [
            `font-size: ${this.fontSize}px`,
            'font-weight: 700',
            `fill: ${this.ringColor}`,
            'dominant-baseline: central',
            'text-anchor: middle'
        ].join('; ') + ';';
    }
}