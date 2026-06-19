/***************************************************************************************************
* Class Name   : BooleanExpressionResolver
* Test Class   : BooleanExpressionResolverTest
* Created Date : Oct 09, 2023
* Author       : Dipali Pedgulwar
* Description  : Class to evaluate a boolean expression for custom logic 
* Example      : (TRUE AND (FALSE OR TRUE)) is TRUE
****************************************************************************************************/
public class BooleanExpressionResolver {
    static Map<String, String> logicTypes = new Map<String, String>();
    static Map<String, Map<String, String>> expressionLogic = new Map<String, Map<String, String>>();
    public static boolean isCheckOnce = false;
    
    /**
    * Evaluate a boolean expreassion 
    * 
    */
    public static Boolean eval(String expression) {  
        System.debug('expression from eval ='+expression);
        // If expression contains all TRUE or FALSE
        if(expression.containsNone('FALSE')) { return TRUE; }        
        if(expression.containsNone('TRUE')) { return FALSE; }
        
       	fillLogic();
        system.debug('@@snehalExpressionin' +expression);
        return Boolean.valueOf(evaluateExpression(expression.toUpperCase()));        
    }
    
    /**
    * Evaluate the expression
    * 
    */
    public static String evaluateExpression(String expression) {        
        for(String logicType : logicTypes.keySet()) {
            if(expression.contains(logicType)) {
                expression = simplifyExpression(expression, logicTypes.get(logicType));
                
            }
        }
        System.debug('expression after simplifyExpression ='+expression);
        
		 if(expression.contains('AND') || expression.contains('OR') || expression.contains('(')) {
            expression = evaluateExpression(expression);
            }
        system.debug('expression1' +expression);
        return expression;
    }
    
    /**
    * Simplify the expression
    * 
    */
    public static string simplifyExpression(String expression, String logicType){
        Map<String, String> logic = new Map<String, String>(expressionLogic.get(logicType));
        System.debug('logic ='+logic);
        
        for(String key : logic.keySet()) {
            expression = expression.replace(key, logic.get(key));
            System.debug('expression 58='+ expression);
        }
        System.debug('expression ='+expression);
        return expression;
    } 
    
    /**
    * Fill AND and OR Logic
    * 
    */
    public static void fillLogic() {
        Map<String, String> andLogic = new Map<String, String>();
        Map<String, String> orLogic = new Map<String, String>();
        Map<String, String> braceLogic = new Map<String, String>();
        
        logicTypes.put('AND', 'AND');
        logicTypes.put('OR', 'OR');
        logicTypes.put('(', 'BRACES');

        
        // AND Logic
        andLogic.put('TRUE AND TRUE', 'TRUE');
        andLogic.put('TRUE AND FALSE', 'FALSE');
        andLogic.put('FALSE AND TRUE', 'FALSE');
        andLogic.put('FALSE AND FALSE', 'FALSE');
        expressionLogic.put('AND', andLogic);
        
        // OR Logic
        orLogic.put('TRUE OR TRUE', 'TRUE');
        orLogic.put('TRUE OR FALSE', 'TRUE');
        orLogic.put('FALSE OR TRUE', 'TRUE');
        orLogic.put('FALSE OR FALSE', 'FALSE');
        expressionLogic.put('OR', orLogic);
        
        // Braces Logic
        braceLogic.put('( TRUE )', 'TRUE');
        braceLogic.put('( FALSE )', 'FALSE');
        expressionLogic.put('BRACES', braceLogic);
    }
}