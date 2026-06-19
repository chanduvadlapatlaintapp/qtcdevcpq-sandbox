@isTest
private class QuoteExtControllerTests {
    @testSetup
    static void setup(){
        Account account = IntappTestObjectfactory.createAccount(true);
        
        Contact con = (Contact) SmartFactory.createSObject('Contact');
        con.AccountId = account.Id; 
        insert con;
        
        Contract ctr = (Contract) SmartFactory.createSObject('Contract');
        ctr.AccountId = account.Id;
        insert ctr;
        
        Opportunity opportunity = (Opportunity) SmartFactory.createSObject('Opportunity');
        opportunity.AccountId = account.Id;
        opportunity.Associated_Contract_OSA__c = ctr.Id;
        opportunity.Contract_Signer__c = con.Id;
        opportunity.Requested_Contract_Expiration__c = Date.today();
        opportunity.Initial_Software_Term_Length_Months__c = 12;
        insert opportunity;
        
        Profile profile = [select id from profile where name='System Administrator' LIMIT 1]; 
        User user = createuser('Testing', '', 'test@testintapp.com', profile.Id, 'intapp_1', 'UTF-8', 'en_US', 'en_US', 'America/Los_Angeles', 'stdtusr@testintapp.com', '', true);
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c = '25-FS AM - NA IB Midmarket';
        AppMatrix1.Approver_Role__c = 'Segment Lead';
        AppMatrix1.Approver_User__c = user.Id;
        insert AppMatrix1;

        Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
        prodObj.Name = 'Testproduct';
        prodObj.IsActive = true;
        prodObj.ProductCode = '123462';
        insert prodObj;

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=Test.getStandardPricebookId(), Product2Id=prodObj.id, UnitPrice=1, IsActive=True);
        insert pbe; 
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket';
        newQuote.SBQQ__Opportunity2__c = opportunity.Id;
        newQuote.SBQQ__Account__c = account.Id;
        newQuote.SBQQ__SubscriptionTerm__c = 36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.Subsidiary__c = '01:200 Integration Appliance (US)';
        newQuote.Bill_To_Account__c =  account.Id;
        newQuote.Ship_To_Account__c =  account.Id;
        newQuote.Quote_Stage__c = 'Configure Products';
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.SBQQ__StartDate__c = system.today();
        newQuote.ApprovalStatus__c='Error';
        insert newQuote;

        Test.startTest();
            SBQQ.TriggerControl.disable();
            SBQQ__QuoteLine__c testqli1 = new SBQQ__QuoteLine__c();
            testqli1.SBQQ__Quote__c = newQuote.Id;
            testqli1.SBQQ__Quantity__c = 1;        
            testqli1.SBQQ__Product__c = prodObj.id;
            testqli1.Print_at_Quote__c = true;
            testqli1.SBQQ__CustomerPrice__c = 25;
            insert testqli1;
        Test.stopTest();
        SBQQ.TriggerControl.enable();
     /*   newQuote.ApprovalStatus__c='Pending';
        newQuote.Quote_Stage__c = 'Finalize OSA';
        newQuote.Contract_Master_Terms__c = 'URL Terms';
        newQuote.Counter__c=20;
        update newQuote; */
        system.assertEquals('Error',newQuote.ApprovalStatus__c);
    }
    private static List<SBQQ__Quote__c> getQuoteList(){
        return [SELECT Id
                , SBQQ__Account__c
                , Segment_Lead__c
                , Industry_Sales_Lead__c
                , Services_Segment_Lead__c
                , SVP_Sales__c
                , SVP_Services__c
                , Industry_President__c
                , COO__c
                , SBQQ__Opportunity2__c
                , SBQQ__SubscriptionTerm__c
                , First_Segment_Months__c
                , License_Basis__c
                , OP4I_Sales_Segment__c
                , ApprovalStatus__c,SBQQ__StartDate__c
                FROM SBQQ__Quote__c LIMIT 1];
    }
    
    private static User getUser(){
        return [SELECT Id
                FROM User
                WHERE Email = 'test@testintapp.com'
                LIMIT 1];
    }
    
    private static User createUser(String lastName, string firstName, string email, String profileId, 
                                   string alias, String emailEncodingKey, string languageLocaleKey,
                                   string localeSidKey, string timeZoneSidKey, string userName,
                                   string communityNickname, Boolean create){
                                       User user = new User();
                                       user.LastName = lastName;
                                       user.FirstName = firstName;
                                       user.Email = email;
                                       user.EmailEncodingKey = emailEncodingKey;
                                       user.LanguageLocaleKey = languageLocaleKey;
                                       user.LocaleSidKey = localeSidKey;
                                       user.TimeZoneSidKey = timeZoneSidKey;
                                       user.ProfileId = profileId;
                                       user.Alias = alias;
                                       user.UserName = userName;
                                       user.CommunityNickname = communityNickname + '-' + (Math.random() * 10000);
                                       if(create)
                                       {
                                           insert user;
                                       }
                                       return user;
    }
    
    testMethod static void testSubmit1() {
        
        List<SBQQ__Quote__c> quotelist = getQuoteList();
        
        for(SBQQ__Quote__c quote : quoteList){
            quote.Segment_Lead__c = null;
            quote.Expected_Signaure_Date_Booking_Date__c = System.today().addDays(-75);    
        }
        update quoteList;
        
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quoteList[0]));
        con.onSubmit();
        SBQQ__Quote__c quote11 = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quoteList[0].Id LIMIT 1];
        Test.stopTest();
        
        System.assertEquals('Approved', quote11.ApprovalStatus__c);
    }
    
    testMethod static void testRecall1() {
        List<SBQQ__Quote__c> quotelist = getQuoteList();
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quotelist[0]));
        con.onRecall();
        SBQQ__Quote__c quote = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quotelist[0].Id LIMIT 1];
        Test.stopTest();
        System.assertEquals('Recalled', quote.ApprovalStatus__c);
    }
    testMethod static void testPerviewApproval() {
        Account acc = IntappTestObjectFactory.createAccount(true);
        acc.Industry = 'Test Industry';
        acc.SBQQ__RenewalModel__c = 'Contract Based';
        acc.OP4I_Sales_Segment__c = '25-FS AM - APAC';
        update acc;
        Id pricebookId = Test.getStandardPricebookId();
        
        Opportunity opp = (Opportunity) SmartFactory.createSObject('Opportunity');
        opp.Name= 'TestOppoty';
      opp.AccountId = acc.Id;
        opp.StageName = '01. Qualify';
      opp.Requested_Contract_Expiration__c = Date.today();
      opp.Initial_Software_Term_Length_Months__c = 12;
      insert opp;
        
        opp.Pricebook2Id = pricebookId;
        update opp;

        Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
        prodObj.Name = 'Testproduct';
        prodObj.IsActive = true;
        prodObj.ProductCode = '123462';
        insert prodObj;
        
        Product2 prodObj1 = (Product2) SmartFactory.createSObject('Product2');
        prodObj1.Name = 'Testproduct2';
        prodObj1.IsActive = true;
        prodObj1.ProductCode = '12346289';
        insert prodObj1;

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=pricebookId, Product2Id=prodObj.id, UnitPrice=1, IsActive=True);
        insert pbe; 
        
        List<SBQQ__Quote__c> quotelist = getQuoteList();
        for(SBQQ__Quote__c newQuote : quoteList){
            newQuote.Expected_Signaure_Date_Booking_Date__c = System.today().addDays(40);
            newQuote.OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket';   
        }
        update quoteList;
        
        SBQQ.TriggerControl.disable();
        SBQQ__QuoteLine__c testqli1 = new SBQQ__QuoteLine__c();
        testqli1.SBQQ__Quote__c = quoteList[0].Id;
        testqli1.SBQQ__Quantity__c = 1;        
        testqli1.SBQQ__Product__c = prodObj.id;
        testqli1.Print_at_Quote__c = true;
        testqli1.SBQQ__CustomerPrice__c = 25;
        testqli1.SBQQ__SegmentIndex__c = 10;
        testqli1.Product_Type__c = 'Training';
        insert testqli1;
        SBQQ.TriggerControl.enable();

        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quoteList[0]));
        con.onPerviewApproval();
        SBQQ__Quote__c quote = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quoteList[0].Id LIMIT 1];
        Test.stopTest();
        System.assertEquals('Error', quote.ApprovalStatus__c);
        
    }
    testMethod static void testPerviewApproval2() {
        Account acc = IntappTestObjectFactory.createAccount(true);
        acc.Industry = 'Test Industry';
        acc.SBQQ__RenewalModel__c = 'Contract Based';
        acc.OP4I_Sales_Segment__c = '25-FS AM - APAC';
        update acc;
        Id pricebookId = Test.getStandardPricebookId();
        
        Opportunity opp = (Opportunity) SmartFactory.createSObject('Opportunity');
        opp.Name= 'TestOppoty';
      opp.AccountId = acc.Id;
        opp.StageName = '01. Qualify';
      opp.Requested_Contract_Expiration__c = Date.today();
      opp.Initial_Software_Term_Length_Months__c = 12;
      insert opp;
        
        opp.Pricebook2Id = pricebookId;
        update opp;
    Product_Line__c p3 = (Product_Line__c) SmartFactory.createSObject('Product_Line__c');
        p3.name = 'Other';
        p3.Active__c = true;
        p3.Deployment__c = 'On-Premise';
        insert p3;  
        Product2 prodObj = (Product2) SmartFactory.createSObject('Product2');
        prodObj.Name = 'Testproduct';
        prodObj.Product_LineNew__c = p3.Id;
         prodObj.IsActive = true;
        prodObj.ProductCode = '123462';
        insert prodObj;
    
        
        Product2 prodObj1 = (Product2) SmartFactory.createSObject('Product2');
        prodObj1.Name = 'Testproduct2';
        prodObj1.IsActive = true;
        prodObj1.Product_LineNew__c = p3.Id;
        prodObj1.ProductCode = '12346289';
        insert prodObj1;

        PricebookEntry pbe = new PricebookEntry(Pricebook2Id=pricebookId, Product2Id=prodObj.id, UnitPrice=1, IsActive=True);
        insert pbe; 
        
        List<SBQQ__Quote__c> quotelist = getQuoteList();
        for(SBQQ__Quote__c newQuote : quoteList){
            newQuote.Expected_Signaure_Date_Booking_Date__c = System.today().addDays(40);
            newQuote.OP4I_Sales_Segment__c = '25-FS AM - NA IB Midmarket';  
        }
        update quoteList;
        
        SBQQ.TriggerControl.disable();
        SBQQ__QuoteLine__c testqli1 = new SBQQ__QuoteLine__c();
        testqli1.SBQQ__Quote__c = quoteList[0].Id;
        testqli1.SBQQ__Quantity__c = 1;        
        testqli1.SBQQ__Product__c = prodObj.id;
        testqli1.Print_at_Quote__c = true;
        testqli1.SBQQ__CustomerPrice__c = 25;
        testqli1.SBQQ__SegmentIndex__c = 10;
        testqli1.Product_Type__c = 'Services';
        insert testqli1;
        SBQQ.TriggerControl.enable();

        Test.startTest();
        List<SBQQ__Quote__c> testList = new List<SBQQ__Quote__c>();
        testList.add(quoteList[0]);
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quoteList[0]));
        QuoteExtController con1 = new QuoteExtController(new ApexPages.StandardSetController(testList));
        con.onPerviewApproval();
        SBQQ__Quote__c quote = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quoteList[0].Id LIMIT 1];
        Test.stopTest();
        System.assertEquals('Error', quote.ApprovalStatus__c);
    }
}