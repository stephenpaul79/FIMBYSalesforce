@IsTest
public class FimbyPushGateStampActionTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, Last_DM_Push_At__c, Last_Activity_Push_At__c, Last_Quiet_Refresh_At__c
            FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true
            LIMIT 1
        ];
    }

    private static User reload(Id userId) {
        return [
            SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c, Last_Quiet_Refresh_At__c
            FROM User WHERE Id = :userId
        ];
    }

    /* ── QUIET stamps only the observability timestamp ───────────────────── */

    @IsTest
    static void testStampGates_Quiet_StampsOnlyQuietTimestamp() {
        User u = getTestUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyPushGateStampAction.stampGatesSync(
                new Map<String, String>{ String.valueOf(u.Id) => 'QUIET' });
        }
        User after = reload(u.Id);
        System.assertNotEquals(null, after.Last_Quiet_Refresh_At__c, 'QUIET stamps the quiet-refresh timestamp');
        System.assertEquals(null, after.Last_DM_Push_At__c, 'QUIET must NOT move the DM doorbell');
        System.assertEquals(null, after.Last_Activity_Push_At__c, 'QUIET must NOT move the activity doorbell');
    }

    /* ── DM / ACTIVITY / BOTH stamp only the doorbell field(s) ───────────── */

    @IsTest
    static void testStampGates_DM_StampsDoorbellOnly() {
        User u = getTestUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyPushGateStampAction.stampGatesSync(
                new Map<String, String>{ String.valueOf(u.Id) => 'DM' });
        }
        User after = reload(u.Id);
        System.assertNotEquals(null, after.Last_DM_Push_At__c, 'DM stamps the DM doorbell');
        System.assertEquals(null, after.Last_Activity_Push_At__c, 'DM does not stamp activity');
        System.assertEquals(null, after.Last_Quiet_Refresh_At__c, 'DM does not touch the quiet timestamp');
    }

    @IsTest
    static void testStampGates_Both_StampsBothDoorbells() {
        User u = getTestUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyPushGateStampAction.stampGatesSync(
                new Map<String, String>{ String.valueOf(u.Id) => 'BOTH' });
        }
        User after = reload(u.Id);
        System.assertNotEquals(null, after.Last_DM_Push_At__c, 'BOTH stamps the DM doorbell');
        System.assertNotEquals(null, after.Last_Activity_Push_At__c, 'BOTH stamps the activity doorbell');
        System.assertEquals(null, after.Last_Quiet_Refresh_At__c, 'BOTH does not touch the quiet timestamp');
    }

    /* ── Unknown gate type → no-op, no exception ─────────────────────────── */

    @IsTest
    static void testStampGates_UnknownGateType_NoOp() {
        User u = getTestUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyPushGateStampAction.stampGatesSync(
                new Map<String, String>{ String.valueOf(u.Id) => 'NONSENSE' });
        }
        User after = reload(u.Id);
        System.assertEquals(null, after.Last_DM_Push_At__c, 'Unknown gate type stamps nothing');
        System.assertEquals(null, after.Last_Activity_Push_At__c, 'Unknown gate type stamps nothing');
        System.assertEquals(null, after.Last_Quiet_Refresh_At__c, 'Unknown gate type stamps nothing');
    }

    /* ── Null / empty map → clean exit ───────────────────────────────────── */

    @IsTest
    static void testStampGates_NullAndEmpty() {
        FimbyPushGateStampAction.stampGatesSync(null);
        FimbyPushGateStampAction.stampGatesSync(new Map<String, String>());
        System.assert(true, 'Null/empty map exits without error');
    }
}
