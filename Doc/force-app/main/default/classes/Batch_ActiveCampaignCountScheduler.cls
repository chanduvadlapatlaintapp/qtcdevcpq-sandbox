/*********************************************************************************************************     
 *  Name             :  Batchable_ActiveCampaignCountTest
 *  Author           :  Anisha
 *  Description      :  Scheduler class for Batchable_Contact_ActiveCampaignCount
 *
 *  Change history   :
 *  Date            Author                      Description
 *  05/10/2018      Anisha Dhekne               Created
 *********************************************************************************************************/
global class Batch_ActiveCampaignCountScheduler implements Schedulable {
	/**
	 * @description Executes the scheduled Apex job. 
	 * @param sc contains the job ID
	 */
	global void execute(SchedulableContext sc) {
		String query = 'SELECT Id from Contact';
		Batchable_Contact_ActiveCampaignCount batch = new Batchable_Contact_ActiveCampaignCount(query);
		Database.executeBatch(batch);
	}
}