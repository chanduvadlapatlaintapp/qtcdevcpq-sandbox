import { LightningElement, track } from 'lwc';

// =========================================================================
// Section Configuration
// =========================================================================

const SECTION_CONFIG = {
    opportunities: {
        label: 'Opportunities',
        description: 'Renewal and Next Year MultiYear',
        icon: 'utility:opportunity',
        accentClass: 'card-opportunities',
        defaultTab: 'opportunityUpdate',
        enabled: true,
        tabs: [
            { value: 'opportunityUpdate', label: 'Opportunity Update' }
        ]
    }
};

// Reverse lookup: tab value -> section key
const TAB_TO_SECTION = {};
for (const [sectionKey, section] of Object.entries(SECTION_CONFIG)) {
    for (const tab of section.tabs) {
        TAB_TO_SECTION[tab.value] = sectionKey;
    }
}

// =========================================================================
// Component
// =========================================================================

export default class BulkDataUpdateApp extends LightningElement {
    // Navigation state
    @track activeView = 'home';
    @track activeSection = null;
    @track activeTab = null;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadManropeFont();
    }

    loadManropeFont() {
        if (!document.querySelector('link[href*="Manrope"]')) {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = 'https://fonts.googleapis.com/css2?family=Manrope:wght@300;400;500;600;700;800&display=swap';
            document.head.appendChild(link);
        }
    }

    // =========================================================================
    // View State Getters
    // =========================================================================

    get isHomeView() {
        return this.activeView === 'home';
    }

    get isSectionView() {
        return this.activeView === 'section';
    }

    // =========================================================================
    // Landing Page Getters
    // =========================================================================

    get visibleCards() {
        return Object.entries(SECTION_CONFIG)
            .map(([key, section]) => {
                const enabled = section.enabled !== false;
                return {
                    key,
                    label: section.label,
                    description: section.description,
                    icon: section.icon,
                    accentClass: section.accentClass + (enabled ? '' : ' card-disabled'),
                    enabled,
                    pills: section.tabs.map(t => t.label)
                };
            });
    }

    // =========================================================================
    // Section Drill-in Getters
    // =========================================================================

    get activeSectionConfig() {
        if (!this.activeSection) return null;
        return SECTION_CONFIG[this.activeSection];
    }

    get activeSectionLabel() {
        return this.activeSectionConfig ? this.activeSectionConfig.label : '';
    }

    get visibleSubTabs() {
        if (!this.activeSectionConfig) return [];
        return this.activeSectionConfig.tabs.map(tab => ({
            ...tab,
            cssClass: 'tab-item' + (this.activeTab === tab.value ? ' tab-active' : ''),
            isActive: this.activeTab === tab.value
        }));
    }

    // =========================================================================
    // Active Tab Getters
    // =========================================================================

    get isOpportunityUpdateActive() {
        return this.activeTab === 'opportunityUpdate';
    }

    // =========================================================================
    // Handlers
    // =========================================================================

    handleCardClick(event) {
        const sectionKey = event.currentTarget.dataset.section;
        const section = SECTION_CONFIG[sectionKey];
        if (section.enabled === false) return;
        this.activeSection = sectionKey;
        this.activeTab = section.defaultTab;
        this.activeView = 'section';
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick(event);
        }
    }

    handleBackToHome() {
        this.activeView = 'home';
        this.activeSection = null;
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }
}