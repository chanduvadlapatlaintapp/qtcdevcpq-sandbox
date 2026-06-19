/**
 * @description Visualforce controller for the OSA PDF template.
 *              Queries quote and quote line data and computes quantity deltas
 *              for display in the generated PDF document.
 * @author AgenticQTC Team
 * @date 2026-03-30
 */
public with sharing class AgenticQTC_OsaTemplateController {
    public String quoteName { get; set; }
    public String accountName { get; set; }
    public String contractNumber { get; set; }
    public String amendmentDate { get; set; }
    public List<LineItem> quoteLines { get; set; }

    public AgenticQTC_OsaTemplateController() {
        String quoteId = ApexPages.currentPage().getParameters().get('quoteId');
        this.quoteLines = new List<LineItem>();

        if (String.isBlank(quoteId)) {
            this.quoteName = '';
            this.accountName = '';
            this.contractNumber = '';
            this.amendmentDate = String.valueOf(Date.today());
            return;
        }

        // BUG FIX #7: Added WITH SECURITY_ENFORCED to enforce field-level and
        // object-level security, preventing data exposure to users without access.
        SBQQ__Quote__c quote = [
            SELECT Id, Name, SBQQ__StartDate__c,
                   SBQQ__Account__r.Name,
                   SBQQ__MasterContract__r.ContractNumber
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        this.quoteName = quote.Name;
        this.accountName = quote.SBQQ__Account__r != null ? quote.SBQQ__Account__r.Name : '';
        this.contractNumber = quote.SBQQ__MasterContract__r != null ? quote.SBQQ__MasterContract__r.ContractNumber : '';
        this.amendmentDate = quote.SBQQ__StartDate__c != null ? String.valueOf(quote.SBQQ__StartDate__c) : String.valueOf(Date.today());

        // BUG FIX #7 (continued): WITH SECURITY_ENFORCED on quote lines query.
        // BUG FIX #10: Added LIMIT 500 to prevent governor limit violations on large quotes.
        for (SBQQ__QuoteLine__c line : [
            SELECT SBQQ__ProductName__c, SBQQ__Quantity__c, SBQQ__PriorQuantity__c,
                   SBQQ__ListPrice__c, SBQQ__NetPrice__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY SBQQ__Number__c
            LIMIT 500
        ]) {
            LineItem item = new LineItem();
            item.productName = line.SBQQ__ProductName__c;

            Decimal newQty = line.SBQQ__Quantity__c != null ? line.SBQQ__Quantity__c : 0;
            Decimal priorQty = line.SBQQ__PriorQuantity__c != null ? line.SBQQ__PriorQuantity__c : 0;

            item.quantity = String.valueOf(newQty.setScale(0).intValue());
            item.priorQuantity = String.valueOf(priorQty.setScale(0).intValue());

            Decimal delta = newQty - priorQty;
            item.isChanged = delta != 0;
            if (delta > 0) {
                item.qtyChange = '+' + String.valueOf(delta.setScale(0).intValue());
            } else if (delta < 0) {
                item.qtyChange = String.valueOf(delta.setScale(0).intValue());
            } else {
                item.qtyChange = 'No change';
            }

            item.listPrice = line.SBQQ__ListPrice__c != null ? line.SBQQ__ListPrice__c.setScale(2).toPlainString() : '0.00';
            item.netPrice = line.SBQQ__NetPrice__c != null ? line.SBQQ__NetPrice__c.setScale(2).toPlainString() : '0.00';
            this.quoteLines.add(item);
        }
    }

    public class LineItem {
        public String productName { get; set; }
        public String quantity { get; set; }
        public String priorQuantity { get; set; }
        public String listPrice { get; set; }
        public String netPrice { get; set; }
        public String qtyChange { get; set; }
        public Boolean isChanged { get; set; }
    }
}