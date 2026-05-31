global class FetchAndReplaceImageFromGDrive {

    global class Request {
        @InvocableVariable(required=true)
        public String googleDriveURL;

        @InvocableVariable(required=true)
        public String FileName; 
        
        @InvocableVariable(required=true)
        public String RelatedRecordID;
        
        @InvocableVariable(required=true)
        public String PhotoNumber;
    }

    global class Response {
        @InvocableVariable
        public String salesforceFileURL;
    }

    @InvocableMethod(label='Fetch Image from Google Drive and Upload to Salesforce Files' description='Takes a Google Drive URL, downloads the image, and uploads it to Salesforce Files, returning the new Salesforce file URL.')
    public static List<Response> fetchAndUploadImage(List<Request> requests) {
        List<Response> responses = new List<Response>();
        
        // Iterate over each request instead of assuming only one request
        for(Request request : requests) {
            String fileId = request.googleDriveURL;
            String Name = request.FileName;
            String RRID = request.RelatedRecordID;
            String PhotoNum = request.PhotoNumber;
    
            Http http = new Http();
    
            HttpRequest metadataReq = new HttpRequest();
            metadataReq.setEndpoint('callout:DriveGet/' + fileId + '?fields=mimeType,name');
            metadataReq.setMethod('GET');
            Response response = new Response(); // Initialize response here to ensure one response per request
    
            try {
                HttpResponse metadataRes = http.send(metadataReq);
                if(metadataRes.getStatusCode() == 200) {
                    Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(metadataRes.getBody());
                    String mimeType = (String) metadata.get('mimeType');
                    String fileExtension = determineFileExtension(mimeType);
    
                    if (fileExtension != null) {
                        HttpRequest contentReq = new HttpRequest();
                        contentReq.setEndpoint('callout:DriveGet/' + fileId + '?alt=media');
                        contentReq.setMethod('GET');
                        
                        HttpResponse contentRes = http.send(contentReq);
                        if(contentRes.getStatusCode() == 200) {
                            Blob fileContent = contentRes.getBodyAsBlob();
    
                            String salesforceFileURL = uploadFileToSalesforce(fileContent, fileId, fileExtension, Name, PhotoNum, RRID);
                            response.salesforceFileURL = salesforceFileURL;
                        }
                    }
                }
            } catch(Exception e) {
                // Optionally handle exception or log error, might set error flag/message in response
            }
            responses.add(response); // Add response for this request, ensuring match between requests and responses
        }
    
        return responses;
    }

    private static String determineFileExtension(String mimeType) {
        Map<String, String> mimeTypeToExtension = new Map<String, String>{
            'image/jpeg' => '.jpg',
            'image/png' => '.png',
            'image/gif' => '.gif',
            'image/webp' => '.webp',
            'image/tiff' => '.tiff',
            'image/bmp' => '.bmp',
            'image/heif' => '.jpg', // Converting HEIF/HEIC to jpg for broader support
            'image/heic' => '.jpg',
            'image/svg+xml' => '.svg'
        };
        
        if (mimeTypeToExtension.containsKey(mimeType)) {
            return mimeTypeToExtension.get(mimeType);
        } else {
            return null; // Unsupported MIME type
        }
    }

    private static String uploadFileToSalesforce(Blob fileContent, String fileId, String fileExtension, String Name, String PhotoNum, String RRID) {
        // Create a new ContentVersion to hold the file data
        ContentVersion cv = new ContentVersion();
        cv.VersionData = fileContent;
        cv.Title = Name; // Optionally, set a more descriptive title
        cv.Google_Drive_ID__c = fileId; // Optionally, set a more descriptive title
        cv.PhotoNumber__c = PhotoNum;
        cv.FirstPublishLocationId = RRID; 
        cv.PathOnClient = fileId + fileExtension; // Name the file
        cv.Resized__c = true;
        insert cv;
        
        // Creating a ContentDistribution record for public sharing
        ContentDistribution cd = new ContentDistribution();
        cd.ContentVersionId = cv.Id;
        cd.Name = cv.Title;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesNotifyOnVisit = false;
        cd.PreferencesPasswordRequired = false;
        cd.PreferencesAllowOriginalDownload = true;
        insert cd;
    
        String orgId = UserInfo.getOrganizationId();

        // Fetch the newly created ContentDistribution record to get the DistributionPublicUrl
        ContentVersion cvrq = [SELECT Id, ContentBodyId, FileType FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        ContentDistribution newcd = [SELECT Id, DistributionPublicUrl FROM ContentDistribution WHERE ContentVersionId = :cv.Id LIMIT 1];

        String versionId15 = cvrq.Id; // Convert to 15-character ID
        versionId15 = versionId15.substring(0, 15); 
        String contentBodyId15 = cvrq.ContentBodyId; // Convert to 15-character ID if not null
        contentBodyId15 = contentBodyId15.substring(0, 15);
        String orgId15 = UserInfo.getOrganizationId(); // Convert to 15-character ID
        orgId15 = orgId15.substring(0, 15);
        
        // Parsing the DistributionPublicUrl
        String baseUrl = newcd.DistributionPublicUrl.substringBefore('/sfc');
        baseUrl = baseUrl.replace('my.salesforce', 'file.force');
        String ending = newcd.DistributionPublicUrl.substringAfterLast('/a/');

        // Construct the URL for viewing the picture
        String fileExt = cvrq.FileType.equalsIgnoreCase('JPG') ? 'Jpg' : cvrq.FileType;
        String viewUrl = baseUrl 
                         + '/sfc/dist/version/renditionDownload?rendition=ORIGINAL_' 
                         + fileExt 
                         + '&versionId=' + versionId15 
                         + '&operationContext=DELIVERY&contentId=' + contentBodyId15
                         + '&page=0&d=/a/' + ending 
                         + '&oid=';

        String sfFileURL = viewUrl;
          
        return sfFileURL;
    }
}