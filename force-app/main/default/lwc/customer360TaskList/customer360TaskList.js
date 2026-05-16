/**
 * @description Task List for Customer 360.
 *              Displays tasks as children of CTAs (parent-child relationship).
 *              Receives flat task list from parent via @api; dispatches mutation events upward.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { formatDate, generateId } from 'c/customer360Utils';
import { CSM_NAMES } from 'c/customer360Constants';

export default class Customer360TaskList extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    @api
    get tasks() {
        return this._tasks;
    }
    set tasks(value) {
        this._tasks = value ? [...value] : [];
        this._isLoaded = true;
    }

    @api
    get ctaOptions() {
        return this._ctaOptions;
    }
    set ctaOptions(value) {
        this._ctaOptions = value ? [...value] : [];
    }

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _tasks = [];
    @track _ctaOptions = [];
    @track _activeFilter = 'all';
    @track _selectedCtaFilter = 'all';
    @track _showAddForm = false;
    @track _newTaskName = '';
    @track _newTaskPriority = 'medium';
    @track _newTaskDueDate = '';
    @track _newTaskAssignee = 'Sarah Chen';
    @track _newTaskCtaId = '';
    @track _editingTaskId = null;
    @track _editingTaskAssignee = '';
    @track _editFullTaskId = null;
    @track _editTaskName = '';
    @track _editTaskPriority = '';
    @track _editTaskAssignee = '';
    @track _editTaskDueDate = '';
    @track _editTaskCtaId = '';
    @track _editTaskOrigCtaId = '';
    _isLoaded = false;

    // ─── Getters ──────────────────────────────────────────────────────────────
    get filteredTasks() {
        let tasks = this._tasks;

        // Filter by CTA
        if (this._selectedCtaFilter !== 'all') {
            tasks = tasks.filter(t => t.ctaId === this._selectedCtaFilter);
        }

        // Filter by status
        if (this._activeFilter === 'pending') {
            tasks = tasks.filter(t => !t.completed);
        } else if (this._activeFilter === 'completed') {
            tasks = tasks.filter(t => t.completed);
        } else if (this._activeFilter === 'overdue') {
            tasks = tasks.filter(t => !t.completed && new Date(t.dueDate) < new Date());
        }

        return tasks.map(t => ({
            ...t,
            assignee: t.assignee || 'Sarah Chen',
            formattedDueDate: formatDate(t.dueDate, 'short'),
            taskClass: t.completed ? 'c360-task__item c360-task__item--done' : 'c360-task__item',
            checkIcon: t.completed ? 'utility:check' : 'utility:radio_button',
            priorityClass: `c360-task__priority c360-task__priority--${t.priority}`,
            dueDateClass: !t.completed && new Date(t.dueDate) < new Date()
                ? 'c360-task__date c360-task__date--overdue'
                : 'c360-task__date',
            isEditingAssignee: t.id === this._editingTaskId,
            ctaLabel: t.ctaName || 'Unassigned',
            ctaBadgeStyle: t.ctaTypeColor ? `background-color: ${t.ctaTypeColor}` : 'background-color: #6B7280',
            ctaTypeDisplay: t.ctaTypeLabel || 'CTA'
        }));
    }

    get hasTasks() {
        return this.filteredTasks.length > 0;
    }

    get showEmpty() {
        return this._isLoaded && !this.hasTasks;
    }

    get totalCount() {
        return this._tasks.length;
    }

    get pendingCount() {
        return this._tasks.filter(t => !t.completed).length;
    }

    get completedCount() {
        return this._tasks.filter(t => t.completed).length;
    }

    get overdueCount() {
        return this._tasks.filter(t => !t.completed && new Date(t.dueDate) < new Date()).length;
    }

    get filterButtons() {
        return [
            { label: `All (${this.totalCount})`, value: 'all' },
            { label: `Pending (${this.pendingCount})`, value: 'pending' },
            { label: `Overdue (${this.overdueCount})`, value: 'overdue' },
            { label: `Done (${this.completedCount})`, value: 'completed' }
        ].map(f => ({
            ...f,
            cssClass: f.value === this._activeFilter
                ? 'c360-task__filter-btn c360-task__filter-btn--active'
                : 'c360-task__filter-btn'
        }));
    }

    get showAddForm() {
        return this._showAddForm;
    }

    get priorityOptions() {
        return [
            { label: 'High', value: 'high' },
            { label: 'Medium', value: 'medium' },
            { label: 'Low', value: 'low' }
        ];
    }

    get assigneeOptions() {
        return CSM_NAMES.map(name => ({ label: name, value: name }));
    }

    get ctaFilterOptions() {
        const opts = [{ label: 'All CTAs', value: 'all' }];
        (this._ctaOptions || []).forEach(c => opts.push(c));
        return opts;
    }

    get ctaPickerOptions() {
        return this._ctaOptions || [];
    }

    get isAddDisabled() {
        return !this._newTaskName || !this._newTaskDueDate || !this._newTaskCtaId;
    }

    get hasCtaFilter() {
        return this._selectedCtaFilter !== 'all';
    }

    get showEditModal() {
        return this._editFullTaskId != null;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleFilterClick(event) {
        this._activeFilter = event.currentTarget.dataset.filter;
    }

    handleCtaFilterChange(event) {
        this._selectedCtaFilter = event.detail.value;
    }

    handleClearCtaFilter() {
        this._selectedCtaFilter = 'all';
    }

    handleToggleTask(event) {
        const taskId = event.currentTarget.dataset.id;
        const task = this._tasks.find(t => t.id === taskId);
        if (!task) return;

        this.dispatchEvent(new CustomEvent('taskmutation', {
            detail: { ctaId: task.ctaId, taskId, mutationType: 'toggle' }
        }));
    }

    handleShowAdd() {
        this._showAddForm = !this._showAddForm;
        this._newTaskName = '';
        this._newTaskPriority = 'medium';
        this._newTaskDueDate = '';
        this._newTaskAssignee = 'Sarah Chen';
        // Default to first CTA if available
        this._newTaskCtaId = (this._ctaOptions && this._ctaOptions.length > 0)
            ? this._ctaOptions[0].value : '';
    }

    handleTaskNameChange(event) {
        this._newTaskName = event.target.value;
    }

    handleTaskPriorityChange(event) {
        this._newTaskPriority = event.detail.value;
    }

    handleTaskDueDateChange(event) {
        this._newTaskDueDate = event.target.value;
    }

    handleTaskAssigneeChange(event) {
        this._newTaskAssignee = event.detail.value;
    }

    handleTaskCtaChange(event) {
        this._newTaskCtaId = event.detail.value;
    }

    handleAddTask() {
        if (!this._newTaskName || !this._newTaskDueDate || !this._newTaskCtaId) return;

        const newTask = {
            id: generateId('TASK', Date.now()),
            name: this._newTaskName,
            completed: false,
            dueDate: this._newTaskDueDate,
            priority: this._newTaskPriority,
            assignee: this._newTaskAssignee,
            isOverdue: new Date(this._newTaskDueDate) < new Date()
        };

        this.dispatchEvent(new CustomEvent('taskmutation', {
            detail: {
                ctaId: this._newTaskCtaId,
                mutationType: 'add',
                taskData: newTask
            }
        }));

        this._showAddForm = false;
        this._newTaskName = '';
        this._newTaskPriority = 'medium';
        this._newTaskDueDate = '';
        this._newTaskAssignee = 'Sarah Chen';
    }

    handleEditTask(event) {
        const taskId = event.currentTarget.dataset.id;
        const task = this._tasks.find(t => t.id === taskId);
        if (!task) return;

        this._editFullTaskId = taskId;
        this._editTaskName = task.name;
        this._editTaskPriority = task.priority || 'medium';
        this._editTaskAssignee = task.assignee || 'Sarah Chen';
        this._editTaskDueDate = task.dueDate || '';
        this._editTaskCtaId = task.ctaId || '';
        this._editTaskOrigCtaId = task.ctaId || '';
        // Close any inline assignee edit
        this._editingTaskId = null;
    }

    handleEditTaskCtaChange(event) {
        this._editTaskCtaId = event.detail.value;
    }

    handleModalBackdropClick() {
        this._editFullTaskId = null;
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    handleEditTaskNameChange(event) {
        this._editTaskName = event.target.value;
    }

    handleEditTaskPriorityChange(event) {
        this._editTaskPriority = event.detail.value;
    }

    handleEditTaskAssigneeChange(event) {
        this._editTaskAssignee = event.detail.value;
    }

    handleEditTaskDueDateChange(event) {
        this._editTaskDueDate = event.target.value;
    }

    handleSaveEditTask() {
        const taskId = this._editFullTaskId;
        const task = this._tasks.find(t => t.id === taskId);
        if (!taskId || !task) return;

        const ctaChanged = this._editTaskCtaId && this._editTaskCtaId !== this._editTaskOrigCtaId;

        if (ctaChanged) {
            // Reassign: move task from old CTA to new CTA
            this.dispatchEvent(new CustomEvent('taskmutation', {
                detail: {
                    ctaId: this._editTaskOrigCtaId,
                    newCtaId: this._editTaskCtaId,
                    taskId,
                    mutationType: 'reassign',
                    taskData: {
                        name: this._editTaskName,
                        priority: this._editTaskPriority,
                        assignee: this._editTaskAssignee,
                        dueDate: this._editTaskDueDate,
                        isOverdue: !task.completed && new Date(this._editTaskDueDate) < new Date()
                    }
                }
            }));
        } else {
            this.dispatchEvent(new CustomEvent('taskmutation', {
                detail: {
                    ctaId: task.ctaId,
                    taskId,
                    mutationType: 'update',
                    taskData: {
                        name: this._editTaskName,
                        priority: this._editTaskPriority,
                        assignee: this._editTaskAssignee,
                        dueDate: this._editTaskDueDate,
                        isOverdue: !task.completed && new Date(this._editTaskDueDate) < new Date()
                    }
                }
            }));
        }

        this._editFullTaskId = null;
    }

    handleCancelEditTask() {
        this._editFullTaskId = null;
    }

    handleDeleteTask(event) {
        const taskId = event.currentTarget.dataset.id;
        const task = this._tasks.find(t => t.id === taskId);
        if (!task) return;

        this.dispatchEvent(new CustomEvent('taskmutation', {
            detail: { ctaId: task.ctaId, taskId, mutationType: 'delete' }
        }));
    }

    handleAssigneeClick(event) {
        const taskId = event.currentTarget.dataset.id;
        const task = this._tasks.find(t => t.id === taskId);
        this._editingTaskId = taskId;
        this._editingTaskAssignee = task?.assignee || 'Sarah Chen';
    }

    handleEditAssigneeChange(event) {
        this._editingTaskAssignee = event.detail.value;
        const taskId = this._editingTaskId;
        const task = this._tasks.find(t => t.id === taskId);
        if (taskId && task) {
            this.dispatchEvent(new CustomEvent('taskmutation', {
                detail: {
                    ctaId: task.ctaId,
                    taskId,
                    mutationType: 'update',
                    taskData: { assignee: this._editingTaskAssignee }
                }
            }));
        }
        this._editingTaskId = null;
    }

    handleCancelEditAssignee() {
        this._editingTaskId = null;
    }
}