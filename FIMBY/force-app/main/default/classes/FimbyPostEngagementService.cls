/**
 * @description Single source of truth for how much a post has been engaged with. Feed cards,
 * the end-of-life job, the refresh reminder, and the reply nudge all classify posts here so
 * "replied", "matched", and "engaged" never drift apart between surfaces.
 *
 * Engagement by type:
 *   Ask/Offer — an Accepted/Completed response, or a non-system message in a response thread
 *               sent by the represented poster (Sender__c = Contact__c) or the real poster
 *               (Sent_By__c = Posted_By__c).
 *   Event     — any active RSVP or interest (New, Accepted, Completed).
 *
 * All reads are set-based: one post query, one response query, one message query, however
 * many posts are passed in.
 */
public without sharing class FimbyPostEngagementService {

    public static final Set<String> ACTIVE_REPLY_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_NEW,
        FimbyConstants.RESPONSE_ACCEPTED,
        FimbyConstants.RESPONSE_COMPLETED
    };

    public static final Set<String> ACCEPTED_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_ACCEPTED,
        FimbyConstants.RESPONSE_COMPLETED
    };

    private static final Set<String> BULK_BUY_VIEWER_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_RESERVED
    };

    public class Summary {
        public Id postId;
        public Integer replyCount = 0;
        public Decimal acceptedQuantity = 0;
        public Boolean viewerHasActiveResponse = false;
        public Boolean hasAcceptedResponse = false;
        public Boolean hasPosterConversation = false;
        public Boolean hasActiveRsvp = false;
        public Boolean isEvent = false;
        public Boolean isBulkBuy = false;

        /**
         * @description True when the post ended with real neighbour engagement and should
         * auto-complete rather than expire.
         */
        public Boolean isEngaged() {
            if (isBulkBuy) {
                return false;
            }
            if (isEvent) {
                return hasActiveRsvp;
            }
            return hasAcceptedResponse || hasPosterConversation;
        }
    }

    /**
     * @description Summarizes engagement for each post.
     * @param postIds posts to summarize
     * @param actingAsContactId represented viewer for viewerHasActiveResponse; null skips viewer state
     * @return summary per post Id (every requested post that exists gets an entry)
     */
    public static Map<Id, Summary> summarize(Set<Id> postIds, Id actingAsContactId) {
        Map<Id, Summary> result = new Map<Id, Summary>();
        if (postIds == null || postIds.isEmpty()) {
            return result;
        }

        Map<Id, Needs_Offers__c> posts = new Map<Id, Needs_Offers__c>([
            SELECT Id, Contact__c, Posted_By__c, Type__c, RecordType.DeveloperName
            FROM Needs_Offers__c
            WHERE Id IN :postIds
        ]);
        for (Needs_Offers__c post : posts.values()) {
            Summary s = new Summary();
            s.postId = post.Id;
            s.isEvent = post.Type__c == 'Event';
            s.isBulkBuy = post.RecordType?.DeveloperName == FimbyConstants.RT_BULK_BUY;
            result.put(post.Id, s);
        }
        if (result.isEmpty()) {
            return result;
        }

        Set<String> statuses = new Set<String>(ACTIVE_REPLY_STATUSES);
        statuses.addAll(BULK_BUY_VIEWER_STATUSES);
        Map<Id, Set<Id>> repliersByPost = new Map<Id, Set<Id>>();
        for (Response__c resp : [
            SELECT Id, Need_Offer_Responded_To__c, Status__c, Amount_Requested__c,
                   Contact__c, On_Behalf_Of_Contact__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :result.keySet()
              AND Status__c IN :statuses
        ]) {
            Summary s = result.get(resp.Need_Offer_Responded_To__c);
            Id represented = representedResponder(resp);
            Boolean isActiveReply = ACTIVE_REPLY_STATUSES.contains(resp.Status__c);

            if (actingAsContactId != null && represented == actingAsContactId) {
                Boolean viewerActive = s.isBulkBuy
                    ? BULK_BUY_VIEWER_STATUSES.contains(resp.Status__c)
                    : isActiveReply;
                if (viewerActive) {
                    s.viewerHasActiveResponse = true;
                }
            }
            if (s.isBulkBuy || !isActiveReply) {
                continue;
            }

            s.hasActiveRsvp = true;
            if (represented != null) {
                if (!repliersByPost.containsKey(s.postId)) {
                    repliersByPost.put(s.postId, new Set<Id>());
                }
                repliersByPost.get(s.postId).add(represented);
            }
            if (ACCEPTED_STATUSES.contains(resp.Status__c)) {
                s.hasAcceptedResponse = true;
                s.acceptedQuantity += resp.Amount_Requested__c != null ? resp.Amount_Requested__c : 0;
            }
        }
        for (Id postId : repliersByPost.keySet()) {
            result.get(postId).replyCount = repliersByPost.get(postId).size();
        }

        Map<Id, Id> postByMessagedResponse = posterMessagedResponses(posts.values());
        for (Id postId : postByMessagedResponse.values()) {
            result.get(postId).hasPosterConversation = true;
        }
        return result;
    }

    /**
     * @description Responses whose thread holds a genuine (non-system) message from the poster,
     * via either the represented poster or the real author.
     * @param posts posts with Contact__c and Posted_By__c selected
     * @return parent post Id keyed by response Id
     */
    public static Map<Id, Id> posterMessagedResponses(List<Needs_Offers__c> posts) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (posts == null || posts.isEmpty()) {
            return result;
        }
        Set<Id> postIds = new Set<Id>();
        Set<Id> posterContactIds = new Set<Id>();
        Map<Id, Needs_Offers__c> postById = new Map<Id, Needs_Offers__c>();
        for (Needs_Offers__c post : posts) {
            postIds.add(post.Id);
            postById.put(post.Id, post);
            if (post.Contact__c != null) {
                posterContactIds.add(post.Contact__c);
            }
            if (post.Posted_By__c != null) {
                posterContactIds.add(post.Posted_By__c);
            }
        }
        if (posterContactIds.isEmpty()) {
            return result;
        }
        for (Response_Message__c msg : [
            SELECT Response__c, Response__r.Need_Offer_Responded_To__c, Sender__c, Sent_By__c
            FROM Response_Message__c
            WHERE Response__r.Need_Offer_Responded_To__c IN :postIds
              AND Is_System_Message__c = false
              AND (Sender__c IN :posterContactIds OR Sent_By__c IN :posterContactIds)
        ]) {
            Needs_Offers__c post = postById.get(msg.Response__r.Need_Offer_Responded_To__c);
            if (post == null) {
                continue;
            }
            Boolean fromRepresentedPoster = post.Contact__c != null && msg.Sender__c == post.Contact__c;
            Boolean fromRealPoster = post.Posted_By__c != null && msg.Sent_By__c == post.Posted_By__c;
            if (fromRepresentedPoster || fromRealPoster) {
                result.put(msg.Response__c, post.Id);
            }
        }
        return result;
    }

    /**
     * @description The identity a response belongs to. Legacy rows predate On_Behalf_Of_Contact__c.
     */
    public static Id representedResponder(Response__c resp) {
        if (resp == null) {
            return null;
        }
        return resp.On_Behalf_Of_Contact__c != null ? resp.On_Behalf_Of_Contact__c : resp.Contact__c;
    }

    /**
     * @description Ask/Offer is matched when it has a target quantity and accepted replies cover it.
     * A post with no quantity is never "matched"; it shows the reply-count pill instead.
     */
    public static Boolean isMatched(Decimal totalQuantity, Decimal acceptedQuantity) {
        return totalQuantity != null && totalQuantity > 0
            && acceptedQuantity != null && acceptedQuantity >= totalQuantity;
    }
}
