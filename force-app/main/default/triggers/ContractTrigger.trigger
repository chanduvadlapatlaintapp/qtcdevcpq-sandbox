/********************************************************************************     
*  Name             :  ContractTrigger
*  Author           :  Hiforte Technologies
*  Description      :  1. Populate Billing Account on Contract
*                                  
*  Change history   : Updated as part of BIZ-66427 and implemented trigger framework 
*  Date                Author                          Description
*  06/01/14        Vasu Pulipati                   Created
*  21/03/25        Ratan Paul                     implemented trigger framework 
********************************************************************************/
trigger ContractTrigger on Contract (before insert,after insert,before update,after update,before delete,after delete,after undelete) {
    TriggerDispatcher.run('Contract');
}