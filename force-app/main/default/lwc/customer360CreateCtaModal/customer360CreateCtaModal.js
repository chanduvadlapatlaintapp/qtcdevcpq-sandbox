/**
 * @description Modal component for creating a CTA (Call-to-Action) Task linked to an Account.
 *              Supports Risk, Expansion, Renewal, and Lifecycle CTA types with priority,
 *              description, and due date fields.
 * @author  Yousef A
 * @date    03/06/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createCta from '@salesforce/apex/Customer360Controller.createCta';
import { isSalesforceId } from 'c/customer360Utils';

export default class Customer360CreateCtaModal extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;
    @api accountName = '';

    // ─── Private Properties ───────────────────────────────────────────────────
    ctaType = 'Risk';
    priority = 'Normal';
    description = '';
    dueDate = '';
    isSaving = false;

    // ─── Lifecycle ────────────────────────────────────────────────────────────
    connectedCallback() {
        // Default due date to 14 days from now
        const d = new Date();
        d.setDate(d.getDate() + 14);
        this.dueDate = d.toISOString().split('T')[0];
    }

    // ─── Getters ──────────────────────────────────────────────────────────────
    get ctaTypeOptions() {
        return [
            { label: 'Risk', value: 'Risk' },
            { label: 'Expansion', value: 'Expansion' },
            { label: 'Renewal', value: 'Renewal' },
            { label: 'Lifecycle', value: 'Lifecycle' }
        ];
    }

    get priorityOptions() {
        return [
            { label: 'High', value: 'High' },
            { label: 'Normal', value: 'Normal' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get modalTitle() {
        return this.accountName ? `Create CTA — ${this.accountName}` : 'Create CTA';
    }

    get isSaveDisabled() {
        return this.isSaving;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleTypeChange(event) {
        this.ctaType = event.detail.value;
    }

    handlePriorityChange(event) {
        this.priority = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    handleDueDateChange(event) {
        this.dueDate = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        // Demo mode — no Apex call
        if (!isSalesforceId(this.accountId)) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Demo Mode',
                message: `${this.ctaType} CTA created (demo only — not saved to Salesforce).`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('ctacreated', {
                detail: {
                    ctaType: this.ctaType,
                    priority: this.priority,
                    description: this.description,
                    dueDate: this.dueDate
                }
            }));
            this.dispatchEvent(new CustomEvent('close'));
            return;
        }

        this.isSaving = true;
        try {
            const taskId = await createCta({
                accountId: this.accountId,
                ctaType: this.ctaType,
                priority: this.priority,
                description: this.description,
                dueDate: this.dueDate
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'CTA Created',
                message: `${this.ctaType} CTA has been created successfully.`,
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('ctacreated', {
                detail: { taskId, ctaType: this.ctaType, priority: this.priority }
            }));

            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || 'Failed to create CTA.',
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }
}