public with sharing class ProductNewsController {
	
	public String recordLimit{get;set;}
	public String recordTypeName{get;set;}

	public List<News_Alert__c> getNewsAlerts () {
		String qry = 'Select n.Product_Line__r.Practice__c, n.Product_Line__r.Name, n.Product_Line__c, n.Name, n.Content__c, CreatedDate'; 
		qry += ' From News_Alert__c n';
		qry += ' Where recordType.developerName = :recordTypeName';
		qry += ' Order by CreatedDate desc '; 
		qry += 'limit ' + recordLimit;
		return (List<News_Alert__c>) Database.query(qry);
	}

	private static testMethod void testProductController() {
	  	ProductNewsController ctrl = new ProductNewsController();
	  	ctrl.recordTypeName = 'News';
	  	ctrl.recordLimit = '10';
	  	ctrl.getNewsAlerts();
	  	
	  }

/*
//Returns list of Alert Strings
public List<String> getlstNewsAlerts () {
	mapNewsAndAlerts = new Map<String, List<News_Alert__c>> ();
String qry = 'Select n.Product_Line__r.Practice__c, n.Product_Line__r.Name, n.Product_Line__c, n.Name, n.Content__c, CreatedDate'; 
qry += ' From News_Alert__c n';
qry += ' Where recordType.Name = ' + recordTypeName;
qry += ' Order by CreatedDate desc '; 
qry += 'limit ' + recordLimit;

List<String> createdDates = new List<String> ();
for (News_Alert__c news : (List<News_Alert__c>) Database.query(qry)) {
	String createdDate = news.createdDate.format('MM/dd/yyyy');
	if (!mapNewsAndAlerts.containsKey(createdDate)) {
		mapNewsAndAlerts.put(createdDate, new List<News_Alert__c> ());
		createdDates.add(createdDate);
	}
	mapNewsAndAlerts.get(createdDate).add(news);
	
}

	return createdDates;
}*/

}