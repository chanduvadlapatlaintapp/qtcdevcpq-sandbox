public with sharing class QLIDataAccess {
    private SBQQ__QuoteLine__c qli;
    private Id oliId;

    public QLIDataAccess(SBQQ__QuoteLine__c qli, Id oliId) {
        this.qli = qli;
        this.oliId = oliId;
    }

    public Object get(String qliFieldApiName) {
        if (qli != null && qli.getSObjectType().getDescribe().fields.getMap().containsKey(qliFieldApiName))
            return qli.get(qliFieldApiName);
        return null;
    }

    public String getRenewedSubscriptionId() {
        if (qli != null && qli.getSObjectType().getDescribe().fields.getMap().containsKey('SBQQ__RenewedSubscription__c')) {
            return (String) qli.get('SBQQ__RenewedSubscription__c');
        }
        return null;
    }

    public Id getOpportunityLineItemId() {
        return oliId; // May be null if no matching OLI
    }

    // Factory method: returns a LIST of DAOs with OLI matching (if any)
    public static List<QLIDataAccess> fetchByQuoteId(Id quoteId) {
        // 1. Get all QLIs for the quote
        List<SBQQ__QuoteLine__c> qlis = [
            SELECT Id, SBQQ__RenewedSubscription__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
        ];
        // 2. Get all OLIs for the opportunity, mapped by QLI
        Map<Id, OpportunityLineItem> oliByQli = new Map<Id, OpportunityLineItem>();
        if (!qlis.isEmpty()) {
            Set<Id> qliIds = new Set<Id>();
            for (SBQQ__QuoteLine__c qli : qlis) qliIds.add(qli.Id);
            for (OpportunityLineItem oli : [
                SELECT Id, SBQQ__QuoteLine__c FROM OpportunityLineItem
                WHERE SBQQ__QuoteLine__c IN :qliIds
            ]) {
                if (oli.SBQQ__QuoteLine__c != null) {
                    oliByQli.put(oli.SBQQ__QuoteLine__c, oli);
                }
            }
        }
        // 3. For each QLI, pair with OLI (if any)
        List<QLIDataAccess> result = new List<QLIDataAccess>();
        for (SBQQ__QuoteLine__c qli : qlis) {
            Id oliId = oliByQli.containsKey(qli.Id) ? oliByQli.get(qli.Id).Id : null;
            result.add(new QLIDataAccess(qli, oliId));
        }
        return result;
    }
  }