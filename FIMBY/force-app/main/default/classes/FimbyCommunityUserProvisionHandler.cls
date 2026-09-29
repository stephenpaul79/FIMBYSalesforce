/**
 * @description Subscriber logic for Community_User_Provision_Event__e. Enables
 * Contacts created by the FIMBY_Sign_Up_Private flow as Customer Community
 * Users (Username = Email) and sends the site welcome email.
 *
 * Why a Platform Event subscriber: the flow runs as the Experience Cloud guest
 * user, who cannot insert Users, and a Contact + User insert in one transaction
 * trips MIXED_DML_OPERATION. The event publishes after the Contact commits and
 * this handler runs as the admin in CommunityUserProvisionEventTriggerConfig.
 *
 * Only an ACTIVE User holding the same Username or CommunityNickname blocks
 * creation. An inactive holder is renamed (".inactive" / "_inactive") to free
 * the value. Duplicate Contact emails are allowed.
 *
 * Failures never touch the Contact. Each one is logged via FimbyLogger and all
 * active System Administrators get a single summary email per batch.
 */
public without sharing class FimbyCommunityUserProvisionHandler {
    @TestVisible
    private static final String PROFILE_NAME = 'Customer Community User - Mobile App';
    private static final String ADMIN_PROFILE_NAME = 'System Administrator';
    private static final String CLASS_NAME = 'FimbyCommunityUserProvisionHandler';
    private static final String INACTIVE_USERNAME_SUFFIX = '.inactive';
    private static final String INACTIVE_NICKNAME_SUFFIX = '_inactive';

    @TestVisible
    private static String nicknameSuffixOverride;

    @TestVisible
    private static Integer alertsQueued = 0;

    /**
     * @description Trigger entry point. Collects Contact Ids from the batch,
     * provisions Users, and alerts admins about anything that failed.
     */
    public static void handle(List<Community_User_Provision_Event__e> events) {
        List<String> failures = new List<String>();
        Set<Id> contactIds = new Set<Id>();

        for (Community_User_Provision_Event__e evt : events) {
            try {
                contactIds.add(Id.valueOf(evt.Contact_Id__c));
            } catch (Exception e) {
                failures.add('Invalid Contact Id on event: "' + evt.Contact_Id__c + '"');
            }
        }

        try {
            failures.addAll(provision(contactIds));
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'handle', e);
            failures.add('Unexpected error provisioning ' + contactIds + ': ' + e.getMessage());
        }

        if (!failures.isEmpty()) {
            notifyAdmins(failures);
        }
    }

    private static List<String> provision(Set<Id> contactIds) {
        List<String> failures = new List<String>();
        if (contactIds.isEmpty()) {
            return failures;
        }

        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Email
            FROM Contact
            WHERE Id IN :contactIds
        ]);
        for (Id missingId : contactIds) {
            if (!contacts.containsKey(missingId)) {
                failures.add('Contact ' + missingId + ' was not found.');
            }
        }

        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :PROFILE_NAME LIMIT 1];
        if (profiles.isEmpty()) {
            failures.add('Profile "' + PROFILE_NAME + '" was not found; no Users were created for ' + contacts.keySet() + '.');
            return failures;
        }

        Set<Id> contactsWithUser = new Set<Id>();
        for (User existing : [SELECT ContactId FROM User WHERE ContactId IN :contacts.keySet()]) {
            contactsWithUser.add(existing.ContactId);
        }

        Set<String> emails = new Set<String>();
        for (Contact c : contacts.values()) {
            if (String.isNotBlank(c.Email)) {
                emails.add(c.Email.trim().toLowerCase());
            }
        }

        List<User> candidates = new List<User>();
        for (Contact c : contacts.values()) {
            if (contactsWithUser.contains(c.Id)) {
                FimbyLogger.info(CLASS_NAME, 'provision', 'Contact ' + c.Id + ' already has a User; skipped.');
                continue;
            }
            if (String.isBlank(c.Email)) {
                failures.add(describe(c) + ' has no email, so no User was created.');
                continue;
            }
            candidates.add(buildUser(c, c.Email.trim().toLowerCase(), profiles[0].Id));
        }
        if (candidates.isEmpty()) {
            return failures;
        }

        Set<String> nicknames = new Set<String>();
        for (User candidate : candidates) {
            nicknames.add(candidate.CommunityNickname.toLowerCase());
        }
        Map<String, User> usernameToExisting = new Map<String, User>();
        Map<String, User> nicknameToExisting = new Map<String, User>();
        for (User existing : [
            SELECT Id, Username, CommunityNickname, IsActive
            FROM User
            WHERE Username IN :emails OR CommunityNickname IN :nicknames
        ]) {
            usernameToExisting.put(existing.Username.toLowerCase(), existing);
            if (String.isNotBlank(existing.CommunityNickname)) {
                nicknameToExisting.put(existing.CommunityNickname.toLowerCase(), existing);
            }
        }

        Map<Id, User> inactiveRenames = new Map<Id, User>();
        Map<Id, Set<Id>> contactIdToRenamedUserIds = new Map<Id, Set<Id>>();
        List<User> usersToInsert = new List<User>();
        for (User candidate : candidates) {
            Contact c = contacts.get(candidate.ContactId);
            User usernameHolder = usernameToExisting.get(candidate.Username);
            User nicknameHolder = nicknameToExisting.get(candidate.CommunityNickname.toLowerCase());

            if (usernameHolder != null && usernameHolder.IsActive) {
                failures.add(describe(c) + ': an active User (' + recordLink(usernameHolder.Id) + ') already has username '
                    + candidate.Username + ', so no User was created.');
                continue;
            }
            if (nicknameHolder != null && nicknameHolder.IsActive) {
                failures.add(describe(c) + ': an active User (' + recordLink(nicknameHolder.Id) + ') already has nickname '
                    + candidate.CommunityNickname + ', so no User was created.');
                continue;
            }

            Set<Id> renamedIds = new Set<Id>();
            if (usernameHolder != null) {
                User rename = inactiveRenames.containsKey(usernameHolder.Id)
                    ? inactiveRenames.get(usernameHolder.Id)
                    : new User(Id = usernameHolder.Id);
                rename.Username = retiredUsername(usernameHolder.Username);
                inactiveRenames.put(usernameHolder.Id, rename);
                renamedIds.add(usernameHolder.Id);
            }
            if (nicknameHolder != null) {
                User rename = inactiveRenames.containsKey(nicknameHolder.Id)
                    ? inactiveRenames.get(nicknameHolder.Id)
                    : new User(Id = nicknameHolder.Id);
                rename.CommunityNickname = retiredNickname(nicknameHolder.CommunityNickname);
                inactiveRenames.put(nicknameHolder.Id, rename);
                renamedIds.add(nicknameHolder.Id);
            }
            contactIdToRenamedUserIds.put(c.Id, renamedIds);
            usersToInsert.add(candidate);
        }

        Map<Id, String> failedRenameToMessage = retireInactiveUsers(inactiveRenames.values());
        if (!failedRenameToMessage.isEmpty()) {
            List<User> stillInsertable = new List<User>();
            for (User candidate : usersToInsert) {
                String blocker;
                for (Id renamedId : contactIdToRenamedUserIds.get(candidate.ContactId)) {
                    if (failedRenameToMessage.containsKey(renamedId)) {
                        blocker = 'renaming inactive User ' + recordLink(renamedId) + ' failed - '
                            + failedRenameToMessage.get(renamedId);
                    }
                }
                if (blocker == null) {
                    stillInsertable.add(candidate);
                } else {
                    failures.add(describe(contacts.get(candidate.ContactId)) + ': ' + blocker + ', so no User was created.');
                }
            }
            usersToInsert = stillInsertable;
        }

        if (usersToInsert.isEmpty()) {
            return failures;
        }

        Database.DMLOptions options = new Database.DMLOptions();
        options.optAllOrNone = false;
        options.EmailHeader.triggerUserEmail = true;

        List<Database.SaveResult> results = Database.insert(usersToInsert, options);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            List<String> messages = new List<String>();
            for (Database.Error err : results[i].getErrors()) {
                messages.add(err.getStatusCode() + ': ' + err.getMessage());
            }
            failures.add(describe(contacts.get(usersToInsert[i].ContactId)) + ': User insert failed - '
                + String.join(messages, '; '));
        }
        return failures;
    }

    private static String retiredUsername(String username) {
        return username + INACTIVE_USERNAME_SUFFIX;
    }

    private static String retiredNickname(String nickname) {
        return nickname.left(40 - INACTIVE_NICKNAME_SUFFIX.length() - 2) + INACTIVE_NICKNAME_SUFFIX;
    }

    /**
     * @description Frees a username/nickname held by an inactive User by renaming
     * it (e.g. jane@x.ca -> jane@x.ca.inactive). Appends 2, 3, ... when an
     * earlier retirement already took the base name.
     * @return failed User Id -> error message
     */
    private static Map<Id, String> retireInactiveUsers(List<User> renames) {
        Map<Id, String> failedIdToMessage = new Map<Id, String>();
        if (renames.isEmpty()) {
            return failedIdToMessage;
        }

        List<String> usernamePatterns = new List<String>();
        List<String> nicknamePatterns = new List<String>();
        for (User rename : renames) {
            if (rename.Username != null) {
                usernamePatterns.add(rename.Username + '%');
            }
            if (rename.CommunityNickname != null) {
                nicknamePatterns.add(rename.CommunityNickname + '%');
            }
        }
        Set<String> takenUsernames = new Set<String>();
        Set<String> takenNicknames = new Set<String>();
        for (User existing : [
            SELECT Username, CommunityNickname
            FROM User
            WHERE Username LIKE :usernamePatterns OR CommunityNickname LIKE :nicknamePatterns
        ]) {
            takenUsernames.add(existing.Username.toLowerCase());
            if (existing.CommunityNickname != null) {
                takenNicknames.add(existing.CommunityNickname.toLowerCase());
            }
        }

        for (User rename : renames) {
            if (rename.Username != null) {
                rename.Username = nextFree(rename.Username, takenUsernames);
            }
            if (rename.CommunityNickname != null) {
                rename.CommunityNickname = nextFree(rename.CommunityNickname, takenNicknames);
            }
        }

        List<Database.SaveResult> results = Database.update(renames, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            List<String> messages = new List<String>();
            for (Database.Error err : results[i].getErrors()) {
                messages.add(err.getStatusCode() + ': ' + err.getMessage());
            }
            failedIdToMessage.put(renames[i].Id, String.join(messages, '; '));
        }
        return failedIdToMessage;
    }

    private static String nextFree(String base, Set<String> taken) {
        String candidate = base;
        Integer n = 2;
        while (taken.contains(candidate.toLowerCase())) {
            candidate = base + n;
            n++;
        }
        taken.add(candidate.toLowerCase());
        return candidate;
    }

    private static User buildUser(Contact c, String email, Id profileId) {
        String first = String.isBlank(c.FirstName) ? '' : c.FirstName.trim();
        String last = c.LastName.trim();
        String suffix = nicknameSuffixOverride != null
            ? nicknameSuffixOverride
            : String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));

        String alias = (first.left(1) + last).replaceAll('[^A-Za-z0-9]', '').toLowerCase().left(8);
        if (String.isBlank(alias)) {
            alias = 'fimby';
        }

        String nickname = ((first + ' ' + last.left(1)).trim()).left(30) + suffix;

        return new User(
            ContactId = c.Id,
            ProfileId = profileId,
            Username = email,
            Email = email,
            FirstName = String.isBlank(first) ? null : first,
            LastName = last,
            Alias = alias,
            CommunityNickname = nickname,
            TimeZoneSidKey = 'America/Vancouver',
            LocaleSidKey = 'en_CA',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            IsActive = true
        );
    }

    private static void notifyAdmins(List<String> failures) {
        for (String failure : failures) {
            FimbyLogger.warn(CLASS_NAME, 'handle', failure);
        }

        try {
            List<String> toAddresses = new List<String>();
            for (User admin : [
                SELECT Email
                FROM User
                WHERE Profile.Name = :ADMIN_PROFILE_NAME AND IsActive = true
                LIMIT 100
            ]) {
                toAddresses.add(admin.Email);
            }
            if (toAddresses.isEmpty()) {
                return;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('FIMBY private sign-up: community user could not be created');
            mail.setPlainTextBody(
                'The Contact record(s) were created, but the Customer Community User step needs attention:\n\n- '
                + String.join(failures, '\n- ')
                + '\n\nFix the issue, then enable the Contact as a customer user manually from the Contact record.'
            );
            mail.setSaveAsActivity(false);
            alertsQueued++;
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'notifyAdmins', e);
        }
    }

    private static String describe(Contact c) {
        return (String.isBlank(c.FirstName) ? '' : c.FirstName + ' ') + c.LastName + ' (' + recordLink(c.Id) + ')';
    }

    private static String recordLink(Id recordId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
    }
}
