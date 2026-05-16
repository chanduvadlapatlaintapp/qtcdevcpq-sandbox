import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getSubscriptions from '@salesforce/apex/ContractSubscriptionController.getSubscriptions';
import getSubscriptionsByContractNumber from '@salesforce/apex/ContractSubscriptionController.getSubscriptionsByContractNumber';
import CONTRACT_ID_FIELD from '@salesforce/schema/Contract.Id';

const FIELDS = [CONTRACT_ID_FIELD];

export default class ContractSubscriptionList extends LightningElement {
    @api recordId; // Contract record ID
    
    subscriptions = [];
    isLoading = false;
    error;
    selectedDate = new Date();
    minDate = new Date(2023, 0, 1);
    maxDate = new Date(2026, 11, 31);
    contractNumber = '';
    customerName = '';
    hasSearched = false;
    
    connectedCallback() {
        // If no recordId, don't load subscriptions initially - wait for contract number input
        if (!this.recordId) {
            this.isLoading = false;
        }
    }
    
    // Wire to get contract record (only when recordId is present)
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredContract({ error, data }) {
        if (this.recordId) {
            if (data) {
                this.loadSubscriptions();
            } else if (error) {
                this.error = error;
                this.isLoading = false;
            }
        }
    }
    
    loadSubscriptions() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        getSubscriptions({ contractId: this.recordId })
            .then(result => {
                this.subscriptions = this.processSubscriptions(result);
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.subscriptions = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    loadAllSubscriptions() {
        this.isLoading = true;
        getSubscriptions({ contractId: null })
            .then(result => {
                this.subscriptions = this.processSubscriptions(result);
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.subscriptions = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    loadSubscriptionsByContractNumber(contractNumber) {
        if (!contractNumber || contractNumber.trim() === '') {
            this.subscriptions = [];
            this.hasSearched = false;
            return;
        }
        
        this.isLoading = true;
        this.hasSearched = true;
        getSubscriptionsByContractNumber({ contractNumber: contractNumber.trim() })
            .then(result => {
                this.subscriptions = this.processSubscriptions(result);
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.subscriptions = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    processSubscriptions(subscriptions) {
        if (!subscriptions) return [];
        return subscriptions.map(sub => {
            const quantity = sub.SBQQ__Quantity__c || 1;
            const monthlyCost = sub.SBQQ__NetPrice__c || 0;
            return {
                ...sub,
                Quantity__c: quantity, // Keep for template compatibility
                MonthlyCost__c: monthlyCost, // Keep for template compatibility
                Contract__r: sub.SBQQ__Contract__r, // Map for template compatibility
                ContractName: sub.SBQQ__Contract__r ? sub.SBQQ__Contract__r.Name : '',
                formattedStartDate: this.formatDateValue(sub.SBQQ__StartDate__c),
                formattedMonthlyCost: this.formatCurrencyValue(monthlyCost),
                formattedACV: this.formatCurrencyValue(monthlyCost * 12 * quantity)
            };
        });
    }
    
    handleRefresh() {
        if (this.recordId) {
            this.loadSubscriptions();
        } else if (this.contractNumber) {
            this.loadSubscriptionsByContractNumber(this.contractNumber);
        } else {
            this.loadAllSubscriptions();
        }
    }
    
    handleContractNumberChange(event) {
        this.contractNumber = event.target.value;
        // Debounce: wait a bit before searching to avoid too many calls
        clearTimeout(this.searchTimeout);
        this.searchTimeout = setTimeout(() => {
            this.loadSubscriptionsByContractNumber(this.contractNumber);
        }, 500); // Wait 500ms after user stops typing
    }
    
    handleCustomerNameChange(event) {
        this.customerName = event.target.value;
        // Customer name is for display/filtering purposes only
        // Could be used for additional filtering in the future
    }
    
    handleDateChange(event) {
        const dateValue = event.target.value;
        if (dateValue) {
            this.selectedDate = new Date(dateValue);
        }
    }
    
    handleSliderChange(event) {
        const daysOffset = parseInt(event.target.value, 10);
        const newDate = new Date(this.minDate);
        newDate.setDate(newDate.getDate() + daysOffset);
        this.selectedDate = newDate;
    }
    
    get hasSubscriptions() {
        return this.activeSubscriptions && this.activeSubscriptions.length > 0;
    }
    
    get activeSubscriptions() {
        if (!this.subscriptions || this.subscriptions.length === 0) {
            return [];
        }
        
        return this.subscriptions.filter(sub => {
            if (!sub.SBQQ__StartDate__c) return false;
            const subStart = new Date(sub.SBQQ__StartDate__c);
            const subEnd = sub.SBQQ__EndDate__c ? new Date(sub.SBQQ__EndDate__c) : null;
            return subStart <= this.selectedDate && (!subEnd || subEnd >= this.selectedDate);
        });
    }
    
    get totalDays() {
        return Math.floor((this.maxDate.getTime() - this.minDate.getTime()) / (1000 * 60 * 60 * 24));
    }
    
    get currentDayOffset() {
        return Math.floor((this.selectedDate.getTime() - this.minDate.getTime()) / (1000 * 60 * 60 * 24));
    }
    
    get formattedSelectedDate() {
        return this.selectedDate.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'long', 
            day: 'numeric' 
        });
    }
    
    get formattedMinDate() {
        return this.minDate.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'long', 
            day: 'numeric' 
        });
    }
    
    get formattedMaxDate() {
        return this.maxDate.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'long', 
            day: 'numeric' 
        });
    }
    
    get totalMonthlyCost() {
        return this.activeSubscriptions.reduce((sum, sub) => {
            return sum + (sub.SBQQ__NetPrice__c || 0);
        }, 0);
    }
    
    get totalACV() {
        return this.activeSubscriptions.reduce((sum, sub) => {
            const quantity = sub.SBQQ__Quantity__c || 1;
            const acv = (sub.SBQQ__NetPrice__c || 0) * 12 * quantity;
            return sum + acv;
        }, 0);
    }
    
    get formattedTotalMonthlyCost() {
        const amount = this.totalMonthlyCost;
        if (!amount) return '$0';
        return '$' + amount.toLocaleString();
    }
    
    get formattedTotalACV() {
        const amount = this.totalACV;
        if (!amount) return '$0';
        return '$' + amount.toLocaleString();
    }
    
    get showContractColumn() {
        // Show contract column when viewing all subscriptions (no recordId) or when searching by contract number
        return !this.recordId;
    }
    
    get showContent() {
        // Show date slider, stats, and table only when we have a recordId or have searched by contract number
        return this.recordId || this.hasSearched;
    }
    
    get errorMessage() {
        if (!this.error) return 'Unknown error';
        if (this.error.body && this.error.body.message) {
            return this.error.body.message;
        }
        if (this.error.message) {
            return this.error.message;
        }
        return 'Unknown error';
    }
    
    // Helper method to format dates (used in template with computed properties)
    formatDateValue(dateString) {
        if (!dateString) return '';
        return new Date(dateString).toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'short', 
            day: 'numeric' 
        });
    }
    
    // Helper method to format currency (used in template with computed properties)
    formatCurrencyValue(amount) {
        if (!amount) return '$0';
        return '$' + amount.toLocaleString();
    }
}