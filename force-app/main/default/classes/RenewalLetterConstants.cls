/**
* @description Constants Class for Renewal Letter Object
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public with sharing class RenewalLetterConstants {
    //Renewal Letter Statuses
    public static final String STATUS_INITIATED = 'Initiated';
    public static final String STATUS_WORKING_WITH_CUSTOMER = 'Working with Customer for changes'; // BIZ-82935
    public static final String STATUS_CANCELLED = 'Cancelled';

    //Activity Statuses
    public static final String ACTIVITY_STATUS_SEND_DOC_TO_CONTACT = 'Sent Document to Contact';
    public static final String ACTIVITY_STATUS_ORDER_ACTIVATED = 'Order Activated';

}