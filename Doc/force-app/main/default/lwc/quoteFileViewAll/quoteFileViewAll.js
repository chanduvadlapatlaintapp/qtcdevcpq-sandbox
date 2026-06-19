/**
 * @description
 *  Full-page view showing all files (ContentVersion + Attachment) linked to a Quote.
 *  Navigated to from the "View All" link in the quoteFileList related list component.
 *  Supports sortable columns, Upload, Edit, and Delete actions.
 *
 * @author  Sahal Mohamed
 * @date    02/20/2026
 * @jira    BIZ-79176
 */
import { LightningElement, api } from 'lwc';
import getQuoteFiles from '@salesforce/apex/QuoteFileUploadController.getQuoteFiles';
import deleteFile from '@salesforce/apex/QuoteFileUploadController.deleteFile';
import deleteAttachment from '@salesforce/apex/QuoteFileUploadController.deleteAttachment';
import QuoteFileUploadModal from 'c/quoteFileUploadModal';
import QuoteFileEditModal from 'c/quoteFileEditModal';

// Row actions for ContentVersion files
const CV_ACTIONS = [
    { label: 'View File Details', name: 'view', iconName: 'utility:preview' },
    { label: 'Edit', name: 'edit', iconName: 'utility:edit' },
    { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
];

// Row actions for classic Attachment records
const ATT_ACTIONS = [
    { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
];

// Column definitions — all sortable
const COLUMNS = [
    {
        label: 'Title',
        fieldName: 'fileUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'fileName' },
            target: '_blank',
            tooltip: { fieldName: 'fileName' }
        },
        sortable: true
    },
    {
        label: 'Document Type',
        fieldName: 'documentType',
        type: 'text',
        sortable: true
    },
    {
        label: 'File Size',
        fieldName: 'formattedSize',
        type: 'text',
        sortable: true
    },
    {
        label: 'File Type',
        fieldName: 'fileType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'numeric',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        },
        sortable: true
    },
    {
        label: 'Uploaded By',
        fieldName: 'createdByName',
        type: 'text',
        sortable: true
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: { fieldName: 'rowActions' }
        }
    }
];

export default class QuoteFileViewAll extends LightningElement {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** Quote record Id passed from the Visualforce page via Lightning Out */
    @api quoteId;

    /**********************************************************************************************
     *
     * Private Properties
     *
     ***********************************************************************************************/

    fileData = [];
    columns = COLUMNS;
    isLoading = true;
    errorMessage = '';
    sortedBy = '';
    sortDirection = 'asc';

    /**********************************************************************************************
     *
     * Lifecycle Hooks
     *
     ***********************************************************************************************/

    connectedCallback() {
        if (this.quoteId) {
            this.loadFiles();
        }
    }

    /**********************************************************************************************
     *
     * Getters
     *
     ***********************************************************************************************/

    /** Returns true if files are available to display */
    get hasFiles() {
        return this.fileData && this.fileData.length > 0;
    }

    /** Returns the total count of files */
    get fileCount() {
        return this.fileData ? this.fileData.length : 0;
    }

    /** Page title with file count */
    get pageTitle() {
        return 'Notes and Attachments (' + this.fileCount + ')';
    }

    /**********************************************************************************************
     *
     * Event Handlers
     *
     ***********************************************************************************************/

    /**
     * Opens the quoteFileUploadModal for file upload with Document Type selection.
     * On successful upload, refreshes the file list.
     */
    async handleUploadClick() {
        const result = await QuoteFileUploadModal.open({
            size: 'small',
            description: 'Upload files with Document Type',
            recordId: this.quoteId
        });

        if (result && result.success) {
            this.loadFiles();
        }
    }

    /**
     * Handles column sort requests from the datatable.
     * @param {Event} event - Sort event from lightning-datatable.
     */
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortDirection = sortDirection;
        this.fileData = this._sortData(fieldName, sortDirection);
    }

    /** Navigates back to the Quote record page */
    handleBack() {
        this._navigateToRecord(this.quoteId);
    }

    /**
     * Handles row-level actions from the datatable (View, Edit, Delete).
     * @param {Event} event - Row action event from lightning-datatable.
     */
    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view') {
            this._viewFileDetails(row);
        } else if (actionName === 'edit') {
            await this._openEditModal(row);
        } else if (actionName === 'delete') {
            await this._confirmAndDeleteFile(row);
        }
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Fetches all files linked to this Quote via Apex and transforms them
     *              for datatable display.
     */
    async loadFiles() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await getQuoteFiles({ quoteId: this.quoteId });
            this.fileData = result.map(fw => ({
                ...fw,
                fileName: fw.title + (fw.fileExtension ? '.' + fw.fileExtension : ''),
                fileUrl: fw.downloadUrl,
                formattedSize: this._formatFileSize(fw.contentSize),
                rowActions: fw.source === 'ContentVersion' ? CV_ACTIONS : ATT_ACTIONS
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error.message || 'Failed to load files.';
            this.fileData = [];
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * @description Sorts the file data array by the given field and direction.
     * @param {String} fieldName - The field API name to sort by.
     * @param {String} direction - 'asc' or 'desc'.
     * @return {Array} A new sorted copy of fileData.
     */
    _sortData(fieldName, direction) {
        const data = [...this.fileData];
        const reverse = direction === 'desc' ? -1 : 1;

        const sortField = fieldName === 'fileUrl' ? 'fileName' : fieldName;

        data.sort((a, b) => {
            let valA = a[sortField];
            let valB = b[sortField];

            if (valA == null && valB == null) return 0;
            if (valA == null) return 1 * reverse;
            if (valB == null) return -1 * reverse;

            if (sortField === 'formattedSize') {
                valA = a.contentSize || 0;
                valB = b.contentSize || 0;
                return (valA - valB) * reverse;
            }

            if (sortField === 'createdDate') {
                return (new Date(valA) - new Date(valB)) * reverse;
            }

            valA = String(valA).toLowerCase();
            valB = String(valB).toLowerCase();
            if (valA < valB) return -1 * reverse;
            if (valA > valB) return 1 * reverse;
            return 0;
        });

        return data;
    }

    /**
     * @description Navigates to the ContentDocument record detail page.
     * @param {Object} row - The row data from the datatable.
     */
    _viewFileDetails(row) {
        this._navigateToRecord(row.contentDocumentId);
    }

    /**
     * @description Opens the edit modal pre-populated with the file's current details.
     * @param {Object} row - The row data from the datatable.
     */
    async _openEditModal(row) {
        const result = await QuoteFileEditModal.open({
            size: 'small',
            description: 'Edit file details',
            contentVersionId: row.id,
            currentTitle: row.title,
            currentDocumentType: row.documentType || ''
        });

        if (result && result.success) {
            this.loadFiles();
        }
    }

    /**
     * @description Shows a confirmation dialog and deletes the file/attachment if confirmed.
     * @param {Object} row - The row data from the datatable.
     */
    async _confirmAndDeleteFile(row) {
        // eslint-disable-next-line no-alert
        const confirmed = confirm('Are you sure you want to delete "' + row.fileName + '"? This cannot be undone.');
        if (!confirmed) {
            return;
        }

        this.isLoading = true;
        try {
            if (row.source === 'Attachment') {
                await deleteAttachment({ attachmentId: row.id });
            } else {
                await deleteFile({ contentDocumentId: row.contentDocumentId });
            }
            this.loadFiles();
        } catch (error) {
            this.errorMessage = 'Failed to delete file: ' +
                (error?.body?.message || error.message || 'Unknown error');
            this.isLoading = false;
        }
    }

    /**
     * @description Navigates to a Salesforce record page using sforce.one (available in VF
     *              pages within Lightning Experience) with a fallback to window.top for
     *              environments where sforce.one is not available.
     * @param {String} recordId - The Salesforce record Id to navigate to.
     */
    _navigateToRecord(recordId) {
        // eslint-disable-next-line no-undef
        if (window.sforce && window.sforce.one) {
            // eslint-disable-next-line no-undef
            window.sforce.one.navigateToSObject(recordId);
        } else {
            window.top.location.href = '/' + recordId;
        }
    }

    /**
     * @description Formats a file size in bytes to a human-readable string (KB/MB/GB).
     * @param {Number} bytes - File size in bytes.
     * @return {String} Formatted file size string.
     */
    _formatFileSize(bytes) {
        if (bytes == null || bytes === 0) {
            return '0 B';
        }
        const units = ['B', 'KB', 'MB', 'GB'];
        let unitIndex = 0;
        let size = bytes;

        while (size >= 1024 && unitIndex < units.length - 1) {
            size /= 1024;
            unitIndex++;
        }

        return size.toFixed(unitIndex === 0 ? 0 : 1) + ' ' + units[unitIndex];
    }
}