/**
 * @description Test class for BatchFileService.
 * @details Tests the creation, retrieval, and summary generation of batch files (ContentVersion).
 * @author Sahal Mohamed
 * @createdDate 2026-01-13
 */
@isTest
public class BatchFileServiceTest {

    /***********************************************************************************************
    *
    * Test Setup
    *
    ***********************************************************************************************/
    
    // No specific @testSetup needed as we create ContentVersion in methods or it's purely utility logic.

    /***********************************************************************************************
    *
    * Unit Tests
    *
    ***********************************************************************************************/

    /**
     * @description Tests the ResultSummaryParams builder pattern.
     */
    @isTest
    static void testResultSummaryParams() {
        Test.startTest();
        BatchFileService.ResultSummaryParams params = new BatchFileService.ResultSummaryParams()
            .withFileType('Successes')
            .withTitle('Test Title')
            .withRowCount(10)
            .withFileUrl('https://example.com/file');
        Test.stopTest();

        System.assertEquals('Successes', params.fileType, 'File Type should match');
        System.assertEquals('Test Title', params.title, 'Title should match');
        System.assertEquals(10, params.rowCount, 'Row Count should match');
        System.assertEquals('https://example.com/file', params.fileUrl, 'File URL should match');
    }

    /**
     * @description Tests creation of a CSV file in Salesforce Files.
     */
    @isTest
    static void testCreateCsvFile() {
        String title = 'TestFile';
        String content = 'col1,col2\nval1,val2';

        Test.startTest();
        String fileUrl = BatchFileService.createCsvFile(title, content);
        Test.stopTest();

        System.assertNotEquals(null, fileUrl, 'File URL should be returned');
        System.assert(fileUrl.contains('/lightning/r/ContentDocument/'), 'URL should contain Lightning ContentDocument path');

        ContentVersion cv = [SELECT Id, Title, VersionData FROM ContentVersion WHERE Title = :title LIMIT 1];
        System.assertNotEquals(null, cv, 'ContentVersion should exist');
        System.assertEquals(title, cv.Title, 'Title should match');
        System.assertEquals(content, cv.VersionData.toString(), 'Content should match');
    }

    /**
     * @description Tests fetching an existing CSV file by title.
     */
    @isTest
    static void testFetchCsvFile() {
        String title = 'FetchTestFile';
        String content = 'data';
        createTestContentVersion(title, content);

        Test.startTest();
        ContentVersion fetchedCv = BatchFileService.fetchCsvFile(title);
        Test.stopTest();

        System.assertNotEquals(null, fetchedCv, 'Should return ContentVersion');
        System.assertEquals(title, fetchedCv.ContentDocument.Title, 'Title should match');
    }

    /**
     * @description Tests fetching a non-existent CSV file.
     */
    @isTest
    static void testFetchCsvFileNonExistent() {
        Test.startTest();
        ContentVersion fetchedCv = BatchFileService.fetchCsvFile('NonExistentFile');
        Test.stopTest();

        System.assertEquals(null, fetchedCv, 'Should return null for non-existent file');
    }

    /**
     * @description Tests creating a result summary string.
     */
    @isTest
    static void testCreateResultSummary() {
        String fileType = 'Errors';
        String title = 'ErrorLog';
        Integer rowCount = 5;
        String url = 'http://test.url';

        Test.startTest();
        String summary = BatchFileService.createResultSummary(fileType, title, rowCount, url);
        Test.stopTest();

        String expected = fileType + ': ' + title + ' (rows: ' + rowCount + ')\n' + url;
        System.assertEquals(expected, summary, 'Summary string format should match');
    }

    /***********************************************************************************************
    *
    * Helper Methods
    *
    ***********************************************************************************************/

    /**
     * @description Creates a ContentVersion for testing purposes.
     * @param title Title of the file.
     * @param content Content of the file.
     */
    private static void createTestContentVersion(String title, String content) {
        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = title + '.csv';
        cv.VersionData = Blob.valueOf(content);
        insert cv;
    }
}