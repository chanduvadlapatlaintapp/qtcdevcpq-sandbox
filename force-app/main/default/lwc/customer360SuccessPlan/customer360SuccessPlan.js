/**
 * @description Success Plan for Customer 360.
 *              Displays objectives with progress tracking and milestones.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { generateSuccessPlan } from 'c/customer360MockData';
import { formatDate } from 'c/customer360Utils';

export default class Customer360SuccessPlan extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _plan = null;
    _isLoaded = false;

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    // ─── Getters ──────────────────────────────────────────────────────────────
    get hasPlan() {
        return this._plan != null;
    }

    get showEmpty() {
        return this._isLoaded && !this.hasPlan;
    }

    get planName() {
        return this._plan?.name || '';
    }

    get planStatus() {
        return this._plan?.status || '';
    }

    get totalObjectives() {
        return this._plan?.totalObjectives || 0;
    }

    get onTrackCount() {
        return this._plan?.onTrack || 0;
    }

    get atRiskCount() {
        return this._plan?.atRisk || 0;
    }

    get overallProgress() {
        if (!this._plan || !this._plan.objectives.length) return 0;
        const total = this._plan.objectives.reduce((sum, obj) => {
            const progress = Math.min((obj.current / obj.target) * 100, 100);
            return sum + progress;
        }, 0);
        return Math.round(total / this._plan.objectives.length);
    }

    get overallProgressWidth() {
        return `width: ${this.overallProgress}%`;
    }

    get overallProgressClass() {
        const p = this.overallProgress;
        if (p >= 70) return 'c360-sp__progress-fill c360-sp__progress-fill--good';
        if (p >= 40) return 'c360-sp__progress-fill c360-sp__progress-fill--fair';
        return 'c360-sp__progress-fill c360-sp__progress-fill--low';
    }

    get objectives() {
        if (!this._plan) return [];
        return this._plan.objectives.map(obj => {
            const progress = Math.min(Math.round((obj.current / obj.target) * 100), 100);
            const completedMilestones = obj.milestones.filter(m => m.completed).length;
            return {
                ...obj,
                key: obj.id,
                progress,
                progressWidth: `width: ${progress}%`,
                progressClass: progress >= 70 ? 'c360-sp__obj-progress-fill c360-sp__obj-progress-fill--good' :
                              progress >= 40 ? 'c360-sp__obj-progress-fill c360-sp__obj-progress-fill--fair' :
                              'c360-sp__obj-progress-fill c360-sp__obj-progress-fill--low',
                progressLabel: `${obj.current}${obj.unit === '%' ? '%' : ''} / ${obj.target}${obj.unit === '%' ? '%' : ''}`,
                formattedDueDate: formatDate(obj.dueDate, 'short'),
                statusClass: `c360-sp__obj-status c360-sp__obj-status--${obj.status}`,
                statusLabel: obj.status === 'in_progress' ? 'In Progress' :
                            obj.status === 'on_track' ? 'On Track' :
                            obj.status === 'at_risk' ? 'At Risk' : obj.status,
                completedMilestones,
                totalMilestones: obj.milestones.length,
                milestoneLabel: `${completedMilestones}/${obj.milestones.length} milestones`,
                enrichedMilestones: obj.milestones.map((m, idx) => ({
                    ...m,
                    key: `${obj.id}-ms-${idx}`,
                    objectiveId: obj.id,
                    milestoneIndex: String(idx),
                    formattedDate: formatDate(m.date, 'short'),
                    msClass: m.completed ? 'c360-sp__ms c360-sp__ms--done c360-sp__ms--clickable' : 'c360-sp__ms c360-sp__ms--clickable',
                    icon: m.completed ? 'utility:check' : 'utility:radio_button'
                }))
            };
        });
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────

    /**
     * @description Handles milestone toggle clicks. Flips the completed state of the milestone
     *              and recalculates objective progress.
     * @param {Event} event - click event with data-objective-id and data-milestone-index
     */
    handleMilestoneToggle(event) {
        const objectiveId = event.currentTarget.dataset.objectiveId;
        const milestoneIndex = parseInt(event.currentTarget.dataset.milestoneIndex, 10);

        if (!this._plan || !this._plan.objectives) return;

        // Deep clone the plan to trigger reactive update
        const updatedPlan = JSON.parse(JSON.stringify(this._plan));
        const objective = updatedPlan.objectives.find(o => o.id === objectiveId);
        if (!objective || !objective.milestones[milestoneIndex]) return;

        // Toggle completed state
        objective.milestones[milestoneIndex].completed = !objective.milestones[milestoneIndex].completed;

        // Recalculate objective current value based on completed milestones
        const completedCount = objective.milestones.filter(m => m.completed).length;
        const totalMilestones = objective.milestones.length;
        if (objective.unit === '%') {
            objective.current = Math.round((completedCount / totalMilestones) * objective.target);
        }

        // Recalculate plan-level metrics
        const onTrack = updatedPlan.objectives.filter(o => {
            const progress = Math.min((o.current / o.target) * 100, 100);
            return progress >= 50;
        }).length;
        updatedPlan.onTrack = onTrack;
        updatedPlan.atRisk = updatedPlan.objectives.length - onTrack;

        this._plan = updatedPlan;
    }

    // ─── Private Methods ──────────────────────────────────────────────────────
    _loadData() {
        try {
            this._plan = generateSuccessPlan(this.accountId);
        } catch (e) {
            this._plan = null;
        }
        this._isLoaded = true;
    }
}