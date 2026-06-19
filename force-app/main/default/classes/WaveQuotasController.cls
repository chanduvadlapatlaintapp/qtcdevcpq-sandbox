/****************************************************************************************************************************
Created By: Chiru
Purpose: To show Reps Quarterly Quotas for Last Quarter, This Quarter and Next Quarter
****************************************************************************************************************************/
Public class WaveQuotasController{
    
    Public List<WaveQuotaWrapper> waveQuotaWrapList {get;set;} 
    List<Wave_Quota__c> waveQuotasQ1QuartList;
    List<Wave_Quota__c> waveQuotasQ2QuartList;
    List<Wave_Quota__c> waveQuotasQ3QuartList;
    List<Wave_Quota__c> waveQuotasQ4QuartList;   
    Set<String> repPracticeSet = new Set<String>();
    Map<Id,User> userMap;
    public list<selectOption> repsDropDwn{get;set;}
    public list<selectOption> practiseDropDwn{get;set;}
    public list<selectOption> ficalDropDwn{get;set;}
    public string selectedRep{get;set;}
    public string selectedPract{get;set;}
    public String selectedFical{get;set;}
    
    public Integer FiscalYearStartMonth{get;set;}
    boolean isUseStartDateAsFiscalYear;
    
    
    Integer currentFiscalYear;
    
    // Constructor
    Public WaveQuotasController(){
        selectedRep = '';  
        selectedPract = '';

                
        FiscalYearStartMonth = [select FiscalYearStartMonth from Organization where id=:Userinfo.getOrganizationId()].FiscalYearStartMonth;   
        isUseStartDateAsFiscalYear =  [select UsesStartDateAsFiscalYearName from Organization where id=:Userinfo.getOrganizationId()].UsesStartDateAsFiscalYearName;  
            
        selectedFical = [SELECT FiscalYearSettings.Name FROM Period WHERE Type = 'Year' AND StartDate <= TODAY AND EndDate >= TODAY].FiscalYearSettings.Name;
        currentFiscalYear = Integer.valueOf(selectedFical);
        
        repsDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        practiseDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        ficalDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        waveQuotaWrapList = new List<WaveQuotaWrapper>();        
         
        List<Wave_Quota__c> waveQuotasList = [Select Sales_Rep__c, Practice__c from Wave_Quota__c where Sales_Rep__c != null and Practice__c != '' and Practice__c != null order by Sales_Rep__r.Name];
        
        Set<Id> userRepIds = new Set<Id>();
        
        for(Wave_Quota__c W : waveQuotasList){
            repPracticeSet.add(W.Sales_Rep__c+'#'+W.Practice__c);
            userRepIds.add(W.Sales_Rep__c);
        }
        
        userMap = new Map<Id,User>([Select Id, Name from User where Id in: userRepIds]);
               
        processData();   
    }
    
    public void repsFilter(){
        
        selectedPract = '';
        practiseDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        processData();
        
    }
    
    public void practiseFilter(){
        processData();
    }
    
    public List<SelectOption> getFicalOptions() {
        List<SelectOption> ficalOptions = new List<SelectOption>();
        //ficalOptions.add(new SelectOption('','-None-'));
        

        Schema.DescribeFieldResult fieldResult = Wave_Quota__c.FY_Year__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();

        for( Schema.PicklistEntry f : ple)
        {
        ficalOptions.add(new SelectOption(f.getLabel(), f.getValue()));
        }       
        
        return ficalOptions;
    }
    
    public List<SelectOption> getQuarterOptions() {
        List<SelectOption> quarterOpt = new List<SelectOption>();
      
        

        Schema.DescribeFieldResult fieldResult = Wave_Quota__c.Quarter__c.getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();

        for( Schema.PicklistEntry f : ple)
        {
        quarterOpt.add(new SelectOption(f.getLabel(), f.getValue()));
        }       
        
        return quarterOpt;
    }
    
    
    
    
    
    Public void processData(){
        
        set<string> repsSet = new set<string>();
        set<string> practSetDups = new set<string>();
        
        repsDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        practiseDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        ficalDropDwn = new list<selectOption>{new selectOption('', '---None--')};
        
        waveQuotaWrapList =  new List<WaveQuotaWrapper>();
                
    
  
         
        //to retrieve wave quotas for each Quarter and for dyanmic fiscal year 
        
        waveQuotasQ1QuartList = [SELECT Id, Quarter__c,FY_Year__c,Sales_Rep__c, Practice__c, Quota_Amount__c from Wave_Quota__c where Sales_Rep__c != null and Practice__c != '' and Practice__c != null 
                                AND FY_Year__c=:selectedFical AND Quarter__c='Q1' ];
        
                 
        waveQuotasQ2QuartList= [SELECT Id, Sales_Rep__c,Quarter__c,FY_Year__c, Practice__c, Quota_Amount__c from Wave_Quota__c where Sales_Rep__c != null and Practice__c != '' and Practice__c != null 
                                AND FY_Year__c=:selectedFical AND Quarter__c='Q2'];
                                
        waveQuotasQ3QuartList= [SELECT Id, Sales_Rep__c,Quarter__c,FY_Year__c, Practice__c, Quota_Amount__c from Wave_Quota__c where Sales_Rep__c != null and Practice__c != '' and Practice__c != null 
                                AND FY_Year__c=:selectedFical AND Quarter__c='Q3'];
                                
        waveQuotasQ4QuartList= [SELECT Id, Sales_Rep__c,Quarter__c,FY_Year__c, Practice__c, Quota_Amount__c from Wave_Quota__c where Sales_Rep__c != null and Practice__c != '' and Practice__c != null 
                               AND FY_Year__c=:selectedFical AND Quarter__c='Q4' ];
        
        
        system.debug('--waveQuotasQ1QuartList-- '+waveQuotasQ1QuartList);
        system.debug('--waveQuotasQ2QuartList-- '+waveQuotasQ2QuartList);
        system.debug('--waveQuotasQ3QuartList-- '+waveQuotasQ3QuartList);
        system.debug('--waveQuotasQ4QuartList-- '+waveQuotasQ4QuartList);
                
        for(String S : repPracticeSet){
            
            WaveQuotaWrapper WQ = new WaveQuotaWrapper();
            
            String[] strArr = S.split('#'); 
                //preparing reps drop down and avoiding dups in drop down
                if(!repsSet.contains(userMap.get(strArr[0]).Name )){
                    
                    repsSet.add(userMap.get(strArr[0]).Name);
                    repsDropDwn.add(new selectoption(userMap.get(strArr[0]).Name, userMap.get(strArr[0]).Name) );
                    
                }                
                //preparing Practise drop down and avoiding duplicates in Practise dropdown
                if(!practSetDups.contains(strArr[1])){
                    practiseDropDwn.add(new selectoption(strArr[1], strArr[1]));
                    practSetDups.add(strArr[1]);
                }
                
                system.debug('---selectedRep-- '+selectedRep+'--selectedPract--'+selectedPract);
                
                
                                
                //to avoid same block of code in above if else checks, considering null check below                                    
                    
                    WQ.rep = userMap.get(strArr[0]).Name;                
                    WQ.practice = strArr[1];                    
                                       
                    if( (selectedRep == '' || selectedRep == null || (selectedRep != '' && WQ.rep == selectedRep)) && (selectedPract == '' || selectedPract == null || (selectedPract != '' && selectedPract == WQ.practice )) ){
                                                                          
                        WQ.q1QuarterAmount = 0;
                        WQ.q2QuarterAmount = 0;
                        WQ.q3QuarterAmount = 0;  
                        WQ.q4QuarterAmount = 0;
                        
                        WQ.q1WaveQuotaRec = new Wave_Quota__c();
                        WQ.q2WaveQuotaRec = new Wave_Quota__c();
                        WQ.q3WaveQuotaRec = new Wave_Quota__c();
                        WQ.q4WaveQuotaRec = new Wave_Quota__c();
                        
                        WQ.q1WaveQuotaRec.Sales_Rep__c = strArr[0];
                        WQ.q1WaveQuotaRec.Practice__c = strArr[1];
                        WQ.q1WaveQuotaRec.FY_Year__c = selectedFical;
                        WQ.q1WaveQuotaRec.Quarter__c = 'Q1';
                        
                        WQ.q2WaveQuotaRec.Sales_Rep__c = strArr[0];
                        WQ.q2WaveQuotaRec.Practice__c = strArr[1];
                        WQ.q2WaveQuotaRec.FY_Year__c = selectedFical;
                        WQ.q2WaveQuotaRec.Quarter__c = 'Q2';
                        
                        WQ.q3WaveQuotaRec.Sales_Rep__c = strArr[0];
                        WQ.q3WaveQuotaRec.Practice__c = strArr[1];
                        WQ.q3WaveQuotaRec.FY_Year__c = selectedFical;
                        WQ.q3WaveQuotaRec.Quarter__c = 'Q3';
                        
                        WQ.q4WaveQuotaRec.Sales_Rep__c = strArr[0];
                        WQ.q4WaveQuotaRec.Practice__c = strArr[1];
                        WQ.q4WaveQuotaRec.FY_Year__c = selectedFical;
                        WQ.q4WaveQuotaRec.Quarter__c = 'Q4';
                                                                                   
                        for(Wave_Quota__c ar : waveQuotasQ1QuartList){
                              system.debug('-ar.Sales_Rep__c-- '+ar.Sales_Rep__c+'-strArr[0]-- '+strArr[0]);                   
                              system.debug('-ar.Practice__c-- '+ar.Practice__c+'-WQ.practice-- '+WQ.practice);
                        
                              if( (ar.Sales_Rep__c == strArr[0] && (selectedRep == '' || selectedRep == null || (selectedRep != '' && ar.Sales_Rep__c == strArr[0])) ) && (ar.Practice__c == WQ.practice && (selectedPract == '' || selectedPract == null || (selectedPract != '' && selectedPract == ar.Practice__c )) ) ){

                                  WQ.q1QuarterAmount = WQ.q1QuarterAmount + ar.Quota_Amount__c;       
                                  WQ.q1WaveQuotaRec = ar;  
  
                                  break;                                                                         
                              }
                        }
                        
                        
                        for(Wave_Quota__c ar : waveQuotasQ2QuartList){
                              if( (ar.Sales_Rep__c == strArr[0] && (selectedRep == '' || selectedRep == null || (selectedRep != '' && ar.Sales_Rep__c == strArr[0])) ) && (ar.Practice__c == WQ.practice && (selectedPract == '' || selectedPract == null || (selectedPract != '' && selectedPract == ar.Practice__c )) ) ){
                                  WQ.q2QuarterAmount = WQ.q2QuarterAmount + ar.Quota_Amount__c; 
                                  WQ.q2WaveQuotaRec = ar;  
                                  break;                                                    
                              }
                        }
                        for(Wave_Quota__c ar : waveQuotasQ3QuartList){
                              if( (ar.Sales_Rep__c == strArr[0] && (selectedRep == '' || selectedRep == null || (selectedRep != '' && ar.Sales_Rep__c == strArr[0])) ) && (ar.Practice__c == WQ.practice && (selectedPract == '' || selectedPract == null || (selectedPract != '' && selectedPract == ar.Practice__c )) ) ){
                                  WQ.q3QuarterAmount = WQ.q3QuarterAmount + ar.Quota_Amount__c;         
                                  WQ.q3WaveQuotaRec = ar;  
                                  break;                                            
                              }
                        }
                        for(Wave_Quota__c ar : waveQuotasQ4QuartList){
                              if( (ar.Sales_Rep__c == strArr[0] && (selectedRep == '' || selectedRep == null || (selectedRep != '' && ar.Sales_Rep__c == strArr[0])) ) && (ar.Practice__c == WQ.practice && (selectedPract == '' || selectedPract == null || (selectedPract != '' && selectedPract == ar.Practice__c )) ) ){
                                  WQ.q4QuarterAmount = WQ.q4QuarterAmount + ar.Quota_Amount__c; 
                                  WQ.q4WaveQuotaRec = ar;
                                  break;                                                       
                              }
                        }                        
                        
                        waveQuotaWrapList.add(WQ);
                        
                 }                

        }
    }
    
    Public void updateRecords(){
        
        List<Wave_Quota__c> waveQuotaUpdateList = new List<Wave_Quota__c>();
        
        for(WaveQuotaWrapper WQ : waveQuotaWrapList){
            //if(WQ.q1WaveQuotaRec.Id != null)    
                waveQuotaUpdateList.add(WQ.q1WaveQuotaRec);
            //if(WQ.q2WaveQuotaRec.Id != null)
                waveQuotaUpdateList.add(WQ.q2WaveQuotaRec);
            //if(WQ.q3WaveQuotaRec.Id != null)    
                waveQuotaUpdateList.add(WQ.q3WaveQuotaRec);
            //if(WQ.q4WaveQuotaRec.Id != null)    
                waveQuotaUpdateList.add(WQ.q4WaveQuotaRec);
        }
        
        System.debug('/////////////// '+waveQuotaUpdateList);
        
        if(!waveQuotaUpdateList.isEmpty()){
            upsert waveQuotaUpdateList;
        }
        
        processData(); 
    } 
    
    // Wrapper class to construct a data to show reps sales quotas 
    Public class WaveQuotaWrapper {
        Public String rep {get;set;}        
        Public String practice {get;set;}
        Public String fical{get;set;}
        Public Decimal q1QuarterAmount {get;set;}
        Public Decimal q2QuarterAmount {get;set;}
        Public Decimal q3QuarterAmount {get;set;}
        Public Decimal q4QuarterAmount {get;set;}
        
        Public Wave_Quota__c q1WaveQuotaRec {get;set;}
        Public Wave_Quota__c q2WaveQuotaRec {get;set;}
        Public Wave_Quota__c q3WaveQuotaRec {get;set;}
        Public Wave_Quota__c q4WaveQuotaRec {get;set;}
        
    }
}