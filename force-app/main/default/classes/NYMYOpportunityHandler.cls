public class NYMYOpportunityHandler {
    public static void updateNYMYOpp(Set<Id> amendedOpportunityIds){
        if(!amendedOpportunityIds.isEmpty()){
            List<Opportunity> amendedOpportunities = [
                SELECT Id, Associated_Contract_OSA__c
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
                    List<Opportunity> nymyOpp = [SELECT id, Deal_Type__c, StageName FROM Opportunity where Associated_Contract_OSA__c IN : contractIds 
                                                 AND Deal_Type__c = 'NextYear_MultiYear'
                                                 AND StageName != 'Closed Won' 
                                                 order by CreatedDate desc limit 1];
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
        for (Opportunity op : amendedOpportunities) {
            amendedIds.add(op.Id);
        }
        setAmendedandNYMYOpportunities.addAll(amendedIds);
        setAmendedandNYMYOpportunities.addAll(relatedNYMY);
        List<Opportunity> relatedNYMYList = [
            SELECT Id, OP4I_Deal_Id__c
            FROM Opportunity
            WHERE Id IN :relatedNYMY
        ];
        String strQuery = createQuery(setAmendedandNYMYOpportunities);
        for(OpportunityLineItem oOLI: Database.query(strQuery)){
            if(amendedIds.contains(oOLI.OpportunityId)){
                originalOptyLines.add(oOLI);
            }
        }
        List<OpportunityLineItem> clonedOptyLines = new List<OpportunityLineItem>();
        Map<String, Decimal> acvBySegKeyAndIndex = new Map<String, Decimal>();
        Map<Id, String>  mapOliIdTosegmentKey = new Map<Id, String>();
        for (OpportunityLineItem oli : originalOptyLines) {
            if (oli != null){ 
                OpportunityLineItem clonedLineRec = oli.clone(false, false, false, false);
                clonedLineRec.UnitPrice = null;
                clonedLineRec.OpportunityId = relatedNYMYList[0].Id;
                clonedLineRec.OP4I_Deal_Id__c = relatedNYMYList[0].OP4I_Deal_Id__c;                
                clonedLineRec.OP4I_System_Id__c = null;
                clonedLineRec.DLIP_OP4I_ID__c = null;
                clonedLineRec.SBQQ__QuoteLine__c = null;                
                clonedLineRec.Original_Opportunity_Product_Id__c = oli.Id;
                clonedLineRec.Original_Oppty_Text_Id__c = oli.id;
                if(oli.SBQQ__QuoteLine__r != null && oli.SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c != null){
                    String lastChar = oli.SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c.right(1);
                    clonedLineRec.Segment_Index__c = Integer.valueOf(lastChar);                    
                }
                else{
                    clonedLineRec.Segment_Index__c = null;
                }
                Decimal ppm  = (oli.Customer_Sales_Price_Per_Month__c == null) ? 0 : oli.Customer_Sales_Price_Per_Month__c;
                Decimal qty  = (oli.Quantity == null) ? 0 : oli.Quantity;
                Decimal term = 12;// term should be annualiized
                Decimal currAcv = ppm * qty * term;
                clonedLineRec.ACV__c = currAcv;
                clonedLineRec.ACV_Change__c = 0;
                String segmentKey = (oli.SBQQ__QuoteLine__r != null)? oli.SBQQ__QuoteLine__r.SBQQ__SegmentKey__c: null;
                if (!String.isBlank(segmentKey) && clonedLineRec.Segment_Index__c != null) {
                    acvBySegKeyAndIndex.put(segmentKey + ':' + String.valueOf(clonedLineRec.Segment_Index__c), currAcv);
                }
                clonedOptyLines.add(clonedLineRec);
                mapOliIdTosegmentKey.put(clonedLineRec.Original_Opportunity_Product_Id__c, segmentKey);
            }
        }
        for (OpportunityLineItem clonedLineRec: clonedOptyLines) {
            
            String segKey = mapOliIdTosegmentKey.get(clonedLineRec.Original_Opportunity_Product_Id__c);
            Integer idx = (clonedLineRec.Segment_Index__c == null) ? null : Integer.valueOf(clonedLineRec.Segment_Index__c);
            if (idx != null && idx > 1 && !String.isBlank(segKey)) {
                String prevKey = segKey + ':' + String.valueOf(idx - 1);
                Decimal prevAcv = acvBySegKeyAndIndex.get(prevKey);
                if (prevAcv != null) {
                    clonedLineRec.ACV_Change__c = clonedLineRec.ACV__c - prevAcv;
                }
            }
        }
        if (!clonedOptyLines.isEmpty()){
            insert clonedOptyLines;
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
            ',SBQQ__QuoteLine__r.SBQQ__UpgradedSubscription__c ' +
            ' FROM ' +
            'OpportunityLineItem' +
            ' WHERE ' +
            ' OpportunityId IN: setAmendedandNYMYOpportunities AND Product_Type__c NOT IN (\'Services\', \'Services Discount\', \'Services (Recurring)\')';
        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}'); 
        return strQuery2;
    }
}