/**
 * @description Schedulable batch dispatcher for push notifications. Runs every 15 minutes.
 * Queries Pending notifications, groups by DELIVERY USER, checks quiet hours,
 * builds one generic push per eligible user, then hands everything to FimbyPushQueueable.
 * Performs ZERO DML -- all writes happen in the Queueable after confirmed delivery.
 *
 * Delivery user, not Contact: a notification whose Contact has no login of their own
 * (elder supportee, organization contact, parent-proxied child) is delivered to every
 * neighbour approved to act for them. One login can therefore serve several inboxes —
 * a parent with two proxied children serves three — and those inboxes are aggregated
 * into a SINGLE push per cycle. The two-gate doorbell exists to limit buzzes, so
 * multiplying cards by inbox count would defeat it. The card copy names the identity
 * instead ("Aisha messaged Maya"), and the badge sums every inbox the user serves so
 * the buzz, the bell, and the OS icon all report the same number.
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

    /**
     * Everything one login needs to receive a single push this cycle, gathered across
     * every inbox they serve.
     */
    private class DeliveryPlan {
        User u;
        Set<Id> inboxIds = new Set<Id>();
        Set<Id> proxiedInboxIds = new Set<Id>();
        List<Notification__c> driverRows = new List<Notification__c>();
        Boolean hasAudible = false;

        DeliveryPlan(User u) {
            this.u = u;
        }
    }

    global void execute(SchedulableContext ctx) {
        Integer batchCap = FimbySettings.pushBatchCap();

        List<Notification__c> pending = [
            SELECT Id, Type__c, Contact__c, Title__c, Body__c, Action_URL__c,
                   Actor_Name__c, Push_Status__c, Delivery_State__c
            FROM Notification__c
            WHERE Push_Status__c IN ('Pending', 'Pending_Quiet')
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT :batchCap
        ];
        if (pending.isEmpty()) {
            return;
        }

        Boolean isSunday = isSundayNow();

        Set<Id> inboxIds = new Set<Id>();
        for (Notification__c n : pending) {
            if (n.Contact__c != null) {
                inboxIds.add(n.Contact__c);
            }
        }
        if (inboxIds.isEmpty()) {
            return;
        }

        // True unread badge: one read-only grouped aggregate per inbox. Counts EVERY
        // unread row (incl. skipPush in-app-only) so the icon badge mirrors the in-app
        // unread list. Zero DML.
        Map<Id, Integer> unreadByInbox = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Contact__c cid, COUNT(Id) cnt
            FROM Notification__c
            WHERE Contact__c IN :inboxIds AND Read_Date__c = null
            WITH SYSTEM_MODE
            GROUP BY Contact__c
        ]) {
            unreadByInbox.put((Id) ar.get('cid'), (Integer) ar.get('cnt'));
        }

        Map<Id, DeliveryPlan> planByUserId = resolveDeliveryPlans(inboxIds);
        if (planByUserId.isEmpty()) {
            return;
        }

        // First names of the proxied inboxes, so aggregate copy can say "messaged Maya"
        // rather than the misleading "messaged you".
        Map<Id, String> inboxNameById = queryInboxNames(planByUserId);

        Map<Id, List<Notification__c>> pendingByInbox = new Map<Id, List<Notification__c>>();
        for (Notification__c n : pending) {
            if (n.Contact__c == null) {
                continue;
            }
            if (!pendingByInbox.containsKey(n.Contact__c)) {
                pendingByInbox.put(n.Contact__c, new List<Notification__c>());
            }
            pendingByInbox.get(n.Contact__c).add(n);
        }

        // ── Decision pass ──────────────────────────────────────────────────
        // Per delivery user, collect the rows this cycle should push and decide
        // whether the buzz is audible (a 'Pending' row for THIS user, gate was
        // open) or quiet (only 'Pending_Quiet'). Audible-only suppression rules
        // (quiet hours, Sunday direct-only) apply to the audible path; a
        // quiet-only cycle is non-disturbing so it proceeds through them.
        List<DeliveryPlan> plans = new List<DeliveryPlan>();

        for (DeliveryPlan plan : planByUserId.values()) {
            for (Id inboxId : plan.inboxIds) {
                List<Notification__c> rows = pendingByInbox.get(inboxId);
                if (rows == null) {
                    continue;
                }
                for (Notification__c n : rows) {
                    String stateForUser = pushStateFor(n, plan.u.Id);
                    if (stateForUser != 'Pending' && stateForUser != 'Pending_Quiet') {
                        // Already delivered to (or permanently failed for) this
                        // recipient; another recipient is keeping the row queued.
                        continue;
                    }
                    plan.driverRows.add(n);
                    if (stateForUser == 'Pending') {
                        plan.hasAudible = true;
                    }
                }
            }

            if (plan.driverRows.isEmpty()) {
                continue;
            }

            if (plan.hasAudible) {
                if (isInQuietHours(plan.u)) {
                    // Quiet hours mute the buzz; demote to a passive refresh so the
                    // card/badge still becomes current without disturbing anyone.
                    plan.hasAudible = false;
                } else if (isSunday && plan.u.Include_Sundays__c != true) {
                    List<Notification__c> directOnly = new List<Notification__c>();
                    for (Notification__c n : plan.driverRows) {
                        if (FimbyEmailAlertService.isDirectActionType(n.Type__c)
                            || FimbyNotificationService.gateTypeFor(n.Type__c) == 'DM') {
                            directOnly.add(n);
                        }
                    }
                    if (directOnly.isEmpty()) {
                        // Nothing audible survives the Sunday filter; fall back to a
                        // passive refresh over the full row set.
                        plan.hasAudible = false;
                    } else {
                        plan.driverRows = directOnly;
                    }
                }
            }

            plans.add(plan);
        }

        if (plans.isEmpty()) {
            return;
        }

        // ── Content pass ───────────────────────────────────────────────────
        // Card title/body/badge are built from the CURRENT UNREAD set across
        // every inbox the user serves, not just this cycle's delta rows, so the
        // named lead and the count come from the same snapshot and can never
        // disagree. Read-only (zero DML).
        Set<Id> contentInboxIds = new Set<Id>();
        for (DeliveryPlan plan : plans) {
            contentInboxIds.addAll(plan.inboxIds);
        }
        Map<Id, List<Notification__c>> unreadByInboxRows = new Map<Id, List<Notification__c>>();
        for (Notification__c n : [
            SELECT Id, Contact__c, Type__c, Actor_Name__c, Title__c, Body__c, Action_URL__c
            FROM Notification__c
            WHERE Contact__c IN :contentInboxIds AND Read_Date__c = null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT :batchCap
        ]) {
            if (!unreadByInboxRows.containsKey(n.Contact__c)) {
                unreadByInboxRows.put(n.Contact__c, new List<Notification__c>());
            }
            unreadByInboxRows.get(n.Contact__c).add(n);
        }

        // ── Build pass ─────────────────────────────────────────────────────
        List<FimbyPushNotificationService.PushPayload> payloads =
            new List<FimbyPushNotificationService.PushPayload>();
        Map<Id, List<Id>> notifIdsByUser = new Map<Id, List<Id>>();
        Map<Id, String> userGateUpdates = new Map<Id, String>();

        for (DeliveryPlan plan : plans) {
            User u = plan.u;

            // The mark set is this cycle's driver rows for THIS user, so the
            // queueable can record each recipient's outcome independently.
            List<Id> markIds = new List<Id>();
            Set<Id> seenRows = new Set<Id>();
            for (Notification__c n : plan.driverRows) {
                if (seenRows.add(n.Id)) {
                    markIds.add(n.Id);
                }
            }
            notifIdsByUser.put(u.Id, markIds);

            // Content spans every inbox this login serves. Falls back to the
            // driver rows if the unread snapshot is somehow empty (just-read race).
            List<Notification__c> contentRows = new List<Notification__c>();
            Set<Id> contentInboxesSeen = new Set<Id>();
            for (Id inboxId : plan.inboxIds) {
                List<Notification__c> rows = unreadByInboxRows.get(inboxId);
                if (rows != null && !rows.isEmpty()) {
                    contentRows.addAll(rows);
                    contentInboxesSeen.add(inboxId);
                }
            }
            if (contentRows.isEmpty()) {
                contentRows = plan.driverRows;
                contentInboxesSeen = new Set<Id>();
                for (Notification__c n : plan.driverRows) {
                    contentInboxesSeen.add(n.Contact__c);
                }
            }

            // Who this cycle is FOR, in words. Null means "you" — the ordinary
            // single-identity case, whose copy is unchanged.
            String recipientLabel = buildRecipientLabel(
                contentInboxesSeen, plan.proxiedInboxIds, inboxNameById);
            Boolean singleProxiedInbox = contentInboxesSeen.size() == 1
                && plan.proxiedInboxIds.containsAll(contentInboxesSeen);

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

            Integer badge = 0;
            for (Id inboxId : plan.inboxIds) {
                Integer unread = unreadByInbox.get(inboxId);
                if (unread != null) {
                    badge += unread;
                }
            }
            badge = Math.min(badge, 9999);

            // Single-notification AUDIBLE cycle: send the actual title/body +
            // deep link so the device can route straight to the surface. The
            // Action_URL__c already carries ?actAs= for a proxied inbox, so the
            // tap lands in the right identity without any extra work here.
            // (Quiet refreshes always use the aggregate path so content reflects
            // the whole unread set, never one drifting row.)
            if (plan.hasAudible && markIds.size() == 1 && contentRows.size() == 1) {
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
                    dmPayload.title = buildAggregateTitle(
                        extractRealNames(dmList), 'DM', recipientLabel, singleProxiedInbox);
                    dmPayload.body = buildAggregateBody(dmList.size(), 'DM');
                    dmPayload.notificationType = FimbyPushNotificationService.NotificationType.MESSAGE;
                    // Quiet DM refresh routes to the low-importance channel so a
                    // tag-replacement does not re-alert on Android.
                    dmPayload.data.put('channelId', plan.hasAudible ? 'messages' : 'messages_quiet');
                    dmPayload.collapseId = u.Id + ':dm';
                    if (!plan.hasAudible) {
                        dmPayload.quiet = true;
                    }
                    payloads.add(dmPayload);
                }
                if (contentHasActivity) {
                    FimbyPushNotificationService.PushPayload activityPayload =
                        new FimbyPushNotificationService.PushPayload();
                    activityPayload.userId = u.Id;
                    activityPayload.badge = badge;
                    activityPayload.title = buildAggregateTitle(
                        extractRealNames(activityList), 'ACTIVITY', recipientLabel, singleProxiedInbox);
                    activityPayload.body = buildAggregateBody(activityList.size(), 'ACTIVITY');
                    activityPayload.notificationType = FimbyPushNotificationService.NotificationType.GENERAL;
                    activityPayload.data.put('channelId', 'activity');
                    activityPayload.collapseId = u.Id + ':activity';
                    if (!plan.hasAudible) {
                        activityPayload.quiet = true;
                    }
                    payloads.add(activityPayload);
                }
                // Gate stamp is per USER (it moves the doorbell timestamps), so a
                // mixed audible cycle still stamps BOTH lanes via audibleGate —
                // independent of how many pings were emitted above.
                userGateUpdates.put(u.Id, plan.hasAudible ? audibleGate : 'QUIET');
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

    /* ---------------------------------------------------------------
     * Delivery resolution
     * --------------------------------------------------------------- */

    /**
     * Turns a set of inbox Contacts into a plan per login. A Contact with a login
     * of their own is served by that login alone; a Contact without one is served
     * by every neighbour holding an approved support relationship.
     */
    private Map<Id, DeliveryPlan> resolveDeliveryPlans(Set<Id> inboxIds) {
        Map<Id, User> ownUserByContact = queryPushUsers(inboxIds);

        Set<Id> unbacked = FimbySupportedIdentityDelivery.unbackedContacts(
            inboxIds, ownUserByContact);
        Map<Id, Set<Id>> helpersBySupportee =
            FimbySupportedIdentityDelivery.resolveHelperContacts(unbacked);

        Set<Id> helperContactIds = new Set<Id>();
        for (Set<Id> helpers : helpersBySupportee.values()) {
            helperContactIds.addAll(helpers);
        }
        Map<Id, User> helperUserByContact = queryPushUsers(helperContactIds);

        Map<Id, List<FimbySupportedIdentityDelivery.Target>> targetsByInbox =
            FimbySupportedIdentityDelivery.buildTargets(
                inboxIds, ownUserByContact, helpersBySupportee, helperUserByContact);

        Map<Id, DeliveryPlan> planByUserId = new Map<Id, DeliveryPlan>();
        for (Id inboxId : targetsByInbox.keySet()) {
            for (FimbySupportedIdentityDelivery.Target t : targetsByInbox.get(inboxId)) {
                Id userId = t.userId();
                if (userId == null) {
                    continue;
                }
                if (!planByUserId.containsKey(userId)) {
                    planByUserId.put(userId, new DeliveryPlan(t.u));
                }
                DeliveryPlan plan = planByUserId.get(userId);
                plan.inboxIds.add(inboxId);
                if (t.isProxy == true) {
                    plan.proxiedInboxIds.add(inboxId);
                }
            }
        }
        return planByUserId;
    }

    private Map<Id, User> queryPushUsers(Set<Id> contactIds) {
        Map<Id, User> byContact = new Map<Id, User>();
        if (contactIds == null || contactIds.isEmpty()) {
            return byContact;
        }
        for (User u : [
            SELECT Id, ContactId, TimeZoneSidKey,
                   Quiet_Hours_Preference__c, Last_App_Open_At__c,
                   Include_Sundays__c
            FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            byContact.put(u.ContactId, u);
        }
        return byContact;
    }

    private Map<Id, String> queryInboxNames(Map<Id, DeliveryPlan> planByUserId) {
        Set<Id> proxiedInboxIds = new Set<Id>();
        for (DeliveryPlan plan : planByUserId.values()) {
            proxiedInboxIds.addAll(plan.proxiedInboxIds);
        }
        Map<Id, String> nameById = new Map<Id, String>();
        if (proxiedInboxIds.isEmpty()) {
            return nameById;
        }
        for (Contact c : [
            SELECT Id, FirstName, LastName
            FROM Contact
            WHERE Id IN :proxiedInboxIds
            WITH SYSTEM_MODE
        ]) {
            nameById.put(c.Id, String.isNotBlank(c.FirstName) ? c.FirstName : c.LastName);
        }
        return nameById;
    }

    /**
     * Per-recipient push state. A fanned-out row tracks each helper separately in
     * its delivery ledger, so one guardian being delivered must not stop the other
     * from being retried. Rows with no ledger use the plain channel status.
     */
    @TestVisible
    static String pushStateFor(Notification__c n, Id userId) {
        if (String.isBlank(n.Delivery_State__c)) {
            return n.Push_Status__c;
        }
        FimbySupportedIdentityDelivery.Ledger ledger =
            FimbySupportedIdentityDelivery.parseLedger(n.Delivery_State__c);
        if (ledger == null) {
            return n.Push_Status__c;
        }
        FimbySupportedIdentityDelivery.Recipient rec = ledger.forUser(userId);
        return rec == null ? null : rec.p;
    }

    /* ---------------------------------------------------------------
     * Quiet hours / calendar
     * --------------------------------------------------------------- */

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

    /* ---------------------------------------------------------------
     * Copy
     * --------------------------------------------------------------- */

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
     * Names who this cycle is for. Returns null for the ordinary case where every
     * row belongs to the recipient's own inbox, which keeps the familiar
     * second-person copy untouched.
     *
     * A card that says "Aisha messaged you" when Aisha actually messaged the
     * user's child is worse than vague — it is wrong, and it hides which identity
     * needs attention. So a proxied cycle always names the identity.
     */
    @TestVisible
    static String buildRecipientLabel(
        Set<Id> contentInboxIds, Set<Id> proxiedInboxIds, Map<Id, String> inboxNameById
    ) {
        if (contentInboxIds == null || contentInboxIds.isEmpty()
            || proxiedInboxIds == null || proxiedInboxIds.isEmpty()) {
            return null;
        }

        Boolean includesOwn = false;
        List<String> proxiedNames = new List<String>();
        for (Id inboxId : contentInboxIds) {
            if (proxiedInboxIds.contains(inboxId)) {
                String name = inboxNameById == null ? null : inboxNameById.get(inboxId);
                proxiedNames.add(String.isNotBlank(name) ? name : 'someone you help');
            } else {
                includesOwn = true;
            }
        }

        if (proxiedNames.isEmpty()) {
            return null;
        }
        proxiedNames.sort();

        String joined;
        if (proxiedNames.size() == 1) {
            joined = proxiedNames[0];
        } else if (proxiedNames.size() == 2) {
            joined = proxiedNames[0] + ' and ' + proxiedNames[1];
        } else {
            joined = proxiedNames[0] + ' and ' + (proxiedNames.size() - 1) + ' others';
        }

        return includesOwn ? 'you and ' + joined : joined;
    }

    /**
     * Builds a name-led aggregate push title for a bucket. gateKind ∈
     * {'DM','ACTIVITY','BOTH'}. Falls back to today's generic strings when no
     * real name is available. Always capped at 80 chars on a word boundary.
     */
    @TestVisible
    static String buildAggregateTitle(List<String> names, String gateKind) {
        return buildAggregateTitle(names, gateKind, null, false);
    }

    /**
     * recipientLabel names who the cycle is for; null keeps the second-person
     * copy. singleProxiedInbox means every row belongs to ONE proxied identity,
     * which is the only case where actor-led phrasing stays grammatical
     * ("Aisha messaged Maya"). A mixed cycle switches to audience-led phrasing
     * ("New messages for you and Maya") because no single actor sentence can
     * honestly describe two different inboxes.
     */
    @TestVisible
    static String buildAggregateTitle(
        List<String> names, String gateKind, String recipientLabel, Boolean singleProxiedInbox
    ) {
        if (String.isNotBlank(recipientLabel) && singleProxiedInbox != true) {
            return truncateAtWord(buildAudienceLedTitle(gateKind, recipientLabel), 80);
        }

        String audience = String.isNotBlank(recipientLabel) ? recipientLabel : 'you';
        String title;

        if (names == null || names.isEmpty()) {
            if (String.isNotBlank(recipientLabel)) {
                return truncateAtWord(buildAudienceLedTitle(gateKind, recipientLabel), 80);
            }
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
                title = first + ' messaged ' + audience;
            } else if (count == 2) {
                title = first + ' and ' + names[1] + ' messaged ' + audience;
            } else {
                title = first + ' and ' + (count - 1) + ' others messaged ' + audience;
            }
        } else if (gateKind == 'BOTH') {
            title = first + ' messaged ' + audience + ', plus neighbourhood activity';
        } else {
            String neighbourhood = String.isNotBlank(recipientLabel)
                ? recipientLabel + '\'s neighbourhood' : 'your neighbourhood';
            if (count == 1) {
                title = first + ' posted in ' + neighbourhood;
            } else if (count == 2) {
                title = first + ' and ' + names[1] + ' posted nearby';
            } else {
                title = first + ', plus ' + (count - 1) + ' more updates';
            }
        }
        return truncateAtWord(title, 80);
    }

    private static String buildAudienceLedTitle(String gateKind, String recipientLabel) {
        if (gateKind == 'DM') {
            return 'New messages for ' + recipientLabel;
        }
        if (gateKind == 'BOTH') {
            return 'Messages and activity for ' + recipientLabel;
        }
        return 'Neighbourhood activity for ' + recipientLabel;
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
