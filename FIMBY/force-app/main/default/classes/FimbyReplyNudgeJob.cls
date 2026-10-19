/**
 * @description Sends the poster one gentle reminder when a neighbour's reply has waited at
 * least Reply_Nudge_Hours__c without a poster message. One nudge per post, ever:
 * Last_Reply_Nudge_Date__c is stamped and never cleared.
 *
 * Schedule daily (America/Vancouver scheduling user):
 *   System.schedule('FIMBY Reply Nudges', '0 15 9 * * ?', new FimbyReplyNudgeJob());
 * Controlled run for QA (admin anonymous Apex):
 *   Database.executeBatch(new FimbyReplyNudgeJob(new Set<Id>{ postId }, Datetime.now()), 50);
 */
public without sharing class FimbyReplyNudgeJob implements Schedulable, Database.Batchable<SObject> {

    public static final Set<String> NUDGEABLE_POST_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_SUBMITTED,
        FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED,
        FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED
    };

    private final Set<Id> scopePostIds;
    private final Datetime asOf;

    public FimbyReplyNudgeJob() {
        this(null, null);
    }

    public FimbyReplyNudgeJob(Set<Id> scopePostIds, Datetime asOf) {
        this.scopePostIds = scopePostIds;
        this.asOf = asOf;
    }

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new FimbyReplyNudgeJob(scopePostIds, asOf), 50);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<Id> scope = scopePostIds;
        Set<String> statuses = NUDGEABLE_POST_STATUSES;
        String soql = 'SELECT Id FROM Needs_Offers__c'
            + ' WHERE RecordType.DeveloperName != \'' + FimbyConstants.RT_BULK_BUY + '\''
            + ' AND Status__c IN :statuses'
            + ' AND Last_Reply_Nudge_Date__c = null';
        if (scope != null) {
            soql += ' AND Id IN :scope';
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<Needs_Offers__c> scope) {
        Datetime effectiveAsOf = asOf != null ? asOf : Datetime.now();
        List<Needs_Offers__c> posts = [
            SELECT Id, Name, Contact__c, Posted_By__c, Type__c, RecordType.DeveloperName
            FROM Needs_Offers__c
            WHERE Id IN :new Map<Id, Needs_Offers__c>(scope).keySet()
              AND Status__c IN :NUDGEABLE_POST_STATUSES
              AND Last_Reply_Nudge_Date__c = null
            FOR UPDATE
        ];
        Map<Id, List<Response__c>> eligible = eligibleResponsesByPost(posts, effectiveAsOf);
        if (eligible.isEmpty()) {
            return;
        }

        List<FimbyNotificationService.NotificationRequest> requests = new List<FimbyNotificationService.NotificationRequest>();
        List<Needs_Offers__c> stamps = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : posts) {
            List<Response__c> waiting = eligible.get(post.Id);
            Id recipient = FimbyConstants.postOwnerContactId(post);
            if (waiting == null || waiting.isEmpty() || recipient == null) {
                continue;
            }
            requests.add(buildRequest(post, recipient, waiting));
            stamps.add(new Needs_Offers__c(Id = post.Id, Last_Reply_Nudge_Date__c = effectiveAsOf.date()));
        }
        FimbyNotificationService.createNotificationsFromRequests(requests, true);
        update stamps;
    }

    public void finish(Database.BatchableContext bc) {
    }

    /**
     * @description New replies at least Reply_Nudge_Hours__c old with no poster-authored message,
     * grouped by post. Pre-cutover replies with legacy Last_Reply_Date__c activity but no
     * Response_Message__c are ambiguous Chatter conversations and are never nudged.
     * @param posts posts with Contact__c and Posted_By__c selected
     * @param asOf reference time
     */
    public static Map<Id, List<Response__c>> eligibleResponsesByPost(List<Needs_Offers__c> posts, Datetime asOf) {
        Map<Id, List<Response__c>> result = new Map<Id, List<Response__c>>();
        if (posts == null || posts.isEmpty()) {
            return result;
        }
        Datetime threshold = (asOf != null ? asOf : Datetime.now()).addHours(-FimbySettings.replyNudgeHours());
        Set<Id> postIds = new Map<Id, Needs_Offers__c>(posts).keySet();

        List<Response__c> candidates = [
            SELECT Id, Need_Offer_Responded_To__c, Last_Reply_Date__c, Contact__c, On_Behalf_Of_Contact__c,
                   Contact__r.FirstName, Contact__r.LastName, Contact__r.Is_Organization_Contact__c,
                   Contact__r.Organization_Account__r.Name,
                   On_Behalf_Of_Contact__r.FirstName, On_Behalf_Of_Contact__r.LastName,
                   On_Behalf_Of_Contact__r.Is_Organization_Contact__c,
                   On_Behalf_Of_Contact__r.Organization_Account__r.Name
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :postIds
              AND Status__c = :FimbyConstants.RESPONSE_NEW
              AND CreatedDate <= :threshold
            ORDER BY CreatedDate ASC
        ];
        if (candidates.isEmpty()) {
            return result;
        }

        Map<Id, Id> posterMessaged = FimbyPostEngagementService.posterMessagedResponses(posts);
        Set<Id> legacyAmbiguous = legacyAmbiguousResponses(candidates);
        for (Response__c resp : candidates) {
            if (posterMessaged.containsKey(resp.Id) || legacyAmbiguous.contains(resp.Id)) {
                continue;
            }
            if (!result.containsKey(resp.Need_Offer_Responded_To__c)) {
                result.put(resp.Need_Offer_Responded_To__c, new List<Response__c>());
            }
            result.get(resp.Need_Offer_Responded_To__c).add(resp);
        }
        return result;
    }

    /**
     * @description Responses with legacy reply activity but no Response_Message__c rows.
     */
    public static Set<Id> legacyAmbiguousResponses(List<Response__c> responses) {
        Set<Id> withLegacyActivity = new Set<Id>();
        for (Response__c resp : responses) {
            if (resp.Last_Reply_Date__c != null) {
                withLegacyActivity.add(resp.Id);
            }
        }
        if (withLegacyActivity.isEmpty()) {
            return withLegacyActivity;
        }
        for (AggregateResult ar : [
            SELECT Response__c rid FROM Response_Message__c
            WHERE Response__c IN :withLegacyActivity
            GROUP BY Response__c
        ]) {
            withLegacyActivity.remove((Id) ar.get('rid'));
        }
        return withLegacyActivity;
    }

    private static FimbyNotificationService.NotificationRequest buildRequest(
        Needs_Offers__c post, Id recipient, List<Response__c> waiting
    ) {
        Set<Id> uniqueResponders = new Set<Id>();
        for (Response__c resp : waiting) {
            uniqueResponders.add(FimbyPostEngagementService.representedResponder(resp));
        }
        if (uniqueResponders.size() == 1) {
            Response__c resp = waiting[0];
            Contact who = resp.On_Behalf_Of_Contact__c != null ? resp.On_Behalf_Of_Contact__r : resp.Contact__r;
            FimbyNotificationService.NotificationRequest req = new FimbyNotificationService.NotificationRequest(
                recipient,
                FimbyConstants.NOTIF_RESPONSE_REMINDER,
                'is waiting to hear back',
                FimbyResponseStatusService.abbreviateTitleInBody(
                    'They replied to “', post.Name, '”. A quick reply lets them know where things stand.'),
                resp.Id,
                'Response__c',
                FimbySettings.getUrl('Response_Reply', null, '?recordId=' + resp.Id),
                displayName(who)
            );
            req.actorContactId = FimbyPostEngagementService.representedResponder(resp);
            return req;
        }
        return new FimbyNotificationService.NotificationRequest(
            recipient,
            FimbyConstants.NOTIF_RESPONSE_REMINDER,
            uniqueResponders.size() + ' neighbours are waiting to hear back',
            FimbyResponseStatusService.abbreviateTitleInBody(
                'They replied to “', post.Name, '”. Take a look when you have a moment.'),
            post.Id,
            'Needs_Offers__c',
            FimbySettings.getUrl('Asks_Offers', post.Id),
            'FIMBY'
        );
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
