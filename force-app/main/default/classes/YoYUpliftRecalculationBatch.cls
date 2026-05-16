/**
 * @description Batch job to recalculate YoY Uplift values for all Quote records.
 *              Populates Min_YoY_Uplift_Calculated__c and Max_YoY_Uplift_Calculated__c
 *              using net software totals (after one-time credits).
 * 
 * Usage:
 *   YoYUpliftRecalculationBatch batch = new YoYUpliftRecalculationBatch();
 *   Database.executeBatch(batch, 200);
 */
public class YoYUpliftRecalculationBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    private Integer recordsProcessed = 0;
    private Integer recordsFailed = 0;
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, First_Year_Software_Total__c, One_time_Credit_Yr1__c, ' +
            'Second_Year_Software_Total__c, One_time_Credit_Yr2__c, ' +
            'Third_Year_Software_Total__c, One_time_Credit_Yr3__c, ' +
            'Fourth_Year_Software_Total__c, One_time_Credit_Yr4__c, ' +
            'Fifth_Year_Software_Total__c, One_time_Credit_Yr5__c, ' +
            'Sixth_Year_Software_Total__c, One_time_Credit_Yr6__c, ' +
            'Min_YoY_Uplift__c, Max_YoY_Uplift__c ' +
            'FROM SBQQ__Quote__c'
        );
    }

    public void execute(Database.BatchableContext bc, List<SBQQ__Quote__c> scope) {
        QuoteTriggerHelper.calculateYoYUplift(scope);
        
        List<Database.SaveResult> results = Database.update(scope, false);
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                recordsProcessed++;
            } else {
                recordsFailed++;
                for (Database.Error err : sr.getErrors()) {
                    System.debug('Error updating Quote: ' + err.getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('=== YoY Uplift Recalculation Complete ===');
        System.debug('Records processed successfully: ' + recordsProcessed);
        System.debug('Records failed: ' + recordsFailed);
    }
}