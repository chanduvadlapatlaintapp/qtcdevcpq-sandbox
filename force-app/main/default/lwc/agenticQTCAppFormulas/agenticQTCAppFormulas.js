/**
 * Pricing & ACV formulas shared across the Agentic QTC LWC family.
 * Pure functions — no DOM, no Apex, safe to unit-test in isolation.
 */
export default class AgenticQTCAppFormulas {

    static toNumber(value) {
        return Number(value) || 0;
    }

    static effectiveQuantity(newQty, priorQty) {
        return AgenticQTCAppFormulas.toNumber(newQty) - AgenticQTCAppFormulas.toNumber(priorQty);
    }

    static monthlyUnitPrice(line) {
        return AgenticQTCAppFormulas.toNumber(line.customerSalePricePerMonth)
            || AgenticQTCAppFormulas.toNumber(line.listPrice);
    }

    static annualUnitPrice(line) {
        return AgenticQTCAppFormulas.toNumber(line.customerPrice);
    }

    static netPrice(line, qty) {
        return AgenticQTCAppFormulas.annualUnitPrice(line) * AgenticQTCAppFormulas.toNumber(qty);
    }

    static acv(line, qty) {
        const newQty = AgenticQTCAppFormulas.toNumber(qty);
        const priorQty = AgenticQTCAppFormulas.toNumber(line.priorQuantity);
        const effectiveQty = newQty - priorQty;
        const monthly = AgenticQTCAppFormulas.monthlyUnitPrice(line);
        const net = AgenticQTCAppFormulas.netPrice(line, newQty);

        if (line.chargeType === 'Recurring') {
            return monthly * effectiveQty * 12;
        }
        if (line.chargeType === 'One-Time') {
            return net;
        }
        return 0;
    }

    /**
     * Returns a NEW line object with quantity, ACV, and live netTotal recomputed.
     * Immutable — caller must replace the line in the array.
     *
     * Live netTotal = effectiveQuantity × NetPrice. The server returns the
     * authoritative SBQQ__NetTotal__c on Save, which overwrites this optimistic
     * value. The editor sums netTotal across visible lines for the live TCV
     * header (see agenticQtcQuoteEditor.totalTcv).
     */
    static recalcLineForQuantity(line, newQty) {
        const qty = AgenticQTCAppFormulas.toNumber(newQty);
        const acv = AgenticQTCAppFormulas.acv(line, qty);
        const effectiveQty = AgenticQTCAppFormulas.effectiveQuantity(qty, line.priorQuantity);
        const netTotal = effectiveQty * AgenticQTCAppFormulas.toNumber(line.netPrice);
        return Object.assign({}, line, {
            quantity: qty,
            acv,
            netTotal
        });
    }

    /**
     * Snapshot the current ACV per line into a Map keyed by line.id.
     * Call once when the quote editor first loads.
     */
    static captureAcvBaseline(lines) {
        const map = new Map();
        for (const line of (lines || [])) {
            if (line && line.id != null) {
                map.set(line.id, AgenticQTCAppFormulas.toNumber(line.acv));
            }
        }
        return map;
    }

    /**
     * Returns a new array of lines where each line's `acvChange` is
     * `currentAcv - baselineAcv`. Lines not in the baseline default to 0
     * (e.g. newly added lines).
     */
    static applyAcvChange(lines, baselineMap) {
        if (!Array.isArray(lines)) return lines;
        return lines.map(line => {
            const baseline = baselineMap && line && baselineMap.has(line.id)
                ? baselineMap.get(line.id)
                : 0;
            const current = AgenticQTCAppFormulas.toNumber(line.acv);
            return Object.assign({}, line, { acvChange: current - baseline });
        });
    }

    static sumField(lines, field) {
        let sum = 0;
        for (const line of (lines || [])) {
            sum += AgenticQTCAppFormulas.toNumber(line[field]);
        }
        return sum;
    }

    static totalAcv(lines)       { return AgenticQTCAppFormulas.sumField(lines, 'acv'); }
    static totalAcvChange(lines) { return AgenticQTCAppFormulas.sumField(lines, 'acvChange'); }
}