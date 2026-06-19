/**
 * @description AuraEnabled controller for the agenticQtcQuoteEditor amendment flow.
 *              Pure router — no SOQL, no business logic, no DTO construction.
 *              All logic lives in AgenticQTC_QuoteAmendmentService.
 * @author AgenticQTC Team
 * @date 2026-04-28
 * @jira BIZ-AgenticQTC
 */

public with sharing class AgenticQTC_AmendContractController {

    private static final String ERR_CONTRACT_REQUIRED   = 'Contract ID is required';
    private static final String ERR_QUANTITIES_REQUIRED = 'Contract ID and quantities are required';
    private static final String ERR_ACCOUNT_REQUIRED    = 'Account ID is required';

    // Test-only seams. Gated by Test.isRunningTest() so production cannot
    // trigger the throw regardless of flag state — the LWC, integrations and
    // every non-test caller see exactly the same behaviour as before.
    @TestVisible private static Boolean throwTestException     = false;
    @TestVisible private static Boolean throwTestAuraException = false;
    // BIZ-83493: when set, throwIfTestRequested() attempts a real 'Finalize OSA' stage
    // update on this quote so the saveQuoteChanges DmlException path can be tested with an
    // authentic org validation message.
    @TestVisible private static Id testDmlFailQuoteId = null;

    /**
     * @description Test-only injection point used to cover the controller's
     *              `catch (AuraHandledException)` and `catch (Exception)`
     *              blocks. Called at the start of every try block. No-op
     *              outside test context.
     */
    private static void throwIfTestRequested() {
        if (!Test.isRunningTest()) return;
        if (throwTestAuraException) {
            throw new AuraHandledException('Test-injected AuraHandledException');
        }
        if (throwTestException) {
            throw new System.NullPointerException();
        }
        if (testDmlFailQuoteId != null) {
            // BIZ-83493: force a real org validation DmlException (e.g. address verification,
            // Contract Master Terms) so saveQuoteChanges' DmlException handler — and its
            // getDmlMessage() extraction — is exercised end to end with an authentic message.
            update new SBQQ__Quote__c(Id = testDmlFailQuoteId, Quote_Stage__c = QuoteConstants.STATUS_FINALIZE_OSA);
        }
    }

    // Cached sandbox flag. The CPQ headless calculator can fail with an opaque
    // "Error parsing quote: Unexpected token [ ..." that the generic catch below
    // otherwise hides behind a friendly message — leaving the real cause only in
    // Nebula logs. In a sandbox we want that real message in the UI toast so the
    // amendment flow can be debugged; production keeps the friendly text. The lone
    // SOQL here is a deliberate, cached exception to this class's "pure router"
    // rule and runs only on the error path.
    @TestVisible private static Boolean exposeInternalErrorsOverride = null;
    private static Boolean exposeInternalErrorsCache;

    private static Boolean exposeInternalErrors() {
        if (exposeInternalErrorsOverride != null) return exposeInternalErrorsOverride;
        // Tests keep the production-style friendly message unless they opt in via
        // the override, so existing message assertions stay stable.
        if (Test.isRunningTest()) return false;
        if (exposeInternalErrorsCache == null) {
            exposeInternalErrorsCache = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        }
        return exposeInternalErrorsCache;
    }

    /**
     * @description Builds the AuraHandledException for a swallowed internal failure.
     *              In a sandbox the real exception message is appended so it surfaces
     *              in the LWC toast; production returns only the friendly text.
     */
    private static AuraHandledException internalError(String friendly, Exception e) {
        return exposeInternalErrors()
            ? new AuraHandledException(friendly + ' [' + e.getMessage() + ']')
            : new AuraHandledException(friendly);
    }

    // ─── Account & contract lookup ─────────────────────────────────────────────

    /**
     * @description Searches accounts by name for the LWC account-search typeahead.
     *              Delegates to AgenticQTC_AccountSearchService so the LWC only ever
     *              talks to this controller.
     * @param searchTerm The search string (minimum 2 characters)
     * @return List of AccountResult DTOs in SOSL relevance order
     */
    @AuraEnabled
    public static List<AgenticQTC_AccountSearchService.AccountResult> searchAccounts(String searchTerm) {
        try {
            throwIfTestRequested();
            return AgenticQTC_AccountSearchService.searchAccounts(searchTerm);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('searchAccounts failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to search accounts. Please try again or contact support.');
        }
    }

    /**
     * @description Lists active, software-bearing contracts for an account — the
     *              eligibility set the OSA selector grid renders. Delegates to
     *              AgenticQTC_ContractService so the LWC only ever talks to this controller.
     * @param accountId The Account record Id
     * @return List of ContractResult DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_ContractService.ContractResult> getActiveContracts(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException(ERR_ACCOUNT_REQUIRED);
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_ContractService.getActiveContracts(accountId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('getActiveContracts failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load contracts for this account. Please try again or contact support.');
        }
    }

    // ─── Amendment quote creation ──────────────────────────────────────────────

    /**
     * @description Lists draft amendment quotes for a contract whose end date is in the
     *              future. Used by the OSA selector to offer "reuse an existing draft"
     *              before falling back to a new amendment.
     * @param contractId The Contract record Id
     * @return List of DraftQuoteOption DTOs (id, name, dealId, endDate) — never null
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.DraftQuoteOption> getDraftQuotesForContract(String contractId) {
        if (String.isBlank(contractId)) {
            throw new AuraHandledException(ERR_CONTRACT_REQUIRED);
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.getDraftQuotesForContract(contractId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('getDraftQuotesForContract failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load existing draft quotes. Please try again or contact support.');
        }
    }

    /**
     * @description Reads an existing draft amendment quote and its lines via pure SOQL
     *              (no CPQ amendment / calculate / save). Returns the same shape as
     *              createAmendmentQuote so the LWC editor can render either path the
     *              same way. Used by the OSA selector's "Existing Draft Quotes" modal
     *              when the user picks a draft to reuse.
     * @param quoteId The existing draft SBQQ__Quote__c Id
     * @return AmendmentQuoteInfo with id, name, status, today's start date and lines
     */
    @AuraEnabled
    public static AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo loadExistingDraftQuote(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('Quote ID is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.loadExistingDraftQuote(quoteId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('loadExistingDraftQuote failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load the selected draft quote. Please try again or contact support.');
        }
    }

    /**
     * @description Creates a CPQ amendment quote for the given contract and returns
     *              the key display fields needed by the LWC quote editor.
     * @param contractId The Contract record Id
     * @return AmendmentQuoteInfo with id, name, status and startDate
     */
    @AuraEnabled
    public static AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo createAmendmentQuote(String contractId) {
        if (String.isBlank(contractId)) {
            throw new AuraHandledException(ERR_CONTRACT_REQUIRED);
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.createAmendmentQuote(contractId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('createAmendmentQuote failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to create amendment quote. Please try again or contact support.');
        }
    }

    /**
     * @description Creates a new CPQ amendment quote and applies user-specified quantity
     *              changes keyed by subscription Id.
     * @param contractId     The Contract record Id
     * @param quantitiesJson JSON-serialised Map<subscriptionId, newQuantity>
     * @return The new amendment SBQQ__Quote__c Id as a String
     */
    @AuraEnabled
    public static String createAmendmentWithQuantities(String contractId, String quantitiesJson) {
        if (String.isBlank(contractId) || String.isBlank(quantitiesJson)) {
            throw new AuraHandledException(ERR_QUANTITIES_REQUIRED);
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.createAmendmentWithQuantities(contractId, quantitiesJson);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('createAmendmentWithQuantities failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to create amendment. Please try again or contact support.');
        }
    }

    // ─── Quote line reads and updates ─────────────────────────────────────────

    /**
     * @description Retrieves all quote lines for the given quote.
     * @param quoteId The SBQQ__Quote__c Id
     * @return List of QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> getQuoteLines(String quoteId) {
        return AgenticQTC_QuoteAmendmentService.getQuoteLines(quoteId);
    }

    /**
     * @description Updates the quantity for a single quote line, then returns the
     *              refreshed set of QuoteLineInfo DTOs.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param quoteLineId The SBQQ__QuoteLine__c Id to update
     * @param newQuantity The new quantity value
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> updateQuoteLineQuantity(
            String quoteId, String quoteLineId, Decimal newQuantity) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId) || newQuantity == null) {
            throw new AuraHandledException('quoteId, quoteLineId and newQuantity are required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.applyLineQuantityUpdate(quoteId, quoteLineId, newQuantity);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('updateQuoteLineQuantity failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to update quote line. Please try again or contact support.');
        }
    }

    /**
     * @description Updates the quantity for an MDQ segment (or all segments sharing a
     *              segmentKey when applyToAllSegments is true), then returns refreshed DTOs.
     * @param quoteId            The SBQQ__Quote__c Id
     * @param quoteLineId        The specific segment SBQQ__QuoteLine__c Id to update
     * @param newQuantity        The new quantity value
     * @param segmentKey         The SBQQ__SegmentKey__c shared by all segments of this product
     * @param applyToAllSegments When true, all segments with the same segmentKey are updated
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> updateMdqSegmentQuantity(
            String quoteId, String quoteLineId, Decimal newQuantity,
            String segmentKey, Boolean applyToAllSegments) {
        if (String.isBlank(quoteId) || String.isBlank(quoteLineId) || newQuantity == null) {
            throw new AuraHandledException('quoteId, quoteLineId and newQuantity are required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.applyMdqSegmentQuantityUpdate(
                quoteId, quoteLineId, newQuantity, segmentKey, applyToAllSegments);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('updateMdqSegmentQuantity failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to update MDQ segment. Please try again or contact support.');
        }
    }

    /**
     * @description Combined save for the quote editor's Save button. Applies pending
     *              line-quantity changes AND quote-header changes (start date, invoicing
     *              contact, software delivery contact) in a single CPQ round-trip.
     *              Returns the refreshed lines plus a fresh QuoteDetailsInfo so the LWC
     *              can map the persisted header values back onto its local state.
     * @param quoteId                   The SBQQ__Quote__c Id
     * @param changesJson               JSON array of { lineId, quantity, segmentKey?, applyToAll? }
     * @param startDate                 The current start-date value to persist (nullable)
     * @param invoicingContactId        The current invoicing contact Id (blank clears)
     * @param softwareDeliveryContactId The current delivery contact Id (blank clears)
     * @return QuoteSaveResult with refreshed lines and quote details
     */
    @AuraEnabled
    public static AgenticQTC_QuoteAmendmentService.QuoteSaveResult saveQuoteChanges(
            String quoteId, String changesJson,
            Date startDate, String invoicingContactId, String softwareDeliveryContactId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.saveQuoteChanges(
                quoteId, changesJson, startDate, invoicingContactId, softwareDeliveryContactId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            // BIZ-83493: surface the exact org validation message(s) (address verification,
            // Contract Master Terms, QLI required, etc.) so the user sees the real reason the
            // save was rejected. The failed 'Finalize OSA' transition has already rolled back the
            // entire synchronous save, so nothing persisted. Iterate getNumDml() to capture every
            // failing rule, not just the first.
            String msg = '';
            for (Integer i = 0; i < e.getNumDml(); i++) {
                msg += (i > 0 ? '\n' : '') + e.getDmlMessage(i);
            }
            Nebula.Logger.warn('saveQuoteChanges validation blocked: ' + msg, e)
                .addTag('AgenticQTC_AmendContractController')
                .setRecordId(quoteId);
            Nebula.Logger.saveLog();
            throw new AuraHandledException(String.isBlank(msg) ? e.getMessage() : msg);
        } catch (Exception e) {
            Nebula.Logger.error('saveQuoteChanges failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw internalError('Failed to save changes. Please try again or contact support.', e);
        }
    }

    /**
     * @description Applies all pending quantity changes for a quote in a single call.
     *              Called by the Save button on the quote editor.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param changesJson JSON array of { lineId, quantity, segmentKey?, applyToAll? }
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> saveQuantityChanges(
            String quoteId, String changesJson) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.saveQuantityChanges(quoteId, changesJson);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('saveQuantityChanges failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to save changes. Please try again or contact support.');
        }
    }

    /**
     * @description Updates the ACV Change value on a single quote line.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param quoteLineId The SBQQ__QuoteLine__c Id to update
     * @param acvChange   The new ACV Change value
     * @return Refreshed list of QuoteLineInfo DTOs
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> updateQuoteLineAcvChange(
            String quoteId, String quoteLineId, Decimal acvChange) {
        return AgenticQTC_QuoteAmendmentService.updateQuoteLineAcvChange(quoteId, quoteLineId, acvChange);
    }

    // ─── Quote-level reads and updates ────────────────────────────────────────

    /**
     * @description Retrieves quote-level display fields for the amendment editor.
     * @param quoteId The SBQQ__Quote__c Id
     * @return QuoteDetailsInfo DTO
     */
    @AuraEnabled
    public static AgenticQTC_QuoteAmendmentService.QuoteDetailsInfo getQuoteDetails(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.getQuoteDetails(quoteId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('getQuoteDetails failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load quote details. Please try again or contact support.');
        }
    }

    /**
     * @description Triggers CPQ price calculation for a quote.
     * @param quoteId The SBQQ__Quote__c Id
     */
    @AuraEnabled
    public static void calculateQuote(String quoteId) {
        AgenticQTC_QuoteAmendmentService.calculateQuote(quoteId);
    }

    /**
     * @description Updates the start date on an amendment quote.
     * @param quoteId   The SBQQ__Quote__c Id
     * @param startDate The new start date
     */
    @AuraEnabled
    public static void updateQuoteStartDate(String quoteId, Date startDate) {
        AgenticQTC_QuoteAmendmentService.updateQuoteStartDate(quoteId, startDate);
    }

    /**
     * @description Updates the SFA flag on an amendment quote.
     * @param quoteId The SBQQ__Quote__c Id
     * @param sfa     The new SFA value
     */
    @AuraEnabled
    public static void updateQuoteSfa(String quoteId, Boolean sfa) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        AgenticQTC_QuoteAmendmentService.updateQuoteSfa(quoteId, sfa);
    }

    // ─── Contact picker (Invoicing / Software Delivery Contact) ────────────────

    /**
     * @description Returns the contacts on the given account for the quote editor's
     *              "Select Contact" modal. Sorted by name in Apex; the LWC moves the
     *              currently selected contact to the top when rendering.
     * @param accountId The Account record Id (already known to the LWC)
     * @return List of ContactOption DTOs (id, name, email, title)
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.ContactOption> getAccountContacts(String accountId) {
        if (String.isBlank(accountId)) {
            throw new AuraHandledException('Account Id is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.getAccountContacts(accountId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('getAccountContacts failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load contacts. Please try again or contact support.');
        }
    }

    /**
     * @description Server-side fallback used by the contact picker when no match exists
     *              in the LWC's locally-cached 1000 contacts. Searches the full Contact
     *              table by `Name LIKE` (case-insensitive). The LWC sends the raw search
     *              term — the service layer trims surrounding whitespace.
     * @param searchTerm Free-text term entered by the user (untrimmed).
     * @return List of ContactOption DTOs that match the term.
     */
    @AuraEnabled
    public static List<AgenticQTC_QuoteAmendmentService.ContactOption> searchContacts(String searchTerm) {
        try {
            throwIfTestRequested();
            return AgenticQTC_QuoteAmendmentService.searchContacts(searchTerm);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('searchContacts failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to search contacts. Please try again or contact support.');
        }
    }

    @AuraEnabled
    public static List<SBQQ__QuoteLine__c> getCurrentSegmentInfo(String quoteId) {
        return AgenticQTC_QuoteAmendmentService.getCurrentSegment(quoteId);
    }

    /**
     * @description Sets ApprovalStatus__c to 'Approved' when SBAA preview returned zero
     *              approval items, meaning no approval rules apply to this quote. Called
     *              by the LWC on save after confirming approvalItems.length === 0.
     * @param quoteId The SBQQ__Quote__c Id
     */
    @AuraEnabled
    public static void autoApproveIfNotRequired(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        try {
            AgenticQTC_QuoteAmendmentService.autoApproveIfNotRequired(quoteId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('autoApproveIfNotRequired failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to update quote approval status. Please try again or contact support.');
        }
    }

    /**
     * @description Updates the invoicing or software delivery contact on the quote.
     *              Pass a blank contactId to clear the field.
     *              No longer called from the LWC after 2026-05-12 — contact changes are now
     *              batched through saveQuoteChanges and persisted in the combined CPQ save.
     *              Method retained (commented out) for future re-use if needed.
     * @param quoteId     The SBQQ__Quote__c Id
     * @param contactType "invoicing" or "delivery"
     * @param contactId   The Contact Id to assign (or blank to clear)
     */
    // @AuraEnabled
    // public static void updateQuoteContact(String quoteId, String contactType, String contactId) {
    //     if (String.isBlank(quoteId) || String.isBlank(contactType)) {
    //         throw new AuraHandledException('Quote Id and contact type are required');
    //     }
    //     try {
    //         AgenticQTC_QuoteAmendmentService.updateQuoteContact(quoteId, contactType, contactId);
    //     } catch (AuraHandledException e) {
    //         throw e;
    //     } catch (Exception e) {
    //         Nebula.Logger.error('updateQuoteContact failed: ' + e.getMessage(), e)
    //             .addTag('AgenticQTC_AmendContractController');
    //         Nebula.Logger.saveLog();
    //         throw new AuraHandledException('Failed to update contact on the quote. Please try again or contact support.');
    //     }
    // }

    // ─── Approval process queries ──────────────────────────────────────────────

    /**
     * @description Returns pending Salesforce Approval Process workitems for a quote,
     *              including approver name, title, reason, and rule name.
     * @param quoteId The SBQQ__Quote__c Id
     * @return List of ApprovalItem DTOs
     */
    /*@AuraEnabled
    public static List<AgenticQTC_ApprovalLogicService.ApprovalItem> getRunningApprovals(String quoteId) {
        if (String.isBlank(quoteId)) {
            throw new AuraHandledException('quoteId is required');
        }
        try {
            throwIfTestRequested();
            return AgenticQTC_ApprovalLogicService.getRunningApprovals(quoteId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error('getRunningApprovals failed: ' + e.getMessage(), e)
                .addTag('AgenticQTC_AmendContractController');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Failed to load running approvals. Please try again or contact support.');
        } 
    }*/
}