/********************************************************************************
*  Name             :  ContentFilesTriggerHandlerTest
*  Author           :  Ratan Paul
*  Description      :  Test class for ContentFilesTriggerHandler and
*                      ContentFilesTriggerHelper. Covers block-delete logic on
*                      Contract Executed quotes (BIZ-81572) plus the no-op
*                      handler methods for coverage.
*  Change history   :
*  Date             Author              Description
*  06/05/26         Ratan Paul          Initial version via BIZ-81572
********************************************************************************/
@isTest
private class ContentFilesTriggerHandlerTest {

    private static final String NON_EXECUTED_STAGE = 'Configure Products';

    /***********************************************************************************************
     *
     * Test Setup
     *
     ***********************************************************************************************/
    @testSetup
    static void setupTestData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account acc = (Account) TestFactory.createSObject(
                new Account(
                    Name = 'CDL Test Account',
                    BillingCountry = 'United States',
                    BillingStreet = '1 Test Way',
                    BillingCity = 'Testville',
                    BillingState = 'CA',
                    BillingPostalCode = '94000'
                ),
                'AccountDefaults'
            );

            Opportunity opp = (Opportunity) TestFactory.createSObject(
                new Opportunity(
                    Name = 'CDL Test Opp',
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addMonths(1),
                    AccountId = acc.Id
                ),
                'OpportunityDefaults'
            );

            SBQQ.TriggerControl.disable();
            try {
                // Deal_Type__c = 'Other' bypasses both OSA_and_Approval_Validation and
                // Quote_Stage_Validation, which otherwise block inserting a Quote in the
                // Contract Executed stage without a full set of OSA / billing fields.
                TestFactory.createSObject(
                    new SBQQ__Quote__c(
                        SBQQ__Opportunity2__c = opp.Id,
                        SBQQ__Account__c = acc.Id,
                        Quote_Stage__c = QuoteConstants.STATUS_CONTRACT_EXECUTED,
                        Deal_Type__c = 'Other'
                    ),
                    'SBQQQuoteDefaults'
                );

                TestFactory.createSObject(
                    new SBQQ__Quote__c(
                        SBQQ__Opportunity2__c = opp.Id,
                        SBQQ__Account__c = acc.Id,
                        Quote_Stage__c = NON_EXECUTED_STAGE,
                        Deal_Type__c = 'Other'
                    ),
                    'SBQQQuoteDefaults'
                );
            } finally {
                SBQQ.TriggerControl.enable();
            }
        }
    }

    /***********************************************************************************************
     *
     * Tests
     *
     ***********************************************************************************************/

    /**
     * @description Deletion of a file linked to a Contract Executed quote is blocked.
     */
    @isTest
    static void testBlockDeleteOnContractExecutedQuote() {
        SBQQ__Quote__c executedQuote = getQuoteByStage(QuoteConstants.STATUS_CONTRACT_EXECUTED);
        ContentDocumentLink cdl = createFileAndLink(executedQuote.Id, 'ExecutedFile');

        Test.startTest();
        Database.DeleteResult result = Database.delete(cdl, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Delete should be blocked for Contract Executed quote');
        Assert.areEqual(
            'Files cannot be deleted from a Contract Executed quote.',
            result.getErrors()[0].getMessage(),
            'Expected block error message'
        );
    }

    /**
     * @description Deletion of a file linked to a non-Contract-Executed quote is permitted.
     */
    @isTest
    static void testAllowDeleteOnNonExecutedQuote() {
        SBQQ__Quote__c openQuote = getQuoteByStage(NON_EXECUTED_STAGE);
        ContentDocumentLink cdl = createFileAndLink(openQuote.Id, 'OpenFile');

        Test.startTest();
        Database.DeleteResult result = Database.delete(cdl, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Delete should be allowed for non-Contract-Executed quote');
    }

    /**
     * @description Deletion of a file linked to a non-Quote entity (Account) is unaffected — the
     *              helper returns early because no quote LinkedEntityIds are present.
     */
    @isTest
    static void testDeleteOnNonQuoteEntityIsAllowed() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'CDL Test Account' LIMIT 1];
        ContentDocumentLink cdl = createFileAndLink(acc.Id, 'AccountFile');

        Test.startTest();
        Database.DeleteResult result = Database.delete(cdl, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'Delete should be allowed when CDL is not linked to a Quote');
    }

    /**
     * @description Directly invokes the helper with an empty list to cover the early-return path.
     *              Also exercises the no-op handler methods through TriggerDispatcher routing.
     */
    @isTest
    static void testHelperEarlyReturnAndHandlerNoOps() {
        Test.startTest();
        // Empty list — early return path
        ContentFilesTriggerHelper.blockDeleteOnContractExecutedQuotes(new List<ContentDocumentLink>());

        // Exercise no-op handler methods directly for coverage
        ContentFilesTriggerHandler handler = new ContentFilesTriggerHandler();
        handler.beforeInsert(new List<SObject>());
        handler.beforeUpdate(new List<SObject>(), new Map<Id, Object>(), new List<Object>(), new Map<Id, Object>());
        handler.afterInsert(new List<SObject>(), new Map<Id, Object>());
        handler.afterUpdate(new List<SObject>(), new Map<Id, Object>(), new List<Object>(), new Map<Id, Object>());
        handler.afterDelete(new List<Object>(), new Map<Id, Object>());
        handler.afterUnDelete(new List<SObject>(), new Map<Id, Object>());
        Test.stopTest();
    }

    /***********************************************************************************************
     *
     * Helpers
     *
     ***********************************************************************************************/

    /**
     * @description Creates a ContentVersion file and links it to the given entity. Returns the
     *              created ContentDocumentLink (re-queried so all fields are populated).
     */
    private static ContentDocumentLink createFileAndLink(Id linkedEntityId, String titleSuffix) {
        ContentVersion cv = new ContentVersion(
            Title = 'CDLTest_' + titleSuffix,
            PathOnClient = 'CDLTest_' + titleSuffix + '.txt',
            VersionData = Blob.valueOf('test content'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V'
        );
        insert link;

        return [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE Id = :link.Id];
    }

    /**
     * @description Returns a Quote by stage.
     */
    private static SBQQ__Quote__c getQuoteByStage(String stage) {
        return [SELECT Id, Quote_Stage__c FROM SBQQ__Quote__c WHERE Quote_Stage__c = :stage LIMIT 1];
    }
}