import { LightningElement, api, track } from 'lwc';
import getEligibleProducts from '@salesforce/apex/AgenticQTC_ProductService.getEligibleProducts';
import addProductToQuote from '@salesforce/apex/AgenticQTC_ProductService.addProductToQuote';

/**
 * Modal component for searching and adding eligible products to an amendment quote.
 * Provides typeahead product search, selection, quantity input, and dispatches
 * a productadded event upon successful addition.
 */
export default class AgenticQtcAddProduct extends LightningElement {
    /** @api @type {string} The Salesforce Quote ID to add products to. */
    @api quoteId;

    /** @type {string} Current product search input value. */
    @track searchTerm = '';

    /** @type {Array<Object>} List of eligible product results. */
    @track products = [];

    /** @type {string|null} ID of the currently selected product. */
    @track selectedProductId = null;

    /** @type {Object|null} The full product object of the current selection. */
    @track selectedProduct = null;

    /** @type {boolean} Whether a product search is in progress. */
    @track isSearching = false;

    /** @type {boolean} Whether the add-to-quote operation is in progress. */
    @track isAdding = false;

    /** @type {number} Quantity to add for the selected product. */
    @track newQuantity = 1;

    /** @type {number|undefined} Timeout ID for debouncing search input. */
    _searchTimeout;

    /**
     * @description Whether product results are available to display.
     * @returns {boolean}
     */
    get hasProducts() { return this.products.length > 0 && !this.isSearching; }

    /**
     * @description Whether the add-to-quote button should be disabled.
     * @returns {boolean} True if no product is selected, an add is in progress, or quantity is invalid.
     */
    get isAddDisabled() { return !this.selectedProduct || this.isAdding || this.newQuantity < 1; }

    /**
     * @description Lifecycle hook that loads the initial product list on component insertion.
     * @returns {void}
     */
    connectedCallback() {
        this.loadProducts();
    }

    /**
     * @description Fetches eligible products from Apex, decorating each with selection state.
     * @returns {Promise<void>}
     */
    async loadProducts() {
        this.isSearching = true;
        try {
            const rawProducts = await getEligibleProducts({ searchTerm: this.searchTerm });
            this.products = (rawProducts || []).map(p => ({
                ...p,
                isSelected: p.id === this.selectedProductId
            }));
        } catch (error) {
            console.error('Product search error:', error);
        } finally {
            this.isSearching = false;
        }
    }

    /**
     * @description Computes the CSS class for a product row based on selection state.
     * @param {string} productId - The product ID to check against the current selection.
     * @returns {string} Space-separated CSS class string.
     */
    getProductClass(productId) {
        return 'product-item' + (productId === this.selectedProductId ? ' selected' : '');
    }

    /**
     * @description Handles search input changes, debouncing the product lookup by 300ms.
     * @param {Event} event - Native input event from the search field.
     * @returns {void}
     */
    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchTimeout);
        this._searchTimeout = setTimeout(() => this.loadProducts(), 300);
    }

    /**
     * @description Selects a product from the results list, updating visual selection state.
     * @param {Event} event - Click event from a product row with data-id attribute.
     * @returns {void}
     */
    handleSelectProduct(event) {
        const productId = event?.currentTarget?.dataset?.id;
        if (!productId) return;
        this.selectedProductId = productId;
        this.selectedProduct = this.products.find(p => p.id === productId) || null;
        this.products = this.products.map(p => ({
            ...p,
            isSelected: p.id === productId
        }));
    }

    /**
     * @description Updates the quantity value when the user changes the quantity input.
     * @param {Event} event - Native change event from the quantity input.
     * @returns {void}
     */
    handleNewQuantityChange(event) { this.newQuantity = Number(event.target.value); }

    /**
     * @description Adds the selected product to the quote via Apex and dispatches a productadded event.
     * @returns {Promise<void>}
     */
    async handleAddToQuote() {
        if (!this.selectedProduct) return;
        this.isAdding = true;
        try {
            await addProductToQuote({
                quoteId: this.quoteId,
                productId: this.selectedProduct.id,
                quantity: this.newQuantity
            });
            this.dispatchEvent(new CustomEvent('productadded'));
        } catch (error) {
            console.error('Error adding product:', error);
        } finally {
            this.isAdding = false;
        }
    }

    /**
     * @description Dispatches a close event to dismiss the modal.
     * @returns {void}
     */
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /**
     * @description Handles clicks on the modal overlay backdrop, closing the modal.
     * @returns {void}
     */
    handleOverlayClick() {
        this.handleClose();
    }

    /**
     * @description Prevents click events from propagating through the modal content to the overlay.
     * @param {Event} event - The click event to stop.
     * @returns {void}
     */
    stopPropagation(event) {
        if (event) {
            event.stopPropagation();
        }
    }
}