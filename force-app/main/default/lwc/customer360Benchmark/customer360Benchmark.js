/**
 * @description Peer comparison visualization showing client metrics vs segment averages.
 *              Renders horizontal bar charts with markers for segment average and top quartile,
 *              along with the client's own value bar, for easy benchmarking.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { getHealthColor } from 'c/customer360Utils';

export default class Customer360Benchmark extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @type {Array<Object>} Array of benchmark objects: {metric, clientValue, segmentAvg, segmentMedian, topQuartile, segment} */
    @api benchmarks = [];

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /**
     * @description Returns the segment label from the first benchmark item, or 'Peer' as fallback.
     * @returns {string}
     */
    get segmentLabel() {
        if (this.benchmarks && this.benchmarks.length > 0) {
            return this.benchmarks[0].segment || 'Peer';
        }
        return 'Peer';
    }

    /**
     * @description Maps each benchmark to an enriched object with computed inline styles and tooltips.
     * @returns {Array<Object>}
     */
    get enrichedBenchmarks() {
        if (!this.benchmarks || !this.benchmarks.length) {
            return [];
        }
        return this.benchmarks.map((item, index) => {
            const clientColor = getHealthColor(item.clientValue);
            const diff = item.clientValue - item.segmentAvg;
            const diffLabel = diff >= 0 ? `+${diff} above avg` : `${diff} below avg`;
            return {
                metric: item.metric,
                index: String(index),
                clientValue: item.clientValue,
                segmentAvg: item.segmentAvg,
                segmentMedian: item.segmentMedian,
                topQuartile: item.topQuartile,
                avgStyle: `left: ${item.segmentAvg}%`,
                topStyle: `left: ${item.topQuartile}%`,
                clientBarStyle: `width: ${item.clientValue}%; background: ${clientColor}`,
                clientColorStyle: `color: ${clientColor}`,
                avgTooltip: `Segment Average: ${item.segmentAvg}`,
                topTooltip: `Top Quartile: ${item.topQuartile}`,
                diffLabel,
                isAboveAvg: diff >= 0,
                isBelowAvg: diff < 0
            };
        });
    }

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    /** @type {string|null} Index of the currently hovered benchmark row */
    @track _hoveredIndex = null;

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * @description Handles mouse enter on a benchmark row. Shows the detail tooltip.
     * @param {Event} event
     */
    handleRowHover(event) {
        this._hoveredIndex = event.currentTarget.dataset.index;
    }

    /**
     * @description Handles mouse leave on a benchmark row. Hides the detail tooltip.
     */
    handleRowLeave() {
        this._hoveredIndex = null;
    }
}