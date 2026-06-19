/**
* @description Batch class for generating Conga documents for renewal letters where status is Initiated
* @author Manisha Sharma
* @jira BIZ-73472
**/
global class GenerateRenLetterPDFBatch implements Database.Batchable<SObject>, Schedulable, Database.AllowsCallouts {

    /***********************************************************************************************
    * Properties
    ***********************************************************************************************/
    private String query;
    private Integer scopeSize;

    /***********************************************************************************************
    * Constructors
    ***********************************************************************************************/
    public GenerateRenLetterPDFBatch() {
        this.query = getDefaultQuery();
        this.scopeSize = 1;
    }

    public GenerateRenLetterPDFBatch(String query, Integer scopeSize) {
        this.query = query != null ? query : getDefaultQuery();
        this.scopeSize = scopeSize != null ? scopeSize : 1;
    }

    /***********************************************************************************************
    * Public Methods
    ***********************************************************************************************/
    public void executeBatch(String query, Integer scopeSize) {
        GenerateRenLetterPDFBatch batch = new GenerateRenLetterPDFBatch(query, scopeSize);
        Database.executeBatch(batch, batch.scopeSize);
    }

    /***********************************************************************************************
    * Batch Methods
    ***********************************************************************************************/
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
        List<Proforma_Invoice__c> invoicesToProcess = new List<Proforma_Invoice__c>();
        Set<Id> scopeIds = new Set<Id>();

        // Collect Ids in current batch scope
        for (SObject sObj : scope) {
            Proforma_Invoice__c pi = (Proforma_Invoice__c) sObj;
            scopeIds.add(pi.Id);
        }

        // Find invoices that already have Conga documents linked
        Set<Id> invoicesWithDocs = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :scopeIds
        ]) {
            invoicesWithDocs.add(cdl.LinkedEntityId);
        }

        // Filter out invoices that already have docs
        for (SObject sObj : scope) {
            Proforma_Invoice__c pi = (Proforma_Invoice__c) sObj;
            if (!invoicesWithDocs.contains(pi.Id)) {
                invoicesToProcess.add(pi);
            }
        }

        // Process each invoice, apply dynamic condition inside Apex
        for (Proforma_Invoice__c renInvoice : invoicesToProcess) {

            // Proceed with Conga document generation

            String sessionId = UserInfo.getSessionId();
            String serverUrl = URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/u/59.0/' + UserInfo.getOrganizationId();

            String fileName = buildFileName(renInvoice);
            // EncodingUtil.urlEncode uses '+' for spaces; Conga examples often show %20, so normalize.
            String encodedFileName = EncodingUtil.urlEncode(fileName, 'UTF-8').replace('+', '%20');

            // Base Conga params (template & queries)
            String baseParams =
                '&queryid=' +
                    '[QuoteLineRenewal]0Q_026MAQ975089' +
                    ',[RenewalLetter]0Q_030MAQ331479' +
                    ',[StaticRenewal]0Q_174MAQ153500' +
                    ',[SelectRenewal]0Q_175MAQ769671' +
                '&defaultPDF=1' +
                '&templateid=0T_071MAQ089302' +
                '&OFN=' + encodedFileName +
                // Email parameters
                (renInvoice.Renewal_Quote__r.Invoicing_Contact__c == null 
                    ? '' 
                    : '&EmailToId=' + renInvoice.Renewal_Quote__r.Invoicing_Contact__c) +
                '&CongaEmailTemplateId=0E_003EAU884391' +
                // IMPORTANT: Use ONLY APIMode OR DS7, not both.
                // APIMode=12 → run in background and send email.
                '&APIMode=12' +
                // Save a copy as Salesforce File (this still works without DS7)
                '&SC1=SalesforceFile&SC0=1';

            String congaUrl = Label.Conga_Composer_URL + 'sessionId=' + sessionId + '&serverUrl=' + serverUrl + '&id=' + renInvoice.Id + baseParams;

            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(congaUrl);
            req.setMethod('GET');
            req.setTimeout(120000);
            req.setHeader('Authorization', 'Bearer ' + sessionId);

            try {
                HttpResponse res = http.send(req);
                if (res.getStatusCode() != 200) {
                    throw new CalloutException('HTTP Status ' + res.getStatusCode() + ': ' + res.getStatus());
                }
            } catch (Exception e) {
                errorLogs.add(new Error_Log__c(
                    ClassName__c = 'GenerateRenLetterPDFBatch',
                    MethodName__c = 'execute',
                    Process__c = 'Generate Renewal PDF Batch',
                    Sobject_Id__c = renInvoice.Id,
                    Sobject_Name__c = 'Proforma_Invoice__c',
                    Exception_Type__c = e.getTypeName(),
                    Exception_Message__c = e.getMessage(),
                    StackTrace__c = 'Conga URL: ' + congaUrl
                ));
            }
        }

        if (!errorLogs.isEmpty()) {
            insert errorLogs;
        }
    }

    global void finish(Database.BatchableContext bc) {}

    /***********************************************************************************************
    * Scheduler Method
    ***********************************************************************************************/
    public void execute(SchedulableContext sc) {
        executeBatch(this.query, this.scopeSize);
    }

    /***********************************************************************************************
    * Private Methods
    ***********************************************************************************************/
    private String getDefaultQuery() {
        return 'SELECT Id, Account_Name__c, Renewal_Quote__c, Renewal_Quote__r.Invoicing_Contact__c, Send_Immediately__c, Days_remaining_for_Renewal__c, ' +
               'Renewal_Quote__r.Disable_RL_PDF_Generation__c, Renewal_Quote__r.SBQQ__Account__c, Renewal_Quote__r.SBQQ__Account__r.Id, ' +
               'Renewal_Quote__r.SBQQ__Account__r.IntApp_Account_Number__c, Renewal_Quote__r.Bill_To_Account__r.Hide_Banking_Details__c ' +
               'FROM Proforma_Invoice__c ' +
               'WHERE Status__c = \'' + RenewalLetterConstants.STATUS_INITIATED + '\' ' +
               'AND Renewal_Quote__r.Disable_RL_PDF_Generation__c = false ' +
               'AND Renewal_Quote__r.SBQQ__Opportunity2__r.Renewals_Pause__c = false'; // BIZ-82935: Skip PDF generation when Renewal Hold is active
    }

    // Helper to build consistent file name (update business format here)
    public static String buildFileName(Proforma_Invoice__c pi) {
        String acct = 'Account';
        try {
            if (pi.Renewal_Quote__r != null &&
                pi.Renewal_Quote__r.SBQQ__Account__c != null &&
                String.isNotBlank(pi.Renewal_Quote__r.SBQQ__Account__r.IntApp_Account_Number__c)) {
                acct = pi.Renewal_Quote__r.SBQQ__Account__r.IntApp_Account_Number__c.trim();
            }
        } catch (SObjectException soe) {
    		// Build one concatenated message
    		Nebula.Logger.error('GenerateRenLetterPDFBatch.buildFileName',soe);
        } finally {
            Nebula.Logger.saveLog();
        }
        // ISO style date for predictability
        Date today = Date.today();
        String rawName = 'Renewal Invoice for ' + acct + ' - ' + today;
        // Scrub characters Conga might dislike in filenames before encoding (retain spaces; encoding will handle them)
        rawName = rawName.replace('\n', ' ').replace('\r', ' ');
        return rawName;
    }
}