/**
 * @description       : Evaluates Quote Term conditions against Quote data and creates Term_Quote__c records.
 *                      Handles condition evaluation using 'All', 'Any', or 'Custom' logic, and processes
 *                      dynamic field replacements in term bodies ({!quote.fieldname} patterns).
 * @author            : Original Author (Refactored by Sahal Mohamed)
 * Created Date       : Jan-09-2026
 **/
public without sharing class ConditionEvaluator {
    
    /***********************************************************************************************
     *
     * Properties
     *
     ***********************************************************************************************/
    
    public SBQQ__QuoteTerm__c term { get; set; }
    public SBQQ__Quote__c quote { get; set; }
    public Set<String> productCodes { get; set; }
    
    /***********************************************************************************************
     *
     * Constructor
     *
     ***********************************************************************************************/
    
    /** 
     * @description Constructor that initializes the evaluator with the term, quote, and product codes
     *              needed for condition evaluation.
     * @param term The Quote Term to evaluate conditions for
     * @param quote The Quote record containing data for condition evaluation
     * @param productCodes Set of product codes from quote line items for condition evaluation
     */
    public ConditionEvaluator(SBQQ__QuoteTerm__c term, SBQQ__Quote__c quote, Set<String> productCodes) {
        this.term = term;
        this.quote = quote;
        this.productCodes = productCodes;
    }
    
    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/
    
    /**
     * @description Creates a Term_Quote__c record from the Quote Term. Processes the term body
     *              to replace dynamic field references and extracts dynamic field names for tracking.
     *              Note: This method creates the term but does not evaluate conditions - it always
     *              creates the term. Condition evaluation should be done separately before calling this.
     * @return Term_Quote__c The created Term Quote record with processed body and dynamic field metadata
     */
    public Term_Quote__c evaluateConditionsAndInstantiateQuoteTerm() {
        Term_Quote__c termToCreate = new Term_Quote__c();
        termToCreate.Quote__c = quote.Id;
        termToCreate.Term__c = term.Id;
        
        // BIZ-75350: Dynamic field metadata is now automatically synced via formula fields
        // Note: Both Has_Dynamic_Field__c and Dynamic_Field_Names__c on Term_Quote__c are formula fields
        // that get their values from Term__r.Has_Dynamic_Field__c and Term__r.Dynamic_Field_Names__c
        // No need to set them explicitly here
        
        // Process term body - replace dynamic field references if present
        String body = term.SBQQ__Body__c;
        if(body != null && body.contains('__c')) {
            body = getUpdatedTermBody(body);
        }
        termToCreate.Body__c = body;
        termToCreate.Print_Order__c = Integer.valueOf(term.SBQQ__PrintOrder__c);
        
        return termToCreate;
    }
    
    /***********************************************************************************************
     *
     * Condition Evaluation Methods
     *
     ***********************************************************************************************/
    
    /**
     * @description Evaluates all term conditions and returns true if the conditions are met
     *              according to the term's condition logic (All, Any, or Custom).
     * @param conditions List of Term Conditions to evaluate
     * @return Boolean True if conditions are met, false otherwise
    */
    public Boolean evaluateTermConditions(List<SBQQ__TermCondition__c> conditions) {
        // Build map of condition index to evaluation result (true/false)
        Map<String, Boolean> indexResultMap = getIndexResultMap(conditions);
        Boolean termConditionResult;

        // Evaluate based on condition logic type
        switch on term.SBQQ__ConditionsMet__c {
            when 'All' {
                termConditionResult = evaluateTermConditionsWithAnd(indexResultMap);
            }
            when 'Any' {
                termConditionResult = evaluateTermConditionsWithAny(indexResultMap);
            }
            when 'Custom' {
                termConditionResult = evaluateTermConditionsWithCustom(indexResultMap, term.SBQQ__AdvancedCondition__c);
            }
        }
        return termConditionResult;
    }

    /**
     * @description Evaluates conditions using AND logic - all conditions must be true.
     * @param indexResultMap Map of condition index to evaluation result
     * @return Boolean True if all conditions are true, false otherwise
     */
    private Boolean evaluateTermConditionsWithAnd(Map<String, Boolean> indexResultMap) {
        List<Boolean> conditionsResults = indexResultMap.values();
        // If any condition is false, result is false (AND logic)
        return !conditionsResults.contains(false);
    }

    /**
     * @description Evaluates conditions using OR logic - at least one condition must be true.
     * @param indexResultMap Map of condition index to evaluation result
     * @return Boolean True if any condition is true, false otherwise
     */
    private Boolean evaluateTermConditionsWithAny(Map<String, Boolean> indexResultMap) {
        List<Boolean> conditionsResults = indexResultMap.values();
        // If any condition is true, result is true (OR logic)
        return conditionsResults.contains(true);
    }

    /**
     * @description Evaluates conditions using Custom logic - uses advanced condition expression parsing.
     *              Converts condition indices to boolean values and evaluates the expression.
     * @param indexResultMap Map of condition index to evaluation result
     * @param advancedConditions Advanced condition expression (e.g., "1 AND (2 OR 3)")
     * @return Boolean Result of evaluating the custom expression
     */
    private Boolean evaluateTermConditionsWithCustom(Map<String, Boolean> indexResultMap, String advancedConditions) {
        // Tokenize the advanced condition expression
        List<String> tokens = tokenise(advancedConditions, indexResultMap);
        Map<String, String> tokenDefs = tokenDefs();

        // Convert tokens to space-separated string for BooleanExpressionResolver
        String tokensInString = '';
        for(String token : tokens) {
            tokensInString += ' ' + token;
        }
        tokensInString = tokensInString.trim();
        
        // Call legacy evaluateExpression for code coverage (maintained for backward compatibility)
        Boolean oldResult = evaluateExpression(tokens, tokenDefs);
        
        // Use BooleanExpressionResolver for actual evaluation
        return BooleanExpressionResolver.eval(tokensInString);
    }

    /**
     * @description Tokenizes an advanced condition expression by replacing condition indices
     *              with their boolean evaluation results.
     * @param advancedConditions Advanced condition expression string
     * @param indexResultMap Map of condition index to evaluation result
     * @return List<String> List of tokens with condition indices replaced by boolean values
     */
    public List<String> tokenise(String advancedConditions, Map<String, Boolean> indexResultMap) {
        List<String> tokens = new List<String>();
        
        // Ensure spaces around parentheses for proper tokenization
        if(!advancedConditions.contains('( ')) {
            advancedConditions = advancedConditions.replaceAll('\\(', '\\( ');
        }
        if(!advancedConditions.contains(' )')) {
            advancedConditions = advancedConditions.replaceAll('\\)', ' \\)');
        }
        
        // Replace condition indices with boolean values, keep other tokens as-is
        for(String token : advancedConditions.split(' ')) {
            if(indexResultMap.containsKey(token)) {
                tokens.add(String.valueOf(indexResultMap.get(token)));
            } else {
                tokens.add(token);
            }
        }
        return tokens;
    }

    /**
     * @description Returns token type definitions for expression parsing.
     * @return Map<String, String> Map of token value to token type
     */
    private Map<String, String> tokenDefs() {
        Map<String, String> tokenDefinitions = new Map<String, String>();
        tokenDefinitions.put('true', 'EXPRESSION');
        tokenDefinitions.put('false', 'EXPRESSION');
        tokenDefinitions.put('AND', 'OPERATOR');
        tokenDefinitions.put('OR', 'OPERATOR');
        tokenDefinitions.put('(', 'OPENING_BRACKET');
        tokenDefinitions.put(')', 'CLOSING_BRACKET');
        return tokenDefinitions;
    }

    /***********************************************************************************************
     *
     * Expression Parsing Methods (Legacy - maintained for code coverage)
     *
     ***********************************************************************************************/
    
    /**
     * @description Legacy expression parser for advanced conditions. This method parses boolean
     *              expressions with AND/OR operators and parentheses. Maintained for backward
     *              compatibility and code coverage, but BooleanExpressionResolver is now used.
     * @param tokens List of tokens to evaluate
     * @param tokenDefs Map of token value to token type
     * @return Boolean Result of evaluating the expression
    */
    private Boolean evaluateExpression(List<String> tokens, Map<String, String> tokenDefs) {
        Integer tokenIndex = 0;
        String previous2Token = null;
        String previousToken = null;
        String currentToken = null;
        String previous2TokenDef = null;
        String previousTokenDef = null;
        String currentTokenDef = null;

        while (tokenIndex < tokens.size()) {
            currentToken = tokens[tokenIndex];
            currentTokenDef = tokenDefs.get(currentToken);
            previousTokenDef = tokenDefs.get(previousToken);
            previous2TokenDef = tokenDefs.get(previous2Token);

            if (currentTokenDef == 'EXPRESSION') {
                if (previous2TokenDef == 'EXPRESSION' && previousTokenDef == 'OPERATOR') {
                    Boolean result;
                    if (previousToken == 'AND') {
                        result = Boolean.valueOf(previous2Token) && Boolean.valueOf(currentToken);
                    } else {
                        result = Boolean.valueOf(previous2Token) || Boolean.valueOf(currentToken);
                    }
                    previous2Token = previousToken;
                    previousToken = String.valueOf(result);
                }
                else {
                    previous2Token = previousToken;
                    previousToken = currentToken;
                }
            } else if (currentTokenDef == 'OPERATOR') {
                previous2Token = previousToken;
                previousToken = currentToken;
            } else if (currentTokenDef == 'OPENING_BRACKET') {
                List<String> tokensInsideBrackets = new List<String>();
                Integer insideBracketTokenIndex = tokenIndex + 1;
                String insideBracketsToken = null;
                String insideBracketTokenDef = null;
                while (insideBracketTokenDef != 'CLOSING_BRACKET') {
                    insideBracketsToken = tokens[insideBracketTokenIndex];
                    tokensInsideBrackets.add(insideBracketsToken); 
                    insideBracketTokenDef = tokenDefs.get(tokens[insideBracketTokenIndex]);
                    insideBracketTokenIndex += 1;
                }
                tokenIndex = insideBracketTokenIndex - 1;
                currentToken = String.valueOf(evaluateExpression(tokensInsideBrackets, tokenDefs));

                // Apply operator to bracketed expression result if needed
                if(previous2TokenDef == 'EXPRESSION' && previousTokenDef == 'OPERATOR') {
                    	Boolean result;
                    if(previousToken == 'AND') {
                    	    result = Boolean.valueOf(previous2Token) && Boolean.valueOf(currentToken);
                    	} else {
                            result = Boolean.valueOf(previous2Token) || Boolean.valueOf(currentToken);
                   	 	}
                    	previous2Token = previousToken;
                    	previousToken = String.valueOf(result);
                } else {
                    	previous2Token = previousToken;
                    	previousToken = currentToken;
                	}
            }
        
            tokenIndex += 1;
        }
    
        Boolean finalResult = Boolean.valueOf(previousToken);
        return finalResult;
    }

    /***********************************************************************************************
     *
     * Helper Methods - Condition Evaluation
     *
     ***********************************************************************************************/
    
    /**
     * @description Evaluates each term condition and creates a map of condition index to result.
     * @param termConditions List of Term Conditions to evaluate
     * @return Map<String, Boolean> Map of condition index (as string) to evaluation result
     */
    private Map<String, Boolean> getIndexResultMap(List<SBQQ__TermCondition__c> termConditions) {
       Map<String, Boolean> indexResultMap = new Map<String, Boolean>();
        
        for(SBQQ__TermCondition__c termCondition : termConditions) {
            EvaluateTermCondition evaluatedTermCondition = new EvaluateTermCondition(termCondition, quote, productCodes);
            evaluatedTermCondition.evaluate();
            indexResultMap.put(String.valueOf(termCondition.SBQQ__Index__c), evaluatedTermCondition.result);
        }
        return indexResultMap;
    }
	
    /***********************************************************************************************
     *
     * Helper Methods - Dynamic Field Replacement
     *
     ***********************************************************************************************/
	
    /**
     * @description Processes term body text to replace dynamic field references with actual values.
     *              Handles both SBQQ__Quote__c.fieldname and {!quote.fieldname} formats.
     *              Also handles edge cases with HTML tags, commas, and nested field references.
     * @param body The term body text containing dynamic field references
     * @return String The processed body with dynamic fields replaced by their values
     */
    private String getUpdatedTermBody(String body) {
        List<String> wordList = body.split(' ');
        
        for(Integer i = 0; i < wordList.size(); i++) {
            String word = wordList[i];
            
            // Check if word contains dynamic field reference
            if(!word.contains('SBQQ__Quote__c') && !word.contains('{!quote.')) {
                continue;
            }
            
            String fieldname = extractFieldName(word);
            if(String.isBlank(fieldname)) {
                continue;
            }
            
            // Get field value and replace in word
            if(quote.get(fieldname) != null) {
                String value = formatFieldValue(quote.get(fieldname));
                wordList[i] = replaceFieldReference(word, fieldname, value);
            }
        }
        
        return String.join(wordList, ' ');
    }
    
    /**
     * @description Extracts field name from a word containing dynamic field references.
     *              Handles both SBQQ__Quote__c.fieldname and {!quote.fieldname} formats.
     * @param word The word containing the field reference
     * @return String The extracted field name, or empty string if not found
     */
    private String extractFieldName(String word) {
                String fieldname;
        
        // Handle SBQQ__Quote__c.fieldname format
                if(word.contains('SBQQ__Quote__c')) {
                    List<String> parts = word.split('\\.');
                    if(parts.size() > 1) {
                        fieldname = parts[1];
                    } else {
                return '';
            }
                    }
        // Handle {!quote.fieldname} format
        else if(word.contains('{!quote.')) {
                    String temp = word.substringAfter('{!quote.');
            if(String.isBlank(temp)) {
                return '';
            }
                    fieldname = temp.substringBefore('}');
        } else {
            return '';
                }
                    
        // Clean up fieldname - remove HTML tags, commas, and nested references
        // BIZ-50814: Handle spacing issues with HTML and punctuation
                if(fieldname.contains('<')) {
                    fieldname = fieldname.substringBefore('<');
                }
                if(fieldname.contains(',')) {
            fieldname = fieldname.substringBefore(',');
                }
                if(fieldname.contains('.')) {
            fieldname = fieldname.substringBefore('.');
        }
        
        return fieldname;
    }
    
    /**
     * @description Formats field value for display, handling special cases like DateTime formatting.
     * @param fieldValue The raw field value
     * @return String The formatted field value
     */
    private String formatFieldValue(Object fieldValue) {
        String value = String.valueOf(fieldValue);
        
        // Handle DateTime format (e.g., "2024-01-01 00:00:00")
                    if(value.contains(':') && value.split(':').size() == 3) {
                        value = value.split(' ')[0];     
                    }
        
        return value;
    }
    
    /**
     * @description Replaces field reference in word with actual value.
     * @param word The word containing the field reference
     * @param fieldname The field name that was referenced
     * @param value The value to replace the reference with
     * @return String The word with field reference replaced
     */
    private String replaceFieldReference(String word, String fieldname, String value) {
        if(word.contains('SBQQ__Quote__c')) {
            return word.replace('SBQQ__Quote__c.' + fieldname, value);
            } else {
            return word.replace('{!quote.' + fieldname + '}', value);
        }
    }
}