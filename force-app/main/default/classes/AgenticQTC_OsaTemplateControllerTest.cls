/**
 * @description Test class for AgenticQTC_OsaTemplateController.
 *              The controller is invoked by the AgenticQTC_OsaTemplate VF page
 *              and pulls quote / quote-line data based on the `quoteId` URL
 *              parameter. These tests exercise:
 *                - Constructor with no / blank `quoteId` → default empty state
 *                - Constructor with valid `quoteId` → fields hydrated from the
 *                  quote and its master contract / account relationships
 *                - All three qtyChange branches (increase / decrease / no change)
 *                - Null price defaults to '0.00'
 *                - Account / MasterContract null-safety in the relationship reads
 * @author AgenticQTC Team
 * @date 2026-05-19
 */
@isTest
private class AgenticQTC_OsaTemplateControllerTest {

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        // Disable CPQ triggers so the multi-line quote insert below loads
        // cleanly in test context.
        SBQQ.TriggerControl.disable();

        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c    = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(
            Name         = 'OsaTemplate Test Acct',
            BillingCity  = 'Austin',
            BillingState = 'TX'
        );
        insert acct;

        Contract con = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            EndDate      = Date.today().addYears(1),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'In Force';
        update con;

        // Opportunity is required — the org's "Quote After Insert-Update"
        // flow dereferences SBQQ__Opportunity2__c and faults when null.
        Opportunity opp = new Opportunity(
            Name      = 'OsaTemplate Test Opp',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Primary quote — has account, contract, start date, and lines covering
        // every qtyChange branch.
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c        = acct.Id,
            SBQQ__Opportunity2__c   = opp.Id,
            SBQQ__MasterContract__c = con.Id,
            SBQQ__Primary__c        = true,
            SBQQ__Status__c         = 'Draft',
            SBQQ__Type__c           = 'Amendment',
            SBQQ__StartDate__c      = Date.today(),
            SBQQ__EndDate__c        = Date.today().addYears(1)
        );
        insert quote;

        Product2 prod = new Product2(
            Name        = 'Template Test Product',
            ProductCode = 'TMPL-001',
            IsActive    = true
        );
        insert prod;

        insert new List<SBQQ__QuoteLine__c>{
            // Line #1 — qty unchanged (10 → 10)  → 'No change'
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c         = quote.Id,
                SBQQ__Product__c       = prod.Id,
                SBQQ__Quantity__c      = 10,
                SBQQ__PriorQuantity__c = 10,
                SBQQ__ListPrice__c     = 100,
                SBQQ__NetPrice__c      = 1000,
                SBQQ__Number__c        = 1
            ),
            // Line #2 — qty decreased (5 < 10)   → '-5'
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c         = quote.Id,
                SBQQ__Product__c       = prod.Id,
                SBQQ__Quantity__c      = 5,
                SBQQ__PriorQuantity__c = 10,
                SBQQ__ListPrice__c     = 100,
                SBQQ__NetPrice__c      = 500,
                SBQQ__Number__c        = 2
            ),
            // Line #3 — qty increased (15 > 10)  → '+5'
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c         = quote.Id,
                SBQQ__Product__c       = prod.Id,
                SBQQ__Quantity__c      = 15,
                SBQQ__PriorQuantity__c = 10,
                SBQQ__ListPrice__c     = 100,
                SBQQ__NetPrice__c      = 1500,
                SBQQ__Number__c        = 3
            ),
            // Line #4 — null prices (and no prior qty) → defaults to '0.00'
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c    = quote.Id,
                SBQQ__Product__c  = prod.Id,
                SBQQ__Quantity__c = 7,
                SBQQ__Number__c   = 4
            )
        };

        // Bare quote — no MasterContract, no StartDate. Used to exercise the
        // null-safety branches in the constructor. Account + Opportunity are
        // still required to get past the org's Quote flow.
        SBQQ__Quote__c bare = new SBQQ__Quote__c(
            SBQQ__Account__c      = acct.Id,
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Status__c       = 'Draft',
            SBQQ__Type__c         = 'Quote'
        );
        insert bare;
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static SBQQ__Quote__c getPrimaryQuote() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Type__c = 'Amendment' LIMIT 1];
    }

    private static SBQQ__Quote__c getBareQuote() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Type__c = 'Quote' LIMIT 1];
    }

    // ─── No / blank quoteId ────────────────────────────────────────────

    @isTest
    static void testNoQuoteIdParam() {
        Test.setCurrentPage(Page.AgenticQTC_OsaTemplate);

        Test.startTest();
        AgenticQTC_OsaTemplateController ctrl = new AgenticQTC_OsaTemplateController();
        Test.stopTest();

        System.assertEquals('', ctrl.quoteName);
        System.assertEquals('', ctrl.accountName);
        System.assertEquals('', ctrl.contractNumber);
        System.assertEquals(String.valueOf(Date.today()), ctrl.amendmentDate,
            'Missing quoteId should default amendmentDate to today');
        System.assertEquals(0, ctrl.quoteLines.size(),
            'Missing quoteId should yield an empty lines list');
    }

    @isTest
    static void testBlankQuoteIdParam() {
        Test.setCurrentPage(Page.AgenticQTC_OsaTemplate);
        ApexPages.currentPage().getParameters().put('quoteId', '');

        Test.startTest();
        AgenticQTC_OsaTemplateController ctrl = new AgenticQTC_OsaTemplateController();
        Test.stopTest();

        System.assertEquals('', ctrl.quoteName);
        System.assertEquals(0, ctrl.quoteLines.size());
    }

    // ─── Happy path: fully populated quote ─────────────────────────────

    @isTest
    static void testValidQuoteIdPopulatesHeader() {
        SBQQ__Quote__c quote = getPrimaryQuote();
        Test.setCurrentPage(Page.AgenticQTC_OsaTemplate);
        ApexPages.currentPage().getParameters().put('quoteId', quote.Id);

        Test.startTest();
        AgenticQTC_OsaTemplateController ctrl = new AgenticQTC_OsaTemplateController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.quoteName,
            'quoteName should be populated from the quote record');
        System.assert(String.isNotBlank(ctrl.quoteName),
            'quoteName should be a non-blank auto-generated value');
        System.assertEquals('OsaTemplate Test Acct', ctrl.accountName,
            'accountName should resolve via SBQQ__Account__r');
        System.assertNotEquals(null, ctrl.contractNumber,
            'contractNumber should resolve via SBQQ__MasterContract__r');
        System.assert(String.isNotBlank(ctrl.contractNumber));
        // SBQQ__StartDate__c was set to today.
        System.assertEquals(String.valueOf(Date.today()), ctrl.amendmentDate);
    }

    @isTest
    static void testValidQuoteIdPopulatesAllLineBranches() {
        SBQQ__Quote__c quote = getPrimaryQuote();
        Test.setCurrentPage(Page.AgenticQTC_OsaTemplate);
        ApexPages.currentPage().getParameters().put('quoteId', quote.Id);

        Test.startTest();
        AgenticQTC_OsaTemplateController ctrl = new AgenticQTC_OsaTemplateController();
        Test.stopTest();

        System.assertEquals(4, ctrl.quoteLines.size(), 'All four seeded lines should be loaded');

        // Lines come back in SBQQ__Number__c order.
        AgenticQTC_OsaTemplateController.LineItem noChange = ctrl.quoteLines[0];
        AgenticQTC_OsaTemplateController.LineItem decrease = ctrl.quoteLines[1];
        AgenticQTC_OsaTemplateController.LineItem increase = ctrl.quoteLines[2];
        AgenticQTC_OsaTemplateController.LineItem nullPrice = ctrl.quoteLines[3];

        // No-change branch (10 vs 10)
        System.assertEquals('No change', noChange.qtyChange);
        System.assertEquals(false, noChange.isChanged,
            'isChanged should be false when qty delta is zero');
        System.assertEquals('10', noChange.quantity);
        System.assertEquals('10', noChange.priorQuantity);

        // Decrease branch (5 vs 10 → -5)
        System.assertEquals('-5', decrease.qtyChange);
        System.assertEquals(true, decrease.isChanged);

        // Increase branch (15 vs 10 → +5)
        System.assertEquals('+5', increase.qtyChange);
        System.assertEquals(true, increase.isChanged);

        // Null-price / null-prior branch (7 vs null → +7, prices default to '0.00')
        System.assertEquals('+7', nullPrice.qtyChange,
            'Null prior quantity should default to 0, delta becomes the new qty');
        System.assertEquals('0', nullPrice.priorQuantity);
        System.assertEquals('0.00', nullPrice.listPrice,
            'Null list price should default to "0.00"');
        System.assertEquals('0.00', nullPrice.netPrice,
            'Null net price should default to "0.00"');
    }

    // ─── Bare quote: null relationships ────────────────────────────────

    @isTest
    static void testBareQuoteDefaultsRelationshipFields() {
        SBQQ__Quote__c bare = getBareQuote();
        Test.setCurrentPage(Page.AgenticQTC_OsaTemplate);
        ApexPages.currentPage().getParameters().put('quoteId', bare.Id);

        Test.startTest();
        AgenticQTC_OsaTemplateController ctrl = new AgenticQTC_OsaTemplateController();
        Test.stopTest();

        // Account is populated (the org's Quote flow requires it), but
        // MasterContract and StartDate are null → covers the corresponding
        // null-safety branches in the constructor.
        System.assertNotEquals(null, ctrl.quoteName);
        System.assertEquals('', ctrl.contractNumber,
            'Contract number should be empty when SBQQ__MasterContract__r is null');
        System.assertEquals(String.valueOf(Date.today()), ctrl.amendmentDate,
            'amendmentDate should default to today when SBQQ__StartDate__c is null');
        System.assertEquals(0, ctrl.quoteLines.size(),
            'Bare quote has no lines so the list should be empty');
    }

    // ─── LineItem DTO direct construction ──────────────────────────────

    @isTest
    static void testLineItemInnerClass() {
        AgenticQTC_OsaTemplateController.LineItem item =
            new AgenticQTC_OsaTemplateController.LineItem();
        item.productName = 'Test';
        item.quantity = '1';
        item.priorQuantity = '0';
        item.qtyChange = '+1';
        item.isChanged = true;
        item.listPrice = '100.00';
        item.netPrice = '90.00';

        System.assertEquals('Test', item.productName);
        System.assertEquals('1', item.quantity);
        System.assertEquals(true, item.isChanged);
    }
}