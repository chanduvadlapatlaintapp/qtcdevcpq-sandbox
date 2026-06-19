/**
 * @description Test class for SubscriptionsMigrationBatch_test.
 * @author      Manisha
 * @date        2025-05-06
 * @jira        BIZ-69719
 */
@isTest
public class SubscriptionsMigrationBatch_test {
    @TestSetup
    static void setup() {
        Account a = IntappTestObjectFactory.createaccount(true);
        
        Id pricebookId = Test.getStandardPricebookId();
        
        Pricebook2 customPricebook = new Pricebook2(
            Name = Label.MigrationPriceBookName,
            IsActive = true
        );
        insert customPricebook;
        
        List<SBQQ__Quote__c> quotes = (List<SBQQ__Quote__c>)TestFactory.createSObjectList(
            new SBQQ__Quote__c(
                SBQQ__Account__c = a.Id,
                Deal_Type__c = 'Renewal'
            ), 3, 'SBQQQuoteDefaults'
        );
        
        Product2 prodObj = IntappTestObjectFactory.createProduct(true);
        prodObj.Name = 'Intapp Select Bundle';
        prodObj.isActive= true;
        update prodObj;

        Product2 prodObj1 = IntappTestObjectFactory.createProduct(true);
        prodObj1.Name = 'TestProd1';
        update prodObj1;
        
        Product2 prodObj2 = IntappTestObjectFactory.createProduct(true);
        prodObj2.Name = 'One-Time';
        prodObj2.SBQQ__ChargeType__c = 'One-Time';
        update prodObj2;
        
        PricebookEntry standardPbe1 = new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = prodObj.Id, UnitPrice = 1000, IsActive = true);
        insert standardPbe1;
        
        PricebookEntry standardPbe2 = new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = prodObj1.Id, UnitPrice = 1000, IsActive = true);
        insert standardPbe2;
        
        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = customPricebook.Id,
            Product2Id = prodObj.Id,
            UnitPrice = 1020,
            IsActive = true
        );
        insert pbe1;
        
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = customPricebook.Id,
            Product2Id = prodObj1.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe2;
        
        SBQQ__Dimension__c priceBookDimension1 = TestDataFactory.createPricebookDimension(prodObj.Id,true);
        
        SBQQ__Dimension__c priceBookDimension2 = TestDataFactory.createPricebookDimension(prodObj1.Id,true);
        
        Contract con1= new Contract();
        con1.Migration_Status__c = 'Ready';
        con1.AccountId = a.Id;
        con1.SBQQ__Quote__c = quotes.get(0).Id;
        con1.Processing_Status__c = 'Parent Subscription Created';
        con1.Legacy_Quote_Id__c = 'test legacy';
        insert con1;
        
        Contract con2 = new Contract();
        con2.Migration_Status__c = 'Ready';
        con2.AccountId = a.Id;
        con2.SBQQ__Quote__c = quotes.get(1).Id;
        con2.Processing_Status__c = 'Parent Subscription Created';
        con2.Legacy_Quote_Id__c = 'test legacy';
        insert con2;
        
        Contract con3 = new Contract();
        con3.Migration_Status__c = 'Ready';
        con3.AccountId = a.Id;
        con3.SBQQ__Quote__c = quotes.get(2).Id;
        con3.Processing_Status__c = 'Parent Subscription Created';
        con3.Legacy_Quote_Id__c = 'test legacy';
        insert con3;
        
        
        OP4I_Entitlement_View__c entitlement0 = new OP4I_Entitlement_View__c();
        entitlement0.Associated_OSA__c = con3.id;
        entitlement0.Deal_Type__c = 'Renewal';
        entitlement0.Name = 'Test Entitlement';
        entitlement0.Start_Date__c = null;
        entitlement0.End_Date__c = null;
        entitlement0.Sale_Price__c = 20.22;
        entitlement0.Product_Type__c = 'Software';
        entitlement0.DLI_Product__c = prodObj.id;
        entitlement0.DLIP_Product__c = prodObj1.id;
        entitlement0.Billing_Frequency__c = 'Annual';
        entitlement0.Processing_Status__c = 'Parent Subscription Created';
        entitlement0.Include_in_Select_Bundle__c = false;
        entitlement0.Additional_Discount__c = 20.12;
        entitlement0.Quote__c = quotes.get(0).Id;
        entitlement0.Segment_Index__c = 1;
        insert entitlement0;
        
        OP4I_Entitlement_View__c entitlement = new OP4I_Entitlement_View__c();
        entitlement.Associated_OSA__c = con1.id;
        entitlement.Deal_Type__c = 'Renewal';
        entitlement.Name = 'Test Entitlement';
        entitlement.Start_Date__c = Date.newInstance(2021, 4, 1);
        entitlement.End_Date__c = Date.newInstance(2022, 3, 31);
        entitlement.Sale_Price__c = 20.22;
        entitlement.Product_Type__c = 'Software';
        entitlement.DLI_Product__c = prodObj.id;
        entitlement.DLIP_Product__c = prodObj1.id;
        entitlement.Billing_Frequency__c = 'Annual';
        entitlement.Processing_Status__c = 'Parent Subscription Created';
        entitlement.Include_in_Select_Bundle__c = true;
        entitlement.Additional_Discount__c = 20.12;
        entitlement.Quote__c = quotes.get(0).Id;
        entitlement.Segment_Index__c = 1;
        insert entitlement;
        
        OP4I_Entitlement_View__c entitlement1 = new OP4I_Entitlement_View__c();
        entitlement1.Associated_OSA__c = con2.id;
        entitlement1.Deal_Type__c = 'Renewal';
        entitlement1.Name = 'Test Entitlement1';
        entitlement1.Start_Date__c = Date.newInstance(2021, 4, 1);
        entitlement1.End_Date__c = Date.newInstance(2022, 3, 31);
        entitlement1.Sale_Price__c = 20.22;
        entitlement1.Product_Type__c = 'Software';
        entitlement1.DLI_Product__c = prodObj.id;
        entitlement1.DLIP_Product__c = prodObj.id;
        entitlement1.Billing_Frequency__c = 'Annual';
        entitlement1.Processing_Status__c = 'Parent Subscription Creation failed';
        entitlement1.Include_in_Select_Bundle__c = true;
        entitlement1.Additional_Discount__c = 20.12;
        entitlement1.Quote__c = quotes.get(0).Id;
        entitlement.Segment_Index__c = 1;
        insert entitlement1;
        
        OP4I_Entitlement_View__c entitlement2 = new OP4I_Entitlement_View__c();
        entitlement2.Associated_OSA__c = con2.id;
        entitlement2.Name = 'Test Entitlement2';
        entitlement2.Deal_Type__c = 'Renewal';
        entitlement2.Start_Date__c = System.today();
        entitlement2.End_Date__c = System.today().addYears(1);
        entitlement2.Sale_Price__c = 20.22;
        entitlement2.Product_Type__c = 'Software';
        entitlement2.DLI_Product__c = prodObj.id;
        entitlement2.DLIP_Product__c = prodObj.id;
        entitlement2.Billing_Frequency__c = 'Annual';
        entitlement2.Processing_Status__c = 'Parent Subscription Creation failed';
        entitlement2.Include_in_Select_Bundle__c = false;
        entitlement2.Additional_Discount__c = 20.12;
        entitlement2.Quote__c = quotes.get(0).Id;
        entitlement.Segment_Index__c = 1;
        insert entitlement2;
        
        OP4I_Entitlement_View__c entitlement3 = new OP4I_Entitlement_View__c();
        entitlement3.Associated_OSA__c = con1.id;
        entitlement3.Name = 'Test Entitlement3';
        entitlement3.Deal_Type__c = 'Renewal';
        entitlement3.Start_Date__c = null;
        entitlement3.End_Date__c = null;
        entitlement3.Sale_Price__c = 20.22;
        entitlement3.Product_Type__c = 'Software';
        entitlement3.DLI_Product__c = prodObj2.id;
        entitlement3.Billing_Frequency__c = 'Annual';
        entitlement3.Additional_Discount__c = 20.12;
        entitlement3.Quote__c = quotes.get(0).Id;
        entitlement.Segment_Index__c = 1;
        insert entitlement3;
        
        OP4I_Entitlement_View__c entitlement4 = new OP4I_Entitlement_View__c();
        entitlement4.Associated_OSA__c = con2.id;
        entitlement4.Include_in_Select_Bundle__c = false;
        entitlement4.Name = 'Test Entitlement3';
        entitlement4.Deal_Type__c = 'Renewal';
        entitlement4.Start_Date__c = System.today();
        entitlement4.End_Date__c = System.today().addYears(1);
        entitlement4.Sale_Price__c = 20.22;
        entitlement4.Product_Type__c = 'Software';
        entitlement4.DLI_Product__c = prodObj2.id;
        entitlement4.DLIP_Product__c = prodObj2.id;
        entitlement4.Billing_Frequency__c = 'Annual';
        entitlement4.Additional_Discount__c = 20.12;
        entitlement4.Quote__c = quotes.get(0).Id;
        entitlement4.Segment_Index__c = 1;
        insert entitlement4;
        
        OP4I_Entitlement_View__c entitlement5 = new OP4I_Entitlement_View__c();
        entitlement5.Associated_OSA__c = con2.id;
        entitlement5.Include_in_Select_Bundle__c = false;
        entitlement5.Name = 'Test Entitlement3';
        //entitlement5.Deal_Type__c = 'Renewal';
        entitlement5.Start_Date__c = null;
        entitlement5.End_Date__c = null;
        entitlement5.Sale_Price__c = 20.22;
        entitlement5.Product_Type__c = 'Software';
        entitlement5.DLI_Product__c = prodObj.id;
        entitlement5.DLIP_Product__c = prodObj.id;
        entitlement5.Billing_Frequency__c = 'Annual';
        entitlement5.Additional_Discount__c = 20.12;
        entitlement5.Quote__c = quotes.get(0).Id;
        entitlement5.Segment_Index__c = 1;
        insert entitlement5;
    }

    @isTest
    public static void testSubscriptionBatch(){
       List<Contract> contracts = [SELECT ContractNumber,Migration_Status__c FROM Contract];
        List<String> contractNumbers = new List<String>();
        for (Contract con : contracts) {
            contractNumbers.add(con.ContractNumber.substring(con.ContractNumber.length() - 1));
        } 
        List<String> emailAddresses = new List<String>{('testdata@gmail.com')};
        
        
        SubscriptionsMigrationBatch sm = new SubscriptionsMigrationBatch(contractNumbers, emailAddresses);
        Test.startTest();
        ID batchProcessId = Database.executeBatch(sm);
        OP4I_Entitlement_View__c ent = [SELECT Id, Associated_OSA__c, Associated_OSA__r.AccountId, OP4I_Deal_Id__c, Parent_Subscription__c,
                                       DLI_Product__c, DLI_Product__r.Id, DLIP_Product__c, DLIP_Product__r.SBQQ__PricingMethod__c, DLIP_Product__r.SBQQ__SubscriptionPricing__c,
                                       DLIP_Product__r.SBQQ__SubscriptionType__c,
                                       DLIP_Product__r.SBQQ__ChargeType__c,
                                       DLIP_Product__r.SBQQ__BillingType__c,
                                       DLIP_Product__r.Product_Type__c,
                                       Quantity__c, Sale_Price__c, Additional_Discount__c,
                                       CurrencyIsoCode, Segment_Index__c,
                                       Start_Date__c, End_Date__c,
                                       Product_Instance__c,
                                       DLI_Id__c, DLIP_Id__c,
                                       Entitlement_Id__c,
                                       Support_Level__c, Meter_Type__c,
                                       Subscription_Term__c
                                FROM OP4I_Entitlement_View__c limit 1];
        Map<String, Id> pricebookMap = new Map<String, Id>();
        //pricebookMap.put('USD'+ent.DLIP_Product__c, 'fakePbeId');
        Map<String, Id> dimMap = new Map<String, Id>();
        //dimMap.put('USD'+ent.DLIP_Product__c, 'fakeDimId');
        Map<String, Date> contractEndDateMap = new Map<String, Date>();
        contractEndDateMap.put(ent.Associated_OSA__c, Date.today().addMonths(12));
        
        
        new SubscriptionsMigrationBatch().createChildSubscription(ent, pricebookMap, dimMap, contractEndDateMap );
        Test.stopTest();
        System.assertEquals('Ready', contracts[0].Migration_Status__c);
    }
}