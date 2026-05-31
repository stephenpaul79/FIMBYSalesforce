/**
 * @description Schedulable batch dispatcher for push notifications. Runs every 15 minutes.
 * Queries Pending notifications, groups by user, checks quiet hours and active session,
 * builds one generic push per eligible user, then hands everything to FimbyPushQueueable.
 * Performs ZERO DML -- all writes happen in the Queueable after confirmed delivery.
 */
global without sharing class FimbyPushBatchJob implements Schedulable {

    private static final Map<String, Integer[]> QUIET_WINDOWS = new Map<String, Integer[]>{
        '9PM_5AM'  => new Integer[]{ 21, 5 },
        '10PM_6AM' => new Integer[]{ 22, 6 },
        '11PM_7AM' => new Integer[]{ 23, 7 },
        '12AM_8AM' => new Integer[]{ 0, 8 },
        'NONE'     => null
    };

    global void execute(SchedulableContext ctx) {
        Integer batchCap = FimbySettings.pushBatchCap();

        List<Notification__c> pending = [
            SELECT Id, Type__c, Contact__c, Title__c, Body__c, Action_URL__c, Actor_Name__c
            FROM Notification__c
            WHERE Push_Status__c = 'Pending'
            ORDER BY CreatedDate ASC
            LIMIT :batchCap
        ];
        if (pending.isEmpty()) {
            return;
        }

        Boolean isSunday = isSundayNow();

        Set<Id> contactIds = new Set<Id>();
        for (Notification__c n : pending) {
            if (n.Contact__c != null) {
                contactIds.add(n.Contact__c);
            }
        }

        Map<Id, User> userByContactId = new Map<Id, User>();
        for (User u : [
            SELECT Id, ContactId, TimeZoneSidKey,
                   Quiet_Hours_Preference__c, Last_App_Open_At__c,
                   Include_Sundays__c
            FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
        ]) {
            userByContactId.put(u.ContactId, u);
        }

        Map<Id, List<Notification__c>> pendingByContact = new Map<Id, List<Notification__c>>();
        for (Notification__c n : pending) {
            if (n.Contact__c == null) {
                continue;
            }
            if (!pendingByContact.containsKey(n.Contact__c)) {
                pendingByContact.put(n.Contact__c, new List<Notification__c>());
            }
            pendingByContact.get(n.Contact__c).add(n);
        }

        List<FimbyPushNotificationService.PushPayload> payloads =
            new List<FimbyPushNotificationService.PushPayload>();
        List<Id> notifIdsToMarkSent = new List<Id>();
        Map<Id, String> userGateUpdates = new Map<Id, String>();

        for (Id contactId : pendingByContact.keySet()) {
            User u = userByContactId.get(contactId);
            if (u == null) {
                continue;
            }

            if (isInQuietHours(u)) {
                continue;
            }

            if (isActiveSession(u)) {
                continue;
            }

            List<Notification__c> userPending = pendingByContact.get(contactId);

            if (isSunday && u.Include_Sundays__c != true) {
                List<Notification__c> directOnly = new List<Notification__c>();
                for (Notification__c n : userPending) {
                    if (FimbyEmailAlertService.isDirectActionType(n.Type__c)
                        || n.Type__c == FimbyConstants.NOTIF_MESSAGE) {
                        directOnly.add(n);
                    }
                }
                userPending = directOnly;
                if (userPending.isEmpty()) {
                    continue;
                }
            }
            Boolean hasDM = false;
            Boolean hasActivity = false;

            for (Notification__c n : userPending) {
                if (n.Type__c == FimbyConstants.NOTIF_MESSAGE) {
                    hasDM = true;
                } else {
                    hasActivity = true;
                }
                notifIdsToMarkSent.add(n.Id);
            }

            FimbyPushNotificationService.PushPayload payload =
                new FimbyPushNotificationService.PushPayload();
            payload.userId = u.Id;
            payload.badge = 1;

            // Single-notification batch: send the actual title/body + deep
            // link so the device can route straight to the surface. Dormant
            // until the mobile client consumes data.action_url and
            // data.notification_id, but harmless to ship today.
            if (userPending.size() == 1) {
                Notification__c only = userPending[0];
                payload.title = String.isNotBlank(only.Title__c) ? only.Title__c : 'New activity';
                payload.body = String.isNotBlank(only.Body__c) ? only.Body__c : '';
                payload.notificationType = mapTypeToPushCategory(only.Type__c);
                payload.data.put('channelId', resolveChannelId(only.Type__c));
                payload.data.put('notification_id', String.valueOf(only.Id));
                if (String.isNotBlank(only.Action_URL__c)) {
                    payload.data.put('action_url', only.Action_URL__c);
                }
                if (String.isNotBlank(only.Type__c)) {
                    payload.data.put('notification_type', only.Type__c);
                }
                userGateUpdates.put(u.Id, hasDM ? 'DM' : 'ACTIVITY');
            } else if (hasDM && hasActivity) {
                payload.title = 'New messages and activity';
                payload.body = 'You have messages, and something\'s happening in your neighbourhood.';
                payload.notificationType = FimbyPushNotificationService.NotificationType.GENERAL;
                payload.data.put('channelId', 'default');
                userGateUpdates.put(u.Id, 'BOTH');
            } else if (hasDM) {
                payload.title = 'New messages';
                payload.body = 'You have new messages from your neighbours.';
                payload.notificationType = FimbyPushNotificationService.NotificationType.MESSAGE;
                payload.data.put('channelId', 'messages');
                userGateUpdates.put(u.Id, 'DM');
            } else {
                payload.title = 'Neighbourhood activity';
                payload.body = 'Something\'s happening in your neighbourhood.';
                payload.notificationType = FimbyPushNotificationService.NotificationType.GENERAL;
                payload.data.put('channelId', 'activity');
                userGateUpdates.put(u.Id, 'ACTIVITY');
            }

            payloads.add(payload);
        }

        if (payloads.isEmpty()) {
            return;
        }

        try {
            System.enqueueJob(new FimbyPushQueueable(payloads, notifIdsToMarkSent, userGateUpdates));
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushBatchJob', 'execute', e);
        }
    }

    @TestVisible
    public static Boolean isInQuietHours(User u) {
        String pref = String.isNotBlank(u.Quiet_Hours_Preference__c)
            ? u.Quiet_Hours_Preference__c : '10PM_6AM';

        Integer[] window = QUIET_WINDOWS.get(pref);
        if (window == null) {
            return false;
        }

        Integer startHour = window[0];
        Integer endHour = window[1];

        String tzSid = String.isNotBlank(u.TimeZoneSidKey)
            ? u.TimeZoneSidKey : 'America/Vancouver';
        TimeZone tz = TimeZone.getTimeZone(tzSid);
        Datetime nowUtc = Datetime.now();
        Integer offsetMs = tz.getOffset(nowUtc);
        Datetime localNow = nowUtc.addSeconds(offsetMs / 1000);
        Integer localHour = localNow.hourGmt();

        if (startHour > endHour) {
            return (localHour >= startHour || localHour < endHour);
        } else if (startHour == 0) {
            return (localHour < endHour);
        }
        return (localHour >= startHour && localHour < endHour);
    }

    @TestVisible
    private static Boolean isActiveSession(User u) {
        if (u.Last_App_Open_At__c == null) {
            return false;
        }
        return u.Last_App_Open_At__c.addMinutes(15) > Datetime.now();
    }

    @TestVisible
    static Boolean isSundayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '7';
    }

    private static FimbyPushNotificationService.NotificationType mapTypeToPushCategory(String type) {
        if (String.isBlank(type)) { return FimbyPushNotificationService.NotificationType.GENERAL; }
        if (type == FimbyConstants.NOTIF_MESSAGE || type == FimbyConstants.NOTIF_EVENT_CHAT) {
            return FimbyPushNotificationService.NotificationType.MESSAGE;
        }
        if (type == FimbyConstants.NOTIF_RESPONSE || type == FimbyConstants.NOTIF_COMMENT) {
            return FimbyPushNotificationService.NotificationType.NEEDS_OFFERS;
        }
        if (type == FimbyConstants.NOTIF_EVENT_REMINDER) {
            return FimbyPushNotificationService.NotificationType.EVENTS;
        }
        if (type == FimbyConstants.NOTIF_LENDING_REQUEST
            || type == FimbyConstants.NOTIF_LOAN_APPROVED
            || type == FimbyConstants.NOTIF_EXTENSION_REQUEST
            || type == FimbyConstants.NOTIF_EXTENSION_APPROVED
            || type == FimbyConstants.NOTIF_EXTENSION_DECLINED
            || type == FimbyConstants.NOTIF_OVERDUE_REMINDER
            || type == FimbyConstants.NOTIF_ITEM_RETURNED) {
            return FimbyPushNotificationService.NotificationType.LIBRARY;
        }
        if (type == FimbyConstants.NOTIF_BULK_BUY_RESERVATION
            || type == FimbyConstants.NOTIF_BULK_BUY_STATUS
            || type == FimbyConstants.NOTIF_BULK_BUY_PICKUP) {
            return FimbyPushNotificationService.NotificationType.BULK_BUY;
        }
        if (type == FimbyConstants.NOTIF_MODERATOR) {
            return FimbyPushNotificationService.NotificationType.MODERATOR;
        }
        return FimbyPushNotificationService.NotificationType.GENERAL;
    }

    private static String resolveChannelId(String type) {
        if (type == FimbyConstants.NOTIF_MESSAGE || type == FimbyConstants.NOTIF_EVENT_CHAT) {
            return 'messages';
        }
        return 'activity';
    }
}
