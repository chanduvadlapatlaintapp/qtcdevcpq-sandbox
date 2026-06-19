public without sharing class EvaluateTermCondition {
    private SBQQ__TermCondition__c termCondition;
    public SBQQ__Quote__c quote;
    public Set<String> productCodes;
    public Boolean result { get; set; }
    public Boolean isEvaluated {private set;}

    public EvaluateTermCondition(SBQQ__TermCondition__c termCondition, SBQQ__Quote__c quote, Set<String> productCodes) {
        this.termCondition = termCondition;
        this.quote = quote;
        this.productCodes = productCodes;
        this.isEvaluated = false;
    }

    public void evaluate() {
        // Logic to evaluate a single condition and then set result to true or false and isEvaluated to true
        if(termCondition.SBQQ__TestedField__c!=null){ 
        if(!termCondition.SBQQ__TestedField__c.equalsIgnoreCase('SBQQ__ProductCode__c')) { 
        	String valueToTest = String.valueOf(getValueToTest());
            System.debug('valueToTest = '+valueToTest);
        switch on termCondition.SBQQ__Operator__c {
            when 'equals' {
                  System.debug('valueToTest = '+String.valueOf(termCondition.SBQQ__Value__c));
                result = evaluateEqualTo(valueToTest, String.valueOf(termCondition.SBQQ__Value__c));
            }
            when 'not equals' {
                    System.debug('valueToTest = '+String.valueOf(termCondition.SBQQ__Value__c));
                result = evaluateNotEqualTo(valueToTest, String.valueOf(termCondition.SBQQ__Value__c));
            }
            when 'greater than' {
                try {
                    result = evaluateGreaterThan(Decimal.valueOf(valueToTest), Decimal.valueOf(termCondition.SBQQ__Value__c));
                } catch(Exception e) {
                    result = false;
                }
            }
            when 'greater or equals' {
                try {
                    System.debug('line 39 ='+Decimal.valueOf(valueToTest));
                    System.debug('line 40 ='+Decimal.valueOf(termCondition.SBQQ__Value__c));
                    result = evaluateGreaterThanOrEqualtTo(Decimal.valueOf(valueToTest), Decimal.valueOf(termCondition.SBQQ__Value__c));
                } catch(Exception e) {
                    result = false;
                }
            }
            when 'less than' {
                try {
                    result = evaluateLessThan(Decimal.valueOf(valueToTest), Decimal.valueOf(termCondition.SBQQ__Value__c));
                } catch(Exception e) {
                    result = false;
                }
            }
            when 'less or equals' {
                try {
                    result = evaluateLessThanOrEqualtTo(Decimal.valueOf(valueToTest), Decimal.valueOf(termCondition.SBQQ__Value__c));
                } catch(Exception e) {
                    result = false;
                }
            }
            when 'starts with' {
                //result = evaluateIsBlank(valueToTest);
            }
            when 'ends with' {
                //result = evaluateIsNotBlank(valueToTest);
            }
            when 'contains' {
                result = evaluateContains(valueToTest, String.valueOf(termCondition.SBQQ__Value__c));
            }
            when 'does not contain' {
                result = !(evaluateContains(valueToTest, String.valueOf(termCondition.SBQQ__Value__c)));
            }
        }
        } else {
            switch on termCondition.SBQQ__Operator__c {
            when 'contains' {
            	result = productCodes.contains(String.valueOf(termCondition.SBQQ__Value__c));
            }
                when 'does not contain' {
                result = !(productCodes.contains(String.valueOf(termCondition.SBQQ__Value__c)));
            }
            }
        }
        this.isEvaluated = true;
    }
}

    /*
     * Private methods
     */

    private Object getValueToTest() {
        
        String testedObject = 'SBQQ__Quote__c';
        String testedField = termCondition.SBQQ__TestedField__c; 
        Object valueToTest;
        switch on testedObject {
            when 'SBQQ__Quote__c' {               
                valueToTest = quote.get(testedField);
            }
        }
        return valueToTest;
    }

    private Boolean evaluateEqualTo(String fieldValue, String value) {
        return fieldValue == value;
    }

    private Boolean evaluateNotEqualTo(String fieldValue, String value) {
        return fieldValue != value;
    }

    private Boolean evaluateGreaterThan(Decimal fieldValue, Decimal value) {
        System.debug('evaluateGreaterThan111 ='+fieldValue);
        System.debug('evaluateGreaterThan112 ='+value);
        return fieldValue > value;
    }

    private Boolean evaluateGreaterThanOrEqualtTo(Decimal fieldValue, Decimal value) {
        return fieldValue >= value;
    }

    private Boolean evaluateLessThan(Decimal fieldValue, Decimal value) {
        return fieldValue < value;
    }

    private Boolean evaluateLessThanOrEqualtTo(Decimal fieldValue, Decimal value) {
        return fieldValue <= value;
    }

    private Boolean evaluateIsBlank(String fieldValue) {
        return String.isBlank(fieldValue);
    }

    private Boolean evaluateIsNotBlank(String fieldValue) {
        return String.isNotBlank(fieldValue);
    }

    private Boolean evaluateContains(String fieldValue, String value) {
        if(String.isNotBlank(fieldValue)) {
            return fieldValue.contains(value);
        }
        else {
        	return false;
        }
    }

    /*private Boolean evaluateIsChanged(String newFieldValue, String oldFieldValue) {
        return newFieldValue != oldFieldValue;
    }*/
}