/**
 * @description The one place a Response__c changes status. Interactive transitions (poster
 * accepts/declines/completes, responder withdraws) and parent-driven cascades both pass
 * through here, so counters, Completed_Date__c, system messages, unread counts,
 * notifications, and auto-share behave the same way on every path.
 *
 * Lock order is always parent Needs_Offers__c first, then Response__c, matching the
 * create, accept, and end-of-life paths so concurrent taps cannot deadlock.
 *
 * Bulk Buy reservations never use this matrix; FimbyBulkBuyController owns them.
 */
public without sharing class FimbyResponseStatusService {

    public enum Source { RESPONDER, POSTER, PARENT_CASCADE, AUTO_LIFECYCLE }

    public class StatusException extends Exception {}

    public class Outcome {
        public Boolean success = false;
        public String error;
        public String message;
        public String newStatus;

        public Map<String, Object> toMap() {
            Map<String, Object> m = new Map<String, Object>{
                'success' => success,
                'message' => message
            };
            if (success) {
                m.put('newStatus', newStatus);
            } else {
                m.put('error', error);
            }
            return m;
        }
    }

    public static final Set<String> ACTIVE_PARENT_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_AVAILABLE,
        FimbyConstants.NEEDS_OFFERS_SUBMITTED,
        FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED,
        FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED
    };

    private static final Map<String, Set<String>> POSTER_MATRIX = new Map<String, Set<String>>{
        FimbyConstants.RESPONSE_ACCEPTED  => new Set<String>{ FimbyConstants.RESPONSE_NEW },
        FimbyConstants.RESPONSE_DECLINED  => new Set<String>{ FimbyConstants.RESPONSE_NEW },
        FimbyConstants.RESPONSE_COMPLETED => new Set<String>{ FimbyConstants.RESPONSE_ACCEPTED }
    };

    private static final Map<String, Set<String>> RESPONDER_MATRIX = new Map<String, Set<String>>{
        FimbyConstants.RESPONSE_CANCELLED => new Set<String>{
            FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED
        }
    };

    private static final Map<String, Set<String>> CASCADE_MATRIX = new Map<String, Set<String>>{
        FimbyConstants.RESPONSE_COMPLETED => new Set<String>{
            FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED
        },
        FimbyConstants.RESPONSE_DECLINED  => new Set<String>{ FimbyConstants.RESPONSE_NEW },
        FimbyConstants.RESPONSE_EXPIRED   => new Set<String>{ FimbyConstants.RESPONSE_NEW },
        FimbyConstants.RESPONSE_CANCELLED => new Set<String>{
            FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED
        }
    };

    /* =====================================================================
     * Interactive transitions
     * ===================================================================== */

    /**
     * @description Poster or responder status change from the UI. Strict: any failure in the
     * transaction (counter, system message, notification, auto-share) throws and rolls back.
     * @param responseId response to change
     * @param newStatus target status
     * @param origin POSTER or RESPONDER
     */
    public static Outcome changeStatus(Id responseId, String newStatus, Source origin) {
        Context ctx = loadAndAuthorize(responseId, origin);
        if (ctx.failure != null) {
            return ctx.failure;
        }
        Outcome matrixFailure = checkMatrix(ctx, newStatus, origin);
        if (matrixFailure != null) {
            return matrixFailure;
        }
        applyInteractive(ctx, newStatus, origin, true, 1);
        return success(newStatus, systemMessageBody(newStatus, ctx.actorName));
    }

    /**
     * @description Poster sends a message and accepts in one transaction: one message, one
     * Accepted transition, one system message, one combined notification to the responder.
     */
    public static Outcome sendMessageAndAccept(Id responseId, String body) {
        if (String.isBlank(body)) {
            return failure('invalidInput', 'Please write a message before sending.');
        }
        Context ctx = loadAndAuthorize(responseId, Source.POSTER);
        if (ctx.failure != null) {
            return ctx.failure;
        }
        Outcome matrixFailure = checkMatrix(ctx, FimbyConstants.RESPONSE_ACCEPTED, Source.POSTER);
        if (matrixFailure != null) {
            return matrixFailure;
        }

        insert new Response_Message__c(
            Response__c = ctx.resp.Id,
            Body__c = body.left(5000),
            Sender__c = ctx.actingAsContactId,
            Sent_By__c = ctx.realContactId,
            Sent_Date__c = Datetime.now(),
            Is_System_Message__c = false
        );

        applyInteractive(ctx, FimbyConstants.RESPONSE_ACCEPTED, Source.POSTER, false, 2, body);

        String snippet = body.length() > 100 ? body.substring(0, 100) + '...' : body;
        notifyCounterpart(ctx, 'accepted your response',
            abbreviateTitleInBody('On “', ctx.post.Name, '”: “' + snippet + '”'));

        return success(FimbyConstants.RESPONSE_ACCEPTED, 'Message sent and response accepted');
    }

    /**
     * @description Quick-event withdraw: the caller already holds the parent and response
     * locks and sends its own one-tap notification. Applies the Cancelled status and the
     * responder-withdrawal counter reversal through the same counter path as the thread.
     * @param resp locked response with Status__c, Contact__c, On_Behalf_Of_Contact__c
     * @param parentRecordTypeName parent record type developer name used for counters
     */
    public static void applyQuietResponderWithdrawal(Response__c resp, String parentRecordTypeName) {
        Set<String> validFrom = RESPONDER_MATRIX.get(FimbyConstants.RESPONSE_CANCELLED);
        if (resp == null || !validFrom.contains(resp.Status__c)) {
            return;
        }
        String oldStatus = resp.Status__c;
        update new Response__c(Id = resp.Id, Status__c = FimbyConstants.RESPONSE_CANCELLED);
        FimbyCounterService.ResponseStatusDelta delta = new FimbyCounterService.ResponseStatusDelta(
            resp.Contact__c, parentRecordTypeName, isActingAsOther(resp), oldStatus, FimbyConstants.RESPONSE_CANCELLED
        );
        delta.isResponderWithdrawal = true;
        FimbyCounterService.onResponseStatusesChanged(new List<FimbyCounterService.ResponseStatusDelta>{ delta }, true);
        resp.Status__c = FimbyConstants.RESPONSE_CANCELLED;
    }

    /* =====================================================================
     * Parent cascade (bulk)
     * ===================================================================== */

    /**
     * @description Applies lifecycle-driven terminal transitions in bulk. No per-response
     * notifications or system messages; FimbyPostLifecycleService sends the curated set.
     * Strict: a failure rolls back the parent status change that caused the cascade.
     * @param responses responses with Status__c, Contact__c, On_Behalf_Of_Contact__c, and
     *        Need_Offer_Responded_To__r.RecordType.DeveloperName selected
     * @param targetByResponseId target status per response Id
     * @param origin PARENT_CASCADE (poster closed) or AUTO_LIFECYCLE (job closed)
     * @return responses that actually changed, with their previous status
     */
    public static Map<Id, String> applyCascade(
        List<Response__c> responses, Map<Id, String> targetByResponseId, Source origin
    ) {
        Map<Id, String> previousById = new Map<Id, String>();
        if (responses == null || responses.isEmpty() || targetByResponseId == null) {
            return previousById;
        }
        List<Response__c> updates = new List<Response__c>();
        List<FimbyCounterService.ResponseStatusDelta> deltas = new List<FimbyCounterService.ResponseStatusDelta>();
        Datetime now = Datetime.now();

        for (Response__c resp : responses) {
            String target = targetByResponseId.get(resp.Id);
            if (target == null || target == resp.Status__c) {
                continue;
            }
            Set<String> validFrom = CASCADE_MATRIX.get(target);
            if (validFrom == null || !validFrom.contains(resp.Status__c)) {
                continue;
            }
            Response__c upd = new Response__c(Id = resp.Id, Status__c = target);
            if (target == FimbyConstants.RESPONSE_COMPLETED) {
                upd.Completed_Date__c = now;
            }
            updates.add(upd);
            previousById.put(resp.Id, resp.Status__c);
            deltas.add(new FimbyCounterService.ResponseStatusDelta(
                resp.Contact__c,
                resp.Need_Offer_Responded_To__r?.RecordType?.DeveloperName,
                isActingAsOther(resp),
                resp.Status__c,
                target
            ));
        }
        if (updates.isEmpty()) {
            return previousById;
        }
        update updates;
        FimbyCounterService.onResponseStatusesChanged(deltas, true);
        return previousById;
    }

    /* =====================================================================
     * Internals
     * ===================================================================== */

    private class Context {
        Response__c resp;
        Needs_Offers__c post;
        Id actingAsContactId;
        Id realContactId;
        String actorName;
        Boolean isPoster = false;
        Boolean isResponder = false;
        Source origin;
        Outcome failure;
    }

    private static Context loadAndAuthorize(Id responseId, Source origin) {
        Context ctx = new Context();
        ctx.origin = origin;
        if (responseId == null) {
            ctx.failure = failure('noRecordId', 'No response selected.');
            return ctx;
        }
        FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
        if (identity == null) {
            ctx.failure = failure('noIdentity', 'Unable to determine your identity.');
            return ctx;
        }
        ctx.actingAsContactId = identity.actingAsContactId;
        ctx.realContactId = identity.contact?.Id != null ? identity.contact.Id : identity.currentUser?.ContactId;
        ctx.actorName = identity.orgDisplayName;

        List<Response__c> peek = [
            SELECT Need_Offer_Responded_To__c FROM Response__c WHERE Id = :responseId LIMIT 1
        ];
        if (peek.isEmpty()) {
            ctx.failure = failure('notFound', 'Response not found.');
            return ctx;
        }
        List<Needs_Offers__c> parents = [
            SELECT Id, Name, Status__c, Contact__c, Posted_By__c, Type__c, Event_Type__c,
                   RecordType.DeveloperName
            FROM Needs_Offers__c
            WHERE Id = :peek[0].Need_Offer_Responded_To__c
            FOR UPDATE
        ];
        if (parents.isEmpty()) {
            ctx.failure = failure('notFound', 'Post not found.');
            return ctx;
        }
        ctx.post = parents[0];
        ctx.resp = [
            SELECT Id, Name, Status__c, Contact__c, On_Behalf_Of_Contact__c,
                   Poster_Unread_Count__c, Responder_Unread_Count__c,
                   Need_Offer_Responded_To__c
            FROM Response__c
            WHERE Id = :responseId
            FOR UPDATE
        ];

        ctx.isPoster = FimbyConstants.isPostOwner(ctx.post, ctx.actingAsContactId, ctx.realContactId);
        ctx.isResponder = (ctx.resp.On_Behalf_Of_Contact__c != null
                && ctx.resp.On_Behalf_Of_Contact__c == ctx.actingAsContactId)
            || (ctx.resp.Contact__c != null
                && (ctx.resp.Contact__c == ctx.actingAsContactId || ctx.resp.Contact__c == ctx.realContactId));

        if (ctx.post.RecordType?.DeveloperName == FimbyConstants.RT_BULK_BUY) {
            ctx.failure = failure('invalidTransition', 'Reservations are managed from the bulk buy.');
        } else if (origin == Source.POSTER && !ctx.isPoster) {
            ctx.failure = failure('notAuthorized', 'Only the poster can perform this action.');
        } else if (origin == Source.RESPONDER && !ctx.isResponder) {
            ctx.failure = failure('notAuthorized', 'Only the respondee can perform this action.');
        }
        return ctx;
    }

    private static Outcome checkMatrix(Context ctx, String newStatus, Source origin) {
        Map<String, Set<String>> matrix = origin == Source.POSTER ? POSTER_MATRIX : RESPONDER_MATRIX;
        Set<String> validFrom = matrix.get(newStatus);
        if (validFrom == null || !validFrom.contains(ctx.resp.Status__c)) {
            return failure('invalidTransition',
                'Cannot change from ' + ctx.resp.Status__c + ' to ' + newStatus + '.');
        }
        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED && !ACTIVE_PARENT_STATUSES.contains(ctx.post.Status__c)) {
            return failure('postClosed', 'This post is no longer open.');
        }
        return null;
    }

    private static void applyInteractive(
        Context ctx, String newStatus, Source origin, Boolean notify, Integer unreadIncrement
    ) {
        applyInteractive(ctx, newStatus, origin, notify, unreadIncrement, null);
    }

    private static void applyInteractive(
        Context ctx, String newStatus, Source origin, Boolean notify, Integer unreadIncrement, String lastReply
    ) {
        String oldStatus = ctx.resp.Status__c;
        Response__c upd = new Response__c(Id = ctx.resp.Id, Status__c = newStatus);
        if (newStatus == FimbyConstants.RESPONSE_COMPLETED) {
            upd.Completed_Date__c = Datetime.now();
        }
        if (origin == Source.POSTER) {
            upd.Responder_Unread_Count__c = nz(ctx.resp.Responder_Unread_Count__c) + unreadIncrement;
            upd.Responder_Archived__c = false;
        } else {
            upd.Poster_Unread_Count__c = nz(ctx.resp.Poster_Unread_Count__c) + unreadIncrement;
            upd.Poster_Archived__c = false;
        }
        if (String.isNotBlank(lastReply)) {
            upd.Last_Reply__c = lastReply.left(255);
            upd.Last_Reply_Date__c = Date.today();
            upd.Last_Reply_Contact_Lookup__c = ctx.actingAsContactId;
        }
        update upd;

        FimbyCounterService.ResponseStatusDelta delta = new FimbyCounterService.ResponseStatusDelta(
            ctx.resp.Contact__c, ctx.post.RecordType?.DeveloperName, isActingAsOther(ctx.resp), oldStatus, newStatus
        );
        delta.isResponderWithdrawal = origin == Source.RESPONDER && newStatus == FimbyConstants.RESPONSE_CANCELLED;
        FimbyCounterService.onResponseStatusesChanged(new List<FimbyCounterService.ResponseStatusDelta>{ delta }, true);

        insert new Response_Message__c(
            Response__c = ctx.resp.Id,
            Body__c = systemMessageBody(newStatus, ctx.actorName),
            Sender__c = ctx.actingAsContactId,
            Sent_Date__c = Datetime.now(),
            Is_System_Message__c = true,
            System_Message_Type__c = 'Status_Change'
        );

        if (notify) {
            notifyCounterpart(ctx, notificationTitle(newStatus),
                abbreviateTitleInBody(notificationBodyPrefix(newStatus), ctx.post.Name, '”.'));
        }

        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED && origin == Source.POSTER) {
            FimbyResponseAutoShareHelper.autoShareOnAccept(ctx.resp.Id, true);
        }
    }

    private static void notifyCounterpart(Context ctx, String title, String body) {
        Id recipient = ctx.origin == Source.POSTER
            ? FimbyPostEngagementService.representedResponder(ctx.resp)
            : FimbyConstants.postOwnerContactId(ctx.post);
        if (recipient == null || recipient == ctx.actingAsContactId) {
            return;
        }
        FimbyNotificationService.NotificationRequest req = new FimbyNotificationService.NotificationRequest(
            recipient,
            FimbyConstants.NOTIF_RESPONSE,
            title,
            body,
            ctx.resp.Id,
            'Response__c',
            FimbySettings.getUrl('Response_Reply', null, '?recordId=' + ctx.resp.Id),
            String.isNotBlank(ctx.actorName) ? ctx.actorName : 'A neighbour'
        );
        req.actorContactId = ctx.actingAsContactId;
        FimbyNotificationService.createNotificationsFromRequests(
            new List<FimbyNotificationService.NotificationRequest>{ req }, true);
    }

    @TestVisible
    private static String systemMessageBody(String newStatus, String actorName) {
        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) return 'Response accepted';
        if (newStatus == FimbyConstants.RESPONSE_DECLINED) return 'Response declined';
        if (newStatus == FimbyConstants.RESPONSE_CANCELLED) {
            return (String.isNotBlank(actorName) ? actorName : 'The neighbour') + ' cancelled their response';
        }
        if (newStatus == FimbyConstants.RESPONSE_COMPLETED) return 'Response marked as complete';
        return 'Status changed to ' + newStatus;
    }

    private static String notificationTitle(String newStatus) {
        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) return 'accepted your response';
        if (newStatus == FimbyConstants.RESPONSE_DECLINED) return 'isn\'t able to go ahead with your response';
        if (newStatus == FimbyConstants.RESPONSE_CANCELLED) return 'withdrew their response';
        if (newStatus == FimbyConstants.RESPONSE_COMPLETED) return 'marked your response complete';
        return 'updated your response';
    }

    private static String notificationBodyPrefix(String newStatus) {
        if (newStatus == FimbyConstants.RESPONSE_DECLINED) return 'Thanks for replying to “';
        return 'On “';
    }

    /**
     * @description Builds prefix + title + suffix within the 140-char body cap by shortening
     * only the post title, so the sentence frame always survives.
     */
    public static String abbreviateTitleInBody(String prefix, String postTitle, String suffix) {
        String title = String.isNotBlank(postTitle) ? postTitle : 'your post';
        Integer room = 140 - prefix.length() - suffix.length();
        if (room < 4) {
            return (prefix + title + suffix).abbreviate(140);
        }
        return prefix + title.abbreviate(room) + suffix;
    }

    private static Boolean isActingAsOther(Response__c resp) {
        return resp.On_Behalf_Of_Contact__c != null && resp.On_Behalf_Of_Contact__c != resp.Contact__c;
    }

    private static Decimal nz(Decimal value) {
        return value != null ? value : 0;
    }

    private static Outcome success(String newStatus, String message) {
        Outcome o = new Outcome();
        o.success = true;
        o.newStatus = newStatus;
        o.message = message;
        return o;
    }

    private static Outcome failure(String error, String message) {
        Outcome o = new Outcome();
        o.error = error;
        o.message = message;
        return o;
    }
}
