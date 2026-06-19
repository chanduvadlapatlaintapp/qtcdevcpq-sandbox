trigger trConfInCompletion on Case (before update) {
	Case myOldCaseData = trigger.old[0];
	String myOldCCDValue = myOldCaseData.PSCase_Confidence_in_Completion__c;
	
	Case myNewCaseData = trigger.new[0];
	myNewCaseData.Confidence_in_Completion_Date_Prior__c = myOldCCDValue; 
	
}