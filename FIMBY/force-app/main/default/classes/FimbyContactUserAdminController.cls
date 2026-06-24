/**
 * @description Resolves the community User linked to a Contact for internal admin LWCs.
 */
public with sharing class FimbyContactUserAdminController {

    public class LinkedUserResult {
        @AuraEnabled public Id userId;
        @AuraEnabled public String username;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isActive;
    }

    /**
     * @description Returns the best-matching User for a Contact (prefers active, then most recent).
     * @param contactId Contact record Id from the hosting record page
     * @return Linked user summary, or null when no User is linked
     */
    @AuraEnabled(cacheable=true)
    public static LinkedUserResult getLinkedUser(Id contactId) {
        if (contactId == null) {
            return null;
        }

        List<User> users = [
            SELECT Id, Username, Name, IsActive
            FROM User
            WHERE ContactId = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY IsActive DESC, CreatedDate DESC
            LIMIT 1
        ];

        if (users.isEmpty()) {
            return null;
        }

        User linkedUser = users[0];
        LinkedUserResult result = new LinkedUserResult();
        result.userId = linkedUser.Id;
        result.username = linkedUser.Username;
        result.name = linkedUser.Name;
        result.isActive = linkedUser.IsActive;
        return result;
    }
}
