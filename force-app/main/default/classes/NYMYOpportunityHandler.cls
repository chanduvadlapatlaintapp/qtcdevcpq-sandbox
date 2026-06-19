public class NYMYOpportunityHandler {
    public static void updateNYMYOpp(Set<Id> amendedOpportunityIds){
        if(!amendedOpportunityIds.isEmpty()){
            List<Opportunity> amendedOpportunities = [
                SELECT Id, Associated_Contract_OSA__c, Quote_Start_Date__c
                FROM Opportunity
                WHERE Id IN :amendedOpportunityIds
            ];
            Set<Id> contractIds = new Set<Id>();
            Set<Id> relatedNYMY = new Set<Id>();
            if(!amendedOpportunities.IsEmpty()){
                for (Opportunity opp : amendedOpportunities) {
                    if (opp.Associated_Contract_OSA__c != null) {
                        contractIds.add(opp.Associated_Contract_OSA__c);
                    }
                }
                if(!contractIds.IsEmpty()){
                    // NYMYs are cloned from the base opportunity at Closed Won time, before the
                    // contract is created. This means Associated_Contract_OSA__c is null on the
                    // NYMY at creation. CloneOptyWithLineItems always sets Related_Opportunity__c
                    // back to the original base opp, so we use that as a reliable fallback.
                    Set<Id> baseOppIds = new Set<Id>(amendedOpportunityIds);
                    for (Opportunity baseOpp : [
                        SELECT Id FROM Opportunity
                        WHERE Associated_Contract_OSA__c IN :contractIds
                        AND Deal_Type__c != :OpportunityConstants.DEAL_TYPE_NYMY
                    ]) {
                        baseOppIds.add(baseOpp.Id);
                    }
                    List<Opportunity> nymyOpp = [
                        SELECT id, Deal_Type__c, StageName FROM Opportunity
                        WHERE Deal_Type__c = :OpportunityConstants.DEAL_TYPE_NYMY
                        AND (Associated_Contract_OSA__c IN :contractIds
                             OR Related_Opportunity__c IN :baseOppIds)
                        ORDER BY CreatedDate ASC
                    ];
                    if(!nymyOpp.IsEmpty()){
                        for(Opportunity o : nymyOpp){
                            if(o.Deal_Type__c == 'NextYear_MultiYear'){
                                relatedNYMY.add(o.Id);
                            }
                        }
                        if(!relatedNYMY.isEmpty()){
                            insertOptyLines(relatedNYMY, amendedOpportunities);
                        }
                    }
                }
            }
        }
    }
    private static void insertOptyLines(Set<Id> relatedNYMY, List<Opportunity> amendedOpportunities){
        Set<Id> setAmendedandNYMYOpportunities = new Set<Id>();
        Set<Id> amendedIds = new Set<Id>();
        List<OpportunityLineItem> originalOptyLines = new List<OpportunityLineItem>();

        // Build map of amendment start dates for date-range filtering.
        // Amendment lines are only folded into NYMYs whose period starts AFTER
        // the amendment's own start date.
        Map<Id, Date> amendmentStartDates = new Map<Id, Date>();
        for (Opportunity op : amendedOpportunities) {
            amendedIds.add(op.Id);
            if (op.Quote_Start_Date__c != null) {
                amendmentStartDates.put(op.Id, op.Quote_Start_Date__c);
            }
        }
        // Fallback when Quote_Start_Date__c is null at trigger time (Quote_After_Insert_Update
        // flow hasn't populated it yet): derive the amendment's start date from the earliest
        // SBQQ__QuoteLine__c.SBQQ__StartDate__c across its OLIs. CPQ sets that at quote time,
        // so it is reliable at trigger time. Note we deliberately take MIN at the opp level so
        // the guard remains opp-level (a multi-segment amendment uses its earliest segment start).
        Set<Id> oppsMissingStart = new Set<Id>(amendedIds);
        oppsMissingStart.removeAll(amendmentStartDates.keySet());
        if (!oppsMissingStart.isEmpty()) {
            for (AggregateResult ar : [
                SELECT OpportunityId oppId, MIN(SBQQ__QuoteLine__r.SBQQ__StartDate__c) earliest
                FROM OpportunityLineItem
                WHERE OpportunityId IN :oppsMissingStart
                GROUP BY OpportunityId
            ]) {
                Date earliest = (Date) ar.get('earliest');
                if (earliest != null) {
                    amendmentStartDates.put((Id) ar.get('oppId'), earliest);
                }
            }
        }
        setAmendedandNYMYOpportunities.addAll(amendedIds);
        setAmendedandNYMYOpportunities.addAll(relatedNYMY);
        List<Opportunity> relatedNYMYList = [
            SELECT Id, OP4I_Deal_Id__c, StageName, Deal_Reconciliation_Notes_OP4I__c, Quote_Start_Date__c
            FROM Opportunity
            WHERE Id IN :relatedNYMY
        ];
        String strQuery = createQuery(setAmendedandNYMYOpportunities);
        for(OpportunityLineItem oOLI: Database.query(strQuery)){
            if(amendedIds.contains(oOLI.OpportunityId)){
                originalOptyLines.add(oOLI);
            }
        }
        if (originalOptyLines.isEmpty()) {
            return;
        }
        List<OpportunityLineItem> allClonedLines = new List<OpportunityLineItem>();
        List<Opportunity> closedWonToUpdate = new List<Opportunity>();
        for (Opportunity nymyOpp : relatedNYMYList) {
            List<OpportunityLineItem> clonedOptyLines = new List<OpportunityLineItem>();
            Map<String, Decimal> acvBySegKeyAndIndex = new Map<String, Decimal>();
            Map<Id, String> mapOliIdToSegmentKey = new Map<Id, String>();
            for (OpportunityLineItem oli : originalOptyLines) {
                if (oli != null){
                    // Date-range guard: only fold into this NYMY if its period starts
                    // strictly after the amendment's start date. The map already contains
                    // either Quote_Start_Date__c (post-flow) or the earliest QL start date
                    // (trigger-time fallback computed above). When neither is available the
                    // guard is skipped (safe fallback to original behaviour).
                    Date amendmentStart = amendmentStartDates.get(oli.OpportunityId);
                    if (amendmentStart != null && nymyOpp.Quote_Start_Date__c != null
                            && nymyOpp.Quote_Start_Date__c <= amendmentStart) {
                        continue;
                    }
                    OpportunityLineItem clonedLineRec = oli.clone(false, false, false, false);
                    clonedLineRec.UnitPrice = null;
                    clonedLineRec.OpportunityId = nymyOpp.Id;
                    clonedLineRec.OP4I_Deal_Id__c = nymyOpp.OP4I_Deal_Id__c;
                    clonedLineRec.OP4I_System_Id__c = null;
                    clonedLineRec.DLIP_OP4I_ID__c = null;
                    clonedLineRec.SBQQ__QuoteLine__c = null;
                    clonedLineRec.Original_Opportunity_Product_Id__c = oli.Id;
                    clonedLineRec.Original_Oppty_Text_Id__c = oli.Id;
                    if(oli.SBQQ__QuoteLine__r != null && oli.SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c != null){
                        String lastChar = oli.SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c.right(1);
                        clonedLineRec.Segment_Index__c = Integer.valueOf(lastChar);
                    }
                    else{
                        clonedLineRec.Segment_Index__c = null;
                    }
                    Decimal ppm  = (oli.Customer_Sales_Price_Per_Month__c == null) ? 0 : oli.Customer_Sales_Price_Per_Month__c;
                    Decimal qty  = (oli.Quantity == null) ? 0 : oli.Quantity;
                    Decimal currAcv = ppm * qty * 12;
                    clonedLineRec.ACV__c = currAcv;
                    clonedLineRec.ACV_Change__c = 0;
                    String segmentKey = (oli.SBQQ__QuoteLine__r != null)? oli.SBQQ__QuoteLine__r.SBQQ__SegmentKey__c: null;
                    if (!String.isBlank(segmentKey) && clonedLineRec.Segment_Index__c != null) {
                        acvBySegKeyAndIndex.put(segmentKey + ':' + String.valueOf(clonedLineRec.Segment_Index__c), currAcv);
                    }
                    clonedOptyLines.add(clonedLineRec);
                    mapOliIdToSegmentKey.put(oli.Id, segmentKey);
                }
            }
            for (OpportunityLineItem clonedLineRec: clonedOptyLines) {
                String segKey = mapOliIdToSegmentKey.get(clonedLineRec.Original_Opportunity_Product_Id__c);
                Integer idx = (clonedLineRec.Segment_Index__c == null) ? null : Integer.valueOf(clonedLineRec.Segment_Index__c);
                if (idx != null && idx > 1 && !String.isBlank(segKey)) {
                    String prevKey = segKey + ':' + String.valueOf(idx - 1);
                    Decimal prevAcv = acvBySegKeyAndIndex.get(prevKey);
                    if (prevAcv != null) {
                        clonedLineRec.ACV_Change__c = clonedLineRec.ACV__c - prevAcv;
                    }
                }
            }
            // Only update reconciliation note and accumulate lines when at least one OLI
            // was actually folded into this NYMY (clonedOptyLines could be empty if all
            // were filtered out by the date-range guard).
            if (!clonedOptyLines.isEmpty()) {
                allClonedLines.addAll(clonedOptyLines);
                if (nymyOpp.StageName == OpportunityConstants.STAGE_CLOSED_WON) {
                    String dateStr = String.valueOf(Date.today().year())
                                   + '-' + String.valueOf(Date.today().month()).leftPad(2, '0')
                                   + '-' + String.valueOf(Date.today().day()).leftPad(2, '0');
                    String newNote = 'Automated Note | ' + dateStr + ' amendment lines folded in post NYMY closure';
                    String existing = nymyOpp.Deal_Reconciliation_Notes_OP4I__c;
                    nymyOpp.Deal_Reconciliation_Notes_OP4I__c = String.isBlank(existing) ? newNote : newNote + '\n' + existing;
                    closedWonToUpdate.add(nymyOpp);
                }
            }
        }
        if (!allClonedLines.isEmpty()){
            insert allClonedLines;
        }
        if (!closedWonToUpdate.isEmpty()) {
            update closedWonToUpdate;

            // Explicitly publish DealEvent__e for the NYMY changes. OpportunityTriggerHelper's
            // firstCall reentrance guard is already true (set by the amendment's own publish),
            // so the nested trigger fired by the update DML would silently skip these records.
            // We bypass IntegrationUtility.publishEligibleSobjectRecords (which calls isChanged
            // against every tracked field — our records are sparsely populated and would throw
            // SObjectException) and publish directly. We know the audit-text field changed.
            IntegrationUtility.publishsObjectRecords(closedWonToUpdate, 'Opportunity');
        }
    }
    public static string createQuery(set<Id> setAmendedandNYMYOpportunities)
    {
        set<String> fieldNames = new set<String>();
        Schema.SObjectType targetObjType = Schema.getGlobalDescribe().get('OpportunityLineItem');
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List<String> fields = new List<String>(fieldNames);
        String query =  ' SELECT ' +
            String.join( fields, ',' ) +
            ',CreatedBy.Name ' + ',SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c ' + ',SBQQ__QuoteLine__r.SBQQ__SegmentKey__c ' +
            ',SBQQ__QuoteLine__r.SBQQ__UpgradedSubscription__c ' + ',SBQQ__QuoteLine__r.SBQQ__StartDate__c ' +
            ' FROM ' +
            'OpportunityLineItem' +
            ' WHERE ' +
            ' OpportunityId IN: setAmendedandNYMYOpportunities AND Product_Type__c NOT IN (\'Services\', \'Services Discount\', \'Services (Recurring)\')';
        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}');
        return strQuery2;
    }
}