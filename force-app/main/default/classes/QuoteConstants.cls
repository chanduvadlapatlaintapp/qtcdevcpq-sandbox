/**
* @description Constant class for Quote
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public with sharing class QuoteConstants {
    
    // Quote Statuses
    public static final String STATUS_CONTRACT_EXECUTED = 'Contract Executed';
    public static final String STATUS_PENDING_SUBMISSION = 'Pending Submission';
    public static final String STATUS_FINALIZE_OSA = 'Finalize OSA';
    public static final String STATUS_CONFIGURE_PRODUCTS = 'Configure Products';

    // Ava tax messages
    public static final String AVA_TAX_MSG_UPTO_DATE = 'Tax Amount Is Up To Date';
    public static final String AVA_TAX_MSG_REFRESH = 'Automated Tax Calculation Triggered, Please Refresh Your Browser';
    
    //Quote Renewal Types
    public static final String RENEWAL_QUOTE_TYPE_AUTO_RENEWAL = 'Auto-Renewal';

    //Quote Types
    public static final String TYPE_QUOTE = 'Quote';
    public static final String TYPE_AMENDMENT = 'Amendment';
    public static final String TYPE_RENEWAL = 'Renewal';
    public static final String TYPE_MIGRATION_QUOTE = 'Migration Quote';
    
    //Quote Renewal Types
    public static final String RENEWAL_TYPE_AUTO = 'Auto-Renewal';
    public static final String RENEWAL_TYPE_CHANGES = 'Renewal-Changes';
    public static final String RENEWAL_TYPE_CONSOLIDATED = 'Consolidated-Quote';
    
    //Deal Types
    public static final String DEAL_TYPE_ADD_ON = 'Add-On';
    public static final String DEAL_TYPE_CONTRACT_REPLACEMENT = 'Contract_Replacement';
    public static final String DEAL_TYPE_NEW_SOFTWARE = 'New_Software';
    public static final String DEAL_TYPE_UPLIFT = 'Uplift';
    
    //Approval Statuses
    public static final String STATUS_APPROVED = 'Approved';
}