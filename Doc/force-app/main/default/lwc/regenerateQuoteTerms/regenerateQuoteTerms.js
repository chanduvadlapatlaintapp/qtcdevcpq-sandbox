/**
 * @description  : LWC Quick Action to regenerate Quote Terms (Term_Quote__c) for a given Quote.
 *                 Resolves BIZ-66664 — allows supersession language to appear in Quote Terms
 *                 immediately after selecting Cancellation_terms__c, without needing to
 *                 generate the OSA document first.
 * @author       : Ratan Paul
 * @date         : 2026-03-04
 * @story        : BIZ-66664
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateQuoteTerms from '@salesforce/apex/QuoteTermValidator.generateQuoteTerms';

export default class RegenerateQuoteTerms extends NavigationMixin(LightningElement) {
    _recordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.regenerateTerms();
        }
    }
    isLoading = false;

    regenerateTerms() {
        console.log('========> recordId: ' + this.recordId);
        if (!this.recordId) return;
        this.isLoading = true;
        generateQuoteTerms({ quoteId: this.recordId })
            .then(result => {
                this.isLoading = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: result || 'Quote Terms regenerated successfully.',
                    variant: 'success'
                }));
                this.navigateToRecord();
            })
            .catch(error => {
                this.isLoading = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : 'Failed to regenerate Quote Terms.',
                    variant: 'error'
                }));
                this.navigateToRecord();
            });
    }

    navigateToRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                actionName: 'view'
            }
        });
    }
}