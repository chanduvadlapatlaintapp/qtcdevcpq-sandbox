/**
 * @description Controller for Product2 and Item_Master_Product__c CRUD operations
 *              in the SKU Management App. Supports FR-1 (Standalone SKU Create),
 *              FR-3 (SKU Update), and shared picklist retrieval.
 */
public with sharing class SkuProductController {

    private static final String PRODUCT_FIELDS = 'Id, Name, ProductCode, Description, IsActive, '
        + 'Bundle_product__c, Cloud_Addendum_Required__c, Eligible_For_Premium__c, '
        + 'Guided_Selling_Type__c, Includes_Assist__c, '
        + 'Is_Accounting__c, Is_Consulting__c, Is_IBA__c, Is_Legal__c, '
        + 'Is_PCM__c, Is_Prime__c, Is_Real_Assets__c, Iss_Corporate__c, '
        + 'Item_Master_Product__c, Item_Master_Product__r.Name, '
        + 'Parent_Of_Bundle__c, Percentage_of_ACV__c, Pricing_Basis__c, '
        + 'Business_Unit_New__c, Product_Group__c, Product_License_Type__c, Product_LineNew__c, '
        + 'Product_LineNew__r.Name, Product_Revenue_Type__c, Revenue_Type__c, '
        + 'ProductRollup__c, ProductRollup__r.Name, '
        + 'Product_Type__c, SBQQ__BillingType__c, SBQQ__ChargeType__c, '
        + 'SBQQ__Component__c, SBQQ__ConfigurationEvent__c, SBQQ__ConfigurationType__c, '
        + 'SBQQ__DefaultPricingTable__c, SBQQ__Optional__c, SBQQ__PriceEditable__c, '
        + 'SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, '
        + 'SBQQ__SubscriptionType__c, Services_Product_Type__c, '
        + 'AVA_SFCPQ__TaxCode__c, SBQQ__TaxCode__c, '
        + 'CreatedDate, LastModifiedDate, CreatedBy.Name, LastModifiedBy.Name';

    private static final String ITEM_MASTER_FIELDS = 'Id, Name, Active__c, '
        + 'Business_Unit__c, Create_Revenue_Plans_On__c, Deferred_Revenue_Account__c, '
        + 'Description__c, Income_Account__c, Intapp_Item_Master_Number__c, Netsuite_Description__c, '
        + 'Intapp_Item_Master_Number_Text__c, Item_Master_Product_ID__c, Item_Name__c, '
        + 'Item_Revenue_Category__c, NS_Error__c, NetSuite_Allocation_Type__c, '
        + 'NetSuite_Billing_Schedule__c, NetSuite_Can_be_fulfilled__c, '
        + 'Exempt_from_Magic_Script__c, NetSuite_Direct_Revenue_Posting__c, NetSuite_Export_to_OpenAir__c, '
        + 'NetSuite_Include_Children__c, NetSuite_Internal_Id__c, '
        + 'NetSuite_Item_Type_For_Invoicing__c, NetSuite_Product_Line_ID__c, '
        + 'NetSuite_Revenue_Recognition_Template__c, NetSuite_SubType__c, '
        + 'NetSuite_Tax_Schedule__c, NetSuite_Type__c, OpenAir_Billing_Rule__c, '
        + 'Product_LineNew__c, Product_LineNew__r.Name, Rev_Rec_Forecast_Rule__c, '
        + 'Revenue_Allocation_Group__c, Revenue_Recognition_Rule__c, '
        + 'Revenue_Type__c, Sync_NetSuite__c, TaxCode__c, Trigger_to_NS__c, '
        + 'CreatedDate, LastModifiedDate, CreatedBy.Name, LastModifiedBy.Name';

    /**
     * @description Creates a standalone SKU: inserts Item_Master_Product__c first,
     *              then Product2 with the lookup set.
     * @param productFields Map of Product2 field API names to values
     * @param itemMasterFields Map of Item_Master_Product__c field API names to values
     * @return Id of the newly created Product2 record
     */
    @AuraEnabled
    public static Id createStandaloneSku(Map<String, Object> productFields, Map<String, Object> itemMasterFields) {
        try {
            // Build and insert Item Master Product
            Item_Master_Product__c itemMaster = (Item_Master_Product__c) buildSObject(
                'Item_Master_Product__c', itemMasterFields
            );
            insert itemMaster;
            itemMaster.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(itemMaster.Id);
            update itemMaster;
            StagingCaptureService.capture(new List<Item_Master_Product__c>{ itemMaster }, 'Item_Master_Product__c', 'Create');

            // Build Product2 and link to Item Master
            Product2 product = (Product2) buildSObject('Product2', productFields);
            product.Item_Master_Product__c = itemMaster.Id;
            insert product;
            product.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(product.Id);
            update product;
            StagingCaptureService.capture(new List<Product2>{ product }, 'Product2', 'Create');

            return product.Id;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Bulk creates multiple standalone SKUs (Product2 + Item_Master_Product__c pairs).
     * @param recordsJson JSON array of { productFields: {}, itemMasterFields: {} } objects
     * @return List of created Product2 Ids
     */
    @AuraEnabled
    public static List<Id> bulkCreateStandaloneSkus(String recordsJson) {
        try {
            List<Object> rowsRaw = (List<Object>) JSON.deserializeUntyped(recordsJson);
            List<Item_Master_Product__c> itemMastersToInsert = new List<Item_Master_Product__c>();
            List<Map<String, Object>> productFieldsList = new List<Map<String, Object>>();

            // Phase 1: Build all Item Master records
            for (Object rowObj : rowsRaw) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Map<String, Object> imFields = (Map<String, Object>) row.get('itemMasterFields');
                Map<String, Object> pFields = (Map<String, Object>) row.get('productFields');

                Item_Master_Product__c im = (Item_Master_Product__c) buildSObject(
                    'Item_Master_Product__c', imFields
                );
                itemMastersToInsert.add(im);
                productFieldsList.add(pFields);
            }

            // Phase 2: Bulk insert Item Masters (trigger validates Name uniqueness)
            insert itemMastersToInsert;
            List<Item_Master_Product__c> imGearsetUpdates = new List<Item_Master_Product__c>();
            for (Item_Master_Product__c im : itemMastersToInsert) {
                im.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(im.Id);
                imGearsetUpdates.add(new Item_Master_Product__c(Id = im.Id, GearsetExternalId__c = im.GearsetExternalId__c));
            }
            Database.update(imGearsetUpdates, false);
            StagingCaptureService.capture(itemMastersToInsert, 'Item_Master_Product__c', 'Create');

            // Phase 3: Build all Product2 records, linking to their Item Masters
            List<Product2> productsToInsert = new List<Product2>();
            for (Integer i = 0; i < productFieldsList.size(); i++) {
                Product2 p = (Product2) buildSObject('Product2', productFieldsList[i]);
                p.Item_Master_Product__c = itemMastersToInsert[i].Id;
                productsToInsert.add(p);
            }

            // Phase 4: Bulk insert Products
            insert productsToInsert;
            List<Product2> prodGearsetUpdates = new List<Product2>();
            for (Product2 p : productsToInsert) {
                p.GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(p.Id);
                prodGearsetUpdates.add(new Product2(Id = p.Id, GearsetExternalId__c = p.GearsetExternalId__c));
            }
            Database.update(prodGearsetUpdates, false);
            StagingCaptureService.capture(productsToInsert, 'Product2', 'Create');

            // Phase 5: Collect and return created Product Ids
            List<Id> createdIds = new List<Id>();
            for (Product2 p : productsToInsert) {
                createdIds.add(p.Id);
            }
            return createdIds;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Retrieves full SKU details (Product2 + related Item_Master_Product__c).
     * @param productId The Product2 record Id
     * @return SkuWrapper containing both records
     */
    @AuraEnabled
    public static SkuWrapper getSkuDetails(Id productId) {
        try {
            SkuWrapper wrapper = new SkuWrapper();

            String productQuery = 'SELECT ' + PRODUCT_FIELDS + ' FROM Product2 WHERE Id = :productId';
            List<Product2> products = Database.query(productQuery);
            if (products.isEmpty()) {
                throw new AuraHandledException('Product not found.');
            }
            wrapper.product = products[0];

            if (wrapper.product.Item_Master_Product__c != null) {
                Id itemMasterId = wrapper.product.Item_Master_Product__c;
                String impQuery = 'SELECT ' + ITEM_MASTER_FIELDS + ' FROM Item_Master_Product__c WHERE Id = :itemMasterId';
                List<Item_Master_Product__c> itemMasters = Database.query(impQuery);
                if (!itemMasters.isEmpty()) {
                    wrapper.itemMaster = itemMasters[0];
                }
            }

            return wrapper;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Updates an existing SKU (Product2 + Item_Master_Product__c).
     *              Note: Item Master Name field is excluded from updates per trigger constraint.
     * @param productFields Map of changed Product2 fields
     * @param itemMasterFields Map of changed Item_Master_Product__c fields (Name excluded)
     * @param productId Product2 record Id
     * @param itemMasterId Item_Master_Product__c record Id
     */
    @AuraEnabled
    public static void updateSku(
        Map<String, Object> productFields,
        Map<String, Object> itemMasterFields,
        Id productId,
        Id itemMasterId
    ) {
        try {
            if (productFields != null && !productFields.isEmpty()) {
                Product2 product = (Product2) buildSObject('Product2', productFields);
                product.Id = productId;
                update product;
                // Idempotent: persist reversed GearsetExternalId__c to DB only if not already set
                for (Product2 check : [SELECT Id, GearsetExternalId__c FROM Product2 WHERE Id = :productId LIMIT 1]) {
                    if (check.GearsetExternalId__c == null) {
                        Database.update(new Product2(Id = productId, GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(productId)), false);
                    }
                }
                StagingCaptureService.capture(new List<Product2>{ product }, 'Product2', 'Update');
            }

            if (itemMasterFields != null && !itemMasterFields.isEmpty() && itemMasterId != null) {
                // Remove Name field to prevent trigger validation error
                itemMasterFields.remove('Name');
                if (!itemMasterFields.isEmpty()) {
                    Item_Master_Product__c itemMaster = (Item_Master_Product__c) buildSObject(
                        'Item_Master_Product__c', itemMasterFields
                    );
                    itemMaster.Id = itemMasterId;
                    update itemMaster;
                    // Idempotent: persist reversed GearsetExternalId__c to DB only if not already set
                    for (Item_Master_Product__c check : [SELECT Id, GearsetExternalId__c FROM Item_Master_Product__c WHERE Id = :itemMasterId LIMIT 1]) {
                        if (check.GearsetExternalId__c == null) {
                            Database.update(new Item_Master_Product__c(Id = itemMasterId, GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(itemMasterId)), false);
                        }
                    }
                    StagingCaptureService.capture(new List<Item_Master_Product__c>{ itemMaster }, 'Item_Master_Product__c', 'Update');
                }
            }
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Searches for existing products for the Update SKU flow.
     * @param searchTerm Search string to match against Name or ProductCode
     * @return List of matching Product2 records with key fields
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> searchProductsForUpdate(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Product2>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        return [
            SELECT Id, Name, ProductCode, IsActive,
                   Product_LineNew__r.Name, Product_Type__c,
                   Item_Master_Product__c, Item_Master_Product__r.Name
            FROM Product2
            WHERE Name LIKE :key OR ProductCode LIKE :key
            ORDER BY Name ASC
            LIMIT 50
        ];
    }

    /**
     * @description Validates that an Item Master Product name is unique before creation.
     * @param name The proposed Item Master Product name
     * @return True if the name is available (no existing record with this name)
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isItemMasterNameAvailable(String name) {
        if (String.isBlank(name)) {
            return false;
        }
        Integer count = [SELECT COUNT() FROM Item_Master_Product__c WHERE Name = :name];
        return count == 0;
    }

    /**
     * @description Gets picklist values for Product2 fields.
     * @return Map of field API names to their picklist options
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getProductPicklistValues() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Product2.fields.getMap();

        List<String> picklistFields = new List<String>{
            'Product_Type__c', 'Product_License_Type__c', 'Pricing_Basis__c',
            'Product_Group__c', 'Services_Product_Type__c', 'Guided_Selling_Type__c',
            'SBQQ__BillingType__c', 'SBQQ__ChargeType__c', 'SBQQ__SubscriptionPricing__c',
            'SBQQ__SubscriptionType__c', 'SBQQ__ConfigurationEvent__c',
            'SBQQ__ConfigurationType__c', 'Revenue_Type__c',
            'Is_Legal__c', 'Is_Accounting__c', 'Is_Consulting__c', 'Is_IBA__c',
            'Is_PCM__c', 'Is_Real_Assets__c', 'Iss_Corporate__c'
        };

        for (String fieldName : picklistFields) {
            if (fieldMap.containsKey(fieldName)) {
                List<PicklistOption> options = new List<PicklistOption>();
                for (Schema.PicklistEntry entry : fieldMap.get(fieldName).getDescribe().getPicklistValues()) {
                    if (entry.isActive()) {
                        options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                    }
                }
                result.put(fieldName, options);
            }
        }

        return result;
    }

    /**
     * @description Gets picklist values for Item_Master_Product__c fields.
     * @return Map of field API names to their picklist options
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getItemMasterPicklistValues() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Item_Master_Product__c.fields.getMap();

        List<String> picklistFields = new List<String>{
            'Item_Revenue_Category__c', 'Revenue_Type__c', 'NetSuite_Type__c',
            'NetSuite_SubType__c', 'Create_Revenue_Plans_On__c',
            'NetSuite_Allocation_Type__c', 'NetSuite_Billing_Schedule__c',
            'NetSuite_Revenue_Recognition_Template__c', 'NetSuite_Tax_Schedule__c',
            'NetSuite_Item_Type_For_Invoicing__c', 'Rev_Rec_Forecast_Rule__c',
            'Revenue_Allocation_Group__c', 'Revenue_Recognition_Rule__c',
            'OpenAir_Billing_Rule__c', 'Income_Account__c', 'Deferred_Revenue_Account__c'
        };

        for (String fieldName : picklistFields) {
            if (fieldMap.containsKey(fieldName)) {
                List<PicklistOption> options = new List<PicklistOption>();
                for (Schema.PicklistEntry entry : fieldMap.get(fieldName).getDescribe().getPicklistValues()) {
                    if (entry.isActive()) {
                        options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                    }
                }
                result.put(fieldName, options);
            }
        }

        return result;
    }

    /**
     * @description Searches for products with optional filters for the inline-edit Update tab.
     *              Returns full Product2 + Item_Master_Product__c data for grid rendering.
     * @param productName Optional LIKE filter on Product2.Name (min 2 chars)
     * @param productCode Optional LIKE filter on Product2.ProductCode (min 2 chars)
     * @param productType Optional exact match on Product2.Product_Type__c
     * @param isActive Optional 'true'/'false' filter on Product2.IsActive
     * @return List of SkuWrapper containing Product2 and related Item_Master_Product__c
     */
    @AuraEnabled
    public static List<SkuWrapper> searchProductsFiltered(
        String productName, String productCode, String productType, String isActive
    ) {
        try {
            String query = 'SELECT ' + PRODUCT_FIELDS + ' FROM Product2 WHERE Id != null';

            if (String.isNotBlank(productName) && productName.length() >= 2) {
                String safeName = '%' + String.escapeSingleQuotes(productName.trim()) + '%';
                query += ' AND Name LIKE \'' + safeName + '\'';
            }
            if (String.isNotBlank(productCode) && productCode.length() >= 2) {
                String safeCode = '%' + String.escapeSingleQuotes(productCode.trim()) + '%';
                query += ' AND ProductCode LIKE \'' + safeCode + '\'';
            }
            if (String.isNotBlank(productType)) {
                String safeType = String.escapeSingleQuotes(productType);
                query += ' AND Product_Type__c = \'' + safeType + '\'';
            }
            if (String.isNotBlank(isActive)) {
                query += ' AND IsActive = ' + (isActive == 'true' ? 'true' : 'false');
            }

            query += ' ORDER BY Name ASC LIMIT 200';
            List<Product2> products = Database.query(query);

            // Collect Item Master Ids and batch-query
            Set<Id> impIds = new Set<Id>();
            for (Product2 p : products) {
                if (p.Item_Master_Product__c != null) {
                    impIds.add(p.Item_Master_Product__c);
                }
            }

            Map<Id, Item_Master_Product__c> impMap = new Map<Id, Item_Master_Product__c>();
            if (!impIds.isEmpty()) {
                String impQuery = 'SELECT ' + ITEM_MASTER_FIELDS
                    + ' FROM Item_Master_Product__c WHERE Id IN :impIds';
                for (Item_Master_Product__c imp : Database.query(impQuery)) {
                    impMap.put(imp.Id, imp);
                }
            }

            List<SkuWrapper> results = new List<SkuWrapper>();
            for (Product2 p : products) {
                SkuWrapper w = new SkuWrapper();
                w.product = p;
                w.itemMaster = impMap.get(p.Item_Master_Product__c);
                results.add(w);
            }
            return results;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Bulk-updates multiple SKU records (Product2 + Item_Master_Product__c).
     *              Accepts a JSON payload of row changes. Each row contains productId,
     *              optional itemMasterId, and maps of changed fields.
     *              Note: Item Master Name field is automatically excluded per trigger constraint.
     * @param recordsJson JSON string of List<Map<String,Object>> with keys:
     *        productId, itemMasterId, productFields, itemMasterFields
     */
    @AuraEnabled
    public static void bulkUpdateSkus(String recordsJson) {
        try {
            List<Object> rowsRaw = (List<Object>) JSON.deserializeUntyped(recordsJson);
            List<Product2> productsToUpdate = new List<Product2>();
            List<Item_Master_Product__c> itemMastersToUpdate = new List<Item_Master_Product__c>();

            for (Object rowObj : rowsRaw) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                Id productId = (Id) row.get('productId');
                Id itemMasterId = row.get('itemMasterId') != null ? (Id) row.get('itemMasterId') : null;
                Map<String, Object> productFields = row.get('productFields') != null
                    ? (Map<String, Object>) row.get('productFields') : null;
                Map<String, Object> itemMasterFields = row.get('itemMasterFields') != null
                    ? (Map<String, Object>) row.get('itemMasterFields') : null;

                if (productFields != null && !productFields.isEmpty()) {
                    Product2 p = (Product2) buildSObject('Product2', productFields);
                    p.Id = productId;
                    productsToUpdate.add(p);
                }

                if (itemMasterFields != null && !itemMasterFields.isEmpty() && itemMasterId != null) {
                    // Remove Name field to prevent trigger validation error
                    itemMasterFields.remove('Name');
                    if (!itemMasterFields.isEmpty()) {
                        Item_Master_Product__c imp = (Item_Master_Product__c) buildSObject(
                            'Item_Master_Product__c', itemMasterFields
                        );
                        imp.Id = itemMasterId;
                        itemMastersToUpdate.add(imp);
                    }
                }
            }

            if (!productsToUpdate.isEmpty()) {
                update productsToUpdate;
                // Idempotent: persist reversed GearsetExternalId__c to DB only for records where it is null
                Set<Id> prodIds = new Set<Id>();
                for (Product2 p : productsToUpdate) { if (p.Id != null) prodIds.add(p.Id); }
                Map<Id, Product2> existingProdGearset = new Map<Id, Product2>(
                    [SELECT Id, GearsetExternalId__c FROM Product2 WHERE Id IN :prodIds]
                );
                List<Product2> prodGearsetUpdates = new List<Product2>();
                for (Product2 p : productsToUpdate) {
                    Product2 existing = existingProdGearset.get(p.Id);
                    if (p.Id != null && existing != null && existing.GearsetExternalId__c == null) {
                        prodGearsetUpdates.add(new Product2(Id = p.Id, GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(p.Id)));
                    }
                }
                if (!prodGearsetUpdates.isEmpty()) Database.update(prodGearsetUpdates, false);
                StagingCaptureService.capture(productsToUpdate, 'Product2', 'Update');
            }
            if (!itemMastersToUpdate.isEmpty()) {
                update itemMastersToUpdate;
                // Idempotent: persist reversed GearsetExternalId__c to DB only for records where it is null
                Set<Id> imIds = new Set<Id>();
                for (Item_Master_Product__c im : itemMastersToUpdate) { if (im.Id != null) imIds.add(im.Id); }
                Map<Id, Item_Master_Product__c> existingImGearset = new Map<Id, Item_Master_Product__c>(
                    [SELECT Id, GearsetExternalId__c FROM Item_Master_Product__c WHERE Id IN :imIds]
                );
                List<Item_Master_Product__c> imGearsetUpdates = new List<Item_Master_Product__c>();
                for (Item_Master_Product__c im : itemMastersToUpdate) {
                    Item_Master_Product__c existing = existingImGearset.get(im.Id);
                    if (im.Id != null && existing != null && existing.GearsetExternalId__c == null) {
                        imGearsetUpdates.add(new Item_Master_Product__c(Id = im.Id, GearsetExternalId__c = StagingCaptureService.buildGearsetExternalId(im.Id)));
                    }
                }
                if (!imGearsetUpdates.isEmpty()) Database.update(imGearsetUpdates, false);
                StagingCaptureService.capture(itemMastersToUpdate, 'Item_Master_Product__c', 'Update');
            }
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns all active Product Line records for use in lookup comboboxes.
     * @return List of PicklistOption with label=Name, value=Id
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getProductLineOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Product_Line__c pl : [SELECT Id, Name FROM Product_Line__c WHERE Active__c = true ORDER BY Name ASC]) {
            options.add(new PicklistOption(pl.Name, pl.Id));
        }
        return options;
    }

    /**
     * @description Gets all Product Rollup records as options for the lookup combobox.
     * @return List of PicklistOption with Name (label) and Id (value)
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getProductRollupOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Product_Rollup__c pr : [SELECT Id, Name FROM Product_Rollup__c ORDER BY Name ASC]) {
            options.add(new PicklistOption(pr.Name, pr.Id));
        }
        return options;
    }

    /**
     * @description Returns inline help text for Product2 and Item_Master_Product__c fields.
     *              Used by the LWC to show field-level help tooltips on hover.
     * @return Map with keys 'product' and 'itemMaster', each containing field API name → help text
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Map<String, String>> getFieldHelpText() {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();

        // Product2 field help text
        Map<String, String> productHelp = new Map<String, String>();
        for (Schema.SObjectField field : Schema.SObjectType.Product2.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = field.getDescribe();
            String helpText = dfr.getInlineHelpText();
            if (String.isNotBlank(helpText)) {
                productHelp.put(dfr.getName(), helpText);
            }
        }
        result.put('product', productHelp);

        // Item_Master_Product__c field help text
        Map<String, String> imHelp = new Map<String, String>();
        for (Schema.SObjectField field : Schema.SObjectType.Item_Master_Product__c.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = field.getDescribe();
            String helpText = dfr.getInlineHelpText();
            if (String.isNotBlank(helpText)) {
                imHelp.put(dfr.getName(), helpText);
            }
        }
        result.put('itemMaster', imHelp);

        return result;
    }

    // =========================================================================
    // Helper Methods
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
        if (value == null) {
            return null;
        }
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

    // =========================================================================
    // Inner Classes
    // =========================================================================

    public class SkuWrapper {
        @AuraEnabled public Product2 product;
        @AuraEnabled public Item_Master_Product__c itemMaster;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}