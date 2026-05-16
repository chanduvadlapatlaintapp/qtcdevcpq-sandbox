@isTest
public with sharing class ConvertFilesToAttachmentsTests {
    
    @isTest
    public static void CanConvert () {
        List<ContentDocumentLink> curDocumentLinks = new List<ContentDocumentLink>();
        ConvertFilesToAttachments.Request curRequest = new ConvertFilesToAttachments.Request();
        
        List<ConvertFilesToAttachments.Request> reqList = new List<ConvertFilesToAttachments.Request>();
        reqList.add(curRequest);

        List<ConvertFilesToAttachments.Response> response = ConvertFilesToAttachments.convert(reqList);
        System.assertEquals(response[0].isSuccess,null);

    }
    
    @isTest
    public static void testCanConvert() {
        // Step 1: Create a parent record to attach file to
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Step 2: Create a test file (ContentVersion)
        ContentVersion cv = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Sample content'),
            IsMajorVersion = true
        );
        insert cv;

        // Step 3: Query to get ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // Step 4: Create a ContentDocumentLink to link file to Account
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        // Step 5: Build request for method
        ConvertFilesToAttachments.Request req = new ConvertFilesToAttachments.Request();
        req.curContentDocumentLinks = new List<ContentDocumentLink> { cdl };

        List<ConvertFilesToAttachments.Request> reqList = new List<ConvertFilesToAttachments.Request> { req };

        // Step 6: Call the method
        List<ConvertFilesToAttachments.Response> responses = ConvertFilesToAttachments.convert(reqList);

        // Step 7: Assertions
        System.assertEquals(1, responses.size());
        ConvertFilesToAttachments.Response response = responses[0];

        System.assertEquals(1, response.curAttachments.size(), 'Should create one attachment');
    }
}