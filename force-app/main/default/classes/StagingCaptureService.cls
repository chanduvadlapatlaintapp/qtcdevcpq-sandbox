/**
 * @description Fail-silent utility that automatically captures DML operations
 *              into SKU_Config_Staging_Entry__c records. Controllers call
 *              capture() after each DML; entries accumulate under an auto-managed
 *              Open session per user.
 *
 *              JSON output matches the Gearset .gs.json format:
 *              { "Object": "...", "Fields": { ... }, "References": [ ... ] }
 *
 *              If staging fails (permissions, limits, etc.), the primary DML is
 *              NOT affected — all staging logic is wrapped in try-catch.
 *
 * @author      Sahal Mohamed
 * @date        2026-03-11
 * @jira        BIZ-80418
 */
public with sharing class StagingCaptureService {

    // ─── Inner Config Classes ─────────────────────────────────────────

    /**
     * @description Describes a lookup / master-detail reference field so that
     *              the serialiser can produce a Gearset-compatible References
     *              array with resolved external Ids.
     */
    public class ReferenceField {
        public String fieldApiName;       // e.g. 'Product__c'
        public String relationshipName;   // e.g. 'Product__r'
        public String referencedObject;   // e.g. 'Product2'

        public ReferenceField(String fieldApiName, String relationshipName, String referencedObject) {
            this.fieldApiName      = fieldApiName;
            this.relationshipName  = relationshipName;
            this.referencedObject  = referencedObject;
        }
    }

    /**
     * @description Configuration for a tracked object: which field holds the
     *              external Id, which fields to serialise, and which fields
     *              are lookup references.
     */
    public class ObjectConfig {
        public String  externalIdField;
        public String  nameField;
        public String  secondaryNameField; // Optional: when set, display name = nameField + ' - ' + secondaryNameField
        public List<String> fields;
        public List<ReferenceField> references;

        public ObjectConfig(String externalIdField, String nameField, List<String> fields) {
            this.externalIdField = externalIdField;
            this.nameField       = nameField;
            this.fields          = fields;
            this.references      = new List<ReferenceField>();
        }

        public ObjectConfig(String externalIdField, String nameField, List<String> fields, List<ReferenceField> refs) {
            this.externalIdField = externalIdField;
            this.nameField       = nameField;
            this.fields          = fields;
            this.references      = refs != null ? refs : new List<ReferenceField>();
        }

        public ObjectConfig(String externalIdField, String nameField, String secondaryNameField, List<String> fields, List<ReferenceField> refs) {
            this.externalIdField     = externalIdField;
            this.nameField           = nameField;
            this.secondaryNameField  = secondaryNameField;
            this.fields              = fields;
            this.references          = refs != null ? refs : new List<ReferenceField>();
        }
    }

    // ─── Object Registry ────────────────────────────────────────────────

    @TestVisible
    private static final Map<String, ObjectConfig> OBJECT_REGISTRY =
        new Map<String, ObjectConfig>{
            'Product2' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name', 'ProductCode', 'IsActive', 'Description', 'Family',
                    'SBQQ__SubscriptionType__c',
                    'GearsetExternalId__c'
                }
            ),
            'Block_Pricing__c' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name', 'Tier_Name__c', 'Type__c',
                    'Lower_Bound__c', 'Upper_Bound__c', 'Price__c',
                    'CurrencyIsoCode', 'Fiscal_Year__c', 'Active__c',
                    'Block_Pricing_Meter_Type__c',
                    'GearsetExternalId__c'
                },
                new List<ReferenceField>{
                    new ReferenceField('Product__c',    'Product__r',    'Product2'),
                    new ReferenceField('Price_Book__c', 'Price_Book__r', 'Pricebook2')
                }
            ),
            'Intapp_Pricing__c' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name', 'Price__c', 'CurrencyIsoCode',
                    'Meter_Type__c',
                    'GearsetExternalId__c'
                },
                new List<ReferenceField>{
                    new ReferenceField('Product__c',    'Product__r',    'Product2'),
                    new ReferenceField('Price_Book__c', 'Price_Book__r', 'Pricebook2')
                }
            ),
            'PricebookEntry' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'UnitPrice', 'IsActive', 'CurrencyIsoCode',
                    'GearsetExternalId__c'
                },
                new List<ReferenceField>{
                    new ReferenceField('Pricebook2Id', 'Pricebook2', 'Pricebook2'),
                    new ReferenceField('Product2Id',   'Product2',   'Product2')
                }
            ),
            'Item_Master_Product__c' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name', 'Item_Name__c', 'Description__c', 'Active__c',
                    'GearsetExternalId__c'
                }
            ),
            'Product_Line__c' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name', 'Cloud_Addendum_Required__c',
                    'GearsetExternalId__c'
                }
            ),
            'Product_Rollup__c' => new ObjectConfig(
                'GearsetExternalId__c', 'Name',
                new List<String>{
                    'Name',
                    'GearsetExternalId__c'
                },
                new List<ReferenceField>{
                    new ReferenceField('Product_Line__c', 'Product_Line__r', 'Product_Line__c')
                }
            ),
            // nameField = SBQQ__PrintOrder__c + ' - ' + SBQQ__Status__c (composite via secondaryNameField)
            // matches Gearset's own GearsetDisplayName convention for quote terms
            'SBQQ__QuoteTerm__c' => new ObjectConfig(
                'GearsetExternalId__c', 'SBQQ__PrintOrder__c', 'SBQQ__Status__c',
                new List<String>{
                    'SBQQ__Body__c', 'SBQQ__PrintOrder__c',
                    'SBQQ__Active__c', 'SBQQ__Status__c',
                    'GearsetExternalId__c'
                },
                null
            )
        };

    // ─── Static Session Cache ───────────────────────────────────────────

    /** Cached session Id for the current transaction (avoids repeated queries). */
    @TestVisible
    private static Id cachedSessionId;

    // ─── Public API ─────────────────────────────────────────────────────

    /**
     * @description Captures insert/update DML operations into staging entries.
     *              Only records that have a populated external Id are captured;
     *              records without one are silently skipped.
     *              For non-delete operations, records are re-queried from the DB
     *              so all OBJECT_REGISTRY fields are fully populated regardless
     *              of what fields the controller had on its in-memory records.
     * @param records        The SObject records that were just DML'd
     * @param objectApiName  API name of the object (e.g., 'Product2')
     * @param operationType  'Create', 'Update', or 'Delete'
     */
    public static void capture(List<SObject> records, String objectApiName, String operationType) {
        try {
            if (records == null || records.isEmpty()) return;

            // Feature flag: allow ops team to disable capture without a deployment
            if (Automation_Controls__c.getInstance().Bypass_Staging_Capture__c == true) return;

            ObjectConfig config = OBJECT_REGISTRY.get(objectApiName);
            if (config == null) return;

            Id sessionId = getOrCreateSession();
            if (sessionId == null) return;

            // Re-query for create/update so serialisation uses full DB field values.
            // Skipped for deletes — records are already gone from the database.
            List<SObject> recordsToCapture = operationType.equalsIgnoreCase('Delete')
                ? records
                : requeryRecords(records, objectApiName, config);

            // Resolve lookup references → GearsetExternalId__c
            Map<Id, String> lookupExternalIds = resolveLookupExternalIds(recordsToCapture, config);

            List<SKU_Config_Staging_Entry__c> entries = new List<SKU_Config_Staging_Entry__c>();

            for (SObject rec : recordsToCapture) {
                // Skip records without an Id (failed partial-success inserts)
                if (rec.Id == null) continue;

                // Get the external Id value
                String externalId = safeGetString(rec, config.externalIdField);
                if (String.isBlank(externalId)) continue;

                // Get display name (composite for objects with secondaryNameField, e.g. QuoteTerm)
                String recordName = buildDisplayName(rec, config);
                if (String.isBlank(recordName)) {
                    recordName = String.valueOf(rec.Id);
                }

                // Serialise in Gearset .gs.json format
                String jsonContent = serializeGearsetFormat(
                    rec, config, objectApiName, lookupExternalIds
                );

                entries.add(new SKU_Config_Staging_Entry__c(
                    Staging__c              = sessionId,
                    Object_API_Name__c      = objectApiName,
                    Record_Name__c          = recordName,
                    Gearset_External_Id__c  = externalId,
                    JSON_Content__c         = jsonContent,
                    Operation_Type__c       = operationType
                ));
            }

            if (entries.isEmpty()) return;

            // Delete-before-insert: remove prior entries in this session for the same
            // external Ids so only the latest state is captured.
            Set<String> externalIds = new Set<String>();
            for (SKU_Config_Staging_Entry__c e : entries) {
                externalIds.add(e.Gearset_External_Id__c);
            }

            List<SKU_Config_Staging_Entry__c> stale = [
                SELECT Id
                FROM SKU_Config_Staging_Entry__c
                WHERE Staging__c = :sessionId
                  AND Gearset_External_Id__c IN :externalIds
            ];
            if (!stale.isEmpty()) {
                delete stale;
            }

            insert entries;

            Nebula.Logger.info('Captured ' + entries.size() + ' ' + objectApiName
                + ' record(s) [' + operationType + '] in session ' + sessionId)
                .addTag('StagingCaptureService');
            Nebula.Logger.saveLog();

        } catch (Exception e) {
            // Fail-silent: log and swallow
            try {
                Nebula.Logger.error('StagingCaptureService.capture failed for ' + objectApiName
                    + ': ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString())
                    .addTag('StagingCaptureService');
                Nebula.Logger.saveLog();
            } catch (Exception logEx) {
                // Swallow logger failures too
            }
        }
    }

    /**
     * @description Captures delete operations into staging entries.
     *              Uses 'Delete' as the operation type and stores the deleted
     *              record's last known state.
     * @param records        The SObject records that were just deleted
     * @param objectApiName  API name of the object
     */
    public static void captureDeletes(List<SObject> records, String objectApiName) {
        capture(records, objectApiName, 'Delete');
    }

    // ─── Private Helpers ────────────────────────────────────────────────

    /**
     * @description Returns the current user's Open staging session, creating one
     *              if none exists. Caches the session Id in a static variable.
     * @return The session Id, or null if creation failed
     */
    @TestVisible
    private static Id getOrCreateSession() {
        if (cachedSessionId != null) {
            return cachedSessionId;
        }

        // Check for an existing Open session for the current user
        List<SKU_Config_Staging__c> existing = [
            SELECT Id
            FROM SKU_Config_Staging__c
            WHERE CreatedById = :UserInfo.getUserId()
              AND Status__c = :SKUConfigStagingBatch.STATUS_OPEN
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            cachedSessionId = existing[0].Id;
            return cachedSessionId;
        }

        // Create a new Open session
        SKU_Config_Staging__c session = new SKU_Config_Staging__c(
            Session_Id__c = generateSessionId(),
            Status__c     = SKUConfigStagingBatch.STATUS_OPEN
        );
        insert session;
        cachedSessionId = session.Id;
        return cachedSessionId;
    }

    /**
     * @description Generates a UUID-style session identifier.
     * @return A unique session Id string
     */
    private static String generateSessionId() {
        Blob randomBytes = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(randomBytes);
        return hex.substring(0, 8) + '-'
             + hex.substring(8, 12) + '-'
             + hex.substring(12, 16) + '-'
             + hex.substring(16, 20) + '-'
             + hex.substring(20, 32);
    }

    /**
     * @description Resolves lookup field values to the referenced records'
     *              GearsetExternalId__c. Groups by referenced object type
     *              and queries each in bulk.
     * @param records List of SObject records to resolve lookups for
     * @param config  ObjectConfig containing reference definitions
     * @return Map of Salesforce Id → GearsetExternalId__c for all referenced records
     */
    private static Map<Id, String> resolveLookupExternalIds(
        List<SObject> records, ObjectConfig config
    ) {
        Map<Id, String> result = new Map<Id, String>();
        if (config.references == null || config.references.isEmpty()) {
            return result;
        }

        // Group lookup Ids by referenced object type
        Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
        for (ReferenceField ref : config.references) {
            if (!idsByObject.containsKey(ref.referencedObject)) {
                idsByObject.put(ref.referencedObject, new Set<Id>());
            }
            for (SObject rec : records) {
                try {
                    Object val = rec.get(ref.fieldApiName);
                    if (val != null) {
                        idsByObject.get(ref.referencedObject).add((Id) val);
                    }
                } catch (Exception e) {
                    // Field not populated — skip
                }
            }
        }

        // Query each referenced object for GearsetExternalId__c
        for (String objName : idsByObject.keySet()) {
            Set<Id> ids = idsByObject.get(objName);
            if (ids.isEmpty()) continue;

            String query = 'SELECT Id, GearsetExternalId__c FROM '
                         + String.escapeSingleQuotes(objName)
                         + ' WHERE Id IN :ids';
            for (SObject r : Database.query(query)) {
                String extId = (String) r.get('GearsetExternalId__c');
                result.put(r.Id, extId != null ? extId : '');
            }
        }

        return result;
    }

    /**
     * @description Serialises a record into the Gearset .gs.json format:
     *              { "Object": "...", "Fields": { ... }, "References": [ ... ] }
     *              All field values are converted to strings. Lookup fields are
     *              placed in the References array with resolved external Ids.
     * @param rec               The SObject record
     * @param config            ObjectConfig with field and reference definitions
     * @param objectApiName     API name of the object
     * @param lookupExternalIds Map of Salesforce Id → GearsetExternalId__c
     * @return JSON string in Gearset .gs.json format
     */
    @TestVisible
    private static String serializeGearsetFormat(
        SObject rec,
        ObjectConfig config,
        String objectApiName,
        Map<Id, String> lookupExternalIds
    ) {
        Map<String, Object> root = new Map<String, Object>();
        root.put('Object', objectApiName);

        // ── Build Fields map (all values as strings) ──
        // Resolve field types so checkbox nulls default to "false"
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        Map<String, String> fieldsMap = new Map<String, String>();
        for (String field : config.fields) {
            try {
                Object val = rec.get(field);
                if (val != null) {
                    fieldsMap.put(field, String.valueOf(val));
                } else {
                    // Checkbox/Boolean fields default to "false", others to ""
                    Schema.SObjectField sof = fieldMap.get(field);
                    if (sof != null && sof.getDescribe().getType() == Schema.DisplayType.BOOLEAN) {
                        fieldsMap.put(field, 'false');
                    } else {
                        fieldsMap.put(field, '');
                    }
                }
            } catch (Exception e) {
                fieldsMap.put(field, '');
            }
        }

        // Add GearsetDisplayName (required by Gearset schema)
        // Composite for objects with secondaryNameField (e.g. QuoteTerm = "PrintOrder - Status")
        String displayName = buildDisplayName(rec, config);
        fieldsMap.put('GearsetDisplayName', displayName != null ? displayName : '');

        root.put('Fields', fieldsMap);

        // ── Build References array ──
        List<Object> references = new List<Object>();
        for (ReferenceField ref : config.references) {
            String extId = '';
            try {
                Id lookupId = (Id) rec.get(ref.fieldApiName);
                if (lookupId != null && lookupExternalIds.containsKey(lookupId)) {
                    extId = lookupExternalIds.get(lookupId);
                }
            } catch (Exception e) {
                // Field not populated — leave extId empty
            }

            Map<String, Object> refEntry = new Map<String, Object>();
            refEntry.put('Name', ref.relationshipName);
            refEntry.put('ReferencedObject', ref.referencedObject);
            refEntry.put('ReferencedFields', new Map<String, String>{
                'GearsetExternalId__c' => extId != null ? extId : ''
            });
            references.add(refEntry);
        }
        root.put('References', references);

        return JSON.serializePretty(root);
    }

    /**
     * @description Re-queries records from the DB with all fields defined in the
     *              ObjectConfig so serialisation always uses complete field values.
     *              Lookup reference fields are included so resolveLookupExternalIds
     *              can read them from the fresh records.
     * @param records       In-memory records (only Id is required to be populated)
     * @param objectApiName API name of the object
     * @param config        ObjectConfig with field and reference definitions
     * @return Freshly queried records, or the original list if no Ids found
     */
    @TestVisible
    private static List<SObject> requeryRecords(
        List<SObject> records, String objectApiName, ObjectConfig config
    ) {
        Set<Id> ids = new Set<Id>();
        for (SObject rec : records) {
            if (rec.Id != null) ids.add(rec.Id);
        }
        if (ids.isEmpty()) return records;

        Set<String> fieldsToQuery = new Set<String>(config.fields);
        fieldsToQuery.add('Id');
        for (ReferenceField ref : config.references) {
            fieldsToQuery.add(ref.fieldApiName);
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ')
            + ' FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE Id IN :ids';

        return Database.query(query);
    }

    /**
     * @description Safely reads a String field value from an SObject.
     * @param rec       The SObject record
     * @param fieldName API name of the field
     * @return The String value, or null if not available
     */
    private static String safeGetString(SObject rec, String fieldName) {
        try {
            Object val = rec.get(fieldName);
            return val != null ? String.valueOf(val) : null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Builds the human-readable display name for a record.
     *              When secondaryNameField is configured, concatenates primary
     *              and secondary field values with ' - ' (e.g. SBQQ__QuoteTerm__c
     *              uses PrintOrder + ' - ' + Status to match Gearset conventions).
     * @param rec    The SObject record
     * @param config ObjectConfig for the object
     * @return The display name string, or null if nameField is blank
     */
    @TestVisible
    private static String buildDisplayName(SObject rec, ObjectConfig config) {
        String primary = safeGetString(rec, config.nameField);
        if (String.isNotBlank(config.secondaryNameField)) {
            String secondary = safeGetString(rec, config.secondaryNameField);
            String combined = (primary != null ? primary : '')
                + ' - '
                + (secondary != null ? secondary : '');
            return combined.trim();
        }
        return primary;
    }

    /**
     * @description Returns the Gearset-compatible external Id for a record:
     *              reverse(String.valueOf(recordId)).
     *              Gearset stores reversed SF Record IDs in GearsetExternalId__c —
     *              all SKU controllers must use this method when populating the field.
     * @param recordId The Salesforce record Id
     * @return The reversed Id string, or null if recordId is null
     */
    public static String buildGearsetExternalId(Id recordId) {
        if (recordId == null) return null;
        return reverseString(String.valueOf(recordId));
    }

    /**
     * @description Reverses a string character by character.
     * @param s The input string
     * @return The reversed string, or the original if blank
     */
    @TestVisible
    private static String reverseString(String s) {
        if (String.isBlank(s)) return s;
        List<String> chars = s.split('');
        List<String> reversed = new List<String>();
        for (Integer i = chars.size() - 1; i >= 0; i--) {
            reversed.add(chars[i]);
        }
        return String.join(reversed, '');
    }
}