import { LightningElement, track } from 'lwc';
import searchAccounts from '@salesforce/apex/AgenticQTC_AccountSearchService.searchAccounts';

/**
 * Account search component that provides typeahead search functionality
 * for finding Salesforce accounts. Dispatches an accountselected event
 * when a user clicks on a search result.
 */
export default class AgenticQtcAccountSearch extends LightningElement {
    /** @type {string} The current search input value. */
    @track searchTerm = '';

    /** @type {Array<Object>} List of account results returned from search. */
    @track accounts = [];

    /** @type {boolean} Whether a search request is in progress. */
    @track isLoading = false;

    /** @type {boolean} Whether at least one search has been performed. */
    @track hasSearched = false;

    /** @type {number|undefined} Timeout ID for debouncing search input. */
    _searchTimeout;

    /**
     * @description Whether search results are available to display.
     * @returns {boolean} True if a search has completed with results and loading is done.
     */
    get hasResults() {
        return this.hasSearched && this.accounts.length > 0 && !this.isLoading;
    }

    /**
     * @description Whether the search completed with zero results.
     * @returns {boolean} True if searched with a valid term but no accounts were found.
     */
    get noResults() {
        return this.hasSearched && this.accounts.length === 0 && !this.isLoading && this.searchTerm.length >= 2;
    }

    /**
     * @description Handles input changes, debouncing the search by 300ms. Clears results if
     *              the search term is too short.
     * @param {Event} event - Native input event from the search field.
     * @returns {void}
     */
    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        clearTimeout(this._searchTimeout);
        if (this.searchTerm.length >= 2) {
            this._searchTimeout = setTimeout(() => this.doSearch(), 300);
        } else {
            this.accounts = [];
            this.hasSearched = false;
            this.isLoading = false;
        }
    }

    /**
     * @description Executes the account search via Apex and updates the results list.
     * @returns {Promise<void>}
     */
    async doSearch() {
        const term = this.searchTerm;
        this.isLoading = true;
        try {
            const results = await searchAccounts({ searchTerm: term });
            if (this.searchTerm === term) {
                this.accounts = results;
                this.hasSearched = true;
            }
        } catch (error) {
            console.error('Account search error:', error);
            if (this.searchTerm === term) {
                this.accounts = [];
            }
        } finally {
            if (this.searchTerm === term) {
                this.isLoading = false;
            }
        }
    }

    /**
     * @description Handles a click on an account result row, dispatching an accountselected event
     *              with the account ID and name.
     * @param {Event} event - Click event from the account row with data-id and data-name attributes.
     * @returns {void}
     */
    handleAccountClick(event) {
        const accountId = event?.currentTarget?.dataset?.id;
        const accountName = event?.currentTarget?.dataset?.name;
        if (!accountId) return;
        this.dispatchEvent(new CustomEvent('accountselected', {
            detail: { accountId, accountName }
        }));
    }
}