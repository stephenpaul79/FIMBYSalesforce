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
 * Failures never touch the Contact. Each one is logged via FimbyLogger and all
 * active System Administrators get a single summary email per batch.
 */
public without sharing class FimbyCommunityUserProvisionHandler {
    @TestVisible
    private static final String PROFILE_NAME = 'Customer Community User - Mobile App';
    private static final String ADMIN_PROFILE_NAME = 'System Administrator';
    private static final String CLASS_NAME = 'FimbyCommunityUserProvisionHandler';

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

        Set<String> takenUsernames = new Set<String>();
        for (User existing : [SELECT Username FROM User WHERE Username IN :emails]) {
            takenUsernames.add(existing.Username.toLowerCase());
        }

        Map<String, Id> emailToOtherContactId = new Map<String, Id>();
        for (Contact other : [
            SELECT Id, Email
            FROM Contact
            WHERE Email IN :emails AND Id NOT IN :contacts.keySet()
        ]) {
            emailToOtherContactId.put(other.Email.toLowerCase(), other.Id);
        }

        List<User> usersToInsert = new List<User>();
        for (Contact c : contacts.values()) {
            if (contactsWithUser.contains(c.Id)) {
                FimbyLogger.info(CLASS_NAME, 'provision', 'Contact ' + c.Id + ' already has a User; skipped.');
                continue;
            }
            if (String.isBlank(c.Email)) {
                failures.add(describe(c) + ' has no email, so no User was created.');
                continue;
            }
            String email = c.Email.trim().toLowerCase();
            if (takenUsernames.contains(email)) {
                failures.add(describe(c) + ': a User with username ' + email + ' already exists, so no User was created.');
                continue;
            }
            if (emailToOtherContactId.containsKey(email)) {
                failures.add(describe(c) + ': email ' + email + ' is already used by Contact '
                    + recordLink(emailToOtherContactId.get(email)) + ', so no User was created.');
                continue;
            }
            usersToInsert.add(buildUser(c, email, profiles[0].Id));
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

    private static User buildUser(Contact c, String email, Id profileId) {
        String first = String.isBlank(c.FirstName) ? '' : c.FirstName.trim();
        String last = c.LastName.trim();
        String suffix = String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));

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
