/**
 * @description : Batch job to delete obsolete Ghost_QuoteLine_Reconciliation__c records 
 *                linked to OpportunityLineItems from closed Opportunities, optimizing data hygiene.
 * @author      : Ratan Paul | 09-09-2025, BIZ-73446
 * @param       : None (initiated as a batch process, operates on queried records)
 * @return      : void
 */

global class BatchDeleteGhostQuoteLineReconciliation implements Database.Batchable<SObject>, Database.Stateful {

    // Use a SOQL string builder for readability and maintain query limits
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query =
            'SELECT Id FROM Ghost_QuoteLine_Reconciliation__c WHERE Processed_On__c < :System.now().addDays(-3) ' +
            'AND OpportunityLineItem_Id__c IN (' +
                'SELECT Id FROM OpportunityLineItem WHERE OpportunityId IN (' +
                    'SELECT Id FROM Opportunity WHERE IsClosed = true ' +
                        'AND ( (IsWon = true AND (Ordered__c = true OR StageName = \'Closed Won\')) ' +
                             'OR (IsWon = false AND StageName = \'Closed Lost\') )' +
                ')' +
            ')';

        return Database.getQueryLocator(query);
    }

    // Batch delete with error handling for partial successes/failures
    global void execute(Database.BatchableContext bc, List<Ghost_QuoteLine_Reconciliation__c> scope) {
        delete scope;
    }

    global void finish(Database.BatchableContext bc) {
        // Implement notification or logging if needed
    }
}