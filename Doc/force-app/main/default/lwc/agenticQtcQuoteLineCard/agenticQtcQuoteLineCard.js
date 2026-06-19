import { LightningElement, api, track } from 'lwc';

export default class AgenticQtcQuoteLineCard extends LightningElement {
    @api lineData;
    @api quoteStartDate;
    @track isExpanded = false;
    _quantityTimeout;
    _acvTimeout;

    get cardClass() {
        let cls = 'line-card';
        if (this.isExpanded) cls += ' expanded';
        if (this.lineData?.isLocked) cls += ' locked';
        if (this.lineData?.approvalRequired === 'Required') cls += ' needs-approval';
        return cls;
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get displayQuantity() {
        return this.lineData?.quantity != null ? Number(this.lineData.quantity).toLocaleString() : '0';
    }

    get displayTotalCost() {
        const val = this.lineData?.totalCost || this.lineData?.netPrice || 0;
        return '$' + Number(val).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    get displayListPrice() {
        const val = this.lineData?.listPrice || 0;
        return '$' + Number(val).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    get displayDiscount() {
        return this.lineData?.discount != null ? this.lineData.discount + '%' : '0%';
    }

    get displayAcvChange() {
        const val = this.lineData?.acvChange || 0;
        return '$' + Number(val).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    get displayProductCode() {
        return this.lineData?.productCode || '—';
    }

    get displayDateRange() {
        const s = this.lineData?.startDate;
        const e = this.lineData?.endDate;
        if (!s && !e) return '—';
        return (s || '—') + ' to ' + (e || '—');
    }

    get approvalBadgeClass() {
        return this.lineData?.approvalRequired === 'Required'
            ? 'approval-badge required'
            : 'approval-badge not-required';
    }

    // BUG FIX #5 (same pattern): Clear pending debounce timers on destroy.
    disconnectedCallback() {
        clearTimeout(this._quantityTimeout);
        clearTimeout(this._acvTimeout);
    }

    toggleExpanded() {
        if (!this.lineData?.isLocked || this.isExpanded) {
            this.isExpanded = !this.isExpanded;
        } else {
            this.isExpanded = true;
        }
    }

    handleQuantityChange(event) {
        clearTimeout(this._quantityTimeout);
        const qty = Number(event.target.value);
        this._quantityTimeout = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('quantitychange', {
                detail: { lineId: this.lineData.id, quantity: qty }
            }));
        }, 500);
    }

    handleAcvChange(event) {
        clearTimeout(this._acvTimeout);
        const acv = Number(event.target.value);
        this._acvTimeout = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('acvchange', {
                detail: { lineId: this.lineData.id, acvChange: acv }
            }));
        }, 500);
    }
}