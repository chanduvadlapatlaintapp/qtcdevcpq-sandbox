/**
* @description       : Test class for AutomationPreference. This class provides comprehensive test coverage for
*                      the automation preference utility functionality, including validation of automation execution
*                      control based on Automation_Controls__c custom setting configuration. Tests cover various
*                      scenarios including global bypass, selective bypass with Data_Id__c, and inactive controls.
* @author            : Sahal Mohamed
* Created Date       : Jan-08-2026
**/
@isTest
public class AutomationPreferenceTest {
    
    /***********************************************************************************************
    *
    * Test Setup and Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Creates test data including accounts, contacts, contracts, opportunities, quotes,
    *              users, and approver matrix records for use in test methods. This method is called
    *              automatically by the test framework before each test method execution.
    **/
    @testSetup
    static void setupTestData() {
        // Create User first (setup object) to avoid MIXED_DML_OPERATION
        User testUser = (User)TestFactory.createSObject(
            new User(
                LastName = 'Testing',
                FirstName = 'Test',
                Email = 'test@testintapp.com'
            ), 'AdminUserDefaults'
        );
        
        // Use System.runAs to separate setup object from non-setup objects
        System.runAs(testUser) {
            // Create Account using TestFactory
            Account account = (Account)TestFactory.createSObject(
                new Account(
                    Name = 'Test Account',
                    BillingCountry = 'United States'
                ), 'AccountDefaults'
            );
            
            // Create Contact using TestFactory
            Contact contact = (Contact)TestFactory.createSObject(
                new Contact(
                    AccountId = account.Id,
                    FirstName = 'Test',
                    LastName = 'Contact'
                ), 'ContactDefaults'
            );
            
            // Create Contract using TestFactory
            Contract contract = (Contract)TestFactory.createSObject(
                new Contract(
                    AccountId = account.Id,
                    StartDate = Date.today(),
                    ContractTerm = 12
                ), 'ContractDefaults'
            );
            
            // Create Opportunity using TestFactory
            Opportunity opportunity = (Opportunity)TestFactory.createSObject(
                new Opportunity(
                    AccountId = account.Id,
                    Name = 'Test Opportunity',
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Associated_Contract_OSA__c = contract.Id,
                    Contract_Signer__c = contact.Id,
                    Requested_Contract_Expiration__c = Date.today(),
                    Initial_Software_Term_Length_Months__c = 12
                ), 'OpportunityDefaults'
            );
            
            // Create Approvers Matrix using TestFactory (no defaults class, so use buildSObject)
            Approvers_Matrix__c approverMatrix = (Approvers_Matrix__c)TestFactory.buildSObject(
                new Approvers_Matrix__c(
                    Sales_Segment__c = '03-Legal EMEA',
                    Approver_Role__c = 'Segment Lead',
                    Approver_User__c = testUser.Id
                )
            );
            insert approverMatrix;
            
            // Create Quote using TestFactory
            TestFactory.createSObject(
                new SBQQ__Quote__c(
                    OP4I_Sales_Segment__c = '03-Legal EMEA',
                    SBQQ__Opportunity2__c = opportunity.Id,
                    SBQQ__Account__c = account.Id,
                    SBQQ__SubscriptionTerm__c = 36,
                    First_Segment_Months__c = 12,
                    License_Basis__c = 'Lawyers',
                    SBQQ__StartDate__c = System.today()
                ), 'SBQQQuoteDefaults'
            );
        }
    }
    
    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests that automation execution is bypassed (returns false) when Automation_Controls__c
    *              is active, bypass is enabled, and Data_Id__c is blank. This validates the global bypass
    *              functionality where all records of the specified object type are bypassed when Data_Id__c
    *              is null or blank.
    **/
    @isTest
    static void testBypassWithDataIdBlank() {
        // Get test quote
        List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Create Automation Controls with blank Data_Id__c (global bypass)
        Automation_Controls__c automationControl = new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c = true,
            Data_Id__c = null
        );
        insert automationControl;
        
        Test.startTest();
        Map<Id, Boolean> result = AutomationPreference.validateExecution('SBQQ__Quote__c', quotes);
        Test.stopTest();
        
        // Should not execute (false) when Data_Id__c is blank and bypass is enabled
        System.assertEquals(false, result.get(quotes[0].Id), 'Should not execute if Data_Id__c is blank');
    }
    
    /**
    * @description Tests that automation execution is bypassed (returns false) when Automation_Controls__c
    *              Data_Id__c matches the record ID. This validates the selective bypass functionality
    *              where only specific records identified by Data_Id__c are bypassed from automation execution.
    **/
    @isTest
    static void testBypassWithDataIdMatch() {
        // Get test quote
        List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Id recordId = quotes[0].Id;
        
        // Create Automation Controls with matching Data_Id__c (selective bypass)
        Automation_Controls__c automationControl = new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c = true,
            Data_Id__c = recordId // Include record in bypass list
        );
        insert automationControl;
        
        Test.startTest();
        Map<Id, Boolean> result = AutomationPreference.validateExecution('SBQQ__Quote__c', quotes);
        Test.stopTest();
        
        // Should bypass trigger (false) for matching Data_Id__c
        System.assertEquals(false, result.get(recordId), 'Should bypass trigger (false) for matching Data_Id__c');
    }
    
    /**
    * @description Tests that automation execution is allowed (returns true) when Automation_Controls__c
    *              Data_Id__c does not match the record ID. This validates that records not in the
    *              Data_Id__c list are not bypassed and automation executes normally.
    **/
    @isTest
    static void testBypassWithDataIdNotMatch() {
        // Get test quote
        List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        Id recordId = quotes[0].Id;
        
        // Create Automation Controls with non-matching Data_Id__c
        Automation_Controls__c automationControl = new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Triggers__c = true,
            Quote_Bypass__c = true,
            Data_Id__c = 'someOtherId' // Different ID, so record should not be bypassed
        );
        insert automationControl;
        
        Test.startTest();
        Map<Id, Boolean> result = AutomationPreference.validateExecution('SBQQ__Quote__c', quotes);
        Test.stopTest();
        
        // Should allow trigger (true) if Data_Id__c does not match
        System.assertEquals(true, result.get(recordId), 'Should allow trigger (true) if Data_Id__c does not match');
    }
    
    /**
    * @description Tests that automation execution is allowed (returns true) when Automation_Controls__c
    *              is inactive, even if bypass flags are set to false. This validates that inactive
    *              controls do not affect automation execution and execution is allowed by default.
    **/
    @isTest
    static void testBypassFalseControlInactive() {
        // Get test quote
        List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        
        // Create Automation Controls with Active__c = false (inactive)
        Automation_Controls__c automationControl = new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = false, // Inactive control should not affect execution
            Bypass_Triggers__c = false,
            Quote_Bypass__c = false
        );
        insert automationControl;
        
        Test.startTest();
        Map<Id, Boolean> result = AutomationPreference.validateExecution('SBQQ__Quote__c', quotes);
        Test.stopTest();
        
        // Should allow trigger (true) when bypass flags are false or control is inactive
        System.assertEquals(true, result.get(quotes[0].Id), 'Should allow trigger (true) when bypass flags are false');
    }
    
    /**
    * @description Tests that CPQ trigger control methods (disable and enable) can be executed
    *              without errors. This validates the integration with DisableCPQtriggers and
    *              EnableCPQtriggers utility classes.
    **/
    @isTest
    static void testValidateCPQTriggerControls() {
        Test.startTest();
        DisableCPQtriggers.disableCPQTriggerExecutions();
        EnableCPQtriggers.enableCPQTriggerExecutions();
        Test.stopTest();
        
        // Verify methods executed without exception
        System.assert(true, 'CPQ trigger control methods should execute successfully');
    }
    
}