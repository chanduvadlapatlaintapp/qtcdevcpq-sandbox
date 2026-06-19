/********************************************************************************     
 *  Name             :  IntappMetadataHelper
 *  Author           :  Intapp
 *  Description      :  Helper class to assist with Metadata retrieval
 *
 *  Change history   :
 *  Date            Author                      Description
 *  12/03/15        Alan Westley                Initial release 
 ********************************************************************************/
global class IntappMetadataHelper {
	webService static List<String> GetPicklistValues(String objectname, String fieldname) {
		List<String> result = new List<String> ();

		Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
		DescribeSObjectResult objectresult = gd.get(objectname).getDescribe();
		Map<String, Schema.SObjectField> fieldMap = objectresult.fields.getMap();

		Schema.DescribeFieldResult fieldResult = fieldmap.get(fieldname).getDescribe();
		if (fieldResult.getType() == Schema.DisplayType.Picklist || fieldResult.getType() == Schema.DisplayType.MultiPicklist) {
			List<Schema.PicklistEntry> ple = fieldresult.getPicklistValues();
			for (Schema.PicklistEntry pl : ple) {
				result.add(pl.getValue());
				system.debug(pl.getValue());
			}


		}
		return result;
	}
}