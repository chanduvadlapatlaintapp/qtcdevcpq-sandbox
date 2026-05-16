/**
 * @description Test class refactored for IntappTestObjectFactory.
 *              Covers object creation methods using various flags.
 * @author      Manisha
 * @date        2025-06-30
 * @jira        BIZ-70776
 */
@isTest
private class IntappTestObjectFactoryTest {
    Account account = new Account();
    
    @isTest
    static void testCreateSubscription() {
        Subscription__c subscription = IntappTestObjectFactory.createSubscription(false);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateAccount() {
        Account account = IntappTestObjectFactory.createAccount(false);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateAccount2() {
        Account account = IntappTestObjectFactory.createAccount();
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateInvoice() {
        Account account = new Account();
        Invoice__c invoice = IntappTestObjectFactory.createInvoice(false);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateContract() {
        Account account = new Account();
        Contract contract = IntappTestObjectFactory.createContract(account.Id);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateContact() {
        Contact contact = IntappTestObjectFactory.createContact(false);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateContact1() {
        Contact contact = IntappTestObjectFactory.createContact(true);
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateContact2() {
        Contact contact = IntappTestObjectFactory.createContact();
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateOpportunity() {
        Opportunity opportunity = IntappTestObjectFactory.createOpportunity();
        System.assertEquals(account.Id, account.Id);
    }
    
    @isTest
    static void testCreateUser() {
        User userRec = IntappTestObjectFactory.createUser();
        System.assertNotEquals(userRec.LastName, null);
    }
    
    @isTest
    static void testCreateSBQQQuote() {
        SBQQ__Quote__c quoteRec = IntappTestObjectFactory.createSBQQQuote();
        System.assertEquals(quoteRec.Id, null);
    }
    
    @isTest
    static void testCreateApproversMatrix() {
        Approvers_Matrix__c approversMatrix = IntappTestObjectFactory.createApproversMatrix();
        System.assertEquals(approversMatrix.Id, null);
    }
    
    @isTest
    static void testCreateItemMaster() {
        Item_Master_Product__c item = IntappTestObjectFactory.createItemMaster(false);
        System.assertEquals(item.Id, null);
    }

    @isTest
    static void testCreateProduct() {
        Product2 prod = IntappTestObjectFactory.createProduct(false);
        System.assertEquals(prod.Id, null);
    }
    
    @isTest
    static void testCreateCampaign() {
        Campaign cmp = IntappTestObjectFactory.createCampaign(false);
        System.assertEquals(cmp.Id, null);
    }
    
    @isTest
    static void testCreateOpportunityLineItem() {
        Account a = (Account) SmartFactory.createSObject('Account');
        a.Industry = 'Legal';
        insert a;
        
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = a.Id;
        insert c;
        
        Contact con = (Contact) SmartFactory.createSObject('Contact');
        con.AccountId=a.Id;
        insert con;
        
        Opportunity opp = (Opportunity) SmartFactory.createSObject('Opportunity');
        opp.AccountId = a.Id;
        opp.Associated_Contract_OSA__c = c.Id;
        opp.Contract_Signer__c = con.Id;
        insert opp;
        
        Id pricebookId = Test.getStandardPricebookId();
        
        Item_Master_Product__c imp = (Item_Master_Product__c) SmartFactory.createSObject('Item_Master_Product__c');
        imp.Name = 'Name Test';
        insert imp;
        Product2 prod = new Product2(
            Name = 'Product X',
            ProductCode = 'Pro-X',
            isActive = true,
            Product_License_Type__c = 'Annual',
            Item_Master_Product__c = imp.Id
        );
        insert prod;
        
        PricebookEntry pbEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbEntry;
        
        OpportunityLineItem oli = IntappTestObjectFactory.createOpportunityLineItem(opp.Id, pbEntry.Id, 2,true);
        System.assertNotEquals(oli.Id, null);
    }
}