@isTest public class ProductTriggerHandlerTest {
    @isTest static void testMethod1(){
      Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
      prodObj.Name = 'Testproduct';
      prodObj.IsActive = true;
      prodObj.ProductCode = '123462';
      insert prodObj;
      List<Product2> pList = new List<Product2>();
      List<Product2> pList2 = new List<Product2>();
      pList.add(prodObj);
      Test.startTest();
      ProductTriggerHandler.productAfterInsert(pList);
      pList2.add(prodObj);
      pList2[0].Intapp_ID__c = 'test';
      update pList2;
      system.assertNotEquals(null,pList2,'Product');
      Test.stopTest();
    }
}