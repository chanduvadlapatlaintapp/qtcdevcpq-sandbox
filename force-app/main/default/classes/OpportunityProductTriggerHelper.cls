/**
* @description Trigger helper class for OpportunityProductTrigger 
* @author Pooja Hemrajani
* @jira BIZ-66418
* @update BIZ-77496 - Replace Segment_Months__c with SBQQ__ProrateMultiplier__c in updateOLIFromGhostQL method
**/
public inherited sharing class OpportunityProductTriggerHelper {
    
    private static Boolean isDelayJobScheduled = false;
    /***********************************************************************************************
    *
    * Public Static Methods
    *
    ***********************************************************************************************/
    /**
     * @description This method updates the Segment_Bundle_Line__c field on static component products by mapping them 
     *              to their corresponding static bundle parent products using quote line references within the provided 
     *              opportunity line items.
     * @param lstNewOpportunityProducts - List of opportunity products to evaluate and update
     */
    public static void updateSegmentedBundleId(List<OpportunityLineItem> lstNewOpportunityProducts){

        Map<String, Id> mapStaticBundleMap = new Map<String, Id>();
        Map<String, Id> mapSegmentBundleMap = new Map<String, Id>();
        List<OpportunityLineItem> lstOppProductsToUpdate = new List<OpportunityLineItem>();
        List<OpportunityLineItem> oppLineItemProductsList = getOpportunityLineItem(lstNewOpportunityProducts);
        for (OpportunityLineItem opProd : lstNewOpportunityProducts) {
            if (opProd.Original_Oppty_Text_Id__c != null ) {
                mapSegmentBundleMap.put(opProd.Original_Oppty_Text_Id__c,opProd.Id);
            }
        }
        for (OpportunityLineItem opProd : lstNewOpportunityProducts) {
            if(mapSegmentBundleMap.containsKey(opProd.Segment_Bundle_Line__c)) {
           		lstOppProductsToUpdate.add(
                   new OpportunityLineItem(
                            Id = opProd.Id, 
                            Segment_Bundle_Line__c = mapSegmentBundleMap.get(opProd.Segment_Bundle_Line__c) 
                        )
                    );
            }
        }
        // Update Opportunity Line Item
        if(lstOppProductsToUpdate.size() > 0) {
        	try {
            	update lstOppProductsToUpdate;
        	} catch (Exception e) {
            	Nebula.Logger.error('OpportunityProductTriggerHandler Update Opportunity Products', lstOppProductsToUpdate, e);
        	} finally {
            	Nebula.Logger.saveLog();
        	}
        }
        // Exit early if no Opportunity Products found
        if (oppLineItemProductsList.isEmpty()) {
            return;
        }
        
        // Identify most parent products and segmented bundle parents
        for (OpportunityLineItem opProd : oppLineItemProductsList) {
            if (opProd.CPQ_Option_Type__c == SubscriptionConstants.OPTION_TYPE_STATIC_BUNDLE && opProd.SBQQ__QuoteLine__r.Line_Item_Key__c != null) {
                // Segmented Bundle Parent
                mapStaticBundleMap.put(opProd.SBQQ__QuoteLine__r.Line_Item_Key__c, opProd.Id);
            }
        }
        for (OpportunityLineItem opProd : oppLineItemProductsList) {
            if (opProd.CPQ_Option_Type__c == SubscriptionConstants.OPTION_TYPE_STATIC_COMPONENT && opProd.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c != null ) {
                
                String unique = opProd.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c;
                // Segmented Bundle Parent
                if(mapStaticBundleMap.containsKey(unique)){
                    lstOppProductsToUpdate.add(
                        new OpportunityLineItem(
                            Id = opProd.Id, 
                            Segment_Bundle_Line__c = mapStaticBundleMap.get(unique) 
                        )
                    );
                }
            }
        }

        // Update Opportunity Line Item
        try {
            update lstOppProductsToUpdate;
        } catch (Exception e) {
            Nebula.Logger.error('OpportunityProductTriggerHandler Update Opportunity Products', lstOppProductsToUpdate, e);
        } finally {
            Nebula.Logger.saveLog();
        }
    }
    public static Boolean isfirstRun = true;
    public static void updateRenewalSegmentedBundleId(List<OpportunityLineItem> lstNewOpportunityProducts){
        Map<Id, Id> mapOliToParentOpp = new Map<Id, Id>();
        for(OpportunityLineItem oli: lstNewOpportunityProducts){
            if(oli.Subscriptions__c != null){
                mapOliToParentOpp.put(oli.Subscriptions__c, oli.Id);
            }
        }
        if(mapOliToParentOpp.isEmpty()) return;
        List<OpportunityLineItem> lstOlis = new List<OpportunityLineItem>();
        for(OpportunityLineItem oli: [SELECT Id, Subscriptions__r.Parent_of_Bundle__c, Subscriptions__r.SBQQ__SegmentStartDate__c, Subscriptions__r.SBQQ__SegmentEndDate__c,
                                      Subscriptions__r.Segment_Bundle_Line__c, Subscriptions__c FROM OpportunityLineItem 
                                      WHERE Id IN: lstNewOpportunityProducts AND Subscriptions__c != null and Subscriptions__r.Segment_Bundle_Line__c != null]){
            if(mapOliToParentOpp.containsKey(oli.Subscriptions__r.Segment_Bundle_Line__c)){
                lstOlis.add(new OpportunityLineItem(Id = oli.id, Segment_Bundle_Line__c = mapOliToParentOpp.get(oli.Subscriptions__r.Segment_Bundle_Line__c)));
            }
        }
        update lstOlis;
    }

    /**
     * @description - This method handles the update of Opportunity Line Items.
     * It filters out Opportunity Line Items that are not related to migration opportunities and publishes them 
     * @param oppProdNewList
     * @param oppProd
     */
    public static void opportunityProductEventafterUpdate(List < OpportunityLineItem > oppProdNewList, Map < Id, OpportunityLineItem > oppProd) {
     
        List < OpportunityLineItem > opportunityItemList = new List < OpportunityLineItem > ();
        Id oppRecordTypeId = RecordTypeUtil.getRecordTypeId(Opportunity.SObjectType, OpportunityConstants.RT_MIGRATION_OPP);

        set < Id > setOfOli = new set < id > ();
        //change for BIZ-65768 POC  
        TimeZone oTimeZone = UserInfo.getTimeZone();
        DateTime dtCurrentUserTime = Datetime.now().addSeconds((oTimeZone.getOffset(Datetime.now())/1000));
        //End of change for BIZ-65768 POC
        for (OpportunityLineItem oli: oppProdNewList) {
            setOfOli.add(oli.id);
        }
        String strQuery = createQuery(setOfOli);
        List < OpportunityLineItem > lstOfOpportunityItem = Database.query(strQuery);
        for (OpportunityLineItem oppLineItem: lstOfOpportunityItem) {
            
             Boolean isValidByOptionType = (
                            // Condition 1: Static Bundle requires OP4I_System_Id__c
                            (oppLineItem.CPQ_Option_Type__c == SubscriptionConstants.OPTION_TYPE_STATIC_BUNDLE && String.isNotBlank(oppLineItem.OP4I_System_Id__c)) ||
                            // Condition 2: Static Component requires DLIP_OP4I_ID__c
                            (oppLineItem.CPQ_Option_Type__c == SubscriptionConstants.OPTION_TYPE_STATIC_COMPONENT && String.isNotBlank(oppLineItem.DLIP_OP4I_ID__c)) ||
                            // Condition 3: Blank Option Type requires both IDs to be present
                            (String.isBlank(oppLineItem.CPQ_Option_Type__c) &&
                             String.isNotBlank(oppLineItem.OP4I_System_Id__c) &&
                             String.isNotBlank(oppLineItem.DLIP_OP4I_ID__c))
                        );
                                
        	//change for BIZ-65768 POC  
            if ((oppLineItem.Opportunity.RecordTypeId != oppRecordTypeId && !(String.isNotBlank(oppLineItem.Opportunity.Renewal_Quote_Type__c) &&
                oppLineItem.Opportunity.Renewal_Quote_Type__c.equalsIgnoreCase('Auto-Renewal') && 
                (String.isBlank(oppLineItem.OP4I_System_Id__c) || (String.isNotBlank(oppLineItem.OP4I_System_Id__c) 
                && oppLineItem.OP4I_System_Id__c.containsIgnoreCase('OP4I'))) && String.isBlank(oppLineItem.OP4I_Error__c) 
                && dtCurrentUserTime < oppLineItem.CreatedDate.addMinutes(7))
                && isValidByOptionType) || oppLineItem.Retrigger_OP4I_Sync__c) {
            //End of change for BIZ-65768 POC
                opportunityItemList.add(oppLineItem);
            }
        }

        if (opportunityItemList.Size() > 0) {
            publishOppLineItems(opportunityItemList, oppProd);
        }
    }

    /**
     * @description - This method handles the deletion of Opportunity Line Items.
     * It filters out Opportunity Line Items that are not related to migration opportunities and publishes them 
     * @param oppProdOldList
     */
    public static void opportunityProductEventafterDelete(List<OpportunityLineItem> oppProdOldList) {
        List<OpportunityLineItem> cancelList = new List<OpportunityLineItem>();
        List<OpportunityLineItem> deleteList = new List<OpportunityLineItem>();
        Id migrationRtId = RecordTypeUtil.getRecordTypeId(Opportunity.SObjectType,OpportunityConstants.RT_MIGRATION_OPP);
        Map<Id, OpportunityLineItem> quoteLineMap = new Map<Id, OpportunityLineItem>();
        
        for (OpportunityLineItem oli : oppProdOldList) {
            if (oli.Renewal_Quote_Type__c == null) {
                if (oli.Opportunity.RecordTypeId != migrationRtId) {
                    deleteList.add(oli);
                }
            } else {
                if (oli.SBQQ__QuoteLine__c != null) {
                    quoteLineMap.put(oli.SBQQ__QuoteLine__c, oli);
                } else if (oli.Opportunity.RecordTypeId != migrationRtId) {
                    deleteList.add(oli);
                }
            }
        }
        
        if (!quoteLineMap.isEmpty()) {
            for (SBQQ__QuoteLine__c ql : [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id IN :quoteLineMap.keySet()]) {
                if (ql.SBQQ__Quantity__c == 0) {
                    cancelList.add(quoteLineMap.get(ql.Id));
                }
            }
        }
        
        if (!isDelayJobScheduled) {
            isDelayJobScheduled = true;
            Integer delayMinutes = 2;
            
            if (!cancelList.isEmpty()) {
                OpportunityProductDelayScheduler.scheduleAfterMinutes(delayMinutes, cancelList, 'Cancelled');
            }
            
            if (!deleteList.isEmpty()) {
                OpportunityProductDelayScheduler.scheduleAfterMinutes( delayMinutes,deleteList, 'Delete');
            }
        }
    }

    /**
     * @description - This method publishes Opportunity Line Items based on certain conditions.
     * @param newList List of Opportunity Line Items to be considered for publishing.
     * @param oldMap Map of old Opportunity Line Items for comparison.
     */
    public static void publishOppLineItems(List < OpportunityLineItem > newList, Map < Id, OpportunityLineItem > oldMap) {

        // Sets to store unique Opportunity Ids and Opportunity Line Item Ids for publishing
        Set < Id > opportunityIdSet = new Set < Id > ();

        // List to store the final Opportunity Line Items to be published
        List < OpportunityLineItem > finalOliListToPublish = new List < OpportunityLineItem > ();
        List < OpportunityLineItem > filteredList = new List < OpportunityLineItem > ();
        List<OpportunityLineItem> updateOli = new List <OpportunityLineItem> ();
        
        // Bulkified: Preload opportunity data for all records at once
        preloadOpportunityData(newList);
        
        // Filter based on opportunity conditions - similar to OpportunityTriggerHelper logic
        if (oldMap != null) {
            for (OpportunityLineItem oliRec: newList) {

                Boolean hasOp4IDealId = oliRec.op4I_Deal_Id__c != null;
                Boolean hasOp4ISystemOrErrorOrDLIP = 
                    oliRec.op4I_System_Id__c != null ||
                    oliRec.OP4I_Error__c != null ||
                    oliRec.DLIP_OP4I_ID__c != null;
                
                // Check if opportunity meets publishing criteria
                Boolean shouldPublish = shouldPublishOpportunityLineItem(oliRec);
                
                if (((hasOp4IDealId && hasOp4ISystemOrErrorOrDLIP) || oliRec.Retrigger_OP4I_Sync__c) && shouldPublish) {
                    filteredList.add(oliRec);
                }
            }
        } else {
            // For inserts, filter based on opportunity conditions
            for (OpportunityLineItem oliRec : newList) {
                if (shouldPublishOpportunityLineItem(oliRec)) {
                    filteredList.add(oliRec);
                }
            }
        }
		Nebula.Logger.debug('Add log entry using Nebula Logger with logging level == DEBUG'+filteredList);
        // Loop to gather unique Opportunity Ids from the new list
        for (OpportunityLineItem oliRec: filteredList) {
            opportunityIdSet.add(oliRec.OpportunityId);
        }
        // Map to store Opportunity Ids and corresponding Parent Opportunity Line Items Id
        Map < Id, Set < Id >> opportunityIdToParentIdMap = new Map < Id, Set < Id >> ();

        if (opportunityIdSet.size() > 0) {

            // Query to retrieve Opportunity Line Items based on the gathered Opportunity Ids
            for (OpportunityLineItem oliRec: [
                SELECT Id, SBQQ__ParentID__c, OpportunityId, Skip_OP4I_Sync__c
                FROM OpportunityLineItem
                WHERE OpportunityId IN: opportunityIdSet
            ]) {
                if (!opportunityIdToParentIdMap.containsKey(oliRec.OpportunityId)) {
                    opportunityIdToParentIdMap.put(oliRec.OpportunityId, new Set<Id>());
                }
                
                if (oliRec.SBQQ__ParentID__c != null) {
                    Set<Id> tempSet = opportunityIdToParentIdMap.get(oliRec.OpportunityId);
                    tempSet.add(oliRec.SBQQ__ParentID__c);
                    opportunityIdToParentIdMap.put(oliRec.OpportunityId, tempSet);
                }
            }
            
            // Logic to determine which Opportunity Line Items to publish
            for (OpportunityLineItem oliRec: filteredList) {
                Boolean isChild = oliRec.SBQQ__ParentID__c != null;
                Boolean isStandalone = !isChild && !opportunityIdToParentIdMap.get(oliRec.OpportunityId).contains(oliRec.Id);
                
                if ((isChild && !oliRec.Skip_OP4I_Sync__c) || isStandalone || oliRec.Retrigger_OP4I_Sync__c) {
                    if (oliRec.Opportunity_Prod_Updated__c == false) {
                        if (oldMap == null) {
                            oliRec.Opportunity_Prod_Updated__c = true;
                            updateOli.add(oliRec);
                        } else {
                            finalOliListToPublish.add(oliRec);
                        }
                    }
                }
            }

            if (!updateOli.isEmpty()) {
            	try {
                	update updateOli;
            	} catch (Exception e) {
                	Nebula.Logger.error('OpportunityProductTriggerHandler.publishOppLineItems', updateOli, e);
            	} finally {
                	Nebula.Logger.saveLog();
            	}
            }
            if (!finalOliListToPublish.isEmpty()) {
                IntegrationUtility.publishEligibleSobjectRecords(finalOliListToPublish, oldMap, 'OpportunityLineItem');
            }
        }
    }

    /**
     * @description - This method handles the insertion of Opportunity Line Items.
     * @param oppProdNewList - List of Opportunity Line Items
     * @param bIsBefore - Boolean to check if method is called from before context
     */
    public static void opportunityProductEventafterInsert(List < OpportunityLineItem > oppProdNewList, Boolean bIsBefore) {
        List < OpportunityLineItem > opportunityItemList = new List < OpportunityLineItem > ();
        Id oppRecordTypeId = RecordTypeUtil.getRecordTypeId(Opportunity.SObjectType, OpportunityConstants.RT_MIGRATION_OPP);

        Map<Id, OpportunityLineItem> mapOLI = new Map<Id, OpportunityLineItem>();
        set < Id > setOfOli = new set < id > ();
        for (OpportunityLineItem oli: oppProdNewList) {
            setOfOli.add(oli.id);
            mapOLI.put(oli.id,oli);
        }
        String strQuery = createQuery(setOfOli);
        List < OpportunityLineItem > lstOfOpportunityItem = Database.query(strQuery);

        for (OpportunityLineItem oppLineItem: lstOfOpportunityItem) {
            if (oppLineItem.Opportunity.RecordTypeId != oppRecordTypeId) {
                if(bIsBefore && String.isNotBlank(oppLineItem.Opportunity.Renewal_Quote_Type__c) && oppLineItem.Opportunity.Renewal_Quote_Type__c.equalsIgnoreCase('Auto-Renewal') && String.isNotBlank(oppLineItem.OP4I_System_Id__c) && !oppLineItem.OP4I_System_Id__c.containsIgnoreCase('OP4I') && mapOLI.containsKey(oppLineItem.Id)){
                    mapOLI.get(oppLineItem.Id).OP4I_System_Id__c = 'OP4I'+Date.today().format();
                } 
                
                // Apply the same filtering logic as OpportunityTriggerHelper
                if (shouldPublishOpportunityLineItemFromQuery(oppLineItem)) {
                    opportunityItemList.add(oppLineItem);
                }
            }
        }

        if (opportunityItemList.Size() > 0) {
            publishOppLineItems(opportunityItemList, null);
        }
    }
    /**
     * @description - This method handles ghost QL Data and update OLI
     * @param oppProdNewList - List of Opportunity Line Items
     * @return  - void
     */
    public static void updateOLIFromGhostQL(List<OpportunityLineItem> oppProdNewList ){
        Map<String, Schema.SObjectField> schemaMap = OpportunityLineItem.SObjectType.getDescribe().fields.getMap();
        
        Set<Id> setSubscriptionIds = new Set<Id>();
        Set<Id> setOppIds = new Set<Id>();
        for (OpportunityLineItem oli : oppProdNewList) {
            setOppIds.add(oli.OpportunityId);
        }
        Map<Id, Opportunity> mapOpportunity = new Map<Id, Opportunity>([SELECT Id, Deal_Type__c FROM Opportunity WHERE Id IN:setOppIds ]);
        for (OpportunityLineItem oli : oppProdNewList) {
            
            System.debug('SBQQ__QuoteLine__c: ' + oli.SBQQ__QuoteLine__c);
			System.debug('Ghost_Mapping_Payload__c: ' + oli.Ghost_Mapping_Payload__c);
			System.debug('Opportunity Deal_Type__c: ' + [SELECT Deal_Type__c FROM Opportunity WHERE Id = :oli.OpportunityId].Deal_Type__c);
            if (String.isNotBlank(oli.Ghost_Mapping_Payload__c) && oli.SBQQ__QuoteLine__c == null  && mapOpportunity.get(oli.OpportunityId).Deal_Type__c == 'Renewal') {
                
                // unpack JSON to map so we only process fields present in payload
                Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(oli.Ghost_Mapping_Payload__c);
                
                for (String fieldName : payloadMap.keySet()) {
                    if (fieldName == 'Id') continue; // skip Id
                    if (!schemaMap.containsKey(fieldName)) continue; // skip unknown fields

                    Schema.DisplayType dt = schemaMap.get(fieldName).getDescribe().getType();
                    Object rawValue = payloadMap.get(fieldName);
                    
                    if (rawValue == null || String.isBlank(''+rawValue)) {
                        // clear the field if JSON has null
                        //oli.put(fieldName, null); do nothing
                    } else if (
                        dt == Schema.DisplayType.STRING ||
                        dt == Schema.DisplayType.PICKLIST ||
                        dt == Schema.DisplayType.ID ||
                        dt == Schema.DisplayType.REFERENCE ||
                        dt == Schema.DisplayType.URL ||
                        dt == Schema.DisplayType.EMAIL ||
                        dt == Schema.DisplayType.PHONE
                    ) {
                        oli.put(fieldName, String.valueOf(rawValue));
                    } else if (dt == Schema.DisplayType.BOOLEAN) {
                        if (rawValue instanceof Boolean) {
                            oli.put(fieldName, (Boolean) rawValue);
                        } else {
                            oli.put(fieldName, Boolean.valueOf(String.valueOf(rawValue)));
                        }
                    } else if (dt == Schema.DisplayType.INTEGER || dt == Schema.DisplayType.LONG) {
                        oli.put(fieldName, Integer.valueOf(String.valueOf(rawValue)));
                    } else if (
                        dt == Schema.DisplayType.DOUBLE ||
                        dt == Schema.DisplayType.CURRENCY ||
                        dt == Schema.DisplayType.PERCENT
                    ) {
                        oli.put(fieldName, Decimal.valueOf(String.valueOf(rawValue)));
                    } else if (dt == Schema.DisplayType.DATE) {
                        if (rawValue instanceof Date) {
                            oli.put(fieldName, (Date) rawValue);
                        } else {
                            oli.put(fieldName, Date.parse(String.valueOf(rawValue)));
                        }
                    } else if (dt == Schema.DisplayType.DATETIME) {
                        if (rawValue instanceof Datetime) {
                            oli.put(fieldName, (Datetime) rawValue);
                        } else {
                            oli.put(fieldName, Datetime.parse(String.valueOf(rawValue)));
                        }
                    } else {
                        // fallback
                        oli.put(fieldName, rawValue);
                    }
                }
                
                if(oli.Subscriptions__c != null){
                    setSubscriptionIds.add(oli.Subscriptions__c);
                }
            }
        }
        if(setSubscriptionIds.isEmpty()) return;
        Map<Id, SBQQ__Subscription__c> mapRenewedSubscription = new Map<Id, SBQQ__Subscription__c>(
            [SELECT Id, SBQQ__Contract__c, SBQQ__NetPrice__c, SBQQ__SegmentQuantity__c, SBQQ__ProrateMultiplier__c, Last_Segment_Subscription__c, Last_Segment_Subscription__r.Id, SBQQ__SegmentIndex__c,
             Last_Segment_Subscription__r.SBQQ__NetPrice__c, Last_Segment_Subscription__r.SBQQ__SegmentQuantity__c, Last_Segment_Subscription__r.SBQQ__ProrateMultiplier__c, Parent_of_Bundle__c,
             CPQ_Option_Type__c
             FROM SBQQ__Subscription__c WHERE Id IN :setSubscriptionIds]
        );
        
        set<Id> setLastSegIds = new set<Id>();
        for(SBQQ__Subscription__c sub:mapRenewedSubscription.values() ){
            if(sub.Last_Segment_Subscription__c != null){
                setLastSegIds.add(sub.Last_Segment_Subscription__c);
            } else if(sub.SBQQ__SegmentIndex__c == 1) {
                setLastSegIds.add(sub.Id);
            }
        }
        Map<Id, SBQQ__Subscription__c> mapRevisedSubscription = new Map<Id, SBQQ__Subscription__c>();
        for(SBQQ__Subscription__c sub:[SELECT Id, SBQQ__Contract__c, SBQQ__NetPrice__c, SBQQ__SegmentQuantity__c, SBQQ__ProrateMultiplier__c, SBQQ__RevisedSubscription__c
                                       FROM SBQQ__Subscription__c WHERE SBQQ__RevisedSubscription__c IN :setLastSegIds order by createdDate asc]){
            mapRevisedSubscription.put(sub.SBQQ__RevisedSubscription__c, sub);
        }
        
        for (OpportunityLineItem oli : oppProdNewList) {if (String.isNotBlank(oli.Ghost_Mapping_Payload__c) && oli.SBQQ__QuoteLine__c == null && 
                oli.Subscriptions__c != null && mapRenewedSubscription.containsKey(oli.Subscriptions__c)) {
                    Decimal prevACV = 0;
                    Decimal acv = oli.ACV__c;
                    
                    // Fetch the related RenewedSubscription (replace SBQQ__Subscription__c with the actual API name if different)
                    SBQQ__Subscription__c renewedSub = mapRenewedSubscription.get(oli.Subscriptions__c);
                    oli.Parent_of_Bundle__c = renewedSub.Parent_of_Bundle__c;
                    SBQQ__Subscription__c lastSegSub;
                    if (renewedSub != null && renewedSub.Last_Segment_Subscription__c != null) {
                        lastSegSub = renewedSub.Last_Segment_Subscription__r;
                    } else if (renewedSub != null && renewedSub.Last_Segment_Subscription__c == null && renewedSub.SBQQ__SegmentIndex__c ==1) {
                        lastSegSub = renewedSub;
                    }
					
                    Decimal netPrice = 0;
                    Decimal qty = 0;
                    Decimal segMonths = 0;
                    
                    if(lastSegSub != null && mapRevisedSubscription.containsKey(lastSegSub.Id)){
                        SBQQ__Subscription__c revisedSub = mapRevisedSubscription.get(lastSegSub.Id);
                        Decimal revisedProrate = revisedSub.SBQQ__ProrateMultiplier__c != null ? revisedSub.SBQQ__ProrateMultiplier__c : 0;
                        
                        if (revisedProrate > 0 && revisedProrate < 12) {
                            // BIZ-78712 Issue 6: Partial-period amendment — revised subscription has prorated
                            // NetPrice/ProrateMultiplier (e.g., ProrateMultiplier = 9.098 for a mid-year amendment).
                            // Using these prorated values in the annualization formula introduces floating-point drift
                            // (e.g., 72000.03 instead of 72000), causing ACV_Change to be 5039.97 instead of 5040.
                            // Fix: Use the original subscription's full-year unit price and prorate multiplier with
                            // the OLI's consolidated quantity (which CPQ sets to the post-amendment total).
                            // This mirrors ACVCalculator.calculateMigratedPreviousValue() from Issue 3.
                            netPrice = lastSegSub.SBQQ__NetPrice__c != null ? lastSegSub.SBQQ__NetPrice__c : 0;
                            qty = oli.Quantity != null ? oli.Quantity : 0;
                            segMonths = lastSegSub.SBQQ__ProrateMultiplier__c != null ? lastSegSub.SBQQ__ProrateMultiplier__c : 0;
                        } else {
                            // Full-period amendment — use revised subscription values directly (no drift risk)
                            netPrice = revisedSub.SBQQ__NetPrice__c != null ? revisedSub.SBQQ__NetPrice__c : 0;
                            qty = revisedSub.SBQQ__SegmentQuantity__c != null ? revisedSub.SBQQ__SegmentQuantity__c : 0;
                            segMonths = revisedProrate;
                        }
                    }
                    else if (lastSegSub != null) {
                        // Use lastSegSub for PrevACV
                        netPrice = lastSegSub.SBQQ__NetPrice__c != null ? lastSegSub.SBQQ__NetPrice__c : 0;
                        qty = lastSegSub.SBQQ__SegmentQuantity__c != null ? lastSegSub.SBQQ__SegmentQuantity__c : 0;
                        segMonths = lastSegSub.SBQQ__ProrateMultiplier__c != null ? lastSegSub.SBQQ__ProrateMultiplier__c : 0;
                    }else{
                         netPrice = renewedSub.SBQQ__NetPrice__c != null ? renewedSub.SBQQ__NetPrice__c : 0;
                         qty = renewedSub.SBQQ__SegmentQuantity__c != null ? renewedSub.SBQQ__SegmentQuantity__c : 0;
                         segMonths = renewedSub.SBQQ__ProrateMultiplier__c != null ? renewedSub.SBQQ__ProrateMultiplier__c : 0;
                    }
					
                    if (segMonths > 0) {
                        prevACV = (netPrice * qty * 12) / segMonths;
                    }
                    
                    // Skip ACV_Change for static components — ACV is tracked on standalone/bundle products only
                    Boolean isStaticComponent = renewedSub.CPQ_Option_Type__c == SubscriptionConstants.OPTION_TYPE_STATIC_COMPONENT;
                    
                    // Set ACVChange if both values are available and product is not a static component
                    if (!isStaticComponent && acv != null && prevACV != null) {
                        oli.ACV_Change__c = (acv - prevACV).setScale(2, RoundingMode.HALF_UP); 
                    }
                }
        }
    }

    /**
     * @description This method creates a SOQL query string to retrieve OpportunityLineItem records based on the provided set of Opportunity Line Item Ids.
     * @param setOfOli - Set of Opportunity Line Item Ids to filter the query.
     * @return String - The constructed SOQL query string.
     */
    public static string createQuery(set < Id > setOfOli) {
        set < String > fieldNames = new set < String > ();
        Schema.SObjectType targetObjType = ((SObject) Type.forName('OpportunityLineItem').newInstance()).getSObjectType();
        Map < String, Schema.SObjectField > fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List < String > fields = new List < String > (fieldNames);
        String query = ' SELECT ' +
            String.join(fields, ',') + ',PriceBookEntry.Product2Id' +
            ',Opportunity.RecordTypeId,Opportunity.Renewal_Quote_Type__c,SBQQ__QuoteLine__r.SBQQ__Quote__r.Quote_Stage__c, Opportunity.AccountId, Opportunity.Deal_Type__c, Opportunity.OP4I_Deal_ID__c ' +
            ' FROM ' +
            'OpportunityLineItem' +
            ' WHERE ' +
            ' Id IN: setOfOli';

        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}');
        return strQuery2;
    }

    /**
     * Called from OpportunityLineItem trigger (after update).
     * If OP4I_System_Id__c is changed on an opportunity line item, set Retrigger_OP4I_Sync__c to true
     * on those opportunity lines where Segment_Bundle_Line__c equals the opportunity line id which had that change.
     *
     * @param newList  Trigger.new list of OpportunityLineItem records
     * @param oldMap   Trigger.oldMap of OpportunityLineItem records
     */
    public static void checkSegmentBundleForRetrigger(List<OpportunityLineItem> newList, Map<Id, OpportunityLineItem> oldMap) {
        if (newList == null || oldMap == null) return;

        // Collect IDs of opportunity line items where OP4I_System_Id__c changed
        Set<Id> changedOliIds = new Set<Id>();
        for (OpportunityLineItem newOli : newList) {
            OpportunityLineItem oldOli = oldMap.get(newOli.Id);
            if (oldOli != null && newOli.OP4I_System_Id__c != oldOli.OP4I_System_Id__c) {
                changedOliIds.add(newOli.Id);
            }
        }

        if (changedOliIds.isEmpty()) return;

        // Query and update all opportunity line items where Segment_Bundle_Line__c 
        // equals the opportunity line id which had the OP4I_System_Id__c change
        List<OpportunityLineItem> olisToUpdate = [
            SELECT Id, Retrigger_OP4I_Sync__c
            FROM OpportunityLineItem
            WHERE Segment_Bundle_Line__c IN :changedOliIds
        ];

        if (!olisToUpdate.isEmpty()) {
            for (OpportunityLineItem oli : olisToUpdate) {
                oli.Retrigger_OP4I_Sync__c = true;
            }
            try {
                update olisToUpdate;
            } catch (Exception e) {
                Nebula.Logger.error('OpportunityProductTriggerHelper.checkSegmentBundleForRetrigger', olisToUpdate, e);
            } finally {
                Nebula.Logger.saveLog();
            }
        }
    }

    /***********************************************************************************************
    *
    * Private Static Methods
    *
    ***********************************************************************************************/
    /**
    * @description Getter for OpportunityLineItem based on Ids.
    * Filters records where CPQ_Option_Type__c, Line_Item_Key__c, and Segment_Bundle_Line_Id__c are not null.
    * @param lstNewOpportunityProducts List of OpportunityLineItem records
    * @return List<OpportunityLineItem> Filtered list of OpportunityLineItems
    */
    private static List<OpportunityLineItem> getOpportunityLineItem(List<OpportunityLineItem> lstNewOpportunityProducts) {
        return [
            SELECT Id, CPQ_Option_Type__c, SBQQ__QuoteLine__r.Line_Item_Key__c, 
            SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c, Segment_Bundle_Line__c, Original_Oppty_Text_Id__c
            FROM OpportunityLineItem 
            WHERE Id IN :lstNewOpportunityProducts
            AND CPQ_Option_Type__c != null AND SBQQ__QuoteLine__c != null
        ];
    }

    /**
     * @description Cache for opportunity data to avoid multiple queries
     */
    private static Map<Id, Opportunity> opportunityCache = new Map<Id, Opportunity>();

    /**
     * @description Bulkified method to preload opportunity data for filtering
     * @param oliList List of OpportunityLineItem records to preload opportunity data for
     */
    private static void preloadOpportunityData(List<OpportunityLineItem> oliList) {
        Set<Id> oppIdsToQuery = new Set<Id>();
        
        // Collect opportunity IDs that are not already cached
        for (OpportunityLineItem oli : oliList) {
            if (!opportunityCache.containsKey(oli.OpportunityId)) {
                oppIdsToQuery.add(oli.OpportunityId);
            }
        }
        
        // Bulk query for all needed opportunities
        if (!oppIdsToQuery.isEmpty()) {
            List<Opportunity> opps = [
                SELECT Id, OP4I_Deal_ID__c, Deal_Type__c 
                FROM Opportunity 
                WHERE Id IN :oppIdsToQuery
            ];
            
            // Cache the results
            for (Opportunity opp : opps) {
                opportunityCache.put(opp.Id, opp);
            }
        }
    }

    /**
     * @description Determines if an OpportunityLineItem should be published based on Opportunity conditions
     * @param oliRec OpportunityLineItem record to evaluate
     * @return Boolean true if should publish, false otherwise
     */
    private static Boolean shouldPublishOpportunityLineItem(OpportunityLineItem oliRec) {
        // Get opportunity from cache (should already be preloaded)
        Opportunity opp = opportunityCache.get(oliRec.OpportunityId);
        
        if (opp == null) {
            return false; // If not in cache, don't publish
        }
        
        // Apply AND condition - both OP4I_Deal_ID__c must be populated AND deal type must be allowed
        return String.isNotBlank(opp.OP4I_Deal_ID__c) || allowedDealTypes.contains(opp.Deal_Type__c);
    }

    /**
     * @description Determines if an OpportunityLineItem should be published based on already queried Opportunity data
     * @param oppLineItem OpportunityLineItem record with Opportunity relationship data
     * @return Boolean true if should publish, false otherwise
     */
    private static Boolean shouldPublishOpportunityLineItemFromQuery(OpportunityLineItem oppLineItem) {
        // Apply AND condition - both OP4I_Deal_ID__c must be populated AND deal type must be allowed
        return String.isNotBlank(oppLineItem.Opportunity.OP4I_Deal_ID__c) || allowedDealTypes.contains(oppLineItem.Opportunity.Deal_Type__c);
    }

    /***********************************************************************************************
    *
    * Private Static Properties
    *
    ***********************************************************************************************/
    /**
     * @description List of allowed deal types for sync from custom metadata
     */
    private static List<String> allowedDealTypes {
        get {
            if (allowedDealTypes == null) {
                allowedDealTypes = new List<String>();
                for (Allowed_Deal_Type_For_Sync__mdt rec : Allowed_Deal_Type_For_Sync__mdt.getAll().values()) {
                    if (String.isNotBlank(rec.DeveloperName)) {
                        allowedDealTypes.add(rec.DeveloperName.trim());
                    }
                }
            }
            return allowedDealTypes;
        }
        private set;
    }
    
}