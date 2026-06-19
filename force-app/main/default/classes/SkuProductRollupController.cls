/**
 * @description Controller for Product_Rollup__c CRUD operations in the SKU Management App.
 *              Supports the Update Product Rollup tab.
 * @author Yousef Alamin
 * @date 2026-03-28
 * @jira BIZ-80750
 */
public with sharing class SkuProductRollupController {

    private static final String PR_FIELDS =
        'Id, Name, Description__c, Don_t_Show_on_Projects__c, '
        + 'Highest_Package__c, Intapp_ID__c, OA_Task_ID__c, '
        + 'Product_Line__c, Product_Line__r.Name, '
        + 'CreatedDate, LastModifiedDate, CreatedBy.Name, LastModifiedBy.Name';

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @description Returns full Product_Rollup__c record for the given Id.
     */
    @AuraEnabled(cacheable=true)
    public static Product_Rollup__c getProductRollupDetails(Id recordId) {
        try {
            List<Product_Rollup__c> records = Database.query(
                'SELECT ' + PR_FIELDS + ' FROM Product_Rollup__c WHERE Id = :recordId LIMIT 1'
            );
            if (records.isEmpty()) {
                throw new AuraHandledException('Product Rollup not found.');
            }
            return records[0];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns all active Product Lines as options for the Product Line lookup combobox.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProductLineOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Product_Line__c pl : [
            SELECT Id, Name FROM Product_Line__c
            WHERE Active__c = true
            ORDER BY Name ASC
            LIMIT 500
        ]) {
            options.add(new Map<String, String>{ 'label' => pl.Name, 'value' => pl.Id });
        }
        return options;
    }

    /**
     * @description Saves changed fields on a Product_Rollup__c record.
     * @param recordId  Id of the Product_Rollup__c record to update
     * @param fields    Map of API field name → new value
     */
    @AuraEnabled
    public static void updateProductRollup(Id recordId, Map<String, Object> fields) {
        try {
            Product_Rollup__c record = new Product_Rollup__c(Id = recordId);
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