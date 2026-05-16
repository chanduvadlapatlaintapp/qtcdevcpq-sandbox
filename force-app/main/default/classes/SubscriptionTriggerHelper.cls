/**
* @description       : This class is a Helper class for SubscriptionTrigger.
* @author            : Sonali Kakade
* @last modified on  : 06-23-2025
* @last modified by  : Sonali Kakade
* Modifications Log
* Ver   Date         Author            Modification
* 1.0   06-23-2025   Sonali Kakade     Initial Version via BIZ-67339
* 2.0 	07-23-2025   Manisha S		   Queried fields in after insert via BIZ-71406
**/
public class SubscriptionTriggerHelper {
    
    /***********************************************************************************************
    *
    * public methods
    *
    ***********************************************************************************************/
    
	/**
    * @description Handles the before insert logic for `SBQQ__Subscription__c` records.
    *              Looks up the OpportunityLineItem linked to the subscription's original quote line
    *              and stamps the `Original_Opportunity_Product__c` field on the subscription.
    * @param subNewList A list of newly inserted `SBQQ__Subscription__c` records (before insert context).
    **/
    public static void populateOriginalOpportunityProduct(List<SBQQ__Subscription__c> subNewList) {
        Set<Id> quoteLineIds = new Set<Id>();
        for (SBQQ__Subscription__c sub : subNewList) {
            if (sub.SBQQ__QuoteLine__c != null) {
                quoteLineIds.add(sub.SBQQ__QuoteLine__c);
            }
        }

        if (quoteLineIds.isEmpty()) {
            return;
        }

        Map<Id, Id> quoteLineToOppProductMap = new Map<Id, Id>();
        for (OpportunityLineItem oli : [
            SELECT Id, SBQQ__QuoteLine__c
              FROM OpportunityLineItem
             WHERE SBQQ__QuoteLine__c IN :quoteLineIds
        ]) {
            quoteLineToOppProductMap.put(oli.SBQQ__QuoteLine__c, oli.Id);
        }

        for (SBQQ__Subscription__c sub : subNewList) {
            if (sub.SBQQ__QuoteLine__c != null
                && quoteLineToOppProductMap.containsKey(sub.SBQQ__QuoteLine__c)) {
                sub.Original_Opportunity_Product__c = quoteLineToOppProductMap.get(sub.SBQQ__QuoteLine__c);
            }
        }
    }

	/**
    * @description Handles the logic after the insertion of `SBQQ__Subscription__c` records. 
    *              It updates the `Segment_Bundle_Line__c` field for segmented bundles, 
    *              filters eligible subscriptions, and publishes them for integration.
    * @param subNewList A list of newly inserted `SBQQ__Subscription__c` records.
    **/
    public static void subscriptionAfterInsert(List<SBQQ__Subscription__c > subNewList) { 

        updateSegmentedBundleId(subNewList);
        if(!subNewList.isEmpty()) {
            set<Id> subSet = new Set<id>();
            for(SBQQ__Subscription__c subObj : subNewList) {
                if(subObj.SBQQ__SubscriptionType__c != 'One-time' && subObj.Parent_Of_Bundle__c == false && subObj.CPQ_Option_Type__c != 'Static Bundle') {
                    subSet.add(subObj.id);
                }
            }

            if(subSet.size() > 0 && !subSet.isEmpty()) {
                String query = buildSubscriptionQuery(subSet);
                List<SBQQ__Subscription__c> subscriptionList  = Database.query(query);
                IntegrationUtility.publishsObjectRecords(subscriptionList, 'SBQQ__Subscription__c');
            }
        }
    } 
    
    /**
    * @description Handles the logic after the update of `SBQQ__Subscription__c` records.
    *              It identifies subscriptions eligible for processing based on changes in 
    *              key fields such as contract number and entitlement ID. The method triggers 
    *              event processing for the updated subscriptions.
    * @param subNewList A list of newly updated `SBQQ__Subscription__c` records.
    * @param subOldMap A map of old values of the `SBQQ__Subscription__c` records.
    **/
    public static void subscriptionAfterUpdate(List<SBQQ__Subscription__c > subNewList, Map<Id, SBQQ__Subscription__c > subOldMap) {
        List<SBQQ__Subscription__c> subsEligibleList = new List<SBQQ__Subscription__c>();
        Set<Id> subscriptionSet = new Set<Id>();
        if(!subNewList.isEmpty()) {
            for(SBQQ__Subscription__c sub : [SELECT Id, OP4I_Contract_Number__c, Parent_Of_Bundle__c,
                                             		OP4I_Entitlement_Id__c, SBQQ__Contract__r.OP4I_Error__c
                                               FROM SBQQ__Subscription__c
                                              WHERE ID IN: subNewList and CPQ_Option_Type__c != 'Static Bundle' and 
                                            	OP4I_Contract_Number__c != null and Parent_Of_Bundle__c = false]) {
				if(sub.OP4I_Entitlement_Id__c != null || sub.SBQQ__Contract__r.OP4I_Error__c != null) {
                	subscriptionSet.add(sub.Id);
                }
        	}
        }
        if(!subscriptionSet.isEmpty()) {
            processEvents(subscriptionSet, subOldMap, true);
        }
    }
    
    /**
    * @description Processes events for the given set of `SBQQ__Subscription__c` records.
    *              This method dynamically constructs a SOQL query to retrieve subscription data 
    *              and publishes eligible subscription records for integration.
    * @param subSet A set of subscription IDs that require event processing.
    * @param subOldMap A map of old subscription records used for comparison during processing.
    * @param sendLines A boolean flag indicating whether to include line items in the processing.
    **/
    public static void processEvents(Set<Id> subSet, Map<Id,SBQQ__Subscription__c > subOldMap, Boolean sendLines){
        List<SBQQ__Subscription__c> subscriptionList = new List<SBQQ__Subscription__c>();
        if(subSet != null) {
            if(sendLines) {
                String query = buildSubscriptionQuery(subSet);
                subscriptionList = Database.query(query);
            }
            if(subscriptionList.size() > 0) {
                IntegrationUtility.publishEligibleSobjectRecords(subscriptionList,subOldMap, 'SBQQ__Subscription__c');
            }
        }
    }

    /**
    * @description Updates the `Segment_Bundle_Line__c` field for subscriptions that are 
    *              part of a segmented bundle relationship. It associates static components 
    *              with their respective static bundle parent based on the bundle relationship.
    * @param lstNewSubscriptions A list of newly inserted or updated `SBQQ__Subscription__c` records.
    **/
    public static void updateSegmentedBundleId(List<SBQQ__Subscription__c> lstNewSubscriptions) {
        Map<String, Id> mapStaticBundleMap = new Map<String, Id>();
        List<SBQQ__Subscription__c> lstOrderProductsToUpdate = new List<SBQQ__Subscription__c>();
        lstNewSubscriptions = getSubscriptions(lstNewSubscriptions);
        // Exit early if the list is empty
        if(lstNewSubscriptions.isEmpty()) {
            return;
        }
        
        //Identify most parent products and segmented bundle parents
        for(SBQQ__Subscription__c sub : lstNewSubscriptions) {
            if(sub.CPQ_Option_Type__c == OpportunityProductConstants.OPTION_TYPE_STATIC_BUNDLE && sub.SBQQ__QuoteLine__r.Line_Item_Key__c != null) {
                // Segmented Bundle Parent
                mapStaticBundleMap.put(sub.SBQQ__QuoteLine__r.Line_Item_Key__c, sub.Id);
            }
        }
        for(SBQQ__Subscription__c sub : lstNewSubscriptions) {
            if(sub.CPQ_Option_Type__c == OpportunityProductConstants.OPTION_TYPE_STATIC_COMPONENT && sub.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c != null ) {  
                String unique = sub.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c;
                // Segmented Bundle Parent
                if(mapStaticBundleMap.containsKey(unique)) {
                    lstOrderProductsToUpdate.add(new SBQQ__Subscription__c(Id = sub.Id, Segment_Bundle_Line__c = mapStaticBundleMap.get(unique)));
                }
            }
        }
        update lstOrderProductsToUpdate;
        // Update Opportunity Line Item
        List<Database.SaveResult> updateSubscriptionResults = Database.update(lstOrderProductsToUpdate, false);
        Set<Id> subscriptionsNotUpdated = ResultHandler.logErrors('SubscriptionTriggerHandler Update Subscriptions', lstOrderProductsToUpdate, updateSubscriptionResults);
    }

    /**
    * @description Getter for Subscription records based on Ids.
    * 			   Filters records where CPQ_Option_Type__c, Line_Item_Key__c, and Segment_Bundle_Line_Id__c are not null.
    * @param lstNewSubscriptions List of SBQQ__Subscription__c records
    * @return List<SBQQ__Subscription__c> Filtered list of subscriptions
    **/
    private static List<SBQQ__Subscription__c> getSubscriptions(List<SBQQ__Subscription__c> lstNewSubscriptions) {
        return [
            SELECT Id, CPQ_Option_Type__c, SBQQ__QuoteLine__r.Line_Item_Key__c, 
                   SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c
              FROM SBQQ__Subscription__c 
             WHERE Id IN :lstNewSubscriptions
               AND CPQ_Option_Type__c != null AND SBQQ__QuoteLine__c != null
        ];
    }

    /**
    * @description Builds the dynamic subscription query used by multiple methods.
    * @param subSet Set of subscription IDs to fetch
    * @return String A SOQL query string
    **/
    private static String buildSubscriptionQuery(Set<Id> subSet) {
        Schema.SObjectType targetObjType = Schema.getGlobalDescribe().get('SBQQ__Subscription__c');
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        List<String> fields = new List<String>(fieldMap.keyset());

        // Additional fields (relationships)
        String additionalFields = '';
        additionalFields += ', Original_Opportunity_Product__r.OP4I_System_Id__c';
        additionalFields += ', Original_Opportunity_Product__r.DLIP_OP4I_ID__c';
        additionalFields += ', SBQQ__Product__r.Intapp_ID__c';
        additionalFields += ', SBQQ__RevisedSubscription__r.OP4I_Entitlement_Id__c';

        String query = 'SELECT ' + String.join(fields, ',') + additionalFields + 
                       ' FROM SBQQ__Subscription__c WHERE Id IN :subSet';
        return query.remove('{').remove('}');
    }
}