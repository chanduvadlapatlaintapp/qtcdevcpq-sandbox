global class ServicesSOW {

    public class FlowRequestResponse {
        public String createdBy;
        public String id;
        public String name;
        public String requestType;
        public String status;
    }
    
    public ServicesSOW() {
    }

    public static String createFlowRequestWithDefaultFieldsHelper(String opportunityId, Boolean isTesting) {
        HttpRequest req = new HttpRequest();
        Opportunity o = [select Type from Opportunity where Id = :opportunityId LIMIT 1];
        String workFlow;
        if (o.Type.contains('Change Request'))
            workFlow = 'Services%20SOW-%20Change%20Request';
        else
            workFlow = 'Services%20SOW-%20Not%20Change%20Request';
        System.debug(workFlow);
        req.setEndpoint('https://intappprod.open.intapp.com/api/api/intake/v1/requests?workflowDefinitionName='+workFlow);
        req.setMethod('POST');
        req.setHeader('content-type', 'application/json');
        if (IsTesting == false)
            req.setHeader('Authorization','Bearer ' + ServicesSOWOAuth.getAuthToken());
        ServicesSOWDataMapper mapper = new ServicesSOWDataMapper(opportunityId);
        req.setBody(mapper.getMappings());
        Http http = new Http();
        HTTPResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            return 'HTTP_ERROR';
        }
        System.debug(res.getStatus());
        if (res.getStatus() != 'OK')
            return 'HTTP_ERROR';
        else if ( (UserInfo.getName() != 'Scott Schwarz') && (UserInfo.getName() != 'Kevin Ehrie') )
            return 'FEATURE_NOT_AVAILABLE_ERROR';
        else {
            FlowRequestResponse f = (FlowRequestResponse)JSON.deserialize(res.getBody(),FlowRequestResponse.class);
            return f.id;
        }
    }

    webservice static String createFlowRequestWithDefaultFields(String opportunityId) {
        return createFlowRequestWithDefaultFieldsHelper(opportunityId,false);
    }
   
    public static String createSFServicesSOWObjectHelper(String fieldData) {
        fieldData = '{"answers": ' + fieldData + '}';
        Services_SOW__c servicesSOW = new Services_SOW__c();
        String answerString = null;
        Boolean IdFieldFound = false;
        
        ServicesSOWAnswers answers = (ServicesSOWAnswers)JSON.deserialize(fieldData,ServicesSOWAnswers.class);
        for (ServicesSOWAnswer answer: answers.answers) {
            answerString = null;
            if (answer.questionName == 'SFAccountId') {
                servicesSOW.put('Account__c',answer.textAnswer);
                IDFieldFound = true;
                }
            else if (answer.questionName == 'SFEmployeeId') {
                servicesSOW.put('Requesting_Employee__c',answer.textAnswer);
                IDFieldFound = true;
                }
            else if (answer.questionName == 'Time_Questionnaire_Available_Bounding__c')
                IDFieldFound = true;
            else if ( (answer.questionName == 'Does_New_Solution_Integrate_With_Existing_Sol') || (answer.questionName == 'Project_Has_Required_Go_Live_Date') )
                IDFieldFound = true;
            else {
                if (answer.textAnswer != null)
                    answerString = answer.textAnswer;
                if (answer.numericAnswer != null)
                    answerString = answer.numericAnswer; 
                else if (answer.booleanAnswer != null)
                    answerString = answer.booleanAnswer;
                else if (answer.dateAnswer != null)
                    answerString = answer.dateAnswer; 
                else if (answer.textListAnswer != null)
                    answerString = answer.textListAnswer[0];
                if ( (answerString != null) && (answerString != '(Select)') && (!IDFieldFound) ){  
                    String s = (String)servicesSOW.put(answer.questionName,answerString);
                    }
            }
        }
        servicesSOW.put('Status__c','Submitted');
        if ( (servicesSOW.get('Product__c') != null) && (servicesSOW.get('Recurring_Involved__c') != null) ) {
            String servicesSOWProduct = (String)(servicesSOW.get('Product__c'));
            if ( (servicesSOWProduct.contains('Time')) && (servicesSOW.get('Recurring_Involved__c') == 'Yes') )
                servicesSOW.put('Time_Questionnaire_Available__c','Yes');
            }
        insert servicesSOW;
        return 'a';
    }
   
    webservice static String createSFServicesSOWObject(String fieldData) {
        return createSFServicesSOWObjectHelper(fieldData);    
    }
   

}