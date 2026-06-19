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
        flow.startFlow("Contract_Amend",inputs);
    },
   recordUpdate: function(component, event) {
    },
    submitAmendContract : function (component, event) {
        var urlEvent = $A.get("e.force:navigateToURL");
        var recordId = component.get("v.recordId");
        if (event.getParam('status') === "FINISHED") {    
            urlEvent.setParams({
                    "url":"/apex/SBQQ__AmendContract?id="+component.get("v.recordId")
                });
                urlEvent.fire(); 
    	}
    }
})