/**
 * @description Handles content reporting operations for Stories, Needs/Offers, Library Items, etc.
 * Creates Feedback__c records with Type = 'Content Report' to store user reports
 * about inappropriate or problematic content.
 */
public with sharing class FimbyContentReportController {

    private static final String DUPLICATE_REPORT_MESSAGE =
        'We\'ve already received your report on this. A moderator is reviewing it — '
        + 'no need to flag it again. If something urgent comes up, email safety@fimby.ca.';

    /**
     * @description Pre-flight check before opening the report modal or submitting.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> checkExistingReport(String contentId, String contentType) {
        ContentReportHelper helper = new ContentReportHelper();
        String normalizedType = helper.normalizeContentTypePublic(contentType);
        Id reporterContactId = resolveRepresentedReporterContactId();
        Id neighbourhoodId = reporterContactId != null ? FimbyIdentityRepository.getNeighbourhoodId() : null;
        Boolean alreadyReported = helper.hasReporterAlreadyFiled(
            reporterContactId, neighbourhoodId, contentId, normalizedType
        );
        return new Map<String, Object>{
            'alreadyReported' => alreadyReported,
            'message' => alreadyReported ? DUPLICATE_REPORT_MESSAGE : null
        };
    }

    /**
     * Submit a content report
     * @param reportData JSON string containing: contentId, contentType, reason, additionalInfo
     * @return Map with success status and message
     */
    @AuraEnabled
    public static Map<String, Object> submitContentReport(String reportData) {
        try {
            return new ContentReportHelper().submitReportInternal(reportData);
        } catch (Exception e) {
            if (isDuplicateReportException(e)) {
                return new Map<String, Object>{
                    'success' => false,
                    'alreadyReported' => true,
                    'message' => DUPLICATE_REPORT_MESSAGE
                };
            }
            AuraHandledException ex = new AuraHandledException('Error submitting report: ' + e.getMessage());
            ex.setMessage('Error submitting report: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Represented identity for report dedup and moderator evidence — matches Posted_By__c on Feedback__c.
     */
    private static Id resolveRepresentedReporterContactId() {
        return FimbyIdentityRepository.getActingAsContactId();
    }

    private static Boolean isDuplicateReportException(Exception e) {
        String msg = e != null ? e.getMessage() : '';
        if (String.isBlank(msg) && e instanceof DmlException) {
            msg = ((DmlException) e).getDmlMessage(0);
        }
        return String.isNotBlank(msg)
            && (msg.contains('Task_Dedup_Key__c') || msg.contains('DUPLICATE_VALUE'));
    }

    /**
     * @description Helper class for DML operations without sharing.
     * Ensures reports can be created regardless of user permissions.
     */
    private without sharing class ContentReportHelper {

        /**
         * @description Parses report JSON and creates a Feedback__c record with Type = 'Content Report'.
         * @param reportDataJson JSON string containing contentId, contentType, reason, additionalInfo
         * @return Map with success, reportId, and message keys
         */
        public Map<String, Object> submitReportInternal(String reportDataJson) {
            Map<String, Object> reportData = (Map<String, Object>) JSON.deserializeUntyped(reportDataJson);

            String contentId = (String) reportData.get('contentId');
            String contentType = normalizeContentType((String) reportData.get('contentType'));
            String reason = (String) reportData.get('reason');
            String additionalInfo = (String) reportData.get('additionalInfo');

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            Id realContactId = currentUser.ContactId;
            Id actingAsContactId = resolveRepresentedReporterContactId();
            Id neighbourhoodId = actingAsContactId != null ? FimbyIdentityRepository.getNeighbourhoodId() : null;

            if (hasReporterAlreadyFiled(actingAsContactId, neighbourhoodId, contentId, contentType)) {
                return new Map<String, Object>{
                    'success' => false,
                    'alreadyReported' => true,
                    'message' => DUPLICATE_REPORT_MESSAGE
                };
            }

            String reasonLabel = getReasonLabel(reason);
            String contentLabel = getContentTypeLabel(contentType);
            String reportTitle = 'Content report: ' + reasonLabel + ' on a ' + contentLabel.toLowerCase();
            if (reportTitle.length() > 80) {
                reportTitle = reportTitle.substring(0, 77) + '...';
            }

            String details = buildReportDetails(contentType, contentLabel, reason, reasonLabel, additionalInfo, contentId);

            // Dual-stamp: Contact__c = real (who clicked), Posted_By__c = acting-as identity
            Feedback__c report = new Feedback__c(
                Name = reportTitle,
                Type__c = 'Content Report',
                Details__c = details,
                Contact__c = realContactId,
                Posted_By__c = actingAsContactId != null ? actingAsContactId : realContactId,
                Neighbourhood__c = neighbourhoodId,
                Related_Record_ID__c = contentId
            );

            Savepoint sp = Database.setSavepoint();
            try {
                insert report;

                if (neighbourhoodId != null) {
                    FimbyModeratorTaskService.TaskRequest taskReq = new FimbyModeratorTaskService.TaskRequest();
                    taskReq.neighbourhoodId = neighbourhoodId;
                    taskReq.category = 'Content_Report';
                    taskReq.priority = (reason == 'harassment' || reason == 'safety') ? 'Urgent' : 'Standard';
                    taskReq.relatedRecordId = contentId;
                    taskReq.relatedRecordType = contentType;
                    taskReq.summary = reportTitle;
                    taskReq.sourceType = 'Content_Report';
                    taskReq.sourceRecordId = String.valueOf(report.Id);
                    taskReq.reporterContactId = actingAsContactId;
                    taskReq.secondaryContactId = realContactId;
                    taskReq.subjectContactId = resolveContentAuthor(contentId, contentType);
                    taskReq.reasonCode = reason;
                    taskReq.details = additionalInfo;
                    FimbyModeratorTaskService.createOrUpdateTask(taskReq);
                }
            } catch (Exception e) {
                Database.rollback(sp);
                if (FimbyContentReportController.isDuplicateReportException(e)
                    || hasReporterAlreadyFiled(actingAsContactId, neighbourhoodId, contentId, contentType)) {
                    return new Map<String, Object>{
                        'success' => false,
                        'alreadyReported' => true,
                        'message' => DUPLICATE_REPORT_MESSAGE
                    };
                }
                throw e;
            }

            return new Map<String, Object>{
                'success' => true,
                'reportId' => report.Id,
                'message' => 'Report submitted successfully. We will review this within 24 hours.'
            };
        }

        private String getReasonLabel(String reasonId) {
            Map<String, String> reasonLabels = new Map<String, String>{
                'inappropriate' => 'Inappropriate content',
                'spam' => 'Spam or misleading',
                'harassment' => 'Harassment or bullying',
                'privacy' => 'Privacy violation',
                'safety' => 'Safety concern',
                'other' => 'Other'
            };
            return reasonLabels.containsKey(reasonId) ? reasonLabels.get(reasonId) : reasonId;
        }

        /**
         * @description Maps LWC shorthand content types (Story, Need_Offer) to Salesforce API names.
         */
        public String normalizeContentTypePublic(String contentType) {
            return normalizeContentType(contentType);
        }

        public Boolean hasReporterAlreadyFiled(
            Id representedReporterContactId,
            Id neighbourhoodId,
            String contentId,
            String contentType
        ) {
            return FimbyModeratorTaskService.hasReporterFiledContentReport(
                neighbourhoodId, representedReporterContactId, contentId, contentType
            );
        }

        private String normalizeContentType(String contentType) {
            if (String.isBlank(contentType)) {
                return contentType;
            }
            if (contentType.endsWith('__c')) {
                return contentType;
            }
            Map<String, String> aliases = new Map<String, String>{
                'Story' => 'Story__c',
                'Need_Offer' => 'Needs_Offers__c',
                'Needs_Offer' => 'Needs_Offers__c',
                'Library_Item' => 'Library_Item__c',
                'Response' => 'Response__c',
                'Story_Comment' => 'Story_Comment__c'
            };
            return aliases.containsKey(contentType) ? aliases.get(contentType) : contentType;
        }

        /**
         * @description Maps a content-object API name to the warm, plain-language label
         *              FIMBY surfaces to neighbours and moderators. Falls back to the
         *              object's Salesforce label, then the raw API name as a last resort,
         *              so a new reportable type never leaks `Foo__c` into a notification.
         */
        private String getContentTypeLabel(String contentType) {
            if (String.isBlank(contentType)) { return 'post'; }
            Map<String, String> labels = new Map<String, String>{
                'Story__c' => 'Sharedlife post',
                'Story_Comment__c' => 'comment on a Sharedlife post',
                'Needs_Offers__c' => 'Ask or Offer post',
                'Library_Item__c' => 'library item',
                'Response__c' => 'reply'
            };
            if (labels.containsKey(contentType)) { return labels.get(contentType); }
            try {
                Schema.DescribeSObjectResult d = Schema.getGlobalDescribe().get(contentType).getDescribe();
                if (d != null) { return d.getLabel(); }
            } catch (Exception e) {
                // Fall through to the API name so we still produce *something* readable.
            }
            return contentType;
        }

        private Id resolveContentAuthor(String contentId, String contentType) {
            if (String.isBlank(contentId) || String.isBlank(contentType)) return null;
            try {
                if (contentType == 'Story__c') {
                    List<Story__c> recs = [SELECT Posted_By__c FROM Story__c WHERE Id = :contentId LIMIT 1];
                    return recs.isEmpty() ? null : recs[0].Posted_By__c;
                } else if (contentType == 'Needs_Offers__c') {
                    List<Needs_Offers__c> recs = [SELECT Contact__c FROM Needs_Offers__c WHERE Id = :contentId LIMIT 1];
                    return recs.isEmpty() ? null : recs[0].Contact__c;
                } else if (contentType == 'Library_Item__c') {
                    List<Library_Item__c> recs = [SELECT Owner_Contact__c FROM Library_Item__c WHERE Id = :contentId LIMIT 1];
                    return recs.isEmpty() ? null : recs[0].Owner_Contact__c;
                } else if (contentType == 'Response__c') {
                    List<Response__c> recs = [SELECT Contact__c FROM Response__c WHERE Id = :contentId LIMIT 1];
                    return recs.isEmpty() ? null : recs[0].Contact__c;
                } else if (contentType == 'Story_Comment__c') {
                    List<Story_Comment__c> recs = [SELECT Posted_By__c FROM Story_Comment__c WHERE Id = :contentId LIMIT 1];
                    return recs.isEmpty() ? null : recs[0].Posted_By__c;
                }
            } catch (Exception e) {
                return null;
            }
            return null;
        }

        private String buildReportDetails(String contentType, String contentLabel, String reason, String reasonLabel, String additionalInfo, String contentId) {
            List<String> detailParts = new List<String>();

            detailParts.add('=== CONTENT REPORT ===');
            detailParts.add('');
            detailParts.add('Content Type: ' + contentLabel + ' (' + contentType + ')');
            detailParts.add('Content ID: ' + contentId);
            detailParts.add('Reason: ' + reasonLabel);
            detailParts.add('');
            
            if (String.isNotBlank(additionalInfo)) {
                detailParts.add('Additional Information:');
                detailParts.add(additionalInfo);
                detailParts.add('');
            }
            
            detailParts.add('Reported: ' + System.now().format('yyyy-MM-dd HH:mm:ss'));
            
            return String.join(detailParts, '\n');
        }
    }
}