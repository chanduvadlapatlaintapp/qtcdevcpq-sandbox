/**
 * @description REST endpoint that runs a full portfolio analysis for a given account,
 *              generates a CSV file, and returns it as a base64-encoded string for the
 *              Copilot Studio Teams bot to pass to Power Automate for file delivery.
 *
 *              GET /services/apexrest/v1/portfolioAnalysis/run?accountId=001xxx&userEmail=user@intapp.com
 *
 *              Returns JSON:
 *              {
 *                "success": true,
 *                "accountName": "Acme Corp",
 *                "fileName": "Acme_Corp_Portfolio_2026-04-24.csv",
 *                "fileUrl": "https://[instance].salesforce.com/sfc/servlet.shepherd/version/download/[id]"
 *              }
 *
 * @author      Vignesh Prabhudoss
 * @date        2026-04-24
 * @jira        BIZ-82161
 */
@RestResource(urlMapping='/portfolioAnalysis/run')
global with sharing class PortfolioAnalysisRunRESTService {

    /***********************************************************************************************
     *
     * Constants
     *
     ***********************************************************************************************/

    // No external dependencies for POC — CSV returned as base64 for Power Automate delivery

    /***********************************************************************************************
     *
     * Inner Classes / Wrappers
     *
     ***********************************************************************************************/

    /**
     * @description Standard REST response returned to the Copilot Studio agent.
     *              fileUrl is an authenticated Salesforce download URL that requires
     *              the caller to be logged in to Salesforce (via SSO) to access the file.
     */
    global class RunResponse {
        global Boolean success;
        global String errorMessage;
        global String accountName;
        global String fileName;
        global String fileUrl;

        global RunResponse() {
            this.success = false;
        }
    }

    /***********************************************************************************************
     *
     * Public Methods
     *
     ***********************************************************************************************/

    /**
     * @description Orchestrates the full portfolio analysis pipeline:
     *              1. Validate inputs
     *              2. Fetch account + subscription + invoice data
     *              3. Build CSV
     *              4. Store CSV as a Salesforce ContentVersion (File)
     *              5. Return authenticated SF download URL
     */
    @HttpGet
    global static void runAnalysis() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        RunResponse response = new RunResponse();

        try {
            // ── 1. Validate inputs ──────────────────────────────────────────────────────
            String accountId   = req.params.get('accountId');
            String userEmail   = req.params.get('userEmail');

            if (String.isBlank(accountId)) {
                res.statusCode = 400;
                response.errorMessage = 'accountId parameter is required.';
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            // ── 2. Fetch data ───────────────────────────────────────────────────────────
            Account accountDetails = PortfolioAnalysisController.getAccountDetails((Id) accountId);

            if (accountDetails == null) {
                res.statusCode = 404;
                response.errorMessage = 'Account not found for Id: ' + accountId;
                res.responseBody = Blob.valueOf(JSON.serialize(response));
                return;
            }

            response.accountName = accountDetails.Name;

            // Fetch active subscriptions
            List<SBQQ__Subscription__c> subscriptions =
                PortfolioAnalysisController.getSubscriptions(accountDetails.Name);

            // Extract OSA numbers for invoice lookup
            Set<String> osaSet = new Set<String>();
            for (SBQQ__Subscription__c sub : subscriptions) {
                if (sub.SBQQ__Contract__r != null &&
                    String.isNotBlank(sub.SBQQ__Contract__r.OSA_Number__c)) {
                    osaSet.add(sub.SBQQ__Contract__r.OSA_Number__c);
                }
            }
            List<String> osaNumbers = new List<String>(osaSet);

            // Fetch invoices from NetSuite
            PortfolioAnalysisController.InvoiceDataResult invoiceResult =
                new PortfolioAnalysisController.InvoiceDataResult();

            if (!osaNumbers.isEmpty()) {
                invoiceResult = PortfolioAnalysisController.getInvoiceData(osaNumbers);
            }

            // Fetch previous contract subscriptions (unpaid period exception)
            List<Id> currentSubIds = new List<Id>();
            for (SBQQ__Subscription__c sub : subscriptions) {
                currentSubIds.add(sub.Id);
            }

            List<SBQQ__Subscription__c> previousSubs = new List<SBQQ__Subscription__c>();
            if (!osaNumbers.isEmpty()) {
                previousSubs = PortfolioAnalysisController.getPreviousContractSubscriptions(
                    accountDetails.Name,
                    osaNumbers,
                    currentSubIds
                );
            }

            // Combine current + previous subscriptions
            List<SBQQ__Subscription__c> allSubscriptions = new List<SBQQ__Subscription__c>();
            allSubscriptions.addAll(subscriptions);
            allSubscriptions.addAll(previousSubs);

            // Build invoice map keyed by OSA|startDate|endDate for row matching
            Map<String, PortfolioAnalysisController.InvoiceRecord> invoiceMap =
                buildInvoiceMap(invoiceResult.invoices);

            // ── 3. Build CSV ────────────────────────────────────────────────────────────
            String csvContent = buildCsv(accountDetails, allSubscriptions, invoiceMap);
            String fileName   = sanitiseFileName(accountDetails.Name) +
                '_Portfolio_' + Date.today().format() + '.csv';

            // ── 4. Store CSV as Salesforce File (ContentVersion) ────────────────────────
            ContentVersion cv = new ContentVersion();
            cv.Title          = fileName;
            cv.PathOnClient   = fileName;
            cv.VersionData    = Blob.valueOf(csvContent);
            cv.IsMajorVersion = true;
            insert cv;

            // ── 5. Return authenticated SF download URL ─────────────────────────────────
            String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
            String fileUrl     = instanceUrl +
                '/sfc/servlet.shepherd/version/download/' + cv.Id;

            response.success  = true;
            response.fileName = fileName;
            response.fileUrl  = fileUrl;
            res.statusCode    = 200;

            Nebula.Logger.info('PortfolioAnalysisRunRESTService: File created for ' +
                accountDetails.Name + ' (' + fileName + ')')
                .addTag('PortfolioAnalysis')
                .addTag('TeamsBot')
                .setRecordId((Id) accountId);
            Nebula.Logger.saveLog();

        } catch (Exception e) {
            res.statusCode = 500;
            response.errorMessage = 'Portfolio analysis failed: ' + e.getMessage();

            Nebula.Logger.error('PortfolioAnalysisRunRESTService: run failed', e)
                .addTag('PortfolioAnalysis')
                .addTag('TeamsBot');
            Nebula.Logger.saveLog();
        }

        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    /***********************************************************************************************
     *
     * Private Methods — CSV Generation
     *
     ***********************************************************************************************/

    /**
     * @description Builds the full portfolio CSV string.
     *              Columns mirror the excelExport.js column set (internal view).
     *
     * @param accountDetails  Account record with metadata fields.
     * @param subscriptions   Combined current + previous subscription records.
     * @param invoiceMap      Map keyed by OSA|startDate|endDate → InvoiceRecord.
     * @return                CSV string ready for upload.
     */
    @TestVisible
    private static String buildCsv(
        Account accountDetails,
        List<SBQQ__Subscription__c> subscriptions,
        Map<String, PortfolioAnalysisController.InvoiceRecord> invoiceMap
    ) {
        List<String> rows = new List<String>();

        // ── Account metadata header block ──────────────────────────────────────────
        rows.add(csvRow(new List<String>{ 'Account', csvEscape(accountDetails.Name) }));
        rows.add(csvRow(new List<String>{ 'GTM Tier', csvEscape(accountDetails.GTM_Motion_Tier__c) }));
        rows.add(csvRow(new List<String>{ 'Client Since', csvEscape(String.valueOf(accountDetails.Customer_Since__c)) }));
        rows.add(csvRow(new List<String>{ 'MSSA #',
            accountDetails.Master_Terms_Contract_Number__r != null
                ? csvEscape(accountDetails.Master_Terms_Contract_Number__r.ContractNumber) : '' }));
        rows.add(csvRow(new List<String>{ 'MSSA Version #', csvEscape(accountDetails.Contract_Term_Version__c) }));
        rows.add(csvRow(new List<String>{ 'MSSA Uplift Cap?', csvEscape(accountDetails.Master_Terms_CPI__c) }));
        rows.add(csvRow(new List<String>{ 'Cloud Addendum #',
            accountDetails.Cloud_Addendum__r != null
                ? csvEscape(accountDetails.Cloud_Addendum__r.ContractNumber) : 'No' }));
        rows.add(''); // blank separator

        // ── Column headers ──────────────────────────────────────────────────────────
        rows.add(csvRow(new List<String>{
            'OSA', 'Uplift Cap?', 'Contract (OSA) #', 'Bundle', 'Invoice #', 'Payment Status',
            'Deployment Model', 'Currency', 'Meter Type', 'Band / Quantity',
            'Product Line', 'Product', '# of Months in Term',
            'Support Level', 'Contract Value', 'Sales Price / Month',
            'Invoice Total', 'ACV',
            'Start Date', 'End Date', '# of Days', 'Per Day', 'Status',
            'Annualized', 'SFA'
        }));

        // ── Data rows ───────────────────────────────────────────────────────────────
        for (SBQQ__Subscription__c sub : subscriptions) {
            String osa = sub.SBQQ__Contract__r != null
                ? sub.SBQQ__Contract__r.OSA_Number__c : '';
            String invoiceKey = osa + '|' +
                String.valueOf(sub.SBQQ__SegmentStartDate__c) + '|' +
                String.valueOf(sub.SBQQ__SegmentEndDate__c);

            PortfolioAnalysisController.InvoiceRecord invoice = invoiceMap.get(invoiceKey);

            Decimal netPrice    = sub.SBQQ__NetPrice__c != null ? sub.SBQQ__NetPrice__c : 0;
            Decimal qty         = sub.SBQQ__SegmentQuantity__c != null ? sub.SBQQ__SegmentQuantity__c : 0;
            Decimal segMonths   = sub.Segment_Months__c != null ? sub.Segment_Months__c : 0;
            Decimal contractVal = netPrice * qty;
            Decimal salePriceMonth = segMonths > 0 ? (netPrice / segMonths).setScale(2) : null;

            Integer days = daysBetween(sub.SBQQ__SegmentStartDate__c, sub.SBQQ__SegmentEndDate__c);
            Decimal perDay = (days != null && days > 0)
                ? (contractVal / days).setScale(2) : null;
            Decimal annualized = annualize(contractVal, sub.SBQQ__StartDate__c, sub.SBQQ__EndDate__c);
            Decimal acv = segMonths > 0
                ? ((netPrice / segMonths) * 12 * qty).setScale(2) : 0;

            Boolean hasCpi    = sub.SBQQ__Contract__r != null && sub.SBQQ__Contract__r.CPI__c != null;
            Boolean hasBundle = sub.SBQQ__Contract__r != null && sub.SBQQ__Contract__r.Hide_Pricing__c != null;

            rows.add(csvRow(new List<String>{
                csvEscape(osa),
                hasCpi    ? csvEscape(String.valueOf(sub.SBQQ__Contract__r.CPI__c)) : '',
                csvEscape(sub.SBQQ__ContractNumber__c),
                hasBundle ? csvEscape(String.valueOf(sub.SBQQ__Contract__r.Hide_Pricing__c)) : '',
                invoice != null ? csvEscape(invoice.invoiceNumber) : '',
                invoice != null ? csvEscape(invoice.paymentStatus) : '',
                csvEscape(sub.SBQQ__Product__r != null ? sub.SBQQ__Product__r.Deployment__c : ''),
                csvEscape(sub.CurrencyIsoCode),
                csvEscape(sub.Per_Integrations__c),
                String.valueOf(qty.intValue()),
                csvEscape(sub.SBQQ__Product__r != null ? sub.SBQQ__Product__r.ProductCode : ''),
                csvEscape(sub.SBQQ__Product__r != null ? sub.SBQQ__Product__r.Name : sub.Name),
                segMonths > 0 ? String.valueOf(segMonths.intValue()) : '',
                csvEscape(sub.Support_Level__c),
                contractVal != null  ? String.valueOf(contractVal.setScale(2))  : '',
                salePriceMonth != null ? String.valueOf(salePriceMonth)          : '',
                invoice != null && invoice.lineAmount != null
                    ? String.valueOf(invoice.lineAmount.abs().setScale(2))       : '',
                String.valueOf(acv),
                String.valueOf(sub.SBQQ__SegmentStartDate__c),
                String.valueOf(sub.SBQQ__SegmentEndDate__c),
                days != null ? String.valueOf(days) : '',
                perDay != null ? String.valueOf(perDay) : '',
                csvEscape(sub.Contract_Status__c),
                annualized != null ? String.valueOf(annualized) : '',
                sub.SBQQ__Contract__r != null && sub.SBQQ__Contract__r.SBQQ__RenewalUpliftRate__c != null
                    ? sub.SBQQ__Contract__r.SBQQ__RenewalUpliftRate__c + '%' : ''
            }));
        }

        return String.join(rows, '\n');
    }

    /**
     * @description Builds an invoice lookup map keyed by OSA|startDate|endDate.
     *
     * @param invoices  List of InvoiceRecord from NetSuite.
     * @return          Map for O(1) invoice matching per subscription row.
     */
    @TestVisible
    private static Map<String, PortfolioAnalysisController.InvoiceRecord> buildInvoiceMap(
        List<PortfolioAnalysisController.InvoiceRecord> invoices
    ) {
        Map<String, PortfolioAnalysisController.InvoiceRecord> invoiceMap =
            new Map<String, PortfolioAnalysisController.InvoiceRecord>();

        if (invoices == null) {
            return invoiceMap;
        }

        for (PortfolioAnalysisController.InvoiceRecord inv : invoices) {
            String key = inv.osaNumber + '|' + inv.termStartDate + '|' + inv.termEndDate;
            if (!invoiceMap.containsKey(key)) {
                invoiceMap.put(key, inv);
            }
        }

        return invoiceMap;
    }

    /***********************************************************************************************
     *
     * Private Methods — Utilities
     *
     ***********************************************************************************************/

    /**
     * @description Wraps a value in CSV double-quotes, escaping internal quotes.
     *              Handles null safely.
     */
    @TestVisible
    private static String csvEscape(String val) {
        if (String.isBlank(val)) {
            return '';
        }
        return '"' + val.replace('"', '""') + '"';
    }

    /**
     * @description Joins a list of values into a single CSV row string.
     */
    private static String csvRow(List<String> values) {
        return String.join(values, ',');
    }

    /**
     * @description Computes the number of days between two dates (inclusive of start).
     *
     * @return Integer day count, or null if either date is null.
     */
    @TestVisible
    private static Integer daysBetween(Date startDate, Date endDate) {
        if (startDate == null || endDate == null) {
            return null;
        }
        return startDate.daysBetween(endDate);
    }

    /**
     * @description Annualizes a contract value over the full contract term.
     *              Returns null if dates are missing or term is zero.
     */
    @TestVisible
    private static Decimal annualize(Decimal contractValue, Date startDate, Date endDate) {
        if (contractValue == null || startDate == null || endDate == null) {
            return null;
        }
        Integer totalDays = startDate.daysBetween(endDate);
        if (totalDays == null || totalDays == 0) {
            return null;
        }
        return ((contractValue / totalDays) * 365).setScale(2);
    }

    /**
     * @description Strips characters that are invalid in SharePoint filenames.
     */
    @TestVisible
    private static String sanitiseFileName(String name) {
        if (String.isBlank(name)) {
            return 'Unknown';
        }
        return name.replaceAll('[^a-zA-Z0-9_\\-]', '_');
    }
}