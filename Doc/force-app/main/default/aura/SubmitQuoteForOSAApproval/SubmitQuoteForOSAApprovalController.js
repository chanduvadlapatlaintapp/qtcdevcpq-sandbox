({
    init : function (component) {
        // Find the component whose aura:id is "flowData"
        var flow = component.find("flowData");
        var newRecordId = component.get("v.recordId");
        console.log(newRecordId);
        const recordId = component.find("ThisRecord").get("v.value");
        const inputs = []; 
        if(recordId) {
            inputs.push({name:"recordId",type:"String",value:recordId});
        }
        // In that component, start your flow. Reference the flow's API Name.
        flow.startFlow("Quote_Submit_for_Approval",inputs);
    },
   recordUpdate: function(component, event) {
    },
    handleStatusChange : function (component, event) {
        const outputVariables = event.getParam("outputVariables");
        var status;
        if (outputVariables && outputVariables.length > 0) {
                let outputVar = outputVariables.find(e => e.name == 'OutputStatus');
                if (outputVar) {
                    status =  outputVar.value;
                }
            }
        //var stage = 'Finalize OSA';//component.get("v.Quote").Quote_Stage__c;
        var stage = component.get("v.Quote").Quote_Stage__c;
        var recordId = component.get("v.recordId");
        if(event.getParam("status") === "FINISHED") {
            /*if(stage == 'Finalize OSA') { 
                //$A.get("e.force:closeQuickAction").fire();
                console.log('in osa');
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Info!",
                    "message": "The record will be submitted for approval."
                });
                toastEvent.fire();
                console.log('calling generateQuoteTerms in osa');
                 var action = component.get('c.generateQuoteTerms'); 
                action.setParams({
                    "quoteId" : recordId
                });
                action.setCallback(this, function(a){
                    var state = a.getState(); // get the response state
                    if(state == 'SUCCESS') {
                        console.log('in osa:SUCCESS generateQuoteTerms');
                        var list = ['/apex/APXTConga4__Conga_Composer?SolMgr=1&serverUrl={!API.Partner_Server_URL_520}&Id='+recordId+'&QueryId=[MDQOneTimeDiscount]0Q_001MAQ106508%3Fpv0%3D'+recordId+',[NonMDQQuoteLines]0Q_003MAQ133545%3Fpv0%3D'+recordId+',[MDQQuoteLines]0Q_002MAQ228749%3Fpv0%3D'+recordId+',[QuoteLineMDQYear1]0Q_000MAQ991196%3Fpv0%3D'+recordId+',[ServiceOneTimeCredit]0Q_060MAQ489742%3Fpv0%3D'+recordId+',[TermConditions]0Q_061MAQ603651%3Fpv0%3D'+recordId+'&TemplateId=0T_088MAQ630558&DS7=11&FP0=1&OFN=OSA','/apex/SubmitQuote?id='+component.get("v.recordId")];
                        
                        for(var i=0;i<list.length;i++){
                            var urlEvent = $A.get("e.force:navigateToURL");
                            urlEvent.setParams({
                                "url": list[i]
                            });
                            urlEvent.fire();
                        }
                        $A.get("e.force:closeQuickAction").fire();
                    }
                });
                $A.enqueueAction(action);
            } else */
            	var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Info!",
                    "message": "The record will be submitted for approval."
                });
            toastEvent.fire();
            var urlEvent = $A.get("e.force:navigateToURL");
            urlEvent.setParams({
                "url":"/apex/SubmitQuote?id="+component.get("v.recordId")
            });
            urlEvent.fire(); 
        } else if(event.getParam("status") === "FINISHED" && status == "Close") {
            $A.get("e.force:closeQuickAction").fire();
        }
    }
})