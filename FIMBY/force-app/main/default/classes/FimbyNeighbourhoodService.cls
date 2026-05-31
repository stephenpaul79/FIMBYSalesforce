public with sharing class FimbyNeighbourhoodService {

    private static Set<Id> cachedAdjacentIds;
    private static Set<Id> cachedAdjacentSharedContactIds;

    public static Set<Id> getAdjacentNeighbourhoodIds() {
        if (cachedAdjacentIds != null) return cachedAdjacentIds;
        User u = FimbyIdentityRepository.getCurrentUser();
        String adjField = u.Contact?.Account?.Adjacent_Neighbourhood_Ids__c;
        cachedAdjacentIds = new Set<Id>();
        if (String.isNotBlank(adjField)) {
            for (String idStr : adjField.split(',')) {
                String trimmed = idStr.trim();
                if (String.isNotBlank(trimmed)) {
                    try {
                        cachedAdjacentIds.add(Id.valueOf(trimmed));
                    } catch (StringException e) {
                        // Skip malformed IDs in denormalized field
                    }
                }
            }
        }
        return cachedAdjacentIds;
    }

    public static Set<Id> getAdjacentSharedContactIds() {
        if (cachedAdjacentSharedContactIds != null) return cachedAdjacentSharedContactIds;
        Id myContactId = FimbyIdentityRepository.getActingAsContactId();
        Set<Id> adjacentIds = getAdjacentNeighbourhoodIds();
        cachedAdjacentSharedContactIds = new Set<Id>();
        if (adjacentIds.isEmpty() || myContactId == null) {
            return cachedAdjacentSharedContactIds;
        }
        for (Shared_Contact_Info__c sci : [
            SELECT Contact__c, Shared_To__c
            FROM Shared_Contact_Info__c
            WHERE (
                (Contact__c = :myContactId AND Shared_To_Neighbourhood__c IN :adjacentIds)
                OR (Shared_To__c = :myContactId AND Contact_Neighbourhood__c IN :adjacentIds)
            )
            AND (Status__c = 'Active' OR Status__c = null)
        ]) {
            cachedAdjacentSharedContactIds.add(
                sci.Contact__c == myContactId ? sci.Shared_To__c : sci.Contact__c);
        }
        return cachedAdjacentSharedContactIds;
    }

    public static ViabilityResult previewViability(Id sourceAccountId, List<String> postalCodesToMove) {
        ViabilityResult result = new ViabilityResult();
        result.sourceAccountId = sourceAccountId;
        result.postalCodesToMove = postalCodesToMove;

        Set<String> moveSet = new Set<String>(postalCodesToMove);

        List<Contact> allContacts = [
            SELECT Id, MailingPostalCode, AccountId
            FROM Contact
            WHERE AccountId = :sourceAccountId
            AND MailingPostalCode != null
        ];

        Set<Id> newCellContactIds = new Set<Id>();
        Set<Id> remainCellContactIds = new Set<Id>();
        for (Contact c : allContacts) {
            String pc = c.MailingPostalCode != null ? c.MailingPostalCode.replaceAll('\\s', '') : '';
            if (moveSet.contains(c.MailingPostalCode) || moveSet.contains(pc)) {
                newCellContactIds.add(c.Id);
            } else {
                remainCellContactIds.add(c.Id);
            }
        }

        result.newCellHouseholds = newCellContactIds.size();
        result.remainCellHouseholds = remainCellContactIds.size();

        Date thirtyDaysAgo = Date.today().addDays(-30);

        Set<Id> newCellActive = getActiveContactIds(newCellContactIds, thirtyDaysAgo);
        Set<Id> remainCellActive = getActiveContactIds(remainCellContactIds, thirtyDaysAgo);
        result.newCellActiveMembers = newCellActive.size();
        result.remainCellActiveMembers = remainCellActive.size();

        result.newCellResponders = countResponders(newCellContactIds, thirtyDaysAgo);
        result.remainCellResponders = countResponders(remainCellContactIds, thirtyDaysAgo);

        result.newCellPostsPerWeek = countWeeklyPosts(newCellContactIds, thirtyDaysAgo);
        result.remainCellPostsPerWeek = countWeeklyPosts(remainCellContactIds, thirtyDaysAgo);

        Map<String, Decimal> tieMetrics = computeTieMetrics(newCellContactIds, remainCellContactIds, thirtyDaysAgo);
        result.newCellInternalTieRatio = tieMetrics.get('newInternal');
        result.remainCellInternalTieRatio = tieMetrics.get('remainInternal');

        result.crossCellSharedContacts = countCrossCellSharedContacts(newCellContactIds, remainCellContactIds);

        return result;
    }

    private static Set<Id> getActiveContactIds(Set<Id> contactIds, Date since) {
        if (contactIds.isEmpty()) return new Set<Id>();
        Set<Id> active = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Posted_By__c cId FROM Needs_Offers__c
            WHERE Posted_By__c IN :contactIds AND CreatedDate >= :since
            GROUP BY Posted_By__c
        ]) {
            active.add((Id) ar.get('cId'));
        }
        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Story__c
            WHERE Contact__c IN :contactIds AND CreatedDate >= :since
            GROUP BY Contact__c
        ]) {
            active.add((Id) ar.get('cId'));
        }
        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Response__c
            WHERE Contact__c IN :contactIds AND CreatedDate >= :since
            GROUP BY Contact__c
        ]) {
            active.add((Id) ar.get('cId'));
        }
        return active;
    }

    private static Integer countResponders(Set<Id> contactIds, Date since) {
        if (contactIds.isEmpty()) return 0;
        return [
            SELECT COUNT_DISTINCT(Contact__c) cnt FROM Response__c
            WHERE Contact__c IN :contactIds AND CreatedDate >= :since
        ][0].get('cnt') != null ? (Integer) [
            SELECT COUNT_DISTINCT(Contact__c) cnt FROM Response__c
            WHERE Contact__c IN :contactIds AND CreatedDate >= :since
        ][0].get('cnt') : 0;
    }

    private static Decimal countWeeklyPosts(Set<Id> contactIds, Date since) {
        if (contactIds.isEmpty()) return 0;
        Integer totalPosts = 0;
        totalPosts += [SELECT COUNT() FROM Needs_Offers__c WHERE Posted_By__c IN :contactIds AND CreatedDate >= :since];
        totalPosts += [SELECT COUNT() FROM Story__c WHERE Contact__c IN :contactIds AND CreatedDate >= :since];
        totalPosts += [SELECT COUNT() FROM Library_Item__c WHERE Owner_Contact__c IN :contactIds AND CreatedDate >= :since];
        return totalPosts / 4.0;
    }

    private static Map<String, Decimal> computeTieMetrics(Set<Id> newIds, Set<Id> remainIds, Date since) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        Integer newInternal = 0;
        Integer newExternal = 0;
        Integer remainInternal = 0;
        Integer remainExternal = 0;

        if (!newIds.isEmpty() && !remainIds.isEmpty()) {
            for (Response__c r : [
                SELECT Contact__c, Need_Offer_Responded_To__r.Posted_By__c
                FROM Response__c
                WHERE (Contact__c IN :newIds OR Contact__c IN :remainIds)
                AND CreatedDate >= :since
                AND Need_Offer_Responded_To__r.Posted_By__c != null
            ]) {
                Boolean responderInNew = newIds.contains(r.Contact__c);
                Boolean posterInNew = newIds.contains(r.Need_Offer_Responded_To__r.Posted_By__c);
                if (responderInNew && posterInNew) newInternal++;
                else if (responderInNew && !posterInNew) newExternal++;
                else if (!responderInNew && !posterInNew) remainInternal++;
                else remainExternal++;
            }
        }

        Integer newTotal = newInternal + newExternal;
        Integer remainTotal = remainInternal + remainExternal;
        result.put('newInternal', newTotal > 0 ? Decimal.valueOf(newInternal) / newTotal : 1.0);
        result.put('remainInternal', remainTotal > 0 ? Decimal.valueOf(remainInternal) / remainTotal : 1.0);
        return result;
    }

    private static Integer countCrossCellSharedContacts(Set<Id> newIds, Set<Id> remainIds) {
        if (newIds.isEmpty() || remainIds.isEmpty()) return 0;
        return [
            SELECT COUNT() FROM Shared_Contact_Info__c
            WHERE (
                (Contact__c IN :newIds AND Shared_To__c IN :remainIds)
                OR (Contact__c IN :remainIds AND Shared_To__c IN :newIds)
            )
            AND (Status__c = 'Active' OR Status__c = null)
        ];
    }

    @TestVisible
    private static void clearCache() {
        cachedAdjacentIds = null;
        cachedAdjacentSharedContactIds = null;
    }

    public class ViabilityResult {
        @AuraEnabled public Id sourceAccountId;
        @AuraEnabled public List<String> postalCodesToMove;
        @AuraEnabled public Integer newCellHouseholds;
        @AuraEnabled public Integer remainCellHouseholds;
        @AuraEnabled public Integer newCellActiveMembers;
        @AuraEnabled public Integer remainCellActiveMembers;
        @AuraEnabled public Integer newCellResponders;
        @AuraEnabled public Integer remainCellResponders;
        @AuraEnabled public Decimal newCellPostsPerWeek;
        @AuraEnabled public Decimal remainCellPostsPerWeek;
        @AuraEnabled public Decimal newCellInternalTieRatio;
        @AuraEnabled public Decimal remainCellInternalTieRatio;
        @AuraEnabled public Integer crossCellSharedContacts;
    }
}
