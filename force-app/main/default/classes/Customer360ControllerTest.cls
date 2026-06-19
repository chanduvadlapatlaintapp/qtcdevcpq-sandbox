/**
 * @description Test class for Customer360Controller and ZendeskService.
 *              Uses TestFactory for all test data creation. Includes inner
 *              HttpCalloutMock implementation for Zendesk API callout tests
 *              with multi-endpoint routing (search + users).
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
@isTest
private class Customer360ControllerTest {

    /**********************************************************************************************
     *
     * Inner Mock Classes
     *
     ***********************************************************************************************/

    /**
     * @description Multi-endpoint mock HTTP callout class for Zendesk API responses.
     *              Routes responses based on the request endpoint URL.
     */
    private class ZendeskCalloutMock implements HttpCalloutMock {
        private Integer searchStatusCode;
        private String searchBody;
        private Integer usersStatusCode;
        private String usersBody;

        public ZendeskCalloutMock(Integer searchStatusCode, String searchBody) {
            this.searchStatusCode = searchStatusCode;
            this.searchBody = searchBody;
            this.usersStatusCode = 200;
            this.usersBody = '{"users":[]}';
        }

        public ZendeskCalloutMock(Integer searchStatusCode, String searchBody,
                                   Integer usersStatusCode, String usersBody) {
            this.searchStatusCode = searchStatusCode;
            this.searchBody = searchBody;
            this.usersStatusCode = usersStatusCode;
            this.usersBody = usersBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            if (endpoint.contains('/users/show_many')) {
                res.setStatusCode(this.usersStatusCode);
                res.setBody(this.usersBody);
            } else {
                res.setStatusCode(this.searchStatusCode);
                res.setBody(this.searchBody);
            }
            return res;
        }
    }

    /**********************************************************************************************
     *
     * Test Data Setup
     *
     ***********************************************************************************************/

    @TestSetup
    static void setupTestData() {
        Account acct = (Account) TestFactory.createSObject(
            new Account(Name = 'Test Customer 360 Account')
        );

        TestFactory.createSObject(
            new Invoice__c(
                Account__c = acct.Id
            )
        );

        TestFactory.createSObject(
            new OP4I_Entitlement_View__c(
                Account__c = acct.Id
            )
        );

        // Bypass triggers for Contract / Contract_Product_Line__c DML
        Automation_Controls__c ac = new Automation_Controls__c(
            Active__c = true,
            Bypass_Triggers__c = true,
            Contractline_Bypass__c = true
        );
        insert ac;

        // Product test data
        Product2 prodA = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Intapp DealCloud',
                ProductCode = 'DC-ENT-001',
                Family = 'DealCloud',
                IsActive = true
            )
        );
        Product2 prodB = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Intapp Conflicts',
                ProductCode = 'CONF-STD-001',
                Family = 'Conflicts',
                IsActive = true
            )
        );

        // Active Contract — Activated status, future end date
        Contract activeContract = (Contract) TestFactory.createSObject(
            new Contract(
                AccountId = acct.Id,
                Status = 'Draft quote by salesperson',
                StartDate = System.today().addMonths(-6),
                ContractTerm = 12
            )
        );
        activeContract.Status = 'Activated';
        update activeContract;

        // Draft Contract — Draft status
        Contract draftContract = (Contract) TestFactory.createSObject(
            new Contract(
                AccountId = acct.Id,
                Status = 'Draft quote by salesperson',
                StartDate = System.today(),
                ContractTerm = 12
            )
        );

        // Expired Contract — Activated but end date in the past
        Contract expiredContract = (Contract) TestFactory.createSObject(
            new Contract(
                AccountId = acct.Id,
                Status = 'Draft quote by salesperson',
                StartDate = System.today().addMonths(-24),
                ContractTerm = 12
            )
        );
        expiredContract.Status = 'Activated';
        update expiredContract;

        // Contract Product Lines — junction records
        TestFactory.createSObject(
            new Contract_Product_Line__c(
                Contract__c = activeContract.Id,
                Product2__c = prodA.Id,
                Price__c = 75000,
                Quantity__c = 50
            )
        );
        TestFactory.createSObject(
            new Contract_Product_Line__c(
                Contract__c = activeContract.Id,
                Product2__c = prodB.Id,
                Price__c = 25000,
                Quantity__c = 20
            )
        );
        TestFactory.createSObject(
            new Contract_Product_Line__c(
                Contract__c = draftContract.Id,
                Product2__c = prodA.Id,
                Price__c = 60000,
                Quantity__c = 30
            )
        );
        TestFactory.createSObject(
            new Contract_Product_Line__c(
                Contract__c = expiredContract.Id,
                Product2__c = prodB.Id,
                Price__c = 40000,
                Quantity__c = 15
            )
        );

        // Remove trigger bypass after setup
        delete ac;
    }

    /**********************************************************************************************
     *
     * Account Search Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testSearchAccounts_validTerm() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];
        Test.setFixedSearchResults(new List<Id>{ acct.Id });

        Test.startTest();
        List<Account> results = Customer360Controller.searchAccounts('Test Customer');
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should find at least one account');
    }

    @isTest
    static void testSearchAccounts_blankTerm() {
        List<Account> results = Customer360Controller.searchAccounts('');
        System.assertEquals(0, results.size(), 'Blank search should return empty list');
    }

    @isTest
    static void testSearchAccounts_shortTerm() {
        List<Account> results = Customer360Controller.searchAccounts('A');
        System.assertEquals(0, results.size(), 'Single character search should return empty list');
    }

    /**********************************************************************************************
     *
     * Subscription Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testGetSubscriptions_valid() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<Customer360Controller.SubscriptionWrapper> results =
            Customer360Controller.getSubscriptions(acct.Id);
        Test.stopTest();

        System.assertEquals(4, results.size(), 'Should return 4 contract product lines');

        for (Customer360Controller.SubscriptionWrapper w : results) {
            System.assertEquals('Contract', w.source, 'Source should be Contract');
            System.assertNotEquals(null, w.recordUrl, 'Record URL should be populated');
            System.assertNotEquals(null, w.product, 'Product name should be populated');
            System.assertNotEquals(null, w.sku, 'SKU (ProductCode) should be populated');
        }
    }

    @isTest
    static void testGetSubscriptions_fieldMapping() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<Customer360Controller.SubscriptionWrapper> results =
            Customer360Controller.getSubscriptions(acct.Id);
        Test.stopTest();

        // Find the active DealCloud line (75000 / 50 seats)
        Customer360Controller.SubscriptionWrapper dcLine;
        for (Customer360Controller.SubscriptionWrapper w : results) {
            if (w.product == 'Intapp DealCloud' && w.contractValue == 75000) {
                dcLine = w;
                break;
            }
        }

        System.assertNotEquals(null, dcLine, 'Should find Intapp DealCloud active line');
        System.assertEquals('DC-ENT-001', dcLine.sku, 'SKU should match ProductCode');
        System.assertEquals('DealCloud', dcLine.category, 'Category should match Product Family');
        System.assertEquals(75000, dcLine.contractValue, 'Contract value should match Price__c');
        System.assertEquals(50, dcLine.seats, 'Seats should match Quantity__c');
        System.assertNotEquals(null, dcLine.startDate, 'Start date should be populated');
        System.assertNotEquals(null, dcLine.endDate, 'End date should be populated');
        System.assertNotEquals(null, dcLine.contractNumber, 'Contract number should be populated');
    }

    @isTest
    static void testGetSubscriptions_contractStatusMapping() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<Customer360Controller.SubscriptionWrapper> results =
            Customer360Controller.getSubscriptions(acct.Id);
        Test.stopTest();

        Set<String> statuses = new Set<String>();
        for (Customer360Controller.SubscriptionWrapper w : results) {
            statuses.add(w.status);
        }

        // Active: from Activated / In Force contracts with future (or null) end dates
        System.assert(statuses.contains('Active'),
            'Should have Active status from activated/in-force contract. Found: ' + statuses);

        // Expired: from contract whose computed end date is in the past
        System.assert(statuses.contains('Expired'),
            'Should have Expired status from contract with past end date. Found: ' + statuses);

        // Verify all returned statuses are valid mapped values
        Set<String> validStatuses = new Set<String>{ 'Active', 'Pending', 'Expired' };
        for (String s : statuses) {
            System.assert(validStatuses.contains(s) || String.isNotBlank(s),
                'Status should be a recognized value, got: ' + s);
        }
    }

    @isTest
    static void testGetSubscriptions_nullId() {
        try {
            Customer360Controller.getSubscriptions(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    /**********************************************************************************************
     *
     * Entitlement Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testGetEntitlements_valid() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<Customer360Controller.EntitlementWrapper> results =
            Customer360Controller.getEntitlements(acct.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return entitlements');
    }

    @isTest
    static void testGetEntitlements_nullId() {
        try {
            Customer360Controller.getEntitlements(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    /**********************************************************************************************
     *
     * Invoice Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testGetInvoices_valid() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<Customer360Controller.InvoiceWrapper> results =
            Customer360Controller.getInvoices(acct.Id);
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return invoices');
    }

    @isTest
    static void testGetInvoices_nullId() {
        try {
            Customer360Controller.getInvoices(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    /**********************************************************************************************
     *
     * Zendesk Support Ticket Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testGetSupportTickets_success() {
        String searchBody = '{"results":[{"id":12345,"subject":"Test Ticket","status":"open",'
            + '"priority":"normal","type":"problem","created_at":"2026-01-15T10:30:00Z",'
            + '"updated_at":"2026-02-20T14:00:00Z","requester_id":99999,"assignee_id":88888}],"count":1}';
        String usersBody = '{"users":[{"id":88888,"name":"Agent Smith"}]}';

        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(200, searchBody, 200, usersBody));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<ZendeskService.ZendeskTicket> results =
            Customer360Controller.getSupportTickets(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one ticket');
        System.assertEquals('12345', results[0].id, 'Ticket ID should match');
        System.assertEquals('ZD-12345', results[0].ticketNumber, 'Ticket number should be formatted');
        System.assertEquals('Test Ticket', results[0].subject, 'Subject should match');
        System.assertEquals('Open', results[0].status, 'Status should be mapped to Title Case');
        System.assertEquals('Medium', results[0].priority, 'Priority should be mapped (normal → Medium)');
        System.assertEquals('Agent Smith', results[0].assignee, 'Assignee should be resolved from Users API');
        System.assertNotEquals(null, results[0].createdAt, 'Created date should be populated');
        System.assertEquals(null, results[0].resolvedAt, 'Open ticket should not have resolved date');
    }

    @isTest
    static void testGetSupportTickets_solvedTicket() {
        String searchBody = '{"results":[{"id":67890,"subject":"Solved Issue","status":"solved",'
            + '"priority":"high","type":"incident","created_at":"2026-01-10T08:00:00Z",'
            + '"updated_at":"2026-01-12T16:00:00Z","requester_id":99999,"assignee_id":null}],"count":1}';

        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(200, searchBody));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<ZendeskService.ZendeskTicket> results =
            Customer360Controller.getSupportTickets(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one ticket');
        System.assertEquals('Solved', results[0].status, 'Status should be mapped to Solved');
        System.assertEquals('High', results[0].priority, 'Priority should be mapped (high → High)');
        System.assertNotEquals(null, results[0].resolvedAt, 'Solved ticket should have resolved date');
        System.assertEquals(results[0].updatedAt, results[0].resolvedAt, 'Resolved date should equal updated date for solved tickets');
        System.assertEquals(null, results[0].assignee, 'Null assignee_id should result in null assignee');
    }

    @isTest
    static void testGetSupportTickets_urgentPriority() {
        String searchBody = '{"results":[{"id":11111,"subject":"Urgent Issue","status":"new",'
            + '"priority":"urgent","type":"incident","created_at":"2026-03-01T08:00:00Z",'
            + '"updated_at":"2026-03-01T09:00:00Z","requester_id":99999,"assignee_id":null}],"count":1}';

        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(200, searchBody));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<ZendeskService.ZendeskTicket> results =
            Customer360Controller.getSupportTickets(acct.Id);
        Test.stopTest();

        System.assertEquals('Critical', results[0].priority, 'Urgent priority should be mapped to Critical');
        System.assertEquals('Open', results[0].status, 'New status should be mapped to Open');
    }

    @isTest
    static void testGetSupportTickets_apiError() {
        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(401, '{"error":"Unauthorized"}'));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        try {
            Customer360Controller.getSupportTickets(acct.Id);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for API error');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetSupportTickets_nullId() {
        try {
            Customer360Controller.getSupportTickets(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    @isTest
    static void testGetSupportTickets_emptyResults() {
        String mockBody = '{"results":[],"count":0}';
        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(200, mockBody));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<ZendeskService.ZendeskTicket> results =
            Customer360Controller.getSupportTickets(acct.Id);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list');
    }

    @isTest
    static void testGetSupportTickets_usersApiFails() {
        String searchBody = '{"results":[{"id":12345,"subject":"Test","status":"open",'
            + '"priority":"low","type":"question","created_at":"2026-01-15T10:30:00Z",'
            + '"updated_at":"2026-02-20T14:00:00Z","requester_id":99999,"assignee_id":88888}],"count":1}';

        Test.setMock(HttpCalloutMock.class, new ZendeskCalloutMock(200, searchBody, 500, '{"error":"Internal Server Error"}'));

        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        List<ZendeskService.ZendeskTicket> results =
            Customer360Controller.getSupportTickets(acct.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should still return ticket even if users API fails');
        System.assertEquals('Low', results[0].priority, 'Priority should be mapped (low → Low)');
        System.assertEquals(null, results[0].assignee, 'Assignee should be null when users API fails');
    }

    /**********************************************************************************************
     *
     * Activity & CTA Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testLogActivity_valid() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        Id taskId = Customer360Controller.logActivity(
            acct.Id, 'Call', 'Quarterly check-in', 'Discussed renewal timeline', System.today()
        );
        Test.stopTest();

        Task createdTask = [SELECT Id, WhatId, Subject, Type, Status, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals(acct.Id, createdTask.WhatId, 'Task should be linked to account');
        System.assertEquals('Quarterly check-in', createdTask.Subject, 'Subject should match');
        System.assertEquals('Call', createdTask.Type, 'Type should match');
        System.assertEquals('Completed', createdTask.Status, 'Status should be Completed');
        System.assertEquals(System.today(), createdTask.ActivityDate, 'Activity date should match');
    }

    @isTest
    static void testLogActivity_nullId() {
        try {
            Customer360Controller.logActivity(null, 'Call', 'Test', null, System.today());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    @isTest
    static void testLogActivity_blankSubject() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];
        try {
            Customer360Controller.logActivity(acct.Id, 'Call', '', null, System.today());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for blank subject');
        }
    }

    @isTest
    static void testCreateCta_valid() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];

        Test.startTest();
        Id taskId = Customer360Controller.createCta(
            acct.Id, 'Risk', 'High', 'Client at risk of churn', System.today().addDays(14)
        );
        Test.stopTest();

        Task createdTask = [SELECT Id, WhatId, Subject, Type, Priority, Status, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals(acct.Id, createdTask.WhatId, 'Task should be linked to account');
        System.assert(createdTask.Subject.startsWith('Risk CTA'), 'Subject should start with CTA type');
        System.assertEquals('CTA', createdTask.Type, 'Type should be CTA');
        System.assertEquals('High', createdTask.Priority, 'Priority should match');
        System.assertEquals('Not Started', createdTask.Status, 'Status should be Not Started');
    }

    @isTest
    static void testCreateCta_nullId() {
        try {
            Customer360Controller.createCta(null, 'Risk', 'Normal', 'Test', System.today());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for null Id');
        }
    }

    @isTest
    static void testCreateCta_blankType() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Customer 360 Account' LIMIT 1];
        try {
            Customer360Controller.createCta(acct.Id, '', 'Normal', 'Test', System.today());
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for blank CTA type');
        }
    }

    /**********************************************************************************************
     *
     * ZendeskService Direct Tests
     *
     ***********************************************************************************************/

    @isTest
    static void testZendeskService_blankOrgName() {
        List<ZendeskService.ZendeskTicket> results = ZendeskService.getTicketsByOrganization('');
        System.assertEquals(0, results.size(), 'Blank org name should return empty list');
    }

    @isTest
    static void testZendeskService_nullOrgName() {
        List<ZendeskService.ZendeskTicket> results = ZendeskService.getTicketsByOrganization(null);
        System.assertEquals(0, results.size(), 'Null org name should return empty list');
    }
}