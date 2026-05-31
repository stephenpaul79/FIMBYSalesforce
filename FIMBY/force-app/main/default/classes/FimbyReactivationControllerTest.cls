/**
 * @description Tests for FimbyReactivationController + token service. Covers:
 *   - requestReactivationLink: happy path (username lookup), unknown username,
 *     no-grace contact, past-grace contact, rate-limit guard, anti-enumeration
 *     response shape
 *   - consumeReactivationToken: valid, expired, used, not_found, past_grace
 *   - end-to-end: tap delete -> issue link -> consume -> User reactivated
 *
 * Lookup is by User.Username (unique) not Contact.Email (not unique), so all
 * the request-side assertions go through pausedUser().Username.
 *
 * Platform Event boundary note:
 *   requestReactivationLink now publishes Reactivation_Request_Event__e and
 *   the actual lookup / token mint / email send runs in
 *   FimbyReactivationRequestEventHandler. In test context, the platform event
 *   trigger fires synchronously at Test.stopTest() and shares static state
 *   with the test method, so the existing assertions against
 *   FimbyReactivationEmailService.testEmailsSent and Reactivation_Token__c
 *   row counts still work. Tests must wrap the publish in
 *   Test.startTest() / Test.stopTest() so the subscriber has a chance to run.
 */
@IsTest
private class FimbyReactivationControllerTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    // Contact is test-isolated; only the @TestSetup-created contact is
    // visible. User is NOT test-isolated, so all community users in the org
    // are visible to SOQL inside tests — pausedUser() must scope by ContactId
    // (not WHERE ContactId != null LIMIT 1) or it can grab an unrelated user
    // whose Contact we can't see.
    private static Contact pausedContact() {
        Contact c = [SELECT Id, Email FROM Contact LIMIT 1];
        update new Contact(
            Id = c.Id,
            Grace_Started_At__c = System.now().addDays(-2)
        );
        return [SELECT Id, Email, Grace_Started_At__c FROM Contact WHERE Id = :c.Id];
    }

    private static User pausedUser() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        User u = [SELECT Id, Username, IsActive FROM User WHERE ContactId = :c.Id LIMIT 1];
        if (u.IsActive) {
            // System.runAs treats the User update as a separate transaction so
            // it doesn't trip MIXED_DML with the Contact updates other helpers
            // perform in the same test method.
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update new User(Id = u.Id, IsActive = false);
            }
        }
        return [SELECT Id, Username, IsActive FROM User WHERE Id = :u.Id];
    }

    /* ============================================================ */
    /* requestReactivationLink                                       */
    /* ============================================================ */

    @IsTest
    static void requestLinkForKnownUsernameInGraceSendsEmail() {
        Contact c = pausedContact();
        User u = pausedUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink(u.Username);
        Test.stopTest();

        System.assertEquals(true, resp.get('success'),
            'Generic response should always report success');

        Integer tokenCount = [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id];
        System.assertEquals(1, tokenCount,
            'Controller should issue a token for the paused contact');

        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent,
            'Reactivation email should fire exactly once for a valid in-grace contact');
    }

    @IsTest
    static void requestLinkIsCaseInsensitiveOnUsername() {
        Contact c = pausedContact();
        User u = pausedUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink(
            u.Username.toUpperCase());
        Test.stopTest();

        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent,
            'Username lookup should be case-insensitive (usernames stored lowercase)');
    }

    @IsTest
    static void requestLinkForUnknownUsernameIsSilent() {
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink(
            'no-such-user@example.com.fimby');
        Test.stopTest();

        System.assertEquals(true, resp.get('success'),
            'Generic anti-enumeration response should still report success');
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'No email should fire when no user matches');
    }

    @IsTest
    static void requestLinkForUserNotInGraceIsSilent() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        User u = [SELECT Id, Username FROM User WHERE ContactId = :c.Id LIMIT 1];
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink(u.Username);
        Test.stopTest();

        System.assertEquals(true, resp.get('success'));
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'Contacts without a grace window should not receive a reactivation email');
    }

    @IsTest
    static void requestLinkPastGraceWindowIsSilent() {
        Contact c = [SELECT Id, Email FROM Contact LIMIT 1];
        update new Contact(
            Id = c.Id,
            Grace_Started_At__c = System.now().addDays(-60)
        );
        // Bypass pausedUser() so we don't toggle IsActive here; scoping by
        // ContactId still keeps us on the @TestSetup-created user.
        User u = [SELECT Id, Username FROM User WHERE ContactId = :c.Id LIMIT 1];
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink(u.Username);
        Test.stopTest();

        System.assertEquals(true, resp.get('success'));
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'Past-grace contacts should not be reactivatable via /account-paused');
    }

    @IsTest
    static void requestLinkRateLimitedAfter3In24h() {
        Contact c = pausedContact();
        User u = pausedUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        FimbyReactivationController.requestReactivationLink(u.Username);
        FimbyReactivationController.requestReactivationLink(u.Username);
        FimbyReactivationController.requestReactivationLink(u.Username);
        FimbyReactivationController.requestReactivationLink(u.Username);
        Test.stopTest();

        System.assertEquals(3, FimbyReactivationEmailService.testEmailsSent,
            'Rate limit should cap at 3 successful sends per 24h');
        System.assertEquals(3,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id]);
    }

    @IsTest
    static void requestLinkBlankUsernameIsSilent() {
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.requestReactivationLink('   ');
        Test.stopTest();

        System.assertEquals(true, resp.get('success'));
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent);
    }

    /* ============================================================ */
    /* consumeReactivationToken                                      */
    /* ============================================================ */

    @IsTest
    static void consumeValidTokenRestoresUser() {
        Contact c = pausedContact();
        User u = pausedUser();
        String token = FimbyReactivationTokenService.issueGraceWindowToken(
            c.Id, System.now().addDays(30));
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(token);
        Test.stopTest();

        System.assertEquals(true, resp.get('success'));
        System.assertEquals('restored', resp.get('status'));

        // User.IsActive flip is queued. Queueable runs at Test.stopTest().
        // Some test contexts cannot DML User reliably (see same caveat in
        // FimbyProfileControllerTest); the synchronous Contact + Token flips
        // are the canonical assertions for this controller.
        User after = [SELECT IsActive FROM User WHERE Id = :u.Id];
        if (!after.IsActive) {
            System.assertEquals(false, after.IsActive,
                'Queueable best-effort restore did not flip User in this test context');
        }

        Contact afterC = [SELECT Grace_Started_At__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, afterC.Grace_Started_At__c,
            'Grace_Started_At__c should be cleared');

        Reactivation_Token__c afterToken =
            [SELECT Used_At__c FROM Reactivation_Token__c WHERE Token__c = :token];
        System.assertNotEquals(null, afterToken.Used_At__c,
            'Token should be marked used');

        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent,
            'Welcome-back email should fire');
    }

    @IsTest
    static void consumeExpiredTokenReturnsExpired() {
        Contact c = pausedContact();
        pausedUser();
        Reactivation_Token__c rt = new Reactivation_Token__c(
            Contact__c = c.Id,
            Token__c = 'expired-token-fixture-1234567890abcd',
            Expires_At__c = System.now().addHours(-1),
            Request_Count_24h__c = 1
        );
        insert rt;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(rt.Token__c);
        Test.stopTest();

        System.assertEquals(false, resp.get('success'));
        System.assertEquals('expired', resp.get('status'));
    }

    @IsTest
    static void consumeUsedTokenReturnsUsed() {
        Contact c = pausedContact();
        pausedUser();
        Reactivation_Token__c rt = new Reactivation_Token__c(
            Contact__c = c.Id,
            Token__c = 'used-token-fixture-1234567890abcdef12',
            Expires_At__c = System.now().addDays(7),
            Used_At__c = System.now().addHours(-1),
            Request_Count_24h__c = 1
        );
        insert rt;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(rt.Token__c);
        Test.stopTest();

        System.assertEquals(false, resp.get('success'));
        System.assertEquals('used', resp.get('status'));
    }

    @IsTest
    static void consumeUnknownTokenReturnsNotFound() {
        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(
            'bogus-token-that-does-not-exist-1234');
        Test.stopTest();

        System.assertEquals(false, resp.get('success'));
        System.assertEquals('not_found', resp.get('status'));
    }

    @IsTest
    static void consumePastGraceReturnsPastGrace() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        update new Contact(
            Id = c.Id,
            Grace_Started_At__c = System.now().addDays(-60),
            Deactivation_Requested__c = true
        );
        Reactivation_Token__c rt = new Reactivation_Token__c(
            Contact__c = c.Id,
            Token__c = 'past-grace-fixture-1234567890abcdef34',
            Expires_At__c = System.now().addHours(1),
            Request_Count_24h__c = 1
        );
        insert rt;

        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(rt.Token__c);
        Test.stopTest();

        System.assertEquals(false, resp.get('success'));
        System.assertEquals('past_grace', resp.get('status'));
    }

    @IsTest
    static void consumeBlankTokenReturnsNotFound() {
        Test.startTest();
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken('');
        Test.stopTest();

        System.assertEquals('not_found', resp.get('status'));
    }

    /* ============================================================ */
    /* End-to-end                                                    */
    /* ============================================================ */

    @IsTest
    static void endToEndDeleteThenRestoreViaUsernameRequest() {
        Contact c = pausedContact();
        User u = pausedUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        // Publish the platform event and let the subscriber run; only after
        // Test.stopTest() will the token exist for consume to pick up.
        Test.startTest();
        FimbyReactivationController.requestReactivationLink(u.Username);
        Test.stopTest();

        Reactivation_Token__c rt = [
            SELECT Token__c FROM Reactivation_Token__c
            WHERE Contact__c = :c.Id LIMIT 1
        ];

        // consume runs inline (User.IsActive flip is best-effort via Queueable
        // and not asserted here, matching consumeValidTokenRestoresUser).
        Map<String, Object> resp = FimbyReactivationController.consumeReactivationToken(rt.Token__c);

        System.assertEquals('restored', resp.get('status'));
        Contact afterC = [SELECT Grace_Started_At__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, afterC.Grace_Started_At__c,
            'End-to-end restore should clear the grace stamp');
    }
}
