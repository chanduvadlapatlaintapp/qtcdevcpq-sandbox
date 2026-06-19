/**
 * AI Quote Assistant Chatbot - Lightning Web Component
 * 
 * A beautiful, AI-powered CPQ chatbot integrated with Google Gemini.
 * Allows users to build quotes using natural language commands.
 * 
 * Features:
 * - Natural language processing via Gemini AI
 * - Real-time cart management
 * - Product search and recommendations
 * - Discount application
 * - Beautiful split-panel UI
 * 
 * @author Salesforce LWC Developer
 * @version 2.0.0
 */

import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Import Apex methods - replace with your actual controller methods
import getAIResponse from '@salesforce/apex/GeminiQuoteAssistantController.getAIResponse';
import getProducts from '@salesforce/apex/GeminiQuoteAssistantController.getProducts';
import addProductsToQuote from '@salesforce/apex/GeminiQuoteAssistantController.addProductsToQuote';

export default class AiQuoteAssistantChatbot extends LightningElement {
    // ============================================
    // PUBLIC API PROPERTIES
    // ============================================
    
    /** Quote record ID to add products to */
    @api quoteId;
    
    /** Enable dark mode theme */
    @api isDarkMode = false;

    // ============================================
    // TRACKED STATE PROPERTIES
    // ============================================
    
    /** Chat messages array */
    @track messages = [];
    
    /** Current user input value */
    @track inputValue = '';
    
    /** Loading state for AI response */
    @track isLoading = false;
    
    /** Cart items array */
    @track cartItems = [];
    
    /** Cart totals object */
    @track cartTotals = {
        subtotal: 0,
        discountTotal: 0,
        grandTotal: 0
    };
    
    /** Available products from Salesforce */
    @track availableProducts = [];
    
    /** Current theme (dark/light) */
    @track currentTheme = 'dark';

    // ============================================
    // PRIVATE PROPERTIES
    // ============================================
    
    /** Message ID counter for unique keys */
    _messageIdCounter = 0;
    
    /** Cart item ID counter */
    _cartItemIdCounter = 0;

    // ============================================
    // CONSTANTS
    // ============================================
    
    /** Suggestion chips for quick actions */
    suggestionChips = [
        { id: '1', text: 'Add 5 Maintenance Technicians' },
        { id: '2', text: 'Show me available products' },
        { id: '3', text: 'Apply 15% discount to all items' },
        { id: '4', text: 'What\'s in my cart?' },
        { id: '5', text: 'Clear my cart' }
    ];

    // ============================================
    // WIRE ADAPTERS
    // ============================================
    
    /**
     * Wire adapter to fetch available products from Salesforce
     */
    @wire(getProducts)
    wiredProducts({ error, data }) {
        if (data) {
            this.availableProducts = data;
            console.log('Products loaded:', data.length);
        } else if (error) {
            console.error('Error loading products:', error);
        }
    }

    // ============================================
    // LIFECYCLE HOOKS
    // ============================================
    
    /**
     * Component connected to DOM - initialize chat
     */
    connectedCallback() {
        // Default to dark theme (property is false by default due to LWC rules)
        this.currentTheme = 'dark';
        this._addWelcomeMessage();
    }

    /**
     * Component rendered - scroll to bottom after updates
     */
    renderedCallback() {
        this._scrollToBottom();
    }

    // ============================================
    // GETTERS - UI STATE
    // ============================================
    
    /** Get theme toggle icon */
    get themeIcon() {
        return this.currentTheme === 'dark' ? 'utility:light_bulb' : 'utility:dayview';
    }

    /** Check if send button should be disabled */
    get isSendDisabled() {
        return !this.inputValue || this.inputValue.trim() === '' || this.isLoading;
    }

    /** Get connection status text */
    get connectionStatus() {
        return this.isLoading ? 'Processing...' : 'Online';
    }

    /** Get status dot CSS class */
    get statusDotClass() {
        return this.isLoading ? 'status-dot processing' : 'status-dot online';
    }

    /** Get cart item count */
    get cartItemCount() {
        return this.cartItems.length;
    }

    /** Check if cart has items */
    get hasCartItems() {
        return this.cartItems.length > 0;
    }

    /** Check if cart is empty */
    get isCartEmpty() {
        return this.cartItems.length === 0;
    }

    /** Check if cart has any discounts applied */
    get hasDiscounts() {
        return this.cartTotals.discountTotal > 0;
    }

    /** Format subtotal for display */
    get formattedSubtotal() {
        return this._formatCurrency(this.cartTotals.subtotal);
    }

    /** Format discount total for display */
    get formattedDiscountTotal() {
        return this._formatCurrency(this.cartTotals.discountTotal);
    }

    /** Format grand total for display */
    get formattedGrandTotal() {
        return this._formatCurrency(this.cartTotals.grandTotal);
    }

    // ============================================
    // EVENT HANDLERS - USER INTERACTIONS
    // ============================================
    
    /**
     * Handle theme toggle button click
     */
    handleToggleTheme() {
        this.currentTheme = this.currentTheme === 'dark' ? 'light' : 'dark';
    }

    /**
     * Handle clear chat button click
     */
    handleClearChat() {
        this.messages = [];
        this._addWelcomeMessage();
        this._showToast('Chat Cleared', 'Conversation has been reset.', 'info');
    }

    /**
     * Handle input field change
     * @param {Event} event - Input event
     */
    handleInputChange(event) {
        this.inputValue = event.target.value;
        this._autoResizeTextarea(event.target);
    }

    /**
     * Handle keyboard events in input field
     * @param {KeyboardEvent} event - Keyboard event
     */
    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (!this.isSendDisabled) {
                this.handleSendMessage();
            }
        }
    }

    /**
     * Handle suggestion chip click
     * @param {Event} event - Click event
     */
    handleSuggestionClick(event) {
        const text = event.currentTarget.dataset.text;
        this.inputValue = text;
        this.handleSendMessage();
    }

    /**
     * Handle send message button click
     */
    async handleSendMessage() {
        if (this.isSendDisabled) return;

        const userText = this.inputValue.trim();
        this.inputValue = '';
        
        // Reset textarea height
        const textarea = this.template.querySelector('[data-id="chatInput"]');
        if (textarea) {
            textarea.style.height = 'auto';
        }

        // Add user message to chat
        this._addMessage(userText, 'user');

        // Set loading state
        this.isLoading = true;

        try {
            // Call Apex to get AI response
            const rawJson = await getAIResponse({ 
                userMessage: userText,
                cartDataJson: JSON.stringify(this.cartItems)
            });

            // Parse AI response
            let aiResponse;
            try {
                aiResponse = this._parseAIResponse(rawJson);
            } catch (parseError) {
                console.error('JSON Parse Error:', parseError);
                this._addMessage(
                    'I apologize, but I had trouble processing the response. Please try again.',
                    'bot'
                );
                return;
            }

            // Extract response components
            const { action, parameters, message } = aiResponse || {};

            // Handle the action
            if (action && action !== 'NONE') {
                this._handleAction(action, parameters || {});
            }

            // Add AI message to chat
            this._addMessage(
                message || 'I processed your request.',
                'bot',
                action
            );

        } catch (error) {
            console.error('Error calling AI:', error);
            
            // Try local processing as fallback
            const localResponse = this._processLocalCommand(userText);
            this._addMessage(localResponse.message, 'bot', localResponse.action);
            
            if (localResponse.action && localResponse.action !== 'NONE' && localResponse.action !== 'CLARIFY') {
                this._handleAction(localResponse.action, localResponse.parameters || {});
            }
        } finally {
            this.isLoading = false;
        }

        // Dispatch cart update event to parent
        this._dispatchCartUpdate();
    }

    /**
     * Handle remove item button click
     * @param {Event} event - Click event
     */
    handleRemoveItem(event) {
        const productId = event.currentTarget.dataset.id;
        this._handleRemoveProduct({ productId });
        this._addMessage(
            'Item removed from your cart.',
            'bot',
            'REMOVE_PRODUCT'
        );
    }

    /**
     * Handle clear cart button click
     */
    handleClearCart() {
        this._handleClearCart();
        this._addMessage(
            'Your cart has been cleared. Ready to start fresh!',
            'bot',
            'CLEAR_CART'
        );
    }

    /**
     * Handle add to quote button click
     */
    async handleAddToQuote() {
        if (this.isCartEmpty) {
            this._showToast('Empty Cart', 'Please add items to your cart first.', 'warning');
            return;
        }

        if (!this.quoteId) {
            this._showToast('No Quote Selected', 'Please select a quote to add products to.', 'warning');
            return;
        }

        try {
            const result = await addProductsToQuote({
                quoteId: this.quoteId,
                productsJson: JSON.stringify(this.cartItems.map(item => ({
                    productId: item.productId,
                    productName: item.productName,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice,
                    discount: item.discountPercent
                })))
            });

            this._showToast('Success', result || 'Products added to quote successfully!', 'success');
            this._handleClearCart();
            this._addMessage(
                'Excellent! I\'ve added all items to your quote. Your cart has been cleared.',
                'bot',
                'ADD_TO_QUOTE'
            );
        } catch (error) {
            console.error('Error adding to quote:', error);
            this._showToast('Error', 'Failed to add products to quote. Please try again.', 'error');
        }
    }

    // ============================================
    // ACTION HANDLERS
    // ============================================
    
    /**
     * Route action to appropriate handler
     * @param {string} action - Action type
     * @param {Object} parameters - Action parameters
     */
    _handleAction(action, parameters) {
        switch (action) {
            case 'ADD_PRODUCT':
                this._handleAddProduct(parameters);
                break;
            case 'REMOVE_PRODUCT':
                this._handleRemoveProduct(parameters);
                break;
            case 'UPDATE_QUANTITY':
                this._handleUpdateQuantity(parameters);
                break;
            case 'APPLY_DISCOUNT':
                this._handleApplyDiscount(parameters);
                break;
            case 'CLEAR_CART':
                this._handleClearCart();
                break;
            case 'GET_SUMMARY':
                this._handleGetSummary();
                break;
            case 'CLARIFY':
                // No cart action needed - just display message
                break;
            default:
                console.log('Unknown action:', action);
        }
    }

    /**
     * Handle ADD_PRODUCT action
     * @param {Object} params - Product parameters
     */
    _handleAddProduct(params) {
        const { productId, productName, quantity = 1, unitPrice = 100 } = params;
        
        if (!productId && !productName) {
            console.warn('ADD_PRODUCT: Missing product identifier');
            return;
        }

        // Find product in available products if we have an ID
        let product = null;
        if (productId) {
            product = this.availableProducts.find(p => p.id === productId);
        } else if (productName) {
            product = this._findProductByName(productName);
        }

        const finalProductId = productId || (product ? product.id : `temp-${Date.now()}`);
        const finalProductName = productName || (product ? product.name : 'Unknown Product');
        const finalUnitPrice = product?.unitPrice || unitPrice;

        // Check if product already in cart
        const existingIndex = this.cartItems.findIndex(item => 
            item.productId === finalProductId
        );

        if (existingIndex >= 0) {
            // Update quantity
            const updatedItems = [...this.cartItems];
            updatedItems[existingIndex] = {
                ...updatedItems[existingIndex],
                quantity: updatedItems[existingIndex].quantity + quantity
            };
            this.cartItems = updatedItems;
        } else {
            // Add new item
            this.cartItems = [...this.cartItems, {
                id: `cart-${++this._cartItemIdCounter}`,
                productId: finalProductId,
                productName: finalProductName,
                quantity: quantity,
                unitPrice: finalUnitPrice,
                discountPercent: 0,
                lineTotal: quantity * finalUnitPrice,
                formattedUnitPrice: this._formatCurrency(finalUnitPrice),
                formattedLineTotal: this._formatCurrency(quantity * finalUnitPrice),
                hasDiscount: false
            }];
        }

        this._recalculateCartTotals();
    }

    /**
     * Handle REMOVE_PRODUCT action
     * @param {Object} params - Product parameters
     */
    _handleRemoveProduct(params) {
        const { productId, productName } = params;
        
        if (productId) {
            this.cartItems = this.cartItems.filter(item => item.productId !== productId);
        } else if (productName) {
            this.cartItems = this.cartItems.filter(item => 
                item.productName.toLowerCase() !== productName.toLowerCase()
            );
        }

        this._recalculateCartTotals();
    }

    /**
     * Handle UPDATE_QUANTITY action
     * @param {Object} params - Update parameters
     */
    _handleUpdateQuantity(params) {
        const { productId, productName, quantity } = params;
        
        this.cartItems = this.cartItems.map(item => {
            const matches = productId 
                ? item.productId === productId 
                : item.productName.toLowerCase() === (productName || '').toLowerCase();
            
            if (matches) {
                const lineTotal = quantity * item.unitPrice * (1 - (item.discountPercent || 0) / 100);
                return {
                    ...item,
                    quantity: quantity,
                    lineTotal: lineTotal,
                    formattedLineTotal: this._formatCurrency(lineTotal)
                };
            }
            return item;
        });

        this._recalculateCartTotals();
    }

    /**
     * Handle APPLY_DISCOUNT action
     * @param {Object} params - Discount parameters
     */
    _handleApplyDiscount(params) {
        const { discountPercent, applyTo = 'all', productId } = params;
        
        this.cartItems = this.cartItems.map(item => {
            const shouldApply = applyTo === 'all' || item.productId === applyTo || item.productId === productId;
            
            if (shouldApply) {
                const discountAmount = item.quantity * item.unitPrice * (discountPercent / 100);
                const lineTotal = item.quantity * item.unitPrice - discountAmount;
                return {
                    ...item,
                    discountPercent: discountPercent,
                    lineTotal: lineTotal,
                    formattedLineTotal: this._formatCurrency(lineTotal),
                    hasDiscount: discountPercent > 0
                };
            }
            return item;
        });

        this._recalculateCartTotals();
    }

    /**
     * Handle CLEAR_CART action
     */
    _handleClearCart() {
        this.cartItems = [];
        this.cartTotals = {
            subtotal: 0,
            discountTotal: 0,
            grandTotal: 0
        };
    }

    /**
     * Handle GET_SUMMARY action
     */
    _handleGetSummary() {
        // The message will be displayed, cart is already visible
        // This could trigger additional UI updates if needed
        this._recalculateCartTotals();
    }

    // ============================================
    // LOCAL COMMAND PROCESSING (FALLBACK)
    // ============================================
    
    /**
     * Process user command locally when AI is unavailable
     * @param {string} text - User input text
     * @returns {Object} Response object with action, parameters, message
     */
    _processLocalCommand(text) {
        const lowerText = text.toLowerCase();

        // Clear cart
        if (lowerText.includes('clear cart') || lowerText.includes('empty cart') || lowerText.includes('remove all')) {
            return {
                action: 'CLEAR_CART',
                parameters: {},
                message: "Done! I've cleared your cart. Ready to start fresh!"
            };
        }

        // Get summary
        if (lowerText.includes('summary') || lowerText.includes('what\'s in') || lowerText.includes('show cart') || lowerText.includes('my cart')) {
            if (this.cartItems.length === 0) {
                return {
                    action: 'GET_SUMMARY',
                    parameters: {},
                    message: 'Your cart is currently empty. Try adding some products!'
                };
            }
            return {
                action: 'GET_SUMMARY',
                parameters: {},
                message: `Your cart has ${this.cartItems.length} item(s) with a total of ${this.formattedGrandTotal}. Check the cart panel for details!`
            };
        }

        // Apply discount
        const discountMatch = lowerText.match(/(\d+)\s*%?\s*discount/);
        if (discountMatch) {
            const discount = parseInt(discountMatch[1], 10);
            return {
                action: 'APPLY_DISCOUNT',
                parameters: { discountPercent: discount, applyTo: 'all' },
                message: `Applied ${discount}% discount to all items in your cart.`
            };
        }

        // Add product
        const addMatch = lowerText.match(/add\s+(\d+)?\s*(.*?)(?:\s+to\s+|$)/i);
        if (addMatch || lowerText.includes('add')) {
            const quantity = addMatch && addMatch[1] ? parseInt(addMatch[1], 10) : 1;
            const productHint = addMatch && addMatch[2] ? addMatch[2].trim() : lowerText.replace(/add\s*/i, '').trim();
            
            const matchedProduct = this._findProductByName(productHint);
            
            if (matchedProduct) {
                return {
                    action: 'ADD_PRODUCT',
                    parameters: {
                        productId: matchedProduct.id,
                        productName: matchedProduct.name,
                        quantity: quantity,
                        unitPrice: matchedProduct.unitPrice || 100
                    },
                    message: `Added ${quantity} x ${matchedProduct.name} to your cart.`
                };
            } else {
                return {
                    action: 'ADD_PRODUCT',
                    parameters: {
                        productName: productHint || 'Product',
                        quantity: quantity,
                        unitPrice: 100
                    },
                    message: `Added ${quantity} x "${productHint || 'Product'}" to your cart. (Note: Running in offline mode)`
                };
            }
        }

        // Default response
        return {
            action: 'CLARIFY',
            parameters: {},
            message: "I'm having trouble connecting to the AI service. Try commands like 'add 5 technicians', 'apply 20% discount', 'show my cart', or 'clear cart'."
        };
    }

    // ============================================
    // HELPER METHODS - MESSAGES
    // ============================================
    
    /**
     * Add welcome message to chat
     */
    _addWelcomeMessage() {
        const welcomeMsg = {
            id: `msg-${++this._messageIdCounter}`,
            text: "Hello! I'm your AI Quote Assistant. I can help you build quotes using natural language. What would you like to do?",
            isBot: true,
            isUser: false,
            isWelcome: true,
            timestamp: this._formatTimestamp(new Date()),
            wrapperClass: 'message-wrapper bot',
            avatarClass: 'message-avatar bot-avatar',
            bubbleClass: 'message-bubble bot-bubble'
        };
        this.messages = [welcomeMsg];
    }

    /**
     * Add a message to the chat
     * @param {string} text - Message text
     * @param {string} from - 'user' or 'bot'
     * @param {string} action - Optional action badge
     */
    _addMessage(text, from, action = null) {
        const isBot = from === 'bot';
        const isUser = from === 'user';

        const message = {
            id: `msg-${++this._messageIdCounter}`,
            text: text,
            isBot: isBot,
            isUser: isUser,
            isWelcome: false,
            timestamp: this._formatTimestamp(new Date()),
            wrapperClass: `message-wrapper ${from}`,
            avatarClass: `message-avatar ${from}-avatar`,
            bubbleClass: `message-bubble ${from}-bubble`,
            actionBadge: action && action !== 'NONE' && action !== 'CLARIFY' ? action.replace('_', ' ') : null,
            actionBadgeClass: action ? `action-badge-pill ${action.toLowerCase().replace('_', '-')}` : ''
        };

        this.messages = [...this.messages, message];
    }

    /**
     * Parse AI response JSON
     * @param {string} rawJson - Raw JSON string from Gemini
     * @returns {Object} Parsed response object
     */
    _parseAIResponse(rawJson) {
        // Handle case where response might have markdown code blocks
        let cleanJson = rawJson;
        
        // Remove markdown code blocks if present
        const jsonMatch = rawJson.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (jsonMatch) {
            cleanJson = jsonMatch[1].trim();
        }
        
        // Try to extract JSON object
        const objectMatch = cleanJson.match(/\{[\s\S]*\}/);
        if (objectMatch) {
            cleanJson = objectMatch[0];
        }

        return JSON.parse(cleanJson);
    }

    // ============================================
    // HELPER METHODS - CART
    // ============================================
    
    /**
     * Recalculate cart totals
     */
    _recalculateCartTotals() {
        let subtotal = 0;
        let discountTotal = 0;

        // Update line totals and calculate totals
        this.cartItems = this.cartItems.map(item => {
            const grossAmount = item.quantity * item.unitPrice;
            const discountAmount = grossAmount * ((item.discountPercent || 0) / 100);
            const lineTotal = grossAmount - discountAmount;

            subtotal += grossAmount;
            discountTotal += discountAmount;

            return {
                ...item,
                lineTotal: lineTotal,
                formattedLineTotal: this._formatCurrency(lineTotal),
                formattedUnitPrice: this._formatCurrency(item.unitPrice),
                hasDiscount: (item.discountPercent || 0) > 0
            };
        });

        this.cartTotals = {
            subtotal: subtotal,
            discountTotal: discountTotal,
            grandTotal: subtotal - discountTotal
        };
    }

    /**
     * Find product by name (fuzzy matching)
     * @param {string} name - Product name to search
     * @returns {Object|null} Matched product or null
     */
    _findProductByName(name) {
        if (!name || !this.availableProducts || this.availableProducts.length === 0) {
            return null;
        }

        const searchTerm = name.toLowerCase();

        // Exact match
        let match = this.availableProducts.find(p => 
            p.name && p.name.toLowerCase() === searchTerm
        );

        // Partial match
        if (!match) {
            match = this.availableProducts.find(p => 
                (p.name && p.name.toLowerCase().includes(searchTerm)) ||
                (p.productCode && p.productCode.toLowerCase().includes(searchTerm))
            );
        }

        // Keyword match
        if (!match) {
            const keywords = searchTerm.split(/\s+/);
            match = this.availableProducts.find(p => 
                p.name && keywords.some(kw => p.name.toLowerCase().includes(kw))
            );
        }

        return match;
    }

    // ============================================
    // HELPER METHODS - UI
    // ============================================
    
    /**
     * Format timestamp for display
     * @param {Date} date - Date to format
     * @returns {string} Formatted time string
     */
    _formatTimestamp(date) {
        return date.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    /**
     * Format currency value
     * @param {number} value - Value to format
     * @returns {string} Formatted currency string
     */
    _formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2
        }).format(value || 0);
    }

    /**
     * Scroll chat container to bottom
     */
    _scrollToBottom() {
        const container = this.template.querySelector('[data-id="messagesContainer"]');
        if (container) {
            // Use requestAnimationFrame for smooth scrolling
            requestAnimationFrame(() => {
                container.scrollTop = container.scrollHeight;
            });
        }
    }

    /**
     * Auto-resize textarea based on content
     * @param {HTMLTextAreaElement} textarea - Textarea element
     */
    _autoResizeTextarea(textarea) {
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
    }

    /**
     * Show toast notification
     * @param {string} title - Toast title
     * @param {string} message - Toast message
     * @param {string} variant - Toast variant (success, error, warning, info)
     */
    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    /**
     * Dispatch cart update event to parent component
     */
    _dispatchCartUpdate() {
        this.dispatchEvent(new CustomEvent('cartupdate', {
            detail: {
                cart: this.cartItems,
                totals: this.cartTotals
            }
        }));
    }

    // ============================================
    // PUBLIC API METHODS
    // ============================================
    
    /**
     * Get current cart state
     * @returns {Array} Cart items array
     */
    @api
    getCart() {
        return [...this.cartItems];
    }

    /**
     * Set cart state
     * @param {Array} items - Cart items to set
     */
    @api
    setCart(items) {
        this.cartItems = items || [];
        this._recalculateCartTotals();
    }

    /**
     * Get cart totals
     * @returns {Object} Cart totals object
     */
    @api
    getCartTotals() {
        return { ...this.cartTotals };
    }

    /**
     * Programmatically send a message
     * @param {string} message - Message to send
     */
    @api
    sendMessage(message) {
        if (message) {
            this.inputValue = message;
            this.handleSendMessage();
        }
    }
}