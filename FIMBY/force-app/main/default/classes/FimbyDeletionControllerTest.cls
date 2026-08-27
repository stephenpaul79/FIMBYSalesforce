/**
 * @description Omnibus test for the Email-to-Case account-deletion flow.
 * Covers the 7 scenarios from the Salesforce Deletion Flow plan:
 *   1. Deletion-keyword Case is created and matched to a Contact (intake).
 *   2. Verification email is captured for that user.
 *   3. CONFIRM DELETE reply moves Case to Confirmed and the safeguard
 *      batch enqueues FimbyDeactivateUserQueueable.
 *   4. Completion email is sent before user deactivation commits.
 *   5. Sender not matched to a Contact -> Cancelled + no-account auto-reply.
 *   6. CONFIRM DELETE on a Case not in Awaiting Confirmation is a no-op.
 *   7. Case sitting past 7 days is expired by the scheduled batch.
 * Plus extras: invocable wrapper, CANCEL reply, rate-limit detection,
 * rate-limit-flagged Case ignores CONFIRM DELETE.
 *
 * Named FimbyDeletionControllerTest because the Salesforce Deletion Flow
 * plan calls out --tests FimbyDeletionControllerTest in the deploy step.
 */
@IsTest
private class FimbyDeletionControllerTest {

    private static Id getDeletionRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> infos =
            Case.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get('Account_Deletion');
        return info == null ? null : info.getRecordTypeId();
    }

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    /**
     * Excludes parent-managed profiles so the verification-email tests below, which add
     * child Contacts, cannot change what this unordered lookup returns.
     */
    private static Contact getContact() {
        return [
            SELECT Id, Email, AccountId FROM Contact
            WHERE Is_Parent_Proxied__c = false LIMIT 1
        ];
    }

    private static User getCommunityUser() {
        return [SELECT Id, Email, ContactId FROM User WHERE ContactId != null LIMIT 1];
    }

    private static Case insertDeletionCase(Id contactId, String suppliedEmail, String subject) {
        Id rtId = getDeletionRecordTypeId();
        Case c = new Case(
            RecordTypeId = rtId,
            ContactId = contactId,
            SuppliedEmail = suppliedEmail,
            Subject = subject,
            Status = 'New',
            Origin = 'Email'
        );
        insert c;
        return c;
    }

    private static EmailMessage insertInboundReply(Id caseId, String body) {
        EmailMessage em = new EmailMessage(
            ParentId = caseId,
            Incoming = true,
            Subject = 'Re: [FIMBY] Please confirm your account deletion',
            TextBody = body,
            MessageDate = System.now(),
            Status = '0'
        );
        insert em;
        return em;
    }

    /* ---------- 1. Intake creates Case + 2. verification email sent ---------- */

    @IsTest
    static void intakeMatchedContactSendsVerification() {
        Contact contact = getContact();
        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();

        Test.startTest();
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        Test.stopTest();

        Case after = [
            SELECT Deletion_Stage__c, Confirmation_Sent_Date__c,
                   Contact_User_Id__c, Deletion_Rate_Limit_Flagged__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Awaiting Confirmation', after.Deletion_Stage__c);
        System.assertNotEquals(null, after.Confirmation_Sent_Date__c);
        System.assertNotEquals(null, after.Contact_User_Id__c,
            'Contact_User_Id__c should be resolved at intake');
        System.assertEquals(false, after.Deletion_Rate_Limit_Flagged__c);
        System.assertEquals(1, FimbyDeletionEmailService.testEmailsSent,
            'Verification email should fire exactly once');
    }

    /* ---------- 3. CONFIRM DELETE reply + 4. safeguard enqueue + completion email ---------- */

    @IsTest
    static void confirmDeleteReplyTransitionsToConfirmedThenSafeguardEnqueues() {
        Contact contact = getContact();
        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionController.testEnqueueCalled = false;
        FimbyDeletionController.testEnqueuedUserIds = new List<Id>();

        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');

        Test.startTest();
        insertInboundReply(c.Id, 'Yes, please CONFIRM DELETE my account.');
        Test.stopTest();

        Case afterReply = [
            SELECT Deletion_Stage__c, Confirmation_Received_Date__c,
                   Safeguard_Enqueue_After__c, Contact_User_Id__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Confirmed', afterReply.Deletion_Stage__c);
        System.assertNotEquals(null, afterReply.Confirmation_Received_Date__c);
        System.assertNotEquals(null, afterReply.Safeguard_Enqueue_After__c);
        System.assert(afterReply.Safeguard_Enqueue_After__c > System.now(),
            'Safeguard should be 24h in the future');

        update new Case(
            Id = c.Id,
            Safeguard_Enqueue_After__c = System.now().addMinutes(-1)
        );

        FimbyDeletionExpiryBatch.run();

        Case afterEnqueue = [
            SELECT Deletion_Stage__c, Deletion_Enqueued_Date__c, Status
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Completed', afterEnqueue.Deletion_Stage__c);
        System.assertNotEquals(null, afterEnqueue.Deletion_Enqueued_Date__c);
        System.assertEquals('Closed', afterEnqueue.Status);

        Contact flagged = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contact.Id];
        System.assertEquals(true, flagged.Deactivation_Requested__c,
            'Contact should be flagged for the retention batch');

        System.assertEquals(true, FimbyDeletionController.testEnqueueCalled,
            'enqueue path should fire');
        System.assertEquals(1, FimbyDeletionController.testEnqueuedUserIds.size(),
            'One user-deactivation enqueue per Case');
    }

    /* ---------- 5. Sender not matched ---------- */

    @IsTest
    static void unmatchedSenderClosesCaseAndSendsNoAccountReply() {
        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();

        Test.startTest();
        Case c = insertDeletionCase(null, 'stranger@example.com', 'Delete my account');
        Test.stopTest();

        Case after = [SELECT Deletion_Stage__c, Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Cancelled', after.Deletion_Stage__c);
        System.assertEquals('Closed', after.Status);
        System.assertEquals(1, FimbyDeletionEmailService.testEmailsSent,
            'No-account auto-reply should fire');
    }

    /* ---------- 5b. Contact matched but no active User ---------- */

    @IsTest
    static void contactWithoutActiveUserClosesCase() {
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact orphan = FimbyTestDataFactory.createNeighbourhoodContact(
            neighbourhood.Id, true);

        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();

        Test.startTest();
        Case c = insertDeletionCase(orphan.Id, orphan.Email, 'Delete my account');
        Test.stopTest();

        Case after = [SELECT Deletion_Stage__c, Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Cancelled', after.Deletion_Stage__c);
        System.assertEquals('Closed', after.Status);
    }

    /* ---------- 6. CONFIRM DELETE on a Case not in Awaiting Confirmation ---------- */

    @IsTest
    static void confirmReplyOnCancelledCaseIsNoop() {
        Contact contact = getContact();
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        update new Case(Id = c.Id, Deletion_Stage__c = 'Cancelled', Status = 'Closed');

        Test.startTest();
        insertInboundReply(c.Id, 'CONFIRM DELETE');
        Test.stopTest();

        Case after = [
            SELECT Deletion_Stage__c, Confirmation_Received_Date__c,
                   Safeguard_Enqueue_After__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Cancelled', after.Deletion_Stage__c,
            'Stage should not move from Cancelled');
        System.assertEquals(null, after.Confirmation_Received_Date__c);
        System.assertEquals(null, after.Safeguard_Enqueue_After__c);
    }

    /* ---------- 7. 7-day expiry pass ---------- */

    @IsTest
    static void staleAwaitingCaseIsExpiredByBatch() {
        Contact contact = getContact();
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');

        update new Case(
            Id = c.Id,
            Confirmation_Sent_Date__c = System.now().addDays(-8)
        );

        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();

        Test.startTest();
        FimbyDeletionExpiryBatch.run();
        Test.stopTest();

        Case after = [SELECT Deletion_Stage__c, Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Expired', after.Deletion_Stage__c);
        System.assertEquals('Closed', after.Status);
        System.assert(FimbyDeletionEmailService.testEmailsSent >= 1,
            'Cancellation email should fire on expiry');
    }

    /* ---------- CANCEL reply ---------- */

    @IsTest
    static void cancelReplyClosesCaseAndSendsCancellationEmail() {
        Contact contact = getContact();
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');

        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();

        Test.startTest();
        insertInboundReply(c.Id, 'I changed my mind. CANCEL.');
        Test.stopTest();

        Case after = [SELECT Deletion_Stage__c, Status FROM Case WHERE Id = :c.Id];
        System.assertEquals('Cancelled', after.Deletion_Stage__c);
        System.assertEquals('Closed', after.Status);
        System.assertEquals(1, FimbyDeletionEmailService.testEmailsSent,
            'Cancellation email should fire');
    }

    /* ---------- Rate-limit detection ---------- */

    @IsTest
    static void rateLimitFlagsExcessCases() {
        Contact contact = getContact();
        Id rtId = getDeletionRecordTypeId();

        List<Case> burst = new List<Case>();
        for (Integer i = 0; i < 4; i++) {
            burst.add(new Case(
                RecordTypeId = rtId,
                ContactId = contact.Id,
                SuppliedEmail = contact.Email,
                Subject = 'Delete my account ' + i,
                Status = 'New',
                Origin = 'Email'
            ));
        }
        Test.startTest();
        insert burst;
        Test.stopTest();

        List<Case> flagged = [
            SELECT Id, Deletion_Rate_Limit_Flagged__c
            FROM Case
            WHERE Id IN :burst AND Deletion_Rate_Limit_Flagged__c = true
        ];
        System.assert(flagged.size() >= 1,
            'At least the over-limit Case should be flagged at intake');

        FimbyDeletionExpiryBatch.run();

        List<Case> allFlaggedAfterBatch = [
            SELECT Id FROM Case
            WHERE Id IN :burst AND Deletion_Rate_Limit_Flagged__c = true
        ];
        System.assertEquals(burst.size(), allFlaggedAfterBatch.size(),
            'Backstop batch should flag the entire burst');
    }

    @IsTest
    static void confirmReplyOnRateLimitFlaggedCaseIsIgnored() {
        Contact contact = getContact();
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        update new Case(Id = c.Id, Deletion_Rate_Limit_Flagged__c = true);

        Test.startTest();
        insertInboundReply(c.Id, 'CONFIRM DELETE');
        Test.stopTest();

        Case after = [
            SELECT Deletion_Stage__c, Safeguard_Enqueue_After__c
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Awaiting Confirmation', after.Deletion_Stage__c,
            'Rate-limit-flagged Cases must not auto-confirm');
        System.assertEquals(null, after.Safeguard_Enqueue_After__c);
    }

    /* ---------- Invocable wrapper for Flow compatibility ---------- */

    @IsTest
    static void invocableEnqueueDeletionUpdatesCaseAndContact() {
        Contact contact = getContact();
        User u = getCommunityUser();
        Id rtId = getDeletionRecordTypeId();

        Case c = new Case(
            RecordTypeId = rtId,
            ContactId = contact.Id,
            SuppliedEmail = contact.Email,
            Status = 'New',
            Origin = 'Email',
            Deletion_Stage__c = 'Confirmed',
            Contact_User_Id__c = u.Id
        );
        insert c;

        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionController.testEnqueueCalled = false;

        Test.startTest();
        FimbyDeletionController.enqueueDeletion(new List<Id>{ c.Id });
        Test.stopTest();

        Case after = [
            SELECT Deletion_Stage__c, Deletion_Enqueued_Date__c, Status
            FROM Case WHERE Id = :c.Id
        ];
        System.assertEquals('Completed', after.Deletion_Stage__c);
        System.assertNotEquals(null, after.Deletion_Enqueued_Date__c);

        Contact afterContact = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contact.Id];
        System.assertEquals(true, afterContact.Deactivation_Requested__c);

        System.assertEquals(true, FimbyDeletionController.testEnqueueCalled);
        System.assertEquals(1, FimbyDeletionEmailService.testEmailsSent,
            'Completion email should be sent');
    }

    /* ---------- Schedulable wrapper ---------- */

    @IsTest
    static void schedulableExecuteRunsAllPasses() {
        Test.startTest();
        String cron = '0 0 0 1 1 ? 2099';
        System.schedule('FIMBY Deletion Expiry Test',
            cron, new FimbyDeletionExpiryBatch());
        Test.stopTest();
    }

    /* ---------- Email service direct paths (coverage) ---------- */

    @IsTest
    static void emailServiceHandlesNullsGracefully() {
        FimbyDeletionEmailService.sendVerification(null, null);
        FimbyDeletionEmailService.sendCancellation(null, null);
        FimbyDeletionEmailService.sendCompletion(null, null);
        FimbyDeletionEmailService.sendNoActiveAccount(null, null);
    }

    /* ---------- Verification email: parent-managed profile warning ---------- */

    private static Contact makeManagedChild(Id nhId, Id displayParentId, String firstName) {
        Contact child = new Contact(
            FirstName = firstName,
            LastName = 'Household',
            AccountId = nhId,
            Birthdate = Date.today().addYears(-12),
            Is_Parent_Proxied__c = true,
            Proxied_By_Contact__c = displayParentId
        );
        insert child;
        return child;
    }

    private static void guardianMandate(Id nhId, Id guardianId, Id childId) {
        insert new Support_Relationship__c(
            Contact__c = guardianId,
            Related_Contact__c = childId,
            Status__c = 'Approved',
            Relationship_Type__c = 'Parent_Guardian',
            Consent_Method__c = 'Guardian',
            Neighbourhood__c = nhId
        );
    }

    private static String capturedVerificationBody() {
        System.assert(!FimbyDeletionEmailService.testCapturedEmails.isEmpty(),
            'The verification email should have been captured');
        return FimbyDeletionEmailService.testCapturedEmails[0].getPlainTextBody();
    }

    private static void resetEmailCapture() {
        FimbyDeletionEmailService.testEmailsSent = 0;
        FimbyDeletionEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();
    }

    /**
     * The Settings flow warns on screen before you confirm. This path has no screen at
     * all, so the verification email is the last moment a last guardian can still reply
     * CANCEL and keep both profiles.
     */
    @IsTest
    static void verificationEmailNamesAnAtRiskManagedProfile() {
        Contact contact = getContact();
        User u = getCommunityUser();
        Account nh = [SELECT Id FROM Account WHERE Id = :contact.AccountId LIMIT 1];
        // The mandate must hang off the User's own Contact: that is the Contact the
        // email service resolves from userId.
        Contact child = makeManagedChild(nh.Id, u.ContactId, 'Maya');
        guardianMandate(nh.Id, u.ContactId, child.Id);

        System.assertEquals(1,
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(u.ContactId).size(),
            'Fixture check: the User\u2019s Contact must be the last guardian');

        // Case insert fires its own intake verification; reset after it so the capture
        // below holds only the email this test asked for.
        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        resetEmailCapture();

        Test.startTest();
        FimbyDeletionEmailService.sendVerification(c.Id, u.Id);
        Test.stopTest();

        String body = capturedVerificationBody();
        System.assert(body.contains('Maya'),
            'The warning must name the young person, not hint at a consequence');
        System.assert(body.contains('last'),
            'The email should say the neighbour is the last approved guardian');
        System.assert(body.contains('CONFIRM DELETE'),
            'The protocol tokens must survive the insertion');
        System.assert(body.contains('CANCEL'),
            'The way out has to stay visible alongside the new warning');
    }

    @IsTest
    static void verificationEmailStaysSilentWhenACoGuardianRemains() {
        Contact contact = getContact();
        User u = getCommunityUser();
        Account nh = [SELECT Id FROM Account WHERE Id = :contact.AccountId LIMIT 1];
        Contact coGuardian = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact child = makeManagedChild(nh.Id, u.ContactId, 'Maya');
        guardianMandate(nh.Id, u.ContactId, child.Id);
        guardianMandate(nh.Id, coGuardian.Id, child.Id);

        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        resetEmailCapture();

        Test.startTest();
        FimbyDeletionEmailService.sendVerification(c.Id, u.Id);
        Test.stopTest();

        System.assert(!capturedVerificationBody().contains('Maya'),
            'The profile carries on with the other guardian, so there is nothing to say');
    }

    /**
     * Confirmation parsing depends on this body, so a neighbour who looks after nobody
     * must receive it byte-for-byte unchanged.
     */
    @IsTest
    static void verificationEmailIsUnchangedForANonGuardian() {
        Contact contact = getContact();
        User u = getCommunityUser();

        Case c = insertDeletionCase(contact.Id, contact.Email, 'Delete my account');
        resetEmailCapture();

        Test.startTest();
        FimbyDeletionEmailService.sendVerification(c.Id, u.Id);
        Test.stopTest();

        String body = capturedVerificationBody();
        System.assert(
            body.contains('Either way, nothing will change unless we hear '
                + '"CONFIRM DELETE" from this address.\n\nOnce you confirm, we wait '
                + '24 more hours'),
            'With nothing at risk the two paragraphs must remain adjacent and unreflowed'
        );
        System.assert(!body.contains('parent-managed'),
            'No warning for someone who looks after nobody');
    }

    @IsTest
    static void noopOnEmptyLists() {
        FimbyDeletionController.enqueue(new List<Id>());
        FimbyDeletionIntakeService.process(new List<Id>());
        FimbyDeletionConfirmationService.process(
            new List<EmailMessage>(),
            new Map<Id, Case>()
        );
    }

    /* ---------- Before-insert: stamps Account_Deletion RT on subject match ---------- */

    @IsTest
    static void beforeInsertStampsDeletionRecordTypeOnEmailKeywordMatch() {
        Contact contact = getContact();
        Id deletionRtId = getDeletionRecordTypeId();

        Case c1 = new Case(
            ContactId = contact.Id,
            SuppliedEmail = contact.Email,
            Subject = 'Please delete my account',
            Status = 'New',
            Origin = 'Email'
        );
        Case c2 = new Case(
            ContactId = contact.Id,
            SuppliedEmail = contact.Email,
            Subject = 'CLOSE MY ACCOUNT please',
            Status = 'New',
            Origin = 'Email'
        );
        Case c3 = new Case(
            ContactId = contact.Id,
            Subject = 'How do I add a library item?',
            Status = 'New',
            Origin = 'Email'
        );
        Case c4 = new Case(
            ContactId = contact.Id,
            Subject = 'delete my account',
            Status = 'New',
            Origin = 'Web'
        );

        Test.startTest();
        insert new List<Case>{ c1, c2, c3, c4 };
        Test.stopTest();

        Map<Id, Case> after = new Map<Id, Case>([
            SELECT Id, RecordTypeId FROM Case
            WHERE Id IN :new List<Id>{ c1.Id, c2.Id, c3.Id, c4.Id }
        ]);
        System.assertEquals(deletionRtId, after.get(c1.Id).RecordTypeId,
            'Email subject "delete my account" should stamp Account_Deletion');
        System.assertEquals(deletionRtId, after.get(c2.Id).RecordTypeId,
            'Email subject "close my account" should stamp Account_Deletion (case-insensitive)');
        System.assertNotEquals(deletionRtId, after.get(c3.Id).RecordTypeId,
            'Unrelated email subject should not be stamped');
        System.assertNotEquals(deletionRtId, after.get(c4.Id).RecordTypeId,
            'Non-Email Origin should not be stamped (only Email-to-Case is in scope)');
    }
}
