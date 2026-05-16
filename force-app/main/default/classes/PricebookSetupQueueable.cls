/**
 * @description Queueable job for one-time pricebook setup (Phase 2 of Pricebook Launch Wizard).
 *              Creates PricebookEntry records (Standard + Custom pricebook) and SBQQ__Dimension__c
 *              records for active products. Processes in batches of 500 products and chains
 *              to the next batch when more products remain.
 *
 *              Phase flow:
 *              1. PRICEBOOK_ENTRIES - Creates Standard + Custom PricebookEntry for 4 currencies
 *              2. DIMENSIONS - Creates SBQQ__Dimension__c for Software/Support/Maintenance products
 *
 * @author  Claude Code
 * @date    2026-02-26
 */
public class PricebookSetupQueueable implements Queueable {

    private static final List<String> CURRENCIES = new List<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final Integer BATCH_SIZE = 500;

    private static final Set<String> DIMENSION_PRODUCT_TYPES = new Set<String>{
        'Software', 'Support', 'Maintenance'
    };

    @TestVisible
    private static Id standardPricebookIdOverride;

    private Id pricebookId;
    private String phase;
    private Integer offset;

    /**
     * @description Constructor for the queueable job.
     * @param pricebookId The target Pricebook2 Id
     * @param phase Current phase: 'PRICEBOOK_ENTRIES' or 'DIMENSIONS'
     * @param offset Product query offset for batching
     */
    public PricebookSetupQueueable(Id pricebookId, String phase, Integer offset) {
        this.pricebookId = pricebookId;
        this.phase = phase;
        this.offset = offset;
    }

    /**
     * @description Main execute method. Routes to the appropriate phase handler.
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        try {
            if (phase == 'PRICEBOOK_ENTRIES') {
                processPricebookEntries();
            } else if (phase == 'DIMENSIONS') {
                processDimensions();
            }
        } catch (Exception e) {
            Nebula.Logger.error('PricebookSetupQueueable error in phase ' + phase + ': ' + e.getMessage())
                .addTag('PricebookWizard')
                .setRecordId(pricebookId);
            Nebula.Logger.saveLog();
        }
    }

    /***********************************************************************************************
     *
     * Phase: PRICEBOOK_ENTRIES
     *
     ***********************************************************************************************/

    /**
     * @description Creates PricebookEntry records for active products under both the Standard
     *              Pricebook (if not existing) and the target custom Pricebook.
     *              Processes BATCH_SIZE products per execution, then chains for next batch.
     */
    private void processPricebookEntries() {
        // Query batch of active products
        List<Product2> products = [
            SELECT Id, ProductCode, Name
            FROM Product2
            WHERE IsActive = true
            ORDER BY Id
            LIMIT :BATCH_SIZE
            OFFSET :offset
        ];

        if (products.isEmpty()) {
            // No more products; move to DIMENSIONS phase
            Nebula.Logger.info('PricebookEntry phase complete. Moving to DIMENSIONS phase.')
                .addTag('PricebookWizard')
                .setRecordId(pricebookId);
            Nebula.Logger.saveLog();

            System.enqueueJob(new PricebookSetupQueueable(pricebookId, 'DIMENSIONS', 0));
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) {
            productIds.add(p.Id);
        }

        // Get Standard Pricebook Id
        Id standardPbId = standardPricebookIdOverride != null
            ? standardPricebookIdOverride
            : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

        // Find existing Standard PricebookEntry records for these products
        Map<String, PricebookEntry> existingStdEntries = new Map<String, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPbId
              AND Product2Id IN :productIds
        ]) {
            existingStdEntries.put(pbe.Product2Id + '_' + pbe.CurrencyIsoCode, pbe);
        }

        // Find existing Custom PricebookEntry records for these products
        Map<String, PricebookEntry> existingCustomEntries = new Map<String, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND Product2Id IN :productIds
        ]) {
            existingCustomEntries.put(pbe.Product2Id + '_' + pbe.CurrencyIsoCode, pbe);
        }

        // Build Standard PricebookEntry records (required before custom)
        List<PricebookEntry> stdEntries = new List<PricebookEntry>();
        for (Product2 p : products) {
            for (String curr : CURRENCIES) {
                String key = p.Id + '_' + curr;
                if (!existingStdEntries.containsKey(key)) {
                    stdEntries.add(new PricebookEntry(
                        Pricebook2Id = standardPbId,
                        Product2Id = p.Id,
                        CurrencyIsoCode = curr,
                        UnitPrice = 0,
                        IsActive = true
                    ));
                }
            }
        }

        // Insert Standard entries first (Salesforce requirement)
        if (!stdEntries.isEmpty()) {
            Database.SaveResult[] stdResults = Database.insert(stdEntries, false);
            Integer stdErrors = 0;
            for (Database.SaveResult sr : stdResults) {
                if (!sr.isSuccess()) stdErrors++;
            }

            Nebula.Logger.info(
                'Standard PBE batch offset=' + offset + ': ' +
                (stdEntries.size() - stdErrors) + ' created, ' + stdErrors + ' errors'
            ).addTag('PricebookWizard').setRecordId(pricebookId);
        }

        // Build Custom PricebookEntry records
        List<PricebookEntry> customEntries = new List<PricebookEntry>();
        for (Product2 p : products) {
            for (String curr : CURRENCIES) {
                String key = p.Id + '_' + curr;
                if (!existingCustomEntries.containsKey(key)) {
                    customEntries.add(new PricebookEntry(
                        Pricebook2Id = pricebookId,
                        Product2Id = p.Id,
                        CurrencyIsoCode = curr,
                        UnitPrice = 0,
                        IsActive = true
                    ));
                }
            }
        }

        if (!customEntries.isEmpty()) {
            Database.SaveResult[] customResults = Database.insert(customEntries, false);
            Integer customErrors = 0;
            for (Database.SaveResult sr : customResults) {
                if (!sr.isSuccess()) customErrors++;
            }

            Nebula.Logger.info(
                'Custom PBE batch offset=' + offset + ': ' +
                (customEntries.size() - customErrors) + ' created, ' + customErrors + ' errors'
            ).addTag('PricebookWizard').setRecordId(pricebookId);
        }

        Nebula.Logger.saveLog();

        // Chain next batch if we processed a full batch
        if (products.size() == BATCH_SIZE) {
            System.enqueueJob(
                new PricebookSetupQueueable(pricebookId, 'PRICEBOOK_ENTRIES', offset + BATCH_SIZE)
            );
        } else {
            // No more products; move to DIMENSIONS phase
            System.enqueueJob(new PricebookSetupQueueable(pricebookId, 'DIMENSIONS', 0));
        }
    }

    /***********************************************************************************************
     *
     * Phase: DIMENSIONS
     *
     ***********************************************************************************************/

    /**
     * @description Creates SBQQ__Dimension__c records for eligible products (Software, Support,
     *              Maintenance). Checks for existing dimensions to avoid duplicates using the
     *              same composite key pattern as PriceDimensionBatch.cls.
     */
    private void processDimensions() {
        // Query batch of active products eligible for dimensions
        List<Product2> products = [
            SELECT Id, Name, Product_Type__c
            FROM Product2
            WHERE IsActive = true
              AND Product_Type__c IN :DIMENSION_PRODUCT_TYPES
            ORDER BY Id
            LIMIT :BATCH_SIZE
            OFFSET :offset
        ];

        if (products.isEmpty()) {
            Nebula.Logger.info('Dimensions phase complete. Pricebook setup finished.')
                .addTag('PricebookWizard')
                .setRecordId(pricebookId);
            Nebula.Logger.saveLog();
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) {
            productIds.add(p.Id);
        }

        // Query existing dimensions for duplicate checking
        // Key: Product__c + CurrencyIsoCode + PriceBook__c
        Map<String, SBQQ__Dimension__c> existingDimensions = new Map<String, SBQQ__Dimension__c>();
        for (SBQQ__Dimension__c dim : [
            SELECT Id, SBQQ__Product__c, CurrencyIsoCode, SBQQ__PriceBook__c
            FROM SBQQ__Dimension__c
            WHERE SBQQ__Product__c IN :productIds
              AND SBQQ__PriceBook__c = :pricebookId
        ]) {
            String key = dim.SBQQ__Product__c + '' + dim.CurrencyIsoCode + '' + dim.SBQQ__PriceBook__c;
            existingDimensions.put(key, dim);
        }

        // Build new dimension records
        List<SBQQ__Dimension__c> newDimensions = new List<SBQQ__Dimension__c>();

        // Get pricebook name for dimension naming
        String pbName = [SELECT Name FROM Pricebook2 WHERE Id = :pricebookId LIMIT 1].Name;

        for (Product2 p : products) {
            for (String curr : CURRENCIES) {
                String key = p.Id + '' + curr + '' + pricebookId;
                if (!existingDimensions.containsKey(key)) {
                    newDimensions.add(new SBQQ__Dimension__c(
                        SBQQ__Product__c   = p.Id,
                        Name               = pbName + ' Annual ' + curr,
                        SBQQ__Type__c      = 'Year',
                        SBQQ__PriceBook__c = pricebookId,
                        CurrencyIsoCode    = curr
                    ));
                }
            }
        }

        if (!newDimensions.isEmpty()) {
            Database.SaveResult[] dimResults = Database.insert(newDimensions, false);
            Integer dimErrors = 0;
            for (Database.SaveResult sr : dimResults) {
                if (!sr.isSuccess()) dimErrors++;
            }

            Nebula.Logger.info(
                'Dimension batch offset=' + offset + ': ' +
                (newDimensions.size() - dimErrors) + ' created, ' + dimErrors + ' errors'
            ).addTag('PricebookWizard').setRecordId(pricebookId);
        }

        Nebula.Logger.saveLog();

        // Chain next batch if we processed a full batch
        if (products.size() == BATCH_SIZE) {
            System.enqueueJob(
                new PricebookSetupQueueable(pricebookId, 'DIMENSIONS', offset + BATCH_SIZE)
            );
        }
        // Otherwise, all done - job completes naturally
    }
}