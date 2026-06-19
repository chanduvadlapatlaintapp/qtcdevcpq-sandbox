/**
 * @description Handles trigger logic for Account object across different trigger events.
 *              Implements the TriggerFunctionInterface to ensure consistency.
 *              Ensures integration logic and address updates are processed conditionally based on context.
 *              
 * @author Manisha
 * @jira BIZ-68205
 */
public class AccountsTriggerHandler implements TriggerFunctionInterface {

    private static Boolean firstcall = false;

    /**
     * @description Returns the value of the static variable `firstcall`, which prevents repeated execution.
     * @return Boolean - true if the trigger logic has already run once in the context, false otherwise.
     */
    public static Boolean firstcall() {
        return firstcall;
    }

    /**
     * @description Placeholder for before insert logic on Account records.
     * @param lstNewObject List of new SObjects being inserted.
     */
    public void beforeInsert(List<SObject> lstNewObject) {}

    /**
     * @description Placeholder for before update logic on Account records.
     * @param lstNewObject List of new SObjects after update.
     * @param mapNewObject Map of updated SObjects by Id.
     * @param lstOldObject List of old SObjects before update.
     * @param mapOldObject Map of old SObjects by Id.
     */
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
     * @description Placeholder for before delete logic on Account records.
     * @param lstOldObject List of SObjects being deleted.
     * @param mapOldObject Map of old SObjects by Id.
     */
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
     * @description Handles after insert logic to update address details for Account.
     *              Integration logic is not triggered during insert.
     * @param lstNewObject List of newly inserted Account records.
     * @param mapNewObject Map of new Account records by Id.
     */
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        // Added via BIZ-68205
        AddressTriggerHelper.handleAccountAddressChange((List<Account>) lstNewObject, null);
    }

    /**
     * @description Handles after update logic for Account.
     *              Invokes address change handling and publishes integration events if applicable.
     * @param lstNewObject List of updated Account records.
     * @param mapNewObject Map of updated Account records by Id.
     * @param lstOldObject List of old Account records before update.
     * @param mapOldObject Map of old Account records by Id.
     */
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
        // Added via BIZ-68205
        AddressTriggerHelper.handleAccountAddressChange((List<Account>) lstNewObject, (Map<Id, Account>) mapOldObject);
        handlePublishandAccountUpdate((List<Account>) lstNewObject, (Map<Id, Account>) mapOldObject);
    }

    /**
     * @description Placeholder for after delete logic on Account records.
     * @param lstOldObject List of deleted SObjects.
     * @param mapOldObject Map of old SObjects by Id.
     */
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {}

    /**
     * @description Placeholder for after undelete logic on Account records.
     * @param lstNewObject List of undeleted SObjects.
     * @param mapNewObject Map of undeleted SObjects by Id.
     */
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {}

    /**
     * @description Publishes Account records to external systems and triggers post-update integration events.
     *              Skips execution if the trigger was already processed (`firstcall`) or if executed by integration user.
     * @param accountList List of updated Account records.
     * @param accountOldMap Map of old Account records by Id.
     */
    public static void handlePublishandAccountUpdate(List<Account> accountList, Map<Id, Account> accountOldMap) {
        String integrationUsername = System.Label.Integration_Username;
        String currentUser = UserInfo.getUserName();
        Boolean isOldMapValid = accountOldMap != null && !accountOldMap.isEmpty();

        if (!firstcall) {
            firstcall = true;
            if (currentUser != integrationUsername &&
                accountList != null && !accountList.isEmpty() &&
                isOldMapValid) {

                IntegrationUtility.publishEligibleSobjectRecords(accountList, accountOldMap, 'Account');
                IntegrationHandler.accountEventAfterUpdate(accountList, accountOldMap);
            }
        }
    }
}