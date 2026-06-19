import { LightningElement, track } from 'lwc';
import HAS_NEW_SKU_BETA from '@salesforce/customPermission/SKU_New_Launch_Beta_Tester';

// =========================================================================
// Section Configuration
// =========================================================================

const SECTION_CONFIG = {
    pricebookView: {
        label: 'Pricebook View',
        description: 'View Product & Pricing data grouped by vertical or business unit',
        icon: 'utility:chart',
        accentClass: 'card-pricebookView',
        defaultTab: 'pricebookView',
        tabs: [
            { value: 'pricebookView', label: 'Pricebook View' }
        ]
    },
    update: {
        label: 'Update Product',
        description: 'Update product, product line, and product rollup',
        icon: 'utility:edit',
        accentClass: 'card-update',
        defaultTab: 'unifiedUpdate',
        tabs: [
            { value: 'unifiedUpdate', label: 'Update Product' },
            { value: 'updateProductLine', label: 'Update Product Line' },
            { value: 'updateProductRollup', label: 'Update Product Rollup' }
        ]
    },
    newSku: {
        label: 'New SKU Launch',
        description: 'Launch new SKUs from Questionnaire Excel upload',
        icon: 'utility:new',
        accentClass: 'card-newSku',
        defaultTab: 'skuNewLaunch',
        permissionGate: 'hasNewSkuBeta',
        tabs: [
            { value: 'skuNewLaunch', label: 'New SKU Launch' }
        ]
    },
    pricebook: {
        label: 'Pricebook Launch',
        description: 'Launch new pricebooks and create pricing records for existing pricebooks',
        icon: 'utility:knowledge_base',
        accentClass: 'card-pricebook',
        defaultTab: 'pricebookWizard',
        enabled: true,
        tabs: [
            { value: 'pricebookWizard', label: 'Pricebook Launch Wizard' }
        ]
    },
    quoteTermUpdate: {
        label: 'Quote Term Update',
        description: 'View and update Active Standard Quote Terms — Body and Description fields',
        icon: 'utility:contract',
        accentClass: 'card-quoteTermUpdate',
        defaultTab: 'quoteTermUpdate',
        enabled: true,
        tabs: [
            { value: 'quoteTermUpdate', label: 'Quote Term Update' }
        ]
    }
};

// Reverse lookup: tab value → section key
const TAB_TO_SECTION = {};
for (const [sectionKey, section] of Object.entries(SECTION_CONFIG)) {
    for (const tab of section.tabs) {
        TAB_TO_SECTION[tab.value] = sectionKey;
    }
}

// =========================================================================
// Component
// =========================================================================

export default class SkuManagementApp extends LightningElement {
    // Feature flags
    showQuoteTermsTab = true;
    hasNewSkuBeta = HAS_NEW_SKU_BETA;

    // Navigation state
    @track activeView = 'home';        // 'home' | 'section'
    @track activeSection = null;        // 'update' | 'newSku' | 'pricebook'
    @track activeTab = 'updateSku';
    @track preselectedProductId;

    // Pricebook View context (preserved for back navigation from Update Product)
    @track pricebookViewContext = null;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    connectedCallback() {
        this.loadManropeFont();
    }

    /**
     * Inject Manrope Google Font into document head (once).
     * Fonts cascade through Shadow DOM, so loading at the app-shell level
     * makes Manrope available to all child LWC components.
     */
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
            .filter(([, section]) => {
                if (section.featureFlag) {
                    return this[section.featureFlag];
                }
                return true;
            })
            .map(([key, section]) => {
                const visibleTabs = section.tabs.filter(tab => {
                    if (tab.featureFlag) {
                        return this[tab.featureFlag];
                    }
                    return true;
                });
                let enabled = section.enabled !== false;
                if (section.permissionGate) {
                    enabled = !!this[section.permissionGate];
                }
                return {
                    key,
                    label: section.label,
                    description: section.description,
                    icon: section.icon,
                    accentClass: section.accentClass + (enabled ? '' : ' card-disabled'),
                    enabled,
                    pills: visibleTabs.map(t => t.label)
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
        return this.activeSectionConfig.tabs
            .filter(tab => {
                if (tab.featureFlag) {
                    return this[tab.featureFlag];
                }
                return true;
            })
            .map(tab => ({
                ...tab,
                cssClass: 'tab-item' + (this.activeTab === tab.value ? ' tab-active' : ''),
                isActive: this.activeTab === tab.value
            }));
    }

    // =========================================================================
    // Active Tab Getters (for child component rendering)
    // =========================================================================

    get isSkuNewLaunchActive() {
        return this.activeTab === 'skuNewLaunch';
    }

    get isCreateStandaloneActive() {
        return this.activeTab === 'createStandalone';
    }

    get isCreateBundleActive() {
        return this.activeTab === 'createBundle';
    }

    get isUnifiedUpdateActive() {
        return this.activeTab === 'unifiedUpdate';
    }

    get isUpdateProductLineActive() {
        return this.activeTab === 'updateProductLine';
    }

    get isUpdateProductRollupActive() {
        return this.activeTab === 'updateProductRollup';
    }

    get isPricebookViewActive() {
        return this.activeTab === 'pricebookView';
    }

    get isPricebookWizardActive() {
        return this.activeTab === 'pricebookWizard';
    }

    get isQuoteTermUpdateActive() {
        return this.activeTab === 'quoteTermUpdate';
    }

    // =========================================================================
    // Handlers
    // =========================================================================

    handleCardClick(event) {
        const sectionKey = event.currentTarget.dataset.section;
        const section = SECTION_CONFIG[sectionKey];
        if (section.enabled === false) return;
        if (section.permissionGate && !this[section.permissionGate]) return;
        this.activeSection = sectionKey;
        this.activeTab = section.defaultTab;
        this.activeView = 'section';
        this.pricebookViewContext = null; // Clear stale context
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
        this.preselectedProductId = undefined;
        this.pricebookViewContext = null;
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleNavigateToTab(event) {
        const { tabName, tab, productId, pricebookContext } = event.detail;
        const resolvedTab = tabName || tab;

        if (productId) {
            this.preselectedProductId = productId;
        }

        // Capture pricebook view context for back navigation
        if (pricebookContext) {
            this.pricebookViewContext = pricebookContext;
        }

        // Look up which section owns this tab and navigate there
        const targetSection = TAB_TO_SECTION[resolvedTab];
        if (targetSection) {
            this.activeSection = targetSection;
            this.activeTab = resolvedTab;
            this.activeView = 'section';
        }
    }

    get hasPricebookContext() {
        return !!this.pricebookViewContext;
    }

    get showPricebookBreadcrumb() {
        return this.hasPricebookContext && this.activeSection !== 'pricebookView';
    }

    handleBackToPricebook() {
        this.activeSection = 'pricebookView';
        this.activeTab = 'pricebookView';
        this.activeView = 'section';
        this.preselectedProductId = undefined;
    }
}