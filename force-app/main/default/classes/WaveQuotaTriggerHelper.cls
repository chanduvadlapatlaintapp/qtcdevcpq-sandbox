/***************************************************************************************************
Creadted By: Anil 

Purpose: a until class for Wave_Quota__c object consists actions for trigger

****************************************************************************************************/

public class WaveQuotaTriggerHelper {

  public static void defineStartDateForQuarter(list<Wave_Quota__c> waveQotas, boolean isBefore, boolean isInsert, boolean isUpdate,
  map<id,Wave_Quota__c> OldMap, map<id,Wave_Quota__c> newMap){
  
  
    Organization orgRec = [select FiscalYearStartMonth,UsesStartDateAsFiscalYearName from Organization where id=:Userinfo.getOrganizationId()];

    integer startMonth = orgRec.FiscalYearStartMonth;
    boolean isStartMonthBased = orgRec.UsesStartDateAsFiscalYearName;
    

  
    for(Wave_Quota__c wve : waveQotas){
    
            boolean hasModified = false;
            
          if(isBefore&&isInsert ){
              
              hasModified = true;
              
          }
          else if(
          isBefore&&isUpdate && 
          (OldMap.get(wve.id).FY_Year__c!=wve.FY_Year__c || OldMap.get(wve.id).Quarter__c!=wve.Quarter__c)
          
          ){
              
              hasModified = true;
          
          }
        
        
    if(hasModified){
        
            Date StartDate;
            string yearSelcted = wve.FY_Year__c;
            string qtrVal = wve.Quarter__c;

            if(string.isNotBlank(qtrVal) && string.isNotBlank(yearSelcted)){
                
                integer FYear = integer.valueOf(yearSelcted);

                FYear = isStartMonthBased==false ? FYear-1 : FYear;
                //startMonth = isStartMonthBased==false ? startMonth+1 : startMonth; 
                
                
                if(qtrVal=='Q1'){
                    
                    StartDate = date.newInstance(FYear, startMonth, 1);
                }
                else if(qtrVal=='Q2'){
                    
                    startMonth = startMonth+3;
                    FYear = startMonth>12 ? FYear+1 : FYear;
                    startMonth = startMonth>12 ? startMonth-12 : startMonth;
                    
                    
                    
                    StartDate = date.newInstance(FYear, startMonth, 1);
                }
                else if(qtrVal=='Q3'){
                    
                    startMonth = startMonth+6;
                    FYear = startMonth>12 ? FYear+1 : FYear;
                    startMonth = startMonth>12 ? startMonth-12 : startMonth;
                    
                    
                    StartDate = date.newInstance(FYear, startMonth, 1);
                }
                else if(qtrVal=='Q4'){
                    
                    startMonth = startMonth+9;
                    FYear = startMonth>12 ? FYear+1 : FYear;
                    startMonth = startMonth>12 ? startMonth-12 : startMonth;
                    
                    
                    StartDate = date.newInstance(FYear, startMonth, 1);
                }

                
                    if(StartDate!=null){
                        wve.Start_Date__c = StartDate;
                    }
            }
    }
    

    }
    

  
  
  
  
  }


}