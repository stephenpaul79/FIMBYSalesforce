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
    }
}
