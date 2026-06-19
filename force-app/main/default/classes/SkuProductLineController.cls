/**
 * @description Controller for Product_Line__c CRUD operations in the SKU Management App.
 *              Supports the Update Product Line tab.
 * @author Yousef Alamin
 * @date 2026-03-28
 * @jira BIZ-80750
 */
public with sharing class SkuProductLineController {

    private static final String PL_FIELDS =
        'Id, Name, Active__c, Cloud_Addendum_Required__c, '
        + 'Deployment__c, IMP_prefix__c, Intapp_ID__c, NetSuite_Product_Line_ID__c, '
        + 'Practice__c, Simple_Product_Line__c, '
        + 'CreatedDate, LastModifiedDate, CreatedBy.Name, LastModifiedBy.Name';

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @description Returns full Product_Line__c record for the given Id.
     */
    @AuraEnabled(cacheable=true)
    public static Product_Line__c getProductLineDetails(Id recordId) {
        try {
            List<Product_Line__c> records = Database.query(
                'SELECT ' + PL_FIELDS + ' FROM Product_Line__c WHERE Id = :recordId LIMIT 1'
            );
            if (records.isEmpty()) {
                throw new AuraHandledException('Product Line not found.');
            }
            return records[0];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns active picklist values for Deployment__c, Practice__c,
     *              and Simple_Product_Line__c on Product_Line__c.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getProductLinePicklists() {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Product_Line__c.fields.getMap();

        for (String fieldName : new List<String>{ 'Deployment__c', 'Practice__c', 'Simple_Product_Line__c' }) {
            if (!fieldMap.containsKey(fieldName)) continue;
            List<Map<String, String>> options = new List<Map<String, String>>();
            for (Schema.PicklistEntry entry : fieldMap.get(fieldName).getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }
            result.put(fieldName, options);
        }
        return result;
    }

    /**
     * @description Saves changed fields on a Product_Line__c record.
     * @param recordId  Id of the Product_Line__c record to update
     * @param fields    Map of API field name → new value
     */
    @AuraEnabled
    public static void updateProductLine(Id recordId, Map<String, Object> fields) {
        try {
            Product_Line__c record = new Product_Line__c(Id = recordId);
            for (String fieldName : fields.keySet()) {
                record.put(fieldName, fields.get(fieldName));
            }
            update record;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}