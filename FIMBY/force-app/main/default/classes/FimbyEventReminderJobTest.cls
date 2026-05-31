@IsTest
private class FimbyEventReminderJobTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact poster = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact attendee1 = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact attendee2 = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
    }

    private static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
    }

    private static List<Contact> getContacts() {
        return [SELECT Id, Full_Name__c FROM Contact WHERE AccountId = :getNeighbourhood().Id ORDER BY CreatedDate ASC];
    }

    private static Needs_Offers__c createEvent(String eventType, Date startDate, Time startTime, Id posterId, Id neighbourhoodId) {
        Id rtId;
        try {
            rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();
        } catch (Exception e) {
            rtId = null;
        }

        String timeText = startTime != null
            ? String.valueOf(startTime.hour()) + ':' + String.valueOf(startTime.minute()).leftPad(2, '0')
            : null;

        Needs_Offers__c evt = new Needs_Offers__c(
            Name = 'Test ' + eventType + ' Event',
            Details__c = 'Event details',
            Status__c = 'Posted',
            Type__c = 'Event',
            Event_Type__c = eventType,
            Posted_By__c = posterId,
            Contact__c = posterId,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Start_Date__c = startDate,
            Start_Time__c = startTime,
            Start_Time_Text__c = timeText,
            Location__c = 'Community Hall',
            End_Date__c = startDate.addDays(1)
        );
        if (eventType == 'Gathering') {
            evt.Total_Quantity__c = 50;
            evt.Per_Response_Limit__c = 5;
        }
        if (eventType == 'Community_Event') {
            evt.Event_Link__c = 'https://example.com/event';
        }
        if (rtId != null) evt.RecordTypeId = rtId;
        insert evt;
        return evt;
    }

    private static Response__c createResponse(Id eventId, Id contactId, Id neighbourhoodId) {
        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = eventId,
            On_Behalf_Of_Contact__c = contactId,
            Contact__c = contactId,
            Status__c = FimbyConstants.RESPONSE_ACCEPTED,
            Amount_Requested__c = 1,
            Neighbourhood__c = neighbourhoodId,
            Response__c = 'Quick event response'
        );
        insert resp;
        return resp;
    }

    /* ── Day-before Gathering: poster + attendees notified ─────────── */

    @IsTest
    static void testDayBefore_Gathering_PosterAndAttendees() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;
        Contact poster = contacts[0];
        Contact att1 = contacts[1];
        Contact att2 = contacts[2];

        Needs_Offers__c evt = createEvent('Gathering', Date.today().addDays(1), Time.newInstance(14, 0, 0, 0), poster.Id, neighbourhoodId);
        createResponse(evt.Id, att1.Id, neighbourhoodId);
        createResponse(evt.Id, att2.Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Title__c, Body__c, Type__c, Action_URL__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER
            AND Related_Record_Id__c = :String.valueOf(evt.Id)
        ];

        System.assertEquals(3, notifs.size(), 'Should create reminders for 2 attendees + poster');

        Map<Id, Notification__c> byContact = new Map<Id, Notification__c>();
        for (Notification__c n : notifs) {
            byContact.put(n.Contact__c, n);
        }

        Notification__c posterNotif = byContact.get(poster.Id);
        System.assertNotEquals(null, posterNotif, 'Poster should receive a reminder');
        System.assert(posterNotif.Title__c.contains('2 neighbours'), 'Poster title should include attendee count: ' + posterNotif.Title__c);
        System.assert(posterNotif.Title__c.contains('tomorrow'), 'Poster title should say tomorrow: ' + posterNotif.Title__c);

        Notification__c att1Notif = byContact.get(att1.Id);
        System.assertNotEquals(null, att1Notif, 'Attendee should receive a reminder');
        System.assert(att1Notif.Title__c.contains('tomorrow'), 'Attendee title should say tomorrow: ' + att1Notif.Title__c);
        System.assert(att1Notif.Action_URL__c.contains('/asks-offers/'), 'Action URL should point to asks-offers');
    }

    /* ── Day-before Community Event: attendees get link, no morning-of ─ */

    @IsTest
    static void testDayBefore_CommunityEvent_WithLink() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;
        Contact poster = contacts[0];
        Contact att1 = contacts[1];

        Needs_Offers__c evt = createEvent('Community_Event', Date.today().addDays(1), Time.newInstance(18, 0, 0, 0), poster.Id, neighbourhoodId);
        createResponse(evt.Id, att1.Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Title__c, Body__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER
            AND Related_Record_Id__c = :String.valueOf(evt.Id)
        ];

        System.assertEquals(2, notifs.size(), 'Should create reminders for attendee + poster');

        Notification__c attendeeNotif;
        Notification__c posterNotif;
        for (Notification__c n : notifs) {
            if (n.Contact__c == att1.Id) attendeeNotif = n;
            if (n.Contact__c == poster.Id) posterNotif = n;
        }

        System.assert(attendeeNotif.Body__c.contains('https://example.com/event'), 'Attendee body should include event link');
        System.assert(posterNotif.Title__c.startsWith('The '), 'Community Event poster title should start with "The": ' + posterNotif.Title__c);
    }

    /* ── Community Event: no morning-of reminders ──────────────────── */

    @IsTest
    static void testMorningOf_CommunityEvent_Skipped() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Community_Event', Date.today(), Time.newInstance(14, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        createResponse(evt.Id, contacts[1].Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER];
        System.assertEquals(0, count, 'Community Event should not get morning-of reminders');
    }

    /* ── Morning-of Open Event (10 AM start): reminders created ────── */

    @IsTest
    static void testMorningOf_OpenEvent_AfterCutoff() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Open_Event', Date.today(), Time.newInstance(10, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        createResponse(evt.Id, contacts[1].Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Title__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER
        ];

        System.assertEquals(2, notifs.size(), 'Morning-of reminders should be created for 10 AM event');

        Boolean hasToday = false;
        for (Notification__c n : notifs) {
            if (n.Title__c.contains('today')) hasToday = true;
        }
        System.assert(hasToday, 'Morning-of title should say today');
    }

    /* ── Morning-of skip: event starts before 9 AM ─────────────────── */

    @IsTest
    static void testMorningOf_EarlyStart_Skipped() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Gathering', Date.today(), Time.newInstance(7, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        createResponse(evt.Id, contacts[1].Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER];
        System.assertEquals(0, count, 'No morning-of reminders for events starting before 9 AM');
    }

    /* ── Dedup: running twice does not double-send ─────────────────── */

    @IsTest
    static void testDedup_NoDuplicateReminders() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Open_Event', Date.today().addDays(1), Time.newInstance(15, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        createResponse(evt.Id, contacts[1].Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER];
        System.assertEquals(2, count, 'Second run should not create duplicates (poster + 1 attendee)');
    }

    /* ── No reminders for withdrawn responses ──────────────────────── */

    @IsTest
    static void testWithdrawnResponse_NoReminder() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Gathering', Date.today().addDays(1), Time.newInstance(12, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        Response__c resp = createResponse(evt.Id, contacts[1].Id, neighbourhoodId);
        resp.Status__c = FimbyConstants.RESPONSE_DECLINED;
        update resp;

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER
        ];

        System.assertEquals(1, notifs.size(), 'Only poster should get reminder (withdrawn attendee excluded)');
        System.assertEquals(contacts[0].Id, notifs[0].Contact__c, 'Reminder should be for poster only');
    }

    /* ── No reminders for closed events ────────────────────────────── */

    @IsTest
    static void testClosedEvent_NoReminders() {
        List<Contact> contacts = getContacts();
        Id neighbourhoodId = getNeighbourhood().Id;

        Needs_Offers__c evt = createEvent('Gathering', Date.today().addDays(1), Time.newInstance(14, 0, 0, 0), contacts[0].Id, neighbourhoodId);
        evt.Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED;
        update evt;

        createResponse(evt.Id, contacts[1].Id, neighbourhoodId);

        Test.startTest();
        FimbyEventReminderJob.processReminders();
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER];
        System.assertEquals(0, count, 'No reminders for completed/closed events');
    }
}
