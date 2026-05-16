/**
* @description       : This class is a Helper class for QuoteTrigger.
* @author            : Pooja Hemrajani
* Created Date       : Mar-20-2025
**/
public inherited sharing class QuoteTriggerHelper {

    /***********************************************************************************************
     * 
     * public methods
     * 
     ***********************************************************************************************/

    /**
     * @description   : Calculates Min and Max Year-over-Year uplift using net software totals
     *                  (Software Total - One Time Credit). Only calculates if the field is empty
     *                  to preserve data-loaded historical values.
     *                  Populates: Min_YoY_Uplift__c, Max_YoY_Uplift__c
     * @author        : Auto-generated | Feb-06-2026 | BIZ-78642
     * @param quotes  : List<SBQQ__Quote__c> - Quote records to calculate YoY uplift for.
     */
    public static void calculateYoYUplift(List<SBQQ__Quote__c> quotes) {
        Set<Id> setOppIds = Pluck.ids(SBQQ__Quote__c.SBQQ__Opportunity2__c, quotes);
        Map<Id, Opportunity> mapOpp = new Map<Id, Opportunity>([SELECT Id, isclosed from Opportunity WHERE Id IN:setOppIds and isclosed = true]);
        for (SBQQ__Quote__c q : quotes) {
            // Skip if values already exist (preserves data-loaded historical values)
            if (mapOpp.containsKey(q.SBQQ__Opportunity2__c)) {
                continue;
            }
            
            // Calculate net values (Software Total - One Time Credit)
            Decimal netYr1 = (q.First_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr1__c ?? 0);
            Decimal netYr2 = (q.Second_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr2__c ?? 0);
            Decimal netYr3 = (q.Third_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr3__c ?? 0);
            Decimal netYr4 = (q.Fourth_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr4__c ?? 0);
            Decimal netYr5 = (q.Fifth_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr5__c ?? 0);
            Decimal netYr6 = (q.Sixth_Year_Software_Total__c ?? 0) + (q.One_time_Credit_Yr6__c ?? 0);
            
            // Calculate uplifts with OTD (net values)
            List<Decimal> uplifts = new List<Decimal>();
            if (netYr1 != 0 && netYr2 != 0) {
                uplifts.add((netYr2 - netYr1) / netYr1);
                if (netYr3 != 0) uplifts.add((netYr3 - netYr2) / netYr2);
                if (netYr4 != 0) uplifts.add((netYr4 - netYr3) / netYr3);
                if (netYr5 != 0) uplifts.add((netYr5 - netYr4) / netYr4);
                if (netYr6 != 0) uplifts.add((netYr6 - netYr5) / netYr5);
            }
            
            if (!uplifts.isEmpty()) {
                uplifts.sort();
                // Store as 0–100 scale, rounded to 2 decimals to match field scale (Percent 18,2)
                q.Min_YoY_Uplift__c = (uplifts[0] * 100).setScale(2, System.RoundingMode.HALF_EVEN);
                q.Max_YoY_Uplift__c = (uplifts[uplifts.size() - 1] * 100).setScale(2, System.RoundingMode.HALF_EVEN);
            } else {
                q.Min_YoY_Uplift__c = 0;
                q.Max_YoY_Uplift__c = 0;
            }
        }
    }

    /**
     * 
     * @description   : This method ensures that a user cannot update the billing frequency or payment terms once the quote is marked as ordered..
     * @param oldQuotesMap Map<Id, SBQQ__Quote__c> - Map of old Quote records (before update).
     * @param newQuotesMap Map<Id, SBQQ__Quote__c> - Map of new Quote records (after update).
     */
    public static void processRecordsBeforeUpdate(Map<Id, SBQQ__Quote__c> oldQuotesMap, Map<Id, SBQQ__Quote__c> newQuotesMap){
          
        /** Changes BIZ-723 : End **/   
        // Set of all the sales segments which got changed.
        Set<String> salesSegments = new Set<String>();
        
        // Re-assign approvers only to only quotes where sales segment changed.
        List<Id> quoteIdsToBeProcessed = new List<Id>();

        Generic_Key_Value_Setting__mdt approvalErrorMaxRetrySetting = Generic_Key_Value_Setting__mdt.getInstance('Approval_Error_Max_Retry');
        Integer approvalErrorMaxRetry = Integer.valueOf(approvalErrorMaxRetrySetting.Value__c);
                    
        Generic_Key_Value_Setting__mdt adminProfileSetting = Generic_Key_Value_Setting__mdt.getInstance('System_Administrator_Profile_ID');
        Id profileID = adminProfileSetting.value__c;

        // Loop through all the new quotes and get the set of sales segment and 
        // the quotes to be processed 
        for(Id quoteId : newQuotesMap.keySet()){            
            //validation BIZ-60530
            if((UserInfo.getProfileId() != profileID)){
                if(newQuotesMap.get(quoteId).SBQQ__Ordered__c 
                    && (newQuotesMap.get(quoteId).Order__c!=null 
                        && (oldQuotesMap.get(quoteId).SBQQ__BillingFrequency__c != newQuotesMap.get(quoteId).SBQQ__BillingFrequency__c)
                        ||(oldQuotesMap.get(quoteId).Software_Payment_Terms__c != newQuotesMap.get(quoteId).Software_Payment_Terms__c)
                        ||(oldQuotesMap.get(quoteId).Renewal_Payment_Terms__c != newQuotesMap.get(quoteId).Renewal_Payment_Terms__c)
                    )
                ){
                    
                    newQuotesMap.get(quoteId).addError(System.Label.Billing_Schedule_validation_message);
                }
            }
            
            if(oldQuotesMap.get(quoteId).ApprovalStatus__c == 'Error'
                && newQuotesMap.get(quoteId).ApprovalStatus__c == 'Pending'
                && newQuotesMap.get(quoteId).Counter__c >= approvalErrorMaxRetry){
                    SBQQ__Quote__c quote = newQuotesMap.get(quoteId);
                    quote.Counter__c = 0;
                }

            if(oldQuotesMap.get(quoteId).OP4I_Sales_Segment__c != newQuotesMap.get(quoteId).OP4I_Sales_Segment__c){
                salesSegments.add(newQuotesMap.get(quoteId).OP4I_Sales_Segment__c);
                quoteIdsToBeProcessed.add(quoteId);
            }
        }

    }
    
    /**
     * @description   : This method is used to publish approval records to OP4i SB.
     * @param quoteNewList List<SBQQ__Quote__c> - New versions of Quote records being processed.
     * @param quoteOldMap  Map<Id, SBQQ__Quote__c> - Old versions of the same Quote records (before update).
     */
    public static void syncApprovalRecordsForChangedQuotes(List<SBQQ__Quote__c> quoteNewList, Map<Id, SBQQ__Quote__c> quoteOldMap) {
        Set<Id> quoteIdSet = new Set<Id>();
        for(SBQQ__Quote__c quoteRec : quoteNewList){
            if(quoteRec.SBQQ__MasterContract__c != quoteOldMap.get(quoteRec.Id).SBQQ__MasterContract__c 
               || quoteRec.ApprovalStatus__c != quoteOldMap.get(quoteRec.Id).ApprovalStatus__c
               || quoteRec.OP4IDealID__c != quoteOldMap.get(quoteRec.Id).OP4IDealID__c )
            {
                quoteIdSet.add(quoteRec.Id);
            }
        }
        Set<Id> approvalIdSet = new Set<Id>(); 
        if(quoteIdSet.size()>0){
            for(SBAA__Approval__c approvalRec : [SELECT Id FROM  SBAA__Approval__c 
                                                    WHERE Quote__c IN: quoteIdSet  
                                                    AND (OP4I_System_Id__c != null 
                                                        OR OP4I_Error__c != null)])
            {
                approvalIdSet.add(approvalRec.Id);
            }
        }
        if(approvalIdSet.size()>0){
            publishApprovalRecords(approvalIdSet);
        }
    }
    
    /**
     * 
     * @description   : This method is used to populate account subsidiary and prospect.
     * @param newQuotes List<SBQQ__Quote__c> - New Quote records
     * @param oldQuotes Map<Id, SBQQ__Quote__c> - Old Quote records (for afterUpdate comparisons).
     */
    public static void handleQuoteProcessing(List<SBQQ__Quote__c> newQuotes, Map<Id, SBQQ__Quote__c> oldQuotes) { 

        // Map to store Account IDs to process and their respective Subsidiary prefixes
        Map<Id, String> accountIdToPrefixMap = new Map<Id, String>();
        Map<Id, String> accountIdToFullSubsidiaryMap = new Map<Id, String>();

        // Collect Account IDs to query
        Set<Id> accountIdsToQuery = new Set<Id>();

        for (SBQQ__Quote__c newQuote : newQuotes) {

            // Check if this is a new record or if Subsidiary__c has changed
            Boolean isNewRecord = oldQuotes == null || !oldQuotes.containsKey(newQuote.Id);
            Boolean isSubsidiaryChanged = !isNewRecord && (
                oldQuotes.get(newQuote.Id).Subsidiary__c != newQuote.Subsidiary__c ||
                oldQuotes.get(newQuote.Id).Quote_Stage__c != newQuote.Quote_Stage__c);
    

            if (isNewRecord || isSubsidiaryChanged) {
                // Check for the desired Quote_Stage__c values
                if (newQuote.Quote_Stage__c == 'Finalize OSA' || 
                    newQuote.Quote_Stage__c == 'Pending Closure' || 
                    newQuote.Quote_Stage__c == 'Contract Executed') {

                    if (String.isNotBlank(newQuote.Subsidiary__c)) {

                        String subsidiaryPrefix = newQuote.Subsidiary__c.substring(0, 2);
                        if (newQuote.Bill_To_Account__c != null) {
                            accountIdsToQuery.add(newQuote.Bill_To_Account__c);
                            accountIdToPrefixMap.put(newQuote.Bill_To_Account__c, subsidiaryPrefix);
                            accountIdToFullSubsidiaryMap.put(newQuote.Bill_To_Account__c, newQuote.Subsidiary__c);
                        }
                        if (newQuote.Ship_To_Account__c != null) {
                            accountIdsToQuery.add(newQuote.Ship_To_Account__c);
                            accountIdToPrefixMap.put(newQuote.Ship_To_Account__c, subsidiaryPrefix);
                            accountIdToFullSubsidiaryMap.put(newQuote.Ship_To_Account__c, newQuote.Subsidiary__c);
                        }
                    }
                }
            }
        }

        // Query Accounts in bulk
        if (!accountIdsToQuery.isEmpty()) {
            Map<Id, Account> accounts = new Map<Id, Account>(
                [SELECT Id, Subsidiaries__c, Subsidiary__c, Create_Prospect__c 
                FROM Account 
                WHERE Id IN :accountIdsToQuery]
            );

            // Prepare Accounts to update
            List<Account> accountsToUpdate = new List<Account>();
            for (Id accountId : accountIdToPrefixMap.keySet()) {
                Account account = accounts.get(accountId);
                if (account != null) {
                    String subsidiaryPrefix = accountIdToPrefixMap.get(accountId);
                    String fullSubsidiaryValue = accountIdToFullSubsidiaryMap.get(accountId);

                    // Update if Subsidiaries__c does not contain the prefix
                    if (account.Subsidiaries__c == null || 
                        !account.Subsidiaries__c.contains(subsidiaryPrefix)) {
                        
                        account.Create_Prospect__c = subsidiaryPrefix;
                        account.Subsidiary__c = fullSubsidiaryValue;
                        accountsToUpdate.add(account);
                    }
                }
            }

            // Update Accounts if need
            if (!accountsToUpdate.isEmpty()) {
                update accountsToUpdate;
            }
        }
    }
    
 	/**
    * @description   : This is a helper method to set Pause Quote Payload field to true if it is a ghost Quote, part of BIZ-74649
    * @author        : Manisha Sharma | 09-10-2025
    * @param newQuotes List<SBQQ__Quote__c> - New Quote records
    */
    public static void setPauseQuotePayload(List<SBQQ__Quote__c> newQuotes) {
        Set<Id> oppIds = new Set<Id>();
        for(SBQQ__Quote__c q : newQuotes) {
            if(q.SBQQ__Opportunity2__c != null) {
                oppIds.add(q.SBQQ__Opportunity2__c);
            }
        }

        if(oppIds.isEmpty()) return;

        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>(
            [SELECT Id, SBQQ__RenewedContract__c, 
                    SBQQ__RenewedContract__r.SBQQ__RenewalForecast__c,
                    SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c
             FROM Opportunity
             WHERE Id IN :oppIds]
        );

        for(SBQQ__Quote__c q : newQuotes) {
            if(q.SBQQ__Type__c == 'Renewal'
               && q.SBQQ__Opportunity2__c != null
               && oppMap.containsKey(q.SBQQ__Opportunity2__c)
               && oppMap.get(q.SBQQ__Opportunity2__c).SBQQ__RenewedContract__c != null
               && oppMap.get(q.SBQQ__Opportunity2__c).SBQQ__RenewedContract__r.SBQQ__RenewalForecast__c == true
               && oppMap.get(q.SBQQ__Opportunity2__c).SBQQ__RenewedContract__r.SBQQ__RenewalQuoted__c == false) {
                   
                   q.Pause_Quote_Payload__c = true;
            }
        }
    }
    
    /**
    * @description   : Publishes only quotes where Pause_Quote_Payload__c = FALSE, part of BIZ-74649
    * @author        : Manisha Sharma | 09-10-2025
    * @param lstQuotes List<SBQQ__Quote__c> - Quote records to consider for publishing.
    * @param mapOldQuotes Map<Id, SBQQ__Quote__c> - Old Quote records (for afterUpdate comparisons).
    */
    public static void publishEligibleQuotes(List<SBQQ__Quote__c> lstQuotes, Map<Id, SBQQ__Quote__c> mapOldQuotes) {
        List<SBQQ__Quote__c> eligibleQuotes = new List<SBQQ__Quote__c>();
        
        for(SBQQ__Quote__c q : lstQuotes){
            if(q.Pause_Quote_Payload__c == FALSE){
                eligibleQuotes.add(q);
            }
        }
        
        if(!eligibleQuotes.isEmpty()){
            IntegrationUtility.publishEligibleSobjectRecords(eligibleQuotes, mapOldQuotes, 'SBQQ__Quote__c');
        }
    }
    
    /**
     * @description   : Helper method to publish approval records.
     * @param approvalIdSet Set<Id> - Approval record Ids to publish.
     * @revision log  : V1.0 - Refactored By Pooja Hemrajani - BIZ-66415
     */
    public static void publishApprovalRecords(Set<Id> approvalIdSet){
        String strQuery = createQuery(approvalIdSet);
        List<SBAA__Approval__c> approvalRecordList = Database.query(strQuery);
        if(approvalRecordList.size() > 0 && !Test.isRunningTest()) {
            IntegrationUtility.publishsObjectRecords(approvalRecordList, 'SBAA__Approval__c');
        }
    }
    
    /**
    * @description   : This resets approval status on the quote. Moved 'Reset Approval Status' Flow logic to Trigger as part of BIZ-71335.
    * @author        : Sonali Kakade | 23-07-2025
    * @param lstNewQuotes List<SBQQ__Quote__c> - Newly updated Quote records (after update)
    * @param mapOldQuotes Map<Id, SBQQ__Quote__c> - Old versions of the same Quote records (before update)
    **/
    public static void resetApprovalStatus(List<SBQQ__Quote__c> lstNewQuotes, Map<Id,SBQQ__Quote__c> mapOldQuotes) {        
        for (SBQQ__Quote__c quote : lstNewQuotes) {
            SBQQ__Quote__c oldQuote = (mapOldQuotes != null) ? mapOldQuotes.get(quote.Id) : null;
            if (oldQuote == null) {
                continue;
            }
            if (hasApprovalAffectingChanges(quote, oldQuote)) {
                quote.ApprovalStatus__c = QuoteConstants.STATUS_PENDING_SUBMISSION;
            }
        }
    }
    
    /**
     * @description   : Populates Custom_Master_Term__c on Quote from the related Account when
     *                  Contract_Master_Terms__c matches the Account’s Custom_Master_Term__c.
     *                  Moved 'Update Custom Master Term on Quote' Flow logic to Trigger as part of BIZ-71335.
     * @author        : Sonali Kakade | 24-07-2025
     * @param lstNewQuotes A list of newly updated SBQQ__Quote__c records.
     **/
    public static void populateCustomMasterTerm(List<SBQQ__Quote__c> lstNewQuotes) {
        Map<Id, String> mapAccountMasterTerm = new Map<Id, String>();
        Set<Id> setAccountIds = Pluck.ids(SBQQ__Quote__c.SBQQ__Account__c, lstNewQuotes);
        for(Account accountIterator : [SELECT Id, Custom_Master_Term__c FROM Account WHERE Id IN :setAccountIds]) {
            mapAccountMasterTerm.put(accountIterator.Id, accountIterator.Custom_Master_Term__c);
        }
        for(SBQQ__Quote__c quote : lstNewQuotes) {
            if(quote.SBQQ__Account__c != null && quote.Contract_Master_Terms__c == mapAccountMasterTerm.get(quote.SBQQ__Account__c)) {
                quote.Custom_Master_Term__c = mapAccountMasterTerm.get(quote.SBQQ__Account__c);
            }  
        }
    }
    
    /**
     * @description   : Updates the Deal Quality Score on related Opportunities when key Quote fields are modified
     *                  on the primary Quote. The score is recalculated using DealQualityScorer logic if any
     *                  scoring-related fields have changed between the old and new Quote versions.
     * @author        : Ratan Paul | 05-11-2025, BIZ-71699
     * @param lstNewQuote  List<SBQQ__Quote__c> - List of new Quote records (after update)
     * @param mapOldQuote  Map<Id, SBQQ__Quote__c> - Map of old Quote records (before update)
     */
    public static void updateOppDealQualityScore(List<SBQQ__Quote__c> lstNewQuote, Map<Id, SBQQ__Quote__c> mapOldQuote){
        
        Set<Id> oppIds = new Set<Id>();
        for (SBQQ__Quote__c quote : lstNewQuote) {
            if (quote.SBQQ__Opportunity2__c != null && quote.SBQQ__Primary__c == true && quote.GTM_Motion_Tier__c != 'EM1') {
                oppIds.add(quote.SBQQ__Opportunity2__c);
            }
        }
        // Calculate the Quote Deal Quality Score only when the Opportunity is not closed
        Date dtClose = Date.newInstance(2025, 09, 31);
        Set<String> setDealTypesNotAllowed = new Set<String>{
            OpportunityConstants.DEAL_TYPE_NYMY,
            OpportunityConstants.DEAL_TYPE_RENEWAL,
            OpportunityConstants.DEAL_TYPE_AMENDMENT_TO_SUPERCEDE,
            OpportunityConstants.DEAL_TYPE_Other,
            OpportunityConstants.DEAL_TYPE_PlatformConversion_INTERNAL, 
            OpportunityConstants.DEAL_TYPE_CANCELLATION
        };
        Map<Id, Opportunity> mapOppIdToDealQualityScore = new Map<Id, Opportunity>([SELECT Id 
                                                                                    FROM Opportunity 
                                                                                    WHERE Id IN:oppIds 
                                                                                    and Date_Opportunity_Closed__c = null 
                                                                                    and (NOT Deal_Type__c IN :setDealTypesNotAllowed)
                                                                                    and CloseDate >: dtClose ]);
        for (SBQQ__Quote__c quote : lstNewQuote) {
            if (quote.SBQQ__Opportunity2__c != null && quote.SBQQ__Primary__c == true && quote.GTM_Motion_Tier__c != 'EM1' 
            &&  mapOppIdToDealQualityScore.containsKey(quote.SBQQ__Opportunity2__c)) {
                quote.Deal_Quality_Score__c = DealQualityScorer.calculateCredit(quote);
            }
        }
    }


    /***********************************************************************************************
    *
    * Private helper methods
    *
    ***********************************************************************************************/
    /**
     * @description   : This is a helper method to create query.
     * @param approvalIdSet Set<Id> - Set of Approval record Ids to include in the WHERE clause.
     * @return        : String - The generated dynamic SOQL query string.
     */
    private static String createQuery(Set<Id> approvalIdSet){
        Set<String> fieldNames = new set<String>();
        Schema.SObjectType targetObjType = ((SObject)Type.forName('SBAA__Approval__c').newInstance()).getSObjectType();
        Map<String, Schema.SObjectField> fieldMap = targetObjType.getDescribe().fields.getMap();
        fieldNames = fieldMap.keyset();
        List<String> fields = new List<String>(fieldNames);
        String query =  ' SELECT ' +
            String.join( fields, ',' ) + ',Quote__r.SBQQ__MasterContract__c' +
            ',Quote__r.ApprovalStatus__c' + ',Quote__r.Intapp_Quote_Number__c' + ',Quote__r.OP4IDealID__c' +
            ',sbaa__AssignedTo__r.name' + ',sbaa__ApprovedBy__r.name ' + 
            ',Quote__r.SBQQ__MasterContract__r.OP4I_Contract_Id__c ' +
            ' FROM ' +
            'SBAA__Approval__c' +
            ' WHERE ' +
            ' Id IN: approvalIdSet';
        String strQuery1 = query.remove('{');
        String strQuery2 = strQuery1.remove('}'); 
        return strQuery2;
    }


    /**
     * @description   : Returns true if any approval-impacting fields changed between the old and new Quote.
     *                  Used by resetApprovalStatus to determine when to reset ApprovalStatus__c to Pending Submission.
     * @param newQ    : SBQQ__Quote__c - The new version of the Quote (after update).
     * @param oldQ    : SBQQ__Quote__c - The old version of the Quote (before update).
     * @return        : Boolean - true if any approval-relevant fields differ between new and old; otherwise false.
     */
    private static Boolean hasApprovalAffectingChanges(SBQQ__Quote__c newQ, SBQQ__Quote__c oldQ) {
        return
            newQ.Additional_Free_months_at_no_cost__c != oldQ.Additional_Free_months_at_no_cost__c ||
            newQ.SBQQ__PaymentTerms__c != oldQ.SBQQ__PaymentTerms__c ||
            newQ.SBQQ__BillingFrequency__c != oldQ.SBQQ__BillingFrequency__c ||
            newQ.SFA_Cap_after_Initial_Term__c != oldQ.SFA_Cap_after_Initial_Term__c ||
            newQ.SFA_Term__c != oldQ.SFA_Term__c ||
            newQ.Initial_Term_Discount__c != oldQ.Initial_Term_Discount__c ||
            newQ.Services_Discount_Percentage__c != oldQ.Services_Discount_Percentage__c ||
            newQ.Min_year_on_year_committed_spend__c != oldQ.Min_year_on_year_committed_spend__c ||
            newQ.Software_Payment_Terms__c != oldQ.Software_Payment_Terms__c;
    }

}