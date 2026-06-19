import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ACCOUNT_ID from '@salesforce/schema/SBQQ__Quote__c.SBQQ__Account__c';
import ACCOUNT_NAME from '@salesforce/schema/SBQQ__Quote__c.Account_Name__c';
import CONTRACT_ID from '@salesforce/schema/SBQQ__Quote__c.SBQQ__MasterContract__c';
import CONTRACT_NUMBER from '@salesforce/schema/SBQQ__Quote__c.SBQQ__MasterContract__r.ContractNumber';
import CURRENCY_CODE from '@salesforce/schema/SBQQ__Quote__c.CurrencyIsoCode';

const FIELDS = [ACCOUNT_ID, ACCOUNT_NAME, CONTRACT_ID, CONTRACT_NUMBER, CURRENCY_CODE];

/**
 * @description Quote record-page quick action that deep-links the current CPQ quote
 *              into the Agentic QTC app's Simplified Quote Editor. Reads the quote's
 *              account + master-contract context and navigates to the "Agentic QTC" tab,
 *              passing it as page state. The app reads those params and opens the quote
 *              directly in the editor — with the account/contract header and breadcrumb
 *              populated, skipping the account/contract selection screens.
 * @author      Anand Manhas
 * @date        2026-06-01
 * @jira        BIZ-81419
 */
export default class SimplifiedQuoteEditor extends NavigationMixin(LightningElement) {
    // Public API
    @api recordId;

    // Private Properties
    _navigated = false;

    // Wired Data
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    handleQuote({ data, error }) {
        if (this._navigated) {
            return;
        }
        if (data) {
            this.navigateToEditor({
                accountId: getFieldValue(data, ACCOUNT_ID),
                accountName: getFieldValue(data, ACCOUNT_NAME),
                contractId: getFieldValue(data, CONTRACT_ID),
                contractNumber: getFieldValue(data, CONTRACT_NUMBER),
                currencyIsoCode: getFieldValue(data, CURRENCY_CODE)
            });
        } else if (error) {
            // Couldn't read the quote (FLS, etc.) — still open the editor with just the
            // id; it loads everything else from the quote via SOQL on the server.
            this.navigateToEditor({});
        }
    }

    // Private Methods
    navigateToEditor(ctx) {
        if (!this.recordId) {
            return;
        }
        this._navigated = true;
        const state = { c__quoteId: this.recordId };
        if (ctx.accountId) state.c__accountId = ctx.accountId;
        if (ctx.accountName) state.c__accountName = ctx.accountName;
        if (ctx.contractId) state.c__contractId = ctx.contractId;
        if (ctx.contractNumber) state.c__contractNumber = ctx.contractNumber;
        if (ctx.currencyIsoCode) state.c__currencyIsoCode = ctx.currencyIsoCode;

        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Agentic_QTC'
            },
            state
        });
        // Close the quick-action modal once navigation has been requested.
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}