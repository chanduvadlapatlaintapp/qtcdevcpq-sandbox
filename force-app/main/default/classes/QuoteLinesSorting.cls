global class QuoteLinesSorting{
webService static void sortQuoteLines(Id quoteId){
        List<SBQQ__QuoteLine__c> lstOfQuoteLines = new List<SBQQ__QuoteLine__c>();
        Integer sortNumber = 1;
        if(quoteId!=null){
           lstOfQuoteLines = [Select Id,NetTotal_No_Currency__c FROM SBQQ__QuoteLine__c 
                             WHERE SBQQ__Quote__c =: quoteId ORDER BY NetTotal_No_Currency__c DESC];
           if(!lstOfQuoteLines.isEmpty()){
             for(SBQQ__QuoteLine__c qle : lstOfQuoteLines)
             {
                qle.Quote_Line_Order__c = sortNumber;
                sortNumber++;
             }
            update lstOfQuoteLines;   
           }
         }                  
      }
   }