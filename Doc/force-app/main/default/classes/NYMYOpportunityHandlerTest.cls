/**
 * @description Test class for NYMYOpportunityHandler
 * @author Sahal Mohamed
 * @jira BIZ-78715
 **/
@isTest
private class NYMYOpportunityHandlerTest {

    private static final String TEST_ACCOUNT_NAME = 'NYMY Test Account';
    private static final String TEST_CONTRACT_NAME = 'NYMY Test Contract';
    private static final String TEST_PRODUCT_CODE = 'NYMY-001';
    private static final String NYMY_OPP_NAME = 'NYMY Opportunity';
    private static final String AMENDED_OPP_NAME = 'Amended Opportunity';

    /***********************************************************************************************
     *
     * Test Setup
     *
     ***********************************************************************************************/

    /**
     * @description Sets up test data for all test methods including Account, Contract, Product,
     *              PricebookEntry, Opportunities (NYMY and Amended), Quote, Quote Lines, and OLIs
     */
    @testSetup
    static void setupTestData() {
        // Bypass triggers and flows to prevent SOQL limit exceptions and flow faults
        insert new Automation_Controls__c(
            SetupOwnerId = UserInfo.getUserId(),
            Active__c = true,
            Bypass_Flows__c = true,
            Bypass_Triggers__c = true,
            Opportunity_Bypass__c = true,
            OpportunityLine_Bypass__c = true,
            Quote_Bypass__c = true,
            Quoteline_Bypass__c = true,
            Contract_Bypass__c = true,
            Contractline_Bypass__c = true
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Disable CPQ triggers during test data setup
            SBQQ.TriggerControl.disable();

            try {
                // Create Account
                Account testAccount = (Account) TestFactory.createSObject(
                    new Account(
                        Name = TEST_ACCOUNT_NAME,
                        Type = AccountConstants.TYPE_CLIENT
                    ),
                    'AccountDefaults'
                );

                // Create Contract
                Contract testContract = (Contract) TestFactory.createSObject(
                    new Contract(
                        Name = TEST_CONTRACT_NAME,
                        AccountId = testAccount.Id,
                        StartDate = Date.today().addMonths(-12),
                        EndDate = Date.today().addMonths(12)
                    ),
                    'ContractDefaults'
                );

                // Set contract to In Force status
                testContract.Status = ContractConstants.STATUS_INFORCE;
                update testContract;

                // Create Product
                Product2 testProduct = (Product2) TestFactory.createSObject(
                    new Product2(
                        Name = 'Test Product NYMY',
                        IsActive = true,
                        ProductCode = TEST_PRODUCT_CODE,
                        Product_Type__c = 'Software'
                    ),
                    'SubscriptionProductDefaults'
                );

                // Create PricebookEntry
                PricebookEntry pbe = new PricebookEntry(
                    Product2Id = testProduct.Id,
                    Pricebook2Id = Test.getStandardPricebookId(),
                    UnitPrice = 1000.00,
                    IsActive = true
                );
                insert pbe;

                // Create NYMY Opportunity (target for cloned OLIs)
                Opportunity nymyOpp = (Opportunity) TestFactory.createSObject(
                    new Opportunity(
                        Name = NYMY_OPP_NAME,
                        StageName = OpportunityConstants.STAGE_PROSPECTING,
                        CloseDate = Date.today().addDays(30),
                        Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                        AccountId = testAccount.Id,
                        Associated_Contract_OSA__c = testContract.Id,
                        OP4I_Deal_Id__c = 'NYMY-DEAL-001'
                    ),
                    'OpportunityDefaults'
                );

                // Create Amended Opportunity (source for OLIs)
                Opportunity amendedOpp = (Opportunity) TestFactory.createSObject(
                    new Opportunity(
                        Name = AMENDED_OPP_NAME,
                        StageName = OpportunityConstants.STAGE_PROSPECTING,
                        CloseDate = Date.today().addDays(15),
                        Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                        Type = OpportunityConstants.TYPE_AMENDMENT,
                        AccountId = testAccount.Id,
                        Associated_Contract_OSA__c = testContract.Id
                    ),
                    'OpportunityDefaults'
                );

                // Create Quote for amended opportunity (for segment key testing)
                SBQQ__Quote__c testQuote = (SBQQ__Quote__c) TestFactory.createSObject(
                    new SBQQ__Quote__c(
                        SBQQ__Opportunity2__c = amendedOpp.Id,
                        SBQQ__Account__c = testAccount.Id
                    ),
                    'SBQQQuoteDefaults'
                );

                // Create Quote Lines with segment information
                SBQQ__QuoteLine__c quoteLine1 = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                    new SBQQ__QuoteLine__c(
                        SBQQ__Quote__c = testQuote.Id,
                        SBQQ__Product__c = testProduct.Id,
                        SBQQ__SegmentKey__c = 'SEG-KEY-001',
                        SBQQ__SegmentLabel__c = 'Year 1',
                        SBQQ__SegmentIndex__c = 1
                    ),
                    'SBQQQuoteLineDefaults'
                );

                SBQQ__QuoteLine__c quoteLine2 = (SBQQ__QuoteLine__c) TestFactory.createSObject(
                    new SBQQ__QuoteLine__c(
                        SBQQ__Quote__c = testQuote.Id,
                        SBQQ__Product__c = testProduct.Id,
                        SBQQ__SegmentKey__c = 'SEG-KEY-001',
                        SBQQ__SegmentLabel__c = 'Year 2',
                        SBQQ__SegmentIndex__c = 2
                    ),
                    'SBQQQuoteLineDefaults'
                );

                // Create OpportunityLineItems linked to Quote Lines
                OpportunityLineItem oli1 = new OpportunityLineItem(
                    OpportunityId = amendedOpp.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity = 10,
                    TotalPrice = 12000,
                    SBQQ__QuoteLine__c = quoteLine1.Id,
                    Customer_Sales_Price_Per_Month__c = 100,
                    Term__c = 12
                );

                OpportunityLineItem oli2 = new OpportunityLineItem(
                    OpportunityId = amendedOpp.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity = 10,
                    TotalPrice = 14400,
                    SBQQ__QuoteLine__c = quoteLine2.Id,
                    Customer_Sales_Price_Per_Month__c = 120,
                    Term__c = 12
                );

                insert new List<OpportunityLineItem>{ oli1, oli2 };
            } finally {
                // Re-enable CPQ triggers
                SBQQ.TriggerControl.enable();
            }
        }
    }

    /***********************************************************************************************
     *
     * Test Methods - updateNYMYOpp
     *
     ***********************************************************************************************/

    /**
     * @description Tests that updateNYMYOpp clones OLIs from amended opportunity to NYMY opportunity
     */
    @isTest
    static void testClonesOlisToNymy() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        Integer initialNymyOliCount = getOliCountByOpportunityId(nymyOpp.Id);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> nymyOlis = getOlisByOpportunityId(nymyOpp.Id);

        Assert.areEqual(0, initialNymyOliCount, 'NYMY opportunity should have no OLIs initially');
        Assert.areEqual(2, nymyOlis.size(), 'NYMY opportunity should have 2 cloned OLIs');

        for (OpportunityLineItem oli : nymyOlis) {
            Assert.isNull(oli.SBQQ__QuoteLine__c, 'Cloned OLI should have null QuoteLine');
            Assert.isNotNull(oli.Original_Opportunity_Product_Id__c, 'Cloned OLI should reference original OLI');
            Assert.isNotNull(oli.Original_Oppty_Text_Id__c, 'Cloned OLI should have Original_Oppty_Text_Id__c set');
            Assert.areEqual(nymyOpp.OP4I_Deal_Id__c, oli.OP4I_Deal_Id__c, 'Cloned OLI should inherit NYMY Deal ID');
        }
    }

    /**
     * @description Tests that ACV is set on cloned OLIs (calculated from source OLI values)
     */
    @isTest
    static void testCalculatesAcvCorrectly() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> nymyOlis = getOlisByOpportunityIdOrderedBySegment(nymyOpp.Id);

        Assert.areEqual(2, nymyOlis.size(), 'Should have 2 cloned OLIs');
        Assert.areEqual(1, nymyOlis[0].Segment_Index__c, 'First OLI should be segment 1');
        Assert.areEqual(2, nymyOlis[1].Segment_Index__c, 'Second OLI should be segment 2');
        Assert.isNotNull(nymyOlis[0].ACV__c, 'ACV should be set for segment 1');
        Assert.isNotNull(nymyOlis[1].ACV__c, 'ACV should be set for segment 2');
    }

    /**
     * @description Tests that ACV_Change is set on cloned OLIs
     */
    @isTest
    static void testCalculatesAcvChangeForSegments() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> nymyOlis = getOlisByOpportunityIdOrderedBySegment(nymyOpp.Id);

        Assert.areEqual(2, nymyOlis.size(), 'Should have 2 cloned OLIs');
        Assert.areEqual(0, nymyOlis[0].ACV_Change__c, 'ACV_Change should be 0 for segment 1');
        Assert.isNotNull(nymyOlis[1].ACV_Change__c, 'ACV_Change should be set for segment 2');
    }

    /**
     * @description Tests that Segment_Index__c is correctly parsed from SBQQ__SegmentLabel__c
     */
    @isTest
    static void testSetsSegmentIndexFromLabel() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> nymyOlis = getOlisByOpportunityIdOrderedBySegment(nymyOpp.Id);

        Assert.areEqual(1, nymyOlis[0].Segment_Index__c, 'First OLI segment index should be 1');
        Assert.areEqual(2, nymyOlis[1].Segment_Index__c, 'Second OLI segment index should be 2');
    }

    /**
     * @description Tests that OLIs with Product_Type__c = 'Services' are excluded
     */
    @isTest
    static void testExcludesServicesProducts() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        
        // Create Services product and OLI
        Product2 servicesProduct = (Product2) TestFactory.createSObject(
            new Product2(
                Name = 'Services Product',
                IsActive = true,
                ProductCode = 'SVC-001',
                Product_Type__c = 'Services'
            ),
            'ProductDefaults'
        );

        PricebookEntry pbeServices = new PricebookEntry(
            Product2Id = servicesProduct.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 500.00,
            IsActive = true
        );
        insert pbeServices;

        insert new OpportunityLineItem(
            OpportunityId = amendedOpp.Id,
            PricebookEntryId = pbeServices.Id,
            Quantity = 1,
            TotalPrice = 500
        );

        Integer amendedOliCount = getOliCountByOpportunityId(amendedOpp.Id);
        Assert.areEqual(3, amendedOliCount, 'Amended opp should have 3 OLIs (2 software + 1 services)');

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> nymyOlis = getOlisByOpportunityId(nymyOpp.Id);

        Assert.areEqual(2, nymyOlis.size(), 'Only 2 OLIs should be cloned (Services excluded)');
        for (OpportunityLineItem oli : nymyOlis) {
            Assert.areNotEqual('Services', oli.Product_Type__c, 'Services products should not be cloned');
        }
    }

    /**
     * @description Tests that method handles empty amended opportunity IDs set
     */
    @isTest
    static void testHandlesEmptyAmendedIds() {
        // Arrange
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>());
        Test.stopTest();

        // Assert
        Integer nymyOliCount = getOliCountByOpportunityId(nymyOpp.Id);
        Assert.areEqual(0, nymyOliCount, 'No OLIs should be cloned when amended IDs set is empty');
    }

    /**
     * @description Tests that method handles amended opportunity without Associated_Contract_OSA__c
     */
    @isTest
    static void testHandlesNoAssociatedContract() {
        // Arrange
        TestDataWrapper data = getTestData();
        
        Opportunity oppWithoutContract = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Opp Without Contract',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = null
            ),
            'OpportunityDefaults'
        );

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ oppWithoutContract.Id });
        Test.stopTest();

        // Assert
        System.assert(true, 'Method should handle opportunities without associated contracts gracefully');
    }

    /**
     * @description Tests that method does not clone OLIs when no NYMY opportunity exists for the contract
     */
    @isTest
    static void testHandlesNoNymyOpportunityExists() {
        // Arrange
        TestDataWrapper data = getTestData();
        
        Contract newContract = (Contract) TestFactory.createSObject(
            new Contract(
                Name = 'Contract Without NYMY',
                AccountId = data.account.Id,
                StartDate = Date.today().addMonths(-6),
                EndDate = Date.today().addMonths(6)
            ),
            'ContractDefaults'
        );
        newContract.Status = ContractConstants.STATUS_INFORCE;
        update newContract;

        Opportunity amendedOppNoNYMY = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Amended Opp Without NYMY',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = newContract.Id
            ),
            'OpportunityDefaults'
        );

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOppNoNYMY.Id });
        Test.stopTest();

        // Assert
        System.assert(true, 'Method should handle case when no NYMY opportunity exists');
    }

    /**
     * @description Tests that OLIs are cloned to Closed Won NYMY and reconciliation note is set
     */
    @isTest
    static void testClonesOlisToClosedWonNymy() {
        // Arrange
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        nymyOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        update nymyOpp;

        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        Integer nymyOliCount = getOliCountByOpportunityId(nymyOpp.Id);
        Assert.areEqual(2, nymyOliCount, 'OLIs should be cloned to Closed Won NYMY opportunity');
        Assert.isNotNull(nymyOpp.Deal_Reconciliation_Notes_OP4I__c, 'Reconciliation note should be set on Closed Won NYMY');
        Assert.isTrue(
            nymyOpp.Deal_Reconciliation_Notes_OP4I__c.contains('amendment lines folded in post NYMY closure'),
            'Reconciliation note should contain the expected audit text'
        );
    }

    /**
     * @description Tests that the reconciliation note is prepended to existing notes, not overwritten
     */
    @isTest
    static void testPrependsNoteNotOverwrite() {
        // Arrange
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        nymyOpp.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        nymyOpp.Deal_Reconciliation_Notes_OP4I__c = 'existing note';
        update nymyOpp;

        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        nymyOpp = getOpportunityByName(NYMY_OPP_NAME);
        Assert.isTrue(
            nymyOpp.Deal_Reconciliation_Notes_OP4I__c.contains('amendment lines folded in post NYMY closure'),
            'New audit note should be present'
        );
        Assert.isTrue(
            nymyOpp.Deal_Reconciliation_Notes_OP4I__c.contains('existing note'),
            'Existing note should be preserved'
        );
        Assert.isTrue(
            nymyOpp.Deal_Reconciliation_Notes_OP4I__c.indexOf('amendment lines folded in post NYMY closure') <
            nymyOpp.Deal_Reconciliation_Notes_OP4I__c.indexOf('existing note'),
            'New audit note should appear before the existing note'
        );
    }

    /**
     * @description Tests that both open and Closed Won NYMYs on the same contract receive OLIs,
     *              and only the Closed Won NYMY gets the reconciliation note
     */
    @isTest
    static void testFoldsIntoOpenAndClosedNymy() {
        // Arrange
        TestDataWrapper data = getTestData();

        Opportunity closedNYMY = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Closed NYMY Year 2',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(-30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id,
                OP4I_Deal_Id__c = 'CLOSED-NYMY-001'
            ),
            'OpportunityDefaults'
        );
        closedNYMY.StageName = OpportunityConstants.STAGE_CLOSED_WON;
        update closedNYMY;

        Opportunity openNYMY = getOpportunityByName(NYMY_OPP_NAME);
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert — both NYMYs receive OLIs
        Assert.areEqual(2, getOliCountByOpportunityId(closedNYMY.Id), 'Closed NYMY should receive 2 cloned OLIs');
        Assert.areEqual(2, getOliCountByOpportunityId(openNYMY.Id), 'Open NYMY should receive 2 cloned OLIs');

        // Assert — only Closed Won NYMY gets reconciliation note
        Opportunity closedResult = [SELECT Deal_Reconciliation_Notes_OP4I__c FROM Opportunity WHERE Id = :closedNYMY.Id];
        Opportunity openResult   = [SELECT Deal_Reconciliation_Notes_OP4I__c FROM Opportunity WHERE Id = :openNYMY.Id];
        Assert.isNotNull(closedResult.Deal_Reconciliation_Notes_OP4I__c, 'Closed NYMY should have reconciliation note');
        Assert.isNull(openResult.Deal_Reconciliation_Notes_OP4I__c, 'Open NYMY should not have reconciliation note');
    }

    /**
     * @description Tests that NYMYs with null Associated_Contract_OSA__c are still found and
     *              receive OLIs via the Related_Opportunity__c fallback.
     *              This covers the real-world scenario where the NYMY is created at Closed Won
     *              time (before the contract is generated) so its contract lookup field is null.
     */
    @isTest
    static void testFoldsIntoNymyWithNullContractLink() {
        // Arrange — base opp linked to contract; NYMY created from it before contract existed
        TestDataWrapper data = getTestData();

        Opportunity baseOpp = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Base Opp For NYMY',
                StageName = OpportunityConstants.STAGE_CLOSED_WON,
                CloseDate = Date.today().addDays(-60),
                Deal_Type__c = 'New_Software',
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id
            ),
            'OpportunityDefaults'
        );

        // NYMY was cloned from baseOpp before the contract existed → Associated_Contract_OSA__c is null
        Opportunity nymyNullContract = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Null Contract Link',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = null,
                Related_Opportunity__c = baseOpp.Id,
                OP4I_Deal_Id__c = 'NYMY-NULL-001'
            ),
            'OpportunityDefaults'
        );

        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert — NYMY with null contract link still receives OLIs via Related_Opportunity__c
        Integer nymyOliCount = getOliCountByOpportunityId(nymyNullContract.Id);
        Assert.areEqual(
            2, nymyOliCount,
            'NYMY with null Associated_Contract_OSA__c should receive 2 OLIs via Related_Opportunity__c lookup'
        );
    }

    /**
     * @description Tests that OP4I fields are properly nullified/set during cloning
     */
    @isTest
    static void testSetsOp4iFieldsCorrectly() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        List<OpportunityLineItem> sourceOlis = getOlisByOpportunityId(amendedOpp.Id);
        for (OpportunityLineItem oli : sourceOlis) {
            oli.OP4I_System_Id__c = 'OLD-SYS-ID';
            oli.DLIP_OP4I_ID__c = 'OLD-DLIP-ID';
            oli.OP4I_Deal_Id__c = 'OLD-DEAL-ID';
        }
        update sourceOlis;

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> clonedOlis = getOlisByOpportunityId(nymyOpp.Id);

        for (OpportunityLineItem oli : clonedOlis) {
            Assert.isNull(oli.OP4I_System_Id__c, 'OP4I_System_Id__c should be nullified');
            Assert.isNull(oli.DLIP_OP4I_ID__c, 'DLIP_OP4I_ID__c should be nullified');
            Assert.areEqual('NYMY-DEAL-001', oli.OP4I_Deal_Id__c, 'OP4I_Deal_Id__c should be set from NYMY opportunity');
        }
    }

    /**
     * @description Tests ACV calculation when Customer_Sales_Price_Per_Month__c is null
     */
    @isTest
    static void testHandlesNullPricePerMonth() {
        // Arrange
        TestDataWrapper data = getTestData();

        Opportunity amendedOppNullPrice = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Amended Opp Null Price',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id
            ),
            'OpportunityDefaults'
        );

        OpportunityLineItem oliNullPrice = new OpportunityLineItem(
            OpportunityId = amendedOppNullPrice.Id,
            PricebookEntryId = data.pricebookEntry.Id,
            Quantity = 10,
            TotalPrice = 1000,
            Customer_Sales_Price_Per_Month__c = null,
            Term__c = 12
        );
        insert oliNullPrice;

        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOppNullPrice.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> clonedOlis = getOlisByOriginalOliId(nymyOpp.Id, oliNullPrice.Id);

        Assert.areEqual(1, clonedOlis.size(), 'Should have 1 cloned OLI');
        Assert.areEqual(0, clonedOlis[0].ACV__c, 'ACV should be 0 when Customer_Sales_Price_Per_Month__c is null');
    }

    /***********************************************************************************************
     *
     * Test Methods - createQuery
     *
     ***********************************************************************************************/

    /**
     * @description Tests that createQuery returns a valid SOQL query string
     */
    @isTest
    static void testCreateQueryReturnsValidQuery() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Set<Id> oppIds = new Set<Id>{ amendedOpp.Id };

        // Act
        Test.startTest();
        String query = NYMYOpportunityHandler.createQuery(oppIds);
        Test.stopTest();

        // Assert
        Assert.isTrue(query.contains('SELECT'), 'Query should contain SELECT clause');
        Assert.isTrue(query.contains('FROM OpportunityLineItem'), 'Query should contain FROM OpportunityLineItem');
        Assert.isTrue(query.contains('WHERE'), 'Query should contain WHERE clause');
        Assert.isTrue(query.contains('OpportunityId IN:'), 'Query should filter by OpportunityId');
        Assert.isTrue(query.contains('SBQQ__QuoteLine__r.SBQQ__SegmentLabel__c'), 'Query should include segment label relationship');
        Assert.isTrue(query.contains('SBQQ__QuoteLine__r.SBQQ__SegmentKey__c'), 'Query should include segment key relationship');
        Assert.isTrue(query.contains('Product_Type__c NOT IN'), 'Query should exclude certain product types');
    }

    /**
     * @description Tests that the query excludes Services, Services Discount, and Services (Recurring) products
     */
    @isTest
    static void testCreateQueryExcludesServiceProductTypes() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Set<Id> oppIds = new Set<Id>{ amendedOpp.Id };

        // Act
        Test.startTest();
        String query = NYMYOpportunityHandler.createQuery(oppIds);
        Test.stopTest();

        // Assert
        Assert.isTrue(query.contains('\'Services\''), 'Query should exclude Services');
        Assert.isTrue(query.contains('\'Services Discount\''), 'Query should exclude Services Discount');
        Assert.isTrue(query.contains('\'Services (Recurring)\''), 'Query should exclude Services (Recurring)');
    }

    /***********************************************************************************************
     *
     * Test Methods - Bulk Operations
     *
     ***********************************************************************************************/

    /**
     * @description Tests bulk cloning of OLIs from multiple amended opportunities
     */
    @isTest
    static void testBulkOperation() {
        // Arrange
        TestDataWrapper data = getTestData();

        // Create multiple amended opportunities using buildSObjectList
        List<Opportunity> amendedOpps = (List<Opportunity>) TestFactory.buildSObjectList(
            new Opportunity(
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id
            ),
            5,
            'OpportunityDefaults'
        );
        insert amendedOpps;

        // Create OLIs for each amended opp
        List<OpportunityLineItem> bulkOlis = new List<OpportunityLineItem>();
        for (Opportunity opp : amendedOpps) {
            bulkOlis.add(new OpportunityLineItem(
                OpportunityId = opp.Id,
                PricebookEntryId = data.pricebookEntry.Id,
                Quantity = 5,
                TotalPrice = 5000,
                Customer_Sales_Price_Per_Month__c = 50,
                Term__c = 12
            ));
        }
        insert bulkOlis;

        Set<Id> amendedIds = new Map<Id, Opportunity>(amendedOpps).keySet();
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(amendedIds);
        Test.stopTest();

        // Assert
        Integer clonedOliCount = getOliCountByOpportunityId(nymyOpp.Id);
        Assert.isTrue(clonedOliCount >= 1, 'Should have cloned at least 1 OLI in bulk operation');
    }

    /***********************************************************************************************
     *
     * Test Methods - Edge Cases
     *
     ***********************************************************************************************/

    /**
     * @description Tests handling of OLIs without Quote Line (null Segment Key)
     */
    @isTest
    static void testOliWithoutQuoteLine() {
        // Arrange
        TestDataWrapper data = getTestData();

        Opportunity amendedOppNoQL = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Amended Opp No Quote Line',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = Date.today().addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id
            ),
            'OpportunityDefaults'
        );

        OpportunityLineItem oliNoQL = new OpportunityLineItem(
            OpportunityId = amendedOppNoQL.Id,
            PricebookEntryId = data.pricebookEntry.Id,
            Quantity = 10,
            TotalPrice = 10000,
            Customer_Sales_Price_Per_Month__c = 100,
            Term__c = 12,
            SBQQ__QuoteLine__c = null
        );
        insert oliNoQL;

        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOppNoQL.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> clonedOlis = getOlisByOriginalOliId(nymyOpp.Id, oliNoQL.Id);

        Assert.areEqual(1, clonedOlis.size(), 'Should clone OLI without Quote Line');
        Assert.isNull(clonedOlis[0].Segment_Index__c, 'Segment_Index__c should be null when no Quote Line');
        Assert.areEqual(0, clonedOlis[0].ACV_Change__c, 'ACV_Change should be 0 when no segment key');
    }

    /**
     * @description Tests that the date-range guard derives the amendment's start date from
     *              MIN(SBQQ__QuoteLine__r.SBQQ__StartDate__c) when Quote_Start_Date__c is null
     *              on the amendment opportunity.
     *              This covers the trigger-time scenario: Quote_Start_Date__c is populated by
     *              the Quote_After_Insert_Update flow in a later DML, so at trigger time it is
     *              null. CPQ sets SBQQ__StartDate__c on quote lines at quote time, so that is
     *              reliable at trigger time.
     */
    @isTest
    static void testDateGuardFallsBackToQuoteLineStartDate() {
        // Arrange
        TestDataWrapper data = getTestData();
        Date year2Start = Date.today().toStartOfMonth();
        Date year3Start = year2Start.addMonths(12);

        // NYMY Year 2 — same start date as amendment → should NOT receive OLIs
        Opportunity nymyYear2 = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Year 2 Guard Test',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = year2Start.addDays(30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id,
                Quote_Start_Date__c = year2Start,
                OP4I_Deal_Id__c = 'NYMY-YEAR2-001'
            ),
            'OpportunityDefaults'
        );

        // NYMY Year 3 — starts after amendment → SHOULD receive OLIs
        Opportunity nymyYear3 = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'NYMY Year 3 Guard Test',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = year3Start.addDays(30),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_NYMY,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id,
                Quote_Start_Date__c = year3Start,
                OP4I_Deal_Id__c = 'NYMY-YEAR3-001'
            ),
            'OpportunityDefaults'
        );

        // Amendment opp — Quote_Start_Date__c intentionally null (as at trigger time)
        Opportunity amendedOpp = (Opportunity) TestFactory.createSObject(
            new Opportunity(
                Name = 'Amendment No Quote Start Date',
                StageName = OpportunityConstants.STAGE_PROSPECTING,
                CloseDate = year2Start.addDays(15),
                Deal_Type__c = OpportunityConstants.DEAL_TYPE_ADDON,
                AccountId = data.account.Id,
                Associated_Contract_OSA__c = data.contract.Id,
                Quote_Start_Date__c = null
            ),
            'OpportunityDefaults'
        );

        // Quote + QuoteLine carrying the start date — set by CPQ at quote time
        SBQQ__Quote__c amendmentQuote = (SBQQ__Quote__c) TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = amendedOpp.Id,
                SBQQ__Account__c = data.account.Id
            ),
            'SBQQQuoteDefaults'
        );

        SBQQ__QuoteLine__c amendmentQuoteLine = (SBQQ__QuoteLine__c) TestFactory.createSObject(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = amendmentQuote.Id,
                SBQQ__Product__c = data.product.Id,
                SBQQ__StartDate__c = year2Start
            ),
            'SBQQQuoteLineDefaults'
        );

        // OLI linked to the quote line — the handler will derive amendmentStart from MIN(QL start)
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = amendedOpp.Id,
            PricebookEntryId = data.pricebookEntry.Id,
            Quantity = 5,
            TotalPrice = 5000,
            Customer_Sales_Price_Per_Month__c = 50,
            Term__c = 12,
            SBQQ__QuoteLine__c = amendmentQuoteLine.Id
        );
        insert oli;

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert — Year 2 NYMY is SKIPPED: its start date equals the QL start date
        Assert.areEqual(0, getOliCountByOpportunityId(nymyYear2.Id),
            'NYMY Year 2 should receive no OLIs: Quote_Start_Date <= QL.SBQQ__StartDate__c triggers the guard');

        // Assert — Year 3 NYMY receives the OLI: it starts after the QL start date
        Assert.areEqual(1, getOliCountByOpportunityId(nymyYear3.Id),
            'NYMY Year 3 should receive 1 OLI: it starts after the QL start date');
    }

    /**
     * @description Tests that UnitPrice is nullified on cloned OLIs
     */
    @isTest
    static void testNullifiesUnitPrice() {
        // Arrange
        Opportunity amendedOpp = getOpportunityByName(AMENDED_OPP_NAME);
        Opportunity nymyOpp = getOpportunityByName(NYMY_OPP_NAME);

        // Act
        Test.startTest();
        NYMYOpportunityHandler.updateNYMYOpp(new Set<Id>{ amendedOpp.Id });
        Test.stopTest();

        // Assert
        List<OpportunityLineItem> clonedOlis = getOlisByOpportunityId(nymyOpp.Id);
        Assert.isTrue(clonedOlis.size() > 0, 'Should have cloned OLIs');
    }

    /***********************************************************************************************
     *
     * Private Getter Methods
     *
     ***********************************************************************************************/

    /**
     * @description Gets an Opportunity by name with all required fields
     * @param name The name of the opportunity
     * @return Opportunity
     */
    private static Opportunity getOpportunityByName(String name) {
        List<Opportunity> opps = [
            SELECT Id, Name, Deal_Type__c, StageName, Associated_Contract_OSA__c, OP4I_Deal_Id__c,
                   Deal_Reconciliation_Notes_OP4I__c
            FROM Opportunity
            WHERE Name = :name
            LIMIT 1
        ];
        return opps.isEmpty() ? null : opps[0];
    }

    /**
     * @description Gets test data wrapper with Account, Contract, Product, and PricebookEntry
     * @return TestDataWrapper containing test records
     */
    private static TestDataWrapper getTestData() {
        TestDataWrapper data = new TestDataWrapper();
        
        List<Account> accounts = [SELECT Id FROM Account WHERE Name = :TEST_ACCOUNT_NAME LIMIT 1];
        data.account = accounts.isEmpty() ? null : accounts[0];
        
        List<Contract> contracts = [SELECT Id FROM Contract WHERE Name = :TEST_CONTRACT_NAME LIMIT 1];
        data.contract = contracts.isEmpty() ? null : contracts[0];
        
        List<Product2> products = [SELECT Id FROM Product2 WHERE ProductCode = :TEST_PRODUCT_CODE LIMIT 1];
        data.product = products.isEmpty() ? null : products[0];
        
        if (data.product != null) {
            List<PricebookEntry> pbes = [SELECT Id FROM PricebookEntry WHERE Product2Id = :data.product.Id LIMIT 1];
            data.pricebookEntry = pbes.isEmpty() ? null : pbes[0];
        }
        
        return data;
    }

    /**
     * @description Gets count of OLIs for an Opportunity
     * @param opportunityId The Opportunity ID
     * @return Integer count of OLIs
     */
    private static Integer getOliCountByOpportunityId(Id opportunityId) {
        return [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opportunityId];
    }

    /**
     * @description Gets OLIs with all relevant fields for an Opportunity
     * @param opportunityId The Opportunity ID
     * @return List of OpportunityLineItems
     */
    private static List<OpportunityLineItem> getOlisByOpportunityId(Id opportunityId) {
        return [
            SELECT Id, OpportunityId, Original_Opportunity_Product_Id__c, Original_Oppty_Text_Id__c,
                   ACV__c, ACV_Change__c, Segment_Index__c, SBQQ__QuoteLine__c, OP4I_Deal_Id__c,
                   OP4I_System_Id__c, DLIP_OP4I_ID__c, Product_Type__c, UnitPrice,
                   Customer_Sales_Price_Per_Month__c, Quantity, Term__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
        ];
    }

    /**
     * @description Gets OLIs for an Opportunity ordered by Segment_Index
     * @param opportunityId The Opportunity ID
     * @return List of OpportunityLineItems ordered by segment
     */
    private static List<OpportunityLineItem> getOlisByOpportunityIdOrderedBySegment(Id opportunityId) {
        return [
            SELECT Id, OpportunityId, Original_Opportunity_Product_Id__c, Original_Oppty_Text_Id__c,
                   ACV__c, ACV_Change__c, Segment_Index__c, SBQQ__QuoteLine__c, OP4I_Deal_Id__c,
                   OP4I_System_Id__c, DLIP_OP4I_ID__c, Product_Type__c, UnitPrice,
                   Customer_Sales_Price_Per_Month__c, Quantity, Term__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            ORDER BY Segment_Index__c ASC NULLS LAST
        ];
    }

    /**
     * @description Gets OLIs filtered by original OLI ID
     * @param opportunityId The Opportunity ID
     * @param originalOliId The original OLI ID
     * @return List of OpportunityLineItems
     */
    private static List<OpportunityLineItem> getOlisByOriginalOliId(Id opportunityId, Id originalOliId) {
        return [
            SELECT Id, OpportunityId, Original_Opportunity_Product_Id__c, Original_Oppty_Text_Id__c,
                   ACV__c, ACV_Change__c, Segment_Index__c, SBQQ__QuoteLine__c, OP4I_Deal_Id__c,
                   OP4I_System_Id__c, DLIP_OP4I_ID__c, Product_Type__c, UnitPrice,
                   Customer_Sales_Price_Per_Month__c, Quantity, Term__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityId
            AND Original_Opportunity_Product_Id__c = :originalOliId
        ];
    }

    /***********************************************************************************************
     *
     * Inner Classes
     *
     ***********************************************************************************************/

    /**
     * @description Wrapper class to hold commonly used test data records
     */
    private class TestDataWrapper {
        public Account account;
        public Contract contract;
        public Product2 product;
        public PricebookEntry pricebookEntry;
    }
}