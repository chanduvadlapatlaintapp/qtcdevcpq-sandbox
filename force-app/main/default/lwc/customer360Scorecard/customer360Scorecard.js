/**
 * @description Customer 360 - Health Scorecard component.
 *              Displays a health score factor breakdown table with weighted scores,
 *              score bars, and trend indicators for each health factor.
 * @author  Yousef A
 * @date    2026-03-05
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { getHealthColor } from 'c/customer360Utils';

export default class Customer360Scorecard extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    @api healthData;

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    get overallScore() {
        return this.healthData?.overall || 0;
    }

    get overallStyle() {
        return `color: ${getHealthColor(this.overallScore)}`;
    }

    get factors() {
        if (!this.healthData?.factors) {
            return [];
        }
        return this.healthData.factors.map(factor => {
            const color = getHealthColor(factor.score);
            return {
                ...factor,
                barStyle: `width: ${factor.score}%; background-color: ${color}; border-radius: 3px; height: 100%;`,
                scoreStyle: `color: ${color}`,
                weightLabel: `${Math.round(factor.weight * 100)}%`,
                isUp: factor.trend === 'up',
                isDown: factor.trend === 'down',
                isStable: factor.trend === 'stable'
            };
        });
    }
}