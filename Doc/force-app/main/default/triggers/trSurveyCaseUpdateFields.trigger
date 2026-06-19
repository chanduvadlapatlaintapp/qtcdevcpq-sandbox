trigger trSurveyCaseUpdateFields on Case (before insert, before update) {
	string label = System.label.CaseIdLabel;
	List<Case> caseList = trigger.new;
	Case myCase = caseList[0]; 
    	// Update the Contact on the Survey Case
    	
    	if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_ContactID__c != null && myCase.ContactID == null ) 
        	{
        	myCase.ContactId = myCase.Survey_ContactID__c;
        	}
        // Update the SE on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_EngineerName__c != null && myCase.Survey_SECalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_SECalculated__c = myCase.Survey_EngineerName__c;
        	}
        // Update the Adoption Consultant on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_AdoptionConsultant__c != null && myCase.Survey_ACCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_ACCalculated__c = myCase.Survey_AdoptionConsultant__c;
        	}
        // Update the Project Manager on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_ProjectManagerName__c != null && myCase.Survey_ProjectManagerName__c != label && myCase.Survey_PMCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_PMCalculated__c = myCase.Survey_ProjectManagerName__c;
        	}          	
        // Update the Account on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_FirmName__c != null && myCase.Survey_AccountCalculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_AccountCalculated__c = myCase.Survey_FirmName__c;
        	} 
        // Update the Principal Consultant on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_Principal_Consultant_Name__c != null && myCase.Survey_Principal_Consultant_Name__c != label && myCase.Survey_PC_Calculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_PC_Calculated__c = myCase.Survey_Principal_Consultant_Name__c;
        	}
            // Update the Principal Consultant on the Survey Case
        if ( myCase.Record_Type_Name__c == 'Survey' && myCase.Survey_Solution_Architect_Name__c != null && myCase.Survey_Solution_Architect_Name__c != label && myCase.Survey_SA_Calculated__c == null && myCase.Survey_AssociatedMilestone__c != null) 
        	{
        	myCase.Survey_SA_Calculated__c = myCase.Survey_Solution_Architect_Name__c;
        	}       
}