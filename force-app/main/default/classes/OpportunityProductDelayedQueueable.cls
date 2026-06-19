/**
 * @description  Queueable class responsible for publishing
 *              OpportunityLineItem events to the integration layer
 *              after a delayed execution.
 * @jira	BIZ-76622
 * @author 	Manisha
 */
public class OpportunityProductDelayedQueueable implements Queueable {

    /* =====================================================================
     * INSTANCE VARIABLES
     * ===================================================================== */

    /**
     * @description List of OpportunityLineItem records to be published.
     *              This list is treated as a read-only payload and is
     *              serialized at the time the Queueable is enqueued.
     */
    private List<OpportunityLineItem> oliList;

    /**
     * @description Integration event type to be sent
     *              (e.g. 'Delete', 'Cancelled').
     */
    private String eventType;

    /* =====================================================================
     * CONSTRUCTOR
     * ===================================================================== */

    /**
     * @description Initializes the queueable job with the OLI payload
     *              and the corresponding integration event type.
     *
     * @param oliList   List of OpportunityLineItem records to publish
     * @param eventType Integration event type identifier
     */
    public OpportunityProductDelayedQueueable( List<OpportunityLineItem> oliList, String eventType) {
        this.oliList = oliList;
        this.eventType = eventType;
    }

    /* =====================================================================
     * QUEUEABLE EXECUTION
     * ===================================================================== */

    /**
     * @description Executes the queueable job.
     *              Safely exits if no OpportunityLineItem records are present.
     *              Publishes the records to the integration layer using
     *              IntegrationUtility.
     *
     * @param qc QueueableContext provided by the Salesforce platform
     */
    public void execute(QueueableContext qc) {

        // Guard clause: nothing to process
        if (oliList == null || oliList.isEmpty()) {
            return;
        }

        // Publish read-only payload to integration (Outbound Message)
        IntegrationUtility.publishsObjectRecords(
            oliList,
            'OpportunityLineItem',
            eventType
        );
    }
}