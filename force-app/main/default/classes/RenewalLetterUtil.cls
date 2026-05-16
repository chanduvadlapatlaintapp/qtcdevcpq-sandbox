/**
 * @author : Sahal Mohamed
 * @date : 02/12/2025
 * @description : common utilities for Renewal Letter Object
**/
public inherited sharing class RenewalLetterUtil {

    /**
    * @description set the state of the renewal letters
    * @param renLetters
    * @param state
    * @return String
    **/
    public static List<Proforma_Invoice__c> updateRenewalLetterState(List<Proforma_Invoice__c> renLetters, String state) {
        for(Proforma_Invoice__c renLetter : renLetters) {
            renLetter.State__c = state;
        }
        return renLetters;
    }
}