@IsTest
private class FetchAndReplaceImageFromGDriveTest {

    private class GoogleDriveMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            if(req.getEndpoint().contains('?fields=mimeType,name')) {
                // Metadata request mock response
                res.setStatusCode(200);
                res.setBody('{"mimeType": "image/jpeg", "name": "testImage.jpg"}');
            } else {
                // File content request mock response
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('Test Image Content'));
            }
            return res;
        }
    }

    private static String createRelatedRecord() {
        // Replace Account with your desired related record type
        Account acc = new Account(Name='Test Account');
        insert acc;
        return acc.Id;
    }

    @IsTest
    public static void testFetchAndUploadImage() {
        // Setup mock callout
        Test.setMock(HttpCalloutMock.class, new GoogleDriveMock());

        // Create related record
        String relatedRecordId = createRelatedRecord();

        // Setup test data
        FetchAndReplaceImageFromGDrive.Request req = new FetchAndReplaceImageFromGDrive.Request();
        req.googleDriveURL = 'mockFileId';
        req.FileName = 'Test Image';
        req.RelatedRecordID = relatedRecordId;
        req.PhotoNumber = '1';

        // Test method
        Test.startTest();
        List<FetchAndReplaceImageFromGDrive.Response> responses = FetchAndReplaceImageFromGDrive.fetchAndUploadImage(new List<FetchAndReplaceImageFromGDrive.Request>{req});
        Test.stopTest();

        // Verify results
        System.assert(!responses.isEmpty(), 'Should have a response.');
        FetchAndReplaceImageFromGDrive.Response response = responses[0];
        System.assertNotEquals(null, response.salesforceFileURL, 'Salesforce File URL should not be null.');

        // Verify records creation
        List<ContentVersion> cvs = [SELECT Id, Title FROM ContentVersion WHERE Title = 'Test Image'];
        System.assertEquals(1, cvs.size(), 'ContentVersion record should be created.');

        List<ContentDistribution> cds = [SELECT Id, Name FROM ContentDistribution WHERE Name = 'Test Image'];
        System.assertEquals(1, cds.size(), 'ContentDistribution record should be created.');
    }
}