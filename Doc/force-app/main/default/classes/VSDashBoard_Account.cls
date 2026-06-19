public without sharing class VSDashBoard_Account { 
    private final Account account;
        
    public VSDashBoard_Account() 
    {
        account = [SELECT Id, Name, Site, Territory__c, Hot_List_Case_Count__c, Hot_List_Status__c, At_Risk_Status__c, At_Risk_Count__c, IntApp_Account_Number__c 
        FROM Account WHERE Id =:ApexPages.currentPage().getParameters().get('id')];
    }
    
    public Account getAccount() {
        return account;
    }
    
   public List<Case> getCases(){  
     return [SELECT Id,CaseNumber,Status,Subject, Priority FROM Case WHERE Account.Id = :account.Id AND isClosed = false  AND Record_Type_Name__c <> 'Survey'];  
   }  
    public List<Subscription__c> getSubscriptions() {
        return [SELECT Id, Name, CSM_Health_Rating__c, Product_Line__c, Customer_Lifecycle_Stage__c, At_Risk_Count__c, At_Risk_Flag__c 
        FROM Subscription__c WHERE Account__c = :account.Id];// AND (Customer_Lifecycle_Stage__c LIKE 'In Production%') AND Status__c = 'Active'];
    }
 }