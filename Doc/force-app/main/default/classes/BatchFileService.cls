/**
 * @description Service class to handle Salesforce Files (ContentVersion) operations for batch processing.
 * @details Provides centralized file management functionality for creating, retrieving, and managing CSV files in Salesforce Files.
 *          Handles ContentVersion creation, Lightning URL generation, file retrieval by title, and result summary formatting.
 *          Designed to support batch processing workflows that require persistent file storage and user-friendly access links.
 * @author Sahal Mohamed
 */
public with sharing class BatchFileService {
    
    /***********************************************************************************************
    *
    * Public Methods
    *
    ***********************************************************************************************/
    
    /***********************************************************************************************
    *
    * Data Structures
    *
    ***********************************************************************************************/
    
    /**
     * @description Data structure to hold parameters for result summary creation.
     */
    public class ResultSummaryParams {
        public String fileType;
        public String title;
        public Integer rowCount;
        public String fileUrl;
        
        /**
         * @description Sets the file type.
         * @param fileType The type of file being processed.
         * @return The current instance for method chaining.
         */
        public ResultSummaryParams withFileType(String fileType) {
            this.fileType = fileType;
            return this;
        }
        
        /**
         * @description Sets the title.
         * @param title The title of the file.
         * @return The current instance for method chaining.
         */
        public ResultSummaryParams withTitle(String title) {
            this.title = title;
            return this;
        }
        
        /**
         * @description Sets the row count.
         * @param rowCount The number of rows in the file.
         * @return The current instance for method chaining.
         */
        public ResultSummaryParams withRowCount(Integer rowCount) {
            this.rowCount = rowCount;
            return this;
        }
        
        /**
         * @description Sets the file URL.
         * @param fileUrl The Lightning URL to access the file.
         * @return The current instance for method chaining.
         */
        public ResultSummaryParams withFileUrl(String fileUrl) {
            this.fileUrl = fileUrl;
            return this;
        }
    }
    
    /**
     * @description Creates a CSV file in Salesforce Files and returns a Lightning URL to it.
     * @param title The title for the file.
     * @param csvContent The CSV content as a string.
     * @return Lightning URL to access the created file.
     */
    public static String createCsvFile(String title, String csvContent) {
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = title + '.csv';
        cv.VersionData = Blob.valueOf(csvContent);
        insert cv;
        
        ContentVersion fetchedCv = [SELECT ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        String baseUrl = Url.getOrgDomainUrl().toExternalForm();
        String fileUrl = baseUrl + '/lightning/r/ContentDocument/' + fetchedCv.ContentDocumentId + '/view';
        
        Nebula.Logger.info('Created file: ' + fetchedCv.Title);
        return fileUrl;
    }
    
    /**
     * @description Fetches a CSV file from Salesforce Files by title.
     * @param fileName The title of the file to fetch.
     * @return ContentVersion record if found, null otherwise.
     */
    public static ContentVersion fetchCsvFile(String fileName) {
        List<ContentVersion> contentVersionList = [
            SELECT Id, VersionData, ContentDocument.Title 
            FROM ContentVersion 
            WHERE ContentDocument.Title = :fileName 
            ORDER BY createdDate desc 
            LIMIT 1
        ];
        Nebula.Logger.info('Fetched ContentVersion records for fileName=' + fileName + ', count=' + contentVersionList.size());
        
        return contentVersionList.isEmpty() ? null : contentVersionList[0];
    }
    
    /**
     * @description Creates a formatted result summary for file creation.
     * @param fileType The type of file.
     * @param title The title of the file.
     * @param rowCount The number of rows in the file.
     * @param fileUrl The Lightning URL to access the file.
     * @return Formatted summary string.
     */
    public static String createResultSummary(String fileType, String title, Integer rowCount, String fileUrl) {
        return fileType + ': ' + title + ' (rows: ' + rowCount + ')\n' + fileUrl;
    }
}