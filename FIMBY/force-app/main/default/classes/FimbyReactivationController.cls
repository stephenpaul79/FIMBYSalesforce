/**
 * @description Guest-user-callable controller for the in-app delete-with-grace
 * restore flow. Two entry points:
 *
 *   requestReactivationLink(username) - called by fimbyAccountReactivate from
 *     the public /account-paused page. Looks up the User by Username (unique
 *     in Salesforce; Contact.Email is not), confirms the linked Contact is
 *     inside its grace window, mints a fresh reactivation token, and sends
 *     the magic link to the User's email. Always returns the same generic
 *     response regardless of match status to prevent enumeration.
 *
 *   consumeReactivationToken(token) - called by fimbyReactivationLanding from
 *     the public /reactivate?token=... page. Validates the token, flips
 *     User.IsActive=true, clears Grace_Started_At__c on the Contact, marks the
 *     token used, and sends a welcome-back email. Returns enough info for the
 *     landing page to show success / expired / not-found states.
 *
 * Why username (not email):
 *   Salesforce only guarantees User.Username uniqueness. Contact.Email and
 *   User.Email can both have duplicates across the org, which would make an
 *   email-based restore ambiguous (or worse, send a magic link to the wrong
 *   neighbour). Usernames are also what the neighbour actually types into the
 *   login form, so asking for it again here is consistent.
 *
 * Why requestReactivationLink fires a Platform Event instead of doing the work
 * inline: the caller is the unauthenticated Experience Cloud guest user. The
 * guest profile cannot read User / Contact, cannot insert Reactivation_Token__c,
 * and cannot send transactional email reliably. Publishing
 * Reactivation_Request_Event__e hands the work off to
 * FimbyReactivationRequestEventHandler, whose Platform Event trigger runs as
 * the Automated Process user (system-level access). The guest's controller
 * call returns the generic response immediately - the lookup, token mint, and
 * email all happen in the subscriber transaction.
 *
 * consumeReactivationToken still runs inline. The caller IS the guest, but the
 * token itself is the authorization proof and the work is allowed by the
 * without-sharing context.
 */
public without sharing class FimbyReactivationController {

    /**
     * @description Publishes a Reactivation_Request_Event__e for the given
     * username so the system-context subscriber can do the lookup, token
     * mint, and email send. Always returns the same generic success response
     * so guests can't enumerate which usernames belong to FIMBY accounts.
     * The magic link itself is emailed to the linked Contact, not echoed
     * back to the caller.
     */
    @AuraEnabled
    public static Map<String, Object> requestReactivationLink(String username) {
        try {
            if (String.isBlank(username)) {
                return genericResponse();
            }
            // EventBus.publish does NOT throw when the running user lacks
            // Create on the platform event - it returns isSuccess()=false on
            // the SaveResult. Inspect it explicitly so a guest-profile perm
            // gap surfaces as a logged error instead of a silent no-op that
            // looks identical to the happy path.
            Database.SaveResult result = EventBus.publish(
                new Reactivation_Request_Event__e(
                    Username__c = username.trim().toLowerCase()
                )
            );
            if (result != null && !result.isSuccess()) {
                String details = '';
                if (result.getErrors() != null) {
                    for (Database.Error err : result.getErrors()) {
                        details += '[' + err.getStatusCode() + '] ' + err.getMessage() + '; ';
                    }
                }
                FimbyLogger.warn(
                    'FimbyReactivationController', 'requestReactivationLink',
                    'EventBus.publish failed: ' + details);
            }
            return genericResponse();
        } catch (Exception e) {
            FimbyLogger.error('FimbyReactivationController', 'requestReactivationLink', e);
            return genericResponse();
        }
    }

    /**
     * @description Consumes a reactivation token. On success: flips
     * User.IsActive=true, clears Grace_Started_At__c, marks token used, sends
     * welcome-back email. On any validation failure returns a non-leaky reason
     * code so the landing page can show the right copy.
     *
     * Status codes returned to LWC:
     *   'restored'   - account is back, redirect to login
     *   'expired'    - token expired (offer to request new one if still in grace)
     *   'used'       - token already consumed (offer to request new one)
     *   'not_found'  - bad/forged token (generic message)
     *   'past_grace' - token exists but Contact's grace window has elapsed and
     *                  Deactivation_Requested__c is already flagged; account is gone
     */
    @AuraEnabled
    public static Map<String, Object> consumeReactivationToken(String token) {
        try {
            if (String.isBlank(token)) {
                return statusResponse('not_found');
            }

            List<Reactivation_Token__c> rows = [
                SELECT Id, Contact__c, Token__c, Expires_At__c, Used_At__c
                FROM Reactivation_Token__c
                WHERE Token__c = :token
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return statusResponse('not_found');
            }

            Reactivation_Token__c rt = rows[0];
            if (rt.Used_At__c != null) {
                return statusResponse('used');
            }
            if (rt.Expires_At__c != null && rt.Expires_At__c < System.now()) {
                return statusResponse('expired');
            }

            List<Contact> contacts = [
                SELECT Id, Grace_Started_At__c, Grace_Window_Days__c,
                       Deactivation_Requested__c
                FROM Contact
                WHERE Id = :rt.Contact__c
                LIMIT 1
            ];
            if (contacts.isEmpty()) {
                return statusResponse('not_found');
            }

            Contact c = contacts[0];
            if (c.Deactivation_Requested__c == true || !isWithinGraceWindow(c)) {
                return statusResponse('past_grace');
            }

            List<User> users = [
                SELECT Id FROM User WHERE ContactId = :c.Id LIMIT 1
            ];
            if (users.isEmpty()) {
                return statusResponse('not_found');
            }

            new ContactRestorer().restore(c.Id);
            FimbyReactivationTokenService.markUsed(rt.Id);
            // User.IsActive is a setup-object flip; defer via Queueable so the
            // synchronous transaction does not trip MIXED_DML_OPERATION.
            System.enqueueJob(new FimbyReactivateUserQueueable(users[0].Id));
            FimbyReactivationEmailService.sendWelcomeBack(users[0].Id);

            return statusResponse('restored');
        } catch (Exception e) {
            FimbyLogger.error('FimbyReactivationController', 'consumeReactivationToken', e);
            throw new AuraHandledException('Could not restore your account. Please try again or email help@fimby.com.');
        }
    }

    /**
     * @description True when the Contact's grace window hasn't elapsed yet.
     * Uses the per-contact Grace_Window_Days__c override if set, else falls
     * back to the org default. Centralized so the request, consume, and event
     * handler paths apply the same rule.
     */
    public static Boolean isWithinGraceWindow(Contact c) {
        if (c == null || c.Grace_Started_At__c == null) return false;
        Integer windowDays = (c.Grace_Window_Days__c != null)
            ? c.Grace_Window_Days__c.intValue()
            : FimbySettings.defaultGraceWindowDays();
        DateTime cutoff = System.now().addDays(-windowDays);
        return c.Grace_Started_At__c > cutoff;
    }

    private static Map<String, Object> genericResponse() {
        return new Map<String, Object>{
            'success' => true,
            'message' => 'If a restorable FIMBY account exists for that username, we\'ve sent a restore link to the email on file. Please check your inbox.'
        };
    }

    private static Map<String, Object> statusResponse(String status) {
        return new Map<String, Object>{
            'success' => status == 'restored',
            'status' => status
        };
    }

    /**
     * @description Without-sharing helper for Contact restore so the guest
     * user can clear Grace_Started_At__c without sharing rules blocking it.
     */
    private without sharing class ContactRestorer {
        public void restore(Id contactId) {
            update new Contact(
                Id = contactId,
                Grace_Started_At__c = null
            );
        }
    }
}
