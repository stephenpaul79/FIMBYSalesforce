/**
 * @description Server-side session termination for a true "logout means logout".
 *
 * The mobile app's OAuth re-login runs in a separate browser (iOS
 * ASWebAuthenticationSession / Android Custom Tabs) whose Salesforce session
 * cookie lives in a different jar than the WebView. Redirecting the WebView to
 * /secur/logout.jsp only clears the WebView's cookie, so the OAuth browser can
 * still hold a live session and Salesforce silently issues a fresh auth code on
 * the next sign-in — re-authentication never actually happens.
 *
 * Deleting the AuthSession record kills the session server-side regardless of
 * which cookie jar holds it. With every session for the user gone, the next
 * OAuth attempt finds nothing to reuse and Salesforce forces a real login.
 *
 * `without sharing` so the AuthSession DML runs in system mode — the community
 * site profile does not need explicit AuthSession permissions.
 */
public without sharing class FimbySessionController {

    /**
     * Terminate every session for the running user so a logout requires
     * re-authentication to get back in. Best-effort: the logout handler does not
     * block its redirect on this and swallows any error.
     *
     * Experience Cloud external-user sessions are SessionType ChatterNetworks /
     * TempChatterNetworks / InternalServiceCall (NOT Oauth2/UI) — an earlier
     * type allowlist matched none of them and made this a silent no-op, which is
     * why silent re-login kept working. An external community user has no
     * federated/SSO session to protect, so we delete ALL of the user's sessions.
     *
     * We delete child sessions (InternalServiceCall carries a ParentId) first so
     * a parent removal can't fault its children, then every other NON-current
     * session — including the OAuth-browser session that enables silent
     * re-login. The running WebView session (IsCurrent = true) is left for the
     * /secur/logout.jsp redirect to clear: deleting the session you are running
     * in mid-transaction can fault, and since all DML here shares one
     * transaction, that fault would roll back the very deletes that matter.
     *
     * Deleting an empty list is a harmless no-op (the normal case in a test
     * context, where AuthSession returns no rows), so no isEmpty() guard needed.
     */
    @AuraEnabled
    public static void endAllSessions() {
        Id userId = UserInfo.getUserId();

        delete [
            SELECT Id
            FROM AuthSession
            WHERE UsersId = :userId
              AND ParentId != null
              AND IsCurrent = false
        ];

        delete [
            SELECT Id
            FROM AuthSession
            WHERE UsersId = :userId
              AND IsCurrent = false
        ];
    }
}
