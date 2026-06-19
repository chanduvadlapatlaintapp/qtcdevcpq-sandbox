trigger trStartDate on Case (before insert, before update) {
	Case myCase = trigger.new[0];
    	if ( myCase.PSCase_Kickoff_Meeting_Date__c != null && myCase.DateOpen__C == null ) 
        	{
        	myCase.DateOpen__C = myCase.PSCase_Kickoff_Meeting_Date__c; 
        	}
}