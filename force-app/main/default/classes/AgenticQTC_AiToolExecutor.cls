/**
 * @description Executes AI tool calls dispatched by the chat controller.
 *              Routes each tool name to the appropriate service method with
 *              null-safe argument extraction and proper JSON error responses.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_AiToolExecutor {

    /**
     * @description Dispatches a tool call to the correct service.
     * @param toolName The tool identifier from Claude's response
     * @param args The input arguments map
     * @return JSON-serialized result string
     */
    public static String executeTool(String toolName, Map<String, Object> args) {
        if (args == null) {
            args = new Map<String, Object>();
        }

        switch on toolName {
            when 'search_accounts' {
                String term = safeString(args, 'search_term');
                List<AgenticQTC_AccountSearchService.AccountResult> results =
                    AgenticQTC_AccountSearchService.searchAccounts(term);
                return JSON.serialize(results);
            }
            when 'get_contracts' {
                String accountId = safeString(args, 'account_id');
                List<AgenticQTC_ContractService.ContractResult> results =
                    AgenticQTC_ContractService.getActiveContracts(accountId);
                return JSON.serialize(results);
            }
            when 'get_contract_detail' {
                String contractId = safeString(args, 'contract_id');
                AgenticQTC_ContractService.ContractDetail result =
                    AgenticQTC_ContractService.getContractDetail(contractId);
                return JSON.serialize(result);
            }
            when 'get_quote_lines' {
                String quoteId = safeString(args, 'quote_id');
                List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> results =
                    AgenticQTC_QuoteAmendmentService.getQuoteLines(quoteId);
                return JSON.serialize(results);
            }
            when 'update_quantity' {
                String quoteId = safeString(args, 'quote_id');
                String lineId = safeString(args, 'quote_line_id');
                Decimal qty = safeDecimal(args, 'new_quantity');
                List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> results =
                    AgenticQTC_QuoteAmendmentService.updateQuoteLineQuantity(quoteId, lineId, qty);
                return JSON.serialize(results);
            }
            when 'search_products' {
                String term = safeString(args, 'search_term');
                List<AgenticQTC_ProductService.ProductInfo> results =
                    AgenticQTC_ProductService.getEligibleProducts(term);
                return JSON.serialize(results);
            }
            when 'check_approval' {
                String quoteId = safeString(args, 'quote_id');
                AgenticQTC_ApprovalLogicService.ApprovalSummary result =
                    AgenticQTC_ApprovalLogicService.evaluateQuoteApproval(quoteId);
                return JSON.serialize(result);
            }
            when 'search_contracts_by_number' {
                String contractNum = safeString(args, 'contract_number');
                List<AgenticQTC_ContractService.ContractResult> results =
                    AgenticQTC_ContractService.searchContractsByNumber(contractNum);
                return JSON.serialize(results);
            }
            when 'create_amendment' {
                String contractId = safeString(args, 'contract_id');
                AgenticQTC_QuoteAmendmentService.QuoteInfo result =
                    AgenticQTC_QuoteAmendmentService.getOrCreateAmendmentQuote(contractId);
                return JSON.serialize(result);
            }
            when 'add_product' {
                String quoteId = safeString(args, 'quote_id');
                String productId = safeString(args, 'product_id');
                Decimal qty = safeDecimal(args, 'quantity');
                AgenticQTC_ProductService.addProductToQuote(quoteId, productId, qty);
                List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> lines =
                    AgenticQTC_QuoteAmendmentService.getQuoteLines(quoteId);
                return JSON.serialize(lines);
            }
            when 'update_discount' {
                String quoteId = safeString(args, 'quote_id');
                String lineId = safeString(args, 'quote_line_id');
                Decimal pct = safeDecimal(args, 'discount_percent');
                Decimal amt = safeDecimal(args, 'discount_amount');
                List<AgenticQTC_QuoteAmendmentService.QuoteLineInfo> results =
                    AgenticQTC_QuoteAmendmentService.updateQuoteLineDiscount(quoteId, lineId, pct, amt);
                return JSON.serialize(results);
            }
            when 'calculate_prices' {
                String quoteId = safeString(args, 'quote_id');
                AgenticQTC_QuoteAmendmentService.calculateQuote(quoteId);
                return '{"success":true,"message":"Quote prices calculated successfully"}';
            }
            when 'generate_osa_document' {
                String quoteId = safeString(args, 'quote_id');
                AgenticQTC_OsaDocumentService.GeneratedDocInfo result =
                    AgenticQTC_OsaDocumentService.generateOsaDocument(quoteId);
                return JSON.serialize(result);
            }
            when else {
                // BUG FIX #9 (related): Use JSON.serialize for all error responses to safely
                // handle any special characters in the tool name.
                return JSON.serialize(new Map<String, Object>{ 'error' => 'Unknown tool: ' + toolName });
            }
        }
    }

    /**
     * @description Safely extracts a String value from the tool arguments map.
     * @param args The tool input arguments
     * @param key The argument name
     * @return String value, or null if key is missing or value is null
     */
    private static String safeString(Map<String, Object> args, String key) {
        Object val = args.get(key);
        return val != null ? String.valueOf(val) : null;
    }

    /**
     * @description Safely extracts a Decimal value from the tool arguments map.
     *              Handles Integer, Long, Double, and String inputs gracefully.
     * @param args The tool input arguments
     * @param key The argument name
     * @return Decimal value, or null if key is missing or unparseable
     */
    private static Decimal safeDecimal(Map<String, Object> args, String key) {
        Object val = args.get(key);
        if (val == null) return null;
        if (val instanceof Decimal) return (Decimal) val;
        if (val instanceof Integer) return Decimal.valueOf((Integer) val);
        if (val instanceof Long) return Decimal.valueOf((Long) val);
        if (val instanceof Double) return Decimal.valueOf((Double) val);
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}