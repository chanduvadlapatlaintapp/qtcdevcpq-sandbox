/**
 * @description 
 *  GenericRelatedList is a reusable Lightning Web Component to display a related list dynamically.
 *  It accepts object name, field names, and a filter field to retrieve and display related records.
 *  This component uses Apex to fetch records and UI API to retrieve field labels.
 * 
 * @author  Ratan Paul
 * @date    05/02/2025
 * @jira    BIZ-68163
 */
import { LightningElement, api, wire } from 'lwc';
import getRelatedRecords from '@salesforce/apex/GenericRelatedListController.getRelatedRecords';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class GenericRelatedList extends LightningElement {
    // Public properties passed from parent
    @api objectApiName;           // API name of the related object (e.g., 'Contact')
    @api fieldApiNames;           // Comma-separated list of field API names to display
    @api filterFieldApiName;      // Field to filter related records (e.g., 'AccountId')
    @api cardTitle = 'Related Records'; // Title shown in the card
    @api recordId;                // Parent record Id to filter by

    // Internal state
    records;                      // Holds fetched related records
    columns = [];                 // Datatable column configuration
    error;                        // Stores error message, if any
    fieldLabelMap = {};           // Maps field API names to their label for display

    /**
     * Fetches object metadata using lightning/uiObjectInfoApi to:
     * - Resolve field labels
     * - Build datatable columns (first column as clickable link)
     */
    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    objectInfoHandler({ data, error }) {
        if (data) {
            // Split and trim field API names
            const fieldApis = this.fieldApiNames.split(',').map(f => f.trim());

            // Build label map
            fieldApis.forEach(field => {
                const fieldMeta = data.fields[field];
                this.fieldLabelMap[field] = fieldMeta ? fieldMeta.label : field;
            });

            // Build columns for lightning-datatable
            this.columns = fieldApis.map((field, index) => {
                const label = this.fieldLabelMap[field];

                // If label is 'Booking Date', use 'EndDate' as the field to display
                const effectiveField = label === 'Booking Date' ? 'Contract End Date' : label;

                // Make first column a clickable link to the record
                if (index === 0) {
                    return {
                        label: effectiveField,
                        fieldName: 'recordLink', // Custom field we'll inject into each record
                        type: 'url',
                        typeAttributes: {
                            label: { fieldName: field }, // Use actual field value as label
                            target: '_blank'
                        }
                    };
                }

                // Standard column
                return {
                    label: effectiveField,
                    fieldName: field
                };
            });

            // Load related records after metadata is ready
            this.loadData();
        } else if (error) {
            this.error = `Error loading object metadata: ${error.body?.message || error.message}`;
        }
    }

    /**
     * Loads related records via Apex using the provided object/field/filter configuration.
     * Adds 'recordLink' to each record for the first column link.
     */
    loadData() {
        getRelatedRecords({
            objectApiName: this.objectApiName,
            fieldApiNames: this.fieldApiNames,
            filterFieldApiName: this.filterFieldApiName,
            filterValue: this.recordId
        })
            .then(result => {
                // Add recordLink to each record (used for URL column)
                this.records = result.map(row => ({
                    ...row,
                    recordLink: '/' + row.Id
                }));
                this.error = undefined;
            })
            .catch(error => {
                this.records = undefined;
                this.error = error?.body?.message || error.message;
            });
    }

    /**
     * Returns the icon URL based on the object API name.
     * Icon should match SLDS standard object icons.
     */
    get objectIcon() {
        return `/img/icon/t4v35/standard/${this.objectApiName.toLowerCase()}_60.png`;
    }

    /**
     * Safely returns the number of loaded records.
     */
    get recordCount() {
        return this.records?.length || 0;
    }
    /**
     * @description 
    *  check if the records variable has data or not. based on that hide the empty table
    */
    get hasRecords() {
        return this.records && this.records.length > 0;
    }
}