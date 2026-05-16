/**
* @description       : BIZ-57672-This class is used in Approval Email Template.
* @author            : Abhijeet bhandari
* @last modified on  : 06-19-2024
* @last modified by  : Abhijeet Bhandari
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   06-19-2024   Abhijeet bhandari   Initial Version
**/
public class GetQuoteTerm {

    public List<SBQQ__QuoteTerm__c> lstQuoteTerms;
    public Id relatedId {get;set;}
 
    public List<SBQQ__QuoteTerm__c> getlstQuoteTerms() {
        try{
            lstQuoteTerms = [SELECT id,SBQQ__Body__c,SBQQ__Quote__c,SBQQ__StandardTerm__c,Name FROM SBQQ__QuoteTerm__c
                          Where SBQQ__Quote__c =: relatedId ];
            if(lstQuoteTerms!=null){
                for(SBQQ__QuoteTerm__c oQuoteTerm:lstQuoteTerms){
                    oQuoteTerm.SBQQ__Body__c = oQuoteTerm.SBQQ__Body__c.stripHtmlTags();
                }
            }
         }catch(Exception ex){
            System.debug('Exception Caught  :'+ex.getMessage() + ' **Line Number : '+ex.getLineNumber());
         }
          return lstQuoteTerms;
    }
}