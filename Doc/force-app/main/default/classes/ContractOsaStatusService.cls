/********************************************************************************
*  Name             :  ContractOsaStatusService
*  Author           :  Sahal Mohamed
*  Description      :  Service class for BIZ-68170 — OSA Status on the Contract object.
*                      Handles three concerns:
*                        1. Sync OSA Status across all contracts sharing the same OSA Number.
*                        2. Calculate and set CPQ Contract Status (Not Started / Active / Lapsed)
*                           based on dates and OSA Status.
*                        3. Propagate Superseded_by_OSA__c across sibling contracts.
*
*  Change history   :
*  Date          Author            Description
*  27/02/26      Sahal Mohamed     Created (BIZ-68170)
********************************************************************************/
public without sharing class ContractOsaStatusService {

    /*****************************************************************************************
    *
    *  Public Methods
    *
    ******************************************************************************************/

    /**
     * @description Entry point called from after-update trigger context.
     *              Detects OSA Status changes and Superseded_by_OSA changes,
     *              then propagates to sibling contracts sharing the same OSA Number.
     * @param newContracts List of updated Contract records
     * @param oldContractMap Map of old Contract records keyed by Id
     */
    public static void syncOsaSiblings(List<Contract> newContracts, Map<Id, Contract> oldContractMap) {
        Map<String, Contract> osaStatusChanges = new Map<String, Contract>();
        Map<String, Id> osaSupersedeChanges = new Map<String, Id>();

        // P1 fix: only track IDs of contracts that originated a change, not all of Trigger.new.
        // This ensures that other contracts in the same bulk DML sharing the OSA Number
        // are still picked up as siblings and receive propagated values.
        Set<Id> sourceIds = new Set<Id>();

        for (Contract newCon : newContracts) {
            Contract oldCon = oldContractMap.get(newCon.Id);
            if (String.isBlank(newCon.OSA_Number__c)) {
                continue;
            }

            Boolean isSource = false;

            if (newCon.Status != oldCon.Status) {
                osaStatusChanges.put(newCon.OSA_Number__c, newCon);
                isSource = true;
            }

            if (newCon.Superseded_by_OSA__c != oldCon.Superseded_by_OSA__c) {
                osaSupersedeChanges.put(newCon.OSA_Number__c, newCon.Superseded_by_OSA__c);
                isSource = true;
            }

            if (isSource) {
                sourceIds.add(newCon.Id);
            }
        }

        if (osaStatusChanges.isEmpty() && osaSupersedeChanges.isEmpty()) {
            return;
        }

        Set<String> allOsaNumbers = new Set<String>();
        allOsaNumbers.addAll(osaStatusChanges.keySet());
        allOsaNumbers.addAll(osaSupersedeChanges.keySet());

        List<Contract> siblings = [
            SELECT Id, OSA_Number__c, Status, CPQ_Contract_Status__c,
                   StartDate, EndDate, Superseded_by_OSA__c,
                   OP4I_Contract_Id__c, OP4I_Error__c
            FROM Contract
            WHERE OSA_Number__c IN :allOsaNumbers
              AND Id NOT IN :sourceIds
        ];

        if (siblings.isEmpty()) {
            return;
        }

        // P2 fix: capture pre-update state so we can publish integration events
        // after the DML. The recursion guard in ContractTriggerHandler prevents
        // publishEligibleSobjectRecords from firing in the nested trigger context.
        // Re-query with all fields so isChanged() can access any Field_Tracking__mdt-tracked
        // field without SObjectException — the siblings query above only carries 8 fields.
        Set<Id> siblingIdSet = (new Map<Id, Contract>(siblings)).keySet();
        String oldStateQuery = ContractTriggerHelper.createQuery('Contract', siblingIdSet);
        String oldStateBound = oldStateQuery.replace('setOfsObjectIds', 'siblingIdSet');
        List<Contract> siblingsAllFields = Database.query(oldStateBound);
        Map<Id, Contract> siblingOldMap = new Map<Id, Contract>();
        for (Contract sib : siblingsAllFields) {
            siblingOldMap.put(sib.Id, sib.clone(true, true));
        }

        List<Contract> toUpdate = new List<Contract>();

        for (Contract sibling : siblings) {
            Boolean changed = false;

            // 1. Sync OSA Status
            if (osaStatusChanges.containsKey(sibling.OSA_Number__c)) {
                Contract source = osaStatusChanges.get(sibling.OSA_Number__c);
                if (sibling.Status != source.Status) {
                    sibling.Status = source.Status;
                    changed = true;
                }
            }

            // 2. Propagate Superseded_by_OSA
            if (osaSupersedeChanges.containsKey(sibling.OSA_Number__c)) {
                Id newSupersededId = osaSupersedeChanges.get(sibling.OSA_Number__c);
                if (sibling.Superseded_by_OSA__c != newSupersededId) {
                    sibling.Superseded_by_OSA__c = newSupersededId;
                    changed = true;
                }
            }

            // 3. Recalculate CPQ Contract Status for the sibling
            String newCpqStatus = calculateCpqStatus(sibling.Status, sibling.StartDate, sibling.EndDate);
            if (sibling.CPQ_Contract_Status__c != newCpqStatus) {
                sibling.CPQ_Contract_Status__c = newCpqStatus;
                changed = true;
            }

            if (changed) {
                toUpdate.add(sibling);
            }
        }

        updateSiblings(toUpdate, siblingOldMap);
    }

    /**
     * @description Calculates and stamps CPQ Contract Status on contracts being inserted or
     *              whose Status / dates have changed. Runs in before-insert and before-update context.
     * @param newContracts List of Contract records in trigger context
     * @param oldContractMap Map of old Contract records (null for insert context)
     */
    public static void setCpqContractStatus(List<Contract> newContracts, Map<Id, Contract> oldContractMap) {
        for (Contract con : newContracts) {
            Boolean isInsert = (oldContractMap == null);
            Boolean statusChanged = false;
            Boolean dateChanged = false;

            if (!isInsert) {
                Contract oldCon = oldContractMap.get(con.Id);
                statusChanged = (con.Status != oldCon.Status);
                dateChanged = (con.StartDate != oldCon.StartDate || con.EndDate != oldCon.EndDate);
            }

            if (isInsert || statusChanged || dateChanged) {
                con.CPQ_Contract_Status__c = calculateCpqStatus(con.Status, con.StartDate, con.EndDate);
            }
        }
    }

    /**
     * @description Recalculates CPQ Contract Status for a list of contracts based on current date.
     *              Used by the daily schedulable batch.
     * @param contracts List of Contract records to evaluate
     * @return List of Contract records that had their status changed
     */
    public static List<Contract> recalculateCpqStatusByDate(List<Contract> contracts) {
        List<Contract> changed = new List<Contract>();
        for (Contract con : contracts) {
            String newStatus = calculateCpqStatus(con.Status, con.StartDate, con.EndDate);
            if (con.CPQ_Contract_Status__c != newStatus) {
                con.CPQ_Contract_Status__c = newStatus;
                changed.add(con);
            }
        }
        return changed;
    }

    /*****************************************************************************************
    *
    *  Private Methods
    *
    ******************************************************************************************/

    /**
     * @description Core calculation for CPQ Contract Status.
     *              Priority: OSA Status override > date-based logic.
     * @param osaStatus The current OSA Status (Contract.Status) value
     * @param startDate The contract start date
     * @param endDate The contract end date
     * @return The calculated CPQ Contract Status value
     */
    @TestVisible
    private static String calculateCpqStatus(String osaStatus, Date startDate, Date endDate) {
        // If OSA Status indicates cancellation/supersession, always Lapsed
        if (ContractConstants.LAPSED_TRIGGER_STATUSES.contains(osaStatus)) {
            return ContractConstants.CPQ_STATUS_LAPSED;
        }

        Date today = Date.today();

        // Date-based logic
        if (startDate != null && today < startDate) {
            return ContractConstants.CPQ_STATUS_NOT_STARTED;
        }
        if (endDate != null && today > endDate) {
            return ContractConstants.CPQ_STATUS_LAPSED;
        }
        if (startDate != null && endDate != null && today >= startDate && today <= endDate) {
            return ContractConstants.CPQ_STATUS_ACTIVE;
        }

        // Fallback: if dates are missing, derive from status
        if (startDate == null && endDate == null) {
            return null;
        }
        if (startDate != null && endDate == null && today >= startDate) {
            return ContractConstants.CPQ_STATUS_ACTIVE;
        }

        return null;
    }

    /*****************************************************************************************
    *
    *  DML Methods
    *
    ******************************************************************************************/

    /**
     * @description Updates sibling contracts with error logging via Nebula Logger.
     *              After a successful DML, publishes integration events for siblings
     *              since the recursion guard skips publishEligibleSobjectRecords in
     *              the nested trigger context.
     * @param siblings List of Contract records to update
     * @param siblingOldMap Map of sibling contracts' pre-update state for integration publishing
     */
    private static void updateSiblings(List<Contract> siblings, Map<Id, Contract> siblingOldMap) {
        if (siblings == null || siblings.isEmpty()) {
            return;
        }

        try {
            update siblings;
            publishSiblingIntegrationEvents(siblings, siblingOldMap);
        } catch (Exception e) {
            Nebula.Logger.error(
                'ContractOsaStatusService.updateSiblings: Error syncing OSA sibling contracts'
            ).addTag('BIZ-68170');
            Nebula.Logger.error(e.getMessage(), e);
        } finally {
            Nebula.Logger.saveLog();
        }
    }

    /**
     * @description Publishes integration events for sibling contracts after OSA sync.
     *              Required because the firstCallUpdate recursion guard in ContractTriggerHandler
     *              prevents publishEligibleSobjectRecords from firing in the nested trigger context.
     *              Siblings are re-queried with all fields so that IntegrationUtility.isChanged()
     *              can safely access any Field_Tracking__mdt-tracked field without an SObjectException.
     * @param siblings List of updated sibling Contract records
     * @param siblingOldMap Map of sibling contracts' pre-update state
     */
    private static void publishSiblingIntegrationEvents(List<Contract> siblings, Map<Id, Contract> siblingOldMap) {
        Set<Id> eligibleIds = new Set<Id>();
        for (Contract sib : siblings) {
            if (sib.OP4I_Contract_Id__c != null || sib.OP4I_Error__c != null) {
                eligibleIds.add(sib.Id);
            }
        }
        if (eligibleIds.isEmpty()) {
            return;
        }
        // Re-query with all fields so isChanged() can access any tracked field.
        // The original sibling records only carry the fields selected in syncOsaSiblings,
        // which caused SObjectException when isChanged() accessed unqueried tracked fields.
        String soql = ContractTriggerHelper.createQuery('Contract', eligibleIds);
        String soqlBound = soql.replace('setOfsObjectIds', 'eligibleIds');
        List<Contract> eligibleContracts = Database.query(soqlBound);
        IntegrationUtility.publishEligibleSobjectRecords(eligibleContracts, siblingOldMap, 'Contract');
    }
}