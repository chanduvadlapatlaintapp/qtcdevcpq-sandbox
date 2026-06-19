({
	init : function (component) {
        var recordId = component.get("v.recordId");
    },
     recordUpdate: function(component, event, helper) {
        var recordId = component.get("v.recordId");
        var status = component.get("v.Quote").Pricing_Proposal_Approval__c;
        var stage = component.get("v.Quote").Quote_Stage__c;
        var quoteNumber = component.get("v.Quote").Name;
        var accountName = component.get("v.Quote").Account_Name__c;
        console.log('in init');
        if(stage == "Pricing Proposal" && status == "Approved") {
            console.log('in yes');
            $A.get("e.force:closeQuickAction").fire();
            var urlEvent = $A.get("e.force:navigateToURL");
    		urlEvent.setParams({
                "url": '/apex/APXTConga4__Conga_Composer?SolMgr=1&serverUrl={!API.Partner_Server_URL_520}&Id='+recordId+'&QueryId=[MDQQuoteLines]0Q_006MAI332677%3Fpv0%3D'+recordId+',[NonMDQQuoteLines]0Q_007MAI278240%3Fpv0%3D'+recordId+',[MDQOneTimeDiscount]0Q_012MAI831841%3Fpv0%3D'+recordId+',[QuoteLineMDQYear1]0Q_013MAI932474%3Fpv0%3D'+recordId+'&TemplateId=0T_003MAI505642&DS7=1&FP0=1&OFN=Pricing+Proposal-'+accountName+'-'+quoteNumber,
                "width" : "700",
                "height" : "1000",
                "scrollbars" : "yes"
            });
        
    		urlEvent.fire();
        } else {
            console.log('in else');
            $A.get("e.force:closeQuickAction").fire();
            var showToastMessage = $A.get("e.force:showToast");
            showToastMessage.setParams({
                "message" : "Please submit Pricing Proposal for Approval before generating Document",
                "type" : "warning",
                "duration" : "50000ms"
           	});
           	showToastMessage.fire();
        }
    }
})