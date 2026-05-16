public with sharing class TB_Renewal_Summary_Controller {

	public Opportunity currentOpp{get;set;}
	public List<SummaryWrapper> listWrappers{get;set;}
	
	public TB_Renewal_Summary_Controller(ApexPages.StandardController stdCon){
		currentOpp = (Opportunity)stdCon.getRecord();
		currentOpp = [Select Id, Name, AccountId,Account.Name,Associated_Contract_OSA__c,Associated_Contract_OSA__r.Name,License_Type__c,QS_TB_Billing_Model__c,
					  Amount, License_Band_Lawyers__c, Total_Firm_Timekeepers__c,QS_TB_Additional_User_Price__c,Associated_Contract_OSA__r.ContractNumber,
					  QS_Total_Enabled_Users_12_Months__c, QS_Total_Enabled_Users_3_Months__c, Associated_Contract_OSA__r.startDate,
					  Unique_Timekeeper_Users_last_12_months__c,Unique_Timekeeper_Users_last_30_days__c,
					  Account.License_Band__c, Account.License_Band_Timekeepers__c,
					  QS_TB_End_User_Recurring_Amount__c, QS_TB_Licensed_Users__c,
					  QS_Unique_Timekeeper_Users_last_3_months__c, QS_TB_Enterprise_Lawyer_Band__c
					  from Opportunity where Id=:currentOpp.Id];               
					  
		listWrappers = new List<SummaryWrapper> ();
		SummaryWrapper wrapper1 = new SummaryWrapper();
		wrapper1.enableUser3Months = currentOpp.QS_Total_Enabled_Users_3_Months__c;
		wrapper1.enableUser12Months = currentOpp.QS_Total_Enabled_Users_12_Months__c; 
		wrapper1.timekeeperUsage3Months = currentOpp.QS_Unique_Timekeeper_Users_last_3_months__c;
		wrapper1.timekeeperUsage12Months = currentOpp.Unique_Timekeeper_Users_last_12_months__c;
		listWrappers.add(wrapper1);      
		    
		SummaryWrapper wrapper2 = new SummaryWrapper();   
		if(currentOpp.QS_TB_Licensed_Users__c != null){
			if(currentOpp.QS_Total_Enabled_Users_3_Months__c != null && currentOpp.QS_Total_Enabled_Users_3_Months__c != 0){
				wrapper2.enableUser3Months = currentOpp.QS_TB_Licensed_Users__c / currentOpp.QS_Total_Enabled_Users_3_Months__c;
			}
			if(currentOpp.QS_Total_Enabled_Users_12_Months__c != null && currentOpp.QS_Total_Enabled_Users_12_Months__c != 0){
				wrapper2.enableUser12Months = currentOpp.QS_TB_Licensed_Users__c / currentOpp.QS_Total_Enabled_Users_12_Months__c;
			}
			if(currentOpp.QS_Unique_Timekeeper_Users_last_3_months__c != null && currentOpp.QS_Unique_Timekeeper_Users_last_3_months__c != 0){
				wrapper2.timekeeperUsage3Months = currentOpp.QS_TB_Licensed_Users__c / currentOpp.QS_Unique_Timekeeper_Users_last_3_months__c;
			}
			if(currentOpp.Unique_Timekeeper_Users_last_12_months__c != null && currentOpp.Unique_Timekeeper_Users_last_12_months__c != 0){
				wrapper2.timekeeperUsage12Months = currentOpp.QS_TB_Licensed_Users__c / currentOpp.Unique_Timekeeper_Users_last_12_months__c;
			}
		}
		// listWrappers.add(wrapper2); Commented out per Laurie's request - VP, 12/10/2012
	}
	
	public class SummaryWrapper{
		public Double enableUser3Months{get;set;}
		public Double enableUser12Months{get;set;}
		public Double timekeeperUsage3Months{get;set;}
		public Double timekeeperUsage12Months{get;set;}
	}
}