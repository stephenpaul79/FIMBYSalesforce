/**
 * @description Applies the post lifecycle contract when an Ask, Offer, or Event closes.
 * Called once per transaction from FimbyNeedsOffersTriggerHandler for every non-Bulk-Buy
 * post that entered Completed, Cancelled, or Expired, whichever path closed it (poster
 * action, end-of-life job, admin edit). Owning it here means a manual close and an
 * automatic close can never both notify the same neighbour.
 *
 * Response transitions:
 *   Parent Completed (Ask/Offer): Accepted -> Completed; New with a poster message -> Completed;
 *                                 other New -> Declined.
 *   Parent Completed (Event):     Accepted -> Completed; New -> Expired, silently.
 *   Parent Expired:               Accepted -> Completed; New -> Expired.
 *   Parent Cancelled:             New or Accepted -> Cancelled.
 *
 * Notifications:
 *   Poster completes:   unresolved Ask/Offer responders once, actor = represented poster.
 *   Poster cancels:     affected New/Accepted responders once, actor = represented poster.
 *   Auto-complete:      poster once (actor FIMBY); unresolved New Ask/Offer responders once.
 *   Auto-expire:        unanswered New Ask/Offer responders once; never the poster or RSVPers.
 */
public without sharing class FimbyPostLifecycleService {

    public static final Set<String> TERMINAL_POST_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_COMPLETED,
        FimbyConstants.NEEDS_OFFERS_CANCELLED,
        FimbyConstants.NEEDS_OFFERS_EXPIRED
    };

    private static final Set<String> OPEN_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_NEW,
        FimbyConstants.RESPONSE_ACCEPTED
    };

    private static final String FIMBY_ACTOR = 'FIMBY';

    private static Set<Id> handledPostIds = new Set<Id>();

    /**
     * @description When true, cascades still run but no closure notifications are sent.
     * Only the one-time cutover reconciliation sets this; neighbours must not receive
     * retroactive notices for posts that closed under the retired Flows.
     */
    public static Boolean suppressNotifications = false;

    /**
     * @description Applies response cascades and curated notifications for closed posts.
     * Each post is handled at most once per transaction.
     * @param closedPosts posts that just entered a terminal status (only Id is required)
     */
    public static void onPostsClosed(List<Needs_Offers__c> closedPosts) {
        if (closedPosts == null || closedPosts.isEmpty()) {
            return;
        }
        Set<Id> scopeIds = new Set<Id>();
        for (Needs_Offers__c post : closedPosts) {
            if (post.Id != null && !handledPostIds.contains(post.Id)) {
                scopeIds.add(post.Id);
            }
        }
        if (scopeIds.isEmpty()) {
            return;
        }
        handledPostIds.addAll(scopeIds);
        Map<Id, Needs_Offers__c> postById = new Map<Id, Needs_Offers__c>([
            SELECT Id, Name, Status__c, Closed_By__c, Contact__c, Posted_By__c, Type__c,
                   RecordType.DeveloperName
            FROM Needs_Offers__c
            WHERE Id IN :scopeIds
              AND RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
              AND Status__c IN :TERMINAL_POST_STATUSES
        ]);
        if (postById.isEmpty()) {
            return;
        }

        List<Response__c> openResponses = [
            SELECT Id, Status__c, Contact__c, On_Behalf_Of_Contact__c, Need_Offer_Responded_To__c,
                   Need_Offer_Responded_To__r.RecordType.DeveloperName
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :postById.keySet()
              AND Status__c IN :OPEN_RESPONSE_STATUSES
            FOR UPDATE
        ];

        Map<Id, Id> messagedPostByResponse = FimbyPostEngagementService.posterMessagedResponses(postById.values());

        Map<Id, String> targetByResponse = new Map<Id, String>();
        for (Response__c resp : openResponses) {
            Needs_Offers__c post = postById.get(resp.Need_Offer_Responded_To__c);
            String target = targetStatus(post, resp, messagedPostByResponse.containsKey(resp.Id));
            if (target != null) {
                targetByResponse.put(resp.Id, target);
            }
        }

        List<Response__c> autoScope = new List<Response__c>();
        List<Response__c> posterScope = new List<Response__c>();
        for (Response__c resp : openResponses) {
            if (isAuto(postById.get(resp.Need_Offer_Responded_To__c))) {
                autoScope.add(resp);
            } else {
                posterScope.add(resp);
            }
        }
        Map<Id, String> previousById = new Map<Id, String>();
        previousById.putAll(FimbyResponseStatusService.applyCascade(
            posterScope, targetByResponse, FimbyResponseStatusService.Source.PARENT_CASCADE));
        previousById.putAll(FimbyResponseStatusService.applyCascade(
            autoScope, targetByResponse, FimbyResponseStatusService.Source.AUTO_LIFECYCLE));

        if (!suppressNotifications) {
            sendNotifications(postById, openResponses, targetByResponse, previousById);
        }
    }

    /**
     * @description Target response status under the lifecycle contract, or null to leave it.
     */
    @TestVisible
    private static String targetStatus(Needs_Offers__c post, Response__c resp, Boolean posterMessaged) {
        Boolean isEvent = post.Type__c == 'Event';
        Boolean isAccepted = resp.Status__c == FimbyConstants.RESPONSE_ACCEPTED;
        Boolean isNew = resp.Status__c == FimbyConstants.RESPONSE_NEW;

        if (post.Status__c == FimbyConstants.NEEDS_OFFERS_CANCELLED) {
            return (isNew || isAccepted) ? FimbyConstants.RESPONSE_CANCELLED : null;
        }
        if (post.Status__c == FimbyConstants.NEEDS_OFFERS_EXPIRED) {
            if (isAccepted) return FimbyConstants.RESPONSE_COMPLETED;
            if (isNew) return FimbyConstants.RESPONSE_EXPIRED;
            return null;
        }
        if (post.Status__c == FimbyConstants.NEEDS_OFFERS_COMPLETED) {
            if (isAccepted) return FimbyConstants.RESPONSE_COMPLETED;
            if (isNew && isEvent) return FimbyConstants.RESPONSE_EXPIRED;
            if (isNew && posterMessaged) return FimbyConstants.RESPONSE_COMPLETED;
            if (isNew) return FimbyConstants.RESPONSE_DECLINED;
        }
        return null;
    }

    private static Boolean isAuto(Needs_Offers__c post) {
        return post.Closed_By__c == FimbyConstants.CLOSED_BY_AUTO
            || post.Status__c == FimbyConstants.NEEDS_OFFERS_EXPIRED;
    }

    /* =====================================================================
     * Notifications
     * ===================================================================== */

    private static void sendNotifications(
        Map<Id, Needs_Offers__c> postById,
        List<Response__c> openResponses,
        Map<Id, String> targetByResponse,
        Map<Id, String> previousById
    ) {
        Map<Id, Contact> posterById = queryPosters(postById.values());
        List<FimbyNotificationService.NotificationRequest> requests =
            new List<FimbyNotificationService.NotificationRequest>();
        Set<String> notifiedKeys = new Set<String>();

        for (Response__c resp : openResponses) {
            if (!previousById.containsKey(resp.Id)) {
                continue;
            }
            Needs_Offers__c post = postById.get(resp.Need_Offer_Responded_To__c);
            String target = targetByResponse.get(resp.Id);
            String previous = previousById.get(resp.Id);
            if (!shouldNotifyResponder(post, previous, target)) {
                continue;
            }
            Id recipient = FimbyPostEngagementService.representedResponder(resp);
            Id posterOwner = FimbyConstants.postOwnerContactId(post);
            String key = post.Id + '|' + recipient;
            if (recipient == null || recipient == posterOwner || notifiedKeys.contains(key)) {
                continue;
            }
            notifiedKeys.add(key);
            requests.add(responderRequest(post, recipient, posterById.get(posterOwner)));
        }

        for (Needs_Offers__c post : postById.values()) {
            if (post.Status__c != FimbyConstants.NEEDS_OFFERS_COMPLETED
                || post.Closed_By__c != FimbyConstants.CLOSED_BY_AUTO) {
                continue;
            }
            Id posterOwner = FimbyConstants.postOwnerContactId(post);
            if (posterOwner == null) {
                continue;
            }
            requests.add(posterAutoCompleteRequest(post, posterOwner));
        }

        FimbyNotificationService.createNotificationsFromRequests(requests, true);
    }

    @TestVisible
    private static Boolean shouldNotifyResponder(Needs_Offers__c post, String previous, String target) {
        Boolean isEvent = post.Type__c == 'Event';
        if (post.Status__c == FimbyConstants.NEEDS_OFFERS_CANCELLED) {
            return !isAuto(post) && target == FimbyConstants.RESPONSE_CANCELLED;
        }
        if (isEvent) {
            return false;
        }
        if (previous != FimbyConstants.RESPONSE_NEW) {
            return false;
        }
        return target == FimbyConstants.RESPONSE_DECLINED || target == FimbyConstants.RESPONSE_EXPIRED;
    }

    private static FimbyNotificationService.NotificationRequest responderRequest(
        Needs_Offers__c post, Id recipient, Contact poster
    ) {
        Boolean isAsk = post.RecordType?.DeveloperName == FimbyConstants.RT_NEED;
        Boolean isEvent = post.Type__c == 'Event';
        Boolean auto = isAuto(post);
        String title;
        String body;

        if (post.Status__c == FimbyConstants.NEEDS_OFFERS_CANCELLED) {
            String noun = isEvent ? 'event' : (isAsk ? 'ask' : 'offer');
            title = 'withdrew their ' + noun;
            body = isEvent
                ? FimbyResponseStatusService.abbreviateTitleInBody('“', post.Name, '” is no longer going ahead.')
                : FimbyResponseStatusService.abbreviateTitleInBody('“', post.Name, '” is no longer open. Thanks for replying.');
        } else {
            body = isAsk
                ? FimbyResponseStatusService.abbreviateTitleInBody(
                    'The ask closed before you heard back. Thanks for offering to help with “', post.Name, '”.')
                : FimbyResponseStatusService.abbreviateTitleInBody(
                    'The offer closed before you heard back. Thanks for letting them know you were interested in “', post.Name, '”.');
            title = auto
                ? (isAsk ? 'An ask you replied to has closed' : 'An offer you replied to has closed')
                : (isAsk ? 'closed their ask' : 'closed their offer');
        }

        Boolean posterIsActor = !auto && poster != null;
        FimbyNotificationService.NotificationRequest req = new FimbyNotificationService.NotificationRequest(
            recipient,
            FimbyConstants.NOTIF_POST_LIFECYCLE_CLOSED,
            title,
            body,
            post.Id,
            'Needs_Offers__c',
            FimbySettings.getUrl('Asks_Offers', post.Id),
            posterIsActor ? displayName(poster) : FIMBY_ACTOR
        );
        if (posterIsActor) {
            req.actorContactId = poster.Id;
        } else if (!auto) {
            req.title = isEvent
                ? 'An event you joined is no longer going ahead'
                : (isAsk ? 'An ask you replied to has closed' : 'An offer you replied to has closed');
        }
        return req;
    }

    private static FimbyNotificationService.NotificationRequest posterAutoCompleteRequest(
        Needs_Offers__c post, Id posterOwner
    ) {
        String outcome = outcomeLabel(post);
        String noun = post.Type__c == 'Event' ? 'event' : (post.RecordType?.DeveloperName == FimbyConstants.RT_NEED ? 'ask' : 'offer');
        String body = post.Type__c == 'Event'
            ? FimbyResponseStatusService.abbreviateTitleInBody('At least one neighbour RSVP’d to “', post.Name, '”, so it now shows as Happened.')
            : FimbyResponseStatusService.abbreviateTitleInBody(
                'A neighbour replied to “', post.Name, '” before it ended, so it now shows as ' + outcome + '.');
        return new FimbyNotificationService.NotificationRequest(
            posterOwner,
            FimbyConstants.NOTIF_POST_LIFECYCLE_CLOSED,
            'Your ' + noun + ' closed as ' + outcome,
            body,
            post.Id,
            'Needs_Offers__c',
            FimbySettings.getUrl('Asks_Offers', post.Id),
            FIMBY_ACTOR
        );
    }

    /**
     * @description Outcome label a completed post shows while it lingers in the feed.
     */
    public static String outcomeLabel(Needs_Offers__c post) {
        if (post == null) {
            return null;
        }
        if (post.RecordType?.DeveloperName == FimbyConstants.RT_BULK_BUY) return 'Purchased';
        if (post.Type__c == 'Event') return 'Happened';
        if (post.RecordType?.DeveloperName == FimbyConstants.RT_NEED) return 'Answered';
        return 'Received';
    }

    private static Map<Id, Contact> queryPosters(List<Needs_Offers__c> posts) {
        Set<Id> ids = new Set<Id>();
        for (Needs_Offers__c post : posts) {
            Id owner = FimbyConstants.postOwnerContactId(post);
            if (owner != null) {
                ids.add(owner);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, Contact>();
        }
        return new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Is_Organization_Contact__c, Organization_Account__r.Name
            FROM Contact
            WHERE Id IN :ids
        ]);
    }

    private static String displayName(Contact c) {
        if (c == null) {
            return 'A neighbour';
        }
        if (c.Is_Organization_Contact__c == true && String.isNotBlank(c.Organization_Account__r?.Name)) {
            return c.Organization_Account__r.Name;
        }
        String name = ((c.FirstName != null ? c.FirstName : '') + ' ' + (c.LastName != null ? c.LastName : '')).trim();
        return String.isNotBlank(name) ? name : 'A neighbour';
    }
}
