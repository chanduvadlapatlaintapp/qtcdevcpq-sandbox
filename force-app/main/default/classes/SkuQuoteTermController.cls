/**
 * @description Controller for SBQQ__QuoteTerm__c CRUD operations in the
 *              SKU Management App. Supports FR-6 (Quote Terms).
 *              Note: QuoteTermTrigger strips HTML <p> tags from Body on
 *              before insert/update, so plain text input is used.
 */
public with sharing class SkuQuoteTermController {

    private static final String QUOTE_TERM_FIELDS =
        'Id, Name, SBQQ__Active__c, SBQQ__Body__c, SBQQ__PrintOrder__c, ' +
        'SBQQ__Status__c, SBQQ__Type__c, Term_Category__c, Description__c';

    /**
     * @description Retrieves Quote Terms with optional filters.
     * @param filterType     Optional SBQQ__Type__c filter value
     * @param filterStatus   Optional SBQQ__Status__c filter value
     * @param searchTerm     Optional search term for Name (min 2 chars)
     * @param filterActive   'true' = active only, 'false' = inactive only, blank = all
     * @param filterCategory Optional Term_Category__c filter value
     * @param filterDesc     Optional Description__c LIKE search term (min 2 chars)
     * @return List of SBQQ__QuoteTerm__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<SBQQ__QuoteTerm__c> getQuoteTerms(
        String filterType, String filterStatus, String searchTerm,
        String filterActive, String filterCategory, String filterDesc
    ) {
        String query = 'SELECT ' + QUOTE_TERM_FIELDS +
            ' FROM SBQQ__QuoteTerm__c WHERE Id != null';

        if (String.isNotBlank(filterType)) {
            query += ' AND SBQQ__Type__c = \'' + String.escapeSingleQuotes(filterType) + '\'';
        }

        if (String.isNotBlank(filterStatus)) {
            query += ' AND SBQQ__Status__c = \'' + String.escapeSingleQuotes(filterStatus) + '\'';
        }

        if (String.isNotBlank(searchTerm) && searchTerm.length() >= 2) {
            String safeSearch = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE \'' + safeSearch + '\'';
        }

        if ('true'.equals(filterActive)) {
            query += ' AND SBQQ__Active__c = true';
        } else if ('false'.equals(filterActive)) {
            query += ' AND SBQQ__Active__c = false';
        }

        if (String.isNotBlank(filterCategory)) {
            query += ' AND Term_Category__c = \'' + String.escapeSingleQuotes(filterCategory) + '\'';
        }

        if (String.isNotBlank(filterDesc) && filterDesc.length() >= 2) {
            String safeDesc = '%' + String.escapeSingleQuotes(filterDesc.trim()) + '%';
            query += ' AND Description__c LIKE \'' + safeDesc + '\'';
        }

        query += ' ORDER BY SBQQ__PrintOrder__c ASC NULLS LAST, Name ASC LIMIT 200';

        return Database.query(query);
    }

    /**
     * @description Upserts Quote Term records from a JSON payload.
     *              Note: QuoteTermTrigger will strip HTML from Body.
     * @param recordsJson JSON string of List<SBQQ__QuoteTerm__c>
     * @return List of upserted records
     */
    @AuraEnabled
    public static List<SBQQ__QuoteTerm__c> saveQuoteTerms(String recordsJson) {
        try {
            List<SBQQ__QuoteTerm__c> records = (List<SBQQ__QuoteTerm__c>) JSON.deserialize(
                recordsJson, List<SBQQ__QuoteTerm__c>.class
            );

            upsert records;
            List<SObject> qtGearsetUpdates = new List<SObject>();
            for (SBQQ__QuoteTerm__c rec : records) {
                if (rec.Id != null && rec.GearsetExternalId__c == null) {
                    String reversedId = StagingCaptureService.buildGearsetExternalId(rec.Id);
                    qtGearsetUpdates.add(new SBQQ__QuoteTerm__c(Id = rec.Id, GearsetExternalId__c = reversedId));
                    rec.GearsetExternalId__c = reversedId;
                }
            }
            if (!qtGearsetUpdates.isEmpty()) Database.update(qtGearsetUpdates, false);
            StagingCaptureService.capture(records, 'SBQQ__QuoteTerm__c', 'Update');
            return records;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deletes Quote Term records by Id.
     * @param recordIds List of SBQQ__QuoteTerm__c Ids to delete
     */
    @AuraEnabled
    public static void deleteQuoteTerms(List<Id> recordIds) {
        try {
            if (recordIds == null || recordIds.isEmpty()) {
                return;
            }
            List<SBQQ__QuoteTerm__c> toDelete = [SELECT Id, GearsetExternalId__c FROM SBQQ__QuoteTerm__c WHERE Id IN :recordIds];
            delete toDelete;
            StagingCaptureService.captureDeletes(toDelete, 'SBQQ__QuoteTerm__c');
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns picklist values for Quote Term fields.
     * @return Map of field API name to list of PicklistOption
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getQuoteTermPicklists() {
        Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.SBQQ__QuoteTerm__c.fields.getMap();

        List<String> picklistFields = new List<String>{
            'SBQQ__Status__c', 'Term_Category__c'
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
     * @description Retrieves Quote Terms associated with a specific product code
     *              by querying SBQQ__TermCondition__c records that test the
     *              master_product_pins_from_all_quote_lines__c field.
     * @param productCode The ProductCode of the product
     * @return List of SBQQ__QuoteTerm__c records linked to this product
     */
    @AuraEnabled(cacheable=true)
    public static List<SBQQ__QuoteTerm__c> getQuoteTermsByProductCode(String productCode) {
        if (String.isBlank(productCode)) {
            return new List<SBQQ__QuoteTerm__c>();
        }

        String safeCode = '%' + String.escapeSingleQuotes(productCode.trim()) + '%';

        // Step 1: Find TermCondition records that reference this product code
        Set<Id> quoteTermIds = new Set<Id>();
        for (SBQQ__TermCondition__c tc : [
            SELECT SBQQ__QuoteTerm__c
            FROM SBQQ__TermCondition__c
            WHERE SBQQ__TestedField__c = 'master_product_pins_from_all_quote_lines__c'
              AND SBQQ__Value__c LIKE :safeCode
        ]) {
            quoteTermIds.add(tc.SBQQ__QuoteTerm__c);
        }

        if (quoteTermIds.isEmpty()) {
            return new List<SBQQ__QuoteTerm__c>();
        }

        // Step 2: Query the parent QuoteTerm records
        return Database.query(
            'SELECT ' + QUOTE_TERM_FIELDS +
            ' FROM SBQQ__QuoteTerm__c WHERE Id IN :quoteTermIds' +
            ' ORDER BY SBQQ__PrintOrder__c ASC NULLS LAST, Name ASC'
        );
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