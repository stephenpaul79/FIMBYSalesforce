/**
 * @description Community User trigger handler. Before insert/update it stamps
 * community User identity fields from the linked Contact, preventing welcome and
 * password emails from greeting neighbours with the activating admin's name. After
 * insert/update it queues a "New Signup" moderator welcome task when a community
 * user tied to a neighbourhood contact becomes active — the signal that a real
 * login account exists, not just a contact (support people / waitlist contacts
 * never reach this path).
 */
public without sharing class FimbyCommunityUserTriggerHandler {

    private static final String COMMUNITY_LICENSE = 'Customer Community';

    public static void handleBeforeInsert(List<User> newUsers) {
        stampIdentityFromContact(newUsers);
    }

    public static void handleBeforeUpdate(List<User> updatedUsers) {
        stampIdentityFromContact(updatedUsers);
    }

    public static void handleAfterInsert(List<User> newUsers) {
        enqueueWelcomeTasks(collectNewlyActiveContactIds(newUsers, null));
    }

    public static void handleAfterUpdate(List<User> newUsers, Map<Id, User> oldMap) {
        enqueueWelcomeTasks(collectNewlyActiveContactIds(newUsers, oldMap));
    }

    /**
     * @description Contacts behind community users that just became active (new
     * active user, newly activated user, or contact newly linked to an active
     * user). The welcome-task de-dupe lives in FimbyWelcomeTaskQueueable.
     */
    private static Set<Id> collectNewlyActiveContactIds(List<User> users, Map<Id, User> oldMap) {
        List<User> candidates = new List<User>();
        Set<Id> profileIds = new Set<Id>();

        for (User u : users) {
            if (u.ContactId == null || u.ProfileId == null || u.IsActive != true) {
                continue;
            }
            if (oldMap != null) {
                User oldUser = oldMap.get(u.Id);
                Boolean becameActive = oldUser == null || oldUser.IsActive != true;
                Boolean contactJustLinked = oldUser == null || oldUser.ContactId == null;
                if (!becameActive && !contactJustLinked) {
                    continue;
                }
            }
            candidates.add(u);
            profileIds.add(u.ProfileId);
        }

        if (candidates.isEmpty()) {
            return new Set<Id>();
        }

        Map<Id, Profile> profileById = new Map<Id, Profile>([
            SELECT Id, UserLicense.Name
            FROM Profile
            WHERE Id IN :profileIds
        ]);

        Set<Id> contactIds = new Set<Id>();
        for (User u : candidates) {
            if (isCommunityUser(profileById.get(u.ProfileId))) {
                contactIds.add(u.ContactId);
            }
        }
        return contactIds;
    }

    private static void enqueueWelcomeTasks(Set<Id> contactIds) {
        if (contactIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new FimbyWelcomeTaskQueueable(contactIds));
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
