public class IntappPSAUtils {
	private static Map<String, TaskCode_Phase_Map__c> f_TaskCodePhaseMap = null;
	
	//Convert a taskCode string into a Phase number based on TaskCode_Phase_Map__c custom setting
	public static String GetPhaseForTaskCode(string taskCode, string activePhase) {
		if (f_TaskCodePhaseMap == null)
		{
			f_TaskCodePhaseMap = TaskCode_Phase_Map__c.getall();
		}

		string phase = f_TaskCodePhaseMap.get(taskCode.substring(0, 4)).Phase__c;
		if (phase == 'CROSS') { return activePhase; }
		else { return phase; }
	}
}