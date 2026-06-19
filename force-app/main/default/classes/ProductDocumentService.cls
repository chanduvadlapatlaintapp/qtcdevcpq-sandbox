/**
 * @description Service class that links product-specific PDF documents to Quotes as Related Content.
 *              Uses Product_Document_Mapping__mdt custom metadata to map product codes (SKUs) to
 *              Salesforce File titles. When a quote contains matching products, the corresponding
 *              PDF is linked as SBQQ__RelatedContent__c so Conga includes it in the OSA bundle.
 * @author Sahal Mohamed
 * @date 2026-03-19
 * @jira BIZ-80922
 */
public without sharing class ProductDocumentService {

    // Allows test classes to inject mock mappings — Custom Metadata Types cannot be
    // inserted via DML in test context, so tests set this before calling the service.
    @TestVisible
    private static List<Product_Document_Mapping__mdt> testMappings;

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Convenience method — looks up product codes for the quote and calls
     *              linkProductDocuments. Called from QuoteTermValidator.generateQuoteTerms()
     *              so product documents are linked whenever quote terms are generated.
     *              On amendment quotes, only lines with a positive effective quantity are
     *              counted — i.e. net-new units being added on the amendment (new lines or
     *              quantity upsells). Carried-over contract lines that are unchanged have an
     *              effective quantity of 0 (reductions are negative) and must not trigger
     *              the attachment (BIZ-83059).
     * @param quoteId The ID of the Quote to link documents to
     */
    public static void linkProductDocumentsForQuote(Id quoteId) {
        if (quoteId == null) {
            return;
        }
        SBQQ__Quote__c quote = [
            SELECT Id, SBQQ__Type__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];
        Boolean isAmendment = quote.SBQQ__Type__c == QuoteConstants.TYPE_AMENDMENT;

        Set<String> productCodes = new Set<String>();
        for (SBQQ__QuoteLine__c ql : [
            SELECT SBQQ__ProductCode__c, SBQQ__EffectiveQuantity__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            AND SBQQ__ProductCode__c != null
        ]) {
            // On amendments, only count net-new units. A null/zero/negative effective
            // quantity means the line adds nothing new to the contract.
            if (isAmendment && !(ql.SBQQ__EffectiveQuantity__c > 0)) {
                continue;
            }
            productCodes.add(ql.SBQQ__ProductCode__c);
        }
        linkProductDocuments(quoteId, productCodes);
    }

    /**
     * @description Links product-specific documents to a quote based on the products present.
     *              Queries Product_Document_Mapping__mdt for active mappings matching the given
     *              product codes, finds the corresponding Salesforce Files (ContentVersion), and
     *              creates SBQQ__RelatedContent__c records to link them to the quote.
     *              Idempotent — skips documents already linked to the quote.
     * @param quoteId The ID of the Quote to link documents to
     * @param productCodes Set of product codes from the quote's line items
     */
    public static void linkProductDocuments(Id quoteId, Set<String> productCodes) {
        if (quoteId == null || productCodes == null || productCodes.isEmpty()) {
            return;
        }

        // Step 1: Find active document mappings for the products on this quote
        List<Product_Document_Mapping__mdt> mappings = getActiveMappings(productCodes);
        if (mappings.isEmpty()) {
            return;
        }

        // Step 1b: Drop mappings excluded for this quote's billing frequency. Some documents
        // (e.g. the Celeste OSA terms) must not attach to Trial quotes (BIZ-83181). The excluded
        // values are configured per mapping on Product_Document_Mapping__mdt.Excluded_Billing_Frequency__c.
        mappings = filterByBillingFrequency(quoteId, mappings);
        if (mappings.isEmpty()) {
            return;
        }

        // Step 2: Collect document titles to query ContentVersions
        Set<String> documentTitles = new Set<String>();
        for (Product_Document_Mapping__mdt mapping : mappings) {
            documentTitles.add(mapping.Document_Title__c);
        }

        // Step 3: Find the latest ContentVersion for each document title
        Map<String, ContentVersion> titleToContentVersion = getLatestContentVersions(documentTitles);
        if (titleToContentVersion.isEmpty()) {
            Nebula.Logger.warn('No ContentVersion files found for product document mappings: ' + documentTitles)
                .addTag('ProductDocumentService')
                .setRecordId(quoteId);
            Nebula.Logger.saveLog();
            return;
        }

        // Step 4: Check for existing Related Content to avoid duplicates
        Set<String> existingExternalIds = getExistingExternalIds(quoteId);

        // Step 5: Create SBQQ__RelatedContent__c records for new documents
        List<SBQQ__RelatedContent__c> relatedContentToInsert = new List<SBQQ__RelatedContent__c>();
        Set<String> queuedContentDocIds = new Set<String>();
        for (Product_Document_Mapping__mdt mapping : mappings) {
            ContentVersion cv = titleToContentVersion.get(mapping.Document_Title__c);
            if (cv == null) {
                continue;
            }

            // Skip if already linked (idempotency) or already queued in this batch
            // (multiple product codes may point to the same document — insert only once)
            if (existingExternalIds.contains(cv.ContentDocumentId) || queuedContentDocIds.contains(cv.ContentDocumentId)) {
                continue;
            }
            queuedContentDocIds.add(cv.ContentDocumentId);

            relatedContentToInsert.add(new SBQQ__RelatedContent__c(
                Name = cv.Title + '.' + cv.FileExtension,
                SBQQ__Quote__c = quoteId,
                SBQQ__ExternalId__c = cv.ContentDocumentId,
                SBQQ__Required__c = true,
                SBQQ__DisplayOrder__c = 2
            ));
        }

        // Step 6: Insert new Related Content records
        if (!relatedContentToInsert.isEmpty()) {
            insert relatedContentToInsert;
            Nebula.Logger.info('Linked ' + relatedContentToInsert.size() + ' product document(s) to Quote: ' + quoteId)
                .addTag('ProductDocumentService')
                .setRecordId(quoteId);
            Nebula.Logger.saveLog();
        }
    }

    /***********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Retrieves active Product_Document_Mapping__mdt records matching the given product codes.
     * @param productCodes Set of product codes to match
     * @return List of matching active mappings
     */
    private static List<Product_Document_Mapping__mdt> getActiveMappings(Set<String> productCodes) {
        if (Test.isRunningTest() && testMappings != null) {
            List<Product_Document_Mapping__mdt> filtered = new List<Product_Document_Mapping__mdt>();
            for (Product_Document_Mapping__mdt m : testMappings) {
                if (productCodes.contains(m.Product_Code__c)) {
                    filtered.add(m);
                }
            }
            return filtered;
        }
        return [
            SELECT Product_Code__c, Document_Title__c, Excluded_Billing_Frequency__c
            FROM Product_Document_Mapping__mdt
            WHERE Product_Code__c IN :productCodes
            AND Active__c = true
        ];
    }

    /**
     * @description Removes mappings that are excluded for the quote's billing frequency.
     *              A mapping with Excluded_Billing_Frequency__c containing the quote's
     *              SBQQ__BillingFrequency__c (e.g. "Trial") must not be linked (BIZ-83181).
     *              Mappings with a blank exclusion are always retained.
     * @param quoteId The Quote being evaluated
     * @param mappings The active mappings matched by product code
     * @return The subset of mappings applicable to this quote's billing frequency
     */
    private static List<Product_Document_Mapping__mdt> filterByBillingFrequency(
        Id quoteId,
        List<Product_Document_Mapping__mdt> mappings
    ) {
        String billingFrequency = getQuoteBillingFrequency(quoteId);
        if (String.isBlank(billingFrequency)) {
            return mappings;
        }

        List<Product_Document_Mapping__mdt> applicable = new List<Product_Document_Mapping__mdt>();
        for (Product_Document_Mapping__mdt mapping : mappings) {
            if (isExcludedForBillingFrequency(mapping, billingFrequency)) {
                Nebula.Logger.info('Skipping product document "' + mapping.Document_Title__c
                        + '" for billing frequency: ' + billingFrequency)
                    .addTag('ProductDocumentService')
                    .setRecordId(quoteId);
                continue;
            }
            applicable.add(mapping);
        }
        return applicable;
    }

    /**
     * @description Checks whether a mapping is excluded for the given billing frequency.
     *              Excluded_Billing_Frequency__c is a comma-separated list of values; the
     *              comparison is case-insensitive and tolerant of surrounding whitespace.
     * @param mapping The mapping to evaluate
     * @param billingFrequency The quote's billing frequency
     * @return true if the document must not be linked for this billing frequency
     */
    private static Boolean isExcludedForBillingFrequency(
        Product_Document_Mapping__mdt mapping,
        String billingFrequency
    ) {
        if (String.isBlank(mapping.Excluded_Billing_Frequency__c)) {
            return false;
        }
        for (String excluded : mapping.Excluded_Billing_Frequency__c.split(',')) {
            if (excluded.trim().equalsIgnoreCase(billingFrequency)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Retrieves the billing frequency for a quote.
     * @param quoteId The Quote ID
     * @return The quote's SBQQ__BillingFrequency__c, or null if not found
     */
    private static String getQuoteBillingFrequency(Id quoteId) {
        List<SBQQ__Quote__c> quotes = [
            SELECT SBQQ__BillingFrequency__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0].SBQQ__BillingFrequency__c;
    }

    /**
     * @description Finds the latest published ContentVersion for each document title.
     * @param documentTitles Set of document titles to search for
     * @return Map of document title to ContentVersion record
     */
    private static Map<String, ContentVersion> getLatestContentVersions(Set<String> documentTitles) {
        Map<String, ContentVersion> titleToContentVersion = new Map<String, ContentVersion>();

        for (ContentVersion cv : [
            SELECT Id, Title, ContentDocumentId, FileExtension
            FROM ContentVersion
            WHERE Title IN :documentTitles
            AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            // Keep only the first (most recent) match per title
            if (!titleToContentVersion.containsKey(cv.Title)) {
                titleToContentVersion.put(cv.Title, cv);
            }
        }

        return titleToContentVersion;
    }

    /**
     * @description Gets the set of SBQQ__ExternalId__c values already linked to this quote.
     *              Used for idempotency to avoid creating duplicate Related Content records.
     * @param quoteId The Quote ID to check
     * @return Set of existing external IDs
     */
    private static Set<String> getExistingExternalIds(Id quoteId) {
        Set<String> existingIds = new Set<String>();
        for (SBQQ__RelatedContent__c rc : [
            SELECT SBQQ__ExternalId__c
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quoteId
            AND SBQQ__ExternalId__c != null
        ]) {
            existingIds.add(rc.SBQQ__ExternalId__c);
        }
        return existingIds;
    }
}