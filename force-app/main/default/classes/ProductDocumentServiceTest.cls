/**
 * @description Test class for ProductDocumentService.
 *              Verifies that product-specific PDF documents are correctly linked
 *              to quotes as SBQQ__RelatedContent__c records based on Product_Document_Mapping__mdt.
 * @author Sahal Mohamed
 * @date 2026-03-19
 * @jira BIZ-80922
 **/
@isTest
public class ProductDocumentServiceTest {

    @testSetup
    static void setup() {
        // Bypass triggers/flows during setup. The "Quote Before Insert" Flow otherwise
        // recomputes Subsidiary__c from the account address to a value that may not exist
        // in every org's restricted picklist (e.g. UAT), failing the insert (BIZ-83059).
        TestFactory.createSObject(
            new Automation_Controls__c(
                Bypass_Flows__c = true,
                Bypass_Triggers__c = true,
                Active__c = true,
                Address_ByPass__c = true,
                Quote_Bypass__c = true,
                SetupOwnerId = UserInfo.getUserId()
            )
        );

        List<Account> accList = TestDataFactory.createAccount(1, true);
        List<Opportunity> opportunityList = TestDataFactory.createOppty(1, accList[0].Id, true);

        List<SBQQ__Quote__c> quoteList = (List<SBQQ__Quote__c>) TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = accList.get(0).Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = opportunityList[0].Id,
                Subsidiary__c = getValidSubsidiary()
            ), 1, 'SBQQQuoteDefaults');

        // Create a ContentVersion (Salesforce File) to simulate the uploaded PDF
        ContentVersion cv = new ContentVersion(
            Title = 'DealCloud with Celeste Terms',
            PathOnClient = 'DealCloud with Celeste Terms.pdf',
            VersionData = Blob.valueOf('Test PDF Content'),
            IsMajorVersion = true
        );
        insert cv;
    }

    /**
     * @description Returns the first active Subsidiary__c picklist value available in this org.
     *              Avoids hardcoding a value that may not exist across all orgs (dev, UAT, prod).
     */
    private static String getValidSubsidiary() {
        // Returns a Subsidiary__c value that is genuinely insertable in the running org.
        // describe().getPicklistValues() cannot be trusted for this restricted picklist —
        // in some orgs it reports values as active that the platform rejects on insert
        // (stale global value set). We probe candidate values against the actual restricted
        // picklist via Schema validity, falling back to null (the "Quote Before Insert" Flow
        // that would otherwise populate it is bypassed in setup, and the field is not required).
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        for (Schema.PicklistEntry entry : SBQQ__Quote__c.Subsidiary__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && isInsertableSubsidiary(acc.Id, opp.Id, entry.getValue())) {
                return entry.getValue();
            }
        }
        return null;
    }

    /**
     * @description Verifies a Subsidiary__c value actually passes restricted-picklist
     *              validation by attempting an insert inside a rolled-back savepoint.
     *              Guards against stale value-set entries that describe still reports active.
     * @param accId Account for the probe quote
     * @param oppId Opportunity for the probe quote
     * @param value Candidate Subsidiary__c value
     * @return true if a record with this value inserts successfully
     */
    private static Boolean isInsertableSubsidiary(Id accId, Id oppId, String value) {
        Savepoint sp = Database.setSavepoint();
        try {
            insert new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = accId,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = oppId,
                Subsidiary__c = value
            );
            return true;
        } catch (Exception e) {
            return false;
        } finally {
            Database.rollback(sp);
        }
    }

    /**
     * @description Injects mock metadata mappings so tests are not dependent on
     *              Custom Metadata Type records being deployed in the org.
     *              DC-02010 and DC-02122 both map to the same document title.
     */
    private static void injectTestMappings() {
        ProductDocumentService.testMappings = new List<Product_Document_Mapping__mdt>{
            new Product_Document_Mapping__mdt(
                Product_Code__c = 'DC-02010',
                Document_Title__c = 'DealCloud with Celeste Terms'
            ),
            new Product_Document_Mapping__mdt(
                Product_Code__c = 'DC-02122',
                Document_Title__c = 'DealCloud with Celeste Terms'
            )
        };
    }

    @isTest
    static void testLinkProductDocuments_withMatchingProduct() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Set<String> productCodes = new Set<String>{ 'DC-02010' };

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocuments(quote.Id, productCodes);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id, Name, SBQQ__ExternalId__c, SBQQ__Quote__c
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(1, relatedContent.size(), 'Expected one Related Content record for DC-02010 PDF');
        System.assert(relatedContent[0].Name.contains('DealCloud with Celeste Terms'), 'Related Content name should contain the document title');
    }

    @isTest
    static void testLinkProductDocuments_noDuplicatesOnRegeneration() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Set<String> productCodes = new Set<String>{ 'DC-02010' };

        injectTestMappings();

        Test.startTest();
        // First call — should create the record
        ProductDocumentService.linkProductDocuments(quote.Id, productCodes);
        // Second call — should NOT create a duplicate
        ProductDocumentService.linkProductDocuments(quote.Id, productCodes);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(1, relatedContent.size(), 'Expected no duplicate Related Content records after regeneration');
    }

    @isTest
    static void testLinkProductDocuments_twoProductsSameDocument() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        // DC-02010 and DC-02122 both map to the same document title — only one record should be created
        Set<String> productCodes = new Set<String>{ 'DC-02010', 'DC-02122' };

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocuments(quote.Id, productCodes);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id, Name, SBQQ__ExternalId__c
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(
            1,
            relatedContent.size(),
            'Expected only one Related Content record when two products share the same document'
        );
    }

    @isTest
    static void testLinkProductDocuments_noMatchingProduct() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Set<String> productCodes = new Set<String>{ 'XX-99999' };

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocuments(quote.Id, productCodes);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(0, relatedContent.size(), 'Expected no Related Content for non-matching product');
    }

    @isTest
    static void testLinkProductDocuments_nullAndEmptyInputs() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        Test.startTest();
        // Null quote ID
        ProductDocumentService.linkProductDocuments(null, new Set<String>{ 'DC-02010' });
        // Null product codes
        ProductDocumentService.linkProductDocuments(quote.Id, null);
        // Empty product codes
        ProductDocumentService.linkProductDocuments(quote.Id, new Set<String>());
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(0, relatedContent.size(), 'Expected no Related Content for null/empty inputs');
    }

    /***********************************************************************************************
     *
     * linkProductDocumentsForQuote — amendment-aware product code resolution (BIZ-83059)
     *
     ***********************************************************************************************/

    /**
     * @description Creates a quote of the given CPQ type reusing the account/opportunity
     *              from test setup.
     * @param quoteType SBQQ__Type__c value (e.g. 'Quote', 'Amendment')
     * @return Inserted SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c createQuote(String quoteType) {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        return (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Type__c = quoteType,
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = acc.Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = opp.Id,
                Subsidiary__c = getValidSubsidiary()
            ), 'SBQQQuoteDefaults');
    }

    /**
     * @description Creates a Product2 with the given product code.
     *              SBQQ__ProductCode__c on the quote line is a formula on
     *              SBQQ__Product__r.ProductCode, so a real product is required.
     * @param productCode ProductCode to stamp on the product
     * @return Inserted Product2 record
     */
    private static Product2 createProduct(String productCode) {
        return (Product2) TestFactory.createSObject(
            new Product2(
                Name = productCode + ' Test Product',
                ProductCode = productCode
            ), 'ProductDefaults');
    }

    /**
     * @description Creates a quote line simulating a CPQ amendment line state.
     *              SBQQ__EffectiveQuantity__c is a formula — for standard pricing it
     *              resolves to Quantity for new lines, and Quantity - PriorQuantity for
     *              carried-over (Existing) lines — so the test drives it via the
     *              writeable source fields. CPQ managed triggers are disabled so the
     *              package does not recalculate or reject the bare line.
     * @param quoteId Parent quote
     * @param productId Product for the line (provides the product code)
     * @param isExisting SBQQ__Existing__c — true = carried over from the existing contract
     * @param quantity SBQQ__Quantity__c — total quantity on the line
     * @param priorQuantity SBQQ__PriorQuantity__c — quantity before the amendment
     * @return Inserted SBQQ__QuoteLine__c record
     */
    private static SBQQ__QuoteLine__c createQuoteLine(Id quoteId, Id productId, Boolean isExisting, Decimal quantity, Decimal priorQuantity) {
        SBQQ.TriggerControl.disable();
        try {
            return (SBQQ__QuoteLine__c) TestFactory.createSObject(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quoteId,
                    SBQQ__Product__c = productId,
                    SBQQ__Existing__c = isExisting,
                    SBQQ__Quantity__c = quantity,
                    SBQQ__PriorQuantity__c = priorQuantity,
                    SBQQ__UpgradedQuantity__c = 0
                ), 'SBQQQuoteLineDefaults');
        } finally {
            SBQQ.TriggerControl.enable();
        }
    }

    @isTest
    static void testAmendment_newProductAdded_docLinked() {
        SBQQ__Quote__c amendment = createQuote(QuoteConstants.TYPE_AMENDMENT);
        // Newly added mapped product on the amendment — effective quantity = 2
        Product2 product = createProduct('DC-02010');
        createQuoteLine(amendment.Id, product.Id, false, 2, 0);

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocumentsForQuote(amendment.Id);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :amendment.Id
        ];
        System.assertEquals(1, relatedContent.size(),
            'Expected the product document to be linked when an amendment adds a mapped product');
    }

    @isTest
    static void testAmendment_onlyCarriedOverProducts_noDocLinked() {
        SBQQ__Quote__c amendment = createQuote(QuoteConstants.TYPE_AMENDMENT);
        // Carried-over, unchanged contract line — effective quantity = 5 - 5 = 0
        Product2 product = createProduct('DC-02010');
        createQuoteLine(amendment.Id, product.Id, true, 5, 5);

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocumentsForQuote(amendment.Id);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :amendment.Id
        ];
        System.assertEquals(0, relatedContent.size(),
            'Expected no product document when an amendment only carries over existing products');
    }

    @isTest
    static void testAmendment_quantityUpsellOnExistingProduct_docLinked() {
        SBQQ__Quote__c amendment = createQuote(QuoteConstants.TYPE_AMENDMENT);
        // Existing contract line upsold from 5 to 8 — effective quantity = 8 - 5 = 3
        Product2 product = createProduct('DC-02010');
        createQuoteLine(amendment.Id, product.Id, true, 8, 5);

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocumentsForQuote(amendment.Id);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :amendment.Id
        ];
        System.assertEquals(1, relatedContent.size(),
            'Expected the product document to be linked when an amendment adds quantity to an existing mapped product');
    }

    @isTest
    static void testAmendment_quantityReduction_noDocLinked() {
        SBQQ__Quote__c amendment = createQuote(QuoteConstants.TYPE_AMENDMENT);
        // Existing contract line reduced from 5 to 3 — effective quantity resolves to 0
        Product2 product = createProduct('DC-02010');
        createQuoteLine(amendment.Id, product.Id, true, 3, 5);

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocumentsForQuote(amendment.Id);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :amendment.Id
        ];
        System.assertEquals(0, relatedContent.size(),
            'Expected no product document when an amendment reduces quantity of an existing product');
    }

    @isTest
    static void testNewBusinessQuote_allLinesCounted_docLinked() {
        SBQQ__Quote__c quote = createQuote(QuoteConstants.TYPE_QUOTE);
        // Non-amendment quotes must count every mapped line as before (regression guard)
        Product2 product = createProduct('DC-02010');
        createQuoteLine(quote.Id, product.Id, false, 1, 0);

        injectTestMappings();

        Test.startTest();
        ProductDocumentService.linkProductDocumentsForQuote(quote.Id);
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(1, relatedContent.size(),
            'Expected the product document to be linked on a new-business quote (existing behaviour unchanged)');
    }

    /***********************************************************************************************
     *
     * Billing-frequency exclusion — Celeste Trial quotes must not receive the OSA doc (BIZ-83181)
     *
     ***********************************************************************************************/

    /**
     * @description Creates a quote with the given billing frequency, reusing the
     *              account/opportunity from test setup.
     * @param billingFrequency SBQQ__BillingFrequency__c value to set
     * @return Inserted SBQQ__Quote__c record
     */
    private static SBQQ__Quote__c createQuoteWithBillingFrequency(String billingFrequency) {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        return (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = acc.Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = opp.Id,
                Subsidiary__c = getValidSubsidiary(),
                SBQQ__BillingFrequency__c = billingFrequency
            ), 'SBQQQuoteDefaults');
    }

    /**
     * @description Injects the Celeste mapping, which is excluded for Trial billing frequency.
     */
    private static void injectCelesteMapping() {
        ProductDocumentService.testMappings = new List<Product_Document_Mapping__mdt>{
            new Product_Document_Mapping__mdt(
                Product_Code__c = 'CE-02134',
                Document_Title__c = 'DealCloud with Celeste Terms',
                Excluded_Billing_Frequency__c = 'Trial'
            )
        };
    }

    @isTest
    static void testTrialBillingFrequency_celesteDocNotLinked() {
        SBQQ__Quote__c quote = createQuoteWithBillingFrequency('Trial');
        injectCelesteMapping();

        Test.startTest();
        ProductDocumentService.linkProductDocuments(quote.Id, new Set<String>{ 'CE-02134' });
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(0, relatedContent.size(),
            'Celeste OSA document must NOT be linked to a Trial quote (BIZ-83181 AC #2)');
    }

    @isTest
    static void testNonTrialBillingFrequency_celesteDocLinked() {
        SBQQ__Quote__c quote = createQuoteWithBillingFrequency('Annual');
        injectCelesteMapping();

        Test.startTest();
        ProductDocumentService.linkProductDocuments(quote.Id, new Set<String>{ 'CE-02134' });
        Test.stopTest();

        List<SBQQ__RelatedContent__c> relatedContent = [
            SELECT Id FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c = :quote.Id
        ];
        System.assertEquals(1, relatedContent.size(),
            'Celeste OSA document must be linked to a non-Trial quote (BIZ-83181 AC #1)');
    }
}