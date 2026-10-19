/**
 * @description Closes Asks, Offers, and Events the day after they end. Replaces the
 * Mark_Old_Posts_as_Expired and Update_Response_Status_Daily Flows.
 *
 *   Engaged   -> Completed (Answered / Received / Happened), Closed_By__c = Auto
 *   Unengaged -> Expired, Closed_By__c = Auto
 *
 * Effective end date (inclusive; a post closes once it is strictly in the past):
 *   Ask   End_Date__c, else Posted_Date__c / CreatedDate + Need_Default_End_Days__c (14)
 *   Offer End_Date__c, else Posted_Date__c / CreatedDate + Offer_Default_End_Days__c (21)
 *   Event End_Date__c, else Start_Date__c; never from posting age
 *
 * Bulk Buys are excluded; their own jobs own reservation accountability. Posts holding a
 * pre-cutover reply with legacy activity but no Response_Message__c are skipped and logged
 * for manual review. Reruns are idempotent because only active posts are selected.
 *
 * Schedule daily (America/Vancouver scheduling user), only after cutover reconciliation:
 *   System.schedule('FIMBY Post End of Life', '0 15 0 * * ?', new FimbyPostEndOfLifeJob());
 * Controlled run for QA (admin anonymous Apex):
 *   Database.executeBatch(new FimbyPostEndOfLifeJob(new Set<Id>{ postId }, Date.today()), 10);
 */
public without sharing class FimbyPostEndOfLifeJob implements Schedulable, Database.Batchable<SObject>, Database.Stateful {

    public static final Set<String> OPEN_POST_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_AVAILABLE,
        FimbyConstants.NEEDS_OFFERS_SUBMITTED,
        FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED,
        FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED
    };

    private final Set<Id> scopePostIds;
    private final Date asOfDate;

    @TestVisible private Integer completedCount = 0;
    @TestVisible private Integer expiredCount = 0;
    @TestVisible private List<Id> skippedLegacyPostIds = new List<Id>();

    public FimbyPostEndOfLifeJob() {
        this(null, null);
    }

    public FimbyPostEndOfLifeJob(Set<Id> scopePostIds, Date asOfDate) {
        this.scopePostIds = scopePostIds;
        this.asOfDate = asOfDate;
    }

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new FimbyPostEndOfLifeJob(scopePostIds, asOfDate), 10);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = effectiveDate();
        Set<Id> scope = scopePostIds;
        Set<String> statuses = OPEN_POST_STATUSES;
        String soql = 'SELECT Id FROM Needs_Offers__c'
            + ' WHERE RecordType.DeveloperName != \'' + FimbyConstants.RT_BULK_BUY + '\''
            + ' AND Status__c IN :statuses'
            + ' AND (End_Date__c < :today OR End_Date__c = null)';
        if (scope != null) {
            soql += ' AND Id IN :scope';
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<Needs_Offers__c> scope) {
        Set<Id> ids = new Map<Id, Needs_Offers__c>(scope).keySet();
        Savepoint sp = Database.setSavepoint();
        try {
            processPosts(ids);
        } catch (Exception e) {
            Database.rollback(sp);
            FimbyLogger.error('FimbyPostEndOfLifeJob', 'execute', e);
            FimbyLogger.warn('FimbyPostEndOfLifeJob', 'execute',
                'Chunk rolled back; it will retry next run. Posts: ' + String.join(new List<Id>(ids), ','));
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!skippedLegacyPostIds.isEmpty()) {
            FimbyLogger.warn('FimbyPostEndOfLifeJob', 'finish',
                'Skipped posts with legacy Chatter replies for manual review: ' + String.join(skippedLegacyPostIds, ','));
        }
    }

    /**
     * @description Classifies and closes due posts. Re-locks the scope before deciding.
     */
    @TestVisible
    private void processPosts(Set<Id> postIds) {
        Date today = effectiveDate();
        List<Needs_Offers__c> locked = [
            SELECT Id, Name, Status__c, Type__c, RecordType.DeveloperName, Contact__c, Posted_By__c,
                   End_Date__c, Start_Date__c, Posted_Date__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Id IN :postIds
              AND Status__c IN :OPEN_POST_STATUSES
              AND RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
            FOR UPDATE
        ];

        List<Needs_Offers__c> due = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : locked) {
            Date endDate = effectiveEndDate(post);
            if (endDate != null && endDate < today) {
                due.add(post);
            }
        }
        if (due.isEmpty()) {
            return;
        }

        Set<Id> legacyPosts = postsWithLegacyReplies(due);
        Map<Id, FimbyPostEngagementService.Summary> summaries =
            FimbyPostEngagementService.summarize(new Map<Id, Needs_Offers__c>(due).keySet(), null);

        List<Needs_Offers__c> updates = new List<Needs_Offers__c>();
        Datetime now = Datetime.now();
        for (Needs_Offers__c post : due) {
            if (legacyPosts.contains(post.Id)) {
                skippedLegacyPostIds.add(post.Id);
                continue;
            }
            FimbyPostEngagementService.Summary s = summaries.get(post.Id);
            Boolean engaged = s != null && s.isEngaged();
            updates.add(new Needs_Offers__c(
                Id = post.Id,
                Status__c = engaged ? FimbyConstants.NEEDS_OFFERS_COMPLETED : FimbyConstants.NEEDS_OFFERS_EXPIRED,
                Closed_By__c = FimbyConstants.CLOSED_BY_AUTO,
                Closed_Date__c = now
            ));
            if (engaged) {
                completedCount++;
            } else {
                expiredCount++;
            }
        }
        if (updates.isEmpty()) {
            return;
        }
        update updates;
        FimbyPostLifecycleService.onPostsClosed(updates);
    }

    /**
     * @description Inclusive last day a post is live, or null when it never ends by age.
     */
    public static Date effectiveEndDate(Needs_Offers__c post) {
        if (post.End_Date__c != null) {
            return post.End_Date__c;
        }
        if (post.Type__c == 'Event') {
            return post.Start_Date__c;
        }
        Datetime base = post.Posted_Date__c != null ? post.Posted_Date__c : post.CreatedDate;
        if (base == null) {
            return null;
        }
        Integer days = post.RecordType?.DeveloperName == FimbyConstants.RT_NEED
            ? FimbySettings.needDefaultEndDays()
            : FimbySettings.offerDefaultEndDays();
        return base.date().addDays(days);
    }

    private Date effectiveDate() {
        return asOfDate != null ? asOfDate : Date.today();
    }

    private static Set<Id> postsWithLegacyReplies(List<Needs_Offers__c> posts) {
        Set<Id> result = new Set<Id>();
        List<Response__c> withLegacyActivity = [
            SELECT Id, Need_Offer_Responded_To__c, Last_Reply_Date__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :new Map<Id, Needs_Offers__c>(posts).keySet()
              AND Last_Reply_Date__c != null
              AND Status__c IN :FimbyPostEngagementService.ACTIVE_REPLY_STATUSES
        ];
        Set<Id> ambiguous = FimbyReplyNudgeJob.legacyAmbiguousResponses(withLegacyActivity);
        for (Response__c resp : withLegacyActivity) {
            if (ambiguous.contains(resp.Id)) {
                result.add(resp.Need_Offer_Responded_To__c);
            }
        }
        return result;
    }
}
