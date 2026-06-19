import { LightningElement, track } from 'lwc';
import getOpportunities from '@salesforce/apex/OpportunityBulkUpdateController.getOpportunities';
import getStageValues from '@salesforce/apex/OpportunityBulkUpdateController.getStageValues';
import getUsers from '@salesforce/apex/OpportunityBulkUpdateController.getUsers';
import saveOpportunities from '@salesforce/apex/OpportunityBulkUpdateController.saveOpportunities';

// =========================================================================
// Constants
// =========================================================================

const DEAL_TYPES = [
    { label: 'Renewal', value: 'Renewal' },
    { label: 'NextYear_MultiYear', value: 'NextYear_MultiYear' }
];

const BULK_EDIT_FIELDS = [
    { label: 'Close Date', value: 'CloseDate' },
    { label: 'Owner', value: 'OwnerId' },
    { label: 'OP4I Deal Owner (Lookup)', value: 'OP4I_Deal_Owner_Id__c' },
    { label: 'OP4I Deal Owner Text', value: 'OP4I_Deal_Owner__c' },
    { label: 'Stage', value: 'StageName' }
];

const EXPORT_COLUMNS = [
    { header: 'Name',                       field: 'Name' },
    { header: 'Opportunity ID',             field: 'Id' },
    { header: 'Created Date',               field: 'CreatedDate' },
    { header: 'Deal Type',                  field: 'Deal_Type__c' },
    { header: 'Owner',                      field: '_ownerName' },
    { header: 'OP4I Deal Owner (Lookup)',   field: '_op4iLookupName' },
    { header: 'OP4I Deal Owner Text',       field: 'OP4I_Deal_Owner__c' },
    { header: 'Close Date',                 field: 'CloseDate' },
    { header: 'Stage',                      field: 'StageName' }
];

const TOAST_DURATION  = 8000;
const MAX_SAVE_RECORDS = 200;

// =========================================================================
// Component
// =========================================================================

export default class OpportunityBulkUpdate extends LightningElement {

    // =========================================================================
    // Private Properties
    // =========================================================================

    // Filter state
    @track filterCloseDate     = '';
    @track filterCreatedDate   = '';
    @track filterName          = '';
    @track filterOpportunityId = '';
    @track filterStage         = '';
    @track selectedDealTypes   = ['Renewal', 'NextYear_MultiYear'];

    // Data state
    @track isLoading       = false;
    @track isSaving        = false;
    @track records         = [];
    @track error           = null;
    @track successMessage  = null;
    @track hasFetched      = false;

    // Cell-level edit state
    @track editingCellRowId  = null;
    @track editingCellField  = null;
    @track changedRows       = {}; // { recordId: { field: newValue } }

    // Selection state
    @track selectedRowMap = {}; // { recordId: true }

    // Bulk edit state
    @track bulkEditField = '';
    @track bulkEditValue = '';

    // Picklist options
    @track stageOptions     = [{ label: 'All Stages', value: '' }];
    @track stageEditOptions = [];
    @track userOptions      = [];

    // Import state
    @track isImporting = false;

    // Save results — maps recordId -> { success: boolean, errorMessage: string|null }
    @track saveResultMap = {};

    // Toast auto-dismiss timer
    _toastTimer = null;

    // =========================================================================
    // Lifecycle Hooks
    // =========================================================================

    connectedCallback() {
        this.loadStageValues();
        this.loadUsers();
        this.setDefaultDates();
    }

    setDefaultDates() {
        this.filterCloseDate   = '2025-12-04';
        this.filterCreatedDate = '2025-08-24';
    }

    async loadStageValues() {
        try {
            const stages = await getStageValues();
            this.stageOptions = [
                { label: 'All Stages', value: '' },
                ...stages.map(s => ({ label: s, value: s }))
            ];
            this.stageEditOptions = stages.map(s => ({ label: s, value: s }));
        } catch (err) {
            // Non-blocking; filters work without stage dropdown
        }
    }

    async loadUsers() {
        try {
            const users = await getUsers();
            this.userOptions = users.map(u => ({ label: u.Name, value: u.Id }));
        } catch (err) {
            // Non-blocking; cells fall back to text input if empty
        }
    }

    // =========================================================================
    // Getters - Data
    // =========================================================================

    get hasResults() {
        return !this.isLoading && this.records.length > 0;
    }

    get showNoResults() {
        return !this.isLoading && this.hasFetched && this.records.length === 0;
    }

    get totalRecordCount() {
        return this.records.length;
    }

    get hasChanges() {
        return Object.keys(this.changedRows).length > 0;
    }

    get changedRowCount() {
        return Object.keys(this.changedRows).length;
    }

    get exceedsMaxRecords() {
        return this.changedRowCount > MAX_SAVE_RECORDS;
    }

    get isSaveDisabled() {
        return !this.hasChanges || this.isSaving || this.exceedsMaxRecords;
    }

    get dealTypePills() {
        return DEAL_TYPES.map(dt => ({
            ...dt,
            cssClass: 'deal-type-pill'
                + (this.selectedDealTypes.includes(dt.value) ? ' deal-type-pill--active' : '')
        }));
    }

    // =========================================================================
    // Getters - Selection & Bulk Edit
    // =========================================================================

    get hasSelectedRows() {
        return Object.keys(this.selectedRowMap).length > 0;
    }

    get selectedRowCount() {
        return Object.keys(this.selectedRowMap).length;
    }

    get isAllSelected() {
        return this.records.length > 0
            && Object.keys(this.selectedRowMap).length === this.records.length;
    }

    get bulkEditFieldOptions() {
        return BULK_EDIT_FIELDS;
    }

    get isBulkFieldDate() {
        return this.bulkEditField === 'CloseDate';
    }

    get isBulkFieldText() {
        return this.bulkEditField === 'OP4I_Deal_Owner__c';
    }

    get isBulkFieldUser() {
        return this.bulkEditField === 'OwnerId'
            || this.bulkEditField === 'OP4I_Deal_Owner_Id__c';
    }

    get isBulkFieldStage() {
        return this.bulkEditField === 'StageName';
    }

    get isBulkApplyDisabled() {
        return !this.bulkEditField || !this.bulkEditValue || !this.hasSelectedRows;
    }

    // =========================================================================
    // Getters - Toast
    // =========================================================================

    get showToast() {
        return this.successMessage || this.error;
    }

    get toastClass() {
        if (this.error) return 'toast toast--error';
        return 'toast toast--success';
    }

    get toastIconName() {
        return this.error ? 'utility:error' : 'utility:success';
    }

    get toastMessage() {
        return this.error || this.successMessage;
    }

    // =========================================================================
    // Getters - Save Results
    // =========================================================================

    get hasSaveResults() {
        return Object.keys(this.saveResultMap).length > 0;
    }

    get saveSuccessCount() {
        return Object.values(this.saveResultMap).filter(r => r.success).length;
    }

    get saveFailureCount() {
        return Object.values(this.saveResultMap).filter(r => !r.success).length;
    }

    get hasSaveSuccesses() {
        return this.saveSuccessCount > 0;
    }

    get hasSaveFailures() {
        return this.saveFailureCount > 0;
    }

    get saveFailedRows() {
        return Object.entries(this.saveResultMap)
            .filter(([, result]) => !result.success)
            .map(([recordId, result]) => {
                const rec = this.records.find(r => r.Id === recordId);
                return {
                    recordId,
                    name: rec ? rec.Name : recordId,
                    errorMessage: result.errorMessage || 'Unknown error'
                };
            });
    }

    // =========================================================================
    // Getter - Display Rows
    // =========================================================================

    get displayRows() {
        const baseUrl = window.location.origin;
        return this.records.map(rec => {
            const changes = this.changedRows[rec.Id] || {};
            const merged  = { ...rec, ...changes };
            const isChanged  = !!this.changedRows[rec.Id];
            const isSelected = !!this.selectedRowMap[rec.Id];

            // Save result for this row
            const saveResult   = this.saveResultMap[rec.Id];
            const isSaveSuccess = !!(saveResult && saveResult.success === true);
            const isSaveFailed  = !!(saveResult && saveResult.success === false);

            // Cell-level editing flags
            const isEditingCloseDate     = this.editingCellRowId === rec.Id && this.editingCellField === 'CloseDate';
            const isEditingOP4IDealOwner = this.editingCellRowId === rec.Id && this.editingCellField === 'OP4I_Deal_Owner__c';
            const isEditingStage         = this.editingCellRowId === rec.Id && this.editingCellField === 'StageName';
            const isEditing = isEditingCloseDate || isEditingOP4IDealOwner || isEditingStage;

            // Format dates
            let closeDateFormatted = '';
            if (merged.CloseDate) {
                const d = new Date(merged.CloseDate + 'T00:00:00');
                closeDateFormatted = (d.getMonth() + 1) + '/' + d.getDate() + '/' + d.getFullYear();
            }

            let createdDateFormatted = '';
            if (rec.CreatedDate) {
                const d = new Date(rec.CreatedDate);
                createdDateFormatted = (d.getMonth() + 1) + '/' + d.getDate() + '/' + d.getFullYear();
            }

            // Stage badge class
            let stageBadgeClass = 'stage-badge';
            const stage = (merged.StageName || '').toLowerCase();
            if (stage.includes('closed won'))  stageBadgeClass += ' stage-badge--won';
            else if (stage.includes('closed')) stageBadgeClass += ' stage-badge--lost';
            else if (stage.includes('qualify')) stageBadgeClass += ' stage-badge--qualify';
            else if (stage.includes('pending')) stageBadgeClass += ' stage-badge--pending';

            return {
                ...merged,
                isEditing,
                isEditingCloseDate,
                isEditingOP4IDealOwner,
                isEditingStage,
                isSelected,
                isSaveSuccess,
                isSaveFailed,
                saveErrorMessage: (saveResult && saveResult.errorMessage) ? saveResult.errorMessage : '',
                closeDateFormatted,
                createdDateFormatted,
                stageBadgeClass,
                ownerName:              rec.Owner ? rec.Owner.Name : '',
                op4iDealOwnerLookupName: rec.OP4I_Deal_Owner_Id__r ? rec.OP4I_Deal_Owner_Id__r.Name : '',
                recordUrl: baseUrl + '/' + rec.Id,
                rowClass: 'data-row'
                    + (isEditing    ? ' data-row--editing'      : '')
                    + (isChanged    ? ' data-row--changed'      : '')
                    + (isSelected   ? ' data-row--selected'     : '')
                    + (isSaveSuccess ? ' data-row--save-success' : '')
                    + (isSaveFailed  ? ' data-row--save-error'   : '')
            };
        });
    }

    // =========================================================================
    // Filter Handlers
    // =========================================================================

    handleCloseDateChange(event) {
        this.filterCloseDate = event.detail.value;
    }

    handleCreatedDateChange(event) {
        this.filterCreatedDate = event.detail.value;
    }

    handleNameChange(event) {
        this.filterName = event.detail.value;
    }

    handleOpportunityIdChange(event) {
        this.filterOpportunityId = event.detail.value;
    }

    handleStageChange(event) {
        this.filterStage = event.detail.value;
    }

    handleDealTypePillClick(event) {
        const value = event.currentTarget.dataset.value;
        if (this.selectedDealTypes.includes(value)) {
            if (this.selectedDealTypes.length > 1) {
                this.selectedDealTypes = this.selectedDealTypes.filter(v => v !== value);
            }
        } else {
            this.selectedDealTypes = [...this.selectedDealTypes, value];
        }
    }

    // =========================================================================
    // Data Fetch
    // =========================================================================

    async handleApplyFilters() {
        this.isLoading       = true;
        this.error           = null;
        this.editingCellRowId = null;
        this.editingCellField = null;
        this.changedRows     = {};
        this.selectedRowMap  = {};
        this.saveResultMap   = {};

        try {
            const data = await getOpportunities({
                closeDateAfter:   this.filterCloseDate   || null,
                createdDateAfter: this.filterCreatedDate || null,
                dealTypes:        this.selectedDealTypes,
                stageName:        this.filterStage       || null,
                nameSearch:       this.filterName        || null,
                opportunityId:    this.filterOpportunityId || null
            });
            this.records    = data;
            this.hasFetched = true;
        } catch (err) {
            this.error   = this._extractErrorMessage(err);
            this.records = [];
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // Cell-Level Inline Edit Handlers
    // =========================================================================

    handleCellClick(event) {
        const rowId = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        this.editingCellRowId = rowId;
        this.editingCellField = field;
    }

    handleCellChange(event) {
        const rowId = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;

        const existing = this.changedRows[rowId] || {};
        this.changedRows = {
            ...this.changedRows,
            [rowId]: { ...existing, [field]: value }
        };

        this.editingCellRowId = null;
        this.editingCellField = null;
    }

    // =========================================================================
    // Selection Handlers
    // =========================================================================

    handleSelectAll(event) {
        const checked = event.target.checked;
        if (checked) {
            const map = {};
            this.records.forEach(r => { map[r.Id] = true; });
            this.selectedRowMap = map;
        } else {
            this.selectedRowMap = {};
        }
    }

    handleRowSelect(event) {
        const rowId   = event.target.dataset.id;
        const checked = event.target.checked;
        const updated = { ...this.selectedRowMap };
        if (checked) {
            updated[rowId] = true;
        } else {
            delete updated[rowId];
        }
        this.selectedRowMap = updated;
    }

    // =========================================================================
    // Bulk Edit Handlers
    // =========================================================================

    handleBulkFieldChange(event) {
        this.bulkEditField = event.detail.value;
        this.bulkEditValue = '';
    }

    handleBulkValueChange(event) {
        this.bulkEditValue = event.detail.value;
    }

    handleBulkApply() {
        if (!this.bulkEditField || !this.bulkEditValue) return;

        const updatedChanges = { ...this.changedRows };
        Object.keys(this.selectedRowMap).forEach(rowId => {
            const existing = updatedChanges[rowId] || {};
            updatedChanges[rowId] = { ...existing, [this.bulkEditField]: this.bulkEditValue };
        });
        this.changedRows = updatedChanges;

        // Clear bulk edit inputs but keep selection
        this.bulkEditField = '';
        this.bulkEditValue = '';
    }

    handleClearSelection() {
        this.selectedRowMap = {};
        this.bulkEditField  = '';
        this.bulkEditValue  = '';
    }

    // =========================================================================
    // Save
    // =========================================================================

    async handleSave() {
        if (!this.hasChanges) return;

        this.isSaving       = true;
        this.error          = null;
        this.successMessage = null;
        this.saveResultMap  = {};
        this._clearToastTimer();

        try {
            const updates = Object.entries(this.changedRows).map(([id, fields]) => ({
                Id: id,
                ...fields
            }));

            const results = await saveOpportunities({ opportunitiesJson: JSON.stringify(updates) });

            // Build result map from returned SaveResult array
            const resultMap = {};
            results.forEach(r => {
                resultMap[r.recordId] = { success: r.success, errorMessage: r.errorMessage };
            });
            this.saveResultMap = resultMap;

            const successCount = results.filter(r => r.success).length;
            const failCount    = results.filter(r => !r.success).length;

            // Capture failed records' staged changes to restore after refetch
            const failedChanges = {};
            results.forEach(r => {
                if (!r.success && this.changedRows[r.recordId]) {
                    failedChanges[r.recordId] = this.changedRows[r.recordId];
                }
            });

            // Set toast message
            if (failCount === 0) {
                this.successMessage = successCount + ' record' + (successCount !== 1 ? 's' : '') + ' saved successfully.';
            } else if (successCount === 0) {
                this.error = 'Save failed — all ' + failCount + ' record' + (failCount !== 1 ? 's' : '') + ' encountered errors. See the results panel below.';
            } else {
                this.successMessage = successCount + ' saved, ' + failCount + ' failed. See the results panel below for details.';
            }

            this.editingCellRowId = null;
            this.editingCellField = null;
            this._startToastTimer();

            // Refetch fresh data (this clears changedRows internally)
            await this._refetchData();

            // Restore staged changes for failed records so the user can fix and retry
            if (Object.keys(failedChanges).length > 0) {
                this.changedRows = { ...this.changedRows, ...failedChanges };
            }
        } catch (err) {
            this.error = this._extractErrorMessage(err);
            this._startToastTimer();
        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================================
    // Save Results Handlers
    // =========================================================================

    handleDismissSaveResults() {
        this.saveResultMap = {};
    }

    // =========================================================================
    // Toast Handlers
    // =========================================================================

    handleDismissToast() {
        this.successMessage = null;
        this.error          = null;
        this._clearToastTimer();
    }

    _startToastTimer() {
        this._clearToastTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => {
            this.successMessage = null;
            this.error          = null;
        }, TOAST_DURATION);
    }

    _clearToastTimer() {
        if (this._toastTimer) {
            clearTimeout(this._toastTimer);
            this._toastTimer = null;
        }
    }

    // =========================================================================
    // Export
    // =========================================================================

    handleExport() {
        if (!this.records || this.records.length === 0) return;

        const rows = this.records.map(rec => {
            const changes = this.changedRows[rec.Id] || {};
            const merged  = { ...rec, ...changes };
            return EXPORT_COLUMNS.map(col => {
                let val = '';
                if (col.field === '_ownerName') {
                    const changedOwnerId = changes.OwnerId;
                    if (changedOwnerId) {
                        const opt = this.userOptions.find(u => u.value === changedOwnerId);
                        val = opt ? opt.label : changedOwnerId;
                    } else {
                        val = rec.Owner ? rec.Owner.Name : '';
                    }
                } else if (col.field === '_op4iLookupName') {
                    const changedLookupId = changes.OP4I_Deal_Owner_Id__c;
                    if (changedLookupId) {
                        const opt = this.userOptions.find(u => u.value === changedLookupId);
                        val = opt ? opt.label : changedLookupId;
                    } else {
                        val = rec.OP4I_Deal_Owner_Id__r ? rec.OP4I_Deal_Owner_Id__r.Name : '';
                    }
                } else {
                    val = merged[col.field] != null ? String(merged[col.field]) : '';
                }
                if (val.includes(',') || val.includes('"') || val.includes('\n')) {
                    val = '"' + val.replace(/"/g, '""') + '"';
                }
                return val;
            });
        });

        const header     = EXPORT_COLUMNS.map(col => col.header).join(',');
        const csvContent = header + '\n' + rows.map(r => r.join(',')).join('\n');

        const encodedCsv = encodeURIComponent(csvContent);
        const dataUri    = 'data:text/csv;charset=utf-8,' + encodedCsv;
        const timestamp  = new Date().toISOString().slice(0, 10);
        const link = document.createElement('a');
        link.setAttribute('href', dataUri);
        link.setAttribute('download', 'Opportunities_Export_' + timestamp + '.csv');
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    // =========================================================================
    // Import
    // =========================================================================

    handleImportClick() {
        const fileInput = this.template.querySelector('input[data-id="csv-import"]');
        if (fileInput) {
            fileInput.value = null;
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.isImporting    = true;
        this.error          = null;
        this.successMessage = null;
        this._clearToastTimer();

        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                this._processImportCsv(e.target.result);
            } catch (err) {
                this.error = 'Import failed: ' + (err.message || 'Invalid CSV format.');
                this._startToastTimer();
            } finally {
                this.isImporting = false;
            }
        };
        reader.onerror = () => {
            this.error       = 'Failed to read file.';
            this.isImporting = false;
            this._startToastTimer();
        };
        reader.readAsText(file);
    }

    _processImportCsv(csvText) {
        const lines = csvText.split(/\r?\n/).filter(line => line.trim() !== '');
        if (lines.length < 2) {
            throw new Error('CSV must contain a header row and at least one data row.');
        }

        const headers = this._parseCsvLine(lines[0]);
        const idIdx   = this._findColumnIndex(headers, ['Opportunity ID', 'Id', 'OpportunityId']);
        if (idIdx === -1) {
            throw new Error('CSV must contain an "Opportunity ID" or "Id" column.');
        }

        const closeDateIdx      = this._findColumnIndex(headers, ['Close Date', 'CloseDate']);
        const ownerIdIdx        = this._findColumnIndex(headers, ['Owner ID', 'OwnerId']);
        const ownerNameIdx      = this._findColumnIndex(headers, ['Owner', 'Owner Name']);
        const op4iLookupIdx     = this._findColumnIndex(headers, ['OP4I Deal Owner (Lookup) ID', 'OP4I_Deal_Owner_Id__c']);
        const op4iLookupNameIdx = this._findColumnIndex(headers, ['OP4I Deal Owner (Lookup)', 'OP4I Deal Owner (Lookup) Name']);
        const ownerIdx          = this._findColumnIndex(headers, ['OP4I Deal Owner Text', 'OP4I Deal Owner', 'OP4I_Deal_Owner__c']);
        const stageValueIdx     = this._findColumnIndex(headers, ['Stage Value', 'Stage', 'StageName']);
        const stageLabelIdx     = this._findColumnIndex(headers, ['Stage Label']);

        const recordMap = {};
        this.records.forEach(r => { recordMap[r.Id] = r; });

        let matchedCount     = 0;
        let skippedCount     = 0;
        let changedFieldCount = 0;
        const updatedChanges = { ...this.changedRows };

        for (let i = 1; i < lines.length; i++) {
            const cols  = this._parseCsvLine(lines[i]);
            const oppId = (cols[idIdx] || '').trim();

            if (!oppId || !recordMap[oppId]) {
                skippedCount++;
                continue;
            }

            matchedCount++;
            const existing = updatedChanges[oppId] || {};
            let rowChanged = false;

            if (closeDateIdx !== -1 && cols[closeDateIdx] != null) {
                const dateVal = this._parseImportDate(cols[closeDateIdx].trim());
                if (dateVal) { existing.CloseDate = dateVal; rowChanged = true; changedFieldCount++; }
            }

            if (ownerIdIdx !== -1 && cols[ownerIdIdx] != null && cols[ownerIdIdx].trim() !== '') {
                existing.OwnerId = cols[ownerIdIdx].trim(); rowChanged = true; changedFieldCount++;
            } else if (ownerNameIdx !== -1 && cols[ownerNameIdx] != null && cols[ownerNameIdx].trim() !== '') {
                const resolvedId = this._findUserIdByName(cols[ownerNameIdx].trim());
                if (resolvedId) { existing.OwnerId = resolvedId; rowChanged = true; changedFieldCount++; }
            }

            if (op4iLookupIdx !== -1 && cols[op4iLookupIdx] != null && cols[op4iLookupIdx].trim() !== '') {
                existing.OP4I_Deal_Owner_Id__c = cols[op4iLookupIdx].trim(); rowChanged = true; changedFieldCount++;
            } else if (op4iLookupNameIdx !== -1 && cols[op4iLookupNameIdx] != null && cols[op4iLookupNameIdx].trim() !== '') {
                const resolvedId = this._findUserIdByName(cols[op4iLookupNameIdx].trim());
                if (resolvedId) { existing.OP4I_Deal_Owner_Id__c = resolvedId; rowChanged = true; changedFieldCount++; }
            }

            if (ownerIdx !== -1 && cols[ownerIdx] != null && cols[ownerIdx].trim() !== '') {
                existing.OP4I_Deal_Owner__c = cols[ownerIdx].trim(); rowChanged = true; changedFieldCount++;
            }

            if (stageValueIdx !== -1 && cols[stageValueIdx] != null && cols[stageValueIdx].trim() !== '') {
                existing.StageName = cols[stageValueIdx].trim(); rowChanged = true; changedFieldCount++;
            } else if (stageLabelIdx !== -1 && cols[stageLabelIdx] != null && cols[stageLabelIdx].trim() !== '') {
                const labelVal = cols[stageLabelIdx].trim();
                const opt = this.stageEditOptions.find(s => s.label.toLowerCase() === labelVal.toLowerCase());
                existing.StageName = opt ? opt.value : labelVal; rowChanged = true; changedFieldCount++;
            }

            if (rowChanged) { updatedChanges[oppId] = existing; }
        }

        this.changedRows = updatedChanges;

        if (matchedCount === 0) {
            throw new Error('No matching Opportunity IDs found. Make sure records are loaded first.');
        }

        this.successMessage = 'Import complete: ' + matchedCount + ' record' + (matchedCount !== 1 ? 's' : '')
            + ' matched, ' + changedFieldCount + ' field' + (changedFieldCount !== 1 ? 's' : '') + ' staged for update.'
            + (skippedCount > 0 ? ' ' + skippedCount + ' row' + (skippedCount !== 1 ? 's' : '') + ' skipped (not in current results).' : '');
        this._startToastTimer();
    }

    _parseCsvLine(line) {
        const result = [];
        let current  = '';
        let inQuotes = false;

        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (inQuotes) {
                if (ch === '"') {
                    if (i + 1 < line.length && line[i + 1] === '"') { current += '"'; i++; }
                    else { inQuotes = false; }
                } else { current += ch; }
            } else if (ch === '"') { inQuotes = true; }
            else if (ch === ',')   { result.push(current); current = ''; }
            else                   { current += ch; }
        }
        result.push(current);
        return result;
    }

    _findColumnIndex(headers, possibleNames) {
        const normalized = headers.map(h => h.trim().toLowerCase());
        for (const name of possibleNames) {
            const idx = normalized.indexOf(name.toLowerCase());
            if (idx !== -1) return idx;
        }
        return -1;
    }

    _findUserIdByName(name) {
        if (!name || !this.userOptions.length) return null;
        const normalized = name.trim().toLowerCase();
        const match = this.userOptions.find(u => u.label.toLowerCase() === normalized);
        return match ? match.value : null;
    }

    _parseImportDate(val) {
        if (!val) return null;
        if (/^\d{4}-\d{2}-\d{2}$/.test(val)) return val;
        const slashMatch = val.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
        if (slashMatch) {
            const m = slashMatch[1].padStart(2, '0');
            const d = slashMatch[2].padStart(2, '0');
            return slashMatch[3] + '-' + m + '-' + d;
        }
        if (val.includes('T')) { return val.split('T')[0]; }
        return null;
    }

    // =========================================================================
    // Private - Re-fetch without clearing messages or save results
    // =========================================================================

    async _refetchData() {
        this.isLoading       = true;
        this.editingCellRowId = null;
        this.editingCellField = null;
        this.changedRows     = {};
        this.selectedRowMap  = {};

        try {
            const data = await getOpportunities({
                closeDateAfter:   this.filterCloseDate   || null,
                createdDateAfter: this.filterCreatedDate || null,
                dealTypes:        this.selectedDealTypes,
                stageName:        this.filterStage       || null,
                nameSearch:       this.filterName        || null,
                opportunityId:    this.filterOpportunityId || null
            });
            this.records    = data;
            this.hasFetched = true;
        } catch (err) {
            if (!this.successMessage) {
                this.error = this._extractErrorMessage(err);
            }
            this.records = [];
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    _extractErrorMessage(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred.';
    }
}