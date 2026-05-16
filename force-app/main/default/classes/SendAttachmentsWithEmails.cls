/**
* @description       : This class is used in Approval Email Template.
* @author            : Rajani
* @last modified on  : 02-07-2024
* @last modified by  : Pankaj Kumar
**/
public class SendAttachmentsWithEmails {

    public  String controllerValue;
    public  Boolean attachmentFound{get;set;}
    
    public SendAttachmentsWithEmails(){
        attachmentFound =false;
    }
    public  void  setControllerValue (String s) { 
        try{
            if (s!= null){
            	List<SBQQ__QuoteDocument__c> cdl = [select Id,SBQQ__AttachmentId__c,SBQQ__DocumentId__c,SBQQ__ViewRecordId__c,SBQQ__Quote__c from SBQQ__QuoteDocument__c 
                                          where SBQQ__Quote__c =: s 
                                          ORDER BY CreatedDate DESC LIMIT 1];
                
            
            	if(cdl!=null && !cdl.isEmpty()){       
                    controllerValue = URL.getOrgDomainURL().toExternalForm()+'/servlet/servlet.FileDownload?file='+cdl[0].SBQQ__ViewRecordId__c;
                    attachmentFound = true;
                }else{
                    List<Attachment> attList = [select Id,Name,ParentId from Attachment
                                          where ParentId =: s 
                                          ORDER BY CreatedDate DESC LIMIT 1];
                    if(attList!=null && !attList.isEmpty()){       
                        controllerValue = URL.getOrgDomainURL().toExternalForm()+'/servlet/servlet.FileDownload?file='+attList[0].Id;
                        attachmentFound = true;
                	}
                }
       		}
        }catch(Exception ex){
            System.debug('Exception Caught  :'+ex.getMessage() + ' **Line Number : '+ex.getLineNumber());
        } 
    }    
    public  String getControllerValue() {
        return controllerValue;
    }   
}