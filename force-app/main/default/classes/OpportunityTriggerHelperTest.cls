/**
 * @description       : Test class for OpportunityTriggerHelper
**/
@isTest
private class OpportunityTriggerHelperTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    /**
     * @description test setup
     */
    @testSetup
    static void setupTestData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Create Account
            Account activeAccount = (Account)TestFactory.buildSObject(
                new Account(
                    Name = 'Active Account', 
                    Type = AccountConstants.TYPE_CLIENT
                ), 'AccountDefaults'
            );

            Account acc2 = (Account)TestFactory.buildSObject(
                new Account(
                    Name = 'Test Account2', 
                    Type = AccountConstants.TYPE_CLIENT
                ), 'AccountDefaults'
            );

            Account unrelatedAccount = (Account)TestFactory.buildSObject(
                new Account(
                    Name = 'Unrelated Account', 
                    Type = AccountConstants.TYPE_CLIENT
                ), 'AccountDefaults'
            );
            //Create a test Account with Type = Prospect
            Account prospectAccount = (Account)TestFactory.buildSObject(
                new Account(
                    Name = 'Test Prospect Account', 
                    Type = AccountConstants.TYPE_PROSPECT
                ), 'AccountDefaults'
            );

            insert new List<Account>{ activeAccount, acc2, unrelatedAccount, prospectAccount };

            // Create Contract with status Active
            List<Contract> contractList = new List<Contract>();
            
            Contract activeContract = (Contract)TestFactory.buildSObject(
                new Contract(
                    Name = 'ActiveContract',
                    AccountId = activeAccount.Id,
                    StartDate = Date.today().addMonths(-12),
                    EndDate = Date.today().addMonths(12)
                ), 'ContractDefaults'
            );


            // Create Contract to be renewed (this will be cancelled)
            Contract contractToBeCancelled = (Contract)TestFactory.buildSObject(
                new Contract(
                    Name = 'ContractToBeCancelled',
                    AccountId = activeAccount.Id,
                    StartDate = Date.today().addMonths(-24),
                    EndDate = Date.today().addMonths(-12)
                ), 'ContractDefaults'
            );

            
            Contract expiredContract = (Contract)TestFactory.buildSObject(
                new Contract(
                    Name = 'ExpiredContract',
                    AccountId = acc2.Id,
                    StartDate = Date.today().addMonths(-24),
                    EndDate = Date.today().addMonths(-12)
                ), 'ContractDefaults'
            );

            Contract expiredContract2 = (Contract)TestFactory.buildSObject(
                new Contract(
                    Name = 'ExpiredContract2',
                    AccountId = prospectAccount.Id,
                    StartDate = Date.today().addMonths(-24),
                    EndDate = Date.today().addMonths(-12)
                ), 'ContractDefaults'
            );

            insert new List<Contract>{ activeContract, contractToBeCancelled, expiredContract, expiredContract2 };
            
            contractToBeCancelled.Status = ContractConstants.STATUS_INFORCE;
            contractList.add(contractToBeCancelled);
            expiredContract.Status = ContractConstants.STATUS_CANCELLED_LAPSED;
            contractList.add(expiredContract);
            activeContract.Status = ContractConstants.STATUS_INFORCE;
            contractList.add(activeContract);
            update contractList;

            // Create Opportunity (Closed Lost & Renewal)
            Opportunity opp1 = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'Renewal Opp',
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.TYPE_RENEWAL,
                    AccountId = activeAccount.Id,
                    SBQQ__RenewedContract__c = contractToBeCancelled.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'Renewal Opp'
                ), 'OpportunityDefaults'
            );

            Opportunity opp2 = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'Another Renewal',
                    StageName = OpportunityConstants.STAGE_CLOSED_LOST,
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.TYPE_RENEWAL,
                    AccountId = acc2.Id,
                    SBQQ__RenewedContract__c = expiredContract.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'Another Renewal'
                ), 'OpportunityDefaults'
            );

            Opportunity opp3 = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'Non-Triggering Opp',
                    StageName = OpportunityConstants.STAGE_PROSPECTING,
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.TYPE_RENEWAL,
                    AccountId = activeAccount.Id,
                    SBQQ__RenewedContract__c = activeContract.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'Non-Triggering Opp'
                ), 'OpportunityDefaults'
            );
            Opportunity opp4 = (Opportunity)TestFactory.buildSObject(
                new Opportunity(
                    Name = 'Triggering Opp2',
                    StageName = OpportunityConstants.STAGE_PROSPECTING,
                    CloseDate = Date.today(),
                    Deal_Type__c = OpportunityConstants.TYPE_RENEWAL,
                    AccountId = prospectAccount.Id,
                    Associated_Contract_OSA__c = expiredContract2.Id,
                    OP4I_Auto_Number_Deal_ID__c = 'Triggering Opp2'
                ), 'OpportunityDefaults'
            );
            	
            insert new List<Opportunity>{ opp1, opp2, opp3, opp4 };    

            
        }

    }

    /**
     * @description test method to test the functionality of the cancelContractAndAccounts method
     */
    @isTest
    static void testCancelContractAndAccounts() {
        // Fetch data
        Opportunity opp = getOpportunity('Renewal Opp');
        // Validate account not updated due to active contract
        Account acc = getAccount('Active Account');
        System.assertNotEquals(AccountConstants.TYPE_CLIENT_LAPSED, acc.Type, 'Account Type not set as Cancelled initially');
        // Call method under test
        Test.startTest();
            opp.StageName = OpportunityConstants.STAGE_CLOSED_LOST;
            update opp;
        Test.stopTest();

        // Validate contract status updated
        Contract updatedContract = getContract('ContractToBeCancelled');
        Assert.areEqual(ContractConstants.STATUS_CANCELLED_LAPSED, updatedContract.Status, 'Contract should be marked as Cancelled / Lapsed');
        Contract activeContract = getContract('ActiveContract');
        Assert.areNotEqual(ContractConstants.STATUS_CANCELLED_LAPSED, activeContract.Status, 'Contract should not be marked as Cancelled / Lapsed');
        
        // Validate account not updated due to active contract
        acc = getAccount('Active Account');
        Assert.areEqual(acc.Id, activeContract.AccountId, 'Account should not be updated');
        Assert.areNotEqual(AccountConstants.TYPE_CLIENT_LAPSED, acc.Type, 'Account type should not change when active contracts exist');
    }

    /**
     * @description test method to test the functionality of the cancelContractAndAccounts method
     */
    @isTest
    static void testAccountTypeUpdateWhenNoActiveContracts() {
        // Create Opportunity
        Opportunity oppAnother = getOpportunity('Non-Triggering Opp');

        // Call method
        Test.startTest();
            oppAnother.StageName = OpportunityConstants.STAGE_CLOSED_LOST;
            update oppAnother;
        Test.stopTest();

        // Assert account is updated
        Account updatedAcc = getAccount('Test Account2');
        Assert.areEqual(AccountConstants.TYPE_CLIENT_LAPSED, updatedAcc.Type, 'Account should be marked as Cancelled / Lapsed');
    }

    /**
     * @description test method to test the functionality of the cancelContractAndAccounts method
     */
    @isTest
    static void testNoUpdateWhenConditionsNotMet() {
        // Opportunity that doesn't meet the condition (e.g., StageName != Closed Lost)
        Opportunity opp = getOpportunity('Non-Triggering Opp');

        Test.startTest();
            update opp;
        Test.stopTest();

        // Validate contract and account unchanged
        Account checkAcc = getAccount('Unrelated Account');
        Contract checkCon = getContract('ActiveContract');

        Assert.areEqual(AccountConstants.TYPE_CLIENT, checkAcc.Type, 'Account type should remain unchanged');
        Assert.areEqual(ContractConstants.STATUS_INFORCE, checkCon.Status, 'Contract status should remain unchanged');
    }

    /**
     * @description test method to test the functionality of the cancelContractAndAccounts method when the Opportunity Stage is Closed Won
     */
    @isTest
    static void testUpdateAccountTypeWhenOpportunityClosedWon() {

        Opportunity opp = getOpportunity('Triggering Opp2');
        
        Test.startTest();
            opp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
            update opp;
        Test.stopTest();

        Account updatedAcc = getAccount('Test Prospect Account');
        Assert.areEqual(AccountConstants.TYPE_CLIENT, updatedAcc.Type, 'Account type should have been updated to Client');

        Contract updatedContract = getContract('ExpiredContract2');
        Assert.areEqual(ContractConstants.STATUS_INFORCE, updatedContract.Status, 'Contract status should have been updated to In Force');
    }

    /**
     * @description test method to test close date setting of renewal opportunities
     */
    @isTest
    static void processOpportunitiesTest() {
        Opportunity opp = getOpportunity('Renewal Opp');
        // Create renewal quote to establish Renewal_Start_Date__c relationship
        TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = opp.Id,
                SBQQ__Type__c = 'Renewal',
                SBQQ__StartDate__c = Date.today()
            ), 'SBQQQuoteDefaults'
        );
        Test.startTest();
        opp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        update opp;
        Test.stopTest();
        opp = getOpportunity('Renewal Opp');
        Assert.areEqual(opp.Renewal_Start_Date__c.addDays(-30), opp.CloseDate, 'Close date should be -30 Renewal Date');

        delete opp;
    }
    
    /**
     * @description test method to validate handleAmendedOpportunities is invoked
     */
    @isTest
    static void testHandleAmendedOpportunities() {
        
        // Insert Opportunity with initial Stage (simulate as old)
        Opportunity opp = new Opportunity(
            Name = 'Amended Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Deal_Type__c = 'Add-On', // assume this passes isAmendmentOpp and isAddOnOpp
            RecordTypeId = getOpportunityRecordTypeId(),
            OP4I_Auto_Number_Deal_ID__c = 'Amended Opp',
            Type = 'Amendment'
        );
        insert opp;
    
        // Update to Closed Won
        opp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
    
        Test.startTest();
            update opp;
        Test.stopTest();
    
        // Validate that the opportunity was updated successfully and is now Closed Won
        Opportunity updatedOpp = getOpportunityById(opp.Id);
        Assert.areEqual(OpportunityConstants.STAGE_CLOSED_WON, updatedOpp.StageName, 'Opportunity should be Closed Won');
        Assert.areEqual('Add-On', updatedOpp.Deal_Type__c, 'Deal Type should remain Add-On');
    }
    
    @isTest
    static void testUpdateNYMYOpp() {
        Id oppRecordTypeId = getOpportunityRecordTypeId();
    
        // Create Account
        Account activeAccount = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account', 
                Type = AccountConstants.TYPE_CLIENT
            ), 'AccountDefaults'
        );

        // Create Contract to be superseded
        Contract oldContract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'ActiveContract',
                AccountId = activeAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(12)
            ), 'ContractDefaults'
        );
    
        // Create NYMY Opportunity (not Closed Won)
        Opportunity nymyOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Opp',
                StageName = 'Negotiation',
                CloseDate = Date.today().addDays(30),
                Deal_Type__c = 'NextYear_MultiYear',
                RecordTypeId = oppRecordTypeId,
                Type = 'New Customer',
                Associated_Contract_OSA__c = oldContract.Id
            ), 'OpportunityDefaults'
        );
    
        // Create Amended Opportunity with same Associated Contract
        Opportunity amendedOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Amended Opp',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = 'Add-On',
                RecordTypeId = oppRecordTypeId,
                Type = 'Amendment',
                Associated_Contract_OSA__c = oldContract.Id
            ), 'OpportunityDefaults'
        );
        
        // Create Product and PricebookEntry
        Product2 prod = (Product2)TestFactory.createSObject(
            new Product2(
                Name = 'Testproduct2',
                IsActive = true,
                ProductCode = 'TP001'
            ), 'ProductDefaults'
        );
    
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe;
    
        // Create OpportunityLineItem with mocked quote line relationship
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = amendedOpp.Id,
            Quantity = 1,
            PricebookEntryId = pbe.Id,
            TotalPrice = 100
        );
        insert oli;
    
        Test.startTest();
            NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();
    
        // Assert that cloned OLI exists for NYMY Opportunity
        List<OpportunityLineItem> oliList = getOpportunityLineItemsByOpportunityId(nymyOpp.Id);
        System.assert(!oliList.isEmpty(), 'Expected cloned OpportunityLineItem to be inserted for NYMY Opportunity');
    }
    
    /**
     * @description BIZ-77189 - Test NYMY line merging for Uplift amendment deal type
     *              When an Uplift amendment closes won with an existing open NYMY, 
     *              lines should be added to existing NYMY (not create new NYMY)
     */
    @isTest
    static void testUpdateNYMYOppUpliftAmendment() {
        // Create Automation Controls to bypass triggers
        TestFactory.createSObject(
            new Automation_Controls__c(
                Bypass_Flows__c = true,
                Bypass_Triggers__c = true,
                Active__c = true,
                SetupOwnerId = UserInfo.getUserId()
            )
        );
        
        Id oppRecordTypeId = getOpportunityRecordTypeId();
    
        Account testAccount = (Account)TestFactory.createSObject(
            new Account(Name = 'Test Account Uplift', Type = AccountConstants.TYPE_CLIENT), 
            'AccountDefaults'
        );

        Contract testContract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'UpliftContract',
                AccountId = testAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(24)
            ), 'ContractDefaults'
        );
    
        // Create existing open NYMY Opportunity
        Opportunity nymyOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Opp Uplift',
                StageName = 'Selected',
                CloseDate = Date.today().addDays(30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                RecordTypeId = oppRecordTypeId,
                Type = 'New Customer',
                Associated_Contract_OSA__c = testContract.Id
            ), 'OpportunityDefaults'
        );
    
        // Create Uplift Amendment Opportunity
        Opportunity upliftOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Uplift Amendment',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_UPLIFT,
                RecordTypeId = oppRecordTypeId,
                Type = OpportunityConstants.TYPE_AMENDMENT,
                Associated_Contract_OSA__c = testContract.Id
            ), 'OpportunityDefaults'
        );
        
        Product2 prod = (Product2)TestFactory.createSObject(
            new Product2(Name = 'Uplift Product', IsActive = true, ProductCode = 'UPL001'), 
            'ProductDefaults'
        );
    
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 200.00,
            IsActive = true
        );
        insert pbe;
    
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = upliftOpp.Id,
            Quantity = 1,
            PricebookEntryId = pbe.Id,
            TotalPrice = 200
        );
        insert oli;
    
        Test.startTest();
            NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ upliftOpp.Id });
        Test.stopTest();
    
        // Assert lines were merged to existing NYMY
        List<OpportunityLineItem> nymyLines = getOpportunityLineItemsByOpportunityId(nymyOpp.Id);
        System.assert(!nymyLines.isEmpty(), 'BIZ-77189: Uplift amendment lines should be merged into existing NYMY opportunity');
    }
    
    /**
     * @description BIZ-77189 - Test NYMY line merging for Expansion amendment deal type
     *              When an Expansion amendment closes won with an existing open NYMY, 
     *              lines should be added to existing NYMY (not create new NYMY)
     */
    @isTest
    static void testUpdateNYMYOppExpansionAmendment() {
        // Create Automation Controls to bypass triggers
        TestFactory.createSObject(
            new Automation_Controls__c(
                Bypass_Flows__c = true,
                Bypass_Triggers__c = true,
                Active__c = true,
                SetupOwnerId = UserInfo.getUserId()
            )
        );
        
        Id oppRecordTypeId = getOpportunityRecordTypeId();
    
        Account testAccount = (Account)TestFactory.createSObject(
            new Account(Name = 'Test Account Expansion', Type = AccountConstants.TYPE_CLIENT), 
            'AccountDefaults'
        );

        Contract testContract = (Contract)TestFactory.createSObject(
            new Contract(
                Name = 'ExpansionContract',
                AccountId = testAccount.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(24)
            ), 'ContractDefaults'
        );
    
        // Create existing open NYMY Opportunity
        Opportunity nymyOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Opp Expansion',
                StageName = 'Selected',
                CloseDate = Date.today().addDays(30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                RecordTypeId = oppRecordTypeId,
                Type = 'New Customer',
                Associated_Contract_OSA__c = testContract.Id
            ), 'OpportunityDefaults'
        );
    
        // Create Expansion Amendment Opportunity
        Opportunity expansionOpp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Expansion Amendment',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_EXPANSION,
                RecordTypeId = oppRecordTypeId,
                Type = OpportunityConstants.TYPE_AMENDMENT,
                Associated_Contract_OSA__c = testContract.Id
            ), 'OpportunityDefaults'
        );
        
        Product2 prod = (Product2)TestFactory.createSObject(
            new Product2(Name = 'Expansion Product', IsActive = true, ProductCode = 'EXP001'), 
            'ProductDefaults'
        );
    
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 300.00,
            IsActive = true
        );
        insert pbe;
    
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = expansionOpp.Id,
            Quantity = 1,
            PricebookEntryId = pbe.Id,
            TotalPrice = 300
        );
        insert oli;
    
        Test.startTest();
            NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ expansionOpp.Id });
        Test.stopTest();
    
        // Assert lines were merged to existing NYMY
        List<OpportunityLineItem> nymyLines = getOpportunityLineItemsByOpportunityId(nymyOpp.Id);
        System.assert(!nymyLines.isEmpty(), 'BIZ-77189: Expansion amendment lines should be merged into existing NYMY opportunity');
    }
    
    /**
     * @description BIZ-77189 - Test that getAmendedOpps correctly identifies Uplift amendments
     */
    @isTest
    static void testGetAmendedOppsUpliftDealType() {
        Opportunity upliftOpp = new Opportunity(
            Name = 'Uplift Amendment Test',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Deal_Type__c = OpportunityConstants.DEAL_TYPE_UPLIFT,
            RecordTypeId = getOpportunityRecordTypeId(),
            Type = OpportunityConstants.TYPE_AMENDMENT,
            OP4I_Auto_Number_Deal_ID__c = 'UpliftAmendTest'
        );
        insert upliftOpp;
        
        // Update to Closed Won
        upliftOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        
        Test.startTest();
            update upliftOpp;
        Test.stopTest();
        
        // Verify isAddOnOpp returns true for Uplift
        Opportunity verifyOpp = getOpportunityById(upliftOpp.Id);
        System.assertEquals(true, OpportunityUtil.isAddOnOpp(verifyOpp), 
            'BIZ-77189: isAddOnOpp should return true for Uplift deal type');
    }
    
    /**
     * @description BIZ-77189 - Test that getAmendedOpps correctly identifies Expansion amendments
     */
    @isTest
    static void testGetAmendedOppsExpansionDealType() {
        Opportunity expansionOpp = new Opportunity(
            Name = 'Expansion Amendment Test',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Deal_Type__c = OpportunityConstants.DEAL_TYPE_EXPANSION,
            RecordTypeId = getOpportunityRecordTypeId(),
            Type = OpportunityConstants.TYPE_AMENDMENT,
            OP4I_Auto_Number_Deal_ID__c = 'ExpansionAmendTest'
        );
        insert expansionOpp;
        
        // Update to Closed Won
        expansionOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        
        Test.startTest();
            update expansionOpp;
        Test.stopTest();
        
        // Verify isAddOnOpp returns true for Expansion
        Opportunity verifyOpp = getOpportunityById(expansionOpp.Id);
        System.assertEquals(true, OpportunityUtil.isAddOnOpp(verifyOpp), 
            'BIZ-77189: isAddOnOpp should return true for Expansion deal type');
    }

    /**
     * @description BIZ-80539 - Test that renewal opportunities are set to Qualify on insert
     *              unless already in a closed stage, and non-renewal opps are unaffected
     */
    @isTest
    static void testSetRenewalStageToQualify() {
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Renewal Opp',
                StageName = OpportunityConstants.STAGE_PRE_SHOPPING,
                CloseDate = Date.today(),
                Type = OpportunityConstants.TYPE_RENEWAL,
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_RENEWAL,
                OP4I_Auto_Number_Deal_ID__c = 'RenewalOpp'
            ),
            new Opportunity(
                Name = 'Non-Renewal Opp',
                StageName = OpportunityConstants.STAGE_PRE_SHOPPING,
                CloseDate = Date.today(),
                Type = 'New Customer',
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NEWSOFTWARE,
                OP4I_Auto_Number_Deal_ID__c = 'NonRenewalOpp'
            ),
            new Opportunity(
                Name = 'Closed Renewal Opp',
                StageName = OpportunityConstants.STAGE_CLOSED_LOST,
                CloseDate = Date.today(),
                Type = OpportunityConstants.TYPE_RENEWAL,
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_RENEWAL,
                OP4I_Auto_Number_Deal_ID__c = 'ClosedRenewalOpp'
            )
        };

        Test.startTest();
            OpportunityTriggerHelper.setRenewalStageToQualify(opps);
        Test.stopTest();

        Assert.areEqual(OpportunityConstants.STAGE_QUALIFY, opps[0].StageName,
            'BIZ-80539: Renewal opportunity should be set to Qualify');
        Assert.areEqual(OpportunityConstants.STAGE_PRE_SHOPPING, opps[1].StageName,
            'BIZ-80539: Non-renewal opportunity should keep its original stage');
        Assert.areEqual(OpportunityConstants.STAGE_CLOSED_LOST, opps[2].StageName,
            'BIZ-80539: Renewal in a closed stage should not be overridden');
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/

    /**
     * @description Gets the Opportunity Record Type Id using RecordTypeUtil
     * @return Id - Record Type Id for Sales_Legal Opportunity
     */
    private static Id getOpportunityRecordTypeId() {
        return RecordTypeUtil.getRecordTypeId(Opportunity.SObjectType, 'Sales_Legal');
    }
    
    /** 
     * @description getter for Account by name
     * @param name
     * @return Account
     */
    private static Account getAccount(String name) {
        List<Account> accounts = [SELECT Id, Name, Type FROM Account WHERE Name = :name LIMIT 1];
        return accounts.isEmpty() ? null : accounts[0];
    }

    /**
     * @description getter for Opportunity by OP4I Auto Number Deal ID
     * @param op4iNum
     * @return Opportunity
     */
    private static Opportunity getOpportunity(String op4iNum) {
        List<Opportunity> opportunities = [
            SELECT Id, AccountId, CloseDate, Renewal_Start_Date__c 
            FROM Opportunity 
            WHERE OP4I_Auto_Number_Deal_ID__c = :op4iNum 
            LIMIT 1
        ];
        return opportunities.isEmpty() ? null : opportunities[0];
    }
    
    /**
     * @description getter for Opportunity by Id
     * @param oppId
     * @return Opportunity
     */
    private static Opportunity getOpportunityById(Id oppId) {
        List<Opportunity> opportunities = [
            SELECT Id, StageName, Deal_Type__c 
            FROM Opportunity 
            WHERE Id = :oppId 
            LIMIT 1
        ];
        return opportunities.isEmpty() ? null : opportunities[0];
    }

    /**
     * @description getter for Contract by name
     * @param name
     * @return Contract
     */
    private static Contract getContract(String name) {
        List<Contract> contracts = [SELECT Id, Status, AccountId FROM Contract WHERE Name = :name LIMIT 1];
        return contracts.isEmpty() ? null : contracts[0];
    }
    
    /**
     * @description getter for OpportunityLineItems by Opportunity Id
     * @param oppId
     * @return List<OpportunityLineItem>
     */
    private static List<OpportunityLineItem> getOpportunityLineItemsByOpportunityId(Id oppId) {
        return [
            SELECT Id, OpportunityId, Original_Opportunity_Product_Id__c 
            FROM OpportunityLineItem 
            WHERE OpportunityId = :oppId
        ];
    }
}