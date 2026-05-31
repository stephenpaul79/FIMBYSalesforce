public with sharing class FimbyModeratorDashboardController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getModeratorHeaderData() {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null) return new Map<String, Object>{ 'isModerator' => false, 'taskCount' => 0 };
        return FimbyModeratorQueryService.getModeratorHeaderData(contactId);
    }

    @AuraEnabled(cacheable=true)
    public static List<Moderator_Assignment__c> getModeratorAssignments() {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null) return new List<Moderator_Assignment__c>();
        return FimbyModeratorQueryService.getModeratorAssignments(contactId);
    }

    @AuraEnabled
    public static Map<String, Object> getDashboardSummary(Id neighbourhoodId) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getDashboardSummary(neighbourhoodId);
    }

    @AuraEnabled
    public static List<Moderator_Task__c> getTasksByCategory(Id neighbourhoodId, String category, Integer pageSize, Integer offset) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getTasksByCategory(neighbourhoodId, category, pageSize, offset);
    }

    @AuraEnabled
    public static List<Moderator_Task__c> getEscalatedTasks(Id neighbourhoodId, Integer pageSize, Integer offset) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getEscalatedTasks(neighbourhoodId, pageSize, offset);
    }

    @AuraEnabled
    public static Map<String, Object> getClosedTasks(
        Id neighbourhoodId, String category, String statusFilter,
        Integer pageSize, Integer offset
    ) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getClosedTasks(
            neighbourhoodId, category, statusFilter, pageSize, offset
        );
    }

    @AuraEnabled
    public static Map<String, Object> getTaskPageBootstrap(Id taskId) {
        return FimbyModeratorQueryService.getTaskPageBootstrap(taskId);
    }

    @AuraEnabled
    public static Map<String, Object> getContentReviewData(String recordId, String recordType, Id taskId) {
        return FimbyModeratorQueryService.getContentReviewData(recordId, recordType, taskId);
    }

    @AuraEnabled
    public static Map<String, Object> getFollowUpReviewData(Id followUpId) {
        return FimbyModeratorQueryService.getFollowUpReviewData(followUpId);
    }

    @AuraEnabled
    public static Map<String, Object> getBlockReviewData(Id blockedContactId) {
        return FimbyModeratorQueryService.getBlockReviewData(blockedContactId);
    }

    @AuraEnabled
    public static Map<String, Object> getFeedbackReviewData(Id feedbackId) {
        return FimbyModeratorQueryService.getFeedbackReviewData(feedbackId);
    }

    @AuraEnabled
    public static Map<String, Object> getSupportReviewData(Id supportRelationshipId) {
        return FimbyModeratorQueryService.getSupportReviewData(supportRelationshipId);
    }

    @AuraEnabled
    public static Map<String, Object> getSupportConcernData(Id taskId) {
        return FimbyModeratorQueryService.getSupportConcernData(taskId);
    }

    @AuraEnabled
    public static Map<String, Object> getEscalationDetail(Id taskId) {
        return FimbyModeratorQueryService.getEscalationDetail(taskId);
    }

    @AuraEnabled
    public static Map<String, Object> getWelcomeReviewData(Id contactId) {
        return FimbyModeratorQueryService.getWelcomeReviewData(contactId);
    }

    @AuraEnabled
    public static Map<String, Object> getNeighbourhoodHealthData(Id neighbourhoodId) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getNeighbourhoodHealthData(neighbourhoodId);
    }

    @AuraEnabled
    public static Map<String, Object> getSubjectHistory(Id subjectContactId, Id neighbourhoodId, Id excludeTaskId) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getSubjectHistory(subjectContactId, neighbourhoodId, excludeTaskId);
    }

    @AuraEnabled
    public static Map<String, Object> getReporterFilingStats(Id reporterContactId, Id neighbourhoodId, Id excludeTaskId) {
        validateModerator(neighbourhoodId);
        return FimbyModeratorQueryService.getReporterFilingStats(reporterContactId, neighbourhoodId, excludeTaskId);
    }

    @AuraEnabled
    public static void resolveTask(Id taskId, String resolution, String notes) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.resolveTask(taskId, resolution, notes, contactId);
    }

    @AuraEnabled
    public static void escalateTask(Id taskId, String reason, Id adminContactId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.escalateTask(taskId, reason, contactId, adminContactId);
    }

    @AuraEnabled
    public static void reopenTask(Id taskId) {
        FimbyModeratorActionService.reopenTask(taskId);
    }

    @AuraEnabled
    public static void updateTaskStage(Id taskId, String newStatus, String enforcementLevel) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, Enforcement_Level__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        if (newStatus != null) task.Status__c = newStatus;
        if (enforcementLevel != null) task.Enforcement_Level__c = enforcementLevel;
        update task;
    }

    @AuraEnabled
    public static Map<String, Object> adminResolveFollowUp(Id followUpId, String resolution, Boolean isConfirmed) {
        return FimbyFollowUpController.adminResolveFollowUp(followUpId, resolution, isConfirmed);
    }

    @AuraEnabled
    public static void claimTask(Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.claimTask(taskId, contactId);
    }

    @AuraEnabled
    public static void reassignTask(Id taskId, Id newOwnerUserId) {
        FimbyModeratorActionService.reassignTask(taskId, newOwnerUserId);
    }

    @AuraEnabled
    public static void releaseTask(Id taskId) {
        FimbyModeratorActionService.releaseTask(taskId);
    }

    @AuraEnabled
    public static void requestMoreInfo(Id taskId, Id targetContactId) {
        FimbyModeratorActionService.requestMoreInfo(taskId);
    }

    @AuraEnabled
    public static void requestReReview(Id taskId) {
        FimbyModeratorActionService.requestReReview(taskId);
    }

    @AuraEnabled
    public static void republishContent(String recordId, String recordType, Id taskId) {
        FimbyModeratorActionService.republishContent(recordId, recordType, taskId);
    }

    @AuraEnabled
    public static void keepContentHidden(Id taskId, String reasonCode, String statement, String notes) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.keepContentHidden(taskId, reasonCode, statement, notes, contactId);
    }

    @AuraEnabled
    public static void flagContent(String recordId, String recordType, String flagValue) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.flagContent(recordId, recordType, flagValue, contactId);
    }

    @AuraEnabled
    public static void issueCheckIn(Id taskId, Id subjectContactId, String reasonCode, String messageBody) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.issueCheckIn(taskId, subjectContactId, reasonCode, messageBody, contactId);
    }

    @AuraEnabled
    public static void recordConcern(Id taskId, Id subjectContactId, String reasonCode, String statement) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.recordConcern(taskId, subjectContactId, reasonCode, statement, contactId);
    }

    @AuraEnabled
    public static void sendWelcomeMessage(Id contactId, String messageBody, Id taskId) {
        Id modContactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.sendWelcomeMessage(contactId, messageBody, taskId, modContactId);
    }

    @AuraEnabled
    public static void markWelcomed(Id contactId, Id taskId, String notes) {
        Id modContactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.markWelcomed(contactId, taskId, notes, modContactId);
    }

    @AuraEnabled
    public static void triageFeedback(Id feedbackId, String triageStatus, Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.triageFeedback(feedbackId, triageStatus, taskId, contactId);
    }

    @AuraEnabled
    public static void approveSupportRelationship(Id supportRelationshipId, Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.approveSupportRelationship(supportRelationshipId, taskId, contactId);
    }

    @AuraEnabled
    public static void declineSupportRelationship(Id supportRelationshipId, String reasonCode, String statement, Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.declineSupportRelationship(supportRelationshipId, reasonCode, statement, taskId, contactId);
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOrganizationReviewData(Id accountId, Id taskId) {
        return FimbyModeratorQueryService.getOrganizationReviewData(accountId, taskId);
    }

    @AuraEnabled
    public static void approveOrganization(Id accountId, Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.approveOrganization(accountId, taskId, contactId);
    }

    @AuraEnabled
    public static void rejectOrganization(Id accountId, String reasonCode, String statement, Id taskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.rejectOrganization(accountId, reasonCode, statement, taskId, contactId);
    }

    @AuraEnabled
    public static void approveOrganizationAndRep(Id accountId, Id orgTaskId, Id supportRelationshipId, Id repTaskId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        FimbyModeratorActionService.approveOrganization(accountId, orgTaskId, contactId);
        if (supportRelationshipId != null) {
            FimbyModeratorActionService.approveSupportRelationship(supportRelationshipId, repTaskId, contactId);
        }
    }

    @AuraEnabled
    public static Id getOrCreateModeratorConversation(Id targetContactId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        return FimbyModeratorActionService.getOrCreateModeratorConversation(contactId, targetContactId);
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isModeratorForNeighbourhood(Id neighbourhoodId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null) return false;
        return FimbyModeratorQueryService.isModeratorForNeighbourhood(contactId, neighbourhoodId);
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getNeighbourhoodModerator() {
        Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
        if (neighbourhoodId == null) return null;

        List<Moderator_Assignment__c> mods = [
            SELECT Contact__c, Contact__r.Name, Contact__r.Pronouns__c, Contact__r.PhotoUrl
            FROM Moderator_Assignment__c
            WHERE Neighbourhood__c = :neighbourhoodId AND Status__c = 'Active' AND Role__c = 'Primary'
            LIMIT 1
        ];
        if (mods.isEmpty()) return null;

        return new Map<String, Object>{
            'contactId' => mods[0].Contact__c,
            'name'      => mods[0].Contact__r.Name,
            'pronouns'  => mods[0].Contact__r.Pronouns__c,
            'photoUrl'  => mods[0].Contact__r.PhotoUrl
        };
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isModeratorContact(Id contactId) {
        if (contactId == null) return false;
        Integer count = [
            SELECT COUNT() FROM Moderator_Assignment__c
            WHERE Contact__c = :contactId AND Status__c = 'Active'
        ];
        return count > 0;
    }

    private static void validateModerator(Id neighbourhoodId) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (!FimbyModeratorQueryService.isModeratorForNeighbourhood(contactId, neighbourhoodId)) {
            throw new AuraHandledException('You do not have moderator access to this neighbourhood.');
        }
    }
}
