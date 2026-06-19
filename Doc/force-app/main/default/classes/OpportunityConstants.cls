/**
* @description Constant class for Opportunity object
* @author Sahal Mohamed
* @jira BIZ-66216
**/
public with sharing class OpportunityConstants {
    
    // Stages
    public static final String STAGE_CLOSED_WON = 'Closed Won';
    public static final String STAGE_CLOSED_LOST = 'Closed Lost';
    public static final String STAGE_PENDING_CANCELLATION = 'Pending Cancellation';
    public static final String STAGE_PROSPECTING = 'Prospecting';
    public static final String STAGE_CLOSED_SUPERSEDED = 'Closed - Superseded By New Contract';
    public static final String STAGE_QUALIFY = 'Qualify';
    public static final String STAGE_VERIFY = 'Verify';
    public static final String STAGE_POSITION = 'Position';
    public static final String STAGE_PROPOSE = 'Propose';
    public static final String STAGE_SELECTED = 'Selected';
    public static final String STAGE_PENDINGCLOSURE = 'Pending Closure';
    public static final String STAGE_PRE_SHOPPING = 'Pre-Shopping'; // BIZ-73256: Sales Nurture removed, Pre-Shopping added
    public static final String STAGE_CLOSED_SHOULD_NEVER_HAVE_OPENED = 'Closed - Should Never have been opened';

    // Record Types
    public static final String RT_MIGRATION_OPP = 'Migration_Opportunity';
    public static final String RT_LEGAL_CANCELLATION = 'Legal_Cancellation';

    // Types
    public static final String TYPE_AMENDMENT = 'Amendment';
    public static final String TYPE_RENEWAL = 'Renewal';

    // Deal Types
    public static final String DEAL_TYPE_ADDON = 'Add-On';
    public static final String DEAL_TYPE_NEWSOFTWARE = 'New_Software';
    public static final String DEAL_TYPE_NYMY = 'NextYear_MultiYear';
    public static final String DEAL_TYPE_RENEWAL = 'Renewal';
    public static final String DEAL_TYPE_CANCELLATION = 'Cancellation';
    public static final String DEAL_TYPE_AMENDMENT_TO_SUPERCEDE = 'Amendment_to_Supercede';
	public static final String DEAL_TYPE_Other = 'Other';
    public static final String DEAL_TYPE_PlatformConversion_INTERNAL = 'PlatformConversion_INTERNAL';
    public static final String DEAL_TYPE_UPLIFT = 'Uplift';
    public static final String DEAL_TYPE_EXPANSION = 'Expansion';
    
    // Closed Stages
    public static final Set<String> CLOSED_STAGES = new Set<String>{
        'Closed Won', 'Closed Lost', 'Closed - No Decision', 'Closed - Should Never have been opened', 'Closed - Merged', 'Pending Cancellation', 'Pending Superseding',
            'Closed - Superseded By New Contract'
    };

    // BIZ-82773: Renewal Opportunity stages that should cancel related Renewal Letters
    public static final Set<String> RL_CANCEL_STAGES = new Set<String>{
        'Closed Lost',
        'Closed - No Decision',
        'Closed - Merged',
        'Pending Cancellation',
        'Closed - Superseded By New Contract',
        'Closed - Should Never have been opened',
        'Closed - Deferred'
    };
}