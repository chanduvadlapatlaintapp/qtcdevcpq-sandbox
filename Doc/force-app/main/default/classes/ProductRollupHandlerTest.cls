@isTest public class ProductRollupHandlerTest {
/* Test */
    @isTest static void testMethod1(){
      Product_Rollup__c prodrollupObj = (Product_Rollup__c) SmartFactory.createSObject('Product_Rollup__c');
      prodrollupObj.Name = 'Testproductproductrollup';
      prodrollupObj.CurrencyIsoCode = 'USD';
      insert prodrollupObj;
      List<Product_Rollup__c> pList = new List<Product_Rollup__c>();
      List<Product_Rollup__c> pList2 = new List<Product_Rollup__c>();
      pList.add(prodrollupObj);
      Test.startTest();
      ProductRollupHandler.productrollupAfterInsert(pList);
      pList2.add(prodrollupObj);
      pList2[0].Intapp_ID__c = 'test';
      update pList2;
      system.assertNotEquals(null,pList2,'Productrollup');
      Test.stopTest();
    }
    }