/**
 * @description
 *  Modal LWC for editing Title and Document Type on an existing file (ContentVersion).
 *  Extends LightningModal to be opened programmatically from quoteFileList.
 *  Dynamically fetches Document_Type__c picklist values via wire adapter.
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
import updateFileDetails from '@salesforce/apex/QuoteFileUploadController.updateFileDetails';

export default class QuoteFileEditModal extends LightningModal {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** @api ContentVersion Id of the file being edited */
    @api contentVersionId;

    /** @api Current title of the file */
    @api currentTitle;

    /** @api Current Document Type value */
    @api currentDocumentType;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    title = '';
    documentType = '';
    documentTypeOptions = [];
    errorMessage = '';
    isSaving = false;

    /**********************************************************************************************
     *
     * Lifecycle Hooks
     *
     ***********************************************************************************************/

    connectedCallback() {
        this.title = this.currentTitle || '';
        this.documentType = this.currentDocumentType || '';
    }

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

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    handleTitleChange(event) {
        this.title = event.detail.value;
        this.errorMessage = '';
    }

    handleDocumentTypeChange(event) {
        this.documentType = event.detail.value;
        this.errorMessage = '';
    }

    handleCancel() {
        this.close({ success: false });
    }

    async handleSave() {
        // Client-side validation
        if (!this.title || !this.title.trim()) {
            this.errorMessage = 'Title is required.';
            return;
        }
        if (!this.documentType) {
            this.errorMessage = 'Document Type is required.';
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            await updateFileDetails({
                contentVersionId: this.contentVersionId,
                title: this.title.trim(),
                documentType: this.documentType
            });
            this.close({ success: true });
        } catch (error) {
            this.errorMessage = 'Failed to save: ' +
                (error?.body?.message || error.message || 'Unknown error');
        } finally {
            this.isSaving = false;
        }
    }
}