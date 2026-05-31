public with sharing class GoogleDriveAPIController {
    @InvocableMethod(label='Upload File to Google Drive' description='Upload File to Google Drive')
    public static List<ResponseWrapper> storeFiletoDrive(List<List<ID>> cdIdList) {
        system.debug('========='+cdIdList);
        ResponseWrapper rw = new ResponseWrapper();
        if(cdIdList.isEmpty() || (!cdIdList.isEmpty() && cdIdList[0].isEmpty() ) ) {
            rw.isSuccess = False;
            rw.response = 'Please select file.';
            return new List<ResponseWrapper>{rw};
        }
        List<ContentVersion> cvFile = [SELECT Id, ContentDocumentId, VersionData, FileType, ContentDocument.Title FROM ContentVersion WHERE ContentDocumentId =: cdIdList[0] ];  
        String boundary = 'SalesforceNewsTechnologyStuff';
        String delimiter = '\r\n--' + boundary + '\r\n';  
        String close_delim = '\r\n--' + boundary + '--';  
        String Neighbourhood = [Select Neighbourhood__c From User Where Id = :UserInfo.getUserId()][0].Neighbourhood__c;
        Google_Drive_Folder__mdt GDF = Google_Drive_Folder__mdt.getInstance(Neighbourhood);
        String FolderId = GDF.Folder_ID__c;
        String bodyEncoded = EncodingUtil.base64Encode(cvFile[0].VersionData);  
        String body = delimiter + 'Content-Type: application/json\r\n\r\n' + '{ "name" : "' + cvFile[0].ContentDocument.Title + '",' + '"parents" : ["' + FolderId +'"],'  + ' "mimeType" : "image/' + cvFile[0].FileType + '"}' + delimiter + 'Content-Type: image/' + cvFile[0].FileType + '\r\n' + 'Content-Transfer-Encoding: base64\r\n' + '\r\n' + bodyEncoded + close_delim;   

        HttpRequest req = new HttpRequest();
        req.setheader('Content-Length',String.valueOf(body.length()));
        req.setheader('Content-Type','multipart/related; boundary='+boundary);
        req.setMethod('POST'); 
        req.setEndpoint('callout:Drive'); 
        req.setBody(body); 
        Http h = new Http(); 
        try {
            Httpresponse resp = h.send(req);
            if(resp.getStatusCode() <= 299) {
                rw.isSuccess = True;
                Map<String,object> responseMap =(Map<String,object>)JSON.deserializeUntyped(resp.getBody());
                String fileId = (String)responseMap.get('id');
                rw.response = 'FileId:' + fileId;

                // Call Google Drive API to get file metadata
                HttpRequest metadataReq = new HttpRequest();
                metadataReq.setMethod('GET');
                metadataReq.setEndpoint('callout:DriveGet'+'/'+ fileId + '?fields=imageMediaMetadata');
                HttpResponse metadataResp = h.send(metadataReq);

                // Extract the width and height
                Map<String, object> metadataMap = (Map<String, object>)JSON.deserializeUntyped(metadataResp.getBody());
                Map<String, object> imageMetadata = (Map<String, object>)metadataMap.get('imageMediaMetadata');
                Integer originalWidth = (Integer)imageMetadata.get('width');
                Integer originalHeight = (Integer)imageMetadata.get('height');
                Integer originalRotation = (Integer)imageMetadata.get('rotation');
                
                
                // Determine the scaling factor
                Double scalingFactor = 200.0 / Math.max(originalWidth, originalHeight);
                
                // Calculate the new proportional dimensions
                rw.width = (Integer)(originalWidth * scalingFactor);
                rw.height = (Integer)(originalHeight * scalingFactor);
                rw.rotation = (Integer)(originalRotation);                 

            }
            else {
                rw.isSuccess = False;
                rw.response = 'Error : '+resp.getBody();
            }
        }
        catch(Exception ex) {
            rw.isSuccess = False;
            rw.response = 'Error : '+ex.getMessage();
        }
        if (rw.isSuccess) {
            // Assume fileId is the Google Drive file ID obtained after successful upload
            String fileId = rw.response.replace('FileId:', '').trim();

            // Upload the file to Salesforce Files
            ContentVersion cvrq = [SELECT Id, Title, ContentBodyId FROM ContentVersion WHERE Id = :cvFile[0].Id LIMIT 1];
            cvrq.Google_Drive_ID__c = fileId; // Assuming you have a custom field for Google Drive ID
            update cvrq;       

            // Creating a ContentDistribution record for public sharing
            ContentDistribution cd = new ContentDistribution();
            cd.ContentVersionId = cvrq.Id;
            cd.Name = cvrq.Title;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesAllowOriginalDownload = true;
            insert cd;

            // Update response wrapper with Salesforce Files and ContentDistribution info
            rw.contentVersionId = cvrq.Id;
            rw.fileExtension = cvFile[0].FileType;
            rw.contentBodyId = cvrq.ContentBodyId;
            rw.distributionPublicUrl = cd.DistributionPublicUrl;
        
            String orgId = UserInfo.getOrganizationId();

            // Fetch the newly created ContentDistribution record to get the DistributionPublicUrl
            ContentDistribution newcd = [SELECT Id, DistributionPublicUrl FROM ContentDistribution WHERE ContentVersionId = :cvrq.Id LIMIT 1];

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
            String fileExtension = cvFile[0].FileType.equalsIgnoreCase('JPG') ? 'Jpg' : cvFile[0].FileType;
            String viewUrl = baseUrl 
                             + '/sfc/dist/version/renditionDownload?rendition=ORIGINAL_' 
                             + fileExtension 
                             + '&versionId=' + versionId15 
                             + '&operationContext=DELIVERY&contentId=' + contentBodyId15
                             + '&page=0&d=/a/' + ending 
                             + '&oid=';

            // Adding the constructed URL to the response wrapper
            rw.viewUrl = viewUrl;
        }        
        return new List<ResponseWrapper>{rw};
    }

        public class ResponseWrapper {
            @InvocableVariable(label='View URL' description='URL to View the Uploaded Image')
            public String viewUrl;
            @InvocableVariable(label='Response' description='Response' required=true)
            public String response;
            @InvocableVariable(label='Success Flag' description='Success Flag' required=true)
            public boolean isSuccess;
            @InvocableVariable(label='Width' description='Image Width in Pixels')
            public Integer width;
            @InvocableVariable(label='Height' description='Image Height in Pixels')
            public Integer height; 
            @InvocableVariable(label='Rotation' description='Rotation Value')
            public Integer rotation; 
            // New variables for Salesforce Files and ContentDistribution
            @InvocableVariable(label='Content Version ID')
            public String contentVersionId;
            @InvocableVariable(label='File Extension')
            public String fileExtension;
            @InvocableVariable(label='Content Body ID')
            public String contentBodyId;
            @InvocableVariable(label='Distribution Public URL')
            public String distributionPublicUrl;
        }
}