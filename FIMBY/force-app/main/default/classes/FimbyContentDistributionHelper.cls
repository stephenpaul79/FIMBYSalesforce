/**
 * @description Uploads a file, links it to a Salesforce record, creates a public distribution,
 * and returns the file.force rendition URL ending in oid= for client-side org-id completion.
 */
public without sharing class FimbyContentDistributionHelper {

    @TestVisible
    private static Boolean forceLiveUploadForTests = false;

    public static String uploadAndLink(String fileData, String fileName, Id linkedEntityId) {
        if (linkedEntityId == null) {
            throw handledException('A link target record Id is required.');
        }
        if (String.isBlank(fileData) || String.isBlank(fileName)) {
            throw handledException('Missing file data or file name.');
        }
        if (Test.isRunningTest() && !forceLiveUploadForTests) {
            return 'https://test.example.com/' + fileName + '?oid=';
        }

        String base64Data = fileData.contains(',') ? fileData.substringAfter(',') : fileData;
        Blob fileBlob = EncodingUtil.base64Decode(base64Data);

        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = fileBlob,
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, ContentBodyId, FileExtension
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        ContentDistribution cd = new ContentDistribution(
            Name = fileName,
            ContentVersionId = cv.Id,
            PreferencesAllowViewInBrowser = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesAllowOriginalDownload = true
        );
        insert cd;

        cd = [
            SELECT Id, DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :cd.Id
            LIMIT 1
        ];

        return buildViewUrl(cv, cd);
    }

    private static String buildViewUrl(ContentVersion cv, ContentDistribution cd) {
        String ext = String.isNotBlank(cv.FileExtension) ? cv.FileExtension : 'Jpg';
        String versionId15 = String.valueOf(cv.Id).substring(0, 15);
        String contentBodyId15 = cv.ContentBodyId != null
            ? String.valueOf(cv.ContentBodyId).substring(0, 15)
            : versionId15;
        String baseUrl = cd.DistributionPublicUrl.substringBefore('/sfc');
        baseUrl = baseUrl.replace('my.salesforce', 'file.force');
        String ending = cd.DistributionPublicUrl.substringAfterLast('/a/');

        return baseUrl
            + FimbySettings.getUrl('File_Download') + '?rendition=ORIGINAL_' + ext
            + '&versionId=' + versionId15
            + '&operationContext=DELIVERY&contentId=' + contentBodyId15
            + '&page=0&d=/a/' + ending
            + '&oid=';
    }

    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
