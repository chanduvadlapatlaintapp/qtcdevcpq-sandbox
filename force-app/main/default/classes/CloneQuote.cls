/**
 * @description       :  class for Renewal based Contract Consolidation
 * @author            : Keerthan N
 * Jira story : BIZ-47457
**/
global without sharing class  CloneQuote {
    
    // FINAL Static String PERFORMA_INVOICE_STATUS_WORKING_WITH_CUSTOMER = 'Working with Customer for changes';
     
     public class InputVariables{
         @InvocableVariable
         public List<Id> contractIdList;
         @InvocableVariable
         public Date startDate;
     }
     
     public class ReturnVariables{
         @InvocableVariable
         public SBQQ__Quote__c consolidatedQuote;
     }
     
     @InvocableMethod(label='Duplicate Renewal Quote' description='Method to clone Quote And Quote Lines for Renewal')
     public static List<ReturnVariables> duplicateQuote(List<InputVariables> inputVariables){
         try{
             System.debug('InputVariables.get(0).contractIdList '+ inputVariables.get(0).contractIdList);
             Date startDate = inputVariables.get(0).startDate;
             Map<Id,Contract> contrMap = new Map<Id,Contract>([Select Id,AccountId,Consolidated_Quote__c From Contract where Id In : inputVariables.get(0).contractIdList Order by CreatedDate]);
             List<SBQQ__Quote__c> quotList = [Select Id,SBQQ__Account__c,Name,currencyIsoCode,Deal_Type__c,SBQQ__Opportunity2__r.SBQQ__RenewedContract__c,SBQQ__Opportunity2__c,SBQQ__StartDate__c From SBQQ__Quote__c Where SBQQ__Opportunity2__r.SBQQ__RenewedContract__c In : contrMap.keyset() And Renewal_Quote_Type__c =: System.Label.Auto_Renewal Order By SBQQ__StartDate__c Asc];
             Id quot1Id = quotList[0].Id;
             //System.debug('quotList'+quotList);  
             SBQQ__Quote__c originalquot = Database.query(allFields('SBQQ__Quote__c')+' Where Id =: quot1Id Limit 1');
             SBQQ__Quote__c quot = originalquot.Clone(false, true, false, false);
             Id devRecordTypeId = Schema.SObjectType.SBQQ__Quote__c.getRecordTypeInfosByDeveloperName().get('Draft_Quote').getRecordTypeId();
             quot.SBQQ__Opportunity2__c = quotList[0].SBQQ__Opportunity2__c;//opp.Id;
             quot.OwnerId = UserInfo.getUserId();
             quot.SBQQ__Primary__c = False;
             //quot.OP4IDealID__c = dealId;
             //quot.OP4I_Deal_Name__c = dealId;
             quot.SBQQ__Account__c = quotList[0].SBQQ__Account__c;
             quot.recordTypeId = devRecordTypeId;
             quot.Deal_Type__c = quotList[0].Deal_Type__c;
             quot.CurrencyIsoCode = quotList[0].currencyIsoCode;
             quot.Renewal_Quote_Type__c = System.Label.Consolidated_Quote;
             quot.SBQQ__ContractingMethod__c = System.Label.Single_Contract;
             quot.SBQQ__StartDate__c = startDate;
             quot.SBQQ__EndDate__c = null;
             quot.Quote_Stage__c = System.Label.Configure_Products;
             //quot.StaticBundleIds__c = '';
             Insert quot;
             List<SBQQ__QuoteLine__c> originalQuoteLines = Database.query(allFields('SBQQ__QuoteLine__c')+' Where SBQQ__Quote__c =: quotList');
             If(originalQuoteLines.size() > 0){
                 List<SBQQ__QuoteLine__c> clonedQuoteLines = new List<SBQQ__QuoteLine__c>();
                 //create renewal lines
                 Map<string,SBQQ__QuoteLine__c> segmentKeyQLMap = new Map<string,SBQQ__QuoteLine__c>();
                 Integer i = 0;
                 for(SBQQ__QuoteLine__c ql : originalQuoteLines){
                     SBQQ__QuoteLine__c clonedLineRec = ql.Clone(false, true, false, false);
                     clonedLineRec.SBQQ__Quote__c = quot.Id;
                     clonedLineRec.SBQQ__StartDate__c = startDate;
                     //Include Select Bundle Products and Stand alone products and Static bundle parent products.
                     //clonedLineRec.SBQQ__EndDate__c = startDate+365;
                     If(segmentKeyQLMap.containsKey(ql.SBQQ__SegmentKey__c)){
                        clonedLineRec.SBQQ__SegmentKey__c = ql.SBQQ__SegmentKey__c+i;
                        i++;
                     }
                     else{
                        clonedLineRec.SBQQ__SegmentKey__c = ql.SBQQ__SegmentKey__c;
                     }
                     segmentKeyQLMap.put(clonedLineRec.SBQQ__SegmentKey__c,clonedLineRec);

                     If(String.isBlank(ql.SBQQ__RequiredBy__c) || ql.Required_By_Product_Code__c==System.Label.Select_Bundle_Product_Code){
                         clonedQuoteLines.add(clonedLineRec);
                     }
                     //Populate Select Bundle Field
                     If(ql.SBQQ__ProductCode__c == System.Label.Select_Bundle_Product_Code){
                         clonedLineRec.Cloned_Select_Bundle_Id__c = ql.Id;
                     }
                 }
                 //create negative lines//
                 for(SBQQ__QuoteLine__c ql : originalQuoteLines){
                     If((ql.SBQQ__Quote__c != quotList[0].Id)||(quotList[0].SBQQ__StartDate__c != startDate)){
                         SBQQ__QuoteLine__c clonedLineRec = ql.Clone(false, true, false, false);
                         clonedLineRec.SBQQ__Quote__c = quot.Id;
                         clonedLineRec.SBQQ__StartDate__c = startDate;
                         clonedLineRec.SBQQ__EndDate__c = ql.Renewed_Subscription_End_Date__c;
                         clonedLineRec.SBQQ__Quantity__c = clonedLineRec.SBQQ__Quantity__c * -1;
                         clonedLineRec.Original_ACV_Change__c = 0;
                         clonedLineRec.isCredit__c = True;
                         clonedLineRec.SBQQ__SegmentIndex__c = null;
                         clonedLineRec.SBQQ__SegmentLabel__c = null;
                         clonedLineRec.SBQQ__SegmentKey__c = null;
                         clonedLineRec.SBQQ__Dimension__c = null;
                         //Populate Select Bundle Field
                         If(ql.SBQQ__ProductCode__c == System.Label.Select_Bundle_Product_Code){
                             clonedLineRec.Cloned_Select_Bundle_Id__c = ql.Id;
                         }
                         //clonedQuoteLines.add(clonedLineRec);
                         If((String.isBlank(ql.SBQQ__RequiredBy__c) || ql.Required_By_Product_Code__c==System.Label.Select_Bundle_Product_Code) &&(startDate <= ql.Renewed_Subscription_End_Date__c)&&(startDate > ql.Renewed_Contract_Start_Date__c)){
                             clonedQuoteLines.add(clonedLineRec);
                         }
                         
                     }
                 }
                 If(clonedQuoteLines.size() > 0){
                     Insert clonedQuoteLines;
                 }
                 Map<String,Id> selectBundleId = new Map<String,Id>();
                 List<SBQQ__QuoteLine__c> updateLines = new List<SBQQ__QuoteLine__c>();
                 for(SBQQ__QuoteLine__c ql : clonedQuoteLines){
                     if(ql.Cloned_Select_Bundle_Id__c != Null && ql.SBQQ__Quantity__c < 0){
                         selectBundleId.put(ql.Cloned_Select_Bundle_Id__c+'-',ql.Id);
                     }
                     else if(ql.Cloned_Select_Bundle_Id__c != Null && ql.SBQQ__Quantity__c >= 0){
                         selectBundleId.put(ql.Cloned_Select_Bundle_Id__c+'+',ql.Id);
                     }
                 }
                 System.debug('selectBundleId'+selectBundleId);
                 for(SBQQ__QuoteLine__c ql : clonedQuoteLines){
                     //System.debug('ql.SBQQ__RequiredBy__c'+ql.SBQQ__RequiredBy__c);
                     //System.debug('ql.Required_By_Product_Code__c'+ql.Required_By_Product_Code__c);
                     //System.debug('ql.SBQQ__RequiredBy__c+String.valueOf(ql.SBQQ__Quantity__c).substring(0,1)'+ql.SBQQ__RequiredBy__c+String.valueOf(ql.SBQQ__Quantity__c).substring(0,1));
                     if(ql.SBQQ__RequiredBy__c != Null && ql.Required_By_Product_Code__c==System.Label.Select_Bundle_Product_Code && ql.SBQQ__Quantity__c >= 0 && selectBundleId.containsKey(ql.SBQQ__RequiredBy__c+'+')){
                             ql.SBQQ__RequiredBy__c = selectBundleId.get(ql.SBQQ__RequiredBy__c+'+');
                             updateLines.add(ql);
                         }
                     else if(ql.SBQQ__RequiredBy__c != Null && ql.Required_By_Product_Code__c==System.Label.Select_Bundle_Product_Code && ql.SBQQ__Quantity__c < 0 && selectBundleId.containsKey(ql.SBQQ__RequiredBy__c+'-')){
                             ql.SBQQ__RequiredBy__c = selectBundleId.get(ql.SBQQ__RequiredBy__c+'-');
                             updateLines.add(ql);
                         }
                     }
                 System.debug('updateLines'+updateLines);
                 If(updateLines.size() > 0){
                     Update updateLines;
                 }
             }
             List<ReturnVariables> outputVariables = new List<ReturnVariables>();
             ReturnVariables outputVariable = new ReturnVariables();
             outputVariable.consolidatedQuote = quot;
             outputVariables.add(outputVariable);
             return outputVariables;
         }
         catch(Exception e){
             System.debug('Exception : '+e);
             return null;
         }
        
     }
     
     
     public static String allFields(String objectName) {
         List<String> fields = new List<String>(Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap().keySet());
         String query  = 'SELECT '+String.join(fields, ',')+' FROM '+objectName;
         return query;
     }
 }