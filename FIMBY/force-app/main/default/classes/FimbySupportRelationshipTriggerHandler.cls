/**
 * @description Handler for FimbySupportRelationshipTrigger (after update).
 * Watches Status__c transitions on the paper-form lifecycle and fires three
 * side effects in plain Apex:
 *   - Approved → stamp paper-form TOS on the supportee Contact, create the
 *     "Mail activation letter" task for the admin, send approval email to
 *     the supporter.
 *   - Rejected → send rejection email to the supporter.
 *   - Pending Paper Review → create the "Verify supportee" task for the
 *     admin queue.
 *
 * All side effects are idempotent — the handler only fires when Status__c
 * actually transitions, so re-fires from validation rules / other triggers
 * don't double-stamp or double-send.
 */
public without sharing class FimbySupportRelationshipTriggerHandler {

    private static final String ACCOUNT_DELETION_QUEUE_NAME = 'FIMBY_Support';
    private static final Integer ACTIVATION_TASK_DUE_DAYS = 2;
    private static final Integer VERIFICATION_TASK_DUE_DAYS = 5;

    /**
     * @description Blocks duplicate (Contact__c, Related_Contact__c|Related_Organization__c,
     * Relationship_Type__c, Neighbourhood__c) tuples where an existing record is already in an
     * active state (anything other than Inactive / Revoked / Declined / Rejected / Expired).
     * This is a soft-link constraint enforced in Apex because Salesforce native unique
     * constraints don't span polymorphic related-record references.
     */
    public static void handleBeforeInsert(List<Support_Relationship__c> newList) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> relatedContactIds = new Set<Id>();
        Set<Id> relatedOrgIds = new Set<Id>();
        Set<Id> neighbourhoodIds = new Set<Id>();
        for (Support_Relationship__c rel : newList) {
            if (rel.Contact__c != null) contactIds.add(rel.Contact__c);
            if (rel.Related_Contact__c != null) relatedContactIds.add(rel.Related_Contact__c);
            if (rel.Related_Organization__c != null) relatedOrgIds.add(rel.Related_Organization__c);
            if (rel.Neighbourhood__c != null) neighbourhoodIds.add(rel.Neighbourhood__c);
        }

        if (contactIds.isEmpty()) return;

        Set<String> activeStatuses = new Set<String>{
            'Pending', 'Pending Paper Review', 'Pending Verification', 'Approved', 'Suspended', 'Draft'
        };

        List<Support_Relationship__c> existing = [
            SELECT Id, Contact__c, Related_Contact__c, Related_Organization__c,
                   Relationship_Type__c, Neighbourhood__c, Status__c
            FROM Support_Relationship__c
            WHERE Contact__c IN :contactIds
              AND Neighbourhood__c IN :neighbourhoodIds
              AND Status__c IN :activeStatuses
              AND (Related_Contact__c IN :relatedContactIds
                   OR Related_Organization__c IN :relatedOrgIds)
        ];

        if (existing.isEmpty()) return;

        Set<String> existingKeys = new Set<String>();
        for (Support_Relationship__c old : existing) {
            existingKeys.add(makeDupKey(old));
        }

        for (Support_Relationship__c rel : newList) {
            if (existingKeys.contains(makeDupKey(rel))) {
                rel.addError('A support relationship for this person already exists in this neighbourhood.');
            }
        }
    }

    private static String makeDupKey(Support_Relationship__c rel) {
        return String.valueOf(rel.Contact__c) + '|' +
               String.valueOf(rel.Related_Contact__c) + '|' +
               String.valueOf(rel.Related_Organization__c) + '|' +
               String.valueOf(rel.Relationship_Type__c) + '|' +
               String.valueOf(rel.Neighbourhood__c);
    }

    /**
     * @description Creates a neighbourhood moderator task when a support relationship
     * is submitted for approval (Status = Pending).
     */
    public static void handleAfterInsert(List<Support_Relationship__c> newList) {
        List<FimbyModeratorTaskService.TaskRequest> requests = new List<FimbyModeratorTaskService.TaskRequest>();

        for (Support_Relationship__c rel : newList) {
            if (rel.Status__c != 'Pending' || rel.Neighbourhood__c == null) {
                continue;
            }

            String relLabel = rel.Relationship_Type__c == 'Community_Group_Rep'
                ? 'Community group rep request'
                : 'Support person request';

            FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
            req.neighbourhoodId = rel.Neighbourhood__c;
            req.category = 'Support_Relationship_Approval';
            req.priority = 'Standard';
            req.subjectContactId = rel.Contact__c;
            req.secondaryContactId = rel.Related_Contact__c;
            req.relatedRecordId = String.valueOf(rel.Id);
            req.relatedRecordType = 'Support_Relationship__c';
            req.summary = relLabel;
            req.sourceType = 'Lifecycle_Request';
            req.sourceRecordId = String.valueOf(rel.Id);
            req.reporterContactId = rel.Contact__c;
            requests.add(req);
        }

        for (FimbyModeratorTaskService.TaskRequest req : requests) {
            FimbyModeratorTaskService.createOrUpdateTask(req);
        }
    }

    public static void handleAfterUpdate(List<Support_Relationship__c> newList,
                                         Map<Id, Support_Relationship__c> oldMap) {
        Set<Id> approvedIds = new Set<Id>();
        Set<Id> rejectedIds = new Set<Id>();
        Set<Id> pendingReviewIds = new Set<Id>();
        List<Support_Relationship__c> revokedRels = new List<Support_Relationship__c>();

        for (Support_Relationship__c rel : newList) {
            Support_Relationship__c old = oldMap.get(rel.Id);
            if (old == null) continue;
            if (rel.Status__c == old.Status__c) continue;

            if (rel.Status__c == 'Approved') {
                approvedIds.add(rel.Id);
            } else if (rel.Status__c == 'Rejected') {
                rejectedIds.add(rel.Id);
            } else if (rel.Status__c == 'Pending Paper Review') {
                pendingReviewIds.add(rel.Id);
            } else if (rel.Status__c == 'Revoked' || rel.Status__c == 'Inactive') {
                revokedRels.add(rel);
            }
        }

        if (!approvedIds.isEmpty()) {
            handleApproved(approvedIds);
            createApprovalNotifications(approvedIds);
        }
        if (!rejectedIds.isEmpty()) {
            handleRejected(rejectedIds);
        }
        if (!pendingReviewIds.isEmpty()) {
            createVerificationTasks(pendingReviewIds);
        }
        if (!revokedRels.isEmpty() && !System.isFuture() && !System.isBatch()) {
            try {
                System.enqueueJob(new FimbySupportRelationshipQueueable(revokedRels));
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                    'enqueueRevocationQueueable', e);
            }
        }
    }

    private static void createApprovalNotifications(Set<Id> srIds) {
        List<Support_Relationship__c> rels = [
            SELECT Id, Contact__c, Related_Contact__c, Related_Contact__r.Name,
                   Related_Organization__c, Related_Organization__r.Name,
                   Relationship_Type__c, Neighbourhood__c
            FROM Support_Relationship__c
            WHERE Id IN :srIds
        ];
        for (Support_Relationship__c rel : rels) {
            if (rel.Contact__c == null) continue;
            String targetName = rel.Related_Contact__c != null
                ? rel.Related_Contact__r.Name
                : (rel.Related_Organization__c != null ? rel.Related_Organization__r.Name : 'your community');
            try {
                FimbyNotificationService.createNotification(
                    rel.Contact__c,
                    'Relationship_Approved',
                    'Support relationship approved',
                    'You can now switch identities to act on behalf of ' + targetName + '.',
                    rel.Id,
                    'Support_Relationship__c',
                    FimbySettings.getUrl('Manage_Identities'),
                    'care'
                );
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                    'createApprovalNotifications', e);
            }
        }
    }

    private static void handleApproved(Set<Id> srIds) {
        List<Support_Relationship__c> rels = [
            SELECT Id, Name, Contact__c, Related_Contact__c, Signed_Date__c,
                   Approved_Date__c, Activation_Letter_Sent_Date__c,
                   Relationship_Type__c,
                   Contact__r.Vouched_Status__c,
                   Related_Contact__r.Vouched_Status__c
            FROM Support_Relationship__c
            WHERE Id IN :srIds
        ];

        String tosVersion = FimbySettings.tosCurrentVersion();

        for (Support_Relationship__c rel : rels) {
            if (rel.Related_Contact__c != null) {
                try {
                    FimbyTosController.recordPaperAcceptance(
                        rel.Related_Contact__c,
                        rel.Signed_Date__c,
                        tosVersion,
                        null
                    );
                } catch (Exception e) {
                    FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                        'handleApproved.recordPaperAcceptance', e, rel.Id);
                }
            }

            try {
                FimbySupportRelationshipEmailService.sendApprovalNotification(rel.Id);
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                    'handleApproved.sendApprovalNotification', e, rel.Id);
            }

            // Vouching inheritance: when a Support_Person relationship is approved AND
            // the supporter is Vouched, the supportee inherits Vouched status. This
            // ensures the most vulnerable users are not gated out of the lending library.
            if (rel.Relationship_Type__c == 'Support_Person'
                    && rel.Related_Contact__c != null
                    && rel.Contact__r != null
                    && 'Vouched'.equals(rel.Contact__r.Vouched_Status__c)
                    && !'Vouched'.equals(rel.Related_Contact__r?.Vouched_Status__c)) {
                try {
                    update new Contact(
                        Id = rel.Related_Contact__c,
                        Vouched_Status__c = 'Vouched',
                        Vouched_By_Contact__c = rel.Contact__c,
                        Vouched_Date__c = System.now(),
                        Vouched_By_Moderator__c = false,
                        Vouch_Source__c = 'Support_Relationship_Inherited'
                    );
                } catch (Exception e) {
                    FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                        'handleApproved.inheritVouch', e, rel.Id);
                }
            }
        }

        Set<Id> activationLetterSrIds = new Set<Id>();
        for (Support_Relationship__c rel : rels) {
            if (rel.Relationship_Type__c == 'Support_Person' && rel.Related_Contact__c != null) {
                activationLetterSrIds.add(rel.Id);
            }
        }
        if (!activationLetterSrIds.isEmpty()) {
            createActivationLetterTasks(activationLetterSrIds);
        }
    }

    private static void handleRejected(Set<Id> srIds) {
        for (Id srId : srIds) {
            try {
                FimbySupportRelationshipEmailService.sendRejectionNotification(srId);
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler',
                    'handleRejected.sendRejectionNotification', e, srId);
            }
        }
    }

    private static void createVerificationTasks(Set<Id> srIds) {
        Id queueId = lookupSupportQueueId();
        if (queueId == null) return;

        List<Task> tasks = new List<Task>();
        for (Id srId : srIds) {
            tasks.add(new Task(
                Subject = 'Verify paper-form support relationship',
                Description = 'Call the supportee to confirm they understand and consent to the ' +
                    'support relationship. If you cannot reach them by phone, mail a postal ' +
                    'verification letter as a fallback.',
                WhatId = srId,
                OwnerId = queueId,
                Priority = 'Normal',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(VERIFICATION_TASK_DUE_DAYS)
            ));
        }
        if (!tasks.isEmpty()) {
            try {
                insert tasks;
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler', 'createVerificationTasks', e);
            }
        }
    }

    private static void createActivationLetterTasks(Set<Id> srIds) {
        Id queueId = lookupSupportQueueId();
        if (queueId == null) return;

        List<Task> tasks = new List<Task>();
        for (Id srId : srIds) {
            tasks.add(new Task(
                Subject = 'Mail FIMBY activation letter to supportee',
                Description = 'Generate the FimbySupporteeActivationLetter PDF and post it to the ' +
                    'supportee. Stamp Activation_Letter_Sent_Date__c once mailed.',
                WhatId = srId,
                OwnerId = queueId,
                Priority = 'Normal',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(ACTIVATION_TASK_DUE_DAYS)
            ));
        }
        if (!tasks.isEmpty()) {
            try {
                insert tasks;
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipTriggerHandler', 'createActivationLetterTasks', e);
            }
        }
    }

    @TestVisible
    private static Id cachedQueueId;
    private static Id lookupSupportQueueId() {
        if (cachedQueueId != null) return cachedQueueId;
        List<Group> queues = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :ACCOUNT_DELETION_QUEUE_NAME
            LIMIT 1
        ];
        cachedQueueId = queues.isEmpty() ? null : queues[0].Id;
        return cachedQueueId;
    }
}
