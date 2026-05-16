/**
 * @description       : Controller for the Portfolio Analysis LWC.
 *                      Provides account search, account details, subscription
 *                      data, and NetSuite invoice enrichment for portfolio
 *                      analysis and reporting.
 * @author            : Vignesh Prabhudoss
 * Created Date       : Mar-02-2026
 * Jira               : BIZ-80262, BIZ-80292
 **/
public with sharing class PortfolioAnalysisController {

    /***********************************************************************************************
     *
     * Constants
     *
     ***********************************************************************************************/

    private static final String SHAREPOINT_BASE =
        'https://intappinc.sharepoint.com/sites/appsintegration/Shared%20Documents/OP4I%20Invoice%20Folders%20Prod/';
    private static final Integer MAX_PAGINATION_ITERATIONS = 10;

    /***********************************************************************************************
     *
     * Inner Classes / Wrappers
     *
     ***********************************************************************************************/

    /**
     * @description Wrapper for a single NetSuite invoice record returned to the LWC.
     */
    public class InvoiceRecord {
        @AuraEnabled public String invoiceId;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String osaNumber;
        @AuraEnabled public String termStartDate;
        @AuraEnabled public String termEndDate;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String sharePointUrl;
        @AuraEnabled public Decimal lineAmount;    // transactionline.foreignamount (transaction currency)
        @AuraEnabled public Decimal lineQuantity;  // transactionline.quantity
        @AuraEnabled public String itemCode;       // REPLACE(item.itemid, ' - Kit', '') — base product code
    }

    /**
     * @description Wrapper for the result of a NetSuite invoice data fetch,
     *              containing success/error metadata alongside invoice records.
     */
    public class InvoiceDataResult {
        @AuraEnabled public List<InvoiceRecord> invoices;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;

        public InvoiceDataResult() {
            this.invoices = new List<InvoiceRecord>();
            this.success = false;
            this.errorMessage = null;
        }
    }

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Searches for Client accounts by name (typeahead).
     * @param searchText The search string to match against account names.
     * @return List of matching Account records (Id, Name).
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchText) {
        if (String.isBlank(searchText) || searchText.length() < 2) {
            return new List<Account>();
        }

        String searchPattern = '%' + String.escapeSingleQuotes(searchText) + '%';

        Nebula.Logger.debug('Portfolio Analysis: Searching accounts with pattern: ' + searchPattern)
            .addTag('PortfolioAnalysis')
            .addTag('AccountSearch');
        Nebula.Logger.saveLog();

        return [
            SELECT Id, Name
            FROM Account
            WHERE Type = 'Client'
              AND Name LIKE :searchPattern
            ORDER BY Name ASC
            LIMIT 20
        ];
    }

    /**
     * @description Fetches account-level metadata fields for the portfolio header.
     * @param accountId The Salesforce Account Id.
     * @return The Account record with metadata fields, or null on failure.
     */
    @AuraEnabled
    public static Account getAccountDetails(Id accountId) {
        if (accountId == null) {
            throwAuraException('Account Id is required.');
        }

        try {
            return [
                SELECT Id, Name,
                       GTM_Motion_Tier__c,
                       Customer_Since__c,
                       Master_Terms_Contract_Number__r.ContractNumber,
                       Contract_Term_Version__c,
                       Master_Terms_CPI__c,
                       Cloud_Addendum__r.ContractNumber
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];
        } catch (Exception e) {
            Nebula.Logger.warn('Portfolio Analysis: fetchAccountDetails failed, attempting fallback', e)
                .addTag('PortfolioAnalysis')
                .addTag('AccountDetails')
                .setRecordId(accountId);
            Nebula.Logger.saveLog();

            try {
                return [
                    SELECT Id, Name
                    FROM Account
                    WHERE Id = :accountId
                    LIMIT 1
                ];
            } catch (Exception fallbackEx) {
                Nebula.Logger.error('Portfolio Analysis: fallback query also failed', fallbackEx)
                    .addTag('PortfolioAnalysis')
                    .addTag('AccountDetails')
                    .setRecordId(accountId);
                Nebula.Logger.saveLog();
                return null;
            }
        }
    }

    /**
     * @description Fetches all active subscriptions for the given account name.
     *              Filters to In Force and Partially Cancelled / Superseded statuses
     *              with segment end date >= TODAY.
     * @param accountName The exact Account Name to filter subscriptions.
     * @return List of SBQQ__Subscription__c records with all portfolio-relevant fields.
     */
    @AuraEnabled
    public static List<SBQQ__Subscription__c> getSubscriptions(String accountName) {
        if (String.isBlank(accountName)) {
            throwAuraException('Account name is required.');
        }

        String escapedName = String.escapeSingleQuotes(accountName);

        Nebula.Logger.info('Portfolio Analysis: Fetching subscriptions for account: ' + escapedName)
            .addTag('PortfolioAnalysis')
            .addTag('Subscriptions');
        Nebula.Logger.saveLog();

        return [
            SELECT Id,
                   Name,
                   SBQQ__Contract__r.OSA_Number__c,
                   SBQQ__Contract__r.CPI__c,
                   SBQQ__Contract__r.SBQQ__RenewalUpliftRate__c,
                   SBQQ__ContractNumber__c,
                   SBQQ__Contract__r.Hide_Pricing__c,
                   SBQQ__Product__r.Deployment__c,
                   SBQQ__Product__r.ProductCode,
                   SBQQ__Product__r.Name,
                   CurrencyIsoCode,
                   Per_Integrations__c,
                   SBQQ__SegmentQuantity__c,
                   Segment_Months__c,
                   Support_Level__c,
                   SBQQ__SegmentStartDate__c,
                   SBQQ__SegmentEndDate__c,
                   SBQQ__StartDate__c,
                   SBQQ__EndDate__c,
                   Contract_Status__c,
                   ACV_Change__c,
                   SBQQ__NetPrice__c,
                   SBQQ__TerminatedDate__c
            FROM SBQQ__Subscription__c
            WHERE Contract_Status__c IN ('In Force', 'Partially Cancelled / Superseded')
              AND SBQQ__Contract__r.EndDate >= TODAY
              AND SBQQ__Account__r.Name = :escapedName
              AND SBQQ__TerminatedDate__c = null
              AND SBQQ__ProductSubscriptionType__c != 'One-time'
            ORDER BY SBQQ__Contract__r.OSA_Number__c, SBQQ__SegmentStartDate__c, SBQQ__Product__r.Name
        ];
    }

    /**
     * @description Fetches invoice data from NetSuite for the given OSA numbers.
     *              Queries the transaction table via SuiteQL, matching on
     *              custbody_osa_contract_num. Computes SharePoint URLs for each invoice.
     * @param osaNumbers List of OSA numbers to query invoices for.
     * @return InvoiceDataResult containing invoice records or error info.
     */
    @AuraEnabled
    public static InvoiceDataResult getInvoiceData(List<String> osaNumbers) {
        InvoiceDataResult result = new InvoiceDataResult();

        if (osaNumbers == null || osaNumbers.isEmpty()) {
            result.errorMessage = 'OSA numbers list is required.';
            return result;
        }

        try {
            String query = buildInvoiceSuiteQLQuery(osaNumbers);
            List<Map<String, Object>> allItems = executePaginatedQuery(query);

            if (allItems == null) {
                result.errorMessage = 'NetSuite query failed. Check logs for details.';
                return result;
            }

            result.invoices = transformInvoiceItems(allItems);
            result.success = true;

            Nebula.Logger.info('Portfolio Analysis: Fetched ' + result.invoices.size() + ' invoices for ' + osaNumbers.size() + ' OSAs')
                .addTag('PortfolioAnalysis')
                .addTag('NetSuiteInvoice');
            Nebula.Logger.saveLog();

        } catch (Exception e) {
            result.errorMessage = 'Invoice data fetch failed: ' + e.getMessage();

            Nebula.Logger.error('Portfolio Analysis: getInvoiceData failed', e)
                .addTag('PortfolioAnalysis')
                .addTag('NetSuiteInvoice');
            Nebula.Logger.saveLog();
        }

        return result;
    }

    /**
     * @description Fetches subscription lines from previous contract periods for the
     *              given OSA numbers. Used for the "previous contract exception" when
     *              the current period's invoice is unpaid — traverses backward to find
     *              the most recent paid period.
     * @param accountName The exact Account Name.
     * @param osaNumbers OSA numbers to fetch previous subscriptions for.
     * @param excludeSubscriptionIds Subscription Ids already in the current dataset (to avoid duplicates).
     * @return List of SBQQ__Subscription__c records from previous contract periods.
     */
    @AuraEnabled
    public static List<SBQQ__Subscription__c> getPreviousContractSubscriptions(
        String accountName,
        List<String> osaNumbers,
        List<Id> excludeSubscriptionIds
    ) {
        if (String.isBlank(accountName)) {
            throwAuraException('Account name is required.');
        }
        if (osaNumbers == null || osaNumbers.isEmpty()) {
            return new List<SBQQ__Subscription__c>();
        }
        if (excludeSubscriptionIds == null) {
            excludeSubscriptionIds = new List<Id>();
        }

        String escapedName = String.escapeSingleQuotes(accountName);

        Nebula.Logger.info('Portfolio Analysis: Fetching previous contract subscriptions for ' + osaNumbers.size() + ' OSAs')
            .addTag('PortfolioAnalysis')
            .addTag('PreviousContract');
        Nebula.Logger.saveLog();

        return [
            SELECT Id,
                   Name,
                   SBQQ__Contract__r.OSA_Number__c,
                   SBQQ__Contract__r.CPI__c,
                   SBQQ__Contract__r.SBQQ__RenewalUpliftRate__c,
                   SBQQ__ContractNumber__c,
                   SBQQ__Contract__r.Hide_Pricing__c,
                   SBQQ__Product__r.Deployment__c,
                   SBQQ__Product__r.ProductCode,
                   SBQQ__Product__r.Name,
                   CurrencyIsoCode,
                   Per_Integrations__c,
                   SBQQ__SegmentQuantity__c,
                   Segment_Months__c,
                   Support_Level__c,
                   SBQQ__SegmentStartDate__c,
                   SBQQ__SegmentEndDate__c,
                   SBQQ__StartDate__c,
                   SBQQ__EndDate__c,
                   Contract_Status__c,
                   ACV_Change__c,
                   SBQQ__NetPrice__c,
                   SBQQ__TerminatedDate__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Contract__r.OSA_Number__c IN :osaNumbers
              AND SBQQ__SegmentEndDate__c < TODAY
              AND SBQQ__Account__r.Name = :escapedName
              AND Id NOT IN :excludeSubscriptionIds
              AND SBQQ__TerminatedDate__c = null
              AND SBQQ__ProductSubscriptionType__c != 'One-time'
            ORDER BY SBQQ__Contract__r.OSA_Number__c, SBQQ__SegmentEndDate__c DESC, SBQQ__Product__r.Name
        ];
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — NetSuite Invoice
     *
     ***********************************************************************************************/

    /**
     * @description Builds the SuiteQL SELECT query for invoices matching the given OSA numbers.
     * @param osaNumbers List of OSA numbers to include in the IN clause.
     * @return SuiteQL query string.
     */
    private static String buildInvoiceSuiteQLQuery(List<String> osaNumbers) {
        List<String> escaped = new List<String>();
        for (String osa : osaNumbers) {
            escaped.add('\'' + String.escapeSingleQuotes(osa) + '\'');
        }
        String inClause = String.join(escaped, ', ');

        return 'SELECT t.id, t.tranid, t.custbody_osa_contract_num, ' +
               't.custbody_inv_term_start_date, t.custbody_inv_term_end_date, ' +
               'BUILTIN.DF(t.status) AS statusdisplay, t.foreigntotal, ' +
               'tl.foreignamount AS lineamount, tl.quantity AS linequantity, ' +
               'REPLACE(i.itemid, \' - Kit\', \'\') AS itemcode ' +
               'FROM transaction t ' +
               'INNER JOIN transactionline tl ON tl.transaction = t.id ' +
               'LEFT JOIN item i ON i.id = tl.item ' +
               'WHERE t.type = \'CustInvc\' ' +
               'AND t.status != \'V\' ' +
               'AND tl.mainline = \'F\' ' +
               'AND t.custbody_osa_contract_num IN (' + inClause + ') ' +
               'ORDER BY t.id DESC';
    }

    /**
     * @description Executes a SuiteQL query with automatic pagination, collecting all result pages.
     *              Caps at MAX_PAGINATION_ITERATIONS to stay within governor callout limits.
     * @param query The SuiteQL query string.
     * @return Combined list of all result items, or null on failure.
     */
    private static List<Map<String, Object>> executePaginatedQuery(String query) {
        List<Map<String, Object>> allItems = new List<Map<String, Object>>();
        Integer offset = 0;
        Boolean hasMore = true;
        Integer iterations = 0;

        while (hasMore && iterations < MAX_PAGINATION_ITERATIONS) {
            NetSuiteSuiteQLService.SuiteQLResult pageResult =
                NetSuiteSuiteQLService.executeQuery(query, 1000, offset);

            if (!pageResult.success) {
                Nebula.Logger.error('Portfolio Analysis: SuiteQL page failed at offset ' + offset + ': ' + pageResult.errorMessage)
                    .addTag('PortfolioAnalysis')
                    .addTag('NetSuiteInvoice');
                Nebula.Logger.saveLog();
                return null;
            }

            allItems.addAll(pageResult.items);
            hasMore = pageResult.hasMore;
            offset += 1000;
            iterations++;
        }

        return allItems;
    }

    /**
     * @description Transforms raw SuiteQL result items into InvoiceRecord wrappers,
     *              normalizing date formats and computing SharePoint URLs.
     * @param items Raw result items from SuiteQL.
     * @return List of InvoiceRecord wrappers.
     */
    private static List<InvoiceRecord> transformInvoiceItems(List<Map<String, Object>> items) {
        List<InvoiceRecord> records = new List<InvoiceRecord>();

        for (Map<String, Object> item : items) {
            InvoiceRecord rec = new InvoiceRecord();
            rec.invoiceId = safeString(item.get('id'));
            rec.invoiceNumber = safeString(item.get('tranid'));
            rec.osaNumber = safeString(item.get('custbody_osa_contract_num'));
            rec.termStartDate = normalizeDateString(safeString(item.get('custbody_inv_term_start_date')));
            rec.termEndDate = normalizeDateString(safeString(item.get('custbody_inv_term_end_date')));
            String rawStatus = safeString(item.get('statusdisplay'));
            // Strip "Invoice : " prefix from BUILTIN.DF(status) display value
            if (rawStatus.startsWith('Invoice : ')) {
                rawStatus = rawStatus.substringAfter('Invoice : ');
            }
            rec.paymentStatus = rawStatus;
            rec.amount = safeDecimal(item.get('foreigntotal'));
            rec.sharePointUrl = SHAREPOINT_BASE + rec.invoiceId + '_' + rec.invoiceNumber;
            rec.lineAmount = safeDecimal(item.get('lineamount'));
            rec.lineQuantity = safeDecimal(item.get('linequantity'));
            rec.itemCode = safeString(item.get('itemcode'));
            records.add(rec);
        }

        return records;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods — Utilities
     *
     ***********************************************************************************************/

    /**
     * @description Safely converts an Object to a String, returning empty string for null.
     * @param val The value to convert.
     * @return String representation or empty string.
     */
    private static String safeString(Object val) {
        return val != null ? String.valueOf(val) : '';
    }

    /**
     * @description Safely converts an Object to a Decimal, returning null for non-numeric values.
     * @param val The value to convert.
     * @return Decimal value or null.
     */
    private static Decimal safeDecimal(Object val) {
        if (val == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Normalizes date strings from NetSuite (e.g., "3/1/2025" or "2025-03-01")
     *              to ISO-8601 format "YYYY-MM-DD" for consistent matching with Salesforce dates.
     * @param dateStr The raw date string from NetSuite.
     * @return Normalized date string in YYYY-MM-DD format, or the original string if parsing fails.
     */
    private static String normalizeDateString(String dateStr) {
        if (String.isBlank(dateStr)) {
            return '';
        }

        // Already in YYYY-MM-DD format
        if (dateStr.contains('-') && dateStr.length() == 10) {
            return dateStr;
        }

        // NetSuite often returns M/D/YYYY — parse and convert
        try {
            List<String> parts = dateStr.split('/');
            if (parts.size() == 3) {
                String month = parts[0].leftPad(2, '0');
                String day = parts[1].leftPad(2, '0');
                String year = parts[2];
                return year + '-' + month + '-' + day;
            }
        } catch (Exception e) {
            // Fall through to return original
        }

        return dateStr;
    }

    /**
     * @description Throws an AuraHandledException with the given message.
     * @param message The error message to surface to the LWC.
     */
    private static void throwAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        throw e;
    }
}