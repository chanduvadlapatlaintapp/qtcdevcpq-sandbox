/********************************************************************************
*  Name             :  CpqContractStatusBatch
*  Author           :  Sahal Mohamed
*  Description      :  Schedulable batch that recalculates CPQ Contract Status
*                      for active contracts whose date-based status may have changed
*                      overnight (e.g. Not Started → Active, Active → Lapsed).
*
*  Change history   :
*  Date          Author            Description
*  27/02/26      Sahal Mohamed     Created (BIZ-68170)
********************************************************************************/
public without sharing class CpqContractStatusBatch implements Database.Batchable<SObject>, Schedulable {

    /*****************************************************************************************
    *
    *  Schedulable Interface
    *
    ******************************************************************************************/

    /**
     * @description Schedulable execute — kicks off the batch with default scope size.
     * @param sc SchedulableContext
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CpqContractStatusBatch(), 200);
    }

    /*****************************************************************************************
    *
    *  Batchable Interface
    *
    ******************************************************************************************/

    /**
     * @description Queries contracts that might need a CPQ Contract Status transition today.
     *              Targets contracts where:
     *                - CPQ status is Not Started and today >= StartDate (should become Active)
     *                - CPQ status is Active and today > EndDate (should become Lapsed)
     *                - CPQ status is null (needs initial calculation)
     * @param bc BatchableContext
     * @return Database.QueryLocator
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Status, CPQ_Contract_Status__c, StartDate, EndDate
            FROM Contract
            WHERE (CPQ_Contract_Status__c = :ContractConstants.CPQ_STATUS_NOT_STARTED
                   AND StartDate <= :today)
               OR (CPQ_Contract_Status__c = :ContractConstants.CPQ_STATUS_ACTIVE
                   AND EndDate < :today)
               OR (CPQ_Contract_Status__c = null)
        ]);
    }

    /**
     * @description Recalculates CPQ Contract Status for each contract in the batch scope.
     * @param bc BatchableContext
     * @param contracts List of Contract records
     */
    public void execute(Database.BatchableContext bc, List<Contract> contracts) {
        List<Contract> changed = ContractOsaStatusService.recalculateCpqStatusByDate(contracts);

        if (!changed.isEmpty()) {
            List<Database.SaveResult> results = Database.update(changed, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    Nebula.Logger.error(
                        'CpqContractStatusBatch: Failed to update Contract ' + changed[i].Id
                    ).addTag('BIZ-68170').setRecordId(changed[i].Id);
                    for (Database.Error err : results[i].getErrors()) {
                        Nebula.Logger.error(err.getMessage());
                    }
                }
            }
            Nebula.Logger.saveLog();
        }
    }

    /**
     * @description Batch finish — no-op.
     * @param bc BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
    }
}