/**
 * @description Mirrors Contact identity fields (FirstName, LastName, Email) to
 * the linked User record. Deferred from FimbyProfileController.updateProfileSection
 * because User is a setup object and Contact is not — updating both in one
 * transaction trips MIXED_DML_OPERATION.
 *
 * Uses SYSTEM_MODE because community profiles cannot grant FLS on standard
 * User.FirstName, User.LastName, or User.Email.
 */
public without sharing class FimbySyncUserIdentityQueueable implements Queueable {

    private final Id userId;
    private final Map<String, String> fieldValues;

    public FimbySyncUserIdentityQueueable(Id userId, Map<String, String> fieldValues) {
        this.userId = userId;
        this.fieldValues = fieldValues;
    }

    public void execute(QueueableContext ctx) {
        try {
            User existing = [
                SELECT Id, Email, Username
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            User u = new User(Id = userId);
            for (String fieldName : fieldValues.keySet()) {
                u.put(fieldName, fieldValues.get(fieldName));
            }

            if (fieldValues.containsKey('Email')) {
                String newEmail = fieldValues.get('Email')?.trim();
                if (String.isNotBlank(newEmail) && usernameTracksEmail(existing)) {
                    u.Username = buildUsernameForNewEmail(existing, newEmail);
                }
            }

            Database.SaveResult sr = Database.update(u, AccessLevel.SYSTEM_MODE);
            if (!sr.isSuccess()) {
                String errorMsg = '';
                for (Database.Error err : sr.getErrors()) {
                    errorMsg += err.getMessage() + '; ';
                }
                FimbyLogger.warn('FimbySyncUserIdentityQueueable', 'execute',
                    'User identity sync failed for ' + userId + ': ' + errorMsg);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbySyncUserIdentityQueueable', 'execute', e, userId);
        }
    }

    private static Boolean usernameTracksEmail(User u) {
        if (String.isBlank(u.Username) || String.isBlank(u.Email)) {
            return false;
        }
        String username = u.Username.toLowerCase();
        String email = u.Email.toLowerCase();
        return username == email || username.startsWith(email + '.');
    }

    private static String buildUsernameForNewEmail(User existing, String newEmail) {
        String normalizedEmail = newEmail.toLowerCase();
        String oldEmail = existing.Email.toLowerCase();
        String oldUsername = existing.Username.toLowerCase();

        if (oldUsername == oldEmail) {
            return normalizedEmail;
        }
        if (oldUsername.startsWith(oldEmail + '.')) {
            String suffix = existing.Username.substring(existing.Email.length());
            return normalizedEmail + suffix;
        }
        return existing.Username;
    }
}