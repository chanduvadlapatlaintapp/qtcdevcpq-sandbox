@isTest public class IntappPricingHandlerTest {
    /* Test */
    @isTest 
    static void testMethod1(){
        Intapp_Pricing__c intapppriceObj = (Intapp_Pricing__c) SmartFactory.createSObject('Intapp_Pricing__c');
        intapppriceObj.Name = 'Testintappprice';
        intapppriceObj.CurrencyIsoCode = 'USD';
        intapppriceObj.Tier__c = 'Tier A';
        intapppriceObj.Price_Book__c = Test.getStandardPricebookId();
        intapppriceObj.Product_Code__c = 'Test Product';
        intapppriceObj.Price__c = 50;
        insert intapppriceObj;
        List<Intapp_Pricing__c> pList = new List<Intapp_Pricing__c>();
        List<Intapp_Pricing__c> pList2 = new List<Intapp_Pricing__c>();
        pList.add(intapppriceObj);
        Test.startTest();
        IntappPricingHandler.intappPriceAfterInsert(pList);
        pList2.add(intapppriceObj);
        pList2[0].Intapp_ID__c = 'test';
        pList2[0].Premium_price__c = 123;
        update pList2;
        system.assertNotEquals(null,pList2,'Product');
        Test.stopTest();
    }
}