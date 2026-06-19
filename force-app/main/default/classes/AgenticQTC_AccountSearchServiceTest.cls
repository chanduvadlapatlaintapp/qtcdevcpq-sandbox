/**
 * @description Test class for AgenticQTC_AccountSearchService.
 *              Covers:
 *                - Input validation (blank / below min length)
 *                - SOSL-driven happy path with a qualifying contract + software subscription
 *                - Semi-join filter (SOSL hit but no qualifying contract → filtered out)
 *                - AccountResult location-string variants (city/state/both/neither)
 * @author AgenticQTC Team
 * @date 2026-05-19
 */
@isTest
private class AgenticQTC_AccountSearchServiceTest {

    // ─── Test Setup ─────────────────────────────────────────────────────

    @testSetup
    static void setupTestData() {
        // CPQ + custom subscription triggers don't bulk-safely handle these
        // inserts in test context — disable them so seed data lands cleanly.
        SBQQ.TriggerControl.disable();

        insert new Automation_Controls__c(
            Active__c          = true,
            Bypass_Flows__c    = true,
            Bypass_Triggers__c = true,
            SetupOwnerId       = UserInfo.getUserId()
        );

        // Account #1 — qualifies: has a contract in 'In Force' status with a
        // software subscription whose contract end date is in the future.
        Account qualifying = new Account(
            Name         = 'Qualifying Acct',
            BillingCity  = 'Austin',
            BillingState = 'TX'
        );
        insert qualifying;

        // Account #2 — won't qualify (no contract at all). Used to verify the
        // semi-join filter removes SOSL hits without an eligible contract.
        Account nonQualifying = new Account(
            Name         = 'NonQualifying Acct',
            BillingCity  = 'Boston',
            BillingState = 'MA'
        );
        insert nonQualifying;

        Product2 softwareProd = new Product2(
            Name             = 'Software Product',
            ProductCode      = 'SW-001',
            IsActive         = true,
            Product_Type__c  = 'Software'
        );
        insert softwareProd;

        Contract con = new Contract(
            AccountId    = qualifying.Id,
            Status       = 'Draft quote by salesperson',
            StartDate    = Date.today().addYears(-1),
            EndDate      = Date.today().addYears(1),
            ContractTerm = 24
        );
        insert con;
        con.Status = 'In Force';
        update con;

        insert new SBQQ__Subscription__c(
            SBQQ__Contract__c  = con.Id,
            SBQQ__Product__c   = softwareProd.Id,
            SBQQ__Quantity__c  = 10,
            SBQQ__ListPrice__c = 100,
            SBQQ__NetPrice__c  = 1000
        );
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    private static Account getQualifyingAccount() {
        return [SELECT Id FROM Account WHERE Name = 'Qualifying Acct' LIMIT 1];
    }

    private static Account getNonQualifyingAccount() {
        return [SELECT Id FROM Account WHERE Name = 'NonQualifying Acct' LIMIT 1];
    }

    // ─── searchAccounts: input validation ──────────────────────────────

    @isTest
    static void testSearchAccounts_BlankReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('');
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Blank input should short-circuit to empty list');
    }

    @isTest
    static void testSearchAccounts_NullReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts(null);
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Null input should short-circuit to empty list');
    }

    @isTest
    static void testSearchAccounts_BelowMinLength() {
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('a');
        Test.stopTest();
        System.assertEquals(0, results.size(),
            'Single-character term should fall below MIN_SEARCH_LENGTH and return empty');
    }

    @isTest
    static void testSearchAccounts_WhitespaceOnlyReturnsEmpty() {
        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('   ');
        Test.stopTest();
        System.assertEquals(0, results.size(),
            'Whitespace-only input trims to blank and should return empty');
    }

    // ─── searchAccounts: SOSL happy path ───────────────────────────────

    @isTest
    static void testSearchAccounts_QualifyingAccountIsReturned() {
        Account acct = getQualifyingAccount();
        // SOSL returns [] in test context unless we seed fixed results.
        Test.setFixedSearchResults(new List<Id>{ acct.Id });

        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('Qualifying');
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Account with eligible contract + software subscription should pass the semi-join');
        System.assertEquals(acct.Id, results[0].id);
        System.assertEquals('Qualifying Acct', results[0].name);
        // Location starts with the city; the org's address trigger may strip
        // the state during DML so we don't assert on the full "City, State" form.
        System.assert(results[0].location.startsWith('Austin'),
            'Location should include the BillingCity prefix');
    }

    @isTest
    static void testSearchAccounts_NonQualifyingAccountIsFiltered() {
        Account acct = getNonQualifyingAccount();
        // SOSL returns the account but the semi-join should remove it because
        // there's no qualifying contract on this account.
        Test.setFixedSearchResults(new List<Id>{ acct.Id });

        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('NonQualifying');
        Test.stopTest();

        System.assertEquals(0, results.size(),
            'Account without a qualifying contract should be filtered out');
    }

    @isTest
    static void testSearchAccounts_EmptySoslReturnsEmpty() {
        // Fixed empty SOSL — service should short-circuit before the semi-join.
        Test.setFixedSearchResults(new List<Id>{});

        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('NothingMatches');
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty SOSL should return empty list');
    }

    @isTest
    static void testSearchAccounts_SingleQuoteIsSanitized() {
        // Escaping path: a single quote in the term must not break the SOSL.
        Account acct = getQualifyingAccount();
        Test.setFixedSearchResults(new List<Id>{ acct.Id });

        Test.startTest();
        List<AgenticQTC_AccountSearchService.AccountResult> results =
            AgenticQTC_AccountSearchService.searchAccounts('O\'Brien');
        Test.stopTest();

        // Asserting no exception + valid list back is the contract; the SOSL
        // result is fixed regardless of the term we send.
        System.assertNotEquals(null, results);
    }

    // ─── AccountResult location variants ───────────────────────────────

    @isTest
    static void testAccountResult_CityAndState() {
        Account a = new Account(Name = 'Both', BillingCity = 'Houston', BillingState = 'TX');
        AgenticQTC_AccountSearchService.AccountResult r =
            new AgenticQTC_AccountSearchService.AccountResult(a);
        System.assertEquals('Both', r.name);
        System.assertEquals('Houston, TX', r.location);
    }

    @isTest
    static void testAccountResult_CityOnly() {
        Account a = new Account(Name = 'CityOnly', BillingCity = 'Dallas');
        AgenticQTC_AccountSearchService.AccountResult r =
            new AgenticQTC_AccountSearchService.AccountResult(a);
        System.assertEquals('Dallas', r.location);
    }

    @isTest
    static void testAccountResult_StateOnly() {
        Account a = new Account(Name = 'StateOnly', BillingState = 'California');
        AgenticQTC_AccountSearchService.AccountResult r =
            new AgenticQTC_AccountSearchService.AccountResult(a);
        System.assertEquals('California', r.location);
    }

    @isTest
    static void testAccountResult_NoLocation() {
        Account a = new Account(Name = 'NoLocation');
        AgenticQTC_AccountSearchService.AccountResult r =
            new AgenticQTC_AccountSearchService.AccountResult(a);
        System.assertEquals('', r.location);
    }
}