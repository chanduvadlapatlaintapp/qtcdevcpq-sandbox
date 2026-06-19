/**
 * @description Apex controller for the AI Quote Assistant Lightning Web Component.
 *              Handles integration with OpenAI API for natural language processing of CPQ quote commands.
 *              Processes user queries, builds system prompts with available products, makes API callouts,
 *              and manages product addition to quotes.
 * @author Auto-generated
 */
public with sharing class AIQuoteAssistantController {
    
    /**
     * @description Retrieves OpenAI API key from Custom Metadata Type (AI_Settings__mdt).
     *              SECURITY NOTE: In production, use Named Credentials instead of storing
     *              API keys in Custom Metadata.
     * @throws AuraHandledException If API key is not configured or metadata record not found
     */
    private static String OPENAI_API_KEY {
        get {
            try {
                // Retrieve API key from Custom Metadata Type or Named Credential
                List<AI_Settings__mdt> settingsList = [SELECT API_Key__c FROM AI_Settings__mdt WHERE DeveloperName = 'OpenAI' LIMIT 1];
                if (settingsList.isEmpty() || String.isBlank(settingsList[0].API_Key__c)) {
                    throw new AuraHandledException('OpenAI API key not configured. Please set up AI_Settings__mdt custom metadata.');
                }
                return settingsList[0].API_Key__c;
            } catch (QueryException e) {
                throw new AuraHandledException('OpenAI API key configuration not found. Please create AI_Settings__mdt custom metadata record.');
            }
        }
    }
    
    /**
     * @description OpenAI API endpoint for chat completions
     */
    private static final String OPENAI_ENDPOINT = 'https://api.openai.com/v1/chat/completions';
    
    /**
     * @description Processes a natural language query from the user and returns an AI-generated response.
     *              This method validates the input, builds a system prompt with available products,
     *              calls the OpenAI API, and returns the parsed response.
     * @param userMessage The natural language message from the user
     * @param quoteId The ID of the quote (used for context in system prompt)
     * @param cartDataJson JSON string containing current cart state (optional)
     * @return String AI-generated response in JSON format with action, parameters, and message
     * @throws AuraHandledException If userMessage is empty, API key is not configured, 
     *                              API call fails, or response parsing fails
     */
    @AuraEnabled
    public static String processNaturalLanguageQuery(String userMessage, String quoteId, String cartDataJson) {
        try {
            // Validate input
            if (String.isBlank(userMessage)) {
                throw new AuraHandledException('User message cannot be empty');
            }
            
            // Build the system prompt for the AI
            String systemPrompt = buildSystemPrompt(quoteId);
            
            // Call OpenAI API
            String aiResponse = callOpenAI(systemPrompt, userMessage);
            
            // Parse and return the response
            return aiResponse;
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledException as-is
            throw e;
        } catch (Exception e) {
            // Log the full exception for debugging
            System.debug('Error in processNaturalLanguageQuery: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error processing request: ' + e.getMessage() + '. Please check the API configuration.');
        }
    }
    
    /**
     * @description Builds a comprehensive system prompt for the AI assistant including available actions,
     *              product list, response format, and parameter examples. The prompt instructs the AI
     *              on how to interpret user commands and format responses.
     * @param quoteId The ID of the quote (currently not used but reserved for future context)
     * @return String Complete system prompt for OpenAI API
     */
    private static String buildSystemPrompt(String quoteId) {
        // Get available products for context
        List<Product2> products = getAvailableProducts();
        
        String productList = '';
        for (Product2 prod : products) {
            productList += '- ' + prod.Name + ' (ID: ' + prod.Id + ', Code: ' + (prod.ProductCode != null ? prod.ProductCode : 'N/A') + ')\n';
        }
        
        String systemPrompt = 'You are an AI Quote Assistant for a CPQ (Configure, Price, Quote) system. ' +
            'Your role is to help users build quotes using natural language commands.\n\n' +
            'AVAILABLE ACTIONS:\n' +
            '1. ADD_PRODUCT: Add products to the cart\n' +
            '2. REMOVE_PRODUCT: Remove products from the cart\n' +
            '3. UPDATE_QUANTITY: Update quantity of a product\n' +
            '4. APPLY_DISCOUNT: Apply a discount to specific products or all items\n' +
            '5. CLEAR_CART: Clear all items from the cart\n' +
            '6. GET_SUMMARY: Show cart summary\n\n' +
            'AVAILABLE PRODUCTS:\n' + productList + '\n\n' +
            'RESPONSE FORMAT:\n' +
            'Always respond in JSON format with the following structure:\n' +
            '{\n' +
            '  "action": "ACTION_NAME",\n' +
            '  "parameters": { ... action-specific parameters ... },\n' +
            '  "message": "Human-readable response to display to the user"\n' +
            '}\n\n' +
            'PARAMETER EXAMPLES:\n' +
            '- ADD_PRODUCT: {"productName": "Product Name", "productId": "ID", "quantity": 5}\n' +
            '- APPLY_DISCOUNT: {"discountPercent": 20, "applyTo": "all" or "productId"}\n' +
            '- UPDATE_QUANTITY: {"productId": "ID", "quantity": 10}\n' +
            '- REMOVE_PRODUCT: {"productId": "ID"}\n' +
            '- CLEAR_CART: {}\n' +
            '- GET_SUMMARY: {}\n\n' +
            'If the user request is unclear or cannot be fulfilled, set action to "CLARIFY" and ask for more information.\n' +
            'Always be helpful and suggest alternatives if exact matches are not found.';
        
        return systemPrompt;
    }
    
    /**
     * @description Retrieves all active products from the system for inclusion in the AI system prompt.
     *              This provides context to the AI about what products are available for quoting.
     * @return List<Product2> List of active products ordered by name
     */
    private static List<Product2> getAvailableProducts() {
        return [
            SELECT Id, Name, ProductCode, Description
            FROM Product2
            WHERE IsActive = true
            ORDER BY Name
        ];
    }
    
    /**
     * @description Makes an HTTP callout to the OpenAI API with the system prompt and user message.
     *              Handles request construction, response parsing, and error handling for various
     *              HTTP status codes and API error formats.
     * @param systemPrompt The system prompt that defines the AI's role and capabilities
     * @param userMessage The user's natural language query
     * @return String The AI-generated response content from the API
     * @throws AuraHandledException If API key is missing, HTTP callout fails, response parsing fails,
     *                              or API returns an error status code
     */
    private static String callOpenAI(String systemPrompt, String userMessage) {
        // Validate API key
        if (String.isBlank(OPENAI_API_KEY)) {
            throw new AuraHandledException('OpenAI API key is not configured. Please set up the AI_Settings__mdt custom metadata.');
        }
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(OPENAI_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + OPENAI_API_KEY);
        req.setTimeout(120000); // 2 minute timeout
        
        // Build request body
        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('model', 'gpt-4o-mini');
        requestBody.put('temperature', 0.7);
        requestBody.put('max_tokens', 1000);
        
        List<Map<String, String>> messages = new List<Map<String, String>>();
        
        // System message
        Map<String, String> systemMessage = new Map<String, String>();
        systemMessage.put('role', 'system');
        systemMessage.put('content', systemPrompt);
        messages.add(systemMessage);
        
        // User message
        Map<String, String> userMsg = new Map<String, String>();
        userMsg.put('role', 'user');
        userMsg.put('content', userMessage);
        messages.add(userMsg);
        
        requestBody.put('messages', messages);
        
        try {
            req.setBody(JSON.serialize(requestBody));
        } catch (Exception e) {
            throw new AuraHandledException('Error serializing request body: ' + e.getMessage());
        }
        
        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
        } catch (CalloutException e) {
            throw new AuraHandledException('Failed to connect to OpenAI API: ' + e.getMessage() + '. Please check your network connection and API endpoint.');
        } catch (Exception e) {
            throw new AuraHandledException('Error making HTTP request: ' + e.getMessage());
        }
        
        if (res.getStatusCode() == 200) {
            try {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> choices = (List<Object>) responseMap.get('choices');
                if (choices != null && !choices.isEmpty()) {
                    Map<String, Object> choice = (Map<String, Object>) choices[0];
                    Map<String, Object> message = (Map<String, Object>) choice.get('message');
                    String content = (String) message.get('content');
                    if (String.isNotBlank(content)) {
                        return content;
                    } else {
                        throw new AuraHandledException('OpenAI API returned empty response content.');
                    }
                } else {
                    throw new AuraHandledException('OpenAI API response did not contain choices.');
                }
            } catch (JSONException e) {
                throw new AuraHandledException('Error parsing OpenAI API response: ' + e.getMessage() + '. Response body: ' + res.getBody().substring(0, Math.min(500, res.getBody().length())));
            } catch (Exception e) {
                throw new AuraHandledException('Error processing OpenAI API response: ' + e.getMessage());
            }
        } else {
            // Handle non-200 status codes
            String errorBody = res.getBody();
            try {
                // Try to parse error response from OpenAI
                Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(errorBody);
                Map<String, Object> error = (Map<String, Object>) errorMap.get('error');
                if (error != null) {
                    String errorMessage = (String) error.get('message');
                    String errorType = (String) error.get('type');
                    throw new AuraHandledException('OpenAI API error (' + res.getStatusCode() + '): ' + errorType + ' - ' + errorMessage);
                }
            } catch (AuraHandledException e) {
                // Re-throw AuraHandledException to preserve specific API error information
                throw e;
            } catch (Exception e) {
                // If we can't parse the error, return the raw response
                // This catch only handles JSON parsing errors, not AuraHandledException
            }
            throw new AuraHandledException('OpenAI API error (' + res.getStatusCode() + '): ' + errorBody.substring(0, Math.min(500, errorBody.length())));
        }
    }
    
    /**
     * @description Retrieves all active products with their details for display in the AI assistant.
     *              Products are filtered to match the same criteria as GuidedSellingController
     *              (active products with Product_LineNew__r.Practice__c).
     * @return List<ProductWrapper> List of product wrappers with id, name, code, description, and category
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getProducts() {
        List<ProductWrapper> products = new List<ProductWrapper>();
        
        // Use same filter as GuidedSellingController to ensure products match
        for (Product2 prod : [
            SELECT Id, Name, ProductCode, Description, Product_LineNew__r.Practice__c
            FROM Product2
            WHERE IsActive = true AND Product_LineNew__r.Practice__c != null
            ORDER BY Name
        ]) {
            ProductWrapper pw = new ProductWrapper();
            pw.id = prod.Id;
            pw.name = prod.Name;
            pw.productCode = prod.ProductCode;
            pw.description = prod.Description;
            pw.category = prod.Product_LineNew__r != null ? prod.Product_LineNew__r.Practice__c : 'General';
            products.add(pw);
        }
        
        return products;
    }
    
    /**
     * @description Adds products from the AI assistant cart to an actual Salesforce Quote by creating
     *              quote lines. This method parses the products JSON, creates SBQQ__QuoteLine__c records,
     *              and inserts them.
     * @param quoteId The ID of the quote to add products to
     * @param productsJson JSON string containing cart items with productId, quantity, and optional discount
     * @return String Success message indicating how many products were added
     * @throws AuraHandledException If JSON parsing fails, quote lines cannot be created, or insert fails
     */
    @AuraEnabled
    public static String addProductsToQuote(String quoteId, String productsJson) {
        try {
            List<CartItemWrapper> items = (List<CartItemWrapper>) JSON.deserialize(productsJson, List<CartItemWrapper>.class);
            
            List<SBQQ__QuoteLine__c> quoteLines = new List<SBQQ__QuoteLine__c>();
            
            for (CartItemWrapper item : items) {
                SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c();
                ql.SBQQ__Quote__c = quoteId;
                ql.SBQQ__Product__c = item.productId;
                ql.SBQQ__Quantity__c = item.quantity;
                if (item.discount != null) {
                    ql.SBQQ__Discount__c = item.discount;
                }
                quoteLines.add(ql);
            }
            
            if (!quoteLines.isEmpty()) {
                insert quoteLines;
            }
            
            return 'Successfully added ' + quoteLines.size() + ' product(s) to the quote.';
        } catch (Exception e) {
            throw new AuraHandledException('Error adding products: ' + e.getMessage());
        }
    }
    
    /**
     * @description Wrapper class for product information returned to LWC components
     */
    public class ProductWrapper {
        /** Product record ID */
        @AuraEnabled public String id { get; set; }
        /** Product name */
        @AuraEnabled public String name { get; set; }
        /** Product code */
        @AuraEnabled public String productCode { get; set; }
        /** Product description */
        @AuraEnabled public String description { get; set; }
        /** Product category (from Product_LineNew__r.Practice__c) */
        @AuraEnabled public String category { get; set; }
    }
    
    /**
     * @description Wrapper class for cart item data when adding products to quote
     */
    public class CartItemWrapper {
        /** Product record ID */
        @AuraEnabled public String productId { get; set; }
        /** Product name */
        @AuraEnabled public String productName { get; set; }
        /** Quantity to add */
        @AuraEnabled public Decimal quantity { get; set; }
        /** Discount percentage (optional) */
        @AuraEnabled public Decimal discount { get; set; }
        /** Unit price (optional) */
        @AuraEnabled public Decimal unitPrice { get; set; }
    }
}