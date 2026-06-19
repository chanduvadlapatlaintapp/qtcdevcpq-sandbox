/**
 * @description This class is used to handle the Opportunity Trigger functionality
 */
public with sharing class OpportunityTriggerHelper {
   
    /***********************************************************************************************
    *
    * Props
    *
    ***********************************************************************************************/
    private static Boolean firstCall = false;
    private static Integer iRunCount = 0;

    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
   /**
     * @description Update Account Type to 'Client' if Associated Opportunity is Closed Won.
     * @param newOpportunities : List of new Opportunity records.
     * BIZ-68167: Scenaio 1
     * When the Account type = “Prospect” and stage is moved to “Closed Won”, Update Contract Status to ‘In Force(already being set by other automation)
     * and Set AccountType = 'Client'
     */
    public static void updateAccountType(List<Opportunity> newOpportunities){
        Set<Id> relatedAccountIds = new Set<Id>();
        for(Opportunity opp : newOpportunities) {
            if (opp.StageName == OpportunityConstants.STAGE_CLOSED_WON && 
                opp.AccountId != null) {
                relatedAccountIds.add(opp.AccountId);
            }
        }
    
        if (relatedAccountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> prospectAccountsWithClosedWonOpp = getProspectAccountsWithClosedWonOpps(relatedAccountIds);

        List<Account> accountsToUpdate = new List<Account>();
        for (Account account : prospectAccountsWithClosedWonOpp.values()) {
            if (!account.Opportunities.isEmpty()) {
                account.Type = AccountConstants.TYPE_CLIENT;
                accountsToUpdate.add(account);
            }
        }

        try {
            update accountsToUpdate;
        } catch (Exception e) {
            Nebula.Logger.error('OpportunityTriggerHelper.updateAccountType', accountsToUpdate, e);
        } finally {
            Nebula.Logger.saveLog();
        }   
    }
    
    /**
    * @description Updates the Opportunity with the related Account and Contract fields
    * @param newOpportunities
    * BIZ-68167: Scenario 3
    * 1. Update Contract Status to ‘Cancelled / Lapsed’ when oppty stage is set ‘closed lost’ and Oppty.deal_type__c = ‘renewal’
    * 2. Update Account Type to ‘Cancelled / Lapsed’ when no active contract exists
    */
    public static void cancelContractAndAccounts(List<Opportunity> newOpportunities) {
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : newOpportunities) {
            if (opp.StageName == OpportunityConstants.STAGE_CLOSED_LOST && 
                opp.Deal_Type__c == OpportunityConstants.TYPE_RENEWAL) {
                opportunityIds.add(opp.Id);
                accountIds.add(opp.AccountId);
            }
        }
    
        if (opportunityIds.isEmpty()) { return; }
    
        Map<Id, Integer> activeContractCountMap = ContractUtil.getActiveContractCountOnAccount(accountIds);
        List<Opportunity> opportunitiesWithRelatedData = getOpportunityRelatedData(opportunityIds);
    
        List<Contract> contractsToUpdate = getContractsToUpdate(opportunitiesWithRelatedData);
        List<Account> accountsToUpdate = getAccountsToUpdate(opportunitiesWithRelatedData, activeContractCountMap);
    

        try {
            update contractsToUpdate;
            update accountsToUpdate;
        } catch (Exception e) {
            Nebula.Logger.error('OpportunityTriggerHelper.cancelContractAndAccounts', e);
        }
        finally {
            Nebula.Logger.saveLog();
        }  
    }
    
    /**
     * @description Sets renewal opportunities to Qualify stage on insert
     * @param opportunities List of Opportunity records
     * @jira BIZ-80539
     */
    public static void setRenewalStageToQualify(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }

        for (Opportunity opp : opportunities) {
            if (OpportunityUtil.isRenewalOpp(opp) &&
                !OpportunityConstants.CLOSED_STAGES.contains(opp.StageName)) {
                opp.StageName = OpportunityConstants.STAGE_QUALIFY;
            }
        }
    }

    /**
     * @description Mark the Opportunity's associated Project as out of sync
     * @param opportunities List of Opportunity records
     */
    public static void markProjectOutOfSync(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }
        
        for (Opportunity opp : opportunities) {
            opp.Project_in_sync__c = false;
        }
    }

    /**
     * @description Publish Opportunity records that are not Migration Opportunities
     * @param records List of Opportunity records
     * @update - Added Op4i Deal Id and Deal Type Check as part of BIZ-74650
     */
    public static void publishNonMigrationOpportunities(List<Opportunity> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        List<Opportunity> opportunityItemList = new List<Opportunity>();
        Id oppRecordTypeId = RecordTypeUtil.getRecordTypeId(Opportunity.sObjectType, OpportunityConstants.RT_MIGRATION_OPP);
		
        for (Opportunity oppObj : records) {
            Boolean isEligibleDealType = allowedDealTypes.contains(oppObj.Deal_Type__c);
        	Boolean hasOP4IDealId = String.isNotBlank(oppObj.OP4I_Deal_ID__c);
            Boolean isSimplifiedQuoting = oppObj.Created_by_Simplified_Quoting__c == true;
            if (oppObj.RecordTypeId != oppRecordTypeId && (isEligibleDealType || hasOP4IDealId || isSimplifiedQuoting)) {
                opportunityItemList.add(oppObj);
            }
        }

        if (!opportunityItemList.isEmpty()) {
            IntegrationUtility.publishEligibleSobjectRecords(records, null, 'Opportunity');
        }
    }
    
    /**
    * @description Sets CloseDate on creation of Renewal Opportunities (after insert only)
    * @param records List of Opportunity records
    */
    public static void setCloseDateAfterInsert(List<Opportunity> opps) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        
        for (Opportunity opp : opps) {
            if (OpportunityUtil.isRenewalOpp(opp)) {
                
                Date computedDate = opp.Renewal_Start_Date__c != null
                    ? opp.Renewal_Start_Date__c.addDays(-30)
                    : System.today().addDays(-30);
                
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    CloseDate = computedDate
                ));
            }
        }
        
        if (!oppsToUpdate.isEmpty()) {
            try {
                update oppsToUpdate;
            } catch (Exception e) {
                Nebula.Logger.error('OpportunityTriggerHelper.setCloseDateAfterInsert', oppsToUpdate, e);
            }
        }
    }
    
    
    
    /**
    * @description Sets CloseDate on creation/updation of NYMY Opportunities (after insert/up only) - BIZ-76798
    * @param records List of Opportunity records
    */
    public static void setNYMYCloseDateAfterInsert(List<Opportunity> opps, Map<Id, Opportunity> existingRecords) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        
        for (Opportunity opp : opps) {
            if (OpportunityUtil.isNYMYOpp(opp)
               && (existingRecords == null || (existingRecords != null && opp.StageName != existingRecords.get(opp.Id).StageName))){
                
                Date nymyDate = opp.Quote_Start_Date__c != null
                    ? opp.Quote_Start_Date__c
                    : System.today();
                
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    CloseDate = nymyDate
                ));
            }
        }
        
        if (!oppsToUpdate.isEmpty()) {
            try {
                update oppsToUpdate;
            } catch (Exception e) {
                Nebula.Logger.error('OpportunityTriggerHelper.setNYMYCloseDateAfterInsert', oppsToUpdate, e);
            }
        }
    }

    /**
     * @description Processes the Opportunity records
     * @param records List of Opportunity records
     * @param existingRecords Map of Opportunity records
     */
    public static void processOpportunities(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        if (records == null || records.isEmpty()) {
            return;
        }

        Id migrationRecordTypeId = RecordTypeUtil.getRecordTypeId(Opportunity.sObjectType, OpportunityConstants.RT_MIGRATION_OPP);

        List<Opportunity> cancellationOpps = getLegalCancellationOpps(records, existingRecords);
        List<Opportunity> nonMigrationOpps = getNonMigrationOpps(records, migrationRecordTypeId);
        List<Opportunity> amendedOpps = getAmendedOpps(records, existingRecords);
        Map<String, Date> renewalOppDateMap = getRenewalOpps(records, existingRecords);

        if (!renewalOppDateMap.isEmpty() && !System.isBatch()) {
            updateOppCloseDateAtFuture(renewalOppDateMap);
        }

        if (!nonMigrationOpps.isEmpty()) {
            publishOpportunities(nonMigrationOpps, existingRecords);
        }

        if (!amendedOpps.isEmpty()) {
            handleAmendedOpportunities(amendedOpps);
        }

        // Optionally call other removed/disabled logic
        // updateOPCTypes();
        // contactRoleValidationForDNBProducts(existingRecords);
    }

    /**
     * @description Sends an email to the Sales team when an Opportunity is deleted
     * @param opps List of Opportunity records
     */
    public static void sendOpportunityDeletionNotification(List<Opportunity> opps) {
        if (opps == null || opps.isEmpty()) {
            return;
        }

        // Collect email addresses of users who should be notified
        List<String> toAddresses = new List<String>();
        for (User u : [SELECT Email FROM User WHERE Opportunity_Deletion_Notification__c = true AND IsActive = true]) {
            if (String.isNotBlank(u.Email)) {
                toAddresses.add(u.Email);
            }
        }

        if (!toAddresses.isEmpty()) {
            // Compose email message
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted');
            mail.setSaveAsActivity(false);

            String textBody = UserInfo.getName() + ' (' + UserInfo.getUserEmail() + ') deleted the following opportunities:\n';
            for (Opportunity opp : opps) {
                textBody += '\n  - ' + opp.Name;
            }

            mail.setPlainTextBody(textBody);

            // Log and send the email
            System.debug('#### OpportunityNotificationUtil - Sending notifications to: ' + toAddresses);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail }, false);
        }
    }

    /**
     * @description Updates the Opportunity fields when the stage changes
     * @param records List of Opportunity records
     * @param existingRecords Map of Opportunity records   
     */
    public static void updateOpportunityFieldsOnStageChange(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        if (records == null || existingRecords == null) {
            return;
        }

        for (Opportunity record : records) {
            Opportunity oldOpp = existingRecords.get(record.Id);
            if (oldOpp == null) {
                continue; // skip if no matching old record
            }

            // Logic: Reset Project sync flag on first-time close-won
            if (!oldOpp.IsWon && record.IsClosed && record.IsWon) {
                record.Project_in_sync__c = false;
            }

            // Logic: Capture previous stage when stage changes
            if (record.StageName != oldOpp.StageName) {
                record.Previous_stage__c = oldOpp.StageName;
            }
        }
    }

    /**
     * @description Cancels Initiated Renewal Letters linked to Renewal Opportunities that
     *              transition to a closed stage that should cancel the RL.
     *              Renewal Letters in 'Working with Customer for changes' are intentionally
     *              excluded by the Initiated-only filter.
     * @param records List of new Opportunity records
     * @param existingRecords Map of old Opportunity records
     * @jira BIZ-82773
     */
    public static void cancelRenewalLettersOnOppClose(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        if (records == null || records.isEmpty() || existingRecords == null) {
            return;
        }

        Set<Id> qualifyingOppIds = new Set<Id>();
        for (Opportunity opp : records) {
            Opportunity oldOpp = existingRecords.get(opp.Id);
            if (oldOpp == null) { continue; }
            if (OpportunityUtil.isRenewalOpp(opp) &&
                opp.StageName != oldOpp.StageName &&
                OpportunityConstants.RL_CANCEL_STAGES.contains(opp.StageName)) {
                qualifyingOppIds.add(opp.Id);
            }
        }

        if (qualifyingOppIds.isEmpty()) { return; }

        List<Proforma_Invoice__c> rlsToCancel = [
            SELECT Id, Status__c
            FROM Proforma_Invoice__c
            WHERE Renewal_Quote__r.SBQQ__Opportunity2__c IN :qualifyingOppIds
            AND Status__c = :RenewalLetterConstants.STATUS_INITIATED
        ];

        if (rlsToCancel.isEmpty()) { return; }

        for (Proforma_Invoice__c rl : rlsToCancel) {
            rl.Status__c = RenewalLetterConstants.STATUS_CANCELLED;
        }

        try {
            update rlsToCancel;
        } catch (Exception e) {
            Nebula.Logger.error('OpportunityTriggerHelper.cancelRenewalLettersOnOppClose', rlsToCancel, e);
        } finally {
            Nebula.Logger.saveLog();
        }
    }

    /**
     * @description Sets the Close Date to today if the Opportunity is Won and not a Renewal
     * @param opps List of Opportunity records
     * @param oldOpps Map of existing Opportunity records
     */
    public static void setCloseDate(List<Opportunity> opps, Map<Id, Opportunity> oldOpps) {
        for(Opportunity opp : opps) {
            Opportunity oldOpp = oldOpps.get(opp.Id);
            if (opp.IsWon && opp.IsWon != oldOpp.IsWon && !OpportunityUtil.isRenewalOpp(opp) && 
                (opp.CloseDate >= System.today() || opp.CloseDate == null)) {
                opp.CloseDate = System.today();
            }
        }
    }

    /***********************************************************************************************
    *
    * Private Methods
    *
    ***********************************************************************************************/
    /**
     * @description get a list of contract to update based on the Opportunity
     * @param opportunities
     * @return List<Contract>
     *  */    
    private static List<Contract> getContractsToUpdate(List<Opportunity> opportunities) {
        List<Contract> contractsToUpdate = new List<Contract>();
        for (Opportunity opp : opportunities) {
            if (opp.SBQQ__RenewedContract__r != null) {
                contractsToUpdate.add(new Contract(
                    Id = opp.SBQQ__RenewedContract__r.Id,
                    Status = ContractConstants.STATUS_CANCELLED_LAPSED
                ));
            }
        }
        return contractsToUpdate;
    }
    
    /**
     * @description Update Account Type to ‘Cancelled / Lapsed’ when no active contract exists
     * @param opportunities
     * @param activeContractCountMap
     * @return List<Account>
     */
    private static List<Account> getAccountsToUpdate(List<Opportunity> opportunities, Map<Id, Integer> activeContractCountMap) {
        List<Account> accountsToUpdate = new List<Account>();
        for (Opportunity opp : opportunities) {
            if (!activeContractCountMap.containsKey(opp.AccountId) || activeContractCountMap.get(opp.AccountId) < 1) {
                accountsToUpdate.add(new Account(
                    Id = opp.Account.Id,
                   Type = AccountConstants.TYPE_CLIENT_LAPSED 
                ));
            }
        }
        return accountsToUpdate;
    }

    /**
     * @description Returns the Opportunity related data.
     * @param opportunityIds
     * @return List<Opportunity> 
     */
    private static List<Opportunity> getOpportunityRelatedData(Set<Id> opportunityIds){
        List<Opportunity> opportunityWithRelatedData = new List<Opportunity>(
            [SELECT Id, 
                StageName, 
                Deal_Type__c,
                SBQQ__RenewedContract__r.Id, 
                SBQQ__RenewedContract__r.Status, 
                Account.Id,
                Account.Type
             FROM Opportunity
             WHERE Id IN :opportunityIds
             AND StageName = :OpportunityConstants.STAGE_CLOSED_LOST
             AND Deal_Type__c = :OpportunityConstants.TYPE_RENEWAL]
        );

        return opportunityWithRelatedData;
    }

    /**
     * @description Returns the prospect accounts with a closed won opportunity.
     * @param accountIds
     * @return Map<Id, Account>
     */
    private static Map<Id, Account> getProspectAccountsWithClosedWonOpps(Set<Id> accountIds) {
        return new Map<Id, Account>([
            SELECT Id, Type,
                (SELECT Id FROM Opportunities WHERE StageName = :OpportunityConstants.STAGE_CLOSED_WON LIMIT 1)
            FROM Account
            WHERE Id IN :accountIds
            AND Type = :AccountConstants.TYPE_PROSPECT
        ]);
    }
    
    /**
     * @description Returns the opps that need to be updated.
     * @param records : List of SObject records.
     * @param existingRecords : Map of SObject records.
     * @return List<Opportunity>
     */
    private static List<Opportunity> getLegalCancellationOpps(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        List<Opportunity> result = new List<Opportunity>();
        for (Opportunity opp : records) {
            Opportunity oldOpp = existingRecords.get(opp.Id);
            if (oldOpp != null && opp.IsWon && opp.IsWon != oldOpp.IsWon &&
                OpportunityConstants.RT_LEGAL_CANCELLATION.equals(opp.RecordType.DeveloperName)) {
                result.add(opp);
            }
        }
        return result;
    }

    /**
     * @description Returns the non-migration opps.
     * @param records : List of SObject records.
     * @param migrationRecordTypeId : Id of the migration record type.
     * @return List<Opportunity>
     */
    private static List<Opportunity> getNonMigrationOpps(List<Opportunity> records, Id migrationRecordTypeId) {
        List<Opportunity> result = new List<Opportunity>();
        for (Opportunity opp : records) {
            if (opp.RecordTypeId != migrationRecordTypeId) {
                result.add(opp);
            }
        }
        return result;
    }

    /**
     * @description Returns the amended opps.
     * @param records : List of SObject records.
     * @param existingRecords : Map of SObject records.
     * @return List<Opportunity>
     */
    private static List<Opportunity> getAmendedOpps(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        List<Opportunity> result = new List<Opportunity>();
        for (Opportunity opp : records) {
            Opportunity oldOpp = existingRecords.get(opp.Id);
            if (oldOpp != null &&
                OpportunityUtil.isAmendmentOpp(opp) &&
                /*OpportunityUtil.isAddOnOpp(opp) &&*/
                OpportunityUtil.isClosedWon(opp) &&
                opp.StageName != oldOpp.StageName) {
                result.add(opp);
            }
        }
        return result;
    }

    /**
     * @description Returns the renewal opps.
     * @param records : List of SObject records.
     * @param existingRecords : Map of SObject records.
     * @return Map<String, Date>
     */
    private static Map<String, Date> getRenewalOpps(List<Opportunity> records, Map<Id, Opportunity> existingRecords) {
        Map<String, Date> result = new Map<String, Date>();
        for (Opportunity opp : records) {
            Opportunity oldOpp = existingRecords.get(opp.Id);
            if (oldOpp != null && opp.IsWon && opp.IsWon != oldOpp.IsWon && OpportunityUtil.isRenewalOpp(opp)) {
                result.put(String.valueOf(opp.Id), opp.Renewal_Start_Date__c.addDays(-30));
            }
        }
        return result;        
    }
    
    /**
     * @description Publishes the opportunities.
     * @param opps : List of SObject records.
     * @param existingRecords : Map of SObject records.
     * @update - Added Op4i Deal Id and Deal Type Check as part of BIZ-74650
     */
    private static void publishOpportunities(List<Opportunity> opps, Map<Id, Opportunity> existingRecords) {
        if (firstCall || opps == null || opps.isEmpty()) {
            return;
        }
    	
        List<Opportunity> filteredOpps = new List<Opportunity>();
    
        for (Opportunity opp : opps) {
            if (String.isNotBlank(opp.OP4I_Deal_ID__c) ||
                allowedDealTypes.contains(opp.Deal_Type__c) ||
                opp.Created_by_Simplified_Quoting__c == true) {
                filteredOpps.add(opp);
            }
        }
    
        if (!filteredOpps.isEmpty()) {
            firstCall = true; // Prevent multiple calls
            IntegrationUtility.publishEligibleSobjectRecords(filteredOpps, existingRecords, 'Opportunity');
        }
    }

    /**
     * @description Updates the Opportunity's Earliest_Won_Date__c field.
     * @param amendedOpps : List of SObject records.
     */
    private static void handleAmendedOpportunities(List<Opportunity> amendedOpps) {
        Set<Id> amendedIds = Pluck.ids(amendedOpps);
        if (!amendedIds.isEmpty() && iRunCount < 1) {
            iRunCount++;
            NYMYOpportunityHandler.updateNYMYOpp(amendedIds);
        }
    }

    /**
     * @description Updates the Opportunity's CloseDate
     * @param oppCloseDateMap : List of SObject records.
     */
    @future
    private static void updateOppCloseDateAtFuture(Map<String, Date> oppCloseDateMap) {
        List<Opportunity> opptyList = new List<Opportunity>();
        for(String opptyId : oppCloseDateMap.keyset()){
            Opportunity opp = new Opportunity(
                Id = Id.valueOf(opptyId), 
                CloseDate = oppCloseDateMap.get(opptyId)
            );
            opptyList.add(opp);
        }
        
        try {
            update opptyList;
        }
        catch (Exception e) {
            Nebula.Logger.error('OpportunityTriggerHelper.updateOppCloseDateAtFuture', opptyList, e);
        }
        finally {
            Nebula.Logger.saveLog();
        }
    }

    /***********************************************************************************************
    *
    * Data Getters
    *
    ***********************************************************************************************/
    // =========================================================================
    // BIZ-82935 — Renewal Hold enforcement
    // =========================================================================

    /**
     * @description Prevents a Renewal Opportunity from being moved to Closed Won
     *              while Renewal Hold (Renewals_Pause__c) is active.
     *              Called from beforeUpdate.
     * @param newOpps  List of updated Opportunity records (new values)
     * @param oldMap   Map of old Opportunity records keyed by Id
     */
    public static void blockRenewalHoldClosedWon(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            // BIZ-82935: Only applies to Renewal Opportunities (have a Renewed Contract)
            if (opp.SBQQ__RenewedContract__c == null) continue;
            if (opp.Renewals_Pause__c == true
                && opp.StageName == OpportunityConstants.STAGE_CLOSED_WON
                && oldOpp.StageName != OpportunityConstants.STAGE_CLOSED_WON) {
                opp.StageName.addError(
                    'Cannot close a Renewal Opportunity while Renewal Hold is active. Remove the hold first.'
                );
            }
        }
    }

    /**
     * @description When Renewal Hold is checked (false → true) on a Renewal Opportunity,
     *              sets related Renewal Letter (Proforma_Invoice__c) Status to
     *              "Working with Customer for changes" if one already exists.
     *              Called from afterUpdate.
     * @param newOpps  List of updated Opportunity records (new values)
     * @param oldMap   Map of old Opportunity records keyed by Id
     */
    public static void updateRenewalLetterOnHold(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            if (opp.Renewals_Pause__c == true && oldMap.get(opp.Id).Renewals_Pause__c == false) {
                oppIds.add(opp.Id);
            }
        }
        if (oppIds.isEmpty()) return;

        List<Proforma_Invoice__c> lettersToUpdate = [
            SELECT Id, Status__c
            FROM Proforma_Invoice__c
            WHERE Renewal_Quote__r.SBQQ__Opportunity2__c IN :oppIds
              AND Status__c != :RenewalLetterConstants.STATUS_WORKING_WITH_CUSTOMER
        ];

        if (lettersToUpdate.isEmpty()) return;

        for (Proforma_Invoice__c rl : lettersToUpdate) {
            rl.Status__c = RenewalLetterConstants.STATUS_WORKING_WITH_CUSTOMER;
        }

        try {
            update lettersToUpdate;
        } catch (Exception e) {
            Nebula.Logger.error(
                'OpportunityTriggerHelper.updateRenewalLetterOnHold: ' + e.getMessage(), e
            ).addTag('BIZ-82935');
            Nebula.Logger.saveLog();
        }
    }

    /**
     * @description List of allowed deal types for sync from custom metadata
     */
    private static List<String> allowedDealTypes {
        get {
            if (allowedDealTypes == null) {
                allowedDealTypes = new List<String>();
                for (Allowed_Deal_Type_For_Sync__mdt rec : Allowed_Deal_Type_For_Sync__mdt.getAll().values()) {
                    if (String.isNotBlank(rec.DeveloperName)) {
                        allowedDealTypes.add(rec.DeveloperName.trim());
                    }
                }
            }
            return allowedDealTypes;
        }
        private set;
    }

}