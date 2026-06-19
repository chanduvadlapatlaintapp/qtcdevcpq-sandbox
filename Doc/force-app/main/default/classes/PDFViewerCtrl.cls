public class PDFViewerCtrl{
    public String PDFData {get; set;} 
    
    public PDFViewerCtrl(){
       string label = Label.CommunityHelpPDFName;
       list<staticResource> resourceLst= [select id, body from staticResource where name=:label];
       Blob csvBlob = resourceLst[0].Body;
       PDFData  =  EncodingUtil.base64Encode(csvBlob);   
    }
}