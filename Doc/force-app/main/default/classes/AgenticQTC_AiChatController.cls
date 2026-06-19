/**
 * @description Controller for the AI chat sidebar. Manages Claude API conversations
 *              using a client-side continuation pattern to avoid the Salesforce
 *              "callout after DML" restriction. Each Apex call performs exactly one
 *              HTTP callout to Claude followed by one batch of tool executions.
 *              If Claude wants to continue (tool_use stop reason), the response
 *              includes continuationNeeded=true and the serialized conversation state
 *              so the LWC can call continueConversation() for the next round.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_AiChatController {

    private static final String CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages';
    private static final String ANTHROPIC_VERSION = '2023-06-01';
    private static final Integer MAX_TOKENS = 4096;

    private static final String TOOL_SEARCH_ACCOUNTS = 'search_accounts';
    private static final String TOOL_SEARCH_CONTRACTS_BY_NUMBER = 'search_contracts_by_number';
    private static final String TOOL_GET_CONTRACTS = 'get_contracts';
    private static final String TOOL_GET_CONTRACT_DETAIL = 'get_contract_detail';
    private static final String TOOL_GET_QUOTE_LINES = 'get_quote_lines';
    private static final String TOOL_UPDATE_QUANTITY = 'update_quantity';
    private static final String TOOL_SEARCH_PRODUCTS = 'search_products';
    private static final String TOOL_CHECK_APPROVAL = 'check_approval';
    private static final String TOOL_CREATE_AMENDMENT = 'create_amendment';
    private static final String TOOL_ADD_PRODUCT = 'add_product';
    private static final String TOOL_UPDATE_DISCOUNT = 'update_discount';
    private static final String TOOL_CALCULATE_PRICES = 'calculate_prices';
    private static final String TOOL_GENERATE_OSA = 'generate_osa_document';

    private static final String UI_SELECT_ACCOUNT = 'selectAccount';
    private static final String UI_SELECT_CONTRACT = 'selectContract';
    private static final String UI_REFRESH_LINES = 'refreshLines';

    private static final Set<String> LINE_MODIFYING_TOOLS = new Set<String>{
        TOOL_UPDATE_QUANTITY, TOOL_ADD_PRODUCT, TOOL_UPDATE_DISCOUNT,
        TOOL_CALCULATE_PRICES, TOOL_CREATE_AMENDMENT
    };

    /**
     * @description Entry point for a new user message. Makes one Claude callout,
     *              executes any requested tools, then returns. If Claude needs more
     *              rounds, continuationNeeded=true tells the LWC to call continueConversation.
     * @param userMessage The text from the user
     * @param contextJson JSON string with current UI context
     * @return ChatResponse with message, tool calls, UI actions, and optional continuation state
     */
    @AuraEnabled
    public static ChatResponse sendMessage(String userMessage, String contextJson) {
        if (String.isBlank(userMessage)) {
            throw new AuraHandledException('Message is required');
        }

        Map<String, Object> context = parseContext(contextJson);
        String systemPrompt = buildSystemPrompt(context);

        List<Object> messages = new List<Object>();
        messages.add(new Map<String, Object>{ 'role' => 'user', 'content' => userMessage });

        return executeOneRound(messages, systemPrompt, new List<ToolCallLog>());
    }

    /**
     * @description Continues a multi-round conversation. Called by the LWC when the
     *              previous response had continuationNeeded=true. Deserializes the
     *              conversation state, makes one callout, executes tools, and returns.
     * @param messagesJson Serialized conversation messages from the previous round
     * @param contextJson JSON string with current UI context
     * @param priorToolCallsJson Serialized tool calls accumulated from prior rounds
     * @return ChatResponse with the next round's results
     */
    @AuraEnabled
    public static ChatResponse continueConversation(String messagesJson, String contextJson, String priorToolCallsJson) {
        if (String.isBlank(messagesJson)) {
            throw new AuraHandledException('Conversation state is required');
        }

        Map<String, Object> context = parseContext(contextJson);
        String systemPrompt = buildSystemPrompt(context);

        List<Object> messages = (List<Object>) JSON.deserializeUntyped(messagesJson);

        List<ToolCallLog> priorToolCalls = new List<ToolCallLog>();
        if (String.isNotBlank(priorToolCallsJson)) {
            List<Object> rawList = (List<Object>) JSON.deserializeUntyped(priorToolCallsJson);
            for (Object item : rawList) {
                Map<String, Object> m = (Map<String, Object>) item;
                ToolCallLog tc = new ToolCallLog();
                tc.name = (String) m.get('name');
                tc.args = (String) m.get('args');
                tc.result = (String) m.get('result');
                tc.success = (Boolean) m.get('success');
                priorToolCalls.add(tc);
            }
        }

        return executeOneRound(messages, systemPrompt, priorToolCalls);
    }

    /**
     * @description Core single-round logic: one callout → parse response → execute tools.
     *              If Claude returns tool_use, tools are executed and the response is marked
     *              for continuation. If Claude returns end_turn, the final message is returned.
     * @param messages The conversation messages array
     * @param systemPrompt The system prompt with context
     * @param accumulatedToolCalls Tool calls from prior rounds to include in the response
     * @return ChatResponse for this round
     */
    private static ChatResponse executeOneRound(List<Object> messages, String systemPrompt, List<ToolCallLog> accumulatedToolCalls) {
        String apiKey;
        try {
          //  apiKey = System.Label.AgenticQTC_ClaudeApiKey;
        } catch (Exception e) {
            throw new AuraHandledException('AI configuration not found. Please set up the AgenticQTC_ClaudeApiKey custom label.');
        }

        String model = AgenticQTC_ConfigService.claudeModel();
        Integer timeout = AgenticQTC_ConfigService.calloutTimeout();
        List<Object> tools = buildToolDefinitions();

        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => model,
            'max_tokens' => MAX_TOKENS,
            'system' => systemPrompt,
            'messages' => messages,
            'tools' => tools
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(CLAUDE_API_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', apiKey);
        req.setHeader('anthropic-version', ANTHROPIC_VERSION);
        req.setBody(JSON.serialize(requestBody));
        req.setTimeout(timeout);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('AI service error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }

        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String stopReason = (String) responseBody.get('stop_reason');
        List<Object> contentBlocks = (List<Object>) responseBody.get('content');

        String textContent = '';
        List<Map<String, Object>> toolUseBlocks = new List<Map<String, Object>>();

        for (Object block : contentBlocks) {
            Map<String, Object> b = (Map<String, Object>) block;
            String blockType = (String) b.get('type');
            if (blockType == 'text') {
                textContent += (String) b.get('text');
            } else if (blockType == 'tool_use') {
                toolUseBlocks.add(b);
            }
        }

        // If Claude is done (no tools to call), return final response
        if (stopReason == 'end_turn' || toolUseBlocks.isEmpty()) {
            ChatResponse response = new ChatResponse();
            response.message = textContent;
            response.toolCalls = accumulatedToolCalls;
            response.uiActions = buildUiActions(accumulatedToolCalls);
            response.continuationNeeded = false;
            return response;
        }

        // Claude wants tools executed — do them, then ask the LWC to continue
        messages.add(new Map<String, Object>{ 'role' => 'assistant', 'content' => contentBlocks });

        List<Object> toolResults = new List<Object>();
        for (Map<String, Object> toolUse : toolUseBlocks) {
            String toolName = (String) toolUse.get('name');
            String toolId = (String) toolUse.get('id');
            Map<String, Object> toolInput = (Map<String, Object>) toolUse.get('input');

            ToolCallLog tcLog = new ToolCallLog();
            tcLog.name = toolName;
            tcLog.args = JSON.serialize(toolInput);

            String toolResult;
            try {
                toolResult = AgenticQTC_AiToolExecutor.executeTool(toolName, toolInput);
                tcLog.success = true;
            } catch (Exception e) {
                // BUG FIX #9: Use JSON.serialize to safely escape all special characters
                // (including double-quotes) in exception messages instead of escapeSingleQuotes.
                toolResult = JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() });
                tcLog.success = false;
            }
            tcLog.result = toolResult;
            accumulatedToolCalls.add(tcLog);

            toolResults.add(new Map<String, Object>{
                'type' => 'tool_result',
                'tool_use_id' => toolId,
                'content' => toolResult
            });
        }

        messages.add(new Map<String, Object>{ 'role' => 'user', 'content' => toolResults });

        // Return with continuation flag — LWC will call continueConversation()
        ChatResponse response = new ChatResponse();
        response.message = '';
        response.toolCalls = accumulatedToolCalls;
        response.uiActions = buildUiActions(accumulatedToolCalls);
        response.continuationNeeded = true;
        response.pendingMessagesJson = JSON.serialize(messages);
        response.pendingToolCallsJson = JSON.serialize(accumulatedToolCalls);
        return response;
    }

    private static Map<String, Object> parseContext(String contextJson) {
        Map<String, Object> context = new Map<String, Object>();
        if (String.isNotBlank(contextJson)) {
            try {
                context = (Map<String, Object>) JSON.deserializeUntyped(contextJson);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Invalid contextJson: ' + e.getMessage());
            }
        }
        return context;
    }

    // ─── UI Action Builder ───────────────────────────────────────────────

    @TestVisible
    private static List<UiAction> buildUiActions(List<ToolCallLog> toolCalls) {
        List<UiAction> actions = new List<UiAction>();
        if (toolCalls == null || toolCalls.isEmpty()) {
            return actions;
        }

        Boolean needsRefresh = false;

        for (ToolCallLog tc : toolCalls) {
            if (!tc.success) continue;

            if (tc.name == TOOL_SEARCH_ACCOUNTS && String.isNotBlank(tc.result)) {
                try {
                    List<Object> accounts = (List<Object>) JSON.deserializeUntyped(tc.result);
                    if (!accounts.isEmpty()) {
                        Map<String, Object> first = (Map<String, Object>) accounts[0];
                        UiAction ua = new UiAction();
                        ua.action = UI_SELECT_ACCOUNT;
                        ua.accountId = String.valueOf(first.get('id'));
                        ua.accountName = String.valueOf(first.get('name'));
                        actions.add(ua);
                    }
                } catch (Exception e) { /* non-list result */ }
            }

            if ((tc.name == TOOL_CREATE_AMENDMENT || tc.name == TOOL_SEARCH_CONTRACTS_BY_NUMBER)
                    && String.isNotBlank(tc.result)) {
                try {
                    Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(tc.result);
                    // BUG FIX #1: Use null-safe extraction before String.valueOf() to avoid
                    // the literal string "null" being treated as a valid, non-blank contract ID.
                    Object cIdObj = resultMap.containsKey('contractId')
                        ? resultMap.get('contractId')
                        : resultMap.get('id');
                    String cId = cIdObj != null ? String.valueOf(cIdObj) : null;
                    Object cNumObj = resultMap.containsKey('contractNumber')
                        ? resultMap.get('contractNumber')
                        : null;
                    String cNum = cNumObj != null ? String.valueOf(cNumObj) : '';
                    if (String.isNotBlank(cId) && cId != 'null') {
                        UiAction ua = new UiAction();
                        ua.action = UI_SELECT_CONTRACT;
                        ua.contractId = cId;
                        ua.contractNumber = cNum;
                        actions.add(ua);
                    }
                } catch (Exception e) {
                    try {
                        List<Object> contracts = (List<Object>) JSON.deserializeUntyped(tc.result);
                        if (!contracts.isEmpty()) {
                            Map<String, Object> first = (Map<String, Object>) contracts[0];
                            // BUG FIX #1 (continued): null-safe extraction for list path too.
                            Object listCIdObj = first.get('id');
                            Object listCNumObj = first.get('contractNumber');
                            Object listAccObj = first.get('accountName');
                            String listCId = listCIdObj != null ? String.valueOf(listCIdObj) : null;
                            if (String.isNotBlank(listCId) && listCId != 'null') {
                                UiAction ua = new UiAction();
                                ua.action = UI_SELECT_CONTRACT;
                                ua.contractId = listCId;
                                ua.contractNumber = listCNumObj != null ? String.valueOf(listCNumObj) : '';
                                ua.accountName = listAccObj != null ? String.valueOf(listAccObj) : '';
                                actions.add(ua);
                            }
                        }
                    } catch (Exception e2) { /* skip */ }
                }
            }

            if (LINE_MODIFYING_TOOLS.contains(tc.name)) {
                needsRefresh = true;
            }
        }

        if (needsRefresh) {
            UiAction ua = new UiAction();
            ua.action = UI_REFRESH_LINES;
            actions.add(ua);
        }

        return actions;
    }

    // ─── System Prompt ───────────────────────────────────────────────────

    private static String buildSystemPrompt(Map<String, Object> context) {
        String prompt = 'You are the Agentic QTC AI Assistant for the Deal Desk team. '
            + 'You help sales reps with Quote-to-Contract amendments in Salesforce CPQ.\n\n'
            + '## Your Capabilities\n'
            + 'You can search accounts, look up contracts by account or contract number, '
            + 'view subscriptions, create amendment quotes, add products, modify quantities, '
            + 'apply discounts (percentage or flat dollar amount), calculate pricing, '
            + 'check approval status, and generate OSA documents.\n\n'
            + '## Workflow Guide\n'
            + 'When a user asks you to perform an amendment, follow this sequence:\n'
            + '1. **Find the account** — use search_accounts with the account name, or search_contracts_by_number if they gave a contract number\n'
            + '2. **Find the contract** — use get_contracts with the account ID, then pick the contract matching the user\'s description\n'
            + '3. **Create the amendment** — use create_amendment with the contract ID to get a draft quote\n'
            + '4. **Add/modify products** — use search_products to find products, add_product to add them, update_quantity or update_discount to adjust lines\n'
            + '5. **Calculate prices** — use calculate_prices to ensure all net prices are correct\n'
            + '6. **Check approval** — use check_approval to see if any lines need Contract Ops review\n\n'
            + '## Important Rules\n'
            + '- Execute tools immediately when the user asks for action. Do not just describe what you would do.\n'
            + '- When you get a list of search results, pick the best match yourself. Do not ask the user to choose unless truly ambiguous.\n'
            + '- Always use Salesforce record IDs (18-char) from tool results when calling subsequent tools.\n'
            + '- Format monetary values with $ and commas (e.g. $1,500.00).\n'
            + '- After completing actions, summarize what you did concisely.\n'
            + '- If you already have context IDs (accountId, contractId, quoteId) from the current session, use them directly instead of searching again.\n\n';

        String ctxAccountId = safeContextVal(context, 'accountId');
        String ctxAccountName = safeContextVal(context, 'accountName');
        String ctxContractId = safeContextVal(context, 'contractId');
        String ctxQuoteId = safeContextVal(context, 'quoteId');
        String ctxPage = safeContextVal(context, 'currentPage');

        if (String.isNotBlank(ctxAccountId) || String.isNotBlank(ctxContractId) || String.isNotBlank(ctxQuoteId)) {
            prompt += '## Current Session Context\n';
            if (String.isNotBlank(ctxAccountId)) prompt += '- Account ID: ' + ctxAccountId + '\n';
            if (String.isNotBlank(ctxAccountName)) prompt += '- Account Name: ' + ctxAccountName + '\n';
            if (String.isNotBlank(ctxContractId)) prompt += '- Contract ID: ' + ctxContractId + '\n';
            if (String.isNotBlank(ctxQuoteId)) prompt += '- Quote ID: ' + ctxQuoteId + ' (use this for quote line operations)\n';
            if (String.isNotBlank(ctxPage)) prompt += '- User is on: ' + ctxPage + ' page\n';
            prompt += '\n';
        }

        return prompt;
    }

    private static String safeContextVal(Map<String, Object> ctx, String key) {
        if (ctx == null || !ctx.containsKey(key)) return null;
        Object val = ctx.get(key);
        return val != null ? String.valueOf(val) : null;
    }

    // ─── Tool Definitions ────────────────────────────────────────────────

    private static List<Object> buildToolDefinitions() {
        List<Object> tools = new List<Object>();

        tools.add(buildTool(TOOL_SEARCH_ACCOUNTS,
            'Search for Salesforce accounts by name. Returns a list of matching accounts with IDs, names, and billing locations. Use the returned account ID to call get_contracts.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'search_term' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Account name to search for (partial match supported, minimum 2 characters)' }
                },
                'required' => new List<String>{ 'search_term' }
            }));

        tools.add(buildTool(TOOL_SEARCH_CONTRACTS_BY_NUMBER,
            'Search for activated contracts by contract number (partial match). Returns contracts with their account names. Use this when the user provides a contract number but no account name.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'contract_number' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Full or partial contract number to search for' }
                },
                'required' => new List<String>{ 'contract_number' }
            }));

        tools.add(buildTool(TOOL_GET_CONTRACTS,
            'Get all active (activated) contracts for a specific account. Returns contract IDs, numbers, dates, and status. Use search_accounts first to get the account ID.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'account_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Salesforce Account ID (18-character)' }
                },
                'required' => new List<String>{ 'account_id' }
            }));

        tools.add(buildTool(TOOL_GET_CONTRACT_DETAIL,
            'Get detailed contract info including all CPQ subscription lines (products, quantities, prices). Useful for understanding what the customer currently has before making amendments.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'contract_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Salesforce Contract ID (18-character)' }
                },
                'required' => new List<String>{ 'contract_id' }
            }));

        tools.add(buildTool(TOOL_CREATE_AMENDMENT,
            'Create a draft amendment quote for a contract (or return existing draft if one exists). This is required before adding products or modifying lines. Returns the quote ID, name, and status.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'contract_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Salesforce Contract ID to amend' }
                },
                'required' => new List<String>{ 'contract_id' }
            }));

        tools.add(buildTool(TOOL_GET_QUOTE_LINES,
            'Get all quote lines on an amendment quote. Returns line IDs, product names, quantities, prior quantities, prices, discounts, and approval status. Call this after create_amendment to see existing lines.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' }
                },
                'required' => new List<String>{ 'quote_id' }
            }));

        tools.add(buildTool(TOOL_SEARCH_PRODUCTS,
            'Search the product catalog for active products by name or product code. Returns product IDs, names, codes, and families. Use the returned product ID with add_product.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'search_term' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Product name or code to search for (partial match)' }
                },
                'required' => new List<String>{ 'search_term' }
            }));

        tools.add(buildTool(TOOL_ADD_PRODUCT,
            'Add a product to an amendment quote as a new quote line. Requires the quote ID (from create_amendment) and product ID (from search_products). Returns the updated list of all quote lines.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' },
                    'product_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Product2 record ID from search_products' },
                    'quantity' => new Map<String, Object>{ 'type' => 'number', 'description' => 'Number of seats/units to add (default 1)' }
                },
                'required' => new List<String>{ 'quote_id', 'product_id' }
            }));

        tools.add(buildTool(TOOL_UPDATE_QUANTITY,
            'Update the quantity on an existing quote line. Returns the updated list of all quote lines. Get the quote_line_id from get_quote_lines or add_product results.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' },
                    'quote_line_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__QuoteLine__c record ID' },
                    'new_quantity' => new Map<String, Object>{ 'type' => 'number', 'description' => 'New quantity value' }
                },
                'required' => new List<String>{ 'quote_id', 'quote_line_id', 'new_quantity' }
            }));

        tools.add(buildTool(TOOL_UPDATE_DISCOUNT,
            'Apply a discount to a quote line. Supports percentage discount (e.g. 50 for 50% off) OR flat per-unit dollar amount (e.g. 20 for $20 off per seat). Provide exactly one of discount_percent or discount_amount. Returns updated quote lines.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' },
                    'quote_line_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__QuoteLine__c record ID' },
                    'discount_percent' => new Map<String, Object>{ 'type' => 'number', 'description' => 'Percentage discount 0-100 (e.g. 50 for 50% off). Omit if using discount_amount.' },
                    'discount_amount' => new Map<String, Object>{ 'type' => 'number', 'description' => 'Flat per-unit dollar discount (e.g. 20 for $20 off each). Omit if using discount_percent.' }
                },
                'required' => new List<String>{ 'quote_id', 'quote_line_id' }
            }));

        tools.add(buildTool(TOOL_CALCULATE_PRICES,
            'Recalculate all quote line prices on a quote (quantity * list price). Call this after making multiple changes to ensure all net prices are correct.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' }
                },
                'required' => new List<String>{ 'quote_id' }
            }));

        tools.add(buildTool(TOOL_CHECK_APPROVAL,
            'Check if any quote lines require approval (e.g. quantity decrease or new product added). Returns a summary with total lines, lines needing approval, and specific reasons.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' }
                },
                'required' => new List<String>{ 'quote_id' }
            }));

        tools.add(buildTool(TOOL_GENERATE_OSA,
            'Generate an OSA (Order Schedule Amendment) PDF document for a quote. The document is stored as a Salesforce file linked to the quote. Returns the document ID and download URL.',
            new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'quote_id' => new Map<String, Object>{ 'type' => 'string', 'description' => 'SBQQ__Quote__c record ID' }
                },
                'required' => new List<String>{ 'quote_id' }
            }));

        return tools;
    }

    private static Map<String, Object> buildTool(String name, String description, Map<String, Object> inputSchema) {
        return new Map<String, Object>{
            'name' => name,
            'description' => description,
            'input_schema' => inputSchema
        };
    }

    // ─── DTOs ────────────────────────────────────────────────────────────

    public class ChatResponse {
        @AuraEnabled public String message;
        @AuraEnabled public List<ToolCallLog> toolCalls;
        @AuraEnabled public List<UiAction> uiActions;
        @AuraEnabled public Boolean continuationNeeded;
        @AuraEnabled public String pendingMessagesJson;
        @AuraEnabled public String pendingToolCallsJson;
    }

    public class ToolCallLog {
        @AuraEnabled public String name;
        @AuraEnabled public String args;
        @AuraEnabled public String result;
        @AuraEnabled public Boolean success;
    }

    public class UiAction {
        @AuraEnabled public String action;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String contractId;
        @AuraEnabled public String contractNumber;
    }
}