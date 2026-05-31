/**
 * @description Account-deletion controller for the Email-to-Case flow.
 * Exposes an InvocableMethod (so a Flow can fire it if the org ever moves
 * intake/confirmation back to Flows), plus a public Apex entry-point used
 * by FimbyDeletionExpiryBatch when the 24-hour safeguard elapses.
 *
 * Two-stage retention is intentional:
 *   - User.IsActive is flipped immediately by FimbyDeactivateUserQueueable —
 *     login is revoked the moment the safeguard expires.
 *   - Contact + content cleanup (anonymize Contact, delete posts/stories/
 *     library items, 90-day Feedback hold, etc.) is the responsibility of
 *     FimbyAccountDeactivationBatch, which picks up Contacts flagged here.
 *
 * The active-loan hold rule is implemented in FimbyAccountDeactivationBatch.
 * The user is still locked out at confirmation time; only the data scrub
 * waits for open lending to resolve.
 */
public without sharing class FimbyDeletionController {

    @TestVisible
    private static Boolean testEnqueueCalled = false;
    @TestVisible
    private static List<Id> testEnqueuedUserIds = new List<Id>();

    /**
     * @description Invocable wrapper used by Flow. Same semantics as
     * enqueue(List<Id>) — given a list of confirmed deletion Case Ids,
     * flag the Contact and enqueue user deactivation.
     */
    @InvocableMethod(label='Enqueue FIMBY Account Deletion' description='Flags the Contact for deactivation and enqueues user-record deactivation. Driven by the EmailMessage-trigger confirmation handler after the 24-hour safeguard.')
    public static void enqueueDeletion(List<Id> caseIds) {
        enqueue(caseIds);
    }

    /**
     * @description Core enqueue logic. Updates each Case to Completed, sets
     * Deletion_Enqueued_Date__c, flags the Contact for the retention batch,
     * sends the completion email (last user-visible communication), then
     * enqueues FimbyDeactivateUserQueueable per user.
     * @param caseIds Cases whose 24-hour safeguard has elapsed (or which
     *                bypassed the safeguard via direct invocation in test).
     */
    public static void enqueue(List<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        Map<Id, Case> caseById = new Map<Id, Case>([
            SELECT Id, ContactId, Contact_User_Id__c,
                   Deletion_Stage__c, Deletion_Enqueued_Date__c
            FROM Case
            WHERE Id IN :caseIds
            LIMIT 200
        ]);
        if (caseById.isEmpty()) return;

        List<Contact> contactsToFlag = new List<Contact>();
        List<Case> casesToUpdate = new List<Case>();
        DateTime nowUtc = System.now();

        for (Case c : caseById.values()) {
            if (c.ContactId != null) {
                contactsToFlag.add(new Contact(
                    Id = c.ContactId,
                    Deactivation_Requested__c = true
                ));
            }
            c.Deletion_Stage__c = 'Completed';
            c.Deletion_Enqueued_Date__c = nowUtc;
            c.Status = 'Closed';
            casesToUpdate.add(c);
        }

        if (!contactsToFlag.isEmpty()) {
            Database.update(contactsToFlag, false);
        }
        if (!casesToUpdate.isEmpty()) {
            Database.update(casesToUpdate, false);
        }

        for (Case c : caseById.values()) {
            if (String.isBlank(c.Contact_User_Id__c)) {
                FimbyLogger.warn('FimbyDeletionController', 'enqueue',
                    'Case ' + c.Id + ' has no Contact_User_Id__c — skipping user deactivation enqueue');
                continue;
            }
            Id userId;
            try {
                userId = (Id) c.Contact_User_Id__c;
            } catch (Exception e) {
                FimbyLogger.warn('FimbyDeletionController', 'enqueue',
                    'Invalid Contact_User_Id__c on Case ' + c.Id + ': ' + c.Contact_User_Id__c);
                continue;
            }

            FimbyDeletionEmailService.sendCompletion(c.Id, userId);

            if (Test.isRunningTest()) {
                testEnqueueCalled = true;
                testEnqueuedUserIds.add(userId);
                continue;
            }
            System.enqueueJob(new FimbyDeactivateUserQueueable(userId));
        }
    }
}
