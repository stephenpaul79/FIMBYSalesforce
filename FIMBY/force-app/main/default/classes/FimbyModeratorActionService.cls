public without sharing class FimbyModeratorActionService {

    public static Boolean isOrganizationVerifiedForRepApproval(String verificationStatus) {
        return verificationStatus == 'Verified';
    }

    public static void resolveTask(Id taskId, String resolution, String notes, Id moderatorContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, OwnerId, Claimed_Date__c, Resolved_Date__c, Resolved_By__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        if (task.Status__c == 'Resolved' || task.Status__c == 'Dismissed') {
            throw new AuraHandledException('This task is already closed. Reopen it before taking new action.');
        }
        task.Status__c = resolution;
        task.Resolved_Date__c = Datetime.now();
        task.Resolved_By__c = moderatorContactId;
        if (String.isNotBlank(notes)) task.Notes__c = notes;
        autoClaimIfNeeded(task, moderatorContactId);
        update task;
    }

    public static void escalateTask(Id taskId, String reason, Id moderatorContactId, Id adminContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, Category__c, Summary__c, Neighbourhood__c, Claimed_Date__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.Status__c = 'Escalated';
        task.Escalated_To__c = adminContactId;
        task.Escalated_Date__c = Datetime.now();
        task.Escalation_Reason__c = reason;
        autoClaimIfNeeded(task, moderatorContactId);
        update task;
        FimbyModeratorAlertService.alertAdmin(task, reason);
    }

    public static void reopenTask(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.Status__c = 'In_Progress';
        task.Escalated_To__c = null;
        task.Escalated_Date__c = null;
        task.Escalation_Reason__c = null;
        task.Resolved_Date__c = null;
        task.Resolved_By__c = null;
        update task;
    }

    public static void claimTask(Id taskId, Id moderatorContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        User modUser = [SELECT Id FROM User WHERE ContactId = :moderatorContactId LIMIT 1];
        task.OwnerId = modUser.Id;
        task.Claimed_Date__c = Datetime.now();
        if (task.Status__c == 'New') task.Status__c = 'In_Progress';
        update task;
    }

    public static void reassignTask(Id taskId, Id newOwnerUserId) {
        Moderator_Task__c task = [
            SELECT Id FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.OwnerId = newOwnerUserId;
        update task;
    }

    public static void releaseTask(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.Claimed_Date__c = null;
        update task;
    }

    public static void requestMoreInfo(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.Status__c = 'Awaiting_Info';
        update task;
    }

    public static void requestReReview(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        task.Re_Review_Requested__c = true;
        if (task.Status__c == 'Resolved' || task.Status__c == 'Dismissed') {
            task.Status__c = 'New';
            task.Resolved_Date__c = null;
            task.Resolved_By__c = null;
        }
        update task;
    }

    public static void republishContent(String recordId, String recordType, Id taskId) {
        if (recordType == 'Needs_Offers__c') {
            Needs_Offers__c rec = [SELECT Id FROM Needs_Offers__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Visible';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Response__c') {
            Response__c rec = [SELECT Id FROM Response__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Visible';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Story__c') {
            Story__c rec = [SELECT Id FROM Story__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Visible';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Library_Item__c') {
            Library_Item__c rec = [SELECT Id FROM Library_Item__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Visible';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Story_Comment__c') {
            Story_Comment__c rec = [SELECT Id FROM Story_Comment__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Visible';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        }

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', 'Content republished', null);
        }
    }

    public static void keepContentHidden(Id taskId, String reasonCode, String statement, String notes, Id moderatorContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, Claimed_Date__c, Related_Record_Id__c, Related_Record_Type__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        if (String.isNotBlank(task.Related_Record_Id__c) && String.isNotBlank(task.Related_Record_Type__c)) {
            flagContent(task.Related_Record_Id__c, task.Related_Record_Type__c, reasonCode, moderatorContactId);
        }
        task.Decision_Reason_Code__c = reasonCode;
        task.Decision_Statement__c = statement;
        task.Status__c = 'Resolved';
        task.Resolved_Date__c = Datetime.now();
        task.Resolved_By__c = moderatorContactId;
        if (String.isNotBlank(notes)) task.Notes__c = notes;
        autoClaimIfNeeded(task, moderatorContactId);
        update task;
    }

    public static void flagContent(String recordId, String recordType, String flagValue, Id moderatorContactId) {
        if (flagValue == 'Moderator_Review') {
            applyModeratorReview(recordId, recordType);
            return;
        }
        String hiddenReason = flagValue == 'Moderator_Hidden' ? 'Moderator_Hidden' : flagValue;
        applyModeratorHidden(recordId, recordType, hiddenReason, moderatorContactId);
    }

    /**
     * @description Marks content under moderator review without hiding it or writing an
     *              invalid Hidden_Reason_Code__c (Moderator_Review is not a picklist value).
     */
    private static void applyModeratorReview(String recordId, String recordType) {
        if (recordType == 'Needs_Offers__c') {
            Needs_Offers__c rec = [SELECT Id FROM Needs_Offers__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Under_Review';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Response__c') {
            Response__c rec = [SELECT Id FROM Response__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Under_Review';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Story__c') {
            Story__c rec = [SELECT Id FROM Story__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Under_Review';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Library_Item__c') {
            Library_Item__c rec = [SELECT Id FROM Library_Item__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Under_Review';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        } else if (recordType == 'Story_Comment__c') {
            Story_Comment__c rec = [SELECT Id FROM Story_Comment__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Under_Review';
            rec.Hidden_By_Moderator__c = null;
            rec.Hidden_Date__c = null;
            rec.Hidden_Reason_Code__c = null;
            update rec;
        }
    }

    private static void applyModeratorHidden(
        String recordId,
        String recordType,
        String reasonCode,
        Id moderatorContactId
    ) {
        if (recordType == 'Needs_Offers__c') {
            Needs_Offers__c rec = [SELECT Id FROM Needs_Offers__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Hidden_By_Moderator';
            rec.Hidden_By_Moderator__c = moderatorContactId;
            rec.Hidden_Date__c = Datetime.now();
            rec.Hidden_Reason_Code__c = reasonCode;
            update rec;
        } else if (recordType == 'Response__c') {
            Response__c rec = [SELECT Id FROM Response__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Hidden_By_Moderator';
            rec.Hidden_By_Moderator__c = moderatorContactId;
            rec.Hidden_Date__c = Datetime.now();
            rec.Hidden_Reason_Code__c = reasonCode;
            update rec;
        } else if (recordType == 'Story__c') {
            Story__c rec = [SELECT Id FROM Story__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Hidden_By_Moderator';
            rec.Hidden_By_Moderator__c = moderatorContactId;
            rec.Hidden_Date__c = Datetime.now();
            rec.Hidden_Reason_Code__c = reasonCode;
            update rec;
        } else if (recordType == 'Library_Item__c') {
            Library_Item__c rec = [SELECT Id FROM Library_Item__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Hidden_By_Moderator';
            rec.Hidden_By_Moderator__c = moderatorContactId;
            rec.Hidden_Date__c = Datetime.now();
            rec.Hidden_Reason_Code__c = reasonCode;
            update rec;
        } else if (recordType == 'Story_Comment__c') {
            Story_Comment__c rec = [SELECT Id FROM Story_Comment__c WHERE Id = :recordId LIMIT 1];
            rec.Moderation_Status__c = 'Hidden_By_Moderator';
            rec.Hidden_By_Moderator__c = moderatorContactId;
            rec.Hidden_Date__c = Datetime.now();
            rec.Hidden_Reason_Code__c = reasonCode;
            update rec;
        }
    }

    public static void issueCheckIn(Id taskId, Id subjectContactId, String reasonCode, String messageBody, Id moderatorContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, Claimed_Date__c, Subject_Contact__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        if (task.Subject_Contact__c == null && subjectContactId != null) {
            task.Subject_Contact__c = subjectContactId;
        }
        task.Enforcement_Level__c = 'Check_In';
        task.Decision_Reason_Code__c = reasonCode;
        task.Decision_Statement__c = messageBody;
        autoClaimIfNeeded(task, moderatorContactId);
        update task;
    }

    public static void recordConcern(Id taskId, Id subjectContactId, String reasonCode, String statement, Id moderatorContactId) {
        Moderator_Task__c task = [
            SELECT Id, Status__c, Claimed_Date__c, Subject_Contact__c
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        if (task.Subject_Contact__c == null && subjectContactId != null) {
            task.Subject_Contact__c = subjectContactId;
        }
        task.Enforcement_Level__c = 'Recorded_Concern';
        task.Decision_Reason_Code__c = reasonCode;
        task.Decision_Statement__c = statement;
        autoClaimIfNeeded(task, moderatorContactId);
        update task;
    }

    public static void sendWelcomeMessage(Id contactId, String messageBody, Id taskId, Id moderatorContactId) {
        Contact c = [SELECT Id, Welcomed_By__c FROM Contact WHERE Id = :contactId LIMIT 1];
        c.Welcomed_By__c = moderatorContactId;
        c.Welcomed_Date__c = Datetime.now();
        update c;

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', 'Welcome sent', moderatorContactId);
        }
    }

    public static void markWelcomed(Id contactId, Id taskId, String notes, Id moderatorContactId) {
        Contact c = [SELECT Id FROM Contact WHERE Id = :contactId LIMIT 1];
        c.Welcomed_By__c = moderatorContactId;
        c.Welcomed_Date__c = Datetime.now();
        update c;

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', notes, moderatorContactId);
        }
    }

    public static void triageFeedback(Id feedbackId, String triageStatus, Id taskId, Id moderatorContactId) {
        Feedback__c fb = [SELECT Id FROM Feedback__c WHERE Id = :feedbackId LIMIT 1];
        fb.Triage_Status__c = triageStatus;
        fb.Triaged_By__c = moderatorContactId;
        fb.Triaged_Date__c = Datetime.now();
        if (triageStatus == 'Enhancement_Flagged') {
            fb.Status__c = 'Roadmap';
        }
        update fb;

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', 'Triaged as ' + triageStatus, moderatorContactId);
        }
    }

    public static void approveSupportRelationship(Id supportRelationshipId, Id taskId, Id moderatorContactId) {
        Support_Relationship__c sr = [
            SELECT Id, Status__c, Relationship_Type__c,
                   Related_Organization__c,
                   Related_Organization__r.Verification_Status__c
            FROM Support_Relationship__c
            WHERE Id = :supportRelationshipId
            LIMIT 1
        ];
        if (sr.Relationship_Type__c == 'Community_Group_Rep' && sr.Related_Organization__c != null) {
            if (!isOrganizationVerifiedForRepApproval(sr.Related_Organization__r?.Verification_Status__c)) {
                throw new AuraHandledException(
                    'The organization must be verified before approving this representative.');
            }
        }
        sr.Status__c = 'Approved';
        sr.Approved_By__c = moderatorContactId;
        sr.Approved_Date__c = Datetime.now();
        update sr;

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', 'Approved', moderatorContactId);
        }
    }

    public static void approveOrganization(Id accountId, Id taskId, Id moderatorContactId) {
        Account acct = [
            SELECT Id, Name, Verification_Status__c, Organization_Contact__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (acct.Verification_Status__c == 'Verified') {
            throw new AuraHandledException('This organization is already verified.');
        }
        if (acct.Verification_Status__c == 'Rejected') {
            throw new AuraHandledException('This organization request was rejected.');
        }

        Id neighbourhoodId = resolvePrimaryNeighbourhoodForOrg(accountId);
        if (neighbourhoodId == null) {
            throw new AuraHandledException('No neighbourhood link found for this organization.');
        }

        Contact orgContact;
        if (acct.Organization_Contact__c != null) {
            orgContact = [SELECT Id FROM Contact WHERE Id = :acct.Organization_Contact__c LIMIT 1];
        } else {
            orgContact = new Contact(
                LastName = acct.Name,
                AccountId = neighbourhoodId,
                Is_Organization_Contact__c = true,
                Organization_Account__c = acct.Id
            );
            insert orgContact;
            orgContact.Organization_Account__c = acct.Id;
            update orgContact;
        }

        acct.Is_Approved_Community_Group__c = true;
        acct.Verification_Status__c = 'Verified';
        acct.Verified_By__c = moderatorContactId;
        acct.Verified_Date__c = Datetime.now();
        acct.Organization_Contact__c = orgContact.Id;
        update acct;

        List<Community_Group_Neighbourhood__c> junctions = [
            SELECT Id, Status__c
            FROM Community_Group_Neighbourhood__c
            WHERE Organization__c = :accountId
              AND Status__c = 'Inactive'
        ];
        for (Community_Group_Neighbourhood__c junction : junctions) {
            junction.Status__c = 'Active';
            junction.Is_Primary__c = true;
            junction.Approved_By__c = moderatorContactId;
            junction.Approved_Date__c = Datetime.now();
        }
        if (!junctions.isEmpty()) {
            update junctions;
        }

        if (taskId != null) {
            resolveTask(taskId, 'Resolved', 'Organization approved', moderatorContactId);
        }
    }

    public static void rejectOrganization(
        Id accountId, String reasonCode, String statement, Id taskId, Id moderatorContactId
    ) {
        Account acct = [
            SELECT Id, Name, Verification_Status__c, Submitted_By__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        if (acct.Verification_Status__c == 'Verified') {
            throw new AuraHandledException('This organization is already verified.');
        }

        acct.Verification_Status__c = 'Rejected';
        update acct;

        List<Support_Relationship__c> pendingReps = [
            SELECT Id, Status__c
            FROM Support_Relationship__c
            WHERE Related_Organization__c = :accountId
              AND Relationship_Type__c = 'Community_Group_Rep'
              AND Status__c = 'Pending'
        ];
        for (Support_Relationship__c sr : pendingReps) {
            sr.Status__c = 'Declined';
        }
        if (!pendingReps.isEmpty()) {
            update pendingReps;
        }

        if (taskId != null) {
            Moderator_Task__c task = [
                SELECT Id, Status__c, Claimed_Date__c
                FROM Moderator_Task__c
                WHERE Id = :taskId
                LIMIT 1
            ];
            task.Decision_Reason_Code__c = reasonCode;
            task.Decision_Statement__c = statement;
            task.Status__c = 'Resolved';
            task.Resolved_Date__c = Datetime.now();
            task.Resolved_By__c = moderatorContactId;
            autoClaimIfNeeded(task, moderatorContactId);
            update task;
        }

        if (acct.Submitted_By__c != null) {
            try {
                FimbyNotificationService.createNotification(
                    acct.Submitted_By__c,
                    'Organization_Rejected',
                    'Your organization request needs a follow-up',
                    'We could not verify ' + acct.Name + ' at this time. A neighbourhood moderator will reach out if more information is needed.',
                    acct.Id,
                    'Account',
                    FimbySettings.getUrl('Manage_Identities'),
                    'care'
                );
            } catch (Exception e) {
                FimbyLogger.error('FimbyModeratorActionService', 'rejectOrganization.notify', e);
            }
        }
    }

    @TestVisible
    private static Id resolvePrimaryNeighbourhoodForOrg(Id accountId) {
        List<Community_Group_Neighbourhood__c> links = [
            SELECT Neighbourhood__c
            FROM Community_Group_Neighbourhood__c
            WHERE Organization__c = :accountId
            ORDER BY Is_Primary__c DESC, CreatedDate ASC
            LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].Neighbourhood__c;
    }

    public static void declineSupportRelationship(
        Id supportRelationshipId, String reasonCode, String statement, Id taskId, Id moderatorContactId
    ) {
        Support_Relationship__c sr = [
            SELECT Id, Status__c FROM Support_Relationship__c WHERE Id = :supportRelationshipId LIMIT 1
        ];
        sr.Status__c = 'Declined';
        update sr;

        if (taskId != null) {
            Moderator_Task__c task = [SELECT Id, Status__c, Claimed_Date__c FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1];
            task.Decision_Reason_Code__c = reasonCode;
            task.Decision_Statement__c = statement;
            task.Status__c = 'Resolved';
            task.Resolved_Date__c = Datetime.now();
            task.Resolved_By__c = moderatorContactId;
            autoClaimIfNeeded(task, moderatorContactId);
            update task;
        }
    }

    public static Id getOrCreateModeratorConversation(Id moderatorContactId, Id targetContactId) {
        List<Conversation__c> existing = [
            SELECT Id FROM Conversation__c
            WHERE (Participant_1__c = :moderatorContactId AND Participant_2__c = :targetContactId)
               OR (Participant_1__c = :targetContactId AND Participant_2__c = :moderatorContactId)
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0].Id;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = moderatorContactId,
            Participant_2__c = targetContactId,
            Status__c = 'Active'
        );
        insert conv;
        return conv.Id;
    }

    private static void autoClaimIfNeeded(Moderator_Task__c task, Id moderatorContactId) {
        if (moderatorContactId == null) return;
        if (task.Claimed_Date__c != null) return;
        List<User> modUsers = [SELECT Id FROM User WHERE ContactId = :moderatorContactId LIMIT 1];
        if (!modUsers.isEmpty()) {
            task.OwnerId = modUsers[0].Id;
            task.Claimed_Date__c = Datetime.now();
        }
        if (task.Status__c == 'New') task.Status__c = 'In_Progress';
    }
}
