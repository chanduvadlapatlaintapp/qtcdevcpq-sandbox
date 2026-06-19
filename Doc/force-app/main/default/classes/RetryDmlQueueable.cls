/**
 * @description
 * Queueable class responsible for retrying failed DML operations on a set of records.
 * This class attempts to update the provided records and handles transient failures,
 * such as row lock or flow execution conflicts, by scheduling controlled retries
 * via RetryScheduler.
 *
 * Retry behavior is governed by a maximum retry threshold and an incremental delay
 * strategy to avoid immediate contention. All retry attempts and terminal failures
 * are logged using the Nebula logging framework for traceability and diagnostics.
 *
 * After successful retry for ContractOrderBatch context, this class triggers 
 * ContractCreationTrackerQueueable to ensure downstream renewal letter updates
 * are properly executed.
 *
 * @author Manisha
 * @jira BIZ-78056
 */
public without sharing class RetryDmlQueueable implements Queueable {

    /***********************************************************************************************
     *
     * CONSTANTS
     *
     ***********************************************************************************************/
    
    private static final Integer MAX_RETRIES = 3;
    private static final String CONTEXT_CONTRACT_ORDER_BATCH = 'ContractOrderBatch';

    /***********************************************************************************************
     *
     * PROPERTIES
     *
     ***********************************************************************************************/

    @TestVisible
    private static Boolean forceTestLockException = false;
    
    private List<SObject> records;
    private Integer attempt;
    private String context;

    /***********************************************************************************************
     *
     * CONSTRUCTORS
     *
     ***********************************************************************************************/

    /**
     * @description Constructor for RetryDmlQueueable
     * @param records List of SObject records to retry DML operation on
     * @param attempt Current retry attempt number (1-based)
     * @param context String identifier for the calling context (e.g., 'ContractOrderBatch')
     */
    public RetryDmlQueueable(List<SObject> records, Integer attempt, String context) {
        this.records = records;
        this.attempt = attempt;
        this.context = context;
    }

    /***********************************************************************************************
     *
     * QUEUEABLE METHODS
     *
     ***********************************************************************************************/

    /**
     * @description Executes the retry logic for failed DML operations.
     *              Attempts to update records and handles lock exceptions by scheduling
     *              another retry via RetryScheduler if under MAX_RETRIES threshold.
     *              On success, triggers context-specific post-retry actions.
     * @param qc QueueableContext provided by the system
     */
    public void execute(QueueableContext qc) {
        if (records == null || records.isEmpty()) {
            Nebula.Logger.warn('RetryDmlQueueable called with empty records | Context=' + context);
            Nebula.Logger.saveLog();
            return;
        }

        try {
            if (Test.isRunningTest() && forceTestLockException) {
                throw new DmlException('UNABLE_TO_LOCK_ROW simulated for test');
            }
            update records;
            Nebula.Logger.info('Retry success | Context=' + context + ' | Attempt=' + attempt);
            
            // Trigger downstream processing for successfully retried orders
            executePostRetryActions();

        } catch (DmlException e) {
            if (isLockException(e) && attempt < MAX_RETRIES) {
                Integer delaySeconds = attempt * 120; // 2, 4, 6 mins
                String jobName = buildUniqueJobName();
                System.schedule(jobName, buildCron(delaySeconds), new RetryScheduler(records, attempt + 1, context));
                Nebula.Logger.info('Retry scheduled | Context=' + context + ' | Attempt=' + (attempt + 1) + ' | JobName=' + jobName);
            } else {
                Nebula.Logger.error('Retry failed permanently | Context=' + context + ' | Attempts=' + attempt, records, e);
            }
        }
        Nebula.Logger.saveLog();
    }

    /***********************************************************************************************
     *
     * PRIVATE METHODS
     *
     ***********************************************************************************************/

    /**
     * @description Executes post-retry actions based on context.
     *              For ContractOrderBatch, triggers ContractCreationTrackerQueueable
     *              to update renewal letters for successfully contracted orders.
     */
    private void executePostRetryActions() {
        if (context == CONTEXT_CONTRACT_ORDER_BATCH && records[0] instanceof Order) {
            List<Order> orders = (List<Order>) records;
            System.enqueueJob(new ContractCreationTrackerQueueable(orders), 10);
            Nebula.Logger.info('ContractCreationTrackerQueueable enqueued for ' + orders.size() + ' orders after successful retry');
        }
    }
    
    /**
     * @description Determines if the exception is a lock-related exception that warrants retry
     * @param e The exception to evaluate
     * @return Boolean true if exception is UNABLE_TO_LOCK_ROW or CANNOT_EXECUTE_FLOW_TRIGGER
     */
    private Boolean isLockException(Exception e) {
        return e.getMessage().contains('UNABLE_TO_LOCK_ROW')
            || e.getMessage().contains('CANNOT_EXECUTE_FLOW_TRIGGER');
    }

    /**
     * @description Builds a unique job name using context, timestamp, and first record ID
     *              to prevent potential name collisions when scheduling retries
     * @return String unique scheduled job name in format 'Retry-{context}-{timestamp}-{recordId}'
     */
    private String buildUniqueJobName() {
        String recordId = records[0].Id != null ? String.valueOf(records[0].Id).substring(0, 15) : 'new';
        return 'Retry-' + context + '-' + System.now().getTime() + '-' + recordId;
    }

    /**
     * @description Builds a cron expression for scheduling a retry after specified delay
     * @param delaySeconds Number of seconds to delay before retry execution
     * @return String cron expression in format 's m H d M ? yyyy'
     */
    private String buildCron(Integer delaySeconds) {
        Datetime dt = System.now().addSeconds(delaySeconds);
        return dt.format('s m H d M ? yyyy');
    }
}