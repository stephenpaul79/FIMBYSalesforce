/**
 * @description Queueable job that deactivates a user account. Replaces the former
 * @future method in FimbyProfileController. Implements System.Finalizer to log
 * success or failure via FimbyLogger.
 */
public without sharing class FimbyDeactivateUserQueueable implements Queueable, System.Finalizer {

    private final Id userId;

    /**
     * @description Constructs the queueable to deactivate the given user.
     * @param userId The User record ID to deactivate
     */
    public FimbyDeactivateUserQueueable(Id userId) {
        this.userId = userId;
    }

    /**
     * @description Queueable execute. Sets User.IsActive = false. Attaches finalizer for error logging.
     * @param ctx Queueable context
     */
    public void execute(QueueableContext ctx) {
        System.attachFinalizer(this);
        User u = new User(Id = userId, IsActive = false);
        Database.SaveResult sr = Database.update(u, false);
        if (!sr.isSuccess()) {
            String errorMsg = '';
            for (Database.Error err : sr.getErrors()) {
                errorMsg += err.getMessage() + '; ';
            }
            FimbyLogger.warn('FimbyDeactivateUserQueueable', 'execute',
                'Deactivation failed for User ' + userId + ': ' + errorMsg);
        }
    }

    /**
     * @description Finalizer callback. Logs unhandled exceptions from the queueable execution.
     * @param fc Finalizer context with result and exception info
     */
    public void execute(System.FinalizerContext fc) {
        switch on fc?.getResult() {
            when UNHANDLED_EXCEPTION {
                FimbyLogger.error('FimbyDeactivateUserQueueable', 'finalizer',
                    new System.CalloutException(
                        'Unhandled exception during user deactivation for ' + userId +
                        ': ' + fc.getException()?.getMessage()
                    ), userId);
            }
            when else {
                // Success path — no action needed
            }
        }
    }
}
