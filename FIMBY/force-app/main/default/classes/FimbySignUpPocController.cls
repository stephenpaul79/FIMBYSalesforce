/**
 * @description Throwaway proof-of-concept controller used to validate that a
 *              guest-context LWC on a public Experience Cloud page can complete
 *              an @AuraEnabled round-trip on Safari (where the Flow runtime fails
 *              with "Unauthorized access" due to ITP cookie stripping).
 *
 *              The ping() method echoes the caller's input, returns the server
 *              time and the running user's type (to confirm Guest context), and
 *              exercises the real FimbyPostalResolver read path the production
 *              sign-up form will depend on.
 *
 *              SAFE TO DELETE once the POC is validated and the real
 *              FimbySignUpController is built.
 */
public with sharing class FimbySignUpPocController {

    @AuraEnabled(cacheable=false)
    public static PingResult ping(String message) {
        PingResult result = new PingResult();
        result.echo = message;
        result.serverTime = String.valueOf(System.now());
        result.userType = UserInfo.getUserType();
        result.userName = UserInfo.getName();

        // Exercise the exact read path the real sign-up form needs as guest.
        if (String.isNotBlank(message)) {
            FimbyPostalResolver.Result resolved = FimbyPostalResolver.resolveSingle(message);
            if (resolved != null) {
                result.postalMatchFound = resolved.isMatchFound;
                result.postalActiveNeighbourhood = resolved.isActiveNeighbourhood;
            }
        }
        return result;
    }

    public class PingResult {
        @AuraEnabled public String echo;
        @AuraEnabled public String serverTime;
        @AuraEnabled public String userType;
        @AuraEnabled public String userName;
        @AuraEnabled public Boolean postalMatchFound;
        @AuraEnabled public Boolean postalActiveNeighbourhood;
    }
}
