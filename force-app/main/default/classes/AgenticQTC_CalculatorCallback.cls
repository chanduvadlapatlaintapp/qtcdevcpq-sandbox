/**
 * @description CPQ Calculator callback implementation. Called by SBQQ.ServiceRouter
 *              after asynchronous quote calculation completes. Saves the calculated
 *              quote back via the QuoteSaver API.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
global class AgenticQTC_CalculatorCallback implements SBQQ.CalculateCallback {

    /**
     * @description Called by CPQ after quote calculation finishes.
     * @param quoteJSON The calculated quote model as JSON
     */
    global void callback(String quoteJSON) {
        if (String.isNotBlank(quoteJSON)) {
            SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', quoteJSON);
        }
    }
}