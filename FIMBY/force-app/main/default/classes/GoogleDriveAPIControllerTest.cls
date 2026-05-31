@IsTest
private class GoogleDriveAPIControllerTest {

    private static Id createTestContentVersion() {
        // Create and insert a ContentVersion record
        // Note: Adjust fields as necessary for your org's schema
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.jpg',
            VersionData = Blob.valueOf('Test data'),
            IsMajorVersion = true
        );
        insert cv;
        
        // Query for the inserted ContentVersion to get the ContentDocumentId
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        return cv.ContentDocumentId;
    }




    // Mock class to generate different HTTP responses based on the request
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private Boolean throwError = false;
        private Boolean httpFailure = false;

        public MockHttpResponseGenerator(Boolean throwError, Boolean httpFailure) {
            this.throwError = throwError;
            this.httpFailure = httpFailure;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            
            if (throwError) {
                throw new System.CalloutException('Mock exception');
            }
            
            if (httpFailure) {
                res.setStatusCode(400);
                res.setBody('{"error": "Bad Request"}');
                return res;
            }

            if (req.getEndpoint().contains('DriveGet')) {
                // Simulate metadata retrieval response
                res.setStatusCode(200);
                res.setBody('{"imageMediaMetadata": {"width": 1024, "height": 768}}');
            } else {
                // Simulate file upload response
                res.setStatusCode(200);
                res.setBody('{"id": "12345"}');
            }
            return res;
        }
    }
    
    // Helper method to create necessary test data, like ContentVersion records
    private static void createTestData() {
        // Implement test data creation, ensuring you have ContentVersion records and associated ContentDocument records
    }

    @IsTest
    public static void testSuccessfulUpload() {
        createTestData();
        Id testContentDocumentId = createTestContentVersion();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false, false));
        
        Test.startTest();
        List<List<ID>> files = new List<List<ID>>{new List<ID>{testContentDocumentId}};
        List<GoogleDriveAPIController.ResponseWrapper> result = GoogleDriveAPIController.storeFiletoDrive(files);
        Test.stopTest();
        
        System.assertEquals(true, result[0].isSuccess, 'Upload should succeed.');
        System.assertNotEquals(null, result[0].viewUrl, 'View URL should be populated.');
    }

    @IsTest
    public static void testUploadFailure() {
        createTestData();
        Id testContentDocumentId = createTestContentVersion();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false, true));
        
        Test.startTest();
        List<List<ID>> files = new List<List<ID>>{new List<ID>{testContentDocumentId}};
        List<GoogleDriveAPIController.ResponseWrapper> result = GoogleDriveAPIController.storeFiletoDrive(files);
        Test.stopTest();
        
        System.assert(result[0].isSuccess == false, 'Upload should fail.');
        System.assert(result[0].response.contains('Error :'), 'Error message should be populated.');
    }

    @IsTest
    public static void testExceptionHandling() {
        createTestData();
        Id testContentDocumentId = createTestContentVersion();
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(true, false));
        
        Test.startTest();
        List<List<ID>> files = new List<List<ID>>{new List<ID>{testContentDocumentId}};
        List<GoogleDriveAPIController.ResponseWrapper> result = GoogleDriveAPIController.storeFiletoDrive(files);
        Test.stopTest();
        
        System.assert(!result[0].isSuccess, 'Upload should fail on exception.');
        System.assert(result[0].response.contains('Error :'), 'Exception message should be captured.');
    }


    @IsTest
    public static void testNoFileSelected() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false, false));
        
        Test.startTest();
        List<List<ID>> files = new List<List<ID>>();
        List<GoogleDriveAPIController.ResponseWrapper> result = GoogleDriveAPIController.storeFiletoDrive(files);
        Test.stopTest();
        
        System.assertEquals(false, result[0].isSuccess, 'No file selected scenario should be handled.');
        System.assertEquals('Please select file.', result[0].response, 'Appropriate message should be returned.');
    }

    // Additional tests can be implemented here to cover more scenarios
}