/**
 * @description Controller for Bundle SKU creation and Product Option management
 *              in the SKU Management App. Supports FR-2 (Static Bundle SKU Launch).
 */
public with sharing class SkuBundleController {

    private static final String PRODUCT_OPTION_FIELDS =
        'Id, Name, SBQQ__ConfiguredSKU__c, SBQQ__ConfiguredSKU__r.Name, ' +
        'SBQQ__OptionalSKU__c, SBQQ__OptionalSKU__r.Name, ' +
        'SBQQ__Bundled__c, SBQQ__DiscountAmount__c, ' +
        'SBQQ__DiscountSchedule__c, SBQQ__Feature__c, ' +
        'SBQQ__MaxQuantity__c, SBQQ__MinQuantity__c, ' +
        'SBQQ__Number__c, SBQQ__Quantity__c, ' +
        'SBQQ__QuantityEditable__c, SBQQ__Required__c, ' +
        'SBQQ__Selected__c, SBQQ__Type__c, SBQQ__UnitPrice__c';

    /**
     * @description Creates a Bundle SKU: inserts Item_Master_Product__c,
     *              then Product2 with bundle flags, then SBQQ__ProductOption__c records.
     * @param productFields Map of Product2 field values
     * @param itemMasterFields Map of Item_Master_Product__c field values
     * @param componentRows List of Maps representing SBQQ__ProductOption__c records
     * @return Id of the newly created bundle Product2
     */
    @AuraEnabled
    public static Id createBundleSku(
        Map<String, Object> productFields,
        Map<String, Object> itemMasterFields,
        List<Map<String, Object>> componentRows
    ) {
        try {
            // Insert Item Master Product
            Item_Master_Product__c itemMaster = (Item_Master_Product__c) buildSObject(
                'Item_Master_Product__c', itemMasterFields
            );
            insert itemMaster;
            itemMaster.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(itemMaster.Id);
            update itemMaster;
            StagingCaptureService.capture(new List<Item_Master_Product__c>{ itemMaster }, 'Item_Master_Product__c', 'Create');

            // Insert Product2 with bundle defaults
            Product2 product = (Product2) buildSObject('Product2', productFields);
            product.Item_Master_Product__c = itemMaster.Id;
            product.Parent_Of_Bundle__c = true;
            product.SBQQ__ConfigurationType__c = 'Allowed';
            insert product;
            product.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(product.Id);
            update product;
            StagingCaptureService.capture(new List<Product2>{ product }, 'Product2', 'Create');

            // Insert Product Options linking bundle to components
            if (componentRows != null && !componentRows.isEmpty()) {
                List<SBQQ__ProductOption__c> options = new List<SBQQ__ProductOption__c>();
                for (Map<String, Object> row : componentRows) {
                    SBQQ__ProductOption__c opt = (SBQQ__ProductOption__c) buildSObject(
                        'SBQQ__ProductOption__c', row
                    );
                    opt.SBQQ__ConfiguredSKU__c = product.Id;
                    options.add(opt);
                }
                insert options;
            }

            return product.Id;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Gets Product Options for an existing bundle product.
     * @param bundleProductId The bundle Product2 Id
     * @return List of SBQQ__ProductOption__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<SBQQ__ProductOption__c> getProductOptions(Id bundleProductId) {
        return Database.query(
            'SELECT ' + PRODUCT_OPTION_FIELDS +
            ' FROM SBQQ__ProductOption__c' +
            ' WHERE SBQQ__ConfiguredSKU__c = :bundleProductId' +
            ' ORDER BY SBQQ__Number__c'
        );
    }

    /**
     * @description Upserts Product Options for a bundle.
     * @param recordsJson JSON string of List<SBQQ__ProductOption__c>
     * @param bundleProductId The bundle Product2 Id
     * @return List of upserted records
     */
    @AuraEnabled
    public static List<SBQQ__ProductOption__c> saveProductOptions(String recordsJson, Id bundleProductId) {
        try {
            List<SBQQ__ProductOption__c> records = (List<SBQQ__ProductOption__c>) JSON.deserialize(
                recordsJson, List<SBQQ__ProductOption__c>.class
            );

            for (SBQQ__ProductOption__c rec : records) {
                if (rec.Id == null) {
                    rec.SBQQ__ConfiguredSKU__c = bundleProductId;
                }
            }

            upsert records;
            return records;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Searches for component products (excluding bundles to avoid circular refs).
     * @param searchTerm Search string
     * @return List of matching Product2 records
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> searchComponentProducts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Product2>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        return [
            SELECT Id, Name, ProductCode, IsActive, Product_Type__c
            FROM Product2
            WHERE (Name LIKE :key OR ProductCode LIKE :key)
                AND Parent_Of_Bundle__c != true
            ORDER BY Name ASC
            LIMIT 50
        ];
    }

    /**
     * @description Deletes Product Option records.
     * @param recordIds List of SBQQ__ProductOption__c Ids
     */
    @AuraEnabled
    public static void deleteProductOptions(List<Id> recordIds) {
        try {
            if (recordIds == null || recordIds.isEmpty()) {
                return;
            }
            delete [SELECT Id FROM SBQQ__ProductOption__c WHERE Id IN :recordIds];
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Helper - reuse SkuProductController.buildSObject pattern
    // =========================================================================

    private static SObject buildSObject(String objectApiName, Map<String, Object> fieldValues) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        SObject record = sObjectType.newSObject();
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        for (String fieldName : fieldValues.keySet()) {
            Object fieldValue = fieldValues.get(fieldName);
            if (fieldMap.containsKey(fieldName) && fieldValue != null) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                if (fieldDescribe.isCreateable() || fieldDescribe.isUpdateable()) {
                    record.put(fieldName, convertFieldValue(fieldDescribe, fieldValue));
                }
            }
        }
        return record;
    }

    private static Object convertFieldValue(Schema.DescribeFieldResult fieldDescribe, Object value) {
        if (value == null) return null;
        Schema.DisplayType fieldType = fieldDescribe.getType();
        String strValue = String.valueOf(value);

        if (fieldType == Schema.DisplayType.BOOLEAN) {
            return Boolean.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.CURRENCY || fieldType == Schema.DisplayType.DOUBLE
                   || fieldType == Schema.DisplayType.PERCENT) {
            return Decimal.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.DATE) {
            return Date.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.DATETIME) {
            return Datetime.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.REFERENCE) {
            return Id.valueOf(strValue);
        }
        return strValue;
    }
}