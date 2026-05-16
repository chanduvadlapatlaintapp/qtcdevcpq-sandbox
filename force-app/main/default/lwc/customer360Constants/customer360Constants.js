/**
 * @description Shared constants for the Customer 360 application.
 *              Colors, product catalogs, firm names, status enums, and icon mappings.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

// ─── Health Score Color Thresholds ───────────────────────────────────────────
export const HEALTH_THRESHOLDS = {
    GOOD: 75,
    FAIR: 60,
    POOR: 40
};

export const HEALTH_COLORS = {
    GOOD: '#04844B',
    FAIR: '#FFB75D',
    POOR: '#E3524F',
    CRITICAL: '#C23934'
};

export const HEALTH_LABELS = {
    GOOD: 'Healthy',
    FAIR: 'Fair',
    POOR: 'At Risk',
    CRITICAL: 'Critical'
};

// ─── Theme Colors ────────────────────────────────────────────────────────────
export const THEME = {
    BG_DARK: '#1B2A4A',
    BG_DARK_HOVER: '#243759',
    BG_SIDEBAR: '#F4F6F9',
    BG_WHITE: '#FFFFFF',
    TEXT_DARK: '#181818',
    TEXT_MUTED: '#706E6B',
    TEXT_INVERSE: '#FFFFFF',
    BORDER: '#E5E5E5',
    PRIMARY: '#0176D3',
    PRIMARY_DARK: '#014486',
    SUCCESS: '#04844B',
    WARNING: '#FFB75D',
    ERROR: '#EA001E',
    INFO: '#0176D3',
    ACCENT_PURPLE: '#9050E9',
    ACCENT_TEAL: '#04A793'
};

// ─── Risk Levels ─────────────────────────────────────────────────────────────
export const RISK_LEVELS = {
    LOW: { label: 'Low', color: '#04844B', variant: 'success' },
    MEDIUM: { label: 'Medium', color: '#FFB75D', variant: 'warning' },
    HIGH: { label: 'High', color: '#E3524F', variant: 'error' },
    CRITICAL: { label: 'Critical', color: '#C23934', variant: 'error' }
};

// ─── Segments ────────────────────────────────────────────────────────────────
export const SEGMENTS = ['Enterprise', 'Mid-Market', 'SMB'];

export const SEGMENT_COLORS = {
    Enterprise: '#0176D3',
    'Mid-Market': '#9050E9',
    SMB: '#04A793'
};

// ─── Industries ──────────────────────────────────────────────────────────────
export const INDUSTRIES = [
    'Legal', 'Accounting', 'Consulting', 'Financial Services',
    'Private Equity', 'Investment Banking', 'Real Estate', 'Insurance'
];

// ─── Intapp Products ─────────────────────────────────────────────────────────
export const PRODUCTS = [
    { name: 'DealCloud', category: 'Deal Management' },
    { name: 'Interact', category: 'Relationship Intelligence' },
    { name: 'Open Portal', category: 'Client Portal' },
    { name: 'Intake', category: 'New Business Intake' },
    { name: 'Walls', category: 'Information Barriers' },
    { name: 'Time', category: 'Time Entry' },
    { name: 'Conflicts', category: 'Conflicts Management' },
    { name: 'Terms', category: 'Engagement Letters' }
];

export const PRODUCT_FEATURES = {
    DealCloud: [
        'Pipeline Management', 'Reporting Suite', 'Email Integration',
        'Mobile App', 'Document Management', 'Workflow Automation'
    ],
    Interact: [
        'Relationship Mapping', 'Activity Capture', 'Email Sync',
        'Analytics Dashboard', 'CRM Integration', 'Mobile Access'
    ],
    'Open Portal': [
        'Client Portal', 'Document Sharing', 'Secure Messaging',
        'Status Tracking', 'Custom Branding'
    ],
    Intake: [
        'New Matter Intake', 'Approval Workflows', 'Conflict Checks',
        'Risk Assessment', 'Reporting'
    ],
    Walls: [
        'Information Barriers', 'Screen Management', 'Audit Tracking',
        'Automated Enforcement', 'Compliance Reporting'
    ],
    Time: [
        'Time Capture', 'Timer Widget', 'Mobile Entry',
        'Calendar Integration', 'Narrative Templates'
    ],
    Conflicts: [
        'Search Engine', 'Automated Screening', 'Waiver Management',
        'Reporting Suite', 'Integration Hub'
    ],
    Terms: [
        'Template Library', 'Approval Workflows', 'E-Signature',
        'Clause Management', 'Compliance Tracking'
    ]
};

// ─── Firm Names (realistic law/professional services firms) ──────────────────
export const FIRM_NAMES = [
    'Morrison & Foerster LLP', 'Kirkland & Ellis LLP', 'Latham & Watkins LLP',
    'Skadden Arps Slate Meagher & Flom', 'Sullivan & Cromwell LLP',
    'Davis Polk & Wardwell LLP', 'Cravath Swaine & Moore LLP',
    'Simpson Thacher & Bartlett LLP', 'Wachtell Lipton Rosen & Katz',
    'Cleary Gottlieb Steen & Hamilton', 'Paul Weiss Rifkind Wharton & Garrison',
    'Gibson Dunn & Crutcher LLP', 'Debevoise & Plimpton LLP',
    'Sidley Austin LLP', 'White & Case LLP', 'Milbank LLP',
    'Willkie Farr & Gallagher LLP', 'Fried Frank Harris Shriver & Jacobson',
    'Ropes & Gray LLP', 'Goodwin Procter LLP', 'Hogan Lovells',
    'Baker McKenzie', 'DLA Piper', 'Norton Rose Fulbright',
    'Allen & Overy', 'Clifford Chance LLP', 'Freshfields Bruckhaus Deringer',
    'Linklaters LLP', 'Slaughter and May', 'Ashurst LLP',
    'Weil Gotshal & Manges LLP', 'Proskauer Rose LLP',
    'King & Spalding LLP', 'Akin Gump Strauss Hauer & Feld',
    'Dechert LLP', 'Morgan Lewis & Bockius LLP'
];

// ─── CSM Names ───────────────────────────────────────────────────────────────
export const CSM_NAMES = [
    'Sarah Chen', 'Michael Torres', 'Jessica Park', 'David Kim',
    'Amanda Rodriguez', 'Chris Johnson', 'Rachel Green', 'James Wilson'
];

// ─── CTA Types ───────────────────────────────────────────────────────────────
export const CTA_TYPES = {
    risk: { label: 'Risk', icon: 'utility:warning', color: '#EA001E' },
    expansion: { label: 'Expansion', icon: 'utility:trending', color: '#04844B' },
    renewal: { label: 'Renewal', icon: 'utility:refresh', color: '#0176D3' },
    lifecycle: { label: 'Lifecycle', icon: 'utility:steps', color: '#9050E9' },
    activity: { label: 'Activity', icon: 'utility:task', color: '#04A793' }
};

export const CTA_PRIORITIES = {
    critical: { label: 'Critical', color: '#C23934' },
    high: { label: 'High', color: '#EA001E' },
    medium: { label: 'Medium', color: '#FFB75D' },
    low: { label: 'Low', color: '#706E6B' }
};

export const CTA_STATUSES = ['open', 'in_progress', 'completed', 'snoozed'];

export const CTA_TAGS = [
    { value: 'executive_escalation', label: 'Executive Escalation' },
    { value: 'renewal_risk', label: 'Renewal Risk' },
    { value: 'upsell', label: 'Upsell Opportunity' },
    { value: 'onboarding', label: 'Onboarding' },
    { value: 'training', label: 'Training Needed' },
    { value: 'champion_change', label: 'Champion Change' },
    { value: 'product_gap', label: 'Product Gap' },
    { value: 'strategic', label: 'Strategic' }
];

// ─── Timeline Event Types ────────────────────────────────────────────────────
export const TIMELINE_TYPES = {
    meeting: { label: 'Meeting', icon: 'standard:event', color: '#0176D3' },
    email: { label: 'Email', icon: 'standard:email', color: '#9050E9' },
    note: { label: 'Note', icon: 'standard:note', color: '#04A793' },
    call: { label: 'Call', icon: 'standard:log_a_call', color: '#FFB75D' },
    milestone: { label: 'Milestone', icon: 'standard:task2', color: '#04844B' },
    cta: { label: 'CTA', icon: 'standard:task', color: '#EA001E' },
    escalation: { label: 'Escalation', icon: 'standard:case_escalation', color: '#C23934' }
};

// ─── Alert Types ─────────────────────────────────────────────────────────────
export const ALERT_TYPES = {
    risk: { label: 'Churn Risk', icon: 'utility:warning', color: '#EA001E', bgColor: '#FEF0EF' },
    usage_decline: { label: 'Usage Decline', icon: 'utility:trending_down', color: '#E3524F', bgColor: '#FEF3F2' },
    health_change: { label: 'Health Change', icon: 'utility:heartbeat', color: '#FFB75D', bgColor: '#FFF8E6' },
    renewal: { label: 'Renewal', icon: 'utility:date_time', color: '#0176D3', bgColor: '#EEF4FF' },
    task_due: { label: 'Task Due', icon: 'utility:task', color: '#9050E9', bgColor: '#F3EDFF' }
};

// ─── Health Score Factors ────────────────────────────────────────────────────
export const HEALTH_FACTORS = [
    { key: 'productAdoption', name: 'Product Adoption', weight: 0.25, icon: 'utility:package' },
    { key: 'supportHealth', name: 'Support Health', weight: 0.20, icon: 'utility:case' },
    { key: 'engagement', name: 'Engagement', weight: 0.20, icon: 'utility:people' },
    { key: 'financialHealth', name: 'Financial Health', weight: 0.15, icon: 'utility:moneybag' },
    { key: 'relationship', name: 'Relationship', weight: 0.10, icon: 'utility:heart' },
    { key: 'outcomes', name: 'Outcomes', weight: 0.10, icon: 'utility:target' }
];

// ─── Subscription Statuses ───────────────────────────────────────────────────
export const SUBSCRIPTION_STATUSES = ['Active', 'Pending', 'Expiring', 'Expired', 'Cancelled'];

// ─── Invoice Statuses ────────────────────────────────────────────────────────
export const INVOICE_STATUSES = ['Paid', 'Open', 'Overdue', 'Partially Paid', 'Void'];

// ─── Ticket Statuses ─────────────────────────────────────────────────────────
export const TICKET_STATUSES = ['New', 'Open', 'Pending', 'Hold', 'Solved', 'Closed'];
export const TICKET_PRIORITIES = ['Low', 'Normal', 'High', 'Urgent'];
export const TICKET_TYPES = ['Question', 'Incident', 'Problem', 'Task'];

// ─── Month Labels ────────────────────────────────────────────────────────────
export const MONTH_LABELS = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

// ─── NPS Categories ──────────────────────────────────────────────────────────
export const NPS_CATEGORIES = {
    PROMOTER: { min: 9, label: 'Promoter', color: '#04844B' },
    PASSIVE: { min: 7, label: 'Passive', color: '#FFB75D' },
    DETRACTOR: { min: 0, label: 'Detractor', color: '#EA001E' }
};

// ─── Product Pricebook (spec-aligned SKUs, categories, base values) ─────────
export const PRICEBOOK = [
    { sku: 'INTAPP-DW-ENT', product: 'DealCloud', category: 'Deal Management', baseValue: 85000 },
    { sku: 'INTAPP-TM-ENT', product: 'Time', category: 'Time Management', baseValue: 45000 },
    { sku: 'INTAPP-CF-ENT', product: 'Conflicts', category: 'Risk & Compliance', baseValue: 62000 },
    { sku: 'INTAPP-IN-ENT', product: 'Intake', category: 'Risk & Compliance', baseValue: 55000 },
    { sku: 'INTAPP-CL-PRO', product: 'Collaborate', category: 'Collaboration', baseValue: 38000 },
    { sku: 'INTAPP-WF-STD', product: 'Walls', category: 'Information Barriers', baseValue: 42000 }
];

export const TIER_MULTIPLIERS = {
    Enterprise: 1.8,
    Professional: 1.2,
    Standard: 1.0
};

// ─── Usage Rating Tiers ─────────────────────────────────────────────────────
export const USAGE_RATING_TIERS = [
    { tier: 'Platinum', min: 85, color: '#a855f7' },
    { tier: 'Gold', min: 70, color: '#f59e0b' },
    { tier: 'Silver', min: 50, color: '#94a3b8' },
    { tier: 'Bronze', min: 30, color: '#cd7f32' },
    { tier: 'At Risk', min: 0, color: '#ef4444' }
];

// ─── Usage Rating Weight Factors ────────────────────────────────────────────
export const USAGE_RATING_WEIGHTS = {
    licenseUtil: 0.25,
    overUsagePenalty: 0.15,
    loginPct: 0.25,
    activityPct: 0.15,
    personaBreadth: 0.20
};

// ─── Login Channels ─────────────────────────────────────────────────────────
export const LOGIN_CHANNELS = [
    'Portal', 'Excel', 'Word', 'Outlook', 'Mobile', 'Reports', 'Notifications'
];

// ─── Persona Definitions (from op4i schema — 15 personas, account-wide) ─────
export const PERSONAS = [
    { key: 'Associate', label: 'Associate' },
    { key: 'BusinessDevelopment', label: 'Business Development' },
    { key: 'DataSteward', label: 'Data Steward' },
    { key: 'DataStewardPS', label: 'Data Steward (PS)' },
    { key: 'DealDriver', label: 'Deal Driver' },
    { key: 'GateKeeper', label: 'Gate Keeper' },
    { key: 'Leadership', label: 'Leadership' },
    { key: 'Marketing', label: 'Marketing' },
    { key: 'Partner', label: 'Partner' },
    { key: 'PSOther', label: 'PS Other' },
    { key: 'RoadWarrior', label: 'Road Warrior' },
    { key: 'SupportStaff', label: 'Support Staff' },
    { key: 'SystemAdministrator', label: 'System Administrator' },
    { key: 'TacticalPlayer', label: 'Tactical Player' },
    { key: 'TimeKeeperNonLawyer', label: 'Time Keeper (Non-Lawyer)' }
];

// ─── User Groups ────────────────────────────────────────────────────────────
export const USER_GROUPS = [
    'Partners', 'Associates', 'Business Development', 'Support Staff', 'IT Admin'
];

// ─── Support Assignees ──────────────────────────────────────────────────────
export const SUPPORT_ASSIGNEES = [
    'Alex Rivera', 'Jordan Lee', 'Priya Sharma', 'Chris Anderson', 'Taylor Morgan'
];

// ─── Support Ticket Subjects ────────────────────────────────────────────────
export const TICKET_SUBJECTS = [
    'SSO login failing intermittently', 'Cannot export data to CSV',
    'Bulk import validation errors', 'Slow performance on large searches',
    'Data sync delay between environments', 'Mobile app crash on iOS 18',
    'Workflow configuration not triggering', 'Ethical wall rule not applying',
    'API rate limit exceeded during batch ops', 'Dashboard loading timeout',
    'DocuSign integration disconnected', 'Time entry rounding issue',
    'Conflict search returning false positives', 'User permissions not propagating',
    'Training environment access request', 'Report scheduling failures',
    'Custom field mapping lost after update', 'Audit log missing entries',
    'Password reset email not arriving', 'Browser compatibility issue with Edge'
];

// ─── Source Badges ──────────────────────────────────────────────────────────
export const SOURCE_BADGES = {
    salesforce: { label: 'Salesforce', color: '#00A1E0', bg: '#E6F6FE' },
    zendesk: { label: 'Zendesk', color: '#03363D', bg: '#E6F0F1' },
    netsuite: { label: 'NetSuite', color: '#1B3A4B', bg: '#E8EEF1' },
    ianlite: { label: 'IanLite', color: '#8b5cf6', bg: '#F3EDFF' }
};

// ─── Shared Design Tokens (from spec) ───────────────────────────────────────
export const DESIGN = {
    TEAL: '#207CEC',
    NAVY: '#1C2B40',
    BG: '#f5f7fa',
    BORDER: '#e2e8f0',
    GREEN: '#10b981',
    AMBER: '#f59e0b',
    RED: '#ef4444',
    PURPLE: '#8b5cf6',
    GRADIENT: 'linear-gradient(135deg, #207CEC, #22ECCF)'
};

// ─── Invoice Statuses (spec-aligned) ────────────────────────────────────────
export const INVOICE_STATUS_CONFIG = {
    Paid: { color: '#10b981', bg: '#10b98115' },
    Overdue: { color: '#ef4444', bg: '#ef444415' },
    Pending: { color: '#f59e0b', bg: '#f59e0b15' },
    Partial: { color: '#207CEC', bg: '#207CEC15' }
};

// ─── Ticket Status Config (spec-aligned) ────────────────────────────────────
export const TICKET_STATUS_CONFIG = {
    Open: { color: '#207CEC', bg: '#207CEC15' },
    Pending: { color: '#f59e0b', bg: '#f59e0b15' },
    Solved: { color: '#10b981', bg: '#10b98115' },
    Closed: { color: '#94a3b8', bg: '#94a3b815' }
};

// ─── Ticket Priority Config (spec-aligned) ──────────────────────────────────
export const TICKET_PRIORITY_CONFIG = {
    Critical: { color: '#ef4444', dot: '#ef4444' },
    High: { color: '#f59e0b', dot: '#f59e0b' },
    Medium: { color: '#207CEC', dot: '#207CEC' },
    Low: { color: '#94a3b8', dot: '#94a3b8' }
};

// ─── Subscription Status Config (spec-aligned) ─────────────────────────────
export const SUBSCRIPTION_STATUS_CONFIG = {
    Active: { color: '#10b981', bg: '#10b98115', icon: 'check' },
    Expired: { color: '#ef4444', bg: '#ef444415', icon: 'close' },
    Pending: { color: '#f59e0b', bg: '#f59e0b15', icon: 'clock' }
};