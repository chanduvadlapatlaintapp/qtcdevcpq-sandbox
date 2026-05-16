@isTest
Public class AssignDefaultApproversControllerTest{
    @isTest
    private static void doProcessContractDefaultApproversVerify(){
        // Arrange
        String contractId;
        Database.SaveResult dsr;
        Account acc = new Account(Name = 'TestClsAcc', Industry = 'Banking' ,Type ='Prospect', Rating = 'Hot' );
        insert acc;
        
        Date dtToday = Date.today();
        Opportunity opp = new Opportunity(Name= 'TestOpp1805' , CloseDate = dtToday, StageName='Prospecting' , Amount = 8008);
        opp.AccountId = acc.Id;
        opp.Requested_Contract_Expiration__c = Date.today();
        opp.Initial_Software_Term_Length_Months__c = 12;
        insert opp;
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix1.Approver_Role__c ='Segment Lead';
        AppMatrix1.Approver_User__c =userinfo.getUserId();
        insert AppMatrix1;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opp.Id;
        newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        newQuote.ApprovalStatus__c = 'Pending';    
        insert newQuote;
        
        Contract drContract;
        drContract=new Contract(AccountId=acc.Id);
        drContract.SBQQ__Quote__c = newQuote.ID;
        dsr=Database.insert(drContract,false);
        contractId = drContract.Id;
        
        // Act
        Test.startTest();
        PageReference pageref = new PageReference('/'+contractId);
        Test.setCurrentPage(pageref);
        pageref.getParameters().put('Id', String.valueOf(contractId));
        
        Contract contract1 = [SELECT Id
                              , Approval_Status__c
                              , SBQQ__Quote__r.ApprovalStatus__c
                              FROM Contract
                              WHERE Id = :contractId LIMIT 1];
        
        contract1.SBQQ__Quote__c = newQuote.ID;
        update contract1;
        
        AssignDefaultApproversController obj = new AssignDefaultApproversController(null);
        obj.doProcessContractDefaultApprovers();
        Test.stopTest();
        
        Account accLst = [SELECT id, Type FROM Account WHERE Type = 'Prospect' LIMIT 1];
        System.assertNotEquals(null, accLst.Id);
    }
    @isTest
    private static void doProcessContractDefaultApproversNullQuote(){
        // Arrange   
        String contractId;
        Database.SaveResult dsr;
        Account acc = new Account(Name = 'TestClsAcc', Industry = 'Banking' ,Type ='Prospect', Rating = 'Hot' );
        insert acc;
        
        Date dtToday = Date.today();
        Opportunity opp = new Opportunity(Name= 'TestOpp1805' , CloseDate = dtToday, StageName='Prospecting' , Amount = 8008);
        opp.AccountId = acc.Id;
        opp.Requested_Contract_Expiration__c = Date.today();
        opp.Initial_Software_Term_Length_Months__c = 12;
        insert opp;
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix1.Approver_Role__c ='Segment Lead';
        AppMatrix1.Approver_User__c =userinfo.getUserId();
        insert AppMatrix1;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opp.Id;
        newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        insert newQuote;
        
        Contract drContract;
        drContract=new Contract(AccountId=acc.Id);
        drContract.SBQQ__Quote__c = null;
        dsr=Database.insert(drContract,false);
        contractId = drContract.Id;
        
        // Act
        Test.startTest();
        PageReference pageref = new PageReference('/'+contractId);
        Test.setCurrentPage(pageref);
        pageref.getParameters().put('Id', String.valueOf(contractId));
        
        Contract contract1 = [SELECT Id
                              , Approval_Status__c
                              , SBQQ__Quote__r.ApprovalStatus__c
                              FROM Contract
                              WHERE Id = :contractId LIMIT 1];
        
        contract1.SBQQ__Quote__c = null;
        update contract1;
        
        AssignDefaultApproversController obj = new AssignDefaultApproversController(null);
        obj.doProcessContractDefaultApprovers();
        Test.stopTest();
        
        Account accLst = [SELECT id, Type FROM Account WHERE Type = 'Prospect' LIMIT 1];
        System.assertNotEquals(null, accLst.Id);
    }
    @isTest
    private static void doProcessContractDefaultApproversPendingApproval(){
        // Arrange
        String contractId;
        Database.SaveResult dsr;
        Account acc = new Account(Name = 'TestClsAcc', Industry = 'Banking' ,Type ='Prospect', Rating = 'Hot' );
        insert acc;
        Date dtToday = Date.today();
        
        Opportunity opp = new Opportunity(Name= 'TestOpp1805' , CloseDate = dtToday, StageName='Prospecting' , Amount = 8008);
        opp.AccountId = acc.Id;
        opp.Requested_Contract_Expiration__c = Date.today();
        opp.Initial_Software_Term_Length_Months__c = 12;
        insert opp;
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix1.Approver_Role__c ='Segment Lead';
        AppMatrix1.Approver_User__c =userinfo.getUserId();
        insert AppMatrix1;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opp.Id;
        newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.ApprovalStatus__c = 'Pending';
        newQuote.License_Basis__c = 'Lawyers';
        insert newQuote;
        
        Contract drContract;
        drContract=new Contract(AccountId=acc.Id);
        drContract.SBQQ__Quote__c = newQuote.ID;
        drContract.Approval_Status__c = 'Pending';    
        dsr=Database.insert(drContract,false);
        contractId = drContract.Id;
        
        // Act            
        Test.startTest();
        PageReference pageref = new PageReference('/'+contractId);
        Test.setCurrentPage(pageref);
        pageref.getParameters().put('Id', String.valueOf(contractId));
        
        Contract contract1 = [SELECT Id
                              , Approval_Status__c
                              , SBQQ__Quote__r.ApprovalStatus__c
                              FROM Contract
                              WHERE Id = :contractId LIMIT 1];
        
        contract1.SBQQ__Quote__c = newQuote.ID;
        update contract1;
        
        AssignDefaultApproversController obj = new AssignDefaultApproversController(null);
        obj.doProcessContractDefaultApprovers();
        Test.stopTest();
        Account accLst = [SELECT id, Type FROM Account WHERE Type = 'Prospect' LIMIT 1];
        System.assertNotEquals(null, accLst.Id);
    }
    @isTest    
    private static void doProcessContractDefaultApproversException(){
        // Arrange
        Database.SaveResult dsr;
        Account acc = new Account(Name = 'TestClsAcc', Industry = 'Banking' ,Type ='Prospect', Rating = 'Hot' );
        insert acc;
        
        Date dtToday = Date.today();
        Opportunity opp = new Opportunity(Name= 'TestOpp1805' , CloseDate = dtToday, StageName='Prospecting' , Amount = 8008);
        opp.AccountId = acc.Id;
        opp.Requested_Contract_Expiration__c = Date.today();
        opp.Initial_Software_Term_Length_Months__c = 12;
        insert opp;
        
        Approvers_Matrix__c appMatrix1 = (Approvers_Matrix__c) SmartFactory.createSObject('Approvers_Matrix__c');
        AppMatrix1.Sales_Segment__c ='03-Legal EMEA';
        AppMatrix1.Approver_Role__c ='Segment Lead';
        AppMatrix1.Approver_User__c =userinfo.getUserId();
        insert AppMatrix1;
        
        SBQQ__Quote__c newQuote = (SBQQ__Quote__c) SmartFactory.createSObject('SBQQ__Quote__c');
        newQuote.SBQQ__Opportunity2__c = opp.Id;
        newQuote.SBQQ__Account__c = acc.Id;
        newQuote.SBQQ__SubscriptionTerm__c =36;
        newQuote.First_Segment_Months__c = 12;
        newQuote.License_Basis__c = 'Lawyers';
        insert newQuote;
        
        Contract drContract;
        drContract=new Contract(AccountId=acc.Id);
        drContract.SBQQ__Quote__c = newQuote.Id;
        dsr=Database.insert(drContract,false);
        
        // Act
        Test.startTest();
        AssignDefaultApproversController obj = new AssignDefaultApproversController(null);
        obj.doProcessContractDefaultApprovers();       
        Test.stopTest();
        Account accLst = [SELECT id, Type FROM Account WHERE Type = 'Prospect' LIMIT 1];
        System.assertNotEquals(null, accLst.Id);
    }
}