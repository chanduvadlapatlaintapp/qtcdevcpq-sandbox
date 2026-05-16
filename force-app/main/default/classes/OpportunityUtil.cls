/**
 * @author : Sahal Mohamed
 * @date : 02/12/2025
 * @description : common utilities for Opportunity Object
**/
public inherited sharing class OpportunityUtil {

    /***********************************************************************************************
    *
    * Util methods
    *
    ***********************************************************************************************/

    /**
    * @description Returns true opp passed in the param is an amendment opportunity
    * @param opp
    * @return Boolean
    */
    public static Boolean isAmendmentOpp(Opportunity opp) {
        return OpportunityConstants.TYPE_AMENDMENT.equals(opp.Type);
    }

    /**
    * @description Returns true opp passed in the param is a renewal opportunity
    * @param opp
    * @return Boolean
    */
    public static Boolean isRenewalOpp(Opportunity opp) {
        return OpportunityConstants.TYPE_RENEWAL.equals(opp.Type);
    }

    /**
    * @description Returns true if opp passed in the param has a deal type that should merge lines into existing NYMY
    * @param opp
    * @return Boolean
    * @jira BIZ-77189 - Added Expansion deal type to support NYMY line merging for all amendment types
    */
    public static Boolean isAddOnOpp(Opportunity opp) {
        return (
            OpportunityConstants.DEAL_TYPE_ADDON.equals(opp.Deal_Type__c) || 
            OpportunityConstants.DEAL_TYPE_UPLIFT.equals(opp.Deal_Type__c) ||
            OpportunityConstants.DEAL_TYPE_EXPANSION.equals(opp.Deal_Type__c)
        );
    }

    /**
    * @description Returns true opp passed in the param has nymy deal type
    * @param opp
    * @return Boolean
    */
    public static Boolean isNYMYOpp(Opportunity opp) {
        return OpportunityConstants.DEAL_TYPE_NYMY.equals(opp.Deal_Type__c);
    }

    /**
    * @description Returns true opp passed in the param is closed won
    * @param opp
    * @return Boolean
    */
    public static Boolean isClosedWon(Opportunity opp) {
        return OpportunityConstants.STAGE_CLOSED_WON.equals(opp.StageName);
    }
    
}