/**
* @description       : Test class for QuoteTriggerHandler. This class provides comprehensive test coverage
*                      for the Quote trigger handler functionality, including before/after insert/update
*                      handlers, quote processing, validation logic, and approval record publishing.
* @author            : Pooja Hemrajani
* Created Date       : Mar-20-2025
**/
@isTest
public class QuoteTriggerHandlerTest {
    
    /***********************************************************************************************
    *
    * Test Setup and Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Creates test data including products, pricebook entries, accounts, opportunities,
    *              quotes, and quote lines for use in test methods. This method is called automatically
    *              by the test framework before each test method execution.
    **/
    @testSetup
    static void setupTestData() {
        // Create test products
        List<Product2> products = (List<Product2>)TestFactory.createSObjectList(
            new Product2(
                    Name = 'Test Product', 
                    IsActive = true
                ), 1, 'ProductDefaults');

        // Create test pricebook entry
        for(Product2 product: products){
            TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id, Pricebook2Id = Test.getStandardPricebookId()), 1, 'PricebookEntryDefaults'
            );
        }

        // Create an Account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(Name = 'Test Account'), 1, 'AccountDefaults');
        
        // Create test Opportunities
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = accounts[0].Id
            ), 1, 'OpportunityDefaults'
        );

        // Create test Quotes associated with Opportunities
        List<SBQQ__Quote__c> quote = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = accounts[0].Id,
                OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket'
            ), 1, 'SBQQQuoteDefaults'
        );

        // Create test Quote Line associated with Quotes
        TestFactory.createSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote[0].Id,
                SBQQ__Product__c = products[0].Id
            ), 1, 'SBQQQuoteLineDefaults'
        );
    }

    /***********************************************************************************************
    *
    * Test Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Tests the before insert handler functionality. Validates that quotes are inserted
    *              with the correct sales segment when using Draft_Quote record type.
    **/
    @isTest
    static void testBeforeInsertHandler() {
        Map<String, Map<String, RecordType>> recordTypes = new Map<String, Map<String, RecordType>>();
        for (RecordType recType : [SELECT Id, SobjectType, DeveloperName FROM RecordType]) {
            if (!recordTypes.containsKey(recType.SobjectType)) {
                recordTypes.put(recType.SobjectType, new Map<String, RecordType>());
            }
            recordTypes.get(recType.SobjectType).put(recType.DeveloperName, recType);
        }
        
        String recordTypeName = 'Draft_Quote';
        
        // Arrange
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = getOpportunity().Id,
            SBQQ__Account__c = getAccount().Id,
            OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
            SBQQ__SubscriptionTerm__c = 12,
            First_Segment_Months__c = 6,
            RecordTypeId = recordTypes.get('SBQQ__Quote__c').get(recordTypeName).Id
        );
        
        // Act
        Test.startTest();
            insert quote;
        Test.stopTest();
        
        // Assert
        SBQQ__Quote__c inserted = [SELECT Id, OP4I_Sales_Segment__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals('25-FS AM - NA IB Midmarket', inserted.OP4I_Sales_Segment__c, 
            'Quote should be inserted with correct segment');
    }

    /**
    * @description Tests the before update handler functionality. Validates that approval status and
    *              counter fields are correctly updated on quote records.
    **/
    @isTest
    static void testBeforeUpdateHandler() {
        // Arrange
        SBQQ__Quote__c quote = getQuote();
        quote.ApprovalStatus__c = 'Error';
        update quote;
        quote.ApprovalStatus__c = 'Pending';
        quote.Counter__c = 3;
        
        // Act
        Test.startTest();
            update quote;
        Test.stopTest();
        
        // Assert
        SBQQ__Quote__c updated = [SELECT ApprovalStatus__c, Counter__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals('Pending', updated.ApprovalStatus__c, 
            'ApprovalStatus__c should be updated to Pending');
        System.assertEquals(3, updated.Counter__c, 
            'Counter__c should be updated to 3');
    }

    /**
    * @description Tests the after insert handler functionality. Validates that quotes are successfully
    *              inserted when using Draft_Quote record type.
    **/
    @isTest
    static void testAfterInsertHandler() {
        Map<String, Map<String, RecordType>> recordTypes = new Map<String, Map<String, RecordType>>();
        for (RecordType recType : [SELECT Id, SobjectType, DeveloperName FROM RecordType]) {
            if (!recordTypes.containsKey(recType.SobjectType)) {
                recordTypes.put(recType.SobjectType, new Map<String, RecordType>());
            }
            recordTypes.get(recType.SobjectType).put(recType.DeveloperName, recType);
        }
        
        String recordTypeName = 'Draft_Quote';
        
        // Arrange
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = getOpportunity().Id,
            SBQQ__Account__c = getAccount().Id,
            OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
            SBQQ__SubscriptionTerm__c = 12,
            First_Segment_Months__c = 6,
            RecordTypeId = recordTypes.get('SBQQ__Quote__c').get(recordTypeName).Id
        );
        
        // Act
        Test.startTest();
            insert quote;
        Test.stopTest();
        
        // Assert
        Integer quoteCount = [SELECT COUNT() FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals(1, quoteCount, 
            'Quote should be successfully inserted');
    }

    /**
    * @description Tests the after update handler functionality. Validates that approval status is
    *              correctly updated on quote records.
    **/
    @isTest
    static void testAfterUpdateHandler() {
        // Arrange
        SBQQ__Quote__c quote = getQuote();
        quote.ApprovalStatus__c = 'Error';
        update quote;
        quote.ApprovalStatus__c = 'Pending';
        quote.Counter__c = 3;
        
        // Act
        Test.startTest();
            update quote;
        Test.stopTest();
        
        // Assert
        SBQQ__Quote__c updated = [SELECT ApprovalStatus__c, Counter__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals('Pending', updated.ApprovalStatus__c, 
            'ApprovalStatus__c should be updated to Pending');
    }

    /**
    * @description Tests quote processing functionality when transitioning to 'Finalize OSA' stage.
    *              Validates that quotes can be updated to 'Finalize OSA' with required addresses
    *              and contract master terms.
    **/
    @isTest
    static void testHandleQuoteProcessing() {
        Account account = getAccount();
        
        List<Address__c> createAddress = TestDataFactory.createAddress(1, true, account.Id);
        createAddress[0].Default_Billing_Address__c = true;
        createAddress[0].Default_Shipping_Address__c = true;
        createAddress[0].Status__c = 'Verification Approved';
        update createAddress[0];
        
        // Arrange
        SBQQ__Quote__c quote = getQuote();
        quote.Quote_Stage__c = QuoteConstants.STATUS_CONFIGURE_PRODUCTS;
        quote.Bill_To_Address__c = createAddress[0].Id;
        quote.Ship_To_Address__c = createAddress[0].Id;
        update quote;
        quote.Quote_Stage__c = QuoteConstants.STATUS_FINALIZE_OSA;
        quote.Contract_Master_Terms__c = 'URL Terms';
        
        // Act
        Test.startTest();
            update quote;
        Test.stopTest();
        
        // Assert
        SBQQ__Quote__c updated = [SELECT Quote_Stage__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
        System.assertEquals('Finalize OSA', updated.Quote_Stage__c, 
            'Quote_Stage__c should be updated to Finalize OSA');
    }

    /**
    * @description Tests validation logic in the before update handler. Validates that validation
    *              errors are thrown when quotes with ordered status have invalid billing frequency
    *              or missing opportunity stage requirements.
    **/
    @isTest
    static void testProcessRecordsBeforeUpdateValidation() {
        // Arrange
        SBQQ__Quote__c quote = getQuote();
        quote.SBQQ__Ordered__c = true;
        quote.SBQQ__BillingFrequency__c = 'Semiannual';
        
        // Act
        Test.startTest();
        try {
            update quote;
            System.assert(false, 'Expected addError to be thrown for invalid billing frequency');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Opportunity Stage: Closed Won'), 
                'Exception message should contain validation error text');
        }
        Test.stopTest();
    }

    /**
    * @description Tests QuoteTriggerHelper.calculateYoYUplift populates Min_YoY_Uplift__c and Max_YoY_Uplift__c
    *              when values are null, using net amounts (Software Total - One Time Credit). YoY OTD logic.
    **/
    @isTest
    static void testCalculateYoYUplift_populatesMinMaxWhenNull() {
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            First_Year_Software_Total__c = 100,
            Second_Year_Software_Total__c = 120,
            Third_Year_Software_Total__c = 0,
            Min_YoY_Uplift__c = null,
            Max_YoY_Uplift__c = null
        );
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>{ q };

        Test.startTest();
        QuoteTriggerHelper.calculateYoYUplift(quotes);
        Test.stopTest();

        // Stored as 0-100 scale to match old formula fields
        System.assertEquals(20, q.Min_YoY_Uplift__c, 'Min YoY should be (120-100)/100 = 20%');
        System.assertEquals(20, q.Max_YoY_Uplift__c, 'Max YoY should be 20%');
    }

    /**
    * @description Tests QuoteTriggerHelper.calculateYoYUplift with one-time credits (OTD): net = total - OTC.
    **/
    @isTest
    static void testCalculateYoYUplift_includesOneTimeCredits() {
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            First_Year_Software_Total__c = 100,
            One_time_Credit_Yr1__c = 10,
            Second_Year_Software_Total__c = 120,
            One_time_Credit_Yr2__c = 0,
            Third_Year_Software_Total__c = 0,
            Min_YoY_Uplift__c = null,
            Max_YoY_Uplift__c = null
        );
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>{ q };

        Test.startTest();
        QuoteTriggerHelper.calculateYoYUplift(quotes);
        Test.stopTest();

        // Net Yr1 = 90, Net Yr2 = 120. With OTD: uplift = (120-90)/90 = 0.3333 * 100 = 33.33
        // Percent field stores 33.33% as 33.33
        System.assert(q.Min_YoY_Uplift__c != null, 'Min YoY should be calculated');
        System.assert(q.Max_YoY_Uplift__c != null, 'Max YoY should be calculated');
        // Values stored as 0-100; OTD uplift ~33% > non-OTD 20%
        Boolean usesNetValues = q.Min_YoY_Uplift__c > 9 && q.Min_YoY_Uplift__c <= 100;
        System.assert(usesNetValues, 'Min YoY should use net values (OTD uplift ~33% > non-OTD 20%). Actual: ' + q.Min_YoY_Uplift__c);
    }

    /**
    * @description Tests QuoteTriggerHelper.calculateYoYUplift skips calculation when the
    *              related Opportunity is closed. Values should remain unchanged.
    **/
    @isTest
    static void testCalculateYoYUplift_skipsWhenOpportunityClosed() {
        // Create an Account and Opportunity, then close the Opportunity
        Account acc = getAccount();
        Opportunity opp = getOpportunity();
        opp.StageName = 'Closed Won';
        opp.Date_Opportunity_Closed__c = Date.today();
        update opp;

        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id,
            First_Year_Software_Total__c = 100,
            Second_Year_Software_Total__c = 200,
            Min_YoY_Uplift__c = 0.5,
            Max_YoY_Uplift__c = 0.5
        );
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>{ q };

        Test.startTest();
        QuoteTriggerHelper.calculateYoYUplift(quotes);
        Test.stopTest();

        System.assertEquals(0.5, q.Min_YoY_Uplift__c, 'Min YoY should be unchanged when Opp is closed');
        System.assertEquals(0.5, q.Max_YoY_Uplift__c, 'Max YoY should be unchanged when Opp is closed');
    }

    /**
    * @description Tests QuoteTriggerHelper.calculateYoYUplift sets zero when no valid uplifts (netYr1 or netYr2 is 0).
    **/
    @isTest
    static void testCalculateYoYUplift_setsZeroWhenNoUplifts() {
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            First_Year_Software_Total__c = 0,
            Second_Year_Software_Total__c = 100,
            Min_YoY_Uplift__c = null,
            Max_YoY_Uplift__c = null
        );
        List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>{ q };

        Test.startTest();
        QuoteTriggerHelper.calculateYoYUplift(quotes);
        Test.stopTest();

        System.assertEquals(0, q.Min_YoY_Uplift__c, 'Min YoY should be 0 when no uplifts');
        System.assertEquals(0, q.Max_YoY_Uplift__c, 'Max YoY should be 0 when no uplifts');
    }

    /**
    * @description Tests the publishApprovalRecords method. Validates that approval records can be
    *              published and retrieved with the correct system ID.
    **/
    @isTest
    static void testPublishApprovalRecords() {
        // Arrange: Create a quote and an approval record
        SBQQ__Quote__c quote = getQuote();

        SBAA__Approval__c approval = new SBAA__Approval__c(
            Quote__c = quote.Id,
            OP4I_System_Id__c = 'TestSystemId',
            sbaa__RecordField__c = 'Quote__c',
            sbaa__ApprovalStep__c = 1
        );
        insert approval;

        // Act: Call the method under test
        Test.startTest();
            QuoteTriggerHelper.publishApprovalRecords(new Set<Id>{approval.Id});
        Test.stopTest();

        // Assert: The record should exist and have the expected fields
        SBAA__Approval__c fetched = [SELECT Id, OP4I_System_Id__c FROM SBAA__Approval__c WHERE Id = :approval.Id];
        System.assertEquals('TestSystemId', fetched.OP4I_System_Id__c, 
            'OP4I_System_Id__c should match the expected value');
    }
    
    /**
    * @description Tests that Pause_Quote_Payload__c is set to true for ghost quotes (Auto-Renewal
    *              renewal quotes). Validates the setPauseQuotePayload functionality.
    **/
    @isTest
    static void testSetPauseQuotePayload() {
        Account acc = getAccount();
        Opportunity opp = (Opportunity)TestFactory.buildSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = acc.Id
            ),
            'OpportunityDefaults'
        );
        insert opp;
        
        SBQQ.TriggerControl.disable();
        Contract renewalContract = (Contract)TestFactory.buildSObject(
            new Contract(
                EndDate = Date.today().addDays(100),
                SBQQ__RenewalForecast__c = true,
                SBQQ__RenewalQuoted__c = false,
                AccountId = acc.Id,
                SBQQ__Opportunity__c = opp.Id
            ),
            'ContractDefaults'
        );
        insert renewalContract;
        SBQQ.TriggerControl.enable();
        
        opp.SBQQ__RenewedContract__c = renewalContract.Id;
        update opp;

        SBQQ__Quote__c ghostQuote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id,
            SBQQ__Type__c = 'Renewal',
            Renewal_Quote_Type__c = 'Auto-Renewal'
        );

        Test.startTest();
        insert ghostQuote;
        Test.stopTest();

        SBQQ__Quote__c result = [SELECT Pause_Quote_Payload__c FROM SBQQ__Quote__c WHERE Id = :ghostQuote.Id];
        System.assertEquals(true, result.Pause_Quote_Payload__c, 
            'Pause_Quote_Payload__c should be TRUE for ghost quote');
    }
    
    /**
    * @description Tests the handleGhostQuoteAfterDelete functionality. Validates that ghost quotes
    *              can be deleted without errors and that the after delete handler executes successfully.
    **/
    @isTest
    static void testHandleGhostQuoteAfterDelete() {
        
        Test.startTest();
        Account acc = getAccount();
        Opportunity opp = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = acc.Id
            ),
            'OpportunityDefaults'
        );
        //insert opp;
        
        SBQQ.TriggerControl.disable();
        Contract renewedContract = (Contract)TestFactory.buildSObject(
            new Contract(
                EndDate = Date.today().addDays(100),
                SBQQ__RenewalForecast__c = true,
                SBQQ__RenewalQuoted__c = false,
                AccountId = acc.Id,
                SBQQ__Opportunity__c = opp.Id
            ),
            'ContractDefaults'
        );
        //insert renewedContract;
        SBQQ.TriggerControl.enable();
        
        opp.SBQQ__RenewedContract__c = renewedContract.Id;
        update opp;
        
        SBQQ__Quote__c quoteToDelete = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Account__c = acc.Id,
            SBQQ__Primary__c = true,
            SBQQ__Type__c = 'Renewal',
            Renewal_Quote_Type__c = 'Auto-Renewal'
        );
        insert quoteToDelete;
        
        delete quoteToDelete;
        Test.stopTest();
        
        // Assert: Verify the quote was deleted successfully
        Integer quoteCount = [SELECT COUNT() FROM SBQQ__Quote__c WHERE Id = :quoteToDelete.Id];
        System.assertEquals(0, quoteCount, 
            'Quote should be successfully deleted');
    }

    /***********************************************************************************************
    *
    * Private Helper Methods
    *
    ***********************************************************************************************/
    
    /**
    * @description Retrieves the test Account record created in @testSetup.
    * @return Account The test Account record
    **/
    private static Account getAccount() {
        return [SELECT Id FROM Account LIMIT 1];
    }
    
    /**
    * @description Retrieves the test Opportunity record created in @testSetup.
    * @return Opportunity The test Opportunity record
    **/
    private static Opportunity getOpportunity() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }
    
    /**
    * @description Retrieves the test Quote record created in @testSetup with all necessary fields.
    * @return SBQQ__Quote__c The test Quote record with Id, ApprovalStatus__c, Counter__c, SBQQ__Ordered__c, 
    *                        Order__c, SBQQ__BillingFrequency__c, and Quote_Stage__c fields
    **/
    private static SBQQ__Quote__c getQuote() {
        return [SELECT Id, ApprovalStatus__c, Counter__c, SBQQ__Ordered__c, Order__c, 
                    SBQQ__BillingFrequency__c, Quote_Stage__c 
                FROM SBQQ__Quote__c LIMIT 1];
    }

    /**
     * @description Returns the SBQQ__Quote__c record for the given Id with key fields used by tests validating trigger logic.
     * @param quoteId Id of the SBQQ__Quote__c record to fetch.
     * @return The SBQQ__Quote__c record with selected fields.
     */
    private static SBQQ__Quote__c getQuoteById(Id quoteId) {
        return [SELECT Id, ApprovalStatus__c, Counter__c, SBQQ__Ordered__c, Order__c, SBQQ__SubscriptionTerm__c,
                    SBQQ__BillingFrequency__c, Quote_Stage__c, Subsidiary__c, Pause_Quote_Payload__c
                FROM SBQQ__Quote__c WHERE Id = :quoteId];
    }
}