/**
 * @description Handles feedback submission operations. Converted from Submit_Feedback.flow (SystemModeWithoutSharing).
 */
public with sharing class FimbyFeedbackController {

    @TestVisible
    private static String testScreenshotUrlOverride;

    /**
     * Get Feedback Type picklist values
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getFeedbackTypePicklist() {
        List<String> picklistValues = new List<String>();
        Schema.DescribeFieldResult fieldResult = Feedback__c.Type__c.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive() && entry.getValue() != 'Content Report') {
                picklistValues.add(entry.getValue());
            }
        }
        return picklistValues;
    }

    /**
     * Submit feedback
     */
    @AuraEnabled
    public static Map<String, Object> submitFeedback(String feedbackData) {
        try {
            return new FeedbackHelper().submitFeedbackInternal(feedbackData);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error submitting feedback: ' + e.getMessage());
            ex.setMessage('Error submitting feedback: ' + e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getScreenshot(String recordId) {
        try {
            return new ScreenshotHelper().getScreenshotInternal(recordId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting screenshot: ' + e.getMessage());
            ex.setMessage('Error getting screenshot: ' + e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static Map<String, Object> uploadScreenshot(
        String fileData,
        String fileName,
        String recordId,
        Integer imageWidth,
        Integer imageHeight
    ) {
        try {
            if (String.isBlank(fileData) || String.isBlank(recordId) || String.isBlank(fileName)) {
                throw new AuraHandledException('Missing required parameters');
            }
            return new ScreenshotHelper().uploadScreenshotInternal(
                fileData, fileName, recordId, imageWidth, imageHeight
            );
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error uploading screenshot: ' + e.getMessage());
            ex.setMessage('Error uploading screenshot: ' + e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static Map<String, Object> removeScreenshot(String recordId) {
        try {
            new ScreenshotHelper().clearScreenshot(recordId);
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Screenshot removed successfully'
            };
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error removing screenshot: ' + e.getMessage());
            ex.setMessage('Error removing screenshot: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Helper class for DML operations without sharing
     * Matches flow's SystemModeWithoutSharing behavior
     */
    private without sharing class FeedbackHelper {
        /**
         * @description Parses feedback JSON and creates Feedback__c record without sharing.
         * Dual-stamps Contact__c (real submitter) and Posted_By__c (acting-as identity).
         * @param feedbackDataJson JSON string with feedbackType, title, details, and optional relatedRecordId
         * @return Map with success, feedbackId, and message
         */
        public Map<String, Object> submitFeedbackInternal(String feedbackDataJson) {
            Map<String, Object> feedbackData = (Map<String, Object>) JSON.deserializeUntyped(feedbackDataJson);

            String feedbackType = (String) feedbackData.get('feedbackType');
            String title = (String) feedbackData.get('title');
            String details = (String) feedbackData.get('details');
            String relatedRecordId = (String) feedbackData.get('relatedRecordId');

            if (feedbackType == 'Content Report') {
                throw new AuraHandledException(
                    'Content reports must be submitted using the report option on the content itself.'
                );
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.contact.Id;
            Id actingAsContactId = identity.actingAsContactId;
            Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();

            Feedback__c feedback = new Feedback__c(
                Name = title,
                Type__c = feedbackType,
                Details__c = details,
                Contact__c = realContactId,
                Posted_By__c = actingAsContactId,
                Neighbourhood__c = neighbourhoodId,
                Related_Record_ID__c = relatedRecordId
            );

            insert feedback;

            if (neighbourhoodId != null && feedbackType != 'Content Report') {
                FimbyModeratorTaskService.TaskRequest taskReq = new FimbyModeratorTaskService.TaskRequest();
                taskReq.neighbourhoodId = neighbourhoodId;
                taskReq.category = 'Feedback_Triage';
                taskReq.priority = 'Low';
                taskReq.subjectContactId = actingAsContactId;
                taskReq.relatedRecordId = String.valueOf(feedback.Id);
                taskReq.relatedRecordType = 'Feedback__c';
                taskReq.summary = feedbackType + ': ' + title;
                taskReq.sourceType = 'Content_Report';
                taskReq.sourceRecordId = String.valueOf(feedback.Id);
                taskReq.reporterContactId = realContactId;
                FimbyModeratorTaskService.createOrUpdateTask(taskReq);
            }

            return new Map<String, Object>{
                'success' => true,
                'feedbackId' => feedback.Id,
                'message' => 'Feedback submitted successfully'
            };
        }
    }

    @TestVisible
    private without sharing class ScreenshotHelper {
        public Map<String, Object> getScreenshotInternal(String recordId) {
            Feedback__c feedback = loadAccessibleFeedback(recordId);
            String imageUrl = feedback.Image_URL__c;
            if (imageUrl != null && imageUrl.endsWith('&oid=')) {
                imageUrl += UserInfo.getOrganizationId();
            }
            return new Map<String, Object>{
                'success' => true,
                'imageUrl' => imageUrl
            };
        }

        private Feedback__c loadAccessibleFeedback(String recordId) {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Missing feedback record');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.contact.Id;
            Id actingAsContactId = identity.actingAsContactId;

            List<Feedback__c> rows = [
                SELECT Id, Contact__c, Posted_By__c, Image_URL__c
                FROM Feedback__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('Feedback record not found');
            }

            Feedback__c feedback = rows[0];
            if (feedback.Contact__c != realContactId && feedback.Posted_By__c != actingAsContactId) {
                throw new AuraHandledException('You do not have permission to update this feedback.');
            }
            return feedback;
        }

        public Map<String, Object> uploadScreenshotInternal(
            String fileData,
            String fileName,
            String recordId,
            Integer imageWidth,
            Integer imageHeight
        ) {
            loadAccessibleFeedback(recordId);

            String viewUrl;
            Id contentVersionId;

            if (Test.isRunningTest()) {
                if (FimbyFeedbackController.testScreenshotUrlOverride != null) {
                    viewUrl = FimbyFeedbackController.testScreenshotUrlOverride;
                } else {
                    viewUrl = 'https://test.example.com/feedback_' + fileName + '&oid=';
                }
                contentVersionId = null;
            } else {
                String base64Data = extractBase64Data(fileData);
                Blob fileBlob = EncodingUtil.base64Decode(base64Data);
                ContentVersion cv = createContentVersion(fileBlob, fileName);
                createContentDocumentLink(cv.ContentDocumentId, recordId);
                ContentDistribution cd = createContentDistribution(cv.Id, fileName);
                viewUrl = buildDistributionUrl(cv, cd);
                contentVersionId = cv.Id;
            }

            Feedback__c feedback = new Feedback__c(
                Id = recordId,
                Image_URL__c = viewUrl,
                Image_Dimensions__c = deriveImageDimensions(imageWidth, imageHeight)
            );
            update feedback;

            String previewUrl = viewUrl + UserInfo.getOrganizationId();
            return new Map<String, Object>{
                'success' => true,
                'contentVersionId' => contentVersionId,
                'viewUrl' => previewUrl,
                'message' => 'Screenshot uploaded successfully'
            };
        }

        public void clearScreenshot(String recordId) {
            loadAccessibleFeedback(recordId);
            update new Feedback__c(
                Id = recordId,
                Image_URL__c = null,
                Image_Dimensions__c = null
            );
        }

        @TestVisible
        private String extractBase64Data(String fileData) {
            if (fileData != null && fileData.contains(',')) {
                return fileData.substringAfter(',');
            }
            return fileData;
        }

        @TestVisible
        private ContentVersion createContentVersion(Blob fileBlob, String fileName) {
            ContentVersion cv = new ContentVersion(
                Title = fileName,
                PathOnClient = fileName,
                VersionData = fileBlob,
                IsMajorVersion = true
            );
            insert cv;

            return [
                SELECT Id, ContentDocumentId, ContentBodyId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];
        }

        @TestVisible
        private void createContentDocumentLink(Id contentDocumentId, Id recordId) {
            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = recordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            insert cdl;
        }

        @TestVisible
        private ContentDistribution createContentDistribution(Id contentVersionId, String fileName) {
            ContentDistribution cd = new ContentDistribution(
                ContentVersionId = contentVersionId,
                Name = fileName,
                PreferencesAllowViewInBrowser = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesAllowOriginalDownload = true
            );
            insert cd;

            return [
                SELECT Id, DistributionPublicUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
                LIMIT 1
            ];
        }

        @TestVisible
        private String buildDistributionUrl(ContentVersion cv, ContentDistribution cd) {
            String versionId15 = String.valueOf(cv.Id).substring(0, 15);
            String contentBodyId15 = String.valueOf(cv.ContentBodyId).substring(0, 15);
            String baseUrl = cd.DistributionPublicUrl.substringBefore('/sfc');
            baseUrl = baseUrl.replace('my.salesforce', 'file.force');
            String ending = cd.DistributionPublicUrl.substringAfterLast('/a/');

            return baseUrl
                + FimbySettings.getUrl('File_Download') + '?rendition=ORIGINAL_Jpg'
                + '&versionId=' + versionId15
                + '&operationContext=DELIVERY&contentId=' + contentBodyId15
                + '&page=0&d=/a/' + ending
                + '&oid=';
        }

        @TestVisible
        private String deriveImageDimensions(Integer imageWidth, Integer imageHeight) {
            if (imageWidth == null || imageHeight == null || imageWidth <= 0 || imageHeight <= 0) {
                return 'Square';
            }
            Decimal ratio = (Decimal) imageWidth / imageHeight;
            if (ratio >= 0.9 && ratio <= 1.1) {
                return 'Square';
            }
            return imageWidth > imageHeight ? 'Rectangle (Wide)' : 'Rectangle (Tall)';
        }
    }
}
