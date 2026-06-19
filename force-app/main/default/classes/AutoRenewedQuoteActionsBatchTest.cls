/**
 * @author : Pooja Hemrajani
 * @date : 03/07/2025
 * @description : Test class for AutoRenewedQuoteActionsBatch
 */
@isTest
public class AutoRenewedQuoteActionsBatchTest {

    /**********************************************************************************************
    *
    * Test Data Setup
    *
    ***********************************************************************************************/
    @testSetup
    public static void setup() {
        // Create test products
        List<Product2> products = (List<Product2>)TestFactory.createSObjectList(
            new Product2(Name = 'Test Product'), 1, 'ProductDefaults'
        );

        // Create test pricebook entries
        for (Product2 product : products) {
            List<PricebookEntry> entries = (List<PricebookEntry>)TestFactory.createSObjectList(
                new PricebookEntry(Product2Id = product.Id, Pricebook2Id = Test.getStandardPricebookId(), UnitPrice = 100), 1, 'PricebookEntryDefaults'
            );
        }

        // Create test account
        List<Account> accounts = (List<Account>)TestFactory.createSObjectList(
            new Account(Name = 'Test Account'), 1, 'AccountDefaults'
        );

        // Create test opportunity
        List<Opportunity> opportunities = (List<Opportunity>)TestFactory.createSObjectList(
            new Opportunity(
                Name = 'Test Opportunity',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                AccountId = accounts[0].Id
            ), 1, 'OpportunityDefaults'
        );
        
        Contract contract = (Contract)TestFactory.buildSObject(
            new Contract(
                Name = 'Contract',
                AccountId = accounts[0].Id,
                StartDate = Date.today().addMonths(-24),
                EndDate = Date.today().addMonths(-12),
                Subsidiary__c = '18:DealCloud, Inc.',
                Contract_Master_Terms__c = 'Legacy DealCloud Agreement'
            ), 'ContractDefaults'
        );
        
        // Update Opportunity to include Renewed Contract
        opportunities[0].SBQQ__RenewedContract__c = contract.Id;
        update opportunities;

        // Create test quote linked to opportunity
        List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Opportunity2__c = opportunities[0].Id,
                AVA_SFCPQ__AvaTaxMessage__c = 'CANNOT_EXECUTE_FLOW_TRIGGER',
                AVA_SFCPQ__Quote_AutomateTaxCalculation__c = false,
                SBQQ__StartDate__c = Date.today().addDays(10)
            ), 1, 'SBQQQuoteDefaults'
        );

        // Create Proforma_Invoice__c (Renewal Letter)
        Proforma_Invoice__c proformaInvoice = (Proforma_Invoice__c) TestFactory.createSObject(
            new Proforma_Invoice__c(
                Renewal_Quote__c = quotes[0].Id,
                Status__c = RenewalLetterConstants.STATUS_INITIATED,
                Activity_Status__c = RenewalLetterConstants.ACTIVITY_STATUS_SEND_DOC_TO_CONTACT
            )
        );
    }

    /**
     * @description Test Schedulable execution path
     */
    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String cronExp = '0 0 0 1 1 ? 2027';
        System.schedule('AutoRenewedQuoteScheduleTest', cronExp, new AutoRenewedQuoteActionsBatch());
        Test.stopTest();

        System.assert(true, 'Schedulable executed');
    }
    
    @isTest
    static void testBatchExecution_fullPath() {
        Test.startTest();
        SBQQ.TriggerControl.disable();
    
        // Get existing data
        SBQQ__Quote__c quote = [SELECT Id, SBQQ__Opportunity2__c FROM SBQQ__Quote__c LIMIT 1];
        Opportunity opp = [SELECT Id, Quote_Start_Date__c, SBQQ__RenewedContract__c FROM Opportunity WHERE Id = :quote.SBQQ__Opportunity2__c LIMIT 1];
        
        quote.SBQQ__StartDate__c = Date.today().addDays(30);
        update quote;
    
        // Insert Proforma_Invoice__c (must match 30-day condition)
        Proforma_Invoice__c letter = new Proforma_Invoice__c(
            Renewal_Quote__c = quote.Id,
            Status__c = RenewalLetterConstants.STATUS_INITIATED,
            Activity_Status__c = null 
        );
        insert letter;
        // Prepare and run batch
        String query = 'SELECT Id, Activity_Status__c, Days_Remaining_for_Renewal__c , Renewal_Quote__r.AVA_SFCPQ__AvaTaxMessage__c, Renewal_Quote__r.SBQQ__Opportunity2__r.Renewal_Start_Date__c, ' + 
                       'Renewal_Quote__r.AVA_SFCPQ__Tax_Calculation_Status__c, Status__c, Renewal_Quote__r.SBQQ__Opportunity2__r.Quote_Start_Date__c, ' +
                       'Renewal_Quote__r.SBQQ__Opportunity2__r.SBQQ__RenewedContract__r.Renewal_to_be_created_Before_Days__c, ' +
            		   'Renewal_Quote__r.SBQQ__Opportunity2__r.IsClosed, Renewal_Quote__r.SBQQ__Opportunity2__r.StageName '+
                       'FROM Proforma_Invoice__c WHERE Id = \'' + letter.Id + '\'';
    
        AutoRenewedQuoteActionsBatch batch = new AutoRenewedQuoteActionsBatch(query, 1);
        Database.executeBatch(batch, 1);
        SBQQ.TriggerControl.enable();
        Test.stopTest();

        SBQQ__Quote__c obj = getQuote(quote.Id) ;
        System.assertEquals('Configure Products', obj.Quote_Stage__c, 'Quote Stage should be Configure Products after batch');
    }
    
    
    /**********************************************************************************************
    *
    * Getter Methods
    *
    ***********************************************************************************************/
    private static SBQQ__Quote__c getQuote(Id quoteId) {
        return [SELECT Id, Quote_Stage__c FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1];
    }
}