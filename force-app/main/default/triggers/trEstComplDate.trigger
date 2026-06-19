trigger trEstComplDate on Case (before update) {
	Case myOldCaseData = trigger.old[0];
	Date myOldECDDate = myOldCaseData.PSCase_Project_Exp_Compl_Date__c;
	
	Case myNewCaseData = trigger.new[0];
	myNewCaseData.Project_Exp_Compl_Date_Prior__c = myOldECDDate; 
	
}