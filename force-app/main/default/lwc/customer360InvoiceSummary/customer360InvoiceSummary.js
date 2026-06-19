/**
 * @description Invoice financial summary for Customer 360 Invoices tab.
 *              Displays total invoiced, outstanding, overdue, and avg days to pay.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { formatCurrency } from 'c/customer360Utils';

export default class Customer360InvoiceSummary extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api invoices = [];

    // ─── Getters ──────────────────────────────────────────────────────────────
    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }

    get totalInvoiced() {
        const total = this.invoices.reduce((sum, inv) => sum + (inv.amountInvoiced || 0), 0);
        return formatCurrency(total, true);
    }

    get totalOutstanding() {
        const total = this.invoices.reduce((sum, inv) => sum + (inv.outstandingBalance || 0), 0);
        return formatCurrency(total, true);
    }

    get outstandingClass() {
        const total = this.invoices.reduce((sum, inv) => sum + (inv.outstandingBalance || 0), 0);
        return total > 0 ? 'c360-is__stat-value c360-is__stat-value--warning' : 'c360-is__stat-value c360-is__stat-value--good';
    }

    get overdueCount() {
        return this.invoices.filter(inv => inv.status === 'Overdue').length;
    }

    get overdueClass() {
        return this.overdueCount > 0
            ? 'c360-is__stat-value c360-is__stat-value--poor'
            : 'c360-is__stat-value c360-is__stat-value--good';
    }

    get overdueAmount() {
        const total = this.invoices
            .filter(inv => inv.status === 'Overdue')
            .reduce((sum, inv) => sum + (inv.outstandingBalance || 0), 0);
        return formatCurrency(total, true);
    }

    get avgDaysToPay() {
        const paid = this.invoices.filter(inv => inv.datePaid && inv.dueDate);
        if (!paid.length) return 'N/A';
        const totalDays = paid.reduce((sum, inv) => {
            const due = new Date(inv.dueDate);
            const paidDate = new Date(inv.datePaid);
            const diff = Math.floor((paidDate - due) / (1000 * 60 * 60 * 24));
            return sum + Math.max(diff, 0);
        }, 0);
        const avg = totalDays / paid.length;
        return avg.toFixed(0) + 'd';
    }

    get paidCount() {
        return this.invoices.filter(inv => inv.status === 'Paid').length;
    }

    get collectionRate() {
        if (!this.invoices.length) return '0%';
        return Math.round((this.paidCount / this.invoices.length) * 100) + '%';
    }
}