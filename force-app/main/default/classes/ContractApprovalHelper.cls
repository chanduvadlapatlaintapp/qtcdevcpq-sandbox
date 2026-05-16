/*
 * Helper class for submitting contract for approval
 * Author : Vasu Pulipati (vasu@hiforte.com)
 * Date   : 1/30/2015
 */
 global class ContractApprovalHelper {

    WebService static String submitForApprovalWS(String contractId){
        try{
            submitForApproval(contractId);
            return '';
        }catch(Exception ex){
            if(ex.getMessage().contains('MANAGER_NOT_DEFINED')){
                return 'Please select approver(s) for the contract and try again';
            }
            return ex.getMessage();
        }
    }
    
    //----------------------------------------------------------------------------------------------------------
    // Prepare and submit contract for approval
    //----------------------------------------------------------------------------------------------------------
    public static void submitForApproval(String contractId){
        if(contractId == null || contractId.trim() == ''){
            return;
        }
        List<Contract> lstContracts = [Select Id, Name, Type__c, Exception_Approval__c, 
                                        Approver_1__c, Approver_2__c, Approver_3__c, Approver_4__c, Approver_5__c,
                                        Approver_6__c, 
                                        Exception_Approver_1__c, Exception_Approver_2__c, Exception_Approver_3__c, 
                                        Exception_Approver_4__c, Exception_Approver_5__c, Exception_Approver_6__c
                                       from Contract
                                       where id = :contractId];
        if(lstContracts==null || lstContracts.size()==0){
            System.debug('#### ContractApprovalHelper.submitForApproval(), no contract found for id: '+ contractId);
            return;
        }
        Contract contr = lstContracts[0];
        System.debug('#### ContractApprovalHelper.submitForApproval(), contract: '+ contr);
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(contr.Id);
        // Submit on behalf of current user
        req.setSubmitterId(UserInfo.getUserId());
        // Approval process fails if all the approvers are not set. So, check and add dummy approvers if required
        Boolean dummyAdded = false;   
        if(contr.Approver_1__c != null){
            if(contr.Approver_2__c == null){
                contr.Approver_2__c = contr.Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Approver_3__c == null){
                contr.Approver_3__c = contr.Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Approver_4__c == null){
                contr.Approver_4__c = contr.Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Approver_5__c == null){
                contr.Approver_5__c = contr.Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Approver_6__c == null){
                contr.Approver_6__c = contr.Approver_1__c;
                dummyAdded = true;
            } 
        } 
        if(contr.Exception_Approver_1__c != null){
            if(contr.Exception_Approver_2__c == null){
                contr.Exception_Approver_2__c = contr.Exception_Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Exception_Approver_3__c == null){
                contr.Exception_Approver_3__c = contr.Exception_Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Exception_Approver_4__c == null){
                contr.Exception_Approver_4__c = contr.Exception_Approver_1__c;
                dummyAdded = true;
            } 
            if(contr.Exception_Approver_5__c == null){
                contr.Exception_Approver_5__c = contr.Exception_Approver_1__c;
                dummyAdded = true;
            }
            if(contr.Exception_Approver_6__c == null){
                contr.Exception_Approver_6__c = contr.Exception_Approver_1__c;
                dummyAdded = true;
            }
        }
        if(dummyAdded){
            System.debug('#### ContractApprovalHelper.submitForApproval(), dummy approvers added, updating contract.. ');
            update contr;
        }
        
        // Submit the approval request
        //req.setSkipEntryCriteria(true);
        Exception ex = null;
        try{
            System.debug('#### ContractApprovalHelper.submitForApproval(), submitting.. ');
            Approval.ProcessResult result = Approval.process(req);
        }catch(Exception e){
            ex = e;
        }
        // If dummy approvers were added above then remove them
        if(dummyAdded){
            if(contr.Approver_1__c != null){
                if(contr.Approver_2__c == contr.Approver_1__c){
                    contr.Approver_2__c = null;
                } 
                if(contr.Approver_3__c == contr.Approver_1__c){
                    contr.Approver_3__c = null;
                } 
                if(contr.Approver_4__c == contr.Approver_1__c){
                    contr.Approver_4__c = null;
                } 
                if(contr.Approver_5__c == contr.Approver_1__c){
                    contr.Approver_5__c = null;
                }
                if(contr.Approver_6__c == contr.Approver_1__c){
                    contr.Approver_6__c = null;
                }
            } 
            if(contr.Exception_Approver_1__c != null){
                if(contr.Exception_Approver_2__c == contr.Exception_Approver_1__c){
                    contr.Exception_Approver_2__c = null;
                } 
                if(contr.Exception_Approver_3__c == contr.Exception_Approver_1__c){
                    contr.Exception_Approver_3__c = null;
                } 
                if(contr.Exception_Approver_4__c == contr.Exception_Approver_1__c){
                    contr.Exception_Approver_4__c = null;
                } 
                if(contr.Exception_Approver_5__c == contr.Exception_Approver_1__c){
                    contr.Exception_Approver_5__c = null;
                }
                if(contr.Exception_Approver_6__c == contr.Exception_Approver_1__c){
                    contr.Exception_Approver_6__c = null;
                }
            }
            System.debug('#### ContractApprovalHelper.submitForApproval(), dummy approvers removed, updating contract.. ');
            update contr;
        }
        // rethrow exception
        if(ex != null){
            throw ex;
        }
    }
}