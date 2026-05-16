/**
 * @description Controller for the Pricebook Launch Wizard in the SKU Management App.
 *              Provides methods for a 4-phase wizard:
 *              Phase 1 - Pricebook selection/creation
 *              Phase 2 - One-time setup of PricebookEntry + SBQQ__Dimension__c (async)
 *              Phase 3 - CSV upload validation
 *              Phase 4 - Pricing data transformation into Intapp_Pricing__c + Block_Pricing__c
 * @author  Claude Code
 * @date    2026-02-26
 */
public with sharing class PricebookWizardController {

    private static final List<String> CURRENCIES = new List<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final List<String> TIERS      = new List<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};
    private static final String NONE_TIER_INTAPP  = 'Tier (none)';
    private static final Integer EXPECTED_COLUMNS  = 10;

    private static final Set<String> VALID_CURRENCIES = new Set<String>{'USD', 'GBP', 'EUR', 'AUD'};
    private static final Set<String> VALID_TIERS      = new Set<String>{'EM1', 'EM2', 'EM3', 'EM4', 'EM5', 'None'};

    private static final Set<String> DIMENSION_PRODUCT_TYPES = new Set<String>{
        'Software', 'Support', 'Maintenance'
    };

    private static final String TIER_BASED = 'Tier based';

    /***********************************************************************************************
     *
     * Phase 1 - Pricebook Selection / Creation
     *
     ***********************************************************************************************/

    /**
     * @description Returns active Pricebook2 records with entry counts for the selection table.
     * @return List of PricebookInfo wrappers
     */
    @AuraEnabled
    public static List<PricebookInfo> getActivePricebooks() {
        try {
            List<Pricebook2> pricebooks = [
                SELECT Id, Name, IsActive, CreatedDate
                FROM Pricebook2
                WHERE IsActive = true AND IsStandard = false
                ORDER BY Name ASC
            ];

            // Count PricebookEntries per pricebook
            Map<Id, Integer> entryCounts = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Pricebook2Id, COUNT(Id) cnt
                FROM PricebookEntry
                WHERE Pricebook2Id IN :pricebooks AND IsActive = true
                GROUP BY Pricebook2Id
            ]) {
                entryCounts.put((Id) ar.get('Pricebook2Id'), (Integer) ar.get('cnt'));
            }

            List<PricebookInfo> results = new List<PricebookInfo>();
            for (Pricebook2 pb : pricebooks) {
                PricebookInfo info = new PricebookInfo();
                info.id = pb.Id;
                info.name = pb.Name;
                info.isActive = pb.IsActive;
                info.entryCount = entryCounts.containsKey(pb.Id) ? entryCounts.get(pb.Id) : 0;
                info.createdDate = pb.CreatedDate;
                results.add(info);
            }

            return results;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Deactivates a Pricebook2 record by setting IsActive = false.
     * @param pricebookId Id of the pricebook to deactivate
     */
    @AuraEnabled
    public static void deactivatePricebook(Id pricebookId) {
        try {
            if (pricebookId == null) {
                throw new AuraHandledException('Pricebook Id is required.');
            }

            Pricebook2 pb = [SELECT Id, Name, IsActive FROM Pricebook2 WHERE Id = :pricebookId LIMIT 1];
            pb.IsActive = false;
            update pb;

            Nebula.Logger.info('Pricebook deactivated: ' + pb.Name)
                .addTag('PricebookWizard')
                .setRecordId(pb.Id);
            Nebula.Logger.saveLog();
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Creates a new active Pricebook2 record.
     * @param name The name for the new pricebook
     * @return Id of the newly created Pricebook2
     */
    @AuraEnabled
    public static Id createPricebook(String name) {
        try {
            if (String.isBlank(name)) {
                throw new AuraHandledException('Pricebook name is required.');
            }

            // Check for duplicate name
            List<Pricebook2> existing = [
                SELECT Id FROM Pricebook2 WHERE Name = :name LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException('A pricebook with the name "' + name + '" already exists.');
            }

            Pricebook2 pb = new Pricebook2(
                Name = name,
                IsActive = true
            );
            insert pb;

            Nebula.Logger.info('Created new Pricebook: ' + name)
                .addTag('PricebookWizard')
                .setRecordId(pb.Id);
            Nebula.Logger.saveLog();

            return pb.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /***********************************************************************************************
     *
     * Phase 2 - One-Time Setup (async PricebookEntry + Dimension creation)
     *
     ***********************************************************************************************/

    /**
     * @description Enqueues the PricebookSetupQueueable to create PricebookEntry and
     *              SBQQ__Dimension__c records for the given pricebook.
     * @param pricebookId The Id of the pricebook to set up
     * @return Id of the enqueued AsyncApexJob
     */
    @AuraEnabled
    public static Id startPricebookSetup(Id pricebookId) {
        try {
            if (pricebookId == null) {
                throw new AuraHandledException('Pricebook Id is required.');
            }

            Id jobId = System.enqueueJob(
                new PricebookSetupQueueable(pricebookId, 'PRICEBOOK_ENTRIES', 0)
            );

            Nebula.Logger.info('Started pricebook setup job: ' + jobId)
                .addTag('PricebookWizard')
                .setRecordId(pricebookId);
            Nebula.Logger.saveLog();

            return jobId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Checks the status of the async pricebook setup job.
     * @param jobId AsyncApexJob Id to check
     * @return SetupStatusResult with current status and progress counts
     */
    @AuraEnabled
    public static SetupStatusResult getSetupStatus(Id jobId) {
        try {
            SetupStatusResult result = new SetupStatusResult();

            if (jobId == null) {
                result.status = 'Failed';
                result.message = 'No job Id provided.';
                return result;
            }

            List<AsyncApexJob> jobs = [
                SELECT Status, NumberOfErrors, ExtendedStatus, JobType, CreatedDate
                FROM AsyncApexJob
                WHERE Id = :jobId
                LIMIT 1
            ];

            if (jobs.isEmpty()) {
                result.status = 'Unknown';
                result.message = 'Job not found.';
                return result;
            }

            AsyncApexJob job = jobs[0];
            result.status = job.Status;
            result.message = String.isNotBlank(job.ExtendedStatus)
                ? job.ExtendedStatus
                : 'Job is ' + job.Status.toLowerCase() + '...';

            // Check if there are any chained jobs still running
            if (job.Status == 'Completed') {
                // Check for chained jobs (newer queueable jobs enqueued after this one)
                List<AsyncApexJob> chainedJobs = [
                    SELECT Id, Status, ExtendedStatus
                    FROM AsyncApexJob
                    WHERE JobType = 'Queueable'
                      AND ApexClass.Name = 'PricebookSetupQueueable'
                      AND CreatedDate >= :job.CreatedDate
                      AND Id != :jobId
                      AND Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (!chainedJobs.isEmpty()) {
                    result.status = 'Processing';
                    result.message = 'Processing next batch...';
                    result.chainedJobId = chainedJobs[0].Id;
                }
            }

            return result;
        } catch (Exception e) {
            SetupStatusResult result = new SetupStatusResult();
            result.status = 'Failed';
            result.message = e.getMessage();
            return result;
        }
    }

    /***********************************************************************************************
     *
     * Phase 3 - CSV Upload Validation
     *
     ***********************************************************************************************/

    /**
     * @description Validates CSV content before processing. Checks column count, required fields,
     *              valid currencies/tiers, numeric prices, and Product Id existence.
     * @param csvContent Raw CSV string uploaded by user
     * @return ValidationResult with errors, warnings, and preview rows
     */
    @AuraEnabled
    public static ValidationResult validateCsvUpload(String csvContent) {
        try {
            ValidationResult result = new ValidationResult();
            result.isValid = true;
            result.errors = new List<String>();
            result.warnings = new List<String>();
            result.previewRows = new List<List<String>>();

            if (String.isBlank(csvContent)) {
                result.isValid = false;
                result.errors.add('CSV content is empty.');
                return result;
            }

            List<String> rows = CsvUtilityService.splitIntoRows(csvContent);
            if (rows.isEmpty()) {
                result.isValid = false;
                result.errors.add('No rows found in CSV file.');
                return result;
            }

            // Parse and validate header row
            List<String> headerCols = CsvUtilityService.parseRow(rows[0]);
            if (headerCols.size() != EXPECTED_COLUMNS) {
                result.isValid = false;
                result.errors.add('Header row must have ' + EXPECTED_COLUMNS + ' columns, found ' + headerCols.size() + '.');
                return result;
            }

            // Collect all Product Ids from data rows for bulk lookup
            Set<String> productIds = new Set<String>();
            Integer dataRowCount = 0;

            for (Integer i = 1; i < rows.size(); i++) {
                String row = rows[i];
                if (String.isBlank(row)) continue;

                List<String> cols = CsvUtilityService.parseRow(row);
                dataRowCount++;

                // Column count validation
                if (cols.size() != EXPECTED_COLUMNS) {
                    result.isValid = false;
                    result.errors.add('Row ' + (i + 1) + ': Expected ' + EXPECTED_COLUMNS + ' columns, found ' + cols.size() + '.');
                    if (result.errors.size() >= 20) {
                        result.errors.add('Too many errors. Showing first 20 only.');
                        break;
                    }
                    continue;
                }

                String productId   = cols[0];
                String productCode = cols[1];
                String meterType   = cols[2];
                String currCode    = cols[3];
                String tier        = cols[4];
                String priceStr    = cols[5];

                // Required field checks
                Boolean validProductId = false;
                if (String.isBlank(productId)) {
                    result.errors.add('Row ' + (i + 1) + ': Product Id is required.');
                    result.isValid = false;
                } else if (productId.length() != 15 && productId.length() != 18) {
                    result.errors.add('Row ' + (i + 1) + ': Invalid Product Id "' + productId + '". Must be a 15 or 18 character Salesforce Id.');
                    result.isValid = false;
                } else {
                    // Verify it's a valid Salesforce Id by attempting cast
                    try {
                        Id testId = Id.valueOf(productId);
                        validProductId = true;
                    } catch (Exception ex) {
                        result.errors.add('Row ' + (i + 1) + ': Invalid Product Id "' + productId + '". Not a valid Salesforce Id.');
                        result.isValid = false;
                    }
                }
                if (String.isBlank(meterType)) {
                    result.errors.add('Row ' + (i + 1) + ': Meter Type is required.');
                    result.isValid = false;
                }

                // Currency validation
                if (!VALID_CURRENCIES.contains(currCode)) {
                    result.errors.add('Row ' + (i + 1) + ': Invalid currency "' + currCode + '". Must be USD, GBP, EUR, or AUD.');
                    result.isValid = false;
                }

                // Tier validation
                if (String.isNotBlank(tier) && !VALID_TIERS.contains(tier)) {
                    result.errors.add('Row ' + (i + 1) + ': Invalid tier "' + tier + '". Must be EM1-EM5 or None.');
                    result.isValid = false;
                }

                // Price validation
                if (String.isNotBlank(priceStr)) {
                    try {
                        Decimal price = Decimal.valueOf(priceStr);
                        if (price < 0) {
                            result.warnings.add('Row ' + (i + 1) + ': Negative price ' + priceStr + '.');
                        }
                    } catch (Exception e) {
                        result.errors.add('Row ' + (i + 1) + ': Invalid price "' + priceStr + '". Must be numeric.');
                        result.isValid = false;
                    }
                }

                // Only add valid-format Ids for the existence check query
                if (validProductId) {
                    productIds.add(productId);
                }

                // Collect preview rows (first 10 data rows)
                if (result.previewRows.size() < 10) {
                    result.previewRows.add(cols);
                }

                if (result.errors.size() >= 20) {
                    result.errors.add('Too many errors. Showing first 20 only.');
                    break;
                }
            }

            result.rowCount = dataRowCount;

            // Validate Product Ids exist in the system
            if (!productIds.isEmpty()) {
                Set<Id> existingIds = new Set<Id>();
                for (Product2 p : [
                    SELECT Id FROM Product2
                    WHERE Id IN :productIds AND IsActive = true
                ]) {
                    existingIds.add(p.Id);
                }

                for (String pid : productIds) {
                    if (!existingIds.contains(pid)) {
                        result.errors.add('Product Id "' + pid + '" not found or inactive.');
                        result.isValid = false;
                    }
                }
            }

            result.headerRow = headerCols;
            return result;

        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /***********************************************************************************************
     *
     * Phase 4 - Pricing Data Processing
     *
     ***********************************************************************************************/

    /**
     * @description Transforms validated CSV data into Intapp_Pricing__c and Block_Pricing__c records.
     *              Block_Pricing__c is only created for products with Pricing_Basis__c = 'Tier Based'.
     *              If the product is Eligible_For_Premium__c = true, sets Premium_price__c = 1.2 * Price.
     * @param csvContent Raw CSV string (already validated via validateCsvUpload)
     * @param pricebookId The selected/created Pricebook2 Id
     * @return ProcessingResult with success/error/skipped counts per object
     */
    @AuraEnabled
    public static ProcessingResult processPricingUpload(String csvContent, Id pricebookId) {
        try {
            ProcessingResult result = new ProcessingResult();

            if (String.isBlank(csvContent) || pricebookId == null) {
                throw new AuraHandledException('CSV content and Pricebook Id are required.');
            }

            List<String> rows = CsvUtilityService.splitIntoRows(csvContent);

            // Collect all Product Ids for bulk lookup
            Set<String> productIds = new Set<String>();
            List<PricingUploadRow> parsedRows = new List<PricingUploadRow>();

            for (Integer i = 1; i < rows.size(); i++) {
                if (String.isBlank(rows[i])) continue;
                List<String> cols = CsvUtilityService.parseRow(rows[i]);
                if (cols.size() != EXPECTED_COLUMNS) continue;

                PricingUploadRow row = new PricingUploadRow();
                row.productId   = cols[0];
                row.productCode = cols[1];
                row.meterType   = cols[2];
                row.currCode    = cols[3];
                row.tier        = cols[4];
                row.price       = String.isNotBlank(cols[5]) ? Decimal.valueOf(cols[5]) : 0;
                row.legalSales  = parseBool(cols[6]);
                row.acSales     = parseBool(cols[7]);
                row.fsSales     = parseBool(cols[8]);
                row.opsOnly     = parseBool(cols[9]);

                productIds.add(row.productId);
                parsedRows.add(row);
            }

            // Query product details by Id: Pricing_Basis__c, Eligible_For_Premium__c, ProductCode
            Map<Id, Product2> productsById = new Map<Id, Product2>();
            for (Product2 p : [
                SELECT Id, ProductCode, Pricing_Basis__c, Eligible_For_Premium__c
                FROM Product2
                WHERE Id IN :productIds AND IsActive = true
            ]) {
                productsById.put(p.Id, p);
            }

            // Build record lists
            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            List<Block_Pricing__c> blockRecords = new List<Block_Pricing__c>();
            Integer skippedBlockCount = 0;

            for (PricingUploadRow row : parsedRows) {
                Product2 prod = productsById.get(row.productId);
                if (prod == null) continue;

                // Intapp_Pricing__c - created for ALL rows
                String intappTier = (row.tier == 'None') ? NONE_TIER_INTAPP : row.tier;
                String resolvedCode = String.isNotBlank(row.productCode) ? row.productCode : prod.ProductCode;
                Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                    Product__c         = prod.Id,
                    Product_Code__c    = resolvedCode,
                    Meter_Type__c      = row.meterType,
                    CurrencyIsoCode    = row.currCode,
                    Tier__c            = intappTier,
                    Price__c           = row.price,
                    Price_Book__c      = pricebookId,
                    Legal_Sales__c     = row.legalSales,
                    A_C_Sales__c       = row.acSales,
                    FS_Sales__c        = row.fsSales,
                    Ops_Only__c        = row.opsOnly
                );

                // Premium Price: if product is eligible, set Premium_price__c = 1.2 * Price
                if (prod.Eligible_For_Premium__c == true && row.price != null && row.price > 0) {
                    intapp.Premium_price__c = (row.price * 1.2).setScale(2, RoundingMode.HALF_UP);
                }

                intappRecords.add(intapp);

                // Block_Pricing__c - ONLY for Tier Based products
                if (TIER_BASED.equalsIgnoreCase(prod.Pricing_Basis__c)) {
                    Block_Pricing__c block = new Block_Pricing__c(
                        Product__c                  = prod.Id,
                        Block_Pricing_Meter_Type__c = row.meterType,
                        CurrencyIsoCode             = row.currCode,
                        Tier_Name__c                = (row.tier == 'None') ? null : row.tier,
                        Price__c                    = row.price,
                        Type__c                     = 'GTM Motion Tier',
                        Active__c                   = true
                    );
                    blockRecords.add(block);
                } else {
                    skippedBlockCount++;
                }
            }

            // DML with partial success
            result.intappResult = performPartialInsert(intappRecords);
            result.blockResult = performPartialInsert(blockRecords);
            result.blockSkippedCount = skippedBlockCount;
            result.totalRowsProcessed = parsedRows.size();

            // Populate Gearset External Id on successfully-inserted records
            populateGearsetExternalIds(intappRecords, result.intappResult);
            populateBlockGearsetExternalIds(blockRecords, result.blockResult);

            Nebula.Logger.info(
                'Pricebook Wizard Phase 4 complete. Intapp: ' + result.intappResult.successCount +
                '/' + intappRecords.size() + ', Block: ' + result.blockResult.successCount +
                '/' + blockRecords.size() + ', Skipped: ' + skippedBlockCount
            ).addTag('PricebookWizard').setRecordId(pricebookId);
            Nebula.Logger.saveLog();

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /***********************************************************************************************
     *
     * Phase 3/4 - Excel (.xlsx) Upload Validation & Processing
     *
     ***********************************************************************************************/

    /**
     * @description Validates parsed Excel upload data (JSON from LWC).
     *              Checks: Product Ids exist and active, meter types populated,
     *              prices are non-negative, and total price entries within DML limits.
     * @param uploadJson JSON string of List<ExcelUploadRow> parsed by SheetJS on the client
     * @return ExcelValidationResult with errors, warnings, and preview
     */
    @AuraEnabled
    public static ExcelValidationResult validateExcelUpload(String uploadJson) {
        try {
            ExcelValidationResult result = new ExcelValidationResult();
            result.isValid = true;
            result.errors = new List<String>();
            result.warnings = new List<String>();
            result.previewRows = new List<ExcelPreviewRow>();

            if (String.isBlank(uploadJson)) {
                result.isValid = false;
                result.errors.add('Upload data is empty.');
                return result;
            }

            List<ExcelUploadRow> rows = (List<ExcelUploadRow>) JSON.deserialize(
                uploadJson, List<ExcelUploadRow>.class
            );

            if (rows.isEmpty()) {
                result.isValid = false;
                result.errors.add('No data rows found in Excel file.');
                return result;
            }

            result.rowCount = rows.size();

            // Collect Product Ids for bulk validation
            Set<String> productIds = new Set<String>();
            Integer totalPriceEntries = 0;

            for (ExcelUploadRow row : rows) {
                Integer rowNum = row.rowNumber != null ? row.rowNumber : 0;

                // Validate Product Id (SFDC ID)
                if (String.isBlank(row.productId)) {
                    result.errors.add('Row ' + rowNum + ': SFDC ID is required.');
                    result.isValid = false;
                } else {
                    try {
                        Id testId = Id.valueOf(row.productId);
                        productIds.add(row.productId);
                    } catch (Exception ex) {
                        result.errors.add('Row ' + rowNum + ': Invalid SFDC ID "' + row.productId + '".');
                        result.isValid = false;
                    }
                }

                // Validate Meter Type
                if (String.isBlank(row.meterType)) {
                    result.errors.add('Row ' + rowNum + ': Meter Type is required.');
                    result.isValid = false;
                }

                // Count non-null prices and validate
                Integer priceCount = 0;
                Decimal samplePrice = null;
                if (row.prices != null) {
                    for (PriceEntry pe : row.prices) {
                        if (pe.price != null) {
                            priceCount++;
                            totalPriceEntries++;
                            if (pe.price < 0) {
                                result.warnings.add('Row ' + rowNum + ': Negative price ' + pe.price +
                                    ' for ' + pe.currencyCode + '/' + pe.tier + '.');
                            }
                            if (samplePrice == null && pe.currencyCode == 'USD' && pe.tier == 'EM1') {
                                samplePrice = pe.price;
                            }
                        }
                    }
                }

                // Warn if row has zero prices
                if (priceCount == 0) {
                    result.warnings.add('Row ' + rowNum + ' (' + row.productCode + '): No prices found.');
                }

                // Build preview (first 10)
                if (result.previewRows.size() < 10) {
                    ExcelPreviewRow preview = new ExcelPreviewRow();
                    preview.productCode = row.productCode;
                    preview.productId = row.productId;
                    preview.meterType = row.meterType;
                    preview.salesChannel = row.salesChannel;
                    preview.priceCount = priceCount;
                    preview.samplePrice = samplePrice != null ? String.valueOf(samplePrice) : '-';
                    result.previewRows.add(preview);
                }

                if (result.errors.size() >= 20) {
                    result.errors.add('Too many errors. Showing first 20 only.');
                    break;
                }
            }

            result.priceEntryCount = totalPriceEntries;

            // Governor limit guard: each price creates Intapp + possibly Block + GearsetExternalId updates
            if (totalPriceEntries > 4500) {
                result.isValid = false;
                result.errors.add('File contains ' + totalPriceEntries + ' price entries. Maximum is 4,500 per upload. Please split the file.');
            }

            // Validate Product Ids exist in the system (bulk query)
            if (!productIds.isEmpty()) {
                Set<Id> existingIds = new Set<Id>();
                for (Product2 p : [
                    SELECT Id FROM Product2
                    WHERE Id IN :productIds AND IsActive = true
                ]) {
                    existingIds.add(p.Id);
                }
                for (String pid : productIds) {
                    if (!existingIds.contains(pid)) {
                        result.errors.add('Product Id "' + pid + '" not found or inactive.');
                        result.isValid = false;
                    }
                }
            }

            return result;

        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Processes validated Excel upload data into Intapp_Pricing__c and Block_Pricing__c records.
     *              Each ExcelUploadRow (one product x one meter type) is expanded into up to 24 individual
     *              price entries. Block_Pricing__c is created only for products with Pricing_Basis__c = 'Tier based'.
     * @param uploadJson JSON string of List<ExcelUploadRow>
     * @param pricebookId The selected/created Pricebook2 Id
     * @return ProcessingResult with success/error/skipped counts
     */
    @AuraEnabled
    public static ProcessingResult processExcelUpload(String uploadJson, Id pricebookId) {
        try {
            ProcessingResult result = new ProcessingResult();

            if (String.isBlank(uploadJson) || pricebookId == null) {
                throw new AuraHandledException('Upload data and Pricebook Id are required.');
            }

            List<ExcelUploadRow> rows = (List<ExcelUploadRow>) JSON.deserialize(
                uploadJson, List<ExcelUploadRow>.class
            );

            // Collect all Product Ids for bulk lookup
            Set<String> productIds = new Set<String>();
            for (ExcelUploadRow row : rows) {
                if (String.isNotBlank(row.productId)) {
                    productIds.add(row.productId);
                }
            }

            // Query product details
            Map<Id, Product2> productsById = new Map<Id, Product2>();
            for (Product2 p : [
                SELECT Id, ProductCode, Pricing_Basis__c, Eligible_For_Premium__c
                FROM Product2
                WHERE Id IN :productIds AND IsActive = true
            ]) {
                productsById.put(p.Id, p);
            }

            // Get pricebook info for dynamic naming
            Pricebook2 pb = [SELECT Name FROM Pricebook2 WHERE Id = :pricebookId LIMIT 1];
            String pricebookName = pb.Name;
            String fyCode = extractFiscalYearCode(pricebookName);

            // Build record lists
            List<Intapp_Pricing__c> intappRecords = new List<Intapp_Pricing__c>();
            List<Block_Pricing__c>  blockRecords  = new List<Block_Pricing__c>();
            Integer skippedBlockCount = 0;

            for (ExcelUploadRow row : rows) {
                Product2 prod = productsById.get(row.productId);
                if (prod == null) continue;

                Boolean isTierBased = TIER_BASED.equalsIgnoreCase(prod.Pricing_Basis__c);
                String resolvedCode = String.isNotBlank(row.productCode) ? row.productCode : prod.ProductCode;
                String op4iAbbrev = deriveExcelOp4iAbbrev(row);

                if (row.prices == null) continue;

                for (PriceEntry pe : row.prices) {
                    if (pe.price == null) continue;

                    String intappTier = (pe.tier == 'None') ? NONE_TIER_INTAPP : pe.tier;

                    // Auto-generate Name: FYCode-ProductCode-MeterType-Currency-OP4I-Tier
                    String intappName = fyCode + '-' + resolvedCode + '-' +
                                        row.meterType + '-' + pe.currencyCode +
                                        (String.isNotBlank(op4iAbbrev) ? '-' + op4iAbbrev : '') +
                                        '-' + intappTier;
                    // Truncate to 80 chars (Salesforce Name field limit)
                    if (intappName.length() > 80) {
                        intappName = intappName.substring(0, 80);
                    }

                    Intapp_Pricing__c intapp = new Intapp_Pricing__c(
                        Name               = intappName,
                        Product__c         = prod.Id,
                        Product_Code__c    = resolvedCode,
                        Meter_Type__c      = row.meterType,
                        CurrencyIsoCode    = pe.currencyCode,
                        Tier__c            = intappTier,
                        Price__c           = pe.price,
                        Price_Book__c      = pricebookId,
                        Price_book_rule__c = pricebookName,
                        Legal_Sales__c     = row.legalSales == true,
                        A_C_Sales__c       = row.acSales == true,
                        FS_Sales__c        = row.fsSales == true,
                        Corporate_Sales__c = row.corporateSales == true,
                        Ops_Only__c        = row.opsOnly == true
                    );

                    // Premium Price
                    if (prod.Eligible_For_Premium__c == true && pe.price > 0) {
                        intapp.Premium_price__c = (pe.price * 1.2).setScale(2, RoundingMode.HALF_UP);
                    }

                    intappRecords.add(intapp);

                    // Block_Pricing__c - only for Tier Based products
                    if (isTierBased) {
                        blockRecords.add(new Block_Pricing__c(
                            Product__c                  = prod.Id,
                            Product_Code__c             = resolvedCode,
                            Block_Pricing_Meter_Type__c = row.meterType,
                            CurrencyIsoCode             = pe.currencyCode,
                            Tier_Name__c                = (pe.tier == 'None') ? null : pe.tier,
                            Price__c                    = pe.price,
                            Type__c                     = 'GTM Motion Tier',
                            Active__c                   = true,
                            Fiscal_Year__c              = fyCode,
                            Price_Book__c               = pricebookId,
                            Lower_Bound__c              = 0,
                            Upper_Bound__c              = 999999999
                        ));
                    } else {
                        skippedBlockCount++;
                    }
                }
            }

            // DML with partial success
            result.intappResult = performPartialInsert(intappRecords);
            result.blockResult  = performPartialInsert(blockRecords);
            result.blockSkippedCount = skippedBlockCount;
            result.totalRowsProcessed = rows.size();

            // Populate Gearset External Ids
            populateGearsetExternalIds(intappRecords, result.intappResult);
            populateBlockGearsetExternalIds(blockRecords, result.blockResult);

            Nebula.Logger.info(
                'Pricebook Wizard Excel upload complete. Intapp: ' + result.intappResult.successCount +
                '/' + intappRecords.size() + ', Block: ' + result.blockResult.successCount +
                '/' + blockRecords.size() + ', Skipped: ' + skippedBlockCount
            ).addTag('PricebookWizard').setRecordId(pricebookId);
            Nebula.Logger.saveLog();

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    // =========================================================================
    // Quantity Pricing Upload (Employee Compliance Block_Pricing__c)
    // =========================================================================

    /**
     * @description Validates parsed Quantity Pricing Excel upload data (JSON from LWC).
     *              Checks: Product Ids exist and active, meter types populated,
     *              bounds valid (lower < upper), prices non-negative, and total within DML limits.
     * @param uploadJson JSON string of List<QuantityUploadRow> parsed by SheetJS on the client
     * @return ExcelValidationResult with errors, warnings, and preview
     */
    @AuraEnabled
    public static ExcelValidationResult validateQuantityExcelUpload(String uploadJson) {
        try {
            ExcelValidationResult result = new ExcelValidationResult();
            result.isValid = true;
            result.errors = new List<String>();
            result.warnings = new List<String>();
            result.previewRows = new List<ExcelPreviewRow>();

            if (String.isBlank(uploadJson)) {
                result.isValid = false;
                result.errors.add('Upload data is empty.');
                return result;
            }

            List<QuantityUploadRow> rows = (List<QuantityUploadRow>) JSON.deserialize(
                uploadJson, List<QuantityUploadRow>.class
            );

            if (rows.isEmpty()) {
                result.isValid = false;
                result.errors.add('No data rows found in Excel file.');
                return result;
            }

            result.rowCount = rows.size();

            // Collect Product Ids for bulk validation
            Set<String> productIds = new Set<String>();
            Integer totalPriceEntries = 0;

            for (QuantityUploadRow row : rows) {
                Integer rowNum = row.rowNumber != null ? row.rowNumber : 0;

                // Validate Product Id (SFDC ID)
                if (String.isBlank(row.productId)) {
                    result.errors.add('Row ' + rowNum + ': SFDC ID is required.');
                    result.isValid = false;
                } else {
                    try {
                        Id testId = Id.valueOf(row.productId);
                        productIds.add(row.productId);
                    } catch (Exception ex) {
                        result.errors.add('Row ' + rowNum + ': Invalid SFDC ID "' + row.productId + '".');
                        result.isValid = false;
                    }
                }

                // Validate Meter Type
                if (String.isBlank(row.meterType)) {
                    result.errors.add('Row ' + rowNum + ': Meter Type is required.');
                    result.isValid = false;
                }

                // Validate Lower/Upper Bound
                if (row.lowerBound == null) {
                    result.errors.add('Row ' + rowNum + ': Lower Bound is required.');
                    result.isValid = false;
                } else if (row.lowerBound < 0) {
                    result.errors.add('Row ' + rowNum + ': Lower Bound cannot be negative.');
                    result.isValid = false;
                }
                if (row.upperBound == null) {
                    result.errors.add('Row ' + rowNum + ': Upper Bound is required.');
                    result.isValid = false;
                } else if (row.upperBound < 0) {
                    result.errors.add('Row ' + rowNum + ': Upper Bound cannot be negative.');
                    result.isValid = false;
                }
                if (row.lowerBound != null && row.upperBound != null && row.lowerBound >= row.upperBound) {
                    result.errors.add('Row ' + rowNum + ': Lower Bound (' + row.lowerBound +
                        ') must be less than Upper Bound (' + row.upperBound + ').');
                    result.isValid = false;
                }

                // Count and validate prices
                Integer priceCount = 0;
                Decimal samplePrice = null;
                if (row.prices != null) {
                    for (CurrencyPrice cp : row.prices) {
                        if (cp.price != null) {
                            priceCount++;
                            totalPriceEntries++;
                            if (cp.price < 0) {
                                result.warnings.add('Row ' + rowNum + ': Negative price ' + cp.price +
                                    ' for ' + cp.currencyCode + '.');
                            }
                            if (samplePrice == null && cp.currencyCode == 'USD') {
                                samplePrice = cp.price;
                            }
                        }
                    }
                }

                if (priceCount == 0) {
                    result.warnings.add('Row ' + rowNum + ' (' + row.productCode + '): No prices found.');
                }

                // Build preview (first 10)
                if (result.previewRows.size() < 10) {
                    ExcelPreviewRow preview = new ExcelPreviewRow();
                    preview.productCode = row.productCode;
                    preview.productId = row.productId;
                    preview.meterType = row.meterType;
                    preview.salesChannel = String.valueOf(row.lowerBound != null ? row.lowerBound.intValue() : 0) +
                        ' \u2013 ' + String.valueOf(row.upperBound != null ? row.upperBound.intValue() : 0);
                    preview.priceCount = priceCount;
                    preview.samplePrice = samplePrice != null ? String.valueOf(samplePrice) : '-';
                    result.previewRows.add(preview);
                }

                if (result.errors.size() >= 20) {
                    result.errors.add('Too many errors. Showing first 20 only.');
                    break;
                }
            }

            result.priceEntryCount = totalPriceEntries;

            // Governor limit guard: each price creates Block_Pricing__c + GearsetExternalId update
            if (totalPriceEntries > 4500) {
                result.isValid = false;
                result.errors.add('File contains ' + totalPriceEntries +
                    ' price entries. Maximum is 4,500 per upload. Please split the file.');
            }

            // Validate Product Ids exist in the system (bulk query)
            if (!productIds.isEmpty()) {
                Set<Id> existingIds = new Set<Id>();
                for (Product2 p : [
                    SELECT Id FROM Product2
                    WHERE Id IN :productIds AND IsActive = true
                ]) {
                    existingIds.add(p.Id);
                }
                for (String pid : productIds) {
                    if (!existingIds.contains(pid)) {
                        result.errors.add('Product Id "' + pid + '" not found or inactive.');
                        result.isValid = false;
                    }
                }
            }

            return result;

        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Processes validated Quantity Pricing Excel upload data into Block_Pricing__c
     *              records with Type = 'Employee Compliance'. Each QuantityUploadRow is expanded
     *              into up to 4 Block_Pricing__c records (one per currency).
     *              Only Quantity-based products are processed; others are skipped.
     * @param uploadJson JSON string of List<QuantityUploadRow>
     * @param pricebookId The Pricebook2 Id selected in Phase 1
     * @return ProcessingResult with block pricing DML summary
     */
    @AuraEnabled
    public static ProcessingResult processQuantityExcelUpload(String uploadJson, Id pricebookId) {
        try {
            ProcessingResult result = new ProcessingResult();

            // Empty intapp summary (no Intapp_Pricing__c for quantity uploads)
            DmlSummary emptyIntapp = new DmlSummary();
            emptyIntapp.successCount = 0;
            emptyIntapp.errorCount = 0;
            emptyIntapp.totalCount = 0;
            emptyIntapp.errors = new List<String>();
            result.intappResult = emptyIntapp;

            List<QuantityUploadRow> rows = (List<QuantityUploadRow>) JSON.deserialize(
                uploadJson, List<QuantityUploadRow>.class
            );

            // Bulk-fetch product details
            Set<String> productIds = new Set<String>();
            for (QuantityUploadRow row : rows) {
                if (String.isNotBlank(row.productId)) {
                    productIds.add(row.productId);
                }
            }

            Map<Id, Product2> productMap = new Map<Id, Product2>([
                SELECT Id, ProductCode, Pricing_Basis__c
                FROM Product2
                WHERE Id IN :productIds
            ]);

            // Extract fiscal year code from pricebook name
            Pricebook2 pb = [SELECT Name FROM Pricebook2 WHERE Id = :pricebookId LIMIT 1];
            String fyCode = extractFiscalYearCode(pb.Name);

            // Resolve per-row pricebook names to Ids (bulk lookup)
            Set<String> rowPricebookNames = new Set<String>();
            for (QuantityUploadRow row : rows) {
                if (String.isNotBlank(row.pricebook)) {
                    rowPricebookNames.add(row.pricebook.trim());
                }
            }
            Map<String, Id> pricebookIdByName = new Map<String, Id>();
            if (!rowPricebookNames.isEmpty()) {
                for (Pricebook2 rowPb : [
                    SELECT Id, Name FROM Pricebook2
                    WHERE Name IN :rowPricebookNames AND IsActive = true
                ]) {
                    pricebookIdByName.put(rowPb.Name, rowPb.Id);
                }
            }

            List<Block_Pricing__c> blockRecords = new List<Block_Pricing__c>();
            Integer skippedBlockCount = 0;

            for (QuantityUploadRow row : rows) {
                Product2 prod = productMap.get(row.productId);
                if (prod == null) continue;

                // Only create for Quantity-based products
                Boolean isQuantityBased = prod.Pricing_Basis__c != null &&
                    prod.Pricing_Basis__c.equalsIgnoreCase('Quantity based');

                if (!isQuantityBased) {
                    Integer priceCount = 0;
                    if (row.prices != null) {
                        for (CurrencyPrice cp : row.prices) {
                            if (cp.price != null) priceCount++;
                        }
                    }
                    skippedBlockCount += priceCount;
                    continue;
                }

                String resolvedCode = String.isNotBlank(row.productCode)
                    ? row.productCode : prod.ProductCode;

                // Use per-row pricebook if specified and resolved; fall back to wizard-level pricebook
                Id resolvedPricebookId = pricebookId;
                if (String.isNotBlank(row.pricebook)) {
                    Id rowPbId = pricebookIdByName.get(row.pricebook.trim());
                    if (rowPbId != null) resolvedPricebookId = rowPbId;
                }

                if (row.prices == null) continue;

                for (CurrencyPrice cp : row.prices) {
                    if (cp.price == null) continue;

                    blockRecords.add(new Block_Pricing__c(
                        Product__c                  = prod.Id,
                        Product_Code__c             = resolvedCode,
                        Block_Pricing_Meter_Type__c = row.meterType,
                        CurrencyIsoCode             = cp.currencyCode,
                        Lower_Bound__c              = row.lowerBound,
                        Upper_Bound__c              = row.upperBound,
                        Price__c                    = cp.price,
                        Type__c                     = 'Employee Compliance',
                        Active__c                   = true,
                        Fiscal_Year__c              = fyCode,
                        Price_Book__c               = resolvedPricebookId
                    ));
                }
            }

            // DML with partial success
            result.blockResult = performPartialInsert(blockRecords);
            result.blockSkippedCount = skippedBlockCount;
            result.totalRowsProcessed = rows.size();

            // Populate Gearset External Ids
            populateBlockGearsetExternalIds(blockRecords, result.blockResult);

            Nebula.Logger.info(
                'Pricebook Wizard Quantity upload complete. Block: ' + result.blockResult.successCount +
                '/' + blockRecords.size() + ', Skipped: ' + skippedBlockCount
            ).addTag('PricebookWizard').setRecordId(pricebookId);
            Nebula.Logger.saveLog();

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage()).addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            throw new AuraHandledException(e.getMessage());
        }
    }

    /***********************************************************************************************
     *
     * Phase 5 — View Results (query uploaded records for display)
     *
     ***********************************************************************************************/

    /**
     * @description Queries uploaded pricing records for a given pricebook and returns them
     *              in a display-ready format matching the Pricebook View table structure.
     *              Scoped to only the products that were part of the upload (productIdsJson).
     * @param pricebookId The Pricebook2 Id used for the upload
     * @param uploadType 'tier' or 'quantity'
     * @param productIdsJson JSON array of Product2 Ids from the uploaded rows
     * @return UploadResultView containing rows and metadata
     */
    @AuraEnabled
    public static UploadResultView getUploadResultView(Id pricebookId, String uploadType, String productIdsJson) {
        try {
            if (pricebookId == null || String.isBlank(uploadType)) {
                throw new AuraHandledException('Pricebook Id and upload type are required.');
            }

            // Parse the product IDs to scope results to only uploaded products
            Set<Id> uploadedProductIds = new Set<Id>();
            if (String.isNotBlank(productIdsJson)) {
                List<String> idStrings = (List<String>) JSON.deserialize(productIdsJson, List<String>.class);
                for (String idStr : idStrings) {
                    if (String.isNotBlank(idStr)) {
                        uploadedProductIds.add(Id.valueOf(idStr.trim()));
                    }
                }
            }

            if (uploadType == 'quantity') {
                return buildQuantityResultView(pricebookId, uploadedProductIds);
            } else {
                return buildTierResultView(pricebookId, uploadedProductIds);
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            Nebula.Logger.error('View Results error: ' + e.getMessage())
                .addTag('PricebookWizard');
            Nebula.Logger.saveLog();
            AuraHandledException aheGeneric = new AuraHandledException(e.getMessage());
            aheGeneric.setMessage(e.getMessage());
            throw aheGeneric;
        }
    }

    /**
     * @description Builds the tier result view by querying Block_Pricing__c (GTM Motion Tier)
     *              and Intapp_Pricing__c for the given pricebook, scoped to uploaded products.
     */
    private static UploadResultView buildTierResultView(Id pricebookId, Set<Id> uploadedProductIds) {
        UploadResultView view = new UploadResultView();
        view.uploadType = 'tier';
        view.tierRows = new List<TierResultRow>();
        view.quantityRows = new List<QuantityResultRow>();

        // 1. Query Block_Pricing__c (GTM Motion Tier) for this pricebook, scoped to uploaded products
        List<Block_Pricing__c> blockRecords;
        if (!uploadedProductIds.isEmpty()) {
            blockRecords = [
                SELECT Product__c, Block_Pricing_Meter_Type__c,
                       CurrencyIsoCode, Tier_Name__c, Price__c
                FROM Block_Pricing__c
                WHERE Price_Book__c = :pricebookId
                  AND Type__c = 'GTM Motion Tier'
                  AND Product__c IN :uploadedProductIds
                ORDER BY Product__c, Block_Pricing_Meter_Type__c, CurrencyIsoCode, Tier_Name__c
                LIMIT 10000
            ];
        } else {
            blockRecords = new List<Block_Pricing__c>();
        }

        // 2. Query Intapp_Pricing__c for the same pricebook, scoped to uploaded products
        List<Intapp_Pricing__c> intappRecords;
        if (!uploadedProductIds.isEmpty()) {
            intappRecords = [
                SELECT Product__c, Product_Code__c, Meter_Type__c,
                       CurrencyIsoCode, Tier__c, Price__c
                FROM Intapp_Pricing__c
                WHERE Price_Book__c = :pricebookId
                  AND Product__c IN :uploadedProductIds
                ORDER BY Product__c, Meter_Type__c, CurrencyIsoCode
                LIMIT 10000
            ];
        } else {
            intappRecords = new List<Intapp_Pricing__c>();
        }

        // 3. Collect all product IDs
        Set<Id> productIds = new Set<Id>();
        for (Block_Pricing__c bp : blockRecords) {
            productIds.add(bp.Product__c);
        }
        for (Intapp_Pricing__c ip : intappRecords) {
            if (ip.Product__c != null) {
                productIds.add(ip.Product__c);
            }
        }

        if (productIds.isEmpty()) {
            view.totalRows = 0;
            return view;
        }

        // 4. Query Product2 details
        Map<Id, Product2> productsById = new Map<Id, Product2>([
            SELECT Id, ProductCode, Name, Product_LineNew__r.Name,
                   Product_Type__c, Pricing_Basis__c
            FROM Product2
            WHERE Id IN :productIds
        ]);

        // 5. Group Block_Pricing__c by product + meterType
        Map<Id, Map<String, List<Block_Pricing__c>>> blockByProductMeter =
            new Map<Id, Map<String, List<Block_Pricing__c>>>();
        Set<Id> productIdsWithBlock = new Set<Id>();

        for (Block_Pricing__c bp : blockRecords) {
            productIdsWithBlock.add(bp.Product__c);
            if (!blockByProductMeter.containsKey(bp.Product__c)) {
                blockByProductMeter.put(bp.Product__c, new Map<String, List<Block_Pricing__c>>());
            }
            String mt = bp.Block_Pricing_Meter_Type__c;
            if (!blockByProductMeter.get(bp.Product__c).containsKey(mt)) {
                blockByProductMeter.get(bp.Product__c).put(mt, new List<Block_Pricing__c>());
            }
            blockByProductMeter.get(bp.Product__c).get(mt).add(bp);
        }

        // 6. Group Intapp_Pricing__c by product + meterType (for non-block products)
        Map<Id, Map<String, List<Intapp_Pricing__c>>> intappByProductMeter =
            new Map<Id, Map<String, List<Intapp_Pricing__c>>>();

        for (Intapp_Pricing__c ip : intappRecords) {
            if (ip.Product__c == null || productIdsWithBlock.contains(ip.Product__c)) continue;
            if (!intappByProductMeter.containsKey(ip.Product__c)) {
                intappByProductMeter.put(ip.Product__c, new Map<String, List<Intapp_Pricing__c>>());
            }
            String mt = ip.Meter_Type__c;
            if (!intappByProductMeter.get(ip.Product__c).containsKey(mt)) {
                intappByProductMeter.get(ip.Product__c).put(mt, new List<Intapp_Pricing__c>());
            }
            intappByProductMeter.get(ip.Product__c).get(mt).add(ip);
        }

        // 7. Build rows from Block_Pricing__c
        for (Id prodId : blockByProductMeter.keySet()) {
            Product2 prod = productsById.get(prodId);
            if (prod == null) continue;

            Map<String, List<Block_Pricing__c>> meterMap = blockByProductMeter.get(prodId);
            for (String meterType : meterMap.keySet()) {
                Map<String, Map<String, Decimal>> currTierMap = buildBlockCurrTierMap(meterMap.get(meterType));
                view.tierRows.add(buildTierResultRow(prod, meterType, currTierMap));
            }
        }

        // 8. Build rows from Intapp_Pricing__c (fallback)
        for (Id prodId : intappByProductMeter.keySet()) {
            Product2 prod = productsById.get(prodId);
            if (prod == null) continue;

            Map<String, List<Intapp_Pricing__c>> meterMap = intappByProductMeter.get(prodId);
            for (String meterType : meterMap.keySet()) {
                Map<String, Map<String, Decimal>> currTierMap = buildIntappCurrTierMap(meterMap.get(meterType));
                view.tierRows.add(buildTierResultRow(prod, meterType, currTierMap));
            }
        }

        // Sort by ProductCode
        view.tierRows.sort();
        view.totalRows = view.tierRows.size();
        return view;
    }

    /**
     * @description Builds the quantity result view by querying Block_Pricing__c
     *              (Employee Compliance) for the given pricebook, scoped to uploaded products.
     */
    private static UploadResultView buildQuantityResultView(Id pricebookId, Set<Id> uploadedProductIds) {
        UploadResultView view = new UploadResultView();
        view.uploadType = 'quantity';
        view.tierRows = new List<TierResultRow>();
        view.quantityRows = new List<QuantityResultRow>();

        List<Block_Pricing__c> records;
        if (!uploadedProductIds.isEmpty()) {
            records = [
                SELECT Product__c, Product_Code__c, Block_Pricing_Meter_Type__c,
                       CurrencyIsoCode, Lower_Bound__c, Upper_Bound__c, Price__c
                FROM Block_Pricing__c
                WHERE Price_Book__c = :pricebookId
                  AND Type__c = 'Employee Compliance'
                  AND Product__c IN :uploadedProductIds
                ORDER BY Product__c, Block_Pricing_Meter_Type__c, Lower_Bound__c, CurrencyIsoCode
                LIMIT 10000
            ];
        } else {
            records = new List<Block_Pricing__c>();
        }

        Set<Id> productIds = new Set<Id>();
        for (Block_Pricing__c bp : records) {
            productIds.add(bp.Product__c);
        }

        if (productIds.isEmpty()) {
            view.totalRows = 0;
            return view;
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>([
            SELECT Id, ProductCode, Name
            FROM Product2
            WHERE Id IN :productIds
        ]);

        // Group by product + meterType + band
        Map<String, QuantityResultRow> rowMap = new Map<String, QuantityResultRow>();

        for (Block_Pricing__c bp : records) {
            Product2 prod = productsById.get(bp.Product__c);
            if (prod == null) continue;

            String bandKey = bp.Product__c + '_' + bp.Block_Pricing_Meter_Type__c + '_' +
                             bp.Lower_Bound__c + '_' + bp.Upper_Bound__c;

            QuantityResultRow row;
            if (rowMap.containsKey(bandKey)) {
                row = rowMap.get(bandKey);
            } else {
                row = new QuantityResultRow();
                row.productId = String.valueOf(bp.Product__c);
                row.productCode = prod.ProductCode;
                row.productName = prod.Name;
                row.meterType = bp.Block_Pricing_Meter_Type__c;
                row.lowerBound = bp.Lower_Bound__c;
                row.upperBound = bp.Upper_Bound__c;
                row.band = String.valueOf(bp.Lower_Bound__c != null ? bp.Lower_Bound__c.intValue() : 0)
                         + ' \u2013 '
                         + String.valueOf(bp.Upper_Bound__c != null ? bp.Upper_Bound__c.intValue() : 0);
                row.rowKey = bandKey;
                rowMap.put(bandKey, row);
            }

            // Assign price to correct currency slot
            if (bp.CurrencyIsoCode == 'USD') row.usdPrice = bp.Price__c;
            else if (bp.CurrencyIsoCode == 'GBP') row.gbpPrice = bp.Price__c;
            else if (bp.CurrencyIsoCode == 'EUR') row.eurPrice = bp.Price__c;
            else if (bp.CurrencyIsoCode == 'AUD') row.audPrice = bp.Price__c;
        }

        view.quantityRows = rowMap.values();
        view.totalRows = view.quantityRows.size();
        return view;
    }

    /**
     * @description Builds currency → tier → price map from Block_Pricing__c records (single meter type).
     */
    private static Map<String, Map<String, Decimal>> buildBlockCurrTierMap(List<Block_Pricing__c> records) {
        Map<String, Map<String, Decimal>> result = new Map<String, Map<String, Decimal>>();
        for (Block_Pricing__c bp : records) {
            String curr = bp.CurrencyIsoCode;
            String tier = bp.Tier_Name__c == null ? 'None' : bp.Tier_Name__c;
            if (!result.containsKey(curr)) {
                result.put(curr, new Map<String, Decimal>());
            }
            result.get(curr).put(tier, bp.Price__c);
        }
        return result;
    }

    /**
     * @description Builds currency → tier → price map from Intapp_Pricing__c records (single meter type).
     */
    private static Map<String, Map<String, Decimal>> buildIntappCurrTierMap(List<Intapp_Pricing__c> records) {
        Map<String, Map<String, Decimal>> result = new Map<String, Map<String, Decimal>>();
        for (Intapp_Pricing__c ip : records) {
            String curr = ip.CurrencyIsoCode;
            String tier = (ip.Tier__c == null || ip.Tier__c == NONE_TIER_INTAPP) ? 'None' : ip.Tier__c;
            if (!result.containsKey(curr)) {
                result.put(curr, new Map<String, Decimal>());
            }
            result.get(curr).put(tier, ip.Price__c);
        }
        return result;
    }

    /**
     * @description Builds a single TierResultRow with 24 PriceCell entries.
     */
    private static TierResultRow buildTierResultRow(
        Product2 product, String meterType,
        Map<String, Map<String, Decimal>> currTierMap
    ) {
        TierResultRow row = new TierResultRow();
        row.productId = String.valueOf(product.Id);
        row.productCode = product.ProductCode;
        row.productName = product.Name;
        row.productLine = product.Product_LineNew__r != null ? product.Product_LineNew__r.Name : '';
        row.productType = product.Product_Type__c;
        row.pricingBasis = product.Pricing_Basis__c;
        row.meterType = meterType;
        row.rowKey = product.Id + '_' + (String.isNotBlank(meterType) ? meterType.replaceAll('[^a-zA-Z0-9]', '') : 'none');
        row.prices = new List<PriceCell>();

        for (String curr : CURRENCIES) {
            for (String tier : TIERS) {
                PriceCell cell = new PriceCell();
                cell.key = curr + '_' + tier;
                cell.currencyCode = curr;
                cell.tier = tier;
                cell.price = null;

                if (currTierMap != null
                    && currTierMap.containsKey(curr)
                    && currTierMap.get(curr).containsKey(tier)) {
                    cell.price = currTierMap.get(curr).get(tier);
                }
                row.prices.add(cell);
            }
        }
        return row;
    }

    /***********************************************************************************************
     *
     * Private Helper Methods
     *
     ***********************************************************************************************/

    /**
     * @description Performs a partial success insert and collects results.
     * @param records List of SObjects to insert
     * @return DmlSummary with success/error counts and error messages
     */
    private static DmlSummary performPartialInsert(List<SObject> records) {
        DmlSummary summary = new DmlSummary();
        summary.successCount = 0;
        summary.errorCount = 0;
        summary.totalCount = records.size();
        summary.errors = new List<String>();

        if (records.isEmpty()) {
            return summary;
        }

        Database.SaveResult[] results = Database.insert(records, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                summary.successCount++;
            } else {
                summary.errorCount++;
                for (Database.Error err : results[i].getErrors()) {
                    if (summary.errors.size() < 10) {
                        summary.errors.add('Row ' + (i + 1) + ': ' + err.getMessage());
                    }
                }
            }
        }

        return summary;
    }

    /**
     * @description Populates GearsetExternalId__c on successfully-inserted Intapp_Pricing__c records.
     *              Uses the record's own Id as the external Id value (numeric, for Number field).
     * @param records The inserted Intapp_Pricing__c records
     * @param summary The DML summary from the initial insert
     */
    private static void populateGearsetExternalIds(List<Intapp_Pricing__c> records, DmlSummary summary) {
        List<Intapp_Pricing__c> toUpdate = new List<Intapp_Pricing__c>();
        for (Intapp_Pricing__c rec : records) {
            if (rec.Id != null) {
                // Extract numeric portion from Salesforce Id for the Number(18,0) field
                toUpdate.add(new Intapp_Pricing__c(
                    Id = rec.Id,
                    GearsetExternalId__c = rec.Id
                ));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Populates GearsetExternalId__c on successfully-inserted Block_Pricing__c records.
     *              Uses the record's own Id as the external Id value.
     * @param records The inserted Block_Pricing__c records
     * @param summary The DML summary from the initial insert
     */
    private static void populateBlockGearsetExternalIds(List<Block_Pricing__c> records, DmlSummary summary) {
        List<Block_Pricing__c> toUpdate = new List<Block_Pricing__c>();
        for (Block_Pricing__c rec : records) {
            if (rec.Id != null) {
                toUpdate.add(new Block_Pricing__c(
                    Id = rec.Id,
                    GearsetExternalId__c = String.valueOf(rec.Id)
                ));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Parses a string to Boolean. Accepts 'true', '1', 'yes' as true.
     * @param value String to parse
     * @return Boolean result
     */
    private static Boolean parseBool(String value) {
        if (String.isBlank(value)) return false;
        String v = value.trim().toLowerCase();
        return v == 'true' || v == '1' || v == 'yes';
    }

    /**
     * @description Derives OP4I pricebook abbreviation from the Excel upload row sales channel flags.
     * @param row ExcelUploadRow with boolean flags
     * @return Abbreviation string for the record Name
     */
    private static String deriveExcelOp4iAbbrev(ExcelUploadRow row) {
        if (row.legalSales == true)     return 'Legal';
        if (row.acSales == true)        return 'AC';
        if (row.fsSales == true)        return 'FS';
        if (row.corporateSales == true) return 'Corporate';
        if (row.opsOnly == true)        return 'Ops Only';
        return '';
    }

    /**
     * @description Extracts fiscal year code from a pricebook name (e.g., 'FY26' from 'FY26_All_Products').
     *              Looks for a pattern matching FY followed by 2 digits.
     * @param pricebookName The full pricebook name
     * @return Fiscal year code (e.g., 'FY26'), or the first token before underscore as fallback
     */
    private static String extractFiscalYearCode(String pricebookName) {
        if (String.isBlank(pricebookName)) return '';
        // Look for FY pattern (e.g., FY26, FY27)
        Pattern fyPattern = Pattern.compile('(FY\\d{2})');
        Matcher m = fyPattern.matcher(pricebookName);
        if (m.find()) {
            return m.group(1);
        }
        // Fallback: use portion before first underscore
        Integer underscoreIdx = pricebookName.indexOf('_');
        return underscoreIdx > 0 ? pricebookName.substring(0, underscoreIdx) : pricebookName;
    }

    /***********************************************************************************************
     *
     * Inner Classes
     *
     ***********************************************************************************************/

    public class PricebookInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Integer entryCount;
        @AuraEnabled public Datetime createdDate;
    }

    public class SetupStatusResult {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Id chainedJobId;
    }

    public class ValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public Integer rowCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public List<String> headerRow;
        @AuraEnabled public List<List<String>> previewRows;
    }

    public class ProcessingResult {
        @AuraEnabled public DmlSummary intappResult;
        @AuraEnabled public DmlSummary blockResult;
        @AuraEnabled public Integer blockSkippedCount;
        @AuraEnabled public Integer totalRowsProcessed;
    }

    public class DmlSummary {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> errors;
    }

    private class PricingUploadRow {
        String productId;
        String productCode;
        String meterType;
        String currCode;
        String tier;
        Decimal price;
        Boolean legalSales;
        Boolean acSales;
        Boolean fsSales;
        Boolean opsOnly;
    }

    /**
     * @description Wrapper for a single row from the pivoted Excel upload.
     *              Each row represents one product x one meter type, with up to 24 price entries.
     */
    public class ExcelUploadRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String pricingBasis;
        @AuraEnabled public String meterType;
        @AuraEnabled public String salesChannel;
        @AuraEnabled public Boolean legalSales;
        @AuraEnabled public Boolean acSales;
        @AuraEnabled public Boolean fsSales;
        @AuraEnabled public Boolean corporateSales;
        @AuraEnabled public Boolean opsOnly;
        @AuraEnabled public List<PriceEntry> prices;
    }

    /**
     * @description Wrapper for a single price cell from the Excel upload.
     *              Represents one currency x tier combination.
     */
    public class PriceEntry {
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String tier;
        @AuraEnabled public Decimal price;
    }

    /**
     * @description Validation result returned by validateExcelUpload.
     *              Includes row/price counts, errors, warnings, and a preview table.
     */
    public class ExcelValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public Integer rowCount;
        @AuraEnabled public Integer priceEntryCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public List<ExcelPreviewRow> previewRows;
    }

    /**
     * @description Preview row for the validation summary table.
     */
    public class ExcelPreviewRow {
        @AuraEnabled public String productCode;
        @AuraEnabled public String productId;
        @AuraEnabled public String meterType;
        @AuraEnabled public String salesChannel;
        @AuraEnabled public Integer priceCount;
        @AuraEnabled public String samplePrice;
    }

    /**
     * @description Wrapper for a single row from the Quantity Pricing Excel upload.
     *              Each row represents one product x one meter type x one quantity band,
     *              with up to 4 currency price entries.
     */
    public class QuantityUploadRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String meterType;
        @AuraEnabled public String pricebook;
        @AuraEnabled public Decimal lowerBound;
        @AuraEnabled public Decimal upperBound;
        @AuraEnabled public List<CurrencyPrice> prices;
    }

    /**
     * @description Wrapper for a single currency price cell (no tier dimension).
     */
    public class CurrencyPrice {
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal price;
    }

    /***********************************************************************************************
     *
     * Phase 5 — View Results Inner Classes
     *
     ***********************************************************************************************/

    /** Result returned by getUploadResultView. */
    public class UploadResultView {
        @AuraEnabled public String uploadType;
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public List<TierResultRow> tierRows;
        @AuraEnabled public List<QuantityResultRow> quantityRows;
    }

    /** A single row in the tier pricing result table (matches PricebookViewRow structure). */
    public class TierResultRow implements Comparable {
        @AuraEnabled public String productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String productLine;
        @AuraEnabled public String productType;
        @AuraEnabled public String pricingBasis;
        @AuraEnabled public String meterType;
        @AuraEnabled public String rowKey;
        @AuraEnabled public List<PriceCell> prices;

        public Integer compareTo(Object compareTo) {
            TierResultRow other = (TierResultRow) compareTo;
            if (this.productCode == null) return -1;
            if (other.productCode == null) return 1;
            return this.productCode.compareTo(other.productCode);
        }
    }

    /** A single row in the quantity pricing result table. */
    public class QuantityResultRow {
        @AuraEnabled public String productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productName;
        @AuraEnabled public String meterType;
        @AuraEnabled public Decimal lowerBound;
        @AuraEnabled public Decimal upperBound;
        @AuraEnabled public String band;
        @AuraEnabled public String rowKey;
        @AuraEnabled public Decimal usdPrice;
        @AuraEnabled public Decimal gbpPrice;
        @AuraEnabled public Decimal eurPrice;
        @AuraEnabled public Decimal audPrice;
    }

    /** A single price cell with key for template iteration. */
    public class PriceCell {
        @AuraEnabled public String key;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String tier;
        @AuraEnabled public Decimal price;
    }
}