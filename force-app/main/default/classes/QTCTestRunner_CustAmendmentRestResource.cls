/**
 * @description REST endpoint for the AgenticQTC custom amendment flow — the
 *              symmetric counterpart to QTCTestRunner_OobAmendmentRestResource.
 *
 *              Delegates to AgenticQTC_QuoteAmendmentService.createAmendmentQuote,
 *              which is the always-fresh entry point that the LWC quote editor
 *              uses (no draft-reuse short-circuit, so every test run produces a
 *              fresh amendment for fair comparison).
 *
 * Usage:
 *   POST /services/apexrest/agenticQtc/amendment/custom
 *   { "contractId": "..." }
 *
 * Response (200):
 *   { "id": "<quoteId>", "status": "success" }
 *
 * @author AgenticQTC Team
 * @date 2026-05-29
 */
@RestResource(urlMapping='/agenticQtc/amendment/custom/*')
global class QTCTestRunner_CustAmendmentRestResource {

  @HttpPost
  global static void createCustomAmendment() {
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

      AgenticQTC_QuoteAmendmentService.AmendmentQuoteInfo info =
          AgenticQTC_QuoteAmendmentService.createAmendmentQuote(contractId);

      if (info == null || String.isBlank(info.id)) {
        throw new IllegalArgumentException('Custom amendment produced no quote Id');
      }

      RestContext.response.statusCode = 200;
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'id'     => info.id,
        'status' => 'success'
      }));

    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'createCustomAmendment failed: ' + e.getMessage() + '\n' + e.getStackTraceString());

      RestContext.response.statusCode = 500;
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'status'  => 'error',
        'message' => e.getMessage()
      }));
    }
  }
}