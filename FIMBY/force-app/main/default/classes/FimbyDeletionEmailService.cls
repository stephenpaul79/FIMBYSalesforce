/**
 * @description Sends the three transactional emails for the Email-to-Case
 * account-deletion flow:
 *   1. Verification — "Reply CONFIRM DELETE within 7 days"
 *   2. Cancellation — sent on CANCEL reply or 7-day expiry
 *   3. Completion  — last email before the user is locked out
 *
 * Why bodies are inline:
 *   The plain-text bodies must contain the exact protocol tokens
 *   (CONFIRM DELETE / CANCEL) and the time-window wording. Treating them
 *   as code keeps the protocol auditable and prevents an admin from
 *   editing a template in a way that breaks confirmation parsing. Copy
 *   changes go through a normal Apex deploy.
 *
 * All emails are sent with setWhatId(caseId) so they thread back via the
 * Email-to-Case Thread Email Headers, and replies append to the same Case.
 */
public without sharing class FimbyDeletionEmailService {

    private static final String OWEA_DISPLAY_NAME = 'FIMBY';

    @TestVisible
    private static Integer testEmailsSent = 0;
    @TestVisible
    private static List<Messaging.SingleEmailMessage> testCapturedEmails =
        new List<Messaging.SingleEmailMessage>();

    private static final String VERIFICATION_SUBJECT =
        '[FIMBY] Please confirm your account deletion';
    private static final String CANCELLED_SUBJECT =
        '[FIMBY] Your deletion request has been cancelled';
    private static final String COMPLETED_SUBJECT =
        '[FIMBY] Your FIMBY account has been deactivated';
    private static final String NO_MATCH_SUBJECT =
        '[FIMBY] We couldn\'t find an account for that email';

    /**
     * @description Sends the verification email asking the user to reply
     * CONFIRM DELETE. Sent to User.Email (via setTargetObjectId) so the
     * email is unlimited / not subject to per-day org limits.
     * @param caseId Case Id (drives threading)
     * @param userId User Id whose email receives the verification
     */
    public static void sendVerification(Id caseId, Id userId) {
        if (caseId == null || userId == null) return;

        String body =
            'Hi neighbour,\n\n' +
            'We received a request to delete the FIMBY account tied to this email address.\n\n' +
            'If that was you, please reply to this email with the words:\n\n' +
            '    CONFIRM DELETE\n\n' +
            'Reply within 7 days. After that, the request will quietly expire and your account will keep working.\n\n' +
            'If you did NOT ask for this, you have two options:\n' +
            '  - Reply with the word CANCEL, or\n' +
            '  - Just ignore this email.\n\n' +
            'Either way, nothing will change unless we hear "CONFIRM DELETE" from this address.\n\n' +
            'Once you confirm, we wait 24 more hours before doing anything irreversible. If you change your mind, write back to us in that window and we can usually pull the request.\n\n' +
            'For more on what happens when you delete your account, see ' + FimbyPublicWebsiteLinks.getUrl('Delete_Account_Docs') + '.\n\n' +
            'With care,\n' +
            'FIMBY';

        send(caseId, userId, VERIFICATION_SUBJECT, body);
    }

    /**
     * @description Sends the cancellation email — fires when the user replies
     * CANCEL or the 7-day window expires without confirmation.
     */
    public static void sendCancellation(Id caseId, Id userId) {
        if (caseId == null || userId == null) return;

        String body =
            'Hi neighbour,\n\n' +
            'Your account-deletion request has been cancelled — your FIMBY account is unchanged and ready when you are.\n\n' +
            'If you ever do want to delete your account, you can:\n' +
            '  - Use the "Deactivate Account" button in Settings while logged in, or\n' +
            '  - Email help@fimby.com from this address with the subject "Delete my account".\n\n' +
            'With care,\n' +
            'FIMBY';

        send(caseId, userId, CANCELLED_SUBJECT, body);
    }

    /**
     * @description Sends the completion email — fires the moment the
     * deletion is enqueued, before User.IsActive flips false. Last email the
     * user will receive from the platform.
     */
    public static void sendCompletion(Id caseId, Id userId) {
        if (caseId == null || userId == null) return;

        String body =
            'Hi neighbour,\n\n' +
            'This is the last email you\'ll get from FIMBY.\n\n' +
            'Your account has been deactivated:\n' +
            '  - Your login is being revoked right now.\n' +
            '  - Your posts, stories, library listings, and group-chat messages will be removed within 24 hours.\n' +
            '  - Your profile is being anonymized to "A former neighbour" so blocks you set and shared lending records still resolve.\n' +
            '  - Reports you filed are kept for 90 days, then anonymized.\n\n' +
            'If this was a mistake, reply within 7 days and we can usually restore your account. After that, the cleanup is final.\n\n' +
            'Thanks for being part of the neighbourhood.\n\n' +
            'With care,\n' +
            'FIMBY';

        send(caseId, userId, COMPLETED_SUBJECT, body);
    }

    /**
     * @description Sends a "no active account for that email" notice to the
     * sender of a deletion email when no matching active User can be resolved.
     * Sent to a raw to-address (not a User) so it falls under standard daily
     * email limits — that's intentional, since this path is also the abuse
     * surface.
     * @param caseId Case Id (drives threading back into the same Case for audit)
     * @param toAddress Raw email address to reply to
     */
    public static void sendNoActiveAccount(Id caseId, String toAddress) {
        if (caseId == null || String.isBlank(toAddress)) return;

        String body =
            'Hi,\n\n' +
            'We received a request to delete a FIMBY account from this email address, but we couldn\'t find an active account that matches it.\n\n' +
            'Two possibilities:\n' +
            '  - The account email may be different. Try emailing us again from the address you log in with.\n' +
            '  - The account may already be deactivated.\n\n' +
            'No further action will be taken on this request.\n\n' +
            'With care,\n' +
            'FIMBY';

        sendDirect(caseId, toAddress, NO_MATCH_SUBJECT, body);
    }

    /**
     * @description Internal sender that targets a User record (unlimited
     * email path). Threads back into the Case via setWhatId.
     */
    private static void send(Id caseId, Id userId, String subject, String body) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(userId);
            email.setTreatTargetObjectAsRecipient(true);
            email.setWhatId(caseId);
            email.setSaveAsActivity(true);
            email.setSubject(subject);
            email.setPlainTextBody(body);

            Id oweaId = getOweaId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            if (Test.isRunningTest()) {
                testCapturedEmails.add(email);
                testEmailsSent++;
                return;
            }
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbyDeletionEmailService', 'send', e, caseId);
        }
    }

    /**
     * @description Internal sender for the no-active-account path. Falls
     * back to setToAddresses since there is no User to target.
     */
    private static void sendDirect(Id caseId, String toAddress, String subject, String body) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ toAddress });
            email.setWhatId(caseId);
            email.setSaveAsActivity(true);
            email.setSubject(subject);
            email.setPlainTextBody(body);

            Id oweaId = getOweaId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            if (Test.isRunningTest()) {
                testCapturedEmails.add(email);
                testEmailsSent++;
                return;
            }
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbyDeletionEmailService', 'sendDirect', e, caseId);
        }
    }

    @TestVisible
    private static Id oweaCached;
    private static Id getOweaId() {
        if (oweaCached == null) {
            List<OrgWideEmailAddress> oweas = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = :OWEA_DISPLAY_NAME LIMIT 1
            ];
            oweaCached = oweas.isEmpty() ? null : oweas[0].Id;
        }
        return oweaCached;
    }
}
