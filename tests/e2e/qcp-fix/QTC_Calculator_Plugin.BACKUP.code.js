/** 
 *  Quote Calculator Plugin Custom Script for pricing logic and QLE field security controls
 **/
/**********************************************************************************************
 *
 * QCP Methods
 *
 ***********************************************************************************************/
/**
 * @description
 * This function is called when the Quote Line Editor (QLE) is initialized.
 * It can be used to set up initial values or perform any necessary setup.
 * @param quoteLineModels 
 * @param conn 
 * @returns {Promise} Returns a resolved promise.
 */
export function onInit(quoteLineModels, conn) {
    printModels('onInit', quoteLineModels, conn);
    return Promise.resolve();
}

/**
 * @description
 * This function is called before the quote lines are calculated.
 * It can be used to perform any necessary setup or validation before calculations.
 * @param quoteModel
 * @param quoteLineModels 
 * @param conn 
 * @returns {Promise} Returns a resolved promise.
 * */
export function onBeforeCalculate(quoteModel, quoteLineModels, conn) {
    printModels('onBeforeCalculate', quoteModel, quoteLineModels, conn);
    // BIZ-80539 : AC-5: Block recalculation once the quote has been contracted.
    // Empty Promise.reject() short-circuits SBQQ's calculator silently 
    /*if (quoteModel.record.Quote_Stage__c === 'Contract Executed') {
        return Promise.reject();
    }*/
    applyOverrideSpecialPrice(quoteModel, quoteLineModels);
    // Compute Has_Partial_Month__c via helper BIZ-77435
    setPartialMonthFlag(quoteLineModels, quoteModel);
    return Promise.resolve();
}

/**
 * @description
 * This function is called before the price rules are executed.
 * It can be used to perform any necessary setup or validation before price rules are applied.
 * @param quoteModel
 * @param quoteLineModels
 * @param conn
 * @returns {Promise} Returns a resolved promise.
 * */
export function onBeforePriceRules(quoteModel, quoteLineModels, conn) {
    printModels('onBeforePriceRules', quoteModel, quoteLineModels, conn);
    return Promise.resolve();
}

/**
 * @description
 * This function is called after the price rules have been executed.
 * It can be used to perform any necessary actions or validations after price rules are applied.
 * @param quote
 * @param quoteLineModels
 * @param conn
 * @returns {Promise} Returns a resolved promise.
 * */
export function onAfterPriceRules(quote, quoteLineModels, conn) {
    // Added via BIZ-60160 --- end
    return new Promise((resolve, reject) => {
        console.log('Completed onAfterPriceRules processing.');
        resolve();
    });
}

/**
 * @description
 * This function is called after the quote lines have been calculated.
 * It can be used to perform any necessary actions or validations after calculations are done.
 * @param quoteModel
 * @param quoteLineModels
 * @param conn
 * @returns {Promise} Returns a promise that resolves when the processing is complete.
 */
export function onAfterCalculate(quoteModel, quoteLineModels, conn) {
    quoteLineModels.forEach(function(line) {
        console.log('ACCPQ_Option_Type__c:..' + line.record.CPQ_Option_Type__c);
    });
    // Log the models for debugging
    printModels('OnAfterCalculate', quoteModel, quoteLineModels, conn);
    setTotals(resetTotals(quoteModel), quoteLineModels);
    // Validate required fields based on Quote Type.
    const missingFields = validateQuoteFields(quoteModel);
    if (missingFields.length > 0) {
        console.log('Missing the fields');
        return Promise.reject(
            new Error(`The following fields are required: ${missingFields.join(', ')}`)
        );
    }

    // Validate % of ACV product quantities.
    const invalidACVProducts = validateACVQuantity(quoteLineModels);
    if (invalidACVProducts.length > 0) {
        return Promise.reject(
            new Error(`The product (${invalidACVProducts.join(', ')}) is based on a percent of ACV. It must be configured with a "1 firmwide" quantity and meter type in order to calculate the list price.`)
        );
    }

    // Apply custom logic if quote line models are provided.
    if (quoteLineModels && quoteLineModels.length > 0) {
        applyPriceRules(quoteLineModels);

        // Set Quote Deployment field.
        quoteModel.record.Quote_Deployment__c = setQuoteDeployment(quoteLineModels);

        // Populate end dates; note that we're using the quote type from the model.
        populateEndDates(quoteLineModels, quoteModel, quoteModel.record['SBQQ__Type__c'], conn);

        //BIZ-71953
        populateTMDiscountOnQuote(quoteModel, quoteLineModels);
    }

    // Additional processing.
    setSegmentedBundleKey(quoteLineModels);
    populateBundleDetails(quoteLineModels, conn);
    calculateServiceGrossTotal(quoteModel, quoteLineModels);

    // Instead of calling meterTypeCalculation multiple times, build a filtered list first.
    // This filtered list uses a fallback for CPQ_Option_Type__c to ensure it's a string.
    const applicableQuoteLines = quoteLineModels.filter(line => {
        // If the field is undefined, default to an empty string.
        const optionType = line.record.CPQ_Option_Type__c || '';
        const productCode = line.record.SBQQ__ProductCode__c || '';

        console.log('Filtering quote line:', {
            Product_Type__c: line.record.Product_Type__c,
            Pricing_Basis__c: line.record.Pricing_Basis__c,
            SBQQ__RenewedSubscription__c: line.record.SBQQ__RenewedSubscription__c,
            SBQQ__UpgradedSubscription__c: line.record.SBQQ__UpgradedSubscription__c,
            CPQ_Option_Type__c: optionType
        });
        return (
            line.record.Product_Type__c === 'Software' &&
            (line.record.Pricing_Basis__c === 'Tier based' ||
                line.record.Pricing_Basis__c === 'Quantity based') &&
            !line.record.SBQQ__RenewedSubscription__c &&
            !line.record.SBQQ__UpgradedSubscription__c &&
            (optionType === '' || optionType === 'Static Bundle') && // Only include lines where the CPQ option type is empty.
            !productCode.endsWith('-P') // Exclude lines where ProductCode ends with '-P'
        );
    });

    console.log('Applicable Quote Lines count:', applicableQuoteLines.length);
    applicableQuoteLines.forEach(line =>
        console.log('Filtered CPQ_Option_Type__c:', line.record.CPQ_Option_Type__c || '')
    );

    // Call the adjusted meterTypeCalculation process with the filtered lines.
    return meterTypeCalculation(quoteModel, applicableQuoteLines, conn)
        .then(result => {
            // If everything passes, simply return the result.
            return result;
        })
        .catch(error => {
            console.error("Error in onAfterCalculate:", error);
            return Promise.reject(error);
        });
}

/**
 * @description
 * Validates that '% of ACV' products have a quantity of exactly 1.
 * A quantity of 0 is permitted to support Amendment/Cancellation workflows.
 * @param {Array} quoteLineModels
 * @returns {string[]} Deduplicated array of product codes with quantity > 1.
 */
function validateACVQuantity(quoteLineModels) {
    const invalidProductCodes = new Set();
    quoteLineModels.forEach(line => {
        const pricingBasis = line.record.Pricing_Basis__c;
        const meterType = line.record.Per_Integrations__c || '';
        const quantity = line.record.SBQQ__Quantity__c;
        const productCode = line.record.SBQQ__ProductCode__c || '';

        if (pricingBasis === '% of ACV' && quantity > 1 && meterType === 'Firmwide') {
            invalidProductCodes.add(productCode);
        }
    });
    return Array.from(invalidProductCodes);
}

/**
 * @description
 * Applies Special Price from monthly override before calculation.
 *
 * Logic:
 * If Override_Sales_Price_Per_Month__c exists,
 * SpecialPrice = Override * ProrateMultiplier
 * SpecialPriceType = Custom
 *
 * @param {Object} quoteModel
 * @param {Array} quoteLineModels
 */
function applyOverrideSpecialPrice(quoteModel, quoteLineModels) {
    if (!quoteModel || !quoteModel.record || !Array.isArray(quoteLineModels)) {
        return;
    }

    quoteLineModels.forEach((lineModel) => {
        if (!lineModel || !lineModel.record) {
            return;
        }

        const line = lineModel.record;
        const quote = quoteModel.record;

        const condition10 = line.Pricing_Basis__c === '% of ACV';

        const condition60 = line.Bypass_PriceRule__c == null || line.Bypass_PriceRule__c === false;
        const condition150 = quote.Total_DealCloud_ACV__c != null && quote.Total_DealCloud_ACV__c > 0;
        const groupB = condition60 || condition150;

        const condition70 = line.SBQQ__Quantity__c > 0;

        const condition120 = quote.SBQQ__Type__c === 'Quote';
        const condition130 = quote.SBQQ__Type__c === 'Amendment';
        const condition100 = line.SBQQ__UpgradedSubscription__c == null;
        const groupD = (condition120 || condition130) && condition100;

        const condition140 = quote.SBQQ__Type__c === 'Renewal';
        const condition110 = line.SBQQ__RenewedSubscription__c == null;
        const condition160 = quote.Renewal_Quote_Type__c === 'Renewal-Changes';
        const groupE = condition140 && (condition110 || condition160);

        /* ------------------------------
           FINAL PRICE RULE LOGIC
        --------------------------------*/
        const shouldApply = condition10 && groupB && condition70 && (groupD || groupE);

        if (!shouldApply) {
            return;
        }
        /* ------------------------------
           OVERRIDE LOGIC
        --------------------------------*/
        const override = Number(line.Override_Sales_Price_Per_Month__c);

        if (!override || override <= 0) {
            return;
        }

        const prorate = Number(line.SBQQ__ProrateMultiplier__c) || 1;

        const customerPrice = override * prorate;

        line.SBQQ__SpecialPrice__c = customerPrice;
        line.SBQQ__SpecialPriceType__c = "Custom";
    });
}

/**
 * @description
 * Calculates and populates the Services Gross Total for the quote. 
 * This function iterates through all quote lines and sums the SBQQ__ListPrice__c
 * values only for lines where:
 *   - Product_Type__c is 'Services Discount' or 'Services'
 *   - Is_Prime__c is false
 * The calculated total is assigned to the quote field Services_Gross_Total__c.
 *
 * @param {Object} quote - The QuoteModel object that holds the header and summary quote fields.
 * @param {Array} lines - An array of QuoteLineModel objects (one for each quote line).
 */
export function calculateServiceGrossTotal(quote, lines) {
    let listTotal = 0;
    let oneTimeCreditTotal = 0;
    lines.forEach(line => {
        if (
            (line.record.Product_Type__c === 'Services Discount' ||
                line.record.Product_Type__c === 'Services')
        ) {
            listTotal += line.record.SBQQ__ListPrice__c || 0;
            oneTimeCreditTotal += line.record.One_Time_Credit__c || 0;
        }
    });
    quote.record.Services_Gross_Total__c = listTotal;
    quote.record.Services_Discount_Total__c = oneTimeCreditTotal;
}

/**
 * @description
 * This function sets the editability of fields based on the object type and field name.
 * @param fieldName
 * @param line
 * @param conn
 * @param objectName
 * @returns {boolean} Returns true if the field is editable, false otherwise.
 * */
export function isFieldEditableForObject(fieldName, line, conn, objectName) {
    if (objectName === 'Quote__c') {
        switch (fieldName) {
            case 'SBQQ__SubscriptionTerm__c':
            case 'First_Segment_Months__c':
            case 'SBQQ__EndDate__c':
            case 'Free_Months__c':
                // New condition: If the quote type is 'Quote', SBQQ__EndDate__c should not be editable.
                if (fieldName === 'SBQQ__EndDate__c' && line.SBQQ__Type__c === 'Quote') {
                    return false;
                }
                return line.SBQQ__Type__c !== 'Amendment';
            case 'SBQQ__StartDate__c':
                return line.Renewal_Quote_Type__c !== 'Consolidated-Quote';
            case 'End_Date__c':
                return false;
            case 'SBQQ__ListPrice__c':
                return line.SBQQ__ListPrice__c === 0; // Enables editability if List Price = 0
        }
    }
    if (objectName === 'QuoteLine__c') {
        const staticComponentFields = [
            'Revenue_Allocation__c',
            'SBQQ__Quantity__c',
            'SBQQ__Discount__c',
            'One_Time_Credit__c',
            'Override_Sales_Price_Per_Month__c',
            'SBQQ__AdditionalDiscount__c',
            'Revenue_Allocated__c'
        ];
        if (line.CPQ_Option_Type__c === 'Static Component' && fieldName === 'Revenue_Allocation__c' &&
            (line.SBQQ__Quote__r.Created_By_Profile__c === 'System Administrator' || line.SBQQ__Quote__r.Created_By_Profile__c === 'Contracts / CRM Ops')) {
            return true;
        }
        if (line.CPQ_Option_Type__c === 'Static Component' && staticComponentFields.includes(fieldName)) {
            return false;
        }
        //BIZ-69486 -  Fields to lock if the line is a bundle parent
        const lockedFields = ['SBQQ__Quantity__c', 'SBQQ__ListPrice__c', 'Per_Integrations__c', 'SBQQ__StartDate__c', 'SBQQ__EndDate__c', 'One_Time_Credit__c', 'SBQQ__AdditionalDiscount__c'];

        // Lock the field if it's in the locked list and this is a parent bundle
        if (line.Parent_of_Bundle__c && !line.CPQ_Option_Type__c && lockedFields.includes(fieldName)) {
            return false;
        }
        const isAmendmentQuote = line.SBQQ__Quote__r.SBQQ__Type__c === 'Amendment';
        // Added via BIZ-60160 --- start
        const isRenewalQuote = line.SBQQ__Quote__r.SBQQ__Type__c === 'Renewal';
        // Added via BIZ-60160 --- end
        const isExistingLine = line.SBQQ__UpgradedSubscription__c !== null;
        // Added via BIZ-60160 --- start
        const isRenewalLine = line.SBQQ__RenewedSubscription__c !== null;
        // Added via BIZ-60160 --- end
        const segmentIndex = line.SBQQ__SegmentIndex__c;
        const amendmentNonEditableFields = [
            'Override_Sales_Price_Per_Month__c',
            'Support_Level__c',
            'Meter_Type__c',
            'SBQQ__ListPrice__c',
            'SBQQ__AdditionalDiscount__c'
        ];
        // Added via BIZ-60160 --- start
        const renewalNonEditableFields = [
            'Support_Level__c'
        ];
        // Added via BIZ-60160 --- end
        // Lock Uplift field for existing lines in Amendment quotes.
        if (isAmendmentQuote && isExistingLine) {
            if (amendmentNonEditableFields.includes(fieldName)) {
                return false;
            }
        }
        // Added via BIZ-60160 --- start
        if (isRenewalQuote && isRenewalLine) {
            if (renewalNonEditableFields.includes(fieldName)) {
                return false;
            }
        }
        // Added via BIZ-60160 --- end
        switch (fieldName) {
            case 'ACV__c':
                return false;
            case 'Support_Level__c':
            case 'SBQQ__Quantity__c':
            case 'SBQQ__AdditionalDiscount__c':
            case 'Uplift_qtc__c':
            case 'One_Time_Credit__c':
            case 'ACV_Type__c':
            case 'Per_Integrations__c':
            case 'ACV_Type_Override__c':
            case 'Original_ACV_Change__c':
            case 'ACV_Change_Manual__c':
                return !(line.SBQQ__RequiredBy__c !== null && line.Skip_OP4I_Sync__c === true);
            case 'SBQQ__Quantity__c':
                return line.CPQ_Option_Type__c === 'Static Bundle';
            case 'Uplift_qtc__c':
                return line.Bundle_Product_Name__c === 'Intapp Select Bundle' && segmentIndex !== 1;
            case 'Year_2_Quantity__c':
            case 'Year_3_Quantity__c':
            case 'Year_4_Quantity__c':
            case 'Year_5_Quantity__c':
            case 'Year_6_Quantity__c':
                return line.SBQQ__ProductCode__c === 'BU-01408';
        }
    }
    // Default: allow editing.
}

/**
 * @description
 * This function sets the visibility of fields based on the object type and field name.
 * @param fieldName 
 * @param line 
 * @param conn 
 * @param objectName 
 * @returns {boolean} Returns true if the field is visible, false otherwise.
 */
export function isFieldVisibleForObject(fieldName, line, conn, objectName) {
    // Quote Line fields.
    if (objectName === 'QuoteLine__c') {
        const quoteType = line.SBQQ__Quote__r.SBQQ__Type__c;
        switch (fieldName) {
            case 'Previous_Unit_Price__c':
                return line.Renewal_Quote_Type__c === 'Auto-Renewal';
            case 'Uplifted_Unit_Price__c':
                return line.Renewal_Quote_Type__c === 'Auto-Renewal';
            case 'Year_2_Quantity__c':
            case 'Year_3_Quantity__c':
            case 'Year_4_Quantity__c':
            case 'Year_5_Quantity__c':
            case 'Year_6_Quantity__c':
                return line.SBQQ__ProductCode__c === 'BU-01408';
        }
    }

    // Quote Level fields.
    if (objectName === 'Quote__c') {
        switch (fieldName) {
            case 'SFA_Override__c':
                return !(line.Renewal_Quote_Type__c === 'Consolidated-Quote' || line.Renewal_Quote_Type__c === null);
            case 'SFA__c':
            case 'SFA_Notes__c':
                return line.SBQQ__Type__c === 'Renewal';
        }
    }
    // Default: show the field.
}

/**********************************************************************************************
 *
 * Private Methods
 *
 ***********************************************************************************************/
/**
 * @description
 * This function prints the models for debugging purposes.
 * It logs the calculation step, quote model, quote line models, and connection object.
 * @param calcStep 
 * @param quoteModel 
 * @param quoteLineModels 
 * @param conn 
 */
function printModels(calcStep, quoteModel, quoteLineModels, conn) {
    console.log('=====START ===== ' + calcStep);
    console.log('Models: ', quoteModel, quoteLineModels, conn);
    console.log('=====END ===== ' + calcStep);
}

/**
 * @description
 * This function sets the Segment Bundle Key for Static Bundles and Static Components in the Quote Line -BIZ-68559.
 * @param quoteLineModels 
 */
// Create a new method to segmented bundle key - BIZ-68559
function setSegmentedBundleKey(quoteLineModels) {
    const bundleMaps = {};
    const bundleNetTotal = {};
    const bundleNames = {};
    const bundleQuantities = {}; // Store quantities for bundles
    const bundleSupportLevels = {}; // Store support levels for bundles
    const bundleMeterTypes = {}; //Added by BIZ-76718
    const bundleCustomerPrice = {}; //BIZ-78504
    const bundleProMultiplier = {}; //BIZ-78504

    // First pass: Build maps for bundles and components
    quoteLineModels.forEach(function(line) {
        line.record.Line_Item_Key__c = line.key;

        if (line.parentItemKey) {
            line.record.Parent_Bundle_Key__c = line.parentItemKey + '' + line.record.SBQQ__SegmentIndex__c;
            line.record.Parent_Line_Id_Text__c = line.parentItemKey;
        }

        const segmentIndex = line.record.SBQQ__SegmentIndex__c;

        if (line.record.CPQ_Option_Type__c === 'Static Bundle') {
            const bundleKey = line.parentItemKey;
            const bundleMapKey = `${segmentIndex}__${bundleKey}`;
            bundleMaps[bundleMapKey] = line.key;
            bundleNetTotal[bundleMapKey] = parseFloat(line.record.SBQQ__NetTotal__c) || 0;
            const qty = parseFloat(line.record.SBQQ__Quantity__c);
            bundleQuantities[bundleMapKey] = isNaN(qty) ? 0 : qty;
            bundleSupportLevels[bundleMapKey] = line.record.Support_Level__c || ''; // Capture Support Level
            //bundleQuantities[bundleMapKey] = parseFloat(line.record.SBQQ__Quantity__c) || 0;
            bundleNames[bundleMapKey] = line.record.SBQQ__ProductName__c || `Segment ${segmentIndex}`;
            line.record.Revenue_Allocation__c = 0; // as part of BIZ-69598

            //Added by BIZ-76718
            bundleMeterTypes[bundleMapKey] = (line.record.Per_Integrations__c !== undefined && line.record.Per_Integrations__c !== null) ? line.record.Per_Integrations__c : null;

            // <-- NEW: capture SBQQ__CustomerPrice__c  from the bundle
            bundleCustomerPrice[bundleMapKey] = (line.record.SBQQ__CustomerPrice__c !== undefined && line.record.SBQQ__CustomerPrice__c !== null) ? line.record.SBQQ__CustomerPrice__c : null;
            bundleProMultiplier[bundleMapKey] = (line.record.SBQQ__ProrateMultiplier__c !== undefined && line.record.SBQQ__ProrateMultiplier__c !== null) ? line.record.SBQQ__ProrateMultiplier__c : null;
        }
    });
    console.log('===bundleCustomerPrice===', bundleCustomerPrice);
    const allocationSums = {}; // compoundKey → sum of allocation

    // Second pass: Calculate allocation & set references
    quoteLineModels.forEach(function(line) {
        const segmentIndex = line.record.SBQQ__SegmentIndex__c;

        if (
            line.record.CPQ_Option_Type__c === 'Static Component' &&
            line.record.Parent_Line_Id_Text__c
        ) {
            const parentKey = line.record.Parent_Line_Id_Text__c;
            const bundleMapKey = `${segmentIndex}__${parentKey}`;

            if (bundleMaps[bundleMapKey] !== undefined) {
                line.record.Segment_Bundle_Line_Id__c = bundleMaps[bundleMapKey];
                // Copy quantity from bundle to component
                line.record.SBQQ__Quantity__c = bundleQuantities[bundleMapKey];
                // Copy support level from bundle to component
                line.record.Support_Level__c = bundleSupportLevels[bundleMapKey];

                //Added by BIZ-76718
                line.record.Per_Integrations__c = bundleMeterTypes[bundleMapKey];

                // BIZ-78504: Copy SBQQ__ProrateMultiplier__c from bundle to component
                line.record.SBQQ__ProrateMultiplier__c = bundleProMultiplier[bundleMapKey];

                const netTotalPrice = bundleNetTotal[bundleMapKey] || 0;
                const revenueAllocation = parseFloat(line.record.Revenue_Allocation__c) || 0;
                line.record.Revenue_Allocated__c = (netTotalPrice * (revenueAllocation / 100));

                // BIZ-78504: Calculate component's customer price as: (Revenue_Allocation__c / 100) * Bundle's CustomerPrice
                const bundleCustPrice = (bundleCustomerPrice[bundleMapKey] !== undefined && bundleCustomerPrice[bundleMapKey] !== null) ? bundleCustomerPrice[bundleMapKey] : 0;
                line.record.SBQQ__CustomerPrice__c = (revenueAllocation / 100) * bundleCustPrice;

                console.log('===Setting Component Fields===', {
                    ProductName: line.record.SBQQ__ProductName__c,
                    revenueAllocation: revenueAllocation,
                    bundleCustPrice: bundleCustPrice,
                    calculatedCustomerPrice: line.record.SBQQ__CustomerPrice__c,
                    bundleProrate: line.record.SBQQ__ProrateMultiplier__c
                });

                if (!allocationSums[bundleMapKey]) {
                    allocationSums[bundleMapKey] = 0;
                }
                allocationSums[bundleMapKey] += revenueAllocation;
            }
        }
    });

    // Third pass: Validate allocation per unique bundle
    Object.keys(allocationSums).forEach(bundleMapKey => {
        const total = allocationSums[bundleMapKey];
        const target = 100;
        const tolerance = 0.01;

        const diff = Math.abs(total - target);
        if (diff > tolerance) {
            const bundleName = bundleNames[bundleMapKey];
            const errorMessage =
                `Revenue Allocation for bundle "${bundleName}" must total ${target}%. ` +
                `Currently: ${total.toFixed(2)}%.`;
            throw new Error(errorMessage);
        }
    });
}

/**
 * @description
 * This function populates the Bundle Parent Product Name field for Static Bundles in the Quote Line Editor.
 * It groups children by their parent bundle and constructs a string that includes the bundle name and its children.
 * @param quoteLineModels 
 */
async function populateBundleDetails(quoteLineModels, conn) {
    const productIds = quoteLineModels.map(line => line.record.SBQQ__Product__c);
    const productIdToItemMaster = {};

    if (productIds.length) {
        const productIdList = "('" + productIds.join("', '") + "')";
        const query = `SELECT Id, Item_Master_Product__r.Item_Name__c FROM Product2 WHERE Item_Master_Product__c != null AND Id IN ${productIdList}`;
        const queryResult = await conn.query(query);

        if (queryResult.totalSize) {
            queryResult.records.forEach(record => {
                console.log('==record====', record);
                productIdToItemMaster[record.Id] = record.Item_Master_Product__r.Item_Name__c || '';
                console.log('==productIdToItemMaster====', productIdToItemMaster);
            });
        }
    }

    console.log('===productIdToItemMaster===', productIdToItemMaster);

    const childrenByParent = {};
    quoteLineModels.forEach(line => {
        if (line.record.CPQ_Option_Type__c === 'Static Component' && line.parentItemKey) {
            const segmentIndex = line.record.SBQQ__SegmentIndex__c || '';
            const parentKey = line.record.Parent_Bundle_Key__c || '';
            const mapKey = `${segmentIndex}__${parentKey}`;

            if (!childrenByParent[mapKey]) {
                childrenByParent[mapKey] = [];
            }
            childrenByParent[mapKey].push(line.record);
        }
    });

    quoteLineModels.forEach(line => {
        const productId = line.record.SBQQ__Product__c;
        line.record.Bundle_Parent_Product_Name__c = productIdToItemMaster[productId] || '';

        /*if (line.record.CPQ_Option_Type__c === 'Static Bundle') {
            const segmentIndex = line.record.SBQQ__SegmentIndex__c || '';
            const bundleKey = line.record.Parent_Bundle_Key__c || '';
            const mapKey = `${segmentIndex}__${bundleKey}`;

            const children = childrenByParent[mapKey] || [];

            if (children.length > 0) {
                const childDetails = children.map(child => {
                    const code = child.SBQQ__ProductCode__c || '';
                    const name = productIdToItemMaster[child.SBQQ__Product__c] || '';
                    return `${code} - ${name}`;
                }).join(', ');

                const bundleName = productIdToItemMaster[line.record.SBQQ__Product__c] || '';
                line.record.Bundle_Parent_Product_Name__c = `${bundleName} including: ${childDetails}`;
            }
        }*/
    });
}



/**
 * Splits a string into chunks of a given size.
 * @param {string} str - The string to split.
 * @param {number} size - The size of each chunk.
 * @returns {string[]} - Array of string chunks.
 */
function splitStringBySize(str, size) {
    const split = [];
    for (let i = 0; i < str.length; i += size) {
        split.push(str.substring(i, i + size));
    }
    return split;
}

/**
 * @description
 * This function sets the Quote Deployment field on the Quote based on the Quote Lines.
 * It collects all non-blank Deployment values from the Quote Lines and joins them into a semicolon-separated string.
 * @param quoteLineModels
 * @returns {string} Returns a semicolon-separated string of all deployments.
 */
function setQuoteDeployment(quoteLineModels) {
    let deployments = [];

    // Iterate through the Quote Lines and append Deployment to the array if it's not blank
    quoteLineModels.forEach(function(line) {
        if (line.record.Deployment__c && line.record.Deployment__c !== '') {
            deployments.push(line.record.Deployment__c);
        }
    });

    // Return a semicolon-separated string of all deployments
    return deployments.join(';');
}

/**
 * @description
 * This function populates the end dates for quote lines based on the quote type and start date.
 * It sets the start date and calculates the end date as one year later, adjusting for amendments.
 * If the quote type is 'Amendment', it checks if the end date is less than the calculated end date and adjusts accordingly.
 * @param quoteLineModels 
 * @param quoteModel 
 * @param quoteType 
 * @param conn 
 */
function populateEndDates(quoteLineModels, quoteModel, quoteType, conn) {
    const FIXED_FEE_TYPE    = 'One-time';
    const FIXED_FEE_PRICING = 'Fixed Price';
    const quote = quoteModel.record;

    quoteLineModels.forEach(function (line) {
        const quoteLine = line.record;
        const product   = quoteLine["SBQQ__Product__r"] || {};

        // BIZ-74134 — Services product, line start ≠ quote start: realign start
        const isServicesWithMismatch =
            product["Product_Type__c"] === 'Services' &&
            quote.SBQQ__StartDate__c != null &&
            quoteLine.SBQQ__StartDate__c != quote.SBQQ__StartDate__c;

        // BIZ-80381 — One-time + Fixed Price: CPQ's day-based math is off; force the correct end date
        const isFixedFee =
            quoteLine.SBQQ__SubscriptionType__c    === FIXED_FEE_TYPE &&
            quoteLine.SBQQ__SubscriptionPricing__c === FIXED_FEE_PRICING &&
            quoteLine.SBQQ__StartDate__c           &&
            !quoteLine.SBQQ__EndDate__c; // BIZ-83557 — preserve custom end dates

        if (!isServicesWithMismatch && !isFixedFee) {
            return;
        }

        // Realign Services-line start before recomputing
        if (isServicesWithMismatch) {
            quoteLine.SBQQ__StartDate__c = quote.SBQQ__StartDate__c;
        }

        let newEndDate = getOneYearLaterDateString(quoteLine.SBQQ__StartDate__c);
        console.log('initial', newEndDate);

        // BIZ-80381 — Fixed Fee end-date convention is start + 1 year (no −1 day adjustment)
        /*if (isFixedFee && newEndDate) {
            newEndDate = addDaysToDateString(newEndDate, 1);
            console.log('fixedFeeAdjusted', newEndDate);
        }*/

        // Amendment cap applies to both branches — line end cannot exceed quote end
        if (quoteType === 'Amendment' &&
            quote.SBQQ__EndDate__c &&
            quote.SBQQ__EndDate__c < newEndDate) {
            quoteLine.SBQQ__EndDate__c = quote.SBQQ__EndDate__c;
            console.log('quoteLine.SBQQ__EndDate__c', quote.SBQQ__EndDate__c);
        } else {
            quoteLine.SBQQ__EndDate__c = newEndDate;
            console.log('newDate', newEndDate);
        }
    });
}

/**
 * @description Adds n days to a "yyyy-MM-dd" date string and returns the result in the same format.
 * @param dateStr  Date string in "yyyy-MM-dd"
 * @param days     Integer number of days to add (can be negative)
 * @returns {string|null}
 */
function addDaysToDateString(dateStr, days) {
    if (!dateStr) return null;
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return null;
    d.setUTCDate(d.getUTCDate() + days);
    return d.toISOString().split('T')[0];
}

/**
 * @description Returns a date string in "yyyy-MM-dd" format, one year later than the provided start date.
 * @param startDateStr 
 * @returns {string|null} Returns a date string in "yyyy-MM-dd" format, one year later than the provided start date.
 */
function getOneYearLaterDateString(startDateStr){
    if(!startDateStr) return null;
    var parts = String(startDateStr).split('T')[0].split('-');
    if(parts.length !== 3) return null;
    var year  = parseInt(parts[0], 10);
    var month = parseInt(parts[1], 10);
    var day   = parseInt(parts[2], 10);
    if(isNaN(year) || isNaN(month) || isNaN(day)) return null;
    // start + 1 year − 1 day, computed entirely in UTC
    var oneYearLater = new Date(Date.UTC(year + 1, month - 1, day - 1));
    return oneYearLater.toISOString().split('T')[0];
}

/**
 * @description -BIZ-67609
 * This function calculates the meter type based on the quote model and filtered quote lines.
 * It queries the Block Pricing records to validate the meter type and product code combinations.
 * @param quoteModel
 * @param filteredQuoteLines
 * @param conn
 * @returns {Promise} Returns a promise that resolves with the query result or rejects with an error message.
 */
function meterTypeCalculation(quoteModel, filteredQuoteLines, conn) {
    // Extract valid Meter Types and Product Codes from the filtered quote lines.
    let meterTypes = [...new Set(filteredQuoteLines.map(line => line.record.Per_Integrations__c).filter(mt => mt))];
    let products = [...new Set(filteredQuoteLines.map(line => line.record.SBQQ__Product__c).filter(pc => pc))];


    let optioncodes = [...new Set(filteredQuoteLines.map(line => line.record.CPQ_Option_Type__c).filter(pc => pc))];

    // Ensure values are correctly enclosed in single quotes
    let meterTypesStr = meterTypes.map(mt => "'" + mt + "'").join(",");
    let productsStr = products.map(pc => "'" + pc + "'").join(",");

    let productCodesStr11 = optioncodes.map(pc => "'" + pc + "'").join(",");

    console.log('Filtered Meter Types:', meterTypesStr);
    console.log('Filtered Product Codes:', productsStr);

    // Run the query only if both strings are not empty.
    if (meterTypesStr && productsStr) {
        let blockPricingQuery = "SELECT Block_Pricing_Meter_Type__c, Product__c, CurrencyIsoCode, Tier_Name__c, Lower_Bound__c, Upper_Bound__c, Type__c FROM Block_Pricing__c " +
            "WHERE Block_Pricing_Meter_Type__c IN (" + meterTypesStr + ") " +
            "AND Product__c IN (" + productsStr + ")";

        console.log('Final Query:', blockPricingQuery);

        return conn.query(blockPricingQuery).then(result => {
            console.log('Query Result:', result);

            const blockPricingRecords = result.records || [];
            console.log('Query blockPricingRecords:', blockPricingRecords);

            // Use the filtered quote lines to validate meter type.
            let errorMessages = [];
            filteredQuoteLines.forEach(line => {
                const meterType = line.record.Per_Integrations__c || '';
                const product = line.record.SBQQ__Product__c || '';
                const productCode = line.record.SBQQ__ProductCode__c || '';
                const currency = line.record.CurrencyIsoCode || '';
                const tier = quoteModel.record.GTM_Motion_Tier__c || '';
                const combinationKey = `${meterType}-${product}-${currency}-${tier}`;
                const quantity = Number(line.record.SBQQ__Quantity__c || 0);
                const pricingBasis = line.record.Pricing_Basis__c || '';

                const combinationErrorKey = `${productCode}-${quantity}-${meterType}`;

                let matchFound = false;

                for (const record of blockPricingRecords) {
                    if (
                        record.Block_Pricing_Meter_Type__c === meterType &&
                        record.Product__c === product &&
                        record.CurrencyIsoCode === currency
                    ) {
                        if (
                            pricingBasis === 'Quantity based' &&
                            record.Type__c === 'Employee Compliance' &&
                            quantity >= (record.Lower_Bound__c || 0) &&
                            quantity <= (record.Upper_Bound__c || Infinity)
                        ) {
                            matchFound = true;
                            break;
                        }

                        if (
                            pricingBasis === 'Tier based' &&
                            record.Type__c !== 'Employee Compliance' &&
                            record.Tier_Name__c === tier
                        ) {
                            matchFound = true;
                            break;
                        }
                    }
                }

                if (!matchFound) {
                    line.record.SBQQ__ListPrice__c = 0;
                    errorMessages.push(`"${combinationErrorKey}"`);
                }

            });
            // If an error message was set, throw the error so that QLE displays it.
            if (errorMessages != null && errorMessages.length > 0) {
                const combinedMessage = Array.from(errorMessages).join(", ");
                const finalMessage = `The selected meter type (or quantity, if quantity-based product) is not valid for this product. There is no list price for this combination (${combinedMessage})`;
                console.log('aggregatedError:..' + finalMessage);
                showBlockingPopup(finalMessage);
            }
            return result;
        }).catch(error => {
            console.log("Error querying Block Pricing records:", error);
            throw error;
        });
    } else {
        console.log("No valid Meter Types or Product Codes defined - skipping query.");
        // Optionally, return an empty promise or handle accordingly
        return Promise.resolve(null);
    }
}

/**
 * @description - BIZ-67609
 * This function validates the required fields for a quote based on its type.
 * It checks for the presence of Start Date, Total Contract Months, and First Segment Months
 * depending on whether the quote is a Quote, Amendment, or Renewal.
 * If any required fields are missing, it returns an array of those fields.
 * @param quoteModel 
 * @returns missingFields {Array} An array of missing fields that are required for the quote.
 */
function validateQuoteFields(quoteModel) {
    const missingFields = [];
    const quoteType = quoteModel.record['SBQQ__Type__c'];
    const startDate = quoteModel.record['SBQQ__StartDate__c'];
    const totalContractMonths = quoteModel.record['SBQQ__SubscriptionTerm__c'];

    if (quoteType === 'Quote') {
        if (!startDate) missingFields.push('Start Date');
        if (!totalContractMonths) missingFields.push('Total Contract Months');
        if (!quoteModel.record['First_Segment_Months__c']) missingFields.push('First Segment Months');
    } else if (quoteType === 'Amendment') {
        if (!startDate) missingFields.push('Start Date');
    } else if (quoteType === 'Renewal') {
        if (!totalContractMonths) missingFields.push('Total Contract Months');
    }
    return missingFields;
}

/**
 * @description
 * This function applies price rules to the quote line models.
 * It checks if the One Time Credit field is present and adjusts the Partner Price accordingly.
 * The Partner Price is calculated as the Net Total minus the One Time Credit, divided by the Effective Quantity.
 * @param quoteLineModels 
 */
function applyPriceRules(quoteLineModels) {
    quoteLineModels.forEach(line => {
        if (line.record.One_Time_Credit__c) {
            line.record.SBQQ__PartnerPrice__c =
                (line.record.SBQQ__NetTotal__c - line.record.One_Time_Credit__c) /
                line.record.SBQQ__EffectiveQuantity__c;
        }
    });
}

/**
 * @description
 * This function resets the totals for the quote.
 * @param quote
 */
function resetTotals(quote) {
    quote.record["First_Year_Software_Total__c"] = 0;
    quote.record["Second_Year_Software_Total__c"] = 0;
    quote.record["Third_Year_Software_Total__c"] = 0;
    quote.record["Fourth_Year_Software_Total__c"] = 0;
    quote.record["Fifth_Year_Software_Total__c"] = 0;
    quote.record["Sixth_Year_Software_Total__c"] = 0;
    quote.record["Segment_Total_List_Unit_Price__c"] = 0;
    quote.record["Segment_Total_Net_unit_Price__c"] = 0;
    quote.record["Total_Subscription_Fees_Year_1__c"] = 0;
    quote.record["Total_Subscription_Fees_2nd_Year__c"] = 0;
    quote.record["Total_Subscription_Fees_3rd_Year__c"] = 0;
    quote.record["Total_Subscription_Fees_4th_Year__c"] = 0;
    quote.record["Total_Subscription_Fees_5th_Year__c"] = 0;
    quote.record["Total_Subscription_Fees_6th_Year__c"] = 0;

    quote.record["One_time_Credit_Yr1__c"] = 0;
    quote.record["One_time_Credit_Yr2__c"] = 0;
    quote.record["One_time_Credit_Yr3__c"] = 0;
    quote.record["One_time_Credit_Yr4__c"] = 0;
    quote.record["One_time_Credit_Yr5__c"] = 0;
    quote.record["One_time_Credit_Yr6__c"] = 0;
    quote.record["One_time_Credit_on_Services__c"] = 0;

    return quote;
}

/**
 * @description
 * This function sets the totals for the quote based on the line items.
 * @param quote 
 * @param lines 
 */
function setTotals(quote, lines) {
    for (let i = 0; i < lines.length; i++) {
        console.log("Total Calculations");
        let line = lines[i];
        // Check if the line is a software product and not a payment adjustment and set the totals accordingly for each year
        if ((line.record["Product_Type__c"] == 'Software' || line.record["Product_Type__c"] == 'Software Discount' || line.record["Product_Type__c"] == 'Software Discount (One-Time)')) {
            if (line.record["SBQQ__SegmentIndex__c"] == 1) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    console.log(i + '====before=====First_Year_Software_Total__c=====' + quote.record["First_Year_Software_Total__c"]);
                    quote.record["First_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                    console.log(i + '====after=====First_Year_Software_Total__c=====' + quote.record["First_Year_Software_Total__c"]);
                }
                quote.record["Total_Subscription_Fees_Year_1__c"] += calculateNetTotal(line.record, false);

            }
            if (line.record["SBQQ__SegmentIndex__c"] == 2) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    console.log(i + '====before=====Second_Year_Software_Total__c=====' + quote.record["Second_Year_Software_Total__c"]);
                    quote.record["Second_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                    console.log(i + '====after=====Second_Year_Software_Total__c=====' + quote.record["Second_Year_Software_Total__c"]);
                }

                quote.record["Total_Subscription_Fees_2nd_Year__c"] += calculateNetTotal(line.record, false);
                console.log(i + '====after=====Second_Year_Software_Total__c=====' + quote.record["Second_Year_Software_Total__c"]);

            }
            if (line.record["SBQQ__SegmentIndex__c"] == 3) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    console.log(i + '====before=====Third_Year_Software_Total__c=====' + quote.record["Third_Year_Software_Total__c"]);
                    quote.record["Third_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                }
                quote.record["Total_Subscription_Fees_3rd_Year__c"] += calculateNetTotal(line.record, false);
                console.log(i + '====after=====Total_Subscription_Fees_3rd_Year__c=====' + quote.record["Second_Year_Software_Total__c"]);

            }
            if (line.record["SBQQ__SegmentIndex__c"] == 4) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    quote.record["Fourth_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                }
                quote.record["Total_Subscription_Fees_4th_Year__c"] += calculateNetTotal(line.record, false);
                console.log(i + '====after=====Total_Subscription_Fees_4th_Year__c=====' + quote.record["Second_Year_Software_Total__c"]);

            }
            if (line.record["SBQQ__SegmentIndex__c"] == 5) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    quote.record["Fifth_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                }
                quote.record["Total_Subscription_Fees_5th_Year__c"] += calculateNetTotal(line.record, false);
                console.log(i + '====after=====Total_Subscription_Fees_5th_Year__c=====' + quote.record["Second_Year_Software_Total__c"]);

            }
            if (line.record["SBQQ__SegmentIndex__c"] == 6) {
                if (!(line.record["SBQQ__ProductName__c"].includes('Payment Adjustment'))) {
                    quote.record["Sixth_Year_Software_Total__c"] += calculateAnnualizedValue(line.record, quote.record);
                }
                console.log(i + '====before====Total_Subscription_Fees_6th_Year__c=====' + quote.record["Total_Subscription_Fees_6th_Year__c"]);
                quote.record["Total_Subscription_Fees_6th_Year__c"] += calculateNetTotal(line.record, false);
                console.log(i + '====after=====Total_Subscription_Fees_6th_Year__c=====' + quote.record["Total_Subscription_Fees_6th_Year__c"]);

            }
        }

        // set the segment totals for list unit price and net unit price
        quote.record["Segment_Total_List_Unit_Price__c"] += calculateTotalPrice(line.record); //line.record["segment_List_Unit_price__c"];
        quote.record["Segment_Total_Net_unit_Price__c"] += calculateNetTotal(line.record, true); //line.record["Segment_Net_Unit_Price__c"];


        if (!['Software', 'Software Discount (One-Time)'].includes(line.record["Product_Type__c"]) && line.record["SBQQ__EffectiveQuantity__c"] !== 0) {
            quote.record["One_time_Credit_on_Services__c"] += line.record["One_Time_Credit__c"];
        }

        let segmentIndexyear = calculateSegmentIndexYear(line.record, quote);

        if (segmentIndexyear == 1) {
            quote.record["One_time_Credit_Yr1__c"] += calculateOneTimeCreditTotal(line.record);
        }
        if (segmentIndexyear == 2) {
            quote.record["One_time_Credit_Yr2__c"] += calculateOneTimeCreditTotal(line.record);
        }
        if (segmentIndexyear == 3) {
            quote.record["One_time_Credit_Yr3__c"] += calculateOneTimeCreditTotal(line.record);
        }
        if (segmentIndexyear == 4) {
            quote.record["One_time_Credit_Yr4__c"] += calculateOneTimeCreditTotal(line.record);
        }
        if (segmentIndexyear == 5) {
            quote.record["One_time_Credit_Yr5__c"] += calculateOneTimeCreditTotal(line.record);
        }
        if (segmentIndexyear == 6) {
            quote.record["One_time_Credit_Yr6__c"] += calculateOneTimeCreditTotal(line.record);
        }
    }
}

/**
 * Calculates the annualized value of a quote line based on Net Price and Effective Quantity,
 * spread over the number of months between Effective Start and End Dates.
 */
function calculateAnnualizedValue(quoteLine, quote) {
    const startDate = quoteLine.SBQQ__StartDate__c ? new Date(quoteLine.SBQQ__StartDate__c) : null;
    const endDate = quoteLine.SBQQ__EndDate__c ? new Date(quoteLine.SBQQ__EndDate__c) : null;
    console.log(startDate + '====startDate=====' + endDate);

    const startDay = startDate ? startDate.getUTCDate() : null;
    const endDay = endDate ? endDate.getUTCDate() : null;
    const startMonth = startDate ? startDate.getUTCMonth() + 1 : null;
    const endMonth = endDate ? endDate.getUTCMonth() + 1 : null;
    const startYear = startDate ? startDate.getUTCFullYear() : null;
    const endYear = endDate ? endDate.getUTCFullYear() : null;

    let months = quoteLine.SBQQ__ProrateMultiplier__c;
    console.log(quoteLine.SBQQ__Renewal__c + '====quoteLine.SBQQ__Existing__c=====' + quoteLine.SBQQ__Existing__c);
    console.log(quoteLine.SBQQ__PriorQuantity__c + '====quoteLine.SBQQ__PriorQuantity__c=====' + quoteLine.SBQQ__CustomerPrice__c);
    let numerator = 0;
    if (
        quoteLine.SBQQ__Renewal__c &&
        !quoteLine.SBQQ__Existing__c &&
        (quoteLine.SBQQ__PriorQuantity__c === null || quoteLine.SBQQ__PriorQuantity__c === undefined)
    ) {
        numerator = 0;
    } else {
        numerator = (quoteLine.SBQQ__CustomerPrice__c || 0) * (quoteLine.SBQQ__Quantity__c || 0);
    }
    console.log(months + '====numerator=====' + numerator + '========months====' + months);
    const result = months > 0 ? (numerator * 12) / months : 0;
    console.log(months + '====numerator=====' + ((numerator * 12) / months) + '========months====' + months);
    return result;
}

/** 
 * @description
 * This function calculates the total price for a quote line based on its product type and name.
 * It returns the Total Price Book Amount for software products, excluding payment adjustments.
 * @param quoteLine 
 * @returns total price for the quote line
 */
function calculateTotalPrice(quoteLine) {
    const productType = quoteLine.Product_Type__c;
    const productName = quoteLine.SBQQ__Product__r.Name || '';
    const isSoftwareType = (
        productType === 'Software' ||
        productType === 'Software Discount' ||
        productType === 'Software Discount (One-Time)'
    );
    const isNotPaymentAdjustment = !productName.includes('Payment Adjustment');
    const isAmendedLine = quoteLine.SBQQ__UpgradedSubscription__c; // BIZ-72128

    if (isAmendedLine) {
        // If it's an amended line, return 0
        return 0;
    } else if (isSoftwareType && isNotPaymentAdjustment) {
        // Return the SBQQ__ListTotal__c for software products
        return (quoteLine.SBQQ__ListTotal__c || 0);
    } else {
        return 0;
    }
}

/**
 * @description
 * This function calculates the net total for a quote line based on its product type and name.
 * It returns the product of quantity and net price for software products, excluding payment adjustments.
 * @param quoteLine 
 * @returns net total for the quote line
 */
function calculateNetTotal(quoteLine, skipAmendedLines) {
    const productType = quoteLine.Product_Type__c;
    const productName = quoteLine.SBQQ__Product__r.Name || '';

    const isSoftwareType = (
        productType === 'Software' ||
        productType === 'Software Discount' ||
        productType === 'Software Discount (One-Time)'
    );

    const isNotPaymentAdjustment = !productName.includes('Payment Adjustment');
    if (isSoftwareType && isNotPaymentAdjustment) {
        const isRenewal = quoteLine.SBQQ__Renewal__c;
        const isExisting = quoteLine.SBQQ__Existing__c;
        const priorQty = quoteLine.SBQQ__PriorQuantity__c;
        const isAmendedLine = quoteLine.SBQQ__UpgradedSubscription__c; // BIZ-72128

        if ((isRenewal && !isExisting && (priorQty === null || priorQty === undefined)) || (skipAmendedLines && isAmendedLine)) {
            return 0;
        } else {
            return (quoteLine.SBQQ__NetPrice__c || 0) * (calculateCustomQuantity(quoteLine) || 0);
        }
    } else {
        return 0;
    }
}

/**
 * @description
 * Calculates the adjusted quantity for a quote line based on CPQ logic.
 * Considers pricing method, subscription type, asset refund, and upgrade quantities.
 * 
 * @param {Object} quoteLine - The quote line record
 * @returns {number} - Final calculated quantity
 */
function calculateCustomQuantity(quoteLine) {
    const isSlab = quoteLine.SBQQ__DiscountScheduleType__c === 'Slab';
    const isBlock = quoteLine.SBQQ__PricingMethod__c === 'Block';
    const isExisting = quoteLine.SBQQ__Existing__c === true;
    const isCarryover = quoteLine.SBQQ__CarryoverLine__c === true;
    const allowAssetRefund = quoteLine.SBQQ__AllowAssetRefund__c === true;
    const subscriptionPricing = quoteLine.SBQQ__SubscriptionPricing__c || '';

    const quantity = quoteLine.SBQQ__Quantity__c || 0;
    const priorQuantity = quoteLine.SBQQ__PriorQuantity__c || 0;
    const upgradedQuantity = quoteLine.SBQQ__UpgradedQuantity__c || 0;

    const condition1 = !isExisting && !isCarryover && quantity === 0;

    const condition2 = (
        (isExisting || isCarryover) &&
        (
            quantity === (priorQuantity - upgradedQuantity) ||
            (!allowAssetRefund && subscriptionPricing === '' && quantity < (priorQuantity - upgradedQuantity))
        )
    );

    if (isSlab || isBlock) {
        if (condition1 || condition2) {
            return 0;
        } else {
            return 1;
        }
    } else {
        if (!isExisting && !isCarryover) {
            return quantity;
        } else if (quantity >= (priorQuantity - upgradedQuantity)) {
            if (subscriptionPricing === 'Percent Of Total') {
                return quantity;
            } else {
                return quantity - priorQuantity + upgradedQuantity;
            }
        } else if (!allowAssetRefund && subscriptionPricing === '') {
            return 0;
        } else {
            return quantity - priorQuantity + upgradedQuantity;
        }
    }
}

/**
 * @description
 * This function calculates one time credit total for a quote line based on its product type.
 * It returns the product of quantity and net price for software products, excluding payment adjustments.
 * @param quoteLine 
 * @returns net total for the quote line
 */
function calculateOneTimeCreditTotal(quoteLine) {
    const productType = quoteLine.Product_Type__c;
    const isParentOfBundle__c = quoteLine.Parent_of_Bundle__c;

    const isSoftwareType = (
        productType === 'Software' ||
        productType === 'Software Discount (One-Time)'
    );


    if (isSoftwareType && !isParentOfBundle__c) {
        return quoteLine.One_Time_Credit__c * -1 || 0;
    } else {
        return 0;
    }
}

/**
 * This function calculates Segment Index Year
 * @param quoteLine 
 * @param quote 
 * @returns 
 */
function calculateSegmentIndexYear(quoteLine, quote) {

    if (quoteLine.SBQQ__SegmentIndex__c == 0 &&
        (quote.SegmentIndex_Max_Value__c == 0 || (quote.SegmentIndex_Max_Value__c > 0 && quoteLine.SBQQ__RequiredBy__c == '') || quoteLine.SBQQ__RequiredBy__c != '')) {
        return 1;
    } else {
        return quoteLine.SBQQ__SegmentIndex__c;
    }
}

/**
 * This function calculates Partial Month
 * @param quote 
 * @returns 
 */
function setPartialMonthFlag(quoteLineModels, quoteModel) {
    const quote = quoteModel.record;
    let hasPartialMonth = false;

    //const lines = quoteLineModels.models || []; // THIS IS KEY

    quoteLineModels.forEach(function(line) {
        const quoteLine = line.record;

        // Start and end dates
        const start = new Date(quoteLine.SBQQ__StartDate__c + 'T00:00:00');
        const end = new Date(quoteLine.SBQQ__EndDate__c + 'T00:00:00');
        const monthsToAdd = quote.First_Segment_Months__c || 0;

        // Calculate expected end date (ADDMONTHS(...)-1)
        const calcEnd = new Date(start.getFullYear(), start.getMonth() + monthsToAdd, start.getDate());
        calcEnd.setDate(calcEnd.getDate() - 1);

        // Compare only year, month, day
        const datesDifferent =
            end.getFullYear() !== calcEnd.getFullYear() ||
            end.getMonth() !== calcEnd.getMonth() ||
            end.getDate() !== calcEnd.getDate();

        // Formula-style condition
        const partial =
            (quoteLine.SBQQ__ProductCode__c || "").slice(-2) !== "-P" &&
            (quoteLine["SBQQ__Product__r"]["SBQQ__SubscriptionType__c"] || "") === "Renewable" &&
            (quoteLine["SBQQ__Product__r"]["SBQQ__SubscriptionPricing__c"] || "") === "Fixed Price" &&
            (quoteLine["SBQQ__Product__r"]["SBQQ__SubscriptionTerm__c"] != null && quoteLine["SBQQ__Product__r"]["SBQQ__SubscriptionTerm__c"] !== "") &&
            quoteLine.SBQQ__SegmentIndex__c === 1 &&
            datesDifferent;

        if (partial) {
            hasPartialMonth = true;
        }
    });

    if (hasPartialMonth) {
        quote.Has_Partial_Month__c = true;
    }
}

function showBlockingPopup(message) {
    // Container
    const popup = document.createElement('div');
    popup.id = 'custom-popup';

    // Message
    const msg = document.createElement('div');
    msg.textContent = message;

    // OK Button
    const okBtn = document.createElement('button');
    okBtn.textContent = 'OK';
    okBtn.onclick = () => popup.remove();

    Object.assign(popup.style, {
        position: 'fixed',
        top: '40%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        background: '#fff',
        padding: '16px',
        border: '1px solid #ccc',
        zIndex: 9999,
        fontSize: '14px',
        textAlign: 'center',
        minWidth: '200px'
    });

    okBtn.style.marginTop = '10px';

    popup.appendChild(msg);
    popup.appendChild(okBtn);
    document.body.appendChild(popup);
}

/**
 * Calculates the total discount across all Quote Lines with Product_Type__c = 'T&M'.
 * For each applicable line, it computes: One_Time_Credit__c,
 * and then sums the results to populate the T_M_Lines_Total_Discount__c field on the Quote.
 * Added via BIZ-71953
 */
function populateTMDiscountOnQuote(quoteModel, quoteLineModels) {

    let rolledUpDiscount = 0;

    quoteLineModels.forEach(line => {
        const record = line.record;
        const isTMService = record["SBQQ__Product__r"]["Services_Product_Type__c"] === 'T&M';
        const credit = parseFloat(record.One_Time_Credit__c || 0);

        if (isTMService && credit > 0) {
            rolledUpDiscount += credit;
            console.log(`Line ${record.Name || '[Unnamed Line]'}: Credit=${credit}, Discount=${rolledUpDiscount}`);
        }
    });

    const discountPercent = Math.floor(rolledUpDiscount);
    quoteModel.record.T_M_Lines_Total_Discount__c = discountPercent;
    console.log(`Rolled-up T&M Services Discount: ${discountPercent}`);
}