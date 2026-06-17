@IsTest
public class FimbyPushActionResourceTest {

    @TestSetup
    static void setup() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true
            LIMIT 1
        ];
    }

    private static Id getTestContactId() {
        return getTestUser().ContactId;
    }

    private static void invoke(String action, String notificationId) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/fimby/push-action';
        req.httpMethod = 'POST';
        Map<String, Object> body = new Map<String, Object>();
        if (action != null) body.put('action', action);
        if (notificationId != null) body.put('notificationId', notificationId);
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        FimbyPushActionResource.handle();
    }

    private static String status() {
        Map<String, Object> parsed =
            (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        return (String) parsed.get('status');
    }

    /* ── mark_read marks an owned notification read ──────────────────────── */

    @IsTest
    static void testMarkRead_OwnedNotification_MarksRead() {
        User u = getTestUser();
        Id contactId = u.ContactId;

        Notification__c notif = new Notification__c(
            Contact__c = contactId, Type__c = 'Response',
            Title__c = 'Maya replied', Body__c = 'b'
        );
        insert notif;

        Test.startTest();
        System.runAs(u) {
            invoke('mark_read', notif.Id);
        }
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('ok', status());
        Notification__c after = [SELECT Read_Date__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertNotEquals(null, after.Read_Date__c, 'Owned notification should be marked read');
    }

    /* ── A foreign notification is never marked read ─────────────────────── */

    @IsTest
    static void testMarkRead_ForeignNotification_NoOp() {
        User u = getTestUser();

        // Notification owned by a different contact.
        Account nb = [SELECT Id FROM Account LIMIT 1];
        Contact other = FimbyTestDataFactory.createNeighbourhoodContact(nb.Id, true);
        Notification__c notif = new Notification__c(
            Contact__c = other.Id, Type__c = 'Response',
            Title__c = 'Not yours', Body__c = 'b'
        );
        insert notif;

        Test.startTest();
        System.runAs(u) {
            invoke('mark_read', notif.Id);
        }
        Test.stopTest();

        System.assertEquals('noop', status(), 'Foreign notification must not be marked read');
        Notification__c after = [SELECT Read_Date__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals(null, after.Read_Date__c, 'Foreign notification stays unread');
    }

    /* ── DM notification also marks the conversation + message read ──────── */

    @IsTest
    static void testMarkRead_MessageNotification_MarksConversationRead() {
        User u = getTestUser();
        Id myContactId = u.ContactId;

        Account nb = [SELECT Id FROM Account LIMIT 1];
        Contact sender = FimbyTestDataFactory.createNeighbourhoodContact(nb.Id, true);

        Conversation__c conv = new Conversation__c(
            Participant_1__c = myContactId,
            Participant_2__c = sender.Id,
            Participant_1_Unread_Count__c = 1,
            Participant_2_Unread_Count__c = 0
        );
        insert conv;

        Message__c inbound = new Message__c(
            Conversation__c = conv.Id,
            Sender__c = sender.Id,
            Body__c = 'hello neighbour',
            Sent_Date__c = Datetime.now()
        );
        insert inbound;

        Notification__c notif = new Notification__c(
            Contact__c = myContactId,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'New message',
            Body__c = 'b',
            Related_Record_Id__c = conv.Id
        );
        insert notif;

        Test.startTest();
        System.runAs(u) {
            invoke('mark_read', notif.Id);
        }
        Test.stopTest();

        System.assertEquals('ok', status());
        Notification__c afterNotif = [SELECT Read_Date__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertNotEquals(null, afterNotif.Read_Date__c, 'Notification marked read');

        Message__c afterMsg = [SELECT Read_Date__c FROM Message__c WHERE Id = :inbound.Id];
        System.assertNotEquals(null, afterMsg.Read_Date__c, 'Inbound message marked read');

        Conversation__c afterConv = [SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(0, afterConv.Participant_1_Unread_Count__c, 'Recipient unread counter reset to 0');
    }

    /* ── Validation: bad input ───────────────────────────────────────────── */

    @IsTest
    static void testValidation_MissingNotificationId() {
        User u = getTestUser();
        Test.startTest();
        System.runAs(u) {
            invoke('mark_read', null);
        }
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('missing_notification_id', status());
    }

    @IsTest
    static void testValidation_UnsupportedAction() {
        User u = getTestUser();
        Test.startTest();
        System.runAs(u) {
            invoke('delete_everything', 'a0X000000000000AAA');
        }
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('unsupported_action', status());
    }

    @IsTest
    static void testValidation_BadNotificationId_NoOp() {
        User u = getTestUser();
        Test.startTest();
        System.runAs(u) {
            invoke('mark_read', 'not-an-id');
        }
        Test.stopTest();
        System.assertEquals('noop', status(), 'Unparseable id is a safe no-op');
    }
}
