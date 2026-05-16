import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import generateQuoteTerms from '@salesforce/apex/CongaUrlService.generateQuoteTerms';
import generateCongaURL from '@salesforce/apex/CongaUrlService.generateCongaURL';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import NAME_FIELD from "@salesforce/schema/SBQQ__Quote__c.Name";
import ACCOUNT_NAME_FIELD from "@salesforce/schema/SBQQ__Quote__c.Account_Name__c";

const fields = [NAME_FIELD, ACCOUNT_NAME_FIELD];

export default class OpenAccountQuickAction extends NavigationMixin(LightningElement) {
    recordId;
    message;
    @track isLoading = false;

    @wire(getRecord, { recordId: '$recordId', fields })
    quote;

    get name() {
        return getFieldValue(this.quote.data, NAME_FIELD);
    }

    get accountName() {
        return getFieldValue(this.quote.data, ACCOUNT_NAME_FIELD);
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.recordId;
        }
    }

    connectedCallback() {
        this.invokeApexClass();
    }

    invokeApexClass() {
        this.isLoading = true;
        generateQuoteTerms({quoteId :this.recordId })
        .then(result => {
            this.message = result;
            this.generateCongaURL(); 
        })
        .catch(error => {
            this.error = error.message;
        });
    }

    generateCongaURL() {
        this.isLoading = true;
        generateCongaURL({ quoteId: this.recordId })
            .then((result) => {
                this.message = result;
                console.log('Message from generateCongaURL: ' + this.message);
                this.redirectToConga(this.message);
            })
            .catch((error) => {
                this.error = error.message;
                console.log('Error generating Conga URL: ' + this.error);
            });
    }

    redirectToConga(message) {
        this.isLoading = false;
        var recId = this.recordId;
        let url = message;
        console.log('Navigating to Conga URL: ' + url + ' for Record ID: ' + recId);
        this.navigateToRecordPage(url);
    }

    navigateToRecordPage(urlRedirect) {
        const config = {
            type: 'standard__webPage',
            attributes: {
                url: urlRedirect,
            },
        };
        this[NavigationMixin.Navigate](config);
    }
}