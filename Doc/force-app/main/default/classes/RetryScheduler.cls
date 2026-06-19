/**
 * @description
 * Scheduler class responsible for triggering retry logic for failed DML operations.
 * This class implements the Schedulable interface and delegates execution to
 * RetryDmlQueueable, passing along the records, retry attempt count, and execution context.
 *
 * The scheduler is typically invoked to reprocess records that failed in earlier
 * asynchronous or transactional flows, ensuring controlled and traceable retries.
 * This class acts as a bridge between scheduled execution and queueable processing,
 * enabling delayed retry attempts with controlled timing.
 *
 * @author Manisha
 * @jira BIZ-78056
 */
public without sharing class RetryScheduler implements Schedulable {

    /***********************************************************************************************
     *
     * PROPERTIES
     *
     ***********************************************************************************************/

    private List<SObject> records;
    private Integer attempt;
    private String context;

    /***********************************************************************************************
     *
     * CONSTRUCTORS
     *
     ***********************************************************************************************/

    /**
     * @description Constructor for RetryScheduler
     * @param records List of SObject records to retry DML operation on
     * @param attempt Current retry attempt number (1-based)
     * @param context String identifier for the calling context (e.g., 'ContractOrderBatch')
     */
    public RetryScheduler(List<SObject> records, Integer attempt, String context) {
        this.records = records;
        this.attempt = attempt;
        this.context = context;
    }

    /***********************************************************************************************
     *
     * SCHEDULABLE METHODS
     *
     ***********************************************************************************************/

    /**
     * @description Executes the scheduled job by enqueuing RetryDmlQueueable
     *              with the stored records, attempt count, and context.
     *              This method is called by the Salesforce scheduler at the scheduled time.
     * @param sc SchedulableContext provided by the system
     */
    public void execute(SchedulableContext sc) {
        System.enqueueJob(new RetryDmlQueueable(records, attempt, context));
    }
}