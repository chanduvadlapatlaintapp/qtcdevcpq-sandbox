/**
 * @description Controller for Block Pricing / Meter Type management in the
 *              SKU Management App. Provides CRUD operations on Block_Pricing__c
 *              records, picklist retrieval, and tier configuration lookup.
 */
public with sharing class SkuBlockPricingController {

    private static final String BLOCK_PRICING_FIELDS =
        'Id, Name, Active__c, Block_Pricing_Meter_Type__c, CurrencyIsoCode, ' +
        'Fiscal_Year__c, Legal__c, Legal_meter_type_USD_AUD__c, Lower_Bound__c, ' +
        'Price__c, Product__c, Product__r.Name, Tier_Name__c, Type__c, Upper_Bound__c, ' +
        'meter_type_Accounting__c, meter_type_Consulting__c, meter_type_Corporate__c, ' +
        'meter_type_IBA__c, meter_type_PCM__c, meter_type_RealAssets__c';

    /**
     * @description Retrieves Block_Pricing__c records for a given Product.
     * @param productId The Product2 record Id
     * @return List of Block_Pricing__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Block_Pricing__c> getMeterTypeRecords(Id productId) {
        return Database.query(
            'SELECT ' + BLOCK_PRICING_FIELDS +
            ' FROM Block_Pricing__c' +
            ' WHERE Product__c = :productId' +
            ' ORDER BY Block_Pricing_Meter_Type__c, Tier_Name__c'
        );
    }

    /**
     * @description Retrieves the single Block_Pricing__c record with Type__c = 'Meter Type'
     *              for a given Product.
     * @param productId The Product2 record Id
     * @return Block_Pricing__c record, or null if none exists
     */
    @AuraEnabled
    public static Block_Pricing__c getMeterTypeRecord(Id productId) {
        List<Block_Pricing__c> records = Database.query(
            'SELECT ' + BLOCK_PRICING_FIELDS +
            ' FROM Block_Pricing__c' +
            ' WHERE Product__c = :productId AND Type__c = \'Meter Type\'' +
            ' LIMIT 1'
        );
        return records.isEmpty() ? null : records[0];
    }

    /**
     * @description Upserts Block_Pricing__c records. New records get Product__c set.
     *              Replicates obsolete flow logic: looks up Pricing_Tier_Configuration__mdt
     *              by Tier + Meter Type to auto-set Lower_Bound__c / Upper_Bound__c.
     * @param recordsJson JSON string of List<Block_Pricing__c>
     * @param productId Product2 Id for new records
     * @return List of upserted records
     */
    @AuraEnabled
    public static List<Block_Pricing__c> saveMeterTypeRecords(String recordsJson, Id productId) {
        try {
            List<Block_Pricing__c> records = (List<Block_Pricing__c>) JSON.deserialize(
                recordsJson, List<Block_Pricing__c>.class
            );

            // Auto-fill bounds from tier configuration (replicates obsolete flow)
            Map<String, Pricing_Tier_Configuration__mdt> tierConfigMap = getTierConfigMap();

            for (Block_Pricing__c rec : records) {
                if (rec.Id == null) {
                    rec.Product__c = productId;
                }
                // Auto-set bounds if tier and meter type are provided
                if (String.isNotBlank(rec.Tier_Name__c) && String.isNotBlank(rec.Block_Pricing_Meter_Type__c)) {
                    String configKey = rec.Tier_Name__c + '|' + rec.Block_Pricing_Meter_Type__c;
                    if (tierConfigMap.containsKey(configKey)) {
                        Pricing_Tier_Configuration__mdt config = tierConfigMap.get(configKey);
                        rec.Lower_Bound__c = config.Lower_Bound__c;
                        rec.Upper_Bound__c = config.Upper_Bound__c;
                    }
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
     * @description Deletes Block_Pricing__c records by Id.
     * @param recordIds List of record Ids to delete
     */
    @AuraEnabled
    public static void deleteBlockPricingRecords(List<Id> recordIds) {
        try {
            if (recordIds == null || recordIds.isEmpty()) {
                return;
            }
            delete [SELECT Id FROM Block_Pricing__c WHERE Id IN :recordIds];
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Queries Pricing_Tier_Configuration__mdt for a specific tier/meter type.
     * @param tierName The tier name
     * @param meterType The meter type value
     * @return TierConfig wrapper with bounds, or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static TierConfig getTierConfiguration(String tierName, String meterType) {
        if (String.isBlank(tierName) || String.isBlank(meterType)) {
            return null;
        }
        List<Pricing_Tier_Configuration__mdt> configs = [
            SELECT Lower_Bound__c, Upper_Bound__c, Tier__c, Meter_Type__c
            FROM Pricing_Tier_Configuration__mdt
            WHERE Tier__c = :tierName AND Meter_Type__c = :meterType
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            return null;
        }
        return new TierConfig(configs[0].Lower_Bound__c, configs[0].Upper_Bound__c);
    }

    /**
     * @description Returns picklist values for Block_Pricing__c fields.
     * @return Map of field API name to list of PicklistOption
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getBlockPricingPicklists() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Block_Pricing__c.fields.getMap();

        List<String> picklistFields = new List<String>{
            'Block_Pricing_Meter_Type__c', 'Type__c', 'Fiscal_Year__c', 'Tier_Name__c',
            'Legal__c', 'Legal_meter_type_USD_AUD__c',
            'meter_type_Accounting__c', 'meter_type_Consulting__c', 'meter_type_Corporate__c',
            'meter_type_IBA__c', 'meter_type_PCM__c', 'meter_type_RealAssets__c'
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
    // Helper Methods
    // =========================================================================

    private static Map<String, Pricing_Tier_Configuration__mdt> getTierConfigMap() {
        Map<String, Pricing_Tier_Configuration__mdt> configMap = new Map<String, Pricing_Tier_Configuration__mdt>();
        for (Pricing_Tier_Configuration__mdt config : [
            SELECT Tier__c, Meter_Type__c, Lower_Bound__c, Upper_Bound__c
            FROM Pricing_Tier_Configuration__mdt
        ]) {
            String key = config.Tier__c + '|' + config.Meter_Type__c;
            configMap.put(key, config);
        }
        return configMap;
    }

    // =========================================================================
    // Inner Classes
    // =========================================================================

    public class TierConfig {
        @AuraEnabled public Decimal lowerBound;
        @AuraEnabled public Decimal upperBound;

        public TierConfig(Decimal lowerBound, Decimal upperBound) {
            this.lowerBound = lowerBound;
            this.upperBound = upperBound;
        }
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