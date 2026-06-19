({
	doInit : function(component, event) {
        var s = window.location.href;
        var topicName =  component.get("v.TopicName");
        var topicId =  component.get("v.TopicId");
        
        var action = component.get("c.getGroups");
        action.setParams({
            'topicId' : topicId
        });
        action.setCallback(this, function(a) {
            var state =  a.getState();
            if(state === "SUCCESS"){
                var res = a.getReturnValue();
                if(!$A.util.isEmpty(res) && !$A.util.isUndefined(res)){
                    component.set("v.showGrp",true);
                    component.set("v.grpName",res.Name);
                    component.set("v.grpId",res.Id);
                    component.set("v.imgUrl",res.SmallPhotoUrl);
                }else{
                    component.set("v.showError",true);
                }
            }          
        });
        $A.enqueueAction(action);       
    }
    
})