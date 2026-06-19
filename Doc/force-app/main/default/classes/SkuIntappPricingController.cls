/**
 * @description Controller for Intapp_Pricing__c CRUD operations in the
 *              SKU Management App. Supports FR-5 (Create/Update Pricing).
 */
public with sharing class SkuIntappPricingController {

    private static final String INTAPP_PRICING_FIELDS =
        'Id, Name, Price__c, Premium_price__c, Price_Book__c, ' +
        'Product_Code__c, Product__c, Product__r.Name, ' +
        'Meter_Type__c, Tier__c, Quantity_Low__c, Quantity_High__c, ' +
        'Gold_Pricing__c, Platinum_Pricing__c, Bundle_Discount__c, ' +
        'Corporate_Sales__c, Legal_Sales__c, A_C_Sales__c, PS_Sales__c, ' +
        'Partner_Sales__c, FS_Sales__c, Ops_Only__c, PS_Ops_Only__c, FS_Ops_Only__c';

    /**
     * @description Retrieves Intapp_Pricing__c records for a given Product.
     * @param productId The Product2 record Id
     * @return List of Intapp_Pricing__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Intapp_Pricing__c> getIntappPricingByProduct(Id productId) {
        return Database.query(
            'SELECT ' + INTAPP_PRICING_FIELDS +
            ' FROM Intapp_Pricing__c' +
            ' WHERE Product__c = :productId' +
            ' ORDER BY Name ASC'
        );
    }

    /**
     * @description Upserts Intapp_Pricing__c records from a JSON payload.
     *              New records get Product__c set automatically.
     *              Note: IntappPricingTrigger fires after insert/update and
     *              publishes DealEvent__e via IntegrationUtility.
     * @param recordsJson JSON string of List<Intapp_Pricing__c>
     * @param productId Product2 Id for new records
     * @return List of upserted records
     */
    @AuraEnabled
    public static List<Intapp_Pricing__c> saveIntappPricingRecords(String recordsJson, Id productId) {
        try {
            List<Intapp_Pricing__c> records = (List<Intapp_Pricing__c>) JSON.deserialize(
                recordsJson, List<Intapp_Pricing__c>.class
            );

            for (Intapp_Pricing__c rec : records) {
                if (rec.Id == null) {
                    rec.Product__c = productId;
                }
            }

            upsert records;
            List<SObject> ipGearsetUpdates = new List<SObject>();
            for (Intapp_Pricing__c rec : records) {
                if (rec.Id != null && rec.GearsetExternalId__c == null) {
                    String reversedId = StagingCaptureService.buildGearsetExternalId(rec.Id);
                    ipGearsetUpdates.add(new Intapp_Pricing__c(Id = rec.Id, GearsetExternalId__c = reversedId));
                    rec.GearsetExternalId__c = reversedId;
                }
            }
            if (!ipGearsetUpdates.isEmpty()) Database.update(ipGearsetUpdates, false);
            StagingCaptureService.capture(records, 'Intapp_Pricing__c', 'Update');
            return records;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes Intapp_Pricing__c records by Id.
     * @param recordIds List of record Ids to delete
     */
    @AuraEnabled
    public static void deleteIntappPricingRecords(List<Id> recordIds) {
        try {
            if (recordIds == null || recordIds.isEmpty()) {
                return;
            }
            List<Intapp_Pricing__c> toDelete = [SELECT Id, GearsetExternalId__c FROM Intapp_Pricing__c WHERE Id IN :recordIds];
            delete toDelete;
            StagingCaptureService.captureDeletes(toDelete, 'Intapp_Pricing__c');
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns picklist values for Intapp_Pricing__c fields.
     * @return Map of field API name to list of PicklistOption
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getIntappPricingPicklists() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Intapp_Pricing__c.fields.getMap();

        List<String> picklistFields = new List<String>{
            'Meter_Type__c', 'Tier__c'
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

    // =========================================================================
    // Inner Classes
    // =========================================================================

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}