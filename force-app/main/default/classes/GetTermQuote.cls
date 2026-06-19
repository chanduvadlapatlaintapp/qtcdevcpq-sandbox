/**
* @description       : BIZ-50132-This class is used in Approval Email Template.
* @author            : Pankaj Kumar
* @last modified on  : 01-08-2024
* @last modified by  : Pankaj Kumar
* Modifications Log
* Ver   Date         Author         Modification
* 1.0   01-02-2024   Pankaj Kumar   Initial Version
**/
public class GetTermQuote {

    public List<Term_Quote__c> termQuotes;
    public Id relatedId {get;set;}
 
    public List<Term_Quote__c> getTermQuotes() {
        try{
            termQuotes = [SELECT id,Body__c,Quote__c,Term__c,Name,Modified__c FROM Term_Quote__c
                          Where Modified__c=true AND Quote__c =: relatedId ];
            if(termQuotes!=null){
                for(Term_Quote__c t:termQuotes){
                    t.Body__c = t.Body__c.stripHtmlTags();
                }
            }
         }catch(Exception ex){
            System.debug('Exception Caught  :'+ex.getMessage() + ' **Line Number : '+ex.getLineNumber());
         }
          return termQuotes;
    }
}