/**
 * @description CTA List for Customer 360.
 *              Displays Calls-to-Action with status, priority, progress, and playbook links.
 *              Supports creating, editing, status transitions, task management.
 *              Receives CTA data from parent via @api; dispatches mutation events upward.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { generatePlaybook } from 'c/customer360MockData';
import { formatDate, generateId } from 'c/customer360Utils';
import { CTA_TYPES, CTA_PRIORITIES, CTA_TAGS, CSM_NAMES } from 'c/customer360Constants';

export default class Customer360CtaList extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    @api
    get ctas() {
        return this._ctas;
    }
    set ctas(value) {
        this._ctas = value ? [...value] : [];
        this._isLoaded = true;
    }

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _ctas = [];
    @track _activeFilter = 'all';
    @track _expandedCtaId = null;
    @track _activePlaybook = null;
    @track _editingCtaId = null;
    @track _showCreateForm = false;
    @track _addingTaskCtaId = null;
    _isLoaded = false;

    // ─── Inline Create Form State ───────────────────────────────────────────
    @track _newCtaName = '';
    @track _newCtaType = 'risk';
    @track _newCtaPriority = 'medium';
    @track _newCtaDueDate = '';
    @track _newCtaAssignee = 'Sarah Chen';

    // ─── Edit Modal State ─────────────────────────────────────────────────
    @track _editName = '';
    @track _editType = '';
    @track _editStatus = '';
    @track _editPriority = '';
    @track _editDueDate = '';
    @track _editAssignee = '';
    @track _editTags = [];

    // ─── Add Task State ─────────────────────────────────────────────────────
    @track _newTaskName = '';

    // ─── Lifecycle Hooks ────────────────────────────────────────────────────
    connectedCallback() {
        // Default new CTA due date to 14 days from now
        const d = new Date();
        d.setDate(d.getDate() + 14);
        this._newCtaDueDate = d.toISOString().split('T')[0];
    }

    // ─── Getters ────────────────────────────────────────────────────────────
    get filteredCtas() {
        let ctas = this._ctas;
        if (this._activeFilter !== 'all') {
            ctas = ctas.filter(c => c.status === this._activeFilter);
        }
        return ctas.map(c => ({
            ...c,
            formattedDueDate: formatDate(c.dueDate, 'short'),
            isOverdue: new Date(c.dueDate) < new Date(),
            dueDateClass: new Date(c.dueDate) < new Date() ? 'c360-cta__due c360-cta__due--overdue' : 'c360-cta__due',
            progressWidth: `width: ${c.progress}%`,
            progressClass: c.progress >= 75 ? 'c360-cta__progress-fill c360-cta__progress-fill--good' :
                          c.progress >= 40 ? 'c360-cta__progress-fill c360-cta__progress-fill--fair' :
                          'c360-cta__progress-fill c360-cta__progress-fill--low',
            isExpanded: c.id === this._expandedCtaId,
            isAddingTask: c.id === this._addingTaskCtaId,
            cardClass: this._getCardClass(c),
            priorityBadgeClass: `c360-cta__priority c360-cta__priority--${c.priority}`,
            statusLabel: this._getStatusLabel(c.status),
            statusBadgeClass: `c360-cta__status c360-cta__status--${c.status}`,
            typeBadgeStyle: `background-color: ${c.typeColor}`,
            isCompleted: c.status === 'completed',
            hasTags: c.tags && c.tags.length > 0,
            tagLabels: (c.tags || []).map(tv => {
                const tagDef = CTA_TAGS.find(t => t.value === tv);
                return tagDef ? tagDef.label : tv;
            }),
            enrichedTasks: (c.tasks || []).map(t => ({
                ...t,
                formattedDueDate: formatDate(t.dueDate, 'short'),
                taskClass: t.completed ? 'c360-cta__task c360-cta__task--done' : 'c360-cta__task',
                checkIcon: t.completed ? 'utility:check' : 'utility:radio_button'
            }))
        }));
    }

    get hasCtas() {
        return this.filteredCtas.length > 0;
    }

    get showEmpty() {
        return this._isLoaded && !this.hasCtas;
    }

    get totalCount() {
        return this._ctas.length;
    }

    get openCount() {
        return this._ctas.filter(c => c.status === 'open').length;
    }

    get inProgressCount() {
        return this._ctas.filter(c => c.status === 'in_progress').length;
    }

    get completedCount() {
        return this._ctas.filter(c => c.status === 'completed').length;
    }

    get filterButtons() {
        return [
            { label: `All (${this.totalCount})`, value: 'all' },
            { label: `Open (${this.openCount})`, value: 'open' },
            { label: `In Progress (${this.inProgressCount})`, value: 'in_progress' },
            { label: `Completed (${this.completedCount})`, value: 'completed' },
            { label: 'Snoozed', value: 'snoozed' }
        ].map(f => ({
            ...f,
            cssClass: f.value === this._activeFilter
                ? 'c360-cta__filter-btn c360-cta__filter-btn--active'
                : 'c360-cta__filter-btn'
        }));
    }

    get showPlaybook() {
        return this._activePlaybook != null;
    }

    get activePlaybook() {
        return this._activePlaybook;
    }

    get showCreateForm() {
        return this._showCreateForm;
    }

    get ctaTypeOptions() {
        return Object.entries(CTA_TYPES).map(([key, val]) => ({
            label: val.label,
            value: key
        }));
    }

    get ctaPriorityOptions() {
        return Object.entries(CTA_PRIORITIES).map(([key, val]) => ({
            label: val.label,
            value: key
        }));
    }

    get ctaStatusOptions() {
        return [
            { label: 'Open', value: 'open' },
            { label: 'In Progress', value: 'in_progress' },
            { label: 'Snoozed', value: 'snoozed' },
            { label: 'Completed', value: 'completed' }
        ];
    }

    get assigneeOptions() {
        return CSM_NAMES.map(name => ({ label: name, value: name }));
    }

    get isCreateDisabled() {
        return !this._newCtaName || !this._newCtaName.trim();
    }

    get showEditModal() {
        return this._editingCtaId != null;
    }

    get editTagOptions() {
        return CTA_TAGS.map(tag => ({
            ...tag,
            pillClass: this._editTags.includes(tag.value)
                ? 'c360-cta__tag-pill c360-cta__tag-pill--selected'
                : 'c360-cta__tag-pill'
        }));
    }

    // ─── Event Handlers: Filters ────────────────────────────────────────────
    handleFilterClick(event) {
        this._activeFilter = event.currentTarget.dataset.filter;
    }

    // ─── Event Handlers: CTA Expand/Collapse ────────────────────────────────
    handleCtaClick(event) {
        const ctaId = event.currentTarget.dataset.id;
        if (this._expandedCtaId === ctaId) {
            this._expandedCtaId = null;
        } else {
            this._expandedCtaId = ctaId;
        }
        this._activePlaybook = null;
        this._editingCtaId = null;
        this._addingTaskCtaId = null;
    }

    // ─── Event Handlers: Task Toggle ────────────────────────────────────────
    handleTaskToggle(event) {
        event.stopPropagation();
        const taskId = event.currentTarget.dataset.taskId;
        const ctaId = event.currentTarget.dataset.ctaId;
        this.dispatchEvent(new CustomEvent('taskmutation', {
            detail: { ctaId, taskId, mutationType: 'toggle' }
        }));
    }

    // ─── Event Handlers: View Playbook ──────────────────────────────────────
    handleViewPlaybook(event) {
        event.stopPropagation();
        const ctaType = event.currentTarget.dataset.type;
        try {
            const playbook = generatePlaybook(ctaType);
            this._activePlaybook = {
                ...playbook,
                steps: playbook.steps.map(s => ({
                    ...s,
                    key: `step-${s.order}`,
                    stepClass: s.completed ? 'c360-cta__pb-step c360-cta__pb-step--done' : 'c360-cta__pb-step',
                    checkIcon: s.completed ? 'utility:check' : 'utility:radio_button'
                }))
            };
        } catch (e) {
            this._activePlaybook = null;
        }
    }

    handleClosePlaybook() {
        this._activePlaybook = null;
    }

    handlePlaybookStepToggle(event) {
        const order = parseInt(event.currentTarget.dataset.order, 10);
        if (this._activePlaybook) {
            this._activePlaybook = {
                ...this._activePlaybook,
                steps: this._activePlaybook.steps.map(s => {
                    if (s.order !== order) return s;
                    const completed = !s.completed;
                    return {
                        ...s,
                        completed,
                        stepClass: completed ? 'c360-cta__pb-step c360-cta__pb-step--done' : 'c360-cta__pb-step',
                        checkIcon: completed ? 'utility:check' : 'utility:radio_button'
                    };
                })
            };
        }
    }

    // ─── Event Handlers: Create CTA ─────────────────────────────────────────
    handleShowCreateForm() {
        this._showCreateForm = true;
    }

    handleHideCreateForm() {
        this._showCreateForm = false;
        this._resetCreateForm();
    }

    handleNewCtaNameChange(event) {
        this._newCtaName = event.detail.value;
    }

    handleNewCtaTypeChange(event) {
        this._newCtaType = event.detail.value;
    }

    handleNewCtaPriorityChange(event) {
        this._newCtaPriority = event.detail.value;
    }

    handleNewCtaDueDateChange(event) {
        this._newCtaDueDate = event.detail.value;
    }

    handleNewCtaAssigneeChange(event) {
        this._newCtaAssignee = event.detail.value;
    }

    handleCreateCta() {
        if (!this._newCtaName || !this._newCtaName.trim()) return;

        const type = this._newCtaType;
        const priority = this._newCtaPriority;
        const ctaTypeInfo = CTA_TYPES[type] || CTA_TYPES.risk;
        const ctaPriorityInfo = CTA_PRIORITIES[priority] || CTA_PRIORITIES.medium;

        const newCta = {
            id: generateId('CTA', Date.now()),
            accountId: this.accountId,
            name: this._newCtaName.trim(),
            type,
            typeLabel: ctaTypeInfo.label,
            typeColor: ctaTypeInfo.color,
            typeIcon: ctaTypeInfo.icon,
            priority,
            priorityLabel: ctaPriorityInfo.label,
            priorityColor: ctaPriorityInfo.color,
            status: 'open',
            dueDate: this._newCtaDueDate,
            assignee: this._newCtaAssignee,
            tasks: [],
            completedTasks: 0,
            totalTasks: 0,
            progress: 0,
            playbookId: generateId('PB', Date.now())
        };

        this.dispatchEvent(new CustomEvent('ctamutation', {
            detail: { type: 'add', newCta }
        }));

        this._showCreateForm = false;
        this._expandedCtaId = newCta.id;
        this._resetCreateForm();
    }

    // ─── Event Handlers: Edit CTA Modal ─────────────────────────────────────
    handleEditCta(event) {
        event.stopPropagation();
        const ctaId = event.currentTarget.dataset.id;
        const cta = this._ctas.find(c => c.id === ctaId);
        if (!cta) return;

        this._editingCtaId = ctaId;
        this._editName = cta.name;
        this._editType = cta.type;
        this._editStatus = cta.status;
        this._editPriority = cta.priority;
        this._editDueDate = cta.dueDate;
        this._editAssignee = cta.assignee;
        this._editTags = cta.tags ? [...cta.tags] : [];
    }

    handleEditNameChange(event) {
        this._editName = event.detail.value;
    }

    handleEditTypeChange(event) {
        this._editType = event.detail.value;
    }

    handleEditStatusChange(event) {
        this._editStatus = event.detail.value;
    }

    handleEditPriorityChange(event) {
        this._editPriority = event.detail.value;
    }

    handleEditDueDateChange(event) {
        this._editDueDate = event.detail.value;
    }

    handleEditAssigneeChange(event) {
        this._editAssignee = event.detail.value;
    }

    handleToggleTag(event) {
        const tagValue = event.currentTarget.dataset.value;
        if (this._editTags.includes(tagValue)) {
            this._editTags = this._editTags.filter(t => t !== tagValue);
        } else {
            this._editTags = [...this._editTags, tagValue];
        }
    }

    handleSaveEdit() {
        const ctaId = this._editingCtaId;
        if (!ctaId) return;

        const newType = this._editType;
        const newPriority = this._editPriority;
        const ctaTypeInfo = CTA_TYPES[newType] || CTA_TYPES.risk;
        const ctaPriorityInfo = CTA_PRIORITIES[newPriority] || CTA_PRIORITIES.medium;

        const updatedCtas = this._ctas.map(cta => {
            if (cta.id !== ctaId) return cta;
            return {
                ...cta,
                name: this._editName,
                type: newType,
                typeLabel: ctaTypeInfo.label,
                typeColor: ctaTypeInfo.color,
                typeIcon: ctaTypeInfo.icon,
                status: this._editStatus,
                priority: newPriority,
                priorityLabel: ctaPriorityInfo.label,
                priorityColor: ctaPriorityInfo.color,
                dueDate: this._editDueDate,
                assignee: this._editAssignee,
                tags: [...this._editTags]
            };
        });

        this.dispatchEvent(new CustomEvent('ctamutation', {
            detail: { type: 'update', ctaData: updatedCtas }
        }));

        this._editingCtaId = null;
    }

    handleCancelEdit() {
        this._editingCtaId = null;
    }

    handleModalBackdropClick() {
        this._editingCtaId = null;
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    // ─── Event Handlers: Quick Status Change ────────────────────────────────
    handleStatusChange(event) {
        event.stopPropagation();
        const ctaId = event.currentTarget.dataset.id;
        const newStatus = event.currentTarget.dataset.status;
        if (!ctaId || !newStatus) return;

        const updatedCtas = this._ctas.map(cta => {
            if (cta.id !== ctaId) return cta;
            return { ...cta, status: newStatus };
        });

        this.dispatchEvent(new CustomEvent('ctamutation', {
            detail: { type: 'update', ctaData: updatedCtas }
        }));
    }

    // ─── Event Handlers: Add Task ───────────────────────────────────────────
    handleShowAddTask(event) {
        event.stopPropagation();
        this._addingTaskCtaId = event.currentTarget.dataset.id;
        this._newTaskName = '';
    }

    handleCancelAddTask(event) {
        event.stopPropagation();
        this._addingTaskCtaId = null;
        this._newTaskName = '';
    }

    handleNewTaskNameChange(event) {
        this._newTaskName = event.detail.value;
    }

    handleAddTask(event) {
        event.stopPropagation();
        const ctaId = this._addingTaskCtaId;
        if (!ctaId || !this._newTaskName || !this._newTaskName.trim()) return;

        const dueDate = new Date();
        dueDate.setDate(dueDate.getDate() + 7);

        const cta = this._ctas.find(c => c.id === ctaId);

        const newTask = {
            id: generateId('TSK', Date.now()),
            name: this._newTaskName.trim(),
            completed: false,
            dueDate: dueDate.toISOString().split('T')[0],
            priority: 'medium',
            assignee: cta?.assignee || 'Sarah Chen',
            isOverdue: false
        };

        this.dispatchEvent(new CustomEvent('taskmutation', {
            detail: { ctaId, mutationType: 'add', taskData: newTask }
        }));

        this._addingTaskCtaId = null;
        this._newTaskName = '';
    }

    // ─── Event Handlers: Delete CTA ─────────────────────────────────────────
    handleDeleteCta(event) {
        event.stopPropagation();
        const ctaId = event.currentTarget.dataset.id;

        this.dispatchEvent(new CustomEvent('ctamutation', {
            detail: { type: 'delete', ctaId }
        }));

        if (this._expandedCtaId === ctaId) {
            this._expandedCtaId = null;
        }
    }

    // ─── Private Methods ────────────────────────────────────────────────────
    _resetCreateForm() {
        this._newCtaName = '';
        this._newCtaType = 'risk';
        this._newCtaPriority = 'medium';
        this._newCtaAssignee = 'Sarah Chen';
        const d = new Date();
        d.setDate(d.getDate() + 14);
        this._newCtaDueDate = d.toISOString().split('T')[0];
    }

    _getCardClass(cta) {
        let cls = 'c360-cta__card';
        if (cta.id === this._expandedCtaId) cls += ' c360-cta__card--expanded';
        if (cta.status === 'completed') cls += ' c360-cta__card--completed';
        return cls;
    }

    _getStatusLabel(status) {
        const labels = {
            open: 'Open',
            in_progress: 'In Progress',
            snoozed: 'Snoozed',
            completed: 'Completed'
        };
        return labels[status] || status;
    }
}