import { LightningElement, wire, api } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CLOSED_DATE_FIELD from '@salesforce/schema/Order.Date_Opportunity_Closed__c';

export default class OrderClosedMonthWarning extends LightningElement {
    @api recordId;
    showWarning = false;

    @wire(getRecord, { recordId: '$recordId', fields: [CLOSED_DATE_FIELD] })
    wiredRecord({ data }) {
        if (data) {
            const closedDate = getFieldValue(data, CLOSED_DATE_FIELD);
            if (closedDate) {
                // Append T00:00:00 to parse as local date, avoiding UTC-shift off-by-one
                const closed = new Date(closedDate + 'T00:00:00');
                const today = new Date();
                this.showWarning =
                    closed.getMonth() !== today.getMonth() ||
                    closed.getFullYear() !== today.getFullYear();
            }
        }
    }
}