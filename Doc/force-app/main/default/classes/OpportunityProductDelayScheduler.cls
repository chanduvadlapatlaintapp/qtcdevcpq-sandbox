/**
 * @description Schedulable class responsible for introducing a controlled
 *              delay before publishing OpportunityLineItem events to the
 *              integration layer.
 * @jira       BIZ-76622
 * @author     Manisha
 */
public class OpportunityProductDelayScheduler implements Schedulable {

    /* =====================================================================
     * INSTANCE VARIABLES
     * ===================================================================== */

    /**
     * @description Snapshot of OpportunityLineItem records captured from
     *              the trigger context. These records are treated as a
     *              read-only payload and passed directly to the Queueable.
     */
    private List<OpportunityLineItem> oliList;

    /**
     * @description Integration event type to be published
     *              (e.g. 'Delete', 'Cancelled').
     */
    private String eventType;

    /* =====================================================================
     * CONSTRUCTORS
     * ===================================================================== */

    /**
     * @description Required no-argument constructor for Schedulable
     *              execution. Salesforce uses this constructor when
     *              instantiating the job at runtime.
     */
    public OpportunityProductDelayScheduler() {}

    /**
     * @description Initializes the scheduler with the OpportunityLineItem
     *              payload and corresponding integration event type.
     *
     * @param oliList   List of OpportunityLineItem records to publish
     * @param eventType Integration event type identifier
     */
    public OpportunityProductDelayScheduler(
        List<OpportunityLineItem> oliList,
        String eventType
    ) {
        this.oliList = oliList;
        this.eventType = eventType;
    }

    /* =====================================================================
     * SCHEDULABLE EXECUTION
     * ===================================================================== */

    /**
     * @description Entry point for the scheduled job.
     *              Enqueues the Queueable job which performs the actual
     *              integration publish.
     *
     * @param sc SchedulableContext provided by the Salesforce platform
     */
    public void execute(SchedulableContext sc) {
        System.enqueueJob(
            new OpportunityProductDelayedQueueable(oliList, eventType)
        );
    }

    /* =====================================================================
     * PUBLIC API
     * ===================================================================== */

    /**
     * @description Schedules a one-time job to execute after the specified
     *              number of minutes. This method is typically invoked
     *              from trigger helper logic.
     *
     * @param minutes   Delay duration in minutes
     * @param oliList   List of OpportunityLineItem records to publish
     * @param eventType Integration event type identifier
     */
    public static void scheduleAfterMinutes(Integer minutes,List<OpportunityLineItem> oliList,String eventType) {
        Datetime runTime = System.now().addMinutes(minutes);

        System.schedule(
            'OPP_PROD_DELAY_' + runTime.getTime(),
            buildCron(runTime),
            new OpportunityProductDelayScheduler(oliList, eventType)
        );
    }

    /* =====================================================================
     * HELPER METHODS
     * ===================================================================== */

    /**
     * @description Builds a CRON expression for a specific Datetime.
     *              Used to create a one-time scheduled execution.
     *
     * @param dt Datetime at which the job should execute
     * @return   CRON expression string
     */
    private static String buildCron(Datetime dt) {
        return String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(dt.minute()),
                String.valueOf(dt.hour()),
                String.valueOf(dt.day()),
                String.valueOf(dt.month()),
                String.valueOf(dt.year())
            }
        );
    }
}