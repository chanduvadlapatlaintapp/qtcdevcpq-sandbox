/**
* @description Test class for RenewalLetterSelectorTest
* @author Sonali Kakade
**/
@isTest
private class RenewalLetterSelectorTest {

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
        Account account = (Account)TestFactory.createSObject(
            new Account(
                Name = 'Test Account'
            ), 'AccountDefaults'
        );
        
        Contact con = (Contact) TestFactory.createSObject(
            new Contact(
                AccountId = account.Id
            ), 'ContactDefaults'
        );
        
        Contract ctr = (Contract) TestFactory.createSObject(
            new Contract(
                Name = 'ActiveContract',
                AccountId = account.Id,
                StartDate = Date.today().addMonths(-12),
                EndDate = Date.today().addMonths(12)
            ), 'ContractDefaults'
        );
        
        // Create test Opportunities
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addMonths(1),
                AccountId = account.Id,
                Associated_Contract_OSA__c = ctr.Id,
                Contract_Signer__c = con.Id,
                Requested_Contract_Expiration__c = Date.today(),
                Initial_Software_Term_Length_Months__c = 12,
                SBQQ__QuotePricebookId__c = Test.getStandardPricebookId(),
                OP4I_Auto_Number_Deal_ID__c = '12345',
                Type = OpportunityConstants.TYPE_RENEWAL,
                Quote_Start_Date__c = Date.today().addDays(30)
            ), 1, 'OpportunityDefaults'
        );
        
        Product2 prodObj = (Product2)TestFactory.createSObject(
            new Product2(Name = 'Testproduct', IsActive = true, ProductCode = '123462'), 'ProductDefaults');

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=Test.getStandardPricebookId(), Product2Id=prodObj.id, UnitPrice=1, IsActive=True);
        insert pbe; 
        
        // Create test Quotes associated with Opportunities
        List<SBQQ__Quote__c> newQuote = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Primary__c = true,
                SBQQ__Opportunity2__c = opportunities[0].Id,
                SBQQ__Account__c = account.Id,
                OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket',
                SBQQ__SubscriptionTerm__c = 36,
                First_Segment_Months__c = 12,
                Subsidiary__c = '01:200 Integration Appliance (US)',
                Bill_To_Account__c =  account.Id,
                Ship_To_Account__c =  account.Id,
                Quote_Stage__c = 'Configure Products',
                License_Basis__c = 'Lawyers',
                SBQQ__StartDate__c = system.today(),
                ApprovalStatus__c='Error',
                Renewal_Quote_Type__c = 'Auto-Renewal',
                SBQQ__PricebookId__c = Test.getStandardPricebookId()
            ), 1, 'SBQQQuoteDefaults'
        );
        
        Test.startTest();
            SBQQ.TriggerControl.disable();
        	List<SBQQ__QuoteLine__c> testqli1 = (List<SBQQ__QuoteLine__c>)TestFactory.createSObjectList(
                new SBQQ__QuoteLine__c(
                    SBQQ__Quote__c = newQuote[0].Id,
                    SBQQ__Quantity__c = 1,   
                    SBQQ__Product__c = prodObj.id,
                    Print_at_Quote__c = true,
                    SBQQ__CustomerPrice__c = 25,
                    SBQQ__PricebookEntryId__c = pbe.Id
                ), 1, 'SBQQQuoteLineDefaults'
            );
            SBQQ.TriggerControl.enable();
            update testqli1;
        Test.stopTest();
        Proforma_Invoice__c proformaInvoice = (Proforma_Invoice__c) TestFactory.createSObject(
            new Proforma_Invoice__c(
                Renewal_Quote__c = newQuote[0].Id,
                Status__c = RenewalLetterConstants.STATUS_INITIATED           
            )
        );
    }


    /**********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/
    /**
     * @description tests the Renewal Letter fetch
     */
    @IsTest
    static void fetchRenewalLetterTest() {
        List<Proforma_Invoice__c> renewalLetters = [SELECT Id, Renewal_Quote__c 
                									  FROM Proforma_Invoice__c];
        Set<Id> existingQuoteIds = new Set<Id>();
        for (Proforma_Invoice__c letter : renewalLetters) {
            if (letter.Renewal_Quote__c != null) {
                existingQuoteIds.add(letter.Renewal_Quote__c);
            }
        }
        Set<String> setFields = new Set<String>{'Activity_Status__c', 'AVA_SalesTaxAmount__c'};
        Test.startTest();
        RenewalLetterSelector renewalLetter = new RenewalLetterSelector(setFields);
        List<Proforma_Invoice__c> fetchedRenewalLetters = renewalLetter.getRenLetterByQuoteIds(existingQuoteIds);
        Test.stopTest();
    	System.assertEquals(renewalLetters.size(), fetchedRenewalLetters.size());
    }
}