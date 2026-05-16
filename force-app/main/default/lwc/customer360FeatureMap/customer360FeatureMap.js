/**
 * @description Feature Enablement Map for Customer 360.
 *              Shows entitled vs enabled features per product with whitespace analysis.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { generateFeatureMap } from 'c/customer360MockData';

export default class Customer360FeatureMap extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _featureData = [];
    _isLoaded = false;

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    // ─── Getters ──────────────────────────────────────────────────────────────
    get hasData() {
        return this._featureData && this._featureData.length > 0;
    }

    get showEmpty() {
        return this._isLoaded && !this.hasData;
    }

    get featureData() {
        return this._featureData;
    }

    get totalWhitespace() {
        return this._featureData.reduce((sum, p) => sum + p.whitespaceCount, 0);
    }

    get totalEntitled() {
        return this._featureData.reduce((sum, p) => sum + p.totalEntitled, 0);
    }

    get totalEnabled() {
        return this._featureData.reduce((sum, p) => sum + p.totalEnabled, 0);
    }

    get enablementRate() {
        const entitled = this.totalEntitled;
        if (!entitled) return '0%';
        return Math.round((this.totalEnabled / entitled) * 100) + '%';
    }

    get isLoaded() {
        return this._isLoaded;
    }

    // ─── Private Methods ──────────────────────────────────────────────────────
    _loadData() {
        try {
            const raw = generateFeatureMap(this.accountId);
            this._featureData = raw.map(product => ({
                ...product,
                key: product.product,
                enablementPercent: product.totalEntitled > 0
                    ? Math.round((product.totalEnabled / product.totalEntitled) * 100)
                    : 0,
                features: product.features.map((f, idx) => ({
                    ...f,
                    key: `${product.product}-${idx}`,
                    statusIcon: f.enabled ? 'utility:success' : (f.entitled ? 'utility:dash' : 'utility:close'),
                    statusClass: f.enabled ? 'c360-fm__status--enabled' : (f.entitled ? 'c360-fm__status--entitled' : 'c360-fm__status--not-entitled'),
                    statusLabel: f.enabled ? 'Enabled' : (f.entitled ? 'Not Enabled' : 'Not Entitled'),
                    adoptionWidth: `width: ${f.adoption}%`,
                    adoptionLabel: f.adoption > 0 ? f.adoption + '%' : '-',
                    adoptionBarClass: f.adoption >= 70 ? 'c360-fm__bar-fill c360-fm__bar-fill--good' :
                                     f.adoption >= 40 ? 'c360-fm__bar-fill c360-fm__bar-fill--fair' :
                                     f.adoption > 0 ? 'c360-fm__bar-fill c360-fm__bar-fill--low' : 'c360-fm__bar-fill'
                }))
            }));
        } catch (e) {
            this._featureData = [];
        }
        this._isLoaded = true;
    }
}