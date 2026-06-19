import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getQuoteLines from '@salesforce/apex/GuidedSellingController.getQuoteLines';

export default class NextGenCPQ extends NavigationMixin(LightningElement) {
    @api quoteId;
    @track firstSegmentMonths;
    @track totalContractMonths;
    @track startDate;
    @track showGuidedSellingModal = false;
    @track isDarkMode = true; // Dark mode state
    @track quoteLines = []; // Existing quote lines
    @track newQuoteLineIds = new Set(); // Track newly added quote line IDs
    @track refreshKey = 0; // Key to force wire refresh
    _quoteIdFromUrl = null; // Store quoteId from URL
    urlParams = {}; // Object to store the URL parameters

    connectedCallback() {
        // Set default values
        this.firstSegmentMonths = 12;
        this.totalContractMonths = 12;
        // Set current date as default
        const today = new Date();
        const year = today.getFullYear();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = String(today.getDate()).padStart(2, '0');
        this.startDate = `${year}-${month}-${day}`;
    }

    @wire(CurrentPageReference)
    getPageReference(pageRef) {
        if (pageRef) {
            // Extracting URL parameters
            this.urlParams = pageRef.state;
            console.log('=====',this.urlParams);
            // Only set quoteId from URL if not already provided via @api
            if (!this.quoteId && !this._quoteIdFromUrl && this.urlParams.c__quoteid) {
                this._quoteIdFromUrl = this.urlParams.c__quoteid;
            }
        }
    }

    // Watch for quoteId changes from parent/URL
    renderedCallback() {
        // If quoteId is passed as property, use it
        // Otherwise try to get from URL if in Lightning context
        if (!this.quoteId) {
            // Try to get from URL parameters (for Visualforce)
            const urlParams = new URLSearchParams(window.location.search);
            const urlQuoteId = urlParams.get('quoteId') || urlParams.get('c__quoteid');
            if (urlQuoteId && !this._quoteIdFromUrl) {
                this._quoteIdFromUrl = urlQuoteId;
            }
        }
    }

    get effectiveQuoteId() {
        return this.quoteId || this._quoteIdFromUrl;
    }

    handleFirstSegmentMonthsChange(event) {
        this.firstSegmentMonths = event.target.value;
    }

    handleTotalContractMonthsChange(event) {
        this.totalContractMonths = event.target.value;
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    @wire(getQuoteLines, { quoteId: '$effectiveQuoteId' })
    wiredQuoteLines(result) {
        this._wiredQuoteLinesResult = result; // Store for refresh
        if (result.data) {
            this.quoteLines = result.data;
            console.log('Quote lines loaded:', this.quoteLines.length);
        } else if (result.error) {
            console.error('Error fetching quote lines:', result.error);
            this.quoteLines = [];
        }
    }

    get hasQuoteLines() {
        return this.quoteLines && this.quoteLines.length > 0;
    }

    handleGuidedSelling() {
        this.showGuidedSellingModal = true;
    }

    handleCloseModal() {
        this.showGuidedSellingModal = false;
    }

    get modalClass() {
        return this.showGuidedSellingModal 
            ? 'slds-modal slds-fade-in-open slds-modal_large' 
            : 'slds-modal slds-modal_large hidden-modal';
    }

    get backdropClass() {
        return this.showGuidedSellingModal 
            ? 'slds-backdrop slds-backdrop_open' 
            : 'slds-backdrop hidden-backdrop';
    }

    handleSaveQuote() {
        if (this.quoteId) {
            // Check if we're in Visualforce context
            const isVisualforce = window.location.pathname.includes('/apex/') || 
                                 window.top !== window || 
                                 typeof sforce !== 'undefined';
            
            if (isVisualforce) {
                // Use window navigation for Visualforce
                const recordUrl = '/' + this.quoteId;
                if (window.top && window.top.location) {
                    window.top.location.href = recordUrl;
                } else {
                    window.location.href = recordUrl;
                }
            } else {
                // Use NavigationMixin for Lightning Experience
                try {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: this.quoteId,
                            actionName: 'view'
                        }
                    });
                } catch (error) {
                    // Fallback to window navigation if NavigationMixin fails
                    console.error('NavigationMixin failed, using window navigation:', error);
                    window.location.href = '/' + this.quoteId;
                }
            }
        }
    }

    handleToggleDarkMode() {
        this.isDarkMode = !this.isDarkMode;
    }

    get containerClass() {
        return this.isDarkMode ? 'cpq-container dark-mode' : 'cpq-container';
    }

    get darkModeIcon() {
        return 'utility:light_bulb';
    }

    get darkModeLabel() {
        return this.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode';
    }

    handleAICartUpdate(event) {
        // Handle cart updates from AI Assistant
        // Add null check for event.detail to prevent TypeError
        if (!event || !event.detail) {
            console.warn('AI cart update event missing detail property');
            return;
        }
        
        const cart = event.detail.cart;
        console.log('AI Cart Updated:', cart);
        
        // Sync cart with the modal Guided Selling component (not the cart-only one)
        const guidedSellingComponent = this.template.querySelector('c-guided-selling[data-id="modal-guided-selling"]');
        console.log('Guided Selling component found:', !!guidedSellingComponent);
        
        if (guidedSellingComponent) {
            // Check if cart is cleared (empty array)
            const isCartCleared = Array.isArray(cart) && cart.length === 0;
            
            if (cart) {
                console.log('Calling syncCartFromAI with cart items:', cart.length);
                guidedSellingComponent.syncCartFromAI(cart);
            }
            
            // If cart was cleared, refresh the guided selling component
            if (isCartCleared) {
                // Refresh the component to update UI state
                guidedSellingComponent.refreshComponent();
            }
        } else {
            console.warn('Modal Guided Selling component not found. Available components:', 
                this.template.querySelectorAll('c-guided-selling').length);
        }
    }

    async handleGuidedSellingClose() {
        // When guided selling modal closes, refresh quote lines to show newly added ones
        this.handleCloseModal();
        console.log('Guided Selling modal closed, refreshing quote lines...');
        // Refresh quote lines immediately
        await this.refreshQuoteLines();
    }

    async handleQuoteLinesCreated(event) {
        console.log('Quote lines created event received:', event.detail);
        // Track newly created quote line IDs
        if (event.detail && event.detail.createdQuoteLineIds) {
            event.detail.createdQuoteLineIds.forEach(id => {
                this.newQuoteLineIds.add(id);
            });
            // Refresh quote lines to show the new ones
            await this.refreshQuoteLines();
        }
    }

    async refreshQuoteLines() {
        console.log('Refreshing quote lines...');
        try {
            // Use refreshApex to re-fetch the wired data
            if (this._wiredQuoteLinesResult) {
                await refreshApex(this._wiredQuoteLinesResult);
                console.log('Quote lines refreshed successfully, count:', this.quoteLines.length);
            } else {
                console.warn('Wire result not available, cannot refresh');
            }
        } catch (error) {
            console.error('Error refreshing quote lines:', error);
        }
    }
}