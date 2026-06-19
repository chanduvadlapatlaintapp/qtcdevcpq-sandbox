/**
 * @description Lightning Web Component to display field history records as a related list
 * @author Sahal
 * @createdDate Jan-05-2026
 */
import { LightningElement, api, wire } from 'lwc';
import getFieldHistoryRecords from '@salesforce/apex/FieldHistoryController.getFieldHistoryRecords';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Field',
        fieldName: 'Field_Label__c',
        type: 'text',
        sortable: true
    },
    {
        label: 'Old Value',
        fieldName: 'Old_Value__c',
        type: 'text',
        wrapText: true,
        sortable: true
    },
    {
        label: 'New Value',
        fieldName: 'New_Value__c',
        type: 'text',
        wrapText: true,
        sortable: true
    },
    {
        label: 'Changed By',
        fieldName: 'Changed_By_Name__c',
        type: 'text',
        sortable: true
    },
    {
        label: 'Change Date',
        fieldName: 'Change_Date__c',
        type: 'date',
        typeAttributes: {
            month: 'numeric',
            day: 'numeric',
            year: 'numeric'
        },
        sortable: true
    }
];

const DISPLAY_LIMIT = 10;

export default class FieldHistoryRelatedList extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    fieldHistoryRecords = [];
    wiredFieldHistoryRecords;
    isLoading = false;
    error;
    sortedBy = 'Change_Date__c';
    sortedDirection = 'desc';

    @wire(getFieldHistoryRecords, { parentRecordId: '$recordId' })
    wiredRecords(result) {
        this.wiredFieldHistoryRecords = result;
        this.isLoading = result.data === undefined && result.error === undefined;

        if (result.data) {
            this.fieldHistoryRecords = result.data.map(record => ({
                ...record,
                Change_Date__c: record.Change_Date__c ? new Date(record.Change_Date__c) : null,
                Changed_By_Name__c: record.Changed_By__r?.Name || 'System'
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error;
            this.fieldHistoryRecords = [];
            this.isLoading = false;
        }
    }

    get hasRecords() {
        return this.fieldHistoryRecords && this.fieldHistoryRecords.length > 0;
    }

    get totalCount() {
        return this.fieldHistoryRecords ? this.fieldHistoryRecords.length : 0;
    }

    get countDisplay() {
        const count = this.totalCount;
        return count > DISPLAY_LIMIT ? `${DISPLAY_LIMIT}+` : `${count}`;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredFieldHistoryRecords)
            .then(() => {
                this.isLoading = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error refreshing',
                    message: error.body?.message || error.message,
                    variant: 'error'
                }));
            });
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;

        const data = [...this.fieldHistoryRecords];
        data.sort((a, b) => {
            let valA = a[fieldName] || '';
            let valB = b[fieldName] || '';
            if (valA instanceof Date) {
                valA = valA.getTime();
                valB = valB ? valB.getTime() : 0;
            } else if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = (valB || '').toLowerCase();
            }
            let result = 0;
            if (valA > valB) result = 1;
            else if (valA < valB) result = -1;
            return sortDirection === 'asc' ? result : -result;
        });
        this.fieldHistoryRecords = data;
    }
}