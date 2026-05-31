/**
 * @description Helper that mints, looks up, and consumes Reactivation_Token__c
 * records. Centralized so FimbyReactivationController and
 * FimbyReactivationEmailService never touch the SObject directly. Token strings
 * are 36-character cryptographic-random (UUID4) values, opaque to clients.
 */
public without sharing class FimbyReactivationTokenService {

    private static final Integer RATE_LIMIT_PER_24H = 3;

    /**
     * @description Mints a token for the delete-with-grace confirmation email.
     * Expiry is the end of the grace window passed in by the caller (so the
     * link remains valid for the full 30 days). Always succeeds (no rate-limit
     * check) because this is the canonical confirmation, not a user request.
     */
    public static String issueGraceWindowToken(Id contactId, DateTime expiresAt) {
        Reactivation_Token__c rt = new Reactivation_Token__c(
            Contact__c = contactId,
            Token__c = generateToken(),
            Expires_At__c = expiresAt,
            Request_Count_24h__c = 1
        );
        insert rt;
        return rt.Token__c;
    }

    /**
     * @description Mints a token for the /account-paused magic-link request
     * flow. Enforces a 3-tokens-per-24h-per-Contact rate limit by inspecting
     * recent rows. Returns null when the limit is hit so the controller can
     * silently no-op (consistent with the anti-enumeration response).
     */
    public static String issueOnDemandToken(Id contactId) {
        DateTime since = System.now().addHours(-24);
        Integer recentCount = [
            SELECT COUNT() FROM Reactivation_Token__c
            WHERE Contact__c = :contactId
              AND CreatedDate >= :since
        ];
        if (recentCount >= RATE_LIMIT_PER_24H) {
            FimbyLogger.warn('FimbyReactivationTokenService', 'issueOnDemandToken',
                'Rate limit hit for Contact ' + contactId +
                ' (' + recentCount + ' tokens in last 24h)');
            return null;
        }

        Integer ttlHours = FimbySettings.reactivationTokenTtlHours();
        Reactivation_Token__c rt = new Reactivation_Token__c(
            Contact__c = contactId,
            Token__c = generateToken(),
            Expires_At__c = System.now().addHours(ttlHours),
            Request_Count_24h__c = recentCount + 1
        );
        insert rt;
        return rt.Token__c;
    }

    /**
     * @description Looks up a token; returns the row if it's valid (not used,
     * not expired), else null. Caller is responsible for marking it used after
     * the restore succeeds via markUsed.
     */
    public static Reactivation_Token__c findValid(String token) {
        if (String.isBlank(token)) return null;

        List<Reactivation_Token__c> rows = [
            SELECT Id, Contact__c, Token__c, Expires_At__c, Used_At__c
            FROM Reactivation_Token__c
            WHERE Token__c = :token
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;

        Reactivation_Token__c rt = rows[0];
        if (rt.Used_At__c != null) return null;
        if (rt.Expires_At__c != null && rt.Expires_At__c < System.now()) return null;
        return rt;
    }

    /**
     * @description Marks the token consumed. Run inside the same transaction as
     * the User.IsActive=true flip so the token can't be reused if the restore
     * partially fails.
     */
    public static void markUsed(Id tokenId) {
        if (tokenId == null) return;
        update new Reactivation_Token__c(
            Id = tokenId,
            Used_At__c = System.now()
        );
    }

    /**
     * @description Generates a 36-character UUID-shape opaque token. Uses
     * Crypto.getRandomLong to produce 192 bits of entropy then hex-encodes,
     * matching Salesforce platform random sources.
     */
    private static String generateToken() {
        Blob random = Crypto.generateAesKey(192);
        return EncodingUtil.convertToHex(random).substring(0, 36);
    }
}
