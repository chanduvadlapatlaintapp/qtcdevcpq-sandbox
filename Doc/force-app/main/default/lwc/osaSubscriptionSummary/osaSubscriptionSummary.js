/**
 * @description OSA Subscription Fee Summary LWC
 *              Displays Quote Lines grouped by Segment Index in a
 *              collapsible accordion. Year totals from existing Quote fields.
 *              Uses imperative Apex (non-cacheable) so every tab activation
 *              fetches fresh data — avoids LDS cache stale-read issues.
 * @author      Satyanarayana Pusuluri
 * @date        2026-05-29
 * @jira        BIZ-81899
 */
import { LightningElement, api, track } from "lwc";
import getOsaSummary from "@salesforce/apex/OsaSubscriptionSummaryController.getOsaSummary";

// ── SLDS2 colour map per segment ─────────────────────────────
const SEGMENT_COLORS = {
  ADJ: {
    chip: "osa-idx-chip osa-idx-blank",
    yearLabel: "osa-year-label",
    yearAmt: "osa-year-amount",
  },
  1: {
    chip: "osa-idx-chip osa-idx-1",
    yearLabel: "osa-year-label osa-y1",
    yearAmt: "osa-year-amount osa-y1",
  },
  2: {
    chip: "osa-idx-chip osa-idx-2",
    yearLabel: "osa-year-label osa-y2",
    yearAmt: "osa-year-amount osa-y2",
  },
  3: {
    chip: "osa-idx-chip osa-idx-3",
    yearLabel: "osa-year-label osa-y3",
    yearAmt: "osa-year-amount osa-y3",
  },
  4: {
    chip: "osa-idx-chip osa-idx-4",
    yearLabel: "osa-year-label osa-y4",
    yearAmt: "osa-year-amount osa-y4",
  },
  5: {
    chip: "osa-idx-chip osa-idx-5",
    yearLabel: "osa-year-label osa-y5",
    yearAmt: "osa-year-amount osa-y5",
  },
  6: {
    chip: "osa-idx-chip osa-idx-6",
    yearLabel: "osa-year-label osa-y6",
    yearAmt: "osa-year-amount osa-y6",
  },
};

const fmt = (val) =>
  new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(val ?? 0);

export default class OsaSubscriptionSummary extends LightningElement {
  // ── Public API ────────────────────────────────────────────
  @api recordId;

  // ── Private state ─────────────────────────────────────────
  @track _openSegments = new Set();
  @track _summaryData;
  @track _isLoading = false;
  @track _errorMessage;

  // ── Lifecycle hooks ───────────────────────────────────────
  /**
   * Fires every time the component is inserted into the DOM.
   * On a Lightning Record Page, switching away and back to the
   * "OSA Details" tab destroys and recreates the component, so
   * connectedCallback always runs with a fresh call — bypassing
   * any LDS / wire-service cache from cacheable=true.
   */
  connectedCallback() {
    this._loadData();
  }

  // ── Computed getters ──────────────────────────────────────
  get isLoading() {
    return this._isLoading;
  }

  get hasError() {
    return !!this._errorMessage;
  }

  get errorMessage() {
    return this._errorMessage;
  }

  get hasData() {
    return !!this._summaryData;
  }

  get summary() {
    if (!this._summaryData) return null;
    return {
      segments: this._buildSegments(this._summaryData.segments),
      formattedNetTotal: fmt(this._summaryData.netSubscriptionFees),
    };
  }

  // ── Event handlers ────────────────────────────────────────
  handleToggle(event) {
    const key = event.currentTarget.dataset.key;
    const updated = new Set(this._openSegments);
    if (updated.has(key)) {
      updated.delete(key);
    } else {
      updated.add(key);
    }
    this._openSegments = updated;
  }

  handleRefresh() {
    this._loadData();
  }

  // ── Private: imperative Apex fetch ───────────────────────
  _loadData() {
    if (!this.recordId) return;
    this._isLoading = true;
    this._errorMessage = null;
    this._summaryData = null;

    getOsaSummary({ quoteId: this.recordId })
      .then((data) => {
        this._summaryData = data;
      })
      .catch((err) => {
        this._errorMessage =
          err?.body?.message ?? "An error occurred loading the OSA summary.";
      })
      .finally(() => {
        this._isLoading = false;
      });
  }

  // ── Private: enrich raw segments ─────────────────────────
  _buildSegments(rawSegments) {
    if (!rawSegments) return [];

    return rawSegments
      .filter(
        (seg) =>
          (seg.yearTotal != null && seg.yearTotal !== 0) ||
          (seg.lines && seg.lines.length > 0),
      )
      .map((seg) => {
        const key = seg.segmentIndex == null ? "ADJ" : String(seg.segmentIndex);
        const colors = SEGMENT_COLORS[key] ?? SEGMENT_COLORS["ADJ"];
        const isOpen = this._openSegments.has(key);

        return {
          ...seg,
          segmentKey: key,
          isOpen,
          hasLines: seg.lines && seg.lines.length > 0,
          hasNoLines: !seg.lines || seg.lines.length === 0,
          lineCount: seg.lines ? seg.lines.length : 0,
          indexLabel: seg.segmentIndex == null ? "–" : String(seg.segmentIndex),
          chevronIcon: isOpen ? "utility:chevrondown" : "utility:chevronright",
          headerClass: `osa-seg-header${isOpen ? " osa-seg-open" : ""}`,
          indexChipClass: colors.chip,
          yearLabelClass: colors.yearLabel,
          yearAmountClass: colors.yearAmt,
          formattedYearTotal: fmt(seg.yearTotal),
          formattedLineSubtotal: fmt(seg.lineSubtotal),
          // ADJ header shows line subtotal (no Quote year-total field for adjustments)
          formattedHeaderTotal:
            seg.segmentIndex == null
              ? fmt(seg.lineSubtotal)
              : fmt(seg.yearTotal),
          // One Time Credit — only shown when the Quote field has a non-null, non-zero value
          hasOneTimeCredit: seg.oneTimeCreditAmount != null,
          formattedOneTimeCredit: fmt(seg.oneTimeCreditAmount),
          lines: (seg.lines || []).map((line) => ({
            ...line,
            formattedQty: fmt(line.quantity),
            formattedSalePrice: fmt(line.salePricePerMonth),
            formattedNetTotal: fmt(line.netTotal),
            supportBadgeClass:
              line.supportLevel === "Premium"
                ? "osa-badge-premium"
                : "osa-badge-standard",
          })),
        };
      });
  }
}