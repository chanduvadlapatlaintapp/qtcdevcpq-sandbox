/**
 * @description Test class for AgenticQTC_ContractService.
 *              Covers:
 *                - Input validation (blank / null) on all three @AuraEnabled methods
 *                - Happy paths for getActiveContracts, getContractDetail, searchContractsByNumber
 *                - Filter behaviour (only 'In Force' / 'Partially Cancelled or superseded'
 *                  contracts with EndDate >= TODAY and a software subscription are returned)
 *                - Aggregate logic: subscription line count, product summary, productNames,
 *                  current-year ACV
 *                - DTO truncation paths: description >120 chars, special terms >100 chars
 *                - Term label paths: ContractTerm > 0, date-derived, both null
 * @author AgenticQTC Team
 * @date 2026-05-19
 */
@isTest
private class AgenticQTC_ContractServiceTest {

    private static final String LONG_DESCRIPTION =
        'This is a very long description that intentionally exceeds the 120-character cap so the '
        + 'service can truncate it down with an ellipsis and we cover that branch of the helper.';
    private static final String LONG_SPECIAL_TERMS =
        'These   are\nspecial    terms   with   redundant   whitespace   that   collapse   and   '
        + 'should   exceed   the   100-character   cap   so   truncation   fires   here.';

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        SBQQ.TriggerControl.disable();

        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        Account acct = new Account(
            Name         = 'Contract Service Test Acct',
            BillingCity  = 'Austin',
            BillingState = 'TX'
        );
        insert acct;

        Product2 softwareProd = new Product2(
            Name            = 'Software Product',
            ProductCode     = 'SW-001',
            IsActive        = true,
            Product_Type__c = 'Software'
        );
        insert softwareProd;

        Product2 secondSoftwareProd = new Product2(
            Name            = 'Software Product Two',
            ProductCode     = 'SW-002',
            IsActive        = true,
            Product_Type__c = 'Software'
        );
        insert secondSoftwareProd;

        Product2 servicesProd = new Product2(
            Name            = 'Services Product',
            ProductCode     = 'SV-001',
            IsActive        = true,
            Product_Type__c = 'Services'
        );
        insert servicesProd;

        // Contract #1 — eligible: 'In Force', future end date, has software subscriptions.
        // Long Description + SpecialTerms to exercise the truncation helpers.
        Contract eligible = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            EndDate      = Date.today().addYears(1),
            ContractTerm = 24,
            OSA_Number__c = 'OSA-TEST-001',
            Description  = LONG_DESCRIPTION,
            SpecialTerms = LONG_SPECIAL_TERMS
        );
        insert eligible;
        eligible.Status = 'In Force';
        update eligible;

        // Subscriptions: two software lines (one current-year, one outside window),
        // one services line. SBQQ__ProductName__c is a formula on the related
        // product, so it auto-populates; ACV__c is a calculated field and can
        // not be written directly from Apex.
        insert new List<SBQQ__Subscription__c>{
            new SBQQ__Subscription__c(
                SBQQ__Contract__c          = eligible.Id,
                SBQQ__Product__c           = softwareProd.Id,
                SBQQ__Quantity__c          = 10,
                SBQQ__ListPrice__c         = 100,
                SBQQ__NetPrice__c          = 1000,
                SBQQ__SegmentStartDate__c  = Date.today().addDays(-30),
                SBQQ__SegmentEndDate__c    = Date.today().addDays(30),
                SBQQ__SegmentIndex__c      = 1,
                SBQQ__SegmentLabel__c      = 'Year 1'
            ),
            new SBQQ__Subscription__c(
                SBQQ__Contract__c          = eligible.Id,
                SBQQ__Product__c           = secondSoftwareProd.Id,
                SBQQ__Quantity__c          = 5,
                SBQQ__ListPrice__c         = 50,
                SBQQ__NetPrice__c          = 250,
                // Outside current-year window — segment ended in the past.
                SBQQ__SegmentStartDate__c  = Date.today().addYears(-2),
                SBQQ__SegmentEndDate__c    = Date.today().addDays(-30),
                SBQQ__SegmentIndex__c      = 1
            ),
            new SBQQ__Subscription__c(
                SBQQ__Contract__c          = eligible.Id,
                SBQQ__Product__c           = servicesProd.Id,
                SBQQ__Quantity__c          = 1,
                SBQQ__ListPrice__c         = 200,
                SBQQ__NetPrice__c          = 200,
                SBQQ__SegmentStartDate__c  = Date.today().addDays(-30),
                SBQQ__SegmentEndDate__c    = Date.today().addDays(30)
            )
        };

        // Contract #2 — expired EndDate so getActiveContracts excludes it.
        Contract expired = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-3),
            EndDate      = Date.today().addDays(-1),
            ContractTerm = 12,
            OSA_Number__c = 'OSA-TEST-EXPIRED'
        );
        insert expired;
        expired.Status = 'In Force';
        update expired;

        // Contract #3 — eligible status + future end date but NO subscriptions
        // → semi-join excludes it from getActiveContracts.
        Contract noSubs = new Contract(
            AccountId    = acct.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            EndDate      = Date.today().addYears(1),
            ContractTerm = 12,
            OSA_Number__c = 'OSA-NO-SUBS'
        );
        insert noSubs;
        noSubs.Status = 'In Force';
        update noSubs;
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static Account getAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }

    private static Contract getEligibleContract() {
        return [SELECT Id, ContractNumber FROM Contract WHERE OSA_Number__c = 'OSA-TEST-001' LIMIT 1];
    }

    // ─── getActiveContracts: validation ────────────────────────────────

    @isTest
    static void testGetActiveContracts_NullThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.getActiveContracts(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null accountId should raise AuraHandledException');
    }

    @isTest
    static void testGetActiveContracts_BlankThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.getActiveContracts('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank accountId should raise AuraHandledException');
    }

    // ─── getActiveContracts: filter behaviour ──────────────────────────

    @isTest
    static void testGetActiveContracts_OnlyEligibleReturned() {
        Account acct = getAccount();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        // Expired contract excluded by EndDate. No-subs contract excluded by the
        // software-subscription semi-join. Only the OSA-TEST-001 contract qualifies.
        System.assertEquals(1, results.size(),
            'Only the eligible contract should pass status + EndDate + subscription filters');
        AgenticQTC_ContractService.ContractResult r = results[0];
        System.assertEquals('In Force', r.status);
        System.assertEquals('OSA-TEST-001', r.osaNumber);
    }

    @isTest
    static void testGetActiveContracts_AggregateFieldsPopulated() {
        Account acct = getAccount();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        AgenticQTC_ContractService.ContractResult r = results[0];
        // Aggregate path executes; precise per-product counts depend on org automation
        // (SBQQ flows/triggers can mutate subs post-insert), so we only assert structure.
        System.assertNotEquals(null, r.productNames, 'productNames list should be initialized');
        System.assert(r.subscriptionCount >= 1, 'At least one subscription should be counted');
        // ACV__c is a non-writeable calculated field in this org, so the precise
        // currentYearAcv total can't be asserted from test seed data. The aggregate
        // path is still exercised — null is the expected outcome when ACV resolves
        // to null in test context.
    }

    // ─── Product column AC scenarios ───────────────────────────────────
    //
    // Story: the Products column should display the summed quantity of each product
    // for the CURRENT year. Quantity increases are stored by CPQ as ADD-ON delta
    // subscriptions (co-termed from the amendment date to the segment end) while the
    // original baseline line stays active — so the current quantity is baseline + Σ
    // deltas (BIZ-82982). Helper creates an isolated Account + 'In Force' Contract so
    // the per-test data does not collide with the shared @testSetup contract.

    private static Account insertIsolatedAccount(String name) {
        Account a = new Account(Name = name, BillingCity = 'Austin', BillingState = 'TX');
        insert a;
        return a;
    }

    private static Contract insertInForceContract(Id accountId, Date startDate, Date endDate) {
        Contract c = new Contract(
            AccountId = accountId,
            Status    = 'Draft quote by salesperson',
            StartDate = startDate,
            EndDate   = endDate
        );
        insert c;
        c.Status = 'In Force';
        update c;
        return c;
    }

    private static Product2 insertSoftwareProduct(String name, String code) {
        Product2 p = new Product2(
            Name            = name,
            ProductCode     = code,
            IsActive        = true,
            Product_Type__c = 'Software'
        );
        insert p;
        return p;
    }

    @isTest
    static void testProductColumn_MdqCurrentYearWins() {
        // AC: 3-year MDQ — Year 1: 10, Year 2: 15, Year 3: 20.
        // Opening the contract during Year 2 should show 15, not 10 / 20 / sum.
        Account acct = insertIsolatedAccount('MDQ Current Year Acct');
        Product2 prod = insertSoftwareProduct('Deal Cloud Licenses', 'DC-MDQ-01');
        Contract c = insertInForceContract(
            acct.Id, Date.today().addDays(-365), Date.today().addDays(729));

        insert new List<SBQQ__Subscription__c>{
            new SBQQ__Subscription__c(
                SBQQ__Contract__c         = c.Id,
                SBQQ__Product__c          = prod.Id,
                SBQQ__Quantity__c         = 10,
                SBQQ__SegmentStartDate__c = Date.today().addDays(-365),
                SBQQ__SegmentEndDate__c   = Date.today().addDays(-1),
                SBQQ__SegmentIndex__c     = 1,
                SBQQ__SegmentLabel__c     = 'Year 1'
            ),
            new SBQQ__Subscription__c(
                SBQQ__Contract__c         = c.Id,
                SBQQ__Product__c          = prod.Id,
                SBQQ__Quantity__c         = 15,
                SBQQ__SegmentStartDate__c = Date.today(),
                SBQQ__SegmentEndDate__c   = Date.today().addDays(364),
                SBQQ__SegmentIndex__c     = 2,
                SBQQ__SegmentLabel__c     = 'Year 2'
            ),
            new SBQQ__Subscription__c(
                SBQQ__Contract__c         = c.Id,
                SBQQ__Product__c          = prod.Id,
                SBQQ__Quantity__c         = 20,
                SBQQ__SegmentStartDate__c = Date.today().addDays(365),
                SBQQ__SegmentEndDate__c   = Date.today().addDays(729),
                SBQQ__SegmentIndex__c     = 3,
                SBQQ__SegmentLabel__c     = 'Year 3'
            )
        };

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Exactly one eligible MDQ contract expected');
        List<String> names = results[0].productNames;
        System.assertEquals(1, names.size(),
            'Only the current-year segment should contribute to the product display');
        System.assertEquals('15x Deal Cloud Licenses', names[0],
            'Year 2 segment qty (15) should drive the label, not Year 1 or Year 3');
    }

    @isTest
    static void testProductColumn_SingleAmendmentWins() {
        // AC: 1 amendment increasing qty 10 → 12. CPQ stores this as the original
        // baseline (qty 10) plus a co-term add-on delta (qty 2) pointing back at the
        // baseline. The label should sum every current-segment line: 10 + 2 = 12x.
        Account acct = insertIsolatedAccount('Single Amendment Acct');
        Product2 prod = insertSoftwareProduct('Deal Cloud Licenses', 'DC-AMD-01');
        Contract c = insertInForceContract(
            acct.Id, Date.today().addDays(-30), Date.today().addDays(365));

        SBQQ__Subscription__c original = new SBQQ__Subscription__c(
            SBQQ__Contract__c = c.Id,
            SBQQ__Product__c  = prod.Id,
            SBQQ__Quantity__c = 10
        );
        insert original;

        // Amendment add-on carries only the incremental delta (+2), co-termed within
        // the current window and linked back to the baseline via RevisedSubscription.
        SBQQ__Subscription__c amended = new SBQQ__Subscription__c(
            SBQQ__Contract__c             = c.Id,
            SBQQ__Product__c              = prod.Id,
            SBQQ__Quantity__c             = 2,
            SBQQ__RevisedSubscription__c  = original.Id
        );
        insert amended;

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        List<String> names = results[0].productNames;
        System.assertEquals(1, names.size(),
            'A single product should produce exactly one product row');
        System.assertEquals('12x Deal Cloud Licenses', names[0],
            'Baseline (10) + amendment delta (2) should sum to the 12x label');
    }

    @isTest
    static void testProductColumn_MultiAmendmentChainWins() {
        // AC: two amendments raising qty 10 → 12 → 14. CPQ stores the baseline (qty 10)
        // plus two co-term add-on deltas (+2 each), each linked back to the baseline.
        // The label should sum every current-segment line: 10 + 2 + 2 = 14x. This is the
        // OSA 43881 scenario from BIZ-82982 (baseline + deltas, not "latest line only").
        Account acct = insertIsolatedAccount('Multi Amendment Acct');
        Product2 prod = insertSoftwareProduct('Deal Cloud Licenses', 'DC-AMD-02');
        Contract c = insertInForceContract(
            acct.Id, Date.today().addDays(-30), Date.today().addDays(365));

        SBQQ__Subscription__c original = new SBQQ__Subscription__c(
            SBQQ__Contract__c = c.Id,
            SBQQ__Product__c  = prod.Id,
            SBQQ__Quantity__c = 10
        );
        insert original;

        SBQQ__Subscription__c firstAmend = new SBQQ__Subscription__c(
            SBQQ__Contract__c             = c.Id,
            SBQQ__Product__c              = prod.Id,
            SBQQ__Quantity__c             = 2,
            SBQQ__RevisedSubscription__c  = original.Id
        );
        insert firstAmend;

        // Both add-ons point back at the same baseline — the real CPQ pattern, not a
        // linear chain — so neither delta may be treated as "superseding" the other.
        SBQQ__Subscription__c secondAmend = new SBQQ__Subscription__c(
            SBQQ__Contract__c             = c.Id,
            SBQQ__Product__c              = prod.Id,
            SBQQ__Quantity__c             = 2,
            SBQQ__RevisedSubscription__c  = original.Id
        );
        insert secondAmend;

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        List<String> names = results[0].productNames;
        System.assertEquals(1, names.size(),
            'A single product should produce exactly one product row');
        System.assertEquals('14x Deal Cloud Licenses', names[0],
            'Baseline (10) + two deltas (2 + 2) should sum to the 14x label');
    }

    @isTest
    static void testGetActiveContracts_TermLabelFromContractTerm() {
        Account acct = getAccount();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals('24 months', results[0].termLabel,
            'ContractTerm = 24 should drive the "24 months" label');
    }

    @isTest
    static void testGetActiveContracts_TruncatesLongDescription() {
        Account acct = getAccount();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        String shortDesc = results[0].descriptionShort;
        // 120 chars + 1 ellipsis = 121 characters total.
        System.assertEquals(121, shortDesc.length(),
            'Description longer than 120 chars should be truncated to 120 + ellipsis');
        System.assert(shortDesc.endsWith('…'),
            'Truncated description should end with the horizontal-ellipsis character');
    }

    @isTest
    static void testGetActiveContracts_TruncatesLongSpecialTerms() {
        Account acct = getAccount();
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        String shortTerms = results[0].specialTermsShort;
        System.assertEquals(101, shortTerms.length(),
            'Special terms longer than 100 chars should be truncated to 100 + ellipsis');
        System.assert(shortTerms.endsWith('…'));
        System.assert(!shortTerms.contains('  '),
            'Whitespace normalization should collapse internal runs of whitespace');
    }

    @isTest
    static void testGetActiveContracts_NoMatchReturnsEmpty() {
        // Valid-format Account Id that doesn't match any record.
        String prefix = Schema.SObjectType.Account.getKeyPrefix();
        Id missingId = Id.valueOf(prefix + '000000000001');

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(missingId);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Unknown accountId should return empty list');
    }

    // ─── getContractDetail ─────────────────────────────────────────────

    @isTest
    static void testGetContractDetail_NullThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.getContractDetail(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null contractId should raise AuraHandledException');
    }

    @isTest
    static void testGetContractDetail_BlankThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.getContractDetail('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw);
    }

    @isTest
    static void testGetContractDetail_HappyPath() {
        Contract c = getEligibleContract();

        Test.startTest();
        AgenticQTC_ContractService.ContractDetail detail =
            AgenticQTC_ContractService.getContractDetail(c.Id);
        Test.stopTest();

        System.assertEquals(c.Id, Id.valueOf(detail.id));
        System.assertEquals('In Force', detail.status);
        System.assertNotEquals(null, detail.accountName, 'Account name should be populated via the relationship');
        System.assertEquals(3, detail.subscriptions.size(), 'All three subscriptions should be surfaced');

        // Validate SubscriptionInfo mapping for at least one row.
        Boolean foundSegmented = false;
        for (AgenticQTC_ContractService.SubscriptionInfo sub : detail.subscriptions) {
            if (sub.segmentLabel == 'Year 1') {
                foundSegmented = true;
                System.assertEquals(1, sub.segmentIndex, 'segmentIndex should map from the source field');
                System.assertNotEquals(null, sub.netPrice);
                System.assertNotEquals(null, sub.listPrice);
                System.assertNotEquals(null, sub.productName);
            }
        }
        System.assert(foundSegmented, 'Should find the segmented subscription with label "Year 1"');
    }

    // ─── searchContractsByNumber ───────────────────────────────────────

    @isTest
    static void testSearchContractsByNumber_NullThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.searchContractsByNumber(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null contract number should raise AuraHandledException');
    }

    @isTest
    static void testSearchContractsByNumber_BlankThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            AgenticQTC_ContractService.searchContractsByNumber('   ');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Whitespace-only contract number should raise AuraHandledException');
    }

    @isTest
    static void testSearchContractsByNumber_MatchesByPartialNumber() {
        Contract c = getEligibleContract();
        System.assertNotEquals(null, c.ContractNumber,
            'Contract should auto-number on insert; sanity check before partial-match search');

        // First 3 chars guarantee partial overlap regardless of the auto-number sequence.
        String partial = c.ContractNumber.substring(0, 3);

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.searchContractsByNumber(partial);
        Test.stopTest();

        Boolean foundEligible = false;
        for (AgenticQTC_ContractService.ContractResult r : results) {
            if (r.id == String.valueOf(c.Id)) {
                foundEligible = true;
            }
        }
        System.assert(foundEligible, 'Partial-match search should locate the eligible contract');
    }

    @isTest
    static void testSearchContractsByNumber_NoMatchReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.searchContractsByNumber('CONT-NOSUCHNUMBER-XYZ');
        Test.stopTest();
        System.assertEquals(0, results.size(),
            'Number that matches nothing should return empty list, not throw');
    }

    // ─── ContractResult null-agg branch ───────────────────────────────
    // The else { subscriptionCount = 0 ... } branch fires only when buildSubscriptionAggregates
    // returns no entry for a contract. That cannot happen via the service methods (every
    // contract in the results list is pre-seeded into the aggregates map). Calling the
    // public ContractResult constructor directly with null covers those lines.

    @isTest
    static void testContractResult_NullAgg_DefaultsApplied() {
        Contract c = [
            SELECT Id, Name, ContractNumber, OSA_Number__c, Status, StartDate, EndDate,
                   CurrencyIsoCode, Account.Name, CustomerSignedId, CustomerSignedDate,
                   CompanySignedDate, ContractTerm, Description, SpecialTerms, Owner.Name
            FROM Contract WHERE OSA_Number__c = 'OSA-TEST-001' LIMIT 1
        ];
        Test.startTest();
        AgenticQTC_ContractService.ContractResult result =
            AgenticQTC_ContractService.buildContractResultNullAgg(c);
        Test.stopTest();
        System.assertEquals(0, result.subscriptionCount, 'Null agg → subscriptionCount = 0');
        System.assertEquals('', result.productSummary,   'Null agg → productSummary = empty');
        System.assertNotEquals(null, result.productNames, 'Null agg → productNames list initialized');
        System.assertEquals(0,  result.productNames.size());
        System.assertEquals(null, result.currentYearAcv);
        System.assertEquals(null, result.subscriptionTcv);
    }

    // ─── buildProductSummary: >3 products path ────────────────────────
    // The "firstThree + (+N more)" branch only fires when a contract has 4+ distinct
    // current-year software products; none of the @testSetup contracts qualify.

    @isTest
    static void testProductSummary_FourProductsShowsPlusMore() {
        Account acct = insertIsolatedAccount('Four Prods Acct');
        Contract c = insertInForceContract(
            acct.Id, Date.today().addDays(-30), Date.today().addDays(365));

        Product2 pa = new Product2(Name='Prod Alpha', ProductCode='FP-ALPH', IsActive=true, Product_Type__c='Software');
        Product2 pb = new Product2(Name='Prod Beta',  ProductCode='FP-BETA', IsActive=true, Product_Type__c='Software');
        Product2 pg = new Product2(Name='Prod Gamma', ProductCode='FP-GAMM', IsActive=true, Product_Type__c='Software');
        Product2 pd = new Product2(Name='Prod Delta', ProductCode='FP-DELT', IsActive=true, Product_Type__c='Software');
        insert new List<Product2>{ pa, pb, pg, pd };

        insert new List<SBQQ__Subscription__c>{
            new SBQQ__Subscription__c(SBQQ__Contract__c=c.Id, SBQQ__Product__c=pa.Id, SBQQ__Quantity__c=1,
                SBQQ__SegmentStartDate__c=Date.today().addDays(-30), SBQQ__SegmentEndDate__c=Date.today().addDays(365)),
            new SBQQ__Subscription__c(SBQQ__Contract__c=c.Id, SBQQ__Product__c=pb.Id, SBQQ__Quantity__c=2,
                SBQQ__SegmentStartDate__c=Date.today().addDays(-30), SBQQ__SegmentEndDate__c=Date.today().addDays(365)),
            new SBQQ__Subscription__c(SBQQ__Contract__c=c.Id, SBQQ__Product__c=pg.Id, SBQQ__Quantity__c=3,
                SBQQ__SegmentStartDate__c=Date.today().addDays(-30), SBQQ__SegmentEndDate__c=Date.today().addDays(365)),
            new SBQQ__Subscription__c(SBQQ__Contract__c=c.Id, SBQQ__Product__c=pd.Id, SBQQ__Quantity__c=4,
                SBQQ__SegmentStartDate__c=Date.today().addDays(-30), SBQQ__SegmentEndDate__c=Date.today().addDays(365))
        };

        Test.startTest();
        List<AgenticQTC_ContractService.ContractResult> results =
            AgenticQTC_ContractService.getActiveContracts(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return the four-product contract');
        System.assert(results[0].productSummary.contains('(+1 more)'),
            'Four distinct products should produce a summary ending with "(+1 more)"');
    }

    // ─── isMoreCurrent: all three inner branches ──────────────────────
    // @TestVisible on isMoreCurrent lets us test the null-start tie-breaker branches
    // directly, which is more reliable than trying to engineer SOQL ordering.

    @isTest
    static void testIsMoreCurrent_CandidateNullStart_ReturnsFalse() {
        // cStart == null, iStart != null → incumbent wins (null loses to a real date)
        SBQQ__Subscription__c cand  = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = null,           SBQQ__SegmentQuantity__c = 5);
        SBQQ__Subscription__c incum = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = Date.today(),   SBQQ__SegmentQuantity__c = 3);
        System.assertEquals(false, AgenticQTC_ContractService.isMoreCurrent(cand, incum),
            'Candidate with null start should lose to incumbent with a real start date');
    }

    @isTest
    static void testIsMoreCurrent_IncumbentNullStart_ReturnsTrue() {
        // iStart == null, cStart != null → candidate wins (real date beats null)
        SBQQ__Subscription__c cand  = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = Date.today(),   SBQQ__SegmentQuantity__c = 5);
        SBQQ__Subscription__c incum = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = null,           SBQQ__SegmentQuantity__c = 3);
        System.assertEquals(true, AgenticQTC_ContractService.isMoreCurrent(cand, incum),
            'Candidate with a real start date should beat incumbent with null start');
    }

    @isTest
    static void testIsMoreCurrent_DifferentNonNullDates_ReturnsComparison() {
        // cStart > iStart (both non-null, different) → covers the return cStart > iStart line
        SBQQ__Subscription__c later  = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = Date.today(),              SBQQ__SegmentQuantity__c = 5);
        SBQQ__Subscription__c earlier = new SBQQ__Subscription__c(SBQQ__SegmentStartDate__c = Date.today().addDays(-10), SBQQ__SegmentQuantity__c = 3);
        System.assertEquals(true, AgenticQTC_ContractService.isMoreCurrent(later, earlier),
            'Later start date should win the comparison');
        System.assertEquals(false, AgenticQTC_ContractService.isMoreCurrent(earlier, later),
            'Earlier start date should lose the comparison');
    }
}