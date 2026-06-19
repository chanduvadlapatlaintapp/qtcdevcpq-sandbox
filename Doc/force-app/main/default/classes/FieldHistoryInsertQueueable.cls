/**
 * @description Queueable class for asynchronously inserting field history records
 * @author Sahal
 * @createdDate Jan-05-2026
 */
public class FieldHistoryInsertQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Field_History__c> historyRecords;
    
    /**
     * @description Constructor
     * @param historyRecords List of Field_History__c records to insert
     */
    public FieldHistoryInsertQueueable(List<Field_History__c> historyRecords) {
        this.historyRecords = historyRecords;
    }
    
    /**
     * @description Execute method for Queueable interface
     * @param context QueueableContext
     */
    public void execute(QueueableContext context) {
        if (historyRecords == null || historyRecords.isEmpty()) {
            Nebula.Logger.debug('No history records to insert')
                .addTag('FieldHistory');
            Nebula.Logger.saveLog();
            return;
        }
        
        try {
            Nebula.Logger.info('Inserting ' + historyRecords.size() + ' field history records')
                .addTag('FieldHistory');
            
            Database.SaveResult[] results = Database.insert(historyRecords, false);
            
            Integer successCount = 0;
            Integer failureCount = 0;
            List<String> errorMessages = new List<String>();
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error error : results[i].getErrors()) {
                        errorMessages.add('Record ' + i + ': ' + error.getMessage() + ' (' + error.getStatusCode() + ')');
                    }
                }
            }
            
            if (successCount > 0) {
                Nebula.Logger.info('Successfully inserted ' + successCount + ' field history records')
                    .addTag('FieldHistory');
            }
            
            if (failureCount > 0) {
                Nebula.Logger.error('Failed to insert ' + failureCount + ' of ' + results.size() + ' field history records. Errors: ' + String.join(errorMessages, '; '))
                    .addTag('FieldHistory');
            }
            
        } catch (Exception e) {
            Nebula.Logger.error('Exception inserting field history records')
                .setExceptionDetails(e)
                .addTag('FieldHistory');
        } finally {
            Nebula.Logger.saveLog();
        }
    }
}