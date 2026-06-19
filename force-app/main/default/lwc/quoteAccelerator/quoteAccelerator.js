import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class QuoteAccelerator extends LightningElement {
    @api quoteId;
    @api recordId;
    
    // Header properties
    @track dealTitle = 'Proposed 2-year deal';
    @track dealStandard = 90;
    @track clientName = 'Latham';
    @track currentPeriod = '2024-25';
    @track proposedTermYears = 2;
    @track year1Period = 'October 2024';
    @track year2Period = 'October 2025';
    
    // Totals
    @track currentTotal = '$2.9M';
    @track year1Total = '$3.9M';
    @track year2Total = '$4.0M';
    
    // Approval levels configuration
    @track approvalLevels = [
        { id: 1, label: 'Level 1 - Approved', class: 'approval-dot approved' },
        { id: 2, label: 'Level 2 - Pending', class: 'approval-dot pending' },
        { id: 3, label: 'Level 3 - Not Required', class: 'approval-dot not-required' }
    ];
    
    // Quote line items - Sample data matching Figma design
    @track quoteLines = [
        {
            id: '1',
            productName: 'Conflicts, Intake, Walls, with Premium Support',
            currentPrice: '37.41',
            currentQuantity: '3600',
            currentACV: '1,346,760',
            year1Price: '43.78',
            year1Quantity: '3600',
            year1ACV: '1,891,080',
            year2Price: '44.71',
            year2Quantity: '3600',
            year2ACV: '1,931,482',
            quantityUnit: 'Lawyers'
        },
        {
            id: '2',
            productName: 'Terms with Standard Support',
            currentPrice: '7.35',
            currentQuantity: '3600',
            currentACV: '264,600',
            year1Price: '7.94',
            year1Quantity: '3600',
            year1ACV: '343,800',
            year2Price: '8.14',
            year2Quantity: '3600',
            year2ACV: '351,738',
            quantityUnit: 'Lawyers'
        },
        {
            id: '3',
            productName: 'Time with Premium Support',
            currentPrice: '20.27',
            currentQuantity: '3600',
            currentACV: '729,720',
            year1Price: '23.89',
            year1Quantity: '3600',
            year1ACV: '1,032,120',
            year2Price: '24.40',
            year2Quantity: '3600',
            year2ACV: '1,054,011',
            quantityUnit: 'Lawyers'
        },
        {
            id: '4',
            productName: 'Integrate with Standard Support',
            currentPrice: '1.03',
            currentQuantity: '3600',
            currentACV: '37,088',
            year1Price: '1.69',
            year1Quantity: '3600',
            year1ACV: '73,088',
            year2Price: '1.75',
            year2Quantity: '3600',
            year2ACV: '75,685',
            quantityUnit: 'Lawyers'
        },
        {
            id: '5',
            productName: 'Workspaces + IIS Essentials with Standard Support',
            currentPrice: '4.36',
            currentQuantity: '7000',
            currentACV: '533,932',
            year1Price: '6.36',
            year1Quantity: '7750',
            year1ACV: '591,145',
            year2Price: '6.80',
            year2Quantity: '7750',
            year2ACV: '632,518',
            quantityUnit: 'Named Users'
        }
    ];
    
    // Summary notes
    @track summaryNotes = [
        {
            id: '1',
            text: 'Adjustment from 3000 lawyers to 3600 lawyers for October 2024 and October 2025, resulting a $962K uplift per year, with year 2 base uplifted by 3%'
        },
        {
            id: '2',
            text: 'Adjustment from 7000 to 7750 named users for Workspaces and IIS Essentials - pro rata increase'
        }
    ];

    @wire(CurrentPageReference)
    getPageReference(pageRef) {
        if (pageRef && pageRef.state) {
            // Extract quote ID from URL if available
            if (pageRef.state.c__quoteid) {
                this.quoteId = pageRef.state.c__quoteid;
            }
        }
    }

    connectedCallback() {
        // Use recordId if quoteId is not set
        if (!this.quoteId && this.recordId) {
            this.quoteId = this.recordId;
        }
        // Initialize component - in real implementation, fetch data from Apex
        this.loadQuoteData();
    }

    loadQuoteData() {
        // In production, this would call an Apex method to fetch quote data
        // For now, using sample data that matches the Figma design
        console.log('Quote Accelerator initialized with quoteId:', this.quoteId);
    }

    // Computed property for Deal Standard color class
    get dealStandardClass() {
        if (this.dealStandard >= 100) {
            return 'deal-standard excellent';
        } else if (this.dealStandard >= 80) {
            return 'deal-standard good';
        }
        return 'deal-standard needs-review';
    }

    // Format currency values
    formatCurrency(value) {
        if (!value) return '$0';
        const num = parseFloat(value.toString().replace(/,/g, ''));
        if (num >= 1000000) {
            return '$' + (num / 1000000).toFixed(1) + 'M';
        } else if (num >= 1000) {
            return '$' + (num / 1000).toFixed(0) + 'K';
        }
        return '$' + num.toFixed(2);
    }

    // Calculate totals from quote lines
    calculateTotals() {
        let currentSum = 0;
        let year1Sum = 0;
        let year2Sum = 0;

        this.quoteLines.forEach(line => {
            currentSum += parseFloat(line.currentACV.replace(/,/g, '')) || 0;
            year1Sum += parseFloat(line.year1ACV.replace(/,/g, '')) || 0;
            year2Sum += parseFloat(line.year2ACV.replace(/,/g, '')) || 0;
        });

        this.currentTotal = this.formatCurrency(currentSum);
        this.year1Total = this.formatCurrency(year1Sum);
        this.year2Total = this.formatCurrency(year2Sum);
    }

    // Public method to update quote lines from external source
    @api
    updateQuoteLines(newLines) {
        if (newLines && Array.isArray(newLines)) {
            this.quoteLines = newLines.map((line, index) => ({
                ...line,
                id: line.id || String(index + 1)
            }));
            this.calculateTotals();
        }
    }

    // Public method to update header information
    @api
    updateHeader(headerData) {
        if (headerData) {
            this.dealTitle = headerData.dealTitle || this.dealTitle;
            this.dealStandard = headerData.dealStandard || this.dealStandard;
            this.clientName = headerData.clientName || this.clientName;
            this.currentPeriod = headerData.currentPeriod || this.currentPeriod;
            this.year1Period = headerData.year1Period || this.year1Period;
            this.year2Period = headerData.year2Period || this.year2Period;
        }
    }

    // Public method to update summary notes
    @api
    updateSummaryNotes(notes) {
        if (notes && Array.isArray(notes)) {
            this.summaryNotes = notes.map((note, index) => ({
                id: String(index + 1),
                text: typeof note === 'string' ? note : note.text
            }));
        }
    }
}