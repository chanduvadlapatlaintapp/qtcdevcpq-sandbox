/**
 * @description Apex controller for the AgenticQTC_OsaDocument Visualforce page.
 *              Produces an "Amendment to Order and Sale Agreement" PDF whose layout
 *              exactly mirrors the Conga Composer template used by the field team.
 *
 *              Key sections rendered by the VF page:
 *                • Header: Intapp logo + "Amendment to Order and Sale Agreement" title
 *                • 3-column address block: Intapp | Customer | Bill To
 *                • Terms grid: Date, OSA No., Amendment No. | Currency, Expires, Version
 *                • Subscription table grouped by contract year with per-year subtotals
 *                • Grand total row
 *                • Disclaimer + Terms &amp; Conditions header
 *                • Page 2: "Agreed to by" signature block
 *                • Repeating footer on every page
 *
 *              Rendering engine: Flying Saucer / iText (Salesforce VF PDF engine).
 *              CSS 2.1 only — no flexbox, grid, or CSS variables.
 *
 * @author  AgenticQTC Team
 * @date    2026-05-22
 * @jira    BIZ-81419
 */
public with sharing class AgenticQTC_NativePdfController {

    // ─── Intapp company address (constant — same on every document) ────────────
    public static final String INTAPP_ADDRESS_LINE1 = 'Integration Appliance, Inc.';
    public static final String INTAPP_ADDRESS_LINE2 = '3101 Park Boulevard';
    public static final String INTAPP_ADDRESS_LINE3 = 'Palo Alto, CA 94306';
    public static final String INTAPP_ADDRESS_LINE4 = 'United States';
    public static final String INTAPP_ADDRESS_LINE5 = 'Phone: (650) 852-0400';
    public static final String INTAPP_ADDRESS_LINE6 = 'Fax: (650) 852-0402';
    public static final String INTAPP_ADDRESS_LINE7 = 'http://www.intapp.com';

    // ─── Public properties exposed to the VF page ─────────────────────────────

    /** Today formatted as "June 19, 2026" for the Date field in the terms grid. */
    public String documentDate         { get; private set; }

    /** OSA (master contract) number, e.g. "38970". */
    public String osaNumber            { get; private set; }

    /** Sequential amendment number on this quote, e.g. "1". */
    public String amendmentNumber      { get; private set; }

    /** ISO currency code, e.g. "USD". */
    public String currencyCode         { get; private set; }

    /** Quote expiration date formatted as "June 11, 2026". */
    public String expiresFormatted     { get; private set; }

    /** Quote version number, e.g. "1". */
    public String versionNumber        { get; private set; }

    /** Account / customer name (used in signature block and footer). */
    public String accountName          { get; private set; }

    /** Customer billing address — line 1 (street). */
    public String billingStreet        { get; private set; }

    /** Customer billing city, state, zip line, e.g. "San Francisco, CA 94111". */
    public String billingCityLine      { get; private set; }

    /** Customer billing country. */
    public String billingCountry       { get; private set; }

    /** Lines of the Intapp "from" address block (constant). */
    public String intappAddrLine1      { get; private set; }
    public String intappAddrLine2      { get; private set; }
    public String intappAddrLine3      { get; private set; }
    public String intappAddrLine4      { get; private set; }
    public String intappAddrLine5      { get; private set; }
    public String intappAddrLine6      { get; private set; }
    public String intappAddrLine7      { get; private set; }

    /** Footer text repeated on every page. */
    public String footerText           { get; private set; }

    /** Grand total of all subscription fees (formatted string). */
    public String grandTotalFormatted  { get; private set; }

    /** Quote lines grouped by contract-year period, each with a subtotal. */
    public List<YearGroup> yearGroups  { get; private set; }

    /** Whether any related/uploaded documents exist (drives appendix section). */
    public Boolean hasRelatedDocs      { get; private set; }

    /** Wrapped related-content docs for the Appendix section. */
    public List<RelatedDocWrapper> relatedDocs { get; private set; }

    /** Raw HTML chunks rendered as the cover page (before page 1). Sourced from the
     *  "OSA First Page" SBQQ Quote Template's TemplateContent records so the Instant
     *  PDF stays in sync with edits Ops makes to the CPQ template. */
    public List<String> coverHtmlBlocks { get; private set; }

    /** True when at least one cover-page section was loaded — drives the cover
     *  block + trailing page break in the VF page. */
    public Boolean hasCoverPage        { get; private set; }

    /** Render-mode flag: when true, the VF page emits ONLY the cover-page block
     *  (no header, terms grid, signature, appendix). Driven by ?coverOnly=true
     *  on the page URL — used by the Conga path to prepend the cover via pdf-lib. */
    public Boolean coverOnly           { get; private set; }

    // SBQQ Quote Template that drives the cover page. Same name in UAT and qtcmock.
    private static final String COVER_TEMPLATE_NAME = 'OSA First Page';

    // Matches the SBQQ-style merge tokens in TemplateContent markup, e.g.
    // "{!quote.Invoicing_Contact_name__c}". Group 1 is the bare field API name.
    private static final Pattern QUOTE_TOKEN_PATTERN =
        Pattern.compile('\\{!quote\\.([A-Za-z0-9_]+)\\}');

    // ─── Constructor ──────────────────────────────────────────────────────────

    public AgenticQTC_NativePdfController() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        String quoteId  = params.get('quoteId');
        coverOnly       = 'true'.equalsIgnoreCase(params.get('coverOnly'));
        documentDate    = formatDate(Date.today());

        // Intapp address lines (constant)
        intappAddrLine1 = INTAPP_ADDRESS_LINE1;
        intappAddrLine2 = INTAPP_ADDRESS_LINE2;
        intappAddrLine3 = INTAPP_ADDRESS_LINE3;
        intappAddrLine4 = INTAPP_ADDRESS_LINE4;
        intappAddrLine5 = INTAPP_ADDRESS_LINE5;
        intappAddrLine6 = INTAPP_ADDRESS_LINE6;
        intappAddrLine7 = INTAPP_ADDRESS_LINE7;

        // Empty defaults for sections that may be skipped in cover-only mode so
        // VF expressions referencing them never NPE.
        yearGroups        = new List<YearGroup>();
        relatedDocs       = new List<RelatedDocWrapper>();
        hasRelatedDocs    = false;
        coverHtmlBlocks   = new List<String>();
        hasCoverPage      = false;
        accountName       = '';
        billingStreet     = '';
        billingCityLine   = '';
        billingCountry    = '';
        osaNumber         = '';
        amendmentNumber   = '';
        currencyCode      = 'USD';
        expiresFormatted  = '';
        versionNumber     = '';
        grandTotalFormatted = '$0.00';
        footerText        = '';

        if (String.isBlank(quoteId)) return;

        if (coverOnly) {
            // Skip the OSA body — cover block is the only thing this render needs.
            loadCoverPage(quoteId);
            return;
        }

        loadQuote(quoteId);
        loadYearGroups(quoteId);
        loadRelatedDocs(quoteId);
        loadCoverPage(quoteId);
    }

    // ─── Private data-load helpers ────────────────────────────────────────────

    /**
     * @description Loads the quote header and sets all metadata properties used
     *              in the address block, terms grid, and footer.
     */
    private void loadQuote(String quoteId) {
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, Name,
                   SBQQ__Account__r.Name,
                   SBQQ__BillingStreet__c,
                   SBQQ__BillingCity__c,
                   SBQQ__BillingState__c,
                   SBQQ__BillingPostalCode__c,
                   SBQQ__BillingCountry__c,
                   SBQQ__MasterContract__r.ContractNumber,
                   SBQQ__ExpirationDate__c,
                   CurrencyIsoCode,
                   OSA_Number__c,
                   Amendment_Count__c,
                   Version__c
            FROM   SBQQ__Quote__c
            WHERE  Id = :quoteId
            WITH   SECURITY_ENFORCED
            LIMIT  1
        ];

        if (quotes.isEmpty()) {
            accountName       = '';
            billingStreet     = '';
            billingCityLine   = '';
            billingCountry    = '';
            osaNumber         = '';
            amendmentNumber   = '';
            currencyCode      = 'USD';
            expiresFormatted  = '';
            versionNumber     = '';
            footerText        = '';
            return;
        }

        SBQQ__Quote__c q = quotes[0];
        accountName  = q.SBQQ__Account__r?.Name ?? '';
        billingStreet = q.SBQQ__BillingStreet__c ?? '';

        // Build "City, State ZIP" line
        String city    = q.SBQQ__BillingCity__c    ?? '';
        String state   = q.SBQQ__BillingState__c   ?? '';
        String zip     = q.SBQQ__BillingPostalCode__c ?? '';
        List<String> cityParts = new List<String>();
        if (String.isNotBlank(city))  cityParts.add(city);
        if (String.isNotBlank(state)) cityParts.add(state);
        billingCityLine = String.isNotBlank(zip)
            ? String.join(cityParts, ', ') + ' ' + zip
            : String.join(cityParts, ', ');
        billingCountry  = q.SBQQ__BillingCountry__c ?? '';

        // OSA and amendment metadata
        osaNumber       = q.OSA_Number__c != null
            ? q.OSA_Number__c
            : (q.SBQQ__MasterContract__r?.ContractNumber ?? q.Name);
        amendmentNumber = q.Amendment_Count__c != null
            ? String.valueOf(q.Amendment_Count__c.intValue())
            : '1';
        currencyCode    = q.CurrencyIsoCode ?? 'USD';
        expiresFormatted = q.SBQQ__ExpirationDate__c != null
            ? formatDate(q.SBQQ__ExpirationDate__c)
            : '';
        versionNumber   = q.Version__c != null ? q.Version__c : '1';

        // Footer text: "Amendment to OSA #XXXXX   AccountName   Integration Appliance (US)"
        footerText = 'Amendment to OSA #' + osaNumber
            + '    ' + accountName
            + '    Integration Appliance (US)';
    }

    /**
     * @description Loads quote lines, groups them by (startDate, endDate) period in
     *              chronological order, and calculates per-year and grand-total fees.
     *
     *              Year labels ("Year 1", "Year 2", …) are assigned in ascending
     *              start-date order, matching the Conga template convention.
     */
    private void loadYearGroups(String quoteId) {
        List<SBQQ__QuoteLine__c> rawLines = [
            SELECT SBQQ__ProductCode__c,
                   SBQQ__ProductName__c,
                   Support_Level__c,
                   SBQQ__StartDate__c,
                   SBQQ__EndDate__c,
                   SBQQ__Quantity__c,
                   License_Basis__c,
                   SBQQ__NetPrice__c
            FROM   SBQQ__QuoteLine__c
            WHERE  SBQQ__Quote__c = :quoteId
            WITH   SECURITY_ENFORCED
            ORDER BY SBQQ__StartDate__c ASC, SBQQ__ProductCode__c ASC
        ];

        // --- Group lines by (startDate, endDate) period ---
        // LinkedHashMap preserves insertion order (chronological, sorted by SOQL).
        Map<String, List<SBQQ__QuoteLine__c>> periodMap =
            new Map<String, List<SBQQ__QuoteLine__c>>();

        for (SBQQ__QuoteLine__c line : rawLines) {
            String key = (line.SBQQ__StartDate__c != null
                              ? String.valueOf(line.SBQQ__StartDate__c)
                              : 'null')
                       + '|'
                       + (line.SBQQ__EndDate__c != null
                              ? String.valueOf(line.SBQQ__EndDate__c)
                              : 'null');
            if (!periodMap.containsKey(key)) {
                periodMap.put(key, new List<SBQQ__QuoteLine__c>());
            }
            periodMap.get(key).add(line);
        }

        // --- Build YearGroup list, assigning "Year N" labels ---
        yearGroups = new List<YearGroup>();
        Decimal grandTotal = 0;
        Integer yearNum    = 1;

        for (String key : periodMap.keySet()) {
            List<SBQQ__QuoteLine__c> periodLines = periodMap.get(key);
            Decimal subtotal = 0;

            List<QuoteLineWrapper> wrappers = new List<QuoteLineWrapper>();
            Integer rowIdx = 0;
            for (SBQQ__QuoteLine__c line : periodLines) {
                wrappers.add(new QuoteLineWrapper(line, rowIdx));
                rowIdx++;
                if (line.SBQQ__NetPrice__c != null) {
                    subtotal += line.SBQQ__NetPrice__c;
                }
            }

            grandTotal += subtotal;
            yearGroups.add(new YearGroup(
                'Year ' + yearNum + ' Incremental Subscription Fees',
                wrappers,
                subtotal,
                currencyCode
            ));
            yearNum++;
        }

        grandTotalFormatted = formatCurrency(grandTotal, currencyCode);
    }

    /**
     * @description Loads SBQQ__RelatedContent__c records and their corresponding
     *              ContentVersion metadata for the optional appendix section.
     */
    private void loadRelatedDocs(String quoteId) {
        List<SBQQ__RelatedContent__c> rcs = [
            SELECT Id, Name, Document_Type__c, SBQQ__ExternalId__c
            FROM   SBQQ__RelatedContent__c
            WHERE  SBQQ__Quote__c        = :quoteId
            AND    Document_Type__c     != 'Conga Generated OSA'
            WITH   SECURITY_ENFORCED
            ORDER BY Name ASC
        ];

        relatedDocs    = new List<RelatedDocWrapper>();
        hasRelatedDocs = !rcs.isEmpty();

        if (rcs.isEmpty()) return;

        // Bulk-fetch latest ContentVersion for each referenced document
        Set<String> docIds = new Set<String>();
        for (SBQQ__RelatedContent__c rc : rcs) {
            if (String.isNotBlank(rc.SBQQ__ExternalId__c)) docIds.add(rc.SBQQ__ExternalId__c);
        }

        Map<String, ContentVersion> cvByDocId = new Map<String, ContentVersion>();
        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, ContentSize, FileType, FileExtension
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :docIds
                AND    IsLatest = true
                WITH   SECURITY_ENFORCED
            ]) {
                cvByDocId.put(cv.ContentDocumentId, cv);
            }
        }

        for (SBQQ__RelatedContent__c rc : rcs) {
            relatedDocs.add(new RelatedDocWrapper(rc, cvByDocId.get(rc.SBQQ__ExternalId__c)));
        }
    }

    /**
     * @description Loads the cover-page HTML chunks from the SBQQ Quote Template
     *              named "OSA First Page". Sections are returned in display order
     *              and skipped when their SBQQ__ConditionalPrintField__c points at
     *              a Quote checkbox that is false (mirrors SBQQ's own gating, e.g.
     *              Software Delivery only prints when Include_Software_Delivery__c).
     */
    private void loadCoverPage(String quoteId) {
        coverHtmlBlocks = new List<String>();
        hasCoverPage    = false;

        List<SBQQ__TemplateSection__c> sections = [
            SELECT SBQQ__DisplayOrder__c,
                   SBQQ__ConditionalPrintField__c,
                   SBQQ__Content__r.SBQQ__RawMarkup__c
            FROM   SBQQ__TemplateSection__c
            WHERE  SBQQ__Template__r.Name = :COVER_TEMPLATE_NAME
            WITH   SECURITY_ENFORCED
            ORDER BY SBQQ__DisplayOrder__c ASC
        ];
        if (sections.isEmpty()) return;

        // Resolve every conditional field once via dynamic SObject access so future
        // conditional sections work without controller changes.
        Set<String> condFields = new Set<String>();
        for (SBQQ__TemplateSection__c s : sections) {
            if (String.isNotBlank(s.SBQQ__ConditionalPrintField__c)) {
                condFields.add(s.SBQQ__ConditionalPrintField__c);
            }
        }

        Map<String, Object> quoteFlagValues = new Map<String, Object>();
        if (!condFields.isEmpty()) {
            String soql = 'SELECT '
                + String.join(new List<String>(condFields), ', ')
                + ' FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1';
            List<SBQQ__Quote__c> qs = Database.query(soql);
            if (!qs.isEmpty()) {
                for (String f : condFields) {
                    quoteFlagValues.put(f, qs[0].get(f));
                }
            }
        }

        for (SBQQ__TemplateSection__c s : sections) {
            String cond = s.SBQQ__ConditionalPrintField__c;
            if (String.isNotBlank(cond)) {
                Object val = quoteFlagValues.get(cond);
                if (val == null || !(Boolean)val) continue;
            }
            String html = s.SBQQ__Content__r?.SBQQ__RawMarkup__c;
            if (String.isNotBlank(html)) coverHtmlBlocks.add(html);
        }

        // Resolve {!quote.<field>} merge tokens. SBQQ does this server-side when
        // it renders ViewDocument; Flying Saucer doesn't, so tokens would otherwise
        // print as literal text in the PDF.
        coverHtmlBlocks = resolveQuoteTokens(coverHtmlBlocks, quoteId);

        hasCoverPage = !coverHtmlBlocks.isEmpty();
    }

    /**
     * @description Replaces every "{!quote.<FieldApiName>}" token in the given HTML
     *              blocks with the corresponding value from the Quote. Discovered
     *              field names are queried via dynamic SOQL so new tokens added to
     *              the SBQQ template work without code changes.
     */
    private List<String> resolveQuoteTokens(List<String> blocks, String quoteId) {
        if (blocks == null || blocks.isEmpty()) return blocks;

        Set<String> fieldNames = new Set<String>();
        for (String b : blocks) {
            Matcher m = QUOTE_TOKEN_PATTERN.matcher(b);
            while (m.find()) fieldNames.add(m.group(1));
        }
        if (fieldNames.isEmpty()) return blocks;

        String soql = 'SELECT ' + String.join(new List<String>(fieldNames), ', ')
            + ' FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1';
        List<SBQQ__Quote__c> qs = Database.query(soql);
        if (qs.isEmpty()) return blocks;
        SBQQ__Quote__c q = qs[0];

        Map<String, String> tokenValues = new Map<String, String>();
        for (String f : fieldNames) {
            Object v = q.get(f);
            String s = (v == null) ? '' : String.valueOf(v);
            tokenValues.put(f, s.escapeHtml4());
        }

        List<String> resolved = new List<String>();
        for (String b : blocks) {
            String text = b;
            for (String f : fieldNames) {
                text = text.replace('{!quote.' + f + '}', tokenValues.get(f));
            }
            // Flying Saucer interprets CSS px at ~0.75pt; SBQQ's renderer treats the
            // template's inline px values closer to pt, so swap the unit to keep the
            // Instant PDF's text sizes consistent with the SBQQ ViewDocument output.
            text = text.replaceAll('(?i)(font-size\\s*:\\s*\\d+)px', '$1pt');
            resolved.add(text);
        }
        return resolved;
    }

    // ─── Formatting helpers ───────────────────────────────────────────────────

    /**
     * @description Formats a Date as "dd-MMM-yy" (e.g. "19-Jun-26"),
     *              matching the Conga Composer template convention.
     */
    @TestVisible
    private static String formatDate(Date d) {
        if (d == null) return '';
        // DateTime.newInstance gives us access to format(pattern)
        return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0))
                       .format('dd-MMM-yy');
    }

    /**
     * @description Formats a Decimal as a currency string, e.g. "$1,234.56".
     *              Prefix is "$" for USD and omitted for other currencies
     *              (ISO code is appended instead).
     */
    @TestVisible
    private static String formatCurrency(Decimal amount, String isoCode) {
        if (amount == null) amount = 0;
        String formatted = amount.setScale(2).toPlainString();
        // Insert thousand-separator manually (Flying Saucer strips MessageFormat)
        List<String> parts = formatted.split('\\.');
        String intPart   = parts[0];
        String decPart   = parts.size() > 1 ? parts[1] : '00';
        String negative  = intPart.startsWith('-') ? '-' : '';
        String digits    = intPart.replace('-', '');
        String withComma = '';
        Integer len = digits.length();
        for (Integer i = 0; i < len; i++) {
            if (i > 0 && Math.mod(len - i, 3) == 0) withComma += ',';
            withComma += digits.substring(i, i + 1);
        }
        String numStr = negative + withComma + '.' + decPart;
        return (isoCode == 'USD' ? '$' : isoCode + ' ') + numStr;
    }

    // ─── Inner Classes ────────────────────────────────────────────────────────

    /**
     * @description Represents one contract-year group of quote lines.
     *              Exposes the label ("Year 1 Incremental Subscription Fees"),
     *              the lines for that period, and a formatted subtotal.
     */
    public class YearGroup {
        /** Display label for the subtotal row, e.g. "Year 2 Incremental Subscription Fees". */
        public String              label             { get; private set; }
        /** Wrapped quote lines belonging to this period. */
        public List<QuoteLineWrapper> lines          { get; private set; }
        /** Formatted subtotal string, e.g. "$1,281.72". */
        public String              subtotalFormatted { get; private set; }
        /** Raw subtotal Decimal (used in grand total calculation). */
        public Decimal             subtotal          { get; private set; }

        public YearGroup(String lbl, List<QuoteLineWrapper> wrappers,
                         Decimal sub, String isoCode) {
            label             = lbl;
            lines             = wrappers;
            subtotal          = sub;
            subtotalFormatted = formatCurrency(sub, isoCode);
        }
    }

    /**
     * @description Wraps a SBQQ__QuoteLine__c for VF expression-language compatibility.
     *              Exposes Boolean helpers because VF cannot reliably do != null on
     *              Decimal or Date fields inline.
     */
    public class QuoteLineWrapper {
        public String  productCode         { get; private set; }
        public String  productName         { get; private set; }
        public String  supportLevel        { get; private set; }
        public String  startDateFormatted  { get; private set; }
        public String  endDateFormatted    { get; private set; }
        public Decimal quantity            { get; private set; }
        /** Unit of measure label, e.g. "Lawyers" — displayed after the quantity number. */
        public String  quantityUnit        { get; private set; }

        /** Alternating row shade class: "even" or "odd". */
        public String  rowCssClass         { get; private set; }

        /** VF rendered= guards. */
        public Boolean hasProductCode   { get; private set; }
        public Boolean hasSupportLevel  { get; private set; }
        public Boolean hasStartDate     { get; private set; }
        public Boolean hasEndDate       { get; private set; }
        public Boolean hasQuantityUnit  { get; private set; }

        /**
         * @param line  Raw SObject record to wrap.
         * @param index Zero-based row index for alternating row CSS.
         */
        public QuoteLineWrapper(SBQQ__QuoteLine__c line, Integer index) {
            productCode  = line.SBQQ__ProductCode__c  ?? '';
            productName  = line.SBQQ__ProductName__c  ?? '';
            supportLevel = line.Support_Level__c       ?? '';
            quantity     = line.SBQQ__Quantity__c ?? 0;
            quantityUnit = line.License_Basis__c  ?? '';

            startDateFormatted = line.SBQQ__StartDate__c != null
                ? formatDate(line.SBQQ__StartDate__c) : '';
            endDateFormatted   = line.SBQQ__EndDate__c   != null
                ? formatDate(line.SBQQ__EndDate__c)   : '';

            rowCssClass     = Math.mod(index, 2) == 0 ? 'even' : 'odd';
            hasProductCode  = String.isNotBlank(productCode);
            hasSupportLevel = String.isNotBlank(supportLevel);
            hasStartDate    = String.isNotBlank(startDateFormatted);
            hasEndDate      = String.isNotBlank(endDateFormatted);
            hasQuantityUnit = String.isNotBlank(quantityUnit);
        }
    }

    /**
     * @description Wraps a SBQQ__RelatedContent__c + its ContentVersion
     *              for display in the optional PDF appendix.
     */
    public class RelatedDocWrapper {
        public String  name         { get; private set; }
        public String  documentType { get; private set; }
        public String  versionId    { get; private set; }
        public String  fileType     { get; private set; }
        public Long    fileSizeKb   { get; private set; }

        public RelatedDocWrapper(SBQQ__RelatedContent__c rc, ContentVersion cv) {
            name         = rc.Name;
            documentType = rc.Document_Type__c ?? '';
            if (cv != null) {
                versionId  = cv.Id;
                fileType   = cv.FileType ?? cv.FileExtension ?? '';
                fileSizeKb = cv.ContentSize != null ? (Long)(cv.ContentSize / 1024) : 0L;
            } else {
                versionId  = '';
                fileType   = '';
                fileSizeKb = 0L;
            }
        }
    }
}