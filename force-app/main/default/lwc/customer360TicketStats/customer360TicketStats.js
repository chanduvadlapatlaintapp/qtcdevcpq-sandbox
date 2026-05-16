/**
 * @description Ticket statistics summary for Customer 360 Support tab.
 *              Displays open/closed counts, avg resolution time, CSAT, and escalation metrics.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';

export default class Customer360TicketStats extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api tickets = [];

    // ─── Getters ──────────────────────────────────────────────────────────────
    get openCount() {
        return this.tickets.filter(t => ['Open', 'New', 'Pending'].includes(t.status)).length;
    }

    get closedCount() {
        return this.tickets.filter(t => ['Solved', 'Closed'].includes(t.status)).length;
    }

    get totalCount() {
        return this.tickets.length;
    }

    get avgResolutionDays() {
        const resolved = this.tickets.filter(t => t.resolutionDays != null);
        if (!resolved.length) return 'N/A';
        const avg = resolved.reduce((sum, t) => sum + t.resolutionDays, 0) / resolved.length;
        return avg.toFixed(1) + 'd';
    }

    get avgCsat() {
        const rated = this.tickets.filter(t => t.csat != null);
        if (!rated.length) return 'N/A';
        const avg = rated.reduce((sum, t) => sum + t.csat, 0) / rated.length;
        return avg.toFixed(1) + '/5';
    }

    get csatClass() {
        const rated = this.tickets.filter(t => t.csat != null);
        if (!rated.length) return 'c360-ts__stat-value';
        const avg = rated.reduce((sum, t) => sum + t.csat, 0) / rated.length;
        if (avg >= 4) return 'c360-ts__stat-value c360-ts__stat-value--good';
        if (avg >= 3) return 'c360-ts__stat-value c360-ts__stat-value--fair';
        return 'c360-ts__stat-value c360-ts__stat-value--poor';
    }

    get urgentCount() {
        return this.tickets.filter(t =>
            ['Urgent', 'High'].includes(t.priority) && ['Open', 'New', 'Pending'].includes(t.status)
        ).length;
    }

    get urgentClass() {
        return this.urgentCount > 0
            ? 'c360-ts__stat-value c360-ts__stat-value--poor'
            : 'c360-ts__stat-value c360-ts__stat-value--good';
    }

    get resolutionRate() {
        if (!this.totalCount) return '0%';
        return Math.round((this.closedCount / this.totalCount) * 100) + '%';
    }

    get hasTickets() {
        return this.tickets && this.tickets.length > 0;
    }
}