/**
* @description Constant Class for Contract object
* @author Suresh Somu
* @jira BIZ-66216
**/
public with sharing class ContractConstants {
    
    // Contract statuses
    public static final String STATUS_INFORCE = 'In Force';
    public static final String STATUS_DRAFT = 'Draft quote by salesperson';
    public static final String STATUS_ACTIVATED = 'Activated';
    public static final String STATUS_CANCELLED_LAPSED = 'Cancelled / Lapsed';
    public static final String STATUS_SUPERSEDED_BY_NEWER_CONTRACT = 'Superseded by Newer Contract';
    public static final String STATUS_PARTIALLY_SUPERSEDED = 'Partially Cancelled or superseded';
    
    
    // CPQ Contract Status values (BIZ-68170)
    public static final String CPQ_STATUS_NOT_STARTED = 'Not Started';
    public static final String CPQ_STATUS_ACTIVE = 'Active';
    public static final String CPQ_STATUS_LAPSED = 'Lapsed';

    // OSA Status values that force CPQ Contract Status to Lapsed
    public static final Set<String> LAPSED_TRIGGER_STATUSES = new Set<String>{
        STATUS_CANCELLED_LAPSED,
        STATUS_SUPERSEDED_BY_NEWER_CONTRACT
    };

    // Deal Type
    public static final String DEAL_TYPE_PARTNER_FEE = 'Partner_Fee';
    public static final String DEAL_TYPE_ADD_ON = 'Add-On';

    // Deal Type
    public static final String CONTRACT_JOB_STATUS_AUTOMATION_INITIATED = 'Automation Initiated';
    public static final String CONTRACT_JOB_STATUS_MIGRATES_ISSUE = 'Renewal not allowed on Migrated Add-on Contracts. Those cannot be renewed';
}