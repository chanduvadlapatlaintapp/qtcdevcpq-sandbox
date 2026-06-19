/********************************************************************************
*  Name             :  ContentFilesTriggerHandler
*  Author           :  Ratan Paul
*  Description      :  Trigger handler for ContentDocumentLink.
*                      Prevents file deletion on Contract Executed quotes (BIZ-81572).
*  Change history   :
*  Date             Author              Description
*  06/05/26         Ratan Paul          Initial version via BIZ-81572
********************************************************************************/
public with sharing class ContentFilesTriggerHandler implements TriggerFunctionInterface {

    /**
     * @description Before insert handler — no action required.
     * @param lstNewObject List<SObject> new ContentDocumentLink records.
     */
    public void beforeInsert(List<SObject> lstNewObject) {
    }

    /**
     * @description Before update handler — no action required.
     * @param lstNewObject List<SObject> new ContentDocumentLink records.
     * @param mapNewObject Map<Id,Object> new ContentDocumentLink records map.
     * @param lstOldObject List<Object> old ContentDocumentLink records.
     * @param mapOldObject Map<Id,Object> old ContentDocumentLink records map.
     */
    public void beforeUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
    }

    /**
     * @description Before delete handler.
     *              Blocks deletion of files linked to Contract Executed quotes.
     *              Allows deletion for all other statuses, including Pending Closure.
     * @param lstOldObject List<SObject> ContentDocumentLink records being deleted.
     * @param mapOldObject Map<Id,Object> ContentDocumentLink records map.
     */
    public void beforeDelete(List<SObject> lstOldObject, Map<Id, Object> mapOldObject) {
        ContentFilesTriggerHelper.blockDeleteOnContractExecutedQuotes(
            (List<ContentDocumentLink>) lstOldObject
        );
    }

    /**
     * @description After insert handler — no action required.
     * @param lstNewObject List<SObject> inserted ContentDocumentLink records.
     * @param mapNewObject Map<Id,Object> inserted ContentDocumentLink records map.
     */
    public void afterInsert(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
        //Update Blng Invoice fields — disabled pending BIZ reactivation
        // ContentFilesTriggerHelper.afterInsert((Map<Id, ContentDocumentLink>) mapNewObject);
    }

    /**
     * @description After update handler — no action required.
     * @param lstNewObject List<SObject> updated ContentDocumentLink records.
     * @param mapNewObject Map<Id,Object> updated ContentDocumentLink records map.
     * @param lstOldObject List<Object> old ContentDocumentLink records.
     * @param mapOldObject Map<Id,Object> old ContentDocumentLink records map.
     */
    public void afterUpdate(List<SObject> lstNewObject, Map<Id, Object> mapNewObject, List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
    }

    /**
     * @description After delete handler — no action required.
     * @param lstOldObject List<Object> deleted ContentDocumentLink records.
     * @param mapOldObject Map<Id,Object> deleted ContentDocumentLink records map.
     */
    public void afterDelete(List<Object> lstOldObject, Map<Id, Object> mapOldObject) {
    }

    /**
     * @description After undelete handler — no action required.
     * @param lstNewObject List<SObject> restored ContentDocumentLink records.
     * @param mapNewObject Map<Id,Object> restored ContentDocumentLink records map.
     */
    public void afterUnDelete(List<SObject> lstNewObject, Map<Id, Object> mapNewObject) {
    }
}