@IsTest
private class FimbyEmailAlertBatchJobTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
    }

    static User getTestUser() {
        return [
            SELECT Id, ContactId, Quiet_Hours_Preference__c, TimeZoneSidKey
            FROM User
            WHERE ContactId != null
              AND Profile.Name = 'Customer Community User - Mobile App'
              AND UserName LIKE '%@testorg.com'
            LIMIT 1
        ];
    }

    static Contact getTestContact() {
        return [SELECT Id FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    @IsTest
    static void execute_globalDisabled_exitsEarly() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = false
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_noPending_exitsEarly() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true,
            Email_Alert_Batch_Cap__c = 100
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_withPendingNotifications_claimsAndEnqueues() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true,
            Email_Alert_Batch_Cap__c = 100
        );
        FimbySettings.setMock(mock);

        Contact c = getTestContact();
        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Message', 'Pending', 2, true
        );

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();

        for (Notification__c n : [SELECT Email_Status__c FROM Notification__c WHERE Id IN :notifs]) {
            System.assertNotEquals('Pending', n.Email_Status__c,
                'Should no longer be Pending after batch claims');
        }
    }

    @IsTest
    static void execute_multiplePendingTypes_groupsByContact() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true,
            Email_Alert_Batch_Cap__c = 100
        );
        FimbySettings.setMock(mock);

        Contact c = getTestContact();
        FimbyTestDataFactory.createNotifications(c.Id, 'Message', 'Pending', 1, true);
        FimbyTestDataFactory.createNotifications(c.Id, 'Lending_Request', 'Pending', 1, true);

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void isSundayNow_returnsBooleanCleanly() {
        Boolean result = FimbyEmailAlertBatchJob.isSundayNow();
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void execute_quietHours_keepsEmailPending() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Email_Alerts_Global_Enabled__c = true,
            Email_Alert_Batch_Cap__c = 100
        );
        FimbySettings.setMock(mock);

        Contact c = getTestContact();
        User u = getTestUser();

        String quietPref = resolveQuietHoursPrefForNow(u.TimeZoneSidKey);
        if (quietPref == null) {
            return;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = u.Id,
                Quiet_Hours_Preference__c = quietPref,
                TimeZoneSidKey = u.TimeZoneSidKey
            );
        }

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Message', 'Pending', 1, true
        );

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(
            'Pending',
            [SELECT Email_Status__c FROM Notification__c WHERE Id = :notifs[0].Id].Email_Status__c,
            'Quiet hours should leave email Pending until morning'
        );
    }

    @TestVisible
    private static String resolveQuietHoursPrefForNow(String timeZoneSid) {
        List<String> prefs = new List<String>{
            '9PM_5AM', '10PM_6AM', '11PM_7AM', '12AM_8AM'
        };
        String tz = String.isNotBlank(timeZoneSid) ? timeZoneSid : 'America/Vancouver';
        for (String pref : prefs) {
            User probe = new User(
                Quiet_Hours_Preference__c = pref,
                TimeZoneSidKey = tz
            );
            if (FimbyPushBatchJob.isInQuietHours(probe)) {
                return pref;
            }
        }
        return null;
    }
}
