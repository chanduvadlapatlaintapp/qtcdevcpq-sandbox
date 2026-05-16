/**
 * @description Usage & Adoption tab for Customer 360.
 *              3-level hierarchy matching op4i schema:
 *                Level 1: Account Usage Stat (overview with KPIs, rating, channels, personas)
 *                Level 2: Client Site Usage Stat (site config, platform metrics, users grid)
 *                Level 3: User Usage Stat (per-user detail with login bars, persona pills)
 *              Drill-down: account → clientSite → user.
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
import { LightningElement, api, track } from 'lwc';
import { generateAccountUsage } from 'c/customer360MockData';
import { SOURCE_BADGES } from 'c/customer360Constants';

export default class Customer360Usage extends LightningElement {

    // ─── Public API ───────────────────────────────────────────────────────────
    @api accountId;

    // ─── Private Properties ───────────────────────────────────────────────────
    @track _usageData = null;
    @track _view = 'account'; // account | clientSite | user
    @track _selectedSiteId = null;
    @track _selectedUserId = null;
    isLoading = true;
    errorMessage = '';
    _isMockData = false;

    // ─── Lifecycle Hooks ──────────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    // ─── View State Getters ─────────────────────────────────────────────────
    get isAccountView() { return this._view === 'account'; }
    get isClientSiteView() { return this._view === 'clientSite'; }
    get isUserView() { return this._view === 'user'; }
    get hasData() { return this._usageData != null; }
    get showEmpty() { return !this.isLoading && !this.hasData && !this.errorMessage; }
    get isMockData() { return this._isMockData; }
    get sourceBadge() { return SOURCE_BADGES.ianlite; }

    // ─── Account-Level Getters ──────────────────────────────────────────────
    get licensed() { return this._usageData ? this._usageData.licensed.toLocaleString() : '0'; }
    get enabled() { return this._usageData ? this._usageData.enabled.toLocaleString() : '0'; }
    get activeUsers() { return this._usageData ? this._usageData.activeCapacity.toLocaleString() : '0'; }
    get loginPct() { return this._usageData ? this._usageData.loginPct + '%' : '0%'; }
    get activityPct() { return this._usageData ? this._usageData.activityPct + '%' : '0%'; }

    get ratingScore() { return this._usageData?.usageRating?.score || 0; }
    get ratingTier() { return this._usageData?.usageRating?.tier || 'N/A'; }
    get ratingColor() { return this._usageData?.usageRating?.color || '#94a3b8'; }
    get ratingBadgeStyle() {
        return `background: ${this.ratingColor}15; color: ${this.ratingColor}; font-weight: 700; padding: 4px 12px; border-radius: 20px; font-size: 12px;`;
    }

    get ratingFactors() {
        if (!this._usageData?.ratingFactors) return [];
        return Object.values(this._usageData.ratingFactors).map(f => ({
            ...f,
            weightPct: Math.round(f.weight * 100) + '%',
            barStyle: `width: ${Math.min(f.value, 100)}%; background: ${f.value >= 70 ? '#10b981' : (f.value >= 40 ? '#f59e0b' : '#ef4444')}`
        }));
    }

    get channelLogins() {
        return this._usageData?.loginsByChannel || [];
    }

    get personaAdoption() {
        return (this._usageData?.personaAdoption || []).map(p => ({
            ...p,
            barStyle: `width: ${Math.min(p.pct, 100)}%; background: ${p.pct >= 70 ? '#10b981' : (p.pct >= 40 ? '#f59e0b' : '#ef4444')}`,
            pctLabel: p.pct + '%'
        }));
    }

    get clientSiteList() {
        if (!this._usageData?.clientSites) return [];
        return this._usageData.clientSites.map(site => ({
            ...site,
            loginPctLabel: site.loginPct + '%',
            userCountLabel: site.totalUsers + ' users',
            enabledLabel: site.enabled + '/' + site.licensed + ' enabled'
        }));
    }

    // ─── Breadcrumb ─────────────────────────────────────────────────────────
    get breadcrumbs() {
        const crumbs = [{ label: 'Account Usage', view: 'account', isCurrent: this._view === 'account' }];
        if (this._view !== 'account') {
            const site = this._selectedSiteObj;
            crumbs.push({ label: site?.siteUrl || 'Client Site', view: 'clientSite', isCurrent: this._view === 'clientSite' });
        }
        if (this._view === 'user') {
            const user = this._selectedUserObj;
            crumbs.push({ label: user?.name || 'User', view: 'user', isCurrent: true });
        }
        return crumbs;
    }

    get showBreadcrumbs() {
        return this._view !== 'account';
    }

    // ─── Client Site View Getters ───────────────────────────────────────────
    get _selectedSiteObj() {
        if (!this._selectedSiteId || !this._usageData?.clientSites) return null;
        return this._usageData.clientSites.find(s => s.id === this._selectedSiteId) || null;
    }

    get siteDetail() {
        const site = this._selectedSiteObj;
        if (!site) return null;

        const configPills = [];
        if (site.config) {
            if (site.config.isDealCloud === 'Yes') configPills.push({ label: 'DealCloud', isGreen: true });
            if (site.config.isOnePlace === 'Yes') configPills.push({ label: 'OnePlace', isGreen: true });
            configPills.push({ label: site.config.twoFactorAuthentication === 'Yes' ? '2FA Enabled' : '2FA Disabled', isGreen: site.config.twoFactorAuthentication === 'Yes' });
            if (site.config.identityProviderName) configPills.push({ label: 'SSO: ' + site.config.identityProviderName, isGreen: true });
            configPills.push({ label: `Timeout: ${site.config.sessionTimeout}m`, isGreen: true });
            if (site.config.isSandbox === 'Yes') configPills.push({ label: 'Sandbox', isGreen: false });
            if (site.config.isDemo === 'Yes') configPills.push({ label: 'Demo', isGreen: false });
            if (site.config.apiAccess === 'Yes') configPills.push({ label: 'API Access', isGreen: true });
            if (site.config.gemstoneEnabled === 'Yes') configPills.push({ label: 'Gemstone', isGreen: true });
            if (site.config.dispatchEnabled === 'Yes') configPills.push({ label: 'Dispatch', isGreen: true });
            if (site.config.allowRelationshipIntelligence === 'Yes') configPills.push({ label: 'Rel. Intelligence', isGreen: true });
        }

        const pm = site.platformMetrics || {};
        const metrics = [
            { label: 'Entries', value: (pm.totalEntries || 0).toLocaleString() },
            { label: 'Fields', value: (pm.totalFields || 0).toLocaleString() },
            { label: 'Lists', value: (pm.totalLists || 0).toLocaleString() },
            { label: 'Reports', value: (pm.totalReports || 0).toLocaleString() },
            { label: 'Views', value: (pm.totalViews || 0).toLocaleString() },
            { label: 'Dashboards', value: (pm.totalDashboards || 0).toLocaleString() },
            { label: 'Workflows', value: (pm.totalWorkflows || 0).toLocaleString() },
            { label: 'Automations', value: (pm.totalAutomation || 0).toLocaleString() }
        ];

        const channels = (site.channels ? Object.entries(site.channels) : []).map(([ch, data]) => ({
            channel: ch,
            distinct: data.distinct,
            total: data.total
        }));

        const personas = (site.personaAdoption || []).map(p => ({
            ...p,
            barStyle: `width: ${Math.min(p.pct, 100)}%; background: ${p.pct >= 70 ? '#10b981' : (p.pct >= 40 ? '#f59e0b' : '#ef4444')}`,
            pctLabel: p.pct + '%'
        }));

        return {
            ...site,
            loginPctLabel: site.loginPct + '%',
            activityPctLabel: site.activityPct + '%',
            licenseCapacityLabel: (site.licenseCapacity || 0) + '%',
            configPills,
            platformMetrics: metrics,
            channelData: channels,
            personaData: personas,
            usersDisplay: site.users.map(u => ({
                ...u,
                loginTotal: (u.portalLoginsL4W || 0) + (u.excelLoginsL4W || 0) + (u.mobileLoginsL4W || 0),
                statusLabel: u.activeLogins === 'Yes' ? 'Active' : 'Inactive',
                statusClass: u.activeLogins === 'Yes' ? 'c360-usage__user-active' : 'c360-usage__user-inactive'
            }))
        };
    }

    // ─── User View Getters ──────────────────────────────────────────────────
    get _selectedUserObj() {
        const site = this._selectedSiteObj;
        if (!site || !this._selectedUserId) return null;
        return site.users.find(u => u.userId === this._selectedUserId) || null;
    }

    get userDetail() {
        const user = this._selectedUserObj;
        if (!user) return null;
        const initials = user.name.split(' ').map(n => n[0]).join('').toUpperCase();
        const channels = [
            { channel: 'Portal', count: user.portalLoginsL4W || 0 },
            { channel: 'Excel', count: user.excelLoginsL4W || 0 },
            { channel: 'Word', count: user.wordLoginsL4W || 0 },
            { channel: 'Outlook', count: user.outlookLoginsL4W || 0 },
            { channel: 'Mobile', count: user.mobileLoginsL4W || 0 },
            { channel: 'Reports', count: user.reportsL4W || 0 },
            { channel: 'Notifications', count: user.notificationsL4W || 0 }
        ];
        const maxChannel = Math.max(...channels.map(c => c.count), 1);
        const channelBars = channels.map(c => ({
            ...c,
            barStyle: `width: ${Math.round((c.count / maxChannel) * 100)}%; background: linear-gradient(135deg, #207CEC, #22ECCF)`
        }));

        const personas = user.personaAdopted ? Object.entries(user.personaAdopted).map(([key, adopted]) => ({
            key,
            name: this._personaLabel(key),
            adopted: adopted === 'Yes',
            pillClass: adopted === 'Yes' ? 'c360-usage__persona-pill c360-usage__persona-pill--adopted' : 'c360-usage__persona-pill'
        })) : [];

        const totalLogins = channels.reduce((s, c) => s + c.count, 0);
        const totalActivity = (user.entriesAdded || 0) + (user.entriesModified || 0) + (user.entriesDeleted || 0);

        return {
            ...user,
            initials,
            isActive: user.activeLogins === 'Yes',
            statusLabel: user.activeLogins === 'Yes' ? 'Active' : 'Inactive',
            totalLogins,
            totalActivity,
            adoptedCount: personas.filter(p => p.adopted).length,
            isBillableLabel: user.isBillable === 'Yes' ? 'Yes' : 'No',
            channelBars,
            personas,
            lastLoginFormatted: user.lastLoginAnyType ? this._formatDate(user.lastLoginAnyType) : 'Never'
        };
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────
    handleRefresh() {
        this._view = 'account';
        this._selectedSiteId = null;
        this._selectedUserId = null;
        this._loadData();
    }

    handleBreadcrumbClick(event) {
        const view = event.currentTarget.dataset.view;
        this._view = view;
        if (view === 'account') {
            this._selectedSiteId = null;
            this._selectedUserId = null;
        } else if (view === 'clientSite') {
            this._selectedUserId = null;
        }
    }

    handleSiteClick(event) {
        this._selectedSiteId = event.currentTarget.dataset.id;
        this._view = 'clientSite';
    }

    handleUserClick(event) {
        this._selectedUserId = event.currentTarget.dataset.id;
        this._view = 'user';
    }

    // ─── Private Methods ──────────────────────────────────────────────────────
    _loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this._usageData = generateAccountUsage(this.accountId);
            this._isMockData = true;
        } catch (err) {
            this.errorMessage = 'Failed to load usage data.';
            this._usageData = null;
        }
        this.isLoading = false;
    }

    _formatDate(isoStr) {
        if (!isoStr) return '—';
        const d = new Date(isoStr);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    }

    _personaLabel(key) {
        const map = {
            Associate: 'Associate', BusinessDevelopment: 'Business Development',
            DataSteward: 'Data Steward', DataStewardPS: 'Data Steward (PS)',
            DealDriver: 'Deal Driver', GateKeeper: 'Gate Keeper',
            Leadership: 'Leadership', Marketing: 'Marketing',
            Partner: 'Partner', PSOther: 'PS Other',
            RoadWarrior: 'Road Warrior', SupportStaff: 'Support Staff',
            SystemAdministrator: 'System Administrator',
            TacticalPlayer: 'Tactical Player',
            TimeKeeperNonLawyer: 'Time Keeper (Non-Lawyer)'
        };
        return map[key] || key;
    }
}