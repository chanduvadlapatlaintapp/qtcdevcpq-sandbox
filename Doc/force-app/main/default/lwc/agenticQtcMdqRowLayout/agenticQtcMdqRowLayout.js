import { LightningElement, api, track } from 'lwc';

export default class AgenticQtcMdqRowLayout extends LightningElement {
    @api groupData;
    @api quoteStartDate;

    @track isExpanded = true;
    @track applyToAll = false;

    _quantityTimeouts = {};
    _acvTimeouts = {};

    get productHeader() {
        const name = this.groupData?.productName || 'Unknown Product';
        const code = this.groupData?.productCode;
        return code ? `${name} (${code})` : name;
    }

    get chevronIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get segmentCount() {
        return this.groupData?.segmentCount || 0;
    }

    get dealTermLabel() {
        return `${this.segmentCount}-year term`;
    }

    get displayTotalCost() {
        const val = this.groupData?.totalCost || 0;
        return this._fmtCurrency(val);
    }

    get cardClass() {
        let cls = 'row-card';
        if (this.groupData?.approvalRequired === 'Required') cls += ' needs-approval';
        return cls;
    }

    get periodRows() {
        const segments = this.groupData?.segments || [];
        return segments.map((seg, idx) => {
            const prevQty = idx > 0 ? (segments[idx - 1].quantity || 0) : (seg.priorQuantity || seg.quantity || 0);
            const qty = seg.quantity || 0;

            let rampDirection = 'same';
            if (idx > 0) {
                if (qty > prevQty) rampDirection = 'up';
                else if (qty < prevQty) rampDirection = 'down';
            }

            const prevAcv = idx > 0 ? (segments[idx - 1].acv || 0) : 0;
            const thisAcv = seg.acv || 0;
            const renewalUplift = (idx > 0 && prevAcv !== 0)
                ? ((thisAcv - prevAcv) / prevAcv * 100)
                : 0;

            const startDate = seg.startDate ? new Date(seg.startDate + 'T00:00:00') : null;
            const endDate = seg.endDate ? new Date(seg.endDate + 'T00:00:00') : null;

            const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            let dateRange = '';
            let duration = '';
            if (startDate && endDate) {
                dateRange = `${monthNames[startDate.getMonth()]} ${startDate.getFullYear()} - ${monthNames[endDate.getMonth()]} ${endDate.getFullYear()}`;
                const months = (endDate.getFullYear() - startDate.getFullYear()) * 12 + (endDate.getMonth() - startDate.getMonth());
                duration = months > 0 ? `${months}mo` : '';
            }

            const discount = seg.discount || 0;
            // SBQQ__NetPrice__c — total line net for this segment (amendment)
            const amendmentNetPrice = seg.netPrice != null ? seg.netPrice : (seg.totalCost || 0);
            // SBQQ__CustomerPrice__c preferred for "monthly sale"; fallback SBQQ__ListPrice__c
            const monthlySalePrice = this._monthlySalePrice(seg);
            const computedAcv = monthlySalePrice * qty * 12;
            // ACV__c from quote line; if unset/zero but pricing implies annual value, show computed
            const lineAcv = this._resolveAcvDisplay(seg.acv, computedAcv);
            // ACV_Change__c
            const lineAcvChange = seg.acvChange;

            return {
                key: 'pr-' + seg.id,
                lineId: seg.id,
                periodLabel: `Year ${idx + 1}`,
                dateRange,
                duration,
                periodSubLabel: dateRange + (duration ? ` · ${duration}` : ''),
                verifiedQty: seg.priorQuantity != null ? Number(seg.priorQuantity).toLocaleString() : '--',
                quantity: qty,
                displayQuantity: Number(qty).toLocaleString(),
                monthlySalePrice,
                displayMonthlySalePrice: this._fmtCurrency(monthlySalePrice),
                discount,
                displayDiscount: discount.toFixed(1),
                renewalUplift,
                displayRenewalUplift: renewalUplift.toFixed(1),
                amendmentNetPrice,
                displayAmendmentNetPrice: this._fmtCurrency(amendmentNetPrice),
                displayAcv: this._fmtCurrency(lineAcv),
                displayAcvChange: this._fmtAcvChange(lineAcvChange),
                rampDirection,
                rampArrowClass: 'ramp-arrow ' + rampDirection,
                isEditable: !seg.isLocked,
                isFirst: idx === 0
            };
        });
    }

    // BUG FIX #5: Clear all pending debounce timers when component is destroyed.
    // Without this, stale timeout callbacks fire after unmount and may dispatch
    // events into a dead component tree or cause NaN display values on re-mount.
    disconnectedCallback() {
        Object.values(this._quantityTimeouts).forEach(t => clearTimeout(t));
        Object.values(this._acvTimeouts).forEach(t => clearTimeout(t));
        this._quantityTimeouts = {};
        this._acvTimeouts = {};
    }

    toggleExpand() {
        this.isExpanded = !this.isExpanded;
    }

    handleApplyToAllChange(event) {
        this.applyToAll = event.target.checked;
    }

    handleQuantityChange(event) {
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

    handleDiscountChange(event) {
        const lineId = event.target.dataset.lineId;
        clearTimeout(this._acvTimeouts[lineId]);
        const val = Number(event.target.value);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._acvTimeouts[lineId] = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('acvchange', {
                detail: { lineId, acvChange: val }
            }));
        }, 500);
    }

    _monthlySalePrice(seg) {
        const cp = seg.customerPrice;
        const lp = seg.listPrice;
        const nCp = cp != null && cp !== undefined ? Number(cp) : null;
        if (nCp != null && !Number.isNaN(nCp) && nCp !== 0) {
            return nCp;
        }
        return Number(lp || 0);
    }

    _resolveAcvDisplay(acvField, computedAcv) {
        if (acvField == null || acvField === undefined || Number.isNaN(Number(acvField))) {
            return computedAcv;
        }
        const sv = Number(acvField);
        if (sv === 0 && computedAcv > 0) {
            return computedAcv;
        }
        return sv;
    }

    _fmtCurrency(val) {
        const n = Number(val || 0);
        if (Math.abs(n) >= 1000000) {
            return '$' + (n / 1000000).toFixed(2) + 'M';
        }
        return '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    _fmtAcvChange(val) {
        if (val == null) return '--';
        const n = Number(val);
        const sign = n < 0 ? '-' : (n > 0 ? '+' : '');
        const abs = '$' + Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
        return sign + abs;
    }
}