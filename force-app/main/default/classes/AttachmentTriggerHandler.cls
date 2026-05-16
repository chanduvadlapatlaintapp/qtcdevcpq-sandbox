public class AttachmentTriggerHandler {
	public Static void attachmentAfterInsert(map<Id,Attachment> mapNewAttachment) {
        Map<Id,Set<String>> mapAttachmentIdSetOfAdditionalDoc = new Map<Id,Set<String>>();
        List<SBQQ__RelatedContent__c> lstAdditionalDocumentInsert = new List<SBQQ__RelatedContent__c>();
        List<SBQQ__RelatedContent__c> lstAdditionalDocumentDelete = new List<SBQQ__RelatedContent__c>();
        Set<Id> setAttachmentIds = new Set<Id>();
        Set<Id> setQuoteIds = new Set<Id>();
        
        for(Attachment oAttachment : mapNewAttachment.values()){
            if(oAttachment.ParentId.getSObjectType().getDescribe().getName().equalsIgnoreCase('SBQQ__Quote__c') && (oAttachment.Name.containsIgnoreCase('bundle') || oAttachment.Name.containsIgnoreCase('_Amendment_'))){
                setAttachmentIds.add(oAttachment.Id);
                setQuoteIds.add(oAttachment.ParentId);
            }
        }
        
        // Added Document Type via BIZ-73733
        lstAdditionalDocumentDelete = [SELECT ID FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c IN :setQuoteIds AND (NAME LIKE '%_bundle_%' OR NAME LIKE '%_Amendment_%') AND Document_Type__c = 'Conga Generated OSA'];
        
        if(setAttachmentIds != null && setAttachmentIds.size() > 0){
        	for(SBQQ__RelatedContent__c oAdditionalDocument : [SELECT Id, SBQQ__ExternalId__c FROM SBQQ__RelatedContent__c WHERE SBQQ__ExternalId__c IN :setAttachmentIds]){
                Set<String> setAdditionalDocIds = new Set<String>();
                if(mapAttachmentIdSetOfAdditionalDoc != null && mapAttachmentIdSetOfAdditionalDoc.containsKey(oAdditionalDocument.SBQQ__ExternalId__c)){
                    setAdditionalDocIds.addAll(mapAttachmentIdSetOfAdditionalDoc.get(oAdditionalDocument.SBQQ__ExternalId__c));               
                }
                setAdditionalDocIds.add(oAdditionalDocument.Id);
                mapAttachmentIdSetOfAdditionalDoc.put(oAdditionalDocument.SBQQ__ExternalId__c,setAdditionalDocIds);              
            }
            
            for(Attachment oAttachment : mapNewAttachment.values()){
                if(!mapAttachmentIdSetOfAdditionalDoc.containsKey(oAttachment.Id)){
                    // Added Document Type via BIZ-73733
                    SBQQ__RelatedContent__c relatedContent = new SBQQ__RelatedContent__c(
                        Name=oAttachment.Name, 
                        SBQQ__DisplayOrder__c=1, 
                        SBQQ__ExternalId__c=oAttachment.Id, 
                        SBQQ__Quote__c=oAttachment.parentId, 
                        SBQQ__Required__c=true
                    );
                    if (UserInfo.getName() != Label.Biz_App_UserName) {
                        relatedContent.Document_Type__c = 'Conga Generated OSA';
                    }
                    lstAdditionalDocumentInsert.add(relatedContent);   
                }            
            }
            if(lstAdditionalDocumentDelete!=null && lstAdditionalDocumentDelete.size()>0){
                for(SBQQ__RelatedContent__c oAdditionalDocument: lstAdditionalDocumentDelete){
                    oAdditionalDocument.SBQQ__Quote__c = null;
                    oAdditionalDocument.SBQQ__ExternalId__c = oAdditionalDocument.Id;
                }
                update lstAdditionalDocumentDelete;
                delete lstAdditionalDocumentDelete;
            }
            if(lstAdditionalDocumentInsert!=null && lstAdditionalDocumentInsert.size() > 0){
                insert lstAdditionalDocumentInsert;
            }   
        }        
    }
}