/**
 * @description Schedulable batch dispatcher for push notifications. Runs every 15 minutes.
 * Queries Pending notifications, groups by user, checks quiet hours,
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

    // Actor_Name__c values that are team/icon tokens, not real neighbour names
    // (notification-contract §4). Skipped when leading an aggregate with a name.
    private static final Set<String> NON_PERSON_ACTORS = new Set<String>{
        'FIMBY', 'Neighbourhood team', 'care', 'system'
    };
    private static final String FALLBACK_ACTOR = 'A neighbour';

    global void execute(SchedulableContext ctx) {
        Integer batchCap = FimbySettings.pushBatchCap();

        List<Notification__c> pending = [
            SELECT Id, Type__c, Contact__c, Title__c, Body__c, Action_URL__c, Actor_Name__c, Push_Status__c
            FROM Notification__c
            WHERE Push_Status__c IN ('Pending', 'Pending_Quiet')
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

        // True unread badge (Phase 3): one read-only grouped aggregate over the
        // cycle's contacts. Counts EVERY unread row (incl. skipPush in-app-only)
        // so the icon badge mirrors the in-app unread list. Zero DML.
        Map<Id, Integer> unreadCountByContact = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Contact__c cid, COUNT(Id) cnt
            FROM Notification__c
            WHERE Contact__c IN :contactIds AND Read_Date__c = null
            GROUP BY Contact__c
        ]) {
            unreadCountByContact.put((Id) ar.get('cid'), (Integer) ar.get('cnt'));
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

        // ── Decision pass ──────────────────────────────────────────────────
        // Determine, per Contact, which rows drive this cycle's push and
        // whether it is audible (has a 'Pending' row, gate was open) or quiet
        // (only 'Pending_Quiet'). The audible-only skip rules (quiet hours,
        // Sunday direct-only) apply to the audible path; a quiet-only cycle is
        // non-disturbing so it proceeds through them.
        Map<Id, List<Notification__c>> driverRowsByContact = new Map<Id, List<Notification__c>>();
        Map<Id, Boolean> isAudibleByContact = new Map<Id, Boolean>();
        Map<Id, User> userByContact = new Map<Id, User>();

        for (Id contactId : pendingByContact.keySet()) {
            User u = userByContactId.get(contactId);
            if (u == null) {
                continue;
            }

            List<Notification__c> rows = pendingByContact.get(contactId);
            Boolean hasAudible = false;
            for (Notification__c n : rows) {
                if (n.Push_Status__c == 'Pending') {
                    hasAudible = true;
                    break;
                }
            }

            if (hasAudible) {
                // Audible cycle: honour the doorbell suppression rules.
                if (isInQuietHours(u)) {
                    // Quiet hours mute the buzz; demote to a passive refresh so the
                    // card/badge still becomes current without disturbing anyone.
                    hasAudible = false;
                } else if (isSunday && u.Include_Sundays__c != true) {
                    List<Notification__c> directOnly = new List<Notification__c>();
                    for (Notification__c n : rows) {
                        if (FimbyEmailAlertService.isDirectActionType(n.Type__c)
                            || FimbyNotificationService.gateTypeFor(n.Type__c) == 'DM') {
                            directOnly.add(n);
                        }
                    }
                    if (directOnly.isEmpty()) {
                        // Nothing audible survives the Sunday filter; fall back to a
                        // passive refresh over the full row set.
                        hasAudible = false;
                    } else {
                        rows = directOnly;
                    }
                }
            }

            driverRowsByContact.put(contactId, rows);
            isAudibleByContact.put(contactId, hasAudible);
            userByContact.put(contactId, u);
        }

        if (driverRowsByContact.isEmpty()) {
            return;
        }

        // ── Content pass (requirement #2) ──────────────────────────────────
        // Card title/body/badge are built from the user's CURRENT UNREAD set,
        // not just this cycle's delta rows, so the named lead and the count come
        // from the same snapshot and can never disagree. Read-only (zero DML).
        Set<Id> pushContactIds = driverRowsByContact.keySet();
        Map<Id, List<Notification__c>> unreadByContact = new Map<Id, List<Notification__c>>();
        for (Notification__c n : [
            SELECT Id, Contact__c, Type__c, Actor_Name__c, Title__c, Body__c, Action_URL__c
            FROM Notification__c
            WHERE Contact__c IN :pushContactIds AND Read_Date__c = null
            ORDER BY CreatedDate DESC
            LIMIT :batchCap
        ]) {
            if (!unreadByContact.containsKey(n.Contact__c)) {
                unreadByContact.put(n.Contact__c, new List<Notification__c>());
            }
            unreadByContact.get(n.Contact__c).add(n);
        }

        // ── Build pass ─────────────────────────────────────────────────────
        List<FimbyPushNotificationService.PushPayload> payloads =
            new List<FimbyPushNotificationService.PushPayload>();
        Map<Id, List<Id>> notifIdsByUser = new Map<Id, List<Id>>();
        Map<Id, String> userGateUpdates = new Map<Id, String>();

        for (Id contactId : driverRowsByContact.keySet()) {
            User u = userByContact.get(contactId);
            List<Notification__c> driverRows = driverRowsByContact.get(contactId);
            Boolean isAudible = isAudibleByContact.get(contactId);

            // The mark-Sent set is this cycle's driver rows (the trigger), keyed
            // by user so the queueable can mark granularly per delivery outcome.
            List<Id> markIds = new List<Id>();
            for (Notification__c n : driverRows) {
                markIds.add(n.Id);
            }
            notifIdsByUser.put(u.Id, markIds);

            // Content is built from current unread (falling back to the driver
            // rows if the unread snapshot is somehow empty, e.g. just-read race).
            List<Notification__c> contentRows = unreadByContact.containsKey(contactId)
                ? unreadByContact.get(contactId) : driverRows;

            // Content routing (title/channel) splits on MESSAGE_STYLE_TYPES so
            // hidden message-style rows (incl. Event_Chat) land in the message
            // bucket and route to the Messages surface.
            Boolean contentHasDM = false;
            Boolean contentHasActivity = false;
            List<Notification__c> dmList = new List<Notification__c>();
            List<Notification__c> activityList = new List<Notification__c>();
            // Gate-stamp split is INDEPENDENT of content routing: it derives each
            // row's doorbell lane from the same map used at creation time
            // (gateTypeFor), so Event_Chat keeps the ACTIVITY gate even though it
            // routes on the 'messages' channel, and the delivered gate can never
            // disagree with the gate checked at creation.
            Boolean gateHasDM = false;
            Boolean gateHasActivity = false;
            for (Notification__c n : contentRows) {
                if (FimbyConstants.MESSAGE_STYLE_TYPES.contains(n.Type__c)) {
                    contentHasDM = true;
                    dmList.add(n);
                } else {
                    contentHasActivity = true;
                    activityList.add(n);
                }
                if (FimbyNotificationService.gateTypeFor(n.Type__c) == 'DM') {
                    gateHasDM = true;
                } else {
                    gateHasActivity = true;
                }
            }

            // The audible doorbell gate(s) to close this cycle, from the rows'
            // creation lanes (not the content bucket).
            String audibleGate = (gateHasDM && gateHasActivity)
                ? 'BOTH' : (gateHasDM ? 'DM' : 'ACTIVITY');

            Integer unread = unreadCountByContact.get(contactId);
            Integer badge = (unread == null) ? 0 : Math.min(unread, 9999);

            // Single-notification AUDIBLE cycle: send the actual title/body +
            // deep link so the device can route straight to the surface.
            // (Quiet refreshes always use the aggregate path so content reflects
            // the whole unread set, never one drifting row.)
            if (isAudible && driverRows.size() == 1 && contentRows.size() == 1) {
                Notification__c only = contentRows[0];
                // Doorbell gate is derived from the SAME map used at creation
                // time (FimbyNotificationService.gateTypeFor) so the delivered
                // stamp can never disagree with the gate checked at creation.
                // Event_Chat is the deliberate channel != gate case: ACTIVITY
                // gate (here) but 'messages' channel (resolveChannelId below).
                Boolean onlyIsDM = FimbyNotificationService.gateTypeFor(only.Type__c) == 'DM';
                FimbyPushNotificationService.PushPayload payload =
                    new FimbyPushNotificationService.PushPayload();
                payload.userId = u.Id;
                payload.badge = badge;
                payload.title = composeSinglePushTitle(only);
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
                payload.collapseId = u.Id + ':' + (onlyIsDM ? 'dm' : 'activity');
                payloads.add(payload);
                userGateUpdates.put(u.Id, onlyIsDM ? 'DM' : 'ACTIVITY');
            } else {
                // Aggregate path. The DM and activity gates NEVER merge into one
                // device ping: each gets its own card so its deep link routes to
                // the surface where that content actually lives (/messages vs
                // /notifications). A single merged ping could only carry one
                // route, stranding the other half. So a mixed cycle emits up to
                // TWO pings — one per gate — collapsing only WITHIN each gate.
                if (contentHasDM) {
                    FimbyPushNotificationService.PushPayload dmPayload =
                        new FimbyPushNotificationService.PushPayload();
                    dmPayload.userId = u.Id;
                    dmPayload.badge = badge;
                    dmPayload.title = buildAggregateTitle(extractRealNames(dmList), 'DM');
                    dmPayload.body = buildAggregateBody(dmList.size(), 'DM');
                    dmPayload.notificationType = FimbyPushNotificationService.NotificationType.MESSAGE;
                    // Quiet DM refresh routes to the low-importance channel so a
                    // tag-replacement does not re-alert on Android (requirement #1).
                    dmPayload.data.put('channelId', isAudible ? 'messages' : 'messages_quiet');
                    dmPayload.collapseId = u.Id + ':dm';
                    if (!isAudible) {
                        dmPayload.quiet = true;
                    }
                    payloads.add(dmPayload);
                }
                if (contentHasActivity) {
                    FimbyPushNotificationService.PushPayload activityPayload =
                        new FimbyPushNotificationService.PushPayload();
                    activityPayload.userId = u.Id;
                    activityPayload.badge = badge;
                    activityPayload.title = buildAggregateTitle(extractRealNames(activityList), 'ACTIVITY');
                    activityPayload.body = buildAggregateBody(activityList.size(), 'ACTIVITY');
                    activityPayload.notificationType = FimbyPushNotificationService.NotificationType.GENERAL;
                    activityPayload.data.put('channelId', 'activity');
                    activityPayload.collapseId = u.Id + ':activity';
                    if (!isAudible) {
                        activityPayload.quiet = true;
                    }
                    payloads.add(activityPayload);
                }
                // Gate stamp is per USER (it moves the doorbell timestamps), so a
                // mixed audible cycle still stamps BOTH lanes via audibleGate —
                // independent of how many pings were emitted above.
                userGateUpdates.put(u.Id, isAudible ? audibleGate : 'QUIET');
            }
        }

        if (payloads.isEmpty()) {
            return;
        }

        try {
            System.enqueueJob(new FimbyPushQueueable(payloads, notifIdsByUser, userGateUpdates));
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
    static Boolean isSundayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '7';
    }

    /**
     * Builds the title for a single-notification push. Bell-visible notification
     * titles are now stored as de-actored verb phrases ("requested to borrow your
     * drill"), so on a lock screen we prepend the real actor name to keep the copy
     * whole ("Maya Chen requested to borrow your drill"), mirroring the aggregate
     * path. Message-style titles already carry the name ("Maya replied", "Maya
     * thanked you") and are owned by the messages/split plan, so they pass through
     * verbatim. Token/system actors (FIMBY, Neighbourhood team, care, system) and
     * blank names also pass through. Capped at 80 chars on a word boundary.
     */
    @TestVisible
    static String composeSinglePushTitle(Notification__c only) {
        String title = String.isNotBlank(only.Title__c) ? only.Title__c : 'New activity';
        String actor = only.Actor_Name__c;
        if (String.isBlank(actor) || NON_PERSON_ACTORS.contains(actor)) {
            return title;
        }
        if (FimbyConstants.MESSAGE_STYLE_TYPES.contains(only.Type__c)) {
            return title;
        }
        return truncateAtWord(actor + ' ' + title, 80);
    }

    /**
     * Collects real neighbour names from a bucket, deduped while preserving
     * first-seen (CreatedDate ASC) order. Team/icon tokens and blanks are
     * skipped (notification-contract §4). Works on any Notification__c list.
     */
    @TestVisible
    static List<String> extractRealNames(List<Notification__c> bucket) {
        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        if (bucket == null) {
            return ordered;
        }
        for (Notification__c n : bucket) {
            String name = n.Actor_Name__c;
            if (String.isBlank(name) || NON_PERSON_ACTORS.contains(name)) {
                continue;
            }
            if (seen.contains(name)) {
                continue;
            }
            seen.add(name);
            ordered.add(name);
        }
        return ordered;
    }

    /**
     * Builds a name-led aggregate push title for a bucket. gateKind ∈
     * {'DM','ACTIVITY','BOTH'}. Falls back to today's generic strings when no
     * real name is available. Always capped at 80 chars on a word boundary.
     */
    @TestVisible
    static String buildAggregateTitle(List<String> names, String gateKind) {
        String title;
        if (names == null || names.isEmpty()) {
            if (gateKind == 'DM') {
                title = 'New messages';
            } else if (gateKind == 'BOTH') {
                title = 'New messages and activity';
            } else {
                title = 'Neighbourhood activity';
            }
            return truncateAtWord(title, 80);
        }

        String first = names[0];
        Integer count = names.size();

        if (gateKind == 'DM') {
            if (count == 1) {
                title = first + ' messaged you';
            } else if (count == 2) {
                title = first + ' and ' + names[1] + ' messaged you';
            } else {
                title = first + ' and ' + (count - 1) + ' others messaged you';
            }
        } else if (gateKind == 'BOTH') {
            title = first + ' messaged you, plus neighbourhood activity';
        } else {
            if (count == 1) {
                title = first + ' posted in your neighbourhood';
            } else if (count == 2) {
                title = first + ' and ' + names[1] + ' posted nearby';
            } else {
                title = first + ', plus ' + (count - 1) + ' more updates';
            }
        }
        return truncateAtWord(title, 80);
    }

    /**
     * Builds the deciding-context body line. The count semantics differ per
     * bucket (see plan): DM passes the unread-message count, ACTIVITY passes the
     * total activity count (body shows the remainder), BOTH ignores the count.
     * Never returns null; capped at 140 chars on a word boundary.
     */
    @TestVisible
    static String buildAggregateBody(Integer count, String gateKind) {
        String body;
        if (gateKind == 'DM') {
            // count is the number of unread DM notifications (one per message),
            // not distinct threads, so the noun is "messages" not "conversations".
            body = (count == 1)
                ? '1 new message waiting.'
                : count + ' new messages waiting.';
        } else if (gateKind == 'BOTH') {
            body = 'Messages and neighbourhood updates are waiting.';
        } else {
            body = (count <= 1)
                ? 'Tap to see what\'s new nearby.'
                : 'and ' + (count - 1) + ' more updates from your neighbourhood.';
        }
        return truncateAtWord(body, 140);
    }

    /**
     * Trims a string to max chars on the last word boundary. No ellipsis.
     */
    @TestVisible
    static String truncateAtWord(String s, Integer max) {
        if (s == null) {
            return '';
        }
        if (s.length() <= max) {
            return s;
        }
        String cut = s.substring(0, max);
        Integer lastSpace = cut.lastIndexOf(' ');
        if (lastSpace > 0) {
            cut = cut.substring(0, lastSpace);
        }
        return cut.trim();
    }

    private static FimbyPushNotificationService.NotificationType mapTypeToPushCategory(String type) {
        if (String.isBlank(type)) { return FimbyPushNotificationService.NotificationType.GENERAL; }
        if (type == FimbyConstants.NOTIF_MESSAGE || type == FimbyConstants.NOTIF_EVENT_CHAT
            || type == FimbyConstants.NOTIF_RESPONSE_REPLY) {
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
        if (FimbyConstants.MESSAGE_STYLE_TYPES.contains(type)) {
            return 'messages';
        }
        return 'activity';
    }
}
