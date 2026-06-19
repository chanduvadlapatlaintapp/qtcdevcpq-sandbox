/**
 * @description : Service class to handle Subsidiary assignment logic for Quotes
 * @author      : Sahal Mohamed | 12-06-2024
 * @modified    : BIZ-80150 — extended to include Client - Lapsed account type
 */
public with sharing class SubsidiaryService {
    /***************************************************************************************************
     * 
     * Public Methods 
     * 
     ***************************************************************************************************/
    /**
     * @description : Updates the Quote Subsidiary based on Account Type and Country_Info__mdt via BIZ-74967 / BIZ-80150
     *                Applies to Account Types: Prospect, Client - Lapsed
     * @param newQuotes List<SBQQ__Quote__c> - List of new Quote records
     * @param oldQuotesMap Map<Id, SBQQ__Quote__c> - Old Quote records map used to detect Account changes (null in before insert)
     */
    public static void updateSubsidiary(List<SBQQ__Quote__c> newQuotes, Map<Id, SBQQ__Quote__c> oldQuotesMap) {

        Set<Id> addressIds = new Set<Id>();
        List<SBQQ__Quote__c> eligibleQuotes = new List<SBQQ__Quote__c>();
        for (SBQQ__Quote__c quote : newQuotes) {
            if (shouldCollectForSubsidiary(quote, oldQuotesMap)) {
                eligibleQuotes.add(quote);
                addressIds.add(quote.Ship_To_Address__c);
            }
        }
        if (eligibleQuotes.isEmpty() || addressIds.isEmpty()) {
            return;
        }

        // Query only the needed addresses
        Map<Id, Address__c> addressMap = queryAddresses(addressIds);
        // Assign subsidiary based on country
        assignSubsidiaryFromAddress(eligibleQuotes, addressMap);
    }

    /***************************************************************************************************************
     * 
     * Private Methods
     * 
     *************************************************************************************************************/
    /**
     * @description : Determines if the quote should be processed for Subsidiary assignment.
     *                Eligible account types: Prospect (BIZ-74967), Client - Lapsed (BIZ-80150).
     * @param quote SBQQ__Quote__c - The quote record to evaluate
     * @param oldQuotesMap Map<Id, SBQQ__Quote__c> - Old Quote records map used to detect Account changes (null in before insert)
     * @return Boolean
     */
    private static Boolean shouldCollectForSubsidiary(SBQQ__Quote__c quote, Map<Id, SBQQ__Quote__c> oldQuotesMap) {
        Boolean isAccountChanged = true;
        Boolean isShippingAddressChanged = true;
        if (oldQuotesMap != null && oldQuotesMap.containsKey(quote.Id)) {
            SBQQ__Quote__c oldQuote = oldQuotesMap.get(quote.Id);
            isAccountChanged = (oldQuote.SBQQ__Account__c != quote.SBQQ__Account__c);
            isShippingAddressChanged = (oldQuote.Ship_To_Address__c != quote.Ship_To_Address__c) && quote.Ship_To_Address__c != null;
        }
        return (quote.Account_Type__c == AccountConstants.TYPE_PROSPECT
                || quote.Account_Type__c == AccountConstants.TYPE_CLIENT_LAPSED)
            && (isAccountChanged || isShippingAddressChanged);
    }

    /**
     * @description : Retrieves a map of Address__c records by their Ids
     * @param addressIds Set<Id> - Set of Address__c record Ids to query
     * @return Map<Id, Address__c>
     */
    private static Map<Id, Address__c> queryAddresses(Set<Id> addressIds) {
        if (addressIds == null || addressIds.isEmpty()) {
            return new Map<Id, Address__c>();
        }
        return new Map<Id, Address__c>(
            [SELECT Id, Country__c, Address__c, Address__CountryCode__s FROM Address__c WHERE Id IN :addressIds]
        );
    }

    /**
     * @description : Assigns Subsidiary__c on quotes based on the shipping address country using countryToSubsidiaryMap
     * @param eligibleQuotes List<SBQQ__Quote__c> - List of eligible quotes to assign subsidiary
     * @param addressMap Map<Id, Address__c> - Map of Address__c records by Id
     */
    private static void assignSubsidiaryFromAddress(List<SBQQ__Quote__c> eligibleQuotes, Map<Id, Address__c> addressMap) {
        if (eligibleQuotes == null || eligibleQuotes.isEmpty() || addressMap == null || addressMap.isEmpty()) {
            return;
        }
        for (SBQQ__Quote__c quote : eligibleQuotes) {
            Address__c address = addressMap.get(quote.Ship_To_Address__c);
            if (address == null) {
                continue;
            }
            String shippingCountry = address.Country__c;
            System.debug('Shipping country: ' + shippingCountry);
            if (String.isNotBlank(shippingCountry) && countryToSubsidiaryMap.containsKey(shippingCountry.trim())) {
                quote.Subsidiary__c = countryToSubsidiaryMap.get(shippingCountry.trim());
            }
        }
    }

    /***********************************************************************************************
    *
    * Getter methods
    *
    ***********************************************************************************************/
    /** @description   : Retrieves a map of Country_Label__c to Subsidiary__c from Country_Info__mdt.
     *                  Used by updateSubsidiary to determine the correct Subsidiary based on Account Shipping Country.
     * @return        : Map<String, String> - Map of Country labels to Subsidiary values.
     */
    private static Map<String, String> countryToSubsidiaryMap {
        get {
            if (countryToSubsidiaryMap == null) {
                countryToSubsidiaryMap = new Map<String, String>();
                for (Country_Info__mdt countryInfo : [
                    SELECT Country_Label__c, Subsidiary__c 
                    FROM Country_Info__mdt 
                    WHERE Subsidiary__c != null
                ]) {
                    countryToSubsidiaryMap.put(countryInfo.Country_Label__c, countryInfo.Subsidiary__c);
                }
            }
            return countryToSubsidiaryMap;
        }
        set;
    }
}