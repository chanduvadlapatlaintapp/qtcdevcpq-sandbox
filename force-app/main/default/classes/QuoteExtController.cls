public with sharing class QuoteExtController {
    
    public QuoteExtController(ApexPages.StandardSetController controller) {
        
    }
    
    private Id quoteId;
    private static Boolean dateInCurrentQuarter = true;
    public QuoteExtController(ApexPages.StandardController stdController) {
        quoteId = stdController.getId();
    }
    public PageReference onSubmit() {
        processApprovalConditions();
        if (quoteId != null) {
            SBAA.ApprovalAPI.submit(quoteId, SBAA__Approval__c.Quote__c);
        }
        return new PageReference('/' + quoteId);
    }
    public PageReference onPerviewApproval() {
        processApprovalConditions();
        return new PageReference('/apex/sbaa__PreviewApprovals?Id=' + quoteId + '&hidesubmit=1');
    }
    public PageReference onRecall() {
        if (quoteId != null) {
            SBAA.ApprovalAPI.recall(quoteId, SBAA__Approval__c.Quote__c);
        }
        return new PageReference('/' + quoteId);
    }
    private void processApprovalConditions() {
        
        Date todayPlus30 = System.today().addDays(30);
        Date todayminus60 = System.today().addDays(-60);
        Boolean hasDeploymentProduct = false;
        if(quoteId!=null){
            List<SBQQ__Quote__c> quoteList = [SELECT Id, Expected_Signaure_Date_Booking_Date__c, Complex_Approval_Condition_Evaluation__c, OP4I_Sales_Segment__c
                                              FROM SBQQ__Quote__c
                                              WHERE Id = :quoteId];
            isDateInCurrentQuarter(quoteList[0].Expected_Signaure_Date_Booking_Date__c);
            String complexApprovalCondition;
            if(dateInCurrentQuarter == true && quoteList[0].Expected_Signaure_Date_Booking_Date__c < System.today() &&
               (complexApprovalCondition == null ||
                (complexApprovalCondition != null && !complexApprovalCondition.contains('T70;')))) {
                    if(complexApprovalCondition == null){
                        complexApprovalCondition = 'T70;';
                    }
                    else{
                        complexApprovalCondition += 'T70;';
                    }
                }
            if(!quoteList.isEmpty()){
                List<SBQQ__QuoteLine__c> oQuoteLine = [SELECT Id, Product_Line_Deployment__c, Product_Type__c, SBQQ__Product__r.Product_LineNew__r.Deployment__c FROM SBQQ__QuoteLine__c where SBQQ__Quote__c = :quoteList[0].id];
                if (quoteList[0].Expected_Signaure_Date_Booking_Date__c > todayPlus30 && 
                    (complexApprovalCondition == null ||
                     (complexApprovalCondition != null && !complexApprovalCondition.contains('T4;')))) {
                         if(complexApprovalCondition == null){
                             complexApprovalCondition = 'T4;';
                         }
                         else{
                             complexApprovalCondition += 'T4;';
                         }
                     }
                if(quoteList[0].OP4I_Sales_Segment__c != null && !quoteList[0].OP4I_Sales_Segment__c.startsWith('0') &&
                   (complexApprovalCondition == null ||
                    (complexApprovalCondition != null && !complexApprovalCondition.contains('T60;')))){
                        if(complexApprovalCondition == null){
                            complexApprovalCondition = 'T60;';
                        }
                        else{
                            complexApprovalCondition += 'T60;';
                        }
                    }
                
                if(quoteList[0].Expected_Signaure_Date_Booking_Date__c < todayminus60 &&
                   (complexApprovalCondition == null ||
                    (complexApprovalCondition != null && !complexApprovalCondition.contains('T32;')))) {
                        if(complexApprovalCondition == null){
                            complexApprovalCondition = 'T32;';
                        }
                        else{
                            complexApprovalCondition += 'T32;';
                        }
                    }
                if(!oQuoteLine.isEmpty()){
                    for(SBQQ__QuoteLine__c quoteline : oQuoteLine){
                        if(quoteline.Product_Line_Deployment__c){
                            hasDeploymentProduct = true;
                        }
                    }
                    for(SBQQ__QuoteLine__c quoteline : oQuoteLine){
                        if((quoteline.Product_Type__c == 'Services' || quoteline.Product_Type__c == 'Services Discount' || quoteline.Product_Type__c == 'Services (Recurring)') && 
                           (complexApprovalCondition == null ||
                            (complexApprovalCondition != null && !complexApprovalCondition.contains('T30;')))) {
                                if(complexApprovalCondition == null){
                                    complexApprovalCondition = 'T30;';
                                }
                                else{
                                    complexApprovalCondition += 'T30;';
                                }
                            }
                        if((quoteline.Product_Type__c == 'Training' || quoteline.Product_Type__c == 'Training Discount') &&
                           (complexApprovalCondition == null ||
                            (complexApprovalCondition != null && !complexApprovalCondition.contains('T33;')))) {
                                if(complexApprovalCondition == null){
                                    complexApprovalCondition = 'T33;';
                                }
                                else{
                                    complexApprovalCondition += 'T33;';
                                }
                            }
                        
                        //Changes for BIZ-59098
                        if(quoteline.SBQQ__Product__r.Product_LineNew__r.Deployment__c == 'On-Premise'	&&
                           (complexApprovalCondition == null ||
                            (complexApprovalCondition != null && !complexApprovalCondition.contains('T80;')))) {
                                if(complexApprovalCondition == null){
                                    complexApprovalCondition = 'T80;';
                                }
                                else{
                                    complexApprovalCondition += 'T80;';
                                }
                            }
                        //Changes for BIZ-59098
                    }
                    if (hasDeploymentProduct &&
                        (complexApprovalCondition == null ||
                         (complexApprovalCondition != null && !complexApprovalCondition.contains('T10;')))) {
                             if(complexApprovalCondition == null){
                                 complexApprovalCondition += 'T10;';
                             }
                             else{
                                 complexApprovalCondition += 'T10;';
                             }
                         }
                }
                quoteList[0].Complex_Approval_Condition_Evaluation__c = complexApprovalCondition;
            }
            update quoteList[0];
        }
    }
    //Method to check if the given date is within the current quarter
    public static Boolean isDateInCurrentQuarter(Date startDate) {
        Date today = Date.today();
        // Calculate the start and end dates of the current quarter
        Date quarterStartDate, quarterEndDate;
        Integer currentMonth = today.month();
        Integer currentYear = today.year();
        if (currentMonth <= 3) {
            // First quarter: January - March
            quarterStartDate = Date.newInstance(currentYear, 1, 1);
            quarterEndDate = Date.newInstance(currentYear, 3, 31);
        } else if (currentMonth <= 6) {
            // Second quarter: April - June
            quarterStartDate = Date.newInstance(currentYear, 4, 1);
            quarterEndDate = Date.newInstance(currentYear, 6, 30);
        } else if (currentMonth <= 9) {
            // Third quarter: July - September
            quarterStartDate = Date.newInstance(currentYear, 7, 1);
            quarterEndDate = Date.newInstance(currentYear, 9, 30);
        } else {
            // Fourth quarter: October - December
            quarterStartDate = Date.newInstance(currentYear, 10, 1);
            quarterEndDate = Date.newInstance(currentYear, 12, 31);
        }
        // Check if the start date is within the current quarter
        if (startDate >= quarterStartDate && startDate <= quarterEndDate) {
            dateInCurrentQuarter = false;
            return true;
        } else {
            dateInCurrentQuarter = true;
            return false;
        }
    }
}