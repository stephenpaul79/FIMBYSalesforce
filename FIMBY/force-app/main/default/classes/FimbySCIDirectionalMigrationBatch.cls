/**
 * @description Brings existing data up to the directional consent-episode model.
 *
 *              Runs as two ordered passes, because duplicate Active pairs must be
 *              resolved BEFORE anything starts writing the unique Active_Pair_Key__c.
 *              Populating the key while two Active rows still exist for one direction
 *              would surface DUPLICATE_VALUE in ordinary neighbour traffic, not just
 *              in this batch.
 *
 *              PASS_A — row normalization. Runs immediately after the schema deploy,
 *              before the service or trigger start enforcing the key. For each exact
 *              direction the newest row is current: legacy null status becomes Active,
 *              older Active/null duplicates are closed, and neighbourhood stamps are
 *              backfilled on every row including history. Rows already Revoked before
 *              this field existed keep a blank Consent_Closed_Date__c — the real
 *              closure date is unknowable and fabricating one would misinform people.
 *
 *              PASS_B — thread binding. Runs after enforcement ships. Participant_1__c
 *              is the recorded thread creator, so a thread is valid only when a current
 *              Active episode runs Participant_2 -> Participant_1. Anything else keeps
 *              its history but locks with an explanation.
 *
 *              Both passes are idempotent and safe to rerun, so the delta sweep after
 *              the migration window costs nothing.
 *
 *              Run with FimbySCIDirectionalMigrationBatch.runPassA() /
 *              .runPassB(), or .dryRunPassA() / .dryRunPassB() to report without
 *              mutating. Counts are logged per category via FimbyLogger.
 */
public without sharing class FimbySCIDirectionalMigrationBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    public enum Phase { PASS_A, PASS_B }

    private final Phase migrationPhase;
    private final Boolean dryRun;

    public Integer rowsNormalized = 0;
    public Integer duplicatesClosed = 0;
    public Integer neighbourhoodsBackfilled = 0;
    public Integer threadsBound = 0;
    public Integer threadsLocked = 0;
    public Integer threadsSkippedExempt = 0;

    public FimbySCIDirectionalMigrationBatch(Phase requestedPhase, Boolean dryRun) {
        this.migrationPhase = requestedPhase;
        this.dryRun = dryRun == true;
    }

    /** @description Normalizes rows and populates pair keys. @return The batch job Id. */
    public static Id runPassA() {
        return Database.executeBatch(new FimbySCIDirectionalMigrationBatch(Phase.PASS_A, false), 200);
    }

    /** @description Reports what pass A would change. @return The batch job Id. */
    public static Id dryRunPassA() {
        return Database.executeBatch(new FimbySCIDirectionalMigrationBatch(Phase.PASS_A, true), 200);
    }

    /** @description Binds or locks existing threads. @return The batch job Id. */
    public static Id runPassB() {
        return Database.executeBatch(new FimbySCIDirectionalMigrationBatch(Phase.PASS_B, false), 200);
    }

    /** @description Reports what pass B would change. @return The batch job Id. */
    public static Id dryRunPassB() {
        return Database.executeBatch(new FimbySCIDirectionalMigrationBatch(Phase.PASS_B, true), 200);
    }

    /**
     * @description Read-only preflight counts, safe to call from anonymous Apex before
     *              any mutation. Returns the numbers the plan asks to review.
     * @return Map of category label to count.
     */
    public static Map<String, Integer> preflightCounts() {
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('sciActive', [
            SELECT COUNT() FROM Shared_Contact_Info__c WHERE Status__c = :FimbyConstants.SHARED_CONTACT_ACTIVE
        ]);
        counts.put('sciRevoked', [
            SELECT COUNT() FROM Shared_Contact_Info__c WHERE Status__c = :FimbyConstants.SHARED_CONTACT_REVOKED
        ]);
        counts.put('sciNullStatus', [
            SELECT COUNT() FROM Shared_Contact_Info__c WHERE Status__c = null
        ]);
        counts.put('sciMissingNeighbourhoodStamp', [
            SELECT COUNT() FROM Shared_Contact_Info__c
            WHERE Contact_Neighbourhood__c = null OR Shared_To_Neighbourhood__c = null
        ]);
        counts.put('sciMissingActiveKey', [
            SELECT COUNT() FROM Shared_Contact_Info__c
            WHERE Active_Pair_Key__c = null
            AND (Status__c = :FimbyConstants.SHARED_CONTACT_ACTIVE OR Status__c = null)
        ]);
        counts.put('duplicateOpenPairs', countDuplicateOpenPairs());
        counts.put('unboundSharingGatedThreads', [
            SELECT COUNT() FROM Conversation__c
            WHERE Authorizing_Shared_Contact_Info__c = null
            AND Is_Group__c = false
            AND (Context_Type__c = null OR Context_Type__c = :FimbyConstants.CTX_DIRECT
                 OR Context_Type__c = :FimbyConstants.CTX_SKILL)
        ]);
        return counts;
    }

    /**
     * @description How many directions still have more than one open episode. Must
     *              reach zero before the trigger or service start setting the key.
     * @return The number of directions with a duplicate open episode.
     */
    public static Integer countDuplicateOpenPairs() {
        Integer duplicates = 0;
        for (AggregateResult ar : [
            SELECT Contact__c, Shared_To__c, COUNT(Id) rowCount
            FROM Shared_Contact_Info__c
            WHERE (Status__c = :FimbyConstants.SHARED_CONTACT_ACTIVE OR Status__c = null)
            AND Contact__c != null AND Shared_To__c != null
            GROUP BY Contact__c, Shared_To__c
            HAVING COUNT(Id) > 1
        ]) {
            duplicates += ((Integer) ar.get('rowCount')) - 1;
        }
        return duplicates;
    }

    /**
     * @description Selects the rows for the current phase.
     * @param bc The batch context.
     * @return The query locator.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (migrationPhase == Phase.PASS_A) {
            // Chunk by sharer so every row for one direction lands in the same scope,
            // which is what makes newest-row-wins decidable inside execute().
            return Database.getQueryLocator([
                SELECT Id, Contact__c, Shared_To__c, Status__c, Active_Pair_Key__c,
                       Consent_Closed_Date__c, Contact_Neighbourhood__c, Shared_To_Neighbourhood__c,
                       CreatedDate
                FROM Shared_Contact_Info__c
                WHERE Contact__c != null AND Shared_To__c != null
                ORDER BY Contact__c, Shared_To__c, CreatedDate DESC, Id DESC
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, Participant_1__c, Participant_2__c, Context_Type__c, Locked__c,
                   Authorizing_Shared_Contact_Info__c
            FROM Conversation__c
            WHERE Authorizing_Shared_Contact_Info__c = null
            AND Is_Group__c = false
            AND Participant_1__c != null AND Participant_2__c != null
            AND (Context_Type__c = null OR Context_Type__c = :FimbyConstants.CTX_DIRECT
                 OR Context_Type__c = :FimbyConstants.CTX_SKILL)
        ]);
    }

    /**
     * @description Applies the current phase to one scope.
     * @param bc The batch context.
     * @param scope The records in this chunk.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (migrationPhase == Phase.PASS_A) {
            executePassA((List<Shared_Contact_Info__c>) scope);
        } else {
            executePassB((List<Conversation__c>) scope);
        }
    }

    /**
     * @description Logs the per-category totals for review.
     * @param bc The batch context.
     */
    public void finish(Database.BatchableContext bc) {
        String summary = 'phase=' + migrationPhase
            + ' dryRun=' + dryRun
            + ' rowsNormalized=' + rowsNormalized
            + ' duplicatesClosed=' + duplicatesClosed
            + ' neighbourhoodsBackfilled=' + neighbourhoodsBackfilled
            + ' threadsBound=' + threadsBound
            + ' threadsLocked=' + threadsLocked
            + ' threadsSkippedExempt=' + threadsSkippedExempt
            + ' remainingDuplicateOpenPairs=' + countDuplicateOpenPairs();
        FimbyLogger.warn('FimbySCIDirectionalMigrationBatch', 'finish', summary);
    }

    private void executePassA(List<Shared_Contact_Info__c> rows) {
        // Re-resolve the whole direction rather than trusting scope boundaries, so a
        // pair split across two chunks still gets one winner.
        Set<Id> sharerIds = new Set<Id>();
        Set<Id> recipientIds = new Set<Id>();
        for (Shared_Contact_Info__c row : rows) {
            sharerIds.add(row.Contact__c);
            recipientIds.add(row.Shared_To__c);
        }

        Map<String, Shared_Contact_Info__c> currentByPair = new Map<String, Shared_Contact_Info__c>();
        List<Shared_Contact_Info__c> allRows = [
            SELECT Id, Contact__c, Shared_To__c, Status__c, Active_Pair_Key__c,
                   Consent_Closed_Date__c, Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c IN :sharerIds AND Shared_To__c IN :recipientIds
            ORDER BY CreatedDate DESC, Id DESC
        ];
        for (Shared_Contact_Info__c row : allRows) {
            String pair = String.valueOf(row.Contact__c) + ':' + String.valueOf(row.Shared_To__c);
            if (!currentByPair.containsKey(pair)) {
                currentByPair.put(pair, row);
            }
        }

        Set<Id> contactIds = new Set<Id>();
        contactIds.addAll(sharerIds);
        contactIds.addAll(recipientIds);
        Map<Id, Id> neighbourhoods = FimbySharedContactService.neighbourhoodsFor(contactIds);

        Datetime migratedAt = System.now();
        Map<Id, Shared_Contact_Info__c> updates = new Map<Id, Shared_Contact_Info__c>();

        for (Shared_Contact_Info__c row : allRows) {
            String pair = String.valueOf(row.Contact__c) + ':' + String.valueOf(row.Shared_To__c);
            Boolean isCurrent = (currentByPair.get(pair).Id == row.Id);
            Boolean wasOpen = (row.Status__c == null
                || row.Status__c == FimbyConstants.SHARED_CONTACT_ACTIVE);
            Boolean shouldBeOpen = isCurrent && wasOpen;

            Shared_Contact_Info__c change = new Shared_Contact_Info__c(Id = row.Id);
            Boolean dirty = false;

            String targetStatus = shouldBeOpen
                ? FimbyConstants.SHARED_CONTACT_ACTIVE
                : FimbyConstants.SHARED_CONTACT_REVOKED;
            if (row.Status__c != targetStatus) {
                change.Status__c = targetStatus;
                dirty = true;
                if (isCurrent) {
                    rowsNormalized++;
                } else {
                    duplicatesClosed++;
                    // A superseded duplicate really did close now, so this date is honest.
                    change.Consent_Closed_Date__c = migratedAt;
                }
            }

            String targetKey = shouldBeOpen
                ? FimbySharedContactService.buildPairKey(row.Contact__c, row.Shared_To__c)
                : null;
            if (row.Active_Pair_Key__c != targetKey) {
                change.Active_Pair_Key__c = targetKey;
                dirty = true;
            }

            Id sharerNeighbourhood = neighbourhoods.get(row.Contact__c);
            Id recipientNeighbourhood = neighbourhoods.get(row.Shared_To__c);
            if (row.Contact_Neighbourhood__c != sharerNeighbourhood
                || row.Shared_To_Neighbourhood__c != recipientNeighbourhood) {
                change.Contact_Neighbourhood__c = sharerNeighbourhood;
                change.Shared_To_Neighbourhood__c = recipientNeighbourhood;
                dirty = true;
                neighbourhoodsBackfilled++;
            }

            if (dirty) {
                updates.put(row.Id, change);
            }
        }

        if (!dryRun && !updates.isEmpty()) {
            update updates.values();
        }
    }

    private void executePassB(List<Conversation__c> threads) {
        Set<Id> participantIds = new Set<Id>();
        for (Conversation__c conv : threads) {
            participantIds.add(conv.Participant_1__c);
            participantIds.add(conv.Participant_2__c);
        }

        // Current open episode per direction, restricted to these participants.
        Map<String, Id> openEpisodeByPair = new Map<String, Id>();
        Set<String> closedPairs = new Set<String>();
        for (Shared_Contact_Info__c sci : [
            SELECT Id, Contact__c, Shared_To__c, Status__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c IN :participantIds AND Shared_To__c IN :participantIds
            ORDER BY CreatedDate DESC, Id DESC
        ]) {
            String pair = String.valueOf(sci.Contact__c) + ':' + String.valueOf(sci.Shared_To__c);
            if (openEpisodeByPair.containsKey(pair) || closedPairs.contains(pair)) {
                continue;
            }
            if (sci.Status__c == null || sci.Status__c == FimbyConstants.SHARED_CONTACT_ACTIVE) {
                openEpisodeByPair.put(pair, sci.Id);
            } else {
                closedPairs.add(pair);
            }
        }

        Set<Id> orgContactIds = new Set<Id>();
        for (Contact c : [
            SELECT Id FROM Contact
            WHERE Id IN :participantIds AND Is_Organization_Contact__c = true
        ]) {
            orgContactIds.add(c.Id);
        }
        Set<Id> moderatorContactIds = new Set<Id>();
        for (Moderator_Assignment__c ma : [
            SELECT Contact__c FROM Moderator_Assignment__c
            WHERE Contact__c IN :participantIds AND Status__c = 'Active'
        ]) {
            moderatorContactIds.add(ma.Contact__c);
        }

        List<Conversation__c> binds = new List<Conversation__c>();
        Set<Id> toLock = new Set<Id>();

        for (Conversation__c conv : threads) {
            if (orgContactIds.contains(conv.Participant_1__c)
                || orgContactIds.contains(conv.Participant_2__c)
                || moderatorContactIds.contains(conv.Participant_1__c)
                || moderatorContactIds.contains(conv.Participant_2__c)) {
                threadsSkippedExempt++;
                continue;
            }

            // Participant_1__c is the recorded creator, so only an episode running
            // Participant_2 -> Participant_1 could ever have authorized this thread.
            String creatorAlignedPair =
                String.valueOf(conv.Participant_2__c) + ':' + String.valueOf(conv.Participant_1__c);
            Id episodeId = openEpisodeByPair.get(creatorAlignedPair);

            if (episodeId != null) {
                binds.add(new Conversation__c(
                    Id = conv.Id,
                    Authorizing_Shared_Contact_Info__c = episodeId
                ));
                threadsBound++;
            } else if (conv.Locked__c != true) {
                toLock.add(conv.Id);
                threadsLocked++;
            }
        }

        if (dryRun) {
            return;
        }
        if (!binds.isEmpty()) {
            update binds;
        }
        if (!toLock.isEmpty()) {
            lockUnauthorizedThreads(toLock);
        }
    }

    /**
     * @description Locks threads that no current episode authorizes, keeping their
     *              history readable and adding the same explanation a live revoke
     *              produces. Empty threads are locked without a message so migration
     *              does not resurface them in anyone's inbox.
     * @param conversationIds The threads to close.
     */
    private void lockUnauthorizedThreads(Set<Id> conversationIds) {
        Set<Id> alreadyExplained = new Set<Id>();
        for (Message__c existing : [
            SELECT Conversation__c FROM Message__c
            WHERE Conversation__c IN :conversationIds
            AND Is_System_Message__c = true
            AND System_Message_Type__c = 'Contact_Sharing_Revoked'
        ]) {
            alreadyExplained.add(existing.Conversation__c);
        }

        Set<Id> hasHistory = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Conversation__c cid FROM Message__c
            WHERE Conversation__c IN :conversationIds
            GROUP BY Conversation__c
        ]) {
            hasHistory.add((Id) ar.get('cid'));
        }

        List<Conversation__c> locks = new List<Conversation__c>();
        List<Message__c> notices = new List<Message__c>();
        Datetime now = System.now();

        for (Id conversationId : conversationIds) {
            locks.add(new Conversation__c(Id = conversationId, Locked__c = true));
            if (!alreadyExplained.contains(conversationId) && hasHistory.contains(conversationId)) {
                notices.add(new Message__c(
                    Conversation__c = conversationId,
                    Body__c = FimbySharedContactService.REVOKE_NOTICE_BODY,
                    Is_System_Message__c = true,
                    System_Message_Type__c = 'Contact_Sharing_Revoked',
                    Status__c = FimbyConstants.MESSAGE_SENT,
                    Sent_Date__c = now
                ));
            }
        }

        update locks;
        if (!notices.isEmpty()) {
            insert notices;
        }
    }
}
