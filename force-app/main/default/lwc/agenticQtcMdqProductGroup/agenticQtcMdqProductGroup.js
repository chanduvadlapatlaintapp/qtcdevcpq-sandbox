import { LightningElement, api, track } from 'lwc';

export default class AgenticQtcMdqProductGroup extends LightningElement {
    @api groupData;
    @api quoteStartDate;
    @track applyToAll = false;
    _quantityTimeouts = {};
    _acvTimeouts = {};

    get productName() {
        return this.groupData?.productName || '';
    }

    get productCode() {
        return this.groupData?.productCode || '';
    }

    get cardClass() {
        let cls = 'mdq-card';
        if (this.groupData?.approvalRequired === 'Required') cls += ' needs-approval';
        return cls;
    }

    get dealTermLabel() {
        const count = this.groupData?.segmentCount || 0;
        return 'Proposed ' + count + '-year term';
    }

    get totalYearCols() {
        return (this.groupData?.segmentCount || 0) * 3;
    }

    get displayTotalCost() {
        const val = this.groupData?.totalCost || 0;
        return '$' + Number(val).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    get yearColumns() {
        const segments = this.groupData?.segments || [];
        let cumulativeTcv = 0;

        return segments.map((seg, idx) => {
            cumulativeTcv += (seg.netPrice || 0);

            const startStr = seg.startDate
                ? new Date(seg.startDate + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                : '';
            const endStr = seg.endDate
                ? new Date(seg.endDate + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                : '';
            const dateRange = startStr && endStr ? startStr + ' - ' + endStr : startStr;

            const prevAcv = idx > 0 ? (segments[idx - 1].acv || 0) : 0;
            const thisAcv = seg.acv || 0;
            const yoyUplift = (idx > 0 && prevAcv !== 0)
                ? ((thisAcv - prevAcv) / prevAcv * 100)
                : 0;

            return {
                lineId: seg.id,
                segmentLabel: seg.segmentLabel || '',
                dateRange,
                keyPrice: 'p-' + seg.id,
                keyQty: 'q-' + seg.id,
                keyAcv: 'a-' + seg.id,
                keyTotal: 't-' + seg.id,
                displayMonthlySalePrice: this._fmtCurrency(seg.customerSalePricePerMonth),
                displayQuantity: seg.quantity != null ? Number(seg.quantity).toLocaleString() : '0',
                quantity: seg.quantity,
                displayAcv: this._fmtCurrency(seg.acv),
                acv: seg.acv,
                acvChange: seg.acvChange,
                displayAcvChange: this._fmtCurrency(seg.acvChange),
                displayTcv: this._fmtCurrency(cumulativeTcv),
                tcv: cumulativeTcv,
                discount: seg.discount,
                displayDiscount: (seg.discount != null ? Number(seg.discount).toFixed(2) : '0.00') + ' %',
                yoyUplift,
                displayYoyUplift: yoyUplift.toFixed(2) + ' %',
                displayTotal: this._fmtCurrency(seg.totalCost || seg.netPrice),
                isEditable: !seg.isLocked,
                isLocked: seg.isLocked
            };
        });
    }

    get detailRows() {
        const cols = this.yearColumns;
        return [
            this._buildDetailRow('ACV', cols, c => this._fmtCurrency(c.acv)),
            this._buildDetailRow('TCV', cols, c => c.displayTcv),
            this._buildDetailRow('Discount %', cols, c => c.displayDiscount),
            this._buildDetailRow('ACV Change', cols, c => this._fmtCurrency(c.acvChange)),
            this._buildDetailRow('YoY Uplift', cols, c => c.displayYoyUplift)
        ];
    }

    _buildDetailRow(label, cols, valueFn) {
        const key = 'dr-' + label.replace(/\s+/g, '-').toLowerCase();
        return {
            key,
            label,
            values: cols.map((c, i) => ({
                key: key + '-' + i,
                display: valueFn(c)
            }))
        };
    }

    _fmtCurrency(val) {
        const n = Number(val || 0);
        if (Math.abs(n) >= 1000000) {
            return '$' + (n / 1000000).toFixed(2) + 'M';
        }
        return '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    // BUG FIX #5 (same pattern): Clear pending debounce timers on destroy.
    disconnectedCallback() {
        Object.values(this._quantityTimeouts).forEach(t => clearTimeout(t));
        Object.values(this._acvTimeouts).forEach(t => clearTimeout(t));
        this._quantityTimeouts = {};
        this._acvTimeouts = {};
    }

    handleApplyToAllChange(event) {
        this.applyToAll = event.target.checked;
    }

    handleSegmentQuantityChange(event) {
        const lineId = event.target.dataset.lineId;
        const segmentKey = this.groupData?.segmentKey;
        clearTimeout(this._quantityTimeouts[lineId]);
        const qty = Number(event.target.value);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._quantityTimeouts[lineId] = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                detail: { lineId, quantity: qty, segmentKey, applyToAll: this.applyToAll }
            }));
        }, 500);
    }

    handleSegmentAcvChange(event) {
        const lineId = event.target.dataset.lineId;
        clearTimeout(this._acvTimeouts[lineId]);
        const acv = Number(event.target.value);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._acvTimeouts[lineId] = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('acvchange', {
                detail: { lineId, acvChange: acv }
            }));
        }, 500);
    }
}