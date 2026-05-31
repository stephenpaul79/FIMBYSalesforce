/**
 * @description Weekly batch computing 4-lens neighbourhood health metrics.
 * Creates one Neighbourhood_Health_Snapshot__c per active Boundary Account and
 * sets Account.Split_Review_Flag__c when thresholds are crossed.
 *
 * Schedule:  System.schedule('FIMBY Health Metrics', '0 0 3 ? * SUN', new FimbyNeighbourhoodHealthBatch());
 * Manual:    Database.executeBatch(new FimbyNeighbourhoodHealthBatch(), 1);
 *
 * Batch size MUST be 1 — each execute uses ~25 SOQL queries per boundary.
 */
public without sharing class FimbyNeighbourhoodHealthBatch
    implements Database.Batchable<SObject>, Schedulable {

    @TestVisible private static final Integer LOOKBACK_DAYS = 30;
    private static final Decimal WEEKS_IN_PERIOD = 4.3;

    // ── Schedulable entry point ──

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new FimbyNeighbourhoodHealthBatch(), 1);
    }

    // ── Batchable ──

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Adjacent_Neighbourhood_Ids__c, Split_Review_Flag__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
              AND Active__c = 'Yes'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        List<Neighbourhood_Health_Snapshot__c> snapshots = new List<Neighbourhood_Health_Snapshot__c>();
        List<Account> accountUpdates = new List<Account>();
        Date today = Date.today();
        Datetime cutoff = Datetime.now().addDays(-LOOKBACK_DAYS);
        Datetime churnStart = Datetime.now().addDays(-60);

        for (Account boundary : scope) {
            try {
                Set<Id> adjacentIds = parseAdjacentIds(boundary.Adjacent_Neighbourhood_Ids__c);
                Neighbourhood_Health_Snapshot__c snap =
                    computeSnapshot(boundary.Id, adjacentIds, today, cutoff, churnStart);
                snapshots.add(snap);

                Boolean flagSplit = shouldFlagForSplitReview(snap);
                snap.Split_Review_Flag__c = flagSplit;

                if (boundary.Split_Review_Flag__c != flagSplit) {
                    accountUpdates.add(new Account(
                        Id = boundary.Id,
                        Split_Review_Flag__c = flagSplit
                    ));
                }
            } catch (Exception e) {
                FimbyLogger.error('FimbyNeighbourhoodHealthBatch', 'execute:' + boundary.Name, e);
            }
        }

        if (!snapshots.isEmpty()) {
            Database.insert(snapshots, false);
        }
        if (!accountUpdates.isEmpty()) {
            Database.update(accountUpdates, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // intentionally empty — snapshot records are the deliverable
    }

    // ── Core computation ──

    @TestVisible
    private Neighbourhood_Health_Snapshot__c computeSnapshot(
        Id boundaryId, Set<Id> adjacentIds, Date today,
        Datetime cutoff, Datetime churnStart
    ) {
        // ════════════════════════════════════════════
        // LENS 1 — DENSITY
        // ════════════════════════════════════════════

        Integer householdCount = [
            SELECT COUNT() FROM Account
            WHERE ParentId = :boundaryId
              AND RecordType.DeveloperName = 'HH_Account'
        ];

        Integer totalMembers = [
            SELECT COUNT() FROM Contact WHERE AccountId = :boundaryId
        ];

        Set<Id> activeContactIds = collectActiveContacts(boundaryId, cutoff);
        Integer activeMembers = activeContactIds.size();

        Decimal activePct = pct(activeMembers, totalMembers);

        Integer noPostCount = countPostsInPeriod(boundaryId, cutoff);
        Integer storyCount = [
            SELECT COUNT() FROM Story__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
        ];
        Integer libCount = [
            SELECT COUNT() FROM Library_Item__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
        ];
        Integer totalPosts = noPostCount + storyCount + libCount;
        Decimal postsPerWeek = (Decimal.valueOf(totalPosts) / WEEKS_IN_PERIOD).setScale(2);

        // ════════════════════════════════════════════
        // LENS 2 — RECIPROCITY
        // ════════════════════════════════════════════

        Integer respondedNeedOffers = 0;
        for (AggregateResult ar : [
            SELECT Need_Offer_Responded_To__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__r.Neighbourhood__c = :boundaryId
              AND Need_Offer_Responded_To__r.CreatedDate >= :cutoff
            GROUP BY Need_Offer_Responded_To__c
        ]) {
            respondedNeedOffers++;
        }
        Decimal responseRate = pct(respondedNeedOffers, noPostCount);

        Id needRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get(FimbyConstants.RT_NEED)?.getRecordTypeId();
        Id offerRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get(FimbyConstants.RT_OFFER)?.getRecordTypeId();

        Integer needPostCount = [SELECT COUNT() FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND RecordTypeId = :needRtId];
        Integer offerPostCount = [SELECT COUNT() FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND RecordTypeId = :offerRtId];

        Integer responsesToNeeds = [SELECT COUNT() FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Status__c IN (:FimbyConstants.RESPONSE_ACCEPTED, :FimbyConstants.RESPONSE_COMPLETED)
              AND Need_Offer_Responded_To__r.RecordTypeId = :needRtId];
        Integer responsesToOffers = [SELECT COUNT() FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Status__c IN (:FimbyConstants.RESPONSE_ACCEPTED, :FimbyConstants.RESPONSE_COMPLETED)
              AND Need_Offer_Responded_To__r.RecordTypeId = :offerRtId];

        Integer givingCount = offerPostCount + responsesToNeeds;
        Integer receivingCount = needPostCount + responsesToOffers;
        Integer totalGR = givingCount + receivingCount;
        Decimal giveTakeBalance = totalGR > 0
            ? (Decimal.valueOf(givingCount) / totalGR * 100).setScale(2)
            : 50.00;

        Integer uniquePairs = 0;
        Integer repeatPairs = 0;
        for (AggregateResult ar : [
            SELECT Contact__c, Need_Offer_Responded_To__r.Posted_By__c posterId, COUNT(Id) cnt
            FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Contact__c != null AND Need_Offer_Responded_To__r.Posted_By__c != null
            GROUP BY Contact__c, Need_Offer_Responded_To__r.Posted_By__c
        ]) {
            uniquePairs++;
            if (((Decimal) ar.get('cnt')).intValue() > 1) {
                repeatPairs++;
            }
        }
        Decimal repeatInteractionRate = pct(repeatPairs, uniquePairs);

        Integer actingAsOtherPosts = 0;
        for (Needs_Offers__c no : [
            SELECT Posted_By__c, Contact__c FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Posted_By__c != null AND Contact__c != null
        ]) {
            if (no.Posted_By__c != no.Contact__c) { actingAsOtherPosts++; }
        }
        Integer actingAsOtherResponses = 0;
        for (Response__c r : [
            SELECT Contact__c, On_Behalf_Of_Contact__c FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Status__c IN (:FimbyConstants.RESPONSE_ACCEPTED, :FimbyConstants.RESPONSE_COMPLETED)
              AND On_Behalf_Of_Contact__c != null
        ]) {
            if (r.Contact__c != r.On_Behalf_Of_Contact__c) { actingAsOtherResponses++; }
        }
        Integer helpingOthersCount = actingAsOtherPosts + actingAsOtherResponses;
        Integer totalResponses = [
            SELECT COUNT() FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
        ];
        Decimal thankYouRate = pct(helpingOthersCount, totalResponses);

        // ════════════════════════════════════════════
        // LENS 3 — RECOGNITION
        // ════════════════════════════════════════════

        Set<String> pairKeys = new Set<String>();

        for (AggregateResult ar : [
            SELECT Contact__c, Need_Offer_Responded_To__r.Posted_By__c posterId
            FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Contact__c != null AND Need_Offer_Responded_To__r.Posted_By__c != null
            GROUP BY Contact__c, Need_Offer_Responded_To__r.Posted_By__c
        ]) {
            pairKeys.add(orderedPairKey((Id) ar.get('Contact__c'), (Id) ar.get('posterId')));
        }

        for (Shared_Contact_Info__c sci : [
            SELECT Contact__c, Shared_To__c
            FROM Shared_Contact_Info__c
            WHERE (Contact_Neighbourhood__c = :boundaryId OR Shared_To_Neighbourhood__c = :boundaryId)
              AND Status__c = 'Active'
              AND Contact__c != null AND Shared_To__c != null
        ]) {
            pairKeys.add(orderedPairKey(sci.Contact__c, sci.Shared_To__c));
        }

        Integer connectedPairs = pairKeys.size();
        Decimal maxPossiblePairs = totalMembers > 1
            ? (Decimal.valueOf(totalMembers) * (totalMembers - 1) / 2) : 1;
        Decimal recognitionScore = Math.min(
            (Decimal.valueOf(connectedPairs) / maxPossiblePairs * 100).setScale(2), 100
        );

        Integer activeSciCount = [
            SELECT COUNT() FROM Shared_Contact_Info__c
            WHERE (Contact_Neighbourhood__c = :boundaryId OR Shared_To_Neighbourhood__c = :boundaryId)
              AND Status__c = 'Active'
        ];
        Decimal sharedContactDensity = totalMembers > 0
            ? (Decimal.valueOf(activeSciCount) / totalMembers).setScale(2) : 0;

        Integer newSciCount = [
            SELECT COUNT() FROM Shared_Contact_Info__c
            WHERE (Contact_Neighbourhood__c = :boundaryId OR Shared_To_Neighbourhood__c = :boundaryId)
              AND CreatedDate >= :cutoff
        ];
        Decimal contactShareRate = pct(newSciCount, totalMembers);

        Map<String, Integer> sciDirMap = new Map<String, Integer>();
        for (Shared_Contact_Info__c sci : [
            SELECT Contact__c, Shared_To__c
            FROM Shared_Contact_Info__c
            WHERE (Contact_Neighbourhood__c = :boundaryId OR Shared_To_Neighbourhood__c = :boundaryId)
              AND Status__c = 'Active'
              AND Contact__c != null AND Shared_To__c != null
        ]) {
            String k = orderedPairKey(sci.Contact__c, sci.Shared_To__c);
            sciDirMap.put(k, (sciDirMap.containsKey(k) ? sciDirMap.get(k) : 0) + 1);
        }
        Integer biPairs = 0;
        for (Integer v : sciDirMap.values()) {
            if (v >= 2) biPairs++;
        }
        Decimal connectionReciprocity = pct(biPairs, sciDirMap.size());

        // ════════════════════════════════════════════
        // SUPPLEMENTARY
        // ════════════════════════════════════════════

        Decimal lurkerRatio = pct(totalMembers - activeMembers, totalMembers);

        Integer adjacentResponses = 0;
        if (!adjacentIds.isEmpty()) {
            adjacentResponses = [
                SELECT COUNT() FROM Response__c
                WHERE Need_Offer_Responded_To__r.Neighbourhood__c = :boundaryId
                  AND CreatedDate >= :cutoff
                  AND Contact__r.AccountId IN :adjacentIds
            ];
        }
        Decimal adjacentResponsePct = pct(adjacentResponses, totalResponses);

        Integer adjacentSci = 0;
        if (!adjacentIds.isEmpty()) {
            adjacentSci = [
                SELECT COUNT() FROM Shared_Contact_Info__c
                WHERE ((Contact_Neighbourhood__c = :boundaryId AND Shared_To_Neighbourhood__c IN :adjacentIds)
                    OR (Shared_To_Neighbourhood__c = :boundaryId AND Contact_Neighbourhood__c IN :adjacentIds))
                  AND Status__c = 'Active'
            ];
        }
        Integer totalInteractions = totalResponses + activeSciCount;
        Decimal adjacentInteractionPct = pct(adjacentResponses + adjacentSci, totalInteractions);

        Integer engagedStories = [
            SELECT COUNT() FROM Story__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
              AND Last_Comment__c != null
        ];
        Decimal storyEngagementRate = pct(engagedStories, storyCount);

        Set<Id> previouslyActive = collectActiveContacts(boundaryId, churnStart, cutoff);
        previouslyActive.removeAll(activeContactIds);
        Integer churnBase = previouslyActive.size() + activeContactIds.size();
        Decimal churnRate = pct(previouslyActive.size(), churnBase);

        // ════════════════════════════════════════════
        // ASSEMBLE SNAPSHOT
        // ════════════════════════════════════════════

        return new Neighbourhood_Health_Snapshot__c(
            Neighbourhood__c           = boundaryId,
            Snapshot_Date__c           = today,
            Period_Type__c             = 'Weekly',
            // Lens 1
            Household_Count__c         = householdCount,
            Total_Member_Count__c      = totalMembers,
            Active_Member_Count__c     = activeMembers,
            Active_Member_Pct__c       = activePct,
            Posts_Per_Week__c          = postsPerWeek,
            // Lens 2
            Response_Rate__c           = responseRate,
            Give_Take_Balance__c       = giveTakeBalance,
            Repeat_Interaction_Rate__c = repeatInteractionRate,
            Thank_You_Rate__c          = thankYouRate,
            // Lens 3
            Recognition_Score__c       = recognitionScore,
            Shared_Contact_Density__c  = sharedContactDensity,
            Contact_Share_Rate__c      = contactShareRate,
            Connection_Reciprocity__c  = connectionReciprocity,
            // Supplementary
            Lurker_Ratio__c            = lurkerRatio,
            Adjacent_Response_Pct__c   = adjacentResponsePct,
            Adjacent_Interaction_Pct__c = adjacentInteractionPct,
            Story_Engagement_Rate__c   = storyEngagementRate,
            Churn_Rate_30d__c          = churnRate
        );
    }

    // ── Split review flag ──

    @TestVisible
    private Boolean shouldFlagForSplitReview(Neighbourhood_Health_Snapshot__c snap) {
        Integer softCap = FimbySettings.neighbourhoodSoftCap();
        Decimal recogThreshold = FimbySettings.recognitionScoreThreshold() * 100;
        Decimal lurkerThreshold = FimbySettings.lurkerRatioThreshold() * 100;

        return (snap.Household_Count__c != null && snap.Household_Count__c >= softCap)
            || (snap.Recognition_Score__c != null && snap.Recognition_Score__c < recogThreshold)
            || (snap.Lurker_Ratio__c != null && snap.Lurker_Ratio__c > lurkerThreshold);
    }

    // ── Active-contact collection ──

    private Set<Id> collectActiveContacts(Id boundaryId, Datetime cutoff) {
        Set<Id> ids = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Posted_By__c cId FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND Posted_By__c != null
            GROUP BY Posted_By__c
        ]) { ids.add((Id) ar.get('cId')); }

        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Story__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND Contact__c != null
            GROUP BY Contact__c
        ]) { ids.add((Id) ar.get('cId')); }

        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Response__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND Contact__c != null
            GROUP BY Contact__c
        ]) { ids.add((Id) ar.get('cId')); }

        for (AggregateResult ar : [
            SELECT Owner_Contact__c cId FROM Library_Item__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff AND Owner_Contact__c != null
            GROUP BY Owner_Contact__c
        ]) { ids.add((Id) ar.get('cId')); }

        return ids;
    }

    /**
     * Overload for churn window: contacts active between rangeStart and rangeEnd.
     */
    private Set<Id> collectActiveContacts(Id boundaryId, Datetime rangeStart, Datetime rangeEnd) {
        Set<Id> ids = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Posted_By__c cId FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId
              AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd AND Posted_By__c != null
            GROUP BY Posted_By__c
        ]) { ids.add((Id) ar.get('cId')); }

        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Response__c
            WHERE Neighbourhood__c = :boundaryId
              AND CreatedDate >= :rangeStart AND CreatedDate < :rangeEnd AND Contact__c != null
            GROUP BY Contact__c
        ]) { ids.add((Id) ar.get('cId')); }

        return ids;
    }

    // ── Helpers ──

    private Integer countPostsInPeriod(Id boundaryId, Datetime cutoff) {
        return [
            SELECT COUNT() FROM Needs_Offers__c
            WHERE Neighbourhood__c = :boundaryId AND CreatedDate >= :cutoff
        ];
    }

    private static Decimal pct(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) return 0;
        return (Decimal.valueOf(numerator) / denominator * 100).setScale(2);
    }

    private static String orderedPairKey(Id a, Id b) {
        return a < b ? (a + ':' + b) : (b + ':' + a);
    }

    @TestVisible
    private static Set<Id> parseAdjacentIds(String csv) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(csv)) return ids;
        for (String part : csv.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                try { ids.add(Id.valueOf(trimmed)); }
                catch (Exception e) { /* skip malformed */ }
            }
        }
        return ids;
    }
}
