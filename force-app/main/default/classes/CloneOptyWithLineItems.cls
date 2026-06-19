/**
* @description       : BIZ-46116-This class is an Invocable class having NYMY functionality which is invoked from Opportunity : After Update flow.
* @author            : Pankaj Kumar
* @last modified on  : 09-21-2023
* @last modified by  : Pankaj Kumar
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   07-07-2023   Pankaj Kumar   Initial Version
*
**/
public without sharing class CloneOptyWithLineItems {
    
    /**
    * @description : This method will handle NYMY opty & line Item cloning. 
    * @author Pankaj Kumar | 09-21-2023 
    * @param List<Id> recordId 
    **/ 
    @InvocableMethod(label='CloneOptyWithLineItems' description='Method to clone Opportunity And Opportunity LineItems')
    public static List<Id> cloneOpp(List<Id> recordId){
        if(!System.isBatch() && !System.isFuture()) { 
            cloneOppFuture(recordId);
        }
        return null;
    }
    
    /**
    * @description : This method will clone Opportunity & Opportunity LineItems.
    * @author Pankaj Kumar | 09-21-2023 
    * @param recordId 
    **/
    @future(callout=false)
    public static void cloneOppFuture(List<Id> recordId){
        try{
            Opportunity original = Database.query(allFields('Opportunity')+' Where Id =:recordId Limit 1');
            
            //Cloned Opty Record
            Opportunity clonedRec = original.Clone(false, true, false, false);
            if(clonedRec.Related_Opportunity__c!=null){
                clonedRec.Segment_Index__c = original.Segment_Index__c + 1;
                clonedRec.Quote_Start_Date__c = original.Quote_Start_Date__c.addMonths(12);
            }else{
                clonedRec.Related_Opportunity__c = original.id;
                if(original.Segment_Index__c == null){
                    clonedRec.Segment_Index__c = 2;
                    clonedRec.Quote_Start_Date__c = original.Quote_Start_Date__c.addMonths(original.First_Segment_Months__c.intValue());
                }
                else{
                    clonedRec.Segment_Index__c = original.Segment_Index__c + 1;
                    
                    clonedRec.Quote_Start_Date__c = original.Quote_Start_Date__c.addMonths(12);
                }
            }
            clonedRec.Name = clonedRec.Name + '_NYMYYear' + clonedRec.Segment_Index__c;
            clonedRec.OP4I_Deal_Id__c = '';
            //clonedRec.OP4I_Deal_Id__c = original.OP4I_Deal_Id__c;
            clonedRec.Deal_Type__c = 'NextYear_MultiYear';
            clonedRec.StageName = 'Selected';
            clonedRec.Source_System__c = 'SFDC';
            clonedRec.OP4I_Deal_Status__c = '';
            clonedRec.Deal_Reconciliation_Notes_OP4I__c = null;
            clonedRec.Total_Contract_Months__c = original.Total_Contract_Months__c;
            clonedRec.First_Segment_Months__c = original.First_Segment_Months__c;
            clonedRec.CloseDate = clonedRec.Quote_Start_Date__c;
            clonedRec.ACV_Type__c = original.ACV_Type__c;
            clonedRec.Start_Date__c = original.Start_Date__c;
            clonedRec.Net_Amount__c = original.Net_Amount__c;
            if(clonedRec!=null){
                insert clonedRec;
            }
            
            //Cloned OptyLines
            String strQuery = allFields('OpportunityLineItem')+' Where OpportunityId =:recordId AND Product_Type__c NOT IN (\'Services\', \'Services Discount\', \'Services (Recurring)\')';
            List<OpportunityLineItem> originalOptyLines = Database.query(strQuery);
            Map<Id,OpportunityLineItem> clonedOpportunityLineWithOriginalIdMap = new Map<Id,OpportunityLineItem>();
            List<OpportunityLineItem> clonedOptyLines = new List<OpportunityLineItem>();
            for(OpportunityLineItem ql : originalOptyLines){
                if(ql!=null){
                    OpportunityLineItem clonedLineRec = ql.Clone(false, true, false, false);
                    clonedLineRec.OpportunityId = clonedRec.Id;
                    clonedLineRec.Original_Opportunity_Product_Id__c = null;
                    clonedLineRec.unitprice=null;
                    clonedLineRec.SBQQ__QuoteLine__c=null;
                    clonedLineRec.OP4I_System_Id__c='';
                    clonedLineRec.DLIP_OP4I_ID__c = '';
                    clonedLineRec.OP4I_Deal_Id__c = '';
                    clonedLineRec.Original_Oppty_Text_Id__c = ql.id;
                   	//clonedLineRec.OP4I_Deal_Id__c = original.OP4I_Deal_Id__c;
                    if(clonedLineRec.SBQQ__ParentID__c != null){
                        clonedOptyLines.add(clonedLineRec);
                    } else{
                        clonedOpportunityLineWithOriginalIdMap.put(ql.Id,clonedLineRec);
                    }
                }
            }
            if(clonedOpportunityLineWithOriginalIdMap.values()!=null && clonedOpportunityLineWithOriginalIdMap.values().size()>0){
                insert clonedOpportunityLineWithOriginalIdMap.values();
            }
            for(OpportunityLineItem oli : clonedOptyLines){
                oli.SBQQ__ParentID__c = clonedOpportunityLineWithOriginalIdMap.get(oli.SBQQ__ParentID__c).Id;
            }
            if(clonedOptyLines!=null){
                insert clonedOptyLines;
            }

        }
        catch(Exception e){
            insert new Error_Log__c(
                Process__c = 'CloneOptyWithLineItems cloneOppFuture', 
                Exception_Message__c = e.getMessage(),
                StackTrace__c = e.getStackTraceString(), 
                Sobject_Name__c = 'Opportunity'
            );
        }
    }
    
    /**
    * @description : This method will dynamic query on the sObject. 
    * @author Pankaj Kumar | 09-21-2023 
    * @param objectName
    * @return String 
    **/    
    public static String allFields(String objectName) {
        List<String> fields = new List<String>(Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap().keySet());
        String query  = 'SELECT '+String.join(fields, ',')+' FROM '+ObjectName;
        return query;
    }
}