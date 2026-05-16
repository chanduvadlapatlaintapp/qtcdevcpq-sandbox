/**
 * @description
 * Support helper for Single Quote Single Deal factory to improve readability.
 * Contains utilities, data accessors, CPQ amender bridge, migration helpers,
 * and amendment update helpers. No business logic changed.
 */
public without sharing class SingleQuoteDealFactorySupport {

    /* ============================================================
       PUBLIC ORCHESTRATION ENTRY POINTS (DELEGATED CALLS)
       ============================================================ */

    // Creates new Opp and Quote for non-amendment path
    public static SBQQ__Quote__c createNewOpportunityAndQuote(SingleQuoteSingleDealController.QuoteWrapper qw) {
        String mappedStage = mapDealStageToStageName(qw.dealStage);
        String opportunityStage = mappedStage != null ? mappedStage : 'Qualify';

        Opportunity opp = new Opportunity(
            Name                  = 'New Opportunity',
            AccountId             = qw.accId,
            OP4I_Deal_Id__c       = qw.dealId,
            CloseDate             = Date.today().addDays(30),
            StageName             = opportunityStage,
            OwnerId               = UserInfo.getUserId(),
            CurrencyIsoCode       = qw.currencyIso,
            Source_System__c	  = 'OP4I'
        );
        if (!String.isBlank(qw.dealOwnerId)) {
            opp.OP4I_Deal_Owner_Id__c = qw.dealOwnerId;
        }   
        insert opp;

        Id draftQuoteRecordTypeId = Schema.SObjectType.SBQQ__Quote__c
            .getRecordTypeInfosByDeveloperName()
            .get('Draft_Quote')
            .getRecordTypeId();

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c                  = opp.Id,
            OwnerId                                = UserInfo.getUserId(),
            SBQQ__Primary__c                       = true,
            OP4IDealID__c                          = qw.dealId,
            OP4I_Sales_Segment__c                  = qw.saleSegment,
            OP4I_Deal_Name__c                      = qw.dealId,
            SBQQ__Account__c                       = qw.accId,
            RecordTypeId                           = draftQuoteRecordTypeId,
            Deal_Type__c                           = qw.dealType,
            CurrencyIsoCode                        = qw.currencyIso,
            Source_System__c					   = 'OP4I',
            Expected_Signaure_Date_Booking_Date__c = qw.expectedSignatureDate
        );
        insert quote;
        return quote;
    }

    // Processes existing amendment Opp/Quote and returns resulting amendment quote
    public static SBQQ__Quote__c processExistingAmendOppAndQuote(SingleQuoteSingleDealController.QuoteWrapper qw, String mockResponse) {
        // There is always exactly one SF primary quote
        SBQQ__Quote__c quoteRec = qw.quotes[0];
        // ---------- Valid amendment → reuse ----------
        return quoteRec;
    }
 
    // Updates non-amendment existing opp/quote values
    public static void updateExistingNonAmend(SBQQ__Quote__c quoteRec,SingleQuoteSingleDealController.QuoteWrapper qw) {
        Boolean oppChanged = false;
        Boolean quoteChanged = false;
        
        if (quoteRec.Deal_Type__c != qw.dealType) {
            quoteRec.Deal_Type__c = qw.dealType;
            quoteChanged = true;
        }
        
        Opportunity opp;
        if (quoteRec.SBQQ__Opportunity2__c != null) {
            opp = [SELECT Id, StageName, OP4I_Deal_Owner_Id__c 
                   FROM Opportunity
                   WHERE Id = :quoteRec.SBQQ__Opportunity2__c
                   LIMIT 1];
        }
        
        if (opp != null) {
            if (opp.OP4I_Deal_Owner_Id__c != qw.dealOwnerId && !String.isBlank(qw.dealOwnerId)) {
                opp.OP4I_Deal_Owner_Id__c = qw.dealOwnerId;
                oppChanged = true;
            }
            
            String mappedStage = mapDealStageToStageName(qw.dealStage);
            if (mappedStage != null && opp.StageName != mappedStage) {
                opp.StageName = mappedStage;
                oppChanged = true;
            }
        }
        
        if (quoteChanged) {
            update quoteRec;
        }
        if (oppChanged) {
            update opp;
        }
    }

    // Applies pending updates to amended opportunities and quotes
    public static void updateAmendOppQuote(SingleQuoteSingleDealController.QuoteWrapper quoteWrapper) {
        if (!quoteWrapper.resultOppUpd.isEmpty() && quoteWrapper.resultOppUpd.size() > 0) {
            update quoteWrapper.resultOppUpd;
        }
        if (!quoteWrapper.resultQuoteUpd.isEmpty() && quoteWrapper.resultQuoteUpd.size() > 0) {
            update quoteWrapper.resultQuoteUpd;
        }
    }

    /* ============================================================
       OSA / CPQ AMENDER
       ============================================================ */

    // Invokes CPQ Amender to create Opp/Quote and updates fields
    public static SBQQ__Quote__c createOpportunityAndQuote(SingleQuoteSingleDealController.QuoteWrapper qw, String mockResponse) {
        String quoteOppJSON =
            Test.isRunningTest()
                ? mockResponse
                : SBQQ.ServiceRouter.load(
                    'SBQQ.ContractManipulationAPI.ContractAmender',
                    qw.activeContract.Id,
                    null
                  );

        String quoteId = quoteOppJSON.substringAfter('SBQQ__Quote__c/').left(18);
        String oppId = quoteOppJSON.substringAfter('Opportunity/').left(18);
        String mappedStage = mapDealStageToStageName(qw.dealStage);

        Opportunity opp = new Opportunity(
            Id = oppId,
            AccountId = qw.accId,
            OP4I_Deal_Id__c = qw.dealId,
            Source_System__c = 'OP4I',
            StageName = (mappedStage != null) ? mappedStage : OpportunityConstants.STAGE_QUALIFY
        );
        if (qw.dealOwnerId != null) {
            opp.OP4I_Deal_Owner_Id__c = qw.dealOwnerId;
        }
        update opp;

        SBQQ__Quote__c quot = new SBQQ__Quote__c(
            Id = quoteId,
            SBQQ__Primary__c = true,
            SBQQ__MasterContract__c = qw.activeContract.Id,
            OP4IDealID__c = qw.dealId,
            OP4I_Sales_Segment__c = qw.saleSegment,
            OP4I_Deal_Name__c = qw.dealId,
            SBQQ__Account__c = qw.accId,
            Deal_Type__c = qw.dealType,
            CurrencyIsoCode = qw.currencyIso,
            Source_System__c = 'OP4I',
            Expected_Signaure_Date_Booking_Date__c = qw.expectedSignatureDate,
            Amendment_Quote__c = qw.oldQuote.Id
        );
        if (qw.amendmentStartDate != null) {
            quot.SBQQ__StartDate__c = qw.amendmentStartDate;
        }
        update quot;
        return quot;
    }

    /* ============================================================
       DATA MIGRATION HELPERS
       ============================================================ */

    // Migrates attachments and quote documents to new quote/opportunity
    public static void migrateQuoteData(Id oldQuoteId, Id newQuoteId) {
        cloneAndReparentAttachments(oldQuoteId, newQuoteId);
        reparentQuoteDocuments(oldQuoteId, newQuoteId);
        linkCasesToNewQuote(oldQuoteId, newQuoteId);
    }
    
    // Relates existing Cases from old Quote to new Quote asynchronously
    @future
    public static void linkCasesToNewQuote(Id oldQuoteId, Id newQuoteId) {
        List<Case> cases = [SELECT Id FROM Case WHERE Quote__c = :oldQuoteId];
        for (Case c : cases) {
            c.Quote__c = newQuoteId;
        }
        if (!cases.isEmpty()) update cases;
    }
    
    // Clones legacy attachments from old quote to new quote and deletes old
    public static void cloneAndReparentAttachments(Id oldQuoteId, Id newQuoteId) {
        if (oldQuoteId == null || newQuoteId == null) return;

        List<Attachment> oldAttachments = fetchLegacyAttachments(oldQuoteId);
        if (oldAttachments.isEmpty()) return;

        List<Attachment> newAttachments = buildAttachmentClones(oldAttachments, newQuoteId);
        if (!newAttachments.isEmpty()) {
            insert newAttachments;
            delete oldAttachments;
        }
    }

    // Builds new Attachment records cloned from old list for a new parent
    public static List<Attachment> buildAttachmentClones(List<Attachment> oldAttachments, Id newQuoteId) {
        List<Attachment> clones = new List<Attachment>();
        for (Attachment oldAtt : oldAttachments) {
            clones.add(new Attachment(
                ParentId    = newQuoteId,
                Name        = oldAtt.Name,
                Body        = oldAtt.Body,
                ContentType = oldAtt.ContentType,
                Description = oldAtt.Description,
                OwnerId     = oldAtt.OwnerId,
                IsPrivate   = oldAtt.IsPrivate
            ));
        }
        return clones;
    }

    // Reparents quote documents from old quote to new quote/opportunity
    public static void reparentQuoteDocuments(Id oldQuoteId, Id newQuoteId) {
        if (oldQuoteId == null || newQuoteId == null) return;

        List<SBQQ__QuoteDocument__c> oldDocs = [
            SELECT Name,
                   CurrencyIsoCode,
                   SBQQ__QuoteTemplate__c,
                   SBQQ__Template__c,
                   SBQQ__Version__c,
                   SBQQ__OutputFormat__c,
                   SBQQ__PaperSize__c,
                   SBQQ__CustomerAmount__c,
                   SBQQ__ListAmount__c,
                   SBQQ__NetAmount__c,
                   SBQQ__ElectronicSignature__c,
                   Sync_NetSuite__c, 
            	   SBQQ__DocumentId__c
            FROM SBQQ__QuoteDocument__c
            WHERE SBQQ__Quote__c = :oldQuoteId
        ];
        if (oldDocs.isEmpty()) return;

        List<SBQQ__QuoteDocument__c> newDocs = new List<SBQQ__QuoteDocument__c>();
        for (SBQQ__QuoteDocument__c oldDoc : oldDocs) {
            newDocs.add(new SBQQ__QuoteDocument__c(
                Name                         = oldDoc.Name,
                CurrencyIsoCode              = oldDoc.CurrencyIsoCode,
                SBQQ__Quote__c               = newQuoteId,
                SBQQ__QuoteTemplate__c       = oldDoc.SBQQ__QuoteTemplate__c,
                SBQQ__Template__c            = oldDoc.SBQQ__Template__c,
                SBQQ__Version__c             = oldDoc.SBQQ__Version__c,
                SBQQ__OutputFormat__c        = oldDoc.SBQQ__OutputFormat__c,
                SBQQ__PaperSize__c           = oldDoc.SBQQ__PaperSize__c,
                SBQQ__CustomerAmount__c      = oldDoc.SBQQ__CustomerAmount__c,
                SBQQ__ListAmount__c          = oldDoc.SBQQ__ListAmount__c,
                SBQQ__NetAmount__c           = oldDoc.SBQQ__NetAmount__c,
                SBQQ__ElectronicSignature__c = oldDoc.SBQQ__ElectronicSignature__c,
                SBQQ__DocumentId__c			 = oldDoc.SBQQ__DocumentId__c,
                Sync_NetSuite__c             = oldDoc.Sync_NetSuite__c
            ));
        }
        insert newDocs;
    }

    /* ============================================================
       DATA ACCESS HELPERS
       ============================================================ */

    // Fetches Account by Id with basic fields
    public static Account getAccount(String accId) {
        return [
            SELECT Id, Name, CurrencyIsoCode
            FROM Account
            WHERE Id = :accId
            LIMIT 1
        ];
    }

    // Fetches the most recently activated Contract by OSA number
    public static Contract getActiveContract(String osaNumber) {
        if (String.isBlank(osaNumber)) {
            return null;
        }
        
        List<Contract> conList = [
            SELECT Id, OSA_Number__c
            FROM Contract
            WHERE OSA_Number__c = :osaNumber
            ORDER BY ActivatedDate DESC
            LIMIT 1
        ];
        
        return conList.isEmpty() ? null : conList[0];
    }

    // Gets primary quotes for a dealId ordered by created date
    public static List<SBQQ__Quote__c> getPrimaryQuotes(String dealId) {
        return [
            SELECT Id, SBQQ__Primary__c, OSA_Number__c, SBQQ__Opportunity2__c, OP4IDealID__c,
                   SBQQ__MasterContract__c, Deal_Type__c, SBQQ__StartDate__c 
            FROM SBQQ__Quote__c
            WHERE OP4IDealID__c = :dealId
              AND SBQQ__Primary__c = TRUE
            ORDER BY CreatedDate DESC
        ];
    }

    // Retrieves legacy Attachments for a given Quote
    public static List<Attachment> fetchLegacyAttachments(Id quoteId) {
        return [
            SELECT Id, Name, Body, ContentType, Description, OwnerId, IsPrivate
            FROM Attachment
            WHERE ParentId = :quoteId
        ];
    }

    // Resolves full Sales Segment picklist value from numeric segment code
    public static String getSalesSegment(String segmentNumber) {
        Schema.SObjectField field = Schema.getGlobalDescribe().get('Account').getDescribe().fields.getMap().get('OP4I_Sales_Segment__c');
        Map<String, String> segments = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            segments.put(entry.getValue().substring(0, 2), entry.getValue());
        }
        return segments.containsKey(segmentNumber) ? segments.get(segmentNumber) : '';
    }

    // Returns a valid Deal Owner Id if exists, otherwise null
    public static String getDealOwner(String dealOwnerId) {
        if(String.isBlank(dealOwnerId)){
            return null;
        }
        List<User> u = [SELECT Id FROM User WHERE Id = :dealOwnerId LIMIT 1];
        return u.isEmpty() ? null : u[0].Id;
    }

    /* ============================================================
       SHARED UTILITIES
       ============================================================ */

    // Determines if inputs require creating an amendment
    public static Boolean shouldCreateAmendment(String osaNumber, String dealType) {
        return String.isNotBlank(osaNumber)
            && new Set<String>{
                QuoteConstants.DEAL_TYPE_ADD_ON,
                QuoteConstants.DEAL_TYPE_CONTRACT_REPLACEMENT,
                QuoteConstants.DEAL_TYPE_NEW_SOFTWARE,
                QuoteConstants.DEAL_TYPE_UPLIFT
            }.contains(dealType);
    }

    // Compares OSA values for change detection
    public static Boolean hasOSAChanged(String oldOSA, String newOSA) {
        if (String.isBlank(newOSA)) {
            return false; // OP4I not sending OSA should not be treated as change
        }
        return oldOSA != newOSA;
    }

    // Maps encoded deal stage string to a valid StageName or null
    public static String mapDealStageToStageName(String dealStage) {
        if (String.isBlank(dealStage)) return null;
        String decoded = EncodingUtil.urlDecode(dealStage, 'UTF-8');
        for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (pe.getValue() == decoded) return decoded;
        }
        return null;
    }
    
    // Transaction decision method
    public static Boolean isTransactionTypeChange(SBQQ__Quote__c existingQuote,SingleQuoteSingleDealController.QuoteWrapper qw) {
        Boolean isOp4IBlankOSA = String.isBlank(qw.osaNumber);
        Boolean isQuoteOSAPlaceholder = !String.isBlank(existingQuote.OSA_Number__c);
        Boolean isMasterContractBlank = existingQuote.SBQQ__MasterContract__c == null;
        
        // Active contract mismatch
        Boolean isActiveContractChanged =
            qw.activeContract != null &&
            existingQuote.SBQQ__MasterContract__c != qw.activeContract.Id;
        
        // Start date mismatch
        Boolean isStartDateChanged =
            (isOp4IBlankOSA && qw.amendmentStartDate == null)
            ? false
            : existingQuote.SBQQ__StartDate__c != qw.amendmentStartDate;
        
        // ------------------------------------------------------------
        // 1) Highest priority: Contract or Start Date mismatch
        // ------------------------------------------------------------
        if (isActiveContractChanged || isStartDateChanged) {
            return true;
        }
        
        // ------------------------------------------------------------
        // 2) NON-transaction case (legacy placeholder)
        //    Only valid when OP4I is not sending contract context
        // ------------------------------------------------------------
        if (isOp4IBlankOSA && isQuoteOSAPlaceholder && isMasterContractBlank && qw.activeContract == null) {
            return false;
        }
        
        // ------------------------------------------------------------
        // 3) Intentional OSA removal => transaction change
        // ------------------------------------------------------------
        if (isOp4IBlankOSA && !isMasterContractBlank) {
            return true;
        }
        
        // ------------------------------------------------------------
        // 4) Default OSA comparison
        // ------------------------------------------------------------
        return SingleQuoteDealFactorySupport.hasOSAChanged(
            existingQuote.OSA_Number__c,
            qw.osaNumber
        );
    }
}