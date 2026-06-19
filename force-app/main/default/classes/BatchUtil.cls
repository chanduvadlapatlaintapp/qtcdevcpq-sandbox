/**
 * @author Sahal Mohamed
 * @date 02/12/2025
 * @description utility class for batch or scheduler operations
 **/
public inherited sharing class BatchUtil {
    
    /**
     * @description This is used to generate the cron for next fire time based on the params
     * @param addnlHour
     * @param addnlMin
     * @param addnlSec
     * @return String
     */
    public static String getNextFireTime(Integer addnlHour, Integer addnlMin, Integer addnlSec) {
        // Get the current datetime  
        Datetime now = Datetime.now();  
        Integer newMin = now.minute() + addnlMin;  
        Integer newHour = now.hour() + addnlHour;  
        Integer newSec = now.second() + addnlSec;  
        
        // Adjust seconds and increment minute if needed  
        if (newSec >= 60) {
            newSec -= 60; // Reset seconds within 0-59 range  
            newMin += 1; // Increment minute  
        }
        
        // Adjust minutes and increment hour if needed  
        if (newMin >= 60) {  
            newMin -= 60; // Reset minutes within 0-59 range  
            newHour += 1; // Increment hour  
        }  
        
        // Ensure hour stays within 0-23 range (not strictly needed for this case)  
        if (newHour >= 24) {  
            newHour -= 24;  
        }  
        
        String min = String.valueOf(newMin);  
        String hour = String.valueOf(newHour);  
        String ss = String.valueOf(newSec);  
        
        // Construct valid cron expression  
        String nextFireTime = ss + ' ' + min + ' ' + hour + ' * * ?';  
        return nextFireTime;
    }

    /**
     * @description This returns the CronTrigger record based on the job name
     * @param cronJobName
     * @return CronTrigger
     */
    public static CronTrigger getCronTrigger(String cronJobName) {
        String compareString = '%' + cronJobName + '%';
        CronTrigger cronTrigger;
        for(CronTrigger cron : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :compareString ORDER BY CreatedDate DESC LIMIT 1]) {
            cronTrigger = cron;
        }
        return cronTrigger;
    } 
}