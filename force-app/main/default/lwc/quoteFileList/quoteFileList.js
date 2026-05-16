/**
 * @description
 *  Custom related list LWC that replaces the standard Files related list on Quote record pages.
 *  Displays both modern ContentVersion files and classic Attachment records linked to the Quote.
 *  ContentVersion rows get View/Edit/Delete actions; Attachment rows get Delete only.
 *  Upload opens quoteFileUploadModal which enforces mandatory Document Type selection.
 *
 * @author  Sahal Mohamed
 * @date    02/17/2026
 * @jira    BIZ-79176
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getQuoteFiles from '@salesforce/apex/QuoteFileUploadController.getQuoteFiles';
import deleteFile from '@salesforce/apex/QuoteFileUploadController.deleteFile';
import deleteAttachment from '@salesforce/apex/QuoteFileUploadController.deleteAttachment';
import QuoteFileUploadModal from 'c/quoteFileUploadModal';
import QuoteFileEditModal from 'c/quoteFileEditModal';

/** Maximum records shown on the related list before "View All" is required */
const DISPLAY_LIMIT = 5;

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

// Column definitions for the datatable
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

export default class QuoteFileList extends NavigationMixin(LightningElement) {

    /**********************************************************************************************
     *
     * Public API
     *
     ***********************************************************************************************/

    /** Quote record Id from the record page */
    @api recordId;

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
        this.loadFiles();
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

    /** Returns the total count of all files */
    get fileCount() {
        return this.fileData ? this.fileData.length : 0;
    }

    /** Returns the first DISPLAY_LIMIT records for the related list datatable */
    get displayData() {
        if (!this.fileData) {
            return [];
        }
        return this.fileData.slice(0, DISPLAY_LIMIT);
    }

    /** Returns true when total files exceed the display limit */
    get showViewAll() {
        return this.fileData && this.fileData.length > DISPLAY_LIMIT;
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
            recordId: this.recordId
        });

        if (result && result.success) {
            this.loadFiles();
            this._refreshRecordPage();
        }
    }

    /**
     * Handles column sort requests from the datatable.
     * Sorts the full fileData array so the display limit applies to sorted data.
     * @param {Event} event - Sort event from lightning-datatable.
     */
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortDirection = sortDirection;
        this.fileData = this._sortData(fieldName, sortDirection);
    }

    /**
     * Navigates to the Visualforce page hosting the quoteFileViewAll LWC
     * via Lightning Out, passing the Quote Id as a URL parameter.
     */
    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/apex/QuoteFileViewAll?quoteId=' + this.recordId
            }
        });
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
     * @description Fetches files linked to this Quote via Apex (ContentVersion + Attachment)
     *              and transforms them for datatable display, assigning dynamic row actions
     *              based on the record source.
     */
    async loadFiles() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await getQuoteFiles({ quoteId: this.recordId });
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
     *              Handles text, date, and numeric types. For the URL-type Title column,
     *              sorts by the display label (fileName) rather than the URL.
     * @param {String} fieldName - The field API name to sort by.
     * @param {String} direction - 'asc' or 'desc'.
     * @return {Array} A new sorted copy of fileData.
     */
    _sortData(fieldName, direction) {
        const data = [...this.fileData];
        const reverse = direction === 'desc' ? -1 : 1;

        // For the URL-type Title column, sort by the display label
        const sortField = fieldName === 'fileUrl' ? 'fileName' : fieldName;

        data.sort((a, b) => {
            let valA = a[sortField];
            let valB = b[sortField];

            // Handle nulls/undefined
            if (valA == null && valB == null) return 0;
            if (valA == null) return 1 * reverse;
            if (valB == null) return -1 * reverse;

            // Numeric sort for contentSize (used by formattedSize)
            if (sortField === 'formattedSize') {
                valA = a.contentSize || 0;
                valB = b.contentSize || 0;
                return (valA - valB) * reverse;
            }

            // Date sort
            if (sortField === 'createdDate') {
                return (new Date(valA) - new Date(valB)) * reverse;
            }

            // Default string sort (case-insensitive)
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
     *              Only applicable for ContentVersion source rows.
     * @param {Object} row - The row data from the datatable.
     */
    _viewFileDetails(row) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.contentDocumentId,
                objectApiName: 'ContentDocument',
                actionName: 'view'
            }
        });
    }

    /**
     * @description Opens the edit modal pre-populated with the file's current Title and Document Type.
     *              Only applicable for ContentVersion source rows.
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
            this._refreshRecordPage();
        }
    }

    /**
     * @description Shows a confirmation dialog and deletes the file/attachment if confirmed.
     *              Uses deleteFile for ContentVersion rows and deleteAttachment for Attachment rows.
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
            this._refreshRecordPage();
        } catch (error) {
            this.errorMessage = 'Failed to delete file: ' +
                (error?.body?.message || error.message || 'Unknown error');
            this.isLoading = false;
        }
    }

    /**
     * Forces a full browser-level page reload after a short delay to allow
     * the modal to close and pending operations to complete.
     */
    _refreshRecordPage() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            window.location.reload();
        }, 500);
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