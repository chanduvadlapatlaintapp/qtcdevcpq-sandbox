import { LightningElement, api, track } from 'lwc';

export default class AgenticQtcMdqTermGroup extends LightningElement {
    @api termData;
    @api quoteStartDate;
    @track expandedProducts = {};
    _quantityTimeouts = {};

    get termLabel() {
        return this.termData?.termLabel || '';
    }

    get yearHeaders() {
        return this.termData?.yearHeaders || [];
    }

    get totalYearCols() {
        return (this.termData?.segmentCount || 0) * 4;
    }

    // For terms longer than 3 years, force a min-width on the table that
    // scales with the year count so the wrapper engages horizontal scroll
    // instead of crushing cells together. ≤3 years still fits the container.
    get tableClass() {
        const count = this.termData?.segmentCount || 0;
        if (count <= 3) return 'mdq-grid';
        return 'mdq-grid mdq-grid-scroll-' + Math.min(count, 12);
    }


    get cardClass() {
        let cls = 'mdq-card';
        const products = this.termData?.products || [];
        if (products.some(p => p.approvalRequired === 'Required')) cls += ' needs-approval';
        return cls;
    }

get fieldHeaders() {
        const out = [];
        const count = this.termData?.segmentCount || 0;
        for (let i = 0; i < count; i++) {
            out.push({ key: 'fh-q-' + i, label: 'Quantity', cls: 'col-field col-year-start' });
            out.push({ key: 'fh-e-' + i, label: 'Eff. Qty', cls: 'col-field' });
            out.push({ key: 'fh-p-' + i, label: 'Monthly Sale Price', cls: 'col-field' });
            out.push({ key: 'fh-a-' + i, label: 'ACV', cls: 'col-field' });
        }
        return out;
    }

    get productRows() {
        const products = this.termData?.products || [];
        return products.map(p => {
            const segs = p.segments || [];
            let cumulativeTcv = 0;
            const yearCells = segs.map((seg, idx) => {
                cumulativeTcv += (seg.netPrice || 0);
                const prevAcv = idx > 0 ? (segs[idx - 1].acv || 0) : 0;
                const thisAcv = seg.acv || 0;
                const yoyUplift = (idx > 0 && prevAcv !== 0)
                    ? ((thisAcv - prevAcv) / prevAcv * 100)
                    : 0;

                const baseline = Number(seg.priorQuantity || 0);
                const current = Number(seg.quantity || 0);
                const delta = current - baseline;
                let displayEffQty;
                let effQtyClass = 'eff-qty';
                if (delta === 0) {
                    displayEffQty = '–';
                    effQtyClass += ' eff-qty-neutral';
                } else if (delta > 0) {
                    displayEffQty = '+' + delta;
                    effQtyClass += ' eff-qty-positive';
                } else {
                    displayEffQty = String(delta);
                    effQtyClass += ' eff-qty-negative';
                }

                return {
                    lineId: seg.id,
                    keyQty: 'q-' + p.key + '-' + seg.id,
                    keyEff: 'e-' + p.key + '-' + seg.id,
                    keyPrice: 'p-' + p.key + '-' + seg.id,
                    keyAcv: 'a-' + p.key + '-' + seg.id,
                    quantity: seg.quantity,
                    displayQuantity: seg.quantity != null ? Number(seg.quantity).toLocaleString() : '0',
                    displayEffQty,
                    effQtyClass,
                    displayMonthlySalePrice: this._fmtCurrency(seg.customerSalePricePerMonth),
                    displayAcv: this._fmtCurrency(seg.acv),
                    acv: seg.acv,
                    displayAcvChange: this._fmtCurrency(seg.acvChange),
                    discount: seg.discount,
                    displayDiscount: (seg.discount != null ? Number(seg.discount).toFixed(2) : '0.00') + ' %',
                    displayTcv: this._fmtCurrency(cumulativeTcv),
                    displayYoyUplift: yoyUplift.toFixed(2) + ' %',
                    isEditable: !seg.isLocked,
                    isLocked: seg.isLocked
                };
            });

            const isExpanded = !!this.expandedProducts[p.key];
            const detailRows = isExpanded ? this._buildDetailRows(yearCells, p.key) : [];

            return {
                key: p.key,
                productName: p.productName,
                productCode: p.productCode,
                meterType: p.meterType,
                hasMeterType: !!p.meterType,
                segmentKey: p.segmentKey,
                yearCells,
                detailRows,
                isExpanded,
                chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass: 'product-row' + (isExpanded ? ' is-expanded' : '')
            };
        });
    }

    _buildDetailRows(cells, productKey) {
        return [
            this._buildDetailRow('ACV', cells, c => this._fmtCurrency(c.acv), productKey),
            this._buildDetailRow('TCV', cells, c => c.displayTcv, productKey),
            this._buildDetailRow('Discount %', cells, c => c.displayDiscount, productKey),
            this._buildDetailRow('ACV Change', cells, c => c.displayAcvChange, productKey),
            this._buildDetailRow('YoY Uplift', cells, c => c.displayYoyUplift, productKey)
        ];
    }

    _buildDetailRow(label, cells, valueFn, productKey) {
        const slug = label.replace(/\s+/g, '-').toLowerCase();
        return {
            key: 'dr-' + productKey + '-' + slug,
            label,
            values: cells.map((c, i) => ({
                key: 'dr-' + productKey + '-' + slug + '-' + i,
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

    handleToggleProduct(event) {
        const productKey = event.currentTarget.dataset.productKey;
        if (!productKey) return;
        const next = { ...this.expandedProducts };
        next[productKey] = !next[productKey];
        this.expandedProducts = next;
    }

    // Stops a click on the disabled meter-type pill from bubbling up and
    // accidentally toggling the product accordion.
    stopPropagation(event) {
        event.stopPropagation();
    }

    // Manual typing → update only the year the user edited.
    handleQuantityChange(event) {
        const lineId = event.target.dataset.lineId;
        const segmentKey = this._segmentKeyForLine(lineId);
        clearTimeout(this._quantityTimeouts[lineId]);
        let qty = Number(event.target.value);
        if (!Number.isFinite(qty) || qty < 0) {
            qty = 0;
            event.target.value = 0;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._quantityTimeouts[lineId] = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                detail: { lineId, quantity: qty, segmentKey, applyToAll: false }
            }));
        }, 500);
    }

    // Stepper ▲/▼ → apply the same delta (+1 / -1) to every year of the
    // same product so the year-over-year offsets are preserved. Blocked
    // entirely if any year would otherwise dip below 0.
    handleStepQuantity(event) {
        const btn = event.currentTarget;
        const clickedLineId = btn.dataset.lineId;
        const direction = btn.dataset.direction;
        const delta = direction === 'up' ? 1 : -1;

        const product = this._findProductByLineId(clickedLineId);
        if (!product) return;
        const segments = product.segments || [];

        for (const seg of segments) {
            const next = (Number(seg.quantity) || 0) + delta;
            if (next < 0) return;
        }

        for (const seg of segments) {
            const current = Number(seg.quantity) || 0;
            const next = current + delta;
            if (next === current) continue;
            clearTimeout(this._quantityTimeouts[seg.id]);
            this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                detail: {
                    lineId: seg.id,
                    quantity: next,
                    segmentKey: product.segmentKey,
                    applyToAll: false
                }
            }));
        }
    }

    _findProductByLineId(lineId) {
        const products = this.termData?.products || [];
        for (const p of products) {
            for (const seg of (p.segments || [])) {
                if (seg.id === lineId) return p;
            }
        }
        return null;
    }

    _segmentKeyForLine(lineId) {
        const product = this._findProductByLineId(lineId);
        return product ? product.segmentKey : null;
    }

    disconnectedCallback() {
        Object.values(this._quantityTimeouts).forEach(t => clearTimeout(t));
        this._quantityTimeouts = {};
    }
}