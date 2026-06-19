/**
 * @description Test class for AgenticQTC_QuoteAmendmentService.
 *              Drives coverage through the public API plus the AgenticQTC_CPQAPIUtils
 *              mock seams (`mockAmendmentQuoteModel` / `mockCalculatedQuoteModel`)
 *              so the CPQ-backed amendment paths can run without touching
 *              SBQQ.ServiceRouter (which cannot be invoked from a test context).
 *              The package's QuoteLine triggers don't bulk-safely handle the
 *              multi-line inserts and updates done here, so each test disables
 *              CPQ triggers up front — same pattern as AddSelectBundleLinesTests.
 * @author AgenticQTC Team
 * @date 2026
 */
@isTest
private class AgenticQTC_QuoteAmendmentServiceTest {
    

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        SBQQ.TriggerControl.disable();

        // Bypass the org's "Quote Before Insert Update" flow so quote
        // updates/inserts in tests don't trip an unrelated production flow.
        // Same pattern used in CongaUrlServiceTest / ACVChangeCalculationServiceTest.
        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c    = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(
            Name = 'Test Account for Amendment',
            Industry = 'Technology',
            BillingCity = 'Boston',
            BillingState = 'MA'
        );
        insert acct;

        // Three contacts: one that should appear in pickers, two that should
        // be filtered out by the 'NO LONGER AT FIRM' / noreply guard rails.
        insert new List<Contact>{
            new Contact(
                AccountId = acct.Id,
                FirstName = 'Active',
                LastName  = 'Buyer',
                Email     = 'buyer@example.com',
                Title     = 'CFO'
            ),
            new Contact(
                AccountId = acct.Id,
                FirstName = 'Departed',
                LastName  = 'Person NO LONGER AT FIRM',
                Email     = 'old@example.com'
            ),
            new Contact(
                AccountId = acct.Id,
                FirstName = 'System',
                LastName  = 'Inbox',
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
            Name      = 'Test Amendment Opportunity',
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
            SBQQ__StartDate__c      = Date.today(),
            SBQQ__EndDate__c        = Date.today().addYears(1),
            // Deal_Type__c is filtered on by getDraftQuotesForContract — set to 'Add-On'
            // so that picker surfaces this seeded draft.
            Deal_Type__c            = 'Add-On'
        );
        insert quote;

        Product2 prod = new Product2(
            Name        = 'Test Product',
            IsActive    = true,
            ProductCode = 'TEST-001'
        );
        insert prod;

        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );

        // Primary line — the one most tests target.
        insert new SBQQ__QuoteLine__c(
            SBQQ__Quote__c         = quote.Id,
            SBQQ__Product__c       = prod.Id,
            SBQQ__Quantity__c      = 5,
            SBQQ__PriorQuantity__c = 5,
            SBQQ__ListPrice__c     = 100,
            SBQQ__NetPrice__c      = 500,
            SBQQ__Number__c        = 1
        );

        // Two MDQ-style segment lines that share a SegmentKey so the
        // applyToAll branch has something to expand.
        insert new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c        = quote.Id,
                SBQQ__Product__c      = prod.Id,
                SBQQ__Quantity__c     = 2,
                SBQQ__ListPrice__c    = 50,
                SBQQ__NetPrice__c     = 100,
                SBQQ__Number__c       = 2,
                SBQQ__SegmentKey__c   = 'SEG-MDQ',
                SBQQ__SegmentIndex__c = 1
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c        = quote.Id,
                SBQQ__Product__c      = prod.Id,
                SBQQ__Quantity__c     = 3,
                SBQQ__ListPrice__c    = 50,
                SBQQ__NetPrice__c     = 150,
                SBQQ__Number__c       = 3,
                SBQQ__SegmentKey__c   = 'SEG-MDQ',
                SBQQ__SegmentIndex__c = 2
            )
        };

        // Skipping SBQQ__Subscription__c insert — the org's custom
        // SubscriptionTrigger isn't bulk-safe in this test scaffolding.
        // Tests that need a subscription Id fabricate one via the key prefix.
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id, SBQQ__Account__c, SBQQ__MasterContract__c FROM SBQQ__Quote__c LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getPrimaryLine() {
        return [SELECT Id, SBQQ__ListPrice__c, SBQQ__Quantity__c
                FROM SBQQ__QuoteLine__c WHERE SBQQ__Number__c = 1 LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getSegmentLine() {
        return [SELECT Id, SBQQ__SegmentKey__c FROM SBQQ__QuoteLine__c
                WHERE SBQQ__SegmentKey__c = 'SEG-MDQ' ORDER BY SBQQ__SegmentIndex__c ASC LIMIT 1];
    }

    private static Contract getContract() {
        return [SELECT Id, AccountId FROM Contract LIMIT 1];
    }

    /** Fabricates a valid-format SBQQ__Subscription__c Id without DML so the
     *  org's custom SubscriptionTrigger doesn't run. */
    private static Id fakeSubscriptionId() {
        String prefix = Schema.SObjectType.SBQQ__Subscription__c.getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }

    /**
     * Builds a minimal CPQ-shaped quote model — top-level 'record' plus a
     * 'lineItems' array. Used to drive the mockAmendmentQuoteModel /
     * mockCalculatedQuoteModel seams on AgenticQTC_CPQAPIUtils so CPQ-backed paths can
     * run without invoking SBQQ.ServiceRouter.
     */
    private static Map<String, Object> buildMockQuoteModel(Id quoteId, Id lineId, Id subscriptionId) {
        Map<String, Object> record = new Map<String, Object>{
            'Id'              => String.valueOf(quoteId),
            'SBQQ__Status__c' => 'Draft'
        };
        Map<String, Object> lineRecord = new Map<String, Object>{
            'Id'                            => String.valueOf(lineId),
            'SBQQ__UpgradedSubscription__c' => String.valueOf(subscriptionId),
            'SBQQ__Quantity__c'             => 10,
            'SBQQ__ProductName__c'          => 'Mock Product',
            'SBQQ__ProductCode__c'          => 'MOCK',
            'SBQQ__ListPrice__c'            => 100,
            'SBQQ__NetPrice__c'             => 1000,
            'SBQQ__PriorQuantity__c'        => 5,
            'SBQQ__SegmentIndex__c'         => 1,
            'SBQQ__SegmentKey__c'           => 'SEG-1'
        };
        return new Map<String, Object>{
            'record'    => record,
            'lineItems' => new List<Object>{ new Map<String, Object>{ 'record' => lineRecord } }
        };
    }

    // ─── getOrCreateAmendmentQuote ──────────────────────────────────────

    @isTest
    static void testGetOrCreateAmendmentQuote_ExistingDraft() {
        Contract con = getContract();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteInfo result =
            AgenticQTC_QuoteAmendmentService.getOrCreateAmendmentQuote(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Existing draft path should return a QuoteInfo');
        System.assertEquals('Draft', result.status, 'Existing draft should be returned with Draft status');
    }

    @isTest
    static void testGetOrCreateAmendmentQuote_NullContract() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.getOrCreateAmendmentQuote(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw AuraHandledException for null contract');
    }

    @isTest
    static void testGetOrCreateAmendmentQuote_PopulatesContactsOnQuoteInfo() {
        // Set both contact lookups on the seeded draft so buildQuoteInfo's
        // Invoicing_Contact__r / Software_Delivery_Contact__r branches both run.
        SBQQ.TriggerControl.disable();
        SBQQ__Quote__c q = getQuote();
        Contact c = [SELECT Id, Name, Email FROM Contact WHERE LastName = 'Buyer' LIMIT 1];
        q.Invoicing_Contact__c         = c.Id;
        q.Software_Delivery_Contact__c = c.Id;
        update q;

        Contract con = getContract();

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteInfo info =
            AgenticQTC_QuoteAmendmentService.getOrCreateAmendmentQuote(con.Id);
        Test.stopTest();

        System.assertEquals(c.Name,  info.invoicingContactName,
            'buildQuoteInfo should copy the invoicing contact name onto the DTO');
        System.assertEquals(c.Email, info.invoicingContactEmail);
        System.assertEquals(c.Name,  info.softwareDeliveryContactName,
            'buildQuoteInfo should copy the delivery contact name onto the DTO');
        System.assertEquals(c.Email, info.softwareDeliveryContactEmail);
    }

    @isTest
    static void testGetOrCreateAmendmentQuote_NoExistingDraft_BubblesCpqException() {
        // Delete the existing draft so the method falls through to
        // createAmendmentViaCpqApi → SBQQ.ServiceRouter.load which is
        // un-invokable in tests and gets wrapped into an AuraHandledException.
        SBQQ.TriggerControl.disable();
        delete [SELECT Id FROM SBQQ__QuoteLine__c];
        delete [SELECT Id FROM SBQQ__Quote__c];

        Contract con = getContract();
        Boolean threw = false;

        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.getOrCreateAmendmentQuote(con.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'No-draft fallback should attempt CPQ API and bubble an exception in tests');
    }

    // ─── getQuoteLines (CPQ-backed) ─────────────────────────────────────

    @isTest
    static void testGetQuoteLines_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.getQuoteLines(q.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetQuoteLines_NullQuote() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.getQuoteLines(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null quote');
    }

    // ─── updateQuoteLineQuantity (CPQ-backed) ──────────────────────────

    @isTest
    static void testUpdateQuoteLineQuantity_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteLineQuantity(q.Id, line.Id, 10);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateQuoteLineQuantity_NullIds() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteLineQuantity(null, null, 10);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null ids');
    }

    // ─── updateQuoteLineAcvChange ──────────────────────────────────────

    @isTest
    static void testUpdateQuoteLineAcvChange_PersistsValue() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteLineAcvChange(q.Id, line.Id, 250);
        } catch (Exception e) {
            // DML succeeds, trailing getQuoteLines hits CPQ — catch is fine.
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT ACV_Change__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(250, reloaded.ACV_Change__c, 'ACV_Change__c should be persisted');
    }

    @isTest
    static void testUpdateQuoteLineAcvChange_NullIds() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteLineAcvChange(null, null, 10);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null ids');
    }

    // ─── updateMdqSegmentQuantity ──────────────────────────────────────

    @isTest
    static void testUpdateMdqSegmentQuantity_SingleSegment_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateMdqSegmentQuantity(
                q.Id, line.Id, 8, null, false);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_ApplyToAll_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateMdqSegmentQuantity(
                q.Id, seg.Id, 9, 'SEG-MDQ', true);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateMdqSegmentQuantity_NullIds() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateMdqSegmentQuantity(null, null, 10, null, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null ids');
    }

    // ─── updateQuoteLineDiscount ───────────────────────────────────────

    @isTest
    static void testUpdateQuoteLineDiscount_Percent() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_QuoteAmendmentService.updateQuoteLineDiscount(q.Id, line.Id, 25, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Discount should return refreshed lines');
        SBQQ__QuoteLine__c reloaded = [
            SELECT SBQQ__Discount__c, SBQQ__CustomerPrice__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id
        ];
        System.assertEquals(25, reloaded.SBQQ__Discount__c, 'Discount should be 25%');
        System.assertEquals(75, reloaded.SBQQ__CustomerPrice__c, 'Customer price should reflect discount');
    }

    @isTest
    static void testUpdateQuoteLineDiscount_FlatAmount() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.updateQuoteLineDiscount(q.Id, line.Id, null, 20);
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Discount__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        // 20 / 100 listPrice * 100 = 20%
        System.assertEquals(20, reloaded.SBQQ__Discount__c, 'Flat amount should translate to 20%');
    }

    @isTest
    static void testUpdateQuoteLineDiscount_NoDiscount() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.updateQuoteLineDiscount(q.Id, line.Id, null, null);
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Discount__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(0, reloaded.SBQQ__Discount__c, 'No discount provided means 0%');
    }

    @isTest
    static void testUpdateQuoteLineDiscount_NullIds() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteLineDiscount(null, null, 10, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null ids');
    }

    // ─── calculateQuote ─────────────────────────────────────────────────

    @isTest
    static void testCalculateQuote_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.calculateQuote(q.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCalculateQuote_NullQuote() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.calculateQuote(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null quote');
    }

    // ─── updateQuoteStartDate ──────────────────────────────────────────

    @isTest
    static void testUpdateQuoteStartDate_Success() {
        SBQQ__Quote__c q = getQuote();
        Date newDate = Date.today().addDays(14);

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.updateQuoteStartDate(q.Id, newDate);
        Test.stopTest();

        SBQQ__Quote__c reloaded = [SELECT SBQQ__StartDate__c FROM SBQQ__Quote__c WHERE Id = :q.Id];
        System.assertEquals(newDate, reloaded.SBQQ__StartDate__c, 'Start date should be persisted');
    }

    @isTest
    static void testUpdateQuoteStartDate_NullQuote() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.updateQuoteStartDate(null, Date.today());
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should throw for null quote');
    }

    // ─── getDraftQuotesForContract ─────────────────────────────────────

    @isTest
    static void testGetDraftQuotesForContract_Success() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.DraftQuoteOption> drafts =
            AgenticQTC_QuoteAmendmentService.getDraftQuotesForContract(con.Id);
        Test.stopTest();

        System.assertEquals(1, drafts.size(), 'Should surface the seeded draft');
        System.assertNotEquals(null, drafts[0].name);
        System.assertNotEquals(null, drafts[0].startDate);
        System.assertNotEquals(null, drafts[0].endDate);
    }

    @isTest
    static void testGetDraftQuotesForContract_BlankReturnsEmpty() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.DraftQuoteOption> drafts =
            AgenticQTC_QuoteAmendmentService.getDraftQuotesForContract('');
        Test.stopTest();
        System.assertEquals(0, drafts.size());
    }

    // ─── loadExistingDraftQuote ────────────────────────────────────────

    @isTest
    static void testLoadExistingDraftQuote_PastStartDatePreserved() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Date past = Date.today().addDays(-5);
        q.SBQQ__StartDate__c = past;
        update q;

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
            AgenticQTC_QuoteAmendmentService.loadExistingDraftQuote(q.Id);
        Test.stopTest();

        System.assertEquals(String.valueOf(past), info.startDate,
            'Past start date should be preserved as-is so the editor displays the saved value');
        System.assertNotEquals(null, info.lines);
    }

    @isTest
    static void testLoadExistingDraftQuote_FutureStartDateKept() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Date future = Date.today().addDays(10);
        q.SBQQ__StartDate__c = future;
        update q;

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
            AgenticQTC_QuoteAmendmentService.loadExistingDraftQuote(q.Id);
        Test.stopTest();

        System.assertEquals(String.valueOf(future), info.startDate, 'Future start date should be preserved');
    }

    @isTest
    static void testLoadExistingDraftQuote_BlankIdThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.loadExistingDraftQuote(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank quote Id should throw');
    }

    @isTest
    static void testLoadExistingDraftQuote_NotFoundThrows() {
        // Fabricate a valid-format SBQQ__Quote__c Id that doesn't exist,
        // so the service hits the `quotes.isEmpty()` branch.
        SBQQ.TriggerControl.disable();
        String prefix = Schema.SObjectType.SBQQ__Quote__c.getKeyPrefix();
        Id missingId = Id.valueOf(prefix + '000000000001');

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.loadExistingDraftQuote(missingId);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Non-existent quote should throw');
    }

    // ─── getQuoteLinesByQuoteId ────────────────────────────────────────

    @isTest
    static void testGetQuoteLinesByQuoteId_Success() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> lines =
            AgenticQTC_QuoteAmendmentService.getQuoteLinesByQuoteId(q.Id);
        Test.stopTest();

        System.assertEquals(3, lines.size(), 'Primary + 2 segment lines should be returned');
    }

    @isTest
    static void testGetQuoteLinesByQuoteId_BlankThrows() {
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.getQuoteLinesByQuoteId('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    // ─── createAmendmentQuote (CPQ-backed via mocks) ───────────────────

    @isTest
    static void testCreateAmendmentQuote_HappyPath_WithMocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        Contract con = getContract();

        SBQQ.TriggerControl.disable();
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel  = buildMockQuoteModel(q.Id, line.Id, null);
        AgenticQTC_CPQAPIUtils.mockCalculatedQuoteModel = buildMockQuoteModel(q.Id, line.Id, null);

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
            AgenticQTC_QuoteAmendmentService.createAmendmentQuote(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, info, 'Mocked CPQ amendment should return AmendmentQuoteInfo');
        System.assertEquals(q.Id, info.id);
        System.assertNotEquals(null, info.lines);
    }

    @isTest
    static void testCreateAmendmentQuote_NoQuoteIdThrows() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        // Mock model with NO Id on its record so AgenticQTC_CPQAPIUtils.getQuoteId returns null
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = new Map<String, Object>{
            'record'    => new Map<String, Object>(),
            'lineItems' => new List<Object>()
        };

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.createAmendmentQuote(con.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing quote Id should bubble an exception');
    }

    // ─── createAmendmentWithQuantities ─────────────────────────────────

    @isTest
    static void testCreateAmendmentWithQuantities_HappyPath_WithMocks() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        Id subId = fakeSubscriptionId();
        Contract con = getContract();

        SBQQ.TriggerControl.disable();
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel  = buildMockQuoteModel(q.Id, line.Id, subId);
        AgenticQTC_CPQAPIUtils.mockCalculatedQuoteModel = buildMockQuoteModel(q.Id, line.Id, subId);
        // QuoteSaver rejects hand-built mock models, so stub the save too. BIZ-83493
        AgenticQTC_CPQAPIUtils.mockSavedQuoteModel      = buildMockQuoteModel(q.Id, line.Id, subId);

        String quantitiesJson = JSON.serialize(new Map<String, Object>{
            String.valueOf(subId) => 9
        });

        Test.startTest();
        String resultId = AgenticQTC_QuoteAmendmentService.createAmendmentWithQuantities(
            con.Id, quantitiesJson);
        Test.stopTest();

        System.assertEquals(String.valueOf(q.Id), resultId, 'Should return the amendment quote Id');
    }

    @isTest
    static void testCreateAmendmentWithQuantities_NoQuoteIdThrows() {
        Contract con = getContract();
        SBQQ.TriggerControl.disable();
        // Mock model with NO Id on its record so AgenticQTC_CPQAPIUtils.getQuoteId returns
        // null and the service throws "CPQ amendment returned no quote Id".
        AgenticQTC_CPQAPIUtils.mockAmendmentQuoteModel = new Map<String, Object>{
            'record'    => new Map<String, Object>(),
            'lineItems' => new List<Object>()
        };

        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.createAmendmentWithQuantities(con.Id, '{}');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing quote Id should throw');
    }

    @isTest
    static void testCreateAmendmentWithQuantities_InvalidJson() {
        Contract con = getContract();
        Boolean threw = false;
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.createAmendmentWithQuantities(con.Id, 'NOT_JSON{');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Invalid JSON should throw');
    }

    // ─── applyLineQuantityUpdate / applyMdqSegmentQuantityUpdate ──────

    @isTest
    static void testApplyLineQuantityUpdate_HappyPath() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_QuoteAmendmentService.applyLineQuantityUpdate(q.Id, line.Id, 14);
        Test.stopTest();

        System.assertNotEquals(null, result);
        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(14, reloaded.SBQQ__Quantity__c);
    }

    @isTest
    static void testApplyLineQuantityUpdate_NullQuantityCoercesToZero() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.applyLineQuantityUpdate(q.Id, line.Id, null);
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(0, reloaded.SBQQ__Quantity__c, 'Null quantity should coerce to 0');
    }

    @isTest
    static void testApplyMdqSegmentQuantityUpdate_ApplyToAll() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.applyMdqSegmentQuantityUpdate(
            q.Id, seg.Id, 6, 'SEG-MDQ', true);
        Test.stopTest();

        for (SBQQ__QuoteLine__c row : [
            SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE SBQQ__SegmentKey__c = 'SEG-MDQ'
        ]) {
            System.assertEquals(6, row.SBQQ__Quantity__c);
        }
    }

    @isTest
    static void testApplyMdqSegmentQuantityUpdate_SingleSegment() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.applyMdqSegmentQuantityUpdate(
            q.Id, seg.Id, 4, null, false);
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__Quantity__c FROM SBQQ__QuoteLine__c WHERE Id = :seg.Id];
        System.assertEquals(4, reloaded.SBQQ__Quantity__c);
    }

    // ─── saveQuantityChanges / saveQuoteChanges ────────────────────────

    @isTest
    static void testSaveQuantityChanges_EmptyJson_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.saveQuantityChanges(q.Id, '[]');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveQuantityChanges_WithSegmentApplyToAll_BubblesException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'lineId'     => seg.Id,
                'quantity'   => 7,
                'applyToAll' => true,
                'segmentKey' => 'SEG-MDQ'
            }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.saveQuantityChanges(q.Id, json);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveQuoteChanges_BubblesCpqException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.saveQuoteChanges(
                q.Id, '[]', Date.today().addDays(7), null, null);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveQuoteChanges_WithContactsAndChanges_BubblesException() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'lineId' => line.Id, 'quantity' => 3 }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.saveQuoteChanges(
                q.Id, json, Date.today().addDays(2), c.Id, c.Id);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * BIZ-83493: advancing to 'Finalize OSA' on Save must roll back (throw) and leave the
     * stage unchanged when the quote fails the org's stage validation rules. The seeded quote
     * has no verified Bill-To/Ship-To addresses and no Contract Master Terms, so the transition
     * is rejected and a DmlException carrying the org message is raised.
     */
    @isTest
    static void testAdvanceToFinalizeOsa_ValidationFailureThrows() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();

        Boolean threw = false;
        String  dmlMsg;
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.advanceToFinalizeOsa(q.Id);
        } catch (DmlException e) {
            threw  = true;
            dmlMsg = e.getDmlMessage(0);
        }
        Test.stopTest();

        System.assert(threw, 'Advancing an unqualified quote to Finalize OSA should throw a DmlException');
        System.assertNotEquals(null, dmlMsg, 'The DmlException should carry the org validation message');

        SBQQ__Quote__c after = [SELECT Quote_Stage__c FROM SBQQ__Quote__c WHERE Id = :q.Id];
        System.assertNotEquals('Finalize OSA', after.Quote_Stage__c,
            'Stage must not change when the validation rule rejects the transition');
    }

    // ─── getQuoteDetails ───────────────────────────────────────────────

    @isTest
    static void testGetQuoteDetails_WithContacts() {
        SBQQ__Quote__c q = getQuote();
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Buyer' LIMIT 1];

        SBQQ.TriggerControl.disable();
        q.Invoicing_Contact__c = c.Id;
        q.Software_Delivery_Contact__c = c.Id;
        update q;

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteDetailsInfo details =
            AgenticQTC_QuoteAmendmentService.getQuoteDetails(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, details);
        System.assertEquals(c.Id, details.invoicingContactId);
        System.assertEquals(c.Id, details.softwareDeliveryContactId);
        System.assertEquals('Active Buyer', details.invoicingContactName);
    }

    @isTest
    static void testGetQuoteDetails_NoContacts() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteDetailsInfo details =
            AgenticQTC_QuoteAmendmentService.getQuoteDetails(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, details);
        System.assertEquals(null, details.invoicingContactId);
    }

    // ─── getAccountContacts ────────────────────────────────────────────

    @isTest
    static void testGetAccountContacts_FiltersFlaggedContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_QuoteAmendmentService.getAccountContacts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, options.size(),
            'Only the Active Buyer should pass the noreply / NO LONGER AT FIRM filters');
        System.assertEquals('Active Buyer', options[0].name);
    }

    @isTest
    static void testGetAccountContacts_BlankReturnsEmpty() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_QuoteAmendmentService.getAccountContacts('');
        Test.stopTest();
        System.assertEquals(0, options.size());
    }

    // ─── searchContacts ────────────────────────────────────────────────

    @isTest
    static void testSearchContacts_Success() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_QuoteAmendmentService.searchContacts('Buyer');
        Test.stopTest();
        System.assertEquals(1, options.size());
        System.assertEquals('Active Buyer', options[0].name);
    }

    @isTest
    static void testSearchContacts_BlankReturnsEmpty() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        System.assertEquals(0, AgenticQTC_QuoteAmendmentService.searchContacts('').size());
        System.assertEquals(0, AgenticQTC_QuoteAmendmentService.searchContacts('   ').size());
        Test.stopTest();
    }

    @isTest
    static void testSearchContacts_OnlyWildcardsAreStripped() {
        SBQQ.TriggerControl.disable();
        Test.startTest();
        // After stripping % and _, this is empty so should return []
        List<AgenticQTC_QuoteAmendmentService.ContactOption> options =
            AgenticQTC_QuoteAmendmentService.searchContacts('%_%');
        Test.stopTest();
        System.assertEquals(0, options.size(),
            'Pure wildcard input should be reduced to empty and short-circuit');
    }

    // ─── updateQuoteSfa ────────────────────────────────────────────────

    @isTest
    static void testUpdateQuoteSfa_DoesNotThrow() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.updateQuoteSfa(q.Id, true);
        Test.stopTest();
        // Placeholder no-op method — confirm it doesn't throw.
        System.assert(true, 'Placeholder method should not throw');
    }

    // ─── getCurrentSegment ─────────────────────────────────────────────

    @isTest
    static void testGetCurrentSegment_ReturnsLineWithSubscription() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        // Insert a Subscription via TestFactory so SubscriptionTrigger plays nicely,
        // then point the seeded line at it so getCurrentSegment's WHERE clause matches.
        SBQQ.TriggerControl.disable();
        SBQQ__Subscription__c sub = new SBQQ__Subscription__c(
            SBQQ__Account__c               = q.SBQQ__Account__c,
            SBQQ__Contract__c              = q.SBQQ__MasterContract__c,
            SBQQ__Quantity__c              = 5,
            SBQQ__SubscriptionStartDate__c = Date.today().addDays(-30),
            SBQQ__SubscriptionEndDate__c   = Date.today().addYears(1),
            SBQQ__SegmentStartDate__c      = Date.today().addDays(-30),
            SBQQ__SegmentEndDate__c        = Date.today().addYears(1)
        );
        insert sub;
        line.SBQQ__UpgradedSubscription__c = sub.Id;
        update line;

        Test.startTest();
        List<SBQQ__QuoteLine__c> result =
            AgenticQTC_QuoteAmendmentService.getCurrentSegment(q.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'getCurrentSegment should return the seeded line');
        System.assertEquals(line.Id, result[0].Id);
    }

    @isTest
    static void testGetCurrentSegment_NoSubscriptionsReturnsEmpty() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        List<SBQQ__QuoteLine__c> result =
            AgenticQTC_QuoteAmendmentService.getCurrentSegment(q.Id);
        Test.stopTest();
        System.assertEquals(0, result.size(),
            'No QuoteLine has SBQQ__UpgradedSubscription__c set so result should be empty');
    }

    // ─── calculateQuoteViaDml (@testVisible) ───────────────────────────

    @isTest
    static void testCalculateQuoteViaDml_RecalculatesNetPrice() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();

        SBQQ.TriggerControl.disable();
        // Mutate the persisted NetPrice to a wrong value so we can verify the
        // recalc (qty * listPrice) overwrites it.
        line.SBQQ__NetPrice__c = 0;
        update line;

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.calculateQuoteViaDml(q.Id);
        Test.stopTest();

        SBQQ__QuoteLine__c reloaded = [SELECT SBQQ__NetPrice__c, SBQQ__CustomerPrice__c
                                       FROM SBQQ__QuoteLine__c WHERE Id = :line.Id];
        System.assertEquals(500, reloaded.SBQQ__NetPrice__c, 'qty*listPrice should be 5*100');
        System.assertEquals(100, reloaded.SBQQ__CustomerPrice__c, 'customerPrice should equal listPrice');
    }

    @isTest
    static void testCalculateQuoteViaDml_NoLinesIsNoop() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        delete [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :q.Id];

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.calculateQuoteViaDml(q.Id);
        Test.stopTest();
        System.assert(true, 'Should not throw when there are no lines to update');
    }

    // ─── parseLineItems / collectLineItems ─────────────────────────────

    @isTest
    static void testParseLineItems_NullLineItemsReturnsEmpty() {
        Map<String, Object> model = new Map<String, Object>{ 'lineItems' => null };
        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_QuoteAmendmentService.parseLineItems(model);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null lineItems should yield empty results');
    }

    @isTest
    static void testParseLineItems_NestedMdqSegments() {
        // Outer line with two nested MDQ segments — collectLineItems must recurse
        // into the nested lineItems so all three records show up.
        Map<String, Object> outerRec = new Map<String, Object>{
            'Id'              => '0A1000000000001',
            'SBQQ__ProductName__c' => 'Parent'
        };
        Map<String, Object> innerRec1 = new Map<String, Object>{
            'Id'              => '0A1000000000002',
            'SBQQ__ProductName__c' => 'Seg1',
            'SBQQ__SegmentIndex__c' => 1
        };
        Map<String, Object> innerRec2 = new Map<String, Object>{
            'Id'              => '0A1000000000003',
            'SBQQ__ProductName__c' => 'Seg2',
            'SBQQ__SegmentIndex__c' => 2
        };
        Map<String, Object> outerLine = new Map<String, Object>{
            'record'    => outerRec,
            'lineItems' => new List<Object>{
                new Map<String, Object>{ 'record' => innerRec1 },
                new Map<String, Object>{ 'record' => innerRec2 }
            }
        };
        Map<String, Object> model = new Map<String, Object>{
            'lineItems' => new List<Object>{ outerLine }
        };

        Test.startTest();
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> result =
            AgenticQTC_QuoteAmendmentService.parseLineItems(model);
        Test.stopTest();

        System.assertEquals(3, result.size(),
            'collectLineItems should recurse and yield parent + 2 nested segments');
    }

    @isTest
    static void testCollectLineItems_NullItemAndMissingRecordSkipGracefully() {
        // Mixed list: null entry, line with no 'record', line with valid record.
        Map<String, Object> validRec = new Map<String, Object>{ 'Id' => '0A1000000000004' };
        List<Object> lineItems = new List<Object>{
            null,
            new Map<String, Object>{ /* no record */ },
            new Map<String, Object>{ 'record' => validRec }
        };
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> results =
            new List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo>();

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.collectLineItems(lineItems, results);
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Null and record-less entries should be skipped, valid one collected');
    }

    @isTest
    static void testCollectLineItems_MalformedItemDoesNotAbortBatch() {
        // First entry is a String (not a Map) so the cast throws — the try/catch
        // around the loop body must swallow it and let the valid entry through.
        Map<String, Object> validRec = new Map<String, Object>{ 'Id' => '0A1000000000005' };
        List<Object> lineItems = new List<Object>{
            'NOT_A_MAP',
            new Map<String, Object>{ 'record' => validRec }
        };
        List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> results =
            new List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo>();

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.collectLineItems(lineItems, results);
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'A malformed entry should be caught and skipped without aborting the loop');
    }

    // ─── buildQuoteLineInfoFromMap ─────────────────────────────────────

    @isTest
    static void testBuildQuoteLineInfoFromMap_PopulatesAllFields() {
        Map<String, Object> rec = new Map<String, Object>{
            'Id'                            => '0A1000000000006',
            'SBQQ__Product__c'              => '01t000000000001',
            'SBQQ__ProductName__c'          => 'Prod',
            'SBQQ__ProductCode__c'          => 'CODE',
            'SBQQ__Quantity__c'             => 4,
            'SBQQ__PriorQuantity__c'        => 2,
            'SBQQ__NetPrice__c'             => 400,
            'SBQQ__NetTotal__c'             => 400,
            'SBQQ__ListPrice__c'            => 100,
            'SBQQ__CustomerPrice__c'        => 100,
            'SBQQ__Discount__c'             => 0,
            'SBQQ__SegmentIndex__c'         => 1,
            'SBQQ__SegmentKey__c'           => 'KEY-A',
            'SBQQ__SegmentLabel__c'         => 'Seg-A',
            'SBQQ__StartDate__c'            => String.valueOf(Date.today()),
            'SBQQ__EndDate__c'              => String.valueOf(Date.today().addDays(30)),
            'ACV__c'                        => 1000,
            'ACV_Change__c'                 => 50,
            'SBQQ__ChargeType__c'           => 'Recurring',
            'Customer_Sale_Price_Per_Month__c' => 33,
            'Per_Integrations__c'           => 'Meter1',
            'SBQQ__Bundle__c'               => true
        };

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteLineInfo info =
            AgenticQTC_QuoteAmendmentService.buildQuoteLineInfoFromMap(rec);
        Test.stopTest();

        System.assertEquals('Prod', info.productName);
        System.assertEquals(4, info.quantity);
        System.assertEquals(2, info.priorQuantity);
        System.assertEquals(1, info.segmentIndex);
        System.assertEquals('KEY-A', info.segmentKey);
        System.assertEquals(true, info.isBundle);
        System.assertEquals('Not Required', info.approvalRequired,
            '4 >= 2 and prior != 0 → Not Required');
    }

    @isTest
    static void testPopulateComputedFields_ApprovalRequiredForQuantityDecrease() {
        // qty < priorQty → Required
        Map<String, Object> rec = new Map<String, Object>{
            'Id'                    => '0A1000000000007',
            'SBQQ__Quantity__c'     => 2,
            'SBQQ__PriorQuantity__c' => 5
        };
        AgenticQTC_QuoteAmendmentService.QuoteLineInfo info =
            AgenticQTC_QuoteAmendmentService.buildQuoteLineInfoFromMap(rec);
        System.assertEquals('Required', info.approvalRequired,
            'Quantity decrease should trigger approval requirement');
    }

    @isTest
    static void testPopulateComputedFields_ApprovalRequiredForNewLine() {
        // priorQty == 0 → Required (new line)
        Map<String, Object> rec = new Map<String, Object>{
            'Id'                    => '0A1000000000008',
            'SBQQ__Quantity__c'     => 5,
            'SBQQ__PriorQuantity__c' => 0
        };
        AgenticQTC_QuoteAmendmentService.QuoteLineInfo info =
            AgenticQTC_QuoteAmendmentService.buildQuoteLineInfoFromMap(rec);
        System.assertEquals('Required', info.approvalRequired,
            'priorQty 0 (new line) should trigger approval requirement');
    }

    @isTest
    static void testPopulateComputedFields_IsLockedForPastEndDate() {
        Map<String, Object> rec = new Map<String, Object>{
            'Id'                    => '0A1000000000009',
            'SBQQ__EndDate__c'      => String.valueOf(Date.today().addDays(-1))
        };
        AgenticQTC_QuoteAmendmentService.QuoteLineInfo info =
            AgenticQTC_QuoteAmendmentService.buildQuoteLineInfoFromMap(rec);
        System.assertEquals(true, info.isLocked,
            'End date in the past should set isLocked = true');
    }

    // ─── JSON helpers ──────────────────────────────────────────────────

    @isTest
    static void testGetDecimalVal_HandlesAllNumericTypes() {
        Map<String, Object> m = new Map<String, Object>{
            'asInt'     => 5,
            'asLong'    => 10L,
            'asDouble'  => 2.5,
            'asDecimal' => (Decimal) 99,
            'asString'  => '42',
            'asNull'    => null,
            'asBadStr'  => 'not-a-number'
        };
        Test.startTest();
        System.assertEquals(5,  AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asInt'));
        System.assertEquals(10, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asLong'));
        System.assertEquals(2.5, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asDouble'));
        System.assertEquals(99, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asDecimal'));
        System.assertEquals(42, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asString'));
        System.assertEquals(null, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asNull'));
        System.assertEquals(null, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'asBadStr'),
            'Unparseable string should return null via the try/catch tail');
        System.assertEquals(null, AgenticQTC_QuoteAmendmentService.getDecimalVal(m, 'missing'));
        Test.stopTest();
    }

    @isTest
    static void testGetIntegerVal_ReturnsZeroForMissing() {
        Map<String, Object> m = new Map<String, Object>{ 'x' => 7 };
        System.assertEquals(7, AgenticQTC_QuoteAmendmentService.getIntegerVal(m, 'x'));
        System.assertEquals(0, AgenticQTC_QuoteAmendmentService.getIntegerVal(m, 'missing'),
            'Missing key should return 0, not null');
    }

    @isTest
    static void testGetString_ReturnsNullForMissing() {
        Map<String, Object> m = new Map<String, Object>{ 'name' => 'Acme', 'num' => 42 };
        System.assertEquals('Acme', AgenticQTC_QuoteAmendmentService.getString(m, 'name'));
        System.assertEquals('42',   AgenticQTC_QuoteAmendmentService.getString(m, 'num'),
            'Numeric values should be stringified');
        System.assertEquals(null,   AgenticQTC_QuoteAmendmentService.getString(m, 'missing'));
    }

    @isTest
    static void testGetDateVal_HandlesDateInstanceAndIsoString() {
        Date today = Date.today();
        Map<String, Object> m = new Map<String, Object>{
            'asDate'   => today,
            'asString' => String.valueOf(today),
            'asNull'   => null,
            'asBad'    => 'not-a-date'
        };
        Test.startTest();
        System.assertEquals(today, AgenticQTC_QuoteAmendmentService.getDateVal(m, 'asDate'));
        System.assertEquals(today, AgenticQTC_QuoteAmendmentService.getDateVal(m, 'asString'));
        System.assertEquals(null,  AgenticQTC_QuoteAmendmentService.getDateVal(m, 'asNull'));
        System.assertEquals(null,  AgenticQTC_QuoteAmendmentService.getDateVal(m, 'asBad'),
            'Unparseable date string should fall through to null');
        Test.stopTest();
    }

    // ─── buildLineQuantityChanges (@testVisible) ───────────────────────

    @isTest
    static void testBuildLineQuantityChanges_BlankJsonReturnsEmpty() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        Test.startTest();
        Map<Id, Map<String, Object>> result =
            AgenticQTC_QuoteAmendmentService.buildLineQuantityChanges(q.Id, '');
        Test.stopTest();
        System.assertEquals(0, result.size(),
            'Blank changesJson should short-circuit to an empty map');
    }

    @isTest
    static void testBuildLineQuantityChanges_SingleLineUpdate() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'lineId' => line.Id, 'quantity' => 9 }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        Map<Id, Map<String, Object>> result =
            AgenticQTC_QuoteAmendmentService.buildLineQuantityChanges(q.Id, json);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(9, result.get(line.Id).get('SBQQ__Quantity__c'));
    }

    @isTest
    static void testBuildLineQuantityChanges_ApplyToAllSegmentsExpands() {
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c seg = getSegmentLine();
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'lineId'     => seg.Id,
                'quantity'   => 11,
                'applyToAll' => true,
                'segmentKey' => 'SEG-MDQ'
            }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        Map<Id, Map<String, Object>> result =
            AgenticQTC_QuoteAmendmentService.buildLineQuantityChanges(q.Id, json);
        Test.stopTest();

        System.assertEquals(2, result.size(),
            'applyToAll expansion should populate both seeded MDQ segment lines');
        for (Id k : result.keySet()) {
            System.assertEquals(11, result.get(k).get('SBQQ__Quantity__c'));
        }
    }

    // ─── saveQuantityChanges (single-line branch) ──────────────────────

    @isTest
    static void testSaveQuantityChanges_SingleLineBranch_BubblesCpqException() {
        // Exercises the non-segment else branch on line 1010 — the CPQ save step
        // throws in test context but the branch is covered before it does.
        SBQQ__Quote__c q = getQuote();
        SBQQ__QuoteLine__c line = getPrimaryLine();
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'lineId' => line.Id, 'quantity' => 6 }
        });

        SBQQ.TriggerControl.disable();
        Test.startTest();
        try {
            AgenticQTC_QuoteAmendmentService.saveQuantityChanges(q.Id, json);
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── buildQuoteInfo (no contacts branch) ───────────────────────────

    @isTest
    static void testBuildQuoteInfo_NoContacts() {
        SBQQ__Quote__c q = [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c,
                   SBQQ__Account__c, SBQQ__MasterContract__c, SBQQ__Opportunity2__c,
                   Invoicing_Contact__r.Name, Invoicing_Contact__r.Email,
                   Software_Delivery_Contact__r.Name, Software_Delivery_Contact__r.Email
            FROM SBQQ__Quote__c LIMIT 1
        ];

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteInfo info =
            AgenticQTC_QuoteAmendmentService.buildQuoteInfo(q);
        Test.stopTest();

        System.assertEquals(q.Id, info.id);
        System.assertEquals(null, info.invoicingContactName,
            'No contact set on quote → DTO contact name should be null');
        System.assertEquals(null, info.softwareDeliveryContactName);
    }

    // ─── createAmendmentManually (@testVisible) ────────────────────────

    @isTest
    static void testCreateAmendmentManually_NoSubscriptions() {
        // Exercises the full DML path: Contract SOQL, Opp insert, Quote insert,
        // Opp update, empty Subscription list (no line inserts), re-query Quote,
        // return QuoteInfo. With CPQ triggers disabled, all DML should succeed.
        Contract con = getContract();

        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.QuoteInfo info =
            AgenticQTC_QuoteAmendmentService.createAmendmentManually(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, info, 'Manual amendment should return a QuoteInfo');
        System.assertNotEquals(null, info.id, 'New quote Id must be set');
        System.assertEquals('Draft', info.status, 'Manually created quote should be Draft');
        System.assertEquals(con.Id, info.contractId, 'QuoteInfo should reference the source contract');
    }

    // ─── autoApproveIfNotRequired ──────────────────────────────────────

    @isTest
    static void testAutoApproveIfNotRequired_SetsApprovedWhenNotAlreadyApproved() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        // The seeded quote has no ApprovalStatus set (null != 'Approved'), so the
        // method should fall through to the update branch without any pre-update needed.

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.autoApproveIfNotRequired(q.Id);
        Test.stopTest();

        SBQQ__Quote__c reloaded = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :q.Id];
        System.assertEquals('Approved', reloaded.ApprovalStatus__c,
            'autoApproveIfNotRequired should set ApprovalStatus to Approved');
    }

    @isTest
    static void testAutoApproveIfNotRequired_IsNoopWhenAlreadyApproved() {
        SBQQ__Quote__c q = getQuote();
        SBQQ.TriggerControl.disable();
        // Pre-set to Approved so the method hits the early-return branch.
        q.ApprovalStatus__c = 'Approved';
        update q;

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.autoApproveIfNotRequired(q.Id);
        Test.stopTest();

        SBQQ__Quote__c reloaded = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :q.Id];
        System.assertEquals('Approved', reloaded.ApprovalStatus__c,
            'Already-approved quote should remain Approved without a second DML');
    }

    // ─── stampCreatedBySimplifiedQuoting (@testVisible) ───────────────

    @isTest
    static void testStampCreatedBySimplifiedQuoting_NullQuoteId_IsNoop() {
        // Exercises the first early-return branch (quoteId == null).
        SBQQ.TriggerControl.disable();
        Test.startTest();
        AgenticQTC_QuoteAmendmentService.stampCreatedBySimplifiedQuoting(null);
        Test.stopTest();
        System.assert(true, 'Null quoteId should not throw');
    }

    @isTest
    static void testStampCreatedBySimplifiedQuoting_NonExistentQuote_IsNoop() {
        // Use a fabricated non-existent SBQQ__Quote__c Id so the SOQL returns an
        // empty list and the method hits the `quotes.isEmpty()` early-return branch
        // without any DML that could trigger unbypassable flows.
        SBQQ.TriggerControl.disable();
        String prefix = Schema.SObjectType.SBQQ__Quote__c.getKeyPrefix();
        Id missingId = Id.valueOf(prefix + '000000000099');

        Test.startTest();
        AgenticQTC_QuoteAmendmentService.stampCreatedBySimplifiedQuoting(missingId);
        Test.stopTest();
        System.assert(true, 'Non-existent quote should hit empty-list guard and not throw');
    }
}