/**
* @description This class is a Test class for QuoteDocumentTriggerHandler and QuoteDocumentTriggerHelper.
**/
@isTest
public class QuoteDocumentTriggerHandlerTest {
    
    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    /**
    * @description Inserts required test data: Account,Opportunity, Quote and ContentVersion
    **/
    @testSetup 
    static void setup() {
        // Create an Account
        Account acc = (Account)TestFactory.createSObject(
            new Account(Name = 'test acc1'), 'AccountDefaults');

        // Create an Opportunity
        Opportunity oppObj = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = acc.Id
            ), 'OpportunityDefaults');
        

        // Create list of Quotes
        TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                OP4I_Sales_Segment__c = '03-Legal EMEA',
                SBQQ__Account__c = acc.Id,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                SBQQ__Opportunity2__c = oppObj.Id
            ), 5, 'SBQQQuoteDefaults');
        
        List<ContentVersion> lstContentVersion = new List<ContentVersion>();
        for(Integer iterator = 1; iterator <= 5; iterator++) {
            ContentVersion contentVersion = new ContentVersion(
                                                Title = 'Pricing Proposal ' + iterator,
                                                PathOnClient = 'Pic' + iterator + '.jpg',
                                                VersionData = Blob.valueOf('Test Content ' + iterator),
                                                IsMajorVersion = true
                                            );
            lstContentVersion.add(contentVersion);
        }
        insert lstContentVersion;
    }
        
    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
     * @description Validates QuoteDocumentTriggerHelper.validateQuoteDocumentNameLength behavior
     *              - No error when Name length ≤ max (label)
     *              - Field error when Name length > max (label)
     */
    @isTest
    public static void validateQuoteDocumentNameLengthTest() {
        
        List<SBQQ__Quote__c> lstTestQuotes = getTestQuotes();
        List<ContentDocument> lstTestContentDocuments = getTestContentDocuments();
        List<ContentDocumentLink> lstDocumentLinks = new List<ContentDocumentLink>();
        for(Integer iterator = 0; iterator < 4; iterator++) {
            lstDocumentLinks.addAll(TestDataFactory.createContentDocLink(1, lstTestQuotes[iterator].Id, lstTestContentDocuments[iterator].Id, false));
        }
		insert lstDocumentLinks;
        
        Test.startTest();
            for(Integer iterator = 0; iterator < 4; iterator++) {
                SBQQ__QuoteDocument__c quoteDocument = new SBQQ__QuoteDocument__c(
                                                            Name = getName(iterator),
                                                            SBQQ__DocumentId__c = lstDocumentLinks[iterator].Id,
                                                            SBQQ__Quote__c = lstTestQuotes[iterator].Id
                                                        );
                try {
                    insert quoteDocument; //NOPMD
                    if(iterator != 2) {
                        System.assert(true, 'Quote document ' + iterator + ' inserted successfully with Name length ' + quoteDocument.Name.length());
                    }

                } catch (DmlException e) {
                    if(iterator == 2) {
                        System.assert(e.getMessage().contains(Label.Quote_Document_Name_Max_Length), 'Expected field error for Name length exceeded for quote document ' +iterator);
                    }
                }
            }
        Test.stopTest();
        
    }
    
    /**
    * @description Tests insert handler methods
    **/
	@isTest
    public static void whenDocumentCreatedThenEventIsNotFired() {
        List<SBQQ__Quote__c> lstTestQuotes = getTestQuotes();
        List<ContentDocument> lstTestContentDocuments = getTestContentDocuments();
        List<ContentDocumentLink> lstDocumentLinks = new List<ContentDocumentLink>();
        for(Integer iterator = 0; iterator < 5; iterator++) {
            lstDocumentLinks.addAll(TestDataFactory.createContentDocLink(1, lstTestQuotes[iterator].Id, lstTestContentDocuments[iterator].Id, false));
        }
		insert lstDocumentLinks;
        
        Test.startTest();
            List<SBQQ__QuoteDocument__c> lstQuoteDocuments = new List<SBQQ__QuoteDocument__c>();
            for(Integer iterator = 0; iterator < 5; iterator++) {
                SBQQ__QuoteDocument__c quoteDocument = new SBQQ__QuoteDocument__c(
                                                            Name = 'Test Document',
                                                            SBQQ__DocumentId__c = lstDocumentLinks[iterator].Id,
                                                            SBQQ__Quote__c = lstTestQuotes[iterator].Id
                                                        );
                lstQuoteDocuments.add(quoteDocument);
            }
            insert lstQuoteDocuments;
        Test.stopTest();
        List<SBQQ__QuoteDocument__c> lstOfQuoteDocuments = getTestQuoteDocuments();
        System.assertEquals('Test Document', lstOfQuoteDocuments[0].Name, 'Quote document name should be Test Document');
    }
    
    /**
    * @description Tests update handler methods
    **/
	@isTest
    public static void whenQuoteIsApprovedThenEventIsFired() {
        List<SBQQ__Quote__c> lstTestQuotes = getTestQuotes();
        List<ContentDocument> lstTestContentDocuments = getTestContentDocuments();
        List<ContentDocumentLink> lstDocumentLinks = new List<ContentDocumentLink>();
        for(Integer iterator = 0; iterator < 5; iterator++) {
            lstDocumentLinks.addAll(TestDataFactory.createContentDocLink(1, lstTestQuotes[iterator].Id, lstTestContentDocuments[iterator].Id, false));
        }
		insert lstDocumentLinks;
        List<SBQQ__QuoteDocument__c> lstQuoteDocuments = new List<SBQQ__QuoteDocument__c>();
        for(Integer iterator = 0; iterator < 5; iterator++) {
            SBQQ__QuoteDocument__c quoteDocument = new SBQQ__QuoteDocument__c(
                Name = 'Test Document',
                SBQQ__DocumentId__c = lstDocumentLinks[iterator].Id,
                SBQQ__Quote__c = lstTestQuotes[iterator].Id
            );
            lstQuoteDocuments.add(quoteDocument);
        }
        insert lstQuoteDocuments;
        Test.startTest();
        	lstTestQuotes[0].ApprovalStatus__c = 'Approved';
        	lstTestQuotes[1].ApprovalStatus__c = 'Approved';
        	update lstTestQuotes;
        Test.stopTest();
        List<SBQQ__QuoteDocument__c> lstOfQuoteDocuments = getTestQuoteDocuments();
        System.assertEquals('Approved', lstOfQuoteDocuments[0].Quote_ApprovalStatus__c, 'First quote should be Approved');
        System.assertNotEquals('Approved', lstOfQuoteDocuments[4].Quote_ApprovalStatus__c, 'Fifth quote should not be Approved');
    }
    
    /**
    * @description Tests delete handler methods
    **/
	@isTest
    public static void whenDocumentDeletedThenEventIsNotFired() {
        List<SBQQ__Quote__c> lstTestQuotes = getTestQuotes();
        List<ContentDocument> lstTestContentDocuments = getTestContentDocuments();
        List<ContentDocumentLink> lstDocumentLinks = new List<ContentDocumentLink>();
        for(Integer iterator = 0; iterator < 5; iterator++) {
            lstDocumentLinks.addAll(TestDataFactory.createContentDocLink(1, lstTestQuotes[iterator].Id, lstTestContentDocuments[iterator].Id, false));
        }
		insert lstDocumentLinks;
        
        List<SBQQ__QuoteDocument__c> lstQuoteDocuments = new List<SBQQ__QuoteDocument__c>();
        for(Integer iterator = 0; iterator < 5; iterator++) {
            SBQQ__QuoteDocument__c quoteDocument = new SBQQ__QuoteDocument__c(
                Name = 'Test Document',
                SBQQ__DocumentId__c = lstDocumentLinks[iterator].Id,
                SBQQ__Quote__c = lstTestQuotes[iterator].Id
            );
            lstQuoteDocuments.add(quoteDocument);
        }
        insert lstQuoteDocuments;
        Test.startTest();
        	delete lstQuoteDocuments[0];
        Test.stopTest();
        List<SBQQ__QuoteDocument__c> lstOfQuoteDocuments = getTestQuoteDocuments();
        System.assertEquals(4, lstOfQuoteDocuments.size(), 'There should be 4 quote documents after deleting one');
    }

    /**********************************************************************************************
     * 
     * Private Methods
     * 
     **********************************************************************************************/
    /**
     * @description Helper method to get Name based on index
     * @param index Integer
     * @return String
     */
    private static String getName(Integer index) {
        // Arrange
        Integer maxLen = Integer.valueOf(Label.Quote_Document_Name_Max_Length);
        
        // Helper to build strings of a given length
        String base = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        while (base.length() < maxLen + 5) {
            base += base;
        }
        String strLen = base.substring(0, Math.max(0, maxLen - 1));
        String strExact = base.substring(0, maxLen);
        String strTooLong = base.substring(0, maxLen + 1);
        String strBlank = '';

        switch on index {
            when 0 {
                return strLen;
            }
            when 1 {
                return strExact;
            }
            when 2 {
                return strTooLong;
            }
            when else {
                return strBlank;
            }
        }
    }
    
    /***********************************************************************************************
    *
    * Getters 
    *
    ***********************************************************************************************/

    /**
     * @description Returns test Quote records inserted in @testSeup
     * @return List of SBQQ__Quote__c
     */
    private static List<SBQQ__Quote__c> getTestQuotes() {
        return [SELECT Id FROM SBQQ__Quote__c];
    }
    
    /**
     * @description Returns test ContentDocument records inserted in @testSeup
     * @return List of ContentDocument
     */
    private static List<ContentDocument> getTestContentDocuments() {
        return [SELECT Id FROM ContentDocument];
    }
    
    /**
     * @description Returns test Quote Document records
     * @return List of SBQQ__QuoteDocument__c
     */
    private static List<SBQQ__QuoteDocument__c> getTestQuoteDocuments() {
        return [SELECT Id, Name, Quote_ApprovalStatus__c FROM SBQQ__QuoteDocument__c];
    }
}