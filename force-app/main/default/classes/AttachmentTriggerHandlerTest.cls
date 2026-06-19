/**
 * @description Test class for AttachmentTriggerHandler
 * @date 2026-03-19
 * @jira BIZ-80922
 **/
@isTest
public class AttachmentTriggerHandlerTest {
    @testSetup
    static void setup() {
        // Create the Account
        Account account = IntappTestObjectfactory.createAccount(true);

        // Create Contact
        Contact con = (Contact) SmartFactory.createSObject('Contact');
        con.AccountId = account.Id; 
        insert con;

        // Create Contract
        Contract ctr = (Contract) SmartFactory.createSObject('Contract');
        ctr.AccountId = account.Id;
        insert ctr;

        // Create Opportunity
        Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
        opportunity.AccountId = account.Id;
        opportunity.Associated_Contract_OSA__c = ctr.Id;
        opportunity.Contract_Signer__c = con.Id;
        opportunity.Requested_Contract_Expiration__c = Date.today();
        opportunity.Initial_Software_Term_Length_Months__c = 12;
        insert opportunity;

        // Create Quote
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = System.today();
        insert newQuote;

        // Create RelatedContent record to simulate deletion
        SBQQ__RelatedContent__c relatedContent = new SBQQ__RelatedContent__c(
            Name = 'Test_bundle_related',
            SBQQ__Quote__c = newQuote.Id,
            SBQQ__ExternalId__c = '123456789012345678'
        );
        insert relatedContent;
    }

    @isTest 
    static void testAdditionalDocumentGeneration() {
        // Retrieve Quote
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];

        // Insert Attachments
        insertAttachment('Test data 1', '.pdf', quote.Id, 'Bundle_Test1.pdf');
        insertAttachment('Test data 2', '.pdf', quote.Id, 'Amendment_Test2.pdf');

        // Simulate RelatedContent linked to Attachments for validation
        List<SBQQ__RelatedContent__c> initialRelatedContent = [
            SELECT Id, Name, SBQQ__ExternalId__c, SBQQ__Quote__c
            FROM SBQQ__RelatedContent__c
        ];

        // Insert another attachment to simulate obsolete RelatedContent
        Attachment obsoleteAttachment = new Attachment(
            Name = 'Obsolete_bundle_document.pdf',
            ParentId = quote.Id,
            Body = Blob.valueOf('Obsolete content')
        );
        insert obsoleteAttachment;

        // Call the trigger handler
        Test.startTest();
        AttachmentTriggerHandler.attachmentAfterInsert(
            new Map<Id, Attachment>([SELECT Id, Name, ParentId FROM Attachment])
        );
        Test.stopTest();

        // Assertions
        // Validate that existing obsolete RelatedContent is deleted
        List<SBQQ__RelatedContent__c> relatedContentAfterDelete = [
            SELECT Id, Name, SBQQ__Quote__c
            FROM SBQQ__RelatedContent__c
            WHERE SBQQ__Quote__c = null
        ];
        System.assertEquals(0, relatedContentAfterDelete.size(), 'Obsolete RelatedContent records should be deleted.');

        // Validate that new RelatedContent is inserted
        List<SBQQ__RelatedContent__c> relatedContentAfterInsert = [
            SELECT Id, Name, SBQQ__ExternalId__c, SBQQ__Quote__c
            FROM SBQQ__RelatedContent__c
        ];
        System.assert(relatedContentAfterInsert.size() > initialRelatedContent.size(), 'New RelatedContent records should be created.');
    }

    private static void insertAttachment(String base64Data, String contentType, String recordId, String name) {
        Attachment attachment = new Attachment(
            ParentId = recordId,
            Body = EncodingUtil.base64Decode(EncodingUtil.urlDecode(base64Data, 'UTF-8')),
            Name = name,
            ContentType = contentType
        );
        insert attachment;
    }
}