// Live Feed Lifecycle: one-time cutover reconciliation.
// Run as an America/Vancouver admin AFTER the nine FlowDefinitions are inactive and the new
// triggers are live, and BEFORE scheduling FIMBY Post End of Life / FIMBY Reply Nudges.
//
//   sf apex run --file scripts/apex/live-feed-cutover-reconcile.apex
//
// Silent: no notifications. Set DRY_RUN = false to apply.

Boolean DRY_RUN = true;

FimbyPostLifecycleService.suppressNotifications = true;
Date today = Date.today();

// 1. Overdue active Asks / Offers / Events.
List<Needs_Offers__c> openPosts = [
    SELECT Id, Name, Status__c, Type__c, RecordType.DeveloperName, End_Date__c, Start_Date__c,
           Posted_Date__c, CreatedDate
    FROM Needs_Offers__c
    WHERE RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
      AND Status__c IN :FimbyPostEndOfLifeJob.OPEN_POST_STATUSES
];
Map<Id, Needs_Offers__c> due = new Map<Id, Needs_Offers__c>();
Map<Id, Date> endById = new Map<Id, Date>();
for (Needs_Offers__c p : openPosts) {
    Date endDate = FimbyPostEndOfLifeJob.effectiveEndDate(p);
    if (endDate != null && endDate < today) {
        due.put(p.Id, p);
        endById.put(p.Id, endDate);
    }
}

Set<Id> ambiguousPosts = new Set<Id>();
if (!due.isEmpty()) {
    List<Response__c> legacy = [
        SELECT Id, Need_Offer_Responded_To__c, Last_Reply_Date__c
        FROM Response__c
        WHERE Need_Offer_Responded_To__c IN :due.keySet()
          AND Last_Reply_Date__c != null
          AND Status__c IN :FimbyPostEngagementService.ACTIVE_REPLY_STATUSES
    ];
    Set<Id> ambiguous = FimbyReplyNudgeJob.legacyAmbiguousResponses(legacy);
    for (Response__c r : legacy) {
        if (ambiguous.contains(r.Id)) {
            ambiguousPosts.add(r.Need_Offer_Responded_To__c);
        }
    }
}

Map<Id, FimbyPostEngagementService.Summary> summaries = due.isEmpty()
    ? new Map<Id, FimbyPostEngagementService.Summary>()
    : FimbyPostEngagementService.summarize(due.keySet(), null);

List<Needs_Offers__c> closeUpdates = new List<Needs_Offers__c>();
for (Needs_Offers__c p : due.values()) {
    if (ambiguousPosts.contains(p.Id)) {
        System.debug(LoggingLevel.WARN, 'MANUAL REVIEW (legacy Chatter reply): ' + p.Id + ' ' + p.Name);
        continue;
    }
    FimbyPostEngagementService.Summary s = summaries.get(p.Id);
    Boolean engaged = s != null && s.isEngaged();
    // Deterministic boundary: midnight starting the day after the effective end date,
    // in the running user's (America/Vancouver) time zone.
    Datetime closedAt = Datetime.newInstance(endById.get(p.Id).addDays(1), Time.newInstance(0, 0, 0, 0));
    closeUpdates.add(new Needs_Offers__c(
        Id = p.Id,
        Status__c = engaged ? FimbyConstants.NEEDS_OFFERS_COMPLETED : FimbyConstants.NEEDS_OFFERS_EXPIRED,
        Closed_By__c = FimbyConstants.CLOSED_BY_AUTO,
        Closed_Date__c = closedAt
    ));
    System.debug('CLOSE ' + p.Id + ' ' + p.Name + ' -> ' + (engaged ? 'Completed' : 'Expired') + ' at ' + closedAt);
}

// 2. Open responses still hanging off parents that are already terminal.
List<AggregateResult> strandedParents = [
    SELECT Need_Offer_Responded_To__c parentId
    FROM Response__c
    WHERE Status__c IN (:FimbyConstants.RESPONSE_NEW, :FimbyConstants.RESPONSE_ACCEPTED)
      AND Need_Offer_Responded_To__r.RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
      AND Need_Offer_Responded_To__r.Status__c IN :FimbyPostLifecycleService.TERMINAL_POST_STATUSES
    GROUP BY Need_Offer_Responded_To__c
];
List<Needs_Offers__c> cascadeParents = new List<Needs_Offers__c>();
for (AggregateResult ar : strandedParents) {
    cascadeParents.add(new Needs_Offers__c(Id = (Id) ar.get('parentId')));
}

Integer pendingFlag = [SELECT COUNT() FROM Response__c WHERE Status_Update_Needed__c != null];

System.debug('Overdue active posts: ' + due.size()
    + ' | to close: ' + closeUpdates.size()
    + ' | manual review: ' + ambiguousPosts.size()
    + ' | terminal parents with open responses: ' + cascadeParents.size()
    + ' | responses with Status_Update_Needed__c: ' + pendingFlag
    + ' | DRY_RUN=' + DRY_RUN);

if (!DRY_RUN) {
    if (!closeUpdates.isEmpty()) {
        update closeUpdates; // trigger cascades responses; notifications suppressed
    }
    if (!cascadeParents.isEmpty()) {
        FimbyPostLifecycleService.onPostsClosed(cascadeParents);
    }
    Integer remaining = [
        SELECT COUNT() FROM Response__c
        WHERE Status__c IN (:FimbyConstants.RESPONSE_NEW, :FimbyConstants.RESPONSE_ACCEPTED)
          AND Need_Offer_Responded_To__r.RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
          AND Need_Offer_Responded_To__r.Status__c IN :FimbyPostLifecycleService.TERMINAL_POST_STATUSES
    ];
    System.debug('Open responses on terminal parents after reconcile: ' + remaining);
}
