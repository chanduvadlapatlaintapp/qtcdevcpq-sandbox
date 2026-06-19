/**
 * @description About page for Customer 360 CS Platform Lite. Displays a comprehensive
 *              inventory of all components, architecture overview, Gainsight requirements
 *              coverage, and project statistics. Serves as in-app documentation.
 * @author  Yousef A
 * @date    2026-03-06
 * @jira    BIZ-80363
 */
import { LightningElement } from 'lwc';

export default class Customer360About extends LightningElement {

    /**********************************************************************************************
     *
     * Component Inventory Data
     *
     ***********************************************************************************************/

    /** Service modules — JS-only, no UI */
    get serviceModules() {
        return [
            { name: 'customer360Constants', purpose: 'Color palettes, product catalog, firm names, status enums, health thresholds' },
            { name: 'customer360Utils', purpose: 'Formatters (currency, date, %), sorting, CSV export, seeded random, health color helpers' },
            { name: 'customer360MockData', purpose: 'All generate*() factory functions \u2014 produces deterministic mock data seeded from account IDs' }
        ];
    }

    /** Reusable atom components */
    get atomComponents() {
        return [
            { name: 'customer360KpiCard', purpose: 'Metric card with label, value, trend arrow, and sparkline' },
            { name: 'customer360HealthRing', purpose: 'SVG circular health score indicator (color-coded green/yellow/red)' },
            { name: 'customer360Badge', purpose: 'Colored status badge (health, risk level, segment, CTA priority)' },
            { name: 'customer360EmptyState', purpose: 'Placeholder for tabs with no data (icon + message)' },
            { name: 'customer360ChartBar', purpose: 'SVG horizontal/vertical bar chart (used for health distribution)' },
            { name: 'customer360ChartDonut', purpose: 'SVG donut/pie chart (used for health segment breakdown)' },
            { name: 'customer360About', purpose: 'This page \u2014 in-app documentation and component inventory' }
        ];
    }

    /** Dashboard components */
    get dashboardComponents() {
        return [
            { name: 'customer360Header', purpose: 'Dark header bar \u2014 CSM name/role, notification bell, info button, logo' },
            { name: 'customer360Dashboard', purpose: 'Main dashboard layout \u2014 6 KPI cards + portfolio list + alerts panel + health charts' },
            { name: 'customer360PortfolioList', purpose: 'Filterable/sortable account list with health rings, segment badges, ARR, renewal dates' },
            { name: 'customer360AlertsPanel', purpose: 'Risk alerts panel \u2014 churn risk, usage decline, health score changes' }
        ];
    }

    /** Customer detail components */
    get detailComponents() {
        return [
            { name: 'customer360Banner', tab: 'Header', purpose: 'Account banner \u2014 name, health ring, stat pills (ARR, segment, CSM, renewal), quick action buttons' },
            { name: 'customer360DetailTabs', tab: 'Navigation', purpose: 'Custom 9-tab navigation bar with active state styling' },
            { name: 'customer360Overview', tab: 'Overview', purpose: 'Summary tab \u2014 KPI cards + recent timeline entries + CTA summary + key stats' },
            { name: 'customer360Scorecard', tab: 'Health', purpose: 'Health factor breakdown \u2014 table of weighted factors (usage, support, engagement, financial)' },
            { name: 'customer360HealthTrend', tab: 'Health', purpose: 'SVG line chart showing 12-month health score history' },
            { name: 'customer360HealthOverride', tab: 'Health', purpose: 'Manual health score override form with reason and history log' },
            { name: 'customer360Benchmark', tab: 'Health', purpose: 'Peer comparison \u2014 horizontal bars comparing account vs segment average' },
            { name: 'customer360FeatureMap', tab: 'Usage & Adoption', purpose: 'Feature enablement grid \u2014 entitled vs enabled vs active, with whitespace analysis' },
            { name: 'customer360TicketStats', tab: 'Support', purpose: 'Support metrics \u2014 open/closed counts, avg resolution time, CSAT score, escalations' },
            { name: 'customer360InvoiceSummary', tab: 'Invoices', purpose: 'Financial summary \u2014 total invoiced, outstanding balance, overdue amount, avg days to pay' },
            { name: 'customer360Timeline', tab: 'Timeline', purpose: 'Vertical activity feed with type filters (calls, emails, meetings, notes, milestones)' },
            { name: 'customer360CtaList', tab: 'CTAs & Playbooks', purpose: 'CTA (Call-to-Action) cards with status, priority, due date, progress tracking' },
            { name: 'customer360Playbook', tab: 'CTAs & Playbooks', purpose: 'Step-by-step playbook checklist with progress indicator and completion tracking' },
            { name: 'customer360TaskList', tab: 'CTAs & Playbooks', purpose: 'Personal task manager \u2014 add, complete, filter, and prioritize tasks' },
            { name: 'customer360SuccessPlan', tab: 'Success Plan', purpose: 'Goals and milestones with progress bars, status indicators, and target dates' }
        ];
    }

    /** Enhanced existing components */
    get enhancedComponents() {
        return [
            { name: 'customer360', purpose: 'Complete rewrite \u2014 root container with two-view routing, state management, event bus' },
            { name: 'customer360Subscriptions', purpose: 'Added summary metrics row + mock data fallback (still uses Apex when available)' },
            { name: 'customer360Usage', purpose: 'Added usage trend charts + adoption progress bars + mock fallback' },
            { name: 'customer360Support', purpose: 'Added ticket stats child component + mock fallback' },
            { name: 'customer360Invoices', purpose: 'Added financial summary child component + mock fallback' }
        ];
    }

    /** Supporting metadata */
    get supportingMetadata() {
        return [
            { type: 'Custom Application', name: 'Customer_360', purpose: 'Lightning app definition with tab navigation' },
            { type: 'Custom Tab', name: 'Customer_360', purpose: 'Tab pointing to the Customer_360_Home FlexiPage' },
            { type: 'FlexiPage', name: 'Customer_360_Home', purpose: 'Lightning App Page hosting the root customer360 LWC' },
            { type: 'Apex Class', name: 'Customer360Controller', purpose: 'Server-side controller for Salesforce data (accounts, subscriptions, invoices)' },
            { type: 'Apex Class', name: 'ZendeskService', purpose: 'Integration service for Zendesk support ticket data' }
        ];
    }

    /**********************************************************************************************
     *
     * Requirements Coverage
     *
     ***********************************************************************************************/

    get priority1Requirements() {
        return [
            { requirement: 'Health Monitoring', components: 'HealthRing, Scorecard, Banner', status: 'done' },
            { requirement: 'Health Trends', components: 'HealthTrend', status: 'done' },
            { requirement: 'Product Usage', components: 'Usage (enhanced), FeatureMap', status: 'done' },
            { requirement: 'Approximate Health', components: 'Scorecard (automated factors)', status: 'done' },
            { requirement: 'Benchmarking', components: 'Benchmark', status: 'done' },
            { requirement: 'Support Stats', components: 'TicketStats', status: 'done' },
            { requirement: 'Timeline', components: 'Timeline', status: 'done' },
            { requirement: 'Prior Communications', components: 'Timeline (filters)', status: 'done' },
            { requirement: 'Feature Enablement', components: 'FeatureMap', status: 'done' },
            { requirement: 'Playbooks', components: 'Playbook', status: 'done' },
            { requirement: 'Task Management', components: 'TaskList', status: 'done' },
            { requirement: 'Manual Health Override', components: 'HealthOverride', status: 'done' },
            { requirement: 'CSAT Feedback', components: 'TicketStats', status: 'done' },
            { requirement: 'Churn Notifications', components: 'AlertsPanel, Header', status: 'done' }
        ];
    }

    get priority2Requirements() {
        return [
            { requirement: 'Usage Decline Alerts', components: 'AlertsPanel', status: 'done' },
            { requirement: 'Health Change Alerts', components: 'AlertsPanel', status: 'done' },
            { requirement: 'Renewal Status', components: 'InvoiceSummary, Overview', status: 'done' },
            { requirement: 'Client Prioritization', components: 'PortfolioList', status: 'done' },
            { requirement: 'Gap Analysis', components: 'FeatureMap, SuccessPlan', status: 'done' },
            { requirement: 'Open Services', components: 'Overview widget', status: 'done' },
            { requirement: 'Reminders', components: 'TaskList, AlertsPanel', status: 'done' }
        ];
    }

    get deferredRequirements() {
        return [
            { requirement: 'Document Sharing', components: '\u2014', status: 'deferred' },
            { requirement: 'Meeting Scheduling', components: '\u2014', status: 'deferred' },
            { requirement: 'Direct Communication', components: '\u2014', status: 'deferred' },
            { requirement: 'AI Templates', components: '\u2014', status: 'deferred' }
        ];
    }

    /**********************************************************************************************
     *
     * Statistics
     *
     ***********************************************************************************************/

    get stats() {
        return [
            { label: 'Total Components', value: '32', icon: 'utility:component_customization' },
            { label: 'Lines of Code', value: '~11,350', icon: 'utility:code_playground' },
            { label: 'Total Files', value: '132', icon: 'utility:file' },
            { label: 'Detail Tabs', value: '9', icon: 'utility:tabs' },
            { label: 'Requirements Met', value: '27/31', icon: 'utility:check' },
            { label: 'Coverage', value: '87%', icon: 'utility:chart' }
        ];
    }

    get detailTabs() {
        return [
            { name: 'Overview', description: 'Summary KPIs, recent activity, CTA summary' },
            { name: 'Health', description: 'Scorecard, trends, benchmarks, manual override' },
            { name: 'Subscriptions', description: 'Active subscriptions with summary metrics' },
            { name: 'Usage & Adoption', description: 'Usage trends, adoption progress, feature map' },
            { name: 'Support', description: 'Support tickets, CSAT, escalations' },
            { name: 'Invoices', description: 'Invoice list, financial summary' },
            { name: 'Timeline', description: 'Activity feed with type filters' },
            { name: 'CTAs & Playbooks', description: 'Call-to-action cards, playbooks, tasks' },
            { name: 'Success Plan', description: 'Goals, milestones, progress tracking' }
        ];
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    handleBackClick() {
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { view: 'dashboard' }
        }));
    }
}