/********************************************************************************     
 *  Name             :  CaseTriggerHandler
 *  Author           :  Hiforte Technologies
 *  Description      :  1. Identifies if an Account has Active projects, for Cases
 *                                  
 *  Change history   :
 *  Date                Author                          Description
 *  02/24/14        Vasu Pulipati                   Created
 *  05/14/19        Venkat                          Added before insert and update functions
 *  05/14/19        Venkat                          Added functionality to update support levels
 ********************************************************************************/
public with sharing class CaseTriggerHandler {
    public static void beforeInsert(List<Case> newCases){  
        updateOpenDate(newCases);
        UpdateSupportLevels(newCases);
        surveyCaseUpdateFields(newCases);
    }
    
    public static void beforeUpdate(List<Case> newCases, Map<ID, Case> newCaseMap,  List<Case> oldCases, Map<ID,Case> oldCaseMap){
       
        updateProjectDates(newCases, oldCases, oldCaseMap);
        updateOpenDate(newCases);  
        UpdateSupportLevels(newCases);
        surveyCaseUpdateFields(newCases);
        assignToFMQueue(newCases, oldCaseMap);
    }
    
    public static void afterInsert(List<Case> newCases, Map<ID, Case> newCaseMap){
        if(!newCases.IsEmpty())
        {           
         hotListCaseCount(newCases);
        }
        
    }
    
    public static void afterUpdate(List<Case> newCases, Map<ID, Case> newCaseMap,  List<Case> oldCases, Map<ID, Case> oldCaseMap){
        if(!newCases.IsEmpty())
        {           
         hotListCaseCount(newCases);
        }
        
    }
    
    public static void afterDelete(List<Case> oldCases, Map<ID, Case> oldCaseMap){
        if(!oldCases.IsEmpty())
        {           
         hotListCaseCount(oldCases);
        }
        
    }
    
    public static void afterUnDelete(List<Case> newCases, Map<ID, Case> newCaseMap){
        if(!newCases.IsEmpty())
        {           
         hotListCaseCount(newCases);
        }
    }
    /*FreshDesk# - 33979*/
    public static void updateSupportLevels(List<Case> cases){
        //Get all case fields to check if the support level fields exists - this is done to dynamically add values to support level fields
        Set<String> caseFields = Schema.SObjectType.Case.fields.getMap().keySet();
        
        //Set Service Level Priority
        Map<String, Integer> mapSupportLevelSupportLevelPriority = new Map<String, Integer>{'Lapsed'=>0, 'LegalKey'=>1, 'Standard (Silver)'=>2, 'Premium (Gold)'=>3, 'Premium (Platinum)'=>4};
        
        //Container for all the accounts related to case
        Set<Id> accountIds = new Set<Id>();
        
        //Map of Map => Example, [0015000000cFGEd = (Time = Standard (Silver), Walls = Premium (Gold))]
        Map<Id, Map<String, String>> mapAccountsWithMapOfProductLineandServiceLevel = new Map<Id, Map<String, String>>();
        
        //Get all unique accounts related to cases
        for(Case c: Cases){
            if(!c.IsClosed){
                AccountIds.add(c.AccountId);
            }
        }
        
        System.debug('Checkpoint 1 ' + AccountIds );
        
        //Loop over all valid PODs related to the Accounts we got in the previous step - 
        for(Product_Ownership_Detail__c pOD: [SELECT Account_Name__c, Product_line_link__c, Product_line_link__r.Name, Support_Level__c 
                                              FROM Product_Ownership_Detail__c 
                                              WHERE Account_Name__c in : AccountIds
                                              AND Product_line_link__c != null
                                              AND Support_Level__c != null
                                              AND Status__c NOT IN ('Lapsed','Converted','Entitled')]){
            
            String productLineName = POD.Product_line_link__c != null ? POD.Product_line_link__r.Name: '';
            
            ProductLineName = ProductLineName.contains(' - Cloud')? ProductLineName.split(' - ')[0]: ProductLineName;
            System.debug('Checkpoint 1.1 ' +  ProductLineName);
            
            //Contruct Map of maps = Example, [0015000000cFGEd = (Time = Standard (Silver), Walls = Premium (Gold))]
            //If Map contains the account already, allow in - If not go to else at 91
            if(mapAccountsWithMapOfProductLineandServiceLevel.containsKey(POD.Account_Name__c)){
                //If Map contains the product line already, allow in - If not go to else at 87
                if(mapAccountsWithMapOfProductLineandServiceLevel.get(POD.Account_Name__c).containsKey(ProductLineName)){
                    //Its time to check if the already existing product line has a lesser service level
                    if(mapSupportLevelSupportLevelPriority.containsKey(mapAccountsWithMapOfProductLineandServiceLevel.get(POD.Account_Name__c).get(ProductLineName)) &&
                       mapSupportLevelSupportLevelPriority.containsKey(POD.Support_Level__c) &&
                       mapSupportLevelSupportLevelPriority.get(POD.Support_Level__c) > mapSupportLevelSupportLevelPriority.get(mapAccountsWithMapOfProductLineandServiceLevel.get(POD.Account_Name__c).get(ProductLineName))){
                           System.debug('Checkpoint 1.1.1 - We have already encountered this product line before and the service level is lower than ' + POD.Support_Level__c);
                           mapAccountsWithMapOfProductLineandServiceLevel.get(POD.Account_Name__c).put(ProductLineName, POD.Support_Level__c);
                       }
                }
                else{
                    mapAccountsWithMapOfProductLineandServiceLevel.get(POD.Account_Name__c).put(ProductLineName, POD.Support_Level__c);
                }
            }
            else{
                mapAccountsWithMapOfProductLineandServiceLevel.put(POD.Account_Name__c, new Map<String, String> {ProductLineName => POD.Support_Level__c});
            }
        }
        
        
        //Loop over all the cases
        for(Case c: Cases){
            if(!mapAccountsWithMapOfProductLineandServiceLevel.containsKey(c.AccountId) || mapAccountsWithMapOfProductLineandServiceLevel.get(c.AccountId) == null){
                continue;
            }
            System.debug('Checkpoint 2 - For Account '+ c.AccountId + ', the PODS are ' + mapAccountsWithMapOfProductLineandServiceLevel.get(c.AccountId));
        
            for(String productLine: mapAccountsWithMapOfProductLineandServiceLevel.get(c.AccountId).keyset()){
                //Form the name of the case field that needs to be populated - example: Support_Level_Conflicts_New__c - Make sure the field name contains the exact product line name
                String supportFieldName = 'Support_Level_' + ProductLine + '_New__c';
                
                System.debug('Checkpoint 3 - ' + SupportFieldName + '? = ' + CaseFields.contains(SupportFieldName.trim().toLowerCase()));
                
                //Check if the case object has this field
                if(!CaseFields.contains(SupportFieldName.trim().toLowerCase())){ 
                    continue;
                }
                
                //Check if there is already a value on this field and if it is correct                  
                if(c.get(SupportFieldName) != mapAccountsWithMapOfProductLineandServiceLevel.get(c.AccountId).get(ProductLine)){    
                    c.put(SupportFieldName, mapAccountsWithMapOfProductLineandServiceLevel.get(c.AccountId).get(ProductLine)); 
                    System.debug('Checkpoint 4 - ' + c.get(SupportFieldName));
                }
            }
        }
        
        if(!Trigger.isExecuting){
            update Cases;
        }
    }
    
    public static void hotListCaseCount(List<Case> newCases)
    {
        
        // get list of accounts
        Set<ID> acctIds = new Set<ID>();
        List<Account> acctsToRollup = new List<Account>();
        
        if(!newCases.IsEmpty())
        {   
            for (Case cse : newCases) {
                acctIds.add(cse.AccountId);
            }
        }
        
        if(acctIds!=null)
        {           
        for (AggregateResult ar : [SELECT AccountId AcctId, Count(id) CaseCount 
                               FROM Case 
                               where AccountId in :acctIds and Record_Type_Name__c = 'Executive Support' and
                               Status not in ('Closed - Resolved','Closed - Unresolved','Abandoned','Escalated to Engineering')
                               GROUP BY AccountId]){
        Account accObj = new Account();
        accObj.Id = (Id) ar.get('AcctId'); //---> handy trick for updates, set the id and update
        if (accObj.Hot_List_Case_Count__c != (Integer) ar.get('CaseCount'))
        {
        accObj.Hot_List_Case_Count__c = (Integer) ar.get('CaseCount');
        acctsToRollup.add(accObj);
        }
    }
                                                                     
        update acctsToRollup;       
        
    }
}
    
    public static void surveyCaseUpdateFields(List<Case> newCases)
    {
        string label = System.label.CaseIdLabel;
      // Update the Contact on the Survey Case
      if(!newCases.IsEmpty())
      {
          for(case myCase : newCases)
          {
              if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_ContactID__c != null && myCase.ContactID == null ) 
                  {
                  myCase.ContactId = myCase.Survey_ContactID__c;
                  }
                // Update the SE on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_EngineerName__c != null && myCase.Survey_SECalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_SECalculated__c = myCase.Survey_EngineerName__c;
                  }
                // Update the Adoption Consultant on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_AdoptionConsultant__c != null && myCase.Survey_ACCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_ACCalculated__c = myCase.Survey_AdoptionConsultant__c;
                  }
                // Update the Project Manager on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_ProjectManagerName__c != null && myCase.Survey_ProjectManagerName__c != label && myCase.Survey_PMCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_PMCalculated__c = myCase.Survey_ProjectManagerName__c;
                  }            
                // Update the Account on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_FirmName__c != null && myCase.Survey_AccountCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_AccountCalculated__c = myCase.Survey_FirmName__c;
                  } 
                // Update the Principal Consultant on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_Principal_Consultant_Name__c != null && myCase.Survey_Principal_Consultant_Name__c != label && myCase.Survey_PC_Calculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_PC_Calculated__c = myCase.Survey_Principal_Consultant_Name__c;
                  }
                    // Update the Principal Consultant on the Survey Case
                if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_Solution_Architect_Name__c != null && myCase.Survey_Solution_Architect_Name__c != label && myCase.Survey_SA_Calculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
                  {
                  myCase.Survey_SA_Calculated__c = myCase.Survey_Solution_Architect_Name__c;
                  }
            }         
        } 
    }
    
    public static void updateOpenDate(List<Case> newCases)
    {
        if(!newCases.IsEmpty())
        {   
            for(case caseObj : newCases)
            {   
             if( caseObj.PSCase_Kickoff_Meeting_Date__c != null && caseObj.DateOpen__C == null ) 
              {
               caseObj.DateOpen__C = caseObj.PSCase_Kickoff_Meeting_Date__c;
              } 
            }
        }       
        
    }
    
    public static void updateProjectDates(List<Case> newCases,  List<Case> oldCases, Map<ID,Case> oldCaseMap)
    {
        if(!newCases.IsEmpty())
        {
            for(case caseObj : newCases)
            {   
            caseObj.Project_Exp_Compl_Date_Prior__c = oldCaseMap.get(caseObj.id).PSCase_Project_Exp_Compl_Date__c;
            caseObj.Confidence_in_Completion_Date_Prior__c = oldCaseMap.get(caseObj.id).PSCase_Confidence_in_Completion__c; 
            }
        }       
        
    }
    
    /**
     * @description Assigns FM Queue as owner to Cases whose Type is changed to Finance Ops Support.
     *              This method is intended to be used in a before update trigger context.
     * @param newCases List of new Case records (Trigger.new)
     * @param oldCaseMap Map of old Case records (Trigger.oldMap)
     */
    public static void assignToFMQueue(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        if (financeQueueId == null) {
            return;
        }
        for (Case newCase : newCases) {
            Case oldCase = oldCaseMap.get(newCase.Id);
            if (oldCase != null && newCase.Type != oldCase.Type && newCase.Type == CaseConstants.TYPE_FINANCE_OPS_SUPPORT) {
                newCase.OwnerId = financeQueueId;
            }
        }
    }
    
    
    /**
    * @description Getter method for FM Queue Id ("Finance Support" queue).
    *              Returns null if the queue is not found.
    * @return Id of the FM Queue or null if not found
    */
    @TestVisible
    private static Id financeQueueId {
        get {
            if (financeQueueId == null) {
                List<Group> queues = [
                    SELECT Id
                    FROM Group
                    WHERE Name = :CaseConstants.QUEUE_FINANCE_SUPPORT AND Type = 'Queue'
                    LIMIT 1
                ];
                if (!queues.isEmpty()) {
                    financeQueueId = queues[0].Id;
                }
            }
            return financeQueueId;
        }
        private set;
    }
}