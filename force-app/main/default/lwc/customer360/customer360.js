/**
 * @description Customer 360 - Main container component.
 *              Manages two-view architecture (Portfolio Dashboard + Customer Detail),
 *              centralized state management, and mock data initialization.
 * @author Yousef A
 * @date 2026-03-05
 * @jira BIZ-80363
 */

import { LightningElement, track } from 'lwc';
import {
    generatePortfolio, generateAlerts, generateHealthScore,
    generateHealthHistory, generateBenchmarks, generateCtas
} from 'c/customer360MockData';
import { generateId } from 'c/customer360Utils';
import { CTA_TYPES, CTA_PRIORITIES } from 'c/customer360Constants';

const STATE_STORAGE_KEY = 'c360_navState';

export default class Customer360 extends LightningElement {

    // ─── Private Properties ──────────────────────────────────────────────────
    @track _currentView = 'dashboard'; // 'dashboard' | 'detail' | 'about'
    @track _selectedAccountId = null;
    @track _portfolioData = [];
    @track _alerts = [];
    @track _activeTab = 'overview';
    @track _healthData = null;
    @track _healthHistory = [];
    @track _benchmarks = [];
    @track _currentUser = {
        name: 'Sarah Chen',
        role: 'Client Success Manager'
    };
    @track _error = null;
    @track _isLoaded = false;
    @track _showLogActivityModal = false;
    @track _showCreateCtaModal = false;
    @track _showNotificationPanel = false;
    @track _ctaData = [];

    // ─── Lifecycle Hooks ─────────────────────────────────────────────────────

    connectedCallback() {
        try {
            this._initializeData();
            const hasRestoredAccount = this._restoreState();
            if (hasRestoredAccount && this._selectedAccountId) {
                this._loadAccountDetail(this._selectedAccountId);
            }
            this._isLoaded = true;
        } catch (e) {
            this._error = e.message || 'Unknown error initializing data';
            console.error('[Customer360] Init error:', e);
        }
    }

    // ─── Getters: View State ─────────────────────────────────────────────────

    get hasError() {
        return !!this._error;
    }

    get errorMessage() {
        return this._error;
    }

    get isDashboardView() {
        return this._currentView === 'dashboard' && this._isLoaded && !this._error;
    }

    get isDetailView() {
        return this._currentView === 'detail';
    }

    get isAboutView() {
        return this._currentView === 'about';
    }

    get userName() {
        return this._currentUser.name;
    }

    get notificationCount() {
        return this._alerts.filter(a => !a.dismissed).length;
    }

    get portfolioData() {
        return this._portfolioData;
    }

    get alerts() {
        return this._alerts;
    }

    get selectedAccount() {
        if (!this._selectedAccountId) return null;
        return this._portfolioData.find(a => a.id === this._selectedAccountId) || null;
    }

    get selectedAccountId() {
        return this._selectedAccountId;
    }

    get activeTab() {
        return this._activeTab;
    }

    get healthData() {
        return this._healthData;
    }

    get healthHistory() {
        return this._healthHistory;
    }

    get benchmarks() {
        return this._benchmarks;
    }

    get currentHealthScore() {
        return this._healthData?.overall || 0;
    }

    get ctaData() {
        return this._ctaData;
    }

    get flatTaskList() {
        if (!this._ctaData || !this._ctaData.length) return [];
        const tasks = [];
        this._ctaData.forEach(cta => {
            (cta.tasks || []).forEach(task => {
                tasks.push({
                    ...task,
                    ctaId: cta.id,
                    ctaName: cta.name,
                    ctaType: cta.type,
                    ctaTypeLabel: cta.typeLabel,
                    ctaTypeColor: cta.typeColor
                });
            });
        });
        return tasks;
    }

    get ctaOptionsForTaskList() {
        return this._ctaData.map(cta => ({ label: cta.name, value: cta.id }));
    }

    // ─── Getters: Tab Visibility ─────────────────────────────────────────────

    get isOverviewTab() {
        return this._activeTab === 'overview';
    }

    get isHealthTab() {
        return this._activeTab === 'health';
    }

    get isSubscriptionsTab() {
        return this._activeTab === 'subscriptions';
    }

    get isUsageTab() {
        return this._activeTab === 'usage';
    }

    get isSupportTab() {
        return this._activeTab === 'support';
    }

    get isInvoicesTab() {
        return this._activeTab === 'invoices';
    }

    get isTimelineTab() {
        return this._activeTab === 'timeline';
    }

    get isCtasTab() {
        return this._activeTab === 'ctas';
    }

    get isSuccessPlanTab() {
        return this._activeTab === 'successplan';
    }

    // ─── Getters: Modal State ─────────────────────────────────────────────────

    get showLogActivityModal() {
        return this._showLogActivityModal;
    }

    get showCreateCtaModal() {
        return this._showCreateCtaModal;
    }

    get selectedAccountName() {
        return this.selectedAccount?.name || '';
    }

    get showNotificationPanel() {
        return this._showNotificationPanel;
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────

    handleNavigate(event) {
        const { view } = event.detail;
        if (view === 'dashboard') {
            this._currentView = 'dashboard';
            this._selectedAccountId = null;
            this._activeTab = 'overview';
            this._ctaData = [];
        }
        this._saveState();
    }

    handleAccountSelect(event) {
        const { accountId } = event.detail;
        if (accountId) {
            this._selectedAccountId = accountId;
            this._currentView = 'detail';
            this._activeTab = 'overview';
            this._loadAccountDetail(accountId);
        }
        this._saveState();
    }

    handleTabChange(event) {
        this._activeTab = event.detail.tab;
        this._saveState();
    }

    handleAlertDismiss(event) {
        const { alertId } = event.detail;
        this._alerts = this._alerts.map(a =>
            a.id === alertId ? { ...a, dismissed: true } : a
        );
    }

    handleAlertClick(event) {
        const { accountId } = event.detail;
        if (accountId) {
            this._selectedAccountId = accountId;
            this._currentView = 'detail';
            this._activeTab = 'overview';
            this._loadAccountDetail(accountId);
        }
        this._saveState();
    }

    handleInfoClick() {
        this._currentView = 'about';
        this._saveState();
    }

    handleNotificationClick() {
        this._showNotificationPanel = !this._showNotificationPanel;
    }

    handleNotificationPanelClose() {
        this._showNotificationPanel = false;
    }

    handleNotificationAlertClick(event) {
        this._showNotificationPanel = false;
        this.handleAlertClick(event);
    }

    handleNotificationAlertDismiss(event) {
        this.handleAlertDismiss(event);
    }

    handleLogActivity() {
        this._showLogActivityModal = true;
    }

    handleCreateCta() {
        this._showCreateCtaModal = true;
    }

    handleModalClose() {
        this._showLogActivityModal = false;
        this._showCreateCtaModal = false;
    }

    handleActivityLogged() {
        this._showLogActivityModal = false;
    }

    handleCtaCreated(event) {
        this._showCreateCtaModal = false;
        if (event.detail) {
            const newCta = this._buildCtaFromModalDetail(event.detail);
            this._ctaData = [newCta, ...this._ctaData];
        }
    }

    handleCtaMutation(event) {
        const { type, ctaId, ctaData: updatedCtas, newCta } = event.detail;
        switch (type) {
            case 'update':
                this._ctaData = this._cascadeCtaCompletion(updatedCtas);
                break;
            case 'add':
                this._ctaData = [newCta, ...this._ctaData];
                break;
            case 'delete':
                this._ctaData = this._ctaData.filter(c => c.id !== ctaId);
                break;
            default:
                break;
        }
    }

    handleTaskMutation(event) {
        const { ctaId, newCtaId, taskId, mutationType, taskData } = event.detail;

        // Reassign: move task from one CTA to another
        if (mutationType === 'reassign' && newCtaId) {
            let movedTask;
            this._ctaData = this._ctaData.map(cta => {
                if (cta.id === ctaId) {
                    // Remove from old CTA, capture the task
                    const task = cta.tasks.find(t => t.id === taskId);
                    if (task) movedTask = { ...task, ...taskData };
                    const tasks = cta.tasks.filter(t => t.id !== taskId);
                    const completedTasks = tasks.filter(t => t.completed).length;
                    return { ...cta, tasks, completedTasks, totalTasks: tasks.length,
                        progress: tasks.length > 0 ? Math.round((completedTasks / tasks.length) * 100) : 0 };
                }
                if (cta.id === newCtaId && movedTask) {
                    // Add to new CTA
                    const tasks = [...cta.tasks, movedTask];
                    const completedTasks = tasks.filter(t => t.completed).length;
                    return { ...cta, tasks, completedTasks, totalTasks: tasks.length,
                        progress: tasks.length > 0 ? Math.round((completedTasks / tasks.length) * 100) : 0 };
                }
                return cta;
            });
            // Handle case where new CTA comes before old CTA in the array
            if (movedTask) {
                this._ctaData = this._ctaData.map(cta => {
                    if (cta.id === newCtaId && !cta.tasks.find(t => t.id === taskId)) {
                        const tasks = [...cta.tasks, movedTask];
                        const completedTasks = tasks.filter(t => t.completed).length;
                        return { ...cta, tasks, completedTasks, totalTasks: tasks.length,
                            progress: tasks.length > 0 ? Math.round((completedTasks / tasks.length) * 100) : 0 };
                    }
                    return cta;
                });
            }
            return;
        }

        this._ctaData = this._ctaData.map(cta => {
            if (cta.id !== ctaId) return cta;
            let tasks;
            switch (mutationType) {
                case 'toggle':
                    tasks = cta.tasks.map(t =>
                        t.id === taskId ? { ...t, completed: !t.completed } : t
                    );
                    break;
                case 'add':
                    tasks = [...cta.tasks, taskData];
                    break;
                case 'delete':
                    tasks = cta.tasks.filter(t => t.id !== taskId);
                    break;
                case 'update':
                    tasks = cta.tasks.map(t =>
                        t.id === taskId ? { ...t, ...taskData } : t
                    );
                    break;
                default:
                    tasks = cta.tasks;
            }
            const completedTasks = tasks.filter(t => t.completed).length;
            return {
                ...cta,
                tasks,
                completedTasks,
                totalTasks: tasks.length,
                progress: tasks.length > 0 ? Math.round((completedTasks / tasks.length) * 100) : 0
            };
        });
    }

    handleHealthOverride(event) {
        const { score, comment } = event.detail;
        if (this._healthData) {
            this._healthData = {
                ...this._healthData,
                overrideScore: score,
                overrideComment: comment,
                overrideDate: new Date().toISOString(),
                overrideBy: this._currentUser.name
            };
        }
    }

    // ─── Private Methods ─────────────────────────────────────────────────────

    _initializeData() {
        this._portfolioData = generatePortfolio(this._currentUser.name);
        this._alerts = generateAlerts(this._portfolioData);
    }

    _loadAccountDetail(accountId) {
        this._healthData = generateHealthScore(accountId);
        this._healthHistory = generateHealthHistory(accountId);
        this._benchmarks = generateBenchmarks(accountId);
        this._ctaData = generateCtas(accountId);
    }

    /**
     * When a CTA is transitioned to 'completed', mark all its child tasks as completed.
     * When a CTA is reopened from 'completed', mark all its child tasks as not completed.
     */
    _cascadeCtaCompletion(updatedCtas) {
        const previousMap = new Map(this._ctaData.map(c => [c.id, c.status]));
        return updatedCtas.map(cta => {
            const prevStatus = previousMap.get(cta.id);
            // CTA just completed — mark all tasks done
            if (cta.status === 'completed' && prevStatus !== 'completed') {
                const tasks = (cta.tasks || []).map(t => ({ ...t, completed: true }));
                return {
                    ...cta,
                    tasks,
                    completedTasks: tasks.length,
                    progress: 100
                };
            }
            // CTA reopened from completed — mark all tasks not done
            if (prevStatus === 'completed' && cta.status !== 'completed') {
                const tasks = (cta.tasks || []).map(t => ({ ...t, completed: false }));
                return {
                    ...cta,
                    tasks,
                    completedTasks: 0,
                    progress: 0
                };
            }
            return cta;
        });
    }

    _saveState() {
        try {
            const state = {
                currentView: this._currentView,
                selectedAccountId: this._selectedAccountId,
                activeTab: this._activeTab
            };
            sessionStorage.setItem(STATE_STORAGE_KEY, JSON.stringify(state));
        } catch (e) {
            // sessionStorage may be unavailable in some Salesforce contexts
            console.warn('[Customer360] Could not save state:', e);
        }
    }

    _restoreState() {
        try {
            const saved = sessionStorage.getItem(STATE_STORAGE_KEY);
            if (!saved) return false;
            const state = JSON.parse(saved);
            if (state.currentView) this._currentView = state.currentView;
            if (state.selectedAccountId) this._selectedAccountId = state.selectedAccountId;
            if (state.activeTab) this._activeTab = state.activeTab;
            return !!state.selectedAccountId;
        } catch (e) {
            console.warn('[Customer360] Could not restore state:', e);
            return false;
        }
    }

    _buildCtaFromModalDetail(detail) {
        const type = (detail.ctaType || 'risk').toLowerCase();
        const ctaTypeInfo = CTA_TYPES[type] || CTA_TYPES.risk;
        const priorityKey = (detail.priority || 'Normal').toLowerCase();
        const priorityMap = { high: 'high', normal: 'medium', low: 'low' };
        const priority = priorityMap[priorityKey] || 'medium';
        const ctaPriorityInfo = CTA_PRIORITIES[priority] || CTA_PRIORITIES.medium;

        return {
            id: detail.taskId || generateId('CTA', Date.now()),
            accountId: this._selectedAccountId,
            name: `${ctaTypeInfo.label}: ${detail.description || 'New CTA'}`.substring(0, 80),
            type,
            typeLabel: ctaTypeInfo.label,
            typeColor: ctaTypeInfo.color,
            typeIcon: ctaTypeInfo.icon,
            priority,
            priorityLabel: ctaPriorityInfo.label,
            priorityColor: ctaPriorityInfo.color,
            status: 'open',
            dueDate: detail.dueDate || new Date().toISOString().split('T')[0],
            assignee: 'Sarah Chen',
            tasks: [],
            completedTasks: 0,
            totalTasks: 0,
            progress: 0,
            playbookId: generateId('PB', Date.now())
        };
    }
}