@IsTest
private class FimbyEmailAlertServiceTest {

    @IsTest
    static void shouldSendEmail_masterToggleOff_returnsNull() {
        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = false,
            Email_Alert_Messages__c = true
        );
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_MESSAGE, u);
        Test.stopTest();

        System.assertEquals(null, result, 'Master toggle off should return null');
    }

    @IsTest
    static void shouldSendEmail_globalFlagOff_returnsNull() {
        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Messages__c = true
        );
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = false
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_MESSAGE, u);
        Test.stopTest();

        System.assertEquals(null, result, 'Global flag off should return null');
    }

    @IsTest
    static void shouldSendEmail_eligibleMessage_returnsPending() {
        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Messages__c = true
        );
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_MESSAGE, u);
        Test.stopTest();

        System.assertEquals('Pending', result);
    }

    @IsTest
    static void shouldSendEmail_categoryToggleOff_returnsNull() {
        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Messages__c = false
        );
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_MESSAGE, u);
        Test.stopTest();

        System.assertEquals(null, result, 'Category toggle off should return null');
    }

    @IsTest
    static void shouldSendEmail_unknownType_returnsNull() {
        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true
        );
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail('System', u);
        Test.stopTest();

        System.assertEquals(null, result, 'Unknown type should return null');
    }

    @IsTest
    static void shouldSendEmail_nullUser_returnsNull() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_MESSAGE, null);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void isDirectActionType_message_returnsTrue() {
        System.assert(FimbyEmailAlertService.isDirectActionType(FimbyConstants.NOTIF_MESSAGE));
    }

    /**
     * Response_Reply email default is ALWAYS, but the toggle stays on the legacy
     * Asks & Offers (Email_Alert_Needs_Offers__c) — matching the push override —
     * not Messages.
     */
    @IsTest
    static void shouldSendEmail_responseReply_usesAsksOffersToggle() {
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Email_Alerts_Global_Enabled__c = true));

        // Asks & Offers OFF → suppressed, even though Messages is ON.
        User off = new User(Id = UserInfo.getUserId(), Email_Alerts_Enabled__c = true,
            Email_Alert_Needs_Offers__c = false, Email_Alert_Messages__c = true);
        System.assertEquals(null,
            FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_RESPONSE_REPLY, off),
            'Asks & Offers email off must suppress a reply email');

        // Asks & Offers ON → eligible.
        User enabled = new User(Id = UserInfo.getUserId(), Email_Alerts_Enabled__c = true,
            Email_Alert_Needs_Offers__c = true, Email_Alert_Messages__c = false);
        System.assertEquals('Pending',
            FimbyEmailAlertService.shouldSendEmail(FimbyConstants.NOTIF_RESPONSE_REPLY, enabled),
            'Reply email default is ALWAYS and gated by Asks & Offers, not Messages');
    }

    @IsTest
    static void isDirectActionType_bulkBuy_returnsFalse() {
        System.assert(!FimbyEmailAlertService.isDirectActionType(FimbyConstants.NOTIF_BULK_BUY_STATUS));
    }

    /**
     * Event chat should now route to Email_Alert_Events__c, not
     * Email_Alert_Needs_Offers__c. Migration test: a user who silenced Asks &
     * Offers but kept Events on still receives event chat.
     */
    @IsTest
    static void shouldSendEmail_eventChat_respectsEventsToggle() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        User asksOffersOff = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Needs_Offers__c = false,
            Email_Alert_Events__c = true
        );

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(
            FimbyConstants.NOTIF_EVENT_CHAT, asksOffersOff
        );
        Test.stopTest();

        System.assertEquals('Pending', result,
            'Event chat should send when Events is on, even if Asks & Offers is off');
    }

    @IsTest
    static void shouldSendEmail_eventReminder_respectsEventsToggle() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        User remindersOff = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Reminders__c = false,
            Email_Alert_Events__c = false
        );

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(
            FimbyConstants.NOTIF_EVENT_REMINDER, remindersOff
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'Event reminder should respect the Events toggle, not the legacy Reminders toggle');
    }

    @IsTest
    static void shouldSendEmail_eventChat_eventsToggleOff_returnsNull() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        User u = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = true,
            Email_Alert_Needs_Offers__c = true,
            Email_Alert_Events__c = false
        );

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(
            FimbyConstants.NOTIF_EVENT_CHAT, u
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'Events toggle off should suppress event chat');
    }

    /**
     * Security/safety bypass infrastructure test. Even when every toggle is
     * off and the master Email_Alerts_Enabled__c is false, a registered
     * security-bypass type still returns 'Pending'. This is a forward-looking
     * contract — at v1 SECURITY_BYPASS_TYPES is empty by design (password
     * resets and account-deletion confirmations don't go through this
     * pipeline), but the infrastructure is in place for future security
     * notification types.
     */
    @IsTest
    static void shouldSendEmail_securityBypass_overridesAllToggles() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = false
        );
        FimbySettings.setMock(mock);

        User everythingOff = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = false,
            Email_Alert_Messages__c = false,
            Email_Alert_Needs_Offers__c = false,
            Email_Alert_Events__c = false,
            Email_Alert_Library__c = false,
            Email_Alert_Stories__c = false,
            Email_Alert_Reminders__c = false,
            Email_Alert_Bulk_Buy__c = false
        );

        String fakeSecurityType = 'Account_Security_Test_Only';
        FimbyEmailAlertService.addSecurityBypassTypeForTest(fakeSecurityType);

        Test.startTest();
        String result = FimbyEmailAlertService.shouldSendEmail(fakeSecurityType, everythingOff);
        Test.stopTest();

        System.assertEquals('Pending', result,
            'Security bypass must send even when every toggle is off and global flag is false');
    }

    /**
     * Vouching is system/safety: every Vouch_* lifecycle type must ride out
     * regardless of master Email_Alerts_Enabled__c, per-category toggles,
     * pilot allowlist, or global flag. Approval grants library access;
     * decline/revoke/pause/reminder/request-received all change or stall
     * that access. None of them can be silenced.
     */
    @IsTest
    static void shouldSendEmail_vouchTypes_bypassEveryGate() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = false
        );
        FimbySettings.setMock(mock);

        User everythingOff = new User(
            Id = UserInfo.getUserId(),
            Email_Alerts_Enabled__c = false,
            Email_Alert_Messages__c = false,
            Email_Alert_Needs_Offers__c = false,
            Email_Alert_Library__c = false,
            Email_Alert_Stories__c = false,
            Email_Alert_Reminders__c = false,
            Email_Alert_Bulk_Buy__c = false,
            Include_Sundays__c = false
        );

        List<String> vouchTypes = new List<String>{
            FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED,
            FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER,
            FimbyConstants.NOTIF_VOUCH_APPROVED,
            FimbyConstants.NOTIF_VOUCH_DECLINED,
            FimbyConstants.NOTIF_VOUCH_REVOKED,
            FimbyConstants.NOTIF_VOUCHER_PAUSED
        };

        Test.startTest();
        for (String t : vouchTypes) {
            System.assertEquals(
                'Pending',
                FimbyEmailAlertService.shouldSendEmail(t, everythingOff),
                t + ' must ride out as system/safety regardless of toggles'
            );
        }
        Test.stopTest();
    }
}
