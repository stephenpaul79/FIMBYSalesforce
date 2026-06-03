/**
 * @description Stamps community User identity fields from the linked Contact
 * before insert and update. Prevents welcome and password emails from greeting
 * neighbours with the activating admin's name when Salesforce defaults User.FirstName
 * from the internal user who created the record.
 */
public without sharing class FimbyCommunityUserTriggerHandler {

    private static final String COMMUNITY_LICENSE = 'Customer Community';

    public static void handleBeforeInsert(List<User> newUsers) {
        stampIdentityFromContact(newUsers);
    }

    public static void handleBeforeUpdate(List<User> updatedUsers) {
        stampIdentityFromContact(updatedUsers);
    }

    private static void stampIdentityFromContact(List<User> users) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> profileIds = new Set<Id>();

        for (User u : users) {
            if (u.ContactId == null || u.ProfileId == null) {
                continue;
            }
            contactIds.add(u.ContactId);
            profileIds.add(u.ProfileId);
        }

        if (contactIds.isEmpty()) {
            return;
        }

        Map<Id, Profile> profileById = new Map<Id, Profile>([
            SELECT Id, UserLicense.Name
            FROM Profile
            WHERE Id IN :profileIds
        ]);

        Map<Id, Contact> contactById = new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Email
            FROM Contact
            WHERE Id IN :contactIds
        ]);

        for (User u : users) {
            if (u.ContactId == null || !isCommunityUser(profileById.get(u.ProfileId))) {
                continue;
            }

            Contact c = contactById.get(u.ContactId);
            if (c == null) {
                continue;
            }

            if (String.isNotBlank(c.FirstName)) {
                u.FirstName = c.FirstName;
            }
            if (String.isNotBlank(c.LastName)) {
                u.LastName = c.LastName;
            }
            if (String.isNotBlank(c.Email)) {
                u.Email = c.Email;
            }
        }
    }

    private static Boolean isCommunityUser(Profile p) {
        return p != null
            && p.UserLicense != null
            && p.UserLicense.Name == COMMUNITY_LICENSE;
    }
}
