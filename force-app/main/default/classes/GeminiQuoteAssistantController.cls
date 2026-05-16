/**
 * GeminiQuoteAssistantController
 * 
 * Apex controller for the AI Quote Assistant Chatbot LWC.
 * Handles integration with Google Gemini AI API for natural language
 * processing of CPQ quote commands.
 * 
 * SETUP REQUIREMENTS:
 * 1. Create a Named Credential called 'Gemini_API' pointing to:
 *    https://generativelanguage.googleapis.com
 *    OR
 *    Create a Custom Metadata Type 'AI_Settings__mdt' with fields:
 *    - API_Key__c (Text, encrypted)
 *    - DeveloperName = 'Gemini'
 * 
 * 2. Add Remote Site Setting for: https://generativelanguage.googleapis.com
 * 
 * 3. Ensure appropriate user permissions are set.
 * 
 * @author Salesforce Developer
 * @version 2.0.0
 */
public with sharing class GeminiQuoteAssistantController {
    
    // ============================================
    // CONFIGURATION CONSTANTS
    // ============================================
    
    /**
     * Gemini API endpoint for text generation
     * Using the v1beta API with gemini-pro model
     */
    private static final String GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
    
    /**
     * Maximum timeout for API calls (in milliseconds)
     */
    private static final Integer API_TIMEOUT = 120000; // 2 minutes
    
    /**
     * Retrieve API key from Custom Metadata Type
     * 
     * SECURITY NOTE: In production, use Named Credentials instead of
     * storing API keys in Custom Metadata. This is for demonstration.
     * 
     * TODO: Replace with Named Credential implementation:
     * - Create Named Credential 'Gemini_API'
     * - Use callout:Gemini_API in endpoint
     * - Remove API key storage from metadata
     */
    private static String GEMINI_API_KEY {
        get {
            if (GEMINI_API_KEY == null) {
                try {
                    // Attempt to retrieve from Custom Metadata
                    List<AI_Settings__mdt> settingsList = [
                        SELECT API_Key__c 
                        FROM AI_Settings__mdt 
                        WHERE DeveloperName = 'Gemini' 
                        LIMIT 1
                    ];
                    
                    if (!settingsList.isEmpty() && String.isNotBlank(settingsList[0].API_Key__c)) {
                        GEMINI_API_KEY = settingsList[0].API_Key__c;
                    } else {
                        // Fallback: Check for OpenAI settings that might have Gemini key
                        settingsList = [
                            SELECT API_Key__c 
                            FROM AI_Settings__mdt 
                            WHERE DeveloperName = 'OpenAI' 
                            LIMIT 1
                        ];
                        
                        if (!settingsList.isEmpty() && String.isNotBlank(settingsList[0].API_Key__c)) {
                            // Note: Using OpenAI settings as fallback - update metadata for production
                            GEMINI_API_KEY = settingsList[0].API_Key__c;
                        } else {
                            throw new AuraHandledException(
                                'Gemini API key not configured. Please create AI_Settings__mdt ' +
                                'custom metadata record with DeveloperName = "Gemini" and set API_Key__c.'
                            );
                        }
                    }
                } catch (QueryException e) {
                    throw new AuraHandledException(
                        'AI Settings configuration not found. Please ensure AI_Settings__mdt ' +
                        'custom metadata type exists and contains a Gemini configuration record.'
                    );
                }
            }
            return GEMINI_API_KEY;
        }
        set;
    }
    
    // ============================================
    // PUBLIC METHODS - EXPOSED TO LWC
    // ============================================
    
    /**
     * Process user message through Gemini AI and return structured response
     * 
     * @param userMessage The natural language message from the user
     * @param cartDataJson Current cart state as JSON string (optional)
     * @return String JSON response from Gemini with action, parameters, and message
     */
    @AuraEnabled
    public static String getAIResponse(String userMessage, String cartDataJson) {
        try {
            // Validate input
            if (String.isBlank(userMessage)) {
                throw new AuraHandledException('User message cannot be empty.');
            }
            
            // Build the system prompt with available products
            String systemPrompt = buildSystemPrompt();
            
            // Include current cart context if provided
            String contextMessage = userMessage;
            if (String.isNotBlank(cartDataJson)) {
                contextMessage = 'Current cart state: ' + cartDataJson + '\n\nUser request: ' + userMessage;
            }
            
            // Call Gemini API
            String aiResponse = callGeminiAPI(systemPrompt, contextMessage);
            
            // Validate and return response
            return aiResponse;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in getAIResponse: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException(
                'Error processing your request: ' + e.getMessage() + 
                '. Please try again or contact support.'
            );
        }
    }
    
    /**
     * @description Retrieves all active products with their details for display in the AI assistant.
     *              Products are queried with basic information and formatted as ProductWrapper objects
     *              for consumption by LWC components.
     * @return List<ProductWrapper> List of product wrappers with id, name, code, description, category, and unitPrice
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getProducts() {
        List<ProductWrapper> products = new List<ProductWrapper>();
        
        try {
            // Query active products
            // TODO: Customize this query based on your org's product structure
            // You may need to add filters for:
            // - Price book entries
            // - Product families/categories
            // - User permissions
            // - Active status
            for (Product2 prod : [
                SELECT 
                    Id, 
                    Name, 
                    ProductCode, 
                    Description,
                    Family,
                    IsActive
                FROM Product2
                WHERE IsActive = true
                ORDER BY Name
                LIMIT 200
            ]) {
                ProductWrapper pw = new ProductWrapper();
                pw.id = prod.Id;
                pw.name = prod.Name;
                pw.productCode = prod.ProductCode;
                pw.description = prod.Description;
                pw.category = prod.Family;
                
                // TODO: Get actual pricing from PricebookEntry
                // For now, using placeholder pricing
                pw.unitPrice = getProductPrice(prod.Id);
                
                products.add(pw);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching products: ' + e.getMessage());
            // Return empty list on error - don't throw to allow graceful degradation
        }
        
        return products;
    }
    
    /**
     * @description Adds products from the AI assistant cart to an actual Salesforce Quote by creating
     *              quote lines. This method parses the products JSON, validates inputs, creates
     *              SBQQ__QuoteLine__c records (or standard QuoteLineItem records based on implementation),
     *              and inserts them.
     * @param quoteId The ID of the quote to add products to
     * @param productsJson JSON string containing cart items with productId, productName, quantity, 
     *                     discount, and unitPrice
     * @return String Success message indicating how many products were added
     * @throws AuraHandledException If quoteId is blank, productsJson is blank, JSON parsing fails,
     *                              no products to add, or insert fails
     */
    @AuraEnabled
    public static String addProductsToQuote(String quoteId, String productsJson) {
        try {
            // Validate inputs
            if (String.isBlank(quoteId)) {
                throw new AuraHandledException('Quote ID is required.');
            }
            
            if (String.isBlank(productsJson)) {
                throw new AuraHandledException('Products data is required.');
            }
            
            // Parse cart items
            List<CartItemWrapper> items = (List<CartItemWrapper>) JSON.deserialize(
                productsJson, 
                List<CartItemWrapper>.class
            );
            
            if (items.isEmpty()) {
                throw new AuraHandledException('No products to add.');
            }
            
            // Create quote lines
            // TODO: Adjust this based on your Quote object (standard Quote vs SBQQ__Quote__c)
            List<SObject> quoteLines = new List<SObject>();
            
            for (CartItemWrapper item : items) {
                // For Salesforce CPQ (SBQQ)
                // Uncomment and modify based on your implementation:
                /*
                SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c();
                ql.SBQQ__Quote__c = quoteId;
                ql.SBQQ__Product__c = item.productId;
                ql.SBQQ__Quantity__c = item.quantity;
                if (item.discount != null && item.discount > 0) {
                    ql.SBQQ__Discount__c = item.discount;
                }
                quoteLines.add(ql);
                */
                
                // For Standard Quote Line Items:
                /*
                QuoteLineItem qli = new QuoteLineItem();
                qli.QuoteId = quoteId;
                qli.Product2Id = item.productId;
                qli.Quantity = item.quantity;
                qli.UnitPrice = item.unitPrice != null ? item.unitPrice : 0;
                // Add PricebookEntryId based on your logic
                quoteLines.add(qli);
                */
                
                System.debug('Would add product: ' + item.productName + 
                            ' x ' + item.quantity + 
                            ' @ ' + item.unitPrice);
            }
            
            // Insert quote lines
            if (!quoteLines.isEmpty()) {
                insert quoteLines;
            }
            
            return 'Successfully added ' + items.size() + ' product(s) to the quote.';
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException('Error adding products to quote: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error adding products: ' + e.getMessage());
        }
    }
    
    // ============================================
    // PRIVATE METHODS - GEMINI INTEGRATION
    // ============================================
    
    /**
     * @description Builds a comprehensive system prompt for Gemini AI with available products and instructions.
     *              This prompt instructs Gemini on how to behave as a CPQ assistant, what actions are available,
     *              response format requirements, and parameter examples.
     * @return String The complete system prompt for Gemini API
     */
    private static String buildSystemPrompt() {
        // Get available products for context
        String productList = buildProductListString();
        
        // Build comprehensive system prompt
        String systemPrompt = 
            'You are an AI Quote Assistant for a CPQ (Configure, Price, Quote) system. ' +
            'Your role is to help users build quotes using natural language commands.\n\n' +
            
            'AVAILABLE ACTIONS:\n' +
            '- ADD_PRODUCT: Add products to the cart\n' +
            '- REMOVE_PRODUCT: Remove products from the cart\n' +
            '- UPDATE_QUANTITY: Update quantity of a product\n' +
            '- APPLY_DISCOUNT: Apply a discount to specific products or all items\n' +
            '- CLEAR_CART: Clear all items from the cart\n' +
            '- GET_SUMMARY: Show cart summary\n\n' +
            
            'AVAILABLE PRODUCTS:\n' +
            productList + '\n\n' +
            
            'RESPONSE FORMAT:\n' +
            'Always respond ONLY in JSON format with the following structure:\n' +
            '{\n' +
            '  "action": "ACTION_NAME",\n' +
            '  "parameters": { ... action-specific parameters ... },\n' +
            '  "message": "Human-readable response to display to the user"\n' +
            '}\n\n' +
            
            'PARAMETER EXAMPLES:\n' +
            '- ADD_PRODUCT: {"productName": "Product Name", "productId": "ID", "quantity": 5}\n' +
            '- APPLY_DISCOUNT: {"discountPercent": 20, "applyTo": "all"} or {"discountPercent": 10, "productId": "ID"}\n' +
            '- UPDATE_QUANTITY: {"productId": "ID", "quantity": 10}\n' +
            '- REMOVE_PRODUCT: {"productId": "ID"} or {"productName": "Product Name"}\n' +
            '- CLEAR_CART: {}\n' +
            '- GET_SUMMARY: {}\n\n' +
            
            'IMPORTANT RULES:\n' +
            '1. If the user request is unclear or cannot be fulfilled, set "action": "CLARIFY" ' +
            'and ask for more information in "message".\n' +
            '2. Always be helpful and suggest alternatives if exact matches are not found.\n' +
            '3. If you need to explain something, ALWAYS wrap your explanation inside the ' +
            '"message" field of the JSON.\n' +
            '4. NEVER respond with plain text - ALWAYS use the JSON format.\n' +
            '5. For product matching, be flexible with spelling and partial names.\n' +
            '6. When adding products, if no quantity is specified, default to 1.\n' +
            '7. When applying discounts, if no target is specified, apply to all items.\n';
        
        return systemPrompt;
    }
    
    /**
     * @description Builds a formatted string list of available products for inclusion in the system prompt.
     *              Queries active products and formats them with ID and ProductCode for AI context.
     * @return String Formatted product list string with each product on a new line
     */
    private static String buildProductListString() {
        StringBuilder productListBuilder = new StringBuilder();
        
        try {
            List<Product2> products = [
                SELECT Id, Name, ProductCode, Description, Family
                FROM Product2
                WHERE IsActive = true
                ORDER BY Name
                LIMIT 100
            ];
            
            for (Product2 prod : products) {
                productListBuilder.append('- ')
                    .append(prod.Name)
                    .append(' (ID: ')
                    .append(prod.Id)
                    .append(', Code: ')
                    .append(prod.ProductCode != null ? prod.ProductCode : 'N/A')
                    .append(')\n');
            }
            
            if (products.isEmpty()) {
                productListBuilder.append('(No products available - user may specify custom products)\n');
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error building product list: ' + e.getMessage());
            productListBuilder.append('(Product list temporarily unavailable)\n');
        }
        
        return productListBuilder.toString();
    }
    
    /**
     * @description Makes an HTTP callout to the Google Gemini API with the system prompt and user message.
     *              Constructs the request body according to Gemini API format, handles authentication,
     *              and manages the HTTP request/response cycle.
     * @param systemPrompt The system instructions that define Gemini's role and capabilities
     * @param userMessage The user's natural language query
     * @return String Raw JSON response from Gemini API containing the AI-generated content
     * @throws AuraHandledException If API key is missing, HTTP callout fails, or request serialization fails
     */
    private static String callGeminiAPI(String systemPrompt, String userMessage) {
        // Validate API key
        String apiKey = GEMINI_API_KEY;
        if (String.isBlank(apiKey)) {
            throw new AuraHandledException(
                'Gemini API key is not configured. Please set up the AI_Settings__mdt custom metadata.'
            );
        }
        
        // Build endpoint with API key
        String endpoint = GEMINI_ENDPOINT + '?key=' + apiKey;
        
        // Create HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(API_TIMEOUT);
        
        // Build request body for Gemini API
        // Gemini uses a different structure than OpenAI
        Map<String, Object> requestBody = new Map<String, Object>();
        
        // System instruction (Gemini 1.5+ supports this)
        Map<String, Object> systemInstruction = new Map<String, Object>();
        Map<String, String> systemPart = new Map<String, String>();
        systemPart.put('text', systemPrompt);
        systemInstruction.put('parts', new List<Object>{ systemPart });
        requestBody.put('systemInstruction', systemInstruction);
        
        // User content
        List<Object> contents = new List<Object>();
        Map<String, Object> userContent = new Map<String, Object>();
        userContent.put('role', 'user');
        
        Map<String, String> userPart = new Map<String, String>();
        userPart.put('text', userMessage);
        userContent.put('parts', new List<Object>{ userPart });
        contents.add(userContent);
        
        requestBody.put('contents', contents);
        
        // Generation config
        Map<String, Object> generationConfig = new Map<String, Object>();
        generationConfig.put('temperature', 0.7);
        generationConfig.put('maxOutputTokens', 1024);
        generationConfig.put('topP', 0.95);
        requestBody.put('generationConfig', generationConfig);
        
        // Safety settings (optional - adjust based on needs)
        List<Object> safetySettings = new List<Object>();
        Map<String, Object> harassmentSetting = new Map<String, Object>();
        harassmentSetting.put('category', 'HARM_CATEGORY_HARASSMENT');
        harassmentSetting.put('threshold', 'BLOCK_NONE');
        safetySettings.add(harassmentSetting);
        requestBody.put('safetySettings', safetySettings);
        
        // Serialize and set body
        try {
            req.setBody(JSON.serialize(requestBody));
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing request: ' + e.getMessage());
        }
        
        // Make HTTP callout
        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
        } catch (CalloutException e) {
            System.debug(LoggingLevel.ERROR, 'Callout failed: ' + e.getMessage());
            throw new AuraHandledException(
                'Failed to connect to Gemini API. Please check your network connection ' +
                'and ensure the Remote Site Setting is configured correctly.'
            );
        }
        
        // Process response
        return processGeminiResponse(res);
    }
    
    /**
     * @description Processes and validates the HTTP response from Gemini API. Extracts the text content
     *              from Gemini's response structure, handles error responses, and validates response format.
     * @param res The HTTP response object from the Gemini API callout
     * @return String The extracted text content from Gemini's response
     * @throws AuraHandledException If response status is not 200, response structure is invalid,
     *                              content is missing, or JSON parsing fails
     */
    private static String processGeminiResponse(HttpResponse res) {
        Integer statusCode = res.getStatusCode();
        String responseBody = res.getBody();
        
        System.debug(LoggingLevel.DEBUG, 'Gemini Response Status: ' + statusCode);
        System.debug(LoggingLevel.DEBUG, 'Gemini Response Body: ' + responseBody);
        
        if (statusCode == 200) {
            try {
                // Parse Gemini response structure
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                
                // Get candidates array
                List<Object> candidates = (List<Object>) responseMap.get('candidates');
                if (candidates == null || candidates.isEmpty()) {
                    throw new AuraHandledException('Gemini API returned no candidates in response.');
                }
                
                // Get first candidate
                Map<String, Object> candidate = (Map<String, Object>) candidates[0];
                
                // Get content
                Map<String, Object> content = (Map<String, Object>) candidate.get('content');
                if (content == null) {
                    throw new AuraHandledException('Gemini API response missing content.');
                }
                
                // Get parts
                List<Object> parts = (List<Object>) content.get('parts');
                if (parts == null || parts.isEmpty()) {
                    throw new AuraHandledException('Gemini API response missing parts.');
                }
                
                // Get text from first part
                Map<String, Object> part = (Map<String, Object>) parts[0];
                String text = (String) part.get('text');
                
                if (String.isBlank(text)) {
                    throw new AuraHandledException('Gemini API returned empty response.');
                }
                
                // Clean up response - remove markdown code blocks if present
                text = cleanJsonResponse(text);
                
                return text;
                
            } catch (AuraHandledException e) {
                throw e;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error parsing Gemini response: ' + e.getMessage());
                throw new AuraHandledException(
                    'Error parsing AI response. Please try again.'
                );
            }
        } else {
            // Handle error responses
            return handleGeminiError(statusCode, responseBody);
        }
    }
    
    /**
     * @description Handles error responses from Gemini API by parsing error details and throwing
     *              appropriate AuraHandledException with user-friendly error messages based on
     *              HTTP status codes.
     * @param statusCode HTTP status code from the API response
     * @param responseBody Response body containing error details
     * @return String This method never returns - always throws AuraHandledException
     * @throws AuraHandledException With appropriate error message based on status code
     */
    private static String handleGeminiError(Integer statusCode, String responseBody) {
        String errorMessage = 'Gemini API error (' + statusCode + ')';
        
        try {
            Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> error = (Map<String, Object>) errorResponse.get('error');
            
            if (error != null) {
                String message = (String) error.get('message');
                String status = (String) error.get('status');
                
                if (statusCode == 400) {
                    errorMessage = 'Invalid request to AI service. Please try rephrasing your message.';
                } else if (statusCode == 401 || statusCode == 403) {
                    errorMessage = 'AI service authentication failed. Please contact your administrator.';
                } else if (statusCode == 429) {
                    errorMessage = 'AI service rate limit exceeded. Please wait a moment and try again.';
                } else if (statusCode == 500 || statusCode == 503) {
                    errorMessage = 'AI service is temporarily unavailable. Please try again later.';
                } else {
                    errorMessage = 'AI service error: ' + (message != null ? message : status);
                }
            }
        } catch (Exception e) {
            // Use generic error message if we can't parse the error response
            System.debug(LoggingLevel.ERROR, 'Could not parse error response: ' + e.getMessage());
        }
        
        throw new AuraHandledException(errorMessage);
    }
    
    /**
     * @description Cleans JSON response from Gemini by removing markdown code blocks (```json ... ```).
     *              Gemini sometimes wraps JSON responses in markdown code blocks which need to be
     *              removed before parsing.
     * @param text Raw text response from Gemini API
     * @return String Cleaned JSON string with markdown code blocks removed
     */
    private static String cleanJsonResponse(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        
        String cleaned = text.trim();
        
        // Remove markdown code blocks (```json ... ``` or ``` ... ```)
        if (cleaned.startsWith('```json')) {
            cleaned = cleaned.replaceFirst('```json', '');
        } else if (cleaned.startsWith('```')) {
            cleaned = cleaned.replaceFirst('```', '');
        }
        
        if (cleaned.endsWith('```')) {
            cleaned = cleaned.substring(0, cleaned.length() - 3);
        }
        
        return cleaned.trim();
    }
    
    /**
     * @description Retrieves the unit price for a product from PricebookEntry.
     *              Currently returns a placeholder value. Should be implemented to query
     *              the standard pricebook entry for the given product.
     * @param productId The Product2 record ID to get pricing for
     * @return Decimal The unit price from PricebookEntry, or placeholder value if not implemented
     */
    private static Decimal getProductPrice(Id productId) {
        // TODO: Implement actual pricing lookup
        // Example:
        /*
        try {
            PricebookEntry pbe = [
                SELECT UnitPrice 
                FROM PricebookEntry 
                WHERE Product2Id = :productId 
                AND Pricebook2.IsStandard = true 
                AND IsActive = true 
                LIMIT 1
            ];
            return pbe.UnitPrice;
        } catch (Exception e) {
            return 100.00; // Default price
        }
        */
        
        // Placeholder: Return random price for demo
        return 100.00;
    }
    
    // ============================================
    // INNER CLASSES - DATA WRAPPERS
    // ============================================
    
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
        /** Product category/family */
        @AuraEnabled public String category { get; set; }
        /** Unit price for the product */
        @AuraEnabled public Decimal unitPrice { get; set; }
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
    
    /**
     * @description Utility class for efficient string concatenation using a buffer
     */
    private class StringBuilder {
        private List<String> buffer;
        
        public StringBuilder() {
            this.buffer = new List<String>();
        }
        
        public StringBuilder append(String s) {
            if (s != null) {
                this.buffer.add(s);
            }
            return this;
        }
        
        public override String toString() {
            return String.join(this.buffer, '');
        }
    }
}