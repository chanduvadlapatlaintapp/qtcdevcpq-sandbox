public without sharing class QTC_GreenboxReassign {
   @InvocableMethod(label='Reassign Approval')
   public static List<Id> reassignApproval(List<Id> approvalId) {
       System.debug('Input approvalId: ' + approvalId);
       if (approvalId == null || approvalId.isEmpty()) {
           System.debug('No Approval IDs were passed.');
           return null;
       }
       // Step 1: Retrieve the current user's ID
       Id currentUserId = UserInfo.getUserId();
       // Step 2: Check if the user has the 'reassign_approval_to_me' permission set
       List<PermissionSetAssignment> psaList = [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :currentUserId AND PermissionSet.Name = 'reassign_approval_to_me'];
       if (psaList.isEmpty()) {
           System.debug('User does not have permission to reassign approval.');
           throw new CustomException('User does not have permission to reassign approval.');
       }
       // Step 3: Retrieve the current user's approver ID
       Id currentUserApproverId;
       List<sbaa__Approver__c> userApprovers = [SELECT Id FROM sbaa__Approver__c WHERE sbaa__User__c = :currentUserId LIMIT 1];
       if (!userApprovers.isEmpty()) {
           currentUserApproverId = userApprovers[0].Id;
       } else {
           System.debug('No approver found for the current user.');
           return null;
       }
       // Step 4: Fetch the sbaa__Approval__c records
       List<sbaa__Approval__c> lstApprovals = [SELECT Id, sbaa__Approver__c, sbaa__AssignedTo__c FROM sbaa__Approval__c WHERE Id IN :approvalId];
       System.debug('Fetched Approvals: ' + lstApprovals);
       List<sbaa__Approval__c> approvalListToUpdate = new List<sbaa__Approval__c>();
       for (sbaa__Approval__c oApproval : lstApprovals) {
           System.debug('Original Approver: ' + oApproval.sbaa__Approver__c);
           System.debug('Original AssignedTo: ' + oApproval.sbaa__AssignedTo__c);
           oApproval.sbaa__AssignedTo__c = currentUserId;
           // oApproval.sbaa__Approver__c = currentUserApproverId;
           System.debug('Updated Approver: ' + oApproval.sbaa__Approver__c);
           System.debug('Updated AssignedTo: ' + oApproval.sbaa__AssignedTo__c);
           approvalListToUpdate.add(oApproval);
       }
       System.debug('Approvals to Update: ' + approvalListToUpdate);
       if (!approvalListToUpdate.isEmpty()) {
           try {
               update approvalListToUpdate;
               System.debug('Update successful for: ' + approvalListToUpdate);
           } catch (Exception e) {
               System.debug('Error during update: ' + e.getMessage());
               throw new CustomException('Error during update: ' + e.getMessage());
           }
       }
       return null;
   }
   public class CustomException extends Exception {}
}