import { LightningElement, wire,track, api } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Account_Status from '@salesforce/schema/SBQQ__Quote__c.SBQQ__Account__r.Status__c';
import Bill_To_Account_Status from '@salesforce/schema/SBQQ__Quote__c.Bill_To_Account__r.Status__c';
import Ship_To_Account_Status from '@salesforce/schema/SBQQ__Quote__c.Ship_To_Account__r.Status__c';
import Bill_To_Address_Status from '@salesforce/schema/SBQQ__Quote__c.Bill_To_Address__r.Status__c';
import Ship_To_Address_Status from '@salesforce/schema/SBQQ__Quote__c.Ship_To_Address__r.Status__c';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class GovernanceChecklist extends LightningElement {
    @api recordId;
    @track quote;
    @wire(getRecord, { recordId: '$recordId', fields: [Account_Status,Bill_To_Account_Status,
        Ship_To_Account_Status,Bill_To_Address_Status,Ship_To_Address_Status]})
    quote;
    get accountStatus() {
        return getFieldValue(this.quote.data, Account_Status);
    }
    get billToAccountStatus() {
        return getFieldValue(this.quote.data, Bill_To_Account_Status);
    }
    get shipToAccountStatus() {
        return getFieldValue(this.quote.data, Ship_To_Account_Status);
    }
    get billToAddressStatus() {
        return getFieldValue(this.quote.data, Bill_To_Address_Status);
    }
    get shipToAddressStatus() {
        return getFieldValue(this.quote.data, Ship_To_Address_Status);
    }

    // handleFinish(event){
    //     this.dispatchEvent(new CloseActionScreenEvent());
    //}

}