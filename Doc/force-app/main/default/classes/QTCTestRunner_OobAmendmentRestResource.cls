/**
 * @description REST endpoint for OOB CPQ amendment creation — the symmetric
 *              baseline counterpart to AgenticQTC_AmendmentRestResource.
 *
 *              Calls SBQQ.ContractManipulationAPI.ContractAmender directly —
 *              the same single step the custom flow's
 *              AgenticQTC_QuoteAmendmentService.createAmendmentQuote performs
 *              when no field updates are supplied. Calculate/Save are NOT run
 *              so both endpoints are symmetric (and so org-specific QuoteLine
 *              validation rules like Retainer typing don't break the baseline).
 *
 * Routing:
 *   Salesforce Apex REST resolves the LONGEST matching URL prefix, so
 *   /agenticQtc/amendment/oob/* wins over /agenticQtc/amendment/* for /oob.
 *
 * Usage:
 *   POST /services/apexrest/agenticQtc/amendment/oob
 *   { "contractId": "..." }
 *
 * Response (200):
 *   { "id": "<quoteId>", "status": "success" }
 *
 * @author AgenticQTC Team
 * @date 2026-05-29
 */
@RestResource(urlMapping='/agenticQtc/amendment/oob/*')
global class QTCTestRunner_OobAmendmentRestResource {

  @HttpPost
  global static void createOobAmendment() {
    try {
      String body = RestContext.request.requestBody.toString();
      Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(body);

      String contractId = (String) params.get('contractId');
      if (String.isBlank(contractId)) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'status'  => 'error',
          'message' => 'contractId is required'
        }));
        return;
      }

      // Vanilla OOB amendment via ContractAmender. The managed package
      // persists the SBQQ__Quote__c header itself; QuoteLines remain in the
      // returned in-memory model. We deliberately skip Calculate + Save to
      // mirror the custom flow's behavior on empty-update calls.
      Map<String, Object> quoteModel = AgenticQTC_CPQAPIUtils.createAmendmentQuote(Id.valueOf(contractId));
      Id quoteId = AgenticQTC_CPQAPIUtils.getQuoteId(quoteModel);
      if (quoteId == null) {
        throw new IllegalArgumentException('OOB amendment produced no quote Id');
      }

      RestContext.response.statusCode = 200;
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'id'     => String.valueOf(quoteId),
        'status' => 'success'
      }));

    } catch (Exception e) {
      Nebula.Logger.error('createOobAmendment failed: ' + e.getMessage(), e)
        .addTag('QTCTestRunner_OobAmendmentRestResource');
      Nebula.Logger.saveLog();

      RestContext.response.statusCode = 500;
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'status'  => 'error',
        'message' => 'Failed to create OOB amendment. Please try again or contact support.'
      }));
    }
  }
}