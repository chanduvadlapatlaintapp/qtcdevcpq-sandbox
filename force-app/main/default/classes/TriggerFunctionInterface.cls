public interface TriggerFunctionInterface {
    void beforeInsert(List<SObject> lstNewObject);
    void beforeUpdate(List<SObject> lstNewObject, Map<Id,Object> mapNewObject,List<Object> lstOldObject,Map<Id,Object> mapOldObject);
    void beforeDelete(List<SObject> lstOldObject,Map<Id,Object> mapOldObject);
    void afterInsert(List<SObject> lstNewObject, Map<Id,Object> mapNewObject);
    void afterUpdate(List<SObject> lstNewObject, Map<Id,Object> mapNewObject,List<Object> lstOldObject,Map<Id,Object> mapOldObject);
    void afterDelete(List<Object> lstOldObject,Map<Id,Object> mapOldObject);
    void afterUnDelete(List<SObject> lstNewObject, Map<Id,Object> mapNewObject);
}