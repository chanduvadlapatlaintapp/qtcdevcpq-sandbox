/**
 * @description
 *  Modal LWC for uploading files to a Quote with a required Document Type selection.
 *  Extends LightningModal to be opened programmatically from quoteFileList.
 *  Uses getPicklistValues wire adapter to dynamically fetch Document_Type__c values.
 *  After upload, stamps Document_Type__c on ContentVersion via Apex.
 *
 * @author  Sahal Mohamed
 * @date    02/17/2026
 * @jira    BIZ-79176
 */
import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CONTENT_VERSION_OBJECT from '@salesforce/schema/ContentVersion';
import DOCUMENT_TYPE_FIELD from '@salesforce/schema/ContentVersion.Document_Type__c';
import updateDocumentType from '@salesforce/apex/QuoteFileUploadController.updateDocumentType';

export default class QuoteFileUploadModal extends LightningModal {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @api Quote record Id passed from the parent component */
    @api recordId;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    selectedDocumentType = '';
    documentTypeOptions = [];
    errorMessage = '';
    isProcessing = false;

    // Stores upload event data for retry
    _pendingContentDocumentIds = [];

    /** Accepted file formats -- allow all common types */
    acceptedFormats = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt', '.png', '.jpg', '.jpeg'];

    /**********************************************************************************************
     *
     * Wire Adapters
     *
     ***********************************************************************************************/

    /** Get ContentVersion object info to retrieve the default record type Id for picklist wire */
    @wire(getObjectInfo, { objectApiName: CONTENT_VERSION_OBJECT })
    contentVersionInfo;

    /** Get picklist values for Document_Type__c */
    @wire(getPicklistValues, {
        recordTypeId: '$defaultRecordTypeId',
        fieldApiName: DOCUMENT_TYPE_FIELD
    })
    wiredPicklistValues({ data, error }) {
        if (data) {
            this.documentTypeOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            this.errorMessage = 'Failed to load Document Type options: ' +
                (error?.body?.message || error.message || 'Unknown error');
        }
    }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /** Returns the default record type Id from the ContentVersion object info */
    get defaultRecordTypeId() {
        return this.contentVersionInfo?.data?.defaultRecordTypeId;
    }

    /** Upload area is only enabled when a Document Type is selected */
    get isUploadEnabled() {
        return !!this.selectedDocumentType;
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * Handles Document Type combobox selection change.
     * @param {Event} event - Change event from lightning-combobox.
     */
    handleDocumentTypeChange(event) {
        this.selectedDocumentType = event.detail.value;
        this.errorMessage = '';
    }

    /**
     * Handles the uploadfinished event from lightning-file-upload.
     * Extracts ContentDocument Ids and calls Apex to stamp Document Type.
     * @param {Event} event - Upload finished event containing file details.
     */
    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        this._pendingContentDocumentIds = uploadedFiles.map(file => file.documentId);

        await this._stampDocumentType();
    }

    /**
     * Retries the Apex call to stamp Document Type (no re-upload needed).
     */
    async handleRetry() {
        if (this._pendingContentDocumentIds.length > 0) {
            await this._stampDocumentType();
        }
    }

    /**
     * Closes the modal without any action.
     */
    handleCancel() {
        this.close({ success: false });
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Calls Apex to stamp Document_Type__c on the uploaded ContentVersion records.
     *              On success, closes modal with success flag. On failure, displays error with retry.
     */
    async _stampDocumentType() {
        this.isProcessing = true;
        this.errorMessage = '';

        try {
            await updateDocumentType({
                contentDocumentIds: this._pendingContentDocumentIds,
                documentType: this.selectedDocumentType
            });

            this._pendingContentDocumentIds = [];
            this.close({ success: true });
        } catch (error) {
            this.errorMessage = 'Failed to set Document Type: ' +
                (error?.body?.message || error.message || 'Unknown error') +
                '. Files were uploaded -- click Retry to stamp the Document Type.';
        } finally {
            this.isProcessing = false;
        }
    }
}