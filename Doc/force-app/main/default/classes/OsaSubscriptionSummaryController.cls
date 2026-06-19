/**
 * @description Apex controller for the osaSubscriptionSummary LWC.
 *              Queries SBQQ__QuoteLine__c records for a given Quote,
 *              groups them by SBQQ__SegmentIndex__c, and returns
 *              per-segment line detail alongside year totals from
 *              existing rollup fields on the Quote.
 * @author      Satyanarayana Pusuluri
 * @date        2026-05-29
 * @jira        BIZ-81899
 */
public with sharing class OsaSubscriptionSummaryController {

    // ─────────────────────────────────────────────────────────
    // Inner wrapper classes
    // ─────────────────────────────────────────────────────────

    /** Top-level wrapper returned to the LWC */
    public class OsaSummaryWrapper {
        @AuraEnabled public List<SegmentGroup> segments;
        @AuraEnabled public Decimal            netSubscriptionFees;
    }

    /** One segment group (e.g. Segment 1 = Year 1) */
    public class SegmentGroup {
        @AuraEnabled public Integer       segmentIndex;        // null = adjustment rows
        @AuraEnabled public String        segmentLabel;        // 'Segment 1' / 'Adjustments'
        @AuraEnabled public String        yearLabel;           // 'Year 1 Subscription Fees'
        @AuraEnabled public String        dateRange;           // '01-Oct-2025 → 30-Sep-2026'
        @AuraEnabled public Decimal       yearTotal;           // from existing Quote field
        @AuraEnabled public Decimal       lineSubtotal;        // SUM of NetTotal for lines
        @AuraEnabled public Decimal       oneTimeCreditAmount; // One_Time_Credit_Yr{N}__c; null = no row shown
        @AuraEnabled public List<LineItem> lines;
    }

    /** One quote line row */
    public class LineItem {
        @AuraEnabled public String  productCode;
        @AuraEnabled public String  productName;
        @AuraEnabled public String  supportLevel;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal salePricePerMonth;
        @AuraEnabled public Decimal netTotal;
        @AuraEnabled public String  currencyCode;
    }

    // ─────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────

    /**
     * @description Main method called by LWC @wire.
     * @param  quoteId  SBQQ__Quote__c record Id
     * @return OsaSummaryWrapper
     */
    @AuraEnabled
    public static OsaSummaryWrapper getOsaSummary(Id quoteId) {

        // 1. Fetch year totals and one-time credit amounts from existing Quote fields
        SBQQ__Quote__c quote = [
            SELECT Total_Subscription_Fees_Year_1__c,
                   Total_Subscription_Fees_2nd_Year__c,
                   Total_Subscription_Fees_3rd_Year__c,
                   Total_Subscription_Fees_4th_Year__c,
                   Total_Subscription_Fees_5th_Year__c,
                   Total_Subscription_Fees_6th_Year__c,
                   One_Time_Credit_Yr1__c,
                   One_Time_Credit_Yr2__c,
                   One_Time_Credit_Yr3__c,
                   One_Time_Credit_Yr4__c,
                   One_Time_Credit_Yr5__c,
                   One_Time_Credit_Yr6__c,
                   SBQQ__StartDate__c,
                   CurrencyIsoCode
            FROM   SBQQ__Quote__c
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        // 2. Query all quote lines
        List<SBQQ__QuoteLine__c> lines = [
            SELECT SBQQ__ProductCode__c,
                   SBQQ__ProductName__c,
                   SBQQ__SegmentIndex__c,
                   SBQQ__StartDate__c,
                   SBQQ__EndDate__c,
                   Customer_Sale_Price_Per_Month__c,
                   SBQQ__NetTotal__c,
                   SBQQ__Quantity__c,
                   Support_Level__c,
                   CurrencyIsoCode
            FROM   SBQQ__QuoteLine__c
            WHERE  SBQQ__Quote__c = :quoteId
            WITH   SECURITY_ENFORCED
            ORDER  BY SBQQ__SegmentIndex__c NULLS FIRST,
                      SBQQ__ProductCode__c
        ];

        // 3. Group lines by segment index key
        Map<String, List<SBQQ__QuoteLine__c>> groupMap =
            new Map<String, List<SBQQ__QuoteLine__c>>();

        for (SBQQ__QuoteLine__c ql : lines) {
            String key = ql.SBQQ__SegmentIndex__c == null
                ? 'ADJ'
                : String.valueOf(Integer.valueOf(ql.SBQQ__SegmentIndex__c));
            if (!groupMap.containsKey(key)) {
                groupMap.put(key, new List<SBQQ__QuoteLine__c>());
            }
            groupMap.get(key).add(ql);
        }

        // 4. Year totals map
        Map<Integer, Decimal> yearTotals = new Map<Integer, Decimal>{
            1 => quote.Total_Subscription_Fees_Year_1__c  != null ? quote.Total_Subscription_Fees_Year_1__c  : 0,
            2 => quote.Total_Subscription_Fees_2nd_Year__c != null ? quote.Total_Subscription_Fees_2nd_Year__c : 0,
            3 => quote.Total_Subscription_Fees_3rd_Year__c != null ? quote.Total_Subscription_Fees_3rd_Year__c : 0,
            4 => quote.Total_Subscription_Fees_4th_Year__c != null ? quote.Total_Subscription_Fees_4th_Year__c : 0,
            5 => quote.Total_Subscription_Fees_5th_Year__c != null ? quote.Total_Subscription_Fees_5th_Year__c : 0,
            6 => quote.Total_Subscription_Fees_6th_Year__c != null ? quote.Total_Subscription_Fees_6th_Year__c : 0
        };

        // One-time credit amounts per year — null means the field is blank (row hidden in LWC)
        Map<Integer, Decimal> otcAmounts = new Map<Integer, Decimal>{
            1 => quote.One_Time_Credit_Yr1__c,
            2 => quote.One_Time_Credit_Yr2__c,
            3 => quote.One_Time_Credit_Yr3__c,
            4 => quote.One_Time_Credit_Yr4__c,
            5 => quote.One_Time_Credit_Yr5__c,
            6 => quote.One_Time_Credit_Yr6__c
        };

        // 5. Build segment list
        List<SegmentGroup> segments = new List<SegmentGroup>();

        // Adjustments group first (null segment index — no OTC for adjustments)
        if (groupMap.containsKey('ADJ')) {
            segments.add(buildGroup(null, groupMap.get('ADJ'), 0, null, quote.SBQQ__StartDate__c));
        }

        // Segments 1–6
        for (Integer i = 1; i <= 6; i++) {
            String key = String.valueOf(i);
            List<SBQQ__QuoteLine__c> segLines = groupMap.containsKey(key)
                ? groupMap.get(key)
                : new List<SBQQ__QuoteLine__c>();
            segments.add(buildGroup(i, segLines, yearTotals.get(i), otcAmounts.get(i), quote.SBQQ__StartDate__c));
        }

        // 6. Net total = sum of all year totals
        Decimal net = 0;
        for (Integer i = 1; i <= 6; i++) {
            net += yearTotals.get(i);
        }

        OsaSummaryWrapper wrapper   = new OsaSummaryWrapper();
        wrapper.segments            = segments;
        wrapper.netSubscriptionFees = net;
        return wrapper;
    }

    // ─────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────

    private static SegmentGroup buildGroup(
        Integer idx,
        List<SBQQ__QuoteLine__c> qlLines,
        Decimal yearTotal,
        Decimal oneTimeCreditAmount,
        Date quoteStartDate
    ) {
        SegmentGroup grp        = new SegmentGroup();
        grp.segmentIndex        = idx;
        grp.yearTotal           = yearTotal != null ? yearTotal : 0;
        grp.lines               = new List<LineItem>();
        grp.lineSubtotal        = 0;
        // Preserve null to signal "no OTC row" — only set when the Quote field has a value
        grp.oneTimeCreditAmount = (oneTimeCreditAmount != null && oneTimeCreditAmount != 0)
            ? oneTimeCreditAmount
            : null;

        if (idx == null) {
            grp.segmentLabel = 'Adjustments / Payment Corrections';
            grp.yearLabel    = 'Subtotal';
            grp.dateRange    = 'No segment index';
        } else {
            grp.segmentLabel = 'Segment ' + idx;
            grp.yearLabel    = 'Year ' + idx + ' Subscription Fees';
            grp.dateRange    = buildDateRange(idx, quoteStartDate);
        }

        for (SBQQ__QuoteLine__c ql : qlLines) {
            LineItem li          = new LineItem();
            li.productCode       = ql.SBQQ__ProductCode__c;
            li.productName       = ql.SBQQ__ProductName__c;
            li.supportLevel      = ql.Support_Level__c;
            li.quantity          = ql.SBQQ__Quantity__c != null ? ql.SBQQ__Quantity__c : 0;
            li.salePricePerMonth = ql.Customer_Sale_Price_Per_Month__c != null ? ql.Customer_Sale_Price_Per_Month__c : 0;
            li.netTotal          = ql.SBQQ__NetTotal__c != null ? ql.SBQQ__NetTotal__c : 0;
            li.currencyCode      = ql.CurrencyIsoCode;
            grp.lineSubtotal    += li.netTotal;
            grp.lines.add(li);
        }
        return grp;
    }

    private static String buildDateRange(Integer idx, Date startDate) {
        if (startDate == null) return '';
        Date segStart = startDate.addYears(idx - 1);
        Date segEnd   = startDate.addYears(idx).addDays(-1);
        return Datetime.newInstance(segStart, Time.newInstance(0, 0, 0, 0)).format('dd-MMM-yyyy')
            + ' → '
            + Datetime.newInstance(segEnd, Time.newInstance(0, 0, 0, 0)).format('dd-MMM-yyyy');
    }
}