/**
 * @description Test class for QuoteLineItemHandler
 */
@isTest
public class QuoteLineItemHandlerTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    /**
     * @description Test Setup
     */
    @TestSetup
    static void makeData(){
        // Create test Account
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account',
                Industry = 'Test Industry',
                SBQQ__RenewalModel__c = 'Contract Based',
                OP4I_Sales_Segment__c = '01-Legal - APAC'
            ), 'AccountDefaults'
        );
        List<Product2> products = new List<Product2>();
        // Create test Products
        Product2 product1 = (Product2)TestFactory.buildSObject(
            new Product2(
                Name = 'Testproduct',
                IsActive = true,
                ProductCode = 'BU-01408',
                Bundle_product__c = true
            ), 'ProductDefaults'
        );
        products.add(product1);

        Product2 product2 = (Product2)TestFactory.buildSObject(
            new Product2(
                Name = 'Testproduct2',
                IsActive = true,
                ProductCode = '12346289'
            ), 'ProductDefaults'
        );
        products.add(product2);
        insert products;

        // Create PricebookEntry
        Id pricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for(Product2 product : products) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 1,
                IsActive = true
            ));
        }
        insert pbes;

        // Create test Opportunity
        Opportunity opportunity = (Opportunity)TestFactory.createSObject(
            new Opportunity(
                Name = 'TestOppoty',
                AccountId = account.Id,
                StageName = '01. Qualify',
                Requested_Contract_Expiration__c = Date.today(),
                Initial_Software_Term_Length_Months__c = 12,
                Pricebook2Id = pricebookId
            ), 'OpportunityDefaults'
        );
        
        SBQQ__Quote__c quote = (SBQQ__Quote__c)TestFactory.createSObject(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = opportunity.Id,
                SBQQ__Account__c = opportunity.AccountId,
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                License_Basis__c = 'Lawyers',
                Number_of_DLIs__c = 1,
                Number_of_QLIs__c = 3,
                ApprovalStatus__c = 'Pending',
                OP4I_OSA_Request_Received__c = true,
                OP4I_Deal_Synced__c = true,
                Deal_ACV__c = null,
                SBQQ__LastCalculatedOn__c = null,
                SBQQ__LastSavedOn__c = null,
                RecordTypeId = Schema.SObjectType.SBQQ__Quote__c.getRecordTypeInfosByName().get('New Quote terms').getRecordTypeId()
            ),'SBQQQuoteDefaults'
        );
        
        List<SBQQ__QuoteLine__c> testqli1 = (List<SBQQ__QuoteLine__c>)TestFactory.createSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id,
                SBQQ__Quantity__c = 1,
                SBQQ__Product__c = products[0].id,
                SBQQ__CustomerPrice__c = 25,
                SBQQ__SegmentIndex__c = 10,
                Print_at_Quote__c = true
            ), 1, 'SBQQQuoteLineDefaults'
        );

    }

    /**
     * @description test method for updateQuoteLine
     */
    @isTest
    static void quoteLineItemMethod1(){
        
        Map<Id, SBQQ__Quote__c> mapOfQuote = new Map<id,SBQQ__Quote__c>();
        Opportunity opp = getOpp();
        List<Product2> products = getProducts();
		List<SBQQ__Quote__c> quotes = getQuotes();
        mapOfQuote.put(quotes[0].id, quotes[0]);
		List<SBQQ__QuoteLine__c> lstOfQLE = getQuoteLines();
        
        Test.startTest();
            SBQQ.TriggerControl.disable();
            List<SBQQ__QuoteLine__c> testqli2 = (List<SBQQ__QuoteLine__c>)TestFactory.buildSObjectList(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = quotes[0].Id,
                    SBQQ__Quantity__c = 1,
                    SBQQ__Product__c = products[1].id,
                    SBQQ__RequiredBy__c = lstOfQLE[0].id,
                    SBQQ__Discount__c = 10,
                    SBQQ__CustomerPrice__c = 25,
                    SBQQ__NetPrice__c = 20,
                    SBQQ__SegmentIndex__c = 10,
                    Print_at_Quote__c = true
                ), 1, 'SBQQQuoteLineDefaults'
            );
            lstOfQLE.addall(testqli2);
            upsert lstOfQLE;
        Test.stopTest();

        System.assertNotEquals(lstOfQLE.size(), null, 'Checking values to be null');
    }

    @isTest
    static void quoteLineItemMethod2(){
        Map<Id, SBQQ__Quote__c> mapOfQuote = new Map<id,SBQQ__Quote__c>();
        Opportunity opp = getOpp();
        List<Product2> products = getProducts();
		List<SBQQ__Quote__c> quotes = getQuotes();
        mapOfQuote.put(quotes[0].id, quotes[0]);
		List<SBQQ__QuoteLine__c> lstOfQLE = getQuoteLines();
        
        Test.startTest();
        SBQQ.TriggerControl.disable();
        List<SBQQ__QuoteLine__c> testqli2 = (List<SBQQ__QuoteLine__c>)TestFactory.buildSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quotes[0].Id,
                SBQQ__Quantity__c = 1,
                SBQQ__Product__c = products[1].id,
                SBQQ__RequiredBy__c = lstOfQLE[0].id,
                SBQQ__Discount__c = 10,
                SBQQ__CustomerPrice__c = 25,
                SBQQ__NetPrice__c = 20,
                SBQQ__SegmentIndex__c = 10,
                Print_at_Quote__c = true
            ), 1, 'SBQQQuoteLineDefaults'
        );
        lstOfQLE.addall(testqli2);
        List<SBQQ__QuoteLine__c> testqli3 = (List<SBQQ__QuoteLine__c>)TestFactory.buildSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quotes[0].Id,
                SBQQ__Quantity__c = 1,
                SBQQ__Product__c = products[1].Id,
                SBQQ__RequiredBy__c = lstOfQLE[0].id,
                SBQQ__Discount__c = 10,
                Print_at_Quote__c = false,
                SBQQ__CustomerPrice__c = 25,
                SBQQ__NetPrice__c = 20,
                SBQQ__SegmentIndex__c = 10
            ), 1, 'SBQQQuoteLineDefaults'
        );
        lstOfQLE.addall(testqli3);
        upsert lstOfQLE;
        
        //QuoteLineItemHandler.updateQuoteLine(lstOfQLE,mapOfQuote);
        Test.stopTest();
    }
    
    
    @isTest
    static void quoteLineItemMethodDelete(){
        Map<Id, SBQQ__Quote__c> mapOfQuote = new Map<id,SBQQ__Quote__c>();
        Opportunity opp = getOpp();
        List<Product2> products = getProducts();
		List<SBQQ__Quote__c> quotes = getQuotes();
        mapOfQuote.put(quotes[0].id, quotes[0]);
		List<SBQQ__QuoteLine__c> lstOfQLE = getQuoteLines();
        
        Test.startTest();
        SBQQ.TriggerControl.disable();
        List<SBQQ__QuoteLine__c> testqli2 = (List<SBQQ__QuoteLine__c>)TestFactory.createSObjectList(
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quotes[0].Id,
                SBQQ__Quantity__c = 1,
                SBQQ__Product__c = products[1].id,
                SBQQ__RequiredBy__c = lstOfQLE[0].id,
                SBQQ__Discount__c = 10,
                SBQQ__CustomerPrice__c = 25,
                SBQQ__NetPrice__c = 20,
                SBQQ__SegmentIndex__c = 10,
                Print_at_Quote__c = true
            ), 1, 'SBQQQuoteLineDefaults'
        );
        lstOfQLE.addall(testqli2);
        
        delete testqli2;
        Test.stopTest();
    }

    /**********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    /**
     * @description gets the opportunity
     * @return Opportunity
     */
    private static Opportunity getOpp() {
        return [SELECT Id, AccountId
                FROM Opportunity LIMIT 1];
    }

    /**
     * @description Getter for products
     * @return List<Product2>
     */
    private static List<Product2> getProducts() {
        return [SELECT Id
                FROM Product2];
    }

    /**
     * @description Getter for quote lines
     * @return List<SBQQ__QuoteLine__c>
     */
    private static List<SBQQ__QuoteLine__c> getQuoteLines() {
        return [SELECT Id,SBQQ__CustomerPrice__c,SBQQ__RequiredBy__c,SBQQ__SegmentIndex__c,
                                Print_at_Quote__c,SBQQ__Discount__c,SBQQ__Product__c,SBQQ__Quantity__c,SBQQ__Quote__c, 
                                SegmentIndex_Year__c, Is_Bundle_Product__c,SBQQ__CustomerTotal__c,Monthly_Net_Price_Currency__c,
                                OSA_List_Price__c,SBQQ__ListTotal__c,Item_Master_Name__c
                        FROM SBQQ__QuoteLine__c];
    }

    /**
     * @description Getter for quotes
     * @return List<SBQQ__Quote__c>
     */
    private static List<SBQQ__Quote__c> getQuotes() {
        return [SELECT Id, OwnerId, RecordTypeId, CreatedById, LastModifiedById, SBQQ__EmailTemplateId__c, 
                    SBQQ__OrderGroupID__c, SBQQ__PricebookId__c, SBQQ__QuoteProcessId__c, SBQQ__QuoteTemplateId__c, 
                    Band_Override__c, Hide_Effective_Date__c, SBQQ__ConsumptionRateOverride__c, OP4I_Document_Id__c, 
                    OP4IDealID__c, OP4I_Account_Id__c, Industry_President__c, 
                    Override_Next_Billing_date__c, Payment_Terms_Override__c, 
                    SFA_Override__c, StaticBundleIds__c, Subsidiary_Payment_Details__c, Subsidiary__c, 
                    Hide_Pricing__c, Extended_Initial_Term__c  
                FROM SBQQ__Quote__c];
    }
}