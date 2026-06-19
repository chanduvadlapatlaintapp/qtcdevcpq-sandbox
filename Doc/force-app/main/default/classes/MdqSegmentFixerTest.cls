/**
 * @description Test class for MdqSegmentFixer.
 *              Validates that missing MDQ segment OrderItems are correctly detected and created
 *              when an Order transitions to Activated status.
 * @author      Satya Pusuluri
 * @date        2026-05-04
 * @jira        BIZ-81576
 */
@isTest
public with sharing class MdqSegmentFixerTest {

    private static final String SEG_KEY = 'TEST_SEG_KEY_001';

    /***********************************************************************************************
    *
    * Shared Test Data Setup
    *
    ***********************************************************************************************/

    /**
     * @description Creates shared test data: Account, Opportunity, Product2, PricebookEntry,
     *              CPQ Quote linked to the Opportunity, two MDQ QuoteLines (SegmentIndex 1 and 2),
     *              one Order (Draft) linked to the Quote, and one existing OrderItem for
     *              SegmentIndex 1 — simulating CPQ skipping the zero-qty SegmentIndex 2.
     *
     *              Note: EndDate is intentionally omitted from QuoteLines and OrderItems to avoid
     *              the "OrderItem EndDate cannot exceed Order EndDate" constraint, which depends on
     *              whatever OrderDefaults sets. This matches the pattern in OrderProductTriggerHandlerTest.
     */
    @testSetup
    static void setup() {

        // ── Account ──────────────────────────────────────────────────────────────────────────────
        Account acct = (Account) TestFactory.createSObject(
            new Account(Name = 'MDQ Test Account'),
            'AccountDefaults'
        );

        // ── Product + PricebookEntry ──────────────────────────────────────────────────────────────
        Product2 prod = (Product2) TestFactory.createSObject(
            new Product2(Name = 'MDQ Test Product'),
            'ProductDefaults'
        );
        PricebookEntry pbe = (PricebookEntry) TestFactory.createSObject(
            new PricebookEntry(
                Product2Id   = prod.Id,
                Pricebook2Id = Test.getStandardPricebookId()
            ),
            'PricebookEntryDefaults'
        );

        // ── Opportunity ───────────────────────────────────────────────────────────────────────────
        // Required by the "Quote After Insert-Update" flow — Quote insert fails without one.
        Opportunity opp = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name      = 'MDQ Test Opp',
                AccountId = acct.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(3)
            ),
            'OpportunityDefaults'
        );

        // ── CPQ Quote ─────────────────────────────────────────────────────────────────────────────
        SBQQ.TriggerControl.disable();

        SBQQ__Quote__c quote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Primary__c      = true,
                SBQQ__Opportunity2__c = opp.Id
            ),
            'SBQQQuoteDefaults'
        );

        // QL for Segment Index 1 — non-zero qty (CPQ creates an OrderItem for this)
        SBQQ__QuoteLine__c ql1 = (SBQQ__QuoteLine__c) TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c             = quote.Id,
                SBQQ__Product__c           = prod.Id,
                SBQQ__Quantity__c          = 10,
                SBQQ__CustomerPrice__c     = 1000,
                SBQQ__SegmentKey__c        = SEG_KEY,
                SBQQ__SegmentIndex__c      = 1,
                SBQQ__StartDate__c         = Date.today(),
                SBQQ__ProrateMultiplier__c = 12
            ),
            'SBQQQuoteLineDefaults'
        );

        // QL for Segment Index 2 — zero qty (CPQ skips this; MdqSegmentFixer must create it)
        SBQQ__QuoteLine__c ql2 = (SBQQ__QuoteLine__c) TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c             = quote.Id,
                SBQQ__Product__c           = prod.Id,
                SBQQ__Quantity__c          = 0,
                SBQQ__CustomerPrice__c     = 0,
                SBQQ__SegmentKey__c        = SEG_KEY,
                SBQQ__SegmentIndex__c      = 2,
                SBQQ__StartDate__c         = Date.today().addMonths(12),
                SBQQ__ProrateMultiplier__c = 12
            ),
            'SBQQQuoteLineDefaults'
        );

        SBQQ.TriggerControl.enable();

        // ── Bill-To Address ───────────────────────────────────────────────────────────────────────
        // Bill_To_Address__c is required on Order in orgs that enforce it (e.g. QTCMOCK).
        // The lookup filter requires Status__c = 'Verification Approved' and a populated address.
        // Pattern from QuoteTermServiceTest.
        Address__c billToAddr = new Address__c(
            Account__c              = acct.Id,
            Address__City__s        = 'Los Angeles',
            Address__CountryCode__s = 'US',
            Address__PostalCode__s  = '90210',
            Address__StateCode__s   = 'CA',
            Address__Street__s      = 'Beverly Hills',
            Status__c               = 'Verification Approved',
            Default_Billing_Address__c  = true,
            Default_Shipping_Address__c = true
        );
        insert billToAddr;

        // ── Automation Controls bypass ────────────────────────────────────────────────────────────
        // The "Order : Before Insert Update" before-save flow requires Bill_To_Address__c to be
        // populated from the linked Quote or amended Contract.  In @testSetup, the Order is linked
        // to the Quote via a post-insert update, so the flow would clear Bill_To_Address__c during
        // the initial insert even when we explicitly set it.  This bypass pattern is documented in
        // OrderTriggerHandlerTest.populateMasterContractNoAmendedContractTest and is the authoritative
        // way to suppress that flow — Active__c + Bypass_Flows__c alone is insufficient;
        // Order_Bypass__c must also be true.
        //
        // Orderline_Bypass__c is also set here so that MdqSegmentFixer.fixMissingSegmentsOnNewOrderItems
        // (wired to OrderProductTriggerHandler.afterInsert) does NOT fire when @testSetup inserts the
        // initial Segment 1 OrderItem.  Tests need to start with exactly 1 OI so they can verify
        // the fix themselves.  The bypass is reset to false after the OI insert so test methods
        // start with Orderline_Bypass__c = false and the hook works normally.
        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        controls.Active__c           = true;
        controls.Bypass_Flows__c     = true;
        controls.Order_Bypass__c     = true;
        controls.Orderline_Bypass__c = true;
        upsert controls;

        // ── Order ─────────────────────────────────────────────────────────────────────────────────
        // Build with OrderDefaults first, then set Bill_To_Address__c and Billing_Account__c
        // AFTER defaults are applied. This guards against OrderDefaults overwriting lookups
        // (observed in QTCMOCK). Pattern: buildSObject → set fields → insert.
        // Billing_Account__c must match Address__c.Account__c for the lookup filter.
        Order ord = (Order) TestFactory.buildSObject(
            new Order(
                AccountId    = acct.Id,
                Pricebook2Id = Test.getStandardPricebookId(),
                Status       = 'Draft'
            ),
            'OrderDefaults'
        );
        ord.Billing_Account__c  = acct.Id;
        ord.Bill_To_Address__c  = billToAddr.Id;
        insert ord;
        // Link to Quote in a separate update — SBQQ__Quote__c cannot be set during initial insert
        ord.SBQQ__Quote__c = quote.Id;
        update ord;

        // ── Existing OrderItem for Segment Index 1 ────────────────────────────────────────────────
        // Simulates what CPQ created when ordering the Quote. Segment Index 2 is intentionally absent.
        // EndDate omitted — OrderItem.EndDate must not exceed Order.EndDate, which is controlled
        // by OrderDefaults and may vary. Omitting is safe and matches OrderProductTriggerHandlerTest.
        TestFactory.createSObject(
            new OrderItem(
                OrderId               = ord.Id,
                PricebookEntryId      = pbe.Id,
                Quantity              = 10,
                UnitPrice             = 1000,
                SBQQ__QuoteLine__c    = ql1.Id,
                SBQQ__SegmentKey__c   = SEG_KEY,
                SBQQ__SegmentIndex__c = 1,
                ServiceDate           = Date.today()
            ),
            'OrderItemDefaults'
        );

        // Reset Orderline_Bypass__c so MdqSegmentFixer.fixMissingSegmentsOnNewOrderItems runs
        // normally in each test method (starting from the 1-OI state set up above).
        Automation_Controls__c postSetup = Automation_Controls__c.getInstance();
        postSetup.Orderline_Bypass__c = false;
        upsert postSetup;
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/

    /**
     * @description When Order Status is not transitioning to Activated (Draft → Draft),
     *              fixMissingSegments must exit early and not insert any OrderItems.
     */
    @isTest
    static void testNoActivationChange_noInsert() {
        Order ord = getTestOrder();
        Integer countBefore = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];

        Map<Id, Object> oldMap = new Map<Id, Object>{
            ord.Id => new Order(Id = ord.Id, Status = 'Draft')
        };
        ord.Status = 'Draft'; // No status change

        Test.startTest();
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ ord }, oldMap);
        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];
        System.assertEquals(countBefore, countAfter,
            'No OrderItems should be inserted when Status is not transitioning to Activated');
    }

    /**
     * @description When an Order transitions to Activated and SegmentIndex 2 has no OrderItem
     *              (QuoteLine has Quantity = 0), fixMissingSegments must insert the missing segment
     *              with Quantity = 0, the correct SegmentIndex, and ServiceDate from the QuoteLine.
     */
    @isTest
    static void testMissingSegmentCreated() {
        Order ord = getTestOrder();

        List<OrderItem> before = [SELECT Id, SBQQ__SegmentIndex__c FROM OrderItem WHERE OrderId = :ord.Id];
        System.assertEquals(1, before.size(),
            'Setup: exactly 1 OrderItem (Segment 1) should exist before the fix');
        System.assertEquals(1, (Integer) before[0].SBQQ__SegmentIndex__c,
            'Setup: existing item should be Segment Index 1');

        Map<Id, Object> oldMap = new Map<Id, Object>{
            ord.Id => new Order(Id = ord.Id, Status = 'Draft')
        };
        ord.Status = 'Activated';

        Test.startTest();
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ ord }, oldMap);
        Test.stopTest();

        // Surface any silent DML errors before asserting row count
        System.assertEquals(0, MdqSegmentFixer.testInsertErrors.size(),
            'Insert failed with DML error(s): ' + MdqSegmentFixer.testInsertErrors);

        List<OrderItem> after = [
            SELECT Id, Quantity, UnitPrice, SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c, ServiceDate
            FROM OrderItem
            WHERE OrderId = :ord.Id
            ORDER BY SBQQ__SegmentIndex__c
        ];
        System.assertEquals(2, after.size(),
            'Should have 2 OrderItems after fix — one per MDQ segment');

        OrderItem created = after[1]; // Segment Index 2 (ordered by SegmentIndex)
        System.assertEquals(2,       (Integer) created.SBQQ__SegmentIndex__c, 'Created item must be Segment Index 2');
        System.assertEquals(SEG_KEY, created.SBQQ__SegmentKey__c,             'Segment key must match');
        // Quantity = 0: "Enable Zero Quantity" Order setting is enabled in this org, and
        // SBQQ.TriggerControl.disable() is active during the insert, so Quantity=0 is allowed.
        System.assertEquals(0,       (Integer) created.Quantity,               'Quantity must be 0 (zero-qty segment; "Enable Zero Quantity" Order setting required)');
        System.assertEquals(0,       created.UnitPrice,                        'Missing segment must have UnitPrice = 0');

        SBQQ__QuoteLine__c ql2 = getQuoteLine(2);
        System.assertEquals(ql2.SBQQ__StartDate__c, created.ServiceDate,
            'ServiceDate must match QuoteLine SBQQ__StartDate__c');
    }

    /**
     * @description PRIMARY path — fixMissingSegmentsOnNewOrderItems (OrderProduct.afterInsert).
     *              Simulates CPQ creating the non-zero Segment 1 OrderItem during the ordering step.
     *              MdqSegmentFixer must detect the missing Segment 2 and create it immediately,
     *              so all segments are present before the user attempts activation.
     */
    @isTest
    static void testMissingSegmentCreated_afterInsertPath() {
        Order ord = getTestOrder();
        // Fetch all fields needed by buildMissingOrderItem so the sibling map is fully populated.
        // In production, Trigger.new carries all fields; in tests we must query them explicitly.
        List<OrderItem> existingItems = [
            SELECT Id, OrderId, PricebookEntryId, Product2Id, ListPrice, ServiceDate, EndDate,
                   SBQQ__QuoteLine__c, SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c,
                   SBQQ__DimensionType__c, SBQQ__ChargeType__c, SBQQ__BillingType__c,
                   SBQQ__BillingFrequency__c, SBQQ__SubscriptionTerm__c, SBQQ__DefaultSubscriptionTerm__c,
                   SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__ProductSubscriptionType__c,
                   SBQQ__ProrateMultiplier__c, SBQQ__PricingMethod__c, SBQQ__QuotedListPrice__c,
                   SBQQ__BookingsIndicator__c, SBQQ__ContractAction__c, SBQQ__ContractingMethod__c,
                   SBQQ__TaxCode__c, SBQQ__Status__c, SBQQ__Activated__c, SBQQ__Contracted__c,
                   ACV_Type__c, Inherited_ACV_Type__c, CPQ_Option_Type__c, OSA_Number__c,
                   Software_Payment_Term__c, Support_Level__c, Days_In_Advance__c, Description
            FROM OrderItem WHERE OrderId = :ord.Id
        ];
        System.assertEquals(1, existingItems.size(), 'Setup: exactly 1 OrderItem (Segment 1) should exist before the fix');

        Test.startTest();
        // Simulate what OrderProductTriggerHandler.afterInsert passes when CPQ creates Segment 1
        MdqSegmentFixer.fixMissingSegmentsOnNewOrderItems(existingItems);
        Test.stopTest();

        // Surface any silent DML errors
        System.assertEquals(0, MdqSegmentFixer.testInsertErrors.size(),
            'Insert failed with DML error(s): ' + MdqSegmentFixer.testInsertErrors);

        List<OrderItem> after = [
            SELECT Id, Quantity, UnitPrice, SBQQ__SegmentIndex__c, SBQQ__SegmentKey__c
            FROM OrderItem
            WHERE OrderId = :ord.Id
            ORDER BY SBQQ__SegmentIndex__c
        ];
        System.assertEquals(2, after.size(),
            'afterInsert path: should have 2 OrderItems — one per MDQ segment');
        System.assertEquals(2, (Integer) after[1].SBQQ__SegmentIndex__c,
            'afterInsert path: created item must be Segment Index 2');
        System.assertEquals(0, (Integer) after[1].Quantity,
            'afterInsert path: Quantity must be 0 (zero-qty segment; "Enable Zero Quantity" Order setting required)');
        System.assertEquals(0, after[1].UnitPrice,
            'afterInsert path: UnitPrice must be 0');
    }

    /**
     * @description When all QuoteLine segments already have corresponding OrderItems,
     *              fixMissingSegments must be idempotent — no extra records inserted.
     *
     *              Strategy: call fixMissingSegments once to create the missing Segment 2 OI
     *              (the same path verified by testMissingSegmentCreated), record the count,
     *              then call it a second time and assert the count is unchanged.
     *              This avoids a direct OrderItem DML with UnitPrice = 0, which triggers the
     *              "Order : Before Insert Update" flow with missing SBQQ metadata fields.
     */
    @isTest
    static void testAllSegmentsPresent_noInsert() {
        Order ord = getTestOrder();

        Map<Id, Object> oldMap = new Map<Id, Object>{
            ord.Id => new Order(Id = ord.Id, Status = 'Draft')
        };
        ord.Status = 'Activated';

        Test.startTest();

        // First call — creates the missing Segment 2 OI (same code path as testMissingSegmentCreated).
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ ord }, oldMap);

        Integer countBefore = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];
        System.assertEquals(2, countBefore,
            'Pre-populate: both Segment 1 and Segment 2 should exist before the idempotency check');

        // Second call — all segments already present; fixer must be idempotent and insert nothing.
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ ord }, oldMap);

        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];
        System.assertEquals(countBefore, countAfter,
            'No new OrderItems should be inserted when all segments are already present (idempotent)');
    }

    /**
     * @description When the activating Order has no linked CPQ Quote (SBQQ__Quote__c is null),
     *              fixMissingSegments must exit early without errors or inserts.
     */
    @isTest
    static void testNoLinkedQuote_noInsert() {
        Account    acct       = getTestAccount();
        Address__c billToAddr = getTestAddress(); // reuse Address from @testSetup (avoids SOQL limit from AddressTrigger re-firing)

        Order standaloneOrd = (Order) TestFactory.createSObject(
            new Order(
                AccountId          = acct.Id,
                Pricebook2Id       = Test.getStandardPricebookId(),
                Status             = 'Draft',
                Billing_Account__c = acct.Id,
                Bill_To_Address__c = billToAddr.Id
            ),
            'OrderDefaults'
        );

        Map<Id, Object> oldMap = new Map<Id, Object>{
            standaloneOrd.Id => new Order(Id = standaloneOrd.Id, Status = 'Draft')
        };
        standaloneOrd.Status = 'Activated';

        Test.startTest();
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ standaloneOrd }, oldMap);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM OrderItem WHERE OrderId = :standaloneOrd.Id];
        System.assertEquals(0, count,
            'No OrderItems should be created for an Order with no linked CPQ Quote');
    }

    /**
     * @description When Automation_Controls__c bypass is fully active
     *              (Active__c + Bypass_Flows__c + Orderline_Bypass__c = true),
     *              fixMissingSegments must respect the bypass and insert nothing.
     */
    @isTest
    static void testBypassRespected_noInsert() {
        // Retrieve the existing controls record (upserted in @testSetup) and additionally enable
        // Orderline_Bypass__c so MdqSegmentFixer.fixMissingSegments exits early.
        // Using getInstance() + upsert (not a fresh new Automation_Controls__c) avoids a
        // DUPLICATE_VALUE error when the @testSetup record already exists at the same hierarchy level.
        Automation_Controls__c controls = Automation_Controls__c.getInstance();
        controls.Active__c           = true;
        controls.Bypass_Flows__c     = true;
        controls.Orderline_Bypass__c = true;
        upsert controls;

        Order ord = getTestOrder();
        Integer countBefore = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];

        Map<Id, Object> oldMap = new Map<Id, Object>{
            ord.Id => new Order(Id = ord.Id, Status = 'Draft')
        };
        ord.Status = 'Activated';

        Test.startTest();
        MdqSegmentFixer.fixMissingSegments(new List<Order>{ ord }, oldMap);
        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM OrderItem WHERE OrderId = :ord.Id];
        System.assertEquals(countBefore, countAfter,
            'No OrderItems should be inserted when the QTC bypass is active');
    }

    /***********************************************************************************************
    *
    * Private Helpers
    *
    ***********************************************************************************************/

    private static Account getTestAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Address__c getTestAddress() {
        return [SELECT Id FROM Address__c LIMIT 1];
    }

    private static Order getTestOrder() {
        return [SELECT Id, Status, SBQQ__Quote__c FROM Order LIMIT 1];
    }

    private static PricebookEntry getPricebookEntry() {
        return [SELECT Id FROM PricebookEntry LIMIT 1];
    }

    private static SBQQ__QuoteLine__c getQuoteLine(Integer segmentIndex) {
        return [
            SELECT Id, SBQQ__SegmentKey__c, SBQQ__SegmentIndex__c,
                   SBQQ__StartDate__c, SBQQ__ProrateMultiplier__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__SegmentIndex__c = :segmentIndex
            LIMIT 1
        ];
    }
}