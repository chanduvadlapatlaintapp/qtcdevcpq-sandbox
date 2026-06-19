public class AttachmentTriggerHandler {

    /**
     * @description Blocks deletion of Attachments whose parent quote is Contract Executed.
     *              Allows deletion for all other statuses, including Pending Closure.
     *              Called from AttachmentTrigger on before delete. (BIZ-81572)
     * @param oldMap Map of Attachment records being deleted.
     */
    public static void attachmentBeforeDelete(Map<Id, Attachment> oldMap) {
        // Collect ParentIds that point to SBQQ__Quote__c records
        Set<Id> quoteIds = new Set<Id>();
        for (Attachment att : oldMap.values()) {
            if (att.ParentId != null
                    && att.ParentId.getSObjectType() == SBQQ__Quote__c.SObjectType) {
                quoteIds.add(att.ParentId);
            }
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        // Query only the quotes that are Contract Executed
        Map<Id, SBQQ__Quote__c> contractExecutedQuotes = new Map<Id, SBQQ__Quote__c>([
            SELECT Id
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
              AND Quote_Stage__c = :QuoteConstants.STATUS_CONTRACT_EXECUTED
        ]);

        if (contractExecutedQuotes.isEmpty()) {
            return;
        }

        // Add an error on each Attachment linked to a Contract Executed quote
        for (Attachment att : oldMap.values()) {
            if (contractExecutedQuotes.containsKey(att.ParentId)) {
                att.addError('Attachments cannot be deleted from a Contract Executed quote.');
            }
        }
    }

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

        // Added Document Type via BIZ-73733. Include null DocType to handle the case where Conga
        // saves the attachment via BizApp service user — that path bypasses the Document_Type__c
        // assignment, leaving DocType null. Without this, old Conga RelatedContent records
        // accumulate across multiple Conga re-runs.
        lstAdditionalDocumentDelete = [SELECT ID FROM SBQQ__RelatedContent__c WHERE SBQQ__Quote__c IN :setQuoteIds AND (NAME LIKE '%_bundle_%' OR NAME LIKE '%_Amendment_%') AND (Document_Type__c = 'Conga Generated OSA' OR Document_Type__c = null)];

        if(setAttachmentIds != null && setAttachmentIds.size() > 0){
        	for(SBQQ__RelatedContent__c oAdditionalDocument : [SELECT Id, SBQQ__ExternalId__c FROM SBQQ__RelatedContent__c WHERE SBQQ__ExternalId__c IN :setAttachmentIds]){
                Set<String> setAdditionalDocIds = new Set<String>();
                if(mapAttachmentIdSetOfAdditionalDoc != null && mapAttachmentIdSetOfAdditionalDoc.containsKey(oAdditionalDocument.SBQQ__ExternalId__c)){
                    setAdditionalDocIds.addAll(mapAttachmentIdSetOfAdditionalDoc.get(oAdditionalDocument.SBQQ__ExternalId__c));
                }
                setAdditionalDocIds.add(oAdditionalDocument.Id);
                mapAttachmentIdSetOfAdditionalDoc.put(oAdditionalDocument.SBQQ__ExternalId__c,setAdditionalDocIds);
            }

            // SBQQ sorts the "Included Content" panel by SBQQ__ExternalId__c DESC.
            // ContentDocumentIds (069...) always sort higher than AttachmentIds (00P...).
            // To ensure the Conga PDF appears BEFORE product docs (e.g. Celeste, which is a
            // ContentDocument), we convert each new Conga Attachment into a ContentDocument
            // so its 069... ExternalId sorts higher than the older Celeste 069... ExternalId.
            // Bulk-query attachment bodies first (avoids SOQL inside loop).
            Set<Id> newAttIds = new Set<Id>();
            for(Attachment oAttachment : mapNewAttachment.values()){
                if(!mapAttachmentIdSetOfAdditionalDoc.containsKey(oAttachment.Id)){
                    newAttIds.add(oAttachment.Id);
                }
            }
            Map<Id, Blob> attBodyMap = new Map<Id, Blob>();
            for(Attachment a : [SELECT Id, Body FROM Attachment WHERE Id IN :newAttIds]){
                attBodyMap.put(a.Id, a.Body);
            }

            // Create ContentVersions for new Conga attachments (bulk insert)
            List<ContentVersion> cvsToInsert = new List<ContentVersion>();
            List<Id> orderedAttIds = new List<Id>();
            for(Attachment oAttachment : mapNewAttachment.values()){
                if(!mapAttachmentIdSetOfAdditionalDoc.containsKey(oAttachment.Id)){
                    Blob body = attBodyMap.get(oAttachment.Id);
                    if(body != null){
                        cvsToInsert.add(new ContentVersion(
                            Title = oAttachment.Name,
                            PathOnClient = oAttachment.Name,
                            VersionData = body,
                            FirstPublishLocationId = oAttachment.ParentId
                        ));
                        orderedAttIds.add(oAttachment.Id);
                    }
                }
            }
            if(!cvsToInsert.isEmpty()){
                insert cvsToInsert;
            }

            // Query ContentDocumentIds for the just-inserted ContentVersions
            Set<Id> insertedCvIds = new Set<Id>();
            for(ContentVersion cv : cvsToInsert){ insertedCvIds.add(cv.Id); }
            Map<Id, Id> cvIdToContentDocId = new Map<Id, Id>();
            for(ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :insertedCvIds]){
                cvIdToContentDocId.put(cv.Id, cv.ContentDocumentId);
            }
            // Map attId -> ContentDocumentId
            Map<Id, Id> attIdToContentDocId = new Map<Id, Id>();
            for(Integer i = 0; i < orderedAttIds.size(); i++){
                Id contentDocId = cvIdToContentDocId.get(cvsToInsert[i].Id);
                if(contentDocId != null){
                    attIdToContentDocId.put(orderedAttIds[i], contentDocId);
                }
            }

            for(Attachment oAttachment : mapNewAttachment.values()){
                if(!mapAttachmentIdSetOfAdditionalDoc.containsKey(oAttachment.Id)){
                    // Use ContentDocumentId (069...) if available; fall back to AttachmentId (00P...)
                    Id externalId = attIdToContentDocId.get(oAttachment.Id);
                    if(externalId == null){ externalId = oAttachment.Id; }
                    // Added Document Type via BIZ-73733
                    SBQQ__RelatedContent__c relatedContent = new SBQQ__RelatedContent__c(
                        Name=oAttachment.Name,
                        SBQQ__DisplayOrder__c=1,
                        SBQQ__ExternalId__c=externalId,
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
                // Product-specific documents (e.g. Celeste Terms) are linked via
                // QuoteTermValidator.generateQuoteTerms() at "Finalize OSA" stage change.
                // Both Conga and Celeste now use ContentDocumentIds (069...) as ExternalId.
                // SBQQ sorts "Included Content" by ExternalId DESC — the newly-created Conga
                // ContentDocumentId is always higher than the older Celeste ContentDocumentId,
                // so Conga always appears first in the panel (the correct bundle order).
            }
        }
    }
}