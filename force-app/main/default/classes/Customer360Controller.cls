/**
 * @description Controller for the Customer 360 Lightning Web Components. Provides methods
 *              to query customer data across four systems: Salesforce (Subscriptions/Contracts),
 *              OP4i (Entitlements/Usage), NetSuite (Invoices), and Zendesk (Support Tickets).
 * @author  Yousef A
 * @date    03/05/2026
 * @jira    BIZ-80363
 */
public with sharing class Customer360Controller {

    /**********************************************************************************************
     *
     * Wrapper Classes
     *
     ***********************************************************************************************/

    /** Wrapper for Contract + Product subscription data */
    public class SubscriptionWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String contractNumber;
        @AuraEnabled public String product;
        @AuraEnabled public String sku;
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal contractValue;
        @AuraEnabled public Decimal seats;
        @AuraEnabled public String source;
        @AuraEnabled public String recordUrl;
    }

    /** Wrapper for OP4i entitlement data */
    public class EntitlementWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String product;
        @AuraEnabled public String entitlementStatus;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal salePrice;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String recordUrl;
    }

    /** Wrapper for Invoice summary data */
    public class InvoiceWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String invoiceNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal amountInvoiced;
        @AuraEnabled public Decimal outstandingBalance;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Decimal daysPastDue;
        @AuraEnabled public Date datePaid;
        @AuraEnabled public String recordUrl;
    }

    /**********************************************************************************************
     *
     * Public Methods - Account Search
     *
     ***********************************************************************************************/

    /**
     * @description Searches for Accounts by name using SOSL for efficient fuzzy matching.
     * @param searchTerm The user-entered search string (minimum 2 characters).
     * @return List<Account> Matching account records with key fields.
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Account>();
        }

        String sanitized = String.escapeSingleQuotes(searchTerm);
        List<List<SObject>> searchResults = [
            FIND :sanitized IN NAME FIELDS
            RETURNING Account(
                Id, Name, BillingCountry, Owner.Name, Industry
                ORDER BY Name
                LIMIT 20
            )
        ];

        return (List<Account>) searchResults[0];
    }

    /**********************************************************************************************
     *
     * Public Methods - Contract Data (Subscriptions)
     *
     ***********************************************************************************************/

    /**
     * @description Retrieves subscription data from Contract_Product_Line__c joined to
     *              Contract and Product2 for a given Account.
     * @param accountId The Account Id to retrieve subscriptions for.
     * @return List<SubscriptionWrapper> Normalized subscription data.
     */
    @AuraEnabled(cacheable=true)
    public static List<SubscriptionWrapper> getSubscriptions(Id accountId) {
        validateAccountId(accountId);

        List<Contract_Product_Line__c> lines = [
            SELECT Id, Name, Price__c, Quantity__c,
                   Contract__r.Id, Contract__r.ContractNumber,
                   Contract__r.Status, Contract__r.StartDate, Contract__r.EndDate,
                   Contract__r.ContractTerm,
                   Product2__r.Name, Product2__r.ProductCode,
                   Product2__r.Family, Product2__r.Product_Group__c
            FROM Contract_Product_Line__c
            WHERE Contract__r.AccountId = :accountId
            ORDER BY Contract__r.Status ASC, Contract__r.EndDate DESC
        ];

        List<SubscriptionWrapper> wrappers = new List<SubscriptionWrapper>();
        for (Contract_Product_Line__c line : lines) {
            SubscriptionWrapper w = new SubscriptionWrapper();
            w.id = line.Id;
            w.contractNumber = line.Contract__r != null ? line.Contract__r.ContractNumber : '';
            w.product = line.Product2__r != null ? line.Product2__r.Name : line.Name;
            w.sku = line.Product2__r != null ? line.Product2__r.ProductCode : '';
            w.category = resolveCategory(line);
            w.startDate = line.Contract__r != null ? line.Contract__r.StartDate : null;
            w.endDate = resolveEndDate(line.Contract__r);
            w.status = mapContractStatus(line.Contract__r, w.endDate);
            w.contractValue = line.Price__c;
            w.seats = line.Quantity__c;
            w.source = 'Contract';
            w.recordUrl = line.Contract__r != null ? '/' + line.Contract__r.Id : '/' + line.Id;
            wrappers.add(w);
        }

        return wrappers;
    }

    /**********************************************************************************************
     *
     * Public Methods - OP4i Data (Entitlements/Usage)
     *
     ***********************************************************************************************/

    /**
     * @description Retrieves OP4I Entitlement View records for a given Account.
     * @param accountId The Account Id to retrieve entitlements for.
     * @return List<EntitlementWrapper> Normalized entitlement data.
     */
    @AuraEnabled(cacheable=true)
    public static List<EntitlementWrapper> getEntitlements(Id accountId) {
        validateAccountId(accountId);

        List<OP4I_Entitlement_View__c> entitlements = [
            SELECT Id, Name, DLI_Product__r.Name, Entitlement_Status__c,
                   Start_Date__c, End_Date__c, Sale_Price__c, Quantity__c
            FROM OP4I_Entitlement_View__c
            WHERE Account__c = :accountId
            ORDER BY End_Date__c DESC
        ];

        List<EntitlementWrapper> wrappers = new List<EntitlementWrapper>();
        for (OP4I_Entitlement_View__c ent : entitlements) {
            EntitlementWrapper w = new EntitlementWrapper();
            w.id = ent.Id;
            w.name = ent.Name;
            w.product = ent.DLI_Product__r != null ? ent.DLI_Product__r.Name : '';
            w.entitlementStatus = ent.Entitlement_Status__c;
            w.startDate = ent.Start_Date__c;
            w.endDate = ent.End_Date__c;
            w.salePrice = ent.Sale_Price__c;
            w.quantity = ent.Quantity__c;
            w.recordUrl = '/' + ent.Id;
            wrappers.add(w);
        }

        return wrappers;
    }

    /**********************************************************************************************
     *
     * Public Methods - NetSuite Data (Invoices)
     *
     ***********************************************************************************************/

    /**
     * @description Retrieves Invoice records for a given Account from synced NetSuite data.
     * @param accountId The Account Id to retrieve invoices for.
     * @return List<InvoiceWrapper> Normalized invoice data.
     */
    @AuraEnabled(cacheable=true)
    public static List<InvoiceWrapper> getInvoices(Id accountId) {
        validateAccountId(accountId);

        List<Invoice__c> invoices = [
            SELECT Id, Name, Invoice_Number__c, Invoice_Status__c,
                   Amount_Invoiced__c, Outstanding_Balance__c, Due_Date__c,
                   Days_Past_Due__c, Date_Paid_new__c
            FROM Invoice__c
            WHERE Account__c = :accountId
            ORDER BY Due_Date__c DESC
            LIMIT 200
        ];

        List<InvoiceWrapper> wrappers = new List<InvoiceWrapper>();
        for (Invoice__c inv : invoices) {
            InvoiceWrapper w = new InvoiceWrapper();
            w.id = inv.Id;
            w.invoiceNumber = inv.Invoice_Number__c != null ? inv.Invoice_Number__c : inv.Name;
            w.status = inv.Invoice_Status__c;
            w.amountInvoiced = inv.Amount_Invoiced__c;
            w.outstandingBalance = inv.Outstanding_Balance__c;
            w.dueDate = inv.Due_Date__c;
            w.daysPastDue = inv.Days_Past_Due__c;
            w.datePaid = inv.Date_Paid_new__c;
            w.recordUrl = '/' + inv.Id;
            wrappers.add(w);
        }

        return wrappers;
    }

    /**********************************************************************************************
     *
     * Public Methods - Zendesk Data (Support Tickets)
     *
     ***********************************************************************************************/

    /**
     * @description Retrieves Zendesk support tickets for a given Account by making a
     *              real-time callout to the Zendesk REST API. NOT cacheable (callout).
     * @param accountId The Account Id (used to look up the organization name).
     * @return List<ZendeskService.ZendeskTicket> Normalized ticket data.
     */
    @AuraEnabled
    public static List<ZendeskService.ZendeskTicket> getSupportTickets(Id accountId) {
        validateAccountId(accountId);

        Account acct = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];

        try {
            List<ZendeskService.ZendeskTicket> tickets = ZendeskService.getTicketsByOrganization(acct.Name);

            Nebula.Logger.debug('Retrieved ' + tickets.size() + ' Zendesk tickets for Account: ' + acct.Name)
                .addTag('Customer360')
                .addTag('Zendesk')
                .setRecordId(accountId);
            Nebula.Logger.saveLog();

            return tickets;
        } catch (Exception e) {
            Nebula.Logger.error('Zendesk callout failed for Account: ' + acct.Name + ' - ' + e.getMessage())
                .addTag('Customer360')
                .addTag('Zendesk')
                .addTag('CalloutError')
                .setRecordId(accountId);
            Nebula.Logger.saveLog();

            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**********************************************************************************************
     *
     * Public Methods - Activity & CTA Creation
     *
     ***********************************************************************************************/

    /**
     * @description Creates a completed Task record (Activity) linked to the given Account.
     * @param accountId The Account Id to log the activity against.
     * @param activityType The activity type (Call, Email, Meeting, etc.).
     * @param subject The subject line for the activity.
     * @param description Optional detailed description.
     * @param activityDate The date the activity occurred.
     * @return Id The created Task record Id.
     */
    @AuraEnabled
    public static Id logActivity(Id accountId, String activityType, String subject, String description, Date activityDate) {
        validateAccountId(accountId);
        if (String.isBlank(subject)) {
            AuraHandledException e = new AuraHandledException('Subject is required.');
            e.setMessage('Subject is required.');
            throw e;
        }

        Task t = new Task(
            WhatId = accountId,
            Subject = subject,
            Description = description,
            ActivityDate = activityDate != null ? activityDate : System.today(),
            Type = activityType,
            Status = 'Completed'
        );
        insert t;

        Nebula.Logger.debug('Logged activity "' + subject + '" for Account: ' + accountId)
            .addTag('Customer360')
            .addTag('Activity')
            .setRecordId(accountId);
        Nebula.Logger.saveLog();

        return t.Id;
    }

    /**
     * @description Creates a CTA Task record linked to the given Account.
     * @param accountId The Account Id.
     * @param ctaType The CTA category (Risk, Expansion, Renewal, Lifecycle).
     * @param priority The priority level (High, Normal, Low).
     * @param description Optional description.
     * @param dueDate The CTA due date.
     * @return Id The created Task record Id.
     */
    @AuraEnabled
    public static Id createCta(Id accountId, String ctaType, String priority, String description, Date dueDate) {
        validateAccountId(accountId);
        if (String.isBlank(ctaType)) {
            AuraHandledException e = new AuraHandledException('CTA Type is required.');
            e.setMessage('CTA Type is required.');
            throw e;
        }

        String subjectLine = ctaType + ' CTA' + (String.isNotBlank(description) ? ': ' + description.abbreviate(100) : '');

        Task t = new Task(
            WhatId = accountId,
            Subject = subjectLine,
            Description = description,
            ActivityDate = dueDate != null ? dueDate : System.today().addDays(14),
            Type = 'CTA',
            Priority = String.isNotBlank(priority) ? priority : 'Normal',
            Status = 'Not Started'
        );
        insert t;

        Nebula.Logger.debug('Created CTA "' + subjectLine + '" for Account: ' + accountId)
            .addTag('Customer360')
            .addTag('CTA')
            .setRecordId(accountId);
        Nebula.Logger.saveLog();

        return t.Id;
    }

    /**********************************************************************************************
     *
     * Private Methods
     *
     ***********************************************************************************************/

    /**
     * @description Resolves the end date from the Contract. Uses Contract.EndDate if populated,
     *              otherwise computes from StartDate + ContractTerm (months).
     * @param con The Contract record (from relationship query).
     * @return Date The resolved end date, or null if insufficient data.
     */
    private static Date resolveEndDate(Contract con) {
        if (con == null) {
            return null;
        }
        if (con.EndDate != null) {
            return con.EndDate;
        }
        if (con.StartDate != null && con.ContractTerm != null && con.ContractTerm > 0) {
            return con.StartDate.addMonths(Integer.valueOf(con.ContractTerm));
        }
        return null;
    }

    /**
     * @description Maps Contract status and dates into a normalized display status.
     * @param con The Contract record (from relationship query).
     * @param resolvedEndDate The pre-resolved end date (accounts for null EndDate).
     * @return String Normalized status: Active, Pending, Expired, or raw status.
     */
    private static String mapContractStatus(Contract con, Date resolvedEndDate) {
        if (con == null) {
            return 'Unknown';
        }
        if (resolvedEndDate != null && resolvedEndDate < System.today()) {
            return 'Expired';
        }
        if (con.Status == 'Activated' || con.Status == 'In Force') {
            return 'Active';
        }
        if (con.Status != null && con.Status.containsIgnoreCase('Draft')) {
            return 'Pending';
        }
        return con.Status != null ? con.Status : 'Unknown';
    }

    /**
     * @description Resolves the product category from Product2 fields.
     *              Prefers Product2.Family, falls back to Product_Group__c, then empty string.
     * @param line The Contract_Product_Line__c record.
     * @return String The resolved category.
     */
    private static String resolveCategory(Contract_Product_Line__c line) {
        if (line.Product2__r != null) {
            if (String.isNotBlank(line.Product2__r.Family)) {
                return line.Product2__r.Family;
            }
            if (String.isNotBlank(line.Product2__r.Product_Group__c)) {
                return line.Product2__r.Product_Group__c;
            }
        }
        return '';
    }

    /**
     * @description Validates that an Account Id is provided.
     * @param accountId The Account Id to validate.
     */
    private static void validateAccountId(Id accountId) {
        if (accountId == null) {
            AuraHandledException e = new AuraHandledException('Account Id is required.');
            e.setMessage('Account Id is required.');
            throw e;
        }
    }
}