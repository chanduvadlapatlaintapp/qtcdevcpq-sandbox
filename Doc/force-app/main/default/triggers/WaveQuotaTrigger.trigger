/***************************************************************************************************
Creadted By: Anil 

Purpose: To verify Duplicates and validations before insert of a Wave Quota

****************************************************************************************************/

trigger WaveQuotaTrigger on Wave_Quota__c (before insert, before update) {
                               


    Map<String, set<string>> usrAndQtr = new Map<String, set<string>>();
    Map<String, set<string>> usrAndYr = new Map<String, set<string>>();
    Map<String, set<string>> usrAndPrac = new Map<String, set<string>>();
    Map<string, list<Wave_Quota__c>> usrAndWQt = new map<string, list<Wave_Quota__c>>();
    
    set<string> usrIds = new set<string>();
    map<string, string> usrRole = new map<string, string>();
    
    for(Wave_Quota__c wqts : Trigger.new){
        usrIds.add(wqts.Sales_Rep__c);
        if(usrAndWQt.containsKey(wqts.Sales_Rep__c)){
            usrAndWQt.get(wqts.Sales_Rep__c).add(wqts); 
        }
        else {
                usrAndWQt.put(wqts.Sales_Rep__c, new list<Wave_Quota__c>{wqts});    
    
        }
        
    }
    

    
    
    
     for (Wave_Quota__c wqta : Trigger.new) {         
         
        if(trigger.isInsert ||
             (trigger.oldMap.get(wqta.id).Sales_Rep__c!=wqta.Sales_Rep__c || 
              trigger.oldMap.get(wqta.id).Practice__c!=wqta.Practice__c || 
              trigger.oldMap.get(wqta.id).FY_Year__c!=wqta.FY_Year__c || 
              trigger.oldMap.get(wqta.id).Quarter__c!=wqta.Quarter__c 
              )
         ){
          boolean isPrcDup = false;
           boolean isYerDup = false;
            boolean isQtrDup = false;
             //boolean isUsrDup = false;
             

             //checking duplicate in Practise for a user
          if(usrAndPrac.containskey(wqta.Sales_Rep__c)){
              if(usrAndPrac.get(wqta.Sales_Rep__c).contains(wqta.Practice__c)){
                  
                  isPrcDup = true;
              }
              else {
                  usrAndPrac.get(wqta.Sales_Rep__c).add(wqta.Practice__c);
              }
          }
          else {
             usrAndPrac.put(wqta.Sales_Rep__c, new set<string>{wqta.Practice__c});
          }
          
         //checking duplicate in year for user
          if(usrAndYr.containskey(wqta.Sales_Rep__c)){
              if(usrAndYr.get(wqta.Sales_Rep__c).contains(wqta.FY_Year__c)){
                  
                  isQtrDup = true;
              }
              else {
                  usrAndYr.get(wqta.Sales_Rep__c).add(wqta.FY_Year__c);
              }
          }
          else {
             usrAndYr.put(wqta.Sales_Rep__c, new set<string>{wqta.FY_Year__c});
          }
          
          
         //checking duplicate in Quarter for user
          if(usrAndQtr.containskey(wqta.Sales_Rep__c)){
              if(usrAndQtr.get(wqta.Sales_Rep__c).contains(wqta.Quarter__c)){
                  
                  isYerDup = true;
              }
              else {
                  usrAndQtr.get(wqta.Sales_Rep__c).add(wqta.Quarter__c);
              }
          }
          else {
             usrAndQtr.put(wqta.Sales_Rep__c, new set<string>{wqta.Quarter__c});
          }

          
          if(isPrcDup&&isYerDup&&isQtrDup){
              
              wqta.addError('Duplicate record found with Sales Rep, Practice, FY Year and Quarter');
          } 
          
         }
         

     }
    


    // database query, find all the Wave_Quota__c matching current insert records
    
    // finding duplicates that have the same Practise and Sales rep and Quarter and year  
    
    // of the Wave_Quota__c being inserted or updated.  
    
    
       
    list<string> qtrVals = new list<string>();
    list<string> fyrVals = new list<string>();
    list<string> prcVals = new list<string>();
    
    for(string str : usrAndYr.keySet()){
        fyrVals.addAll(usrAndYr.get(str));
    }
    for(string str : usrAndQtr.keySet()){
        qtrVals.addAll(usrAndQtr.get(str));
    }
    for(string str : usrAndPrac.keySet()){
        prcVals.addAll(usrAndPrac.get(str));
    }
    
    for (Wave_Quota__c wavQts : [SELECT id,Quarter__c,Sales_Rep__c,FY_Year__c,Practice__c FROM Wave_Quota__c
                      WHERE 
                      Sales_Rep__c IN :usrIds AND
                      FY_Year__c IN :fyrVals AND
                      Quarter__c IN : qtrVals AND
                      Practice__c IN : prcVals
                         ]) {
        
        
        //checking existing records with currently being insert / update records
        if(usrAndWQt.containskey(wavQts.Sales_Rep__c)){
            for(Wave_Quota__c wqt : usrAndWQt.get(wavQts.Sales_Rep__c)){
                
                if(wqt.Quarter__c==wavQts.Quarter__c && 
                wqt.FY_Year__c==wavQts.FY_Year__c && 
                wqt.Practice__c==wavQts.Practice__c
                ){
                    
                    wqt.addError('Duplicate record found with Sales Rep, Practice, FY Year and Quarter');
                    
                    
                }
                
            }           
        }

        
    }
    
    
    if(trigger.isBefore && (trigger.isUpdate || trigger.isInsert) ){
        
        
        WaveQuotaTriggerHelper.defineStartDateForQuarter(trigger.new,
        trigger.isBefore, trigger.isInsert, trigger.isUpdate, trigger.oldMap, trigger.newMap);
        
        
    }
    
    
}