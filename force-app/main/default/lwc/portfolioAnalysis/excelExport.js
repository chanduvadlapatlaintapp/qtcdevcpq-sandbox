/**
 * @description Excel export module for the Portfolio Analysis LWC. Generates a styled
 *              .xlsx workbook with account metadata header, Cloud/On-Prem summary,
 *              grouped subscription rows (alternating colors per OSA), invoice columns,
 *              and a grand total row. Supports internal and client-facing modes
 *              (client view hides bundled pricing). Uses xlsx-js-style for formatting.
 * @author      Vignesh Prabhudoss
 * @date        Mar-02-2026
 * @jira        BIZ-80262
 */

// ── Helpers ──────────────────────────────────────────────────

/**
 * @description Formats an ISO date string as a US-locale short date (M/D/YYYY).
 * @param {string} dateStr - ISO date string.
 * @returns {string} Formatted date or empty string.
 */
function fmtDate(dateStr) {
    if (!dateStr) return '';
    return new Date(dateStr).toLocaleDateString('en-US', { month: 'numeric', day: 'numeric', year: 'numeric' });
}

/**
 * @description Calculates the number of calendar days between two date strings.
 * @param {string} startStr - Start date (ISO).
 * @param {string} endStr   - End date (ISO).
 * @returns {number|null} Day count or null.
 */
function daysBetween(startStr, endStr) {
    if (!startStr || !endStr) return null;
    const diff = new Date(endStr) - new Date(startStr);
    return Math.round(diff / (1000 * 60 * 60 * 24));
}

/**
 * @description Rounds a number to two decimal places.
 * @param {number} val - Value to round.
 * @returns {number|null} Rounded value or null.
 */
function round2(val) {
    if (val == null || isNaN(val)) return null;
    return Math.round(val * 100) / 100;
}

// ── Style Definitions ────────────────────────────────────────

const COLORS = {
    navyDark: '003C80',
    navyMid: '0E54A9',
    headerBg: '003C80',
    sectionBg: '003C80',
    metaLabelBg: 'D5E6FB',
    metaValueBg: 'EBF4FE',
    altRowBg: 'F4F7FA',
    white: 'FFFFFF',
    black: '073C7D',
    darkText: '003C80',
    lightBorder: 'A4B9D7',
    greenAccent: '548235',
    greenBg: 'E2EFDA'
};

const FONT = {
    title: { bold: true, sz: 16, color: { rgb: COLORS.white }, name: 'Calibri' },
    subtitle: { bold: false, sz: 10, italic: true, color: { rgb: COLORS.white }, name: 'Calibri' },
    metaLabel: { bold: true, sz: 10, color: { rgb: COLORS.darkText }, name: 'Calibri' },
    metaValue: { bold: false, sz: 10, color: { rgb: COLORS.black }, name: 'Calibri' },
    colHeader: { bold: true, sz: 9, color: { rgb: COLORS.white }, name: 'Calibri' },
    data: { bold: false, sz: 9, color: { rgb: COLORS.black }, name: 'Calibri' },
    summaryLabel: { bold: true, sz: 10, color: { rgb: COLORS.darkText }, name: 'Calibri' },
    summaryValue: { bold: true, sz: 10, color: { rgb: COLORS.greenAccent }, name: 'Calibri' }
};

const BORDER_THIN = {
    top: { style: 'thin', color: { rgb: COLORS.lightBorder } },
    bottom: { style: 'thin', color: { rgb: COLORS.lightBorder } },
    left: { style: 'thin', color: { rgb: COLORS.lightBorder } },
    right: { style: 'thin', color: { rgb: COLORS.lightBorder } }
};

const NUM_FMT_CURRENCY = '#,##0.00';
const NUM_FMT_INTEGER = '#,##0';

// ── Cell helpers ─────────────────────────────────────────────

/**
 * @description Writes a styled cell to the worksheet at the given row/column.
 * @param {Object} XLSX   - xlsx-js-style library reference.
 * @param {Object} ws     - Worksheet object.
 * @param {number} row    - Zero-based row index.
 * @param {number} col    - Zero-based column index.
 * @param {*}      value  - Cell value (string, number, or null).
 * @param {Object} style  - Cell style object (font, fill, border, alignment).
 * @param {string} numFmt - Optional Excel number format string.
 */
function setCellStyle(XLSX, ws, row, col, value, style, numFmt) {
    const addr = XLSX.utils.encode_cell({ r: row, c: col });
    const cell = { v: value, s: style };
    if (value == null || value === '') {
        cell.v = '';
        cell.t = 's';
    } else if (typeof value === 'number') {
        cell.t = 'n';
        if (numFmt) cell.z = numFmt;
    } else {
        cell.t = 's';
    }
    ws[addr] = cell;
}

// ── Main export function ─────────────────────────────────────

/**
 * @description Generates and downloads a styled Excel workbook for a portfolio analysis.
 *              Builds a single "Current Term" sheet with metadata header, Cloud/On-Prem
 *              totals, column headers with auto-filter, alternating-color data rows
 *              grouped by OSA, and a grand total row.
 * @param {Object}  XLSX           - xlsx-js-style library reference.
 * @param {Object}  account        - Selected account ({id, name}).
 * @param {Array}   subscriptions  - SBQQ__Subscription__c records.
 * @param {boolean} clientFacing   - True to hide internal-only columns and bundled pricing.
 * @param {string}  currency       - Dominant ISO currency code.
 * @param {Object}  accountDetails - Account metadata fields.
 * @param {Object}  invoiceMap     - Invoice lookup map keyed by osa|startDate|endDate.
 */
export function exportPortfolioExcel(XLSX, account, subscriptions, clientFacing, currency, accountDetails, invoiceMap = {}) {
    const wb = XLSX.utils.book_new();

    // Column headers
    const baseHeaders = [
        'OSA', 'Uplift Cap?', 'Contract (OSA) #', 'Bundle', 'Invoice #', 'Payment Status',
        'Deployment Model', 'Currency', 'Meter Type', 'Band / Quantity',
        'Product Line', 'Invoice Item (Product(s))', 'Term # of Months in Term',
        'Support Level', 'Contract Value', 'Sales Price / Month'
    ];
    const internalHeaders = clientFacing ? [] : ['Invoice Total', 'ACV'];
    const remainingHeaders = [
        'Start Date', 'End Date', '# of Days', 'Per Day', 'Status',
        'SFA'
    ];
    const allHeaders = [...baseHeaders, ...internalHeaders, ...remainingHeaders];
    const numCols = allHeaders.length;

    // Numeric column sets
    const currencyCols = new Set([
        'Contract Value', 'Sales Price / Month', 'Invoice Total',
        'ACV', 'Per Day',
        'New Annual Amount', 'Upgrade Cost from Current Investment', 'New Annual Amount with Upgrade'
    ]);
    const integerCols = new Set(['Band / Quantity', '# of Days', 'Term # of Months in Term']);

    // Cloud/On-Prem totals
    let cloudTotal = 0;
    let onPremTotal = 0;
    subscriptions.forEach(s => {
        const rev = (s.SBQQ__NetPrice__c || 0) * (s.SBQQ__SegmentQuantity__c || 0);
        const deploy = s.SBQQ__Product__r?.Deployment__c || '';
        if (deploy === 'Cloud') cloudTotal += rev;
        else onPremTotal += rev;
    });

    // Group by OSA
    const groupedData = {};
    subscriptions.forEach(s => {
        const osa = s.SBQQ__Contract__r?.OSA_Number__c || '\u2014';
        if (!groupedData[osa]) groupedData[osa] = [];
        groupedData[osa].push(s);
    });

    // Build data rows
    const dataRows = [];
    const rowOsaGroupIndex = [];
    let osaGroupIdx = 0;

    Object.entries(groupedData)
        .sort((a, b) => a[0].localeCompare(b[0]))
        .forEach(([osa, subs]) => {
            subs.forEach(s => {
                const net = s.SBQQ__NetPrice__c || 0;
                const qty = s.SBQQ__SegmentQuantity__c || 0;
                const contractValue = net * qty;
                const segMonths = s.Segment_Months__c || 0;
                const salePriceMonth = segMonths > 0 ? net / segMonths : null;
                const days = daysBetween(s.SBQQ__SegmentStartDate__c, s.SBQQ__SegmentEndDate__c);
                const perDay = days && days > 0 ? contractValue / days : null;
                const ann = segMonths > 0 ? (net / segMonths) * qty * 12 : null;
                const acv = segMonths > 0 ? (net / segMonths) * 12 * qty : 0;
                const cpi = s.SBQQ__Contract__r?.CPI__c;
                const bundle = s.SBQQ__Contract__r?.Hide_Pricing__c;
                const hidePricing = clientFacing && bundle;

                // Invoice matching: first by composite key (header), then by product code + quantity (line)
                const segStart = s.SBQQ__SegmentStartDate__c || '';
                const segEnd = s.SBQQ__SegmentEndDate__c || '';
                const invoiceKey = `${osa}|${segStart}|${segEnd}`;
                const matchedLines = invoiceMap[invoiceKey] || [];

                const productCode = s.SBQQ__Product__r?.ProductCode || '';
                const matchedLine = matchedLines.find(line => {
                    if (!line.itemCode) return false;
                    return line.itemCode === productCode &&
                           Math.abs(Number(line.lineQuantity)) === Math.abs(qty);
                });
                const invoice = matchedLine || (matchedLines.length > 0 ? matchedLines[0] : null);

                const baseRow = [
                    osa,
                    cpi != null ? (typeof cpi === 'boolean' ? (cpi ? 'Yes' : 'No') : String(cpi)) : '',
                    s.SBQQ__ContractNumber__c || '',
                    bundle != null ? (typeof bundle === 'boolean' ? (bundle ? 'Yes' : 'No') : String(bundle)) : '',
                    invoice ? invoice.invoiceNumber : '',
                    invoice ? invoice.paymentStatus : '',
                    s.SBQQ__Product__r?.Deployment__c || '',
                    s.CurrencyIsoCode || 'USD',
                    s.Per_Integrations__c || '',
                    qty,
                    s.SBQQ__Product__r?.ProductCode || '',
                    s.SBQQ__Product__r?.Name || s.Name || '',
                    segMonths || '',
                    s.Support_Level__c || '',
                    hidePricing ? '' : round2(contractValue),
                    hidePricing ? '' : round2(salePriceMonth)
                ];
                const invoiceTotal = matchedLine ? Math.abs(matchedLine.lineAmount) : null;
                const internalRow = clientFacing ? [] : [round2(invoiceTotal), round2(acv)];
                const remainingRow = [
                    fmtDate(s.SBQQ__SegmentStartDate__c),
                    fmtDate(s.SBQQ__SegmentEndDate__c),
                    days,
                    round2(perDay),
                    s.Contract_Status__c || '',
                    s.SBQQ__Contract__r?.SBQQ__RenewalUpliftRate__c != null ? s.SBQQ__Contract__r.SBQQ__RenewalUpliftRate__c + '%' : ''
                ];
                dataRows.push([...baseRow, ...internalRow, ...remainingRow]);
                rowOsaGroupIndex.push(osaGroupIdx);
            });
            osaGroupIdx++;
        });

    // ── Build worksheet ──
    const metaFields = [
        { label: 'GTM Tier', value: accountDetails?.GTM_Motion_Tier__c || '' },
        { label: 'Client Since', value: accountDetails?.Customer_Since__c || '' },
        { label: 'MSSA #', value: accountDetails?.Master_Terms_Contract_Number__r?.ContractNumber || '' },
        { label: 'MSSA Version #', value: accountDetails?.Contract_Term_Version__c || '' },
        { label: 'MSSA Uplift Cap?', value: accountDetails?.Master_Terms_CPI__c || '' },
        { label: 'Cloud Addendum #', value: accountDetails?.Cloud_Addendum__r?.ContractNumber || 'No' }
    ];
    const metaStartRow = 3;
    const summaryRow1 = metaStartRow + metaFields.length + 1;
    const summaryRow2 = summaryRow1 + 1;
    const colHeaderRow = summaryRow2 + 2;
    const dataStartRow = colHeaderRow + 1;
    const lastDataRow = dataStartRow + dataRows.length - 1;

    const ws = {};
    const range = { s: { r: 0, c: 0 }, e: { r: lastDataRow, c: numCols - 1 } };
    ws['!ref'] = XLSX.utils.encode_range(range);

    // Row 0: Title
    const titleStyle = {
        font: FONT.title,
        fill: { fgColor: { rgb: COLORS.sectionBg } },
        alignment: { horizontal: 'left', vertical: 'center' }
    };
    setCellStyle(XLSX, ws, 0, 0, 'Portfolio Analysis \u2014 ' + account.name, titleStyle);
    for (let c = 1; c < numCols; c++) setCellStyle(XLSX, ws, 0, c, '', titleStyle);

    // Row 1: Date
    const dateStyle = {
        font: FONT.subtitle,
        fill: { fgColor: { rgb: COLORS.navyMid } },
        alignment: { horizontal: 'left', vertical: 'center' }
    };
    const dateStr = 'Generated: ' + new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    setCellStyle(XLSX, ws, 1, 0, dateStr, dateStyle);
    for (let c = 1; c < numCols; c++) setCellStyle(XLSX, ws, 1, c, '', dateStyle);

    // Row 2: blank
    for (let c = 0; c < numCols; c++) setCellStyle(XLSX, ws, 2, c, '', {});

    // Metadata rows
    const metaLabelStyle = {
        font: FONT.metaLabel, fill: { fgColor: { rgb: COLORS.metaLabelBg } },
        border: BORDER_THIN, alignment: { horizontal: 'right', vertical: 'center' }
    };
    const metaValueStyle = {
        font: FONT.metaValue, fill: { fgColor: { rgb: COLORS.metaValueBg } },
        border: BORDER_THIN, alignment: { horizontal: 'left', vertical: 'center' }
    };
    metaFields.forEach((field, i) => {
        const r = metaStartRow + i;
        setCellStyle(XLSX, ws, r, 0, field.label, metaLabelStyle);
        setCellStyle(XLSX, ws, r, 1, field.value, metaValueStyle);
        for (let c = 2; c < numCols; c++) setCellStyle(XLSX, ws, r, c, '', {});
    });

    // Blank after metadata
    const blankAfterMeta = metaStartRow + metaFields.length;
    for (let c = 0; c < numCols; c++) setCellStyle(XLSX, ws, blankAfterMeta, c, '', {});

    // Summary rows
    const summaryLabelStyle = {
        font: FONT.summaryLabel, fill: { fgColor: { rgb: COLORS.greenBg } },
        border: BORDER_THIN, alignment: { horizontal: 'right', vertical: 'center' }
    };
    const summaryValueStyle = {
        font: FONT.summaryValue, fill: { fgColor: { rgb: COLORS.greenBg } },
        border: BORDER_THIN, alignment: { horizontal: 'left', vertical: 'center' }
    };
    setCellStyle(XLSX, ws, summaryRow1, 0, 'Cloud Total', summaryLabelStyle);
    setCellStyle(XLSX, ws, summaryRow1, 1, round2(cloudTotal), summaryValueStyle);
    if (typeof round2(cloudTotal) === 'number') {
        ws[XLSX.utils.encode_cell({ r: summaryRow1, c: 1 })].z = NUM_FMT_CURRENCY;
    }
    for (let c = 2; c < numCols; c++) setCellStyle(XLSX, ws, summaryRow1, c, '', {});

    setCellStyle(XLSX, ws, summaryRow2, 0, 'On Premise Total', summaryLabelStyle);
    setCellStyle(XLSX, ws, summaryRow2, 1, round2(onPremTotal), summaryValueStyle);
    if (typeof round2(onPremTotal) === 'number') {
        ws[XLSX.utils.encode_cell({ r: summaryRow2, c: 1 })].z = NUM_FMT_CURRENCY;
    }
    for (let c = 2; c < numCols; c++) setCellStyle(XLSX, ws, summaryRow2, c, '', {});

    // Blank before headers
    for (let c = 0; c < numCols; c++) setCellStyle(XLSX, ws, colHeaderRow - 1, c, '', {});

    // Column headers
    const colHeaderStyle = {
        font: FONT.colHeader, fill: { fgColor: { rgb: COLORS.headerBg } },
        border: BORDER_THIN, alignment: { horizontal: 'center', vertical: 'center', wrapText: true }
    };
    allHeaders.forEach((h, c) => setCellStyle(XLSX, ws, colHeaderRow, c, h, colHeaderStyle));

    // Data rows — alternate fill color per OSA group for readability
    dataRows.forEach((row, ri) => {
        const isEvenGroup = rowOsaGroupIndex[ri] % 2 === 0;
        const fillColor = isEvenGroup ? COLORS.altRowBg : COLORS.white;
        const rowStyle = {
            font: FONT.data, fill: { fgColor: { rgb: fillColor } },
            border: BORDER_THIN, alignment: { vertical: 'center' }
        };
        row.forEach((val, ci) => {
            const isCurrency = currencyCols.has(allHeaders[ci]);
            const isInteger = integerCols.has(allHeaders[ci]);
            const align = (isCurrency || isInteger) ? 'right' : 'left';
            const cellStyle = { ...rowStyle, alignment: { ...rowStyle.alignment, horizontal: align } };
            const r = dataStartRow + ri;
            setCellStyle(XLSX, ws, r, ci, val, cellStyle);
            if (val != null && val !== '' && typeof val === 'number') {
                const addr = XLSX.utils.encode_cell({ r, c: ci });
                if (isCurrency) ws[addr].z = NUM_FMT_CURRENCY;
                else if (isInteger) ws[addr].z = NUM_FMT_INTEGER;
            }
        });
    });

    // Column widths
    ws['!cols'] = allHeaders.map(h => {
        if (h.includes('Product') || h.includes('Invoice Item')) return { wch: 35 };
        if (h.includes('Annualized Totals')) return { wch: 24 };
        if (h.includes('Annualized')) return { wch: 18 };
        if (h.includes('Upgrade')) return { wch: 24 };
        if (h.includes('Annual Amount')) return { wch: 20 };
        if (h.includes('Contract Value')) return { wch: 16 };
        if (h.includes('Sales Price')) return { wch: 18 };
        if (h.includes('Support')) return { wch: 14 };
        if (h.includes('Deployment')) return { wch: 16 };
        if (h.includes('Date')) return { wch: 12 };
        if (h.includes('OSA')) return { wch: 16 };
        if (h.includes('Currency')) return { wch: 10 };
        if (h === 'Invoice #') return { wch: 16 };
        if (h === 'Payment Status') return { wch: 16 };
        if (h.includes('Status')) return { wch: 14 };
        return { wch: Math.max(h.length + 2, 10) };
    });

    // Row heights
    ws['!rows'] = [];
    ws['!rows'][0] = { hpt: 30 };
    ws['!rows'][1] = { hpt: 20 };
    ws['!rows'][colHeaderRow] = { hpt: 36 };

    // Merge cells
    ws['!merges'] = [
        { s: { r: 0, c: 0 }, e: { r: 0, c: numCols - 1 } },
        { s: { r: 1, c: 0 }, e: { r: 1, c: numCols - 1 } }
    ];

    // Auto-filter on column header row (row 14)
    ws['!autofilter'] = {
        ref: XLSX.utils.encode_range({ s: { r: colHeaderRow, c: 0 }, e: { r: colHeaderRow, c: numCols - 1 } })
    };

    XLSX.utils.book_append_sheet(wb, ws, 'Current Term');

    // Save
    const safeName = account.name.replace(/[^a-zA-Z0-9]/g, '_');
    const dateStamp = new Date().toISOString().slice(0, 10);
    const suffix = clientFacing ? 'Client' : 'Internal';
    XLSX.writeFile(wb, `Portfolio_Analysis_${safeName}_${suffix}_${dateStamp}.xlsx`);
}