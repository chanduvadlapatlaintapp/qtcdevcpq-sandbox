public class QuoteApproveAllExtController {    
    private final SBQQ__Quote__c oQuote{get;set;}
        
    public String sQuoteId{get;set;}
    public Boolean bHasApproveAllPermission{get;set;}
    public String commentValue { get; set; }
    public Boolean submitted { get; set; }
    public Boolean showError { get; set; }
    public String flowParams { get; set; }
    
    public QuoteApproveAllExtController(ApexPages.StandardController oStandardController){
        this.oQuote = (SBQQ__Quote__c)oStandardController.getRecord();
        sQuoteId = this.oQuote.Id;
        submitted = false;
        showError = false;
        bHasApproveAllPermission = FeatureManagement.checkPermission('Approve_All');
    }
    
    public PageReference messageConfirmed(){
        PageReference pg = new PageReference('/'+sQuoteId);
        pg.setRedirect(true);
        return pg; 
    }

    public void submit() {
        if(commentValue != null && commentValue != ''){
            submitted = true;
            showError = false;
            flowParams = sQuoteId + '-$-' + commentValue;
        } else {
            showError = true;
        }
        
    }
}