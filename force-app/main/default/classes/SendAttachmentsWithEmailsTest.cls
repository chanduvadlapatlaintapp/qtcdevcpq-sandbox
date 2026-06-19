/**
 * @description       : Test class for SendAttachmentsWithEmails
 * @author            : Rajani Peddinti
 * Jira story : BIZ-48394
**/
@isTest
public class SendAttachmentsWithEmailsTest {
  @testSetup
    public static void setup(){     
	List<Account> accList = TestDataFactory.createAccount(1,True);
        Id pricebookId = Test.getStandardPricebookId();
        
        List<Opportunity> opp = TestDataFactory.createOppty(1,accList[0].Id,false);
      	insert opp;
        
        List<SBQQ__Quote__c> lstOfQuote = TestDataFactory.createQuote(1,opp[0].Id,false);
        lstOfQuote[0].SBQQ__Account__c = accList[0].Id;
        insert lstOfQuote;
                   
        ContentVersion contentVersion = new ContentVersion(
                    Title          = 'Pricing Proposal',
                    PathOnClient   = 'Pic.jpg',
                    VersionData    = Blob.valueOf('Test Content'),
                    IsMajorVersion = true);
            		insert contentVersion;
    }
    
    @istest
    private static void setControllerValue(){
		List<ContentDocument> documents = [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument];
		List<SBQQ__Quote__c> lstOfQuote = [SELECT Id, Name FROM SBQQ__Quote__c LIMIT 1];
        List<ContentDocumentLink> cdoclink1 = TestDataFactory.createContentDocLink(1, String.valueof(lstOfQuote[0].Id), String.valueof(documents[0].Id), false);
      	insert cdoclink1;
        SBQQ__QuoteDocument__c qtDoc = new SBQQ__QuoteDocument__c(Name='Doc1',SBQQ__DocumentId__c=cdoclink1[0].Id,SBQQ__Quote__c=lstOfQuote[0].Id);
        insert qtDoc;
        Test.startTest();
       	SendAttachmentsWithEmails attachmentEmail = new SendAttachmentsWithEmails();
        attachmentEmail.setControllerValue(lstOfQuote[0].Id);        
        
        attachmentEmail.getControllerValue();
        Test.stopTest();
        System.assertEquals(cdoclink1[0].linkedEntityId, lstOfQuote[0].Id);
        
    } 
    @istest
    private static void setControllerValue1(){
		List<ContentDocument> documents = [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument];
		List<SBQQ__Quote__c> lstOfQuote = [SELECT Id, Name FROM SBQQ__Quote__c LIMIT 1];
        List<ContentDocumentLink> cdoclink1 = TestDataFactory.createContentDocLink(1, String.valueof(lstOfQuote[0].Id), String.valueof(documents[0].Id), false);
      	insert cdoclink1;
        Attachment atDoc = new Attachment(Name='Doc1',ParentId=lstOfQuote[0].Id,Body=Blob.valueOf('Test Content'));
        insert atDoc;
        Test.startTest();
       	SendAttachmentsWithEmails attachmentEmail = new SendAttachmentsWithEmails();
        attachmentEmail.setControllerValue(lstOfQuote[0].Id);        
        
        attachmentEmail.getControllerValue();
        Test.stopTest();
        System.assertEquals(cdoclink1[0].linkedEntityId, lstOfQuote[0].Id);        
    }
}