/**
* @description Trigger helper class for OrderTrigger 
* @author Sahal Mohamed
* @CreatedDate: Mar-6-2025
**/
public inherited sharing class OrderTriggerHelper {

    /***********************************************************************************************
    *
    * props
    *
    ***********************************************************************************************/
    public static set<Id> publishedOrderIds = new set<Id>();

    /***********************************************************************************************
    *
    * public methods
    *
    ***********************************************************************************************/

    /**
    * @description Populates Order.Master_Contract__c from Opportunity.SBQQ__AmendedContract__c when an Order is created from an Amendment Quote.
    * Ensures all amendment orders reference the same original (root) contract across amendment cycles.
    * @param newOrders List of Orders in before insert context
    **/
    public static void populateMasterContract(List<Order> newOrders) {
        if(newOrders == null || newOrders.isEmpty()) {
            return;
        }
        Set<Id> opportunityIds = Pluck.ids(Order.OpportunityId, newOrders);
        if(opportunityIds.isEmpty()) {
            return;
        }
        Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>([
            SELECT Id, SBQQ__AmendedContract__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            AND SBQQ__AmendedContract__c != null
        ]);
        for(Order ord : newOrders) {
            Opportunity opp = opportunityById.get(ord.OpportunityId);
            if(opp != null) {
                ord.Master_Contract__c = opp.SBQQ__AmendedContract__c;
            }
        }
    }

    /**
    * @description Method which excutes when an order is updated. Currently sends activated orders and order line items to IntegrationUtility class
    * @param orderNewList
    * @param orderOldMap
    * @param sendLines
    **/
    public static void processEvents(list<Order> orderNewList,Map<Id,Order> orderOldMap,Boolean sendLines) {
        List<Order> orderEligibleList = new List<Order>();
        List<OrderItem> orderItemList = new List<OrderItem>();
        if(!orderNewList.isEmpty()) {
            orderEligibleList = eligibleOrders(orderNewList,orderOldMap);      
            if(!orderEligibleList.isEmpty()) {
                IntegrationUtility.publishsObjectRecords(orderEligibleList,'Order');
                if (sendLines) {
                    Schema.SObjectType targetObjType = Schema.getGlobalDescribe().get('OrderItem');
                    Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
                    List<String> fields = new List<String>(fieldMap.keyset());
                    String query =
                        ' SELECT ' +
                        String.join( fields, ',' ) +
                        ' FROM ' +
                        'OrderItem' +
                        ' WHERE ' +
                        ' OrderId IN :orderEligibleList';
                    
                    query = query.remove('{');
                    query = query.remove('}');
                    
                    orderItemList = Database.query(query);        
                    if(!orderItemList.IsEmpty()) {
                        IntegrationUtility.publishsObjectRecords(orderItemList,'OrderItem');
                    }   
                }     
            }
        }
    }

    /**
    * @description Method to populate NS Order Id on the Opportunity Products related to Order - BIZ-67369
    * @param lstNewOrders
    * @param mapOldOrders
    **/
    public static void populateNSOrderId(List<Order> lstNewOrders, Map<Id, Order> mapOldOrders) {
        Set<Id> setOrderIds = new Set<Id>();
        List<OpportunityLineItem> lstOppProducts = new List<OpportunityLineItem>(); 
        
        //Iterating on Orders to collect Orders with Netsuite Sales Order Internal Id change
        for(Order order : lstNewOrders) {
            Order oldOrder = mapOldOrders.get(order.Id);
            if(order.NetSuite_Sales_order_Internal_Id__c != oldOrder.NetSuite_Sales_order_Internal_Id__c) {
                setOrderIds.add(order.Id);
            }
        }
        
        //Populating Netsuite Sales Order Internal Id on Opportunity Line Items 
        for(SBQQ__QuoteLine__c quoteLine : [SELECT Id
                                            	 , (SELECT Id
                                                    	 , NS_Order_id__c
                                                    	 , Salesforce_Order_Line_Id__r.Order.NetSuite_Sales_order_Internal_Id__c
                                                      FROM SBQQ__OpportunityProducts__r)
                                              FROM SBQQ__QuoteLine__c
                                             WHERE Id IN (SELECT SBQQ__QuoteLine__c
                                                            FROM OrderItem
                                                           WHERE OrderId IN :setOrderIds
                                                             AND Order.SBQQ__Quote__r.Renewal_Letter__c = null)]) {
			if(quoteLine.SBQQ__OpportunityProducts__r != null) {
            	for(OpportunityLineItem opportunityLine : quoteLine.SBQQ__OpportunityProducts__r) {
                    opportunityLine.NS_Order_id__c = opportunityLine?.Salesforce_Order_Line_Id__r?.Order?.NetSuite_Sales_order_Internal_Id__c;
                    lstOppProducts.add(opportunityLine);
                }                                                        
            }
        }
        
        //Updating Opportunity Line Items if any
        try {
            update lstOppProducts;
        } catch (Exception e) {
            Nebula.Logger.error('OrderTriggerHelper.populateNSOrderId', lstOppProducts, e)
                .addTag('OrderTriggerHelper')
                .addTag('DML_Update');
        }
        finally {
            Nebula.Logger.saveLog();
        }       
    }

    /**
     * @description Enqueues a delayed Queueable to supersede a contract when a supersession amendment
     *              order is contracted. The Queueable checks for active recurring subscriptions
     *              (partial-cancellation guard) after CPQ has terminated subs. - BIZ-68972, BIZ-69730
     * @param orders
     */
    public static void setContractAsSuperceded(List<Order> orders) {
        Set<Id> orderIds = new Set<Id>();
        Map<Id, Id> contractIdToAccountId = new Map<Id, Id>();

        for (Order order : orders) {
            if (isRMAOrderContracted(order)) {
                orderIds.add(order.Id);
            }
        }

        for (Order order : getOrders(orderIds)) {
            if (order.Opportunity.Deal_Type__c == OpportunityConstants.DEAL_TYPE_AMENDMENT_TO_SUPERCEDE) {
                contractIdToAccountId.put(order.Opportunity.SBQQ__AmendedContract__c, order.AccountId);
            }
        }

        if (contractIdToAccountId.isEmpty()) {
            return;
        }

        contractIdToAccountId = filterContractsNotInStatus(contractIdToAccountId.keySet(),
            ContractConstants.STATUS_SUPERSEDED_BY_NEWER_CONTRACT, contractIdToAccountId);

        if (contractIdToAccountId.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new ContractStatusQueueable(contractIdToAccountId, ContractStatusQueueable.ACTION_SUPERSESSION),
            2
        );
    }

    /**
     * @description Enqueues a delayed Queueable to cancel a contract when a cancellation amendment
     *              order is contracted. The Queueable checks for active recurring subscriptions
     *              (partial-cancellation guard) after CPQ has terminated subs, then updates contract
     *              status, closes NYMY/Renewal opps, and lapses the account. - BIZ-68972, BIZ-69730
     * @param orders
     */
    public static void setContractAsCancelled(List<Order> orders) {
        Set<Id> orderIds = new Set<Id>();
        Map<Id, Id> contractIdToAccountId = new Map<Id, Id>();

        for (Order order : orders) {
            if (isRMAOrderContracted(order)) {
                orderIds.add(order.Id);
            }
        }

        for (Order order : getOrders(orderIds)) {
            if (order.Opportunity.Deal_Type__c == OpportunityConstants.DEAL_TYPE_CANCELLATION) {
                contractIdToAccountId.put(order.Opportunity.SBQQ__AmendedContract__c, order.AccountId);
            }
        }

        if (contractIdToAccountId.isEmpty()) {
            return;
        }

        contractIdToAccountId = filterContractsNotInStatus(contractIdToAccountId.keySet(),
            ContractConstants.STATUS_CANCELLED_LAPSED, contractIdToAccountId);

        if (contractIdToAccountId.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new ContractStatusQueueable(contractIdToAccountId, ContractStatusQueueable.ACTION_CANCELLATION),
            2
        );
    }

    /***********************************************************************************************
    *
    * private Methods
    *
    ***********************************************************************************************/

    /**
    * @description Method to fetch eligible orders to which needs to be send to IntegrationUtility class
    * @param orderList
    * @param orderOldMap
    * @return List<Order>
    **/
    private static List<Order> eligibleOrders(List<Order> orderList,Map<Id,Order> orderOldMap){
        List<Order> orderEligibleList = new List<Order>();
        List<Order> orderUpdatedList = new List<Order>();
        Id oppRecordTypeId = RecordTypeUtil.getRecordTypeId(Opportunity.SObjectType, OpportunityConstants.RT_MIGRATION_OPP);
        Set<Id> setOfOrder = new Set<Id>();
        for(Order order : orderList){
            setOfOrder.add(order.id);     
        }
        String strQuery = createQuery(setOfOrder);
        List<Order> lstOfOrders = Database.query(strQuery);
        for(Order orderObj : lstOfOrders){
            if(orderObj.Opportunity.RecordTypeId != oppRecordTypeId){
                orderUpdatedList.add(orderObj);  
            }     
        }
        if(orderUpdatedList.isEmpty()) { return orderUpdatedList; }

        for(Order orderObj : orderUpdatedList) {
            Order orderOld = orderOldMap != null && orderOldMap.containsKey(orderObj.Id)? orderOldMap.get(orderObj.Id) : new Order();       
            if(!publishedOrderIds.contains(orderObj.Id) && orderObj.Status == OrderConstants.STATUS_ACTIVATED && orderObj.ContractNumber__c != null 
                && IntegrationUtility.isChanged(orderObj, orderOld, fieldTrackingList) && !orderObj.Don_t_Sync_Order_to_NS__c) {
                    if(orderObj.Sync_NetSuite__c == false && orderOld.Sync_NetSuite__c == true && orderObj.lastmodifiedby.name == 'Biz Apps Integration'){
                        system.debug('Modified by Bizapps Integration User');                   
                    }
                    else{
                        orderEligibleList.add(orderObj);
                        publishedOrderIds.add(orderObj.Id);
                    }
                }       
        }    
        return orderEligibleList; 
    }

    /**
    * @description Method to create query for the given set of Orders
    * @param setOfOrder
    * @return String
    **/
    private static string createQuery(set<Id> setOfOrder) {
        set<String> fieldNames = new set<String>();
        Schema.SObjectType targetObjType = Schema.getGlobalDescribe().get('Order');
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List<String> fields = new List<String>(fieldNames);
        String query =  ' SELECT ' +
            String.join( fields, ',' ) + 
            ',Opportunity.RecordTypeId' +
            ',lastmodifiedby.name ' +
            ' FROM ' +
            'Order' +
            ' WHERE ' +
            ' Id IN: setOfOrder';
        
        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}'); 
        return strQuery2;
    }

    /**
     * @description Filters out contracts that are already in the given status, returning
     *              a new map containing only the contracts that still need updating.
     *              Prevents redundant Queueable jobs on subsequent Order updates (BIZ-69730).
     * @param contractIds Candidate contract IDs
     * @param excludeStatus The status to exclude (contracts already in this status are filtered out)
     * @param originalMap The original contractId-to-accountId map to filter
     * @return Filtered map with contracts not yet in the target status
     */
    private static Map<Id, Id> filterContractsNotInStatus(Set<Id> contractIds, String excludeStatus,
            Map<Id, Id> originalMap) {
        Map<Id, Id> filtered = new Map<Id, Id>();
        for (Contract c : [SELECT Id FROM Contract WHERE Id IN :contractIds AND Status != :excludeStatus]) {
            filtered.put(c.Id, originalMap.get(c.Id));
        }
        return filtered;
    }

    /**
     * @description Checks if the order is a contracted RMA Order.
     * Does not rely on old-vs-new field-change detection because CPQ's
     * internal contracting process can set SBQQ__Contracted__c in a way
     * that bypasses standard change detection (BIZ-69730).
     * @param order
     * @return Boolean
     */
    private static Boolean isRMAOrderContracted(Order order) {
        return order.SBQQ__Contracted__c && order.Is_RMA_Order__c == 'Yes';
    }

    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/

    /**
     * @description Method to get Order records
     * @param Set<Id> orderIds
     * @return List<Order>
     */
    private static List<Order> getOrders(Set<Id> orderIds) {
        return [SELECT Id, AccountId, Opportunity.SBQQ__RenewedContract__c, Opportunity.Deal_Type__c, Opportunity.SBQQ__AmendedContract__c,
                	Opportunity.Name, Opportunity.OP4I_Auto_Number_Deal_ID__c
                FROM Order
                WHERE Id IN :orderIds AND (Opportunity.SBQQ__RenewedContract__c != null OR Opportunity.SBQQ__AmendedContract__c != null)];
    }

    /**
     * @description Method to get the Order Fields Tracking Mapping records
     * @return List<Field_Tracking__mdt>
     */
    private static List<Field_Tracking__mdt> fieldTrackingList {
        get {
            if(fieldTrackingList == null) {
                fieldTrackingList = [SELECT Field_Api_Name__c, Object_Name__c   
                                    FROM Field_Tracking__mdt
                                    WHERE Object_Name__c = 'Order'];
            }
            return fieldTrackingList;
        }
        set;
    }
}