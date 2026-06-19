/**
* @description       : This class is a Helper class for Ghost_QuoteLine_Rec_TriggerHandler.
* @author            : Ratan Paul
* Created Date       : Mar-20-2025
**/
public inherited sharing class Ghost_QuoteLine_Rec_TriggerHelper {
	/**
    * @description	:Update the Opp Lines using ghost QuoteLine JSON data.
    * @author     	:Ratan Paul | 09-09-2025, BIZ-73446
    * @param		:lstGhostQLines - List of deleted Quote records
    * @return       :void
    */
    public static void updateOppLines(List<Ghost_QuoteLine_Reconciliation__c> lstGhostQLines) {
        List<OpportunityLineItem> lstOLIUpdates = new List<OpportunityLineItem>();
        for(Ghost_QuoteLine_Reconciliation__c gQL:lstGhostQLines){
            OpportunityLineItem objOLI = (OpportunityLineItem)JSON.deserialize(gQL.OLI_Field_Payload__c, OpportunityLineItem.Class);
            objOLI.Id = gQL.OpportunityLineItem_Id__c;
            lstOLIUpdates.add(objOLI);
        }
        update lstOLIUpdates;
    }
}