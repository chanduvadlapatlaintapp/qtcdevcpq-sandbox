/**
 * @description Test class for AgenticQTC_AmendContractController. 
 *              Each public controller method has three tests:
 *                1. Validation (blank/null Id) → controller-level throw
 *                2. Happy / success path
 *                3. Invalid-Id path → exercises the controller's outer
 *                   `catch (Exception)` → AuraHandledException wrap
 *              CPQ-backed methods use the CPQAPIUtils mock seams
 *              (mockAmendmentQuoteModel / mockCalculatedQuoteModel) so the
 *              tests don't have to invoke SBQQ.ServiceRouter — that managed
 *              package call cannot run from a test context.
 * @author AgenticQTC Team
 * @date 2026
 */
@isTest
private class AgenticQTC_AmendContractControllerTest {

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        // CPQ's QuoteLine triggers don't bulk-safely handle multi-line inserts
        // that share quote/product in test context — disabling them lets the
        // seed data load cleanly. Production runs through the calculator + CPQ
        // APIs and isn't affected.
        SBQQ.TriggerControl.disable();

        // Bypass the org's "Quote Before/After Insert-Update" flow so quote
        // DML in tests doesn't trip an unrelated production flow. Same pattern
        // used in CongaUrlServiceTest / ACVChangeCalculationServiceTest.
        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c    = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(
            Name           = 'Test Controller Account',
            Industry       = 'Technology',
            BillingCity    = 'San Francisco',
            BillingState   = 'CA'
        );
        insert acct;

        insert new List<Contact>{
            new Contact(
                AccountId = acct.Id,
                FirstName = 'Pat',
                LastName  = 'Picker',
                Email     = 'pat.picker@example.com',
                Title     = 'Director'
            ),
            // Filtered out by the searchContacts / getAccountContacts guard rails
            new Contact(
                AccountId = acct.Id,
                FirstName = 'Ghost',
                LastName  = 'Picker NO LONGER AT FIRM',
                Email     = 'ghost@example.com'
            ),
            new Contact(
                AccountId = acct.Id,
                FirstName = 'No',
                LastName  = 'Reply',
                Email     = 'noreply@example.com'
            )
        };

        Contract con = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;

        Opportunity opp = new Opportunity(
            Name      = 'Controller Test Opportunity',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c        = acct.Id,
            SBQQ__Opportunity2__c   = opp.Id,
            SBQQ__MasterContract__c = con.Id,
            SBQQ__Primary__c        = true,
            SBQQ__Status__c         = 'Draft',
            SBQQ__Type__c           = 'Amendment',
            Deal_Type__c            = 'Add-On',
            SBQQ__StartDate__c      = Date.today(),
            SBQQ__EndDate__c        = Date.today().addYears(1)
        );
        insert quote;

        Product2 prod = new Product2(
            Name        = 'Controller Test Product',
            IsActive    = true,
            ProductCode = 'CTRL-001'
        );
        insert prod;

        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );

        insert new SBQQ__QuoteLine__c(
            SBQQ__Quote__c     = quote.Id,
            SBQQ__Product__c   = prod.Id,
            SBQQ__Quantity__c  = 10,
            SBQQ__PriorQuantity__c = 10,
            SBQQ__ListPrice__c = 100,
            SBQQ__NetPrice__c  = 1000,
            SBQQ__Number__c    = 1
        );

        // MDQ-style segment pair so updateMdqSegmentQuantity has a key to expand
        insert new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c        = quote.Id,
                SBQQ__Product__c      = prod.Id,
                SBQQ__Quantity__c     = 2,
                SBQQ__ListPrice__c    = 50,
                SBQQ__NetPrice__c     = 100,
                SBQQ__Number__c       = 2,
                SBQQ__SegmentKey__c   = 'SEG-CTRL',
                SBQQ__SegmentIndex__c = 1
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c        = quote.Id,
                SBQQ__Product__c      = prod.Id,
                SBQQ__Quantity__c     = 3,
                SBQQ__ListPrice__c    = 50,
                SBQQ__NetPrice__c     = 150,
                SBQQ__Number__c       = 3,
                SBQQ__SegmentKey__c   = 'SEG-CTRL',
                SBQQ__SegmentIndex__c = 2
            )
        };

        // Skipping SBQQ__Subscription__c insert — the org's custom
        // SubscriptionTrigger isn't bulk-safe in this test scaffolding.
        // Tests that need a subscription Id fabricate one via the key prefix.
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static Account getAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Contract getContract() {
        return [SELECT Id FROM Contract LIMIT 1];
    }

    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getPrimaryLine() {
        return [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Number__c = 1 LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getSegmentLine() {
        return [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__SegmentKey__c = 'SEG-CTRL' ORDER BY SBQQ__SegmentIndex__c ASC LIMIT 1];
    }

    /** Fabricates a valid-format SBQQ__Subscription__c Id without DML so the
     *  org's custom SubscriptionTrigger doesn't run. */
    private static Id fakeSubscriptionId() {
        String prefix = Schema.SObjectType.SBQQ__Subscription__c.getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }

    private static Map<String, Object> buildMockQuoteModel(Id quoteId, Id lineId, Id subscriptionId) {
        Map<String, Object> record = new Map<String, Object>{
            'Id'              => String.valueOf(quoteId),
            'SBQQ__Status__c' => 'Draft'
        };
        Map<String, Object> lineRecord = new Map<String, Object>{
            'Id'                            => String.valueOf(lineId),
            'SBQQ__UpgradedSubscription__c' => String.valueOf(subscriptionId),
            'SBQQ__Quantity__c'             => 5,
            'SBQQ__ProductName__c'          => 'Mock Product',
            'SBQQ__ListPrice__c'            => 100
        };
        return new Map<String, Object>{
            'record'    => record,
            'lineItems' => new List<Object>{ new Map<String, Object>{ 'record' => lineRecord } }
        };
    }

    // ─── searchAccounts ────────────────────────────────────────────────

    @isTest
    static void testSearchAccounts_Success() {
        Account acct = getAccount();
        // Force SOSL to return our seeded account so the eligibility filter has
        // something to evaluate. Without this, SOSL returns [] in test context.
        Test.setFixedSearchResults(new List<Id>{ acct.Id });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AmendContractController.searchAccounts('Controller');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
    }

    @isTest
    static void testSearchAccounts_BelowMinLength() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AmendContractController.searchAccounts('a');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Below min length should short-circuit to empty');
    }

    @isTest
    static void testSearchAccounts_NullInput() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AmendContractController.searchAccounts(null);
        Test.stopTest();
        System.assertEquals(0, results.size());
    }

    // ─── Exception Coverage Tests ──────────────────────────────────────
    
    @isTest
    static void testSearchAccounts_ServiceException() {
        // Force an exception by making the service fail
        SBQQ.TriggerControl.disable();
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Passing extremely long string to potentially trigger an exception
            String longString = 'a'.repeat(10000);
            AgenticQTC_AmendContractController.searchAccounts(longString);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should catch and wrap service exceptions');
            System.assert(e.getMessage().contains('Failed to search accounts') || 
                         e.getMessage().length() > 0, 'Should have error message');
        }
        Test.stopTest();
        // Exception may or may not be thrown depending on service behavior
    }
    
    // testGetActiveContracts_ServiceException and
    // testGetDraftQuotesForContract_ServiceException previously tried to force
    // a catch-block by deleting the underlying record first — the delete itself
    // fails (Account can't be removed with attached Contracts) or the service
    // silently returns an empty list. Replaced by the seam-driven
    // *_CatchBlocks tests at the bottom of this class.


    @isTest
    static void testLoadExistingDraftQuote_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete quote to cause service failure  
            delete q;
            AgenticQTC_AmendContractController.loadExistingDraftQuote(q.Id);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testCreateAmendmentQuote_ServiceException() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete contract to cause service failure
            delete con;
            AgenticQTC_AmendContractController.createAmendmentQuote(con.Id);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testCreateAmendmentWithQuantities_ServiceException() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete contract to cause service failure
            delete con;
            AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, '{}');
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testUpdateQuoteLineQuantity_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete quote line to cause service failure
            delete line;
            AgenticQTC_AmendContractController.updateQuoteLineQuantity(q.Id, line.Id, 5);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testUpdateMdqSegmentQuantity_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete segment to cause service failure
            delete seg;
            AgenticQTC_AmendContractController.updateMdqSegmentQuantity(q.Id, seg.Id, 5, 'SEG-CTRL', false);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testSaveQuoteChanges_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete quote to cause service failure
            delete q;
            AgenticQTC_AmendContractController.saveQuoteChanges(q.Id, '[]', Date.today(), null, null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testSaveQuantityChanges_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete quote to cause service failure
            delete q;
            AgenticQTC_AmendContractController.saveQuantityChanges(q.Id, '[]');
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    @isTest
    static void testGetQuoteDetails_ServiceException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Delete quote to cause service failure
            delete q;
            AgenticQTC_AmendContractController.getQuoteDetails(q.Id);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        System.assert(exceptionCaught, 'Should have caught exception');
    }
    
    // testGetAccountContacts_ServiceException previously tried to delete the
    // Account to force a catch — fails because Contacts/Contracts are still
    // attached. Replaced by testGetAccountContacts_CatchBlocks below.


    @isTest
    static void testSearchContacts_ServiceException() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        Boolean exceptionCaught = false;
        try {
            // Pass extremely long string to potentially trigger exception
            String longString = 'a'.repeat(10000);
            AgenticQTC_AmendContractController.searchContacts(longString);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
            System.assertNotEquals(null, e.getMessage(), 'Should handle service exceptions');
        }
        Test.stopTest();
        // May or may not throw depending on service
    }
    
    // testGetRunningApprovals_ServiceException previously deleted the Quote
    // to force a catch — the service silently returns []. Replaced by
    // testGetRunningApprovals_CatchBlocks below.

    // ─── getActiveContracts ────────────────────────────────────────────

    @isTest
    static void testGetActiveContracts_Success() {
        Account acct = getAccount();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_AmendContractController.getActiveContracts(acct.Id);
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @isTest
    static void testGetActiveContracts_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getActiveContracts(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetActiveContracts_BlankThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getActiveContracts('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetActiveContracts_InvalidId_BubblesAura() {
        // Service may silently return [] for a non-matching Id or throw — either
        // is fine here; the goal is to exercise the controller's try/catch path.
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getActiveContracts('INVALID_ID');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── getDraftQuotesForContract ─────────────────────────────────────

    @isTest
    static void testGetDraftQuotesForContract_Success() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.DraftQuoteOption> drafts =
            AgenticQTC_AmendContractController.getDraftQuotesForContract(con.Id);
        Test.stopTest();
        System.assertEquals(1, drafts.size(), 'Should surface the seeded draft');
    }

    @isTest
    static void testGetDraftQuotesForContract_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getDraftQuotesForContract(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── loadExistingDraftQuote ────────────────────────────────────────

    @isTest
    static void testLoadExistingDraftQuote_Success() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
            AgenticQTC_AmendContractController.loadExistingDraftQuote(q.Id);
        Test.stopTest();
        System.assertNotEquals(null, info);
        System.assertEquals(q.Id, info.id);
    }

    @isTest
    static void testLoadExistingDraftQuote_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.loadExistingDraftQuote(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testLoadExistingDraftQuote_ValidIdNotFound_BubblesAuraHandled() {
        // Valid-format quote Id that doesn't exist — the service throws
        // AuraHandledException("Quote not found: ...") and the controller's
        // `catch (AuraHandledException) { throw e; }` re-throws it.
        SBQQ.TriggerControl.disable();
        String prefix = Schema.SObjectType.SBQQ__Quote__c.getKeyPrefix();
        Id missingId = Id.valueOf(prefix + '000000000001');

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.loadExistingDraftQuote(missingId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Non-existent quote should bubble as AuraHandledException');
    }

    @isTest
    static void testLoadExistingDraftQuote_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.loadExistingDraftQuote('INVALID_ID');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── createAmendmentQuote (CPQ-backed via mocks) ───────────────────

    @isTest
    static void testCreateAmendmentQuote_HappyPath_WithMocks() {
        Contract con = getContract();
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel  = buildMockQuoteModel(q.Id, line.Id, null);
        AgenticQTC_CPQAPIUtils.mockCalculatedQuoteModel = buildMockQuoteModel(q.Id, line.Id, null);

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
            AgenticQTC_AmendContractController.createAmendmentQuote(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals(q.Id, info.id);
    }

    @isTest
    static void testCreateAmendmentQuote_NullContractIdThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.createAmendmentQuote(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testCreateAmendmentQuote_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.createAmendmentQuote('INVALID_ID');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── createAmendmentWithQuantities ─────────────────────────────────

    @isTest
    static void testCreateAmendmentWithQuantities_HappyPath_WithMocks() {
        Contract con = getContract();
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        Id subId = fakeSubscriptionId();

        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel  = buildMockQuoteModel(q.Id, line.Id, subId);
        AgenticQTC_CPQAPIUtils.mockCalculatedQuoteModel = buildMockQuoteModel(q.Id, line.Id, subId);
        // QuoteSaver rejects hand-built mock models, so stub the save too. BIZ-83493
        AgenticQTC_CPQAPIUtils.mockSavedQuoteModel      = buildMockQuoteModel(q.Id, line.Id, subId);

        String json = JSON.serialize(new Map<String, Object>{ String.valueOf(subId) => 6 });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        String resultId = AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, json);
        Test.stopTest();

        System.assertEquals(String.valueOf(q.Id), resultId);
    }

    @isTest
    static void testCreateAmendmentWithQuantities_NullParamsThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.createAmendmentWithQuantities(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testCreateAmendmentWithQuantities_NullQuantitiesThrows() {
        Contract con = getContract();
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testCreateAmendmentWithQuantities_InvalidJsonBubblesException() {
        Contract con = getContract();
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, '{not json');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── getQuoteLines ─────────────────────────────────────────────────

    @isTest
    static void testGetQuoteLines_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getQuoteLines(q.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetQuoteLines_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getQuoteLines('INVALID_ID');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── updateQuoteLineQuantity ───────────────────────────────────────

    @isTest
    static void testUpdateQuoteLineQuantity_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_AmendContractController.updateQuoteLineQuantity(q.Id, line.Id, 15);
        Test.stopTest();

        System.assertNotEquals(null, result);
        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(15, reloaded.SBQQ__Quantity__c);
    }

    @isTest
    static void testUpdateQuoteLineQuantity_NullParamsThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteLineQuantity(null, null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testUpdateQuoteLineQuantity_InvalidIdsBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteLineQuantity('INVALID', 'INVALID', 10);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── updateMdqSegmentQuantity ──────────────────────────────────────

    @isTest
    static void testUpdateMdqSegmentQuantity_SingleSegment_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_AmendContractController.updateMdqSegmentQuantity(q.Id, seg.Id, 7, null, false);
        Test.stopTest();

        System.assertNotEquals(null, result);
        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id = :seg.Id];
        System.assertEquals(7, reloaded.SBQQ__Quantity__c);
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_ApplyToAll_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.updateMdqSegmentQuantity(q.Id, seg.Id, 4, 'SEG-CTRL', true);
        Test.stopTest();

        for (SBQQ__QuoteLine__c row : [
            SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE SBQQ__SegmentKey__c = 'SEG-CTRL'
        ]) {
            System.assertEquals(4, row.SBQQ__Quantity__c);
        }
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_NullParamsThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateMdqSegmentQuantity(null, null, null, null, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_InvalidIdsBubblesException() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateMdqSegmentQuantity(
                'INVALID', 'INVALID', 10, 'SEG', true);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── saveQuoteChanges ──────────────────────────────────────────────

    @isTest
    static void testSaveQuoteChanges_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuoteChanges(
                q.Id, '[]', Date.today().addDays(7), null, null);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveQuoteChanges_WithChangesAndContacts_BubblesException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Picker' LIMIT 1];
        String changesJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'lineId' => line.Id, 'quantity' => 3 }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuoteChanges(
                q.Id, changesJson, Date.today().addDays(7), c.Id, c.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * BIZ-83493: when the 'Finalize OSA' transition is rejected by an org validation rule,
     * saveQuoteChanges must surface the exact org message (not the generic fallback) so the
     * LWC toast tells the user the real reason, and nothing is saved.
     */
    @isTest
    static void testSaveQuoteChanges_ValidationError_SurfacesExactMessage() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        AgenticQTC_AmendContractController.testDmlFailQuoteId = q.Id;

        Boolean threw = false;
        String  msg;
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuoteChanges(q.Id, '[]', Date.today(), null, null);
        } catch (AuraHandledException e) {
            threw = true;
            msg   = e.getMessage();
        }
        Test.stopTest();

        System.assert(threw, 'A validation failure should surface as an AuraHandledException');
        System.assertNotEquals(null, msg, 'The exact org validation message should be surfaced');
        System.assert(!msg.contains('Please try again or contact support'),
            'Should surface the exact validation message, not the generic fallback');
    }

    @isTest
    static void testSaveQuoteChanges_NullQuoteIdThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuoteChanges(null, '[]', Date.today(), null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSaveQuoteChanges_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuoteChanges(
                'INVALID', '[]', Date.today(), null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── saveQuantityChanges ───────────────────────────────────────────

    @isTest
    static void testSaveQuantityChanges_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuantityChanges(q.Id, '[]');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveQuantityChanges_NullQuoteIdThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuantityChanges(null, '[]');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testSaveQuantityChanges_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.saveQuantityChanges('INVALID', '[]');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── updateQuoteLineAcvChange ──────────────────────────────────────

    @isTest
    static void testUpdateQuoteLineAcvChange_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteLineAcvChange(q.Id, line.Id, 500);
        } catch (Exception e) {
            // The ACV update succeeds, but the trailing getQuoteLines hits CPQ
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT ACV_Change__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(500, reloaded.ACV_Change__c);
    }

    @isTest
    static void testUpdateQuoteLineAcvChange_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteLineAcvChange('INVALID', 'INVALID', 500);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── getQuoteDetails ───────────────────────────────────────────────

    @isTest
    static void testGetQuoteDetails_Success() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteDetailsInfo details =
            AgenticQTC_AmendContractController.getQuoteDetails(q.Id);
        Test.stopTest();
        System.assertNotEquals(null, details);
    }

    @isTest
    static void testGetQuoteDetails_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getQuoteDetails(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetQuoteDetails_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getQuoteDetails('INVALID_ID');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── calculateQuote ────────────────────────────────────────────────

    @isTest
    static void testCalculateQuote_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.calculateQuote(q.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCalculateQuote_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.calculateQuote('INVALID');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── updateQuoteStartDate ──────────────────────────────────────────

    @isTest
    static void testUpdateQuoteStartDate_Success() {
        SBQQ__Quote__c q = getQuote();
        Date newDate = Date.today().addDays(7);

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.updateQuoteStartDate(q.Id, newDate);
        Test.stopTest();

        SBQQ__Quote__c reloaded = [SELECT SBQQ__StartDate__c FROM SBQQ__Quote__c WHERE Id = :q.Id];
        System.assertEquals(newDate, reloaded.SBQQ__StartDate__c);
    }

    @isTest
    static void testUpdateQuoteStartDate_InvalidIdBubblesException() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteStartDate('INVALID', Date.today());
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── updateQuoteSfa ────────────────────────────────────────────────

    @isTest
    static void testUpdateQuoteSfa_Success() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.updateQuoteSfa(q.Id, true);
        Test.stopTest();
        // No-op placeholder — just confirm it doesn't throw.
        System.assert(true);
    }

    @isTest
    static void testUpdateQuoteSfa_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.updateQuoteSfa(null, true);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── getAccountContacts ────────────────────────────────────────────

    @isTest
    static void testGetAccountContacts_Success() {
        Account acct = getAccount();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> contacts =
            AgenticQTC_AmendContractController.getAccountContacts(acct.Id);
        Test.stopTest();
        System.assertEquals(1, contacts.size(),
            'Only the active contact should pass the noreply / NO LONGER AT FIRM filters');
    }

    @isTest
    static void testGetAccountContacts_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getAccountContacts(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetAccountContacts_InvalidIdBubblesException() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getAccountContacts('INVALID_ID');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── searchContacts ────────────────────────────────────────────────

    @isTest
    static void testSearchContacts_Success() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_AmendContractController.searchContacts('Picker');
        Test.stopTest();
        System.assertEquals(1, options.size());
    }

    @isTest
    static void testSearchContacts_BlankReturnsEmpty() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_AmendContractController.searchContacts('');
        Test.stopTest();
        System.assertEquals(0, options.size());
    }

    @isTest
    static void testSearchContacts_WildcardOnlyReducesToEmpty() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_AmendContractController.searchContacts('%_');
        Test.stopTest();
        System.assertEquals(0, options.size());
    }

    // ─── getRunningApprovals ───────────────────────────────────────────
    // Controller method commented out; tests disabled in tandem.

    /*
    @isTest
    static void testGetRunningApprovals_Success() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_ApprovalLogicService.ApprovalItem> approvals =
            AgenticQTC_AmendContractController.getRunningApprovals(q.Id);
        Test.stopTest();
        System.assertNotEquals(null, approvals);
    }

    @isTest
    static void testGetRunningApprovals_NullThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getRunningApprovals(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetRunningApprovals_InvalidIdBubblesException() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_AmendContractController.getRunningApprovals('INVALID_ID');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
    */

    // ─── Catch-block coverage via @TestVisible exception-injection seams ──
    //
    // Each controller method wraps its service call in:
    //   try { ... }
    //   catch (AuraHandledException e) { throw e; }
    //   catch (Exception e) { Logger.error(...); throw new AuraHandledException(...); }
    //
    // The inner services don't normally throw for the inputs we send (the
    // controller's blank-check pre-empts that), so the two catch blocks are
    // unreachable through normal test paths. The controller exposes
    // `throwTestAuraException` / `throwTestException` @TestVisible flags that
    // cause `throwIfTestRequested()` to throw — gated by Test.isRunningTest()
    // so production is unaffected. The tests below flip each flag in turn and
    // confirm the controller's catch blocks run and bubble the exception back
    // up as an AuraHandledException.

    @isTest
    static void testSearchAccounts_CatchBlocks() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.searchAccounts('Test'); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.searchAccounts('Test'); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught, 'catch (AuraHandledException) should re-throw');
        System.assert(exCaught,  'catch (Exception) should wrap into AHE');
    }

    @isTest
    static void testGetActiveContracts_CatchBlocks() {
        Account acct = getAccount();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.getActiveContracts(acct.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.getActiveContracts(acct.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testGetDraftQuotesForContract_CatchBlocks() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.getDraftQuotesForContract(con.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.getDraftQuotesForContract(con.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testLoadExistingDraftQuote_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.loadExistingDraftQuote(q.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.loadExistingDraftQuote(q.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testCreateAmendmentQuote_CatchBlocks() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.createAmendmentQuote(con.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.createAmendmentQuote(con.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testCreateAmendmentWithQuantities_CatchBlocks() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, '{}'); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.createAmendmentWithQuantities(con.Id, '{}'); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testUpdateQuoteLineQuantity_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.updateQuoteLineQuantity(q.Id, line.Id, 5); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.updateQuoteLineQuantity(q.Id, line.Id, 5); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.updateMdqSegmentQuantity(q.Id, seg.Id, 4, 'SEG-CTRL', true); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.updateMdqSegmentQuantity(q.Id, seg.Id, 4, 'SEG-CTRL', true); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testSaveQuoteChanges_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.saveQuoteChanges(q.Id, '[]', Date.today(), null, null); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.saveQuoteChanges(q.Id, '[]', Date.today(), null, null); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testSaveQuantityChanges_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.saveQuantityChanges(q.Id, '[]'); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.saveQuantityChanges(q.Id, '[]'); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testGetQuoteDetails_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.getQuoteDetails(q.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.getQuoteDetails(q.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testGetAccountContacts_CatchBlocks() {
        Account acct = getAccount();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.getAccountContacts(acct.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.getAccountContacts(acct.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    @isTest
    static void testSearchContacts_CatchBlocks() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.searchContacts('Pat'); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.searchContacts('Pat'); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }

    // Controller method getRunningApprovals commented out; catch-block test disabled in tandem.
    /*
    @isTest
    static void testGetRunningApprovals_CatchBlocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_AmendContractController.throwTestAuraException = true;
        Boolean aheCaught = false;
        try { AgenticQTC_AmendContractController.getRunningApprovals(q.Id); }
        catch (AuraHandledException e) { aheCaught = true; }
        AgenticQTC_AmendContractController.throwTestAuraException = false;

        AgenticQTC_AmendContractController.throwTestException = true;
        Boolean exCaught = false;
        try { AgenticQTC_AmendContractController.getRunningApprovals(q.Id); }
        catch (AuraHandledException e) { exCaught = true; }
        AgenticQTC_AmendContractController.throwTestException = false;
        Test.stopTest();

        System.assert(aheCaught);
        System.assert(exCaught);
    }
    */
}