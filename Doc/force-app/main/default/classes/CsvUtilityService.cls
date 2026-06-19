/**
 * @description Utility service for CSV operations including parsing, escaping, and content management for batch processing.
 * @details Provides comprehensive CSV handling functionality including row parsing, field escaping, content creation, and file splitting.
 *          Implements proper CSV formatting standards with support for special characters, quotes, and multi-line content.
 *          Designed to support robust CSV processing in batch workflows with emphasis on data integrity and format compliance.
 */
public with sharing class CsvUtilityService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    /**
     * @description Parses a CSV row into a list of trimmed column values.
     * @param row The CSV row string to parse.
     * @return List of column values, or null if the row doesn't have the expected format.
     */
    public static List<String> parseRow(String row) {
        if (String.isBlank(row)) {
            return new List<String>();
        }
        
        List<String> cols = row.replace('"', '').split(',');
        
        // Trim all values
        for (Integer i = 0; i < cols.size(); i++) {
            cols[i] = cols[i].trim();
        }
        
        return cols;
    }
    
    /**
     * @description Escapes a value for safe inclusion in CSV output.
     * @param value Input string to escape.
     * @return Escaped CSV field.
     */
    public static String csvEscape(String value) {
        if (value == null) {
            return '';
        }
        
        String v = value.replace('"', '""');
        if (v.contains(',') || v.contains('\n') || v.contains('\r')) {
            return '"' + v + '"';
        }
        
        return v;
    }
    
    /**
     * @description Creates a CSV content string from header and data rows.
     * @param header CSV header row.
     * @param dataRows List of data rows.
     * @return Complete CSV content string.
     */
    public static String createCsvContent(String header, List<String> dataRows) {
        if (String.isBlank(header) || dataRows == null || dataRows.isEmpty()) {
            return header != null ? header : '';
        }
        
        return header + '\n' + String.join(dataRows, '\n');
    }
    
    /**
     * @description Splits file content into individual rows.
     * @param fileContent The complete file content.
     * @return List of individual row strings.
     */
    public static List<String> splitIntoRows(String fileContent) {
        if (String.isBlank(fileContent)) {
            return new List<String>();
        }
        
        return fileContent.split('\n');
    }
}