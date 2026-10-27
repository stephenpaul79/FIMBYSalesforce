/**
 * @description Shared contact-visibility gate for neighbour and org profile surfaces.
 * Mirrors FimbySearchController.buildContactFilter scoping plus blocking.
 */
public with sharing class FimbyContactVisibility {

    /**
     * @description Returns true when the viewer may see the target contact's profile and activity feed.
     * @param viewerActingAsContactId Viewer's represented identity
     * @param targetContactId Contact whose profile or activity is requested
     */
    public static Boolean canView(Id viewerActingAsContactId, Id targetContactId) {
        if (viewerActingAsContactId == null || targetContactId == null) {
            return false;
        }
        if (viewerActingAsContactId == targetContactId) {
            return true;
        }

        Set<Id> blocked = FimbyBlockingHelper.getBidirectionalBlocks(viewerActingAsContactId);
        if (blocked.contains(targetContactId)) {
            return false;
        }

        Contact target = new VisibilityHelper().getTargetContact(targetContactId);
        if (target == null) {
            return false;
        }

        if (target.Is_Organization_Contact__c == true) {
            return new VisibilityHelper().hasActiveNeighbourhoodLink(target.Organization_Account__c);
        }
        return canViewNeighbourContact(target);
    }

    /**
     * @description Filters organization contacts down to the ones a message would actually
     *              reach: an approved group with an Active link to the viewer's neighbourhood
     *              and at least one approved, active rep other than the viewer. Any of the
     *              org's reps may answer; they need not live in the viewer's neighbourhood.
     * @param orgContactIds Candidate organization contact Ids
     * @return The subset that someone is available to receive messages for
     */
    public static Set<Id> getMessageableOrgContactIds(Set<Id> orgContactIds) {
        if (orgContactIds == null || orgContactIds.isEmpty()) {
            return new Set<Id>();
        }
        return new VisibilityHelper().getMessageableOrgContactIds(
            orgContactIds,
            FimbyIdentityRepository.getNeighbourhoodId(),
            FimbyIdentityRepository.getCurrentUser().ContactId
        );
    }

    public static Boolean isMessageableOrgContact(Id orgContactId) {
        return orgContactId != null
            && getMessageableOrgContactIds(new Set<Id>{ orgContactId }).contains(orgContactId);
    }

    private static Boolean canViewNeighbourContact(Contact target) {
        if (target.Is_Organization_Contact__c == true) {
            return false;
        }

        Id viewerNeighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
        if (viewerNeighbourhoodId == null || target.AccountId == null) {
            return false;
        }
        if (target.AccountId == viewerNeighbourhoodId) {
            return true;
        }

        Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
        Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();
        return adjacentIds.contains(target.AccountId) && sharedContactIds.contains(target.Id);
    }

    private without sharing class VisibilityHelper {
        public Contact getTargetContact(Id targetContactId) {
            List<Contact> targets = [
                SELECT Id, AccountId, Is_Organization_Contact__c, Organization_Account__c
                FROM Contact
                WHERE Id = :targetContactId
                LIMIT 1
            ];
            return targets.isEmpty() ? null : targets[0];
        }

        public Boolean hasActiveNeighbourhoodLink(Id orgAccountId) {
            Id viewerNeighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
            if (viewerNeighbourhoodId == null || orgAccountId == null) {
                return false;
            }

            Integer linkCount = [
                SELECT COUNT()
                FROM Community_Group_Neighbourhood__c
                WHERE Organization__c = :orgAccountId
                  AND Neighbourhood__c = :viewerNeighbourhoodId
                  AND Status__c = 'Active'
            ];
            return linkCount > 0;
        }

        public Set<Id> getMessageableOrgContactIds(Set<Id> orgContactIds, Id viewerNeighbourhoodId, Id viewerRealContactId) {
            Set<Id> result = new Set<Id>();
            if (viewerNeighbourhoodId == null) {
                return result;
            }

            Map<Id, Id> orgContactByAccount = new Map<Id, Id>();
            for (Community_Group_Neighbourhood__c link : [
                SELECT Organization__c, Organization__r.Organization_Contact__c
                FROM Community_Group_Neighbourhood__c
                WHERE Neighbourhood__c = :viewerNeighbourhoodId
                  AND Status__c = 'Active'
                  AND Organization__r.Is_Approved_Community_Group__c = true
                  AND Organization__r.Organization_Contact__c IN :orgContactIds
            ]) {
                orgContactByAccount.put(link.Organization__c, link.Organization__r.Organization_Contact__c);
            }
            if (orgContactByAccount.isEmpty()) {
                return result;
            }

            Map<Id, Set<Id>> repsByAccount = new Map<Id, Set<Id>>();
            Set<Id> repContactIds = new Set<Id>();
            for (Support_Relationship__c rel : [
                SELECT Contact__c, Related_Organization__c
                FROM Support_Relationship__c
                WHERE Related_Organization__c IN :orgContactByAccount.keySet()
                  AND Relationship_Type__c = 'Community_Group_Rep'
                  AND Status__c = 'Approved'
                  AND Dismissed_By_Helper__c = false
                  AND Contact__c != null
                  AND Contact__c != :viewerRealContactId
            ]) {
                if (!repsByAccount.containsKey(rel.Related_Organization__c)) {
                    repsByAccount.put(rel.Related_Organization__c, new Set<Id>());
                }
                repsByAccount.get(rel.Related_Organization__c).add(rel.Contact__c);
                repContactIds.add(rel.Contact__c);
            }
            if (repContactIds.isEmpty()) {
                return result;
            }

            Set<Id> activeRepContactIds = new Set<Id>();
            for (User u : [
                SELECT ContactId FROM User
                WHERE ContactId IN :repContactIds AND IsActive = true
            ]) {
                activeRepContactIds.add(u.ContactId);
            }

            for (Id accountId : repsByAccount.keySet()) {
                for (Id repId : repsByAccount.get(accountId)) {
                    if (activeRepContactIds.contains(repId)) {
                        result.add(orgContactByAccount.get(accountId));
                        break;
                    }
                }
            }
            return result;
        }
    }
}
