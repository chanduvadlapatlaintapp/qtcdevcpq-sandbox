/**
 * @description Modal component for logging an activity (Task) against an Account.
 *              Supports Call, Email, and Meeting activity types with subject, description,
 *              and date fields. Creates a completed Task via Apex.
 * @author  Yousef A
 * @date    03/06/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import logActivity from '@salesforce/apex/Customer360Controller.logActivity';
import { isSalesforceId } from 'c/customer360Utils';

export default class Customer360LogActivityModal extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;
    @api accountName = '';

    // ─── Private Properties ───────────────────────────────────────────────────
    activityType = 'Call';
    subject = '';
    description = '';
    activityDate = new Date().toISOString().split('T')[0];
    isSaving = false;

    // ─── Getters ──────────────────────────────────────────────────────────────
    get activityTypeOptions() {
        return [
            { label: 'Call', value: 'Call' },
            { label: 'Email', value: 'Email' },
            { label: 'Meeting', value: 'Meeting' }
        ];
    }

    get modalTitle() {
        return this.accountName ? `Log Activity — ${this.accountName}` : 'Log Activity';
    }

    get isSaveDisabled() {
        return this.isSaving || !this.subject.trim();
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleTypeChange(event) {
        this.activityType = event.detail.value;
    }

    handleSubjectChange(event) {
        this.subject = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    handleDateChange(event) {
        this.activityDate = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        if (!this.subject.trim()) return;

        // Demo mode — no Apex call
        if (!isSalesforceId(this.accountId)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Demo Mode',
                message: `Activity "${this.subject}" logged (demo only — not saved to Salesforce).`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('activitylogged', {
                detail: {
                    activityType: this.activityType,
                    subject: this.subject,
                    description: this.description,
                    activityDate: this.activityDate
                }
            }));
            this.dispatchEvent(new CustomEvent('close'));
            return;
        }

        this.isSaving = true;
        try {
            const taskId = await logActivity({
                accountId: this.accountId,
                activityType: this.activityType,
                subject: this.subject,
                description: this.description,
                activityDate: this.activityDate
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Activity Logged',
                message: `${this.activityType} "${this.subject}" has been logged successfully.`,
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('activitylogged', {
                detail: { taskId, activityType: this.activityType, subject: this.subject }
            }));

            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to log activity.',
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }
}