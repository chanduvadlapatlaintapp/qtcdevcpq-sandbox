public with sharing class IntappTestObjectFactory {
    
    
    public static User createUser(){
        
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User user = (User) SmartFactory.createSObject('User');
        user.Alias = 'standt'; 
        user.Email='standarduser@intapp.com'; 
        user.EmailEncodingKey='UTF-8'; 
        user.LastName='Testing';
        user.LanguageLocaleKey='en_US'; 
        user.LocaleSidKey='en_US'; 
        user.ProfileId = p.Id; 
        user.TimeZoneSidKey='America/Los_Angeles'; 
        user.UserName='standarduser@intapp.com';
        return user;
    }
    
    public static Subscription__c createSubscription(Boolean isInsert)
    {
        Subscription__c subscription = (Subscription__c) SmartFactory.createSObject('Subscription__c');
        if (isInsert) {
            insert subscription;
        }
        return subscription;
    }
    
    public static Account createAccount(Boolean isInsert)
    {
        Account account = (Account) SmartFactory.createSObject('Account');
        account.Name = 'Test Account';
        account.BillingCountry = 'India';
        account.BillingState = 'Punjab';
        account.Industry = 'Chemicals';
        account.CurrencyIsoCode = 'USD';
        account.SBQQ__RenewalModel__c = 'Contract Based';
        account.OP4I_Sales_Segment__c = '01-Legal - APAC';
        if (isInsert) {
            insert account;
        }
        return account;
    }
    
    public static Account createAccount()
    {
        return createAccount(false);
    }
    
    public static Invoice__c createInvoice(Boolean isInsert)
    {
        Invoice__c i = (Invoice__c) SmartFactory.createSObject('Invoice__c');
        if (isInsert)
        {
            insert i;
        }
        return i;
    }
    
    public static Contract createContract(Id accountID)
    {
        Contract c = (Contract) SmartFactory.createSObject('Contract');
        c.AccountId = accountID;
        c.Name='test contract';
        c.Status='Specialist Approval Needed';
        c.StartDate=Date.TODAY();
        c.EndDate=Date.Today().addDays(5);
        c.Type__c='Standard';
        c.OSA_Type__c='Other';
        c.Subsidiary__c = '01:200 Integration Appliance (US)';
        return c;
    }
    
    public static Contact createContact()
    {
        return createContact(false);
    }
    
    public static Contact createContact(Boolean isInsert)
    {
        Contact contact = (Contact) SmartFactory.createSObject('Contact');
        contact.FirstName = 'Test First';
        contact.LastName = 'Test Last';
        contact.CurrencyIsoCode = 'USD';
        if (isInsert) {
            insert contact;
        }
        return contact;
    }
    
    public static Opportunity createOpportunity()
    {
        Opportunity opp = (Opportunity) SmartFactory.createSObject('Opportunity');
        opp.Name = 'Test Opportunity';
        opp.StageName='Evaluation of Options';
        opp.CloseDate=System.today();
        opp.Requested_Contract_Expiration__c = Date.today();
        opp.Initial_Software_Term_Length_Months__c = 12;        
        opp.Type = 'Accounting Adjustment';
        return opp;
    }
    
    public static SBQQ__Quote__c createSBQQQuote()
    {
        SBQQ__Quote__c sbqqQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        return sbqqQuote;
    }
    
    public static Approvers_Matrix__c createApproversMatrix(){
        Approvers_Matrix__c approversMatrix = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        approversMatrix.Sales_Segment__c = '03-Legal EMEA';
        approversMatrix.Approver_Role__c = 'Segment Lead';
        return approversMatrix;
    }
    
    public static Item_Master_Product__c createItemMaster(Boolean isInsert) {
        Item_Master_Product__c item   = new Item_Master_Product__c();
        item.Item_Name__c  = 'test name';
        item.CurrencyIsoCode = 'USD';
        
        if(isInsert) {
            insert item;
        }
        return item;
    }
    
    public static ACV_Allocation__c createAcvAllocation(Id itemMaster , Boolean isInsert) {
        ACV_Allocation__c acvLocation   = new ACV_Allocation__c();
        acvLocation.Product_Line__c = 'Wall Builder';
        acvLocation.Item_Master_Product__c = itemMaster;
        acvLocation.CurrencyIsoCode = 'USD';
        
        if(isInsert) {
            insert acvLocation;
        }
        return acvLocation;
    }
    
    public static Product2 createProduct(Boolean isInsert) {
        Product2 prod = new Product2();
        prod.Name = 'Test Prd1';
        prod.Family = 'Major';
        prod.IsActive = true;
        prod.ProductCode = '1234';
        if(isInsert) {
            insert prod;
        }
        return prod;
    }
    
    public static OpportunityLineItem createOpportunityLineItem(Id oppId, Id pbEntryId, double unitPrice, Boolean isInsert) {
        OpportunityLineItem oli = new OpportunityLineItem();
        oli.opportunityid = oppId; 
        oli.pricebookentryid = pbEntryId; 
        oli.unitprice = unitPrice;
        oli.quantity  = 2;
        if(isInsert) {
            insert oli;
        }
        return oli;
    }
    
    public static Campaign createCampaign(Boolean isInsert) {
        Campaign cmp = new Campaign();
        cmp.Name = 'Test campaign';
        
        if(isInsert) {        
            insert cmp;   
        }
        return cmp; 
    }
    // public static blng__Payment__c createPayment()
    // {
    //     blng__Payment__c payment = (blng__Payment__c) SmartFactory.createSObject('blng__Payment__c');
    //     return payment;
    // }
    //     public static blng__CreditNote__c createCreditnote()
    // {
    //     blng__CreditNote__c creditnote = (blng__CreditNote__c) SmartFactory.createSObject('blng__CreditNote__c');
    //     return creditnote;
    // }
}