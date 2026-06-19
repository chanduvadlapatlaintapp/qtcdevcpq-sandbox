public class CreateContractFromQuoteController {
	
    String quoteId;
    public boolean isError {get; set;}
    public String msgToDisplay {get; set;}
 	ApexPages.StandardController sc;

    public CreateContractFromQuoteController(ApexPages.StandardController sc){
        this.sc = sc;
        quoteId = ApexPages.currentPage().getParameters().get('id');
        isError = false;
        
        if(quoteId != null){
            SBQQ__Quote__c quote = [SELECT Id
                                        , SBQQ__MasterContract__c
                                        FROM SBQQ__Quote__c
                                        WHERE Id = :quoteId 
                                        LIMIT 1];
            
            if (quote.SBQQ__MasterContract__c != null){
                msgToDisplay = 'Retrieving Contract.';
            }
            else{
                msgToDisplay = 'Creating Contract.';
            }
        }
    }
    
    public PageReference createContractOnQuote(){
        
        try{
            
            SBQQ__Quote__c quote = [SELECT Id
                                    , SBQQ__Account__c
                                 	, SBQQ__Opportunity2__c
                                    , SBQQ__Opportunity2__r.Name
                                    , SBQQ__MasterContract__c
                                    FROM SBQQ__Quote__c
                                    WHERE Id = :quoteId 
                                    LIMIT 1];
            
            if (quote.SBQQ__MasterContract__c != null){
                PageReference pageref = new PageReference('/'+ quote.SBQQ__MasterContract__c + '?retURL=' + quote.SBQQ__MasterContract__c);
                pageref.setRedirect(true);
                
                return pageref;
            }
            else{
            	Contract contract = new Contract(Name = quote.SBQQ__Opportunity2__r.Name, SBQQ__Quote__c = quoteId, AccountId = quote.SBQQ__Account__c, SBQQ__Opportunity__c = quote.SBQQ__Opportunity2__c);
            	insert contract;
                        
                Opportunity opportunity = new Opportunity(Id = quote.SBQQ__Opportunity2__c, Associated_Contract_OSA__c = contract.Id);
                update opportunity;
                
                PageReference pageref = new PageReference('/'+ contract.Id + '/e?retURL=' + contract.Id);
                pageref.setRedirect(true);
                return pageref;
            }

        }
        catch(Exception ex){
            isError = true;
            ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR, String.valueOf(ex.getLineNumber()) ));
        }
        return null;
    }
    
    public PageReference goBack(){       
        PageReference pageref = new PageReference('/'+quoteId);
        pageref.setRedirect(true);
        return pageref;
    }
}