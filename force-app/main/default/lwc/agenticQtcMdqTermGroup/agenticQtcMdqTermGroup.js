import { LightningElement, api, track } from 'lwc';

export default class AgenticQtcMdqTermGroup extends LightningElement {
    @api termData;
    @api quoteStartDate;
    /** ISO 4217 currency code from Contract.CurrencyIsoCode — used by _fmtCurrency
     *  to render per-segment ACV / Cost / TCV cells. Falls back to "USD" when null. */
    @api currencyIsoCode;
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
            out.push({ key: 'fh-a-' + i, label: 'Cost', cls: 'col-field' });
        }
        return out;
    }

    // Per-year sum of every product's live cost (seg.netTotal). The optimistic
    // update path (recalcLineForQuantity) and the server-refresh path both
    // write into seg.netTotal, so this getter reflects whichever value is
    // currently on the line — no extra plumbing needed for live updates.
    get totalCostCells() {
        const products = this.termData?.products || [];
        const segCount = this.termData?.segmentCount || 0;
        const totals = new Array(segCount).fill(0);
        for (const p of products) {
            const segs = p.segments || [];
            for (let i = 0; i < segs.length && i < segCount; i++) {
                totals[i] += Number(segs[i].netTotal) || 0;
            }
        }
        return totals.map((t, i) => ({
            key: 'tc-' + i,
            display: this._fmtCurrency(t)
        }));
    }

    get productRows() {
        const products = this.termData?.products || [];
        return products.map(p => {
            const segs = p.segments || [];
            // Floor each segment at its verified (prior) quantity so Eff. Qty
            // can never go negative. Each year's down arrow is disabled solely
            // by that year's own floor — the first year's cascade still ticks
            // every year down, but years already at their floor simply stay.
            const canDecreaseEach = segs.map(s =>
                (Number(s.quantity) || 0) > (Number(s.priorQuantity) || 0)
            );
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

                const minQuantity = Number(seg.priorQuantity) || 0;
                const decrementDisabled = !canDecreaseEach[idx];

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
                    displayCost: this._fmtCurrency(seg.netTotal),
                    acv: seg.acv,
                    displayAcvChange: this._fmtCurrency(seg.acvChange),
                    discount: seg.discount,
                    displayDiscount: (seg.discount != null ? Number(seg.discount).toFixed(2) : '0.00') + ' %',
                    displayTcv: this._fmtCurrency(cumulativeTcv),
                    displayYoyUplift: yoyUplift.toFixed(2) + ' %',
                    isEditable: !seg.isLocked,
                    isLocked: seg.isLocked,
                    minQuantity,
                    decrementDisabled
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
            this._buildDetailRow('ACV', cells, c => this._fmtCurrency(c.acv), productKey)
            // VK: TCV / Discount % / ACV Change / YoY Uplift detail rows hidden from
            // the expanded product card for the current release. Re-add to the array
            // when the metrics are needed again — no template logic to restore, just
            // uncomment the four entries below.
            // this._buildDetailRow('TCV', cells, c => c.displayTcv, productKey),
            // this._buildDetailRow('Discount %', cells, c => c.displayDiscount, productKey),
            // this._buildDetailRow('ACV Change', cells, c => c.displayAcvChange, productKey),
            // this._buildDetailRow('YoY Uplift', cells, c => c.displayYoyUplift, productKey)
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
        const code = this.currencyIsoCode || 'USD';
        if (Math.abs(n) >= 1000000) {
            return code + ' ' + (n / 1000000).toFixed(2) + 'M';
        }
        return code + ' ' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
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

    // Typing → editing the FIRST year cascades the delta to every year
    // (clamped at each year's verified floor); edits on any later year only
    // update that year. The first year itself is still rejected with a toast
    // if the entered value would drop it below its own verified quantity —
    // quantity can grow without bound but never drop below that baseline.
    handleQuantityChange(event) {
        const lineId = event.target.dataset.lineId;
        const product = this._findProductByLineId(lineId);
        if (!product) return;
        const segments = product.segments || [];
        const segmentKey = product.segmentKey;
        const editableSegments = segments.filter(s => !s.isLocked);
        const clickedSeg = segments.find(s => s.id === lineId);
        if (!clickedSeg) return;
        const isFirstSegment = editableSegments.length > 0 && editableSegments[0].id === lineId;
        const ownCurrent = Number(clickedSeg.quantity) || 0;
        const ownMin = Number(clickedSeg.priorQuantity) || 0;

        clearTimeout(this._quantityTimeouts[lineId]);
        let qty = Number(event.target.value);
        if (!Number.isFinite(qty) || qty < 0) {
            qty = 0;
            event.target.value = 0;
        }

        if (qty < ownMin) {
            event.target.value = ownCurrent;
            this._dispatchValidationError(
                'Quantity cannot be decreased below the verified quantity (' + ownMin + ').'
            );
            return;
        }

        // Snapshot quantities and floors NOW as plain numbers while still in the
        // synchronous event handler. LWC @api props are live reactive proxies —
        // reading seg.quantity inside the async timeout would return whatever value
        // the data store holds at that moment (potentially already updated by the
        // parent), making the delta calculation wrong (delta=0 → early return →
        // Year 2+ segments never receive the cascade).
        const baseQuantities = editableSegments.map(s => Number(s.quantity) || 0);
        const baseMins       = editableSegments.map(s => Number(s.priorQuantity) || 0);

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._quantityTimeouts[lineId] = setTimeout(() => {
            if (isFirstSegment && editableSegments.length > 1) {
                const delta = qty - baseQuantities[0];
                if (delta === 0) return;

                // Apply the delta to every year, clamping each one at its own
                // verified floor — later years that are already at the floor
                // simply stay put rather than blocking the first year's edit.
                for (let i = 0; i < editableSegments.length; i++) {
                    const seg        = editableSegments[i];
                    const segCurrent = baseQuantities[i];
                    const segMin     = baseMins[i];
                    const computed   = segCurrent + delta;
                    const next       = computed < segMin ? segMin : computed;
                    if (next === segCurrent) continue;
                    clearTimeout(this._quantityTimeouts[seg.id]);
                    this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                        detail: { lineId: seg.id, quantity: next, segmentKey, applyToAll: false }
                    }));
                }
            } else {
                this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                    detail: { lineId, quantity: qty, segmentKey, applyToAll: false }
                }));
            }
        }, 500);
    }

    _dispatchValidationError(message) {
        this.dispatchEvent(new CustomEvent('mdqvalidationerror', {
            detail: { message }
        }));
    }

    // Stepper ▲/▼ → clicking the FIRST year applies the +1/-1 delta to
    // every year, but each year is clamped at its own verified floor —
    // years already at the floor stay put rather than blocking the rest.
    // The first year's own down arrow is disabled when year 1 hits its
    // floor. Clicks on any later year only step that year.
    handleStepQuantity(event) {
        const btn = event.currentTarget;
        const clickedLineId = btn.dataset.lineId;
        const direction = btn.dataset.direction;
        const delta = direction === 'up' ? 1 : -1;

        const product = this._findProductByLineId(clickedLineId);
        if (!product) return;
        const segments = product.segments || [];
        const editableSegments = segments.filter(s => !s.isLocked);
        const isFirstSegment = editableSegments.length > 0 && editableSegments[0].id === clickedLineId;

        if (isFirstSegment && editableSegments.length > 1) {
            // Cascade only steps the years that still have slack; years
            // already at their verified floor stay put rather than blocking
            // the click for every other year.
            const firstMin = Number(editableSegments[0].priorQuantity) || 0;
            const firstNext = (Number(editableSegments[0].quantity) || 0) + delta;
            if (firstNext < firstMin) return;

            for (const seg of editableSegments) {
                const current = Number(seg.quantity) || 0;
                const segMin = Number(seg.priorQuantity) || 0;
                const next = current + delta;
                if (next === current) continue;
                if (next < segMin) continue;
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
        } else {
            const clickedSeg = segments.find(s => s.id === clickedLineId);
            if (!clickedSeg) return;
            const current = Number(clickedSeg.quantity) || 0;
            const next = current + delta;
            const segMin = Number(clickedSeg.priorQuantity) || 0;
            if (next < segMin) return;
            clearTimeout(this._quantityTimeouts[clickedLineId]);
            this.dispatchEvent(new CustomEvent('mdqquantitychange', {
                detail: {
                    lineId: clickedLineId,
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

    disconnectedCallback() {
        Object.values(this._quantityTimeouts).forEach(t => clearTimeout(t));
        this._quantityTimeouts = {};
    }
}