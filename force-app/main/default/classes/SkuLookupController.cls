/**
 * @description Shared lookup/search controller for the SKU Management App.
 *              Provides search methods for Product2, Product_Line__c, Pricebook2,
 *              Product_Rollup__c, and Item_Master_Product__c.
 *              Returns results compatible with the existing c-lookup component.
 */
public with sharing class SkuLookupController {

    private static final Integer MAX_RESULTS = 20;

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchProducts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<LookupResult>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<LookupResult> results = new List<LookupResult>();
        for (Product2 p : [
            SELECT Id, Name, ProductCode, Product_LineNew__r.Name, IsActive
            FROM Product2
            WHERE (Name LIKE :key OR ProductCode LIKE :key)
              AND IsActive = true
            ORDER BY Name ASC
            LIMIT :MAX_RESULTS
        ]) {
            String subtitle = p.ProductCode != null ? p.ProductCode : '';
            if (p.Product_LineNew__r != null && p.Product_LineNew__r.Name != null) {
                subtitle += (String.isNotBlank(subtitle) ? ' | ' : '') + p.Product_LineNew__r.Name;
            }
            results.add(new LookupResult(p.Id, p.Name, subtitle, 'standard:product'));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchProductLines(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<LookupResult>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<LookupResult> results = new List<LookupResult>();
        for (Product_Line__c pl : [
            SELECT Id, Name, Practice__c, Deployment__c
            FROM Product_Line__c
            WHERE Name LIKE :key AND Active__c = true
            ORDER BY Name ASC
            LIMIT :MAX_RESULTS
        ]) {
            String subtitle = '';
            if (pl.Practice__c != null) {
                subtitle = pl.Practice__c;
            }
            if (pl.Deployment__c != null) {
                subtitle += (String.isNotBlank(subtitle) ? ' | ' : '') + pl.Deployment__c;
            }
            results.add(new LookupResult(pl.Id, pl.Name, subtitle, 'standard:product_required'));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchPricebooks(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<LookupResult>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<LookupResult> results = new List<LookupResult>();
        for (Pricebook2 pb : [
            SELECT Id, Name, IsActive, CurrencyIsoCode
            FROM Pricebook2
            WHERE Name LIKE :key AND IsActive = true
            ORDER BY Name ASC
            LIMIT :MAX_RESULTS
        ]) {
            results.add(new LookupResult(
                pb.Id, pb.Name,
                pb.CurrencyIsoCode != null ? pb.CurrencyIsoCode : '',
                'standard:pricebook'
            ));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchProductRollups(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<LookupResult>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<LookupResult> results = new List<LookupResult>();
        for (Product_Rollup__c pr : [
            SELECT Id, Name, Product_Line__r.Name, Description__c
            FROM Product_Rollup__c
            WHERE Name LIKE :key
            ORDER BY Name ASC
            LIMIT :MAX_RESULTS
        ]) {
            String subtitle = pr.Product_Line__r != null && pr.Product_Line__r.Name != null
                ? pr.Product_Line__r.Name : '';
            results.add(new LookupResult(pr.Id, pr.Name, subtitle, 'standard:product_item'));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchItemMasterProducts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<LookupResult>();
        }
        String key = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<LookupResult> results = new List<LookupResult>();
        for (Item_Master_Product__c imp : [
            SELECT Id, Name, Item_Name__c, Active__c
            FROM Item_Master_Product__c
            WHERE (Name LIKE :key OR Item_Name__c LIKE :key)
            ORDER BY Name ASC
            LIMIT :MAX_RESULTS
        ]) {
            String subtitle = imp.Item_Name__c != null ? imp.Item_Name__c : '';
            if (!imp.Active__c) {
                subtitle += ' (Inactive)';
            }
            results.add(new LookupResult(imp.Id, imp.Name, subtitle, 'standard:product_item_transaction'));
        }
        return results;
    }

    public class LookupResult {
        @AuraEnabled public String id;
        @AuraEnabled public String sObjectType;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String icon;

        public LookupResult(String id, String title, String subtitle, String icon) {
            this.id = id;
            this.title = title;
            this.subtitle = subtitle;
            this.icon = icon;
        }
    }
}