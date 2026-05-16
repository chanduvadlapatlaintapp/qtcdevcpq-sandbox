import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveProducts from '@salesforce/apex/GuidedSellingController.getActiveProducts';
import createQuoteLines from '@salesforce/apex/GuidedSellingController.createQuoteLines';
import calculateDealQualityScoreWithBreakdown from '@salesforce/apex/GuidedSellingController.calculateDealQualityScoreWithBreakdown';
import getQuoteLines from '@salesforce/apex/GuidedSellingController.getQuoteLines';
import updateQuoteMonths from '@salesforce/apex/GuidedSellingController.updateQuoteMonths';
export default class GuidedSelling extends NavigationMixin(LightningElement) {
    @api quoteId; // Accept quoteId from parent component
    _isDarkMode = false; // Internal tracking
    
    @api 
    get isDarkMode() {
        return this._isDarkMode;
    }
    set isDarkMode(value) {
        this._isDarkMode = value;
    }
    
    _firstSegmentMonths = 12; // Internal tracking
    _totalContractMonths = 12; // Internal tracking
    
    @api 
    get firstSegmentMonths() {
        return this._firstSegmentMonths;
    }
    set firstSegmentMonths(value) {
        const oldValue = this._firstSegmentMonths;
        this._firstSegmentMonths = value;
        // Sync Year 1 if it hasn't been manually modified
        if (oldValue !== value && this.rampItems && this.rampItems.length > 0) {
            this.syncYear1WithFirstSegmentMonths();
        }
    }
    
    @api 
    get totalContractMonths() {
        return this._totalContractMonths;
    }
    set totalContractMonths(value) {
        this._totalContractMonths = value;
    }
    @api startDate; // Start date from parent component
    @api showCartOnly = false; // If true, show only cart step (for main page display)
    
    @track allProducts = [];
    @track filteredProducts = [];
    @track selectedCategory = null;
    @track cart = [];
    @track showAddToCartMessage = false;
    @track addedProductId = null;
    @track searchTerm = '';
    @api currentStep = 'products'; // 'products', 'ramp', or 'cart'
    @track rampItems = []; // Cart items with additional Ramp fields
    @track promotionsItems = []; // Items with promotions applied
    @track cartItems = []; // Final cart items
    @track promotionSearchTerm = '';
    @track promotionSortValue = 'name-asc';
    @track appliedPromotions = [];
    @track isLoading = false;
    @track dealQualityScore = null;
    @track dealQualityScoreBreakdown = null;
    @track isCalculatingScore = false;
    
    // Track pending AI cart syncs (in case sync is called before products load)
    // Use array to queue multiple syncs instead of overwriting
    pendingAICartSyncs = [];

    // Sample promotions data - replace with actual Apex call
    @track availablePromotions = [
        { id: '1', name: '2024-09_01-BO-6freemonths-competitive', description: 'Pricing offer for existing customers on Build Ops OR potential customers who are also thinking of using BuildOps instead ...', discountType: 'Percent', discountAmount: 100, duration: 6, isApplied: false },
        { id: '2', name: '2024-09-01-TRANE-AS-50off-core+pro', description: 'Trane and American Standard (AS) customers take a meeting starting in August 2024 and sign by August 31, 2025, to...', discountType: 'Percent', discountAmount: 50, duration: 3, isApplied: false },
        { id: '3', name: '2024-09-01-TRANE-AS-50off-pro-standalone', description: 'Existing Trane and American Standard (AS) customers take a meeting starting in August 2024 and sign by August 31, 202...', discountType: 'Percent', discountAmount: 50, duration: 3, isApplied: false },
        { id: '4', name: '2025-02_01-3mofree-sales', description: 'Up to 3 Free Months of SeviceTitan when signing up', discountType: 'Dollars', discountAmount: 100, duration: 1, isApplied: false },
        { id: '5', name: '2025-03_01-6mos_50%off-sales', description: 'Evergreen promotion to offer up to 6 months at 50% off or any equivalent of 3 months free.', discountType: 'Percent', discountAmount: 50, duration: 6, isApplied: false },
        { id: '6', name: '2025-03_2026-01-3mofree-bd-mpa', description: 'Offering 3 months free to any member of Master Plumbers Association (Queensland or New South Wales) in Australia.', discountType: 'Percent', discountAmount: 100, duration: 3, isApplied: false },
        { id: '7', name: '2025-03-01-FERGUSON-50off-suppliers', description: 'Ferguson customers take a meeting starting in March 2025 and sign by March 31, 2026, to receive 50% off the first 6...', discountType: 'Percent', discountAmount: 50, duration: 6, isApplied: false },
        { id: '8', name: '2025-06-_abc-3mofree-bd', description: 'First 3 months of ServiceTitan are free for ABC Members when they sign up (ABC tech marketplace offer)', discountType: 'Percent', discountAmount: 100, duration: 3, isApplied: false },
        { id: '9', name: '2025-08-_csp-2mofree-bd', description: '2 months free for Core subscriptions referred to ServiceTitan through the Channel Sales Partnership program.', discountType: 'Percent', discountAmount: 100, duration: 2, isApplied: false },
        { id: '10', name: '2025-08-01-1mofree-proproduct', description: '1 Free month of subscription when signing up for a new pro product. Eligible Products include MP, PBP, Scheduling Pro,...', discountType: 'Percent', discountAmount: 100, duration: 1, isApplied: false },
        { id: '11', name: '2025-08-01-2mofree-proproduct', description: '2 Free months of subscription if signing for a new pro prod annual contract. Products include MP, PBP, Scheduling Pro,...', discountType: 'Percent', discountAmount: 100, duration: 2, isApplied: false }
    ];

    @track categories = [
        { id: 'all', name: 'All Products', categoryName: null, isActive: true, className: 'category-item active' }
    ];

    // Dynamic month indices based on totalContractMonths
    get monthIndices() {
        const totalMonths = parseInt(this.totalContractMonths, 10) || 12;
        return Array.from({ length: totalMonths }, (_, i) => i);
    }

    connectedCallback() {
        // Initialize dark mode from prop
        if (this.isDarkMode !== undefined) {
            this._isDarkMode = this.isDarkMode;
        }
        // Set "All Products" as default selected category
        const allProductsCategory = this.categories.find(cat => cat.id === 'all');
        if (allProductsCategory) {
            this.selectedCategory = {
                id: allProductsCategory.id,
                name: allProductsCategory.name,
                categoryName: allProductsCategory.categoryName
            };
        }
        
        // If showCartOnly is true, load existing quote lines into cart
        if (this.showCartOnly && this.quoteId) {
            this.loadExistingQuoteLines();
        }
    }

    /**
     * @description Loads existing quote lines from the quote and converts them to cartItems format
     */
    async loadExistingQuoteLines() {
        if (!this.quoteId) {
            return;
        }

        try {
            const quoteLines = await getQuoteLines({ quoteId: this.quoteId });
            
            if (!quoteLines || quoteLines.length === 0) {
                this.cartItems = [];
                return;
            }

            // Group quote lines by product
            const productMap = new Map();
            
            quoteLines.forEach(line => {
                const productId = line.SBQQ__Product__c;
                if (!productMap.has(productId)) {
                    productMap.set(productId, {
                        Id: productId,
                        Name: line.SBQQ__Product__r ? line.SBQQ__Product__r.Name : 'Unknown Product',
                        ProductCode: line.SBQQ__Product__r ? line.SBQQ__Product__r.ProductCode : '',
                        quantity: line.SBQQ__Quantity__c || 1,
                        years: [],
                        isExpanded: true,
                        expandIcon: 'utility:chevrondown',
                        isExisting: true // Mark as existing quote line
                    });
                }
                
                const product = productMap.get(productId);
                
                // Convert quote line to year format
                const yearNumber = product.years.length + 1;
                const listPriceTotal = line.SBQQ__ListPrice__c || 0; // Total list price for period
                const netPriceTotal = line.SBQQ__NetPrice__c || 0;   // Total net price for period
                const overrideSalePricePerMonth = line.Override_Sales_Price_Per_Month__c || null;
                
                // Calculate months from pricing (approximate)
                const months = overrideSalePricePerMonth && overrideSalePricePerMonth > 0 
                    ? Math.round(netPriceTotal / overrideSalePricePerMonth)
                    : 12;
                
                // Calculate monthly list price (unitPrice should be monthly)
                const unitPricePerMonth = months > 0 ? listPriceTotal / months : listPriceTotal;
                
                // Calculate discount based on monthly prices
                const effectiveOverrideSalePricePerMonth = overrideSalePricePerMonth || (months > 0 ? netPriceTotal / months : netPriceTotal);
                const discount = unitPricePerMonth > 0 ? ((unitPricePerMonth - effectiveOverrideSalePricePerMonth) / unitPricePerMonth) * 100 : 0;
                
                // Calculate total price: (Override Sale Price Per Month * Months * Quantity) - One Time Credit
                const oneTimeCredit = 0;
                const totalPrice = Math.max(0, (effectiveOverrideSalePricePerMonth * months * product.quantity) - oneTimeCredit);
                
                product.years.push({
                    yearNumber: yearNumber,
                    months: months,
                    startMonth: 1,
                    endMonth: months,
                    discount: discount.toFixed(2),
                    overrideSalePricePerMonth: effectiveOverrideSalePricePerMonth.toFixed(2),
                    unitPrice: unitPricePerMonth.toFixed(2), // Monthly list price
                    netPrice: netPriceTotal.toFixed(2),      // Total net price for period
                    totalPrice: totalPrice.toFixed(2),
                    oneTimeCredit: oneTimeCredit,
                    hasPromo: false,
                    promoLabel: '',
                    hasSalesVpRate: discount >= 100,
                    hasGvpRate: false,
                    hasManagerRate: false,
                    periodLabel: `Year ${yearNumber} - ${months} months`
                });
            });

            // Convert map to array
            this.cartItems = Array.from(productMap.values());
            
            // Set current step to cart
            this.currentStep = 'cart';
            
            // Calculate deal quality score
            await this.calculateDealQualityScore();
        } catch (error) {
            console.error('Error loading existing quote lines:', error);
            this.showToast('Error', 'Failed to load existing quote lines', 'error');
        }
    }

    // Helper method to create delays using Promise (LWC-compliant alternative to setTimeout)
    delay(ms) {
        return new Promise(resolve => {
            const start = Date.now();
            const checkTime = () => {
                if (Date.now() - start >= ms) {
                    resolve();
                } else {
                    // Use Promise.resolve().then() which is allowed in LWC
                    Promise.resolve().then(checkTime);
                }
            };
            Promise.resolve().then(checkTime);
        });
    }

    renderedCallback() {
        // Sync internal dark mode state when prop changes
        if (this._isDarkMode !== this.isDarkMode) {
            this._isDarkMode = this.isDarkMode;
        }
        
        // Manually apply/remove dark mode class to ensure DOM updates
        const container = this.template.querySelector('.guided-selling-container');
        if (container) {
            if (this._isDarkMode) {
                container.classList.add('dark-mode');
            } else {
                container.classList.remove('dark-mode');
            }
            
            if (this.showCartOnly) {
                container.classList.add('cart-only-mode');
            } else {
                container.classList.remove('cart-only-mode');
            }
        }
    }

    get containerClass() {
        // Use internal state for reactivity
        const darkMode = this._isDarkMode;
        let classes = darkMode ? 'guided-selling-container dark-mode' : 'guided-selling-container';
        if (this.showCartOnly) {
            classes += ' cart-only-mode';
        }
        return classes;
    }

    // Get total months for timeline - use dynamic calculation from ramp items if available, otherwise use static value
    get timelineMonthCount() {
        // If we're on the ramp step and have ramp items, calculate dynamically
        if (this.currentStep === 'ramp' && this.rampItems && this.rampItems.length > 0) {
            const maxEndMonth = Math.max(...this.rampItems.map(item => {
                if (item.years && item.years.length > 0) {
                    return Math.max(...item.years.map(year => year.endMonth || 0));
                }
                return 0;
            }), 0);
            // Use the maximum of calculated end month or the static totalContractMonths
            return Math.max(maxEndMonth, parseInt(this.totalContractMonths, 10) || 12);
        }
        return parseInt(this.totalContractMonths, 10) || 12;
    }

    // Get month labels with dates - dynamic based on totalContractMonths
    get monthLabels() {
        const totalMonths = this.timelineMonthCount;
        const indices = Array.from({ length: totalMonths }, (_, i) => i);
        
        if (!this.startDate) {
            return indices.map(idx => ({
                index: idx,
                monthNumber: idx + 1,
                label: `M${idx + 1}`,
                dateLabel: `M${idx + 1}`
            }));
        }
        
        const start = new Date(this.startDate);
        const monthNames = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
        
        return indices.map(idx => {
            const monthDate = new Date(start.getFullYear(), start.getMonth() + idx, start.getDate());
            const day = monthDate.getDate();
            const monthName = monthNames[monthDate.getMonth()];
            return {
                index: idx,
                monthNumber: idx + 1,
                label: `M${idx + 1}`,
                dateLabel: `${day} ${monthName}`
            };
        });
    }

    @wire(getActiveProducts, { quoteId: '$quoteId' })
    wiredProducts({ error, data }) {
        if (data) {
            // Process products and extract categories
            this.allProducts = data.map(product => {
                // Access Practice__c from the relationship
                let practiceValue = null;
                
                if (product.Product_LineNew__r) {
                    practiceValue = product.Product_LineNew__r.Practice__c;
                }
                
                return {
                    ...product,
                    quantity: 1,
                    inCart: false,
                    category: practiceValue
                };
            });
            
            // Extract distinct categories from Product_LineNew__r.Practice__c
            const categorySet = new Set();
            this.allProducts.forEach(product => {
                const cat = product.category;
                if (cat && String(cat).trim() !== '' && String(cat) !== 'null' && String(cat) !== 'undefined') {
                    categorySet.add(String(cat).trim());
                }
            });
            
            const categoryArray = Array.from(categorySet).sort();
            
            // Calculate count for "All Products"
            const allProductsCount = this.allProducts.length;
            
            // Build categories list: "All Products" + distinct Product_LineNew__r.Practice__c values
            const newCategories = [
                { id: 'all', name: 'All Products', categoryName: null, isActive: true, className: 'category-item active', count: allProductsCount }
            ];
            
            // Add practice categories with counts
            categoryArray.forEach((catName, index) => {
                // Count products in this category
                const categoryCount = this.allProducts.filter(product => 
                    product.category && String(product.category).trim() === String(catName).trim()
                ).length;
                
                newCategories.push({
                    id: `category-${index}`,
                    name: String(catName),
                    categoryName: String(catName),
                    isActive: false,
                    className: 'category-item',
                    count: categoryCount
                });
            });
            
            // Force reactivity by creating new array reference
            this.categories = [...newCategories];
            
            // Optimize: Create product lookup map for O(1) access
            this._productMap = new Map(this.allProducts.map(p => [p.Id, p]));
            
            this.updateProductCartStatus();
            // Apply filters after products are loaded to show all products by default
            this.applyFilters();
            
            // Process any pending AI cart syncs now that products are loaded
            if (this.pendingAICartSyncs && this.pendingAICartSyncs.length > 0) {
                // Process all queued syncs in order
                this.pendingAICartSyncs.forEach(aiCart => {
                    this.processAICartSync(aiCart);
                });
                // Clear the queue after processing
                this.pendingAICartSyncs = [];
            }
        } else if (error) {
            console.error('Error fetching products:', error);
        }
    }

    handleCategoryClick(event) {
        const categoryId = event.currentTarget.dataset.categoryId;
        const category = this.categories.find(cat => cat.id === categoryId);
        
        if (category) {
            // Reset all categories and update className
            this.categories = this.categories.map(cat => ({
                ...cat,
                isActive: cat.id === categoryId,
                className: cat.id === categoryId ? 'category-item active' : 'category-item'
            }));
            
            // Create a new object to ensure reactivity
            this.selectedCategory = {
                id: category.id,
                name: category.name,
                categoryName: category.categoryName
            };
            
            // Force reactivity
            this.selectedCategory = {...this.selectedCategory};
            
            console.log('Category clicked:', category.name, 'CategoryName:', category.categoryName);
            this.applyFilters();
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.applyFilters();
    }

    applyFilters() {
        if (!this.allProducts || this.allProducts.length === 0) {
            this.filteredProducts = [];
            return;
        }

        // Optimize: Create Set of cart IDs once for O(1) lookups instead of O(n) some() checks
        const cartIds = new Set(this.cart.map(item => item.Id));

        let filtered = this.allProducts;

        // Apply category filter based on Product_LineNew__r.Practice__c
        if (this.selectedCategory && this.selectedCategory.categoryName) {
            filtered = filtered.filter(product => {
                return product.category === this.selectedCategory.categoryName;
            });
        }
        // If "All Products" is selected, show all products (no category filter)

        // Apply search filter
        if (this.searchTerm && this.searchTerm.trim() !== '') {
            const searchLower = this.searchTerm.toLowerCase().trim();
            filtered = filtered.filter(product => {
                const nameMatch = product.Name && product.Name.toLowerCase().includes(searchLower);
                const codeMatch = product.ProductCode && product.ProductCode.toLowerCase().includes(searchLower);
                const descMatch = product.Description && product.Description.toLowerCase().includes(searchLower);
                return nameMatch || codeMatch || descMatch;
            });
        }

        // Optimize: Use Set lookup instead of some() for O(1) vs O(n) performance
        const addedProductId = this.addedProductId;
        this.filteredProducts = filtered.map(product => ({
            ...product,
            inCart: cartIds.has(product.Id), // O(1) lookup instead of O(n) some()
            isAdded: addedProductId === product.Id
        }));
    }

    handleQuantityChange(event) {
        const productId = event.target.dataset.productId;
        const quantity = parseInt(event.target.value, 10);
        
        const product = this.allProducts.find(p => p.Id === productId);
        if (product) {
            product.quantity = quantity;
            // Update in filtered products as well
            const filteredProduct = this.filteredProducts.find(p => p.Id === productId);
            if (filteredProduct) {
                filteredProduct.quantity = quantity;
            }
        }
    }

    handleIncreaseQuantity(event) {
        const productId = event.currentTarget.dataset.productId;
        const product = this.allProducts.find(p => p.Id === productId);
        
        if (product) {
            product.quantity = (product.quantity || 1) + 1;
            // Update in filtered products as well
            const filteredProduct = this.filteredProducts.find(p => p.Id === productId);
            if (filteredProduct) {
                filteredProduct.quantity = product.quantity;
            }
            // Force reactivity
            this.allProducts = [...this.allProducts];
            this.filteredProducts = [...this.filteredProducts];
        }
    }

    handleDecreaseQuantity(event) {
        const productId = event.currentTarget.dataset.productId;
        const product = this.allProducts.find(p => p.Id === productId);
        
        if (product && product.quantity > 1) {
            product.quantity = product.quantity - 1;
            // Update in filtered products as well
            const filteredProduct = this.filteredProducts.find(p => p.Id === productId);
            if (filteredProduct) {
                filteredProduct.quantity = product.quantity;
            }
            // Force reactivity
            this.allProducts = [...this.allProducts];
            this.filteredProducts = [...this.filteredProducts];
        }
    }

    updateProductCartStatus() {
        // Optimize: Only update if we have products
        if (!this.allProducts || this.allProducts.length === 0) {
            return;
        }
        
        const cartIds = new Set(this.cart.map(item => item.Id));
        
        // Check if any products need updating to avoid unnecessary re-renders
        let needsUpdate = false;
        for (let i = 0; i < this.allProducts.length; i++) {
            const shouldBeInCart = cartIds.has(this.allProducts[i].Id);
            if (this.allProducts[i].inCart !== shouldBeInCart) {
                needsUpdate = true;
                break;
            }
        }
        
        if (needsUpdate) {
            this.allProducts = this.allProducts.map(product => ({
                ...product,
                inCart: cartIds.has(product.Id)
            }));
            // Update filtered products as well
            this.applyFilters();
        }
    }

    handleAddToCart(event) {
        const productId = event.currentTarget?.dataset?.productId || event.target?.dataset?.productId;
        
        if (!productId) {
            console.error('No product ID found in event');
            return;
        }
        
        // Optimize: Use a Map for O(1) lookups instead of find() which is O(n)
        // Create product lookup map if it doesn't exist
        if (!this._productMap) {
            this._productMap = new Map(this.allProducts.map(p => [p.Id, p]));
        }
        
        const product = this._productMap.get(productId) || this.allProducts.find(p => p.Id === productId);
        
        if (!product) {
            console.error('Product not found in allProducts for ID:', productId);
            this.showToast('Error', 'Product not found. Please try again.', 'error');
            return;
        }
        
        // Optimize: Update cart immediately for instant UI feedback
        const existingIndex = this.cart.findIndex(item => item.Id === productId);
        
        if (existingIndex >= 0) {
            // Update existing item - create new array for reactivity
            const updatedCart = [...this.cart];
            updatedCart[existingIndex] = {
                ...updatedCart[existingIndex],
                quantity: product.quantity || 1
            };
            this.cart = updatedCart;
        } else {
            // Add new item - use push with spread for better performance
            this.cart = [...this.cart, {
                ...product,
                quantity: product.quantity || 1
            }];
        }
        
        // Show success message immediately - don't wait for other operations
        this.showAddToCartMessage = true;
        this.addedProductId = productId;
        
        // Optimize: Update only the affected product in allProducts
        const productIndex = this.allProducts.findIndex(p => p.Id === productId);
        if (productIndex >= 0 && !this.allProducts[productIndex].inCart) {
            this.allProducts[productIndex] = {
                ...this.allProducts[productIndex],
                inCart: true
            };
            // Force reactivity
            this.allProducts = [...this.allProducts];
        }
        
        // Update only the affected product in filteredProducts
        const filteredIndex = this.filteredProducts.findIndex(p => p.Id === productId);
        if (filteredIndex >= 0) {
            this.filteredProducts[filteredIndex] = {
                ...this.filteredProducts[filteredIndex],
                inCart: true,
                isAdded: true
            };
            // Force reactivity
            this.filteredProducts = [...this.filteredProducts];
        }
        
        // Hide add to cart message after delay
        this.delay(3000).then(() => {
            this.showAddToCartMessage = false;
            this.addedProductId = null;
            
            // Update isAdded property only for the specific product
            const filteredIndexToUpdate = this.filteredProducts.findIndex(p => p.Id === productId);
            if (filteredIndexToUpdate >= 0) {
                this.filteredProducts[filteredIndexToUpdate] = {
                    ...this.filteredProducts[filteredIndexToUpdate],
                    isAdded: false
                };
                // Force reactivity
                this.filteredProducts = [...this.filteredProducts];
            }
        });
    }

    handleRemoveFromCart(event) {
        const productId = event.currentTarget.dataset.productId;
        this.cart = this.cart.filter(item => item.Id !== productId);
        console.log('Product removed from cart, cart length:', this.cart.length);
        this.updateProductCartStatus();
    }

    handleRemoveFromProductList(event) {
        const productId = event.currentTarget.dataset.productId;
        this.cart = this.cart.filter(item => item.Id !== productId);
        this.updateProductCartStatus();
        this.showAddToCartMessage = false;
        this.addedProductId = null;
    }

    get cartTotal() {
        return this.cart ? this.cart.length : 0;
    }

    get isProductsStep() {
        return this.currentStep === 'products';
    }

    get isRampStep() {
        return this.currentStep === 'ramp';
    }

    get isPromotionsStep() {
        return this.currentStep === 'promotions';
    }

    get isCartStep() {
        return this.currentStep === 'cart';
    }

    get showCartTotalAndScore() {
        return this.currentStep === 'cart';
    }

    get cartTotalPrice() {
        let total = 0;
        if (this.cartItems && this.cartItems.length > 0) {
            this.cartItems.forEach(item => {
                if (item.years && item.years.length > 0) {
                    item.years.forEach(year => {
                        total += parseFloat(year.totalPrice) || 0;
                    });
                }
            });
        }
        return total;
    }

    get formattedCartTotal() {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(this.cartTotalPrice);
    }

    get isAllProductsCategory() {
        return this.selectedCategory && (this.selectedCategory.id === 'all' || this.selectedCategory.name === 'All Products');
    }

    get currentMonth() {
        return new Date().getMonth() + 1; // 1-12
    }

    get currentYear() {
        return new Date().getFullYear();
    }

    getMonthName(monthIndex) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[monthIndex - 1];
    }

    get productsStepClass() {
        let classes = 'progress-step';
        if (this.currentStep === 'products') {
            classes += ' active';
        }
        return classes;
    }

    get rampStepClass() {
        let classes = 'progress-step';
        if (this.currentStep === 'ramp') {
            classes += ' active';
        } else if (this.currentStep === 'cart') {
            classes += ' completed';
        }
        return classes;
    }

    get promotionsStepClass() {
        let classes = 'progress-step';
        if (this.currentStep === 'promotions') {
            classes += ' active';
        } else if (this.currentStep === 'cart') {
            classes += ' completed';
        }
        return classes;
    }

    get cartStepClass() {
        let classes = 'progress-step';
        if (this.currentStep === 'cart') {
            classes += ' active';
        }
        return classes;
    }

    get startMonthLabel() {
        return `${this.getMonthName(this.currentMonth)} ${this.currentYear}`;
    }

    get isCartEmpty() {
        return this.cart.length === 0;
    }

    get isProductsCompleted() {
        return ['ramp', 'cart'].includes(this.currentStep);
    }

    get isRampCompleted() {
        return this.currentStep === 'cart';
    }

    get isPromotionsCompleted() {
        return this.currentStep === 'cart';
    }

    get isNextDisabled() {
        // Don't disable button in cart-only mode (it's not shown anyway)
        if (this.showCartOnly) {
            return false;
        }
        
        if (this.currentStep === 'products') {
            // Access cart length to ensure reactivity - check both cart and cartItems
            const cartLength = (this.cart && Array.isArray(this.cart)) ? this.cart.length : 0;
            const hasItems = cartLength > 0;
            console.log('isNextDisabled - products step, cart.length:', cartLength, 'hasItems:', hasItems);
            return !hasItems;
        }
        if (this.currentStep === 'ramp') {
            return false; // Always enabled on ramp step
        }
        if (this.currentStep === 'cart') {
            return this.isLoading || !this.cartItems || this.cartItems.length === 0;
        }
        return false;
    }

    get nextButtonLabel() {
        if (this.currentStep === 'cart') {
            return this.isLoading ? 'Saving...' : 'Save & Finish';
        }
        return 'Save & Next';
    }

    getEndMonthLabel(months) {
        const endMonth = (this.currentMonth + months - 1) % 12 || 12;
        const endYear = this.currentYear + Math.floor((this.currentMonth + months - 2) / 12);
        return `${this.getMonthName(endMonth)} ${endYear}`;
    }

    // Calculate years and months per year based on firstSegmentMonths and totalContractMonths
    calculateYearMonths() {
        const firstSegment = parseInt(this._firstSegmentMonths, 10) || 12;
        const totalMonths = parseInt(this._totalContractMonths, 10) || 12;
        
        const years = [];
        let remainingMonths = totalMonths;
        
        // Year 1: Use firstSegmentMonths exactly (no 12-month cap, but respect totalMonths)
        const year1Months = Math.min(firstSegment, remainingMonths);
        years.push({
            yearNumber: 1,
            months: year1Months,
            maxMonths: totalMonths, // Allow up to total contract months
            isManuallyModified: false, // Track if Year 1 has been manually modified
            isYear1: true, // Flag to identify Year 1 in template
            durationBarClass: 'duration-bar' // CSS class for the bar
        });
        remainingMonths -= year1Months;
        
        // Subsequent years: 12 months each (or remaining months if less)
        let yearNumber = 2;
        while (remainingMonths > 0) {
            const yearMonths = Math.min(12, remainingMonths);
            years.push({
                yearNumber: yearNumber,
                months: yearMonths,
                maxMonths: 12,
                isYear1: false, // Not Year 1
                durationBarClass: 'duration-bar read-only-bar' // Read-only class
            });
            remainingMonths -= yearMonths;
            yearNumber++;
        }
        
        return years;
    }

    async handleNext() {
        console.log('handleNext called, currentStep:', this.currentStep, 'cart.length:', this.cart.length);
        try {
            if (this.currentStep === 'products') {
                if (!this.cart || this.cart.length === 0) {
                    // Show error message - cart is empty
                    this.showToast('Error', 'Please add at least one product to the cart before proceeding', 'error');
                    return;
                }
                
                console.log('Moving from products to ramp, cart items:', this.cart.length);
                
                // Calculate years based on firstSegmentMonths and totalContractMonths
                const yearMonths = this.calculateYearMonths();
                console.log('Calculated yearMonths:', yearMonths);
                
                // Initialize Ramp items with cart data and year-based months
                const totalMonths = this.timelineMonthCount;
                this.rampItems = this.cart.map(item => {
                // Calculate years with start positions
                let cumulativeMonths = 0;
                const years = yearMonths.map(year => {
                    const startMonth = cumulativeMonths + 1; // 1-based month index
                    const endMonth = cumulativeMonths + year.months;
                    // Calculate bar position and width (percentage based on totalContractMonths)
                    const barLeft = ((startMonth - 1) / totalMonths) * 100;
                    const barWidth = (year.months / totalMonths) * 100;
                    const yearObj = {
                        ...year,
                        months: year.months,
                        startMonth: startMonth,
                        endMonth: endMonth,
                        discount: 0,
                        barStyle: `left: ${barLeft}%; width: ${barWidth}%;`,
                        isYear1: year.yearNumber === 1, // Flag to identify Year 1 in template
                        durationBarClass: year.yearNumber === 1 ? 'duration-bar' : 'duration-bar read-only-bar' // CSS class for the bar
                    };
                    cumulativeMonths += year.months;
                    return yearObj;
                });
                
                return {
                    ...item,
                    discount: 0,
                    years: years,
                    totalMonths: yearMonths.reduce((sum, year) => sum + year.months, 0)
                };
            });
            
            console.log('Setting currentStep to ramp, rampItems:', this.rampItems.length);
            this.currentStep = 'ramp';
            console.log('Current step after update:', this.currentStep);
        } else if (this.currentStep === 'ramp') {
            // Move directly to Cart step - prepare cart items with pricing details
            // Use rampItems which contains all the year/ramp data
            this.cartItems = this.rampItems.map(item => {
                // Ensure years array exists and has data
                const itemYears = item.years || [];
                
                // Calculate period labels and pricing for each year/ramp
                const yearsWithPricing = itemYears.map(year => {
                    const startDate = this.startDate ? new Date(this.startDate) : new Date();
                    const startMonthDate = new Date(startDate.getFullYear(), startDate.getMonth() + (year.startMonth - 1), 1);
                    const endMonthDate = new Date(startDate.getFullYear(), startDate.getMonth() + (year.endMonth - 1), 1);
                    
                    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                    const periodLabel = `${monthNames[startMonthDate.getMonth()]}-${monthNames[endMonthDate.getMonth()]} - ${year.months} months`;
                    
                    // Pricing calculation - unitPrice is MONTHLY list price
                    const months = year.months || 12;
                    const unitPricePerMonth = 833.33; // Sample monthly list price (replace with actual pricing logic)
                    const unitPrice = unitPricePerMonth.toFixed(2); // Monthly list price
                    const discountAmount = year.discount || 0;
                    
                    // Net price is the total for the period after discount
                    // Net Price = Monthly List Price * Months * (1 - Discount%)
                    const netPrice = (unitPricePerMonth * months * (1 - discountAmount / 100)).toFixed(2);
                    const oneTimeCredit = year.oneTimeCredit || 0;
                    
                    // Override sale price per month (initially same as list price with discount applied)
                    const overrideSalePricePerMonth = (unitPricePerMonth * (1 - discountAmount / 100)).toFixed(2);
                    
                    // Calculate total price: (Override Sale Price Per Month * Months * Quantity) - One Time Credit
                    const totalPrice = Math.max(0, (parseFloat(overrideSalePricePerMonth) * months * (item.quantity || 1)) - oneTimeCredit).toFixed(2);
                    
                    // Check for applied promotions
                    const appliedPromo = this.appliedPromotions.length > 0 ? this.appliedPromotions[0] : null;
                    const hasPromo = appliedPromo && year.yearNumber === 1 && discountAmount > 0;
                    const promoLabel = hasPromo ? `${appliedPromo.discountAmount}% | ${appliedPromo.duration} Mo` : '';
                    
                    // Random approval flags for demonstration
                    const hasGvpRate = Math.random() > 0.6; // 40% chance
                    const hasManagerRate = Math.random() > 0.6; // 40% chance
                    
                    return {
                        yearNumber: year.yearNumber,
                        months: months,
                        startMonth: year.startMonth,
                        endMonth: year.endMonth,
                        discount: year.discount || 0,
                        overrideSalePricePerMonth: parseFloat(overrideSalePricePerMonth),
                        oneTimeCredit: oneTimeCredit,
                        maxMonths: year.maxMonths,
                        barStyle: year.barStyle,
                        periodLabel,
                        unitPrice, // Monthly list price
                        netPrice,  // Total for period after discount
                        totalPrice, // Final total after quantity and credits
                        hasPromo,
                        promoLabel,
                        hasSalesVpRate: discountAmount === 100,
                        hasGvpRate: hasGvpRate,
                        hasManagerRate: hasManagerRate
                    };
                });
                
                return {
                    ...item,
                    years: yearsWithPricing,
                    isExpanded: true,
                    expandIcon: 'utility:chevrondown'
                };
            });
            this.currentStep = 'cart';
            // Calculate deal quality score when moving to cart step
            await this.calculateDealQualityScore();
        } else if (this.currentStep === 'cart') {
            // Create quote lines and redirect to Quote record
            this.saveQuoteLines();
        }
        } catch (error) {
            console.error('Error in handleNext:', error);
            console.error('Error stack:', error.stack);
            this.showToast('Error', 'An error occurred while proceeding: ' + (error.message || 'Unknown error'), 'error');
        }
    }

    /**
     * @description Calculates the Deal Quality Score based on cart data
     */
    async calculateDealQualityScore() {
        if (!this.quoteId || !this.cartItems || this.cartItems.length === 0) {
            this.dealQualityScore = null;
            this.dealQualityScoreBreakdown = null;
            return;
        }

        this.isCalculatingScore = true;

        try {
            // Calculate formula fields from cart data
            const quoteData = this.calculateQuoteFieldsFromCart();

            // Call Apex method to calculate score with breakdown
            const result = await calculateDealQualityScoreWithBreakdown({
                quoteId: this.quoteId,
                quoteData: JSON.stringify(quoteData)
            });

            this.dealQualityScore = result.score;
            this.dealQualityScoreBreakdown = result.breakdown;
        } catch (error) {
            console.error('Error calculating deal quality score:', error);
            this.dealQualityScore = null;
            this.dealQualityScoreBreakdown = null;
        } finally {
            this.isCalculatingScore = false;
        }
    }

    /**
     * @description Calculates quote fields from cart items for deal quality score
     * Based on QTC_QCP.ts logic: Segment totals use calculateTotalPrice and calculateNetTotal
     * Year totals use calculateAnnualizedValue (which annualizes based on months)
     * @returns {Object} Quote data object with calculated fields
     */
    calculateQuoteFieldsFromCart() {
        const quoteData = {};

        // Calculate Segment_Total_List_Unit_Price__c and Segment_Total_Net_unit_Price__c
        // These are sums of list totals and net totals for all software products
        let segmentTotalListPrice = 0;
        let segmentTotalNetPrice = 0;

        // Calculate year totals for Min_year_on_year_committed_spend__c
        // These use annualized values (price * 12 / months) for each year
        const yearTotals = {
            year1: 0,
            year2: 0,
            year3: 0,
            year4: 0,
            year5: 0,
            year6: 0
        };

        this.cartItems.forEach(item => {
            if (item.years && item.years.length > 0) {
                item.years.forEach(year => {
                    // unitPrice and netPrice are already total prices for the year period
                    // totalPrice = netPrice * quantity (already calculated in cart)
                    const unitPrice = parseFloat(year.unitPrice) || 0;
                    const netPrice = parseFloat(year.netPrice) || 0;
                    const totalPrice = parseFloat(year.totalPrice) || 0;
                    const quantity = parseFloat(item.quantity) || 1;
                    const months = year.months || 12;

                    // Segment totals: sum of list totals and net totals
                    // List total = unit price * quantity (unitPrice is per-year-period price)
                    // Net total = net price * quantity OR use totalPrice if available
                    const listTotal = unitPrice * quantity;
                    const netTotal = totalPrice > 0 ? totalPrice : (netPrice * quantity);

                    segmentTotalListPrice += listTotal;
                    segmentTotalNetPrice += netTotal;

                    // Year totals: annualized values (net total * 12 / months)
                    // This matches calculateAnnualizedValue logic from QTC_QCP.ts
                    // numerator = netPrice * quantity, then annualize by * 12 / months
                    const annualizedValue = months > 0 ? (netTotal * 12) / months : 0;

                    // Sum totals by year for YoY calculation
                    if (year.yearNumber === 1) {
                        yearTotals.year1 += annualizedValue;
                    } else if (year.yearNumber === 2) {
                        yearTotals.year2 += annualizedValue;
                    } else if (year.yearNumber === 3) {
                        yearTotals.year3 += annualizedValue;
                    } else if (year.yearNumber === 4) {
                        yearTotals.year4 += annualizedValue;
                    } else if (year.yearNumber === 5) {
                        yearTotals.year5 += annualizedValue;
                    } else if (year.yearNumber === 6) {
                        yearTotals.year6 += annualizedValue;
                    }
                });
            }
        });

        quoteData.Segment_Total_List_Unit_Price__c = segmentTotalListPrice;
        quoteData.Segment_Total_Net_unit_Price__c = segmentTotalNetPrice;
        quoteData.First_Year_Software_Total__c = yearTotals.year1;
        quoteData.Second_Year_Software_Total__c = yearTotals.year2;
        quoteData.Third_Year_Software_Total__c = yearTotals.year3;
        quoteData.Fourth_Year_Software_Total__c = yearTotals.year4;
        quoteData.Fifth_Year_Software_Total__c = yearTotals.year5;
        quoteData.Sixth_Year_Software_Total__c = yearTotals.year6;

        // Note: Other fields like SFA_Cap_after_Initial_Term__c, SFA_Term__c, etc.
        // should be retrieved from the quote record or set by user input
        // For now, we'll let Apex fetch them from the quote record

        return quoteData;
    }

    get dealQualityScoreClass() {
        if (this.dealQualityScore === null) {
            return 'deal-quality-score-value';
        }
        if (this.dealQualityScore >= 110) {
            return 'deal-quality-score-value score-excellent';
        }
        if (this.dealQualityScore >= 100) {
            return 'deal-quality-score-value score-good';
        }
        return 'deal-quality-score-value score-poor';
    }

    async saveQuoteLines() {
        if (!this.quoteId) {
            this.showToast('Error', 'Quote ID is missing', 'error');
            return;
        }

        if (!this.cartItems || this.cartItems.length === 0) {
            this.showToast('Error', 'No items in cart to save', 'error');
            return;
        }

        this.isLoading = true;

        try {
            // Prepare cart items data for Apex
            const cartItemsData = this.cartItems.map(item => ({
                Id: item.Id,
                Name: item.Name,
                quantity: item.quantity || 1,
                years: item.years || []
            }));

            const cartItemsJson = JSON.stringify(cartItemsData);

            // Call Apex method to create quote lines
            // Note: Apex method only accepts quoteId and cartItemsJson parameters
            const result = await createQuoteLines({
                quoteId: this.quoteId,
                cartItemsJson: cartItemsJson
            });

            // Show success message
            this.showToast('Success', result.message || result, 'success');

            // Dispatch event with created quote line IDs to parent
            if (result.createdQuoteLineIds && result.createdQuoteLineIds.length > 0) {
                this.dispatchEvent(new CustomEvent('quotelinescreated', {
                    detail: {
                        createdQuoteLineIds: result.createdQuoteLineIds
                    },
                    bubbles: true,
                    composed: true
                }));
            } 

            // Reset loading flag on success
            this.isLoading = false;

            // Close modal and let parent handle navigation/refresh
            this.handleClose();
            
            // Redirect to QuoteListViewPage
            //this.navigateToQuoteListView();

        } catch (error) {
            console.error('Error creating quote lines:', error);
            this.showToast('Error', error.body?.message || error.message || 'Failed to create quote lines', 'error');
            this.isLoading = false;
        }
    }

    navigateToQuote() {
        if (!this.quoteId) {
            return;
        }

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

    navigateToQuoteListView() {
        // Check if we're in Visualforce context
        const isVisualforce = window.location.pathname.includes('/apex/') || 
                             window.top !== window || 
                             typeof sforce !== 'undefined';
        
        const quoteListViewUrl = '/apex/QuoteListViewPage';
        
        if (isVisualforce) {
            // Use window navigation for Visualforce
            if (window.top && window.top.location) {
                window.top.location.href = quoteListViewUrl;
            } else {
                window.location.href = quoteListViewUrl;
            }
        } else {
            // Use NavigationMixin for Lightning Experience
            try {
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: {
                        url: quoteListViewUrl
                    }
                });
            } catch (error) {
                // Fallback to window navigation if NavigationMixin fails
                console.error('NavigationMixin failed, using window navigation:', error);
                window.location.href = quoteListViewUrl;
            }
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    handleBack() {
        if (this.currentStep === 'ramp') {
            this.currentStep = 'products';
        } else if (this.currentStep === 'cart') {
            this.currentStep = 'ramp';
        }
    }

    handleClose() {
        // Dispatch custom event to parent component to close the modal
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }

    /**
     * Syncs Year 1 duration with firstSegmentMonths if Year 1 hasn't been manually modified
     */
    syncYear1WithFirstSegmentMonths() {
        if (!this.rampItems || this.rampItems.length === 0) {
            return;
        }

        const firstSegment = parseInt(this._firstSegmentMonths, 10) || 12;
        
        // Update Year 1 for all products if not manually modified
        this.rampItems.forEach(item => {
            if (item.years && item.years.length > 0) {
                const year1 = item.years.find(y => y.yearNumber === 1);
                if (year1 && !year1.isManuallyModified) {
                    const totalMonths = this.timelineMonthCount;
                    const maxAllowedMonths = totalMonths - year1.startMonth + 1;
                    const newMonths = Math.min(firstSegment, maxAllowedMonths);
                    
                    if (newMonths !== year1.months) {
                        year1.months = newMonths;
                        year1.endMonth = year1.startMonth + newMonths - 1;
                        
                        // Recalculate bar style
                        const barLeft = ((year1.startMonth - 1) / totalMonths) * 100;
                        const barWidth = (year1.months / totalMonths) * 100;
                        year1.barStyle = `left: ${barLeft}%; width: ${barWidth}%;`;
                        
                        // Adjust subsequent years
                        let cumulativeMonths = year1.endMonth;
                        const year1Index = item.years.indexOf(year1);
                        for (let i = year1Index + 1; i < item.years.length; i++) {
                            item.years[i].startMonth = cumulativeMonths + 1;
                            item.years[i].endMonth = cumulativeMonths + item.years[i].months;
                            const nextBarLeft = ((item.years[i].startMonth - 1) / totalMonths) * 100;
                            const nextBarWidth = (item.years[i].months / totalMonths) * 100;
                            item.years[i].barStyle = `left: ${nextBarLeft}%; width: ${nextBarWidth}%;`;
                            cumulativeMonths = item.years[i].endMonth;
                        }
                        
                        // Recalculate total months
                        item.totalMonths = item.years.reduce((sum, r) => sum + r.months, 0);
                    }
                }
            }
        });
        
        // Force reactivity
        this.rampItems = [...this.rampItems];
    }


    handleRampQuantityChange(event) {
        const productId = event.target.dataset.productId;
        const quantity = parseInt(event.target.value, 10);
        
        const item = this.rampItems.find(p => p.Id === productId);
        if (item) {
            item.quantity = quantity;
            this.rampItems = [...this.rampItems];
        }
    }

    handleRampDiscountChange(event) {
        const productId = event.target.dataset.productId;
        const discount = parseFloat(event.target.value) || 0;
        
        const item = this.rampItems.find(p => p.Id === productId);
        if (item) {
            item.discount = discount;
            this.rampItems = [...this.rampItems];
        }
    }

    handleRampMonthsChange(event) {
        const productId = event.target.dataset.productId;
        const months = parseInt(event.target.value, 10);
        
        const item = this.rampItems.find(p => p.Id === productId);
        if (item) {
            item.months = months;
            // Update end month label
            const endMonth = (this.currentMonth + months - 1) % 12 || 12;
            const endYear = this.currentYear + Math.floor((this.currentMonth + months - 2) / 12);
            item.endMonthLabel = `${this.getMonthName(endMonth)} ${endYear}`;
            this.rampItems = [...this.rampItems];
        }
    }

    handleYearMonthsChange(event) {
        const productId = event.target.dataset.productId;
        const yearNumber = parseInt(event.target.dataset.yearNumber, 10);
        
        // Only Year 1 can be modified
        if (yearNumber !== 1) {
            console.log('Cannot modify year', yearNumber, '- only Year 1 is modifiable');
            return;
        }
        
        const months = parseInt(event.target.value, 10);
        
        this.updateYearMonths(productId, yearNumber, months);
    }

    updateYearMonths(productId, yearNumber, months) {
        // Only Year 1 can be modified
        if (yearNumber !== 1) {
            console.log('Cannot modify year', yearNumber, '- only Year 1 is modifiable');
            return;
        }
        
        const item = this.rampItems.find(p => p.Id === productId);
        const totalMonths = this.timelineMonthCount;
        if (item && item.years) {
            const year = item.years.find(r => r.yearNumber === yearNumber);
            if (year) {
                // Cap months considering startMonth position to prevent exceeding timeline boundary
                // Maximum months = totalMonths - startMonth + 1 (to account for 1-based indexing)
                const maxAllowedMonths = totalMonths - year.startMonth + 1;
                year.months = Math.max(1, Math.min(maxAllowedMonths, months));
                
                // Mark Year 1 as manually modified if user changes it
                if (yearNumber === 1) {
                    year.isManuallyModified = true;
                }
                
                // Recalculate end month and adjust subsequent years
                year.endMonth = year.startMonth + year.months - 1;
                
                // Recalculate bar style based on totalContractMonths
                const barLeft = ((year.startMonth - 1) / totalMonths) * 100;
                const barWidth = (year.months / totalMonths) * 100;
                year.barStyle = `left: ${barLeft}%; width: ${barWidth}%;`;
                
                // Adjust start positions of subsequent years
                let cumulativeMonths = year.endMonth;
                const yearIndex = item.years.indexOf(year);
                for (let i = yearIndex + 1; i < item.years.length; i++) {
                    item.years[i].startMonth = cumulativeMonths + 1;
                    item.years[i].endMonth = cumulativeMonths + item.years[i].months;
                    // Recalculate bar style for subsequent years
                    const nextBarLeft = ((item.years[i].startMonth - 1) / totalMonths) * 100;
                    const nextBarWidth = (item.years[i].months / totalMonths) * 100;
                    item.years[i].barStyle = `left: ${nextBarLeft}%; width: ${nextBarWidth}%;`;
                    cumulativeMonths = item.years[i].endMonth;
                }
                
                // Recalculate total months
                item.totalMonths = item.years.reduce((sum, r) => sum + r.months, 0);
                // Force reactivity
                this.rampItems = [...this.rampItems];
                
                // Update Quote's firstSegmentMonths if this is the first year of the first product
                if (this.quoteId && yearNumber === 1) {
                    const firstProduct = this.rampItems[0];
                    if (firstProduct && firstProduct.years && firstProduct.years.length > 0) {
                        const firstYear = firstProduct.years.find(y => y.yearNumber === 1);
                        if (firstYear) {
                            updateQuoteMonths({ 
                                quoteId: this.quoteId, 
                                totalContractMonths: null,
                                firstSegmentMonths: firstYear.months 
                            }).catch(error => {
                                console.error('Error updating quote first segment months:', error);
                            });
                        }
                    }
                }
            }
        }
    }

    handleBarDragStart(event) {
        event.preventDefault();
        const handle = event.currentTarget.dataset.handle;
        const productId = event.currentTarget.dataset.productId;
        const yearNumber = parseInt(event.currentTarget.dataset.yearNumber, 10);
        
        // Only Year 1 can be modified
        if (yearNumber !== 1) {
            console.log('Cannot modify year', yearNumber, '- only Year 1 is modifiable');
            return;
        }
        
        const totalMonths = this.timelineMonthCount;
        
        const item = this.rampItems.find(p => p.Id === productId);
        if (!item || !item.years) return;
        
        const year = item.years.find(r => r.yearNumber === yearNumber);
        if (!year) return;

        // Get the timeline container for calculating positions
        const timelineRow = event.currentTarget.closest('.timeline-row');
        if (!timelineRow) return;

        const timelineRect = timelineRow.getBoundingClientRect();
        const monthWidth = timelineRect.width / totalMonths;

        const initialMouseX = event.clientX;
        const initialStartMonth = year.startMonth;
        const initialMonths = year.months;

        const handleMouseMove = (moveEvent) => {
            // Double-check: Only Year 1 can be modified
            if (yearNumber !== 1) {
                return;
            }
            
            const deltaX = moveEvent.clientX - initialMouseX;
            const deltaMonths = Math.round(deltaX / monthWidth);

            if (handle === 'right') {
                // Resize from right - change duration
                const newMonths = Math.max(1, Math.min(totalMonths - initialStartMonth + 1, initialMonths + deltaMonths));
                if (newMonths !== year.months) {
                    this.updateYearMonths(productId, yearNumber, newMonths);
                }
            } else if (handle === 'left') {
                // Resize from left - change start position and duration
                // Additional safety check: Only Year 1 can be modified
                if (yearNumber !== 1) {
                    return;
                }
                
                const newStartMonth = Math.max(1, Math.min(totalMonths, initialStartMonth + deltaMonths));
                const monthsChange = newStartMonth - initialStartMonth;
                const newMonths = Math.max(1, initialMonths - monthsChange);
                
                if (newStartMonth !== year.startMonth || newMonths !== year.months) {
                    year.startMonth = newStartMonth;
                    year.months = newMonths;
                    year.endMonth = newStartMonth + newMonths - 1;
                    
                    // Mark Year 1 as manually modified if user drags it
                    year.isManuallyModified = true;
                    
                    // Recalculate bar style based on totalContractMonths
                    const barLeft = ((year.startMonth - 1) / totalMonths) * 100;
                    const barWidth = (year.months / totalMonths) * 100;
                    year.barStyle = `left: ${barLeft}%; width: ${barWidth}%;`;
                    
                    // Force reactivity
                    this.rampItems = [...this.rampItems];
                }
            }
        };

        const handleMouseUp = () => {
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);
            
            // Update Quote's firstSegmentMonths if this is the first year of the first product
            if (this.quoteId && yearNumber === 1 && productId) {
                const firstProduct = this.rampItems.find(p => p.Id === productId);
                if (firstProduct && firstProduct.years && firstProduct.years.length > 0) {
                    const firstYear = firstProduct.years.find(y => y.yearNumber === 1);
                    if (firstYear) {
                        updateQuoteMonths({ 
                            quoteId: this.quoteId, 
                            totalContractMonths: null,
                            firstSegmentMonths: firstYear.months 
                        }).catch(error => {
                            console.error('Error updating quote first segment months:', error);
                        });
                    }
                }
            }
        };

        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);
    }

    handleYearDiscountChange(event) {
        const productId = event.target.dataset.productId;
        const yearNumber = parseInt(event.target.dataset.yearNumber, 10);
        const discount = parseFloat(event.target.value) || 0;
        
        const item = this.rampItems.find(p => p.Id === productId);
        if (item && item.years) {
            const year = item.years.find(r => r.yearNumber === yearNumber);
            if (year) {
                year.discount = discount;
                // Force reactivity
                this.rampItems = [...this.rampItems];
            }
        }
    }

    handleAddYear(event) {
        console.log('handleAddYear called');
        const productId = event.currentTarget?.dataset?.productId || event.target?.dataset?.productId;
        console.log('Product ID from event:', productId);
        console.log('rampItems length:', this.rampItems?.length);
        
        if (!productId) {
            console.error('No product ID found in event');
            return;
        }
        
        const item = this.rampItems.find(p => p.Id === productId);
        console.log('Item found:', item ? item.Name : 'NOT FOUND');
        
        if (!item) {
            console.error('Item not found in rampItems for ID:', productId);
            this.showToast('Error', 'Product not found. Please try again.', 'error');
            return;
        }
        
        // Ensure years array exists
        if (!item.years) {
            console.log('Initializing years array for item');
            item.years = [];
        }
        
        // Calculate current total months dynamically from all ramp items
        const currentTotalMonths = this.timelineMonthCount;
        const maxEndMonth = Math.max(...this.rampItems.map(rampItem => {
            if (rampItem.years && rampItem.years.length > 0) {
                return Math.max(...rampItem.years.map(year => year.endMonth || 0));
            }
            return 0;
        }), 0);
        
        // Use the maximum of current total months or max end month, with a minimum of the static totalContractMonths
        const totalMonths = Math.max(
            maxEndMonth,
            currentTotalMonths,
            parseInt(this.totalContractMonths, 10) || 12
        );
        
        console.log('Total months:', totalMonths, 'Current years:', item.years.length, 'Max end month:', maxEndMonth);
        
        // Find the last year to determine the next start month
        const lastYear = item.years.length > 0 ? item.years[item.years.length - 1] : null;
        const nextStartMonth = lastYear ? lastYear.endMonth + 1 : 1;
        const nextYearNumber = item.years.length + 1;
        
        console.log('Last year:', lastYear, 'Next start month:', nextStartMonth, 'Next year number:', nextYearNumber);
        
        // Allow adding years - we'll update totalContractMonths dynamically
        // Set a reasonable maximum limit (e.g., 120 months = 10 years) to prevent excessive years
        const absoluteMaxMonths = 120; // 10 years maximum
        
        if (nextStartMonth > absoluteMaxMonths) {
            // Cannot add more years - exceeded maximum limit
            console.log('Cannot add more years - exceeded maximum limit of', absoluteMaxMonths, 'months');
            this.showToast('Info', `Cannot add more years. Maximum limit of ${absoluteMaxMonths} months (10 years) reached.`, 'info');
            return;
        }
        
        // Default to 12 months for new year
        // Calculate based on current timeline, but allow extending beyond it
        const currentTimelineMonths = parseInt(this.totalContractMonths, 10) || 12;
        let defaultMonths = 12;
        
        // If adding would exceed current timeline, use remaining months or default to 12
        if (nextStartMonth + 11 > currentTimelineMonths) {
            // We'll extend the timeline, so use full 12 months
            defaultMonths = 12;
        } else {
            // Use remaining months in current timeline, but at least 1 month
            defaultMonths = Math.max(1, Math.min(12, currentTimelineMonths - nextStartMonth + 1));
        }
        
        // Ensure at least 1 month
        if (defaultMonths < 1) {
            defaultMonths = 1;
        }
        
        const nextEndMonth = nextStartMonth + defaultMonths - 1;
        
        // Calculate bar style - use totalMonths for positioning (will be updated dynamically)
        const effectiveTotalMonths = Math.max(totalMonths, nextEndMonth);
        const barLeft = Math.max(0, ((nextStartMonth - 1) / effectiveTotalMonths) * 100);
        const barWidth = (defaultMonths / effectiveTotalMonths) * 100;
        
        // Create new year (not Year 1, so it's not modifiable)
        const newYear = {
            yearNumber: nextYearNumber,
            months: defaultMonths,
            maxMonths: totalMonths,
            startMonth: nextStartMonth,
            endMonth: nextEndMonth,
            discount: 0,
            barStyle: `left: ${barLeft}%; width: ${barWidth}%;`,
            isYear1: false, // New years are never Year 1
            durationBarClass: 'duration-bar read-only-bar' // Set read-only class
        };
        
        console.log('Creating new year:', newYear);
        
        // Find the item index to update it properly
        const itemIndex = this.rampItems.findIndex(p => p.Id === productId);
        if (itemIndex >= 0) {
            // IMPORTANT: Store Year 1's original values BEFORE any modifications
            const originalYear1 = this.rampItems[itemIndex].years?.find(y => y.yearNumber === 1);
            const originalYear1Months = originalYear1 ? originalYear1.months : null;
            const originalYear1StartMonth = originalYear1 ? originalYear1.startMonth : null;
            const originalYear1EndMonth = originalYear1 ? originalYear1.endMonth : null;
            
            console.log('BEFORE adding year - Year 1 months:', originalYear1Months, 'startMonth:', originalYear1StartMonth, 'endMonth:', originalYear1EndMonth);
            
            // Create a new array with the updated item
            const updatedRampItems = [...this.rampItems];
            const updatedItem = {
                ...updatedRampItems[itemIndex],
                years: [...(updatedRampItems[itemIndex].years || []), newYear]
            };
            
            // CRITICAL: Restore Year 1's original values if they were modified
            if (originalYear1Months !== null) {
                const year1 = updatedItem.years.find(y => y.yearNumber === 1);
                if (year1) {
                    year1.months = originalYear1Months;
                    year1.startMonth = originalYear1StartMonth;
                    year1.endMonth = originalYear1EndMonth;
                    console.log('RESTORED Year 1 - months:', year1.months, 'startMonth:', year1.startMonth, 'endMonth:', year1.endMonth);
                }
            }
            
            // Recalculate total months
            updatedItem.totalMonths = updatedItem.years.reduce((sum, r) => sum + r.months, 0);
            
            // Calculate total contract months from all ramp items
            // First, get max end month from OTHER items (not the one we're updating)
            const otherItemsMaxEndMonth = updatedRampItems
                .filter((_, idx) => idx !== itemIndex)
                .map(rampItem => {
                    if (rampItem.years && rampItem.years.length > 0) {
                        return Math.max(...rampItem.years.map(year => year.endMonth || 0));
                    }
                    return 0;
                });
            
            // Then get max end month from the updated item (which now includes the new year)
            const updatedItemMaxEndMonth = updatedItem.years && updatedItem.years.length > 0
                ? Math.max(...updatedItem.years.map(year => year.endMonth || 0))
                : 0;
            
            // Find the maximum end month across all items
            const calculatedMaxEndMonth = Math.max(
                ...otherItemsMaxEndMonth,
                updatedItemMaxEndMonth,
                0
            );
            
            // Use the maximum end month as the total contract months
            // This ensures the timeline accommodates all years
            const newTotalContractMonths = Math.max(calculatedMaxEndMonth, nextEndMonth, parseInt(this.totalContractMonths, 10) || 12);
            
            // Recalculate bar styles for ALL years in this item using the new total contract months
            // IMPORTANT: Preserve Year 1's months exactly - don't modify them
            let cumulativeMonths = 0;
            updatedItem.years.forEach(year => {
                // Preserve Year 1's months and start position - don't modify them
                if (year.yearNumber === 1) {
                    // Keep Year 1's months, startMonth, and endMonth as-is, just recalculate bar style
                    // DO NOT modify year.months, year.startMonth, or year.endMonth
                    year.isYear1 = true; // Ensure flag is set
                    year.durationBarClass = 'duration-bar'; // Set modifiable class
                    cumulativeMonths = year.endMonth; // Use existing endMonth for positioning subsequent years
                    console.log('Year 1 preserved - months:', year.months, 'startMonth:', year.startMonth, 'endMonth:', year.endMonth);
                } else {
                    // For other years, recalculate start/end months based on previous year
                    year.isYear1 = false; // Ensure flag is set
                    year.durationBarClass = 'duration-bar read-only-bar'; // Set read-only class
                    year.startMonth = cumulativeMonths + 1;
                    year.endMonth = cumulativeMonths + year.months;
                    cumulativeMonths = year.endMonth;
                }
                
                // Recalculate bar style using new total contract months
                const yearBarLeft = ((year.startMonth - 1) / newTotalContractMonths) * 100;
                const yearBarWidth = (year.months / newTotalContractMonths) * 100;
                year.barStyle = `left: ${yearBarLeft}%; width: ${yearBarWidth}%;`;
            });
            
            // Final check: Ensure Year 1's months haven't been modified
            const finalYear1 = updatedItem.years.find(y => y.yearNumber === 1);
            if (finalYear1 && originalYear1Months !== null && finalYear1.months !== originalYear1Months) {
                console.error('ERROR: Year 1 months were modified! Restoring...');
                finalYear1.months = originalYear1Months;
                finalYear1.startMonth = originalYear1StartMonth;
                finalYear1.endMonth = originalYear1EndMonth;
                // Recalculate bar style for Year 1
                const yearBarLeft = ((finalYear1.startMonth - 1) / newTotalContractMonths) * 100;
                const yearBarWidth = (finalYear1.months / newTotalContractMonths) * 100;
                finalYear1.barStyle = `left: ${yearBarLeft}%; width: ${yearBarWidth}%;`;
            }
            
            // Update the item in the array
            updatedRampItems[itemIndex] = updatedItem;
            
            // Force reactivity by reassigning the entire array
            this.rampItems = updatedRampItems;
            
            console.log('Year added successfully. New years count:', updatedItem.years.length);
            console.log('AFTER adding year - Year 1 months:', finalYear1?.months);
            
            // Update Quote's totalContractMonths
            if (this.quoteId && newTotalContractMonths > 0) {
                updateQuoteMonths({ 
                    quoteId: this.quoteId, 
                    totalContractMonths: newTotalContractMonths,
                    firstSegmentMonths: null 
                }).catch(error => {
                    console.error('Error updating quote total contract months:', error);
                });
            }
        } else {
            console.error('Item index not found');
        }
    }

    handleDeleteYear(event) {
        const productId = event.currentTarget.dataset.productId;
        const yearNumber = parseInt(event.currentTarget.dataset.yearNumber, 10);
        
        // Year 1 cannot be deleted
        if (yearNumber === 1) {
            console.log('Cannot delete Year 1');
            this.showToast('Info', 'Year 1 cannot be deleted.', 'info');
            return;
        }
        
        const item = this.rampItems.find(p => p.Id === productId);
        const totalMonths = this.timelineMonthCount;
        
        if (item && item.years && item.years.length > 1) {
            // Remove the year
            item.years = item.years.filter(r => r.yearNumber !== yearNumber);
            
            // Renumber remaining years and recalculate positions
            let cumulativeMonths = 0;
            item.years.forEach((year, index) => {
                year.yearNumber = index + 1;
                year.isYear1 = year.yearNumber === 1; // Update flag
                year.durationBarClass = year.yearNumber === 1 ? 'duration-bar' : 'duration-bar read-only-bar'; // Update class
                year.startMonth = cumulativeMonths + 1;
                year.endMonth = cumulativeMonths + year.months;
                
                // Recalculate bar style based on totalContractMonths
                const barLeft = ((year.startMonth - 1) / totalMonths) * 100;
                const barWidth = (year.months / totalMonths) * 100;
                year.barStyle = `left: ${barLeft}%; width: ${barWidth}%;`;
                
                cumulativeMonths = year.endMonth;
            });
            
            // Recalculate total months
            item.totalMonths = item.years.reduce((sum, r) => sum + r.months, 0);
            
            // Force reactivity
            this.rampItems = [...this.rampItems];
        }
    }

    getMonthOptions() {
        const options = [];
        const currentDate = new Date();
        const currentMonth = currentDate.getMonth() + 1;
        const currentYear = currentDate.getFullYear();
        
        for (let i = 0; i < 12; i++) {
            const date = new Date(currentYear, currentMonth - 1 + i, 1);
            const month = date.getMonth() + 1;
            const year = date.getFullYear();
            options.push({
                value: i + 1,
                label: `${this.getMonthName(month)} ${year}`,
                month: month,
                year: year
            });
        }
        
        return options;
    }

    // Promotion sort options
    get promotionSortOptions() {
        return [
            { label: 'Name (A-Z)', value: 'name-asc' },
            { label: 'Name (Z-A)', value: 'name-desc' },
            { label: 'Discount (High-Low)', value: 'discount-desc' },
            { label: 'Discount (Low-High)', value: 'discount-asc' },
            { label: 'Duration (Long-Short)', value: 'duration-desc' },
            { label: 'Duration (Short-Long)', value: 'duration-asc' }
        ];
    }

    // Filtered and sorted promotions
    get filteredPromotions() {
        let promos = [...this.availablePromotions];
        
        // Apply search filter
        if (this.promotionSearchTerm && this.promotionSearchTerm.trim() !== '') {
            const searchLower = this.promotionSearchTerm.toLowerCase().trim();
            promos = promos.filter(p => 
                p.name.toLowerCase().includes(searchLower) || 
                p.description.toLowerCase().includes(searchLower)
            );
        }
        
        // Apply sorting
        switch (this.promotionSortValue) {
            case 'name-asc':
                promos.sort((a, b) => a.name.localeCompare(b.name));
                break;
            case 'name-desc':
                promos.sort((a, b) => b.name.localeCompare(a.name));
                break;
            case 'discount-desc':
                promos.sort((a, b) => b.discountAmount - a.discountAmount);
                break;
            case 'discount-asc':
                promos.sort((a, b) => a.discountAmount - b.discountAmount);
                break;
            case 'duration-desc':
                promos.sort((a, b) => b.duration - a.duration);
                break;
            case 'duration-asc':
                promos.sort((a, b) => a.duration - b.duration);
                break;
            default:
                break;
        }
        
        // Map to display format
        return promos.map(p => ({
            ...p,
            typeAmount: p.discountType === 'Percent' ? `${p.discountAmount} % Discount` : `${p.discountAmount} Dollars`,
            duration: `${p.duration} Months`,
            applyLabel: p.isApplied ? 'Applied' : 'Apply',
            cardClass: p.isApplied ? 'promo-card promo-card-applied' : 'promo-card'
        }));
    }

    handlePromotionSearchChange(event) {
        this.promotionSearchTerm = event.target.value;
    }

    handlePromotionSortChange(event) {
        this.promotionSortValue = event.detail.value;
    }

    handleViewPromoDetails(event) {
        const promoId = event.currentTarget.dataset.promoId;
        // TODO: Open modal with promotion details
        console.log('View details for promotion:', promoId);
    }

    handleApplyPromotion(event) {
        const promoId = event.currentTarget.dataset.promoId;
        const promoIndex = this.availablePromotions.findIndex(p => p.id === promoId);
        
        if (promoIndex !== -1) {
            this.availablePromotions[promoIndex].isApplied = true;
            this.appliedPromotions = [...this.appliedPromotions, this.availablePromotions[promoIndex]];
            // Force reactivity
            this.availablePromotions = [...this.availablePromotions];
        }
    }

    handlePromotionToggle(event) {
        const productId = event.target.dataset.productId;
        const checked = event.target.checked;
        
        const item = this.promotionsItems.find(p => p.Id === productId);
        if (item) {
            item.promotionApplied = checked;
            if (!checked) {
                item.promotionDiscount = 0;
            }
            this.promotionsItems = [...this.promotionsItems];
        }
    }

    // Cart Step Handlers
    handleToggleProductExpand(event) {
        const productId = event.currentTarget.dataset.productId;
        const item = this.cartItems.find(p => p.Id === productId);
        if (item) {
            item.isExpanded = !item.isExpanded;
            item.expandIcon = item.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
            this.cartItems = [...this.cartItems];
        }
    }

    handleRemoveCartProduct(event) {
        const productId = event.currentTarget.dataset.productId;
        this.cartItems = this.cartItems.filter(p => p.Id !== productId);
    }

    handleConfigureYear(event) {
        const productId = event.currentTarget.dataset.productId;
        // Navigate back to Ramp step for this product
        console.log('Configure year for product:', productId);
    }

    handleRemoveYear(event) {
        const productId = event.currentTarget.dataset.productId;
        const item = this.cartItems.find(p => p.Id === productId);
        if (item && item.years && item.years.length > 1) {
            // Remove the last year
            item.years = item.years.slice(0, -1);
            this.cartItems = [...this.cartItems];
        }
    }

    handleRemovePromo(event) {
        const productId = event.currentTarget.dataset.productId;
        const item = this.cartItems.find(p => p.Id === productId);
        if (item && item.years) {
            item.years = item.years.map(year => ({
                ...year,
                hasPromo: false,
                promoLabel: '',
                hasSalesVpRate: false
            }));
            this.cartItems = [...this.cartItems];
        }
    }

    handleCartQuantityChange(event) {
        const productId = event.target.dataset.productId;
        const quantity = parseInt(event.target.value, 10) || 1;
        
        const item = this.cartItems.find(p => p.Id === productId);
        if (item) {
            item.quantity = quantity;
            // Recalculate totals: Total = (Override Sale Price Per Month * Months * Quantity) - One Time Credit
            item.years = item.years.map(year => {
                const months = year.months || 12;
                const oneTimeCredit = year.oneTimeCredit || 0;
                // Use override sale price per month, fallback to monthly list price
                const effectiveMonthlyPrice = year.overrideSalePricePerMonth && year.overrideSalePricePerMonth > 0 
                    ? year.overrideSalePricePerMonth 
                    : parseFloat(year.unitPrice);
                const totalPrice = Math.max(0, (effectiveMonthlyPrice * months * quantity) - oneTimeCredit);
                return {
                    ...year,
                    totalPrice: totalPrice.toFixed(2)
                };
            });
            this.cartItems = [...this.cartItems];
            // Recalculate deal quality score
            this.calculateDealQualityScore();
        }
    }

    handleCartOverrideSalePriceChange(event) {
        const productId = event.target.dataset.productId;
        const yearNumber = parseInt(event.target.dataset.yearNumber, 10);
        const overrideSalePricePerMonth = parseFloat(event.target.value) || 0;
        
        const item = this.cartItems.find(p => p.Id === productId);
        if (item && item.years) {
            const year = item.years.find(y => y.yearNumber === yearNumber);
            if (year) {
                year.overrideSalePricePerMonth = overrideSalePricePerMonth;
                const months = year.months || 12;
                const oneTimeCredit = year.oneTimeCredit || 0;
                const unitPricePerMonth = parseFloat(year.unitPrice) || 0;
                
                // Net price = Override Sale Price Per Month * Months
                const netPrice = (overrideSalePricePerMonth * months).toFixed(2);
                year.netPrice = netPrice;
                
                // Total price = (Override Sale Price Per Month * Months * Quantity) - One Time Credit
                const effectiveMonthlyPrice = overrideSalePricePerMonth > 0 
                    ? overrideSalePricePerMonth 
                    : unitPricePerMonth;
                year.totalPrice = Math.max(0, (effectiveMonthlyPrice * months * (item.quantity || 1)) - oneTimeCredit).toFixed(2);
                
                // Calculate discount percentage: (List Price - Override Sale Price) / List Price * 100
                if (unitPricePerMonth > 0) {
                    year.discount = ((unitPricePerMonth - overrideSalePricePerMonth) / unitPricePerMonth * 100).toFixed(2);
                } else {
                    year.discount = 0;
                }
                year.hasSalesVpRate = parseFloat(year.discount) === 100;
                this.cartItems = [...this.cartItems];
                // Recalculate deal quality score
                this.calculateDealQualityScore();
            }
        }
    }

    handleCartDiscountChange(event) {
        const productId = event.target.dataset.productId;
        const yearNumber = parseInt(event.target.dataset.yearNumber, 10);
        const discount = parseFloat(event.target.value) || 0;
        
        const item = this.cartItems.find(p => p.Id === productId);
        if (item && item.years) {
            const year = item.years.find(y => y.yearNumber === yearNumber);
            if (year) {
                const months = year.months || 12;
                const oneTimeCredit = year.oneTimeCredit || 0;
                const unitPricePerMonth = parseFloat(year.unitPrice) || 0;
                
                year.discount = discount;
                
                // Override Sale Price Per Month = List Price Per Month * (1 - Discount%)
                const overrideSalePricePerMonth = unitPricePerMonth * (1 - discount / 100);
                year.overrideSalePricePerMonth = overrideSalePricePerMonth.toFixed(2);
                
                // Net price = Override Sale Price Per Month * Months
                year.netPrice = (overrideSalePricePerMonth * months).toFixed(2);
                
                // Total price = (Override Sale Price Per Month * Months * Quantity) - One Time Credit
                year.totalPrice = Math.max(0, (overrideSalePricePerMonth * months * (item.quantity || 1)) - oneTimeCredit).toFixed(2);
                
                year.hasSalesVpRate = discount === 100;
                this.cartItems = [...this.cartItems];
                // Recalculate deal quality score
                this.calculateDealQualityScore();
            }
        }
    }

    handleCartOneTimeCreditChange(event) {
        const productId = event.target.dataset.productId;
        const yearNumber = parseInt(event.target.dataset.yearNumber, 10);
        const oneTimeCredit = parseFloat(event.target.value) || 0;
        
        const item = this.cartItems.find(p => p.Id === productId);
        if (item && item.years) {
            const year = item.years.find(y => y.yearNumber === yearNumber);
            if (year) {
                year.oneTimeCredit = oneTimeCredit;
                const months = year.months || 12;
                const unitPricePerMonth = parseFloat(year.unitPrice) || 0;
                
                // Use override sale price per month, fallback to monthly list price
                const effectiveMonthlyPrice = year.overrideSalePricePerMonth && year.overrideSalePricePerMonth > 0 
                    ? parseFloat(year.overrideSalePricePerMonth) 
                    : unitPricePerMonth;
                
                // Total price = (Effective Monthly Price * Months * Quantity) - One Time Credit
                year.totalPrice = Math.max(0, (effectiveMonthlyPrice * months * (item.quantity || 1)) - oneTimeCredit).toFixed(2);
                this.cartItems = [...this.cartItems];
                // Recalculate deal quality score
                this.calculateDealQualityScore();
            }
        }
    }

    handlePromotionDiscountChange(event) {
        const productId = event.target.dataset.productId;
        const discount = parseFloat(event.target.value) || 0;
        
        const item = this.promotionsItems.find(p => p.Id === productId);
        if (item) {
            item.promotionDiscount = discount;
            this.promotionsItems = [...this.promotionsItems];
        }
    }

    // Public method to sync cart from AI Assistant format
    @api
    syncCartFromAI(aiCart) {
        if (!aiCart || !Array.isArray(aiCart)) {
            return;
        }

        // Check if products are loaded - if not, queue the sync for later
        if (!this.allProducts || this.allProducts.length === 0) {
            // Add to queue instead of overwriting
            this.pendingAICartSyncs.push(aiCart);
            console.log(`Products not yet loaded, queuing AI cart sync (${this.pendingAICartSyncs.length} pending)`);
            return;
        }

        // Process the sync now that products are available
        this.processAICartSync(aiCart);
    }

    // Internal method to process AI cart sync (assumes products are loaded)
    processAICartSync(aiCart) {
        console.log('processAICartSync called with:', JSON.stringify(aiCart));
        
        if (!aiCart || !Array.isArray(aiCart)) {
            console.warn('processAICartSync: Invalid aiCart parameter');
            return;
        }

        // Validate that products are loaded
        if (!this.allProducts || this.allProducts.length === 0) {
            console.warn('Cannot sync AI cart: products not yet loaded');
            // Add to queue instead of overwriting
            this.pendingAICartSyncs.push(aiCart);
            return;
        }

        console.log('Available products count:', this.allProducts.length);
        console.log('Sample product IDs:', this.allProducts.slice(0, 3).map(p => p.Id));

        // If AI cart is empty (clear cart command), clear the guided selling cart
        if (aiCart.length === 0) {
            this.cart = [];
            this.updateProductCartStatus();
            console.log('Cart cleared');
            return;
        }

        // Transform AI cart items to Guided Selling format
        const updatedCart = [...this.cart];
        
        // Update existing items or add new ones from AI cart
        aiCart.forEach(aiItem => {
            console.log('Processing AI cart item:', aiItem.productId, aiItem.name);
            
            // Find the full product object from allProducts
            const product = this.allProducts.find(p => p.Id === aiItem.productId);
            
            if (product) {
                console.log('Found matching product:', product.Id, product.Name);
                // Check if product already exists in cart
                const existingIndex = updatedCart.findIndex(item => item.Id === product.Id);
                
                if (existingIndex >= 0) {
                    // Update existing item quantity
                    updatedCart[existingIndex] = {
                        ...updatedCart[existingIndex],
                        quantity: aiItem.quantity || 1
                    };
                    console.log('Updated existing cart item quantity');
                } else {
                    // Add new item with full product details
                    updatedCart.push({
                        ...product,
                        quantity: aiItem.quantity || 1
                    });
                    console.log('Added new item to cart');
                }
            } else {
                console.warn(`Product with ID ${aiItem.productId} not found in available products. Looking for ID in ${this.allProducts.length} products.`);
            }
        });

        // Remove items that were removed from AI cart (but keep items that were manually added in guided selling)
        // Only remove if they were originally added via AI (we'll track this, but for now, be conservative)
        // Actually, let's keep all manually added items and only sync AI-added items
        // This means we merge rather than replace
        
        this.cart = updatedCart;
        console.log('Cart updated, new length:', this.cart.length);
        
        // Update product cart status to reflect changes
        this.updateProductCartStatus();
    }

    // Public method to refresh component state (called when cart is cleared)
    @api
    refreshComponent() {
        // Update product cart status to reflect cleared cart
        this.updateProductCartStatus();
        
        // Reapply filters to refresh the UI
        this.applyFilters();
        
        // Reset step to products if we're still on products step
        // This ensures the UI reflects the cleared state
        if (this.currentStep === 'products') {
            // Force reactivity by updating filtered products
            this.filteredProducts = [...this.filteredProducts];
        }
        
        console.log('Guided Selling component refreshed after cart clear');
    }
}