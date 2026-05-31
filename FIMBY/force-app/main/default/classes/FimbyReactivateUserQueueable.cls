/**
 * @description Mirror of FimbyDeactivateUserQueueable for the restore path.
 * Flipping User.IsActive=true in the same transaction as Contact/Token DML
 * would trip the MIXED_DML_OPERATION restriction (User is a setup object),
 * so the synchronous reactivation controller hands the flip off to this
 * queueable. In production it runs within seconds of the trigger; the LWC
 * shows "Welcome back" immediately and the user logs in moments later.
 */
public without sharing class FimbyReactivateUserQueueable implements Queueable {

    private final Id userId;

    public FimbyReactivateUserQueueable(Id userId) {
        this.userId = userId;
    }

    /**
     * @description Queueable execute. Sets User.IsActive = true. Errors are
     * caught and logged so a failed flip never silently rolls back the
     * caller's Contact/Token updates from the synchronous transaction.
     */
    public void execute(QueueableContext ctx) {
        try {
            User u = new User(Id = userId, IsActive = true);
            Database.SaveResult sr = Database.update(u, false);
            if (!sr.isSuccess()) {
                String errorMsg = '';
                for (Database.Error err : sr.getErrors()) {
                    errorMsg += err.getMessage() + '; ';
                }
                FimbyLogger.warn('FimbyReactivateUserQueueable', 'execute',
                    'Reactivation failed for User ' + userId + ': ' + errorMsg);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyReactivateUserQueueable', 'execute', e, userId);
        }
    }
}
