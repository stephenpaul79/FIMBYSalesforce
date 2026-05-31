/**
 * @description Mirrors Contact identity fields (FirstName, LastName, Email) to
 * the linked User record. Deferred from FimbyProfileController.updateProfileSection
 * because User is a setup object and Contact is not — updating both in one
 * transaction trips MIXED_DML_OPERATION.
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
            User u = new User(Id = userId);
            for (String fieldName : fieldValues.keySet()) {
                u.put(fieldName, fieldValues.get(fieldName));
            }

            Database.SaveResult sr = Database.update(u, false);
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
}
