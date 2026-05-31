/**
 * @description Subscriber for Reactivation_Request_Event__e. Does the
 * actual work of the /account-paused restore-link flow - looking up the User
 * by Username, confirming the linked Contact is still inside its grace window,
 * minting a token, and emailing the magic link.
 *
 * Why this is a Platform Event subscriber (not inline in the controller):
 *   The publisher is the unauthenticated Experience Cloud guest user. Guests
 *   can't read User / Contact, can't write Reactivation_Token__c, and have
 *   limited Messaging.sendEmail rights. Platform Event triggers run as the
 *   Automated Process user with system-level access, so all that work happens
 *   safely in a separate transaction after the guest's POST returns.
 *
 * Per-event try/catch:
 *   One bad payload shouldn't poison the rest of the batch. Anything that
 *   fails inside processRequest is logged via FimbyLogger and skipped. We
 *   deliberately do NOT rethrow - the user has already been told "if a
 *   restorable account exists we sent a link", so leaking a different outcome
 *   here would only confuse them.
 */
public without sharing class FimbyReactivationRequestEventHandler {

    /**
     * @description Trigger entry point. Iterates the batch and processes each
     * request in isolation.
     */
    public static void handle(List<Reactivation_Request_Event__e> events) {
        if (events == null || events.isEmpty()) return;
        for (Reactivation_Request_Event__e evt : events) {
            try {
                processRequest(evt.Username__c);
            } catch (Exception e) {
                FimbyLogger.error(
                    'FimbyReactivationRequestEventHandler', 'handle', e);
            }
        }
    }

    /**
     * @description Per-event worker. Mirrors the validation gates the old
     * inline controller logic used (silent on unknown username, not-in-grace,
     * past-grace, rate-limit). All failure modes are no-ops because the
     * caller already received the generic anti-enumeration response.
     */
    @TestVisible
    private static void processRequest(String username) {
        if (String.isBlank(username)) return;

        String normalized = username.trim().toLowerCase();
        List<User> users = [
            SELECT Id, ContactId FROM User
            WHERE Username = :normalized
              AND ContactId != NULL
            LIMIT 1
        ];
        if (users.isEmpty()) return;

        User u = users[0];
        List<Contact> contacts = [
            SELECT Id, Grace_Started_At__c, Grace_Window_Days__c
            FROM Contact
            WHERE Id = :u.ContactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) return;

        Contact c = contacts[0];
        if (c.Grace_Started_At__c == null || !FimbyReactivationController.isWithinGraceWindow(c)) {
            return;
        }

        String token = FimbyReactivationTokenService.issueOnDemandToken(c.Id);
        if (token == null) return;

        FimbyReactivationEmailService.sendReactivationLink(u.Id, token);
    }
}
