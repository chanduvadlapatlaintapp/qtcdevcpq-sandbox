import { LightningElement, api, track, wire } from 'lwc';
import processNaturalLanguageQuery from '@salesforce/apex/AIQuoteAssistantController.processNaturalLanguageQuery';
import getProducts from '@salesforce/apex/AIQuoteAssistantController.getProducts';

export default class AiQuoteAssistant extends LightningElement {
    @api quoteId;
    @api isDarkMode = false;
    
    @track messages = [];
    @track userInput = '';
    @track isTyping = false;
    @track isCollapsed = true;
    @track cart = [];
    @track availableProducts = [];
    
    messageIdCounter = 0;

    // Welcome suggestions list
    welcomeSuggestions = [
        'Add 5 Intapp DealCloud',
        'Add 10 Intapp Documents with 20% discount',
        'Add Intapp Terms'
    ];

    // Quick action buttons
    quickActions = [
        { id: 1, text: 'Add 5 Intapp DealCloud' },
        { id: 2, text: 'Add 10 Intapp Documents with 20% discount' },
        { id: 3, text: 'Add Intapp Terms ' }
    ];

    @wire(getProducts)
    wiredProducts({ error, data }) {
        if (data) {
            this.availableProducts = data;
        } else if (error) {
            console.error('Error loading products:', error);
        }
    }

    connectedCallback() {
        // Add welcome message
        this.addWelcomeMessage();
    }

    addWelcomeMessage() {
        const welcomeMessage = {
            id: this.generateMessageId(),
            text: "Hi! I'm your AI Quote Assistant. I can help you build quotes using natural language.",
            isBot: true,
            isUser: false,
            isWelcome: true,
            timestamp: this.formatTimestamp(new Date()),
            containerClass: 'message-row bot',
            messageClass: 'message bot-message'
        };
        this.messages = [welcomeMessage];
    }

    generateMessageId() {
        return `msg-${++this.messageIdCounter}-${Date.now()}`;
    }

    formatTimestamp(date) {
        return date.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            second: '2-digit',
            hour12: true
        });
    }

    get wrapperClass() {
        let classes = 'assistant-wrapper';
        if (this.isCollapsed) classes += ' collapsed';
        return classes;
    }

    get containerClass() {
        let classes = 'ai-assistant-container';
        if (this.isDarkMode) classes += ' dark-mode';
        if (this.isCollapsed) classes += ' collapsed';
        return classes;
    }

    get collapseIcon() {
        return this.isCollapsed ? 'utility:chevronleft' : 'utility:chevronright';
    }

    get isSendDisabled() {
        return !this.userInput || this.userInput.trim() === '' || this.isTyping;
    }

    handleInputChange(event) {
        this.userInput = event.detail.value || event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (!this.isSendDisabled) {
                this.handleSendMessage();
            }
        }
    }

    handleQuickAction(event) {
        const actionText = event.currentTarget.dataset.action;
        this.userInput = actionText;
        this.handleSendMessage();
    }

    async handleSendMessage() {
        if (this.isSendDisabled) return;

        const userText = this.userInput.trim();
        this.userInput = '';

        // Add user message
        const userMessage = {
            id: this.generateMessageId(),
            text: userText,
            isBot: false,
            isUser: true,
            isWelcome: false,
            timestamp: this.formatTimestamp(new Date()),
            containerClass: 'message-row user',
            messageClass: 'message user-message'
        };
        this.messages = [...this.messages, userMessage];
        
        // Scroll to bottom
        this.scrollToBottom();

        // Show typing indicator
        this.isTyping = true;

        try {
            // Process with AI
            const response = await processNaturalLanguageQuery({
                userMessage: userText,
                quoteId: this.quoteId,
                cartDataJson: JSON.stringify(this.cart)
            });

            // Parse AI response
            const aiResponse = this.parseAIResponse(response);
            
            // Execute action if applicable
            this.executeAction(aiResponse);

            // Add bot response
            const botMessage = {
                id: this.generateMessageId(),
                text: aiResponse.message || response,
                isBot: true,
                isUser: false,
                isWelcome: false,
                hasCartSummary: aiResponse.action === 'GET_SUMMARY' && this.cart.length > 0,
                cartItems: this.cart,
                timestamp: this.formatTimestamp(new Date()),
                containerClass: 'message-row bot',
                messageClass: 'message bot-message'
            };
            this.messages = [...this.messages, botMessage];

        } catch (error) {
            console.error('Error processing message:', error);
            
            // Fallback to local processing if API fails
            const localResponse = this.processLocalCommand(userText);
            
            const botMessage = {
                id: this.generateMessageId(),
                text: localResponse.message,
                isBot: true,
                isUser: false,
                isWelcome: false,
                hasCartSummary: localResponse.action === 'GET_SUMMARY' && this.cart.length > 0,
                cartItems: this.cart,
                timestamp: this.formatTimestamp(new Date()),
                containerClass: 'message-row bot',
                messageClass: 'message bot-message'
            };
            this.messages = [...this.messages, botMessage];
        }

        this.isTyping = false;
        this.scrollToBottom();
        
        // Dispatch event to parent component
        this.dispatchEvent(new CustomEvent('cartupdate', {
            detail: { cart: this.cart }
        }));
    }

    parseAIResponse(response) {
        try {
            // Try to parse as JSON
            const jsonMatch = response.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                return JSON.parse(jsonMatch[0]);
            }
            return { action: 'NONE', message: response };
        } catch (e) {
            return { action: 'NONE', message: response };
        }
    }

    executeAction(aiResponse) {
        const action = aiResponse.action;
        const params = aiResponse.parameters || {};

        switch (action) {
            case 'ADD_PRODUCT':
                this.addToCart(params);
                break;
            case 'REMOVE_PRODUCT':
                this.removeFromCart(params.productId);
                break;
            case 'UPDATE_QUANTITY':
                this.updateQuantity(params.productId, params.quantity);
                break;
            case 'APPLY_DISCOUNT':
                this.applyDiscount(params.discountPercent, params.applyTo);
                break;
            case 'CLEAR_CART':
                this.clearCart();
                break;
            default:
                break;
        }
    }

    processLocalCommand(userText) {
        const text = userText.toLowerCase();
        
        // Clear cart
        if (text.includes('clear cart') || text.includes('empty cart') || text.includes('remove all')) {
            this.clearCart();
            return {
                action: 'CLEAR_CART',
                message: "Done! I've cleared your cart. Ready to start fresh!"
            };
        }

        // Apply discount
        const discountMatch = text.match(/(\d+)%?\s*discount/);
        if (discountMatch) {
            const discount = parseInt(discountMatch[1]);
            this.applyDiscount(discount, 'all');
            return {
                action: 'APPLY_DISCOUNT',
                message: `Applied ${discount}% discount to all items in your cart.`
            };
        }

        // Add products - parse quantity and product name
        const addMatch = text.match(/add\s+(\d+)?\s*(.*?)(?:\s+for\s+|$)/i);
        if (addMatch || text.includes('add')) {
            const quantity = addMatch && addMatch[1] ? parseInt(addMatch[1]) : 1;
            const productHint = addMatch && addMatch[2] ? addMatch[2].trim() : text.replace(/add\s*/i, '').trim();
            
            // Find matching product
            const matchedProduct = this.findProduct(productHint);
            
            if (matchedProduct) {
                console.log('AI Assistant: Found product to add:', matchedProduct.name, 'ID:', matchedProduct.id);
                this.addToCart({
                    productName: matchedProduct.name,
                    productId: matchedProduct.id,
                    quantity: quantity
                });
                return {
                    action: 'ADD_PRODUCT',
                    message: `Added ${quantity} x ${matchedProduct.name} to your cart.`
                };
            } else {
                return {
                    action: 'CLARIFY',
                    message: `I couldn't find a product matching "${productHint}". Could you try being more specific or check the product name?`
                };
            }
        }

        // Get summary
        if (text.includes('summary') || text.includes('show cart') || text.includes('what\'s in')) {
            return {
                action: 'GET_SUMMARY',
                message: this.cart.length > 0 
                    ? `Your cart has ${this.cart.length} item(s). Here's the summary:`
                    : 'Your cart is empty. Try adding some products!'
            };
        }

        // Default response
        return {
            action: 'NONE',
            message: "I understand you want to work with quotes. Try commands like 'add 5 technicians', 'apply 20% discount', or 'clear cart'."
        };
    }

    findProduct(hint) {
        const searchTerm = hint.toLowerCase();
        
        // First try exact match
        let match = this.availableProducts.find(p => 
            p.name.toLowerCase() === searchTerm ||
            (p.productCode && p.productCode.toLowerCase() === searchTerm)
        );
        
        if (!match) {
            // Try partial match
            match = this.availableProducts.find(p => 
                p.name.toLowerCase().includes(searchTerm) ||
                searchTerm.includes(p.name.toLowerCase()) ||
                (p.productCode && p.productCode.toLowerCase().includes(searchTerm))
            );
        }

        // If still no match, try fuzzy matching on keywords
        if (!match) {
            const keywords = searchTerm.split(/\s+/);
            match = this.availableProducts.find(p => 
                keywords.some(kw => p.name.toLowerCase().includes(kw))
            );
        }

        return match;
    }

    addToCart(params) {
        const existingIndex = this.cart.findIndex(item => item.productId === params.productId);
        
        if (existingIndex >= 0) {
            // Update quantity
            const updatedCart = [...this.cart];
            updatedCart[existingIndex] = {
                ...updatedCart[existingIndex],
                quantity: updatedCart[existingIndex].quantity + (params.quantity || 1)
            };
            this.cart = updatedCart;
        } else {
            // Add new item
            this.cart = [...this.cart, {
                id: `cart-${Date.now()}`,
                productId: params.productId,
                name: params.productName,
                quantity: params.quantity || 1,
                discount: 0
            }];
        }
    }

    removeFromCart(productId) {
        this.cart = this.cart.filter(item => item.productId !== productId);
    }

    updateQuantity(productId, quantity) {
        this.cart = this.cart.map(item => 
            item.productId === productId 
                ? { ...item, quantity: quantity }
                : item
        );
    }

    applyDiscount(discountPercent, applyTo) {
        if (applyTo === 'all') {
            this.cart = this.cart.map(item => ({
                ...item,
                discount: discountPercent
            }));
        } else {
            this.cart = this.cart.map(item => 
                item.productId === applyTo
                    ? { ...item, discount: discountPercent }
                    : item
            );
        }
    }

    clearCart() {
        this.cart = [];
    }

    handleClearChat() {
        this.messages = [];
        this.addWelcomeMessage();
    }

    handleToggleCollapse() {
        this.isCollapsed = !this.isCollapsed;
    }

    scrollToBottom() {
        // Use setTimeout to ensure DOM has updated
        setTimeout(() => {
            const container = this.template.querySelector('[data-id="chatContainer"]');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 0);
    }

    // Public method to get current cart
    @api
    getCart() {
        return this.cart;
    }

    // Public method to set cart
    @api
    setCart(cartItems) {
        this.cart = cartItems || [];
    }
}