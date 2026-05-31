/**
 * @description Scheduled job that creates event reminder notifications for
 * attendees and posters. Runs daily; produces day-before and morning-of
 * reminders. Community Events receive day-before only. Morning-of is skipped
 * when the event starts before 9 AM.
 *
 * Schedule: System.schedule('FIMBY Event Reminders', '0 0 7 * * ?', new FimbyEventReminderJob());
 */
global without sharing class FimbyEventReminderJob implements Schedulable {

    @TestVisible
    private static final Time MORNING_OF_CUTOFF = Time.newInstance(9, 0, 0, 0);

    private static final Set<String> ACTIVE_POST_STATUSES = new Set<String>{
        'Posted', 'Reply Received', 'Reply Accepted'
    };

    private static final Set<String> ACTIVE_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_NEW,
        FimbyConstants.RESPONSE_ACCEPTED
    };

    global void execute(SchedulableContext ctx) {
        try {
            processReminders();
        } catch (Exception e) {
            FimbyLogger.error('FimbyEventReminderJob', 'execute', e);
        }
    }

    @TestVisible
    private static void processReminders() {
        Date today = Date.today();
        Date tomorrow = today.addDays(1);

        List<Needs_Offers__c> events = [
            SELECT Id, Name, Event_Type__c, Start_Date__c, Start_Time__c,
                   Start_Time_Text__c, Location__c, Event_Link__c,
                   Posted_By__c, Posted_By__r.Full_Name__c
            FROM Needs_Offers__c
            WHERE Type__c = 'Event'
            AND Status__c IN :ACTIVE_POST_STATUSES
            AND Start_Date__c IN (:today, :tomorrow)
        ];

        if (events.isEmpty()) {
            return;
        }

        Set<Id> eventIds = new Set<Id>();
        for (Needs_Offers__c evt : events) {
            eventIds.add(evt.Id);
        }

        Map<Id, List<Id>> attendeesByEvent = buildAttendeeMap(eventIds);

        Set<String> alreadySent = buildDedup(eventIds);

        List<Notification__c> notifications = new List<Notification__c>();

        for (Needs_Offers__c evt : events) {
            Boolean isDayBefore = evt.Start_Date__c == tomorrow;
            Boolean isMorningOf = evt.Start_Date__c == today;

            if (isMorningOf && !isMorningOfEligible(evt)) {
                continue;
            }

            List<Id> attendeeContactIds = attendeesByEvent.containsKey(evt.Id)
                ? attendeesByEvent.get(evt.Id) : new List<Id>();
            Integer attendeeCount = attendeeContactIds.size();

            String timeLabel = isDayBefore ? 'tomorrow' : 'today';

            for (Id contactId : attendeeContactIds) {
                String key = contactId + '|' + evt.Id;
                if (alreadySent.contains(key)) continue;

                String title = buildAttendeeTitle(evt, timeLabel);
                String body = buildAttendeeBody(evt, timeLabel);

                notifications.add(buildNotification(contactId, title, body, evt.Id));
            }

            if (evt.Posted_By__c != null) {
                String posterKey = evt.Posted_By__c + '|' + evt.Id;
                if (!alreadySent.contains(posterKey)) {
                    String posterTitle = buildPosterTitle(evt, timeLabel, attendeeCount);
                    String posterBody = buildPosterBody(evt, timeLabel);

                    notifications.add(buildNotification(evt.Posted_By__c, posterTitle, posterBody, evt.Id));
                }
            }
        }

        if (!notifications.isEmpty()) {
            FimbyNotificationService.createNotifications(notifications);
        }
    }

    private static Boolean isMorningOfEligible(Needs_Offers__c evt) {
        if (evt.Event_Type__c == 'Community_Event') {
            return false;
        }
        if (evt.Start_Time__c != null && evt.Start_Time__c < MORNING_OF_CUTOFF) {
            return false;
        }
        return true;
    }

    private static Map<Id, List<Id>> buildAttendeeMap(Set<Id> eventIds) {
        Map<Id, List<Id>> result = new Map<Id, List<Id>>();
        List<Response__c> responses = [
            SELECT On_Behalf_Of_Contact__c, Need_Offer_Responded_To__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :eventIds
            AND Status__c IN :ACTIVE_RESPONSE_STATUSES
        ];
        for (Response__c r : responses) {
            if (!result.containsKey(r.Need_Offer_Responded_To__c)) {
                result.put(r.Need_Offer_Responded_To__c, new List<Id>());
            }
            result.get(r.Need_Offer_Responded_To__c).add(r.On_Behalf_Of_Contact__c);
        }
        return result;
    }

    private static Set<String> buildDedup(Set<Id> eventIds) {
        Set<String> keys = new Set<String>();
        List<Notification__c> existing = [
            SELECT Contact__c, Related_Record_Id__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_REMINDER
            AND Related_Record_Id__c IN :eventIds
            AND CreatedDate = TODAY
        ];
        for (Notification__c n : existing) {
            keys.add(n.Contact__c + '|' + n.Related_Record_Id__c);
        }
        return keys;
    }

    @TestVisible
    private static String buildAttendeeTitle(Needs_Offers__c evt, String timeLabel) {
        if (timeLabel == 'today') {
            if (evt.Event_Type__c == 'Gathering') {
                return 'See you at ' + evt.Name + ' today!';
            }
            return evt.Name + ' is today at ' + formatTime(evt) + locationSuffix(evt);
        }
        if (evt.Event_Type__c == 'Gathering') {
            String posterName = evt.Posted_By__r != null ? evt.Posted_By__r.Full_Name__c : null;
            String prefix = String.isNotBlank(posterName) ? (posterName + '\'s ') : '';
            return prefix + evt.Name + ' is tomorrow at ' + formatTime(evt) + locationSuffix(evt);
        }
        if (evt.Event_Type__c == 'Community_Event') {
            return evt.Name + ' is tomorrow at ' + formatTime(evt);
        }
        return evt.Name + ' is tomorrow at ' + formatTime(evt) + locationSuffix(evt);
    }

    @TestVisible
    private static String buildAttendeeBody(Needs_Offers__c evt, String timeLabel) {
        if (evt.Event_Type__c == 'Community_Event' && String.isNotBlank(evt.Event_Link__c)) {
            return 'Event Link: ' + evt.Event_Link__c;
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(formatTime(evt))) {
            parts.add((timeLabel == 'today' ? 'Today' : 'Tomorrow') + ' at ' + formatTime(evt));
        }
        if (String.isNotBlank(evt.Location__c)) {
            parts.add(evt.Location__c);
        }
        return String.join(parts, ', ');
    }

    @TestVisible
    private static String buildPosterTitle(Needs_Offers__c evt, String timeLabel, Integer attendeeCount) {
        if (evt.Event_Type__c == 'Community_Event') {
            return 'The ' + evt.Name + ' is tomorrow';
        }
        String countText = attendeeCount + ' neighbour' + (attendeeCount == 1 ? '' : 's');
        if (timeLabel == 'today') {
            if (evt.Event_Type__c == 'Gathering') {
                return 'Your ' + evt.Name + ' is today \u2014 ' + countText + ' coming!';
            }
            return evt.Name + ' is today \u2014 people are excited!';
        }
        if (evt.Event_Type__c == 'Gathering') {
            return countText + ' coming to ' + evt.Name + ' tomorrow!';
        }
        return evt.Name + ' is tomorrow \u2014 ' + countText + ' interested!';
    }

    @TestVisible
    private static String buildPosterBody(Needs_Offers__c evt, String timeLabel) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(formatTime(evt))) {
            parts.add((timeLabel == 'today' ? 'Today' : 'Tomorrow') + ' at ' + formatTime(evt));
        }
        if (String.isNotBlank(evt.Location__c)) {
            parts.add(evt.Location__c);
        }
        return String.join(parts, ', ');
    }

    private static String formatTime(Needs_Offers__c evt) {
        return String.isNotBlank(evt.Start_Time_Text__c) ? evt.Start_Time_Text__c : '';
    }

    private static String locationSuffix(Needs_Offers__c evt) {
        return String.isNotBlank(evt.Location__c) ? (', ' + evt.Location__c) : '';
    }

    private static Notification__c buildNotification(Id contactId, String title, String body, Id eventId) {
        return new Notification__c(
            Contact__c = contactId,
            Type__c = FimbyConstants.NOTIF_EVENT_REMINDER,
            Title__c = title,
            Body__c = body,
            Related_Record_Id__c = String.valueOf(eventId),
            Related_Record_Type__c = 'Needs_Offers__c',
            Action_URL__c = FimbySettings.getUrl('Asks_Offers', String.valueOf(eventId)),
            Actor_Name__c = 'FIMBY'
        );
    }
}
