/**
 * @description
 * Factory + business logic helper for Single Quote Single Deal flow.
 * Contains all SOQL, DML, CPQ Amender calls, migration logic,
 * and amendment handling.
 */
public without sharing class SingleQuoteDealFactoryHelper {

    /* ============================================================
       ORCHESTRATION
       ============================================================ */

    // Orchestrates processing based on presence of existing quotes and amendment flag
    public static String process( SingleQuoteSingleDealController.QuoteWrapper qw,String mockResponse) {
        if (!qw.quotes.isEmpty()) {
            return handleExistingQuotes(qw, mockResponse);
        }
        return handleNewQuote(qw, mockResponse);
    }

    /* ============================================================
       NEW QUOTE HANDLING
       ============================================================ */

    // Handles creation path for new quote/opportunity or amendment when no existing quotes
    private static String handleNewQuote(SingleQuoteSingleDealController.QuoteWrapper qw,String mockResponse) {
        Nebula.Logger.debug(
            'ManageQuote - NewQuote flow | ' +
            ' OP4I_OSA=' + qw.osaNumber +
            ', OP4I_DealId=' + qw.dealId
        );
        Nebula.Logger.saveLog();
        if (qw.account == null) {
            return 'Error;' + System.Label.Manage_Quote_OpportunityError;
        }

        if (!qw.isAmendment) {
            SBQQ__Quote__c quote = SingleQuoteDealFactorySupport.createNewOpportunityAndQuote(qw);
            return 'Success;SBQQ__Quote__c;' + quote.Id;
        }

        if (String.isBlank(qw.osaNumber)) {
            return 'Error;' + System.Label.Manage_Quote_OSA_Blank;
        }

        if (qw.activeContract == null) {
            return 'Error;' + System.Label.Manage_Quote_Contract_Blank;
        }

        SBQQ__Quote__c amendedQuote =
            SingleQuoteDealFactorySupport.createOpportunityAndQuote(qw, mockResponse);

        return 'Success;SBQQ__Quote__c;' + amendedQuote.Id;
    }
    
    /* ============================================================
       EXISTING QUOTE HANDLING
       ============================================================ */
    private static String handleExistingQuotes(SingleQuoteSingleDealController.QuoteWrapper qw, String mockResponse) {
        SBQQ__Quote__c existingQuote = qw.quotes[0];
        
        // ------------------------------------------------------------
        // Condition flags (same logic as isTransactionTypeChange)
        // ------------------------------------------------------------
        Boolean isOp4IBlankOSA = String.isBlank(qw.osaNumber);
        Boolean isQuoteOSAPlaceholder = !String.isBlank(existingQuote.OSA_Number__c);
        Boolean isMasterContractBlank = existingQuote.SBQQ__MasterContract__c == null;
        
        Boolean isActiveContractChanged =
            qw.activeContract != null &&
            existingQuote.SBQQ__MasterContract__c != qw.activeContract.Id;
      
        Boolean isStartDateChanged =
            (isOp4IBlankOSA && qw.amendmentStartDate == null)
            ? false
            : existingQuote.SBQQ__StartDate__c != qw.amendmentStartDate;
        
        Boolean isIntentionalOSARemoval =
            isOp4IBlankOSA && !isMasterContractBlank;
        
        Boolean isNonTransactionCase =
            isOp4IBlankOSA &&
            isQuoteOSAPlaceholder &&
            isMasterContractBlank &&
            qw.activeContract == null;
        
        Boolean isOSAChanged =
            SingleQuoteDealFactorySupport.hasOSAChanged(
                existingQuote.OSA_Number__c,
                qw.osaNumber
            );
        
        // ------------------------------------------------------------
        // Debug: show all values + which condition will fire
        // ------------------------------------------------------------
        String decisionPath =
            isActiveContractChanged ? 'TRANSACTION_CHANGE_ACTIVE_CONTRACT_MISMATCH' :
        isStartDateChanged ? 'TRANSACTION_CHANGE_START_DATE_MISMATCH' :
        isNonTransactionCase ? 'NON_TRANSACTION_CASE' :
        isIntentionalOSARemoval ? 'TRANSACTION_CHANGE_INTENTIONAL_OSA_REMOVAL' :
        isOSAChanged ? 'TRANSACTION_CHANGE_OSA_CHANGED' :
        'NO_TRANSACTION_CHANGE';

        Nebula.Logger.debug(
            'ManageQuote - ExistingQuote detected | ' +
            'DecisionPath=' + decisionPath +
            ' | QuoteId=' + existingQuote.Id +
            ', QuoteOSA=' + existingQuote.OSA_Number__c +
            ', OP4I_OSA=' + qw.osaNumber +
            ', QuoteStartDate=' + existingQuote.SBQQ__StartDate__c +
            ', OP4I_StartDate=' + qw.amendmentStartDate +
            ', QuoteMasterContract=' + existingQuote.SBQQ__MasterContract__c +
            ', ActiveContract=' + qw.activeContract +
            ', MasterContractMismatch=' + isActiveContractChanged +
            ', StartDateMismatch=' + isStartDateChanged +
            ', IntentionalOSARemoval=' + isIntentionalOSARemoval +
            ', OSAChanged=' + isOSAChanged
        );
        Nebula.Logger.saveLog();
        
        // ============================================================
        // Transaction-Type Decision
        // ============================================================
        if (SingleQuoteDealFactorySupport.isTransactionTypeChange(existingQuote, qw)) {
            return recreateForTransactionChange(existingQuote, qw, mockResponse);
        }
        
        // ============================================================
        // No Transaction Change
        // ============================================================
        if (!qw.isAmendment) {
            SingleQuoteDealFactorySupport.updateExistingNonAmend(existingQuote, qw);
            return 'Success;SBQQ__Quote__c;' + existingQuote.Id;
        }
        
        // ============================================================
        // Amendment Path
        // ============================================================
        SBQQ__Quote__c amended =
            SingleQuoteDealFactorySupport.processExistingAmendOppAndQuote(qw, mockResponse);
        
        return 'Success;SBQQ__Quote__c;' + amended.Id;
    }
    
    /* ============================================================
       OSA CHANGE FLOW
       ============================================================ */

    // Recreates opportunity/quote when OSA changes and migrates related data
    private static String recreateForTransactionChange(SBQQ__Quote__c oldQuote,SingleQuoteSingleDealController.QuoteWrapper qw,String mockResponse) {
        qw.oldQuote = oldQuote;

        SBQQ__Quote__c newQuote = SingleQuoteDealFactorySupport.createOpportunityAndQuote(qw, mockResponse);

        Opportunity oldOpp = [
            SELECT Id, StageName, OP4I_Deal_Id__c, OP4I_Auto_Number_Deal_ID__c
            FROM Opportunity
            WHERE Id = :oldQuote.SBQQ__Opportunity2__c
            FOR UPDATE
        ];

        oldOpp.StageName = OpportunityConstants.STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED;
        oldOpp.OP4I_Deal_Id__c = null;
        oldOpp.OP4I_Auto_Number_Deal_ID__c = null;
        oldQuote.OP4IDealID__c = null;
        oldQuote.SBQQ__Primary__c = false;

        update new List<SObject>{ oldOpp, oldQuote };

        SingleQuoteDealFactorySupport.migrateQuoteData(oldQuote.Id, newQuote.Id);

        return 'Success;SBQQ__Quote__c;' + newQuote.Id;
    }
}