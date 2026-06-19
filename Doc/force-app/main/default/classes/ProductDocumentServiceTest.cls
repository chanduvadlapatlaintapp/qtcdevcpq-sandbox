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
        List<Account> accList = TestDataFactory.createAccount(1, true);
        List<Opportunity> opportunityList = TestDataFactory.createOppty(1, accList[0].Id, true);

        List<SBQQ__Quote__c> quoteList = (List<SBQQ__Quote__c>) TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = accList.get(0).Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = opportunityList[0].Id
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
}