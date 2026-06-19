/**
 * @description Controller for the Pricebook View section of the SKU Management App.
 *              Provides read-only access to product pricing data grouped by
 *              Business Unit or Vertical with pricing matrix (GTM Motion Tier or Intapp Pricing fallback).
 *              Each product shows a single row per vertical, using the vertical's
 *              default meter type from the Block_Pricing__c (Type = Meter Type) record.
 *              If a product has no Block_Pricing__c (GTM Motion Tier) records,
 *              falls back to Intapp_Pricing__c (FY26_All_Products pricebook).
 *              Supports two filter modes:
 *              - By Business Unit: groups results by Vertical (Active / Restricted)
 *              - By Vertical: groups results by Business Unit (Active / Restricted)
 */
public with sharing class PricebookViewController {

    // =========================================================================
    // Constants
    // =========================================================================

    private static final List<String> CURRENCIES = new List<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final List<String> TIERS = new List<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};

    /** Intapp Pricing fallback constants (used when no Block Pricing GTM records exist) */
    private static final String PRICEBOOK_NAME = 'FY26_All_Products';
    private static final String NONE_TIER_INTAPP = 'Tier (none)';

    /** Map of vertical display name → Product2 field API name */
    private static final Map<String, String> VERTICAL_FIELD_MAP = new Map<String, String>{
        'Legal'       => 'Is_Legal__c',
        'Accounting'  => 'Is_Accounting__c',
        'Consulting'  => 'Is_Consulting__c',
        'IBA'         => 'Is_IBA__c',
        'PCM'         => 'Is_PCM__c',
        'Real Assets' => 'Is_Real_Assets__c',
        'Corporate'   => 'Iss_Corporate__c'
    };

    /** Map of vertical display name → Block_Pricing__c meter type field API name.
     *  Legal uses the USD/AUD field as the primary; GBP/EUR handled separately via LEGAL_GBP_EUR_FIELD. */
    private static final Map<String, String> VERTICAL_METER_FIELD_MAP = new Map<String, String>{
        'Legal'       => 'Legal_meter_type_USD_AUD__c',
        'Accounting'  => 'meter_type_Accounting__c',
        'Consulting'  => 'meter_type_Consulting__c',
        'IBA'         => 'meter_type_IBA__c',
        'PCM'         => 'meter_type_PCM__c',
        'Real Assets' => 'meter_type_RealAssets__c',
        'Corporate'   => 'meter_type_Corporate__c'
    };

    /** Legal GBP/EUR meter type field (used for Legal merge logic) */
    private static final String LEGAL_GBP_EUR_FIELD = 'Legal__c';

    /** Ordered list of vertical names for consistent group ordering */
    private static final List<String> VERTICAL_NAMES = new List<String>{
        'Legal', 'Accounting', 'Consulting', 'IBA', 'PCM', 'Real Assets', 'Corporate'
    };

    /** Priority ordering for Business Units — these appear first in this exact order, then any remaining alphabetically */
    private static final List<String> BU_ORDER = new List<String>{
        'DealCloud', 'Compliance', 'Time', 'Collaboration', 'Tech',
        'Multiple Products', 'Ops & Finance', 'Unassigned'
    };

    /** Priority ordering for Pricing Basis sort (flat list — no sub-grouping) */
    private static final List<String> PRICING_BASIS_ORDER = new List<String>{
        'Tier based', '% of ACV', 'Free', 'Quantity based'
    };

    /** Product2 fields to query */
    private static final String PRODUCT_QUERY_FIELDS =
        'Id, ProductCode, Name, IsActive, ' +
        'Product_LineNew__r.Name, Business_Unit_New__c, Product_Type__c, Pricing_Basis__c, ' +
        'Is_Legal__c, Is_Accounting__c, Is_Consulting__c, ' +
        'Is_IBA__c, Is_PCM__c, Is_Real_Assets__c, Iss_Corporate__c';

    /** Block_Pricing__c Meter Type record fields to query */
    private static final String METER_TYPE_QUERY_FIELDS =
        'Id, Product__c, Legal_meter_type_USD_AUD__c, Legal__c, ' +
        'meter_type_Accounting__c, meter_type_Consulting__c, ' +
        'meter_type_Corporate__c, meter_type_IBA__c, ' +
        'meter_type_PCM__c, meter_type_RealAssets__c';

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * @description Returns distinct Business Unit values from Product Line records.
     * @return List of Business Unit names (from Product_Line__c.Practice__c)
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getBusinessUnits() {
        Set<String> buSet = new Set<String>();
        for (AggregateResult ar : [
            SELECT Practice__c val
            FROM Product_Line__c
            WHERE Practice__c != null
            GROUP BY Practice__c
        ]) {
            buSet.add((String) ar.get('val'));
        }
        return sortByBuOrder(buSet);
    }

    /**
     * @description Returns the ordered list of vertical names.
     * @return List of vertical display names
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getVerticals() {
        return VERTICAL_NAMES;
    }

    /** Priority ordering for Product Type dropdown — these appear first, then remaining alphabetically */
    private static final List<String> PRODUCT_TYPE_PRIORITY = new List<String>{
        'Software', 'Services', 'Support', 'Maintenance',
        'Software Discount (One-Time)', 'Services Discount'
    };

    /**
     * @description Returns distinct Product_Type__c and Pricing_Basis__c values
     *              from Product2 records. Normalizes "Software Discount (One Time)"
     *              to "Software Discount (One-Time)" for display consistency.
     *              Product Types are ordered with priority values first, then remaining alphabetically.
     * @return Map with keys 'productTypes' and 'pricingBases'
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getFilterPicklistValues() {
        Set<String> productTypes = new Set<String>();
        Set<String> pricingBases = new Set<String>();

        for (AggregateResult ar : [
            SELECT Product_Type__c val
            FROM Product2
            WHERE Product_Type__c != null
            GROUP BY Product_Type__c
            ORDER BY Product_Type__c
        ]) {
            String val = (String) ar.get('val');
            // Normalize variant spelling
            if (val == 'Software Discount (One Time)') {
                val = 'Software Discount (One-Time)';
            }
            productTypes.add(val);
        }

        for (AggregateResult ar : [
            SELECT Pricing_Basis__c val
            FROM Product2
            WHERE Pricing_Basis__c != null
            GROUP BY Pricing_Basis__c
            ORDER BY Pricing_Basis__c
        ]) {
            pricingBases.add((String) ar.get('val'));
        }

        // Build ordered Product Type list: priority values first, then remaining alphabetically
        List<String> orderedTypes = new List<String>();
        for (String priority : PRODUCT_TYPE_PRIORITY) {
            if (productTypes.contains(priority)) {
                orderedTypes.add(priority);
                productTypes.remove(priority);
            }
        }
        List<String> remainingTypes = new List<String>(productTypes);
        remainingTypes.sort();
        orderedTypes.addAll(remainingTypes);

        List<String> sortedBases = new List<String>(pricingBases);
        sortedBases.sort();

        return new Map<String, List<String>>{
            'productTypes' => orderedTypes,
            'pricingBases' => sortedBases
        };
    }

    /**
     * @description Main data method. Queries products, Block_Pricing__c (GTM Motion Tier)
     *              pricing data, and Meter Type records, then groups results into accordion
     *              groups with Active/Restricted sub-groups. Each product shows exactly one
     *              row per vertical using the vertical's default meter type.
     * @param filterMode 'businessUnit' or 'vertical'
     * @param filterValue The selected BU name or vertical name
     * @param productStatus 'Active', 'Inactive', or 'All'
     * @param productType Optional Product_Type__c filter (blank = all)
     * @param pricingBasis Optional Pricing_Basis__c filter (blank = all)
     * @return PricebookViewResult containing grouped product rows with pricing
     */
    @AuraEnabled
    public static PricebookViewResult getPricebookViewData(
        String filterMode, String filterValue, String productStatus,
        String productType, String pricingBasis
    ) {
        try {
            if (String.isBlank(filterMode) || String.isBlank(filterValue)) {
                AuraHandledException aheBlank = new AuraHandledException('Filter mode and value are required.');
                aheBlank.setMessage('Filter mode and value are required.');
                throw aheBlank;
            }

            // 1. Query products matching the filter criteria
            List<Product2> products = queryProducts(filterMode, filterValue, productStatus, productType, pricingBasis);

            if (products.isEmpty()) {
                return buildEmptyResult();
            }

            // 2. Collect product IDs and query pricing + meter type data in bulk
            Set<Id> productIds = new Set<Id>();
            for (Product2 p : products) {
                productIds.add(p.Id);
            }
            Map<Id, List<Block_Pricing__c>> pricingByProduct = queryPricingData(productIds);
            Map<Id, Block_Pricing__c> meterTypeByProduct = queryMeterTypeRecords(productIds);

            // 2b. Intapp Pricing fallback for products with no Block Pricing GTM data
            Set<String> fallbackProductCodes = new Set<String>();
            Map<String, Id> productCodeToId = new Map<String, Id>();
            for (Product2 p : products) {
                productCodeToId.put(p.ProductCode, p.Id);
                if (!pricingByProduct.containsKey(p.Id)) {
                    fallbackProductCodes.add(p.ProductCode);
                }
            }

            Map<Id, Map<String, Map<String, Map<String, Decimal>>>> intappPricingMaps =
                new Map<Id, Map<String, Map<String, Map<String, Decimal>>>>();
            if (!fallbackProductCodes.isEmpty()) {
                Map<String, List<Intapp_Pricing__c>> intappByCode = queryIntappPricingData(fallbackProductCodes);
                for (String code : intappByCode.keySet()) {
                    Id prodId = productCodeToId.get(code);
                    if (prodId != null) {
                        intappPricingMaps.put(prodId, buildIntappPricingMap(intappByCode.get(code)));
                    }
                }
            }

            // 3. Build grouped result based on filter mode
            if (filterMode == 'businessUnit') {
                return buildGroupedByVertical(products, pricingByProduct, meterTypeByProduct, intappPricingMaps, productStatus);
            } else {
                return buildGroupedByBusinessUnit(products, pricingByProduct, meterTypeByProduct, filterValue, intappPricingMaps);
            }

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            Nebula.Logger.error('PricebookView error: ' + e.getMessage())
                .addTag('PricebookView');
            Nebula.Logger.saveLog();
            AuraHandledException aheGeneric = new AuraHandledException(e.getMessage());
            aheGeneric.setMessage(e.getMessage());
            throw aheGeneric;
        }
    }

    // =========================================================================
    // Private — Query Methods
    // =========================================================================

    /**
     * @description Builds and executes a dynamic SOQL query for Product2 records
     *              based on the selected filter mode and criteria.
     */
    private static List<Product2> queryProducts(
        String filterMode, String filterValue, String productStatus,
        String productType, String pricingBasis
    ) {
        String query = 'SELECT ' + PRODUCT_QUERY_FIELDS + ' FROM Product2 WHERE ';
        List<String> conditions = new List<String>();

        // Always show only active products; exclude placeholder bundle products (-P suffix)
        conditions.add('IsActive = true');
        conditions.add('(NOT ProductCode LIKE \'%-P\')');

        // Mode-specific filter
        if (filterMode == 'businessUnit') {
            conditions.add('Business_Unit_New__c = \'' +
                String.escapeSingleQuotes(filterValue) + '\'');
            // Product status filter — require at least one vertical with matching status
            List<String> verticalFields = VERTICAL_FIELD_MAP.values();
            if (productStatus == 'Active') {
                List<String> orParts = new List<String>();
                for (String vf : verticalFields) {
                    orParts.add(vf + ' = \'Active\'');
                }
                conditions.add('(' + String.join(orParts, ' OR ') + ')');
            } else if (productStatus == 'Restricted') {
                List<String> orParts = new List<String>();
                for (String vf : verticalFields) {
                    orParts.add(vf + ' = \'Restricted\'');
                }
                conditions.add('(' + String.join(orParts, ' OR ') + ')');
            } else {
                // "All" — at least one vertical Active or Restricted
                List<String> orParts = new List<String>();
                for (String vf : verticalFields) {
                    orParts.add(vf + ' IN (\'Active\', \'Restricted\')');
                }
                conditions.add('(' + String.join(orParts, ' OR ') + ')');
            }
        } else if (filterMode == 'vertical') {
            String fieldName = VERTICAL_FIELD_MAP.get(filterValue);
            if (fieldName == null) {
                AuraHandledException aheInvalid = new AuraHandledException('Invalid vertical: ' + filterValue);
                aheInvalid.setMessage('Invalid vertical: ' + filterValue);
                throw aheInvalid;
            }
            // Filter by vertical status: Active, Restricted, or both
            if (productStatus == 'Active') {
                conditions.add(fieldName + ' = \'Active\'');
            } else if (productStatus == 'Restricted') {
                conditions.add(fieldName + ' = \'Restricted\'');
            } else {
                conditions.add(fieldName + ' IN (\'Active\', \'Restricted\')');
            }
        }

        // Product Type filter (handle "Software Discount (One-Time)" matching both spellings)
        if (String.isNotBlank(productType)) {
            if (productType == 'Software Discount (One-Time)') {
                conditions.add('Product_Type__c IN (\'Software Discount (One-Time)\', \'Software Discount (One Time)\')');
            } else {
                conditions.add('Product_Type__c = \'' +
                    String.escapeSingleQuotes(productType) + '\'');
            }
        }

        // Pricing Basis filter
        if (String.isNotBlank(pricingBasis)) {
            conditions.add('Pricing_Basis__c = \'' +
                String.escapeSingleQuotes(pricingBasis) + '\'');
        }

        if (conditions.isEmpty()) {
            conditions.add('Id != null');
        }

        query += String.join(conditions, ' AND ');
        query += ' ORDER BY ProductCode';
        query += ' LIMIT 500';

        return Database.query(query);
    }

    /**
     * @description Queries Block_Pricing__c records (Type = GTM Motion Tier) in bulk
     *              for all provided product IDs.
     * @return Map of Product ID → list of Block_Pricing__c records
     */
    private static Map<Id, List<Block_Pricing__c>> queryPricingData(Set<Id> productIds) {
        List<Block_Pricing__c> records = [
            SELECT Product__c, Block_Pricing_Meter_Type__c,
                   CurrencyIsoCode, Tier_Name__c, Price__c
            FROM Block_Pricing__c
            WHERE Product__c IN :productIds
              AND Type__c = 'GTM Motion Tier'
              AND Active__c = true
            ORDER BY Product__c, Block_Pricing_Meter_Type__c, CurrencyIsoCode, Tier_Name__c
        ];

        Map<Id, List<Block_Pricing__c>> result = new Map<Id, List<Block_Pricing__c>>();
        for (Block_Pricing__c r : records) {
            if (!result.containsKey(r.Product__c)) {
                result.put(r.Product__c, new List<Block_Pricing__c>());
            }
            result.get(r.Product__c).add(r);
        }
        return result;
    }

    /**
     * @description Queries Block_Pricing__c records (Type = Meter Type) in bulk.
     *              These records map each vertical to its default meter type per product.
     * @return Map of Product ID → Meter Type Block_Pricing__c record
     */
    private static Map<Id, Block_Pricing__c> queryMeterTypeRecords(Set<Id> productIds) {
        List<Block_Pricing__c> records = Database.query(
            'SELECT ' + METER_TYPE_QUERY_FIELDS +
            ' FROM Block_Pricing__c' +
            ' WHERE Product__c IN :productIds AND Type__c = \'Meter Type\''
        );

        Map<Id, Block_Pricing__c> result = new Map<Id, Block_Pricing__c>();
        for (Block_Pricing__c r : records) {
            result.put(r.Product__c, r);
        }
        return result;
    }

    /**
     * @description Queries Intapp_Pricing__c records for products that lack Block Pricing.
     *              Uses Product_Code__c (text match) to find records in the FY26_All_Products pricebook.
     * @param productCodes Set of product code strings to query
     * @return Map of Product_Code__c → list of Intapp_Pricing__c records
     */
    private static Map<String, List<Intapp_Pricing__c>> queryIntappPricingData(Set<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new Map<String, List<Intapp_Pricing__c>>();
        }

        List<Intapp_Pricing__c> records = [
            SELECT Product_Code__c, Meter_Type__c, CurrencyIsoCode, Tier__c, Price__c
            FROM Intapp_Pricing__c
            WHERE Product_Code__c IN :productCodes
              AND Price_Book__r.Name = :PRICEBOOK_NAME
            ORDER BY Product_Code__c, Meter_Type__c, CurrencyIsoCode
        ];

        Map<String, List<Intapp_Pricing__c>> result = new Map<String, List<Intapp_Pricing__c>>();
        for (Intapp_Pricing__c r : records) {
            if (!result.containsKey(r.Product_Code__c)) {
                result.put(r.Product_Code__c, new List<Intapp_Pricing__c>());
            }
            result.get(r.Product_Code__c).add(r);
        }
        return result;
    }

    // =========================================================================
    // Private — Grouping Methods
    // =========================================================================

    /**
     * @description Groups products by Vertical for the "Filter by Business Unit" mode.
     *              A single product may appear in multiple vertical groups based on its
     *              Is_Legal__c, Is_Accounting__c, etc. field values. Each product shows
     *              exactly one row per vertical using the vertical's default meter type.
     *              The productStatus filter is applied per-vertical: a product only appears
     *              under a vertical if its status in that vertical matches the filter.
     */
    private static PricebookViewResult buildGroupedByVertical(
        List<Product2> products,
        Map<Id, List<Block_Pricing__c>> pricingByProduct,
        Map<Id, Block_Pricing__c> meterTypeByProduct,
        Map<Id, Map<String, Map<String, Map<String, Decimal>>>> intappPricingMaps,
        String productStatus
    ) {
        // Map: verticalName → status → List<PricebookViewRow>
        Map<String, Map<String, List<PricebookViewRow>>> groupMap =
            new Map<String, Map<String, List<PricebookViewRow>>>();

        Set<Id> countedProducts = new Set<Id>();

        for (Product2 p : products) {
            Map<String, Map<String, Map<String, Decimal>>> pricingMap;
            if (pricingByProduct.containsKey(p.Id)) {
                pricingMap = buildPricingMap(pricingByProduct.get(p.Id));
            } else if (intappPricingMaps.containsKey(p.Id)) {
                pricingMap = intappPricingMaps.get(p.Id);
            } else {
                pricingMap = new Map<String, Map<String, Map<String, Decimal>>>();
            }
            Block_Pricing__c mtRecord = meterTypeByProduct.get(p.Id);

            for (String verticalName : VERTICAL_NAMES) {
                String fieldName = VERTICAL_FIELD_MAP.get(verticalName);
                String fieldValue = (String) p.get(fieldName);

                // Apply product status filter per-vertical
                Boolean includeInVertical = false;
                if (productStatus == 'Active') {
                    includeInVertical = (fieldValue == 'Active');
                } else if (productStatus == 'Restricted') {
                    includeInVertical = (fieldValue == 'Restricted');
                } else {
                    // 'All' — include both Active and Restricted
                    includeInVertical = (fieldValue == 'Active' || fieldValue == 'Restricted');
                }

                if (includeInVertical) {
                    if (!groupMap.containsKey(verticalName)) {
                        groupMap.put(verticalName, new Map<String, List<PricebookViewRow>>{
                            'all' => new List<PricebookViewRow>()
                        });
                    }

                    PricebookViewRow row = buildRowForVertical(
                        p, pricingMap, verticalName, mtRecord, fieldValue
                    );
                    groupMap.get(verticalName).get('all').add(row);
                    countedProducts.add(p.Id);
                }
            }
        }

        // Build ordered groups (consistent ordering by VERTICAL_NAMES)
        List<PricebookViewGroup> groups = new List<PricebookViewGroup>();
        for (String verticalName : VERTICAL_NAMES) {
            if (groupMap.containsKey(verticalName)) {
                Map<String, List<PricebookViewRow>> statusMap = groupMap.get(verticalName);
                PricebookViewGroup grp = new PricebookViewGroup();
                grp.groupName = verticalName;
                grp.groupKey = verticalName.toLowerCase().replace(' ', '');
                grp.subGroups = buildSubGroups(statusMap);
                grp.productCount = 0;
                for (String key : statusMap.keySet()) {
                    grp.productCount += statusMap.get(key).size();
                }
                groups.add(grp);
            }
        }

        PricebookViewResult result = new PricebookViewResult();
        result.groups = groups;
        result.totalProducts = countedProducts.size();
        return result;
    }

    /**
     * @description Groups products by Business Unit for the "Filter by Vertical" mode.
     *              Each product appears in exactly one BU group, sub-grouped by the
     *              selected vertical field value (Active or Restricted). Each product
     *              shows exactly one row using the selected vertical's default meter type.
     */
    private static PricebookViewResult buildGroupedByBusinessUnit(
        List<Product2> products,
        Map<Id, List<Block_Pricing__c>> pricingByProduct,
        Map<Id, Block_Pricing__c> meterTypeByProduct,
        String verticalName,
        Map<Id, Map<String, Map<String, Map<String, Decimal>>>> intappPricingMaps
    ) {
        String verticalField = VERTICAL_FIELD_MAP.get(verticalName);

        // Map: BU → status → List<PricebookViewRow>
        Map<String, Map<String, List<PricebookViewRow>>> groupMap =
            new Map<String, Map<String, List<PricebookViewRow>>>();
        List<String> orderedBUs = new List<String>();

        for (Product2 p : products) {
            String bu = p.Business_Unit_New__c;
            if (String.isBlank(bu)) {
                bu = 'Unassigned';
            }

            String status = (String) p.get(verticalField);
            if (status != 'Active' && status != 'Restricted') {
                continue;
            }

            if (!groupMap.containsKey(bu)) {
                groupMap.put(bu, new Map<String, List<PricebookViewRow>>{
                    'all' => new List<PricebookViewRow>()
                });
                orderedBUs.add(bu);
            }

            Map<String, Map<String, Map<String, Decimal>>> pricingMap;
            if (pricingByProduct.containsKey(p.Id)) {
                pricingMap = buildPricingMap(pricingByProduct.get(p.Id));
            } else if (intappPricingMaps.containsKey(p.Id)) {
                pricingMap = intappPricingMaps.get(p.Id);
            } else {
                pricingMap = new Map<String, Map<String, Map<String, Decimal>>>();
            }
            Block_Pricing__c mtRecord = meterTypeByProduct.get(p.Id);

            PricebookViewRow row = buildRowForVertical(
                p, pricingMap, verticalName, mtRecord, status
            );
            groupMap.get(bu).get('all').add(row);
        }

        List<String> sortedBUs = sortByBuOrder(new Set<String>(orderedBUs));

        List<PricebookViewGroup> groups = new List<PricebookViewGroup>();
        for (String bu : sortedBUs) {
            Map<String, List<PricebookViewRow>> statusMap = groupMap.get(bu);
            PricebookViewGroup grp = new PricebookViewGroup();
            grp.groupName = bu;
            grp.groupKey = bu.toLowerCase().replaceAll('[^a-z0-9]', '');
            grp.subGroups = buildSubGroups(statusMap);
            grp.productCount = 0;
            for (String key : statusMap.keySet()) {
                grp.productCount += statusMap.get(key).size();
            }
            groups.add(grp);
        }

        PricebookViewResult result = new PricebookViewResult();
        result.groups = groups;
        result.totalProducts = products.size();
        return result;
    }

    /**
     * @description Sorts a set of Business Unit names according to BU_ORDER priority,
     *              then appends any remaining values alphabetically.
     * @param buSet Set of Business Unit names to sort
     * @return Ordered list of Business Unit names
     */
    private static List<String> sortByBuOrder(Set<String> buSet) {
        List<String> sorted = new List<String>();
        Set<String> remaining = new Set<String>(buSet);
        for (String bu : BU_ORDER) {
            if (remaining.contains(bu)) {
                sorted.add(bu);
                remaining.remove(bu);
            }
        }
        if (!remaining.isEmpty()) {
            List<String> extras = new List<String>(remaining);
            extras.sort();
            sorted.addAll(extras);
        }
        return sorted;
    }

    // =========================================================================
    // Private — Row Building
    // =========================================================================

    /**
     * @description Builds a pricing map from Intapp_Pricing__c records (fallback).
     *              Same output structure as buildPricingMap: meterType → currency → tier → price.
     *              Normalizes Tier__c: null or 'Tier (none)' → 'None'.
     */
    private static Map<String, Map<String, Map<String, Decimal>>> buildIntappPricingMap(
        List<Intapp_Pricing__c> records
    ) {
        Map<String, Map<String, Map<String, Decimal>>> pricingMap =
            new Map<String, Map<String, Map<String, Decimal>>>();

        if (records != null) {
            for (Intapp_Pricing__c ip : records) {
                String mt = ip.Meter_Type__c;
                String curr = ip.CurrencyIsoCode;
                String tier = (ip.Tier__c == null || ip.Tier__c == NONE_TIER_INTAPP) ? 'None' : ip.Tier__c;

                if (!pricingMap.containsKey(mt)) {
                    pricingMap.put(mt, new Map<String, Map<String, Decimal>>());
                }
                if (!pricingMap.get(mt).containsKey(curr)) {
                    pricingMap.get(mt).put(curr, new Map<String, Decimal>());
                }
                pricingMap.get(mt).get(curr).put(tier, ip.Price__c);
            }
        }

        return pricingMap;
    }

    /**
     * @description Builds a pricing map from Block_Pricing__c records.
     *              Groups pricing by: meterType → currency → tier → price.
     */
    private static Map<String, Map<String, Map<String, Decimal>>> buildPricingMap(
        List<Block_Pricing__c> pricing
    ) {
        Map<String, Map<String, Map<String, Decimal>>> pricingMap =
            new Map<String, Map<String, Map<String, Decimal>>>();

        if (pricing != null) {
            for (Block_Pricing__c bp : pricing) {
                String mt = bp.Block_Pricing_Meter_Type__c;
                String curr = bp.CurrencyIsoCode;
                String tier = bp.Tier_Name__c == null ? 'None' : bp.Tier_Name__c;

                if (!pricingMap.containsKey(mt)) {
                    pricingMap.put(mt, new Map<String, Map<String, Decimal>>());
                }
                if (!pricingMap.get(mt).containsKey(curr)) {
                    pricingMap.get(mt).put(curr, new Map<String, Decimal>());
                }
                pricingMap.get(mt).get(curr).put(tier, bp.Price__c);
            }
        }

        return pricingMap;
    }

    /**
     * @description Builds a single row for a product in a specific vertical context.
     *              Uses the vertical's default meter type from the Meter Type record.
     *              For Legal: merges two meter type fields (USD/AUD and GBP/EUR).
     *              If meter types differ, USD/AUD columns use one meter type and
     *              GBP/EUR columns use the other. Display shows "TypeA / TypeB".
     */
    private static PricebookViewRow buildRowForVertical(
        Product2 product,
        Map<String, Map<String, Map<String, Decimal>>> pricingMap,
        String verticalName,
        Block_Pricing__c mtRecord,
        String verticalStatus
    ) {
        if (verticalName == 'Legal') {
            return buildLegalRow(product, pricingMap, mtRecord, verticalStatus);
        }

        // Non-Legal verticals: look up the single meter type field
        String meterFieldName = VERTICAL_METER_FIELD_MAP.get(verticalName);
        String defaultMeterType = null;
        if (mtRecord != null && meterFieldName != null) {
            defaultMeterType = (String) mtRecord.get(meterFieldName);
        }

        // If we have a default meter type, always use it (even without pricing data)
        if (String.isNotBlank(defaultMeterType)) {
            Map<String, Map<String, Decimal>> currTierMap = pricingMap.containsKey(defaultMeterType)
                ? pricingMap.get(defaultMeterType) : null;
            return buildRow(product, defaultMeterType, currTierMap, verticalStatus);
        }

        // Fallback: use first available meter type, or empty row
        if (!pricingMap.isEmpty()) {
            List<String> sortedMeterTypes = new List<String>(pricingMap.keySet());
            sortedMeterTypes.sort();
            String fallbackMt = sortedMeterTypes[0];
            return buildRow(product, fallbackMt, pricingMap.get(fallbackMt), verticalStatus);
        }

        return buildRow(product, '', null, verticalStatus);
    }

    /**
     * @description Builds a row for the Legal vertical with merged meter type logic.
     *              Legal has two meter type fields: Legal_meter_type_USD_AUD__c and Legal__c.
     *              - If both values are the same: single meter type label, all prices from that type
     *              - If different: label = "TypeA / TypeB", USD/AUD prices from TypeA, GBP/EUR from TypeB
     */
    private static PricebookViewRow buildLegalRow(
        Product2 product,
        Map<String, Map<String, Map<String, Decimal>>> pricingMap,
        Block_Pricing__c mtRecord,
        String verticalStatus
    ) {
        String usdAudMeterType = null;
        String gbpEurMeterType = null;

        if (mtRecord != null) {
            usdAudMeterType = (String) mtRecord.get('Legal_meter_type_USD_AUD__c');
            gbpEurMeterType = (String) mtRecord.get(LEGAL_GBP_EUR_FIELD);
        }

        // Determine display label
        String displayMeterType;
        if (String.isNotBlank(usdAudMeterType) && String.isNotBlank(gbpEurMeterType)) {
            if (usdAudMeterType == gbpEurMeterType) {
                displayMeterType = usdAudMeterType;
            } else {
                displayMeterType = usdAudMeterType + ' / ' + gbpEurMeterType;
            }
        } else if (String.isNotBlank(usdAudMeterType)) {
            displayMeterType = usdAudMeterType;
        } else if (String.isNotBlank(gbpEurMeterType)) {
            displayMeterType = gbpEurMeterType;
        } else {
            // No meter type data — fall back to first available
            if (!pricingMap.isEmpty()) {
                List<String> sortedMeterTypes = new List<String>(pricingMap.keySet());
                sortedMeterTypes.sort();
                return buildRow(product, sortedMeterTypes[0], pricingMap.get(sortedMeterTypes[0]), verticalStatus);
            }
            return buildRow(product, '', null, verticalStatus);
        }

        // Build the row with merged pricing
        PricebookViewRow row = new PricebookViewRow();
        row.productId = product.Id;
        row.productCode = product.ProductCode;
        row.productName = product.Name;
        row.productLine = product.Product_LineNew__r != null
            ? product.Product_LineNew__r.Name : '';
        row.productType = product.Product_Type__c;
        row.pricingBasis = product.Pricing_Basis__c;
        row.meterType = displayMeterType;
        row.isActive = product.IsActive;
        row.verticalStatus = verticalStatus;
        row.rowKey = product.Id + '_' + displayMeterType.replaceAll('[^a-zA-Z0-9]', '');
        row.prices = new List<PriceCell>();

        // Build 24 price cells, sourcing from the correct meter type per currency
        for (String curr : CURRENCIES) {
            // Determine which meter type to use for this currency
            String sourceMeterType;
            if (curr == 'USD' || curr == 'AUD') {
                sourceMeterType = usdAudMeterType;
            } else {
                sourceMeterType = gbpEurMeterType;
            }

            Map<String, Map<String, Decimal>> meterPricing =
                (String.isNotBlank(sourceMeterType) && pricingMap.containsKey(sourceMeterType))
                    ? pricingMap.get(sourceMeterType) : null;

            for (String tier : TIERS) {
                PriceCell cell = new PriceCell();
                cell.key = curr + '_' + tier;
                cell.currencyCode = curr;
                cell.tier = tier;
                cell.price = null;

                if (meterPricing != null
                    && meterPricing.containsKey(curr)
                    && meterPricing.get(curr).containsKey(tier)) {
                    cell.price = meterPricing.get(curr).get(tier);
                }

                row.prices.add(cell);
            }
        }

        return row;
    }

    /**
     * @description Builds a single PricebookViewRow with 24 price cells in fixed order:
     *              USD×EM1, USD×EM2, ..., USD×None, GBP×EM1, ..., AUD×None
     */
    private static PricebookViewRow buildRow(
        Product2 product,
        String meterType,
        Map<String, Map<String, Decimal>> currencyTierMap,
        String verticalStatus
    ) {
        PricebookViewRow row = new PricebookViewRow();
        row.productId = product.Id;
        row.productCode = product.ProductCode;
        row.productName = product.Name;
        row.productLine = product.Product_LineNew__r != null
            ? product.Product_LineNew__r.Name : '';
        row.productType = product.Product_Type__c;
        row.pricingBasis = product.Pricing_Basis__c;
        row.meterType = meterType;
        row.isActive = product.IsActive;
        row.verticalStatus = verticalStatus;
        row.rowKey = product.Id + '_' + (String.isNotBlank(meterType) ? meterType : 'none');
        row.prices = new List<PriceCell>();

        for (String curr : CURRENCIES) {
            for (String tier : TIERS) {
                PriceCell cell = new PriceCell();
                cell.key = curr + '_' + tier;
                cell.currencyCode = curr;
                cell.tier = tier;
                cell.price = null;

                if (currencyTierMap != null
                    && currencyTierMap.containsKey(curr)
                    && currencyTierMap.get(curr).containsKey(tier)) {
                    cell.price = currencyTierMap.get(curr).get(tier);
                }

                row.prices.add(cell);
            }
        }

        return row;
    }

    // =========================================================================
    // Private — Helpers
    // =========================================================================

    /**
     * @description Returns a single flat sub-group with all rows sorted by Pricing Basis
     *              priority (Tier based → % of ACV → Free → Quantity based → Other/Mixed),
     *              with Active products before Restricted within each basis group.
     */
    private static List<PricebookViewSubGroup> buildSubGroups(
        Map<String, List<PricebookViewRow>> statusMap
    ) {
        // Flatten all rows from all status groups
        List<PricebookViewRow> allRows = new List<PricebookViewRow>();
        for (String key : statusMap.keySet()) {
            List<PricebookViewRow> rows = statusMap.get(key);
            if (rows != null) {
                allRows.addAll(rows);
            }
        }

        // Bucket rows by Pricing Basis
        Map<String, List<PricebookViewRow>> basisMap = new Map<String, List<PricebookViewRow>>();
        for (PricebookViewRow row : allRows) {
            String basis = String.isNotBlank(row.pricingBasis) ? row.pricingBasis : 'Other/Mixed';
            if (!basisMap.containsKey(basis)) {
                basisMap.put(basis, new List<PricebookViewRow>());
            }
            basisMap.get(basis).add(row);
        }

        // Build flat sorted list: priority bases first, then remaining as Other/Mixed
        List<PricebookViewRow> sortedRows = new List<PricebookViewRow>();
        Set<String> added = new Set<String>();

        for (String priorityBasis : PRICING_BASIS_ORDER) {
            if (basisMap.containsKey(priorityBasis)) {
                sortedRows.addAll(sortRowsByStatus(basisMap.get(priorityBasis)));
                added.add(priorityBasis);
            }
        }

        // Remaining bases (Other/Mixed)
        for (String basis : basisMap.keySet()) {
            if (!added.contains(basis)) {
                sortedRows.addAll(sortRowsByStatus(basisMap.get(basis)));
            }
        }

        // Return single sub-group with no visible header
        PricebookViewSubGroup sg = new PricebookViewSubGroup();
        sg.status = '';
        sg.rows = sortedRows;
        return new List<PricebookViewSubGroup>{ sg };
    }

    /**
     * @description Sorts rows so Active products appear before Restricted,
     *              maintaining ProductCode order within each status group.
     */
    private static List<PricebookViewRow> sortRowsByStatus(List<PricebookViewRow> rows) {
        List<PricebookViewRow> activeRows = new List<PricebookViewRow>();
        List<PricebookViewRow> restrictedRows = new List<PricebookViewRow>();
        for (PricebookViewRow row : rows) {
            if (row.verticalStatus == 'Restricted') {
                restrictedRows.add(row);
            } else {
                activeRows.add(row);
            }
        }
        // Both lists already maintain ProductCode order from the original SOQL ORDER BY
        activeRows.addAll(restrictedRows);
        return activeRows;
    }

    /**
     * @description Returns an empty result with zero products and no groups.
     */
    private static PricebookViewResult buildEmptyResult() {
        PricebookViewResult result = new PricebookViewResult();
        result.groups = new List<PricebookViewGroup>();
        result.totalProducts = 0;
        return result;
    }

    // =========================================================================
    // Inner Classes
    // =========================================================================

    /**
     * @description Top-level result returned by getPricebookViewData.
     */
    public class PricebookViewResult {
        @AuraEnabled public List<PricebookViewGroup> groups;
        @AuraEnabled public Integer totalProducts;
    }

    /**
     * @description A group (one per Vertical when filtering by BU, or per BU when filtering by Vertical).
     */
    public class PricebookViewGroup {
        @AuraEnabled public String groupName;
        @AuraEnabled public String groupKey;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public List<PricebookViewSubGroup> subGroups;
    }

    /**
     * @description A sub-group within a group (Active or Restricted).
     */
    public class PricebookViewSubGroup {
        @AuraEnabled public String status;
        @AuraEnabled public List<PricebookViewRow> rows;
    }

    /**
     * @description A single row in the pricing table (one per Product x Vertical).
     */
    public class PricebookViewRow {
        @AuraEnabled public String productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String productLine;
        @AuraEnabled public String productType;
        @AuraEnabled public String pricingBasis;
        @AuraEnabled public String meterType;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String verticalStatus;
        @AuraEnabled public String rowKey;
        @AuraEnabled public List<PriceCell> prices;
    }

    /**
     * @description A single price cell in the 24-column pricing matrix.
     */
    public class PriceCell {
        @AuraEnabled public String key;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String tier;
        @AuraEnabled public Decimal price;
    }

    // =========================================================================
    // Product Detail Drawer
    // =========================================================================

    /**
     * @description Fetches detailed product info for the side drawer panel.
     *              Returns verticals with status & default meter types, plus
     *              Item Master fields for the selected product.
     * @param productId The Product2 Id
     * @return ProductDetailResult with verticals and itemMaster sections
     */
    @AuraEnabled(cacheable=true)
    public static ProductDetailResult getProductDetails(Id productId) {
        ProductDetailResult result = new ProductDetailResult();
        result.verticals = new List<VerticalDetail>();
        result.itemMasterFields = new List<DetailField>();

        // Query Product2 with vertical fields
        Product2 p = [
            SELECT Id, ProductCode, Name, Product_LineNew__r.Name, Product_Type__c,
                   Pricing_Basis__c, Revenue_Type__c, IsActive,
                   Is_Legal__c, Is_Accounting__c, Is_Consulting__c,
                   Is_IBA__c, Is_PCM__c, Is_Real_Assets__c, Iss_Corporate__c,
                   Item_Master_Product__c
            FROM Product2 WHERE Id = :productId LIMIT 1
        ];

        result.productCode = p.ProductCode;
        result.productName = p.Name;

        // Query Block_Pricing__c Meter Type record
        List<Block_Pricing__c> meterTypes = [
            SELECT Legal_meter_type_USD_AUD__c, Legal__c,
                   meter_type_Accounting__c, meter_type_Consulting__c,
                   meter_type_Corporate__c, meter_type_IBA__c,
                   meter_type_PCM__c, meter_type_RealAssets__c
            FROM Block_Pricing__c
            WHERE Product__c = :productId AND Type__c = 'Meter Type'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        Block_Pricing__c mt = meterTypes.isEmpty() ? null : meterTypes[0];

        // Build vertical rows
        result.verticals.add(buildVerticalRow('Legal (USD/AUD)', p.Is_Legal__c, mt != null ? mt.Legal_meter_type_USD_AUD__c : null));
        result.verticals.add(buildVerticalRow('Legal (GBP/EUR)', p.Is_Legal__c, mt != null ? mt.Legal__c : null));
        result.verticals.add(buildVerticalRow('Accounting', p.Is_Accounting__c, mt != null ? mt.meter_type_Accounting__c : null));
        result.verticals.add(buildVerticalRow('Consulting', p.Is_Consulting__c, mt != null ? mt.meter_type_Consulting__c : null));
        result.verticals.add(buildVerticalRow('IBA', p.Is_IBA__c, mt != null ? mt.meter_type_IBA__c : null));
        result.verticals.add(buildVerticalRow('PCM', p.Is_PCM__c, mt != null ? mt.meter_type_PCM__c : null));
        result.verticals.add(buildVerticalRow('Real Assets', p.Is_Real_Assets__c, mt != null ? mt.meter_type_RealAssets__c : null));
        result.verticals.add(buildVerticalRow('Corporate', p.Iss_Corporate__c, mt != null ? mt.meter_type_Corporate__c : null));

        // Query Item Master
        if (p.Item_Master_Product__c != null) {
            Item_Master_Product__c im = [
                SELECT Name, Item_Name__c, Active__c, Description__c,
                       Revenue_Type__c, Item_Revenue_Category__c,
                       Product_LineNew__r.Name,
                       NetSuite_Type__c, NetSuite_SubType__c, NetSuite_Internal_Id__c,
                       NetSuite_Product_Line_ID__c,
                       Income_Account__c, Deferred_Revenue_Account__c,
                       NetSuite_Allocation_Type__c, NetSuite_Billing_Schedule__c,
                       NetSuite_Can_be_fulfilled__c, NetSuite_Direct_Revenue_Posting__c,
                       NetSuite_Export_to_OpenAir__c, NetSuite_Include_Children__c,
                       NetSuite_Item_Type_For_Invoicing__c,
                       NetSuite_Revenue_Recognition_Template__c,
                       NetSuite_Tax_Schedule__c, NS_Error__c,
                       OpenAir_Billing_Rule__c, Rev_Rec_Forecast_Rule__c,
                       Revenue_Allocation_Group__c, Revenue_Recognition_Rule__c,
                       Sync_NetSuite__c, TaxCode__c, Create_Revenue_Plans_On__c
                FROM Item_Master_Product__c WHERE Id = :p.Item_Master_Product__c LIMIT 1
            ];

            result.itemMasterFields.add(new DetailField('IM Number', im.Name));
            result.itemMasterFields.add(new DetailField('Item Name', im.Item_Name__c));
            result.itemMasterFields.add(new DetailField('Active', im.Active__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('Description', im.Description__c));
            result.itemMasterFields.add(new DetailField('Revenue Type', im.Revenue_Type__c));
            result.itemMasterFields.add(new DetailField('Item Rev Category', im.Item_Revenue_Category__c));
            result.itemMasterFields.add(new DetailField('Product Line', im.Product_LineNew__r != null ? im.Product_LineNew__r.Name : null));
            result.itemMasterFields.add(new DetailField('NS Type', im.NetSuite_Type__c));
            result.itemMasterFields.add(new DetailField('NS SubType', im.NetSuite_SubType__c));
            result.itemMasterFields.add(new DetailField('NS Internal Id', im.NetSuite_Internal_Id__c));
            result.itemMasterFields.add(new DetailField('NS Product Line ID', im.NetSuite_Product_Line_ID__c));
            result.itemMasterFields.add(new DetailField('Income Account', im.Income_Account__c));
            result.itemMasterFields.add(new DetailField('Deferred Revenue', im.Deferred_Revenue_Account__c));
            result.itemMasterFields.add(new DetailField('Rev Rec Rule', im.Revenue_Recognition_Rule__c));
            result.itemMasterFields.add(new DetailField('Rev Rec Forecast', im.Rev_Rec_Forecast_Rule__c));
            result.itemMasterFields.add(new DetailField('Rev Rec Template', im.NetSuite_Revenue_Recognition_Template__c));
            result.itemMasterFields.add(new DetailField('Rev Alloc Group', im.Revenue_Allocation_Group__c));
            result.itemMasterFields.add(new DetailField('Create Rev Plans On', im.Create_Revenue_Plans_On__c));
            result.itemMasterFields.add(new DetailField('Allocation Type', im.NetSuite_Allocation_Type__c));
            result.itemMasterFields.add(new DetailField('Item Type Invoicing', im.NetSuite_Item_Type_For_Invoicing__c));
            result.itemMasterFields.add(new DetailField('Include Children', im.NetSuite_Include_Children__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('Can be Fulfilled', im.NetSuite_Can_be_fulfilled__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('Direct Rev Posting', im.NetSuite_Direct_Revenue_Posting__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('Export to OpenAir', im.NetSuite_Export_to_OpenAir__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('Billing Schedule', im.NetSuite_Billing_Schedule__c));
            result.itemMasterFields.add(new DetailField('OA Billing Rule', im.OpenAir_Billing_Rule__c));
            result.itemMasterFields.add(new DetailField('Tax Code', im.TaxCode__c));
            result.itemMasterFields.add(new DetailField('Tax Schedule', im.NetSuite_Tax_Schedule__c));
            result.itemMasterFields.add(new DetailField('Sync NetSuite', im.Sync_NetSuite__c == true ? 'Yes' : 'No'));
            result.itemMasterFields.add(new DetailField('NS Error', im.NS_Error__c));
        }

        return result;
    }

    private static VerticalDetail buildVerticalRow(String name, String status, String meterType) {
        VerticalDetail v = new VerticalDetail();
        v.name = name;
        v.status = String.isNotBlank(status) ? status : '—';
        v.meterType = String.isNotBlank(meterType) ? meterType : '—';
        v.statusClass = status == 'Active' ? 'status-pill status-pill--active'
                       : status == 'Restricted' ? 'status-pill status-pill--restricted'
                       : 'status-pill status-pill--none';
        return v;
    }

    /** Result for the product detail drawer */
    public class ProductDetailResult {
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public List<VerticalDetail> verticals;
        @AuraEnabled public List<DetailField> itemMasterFields;
    }

    /** A vertical row with status and meter type */
    public class VerticalDetail {
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String meterType;
        @AuraEnabled public String statusClass;
    }

    /** A label/value pair for the Item Master detail section */
    public class DetailField {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public DetailField(String label, String value) {
            this.label = label;
            this.value = String.isNotBlank(value) ? value : '—';
        }
    }
}