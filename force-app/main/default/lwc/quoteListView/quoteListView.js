import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUserQuotes from '@salesforce/apex/GuidedSellingController.getUserQuotes';

export default class QuoteListView extends NavigationMixin(LightningElement) {
    quotes = [];
    isLoading = true;
    error;
    @track isDarkMode = true; // Dark mode state

    @wire(getUserQuotes)
    wiredQuotes({ error, data }) {
        if (data) {
            console.log('Quotes data received:', data);
            console.log('Sample quote:', data.length > 0 ? data[0] : 'No quotes');
            this.quotes = data;
            this.isLoading = false;
            this.error = undefined;
        } else if (error) {
            console.error('Error fetching quotes:', error);
            this.error = error;
            this.isLoading = false;
            this.quotes = [];
        }
    }

    get hasQuotes() {
        return this.quotes && this.quotes.length > 0;
    }

    get errorMessage() {
        if (!this.error) return '';
        if (this.error.body && this.error.body.message) {
            return this.error.body.message;
        }
        if (this.error.message) {
            return this.error.message;
        }
        return 'Unknown error';
    }

    get formattedQuotes() {
        return this.quotes.map(quote => ({
            ...quote,
            quoteId: quote.id,
            quoteName: quote.name,
            quoteStage: quote.quoteStage,
            op4iDealUrl: quote.op4iDealUrl,
            op4iDealId: quote.op4iDealId,
            formattedCreatedDate: this.formatDate(quote.createdDate),
            formattedLastModifiedDate: this.formatDate(quote.lastModifiedDate)
        }));
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = new Date(dateValue);
        return date.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: 'short', 
            day: 'numeric' 
        });
    }

    handleConfigure(event) {
        // Get quoteId from the button's data attribute
        // For lightning-button, the event target is the button element
        const button = event.target.closest('lightning-button') || event.currentTarget;
        let quoteId = button?.dataset?.quoteId || 
                     button?.dataset?.id ||
                     button?.getAttribute('data-quote-id') ||
                     event.currentTarget?.dataset?.quoteId;
        
        console.log('handleConfigure called');
        console.log('Button element:', button);
        console.log('QuoteId found:', quoteId);
        
        if (quoteId) {
            // Navigate to nextGenCPQ Visualforce page with quoteId parameter
            const targetUrl = `/apex/NextGenCPQPage?c__quoteid=${quoteId}`;
            console.log('Navigating to:', targetUrl);
            
            // Always try window navigation first for Visualforce context
            try {
                if (window.top && window.top !== window) {
                    window.top.location.href = targetUrl;
                } else {
                    window.location.href = targetUrl;
                }
            } catch (error) {
                console.error('Window navigation failed, trying NavigationMixin:', error);
                // Fallback to NavigationMixin
                try {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: {
                            url: targetUrl
                        }
                    }, false);
                } catch (navError) {
                    console.error('NavigationMixin also failed:', navError);
                }
            }
        } else {
            console.error('No quoteId found');
        }
    }

    handleViewQuote(event) {
        event.preventDefault();
        const quoteId = event.currentTarget.dataset.quoteId;
        if (quoteId) {
            // Navigate to quote record page
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: quoteId,
                    objectApiName: 'SBQQ__Quote__c',
                    actionName: 'view'
                }
            });
        }
    }

    handleToggleDarkMode() {
        this.isDarkMode = !this.isDarkMode;
    }

    get containerClass() {
        return this.isDarkMode ? 'quote-list-container dark-mode' : 'quote-list-container';
    }

    renderedCallback() {
        // Apply dark mode class to host element for CSS variable access
        const hostElement = this.template.host;
        if (hostElement) {
            if (this.isDarkMode) {
                hostElement.classList.add('dark-mode');
            } else {
                hostElement.classList.remove('dark-mode');
            }
        }
    }

    get darkModeIcon() {
        return 'utility:light_bulb';
    }

    get darkModeLabel() {
        return this.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode';
    }
}