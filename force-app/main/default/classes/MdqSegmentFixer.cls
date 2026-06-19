/**
 * @description Detects and creates missing MDQ (Multi-Dimensional Quoting) segment OrderItems
 *              that Salesforce CPQ skips when a QuoteLine has Quantity = 0.
 *
 *              Invocation paths:
 *              1. OrderProductTriggerHandler.afterInsert — PRIMARY path.
 *                 newOrderItems = Trigger.new. Sibling map built from Trigger.new (no SOQL).
 *                 SOQLs: 3  (Order + lightweight existence check + QuoteLine).
 *              2. fixOrdersById(Set<Id>) — RETROACTIVE path.
 *                 Called from anonymous Apex to repair pre-existing orders.
 *                 SOQLs: 3  (Order + full-field OrderItem sibling + QuoteLine).
 *
 *              Duplicate / retrigger guards:
 *              - isRunning static flag       : prevents re-entry on our own insert.
 *              - SBQQ.TriggerControl.disable(): suppresses CPQ triggers during insert.
 *              - existingKeyMap              : composite (OrderId+SegmentKey+SegmentIndex)
 *                                             presence check — fully idempotent.
 *
 *              Quantity = 0:
 *              Matches the zero-qty QuoteLine. Requires "Enable Zero Quantity" to be enabled
 *              on the Order (CPQ sets this automatically when ordering MDQ quotes).
 *              The standard platform validation rejecting Quantity = 0 on OrderItem is
 *              suppressed while SBQQ.TriggerControl.disable() is active — CPQ registers an
 *              MDQ override for exactly this scenario.
 *
 *              See: Salesforce Known Issue 004518581
 * @author      Satya Pusuluri
 * @date        2026-05-04
 * @jira        BIZ-81576
 */
public without sharing class MdqSegmentFixer {

    /** @TestVisible capture of insert errors — populated only when Test.isRunningTest() is true. */
    @TestVisible
    private static List<String> testInsertErrors = new List<String>();

    /**
     * Recursion guard — prevents OrderProduct.afterInsert from re-entering this class
     * when we insert the missing segment OrderItems.
     */
    private static Boolean isRunning = false;

    /***********************************************************************************************
    *
    * Public API
    *
    ***********************************************************************************************/

    /**
     * @description PRIMARY entry point — called from OrderProductTriggerHandler.afterInsert.
     *
     *              SOQLs: 3
     *                1. Order         — EffectiveDate + SBQQ__Quote__c
     *                2. OrderItem     — lightweight existence check (Id, SegmentKey, SegmentIndex
     *                                   only) to catch any OIs from prior batches. No full re-query.
     *                3. QuoteLine     — all MDQ segments for the Quote
     *
     *              Sibling map built directly from Trigger.new — zero SOQL for sibling data.
     *
     * @param newOrderItems  List<OrderItem> from Trigger.new
     */
    public static void fixMissingSegmentsOnNewOrderItems(List<OrderItem> newOrderItems) {
        if (isRunning) {
            return;
        }

        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        if (controls != null
                && controls.Active__c
                && controls.Bypass_Flows__c
                && controls.Orderline_Bypass__c) {
            return;
        }

        // ── Build sibling map and existingKeyMap from Trigger.new — zero SOQLs ────────────────
        // CPQ populates all fields before afterInsert fires, so Trigger.new records are complete.
        // We also seed existingKeyMap here so we don't re-insert OIs already in the current batch.
        Set<Id>                orderIds       = new Set<Id>();
        Map<String, OrderItem> siblingMap     = new Map<String, OrderItem>();
        Map<String, Boolean>   existingKeyMap = new Map<String, Boolean>();

        for (OrderItem oi : newOrderItems) {
            if (oi.SBQQ__SegmentKey__c == null) {
                continue;
            }
            orderIds.add(oi.OrderId);

            String compositeKey = oi.OrderId + '_' + oi.SBQQ__SegmentKey__c + '_'
                                  + String.valueOf(oi.SBQQ__SegmentIndex__c);
            existingKeyMap.put(compositeKey, true);

            String siblingKey = oi.OrderId + '_' + oi.SBQQ__SegmentKey__c;
            if (!siblingMap.containsKey(siblingKey)) {
                siblingMap.put(siblingKey, oi);
            }
        }

        if (orderIds.isEmpty()) {
            return;
        }

        runFixForOrders(orderIds, existingKeyMap, siblingMap);
    }

    /**
     * @description SAFETY-NET entry point — called from OrderTriggerHandler.beforeUpdate.
     *              Fires when an Order transitions to Activated. Acts as a backstop for orders
     *              that bypassed the afterInsert path (e.g. created before this fix deployed).
     *              NOTE: if CPQ's own beforeUpdate trigger fires first and adds an error,
     *              Salesforce rolls back the entire transaction including any DML done here.
     *              The afterInsert path is therefore the reliable primary mechanism.
     *
     * @param newOrders    List<Order> from Trigger.new
     * @param oldOrderMap  Map<Id, Object> from Trigger.oldMap
     */
    public static void fixMissingSegments(List<Order> newOrders, Map<Id, Object> oldOrderMap) {
        if (isRunning) {
            return;
        }

        Set<Id> orderIds = new Set<Id>();
        for (Order ord : newOrders) {
            Order oldOrd = (Order) oldOrderMap.get(ord.Id);
            // Guard against a null old record (partial/empty oldOrderMap passed by a caller or test).
            // Treat a missing old record as not previously Activated — safe conservative default.
            String oldStatus = (oldOrd != null) ? oldOrd.Status : '';
            if (ord.Status == 'Activated'
                    && oldStatus != 'Activated'
                    && ord.SBQQ__Quote__c != null) {
                orderIds.add(ord.Id);
            }
        }
        if (orderIds.isEmpty()) {
            return;
        }

        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        if (controls != null
                && controls.Active__c
                && controls.Bypass_Flows__c
                && controls.Orderline_Bypass__c) {
            return;
        }

        // Safety-net path has no Trigger.new OrderItems — pass null maps; built inside runFixForOrders
        runFixForOrders(orderIds, null, null);
    }

    /**
     * @description Retroactive fix — callable from anonymous Apex to repair pre-existing orders
     *              that were created before the afterInsert hook was deployed.
     *              Example:
     *                  MdqSegmentFixer.fixOrdersById(new Set<Id>{ '801WA00000eKFdOYAW' });
     * @param orderIds  Set of Order IDs to inspect and repair
     */
    public static void fixOrdersById(Set<Id> orderIds) {
        // Bypass flags are intentionally NOT checked here.
        // This is an admin repair tool invoked manually from anonymous Apex — it must always run
        // regardless of Automation_Controls__c settings so that data fixes are not accidentally
        // suppressed by a global bypass flag left active during a data-load window.
        runFixForOrders(orderIds, null, null);
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/

    /**
     * @description Core fix logic shared by all entry points.
     *
     *              afterInsert path (existingKeyMap + siblingMap pre-populated from Trigger.new):
     *                - Runs a lightweight 3-field existence SOQL to catch OIs from prior batches
     *                - Skips full-field OrderItem SOQL entirely
     *
     *              beforeUpdate / fixOrdersById path (existingKeyMap + siblingMap null):
     *                - Runs a full-field OrderItem SOQL to build both maps from scratch
     *
     * @param orderIds        Set of Order IDs to process
     * @param existingKeyMap  Pre-seeded from Trigger.new, or null for safety-net/retroactive path
     * @param siblingMap      Pre-built from Trigger.new, or null for safety-net/retroactive path
     */
    private static void runFixForOrders(
        Set<Id>                orderIds,
        Map<String, Boolean>   existingKeyMap,
        Map<String, OrderItem> siblingMap
    ) {

        // ── SOQL 1: Order.EffectiveDate + SBQQ__Quote__c ─────────────────────────────────────
        Map<Id, Id>   quoteByOrderId     = new Map<Id, Id>();
        Map<Id, Date> ordEffectiveDateMap = new Map<Id, Date>();

        for (Order ord : [
            SELECT Id, SBQQ__Quote__c, EffectiveDate
            FROM   Order
            WHERE  Id IN :orderIds
              AND  SBQQ__Quote__c != null
        ]) {
            quoteByOrderId.put(ord.Id, ord.SBQQ__Quote__c);
            ordEffectiveDateMap.put(ord.Id, ord.EffectiveDate);
        }
        if (quoteByOrderId.isEmpty()) {
            return;
        }

        Map<Id, Id> orderByQuoteId = new Map<Id, Id>();
        for (Id ordId : quoteByOrderId.keySet()) {
            orderByQuoteId.put(quoteByOrderId.get(ordId), ordId);
        }

        // ── SOQL 2: OrderItem existence + sibling data ────────────────────────────────────────
        //
        // afterInsert path (siblingMap != null):
        //   Sibling map already built from Trigger.new — we only run a lightweight existence
        //   SOQL (3 fields) to merge any OIs created in earlier batches of this transaction.
        //
        // beforeUpdate / retroactive path (siblingMap == null):
        //   Full-field SOQL runs to build both existingKeyMap and siblingMap from scratch.
        //
        // In both cases: exactly ONE OrderItem SOQL runs, shaped to what is actually needed.

        Boolean needsSiblingData = (siblingMap == null);

        if (existingKeyMap == null) {
            existingKeyMap = new Map<String, Boolean>();
            siblingMap     = new Map<String, OrderItem>();
        }

        if (needsSiblingData) {
            // beforeUpdate / retroactive path — full field set needed for cloning
            for (OrderItem oi : [
                SELECT Id, OrderId, PricebookEntryId, Product2Id, ListPrice,
                       ServiceDate, EndDate,
                       SBQQ__QuoteLine__c, SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c,
                       SBQQ__DimensionType__c,
                       SBQQ__ChargeType__c, SBQQ__BillingType__c,
                       SBQQ__BillingFrequency__c,
                       SBQQ__SubscriptionTerm__c, SBQQ__DefaultSubscriptionTerm__c,
                       SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c,
                       SBQQ__ProductSubscriptionType__c,
                       SBQQ__ProrateMultiplier__c, SBQQ__PricingMethod__c,
                       SBQQ__QuotedListPrice__c,
                       SBQQ__BookingsIndicator__c, SBQQ__ContractAction__c,
                       SBQQ__ContractingMethod__c, SBQQ__TaxCode__c,
                       SBQQ__Status__c, SBQQ__Activated__c, SBQQ__Contracted__c,
                       ACV_Type__c, Inherited_ACV_Type__c, CPQ_Option_Type__c,
                       OSA_Number__c, Software_Payment_Term__c, Support_Level__c,
                       Days_In_Advance__c, Description
                FROM   OrderItem
                WHERE  OrderId IN :orderIds
                  AND  SBQQ__SegmentKey__c != null
            ]) {
                String compositeKey = oi.OrderId + '_' + oi.SBQQ__SegmentKey__c + '_'
                                      + String.valueOf(oi.SBQQ__SegmentIndex__c);
                existingKeyMap.put(compositeKey, true);

                String siblingKey = oi.OrderId + '_' + oi.SBQQ__SegmentKey__c;
                if (!siblingMap.containsKey(siblingKey)) {
                    siblingMap.put(siblingKey, oi);
                }
            }
            if (siblingMap.isEmpty()) {
                return; // No MDQ OrderItems found — nothing to fix
            }
        } else {
            // afterInsert path — lightweight existence-only SOQL to catch prior-batch OIs.
            // Only three fields selected — minimal governor and heap cost.
            for (OrderItem oi : [
                SELECT Id, OrderId, SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c
                FROM   OrderItem
                WHERE  OrderId IN :orderIds
                  AND  SBQQ__SegmentKey__c != null
            ]) {
                String compositeKey = oi.OrderId + '_' + oi.SBQQ__SegmentKey__c + '_'
                                      + String.valueOf(oi.SBQQ__SegmentIndex__c);
                existingKeyMap.put(compositeKey, true);
            }
        }

        // ── SOQL 3: QuoteLine segment query ───────────────────────────────────────────────────
        // Targets only zero-qty MDQ segments — the exact segments CPQ skips during ordering.
        // CPQ always creates OrderItems for non-zero-qty QuoteLines, so restricting to
        // SBQQ__Quantity__c = 0 is safe and reduces the result set.
        List<SBQQ__QuoteLine__c> segmentQls = [
            SELECT Id, SBQQ__Quote__c,
                   SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c,
                   SBQQ__EffectiveStartDate__c, SBQQ__EffectiveEndDate__c,
                   SBQQ__StartDate__c, SBQQ__EndDate__c,
                   SBQQ__ProrateMultiplier__c
            FROM   SBQQ__QuoteLine__c
            WHERE  SBQQ__Quote__c      IN :orderByQuoteId.keySet()
              AND  SBQQ__SegmentKey__c != null
              AND  SBQQ__Quantity__c    = 0
        ];
        if (segmentQls.isEmpty()) {
            return;
        }

        // ── Detect missing segments and build OrderItems ──────────────────────────────────────
        List<OrderItem> toInsert = new List<OrderItem>();

        for (SBQQ__QuoteLine__c ql : segmentQls) {
            Id orderId = orderByQuoteId.get(ql.SBQQ__Quote__c);
            if (orderId == null) {
                continue;
            }

            String compositeKey = orderId + '_' + ql.SBQQ__SegmentKey__c + '_'
                                  + String.valueOf(ql.SBQQ__SegmentIndex__c);
            if (existingKeyMap.containsKey(compositeKey)) {
                continue; // Segment already exists — idempotent, skip
            }

            String siblingKey = orderId + '_' + ql.SBQQ__SegmentKey__c;
            OrderItem sibling = siblingMap.get(siblingKey);
            if (sibling == null) {
                continue; // No sibling to clone from — cannot safely build the record
            }

            toInsert.add(buildMissingOrderItem(orderId, ordEffectiveDateMap.get(orderId), ql, sibling));
        }

        if (toInsert.isEmpty()) {
            return;
        }

        // ── Bulk insert all missing segments ──────────────────────────────────────────────────
        // isRunning prevents OrderProduct.afterInsert from recursing back here.
        // SBQQ.TriggerControl.disable() suppresses CPQ triggers AND lifts the platform
        // Quantity = 0 constraint for MDQ segment OrderItems (requires "Enable Zero Quantity"
        // on the Order, which CPQ sets automatically when ordering an MDQ quote).
        List<Database.SaveResult> results;
        try {
            isRunning = true;
            SBQQ.TriggerControl.disable();
            results = Database.insert(toInsert, false);
        } finally {
            SBQQ.TriggerControl.enable();
            isRunning = false;
        }

        // Capture errors for test visibility
        if (Test.isRunningTest()) {
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        String msg = err.getStatusCode() + ': ' + err.getMessage();
                        if (!err.getFields().isEmpty()) {
                            msg += ' [fields: ' + String.join(err.getFields(), ', ') + ']';
                        }
                        testInsertErrors.add('Row ' + i + ' — ' + msg);
                    }
                }
            }
        }

        ResultHandler.logErrors('MdqSegmentFixer.runFixForOrders', toInsert, results);
    }

    /**
     * @description Builds a missing MDQ segment OrderItem by combining:
     *              - Segment identity and date fields from the zero-qty QuoteLine
     *              - Shared product/billing fields cloned from a sibling OrderItem
     *              - All monetary/quantity fields zeroed (it is a zero-qty segment by definition)
     *
     * @param orderId          The Order this segment belongs to
     * @param ordEffectiveDate The Order's EffectiveDate — used to clamp ServiceDate
     * @param ql               The QuoteLine representing the missing segment
     * @param sibling          An existing OrderItem from the same SegmentKey group for field cloning
     * @return                 A new OrderItem ready for insertion
     */
    private static OrderItem buildMissingOrderItem(
        Id orderId, Date ordEffectiveDate,
        SBQQ__QuoteLine__c ql, OrderItem sibling
    ) {
        OrderItem missing = new OrderItem();

        // ── Parent Order ──────────────────────────────────────────────────────────────────────
        missing.OrderId = orderId;

        // ── Product and pricebook ─────────────────────────────────────────────────────────────
        missing.PricebookEntryId = sibling.PricebookEntryId;
        missing.Product2Id       = sibling.Product2Id;
        missing.ListPrice        = sibling.ListPrice;

        // ── Segment identity ──────────────────────────────────────────────────────────────────
        missing.SBQQ__QuoteLine__c    = ql.Id;
        missing.SBQQ__SegmentKey__c   = ql.SBQQ__SegmentKey__c;
        missing.SBQQ__SegmentIndex__c = ql.SBQQ__SegmentIndex__c;

        // ── Date resolution — primary: EffectiveStart/EndDate; fallback: Start/EndDate ────────
        Date startDate = ql.SBQQ__EffectiveStartDate__c != null
            ? ql.SBQQ__EffectiveStartDate__c : ql.SBQQ__StartDate__c;
        Date endDate   = ql.SBQQ__EffectiveEndDate__c != null
            ? ql.SBQQ__EffectiveEndDate__c   : ql.SBQQ__EndDate__c;

        // Clamp ServiceDate to Order.EffectiveDate if the QL start predates it
        Boolean startClamped = false;
        if (ordEffectiveDate != null && (startDate == null || startDate < ordEffectiveDate)) {
            startDate    = ordEffectiveDate;
            startClamped = true;
        }
        // Derive endDate from sibling duration ONLY when start was clamped and endDate became invalid
        if (startClamped && (endDate == null || endDate < startDate)) {
            Integer segDays = (sibling.ServiceDate != null && sibling.EndDate != null)
                ? sibling.ServiceDate.daysBetween(sibling.EndDate) : 364;
            endDate = startDate.addDays(segDays);
        }
        // Safety guard: platform rejects EndDate < ServiceDate regardless of other settings
        if (endDate != null && endDate < startDate) {
            endDate = null;
        }
        missing.ServiceDate = startDate;
        missing.EndDate     = endDate;

        // ── ProrateMultiplier — from QL (may vary per segment year); fallback to sibling ──────
        missing.SBQQ__ProrateMultiplier__c = ql.SBQQ__ProrateMultiplier__c != null
            ? ql.SBQQ__ProrateMultiplier__c
            : sibling.SBQQ__ProrateMultiplier__c;

        // ── CPQ fields — identical across all segments of the same MDQ product ─────────────────
        missing.SBQQ__DimensionType__c           = sibling.SBQQ__DimensionType__c;
        missing.SBQQ__ChargeType__c              = sibling.SBQQ__ChargeType__c;
        missing.SBQQ__BillingType__c             = sibling.SBQQ__BillingType__c;
        missing.SBQQ__BillingFrequency__c        = sibling.SBQQ__BillingFrequency__c;
        missing.SBQQ__SubscriptionTerm__c        = sibling.SBQQ__SubscriptionTerm__c;
        missing.SBQQ__DefaultSubscriptionTerm__c = sibling.SBQQ__DefaultSubscriptionTerm__c;
        missing.SBQQ__SubscriptionType__c        = sibling.SBQQ__SubscriptionType__c;
        missing.SBQQ__SubscriptionPricing__c     = sibling.SBQQ__SubscriptionPricing__c;
        missing.SBQQ__ProductSubscriptionType__c = sibling.SBQQ__ProductSubscriptionType__c;
        missing.SBQQ__PricingMethod__c           = sibling.SBQQ__PricingMethod__c;
        missing.SBQQ__QuotedListPrice__c         = sibling.SBQQ__QuotedListPrice__c;
        missing.SBQQ__BookingsIndicator__c       = sibling.SBQQ__BookingsIndicator__c;
        missing.SBQQ__ContractAction__c          = sibling.SBQQ__ContractAction__c;
        missing.SBQQ__ContractingMethod__c       = sibling.SBQQ__ContractingMethod__c;
        missing.SBQQ__TaxCode__c                 = sibling.SBQQ__TaxCode__c;
        // SBQQ__Status__c, SBQQ__Contracted__c, SBQQ__Activated__c intentionally NOT set —
        // validation rules block direct writes; platform applies safe defaults.

        // ── Custom Intapp fields — cloned from sibling ────────────────────────────────────────
        missing.ACV_Type__c              = sibling.ACV_Type__c;
        missing.Inherited_ACV_Type__c    = sibling.Inherited_ACV_Type__c;
        missing.CPQ_Option_Type__c       = sibling.CPQ_Option_Type__c;
        missing.OSA_Number__c            = sibling.OSA_Number__c;
        missing.Software_Payment_Term__c = sibling.Software_Payment_Term__c;
        missing.Support_Level__c         = sibling.Support_Level__c;
        missing.Days_In_Advance__c       = sibling.Days_In_Advance__c;
        missing.Description              = sibling.Description;

        // ── Monetary / quantity fields — all zeroed ───────────────────────────────────────────
        // Quantity = 0 matches the zero-qty QuoteLine this segment represents.
        // "Enable Zero Quantity" must be enabled on the Order (CPQ sets this automatically
        // when ordering an MDQ quote). SBQQ.TriggerControl.disable() suppresses the standard
        // platform validation that would otherwise reject Quantity = 0 on OrderItem.
        missing.Quantity                         = 0;
        missing.UnitPrice                        = 0;
        missing.ACV__c                           = 0;
        missing.SBQQ__QuotedQuantity__c          = 0;
        missing.SBQQ__OrderedQuantity__c         = 0;
        missing.Customer_Sale_Price_Per_Month__c = 0;
        missing.Net_Unit_Price__c                = 0;

        return missing;
    }
}