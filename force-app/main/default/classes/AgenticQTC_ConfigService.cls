/**
 * @description Centralized configuration service for AgenticQTC.
 *              Reads the AgenticQTC_Config__mdt custom metadata record and caches it
 *              for the duration of the transaction to avoid repeated SOQL.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_ConfigService {

    private static final String DEFAULT_RECORD = 'Default';
    private static final String DEFAULT_CURRENCY = 'USD';
    private static final String DEFAULT_MODEL = 'claude-sonnet-4-20250514';
    private static final Integer DEFAULT_MAX_ROUNDS = 5;
    private static final Integer DEFAULT_CALLOUT_TIMEOUT = 120000;

    @TestVisible
    private static AgenticQTC_Config__mdt cachedConfig;

    /**
     * @description Returns the cached AgenticQTC_Config__mdt record. Falls back to
     *              a new instance with default values if no record exists.
     * @return AgenticQTC_Config__mdt The configuration record
     */
    public static AgenticQTC_Config__mdt getConfig() {
        if (cachedConfig != null) {
            return cachedConfig;
        }
        List<AgenticQTC_Config__mdt> configs = AgenticQTC_Config__mdt.getAll().values();
        if (!configs.isEmpty()) {
            cachedConfig = configs[0];
        } else {
            cachedConfig = new AgenticQTC_Config__mdt(
                Use_CPQ_APIs__c = false,
                Default_Currency__c = DEFAULT_CURRENCY,
                Claude_Model__c = DEFAULT_MODEL,
                Max_AI_Rounds__c = DEFAULT_MAX_ROUNDS,
                Callout_Timeout__c = DEFAULT_CALLOUT_TIMEOUT
            );
        }
        return cachedConfig;
    }

    /**
     * @description Whether CPQ ServiceRouter APIs should be used instead of direct DML.
     * @return Boolean True to use CPQ APIs; false (default) for direct SOQL/DML.
     */
    public static Boolean useCpqApis() {
        return getConfig().Use_CPQ_APIs__c == true;
    }

    /**
     * @description The default ISO currency code for pricing operations.
     * @return String Currency code (e.g. 'USD')
     */
    public static String defaultCurrency() {
        String val = getConfig().Default_Currency__c;
        return String.isNotBlank(val) ? val : DEFAULT_CURRENCY;
    }

    /**
     * @description The Claude model name for AI chat.
     * @return String Model identifier
     */
    public static String claudeModel() {
        String val = getConfig().Claude_Model__c;
        return String.isNotBlank(val) ? val : DEFAULT_MODEL;
    }

    /**
     * @description Maximum number of AI tool-call round-trips.
     * @return Integer Max rounds
     */
    public static Integer maxAiRounds() {
        Decimal val = getConfig().Max_AI_Rounds__c;
        return val != null ? val.intValue() : DEFAULT_MAX_ROUNDS;
    }

    /**
     * @description HTTP callout timeout in milliseconds.
     * @return Integer Timeout in ms
     */
    public static Integer calloutTimeout() {
        Decimal val = getConfig().Callout_Timeout__c;
        return val != null ? val.intValue() : DEFAULT_CALLOUT_TIMEOUT;
    }

    /**
     * @description Resets the cached config. For testing only.
     */
    @TestVisible
    private static void resetCache() {
        cachedConfig = null;
    }
}