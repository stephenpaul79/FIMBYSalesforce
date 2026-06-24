/**
 * @description Sends the one-time post-onboarding welcome email after profile setup completes.
 * Runs asynchronously to avoid mixed-DML issues (Contact update in controller, email + guard stamp here).
 */
public without sharing class FimbyOnboardingWelcomeEmailQueueable implements System.Queueable, System.Finalizer {

    private static final Integer PREVIEW_MAX_ITEMS = 5;
    private static final Integer PREVIEW_WINDOW_DAYS = 7;

    private final Id contactId;
    private final Id userId;
    private final Id neighbourhoodId;

    public FimbyOnboardingWelcomeEmailQueueable(Id contactId, Id userId, Id neighbourhoodId) {
        this.contactId = contactId;
        this.userId = userId;
        this.neighbourhoodId = neighbourhoodId;
    }

    public void execute(System.QueueableContext qc) {
        System.attachFinalizer(this);
        if (contactId == null || userId == null || neighbourhoodId == null) {
            return;
        }

        List<Contact> contacts = [
            SELECT Id, Welcome_Email_Sent_Date__c, FirstName
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        if (contacts.isEmpty() || contacts[0].Welcome_Email_Sent_Date__c != null) {
            return;
        }

        List<User> users = [
            SELECT Id, FirstName, Email
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        if (users.isEmpty() || String.isBlank(users[0].Email)) {
            return;
        }

        String neighbourhoodName = null;
        List<Account> neighbourhoods = [
            SELECT Name FROM Account WHERE Id = :neighbourhoodId LIMIT 1
        ];
        if (!neighbourhoods.isEmpty()) {
            neighbourhoodName = neighbourhoods[0].Name;
        }

        Date windowEnd = Date.today();
        Date windowStart = windowEnd.addDays(-PREVIEW_WINDOW_DAYS);
        Set<Id> excluded = FimbyBlockingHelper.getBidirectionalBlocks(contactId);
        FimbyDigestEmailBuilder.DigestResult miniDigest = FimbyDigestEmailBuilder.buildCappedMixedPreview(
            neighbourhoodId, windowStart, windowEnd, PREVIEW_MAX_ITEMS, excluded
        );

        String firstName = String.isNotBlank(users[0].FirstName)
            ? users[0].FirstName
            : contacts[0].FirstName;
        String cardHtml = FimbyOnboardingWelcomeEmailBuilder.buildFullBodyHtml(
            firstName, neighbourhoodName, miniDigest
        );

        FimbyTransactionalEmailService.TransactionalEmailRequest request =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        request.recipientUserId = userId;
        request.subject = FimbyOnboardingWelcomeEmailBuilder.SUBJECT;
        request.cardHtml = cardHtml;
        request.ctaUrl = FimbySettings.getUrl('Site_Base');
        request.ctaLabel = 'Open FIMBY';
        FimbyTransactionalEmailService.send(request);

        update new Contact(
            Id = contactId,
            Welcome_Email_Sent_Date__c = DateTime.now()
        );
    }

    public void execute(System.FinalizerContext fc) {
        if (fc != null && fc.getResult() == System.ParentJobResult.UNHANDLED_EXCEPTION) {
            FimbyLogger.error(
                'FimbyOnboardingWelcomeEmailQueueable',
                'execute',
                fc.getException()
            );
        }
    }
}
