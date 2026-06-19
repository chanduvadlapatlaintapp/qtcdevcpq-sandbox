/**
 * @description Trigger helper class for processing OrderItem (Order Product) updates, 
 *              specifically handling segmented bundle relationships between static bundles 
 *              and their components.
 * @author Ratan Paul
 * @jira BIZ-68140
 */
public class OrderProductTriggerHelper {
    
    /**
    * @description This method updates the Segment_Bundle_Line__c field on static component products by mapping them 
    *              to their corresponding static bundle parent products using quote line references within the provided 
    *              order line items.
    * @param lstNewOrderProducts - List of order products to evaluate and update
    */
    public static void updateSegmentedBundleId(List<OrderItem> lstNewOrderProducts){
        
        List<OrderItem> lstOrderProductsToUpdate = new List<OrderItem>();
        Map<String, Id> mapStaticBundleMap = new Map<String, Id>();
        List<OrderItem> orderProductsList = getOrderLineItem(lstNewOrderProducts);
        // Exit early if the retrieved Order Items list is empty
        if (orderProductsList.isEmpty()) {
            return;
        }
        
        // Identify most parent products and segmented bundle parents
        for (OrderItem opProd : orderProductsList) {
            if (opProd.CPQ_Option_Type__c == OpportunityProductConstants.OPTION_TYPE_STATIC_BUNDLE && opProd.SBQQ__QuoteLine__r.Line_Item_Key__c != null) {
                // Segmented Bundle Parent
                mapStaticBundleMap.put(opProd.SBQQ__QuoteLine__r.Line_Item_Key__c, opProd.Id);
            }
        }
        for (OrderItem opProd : orderProductsList) {
            if (opProd.CPQ_Option_Type__c == OpportunityProductConstants.OPTION_TYPE_STATIC_COMPONENT && opProd.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c != null ) {
                
                String unique = opProd.SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c;
                // Segmented Bundle Parent
                if(mapStaticBundleMap.containsKey(unique)){
                    lstOrderProductsToUpdate.add(new OrderItem(Id = opProd.Id, 
                                                               Segment_Bundle_Line__c = mapStaticBundleMap.get(unique) ));
                }
            }
        }
        // Update Order Line Item
        List<Database.SaveResult> updateOrderProductsResults = Database.update(lstOrderProductsToUpdate, false);
        ResultHandler.logErrors('OrderProductTriggerHandler Update Order Products', lstOrderProductsToUpdate, updateOrderProductsResults);
    }
    
    /**
    * @description Retrieves OrderItem records where CPQ_Option_Type__c, 
    * Line_Item_Key__c, and Segment_Bundle_Line_Id__c are not null.
    * Returns an empty list if input is empty.
    * @param lstNewOrderProducts - List of OrderItem Ids to query
    * @return List<OrderItem> - List of OrderItem records with specified criteria
    */
    private static List<OrderItem> getOrderLineItem(List<OrderItem> lstNewOrderProducts) {
        return [
            SELECT Id, CPQ_Option_Type__c, SBQQ__QuoteLine__r.Line_Item_Key__c, 
            SBQQ__QuoteLine__r.Segment_Bundle_Line_Id__c
            FROM OrderItem  
            WHERE Id IN :lstNewOrderProducts
            AND CPQ_Option_Type__c != null AND SBQQ__QuoteLine__c != null
        ];
    }
}