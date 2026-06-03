/**
 * @description Controller for bulk buy accountability check-ins and admin restorations.
 * Manages the follow-up lifecycle: report, resolve, escalate, admin actions, and history queries.
 */
public with sharing class FimbyFollowUpController {

    private static final String CLASS_NAME = 'FimbyFollowUpController';

    @AuraEnabled
    public static Map<String, Object> reportFollowUp(Id reservationId, String message, String reasonSubtype) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            Id realContactId = (Id) actingAs.get('realContactId');
            Id actingAsContactId = (Id) actingAs.get('actingAsContactId');

            FollowUpHelper helper = new FollowUpHelper();
            List<Response__c> responses = helper.getResponseForReport(reservationId);
            if (responses.isEmpty()) {
                throw new AuraHandledException('Reservation not found.');
            }
            Response__c resp = responses[0];

            Boolean isOrganiser = resp.Need_Offer_Responded_To__r.Posted_By__c == realContactId
                || resp.Need_Offer_Responded_To__r.Contact__c == actingAsContactId;
            if (!isOrganiser) {
                throw new AuraHandledException('Only the organiser can initiate a check-in.');
            }
            if (resp.Need_Offer_Responded_To__r.Status__c != FimbyConstants.NEEDS_OFFERS_PICKUP_READY) {
                throw new AuraHandledException('Check-ins can only be initiated after pickup notification.');
            }

            Datetime pickupDate = resp.Need_Offer_Responded_To__r.Pickup_Notified_Date__c;
            if (pickupDate == null || pickupDate.addHours(48) > System.now()) {
                throw new AuraHandledException('Please wait at least 48 hours after pickup notification.');
            }

            List<Bulk_Buy_Follow_Up__c> existing = [
                SELECT Id FROM Bulk_Buy_Follow_Up__c
                WHERE Reservation__c = :reservationId
                AND Status__c IN (:FimbyConstants.FOLLOWUP_PENDING, :FimbyConstants.FOLLOWUP_ESCALATED)
                /* with sharing enforces record access */
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException('An active check-in already exists for this reservation.');
            }

            return helper.doReport(resp, actingAsContactId, message, reasonSubtype);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'reportFollowUp', e);
            throw buildAuraException('Error creating check-in: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> resolveFollowUp(Id followUpId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');

            Bulk_Buy_Follow_Up__c fu = [
                SELECT Id, Status__c, Reporter__c, Checkin_Conversation__c,
                       Bulk_Buy__c, Reported_User__r.FirstName
                FROM Bulk_Buy_Follow_Up__c
                WHERE Id = :followUpId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (fu.Reporter__c != contactId) {
                throw new AuraHandledException('Only the organiser who created this check-in can resolve it.');
            }
            if (fu.Status__c != FimbyConstants.FOLLOWUP_PENDING && fu.Status__c != FimbyConstants.FOLLOWUP_ESCALATED) {
                throw new AuraHandledException('This check-in cannot be resolved in its current state.');
            }

            fu.Status__c = FimbyConstants.FOLLOWUP_RESOLVED;
            fu.Resolution_Date__c = System.now();
            fu.Resolved_By__c = UserInfo.getUserId();
            new FollowUpHelper().updateFollowUp(fu);

            if (fu.Checkin_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    fu.Checkin_Conversation__c,
                    'Marked resolved by organiser.',
                    FimbyConstants.SYS_MSG_STATUS_CHANGE
                );
            }

            String reserverName = fu.Reported_User__r?.FirstName ?? 'A neighbour';
            FimbyNotificationService.createNotification(
                fu.Reporter__c,
                FimbyConstants.NOTIF_FOLLOW_UP_RESOLVED,
                'Check-in with ' + reserverName + ' resolved',
                'Your check-in has been marked as resolved.',
                fu.Checkin_Conversation__c,
                'Conversation__c',
                FimbySettings.getUrl('Conversation', String.valueOf(fu.Checkin_Conversation__c)),
                reserverName,
                true
            );

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'resolveFollowUp', e);
            throw buildAuraException('Error resolving: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> escalateFollowUp(Id followUpId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');

            Bulk_Buy_Follow_Up__c fu = [
                SELECT Id, Status__c, Reporter__c, Checkin_Conversation__c,
                       Reported_User__c, Bulk_Buy__c, Bulk_Buy__r.Name,
                       Bulk_Buy__r.Neighbourhood__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Id = :followUpId
                LIMIT 1
            ];

            if (fu.Reporter__c != contactId) {
                throw new AuraHandledException('Only the organiser can escalate.');
            }
            if (fu.Status__c != FimbyConstants.FOLLOWUP_PENDING) {
                throw new AuraHandledException('Only pending check-ins can be escalated.');
            }

            fu.Status__c = FimbyConstants.FOLLOWUP_ESCALATED;
            new FollowUpHelper().updateFollowUp(fu);

            if (fu.Checkin_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    fu.Checkin_Conversation__c,
                    'Escalated to admin for review.',
                    FimbyConstants.SYS_MSG_STATUS_CHANGE
                );
            }

            if (fu.Bulk_Buy__r.Neighbourhood__c != null) {
                FimbyModeratorTaskService.TaskRequest taskReq = new FimbyModeratorTaskService.TaskRequest();
                taskReq.neighbourhoodId = fu.Bulk_Buy__r.Neighbourhood__c;
                taskReq.category = 'Bulk_Buy_Escalation';
                taskReq.priority = 'Urgent';
                taskReq.subjectContactId = fu.Reported_User__c;
                taskReq.relatedRecordId = String.valueOf(fu.Id);
                taskReq.relatedRecordType = 'Bulk_Buy_Follow_Up__c';
                taskReq.summary = 'Bulk buy escalation: ' + fu.Bulk_Buy__r.Name;
                taskReq.sourceType = 'System_Alert';
                taskReq.sourceRecordId = String.valueOf(fu.Id);
                taskReq.reporterContactId = fu.Reporter__c;
                FimbyModeratorTaskService.createOrUpdateTask(taskReq);
            }

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'escalateFollowUp', e);
            throw buildAuraException('Error escalating: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getFollowUpStatus(Id bulkBuyId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();

            List<Bulk_Buy_Follow_Up__c> followUps = [
                SELECT Id, Reservation__c, Status__c, Reported_User__c, Checkin_Conversation__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Bulk_Buy__c = :bulkBuyId
                AND RecordType.DeveloperName = :FimbyConstants.RT_FOLLOW_UP
                /* with sharing enforces record access */
                ORDER BY Reported_Date__c DESC
            ];

            Map<String, Object> statusByReservation = new Map<String, Object>();
            for (Bulk_Buy_Follow_Up__c fu : followUps) {
                String key = fu.Reservation__c;
                if (!statusByReservation.containsKey(key)) {
                    statusByReservation.put(key, new Map<String, Object>{
                        'followUpId' => fu.Id,
                        'status' => fu.Status__c,
                        'conversationId' => fu.Checkin_Conversation__c
                    });
                }
            }

            return new Map<String, Object>{ 'success' => true, 'statusByReservation' => statusByReservation };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getFollowUpStatus', e);
            throw buildAuraException('Error loading status: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getFollowUpByConversation(Id conversationId) {
        try {
            List<Bulk_Buy_Follow_Up__c> followUps = [
                SELECT Id, Status__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Checkin_Conversation__c = :conversationId
                AND RecordType.DeveloperName = :FimbyConstants.RT_FOLLOW_UP
                /* with sharing enforces record access */
                ORDER BY Reported_Date__c DESC
                LIMIT 1
            ];
            if (followUps.isEmpty()) {
                return null;
            }
            Bulk_Buy_Follow_Up__c fu = followUps[0];
            return new Map<String, Object>{
                'followUpId' => fu.Id,
                'status' => fu.Status__c
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getFollowUpByConversation', e);
            throw buildAuraException('Error loading check-in: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getBulkBuyHistory(Id contactId) {
        try {
            Id bulkBuyRtId = Schema.SObjectType.Needs_Offers__c
                .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY)?.getRecordTypeId();
            Id restorationRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
                .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_RESTORATION)?.getRecordTypeId();

            Boolean hasActiveAmber = false;
            FollowUpHelper helper = new FollowUpHelper();
            if (restorationRtId != null) {
                List<Bulk_Buy_Follow_Up__c> restorations = [
                    SELECT Id, Resolution_Date__c FROM Bulk_Buy_Follow_Up__c
                    WHERE Reported_User__c = :contactId
                    AND RecordTypeId = :restorationRtId
                    AND Status__c = :FimbyConstants.FOLLOWUP_PROBATIONARY_RESTORED
                    ORDER BY Resolution_Date__c DESC
                    LIMIT 1
                ];
                if (!restorations.isEmpty()) {
                    Integer newerOutcomes = helper.countNewerOutcomesSince(
                        contactId, bulkBuyRtId, restorations[0].Resolution_Date__c
                    );
                    hasActiveAmber = (newerOutcomes == 0);
                }
            }

            Integer queryLimit = hasActiveAmber ? 2 : 3;
            List<Response__c> outcomes = helper.getOutcomeResponsesForHistory(
                contactId, bulkBuyRtId, queryLimit
            );

            List<String> slots = new List<String>();

            // Build slots newest-first (left). Restoration is the most recent event when present,
            // so it lands in the leftmost slot. Outcomes from the query are already DESC.
            if (hasActiveAmber) {
                slots.add('amber');
            }
            for (Response__c r : outcomes) {
                slots.add(r.Status__c == FimbyConstants.RESPONSE_COMPLETED ? 'green' : 'red');
            }

            // Pad empty slots on the right.
            while (slots.size() < 3) {
                slots.add('neutral');
            }

            return new Map<String, Object>{
                'success' => true,
                'slots' => slots,
                'hasActiveAmber' => hasActiveAmber,
                'isBlocked' => [SELECT Is_Bulk_Buy_Blocked__c FROM Contact WHERE Id = :contactId].Is_Bulk_Buy_Blocked__c
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getBulkBuyHistory', e);
            throw buildAuraException('Error loading history: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> adminResolveFollowUp(Id followUpId, String resolution, Boolean isConfirmed) {
        try {
            Bulk_Buy_Follow_Up__c fu = [
                SELECT Id, Status__c, Reservation__c, Reported_User__c, Checkin_Conversation__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Id = :followUpId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (fu.Status__c != FimbyConstants.FOLLOWUP_ESCALATED) {
                throw new AuraHandledException('Only escalated follow-ups can be admin-resolved.');
            }

            fu.Resolution_Date__c = System.now();
            fu.Resolved_By__c = UserInfo.getUserId();
            fu.Resolution_Notes__c = resolution;

            if (isConfirmed) {
                fu.Status__c = FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED;
                Response__c resp = new Response__c(
                    Id = fu.Reservation__c,
                    Status__c = FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH
                );
                new FollowUpHelper().updateResponse(resp);

                if (fu.Checkin_Conversation__c != null) {
                    FimbyGroupConversationController.sendSystemMessage(
                        fu.Checkin_Conversation__c,
                        'Recorded by admin after review.',
                        FimbyConstants.SYS_MSG_STATUS_CHANGE
                    );
                }
            } else {
                fu.Status__c = FimbyConstants.FOLLOWUP_ADMIN_CLEARED;
                if (fu.Checkin_Conversation__c != null) {
                    FimbyGroupConversationController.sendSystemMessage(
                        fu.Checkin_Conversation__c,
                        'Cleared by admin after review.',
                        FimbyConstants.SYS_MSG_STATUS_CHANGE
                    );
                }
            }

            new FollowUpHelper().updateFollowUp(fu);

            FimbyBulkBuyController.recalculateBlockedFlagsForContacts(new Set<Id>{ fu.Reported_User__c });

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'adminResolveFollowUp', e);
            throw buildAuraException('Error resolving: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> adminRestoreEligibility(Id contactId, String restorationNotes, String followThroughPlan) {
        try {
            Id restorationRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
                .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_RESTORATION)?.getRecordTypeId();

            // Find the 3 follow-ups that caused the block
            Id bulkBuyRtId = Schema.SObjectType.Needs_Offers__c
                .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY)?.getRecordTypeId();

            List<Response__c> last3 = [
                SELECT Id, (SELECT Id FROM Follow_Ups__r WHERE Status__c IN (:FimbyConstants.FOLLOWUP_NO_RESPONSE, :FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED) ORDER BY Reported_Date__c DESC LIMIT 1)
                FROM Response__c
                WHERE Contact__c = :contactId
                AND Need_Offer_Responded_To__r.RecordTypeId = :bulkBuyRtId
                AND Status__c = :FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH
                ORDER BY CreatedDate DESC
                LIMIT 3
            ];

            List<String> linkedIds = new List<String>();
            for (Response__c r : last3) {
                for (Bulk_Buy_Follow_Up__c fu : r.Follow_Ups__r) {
                    linkedIds.add(fu.Id);
                }
            }

            Bulk_Buy_Follow_Up__c restoration = new Bulk_Buy_Follow_Up__c(
                RecordTypeId = restorationRtId,
                Reported_User__c = contactId,
                Status__c = FimbyConstants.FOLLOWUP_PROBATIONARY_RESTORED,
                Resolution_Date__c = System.now(),
                Resolved_By__c = UserInfo.getUserId(),
                Restoration_Notes__c = restorationNotes,
                Follow_Through_Plan__c = followThroughPlan,
                Linked_Follow_Ups__c = String.join(linkedIds, ',')
            );
            new FollowUpHelper().insertFollowUp(restoration);

            FimbyBulkBuyController.recalculateBlockedFlagsForContacts(new Set<Id>{ contactId });

            return new Map<String, Object>{ 'success' => true, 'restorationId' => restoration.Id };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'adminRestoreEligibility', e);
            throw buildAuraException('Error restoring eligibility: ' + e.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    private without sharing class FollowUpHelper {

        public List<Response__c> getResponseForReport(Id reservationId) {
            return [
                SELECT Id, Contact__c, Need_Offer_Responded_To__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Contact__c,
                       Need_Offer_Responded_To__r.Pickup_Notified_Date__c,
                       Need_Offer_Responded_To__r.Status__c,
                       Need_Offer_Responded_To__r.Name,
                       Contact__r.FirstName
                FROM Response__c
                WHERE Id = :reservationId
                LIMIT 1
            ];
        }

        public Integer countNewerOutcomesSince(Id contactId, Id bulkBuyRtId, Datetime sinceDate) {
            return [
                SELECT COUNT() FROM Response__c
                WHERE Contact__c = :contactId
                AND Need_Offer_Responded_To__r.RecordTypeId = :bulkBuyRtId
                AND Status__c IN (:FimbyConstants.RESPONSE_COMPLETED, :FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH)
                AND CreatedDate > :sinceDate
            ];
        }

        public List<Response__c> getOutcomeResponsesForHistory(Id contactId, Id bulkBuyRtId, Integer limitCount) {
            return [
                SELECT Status__c, CreatedDate FROM Response__c
                WHERE Contact__c = :contactId
                AND Need_Offer_Responded_To__r.RecordTypeId = :bulkBuyRtId
                AND Status__c IN (:FimbyConstants.RESPONSE_COMPLETED, :FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH)
                ORDER BY CreatedDate DESC
                LIMIT :limitCount
            ];
        }

        public Map<String, Object> doReport(Response__c resp, Id reporterContactId, String message, String reasonSubtype) {
            Conversation__c dmConv = new Conversation__c(
                Context_Type__c = FimbyConstants.CTX_MISSED_PICKUP,
                Related_Record_Id__c = resp.Need_Offer_Responded_To__c,
                Status__c = FimbyConstants.CONVERSATION_ACTIVE,
                Participant_1__c = reporterContactId,
                Participant_2__c = resp.Contact__c
            );
            insert dmConv;

            String reasonLabel = getReasonLabel(reasonSubtype);
            Message__c sysMsg = new Message__c(
                Conversation__c = dmConv.Id,
                Body__c = 'This check-in is about a ' + reasonLabel + ' for ' + resp.Need_Offer_Responded_To__r.Name,
                Sent_Date__c = System.now(),
                Status__c = FimbyConstants.MESSAGE_SENT,
                Is_System_Message__c = true,
                System_Message_Type__c = FimbyConstants.SYS_MSG_NOT_RESPONDING_FLAG
            );
            insert sysMsg;

            Message__c posterMsg = new Message__c(
                Conversation__c = dmConv.Id,
                Sender__c = reporterContactId,
                Sent_By__c = reporterContactId,
                Body__c = message,
                Sent_Date__c = System.now(),
                Status__c = FimbyConstants.MESSAGE_SENT,
                Is_System_Message__c = false
            );
            insert posterMsg;

            Id followUpRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
                .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_FOLLOW_UP)?.getRecordTypeId();

            Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
                RecordTypeId = followUpRtId,
                Bulk_Buy__c = resp.Need_Offer_Responded_To__c,
                Reservation__c = resp.Id,
                Reporter__c = reporterContactId,
                Reported_User__c = resp.Contact__c,
                Status__c = FimbyConstants.FOLLOWUP_PENDING,
                Reason_Subtype__c = reasonSubtype,
                Report_Message__c = message,
                Reported_Date__c = System.now(),
                Checkin_Conversation__c = dmConv.Id
            );
            insert fu;

            String reporterFirstName = [SELECT FirstName FROM Contact WHERE Id = :reporterContactId].FirstName;
            FimbyNotificationService.createNotification(
                resp.Contact__c,
                FimbyConstants.NOTIF_NOT_RESPONDING_FLAG,
                reporterFirstName + ' would like to check in',
                'About "' + resp.Need_Offer_Responded_To__r.Name + '".',
                dmConv.Id,
                'Conversation__c',
                FimbySettings.getUrl('Conversation', String.valueOf(dmConv.Id)),
                reporterFirstName
            );

            return new Map<String, Object>{
                'success' => true,
                'followUpId' => fu.Id,
                'conversationId' => dmConv.Id
            };
        }

        public void updateFollowUp(Bulk_Buy_Follow_Up__c fu) { update fu; }
        public void insertFollowUp(Bulk_Buy_Follow_Up__c fu) { insert fu; }
        public void updateResponse(Response__c resp) { update resp; }

        private String getReasonLabel(String subtype) {
            Map<String, String> labels = new Map<String, String>{
                'Missed_Pickup_Window' => 'missed pickup',
                'Stopped_Replying' => 'stopped replying',
                'Payment_Not_Settled' => 'payment not yet settled',
                'Other' => 'something else'
            };
            return labels.containsKey(subtype) ? labels.get(subtype) : 'follow-up';
        }
    }
}
