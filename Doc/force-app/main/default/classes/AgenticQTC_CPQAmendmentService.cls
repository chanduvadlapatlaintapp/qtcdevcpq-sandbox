/********************************************************************************
*  Name             :  AgenticQTC_CPQAmendmentService
*  Description      :  Generic CPQ amendment / quote-line update service.
*                      Single Aura-enabled entry point handles two scenarios:
*                        1. Subscription-keyed: create amendment from contract,
*                           match QuoteLines by SBQQ__RenewedSubscription__c,
*                           apply field updates, calculate & save.
*                        2. QuoteLine-keyed: load quote, match by QuoteLine Id,
*                           apply field updates, calculate & save.
*  Change history   :
*  Date          Author            Description
*  24/04/26      Gaurav Mishra     Created
*  28/04/26                        Generic field-update rewrite
********************************************************************************/
// Intentionally without sharing: orchestrates CPQ API calls via AgenticQTC_CPQAPIUtils (ServiceRouter)
// and accesses quote/subscription records that may be owned by integration users.
// Security is enforced at the @AuraEnabled controller layer (with sharing).
public without sharing class AgenticQTC_CPQAmendmentService {

    private static final String SUBSCRIPTION_MATCH_FIELD = 'SBQQ__UpgradedSubscription__c';

    public class CPQAmendmentException extends Exception {}

    /**
     * @description LWC-friendly input. Provide ONE of contractId or quoteId.
     *              lineUpdates carries per-line field/value maps keyed by either
     *              Subscription Id (when contractId is set) or QuoteLine Id
     *              (when quoteId is set).
     */
    public class AmendmentRequest {
        @AuraEnabled public String contractId;
        @AuraEnabled public String quoteId;
        @AuraEnabled public List<LineFieldValues> lineUpdates;
        @AuraEnabled public Map<String, Object> quoteFieldValues; // optional header-level field updates for quote (e.g. start date)
    }

    public class LineFieldValues {
        @AuraEnabled public Id keyId;
        @AuraEnabled public Map<String, Object> fieldValues;
    }

    /**
     * @description Single Aura-enabled entry point. Routes to the contract-amendment
     *              flow or the existing-quote flow based on the request.
     */
    @AuraEnabled
    public static Map<String, Object> applyQuoteLineUpdates(AmendmentRequest request) {
        System.debug('AgenticQTC_CPQAmendmentService.applyQuoteLineUpdates request: ' + JSON.serialize(request));
        try {
            if (request == null) {
                throw new CPQAmendmentException('Request is required.');
            }
            if (request.contractId != null && request.quoteId != null) {
                throw new CPQAmendmentException('Provide either contractId or quoteId, not both.');
            }

            Map<Id, Map<String, Object>> fieldValuesByKeyId = buildFieldValuesByKeyId(request.lineUpdates);

            if (request.contractId != null) {
                return amendAndUpdateLines(request.contractId, fieldValuesByKeyId);
            }
            if (request.quoteId != null) {
                return updateQuoteAndLines(request.quoteId, request.quoteFieldValues, fieldValuesByKeyId);
            }
            throw new CPQAmendmentException('Either contractId or quoteId is required.');
        } catch (Exception e) {
            Nebula.Logger.error('applyQuoteLineUpdates failed: ' + e.getMessage(), e).addTag('AgenticQTC_CPQAmendmentService').addTag('Amendment');
            Nebula.Logger.saveLog();
            throw new AuraHandledException('Amendment request failed. Please try again or contact support.');
        }
    }

    /**
     * @description Scenario 1 — Creates an amendment quote from the contract, then
     *              applies the supplied field/value maps to QuoteLines whose
     *              SBQQ__UpgradedSubscription__c matches the input keys. Calculates
     *              and saves the quote.
     */
    public static Map<String, Object> amendAndUpdateLines(Id contractId,
            Map<Id, Map<String, Object>> fieldValuesBySubscriptionId) {
        try {
            Map<String, Object> quoteModel = AgenticQTC_CPQAPIUtils.createAmendmentQuote(contractId);
            Id amendmentQuoteId = AgenticQTC_CPQAPIUtils.getQuoteId(quoteModel);

            if (fieldValuesBySubscriptionId == null || fieldValuesBySubscriptionId.isEmpty()) {
                return quoteModel;
            }

            Map<Id, Map<String, Object>> fieldValuesByLineId =
                translateSubscriptionKeysToLineIds(quoteModel, fieldValuesBySubscriptionId);

            Integer count = applyFieldValuesToQuoteLines(quoteModel, fieldValuesByLineId);

            return calculateAndSaveQuote(quoteModel);
        } catch (Exception e) {
            Nebula.Logger.error('amendAndUpdateLines failed for contract ' + contractId + ': ' + e.getMessage(), e).addTag('AgenticQTC_CPQAmendmentService').addTag('Amendment').setRecordId(contractId);
            Nebula.Logger.saveLog();
            throw new CPQAmendmentException('Failed to amend contract ' + contractId + ': ' + e.getMessage(), e);
        }
    }

    /**
     * @description Loads an existing quote, applies a map of header field values to the
     *              top-level quote record AND per-line field/value maps to the matching
     *              QuoteLines, then calculates and saves in a single CPQ round-trip.
     *              Pass null/empty for either side if only the other set of fields changed.
     */
    public static Map<String, Object> updateQuoteAndLines(Id quoteId,
            Map<String, Object> quoteFieldValues,
            Map<Id, Map<String, Object>> fieldValuesByLineId) {
        try {
            Map<String, Object> quoteModel = AgenticQTC_CPQAPIUtils.readQuoteModel(quoteId);

            if ((quoteFieldValues == null || quoteFieldValues.isEmpty()) && (fieldValuesByLineId == null || fieldValuesByLineId.isEmpty())) {
                return quoteModel;
            }
            if (quoteFieldValues != null && !quoteFieldValues.isEmpty()) {
                applyFieldValuesToQuoteRecord(quoteModel, quoteFieldValues);
            }
            if (fieldValuesByLineId != null && !fieldValuesByLineId.isEmpty()) {
                applyFieldValuesToQuoteLines(quoteModel, fieldValuesByLineId);
            }

            return calculateAndSaveQuote(quoteModel);

        } catch (Exception e) {
            Nebula.Logger.error('updateQuoteAndLines failed for quote ' + quoteId + ': ' + e.getMessage(), e).addTag('AgenticQTC_CPQAmendmentService').addTag('Amendment').setRecordId(quoteId);
            Nebula.Logger.saveLog();
            throw new CPQAmendmentException('Failed to update quote ' + quoteId + ': ' + e.getMessage(), e);
        }
    }

    /**
     * @description Runs CPQ price calculation synchronously, then saves the result
     *              via QuoteSaver so changes are persisted to the database.
     */
    public static Map<String, Object> calculateAndSaveQuote(Map<String, Object> quoteModel) {
        try {
            // Mark this quote as created/managed by the AgenticQTC (Simplified Quoting)
            // flow so the Quote Calculator Plugin runs the AgenticQTC code path (awaits
            // async bundle work, avoiding the JSQC "Error parsing quote" race). Stamped on
            // the model here (creation + every AgenticQTC save) and persisted via QuoteSaver.
            // Standard QLE / record Calculate / batch never set this -> unchanged behavior.
            Object recObj = (quoteModel != null) ? quoteModel.get('record') : null;
            if (recObj instanceof Map<String, Object>) {
                ((Map<String, Object>) recObj).put('Created_by_Simplified_Quoting__c', true);
            }
            Map <String, Object> calculatedQuote = AgenticQTC_CPQAPIUtils.calculateQuoteModel(quoteModel, '');
            Map<String, Object> saved = AgenticQTC_CPQAPIUtils.saveQuoteModel(calculatedQuote);
            // BIZ-83387: re-fire CPQ's native primary-quote -> Opportunity Products sync.
            // Must run synchronously here -- CPQ's sync throws hasMaxStackDepth from an
            // async/Queueable context.
            resyncOpportunityProducts(AgenticQTC_CPQAPIUtils.getQuoteId(saved));
            return saved;
            //return AgenticQTC_CPQAPIUtils.calculateQuoteModel(quoteModel, 'AgenticQTC_CalculatorCallback');
        } catch (Exception e) {
            System.debug('Error in calculateAndSaveQuote: ' + e.getMessage());
            Nebula.Logger.error('calculateAndSaveQuote failed: ' + e.getMessage(), e).addTag('AgenticQTC_CPQAmendmentService').addTag('Amendment');
            Nebula.Logger.saveLog();
            throw new CPQAmendmentException('Calculate/save failed: ' + e.getMessage(), e);
        }
    }

    /**
     * @description BIZ-83387 — Re-fires Salesforce CPQ's out-of-the-box "primary quote ->
     *              Opportunity Products" sync. Per the SBQQ__Primary__c help text, selecting
     *              that checkbox "sync[s] quote line items with opportunity line items", and
     *              CPQ only runs the sync on a false -> true transition (or a Quote Line
     *              Editor save). The agentic amendment quote is created already-primary and
     *              saved via the headless QuoteSaver API, so the transition never fires and
     *              the Opportunity stays empty. Cycling the flag false -> true reproduces the
     *              manual fix.
     *
     *              Runs SYNCHRONOUSLY (no Queueable) — CPQ's sync throws hasMaxStackDepth
     *              from an async context. Verified in qtcmock that a same-transaction
     *              false -> true toggle (after the QuoteSaver save) regenerates the
     *              Opportunity Products with correct amendment deltas. Guarded to Primary,
     *              Opportunity-linked quotes; skipped in test context (no live CPQ engine).
     * @param quoteId The amendment SBQQ__Quote__c Id whose Opportunity Products to re-sync
     */
    @TestVisible
    private static void resyncOpportunityProducts(Id quoteId) {
        if (quoteId == null || Test.isRunningTest()) {
            return;
        }
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, SBQQ__Primary__c, SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            LIMIT 1
        ];
        // Only a Primary quote linked to an Opportunity has products to sync.
        if (quotes.isEmpty() || quotes[0].SBQQ__Primary__c != true || quotes[0].SBQQ__Opportunity2__c == null) {
            return;
        }
        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Primary__c = false);
        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Primary__c = true);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    private static Map<Id, Map<String, Object>> buildFieldValuesByKeyId(List<LineFieldValues> updates) {
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        if (updates == null) {
            return result;
        }
        for (LineFieldValues entry : updates) {
            if (entry != null && entry.keyId != null && entry.fieldValues != null) {
                result.put(entry.keyId, entry.fieldValues);
            }
        }
        return result;
    }

    @TestVisible
    private static Map<Id, Map<String, Object>> translateSubscriptionKeysToLineIds(
            Map<String, Object> quoteModel,
            Map<Id, Map<String, Object>> fieldValuesBySubscriptionId) {

        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        for (Map<String, Object> lineRecord : collectLineRecords(quoteModel)) {
            Object subRef = lineRecord.get(SUBSCRIPTION_MATCH_FIELD);
            Object lineIdRef = lineRecord.get('Id');
            if (subRef == null || lineIdRef == null) {
                continue;
            }
            Id subId  = Id.valueOf(String.valueOf(subRef));
            Id lineId = Id.valueOf(String.valueOf(lineIdRef));
            Map<String, Object> values = fieldValuesBySubscriptionId.get(subId);
            if (values != null) {
                result.put(lineId, values);
            }
        }
        return result;
    }

    /**
     * @description Writes header field/value pairs onto the top-level quote record map
     *              of the CPQ quote model. Used for fields like SBQQ__StartDate__c and
     *              custom contact lookups during the combined save flow.
     */
    @TestVisible
    private static void applyFieldValuesToQuoteRecord(Map<String, Object> quoteModel,
            Map<String, Object> quoteFieldValues) {
        Map<String, Object> record = (Map<String, Object>) quoteModel.get('record');
        if (record == null) {
            return;
        }
        for (String fieldName : quoteFieldValues.keySet()) {
            record.put(fieldName, quoteFieldValues.get(fieldName));
        }
    }

    @TestVisible
    private static Integer applyFieldValuesToQuoteLines(Map<String, Object> quoteModel,
            Map<Id, Map<String, Object>> fieldValuesByLineId) {

        Map<String, Map<String, Object>> valuesByLineIdStr = new Map<String, Map<String, Object>>();
        for (Id lineId : fieldValuesByLineId.keySet()) {
            valuesByLineIdStr.put(String.valueOf(lineId), fieldValuesByLineId.get(lineId));
        }

        Integer count = 0;
        for (Map<String, Object> lineRecord : collectLineRecords(quoteModel)) {
            String lineId = String.valueOf(lineRecord.get('Id'));
            Map<String, Object> values = valuesByLineIdStr.get(lineId);
            if (values == null) {
                continue;
            }
            for (String fieldName : values.keySet()) {
                lineRecord.put(fieldName, values.get(fieldName));
            }
            count++;
        }
        return count;
    }

    /**
     * @description Returns the QuoteLine 'record' maps from both top-level lineItems
     *              and any group lineItems on the quote model.
     */
    @TestVisible
    private static List<Map<String, Object>> collectLineRecords(Map<String, Object> quoteModel) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        addRecordsFromLines((List<Object>) quoteModel.get('lineItems'), records);

        List<Object> groups = (List<Object>) quoteModel.get('groups');
        if (groups != null) {
            for (Object grpObj : groups) {
                addRecordsFromLines(
                    (List<Object>) ((Map<String, Object>) grpObj).get('lineItems'),
                    records);
            }
        }
        return records;
    }

    private static void addRecordsFromLines(List<Object> lineItems, List<Map<String, Object>> records) {
        if (lineItems == null) {
            return;
        }
        for (Object lineObj : lineItems) {
            Map<String, Object> rec = (Map<String, Object>) ((Map<String, Object>) lineObj).get('record');
            if (rec != null) {
                records.add(rec);
            }
        }
    }

    // ─── SOQL helpers (called by AgenticQTC_AmendContractController) ─────────

    public static SBQQ__Quote__c getQuoteById(Id quoteId) {
        return [
            SELECT Id, Name, SBQQ__Status__c, SBQQ__StartDate__c
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            LIMIT 1
        ];
    }

    public static List<SBQQ__QuoteLine__c> getSegmentLines(Id quoteId, String segmentKey) {
        return [
            SELECT Id FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId AND SBQQ__SegmentKey__c = :segmentKey
            LIMIT 50000
        ];
    }
}