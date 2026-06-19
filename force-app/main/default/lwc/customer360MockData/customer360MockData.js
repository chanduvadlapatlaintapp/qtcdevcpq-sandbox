/**
 * @description Mock data generators for the Customer 360 application.
 *              All generators use seeded random for deterministic, consistent data.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

import {
    FIRM_NAMES, INDUSTRIES, SEGMENTS, PRODUCTS, PRODUCT_FEATURES,
    HEALTH_FACTORS, SUBSCRIPTION_STATUSES, INVOICE_STATUSES,
    TICKET_STATUSES, TICKET_PRIORITIES, TICKET_TYPES,
    CTA_TYPES, CTA_PRIORITIES, CTA_TAGS, TIMELINE_TYPES, ALERT_TYPES,
    CSM_NAMES, MONTH_LABELS,
    PRICEBOOK, TIER_MULTIPLIERS, USAGE_RATING_TIERS, USAGE_RATING_WEIGHTS,
    LOGIN_CHANNELS, PERSONAS, USER_GROUPS,
    SUPPORT_ASSIGNEES, TICKET_SUBJECTS
} from 'c/customer360Constants';

import {
    seededRandom, generateId, pickRandom, pickRandomN,
    randomInt, randomFloat, getHealthTrend, getRiskLevel,
    clamp, addDays
} from 'c/customer360Utils';

// ─── Portfolio Generator ─────────────────────────────────────────────────────

/**
 * Generate a portfolio of mock accounts for the CSM dashboard.
 * @param {string} [csmName='Sarah Chen']
 * @returns {Array<Object>} Array of account objects
 */
export function generatePortfolio(csmName = 'Sarah Chen') {
    const rng = seededRandom('portfolio-' + csmName);
    const count = randomInt(25, 32, rng);
    const accounts = [];

    for (let i = 0; i < count; i++) {
        const id = generateId('ACC', i + 1);
        const accRng = seededRandom(id);
        const healthScore = _generateRawScore(accRng);
        const previousHealth = clamp(healthScore + randomInt(-10, 10, accRng), 0, 100);
        const segment = pickRandom(SEGMENTS, accRng);
        const arr = _arrForSegment(segment, accRng);
        const products = pickRandomN(PRODUCTS.map(p => p.name), randomInt(1, 4, accRng), accRng);
        const lastContactDays = randomInt(0, 45, accRng);
        const renewalMonths = randomInt(1, 18, accRng);
        const renewalDate = new Date();
        renewalDate.setMonth(renewalDate.getMonth() + renewalMonths);

        accounts.push({
            id,
            name: FIRM_NAMES[i % FIRM_NAMES.length],
            industry: pickRandom(INDUSTRIES, accRng),
            segment,
            region: pickRandom(['North America', 'EMEA', 'APAC'], accRng),
            csm: csmName,
            arr,
            healthScore,
            previousHealthScore: previousHealth,
            healthTrend: getHealthTrend(healthScore, previousHealth),
            riskLevel: getRiskLevel(healthScore),
            renewalDate: renewalDate.toISOString().split('T')[0],
            nps: randomInt(1, 10, accRng),
            openCtas: randomInt(0, 6, accRng),
            lastContactDate: addDays(new Date(), -lastContactDays).toISOString().split('T')[0],
            daysSinceContact: lastContactDays,
            products,
            productCount: products.length,
            logo: null
        });
    }

    return accounts;
}

// ─── Health Score Generator ──────────────────────────────────────────────────

/**
 * Generate detailed health score breakdown for an account.
 * @param {string} accountId
 * @returns {Object} Health score with factor breakdown
 */
export function generateHealthScore(accountId) {
    const rng = seededRandom('health-' + accountId);
    const factors = HEALTH_FACTORS.map(factor => {
        const score = _generateRawScore(rng);
        const prevScore = clamp(score + randomInt(-12, 12, rng), 0, 100);
        return {
            key: factor.key,
            name: factor.name,
            score,
            weight: factor.weight,
            trend: getHealthTrend(score, prevScore),
            icon: factor.icon,
            weightedScore: Math.round(score * factor.weight)
        };
    });

    const overall = Math.round(factors.reduce((sum, f) => sum + f.score * f.weight, 0));

    return {
        overall,
        trend: getHealthTrend(overall, overall + randomInt(-8, 8, rng)),
        factors,
        overrideScore: null,
        overrideComment: '',
        overrideDate: null,
        overrideBy: null
    };
}

// ─── Health History Generator ────────────────────────────────────────────────

/**
 * Generate 12 months of health score history.
 * @param {string} accountId
 * @param {number} [months=12]
 * @returns {Array<Object>}
 */
export function generateHealthHistory(accountId, months = 12) {
    const rng = seededRandom('history-' + accountId);
    const history = [];
    let baseScore = randomInt(50, 90, rng);
    const now = new Date();

    for (let i = months - 1; i >= 0; i--) {
        const date = new Date(now);
        date.setMonth(date.getMonth() - i);
        const drift = randomInt(-8, 8, rng);
        baseScore = clamp(baseScore + drift, 20, 98);

        history.push({
            month: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`,
            monthLabel: MONTH_LABELS[date.getMonth()],
            score: baseScore,
            year: date.getFullYear()
        });
    }

    return history;
}

// ─── Subscription Generator ──────────────────────────────────────────────────

/**
 * Generate mock subscription records for an account.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateSubscriptions(accountId) {
    const rng = seededRandom('subs-' + accountId);
    const pcCount = randomInt(2, 5, rng);
    const cpqCount = randomInt(2, 4, rng);
    const subscriptions = [];
    const healthRatings = ['Green', 'Yellow', 'Red'];
    const cpqTypes = ['Renewable', 'One-time', 'Evergreen'];

    // Product Customer subscriptions
    for (let i = 0; i < pcCount; i++) {
        const product = pickRandom(PRODUCTS, rng);
        const status = pickRandom(SUBSCRIPTION_STATUSES, rng);
        const amount = randomInt(15000, 350000, rng);
        const startDate = addDays(new Date(), -randomInt(90, 730, rng));
        const endDate = addDays(startDate, randomInt(365, 1095));

        subscriptions.push({
            id: generateId('SUB', i + 1),
            subscriptionName: `${product.name} - ${product.category}`,
            productLine: product.name,
            status,
            csmHealthRating: pickRandom(healthRatings, rng),
            termEndDate: endDate.toISOString().split('T')[0],
            amount,
            startDate: startDate.toISOString().split('T')[0],
            source: 'Product Customer',
            subscriptionType: null
        });
    }

    // CPQ subscriptions
    for (let i = 0; i < cpqCount; i++) {
        const product = pickRandom(PRODUCTS, rng);
        const status = pickRandom(['Active', 'Expired', 'Pending', 'Terminated'], rng);
        const amount = randomInt(10000, 250000, rng);
        const startDate = addDays(new Date(), -randomInt(90, 730, rng));
        const endDate = addDays(startDate, randomInt(365, 1095));

        subscriptions.push({
            id: generateId('CPQ', i + 1),
            subscriptionName: `${product.name} License`,
            productLine: product.name,
            status,
            csmHealthRating: null,
            termEndDate: endDate.toISOString().split('T')[0],
            amount,
            startDate: startDate.toISOString().split('T')[0],
            source: 'CPQ',
            subscriptionType: pickRandom(cpqTypes, rng)
        });
    }

    return subscriptions;
}

// ─── Usage / Entitlement Generator ───────────────────────────────────────────

/**
 * Generate mock usage/entitlement records.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateEntitlements(accountId) {
    const rng = seededRandom('usage-' + accountId);
    const count = randomInt(3, 10, rng);
    const entitlements = [];

    for (let i = 0; i < count; i++) {
        const product = pickRandom(PRODUCTS, rng);
        const statuses = ['Active', 'Expired', 'Pending'];
        const startDate = addDays(new Date(), -randomInt(60, 365, rng));
        const endDate = addDays(startDate, randomInt(365, 730));

        entitlements.push({
            id: generateId('ENT', i + 1),
            product: product.name,
            entitlementStatus: pickRandom(statuses, rng),
            startDate: startDate.toISOString().split('T')[0],
            endDate: endDate.toISOString().split('T')[0],
            salePrice: randomInt(5000, 200000, rng),
            quantity: randomInt(1, 500, rng)
        });
    }

    return entitlements;
}

// ─── Feature Enablement Generator ────────────────────────────────────────────

/**
 * Generate feature enablement/whitespace data for an account.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateFeatureMap(accountId) {
    const rng = seededRandom('features-' + accountId);
    const productNames = pickRandomN(Object.keys(PRODUCT_FEATURES), randomInt(2, 4, rng), rng);

    return productNames.map(productName => {
        const features = PRODUCT_FEATURES[productName].map(featureName => {
            const entitled = rng() > 0.15;
            const enabled = entitled && rng() > 0.3;
            const adoption = enabled ? randomInt(10, 100, rng) : 0;

            return {
                name: featureName,
                entitled,
                enabled,
                adoption
            };
        });

        return {
            product: productName,
            features,
            totalEntitled: features.filter(f => f.entitled).length,
            totalEnabled: features.filter(f => f.enabled).length,
            whitespaceCount: features.filter(f => f.entitled && !f.enabled).length
        };
    });
}

// ─── Invoice Generator ───────────────────────────────────────────────────────

/**
 * Generate mock invoice records.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateInvoices(accountId) {
    const rng = seededRandom('invoices-' + accountId);
    const count = randomInt(5, 15, rng);
    const invoices = [];

    for (let i = 0; i < count; i++) {
        const status = pickRandom(INVOICE_STATUSES, rng);
        const amount = randomInt(5000, 200000, rng);
        const isPaid = status === 'Paid';
        const isOverdue = status === 'Overdue';
        const dueDate = addDays(new Date(), randomInt(-90, 90, rng));
        const daysPastDue = isOverdue ? randomInt(1, 120, rng) : 0;
        const outstanding = isPaid ? 0 : (status === 'Partially Paid' ? Math.round(amount * rng() * 0.5) : amount);

        invoices.push({
            id: generateId('INV', i + 1),
            invoiceNumber: `INV-${2026}-${String(randomInt(1000, 9999, rng))}`,
            status,
            amountInvoiced: amount,
            outstandingBalance: outstanding,
            dueDate: dueDate.toISOString().split('T')[0],
            daysPastDue,
            datePaid: isPaid ? addDays(dueDate, -randomInt(0, 15, rng)).toISOString().split('T')[0] : null
        });
    }

    return invoices;
}

// ─── Support Ticket Generator ────────────────────────────────────────────────

/**
 * Generate mock support tickets.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateTickets(accountId) {
    const rng = seededRandom('tickets-' + accountId);
    const count = randomInt(5, 20, rng);
    const tickets = [];
    const subjects = [
        'Login issues after SSO update', 'Data sync failure between systems',
        'Report generation taking too long', 'Feature request: bulk export',
        'Permission error accessing dashboard', 'Calendar integration not working',
        'Missing data in quarterly report', 'API rate limit exceeded',
        'Mobile app crashing on startup', 'Email notification delays',
        'Search functionality returning incorrect results', 'File upload size limit too restrictive',
        'Custom field not saving properly', 'Workflow automation stopped running',
        'User unable to reset password', 'Integration with Outlook failing',
        'Dashboard widgets not loading', 'Duplicate records appearing',
        'Audit log missing entries', 'Performance degradation during peak hours'
    ];

    for (let i = 0; i < count; i++) {
        const status = pickRandom(TICKET_STATUSES, rng);
        const createdDate = addDays(new Date(), -randomInt(1, 180, rng));
        const updatedDate = addDays(createdDate, randomInt(0, 30, rng));

        tickets.push({
            id: generateId('TKT', i + 1),
            ticketId: randomInt(10000, 99999, rng),
            subject: pickRandom(subjects, rng),
            status,
            priority: pickRandom(TICKET_PRIORITIES, rng),
            type: pickRandom(TICKET_TYPES, rng),
            createdDate: createdDate.toISOString(),
            updatedDate: updatedDate.toISOString(),
            resolutionDays: ['Solved', 'Closed'].includes(status) ? randomInt(1, 30, rng) : null,
            csat: ['Solved', 'Closed'].includes(status) ? randomInt(1, 5, rng) : null
        });
    }

    return tickets;
}

// ─── Timeline Generator ─────────────────────────────────────────────────────

/**
 * Generate activity timeline events.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateTimeline(accountId) {
    const rng = seededRandom('timeline-' + accountId);
    const count = randomInt(15, 40, rng);
    const events = [];
    const typeKeys = Object.keys(TIMELINE_TYPES);

    const meetingTitles = [
        'Quarterly Business Review', 'Product Roadmap Discussion', 'Onboarding Kickoff',
        'Executive Sponsor Check-in', 'Training Session: Advanced Features',
        'Release Review Session', 'Strategic Planning Meeting', 'Adoption Review',
        'Health Check Call', 'Expansion Discussion'
    ];

    const emailSubjects = [
        'Follow-up: Action Items from QBR', 'Re: License Renewal Discussion',
        'New Feature Announcement', 'Monthly Usage Report', 'Training Materials Shared',
        'Re: Support Escalation Update', 'Introduction: New Team Member',
        'Feedback Request: Recent Implementation'
    ];

    const noteContents = [
        'Client expressed interest in expanding DealCloud deployment to APAC offices.',
        'Key stakeholder change: New CIO starting next month. Need to schedule intro call.',
        'Usage has increased 15% month-over-month. Training program showing results.',
        'Client raised concerns about upcoming renewal pricing. Flagged for account team.',
        'Successful completion of Phase 2 implementation. Moving to Phase 3.',
        'NPS score improved from 6 to 8 after resolving integration issues.',
        'Client requested demo of new Walls features for compliance team.',
        'Budget approval confirmed for additional licenses in Q3.'
    ];

    const milestoneTitles = [
        'Go-Live: DealCloud', 'Contract Signed', 'First QBR Completed',
        'Training Complete: Phase 1', '100 Active Users Milestone',
        'Renewal Signed', 'Executive Sponsor Identified', 'Integration Complete'
    ];

    for (let i = 0; i < count; i++) {
        const type = pickRandom(typeKeys, rng);
        const daysAgo = randomInt(0, 365, rng);
        const date = addDays(new Date(), -daysAgo);
        const user = pickRandom(CSM_NAMES, rng);
        let title, description;

        switch (type) {
            case 'meeting':
                title = pickRandom(meetingTitles, rng);
                description = `Attendees: ${randomInt(2, 8, rng)} participants. Duration: ${randomInt(30, 90, rng)} minutes.`;
                break;
            case 'email':
                title = pickRandom(emailSubjects, rng);
                description = `Email sent to ${randomInt(1, 4, rng)} recipients.`;
                break;
            case 'note':
                title = 'Internal Note';
                description = pickRandom(noteContents, rng);
                break;
            case 'call':
                title = `Call with ${pickRandom(['CFO', 'CIO', 'COO', 'IT Director', 'Project Lead'], rng)}`;
                description = `Duration: ${randomInt(10, 45, rng)} minutes. ${pickRandom(['Productive call.', 'Follow-up needed.', 'No concerns raised.', 'Action items assigned.'], rng)}`;
                break;
            case 'milestone':
                title = pickRandom(milestoneTitles, rng);
                description = 'Milestone achieved.';
                break;
            case 'cta':
                title = `CTA: ${pickRandom(['At-Risk Intervention', 'Renewal Follow-up', 'Adoption Review', 'Onboarding Check-in'], rng)}`;
                description = `Status: ${pickRandom(['Completed', 'In Progress', 'Open'], rng)}`;
                break;
            case 'escalation':
                title = `Escalation: ${pickRandom(['Support ticket #' + randomInt(10000, 99999, rng), 'Billing dispute', 'Feature request priority', 'SLA concern'], rng)}`;
                description = `Escalated to ${pickRandom(['Engineering', 'Product', 'VP of CS', 'Account Executive'], rng)}.`;
                break;
            default:
                title = 'Activity';
                description = '';
        }

        events.push({
            id: generateId('TL', i + 1),
            type,
            title,
            description,
            date: date.toISOString(),
            user,
            icon: TIMELINE_TYPES[type].icon,
            color: TIMELINE_TYPES[type].color
        });
    }

    return events.sort((a, b) => new Date(b.date) - new Date(a.date));
}

// ─── CTA Generator ───────────────────────────────────────────────────────────

/**
 * Generate Calls-to-Action for an account.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateCtas(accountId) {
    const rng = seededRandom('ctas-' + accountId);
    const count = randomInt(2, 8, rng);
    const ctas = [];
    const typeKeys = Object.keys(CTA_TYPES);
    const priorityKeys = Object.keys(CTA_PRIORITIES);

    const ctaNames = {
        risk: ['At-Risk Intervention', 'Churn Prevention Outreach', 'Declining Usage Follow-up', 'Health Score Recovery Plan'],
        expansion: ['Upsell Opportunity: New Product', 'Cross-sell Discussion', 'License Expansion Review', 'New Department Onboarding'],
        renewal: ['Annual Renewal Preparation', 'Contract Negotiation', 'Renewal Risk Assessment', 'Multi-year Proposal'],
        lifecycle: ['Onboarding Follow-up', 'Training Completion Check', '90-Day Check-in', 'Annual Review Planning'],
        activity: ['QBR Scheduling', 'Executive Sponsor Meeting', 'Usage Report Review', 'Feedback Collection']
    };

    for (let i = 0; i < count; i++) {
        const type = pickRandom(typeKeys, rng);
        const priority = pickRandom(priorityKeys, rng);
        const status = pickRandom(['open', 'in_progress', 'open', 'in_progress', 'snoozed'], rng);
        const dueDate = addDays(new Date(), randomInt(-7, 30, rng));
        const taskCount = randomInt(3, 6, rng);
        const completedTasks = randomInt(0, taskCount, rng);
        const tasks = [];

        const taskTemplates = [
            'Schedule discovery call', 'Review usage dashboard', 'Send training resources',
            'Update success plan', 'Prepare QBR deck', 'Follow up on action items',
            'Escalate to product team', 'Send renewal proposal', 'Conduct health assessment',
            'Review support tickets', 'Document meeting notes', 'Create action plan'
        ];

        for (let t = 0; t < taskCount; t++) {
            const taskDueDate = addDays(dueDate, -randomInt(0, 14, rng));
            const taskCompleted = t < completedTasks;
            tasks.push({
                id: generateId('TSK', (i * 10) + t + 1),
                name: taskTemplates[(i * taskCount + t) % taskTemplates.length],
                completed: taskCompleted,
                dueDate: taskDueDate.toISOString().split('T')[0],
                priority: pickRandom(['high', 'medium', 'low'], rng),
                assignee: pickRandom(CSM_NAMES, rng),
                isOverdue: !taskCompleted && taskDueDate < new Date()
            });
        }

        const tagCount = randomInt(0, 3, rng);
        const tagValues = CTA_TAGS.map(t => t.value);
        const tags = pickRandomN(tagValues, tagCount, rng);

        ctas.push({
            id: generateId('CTA', i + 1),
            accountId,
            name: pickRandom(ctaNames[type], rng),
            type,
            typeLabel: CTA_TYPES[type].label,
            typeColor: CTA_TYPES[type].color,
            typeIcon: CTA_TYPES[type].icon,
            priority,
            priorityLabel: CTA_PRIORITIES[priority].label,
            priorityColor: CTA_PRIORITIES[priority].color,
            status,
            dueDate: dueDate.toISOString().split('T')[0],
            assignee: pickRandom(CSM_NAMES, rng),
            tasks,
            completedTasks,
            totalTasks: taskCount,
            progress: Math.round((completedTasks / taskCount) * 100),
            playbookId: generateId('PB', i + 1),
            tags
        });
    }

    return ctas.sort((a, b) => {
        const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
        return priorityOrder[a.priority] - priorityOrder[b.priority];
    });
}

// ─── Playbook Generator ─────────────────────────────────────────────────────

/**
 * Generate playbook steps for a CTA.
 * @param {string} ctaType - risk | expansion | renewal | lifecycle | activity
 * @returns {Object}
 */
export function generatePlaybook(ctaType) {
    const playbooks = {
        risk: {
            id: 'PB-RISK',
            name: 'At-Risk Intervention Playbook',
            description: 'Structured approach to address declining health for at-risk accounts.',
            steps: [
                { order: 1, name: 'Review Health Factors', description: 'Analyze each health score component to identify root causes of decline.', completed: false },
                { order: 2, name: 'Internal Alignment', description: 'Meet with account team (AE, SE, Support) to align on risk assessment and strategy.', completed: false },
                { order: 3, name: 'Customer Outreach', description: 'Schedule a call with the primary stakeholder to discuss their experience and concerns.', completed: false },
                { order: 4, name: 'Create Recovery Plan', description: 'Document an action plan with specific milestones and owners. Share with customer.', completed: false },
                { order: 5, name: 'Execute & Monitor', description: 'Execute recovery actions and monitor health score weekly for 30 days.', completed: false },
                { order: 6, name: 'Follow-up Assessment', description: 'Reassess health factors after 30 days. Close CTA if health has improved.', completed: false }
            ]
        },
        expansion: {
            id: 'PB-EXPAND',
            name: 'Expansion Opportunity Playbook',
            description: 'Guide for identifying and closing expansion opportunities.',
            steps: [
                { order: 1, name: 'Whitespace Analysis', description: 'Review feature enablement and product adoption to identify expansion opportunities.', completed: false },
                { order: 2, name: 'Build Business Case', description: 'Prepare ROI analysis and value proposition for the expansion.', completed: false },
                { order: 3, name: 'Stakeholder Alignment', description: 'Present opportunity to customer champion and gain internal buy-in.', completed: false },
                { order: 4, name: 'Involve Sales', description: 'Brief AE on opportunity. Coordinate joint call with customer.', completed: false },
                { order: 5, name: 'Proposal & Close', description: 'Support AE in delivering proposal. Track through sales cycle.', completed: false }
            ]
        },
        renewal: {
            id: 'PB-RENEW',
            name: 'Renewal Management Playbook',
            description: 'End-to-end renewal process from 120 days out.',
            steps: [
                { order: 1, name: 'Health Assessment (120 days)', description: 'Review account health, usage trends, and support history.', completed: false },
                { order: 2, name: 'Value Review (90 days)', description: 'Prepare value delivered report. Schedule review with customer.', completed: false },
                { order: 3, name: 'Renewal Kickoff (60 days)', description: 'Brief AE on account status. Initiate renewal process.', completed: false },
                { order: 4, name: 'Negotiation Support (30 days)', description: 'Support AE with any customer concerns or requests.', completed: false },
                { order: 5, name: 'Close & Handoff', description: 'Confirm renewal execution. Update success plan for next term.', completed: false }
            ]
        },
        lifecycle: {
            id: 'PB-LIFE',
            name: 'Lifecycle Milestone Playbook',
            description: 'Standard process for lifecycle stage transitions.',
            steps: [
                { order: 1, name: 'Assess Current State', description: 'Review where the customer is in their journey and any blockers.', completed: false },
                { order: 2, name: 'Set Expectations', description: 'Communicate next milestones and success criteria to customer.', completed: false },
                { order: 3, name: 'Execute Activities', description: 'Complete all required activities for this lifecycle stage.', completed: false },
                { order: 4, name: 'Verify & Transition', description: 'Confirm milestone completion and transition to next stage.', completed: false }
            ]
        },
        activity: {
            id: 'PB-ACT',
            name: 'Activity Checklist',
            description: 'Standard checklist for recurring customer activities.',
            steps: [
                { order: 1, name: 'Preparation', description: 'Gather relevant data, reports, and talking points.', completed: false },
                { order: 2, name: 'Execution', description: 'Conduct the activity with the customer.', completed: false },
                { order: 3, name: 'Documentation', description: 'Log activity in timeline with notes and action items.', completed: false },
                { order: 4, name: 'Follow-up', description: 'Send summary and action items to attendees.', completed: false }
            ]
        }
    };

    return playbooks[ctaType] || playbooks.activity;
}

// ─── Success Plan Generator ──────────────────────────────────────────────────

/**
 * Generate a success plan with objectives and milestones.
 * @param {string} accountId
 * @returns {Object}
 */
export function generateSuccessPlan(accountId) {
    const rng = seededRandom('successplan-' + accountId);

    const objectives = [
        {
            id: generateId('OBJ', 1),
            name: 'Increase product adoption to 80%',
            target: 80,
            current: randomInt(40, 85, rng),
            unit: '%',
            status: 'in_progress',
            dueDate: addDays(new Date(), randomInt(30, 180, rng)).toISOString().split('T')[0],
            milestones: [
                { name: 'Complete admin training', completed: rng() > 0.3, date: addDays(new Date(), -randomInt(10, 60, rng)).toISOString().split('T')[0] },
                { name: 'Launch pilot group (25 users)', completed: rng() > 0.4, date: addDays(new Date(), -randomInt(0, 30, rng)).toISOString().split('T')[0] },
                { name: 'Full rollout to all users', completed: rng() > 0.7, date: addDays(new Date(), randomInt(10, 60, rng)).toISOString().split('T')[0] },
                { name: 'Achieve 80% adoption target', completed: false, date: addDays(new Date(), randomInt(60, 120, rng)).toISOString().split('T')[0] }
            ]
        },
        {
            id: generateId('OBJ', 2),
            name: 'Reduce support ticket volume by 30%',
            target: 30,
            current: randomInt(5, 35, rng),
            unit: '%',
            status: randomInt(0, 10, rng) > 5 ? 'in_progress' : 'on_track',
            dueDate: addDays(new Date(), randomInt(60, 240, rng)).toISOString().split('T')[0],
            milestones: [
                { name: 'Identify top ticket categories', completed: true, date: addDays(new Date(), -randomInt(30, 90, rng)).toISOString().split('T')[0] },
                { name: 'Deploy self-service documentation', completed: rng() > 0.4, date: addDays(new Date(), -randomInt(0, 30, rng)).toISOString().split('T')[0] },
                { name: 'Train power users as tier-1 support', completed: rng() > 0.6, date: addDays(new Date(), randomInt(10, 60, rng)).toISOString().split('T')[0] }
            ]
        },
        {
            id: generateId('OBJ', 3),
            name: 'Achieve NPS score of 8+',
            target: 8,
            current: randomInt(5, 9, rng),
            unit: 'score',
            status: 'in_progress',
            dueDate: addDays(new Date(), randomInt(90, 365, rng)).toISOString().split('T')[0],
            milestones: [
                { name: 'Baseline NPS survey', completed: true, date: addDays(new Date(), -randomInt(60, 120, rng)).toISOString().split('T')[0] },
                { name: 'Address top detractor themes', completed: rng() > 0.5, date: addDays(new Date(), -randomInt(0, 45, rng)).toISOString().split('T')[0] },
                { name: 'Follow-up NPS survey', completed: false, date: addDays(new Date(), randomInt(30, 90, rng)).toISOString().split('T')[0] }
            ]
        }
    ];

    return {
        id: generateId('SP', 1),
        name: 'FY2026 Success Plan',
        status: 'active',
        objectives,
        totalObjectives: objectives.length,
        onTrack: objectives.filter(o => o.current >= o.target * 0.7).length,
        atRisk: objectives.filter(o => o.current < o.target * 0.5).length
    };
}

// ─── Benchmark Generator ─────────────────────────────────────────────────────

/**
 * Generate benchmark comparison data for an account.
 * @param {string} accountId
 * @returns {Array<Object>}
 */
export function generateBenchmarks(accountId) {
    const rng = seededRandom('bench-' + accountId);
    const health = generateHealthScore(accountId);

    const metrics = [
        { metric: 'Health Score', clientValue: health.overall },
        { metric: 'Product Adoption', clientValue: health.factors.find(f => f.key === 'productAdoption')?.score || 70 },
        { metric: 'Support Health', clientValue: health.factors.find(f => f.key === 'supportHealth')?.score || 70 },
        { metric: 'NPS', clientValue: randomInt(4, 10, rng) },
        { metric: 'Engagement', clientValue: health.factors.find(f => f.key === 'engagement')?.score || 70 }
    ];

    return metrics.map(m => ({
        ...m,
        segmentAvg: clamp(m.clientValue + randomInt(-15, 10, rng), 20, 95),
        segmentMedian: clamp(m.clientValue + randomInt(-10, 8, rng), 25, 92),
        topQuartile: clamp(m.clientValue + randomInt(5, 20, rng), 60, 98),
        segment: 'Enterprise Legal'
    }));
}

// NOTE: generateTasks() removed — tasks are now children of CTAs (generated within generateCtas).

// ═══════════════════════════════════════════════════════════════════════════════
// SPEC-ALIGNED GENERATORS (Here.docx)
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Subscriptions V2 (spec-aligned with pricebook, SKUs, seats) ────────────

/**
 * Generate spec-aligned subscription records with pricebook data.
 * @param {string} customerId
 * @returns {Array<Object>}
 */
export function generateSubscriptionsV2(customerId) {
    const rng = seededRandom('subsv2-' + customerId);
    const count = randomInt(3, 6, rng);
    const subscriptions = [];
    const tiers = Object.keys(TIER_MULTIPLIERS);
    const used = new Set();

    for (let i = 0; i < count; i++) {
        let product;
        do {
            product = pickRandom(PRICEBOOK, rng);
        } while (used.has(product.sku) && used.size < PRICEBOOK.length);
        used.add(product.sku);

        const tier = pickRandom(tiers, rng);
        const status = pickRandom(['Active', 'Active', 'Active', 'Expired', 'Pending'], rng);
        const seats = randomInt(50, 450, rng);
        const multiplier = TIER_MULTIPLIERS[tier];
        const contractValue = Math.round(product.baseValue * multiplier);
        const startDate = addDays(new Date(), -randomInt(90, 730, rng));
        const endDate = addDays(startDate, randomInt(365, 1095));

        subscriptions.push({
            id: `SUB-${customerId}-${i}`,
            customerId,
            sku: product.sku,
            product: product.product,
            category: product.category,
            status,
            startDate: startDate.toISOString().split('T')[0],
            endDate: endDate.toISOString().split('T')[0],
            seats,
            contractValue,
            tier
        });
    }

    return subscriptions;
}

// ─── Support Tickets V2 (spec-aligned with ZD numbers, assignees) ───────────

/**
 * Generate spec-aligned support tickets.
 * @param {string} customerId
 * @returns {Array<Object>}
 */
export function generateTicketsV2(customerId) {
    const rng = seededRandom('tktv2-' + customerId);
    const count = randomInt(8, 20, rng);
    const tickets = [];
    const statuses = ['Open', 'Pending', 'Solved', 'Closed'];
    const priorities = ['Critical', 'High', 'Medium', 'Low'];

    for (let i = 0; i < count; i++) {
        const status = pickRandom(statuses, rng);
        const createdAt = addDays(new Date(), -randomInt(1, 180, rng));
        const updatedAt = addDays(createdAt, randomInt(0, 30, rng));
        const resolved = ['Solved', 'Closed'].includes(status);

        tickets.push({
            id: `TKT-${customerId}-${i}`,
            ticketNumber: `ZD-${randomInt(10000, 99999, rng)}`,
            customerId,
            subject: pickRandom(TICKET_SUBJECTS, rng),
            priority: pickRandom(priorities, rng),
            status,
            assignee: pickRandom(SUPPORT_ASSIGNEES, rng),
            createdAt: createdAt.toISOString(),
            updatedAt: updatedAt.toISOString(),
            resolvedAt: resolved ? addDays(createdAt, randomInt(1, 14, rng)).toISOString() : null
        });
    }

    return tickets.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
}

// ─── Invoices V2 (spec-aligned with NS numbers, payment data) ──────────────

/**
 * Generate spec-aligned invoice records.
 * @param {string} customerId
 * @returns {Array<Object>}
 */
export function generateInvoicesV2(customerId) {
    const rng = seededRandom('invv2-' + customerId);
    const count = randomInt(6, 14, rng);
    const invoices = [];
    const statuses = ['Paid', 'Paid', 'Paid', 'Overdue', 'Pending', 'Partial'];

    for (let i = 0; i < count; i++) {
        const status = pickRandom(statuses, rng);
        const amount = randomInt(15000, 95000, rng);
        const date = addDays(new Date(), -randomInt(10, 365, rng));
        const dueDate = addDays(date, 30);
        let paidAmount = 0;
        let paymentDate = null;

        if (status === 'Paid') {
            paidAmount = amount;
            paymentDate = addDays(dueDate, -randomInt(0, 10, rng)).toISOString().split('T')[0];
        } else if (status === 'Partial') {
            paidAmount = Math.round(amount * 0.6);
            paymentDate = addDays(dueDate, randomInt(1, 15, rng)).toISOString().split('T')[0];
        }

        invoices.push({
            id: `INV-${customerId}-${i}`,
            invoiceNumber: `NS-${2024}${randomInt(100, 999, rng)}`,
            customerId,
            date: date.toISOString().split('T')[0],
            dueDate: dueDate.toISOString().split('T')[0],
            amount,
            status,
            paidAmount,
            paymentDate
        });
    }

    return invoices.sort((a, b) => new Date(b.date) - new Date(a.date));
}

// ─── Usage Data Generator (op4i 3-level hierarchy) ──────────────────────────

/**
 * Generate account usage data with 3-level hierarchy matching op4i schema:
 *   Level 1: Account Usage Stat  — account-level aggregates
 *   Level 2: Client Site Usage Stat — per-site breakdown (linked to Account)
 *   Level 3: User Usage Stat — per-user detail (linked to Account + SiteURL)
 */
export function generateAccountUsage(customerId) {
    const rng = seededRandom('usagev2-' + customerId);
    const siteCount = randomInt(2, 5, rng);
    if (siteCount === 0) return _emptyAccountUsage(customerId);

    const clientSites = [];
    let totalLicensed = 0;
    let totalEnabled = 0;
    let totalCapacity = 0;
    let totalActiveCapacity = 0;
    let totalActiveLoginsReportNotifications = 0;
    const channelTotals = {};
    LOGIN_CHANNELS.forEach(ch => { channelTotals[ch] = { distinct: 0, total: 0 }; });
    const personaTotals = {};
    PERSONAS.forEach(p => { personaTotals[p.key] = { adopted: 0, total: 0 }; });

    const SITE_DOMAINS = ['dc1.intapp.com', 'dc2.intapp.com', 'cloud.intapp.com', 'app.intapp.com', 'portal.intapp.com'];

    for (let s = 0; s < siteCount; s++) {
        const siteRng = seededRandom(`site-${customerId}-${s}`);
        const siteUrl = SITE_DOMAINS[s % SITE_DOMAINS.length];
        const userCount = randomInt(12, 30, siteRng);
        const siteLicensed = randomInt(userCount, Math.round(userCount * 1.3), siteRng);
        const users = [];

        for (let u = 0; u < userCount; u++) {
            const uRng = seededRandom(`user-${customerId}-${s}-${u}`);
            const firstName = pickRandom(['James', 'Emma', 'Oliver', 'Sophia', 'Liam', 'Ava', 'Noah', 'Isabella', 'William', 'Mia', 'Ethan', 'Charlotte', 'Mason', 'Amelia', 'Lucas'], uRng);
            const lastName = pickRandom(['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Martinez', 'Anderson', 'Taylor', 'Thomas', 'Moore', 'Jackson', 'White'], uRng);
            const name = `${firstName} ${lastName}`;
            const email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}@firm.com`;
            const activeLogins = uRng() > 0.15 ? 'Yes' : 'No';
            const isActive = activeLogins === 'Yes';
            const hasActivity = isActive && uRng() > 0.2;
            const activeLoginsActivity = hasActivity ? 'Yes' : 'No';

            const portalLogins = isActive ? randomInt(0, 40, uRng) : 0;
            const excelLogins = isActive ? randomInt(0, 25, uRng) : 0;
            const wordLogins = isActive ? randomInt(0, 15, uRng) : 0;
            const outlookLogins = isActive ? randomInt(0, 20, uRng) : 0;
            const mobileLogins = isActive ? randomInt(0, 12, uRng) : 0;
            const notificationsL4W = randomInt(0, 50, uRng);
            const reportsL4W = randomInt(0, 10, uRng);

            // 15 persona booleans (Adopted = "Yes" / "No" text per op4i schema)
            const personaAdopted = {};
            PERSONAS.forEach(p => {
                personaAdopted[p.key] = uRng() > 0.45 ? 'Yes' : 'No';
            });

            users.push({
                userId: `USR-${customerId}-${s}-${u}`,
                name,
                email,
                siteUrl,
                clientId: `CL-${randomInt(1000, 9999, uRng)}`,
                activeLogins,
                activeLoginsActivity,
                portalLoginsL4W: portalLogins,
                excelLoginsL4W: excelLogins,
                wordLoginsL4W: wordLogins,
                outlookLoginsL4W: outlookLogins,
                mobileLoginsL4W: mobileLogins,
                notificationsL4W,
                reportsL4W,
                entriesAdded: hasActivity ? randomInt(0, 200, uRng) : 0,
                entriesDeleted: hasActivity ? randomInt(0, 20, uRng) : 0,
                entriesModified: hasActivity ? randomInt(0, 150, uRng) : 0,
                lastLoginAnyType: isActive ? addDays(new Date(), -randomInt(0, 28, uRng)).toISOString().split('T')[0] : null,
                lastLoginMobile: mobileLogins > 0 ? addDays(new Date(), -randomInt(0, 28, uRng)).toISOString().split('T')[0] : null,
                lastLoginPortal: portalLogins > 0 ? addDays(new Date(), -randomInt(0, 28, uRng)).toISOString().split('T')[0] : null,
                isBillable: uRng() > 0.1 ? 'Yes' : 'No',
                isEnabledBillable: isActive ? 'Yes' : 'No',
                personaAdopted,
                userGroups: pickRandom(USER_GROUPS, uRng),
                snapshotDate: new Date().toISOString().split('T')[0]
            });
        }

        const siteEnabled = users.filter(u => u.activeLogins === 'Yes').length;
        const siteActive = users.filter(u => u.activeLoginsActivity === 'Yes').length;
        const siteActiveLoginsRptNot = users.filter(u =>
            u.activeLogins === 'Yes' || u.reportsL4W > 0 || u.notificationsL4W > 0
        ).length;
        const siteLoginPct = userCount > 0 ? Math.round((siteEnabled / userCount) * 100) : 0;
        const siteActivityPct = userCount > 0 ? Math.round((siteActive / userCount) * 100) : 0;
        const siteLicenseCapacity = siteLicensed > 0 ? Math.round((siteEnabled / siteLicensed) * 100) : 0;
        const siteActiveLicenseCapacity = siteLicensed > 0 ? Math.round((siteActive / siteLicensed) * 100) : 0;

        // Channel aggregation for site
        const siteChannels = {};
        LOGIN_CHANNELS.forEach(ch => {
            const key = ch.toLowerCase() + 'LoginsL4W';
            const altKey = ch.toLowerCase() + 'L4W';
            let distinct = 0;
            let total = 0;
            users.forEach(u => {
                const val = u[key] || u[altKey] || 0;
                if (val > 0) distinct++;
                total += val;
            });
            siteChannels[ch] = { distinct, total };
            channelTotals[ch].distinct += distinct;
            channelTotals[ch].total += total;
        });

        // Persona adoption % for site
        const sitePersonaAdoption = [];
        PERSONAS.forEach(p => {
            const adoptedCount = users.filter(u => u.personaAdopted[p.key] === 'Yes').length;
            const pct = userCount > 0 ? Math.round((adoptedCount / userCount) * 100) : 0;
            sitePersonaAdoption.push({ persona: p.label, key: p.key, adopted: adoptedCount, total: userCount, pct });
            personaTotals[p.key].adopted += adoptedCount;
            personaTotals[p.key].total += userCount;
        });

        // Site configuration flags (op4i Client Site fields)
        const isDealCloud = siteRng() > 0.4 ? 'Yes' : 'No';
        const config = {
            isDealCloud,
            isOnePlace: isDealCloud === 'Yes' ? (siteRng() > 0.6 ? 'Yes' : 'No') : 'No',
            isSandbox: siteRng() > 0.85 ? 'Yes' : 'No',
            isDemo: siteRng() > 0.9 ? 'Yes' : 'No',
            twoFactorAuthentication: siteRng() > 0.3 ? 'Yes' : 'No',
            sessionTimeout: pickRandom([15, 30, 60, 120], siteRng),
            identityProviderName: siteRng() > 0.4 ? pickRandom(['Okta', 'Azure AD', 'OneLogin', 'Ping Identity'], siteRng) : '',
            serverSideSyncEnabled: siteRng() > 0.5 ? 'Yes' : 'No',
            apiAccess: siteRng() > 0.3 ? 'Yes' : 'No',
            dataProviderAccess: siteRng() > 0.5 ? 'Yes' : 'No',
            dataProviderType: pickRandom(['S&P', 'PitchBook', 'Dun & Bradstreet', ''], siteRng),
            dispatchEnabled: siteRng() > 0.4 ? 'Yes' : 'No',
            gemstoneEnabled: siteRng() > 0.3 ? 'Yes' : 'No',
            googleMapsEnabled: siteRng() > 0.5 ? 'Yes' : 'No',
            allowRelationshipIntelligence: siteRng() > 0.4 ? 'Yes' : 'No',
            usingMailchimp: siteRng() > 0.8 ? 'Yes' : 'No'
        };

        // Platform metrics (op4i Total* fields)
        const platformMetrics = {
            totalEntries: randomInt(500, 50000, siteRng),
            totalFields: randomInt(20, 200, siteRng),
            totalLists: randomInt(5, 50, siteRng),
            totalReports: randomInt(10, 100, siteRng),
            totalViews: randomInt(10, 80, siteRng),
            totalDashboards: randomInt(2, 20, siteRng),
            totalWorkflows: randomInt(3, 30, siteRng),
            totalAutomation: randomInt(1, 15, siteRng),
            totalRecurringTasks: randomInt(0, 10, siteRng),
            draftAutomation: randomInt(0, 5, siteRng),
            liveAutomation: randomInt(1, 10, siteRng),
            instantCriteria: randomInt(0, 20, siteRng),
            recurringCriteria: randomInt(0, 10, siteRng),
            auditFileSize: randomInt(100, 5000, siteRng)
        };

        clientSites.push({
            id: `SITE-${customerId}-${s}`,
            siteUrl,
            licensed: siteLicensed,
            enabled: siteEnabled,
            active: siteActive,
            totalUsers: userCount,
            loginPct: siteLoginPct,
            activityPct: siteActivityPct,
            licenseCapacity: siteLicenseCapacity,
            activeLicenseCapacity: siteActiveLicenseCapacity,
            noOfActiveLoginsL4W: siteEnabled,
            noOfActiveLoginsReportNotificationsL4W: siteActiveLoginsRptNot,
            users,
            channels: siteChannels,
            personaAdoption: sitePersonaAdoption,
            config,
            platformMetrics,
            isLatestDate: 'Yes',
            snapshotDate: new Date().toISOString().split('T')[0]
        });

        totalLicensed += siteLicensed;
        totalEnabled += siteEnabled;
        totalCapacity += userCount;
        totalActiveCapacity += siteActive;
        totalActiveLoginsReportNotifications += siteActiveLoginsRptNot;
    }

    // Account-level aggregation
    const loginPct = totalCapacity > 0 ? Math.round((totalEnabled / totalCapacity) * 100) : 0;
    const activityPct = totalCapacity > 0 ? Math.round((totalActiveCapacity / totalCapacity) * 100) : 0;
    const licenseCapacity = totalLicensed > 0 ? Math.round((totalEnabled / totalLicensed) * 100) : 0;
    const activeLicenseCapacity = totalLicensed > 0 ? Math.round((totalActiveCapacity / totalLicensed) * 100) : 0;

    const loginsByChannel = LOGIN_CHANNELS.map(ch => ({
        channel: ch,
        distinct: channelTotals[ch].distinct,
        total: channelTotals[ch].total
    }));

    const personaAdoption = PERSONAS.map(p => ({
        persona: p.label,
        key: p.key,
        adopted: personaTotals[p.key].adopted,
        total: personaTotals[p.key].total,
        pct: personaTotals[p.key].total > 0 ? Math.round((personaTotals[p.key].adopted / personaTotals[p.key].total) * 100) : 0
    }));

    // Rating score
    const licenseUtil = totalLicensed > 0 ? Math.min(100, Math.round((totalEnabled / totalLicensed) * 100)) : 0;
    const overUsagePenalty = totalLicensed > 0 && totalCapacity > totalLicensed ?
        Math.max(0, 100 - Math.round(((totalCapacity - totalLicensed) / totalLicensed) * 100)) : 100;
    const personaCount = personaAdoption.length;
    const personaBreadth = personaCount > 0 ?
        Math.round((personaAdoption.filter(p => p.pct >= 30).length / personaCount) * 100) : 0;

    const ratingScore = Math.round(
        licenseUtil * USAGE_RATING_WEIGHTS.licenseUtil +
        overUsagePenalty * USAGE_RATING_WEIGHTS.overUsagePenalty +
        loginPct * USAGE_RATING_WEIGHTS.loginPct +
        activityPct * USAGE_RATING_WEIGHTS.activityPct +
        personaBreadth * USAGE_RATING_WEIGHTS.personaBreadth
    );

    const ratingTier = USAGE_RATING_TIERS.find(t => ratingScore >= t.min) || USAGE_RATING_TIERS[USAGE_RATING_TIERS.length - 1];

    return {
        customerId,
        licensed: totalLicensed,
        enabled: totalEnabled,
        capacity: totalCapacity,
        activeCapacity: totalActiveCapacity,
        licenseCapacity,
        activeLicenseCapacity,
        loginPct,
        activityPct,
        noOfActiveLoginsL4W: totalEnabled,
        noOfActiveLoginsReportNotificationsL4W: totalActiveLoginsReportNotifications,
        loginsByChannel,
        personaAdoption,
        usageRating: { score: ratingScore, tier: ratingTier.tier, color: ratingTier.color },
        ratingFactors: {
            licenseUtil: { value: licenseUtil, weight: USAGE_RATING_WEIGHTS.licenseUtil, label: 'License Utilization' },
            overUsagePenalty: { value: overUsagePenalty, weight: USAGE_RATING_WEIGHTS.overUsagePenalty, label: 'Over-Usage Penalty' },
            loginPct: { value: loginPct, weight: USAGE_RATING_WEIGHTS.loginPct, label: 'Login Adoption' },
            activityPct: { value: activityPct, weight: USAGE_RATING_WEIGHTS.activityPct, label: 'Activity Rate' },
            personaBreadth: { value: personaBreadth, weight: USAGE_RATING_WEIGHTS.personaBreadth, label: 'Persona Breadth' }
        },
        clientSites,
        snapshotDate: new Date().toISOString().split('T')[0],
        isLatestDate: 'Yes'
    };
}

function _emptyAccountUsage(customerId) {
    return {
        customerId,
        licensed: 0, enabled: 0, capacity: 0, activeCapacity: 0,
        licenseCapacity: 0, activeLicenseCapacity: 0,
        loginPct: 0, activityPct: 0,
        noOfActiveLoginsL4W: 0, noOfActiveLoginsReportNotificationsL4W: 0,
        loginsByChannel: LOGIN_CHANNELS.map(ch => ({ channel: ch, distinct: 0, total: 0 })),
        personaAdoption: [],
        usageRating: { score: 0, tier: 'At Risk', color: '#ef4444' },
        ratingFactors: {},
        clientSites: []
    };
}

// ─── Alert Generator ─────────────────────────────────────────────────────────

/**
 * Generate alerts/notifications for the portfolio.
 * @param {Array<Object>} portfolio - Array of account objects
 * @returns {Array<Object>}
 */
export function generateAlerts(portfolio) {
    const rng = seededRandom('alerts-global');
    const alerts = [];
    const alertTypeKeys = Object.keys(ALERT_TYPES);

    portfolio.forEach(account => {
        if (account.healthScore < 60) {
            alerts.push({
                id: generateId('ALT', alerts.length + 1),
                type: 'risk',
                ...ALERT_TYPES.risk,
                title: `Churn risk: ${account.name}`,
                description: `Health score dropped to ${account.healthScore}. Immediate attention required.`,
                timestamp: addDays(new Date(), -randomInt(0, 3, rng)).toISOString(),
                accountId: account.id,
                accountName: account.name,
                dismissed: false
            });
        }

        if (account.healthTrend === 'down') {
            alerts.push({
                id: generateId('ALT', alerts.length + 1),
                type: 'health_change',
                ...ALERT_TYPES.health_change,
                title: `Health declining: ${account.name}`,
                description: `Health score decreased from ${account.previousHealthScore} to ${account.healthScore}.`,
                timestamp: addDays(new Date(), -randomInt(0, 5, rng)).toISOString(),
                accountId: account.id,
                accountName: account.name,
                dismissed: false
            });
        }

        const daysToRenewal = Math.floor((new Date(account.renewalDate) - new Date()) / (1000 * 60 * 60 * 24));
        if (daysToRenewal <= 90 && daysToRenewal > 0) {
            alerts.push({
                id: generateId('ALT', alerts.length + 1),
                type: 'renewal',
                ...ALERT_TYPES.renewal,
                title: `Renewal in ${daysToRenewal} days: ${account.name}`,
                description: `Annual renewal approaching. ARR: $${(account.arr / 1000).toFixed(0)}K.`,
                timestamp: addDays(new Date(), -randomInt(0, 7, rng)).toISOString(),
                accountId: account.id,
                accountName: account.name,
                dismissed: false
            });
        }

        if (account.daysSinceContact > 30) {
            alerts.push({
                id: generateId('ALT', alerts.length + 1),
                type: 'usage_decline',
                ...ALERT_TYPES.usage_decline,
                title: `No contact in ${account.daysSinceContact} days: ${account.name}`,
                description: `Last engagement was ${account.daysSinceContact} days ago. Consider reaching out.`,
                timestamp: addDays(new Date(), -randomInt(0, 3, rng)).toISOString(),
                accountId: account.id,
                accountName: account.name,
                dismissed: false
            });
        }
    });

    // Add a few task_due alerts
    for (let i = 0; i < Math.min(3, portfolio.length); i++) {
        const acc = portfolio[i];
        alerts.push({
            id: generateId('ALT', alerts.length + 1),
            type: 'task_due',
            ...ALERT_TYPES.task_due,
            title: `Task overdue: ${pickRandom(['QBR prep', 'Usage review', 'Follow-up call'], rng)}`,
            description: `Task for ${acc.name} is past due.`,
            timestamp: addDays(new Date(), -randomInt(0, 2, rng)).toISOString(),
            accountId: acc.id,
            accountName: acc.name,
            dismissed: false
        });
    }

    return alerts.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
}

// ─── Private Helpers ─────────────────────────────────────────────────────────

function _generateRawScore(rng) {
    // Weighted toward 50-90 range for realistic distribution
    const base = rng();
    if (base < 0.05) return randomInt(15, 35, rng);   // 5% critical
    if (base < 0.15) return randomInt(35, 55, rng);    // 10% poor
    if (base < 0.35) return randomInt(55, 72, rng);    // 20% fair
    return randomInt(72, 96, rng);                      // 65% good
}

function _arrForSegment(segment, rng) {
    switch (segment) {
        case 'Enterprise': return randomInt(250000, 2000000, rng);
        case 'Mid-Market': return randomInt(75000, 400000, rng);
        case 'SMB': return randomInt(15000, 100000, rng);
        default: return randomInt(50000, 500000, rng);
    }
}