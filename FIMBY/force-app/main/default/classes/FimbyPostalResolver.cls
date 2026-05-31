/**
 * @description Invocable Apex resolver for postal-code lookups during sign-up.
 *
 * Used by the FIMBY_Sign_Up Screen Flow to decide between two branches:
 *   1. The postal code matches a Postal_Codes__c row AND the neighbourhood
 *      Account is active (Account.Active__c = 'Yes') -> continue to
 *      Create_Contact path (Vouched_Status__c defaults to 'New').
 *   2. No match, or matched neighbourhood is inactive -> create a Lead.
 *
 * Runs in system context (without sharing) because it is called pre-login
 * by the public sign-up flow where the guest user lacks read access to
 * Postal_Codes__c or Account.Active__c.
 *
 * Returns the resolved Neighbourhood Account Id when found and active so
 * downstream flow elements can stamp Contact.AccountId without re-querying.
 *
 * Public Apex callable from the Screen Flow. NOT exposed to LWCs.
 */
public without sharing class FimbyPostalResolver {

    /**
     * @description Bulkified entry for the screen flow. Each request resolves
     *              one postal code. Results are returned 1:1 in the same order.
     */
    @InvocableMethod(label='Resolve FIMBY Postal Code'
        description='Looks up a postal code and returns whether it maps to an active FIMBY neighbourhood.')
    public static List<Result> resolve(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Result>();
        }

        // Normalize all postal codes once.
        List<String> normalized = new List<String>();
        for (Request r : requests) {
            normalized.add(normalize(r != null ? r.postalCode : null));
        }

        // Single bulk query: match either Name (with-spaces) or Postal_Code_No_Spaces__c.
        Map<String, Postal_Codes__c> byKey = new Map<String, Postal_Codes__c>();
        if (!normalized.isEmpty()) {
            for (Postal_Codes__c pc : [
                SELECT Id, Name, Postal_Code_No_Spaces__c,
                       Neighbourhood_Account__c,
                       Neighbourhood_Account__r.Active__c,
                       Boundary_Account__c,
                       Boundary_Account__r.Active__c
                FROM Postal_Codes__c
                WHERE Postal_Code_No_Spaces__c IN :normalized
            ]) {
                String key = pc.Postal_Code_No_Spaces__c;
                if (String.isNotBlank(key)) {
                    byKey.put(key, pc);
                }
            }
        }

        List<Result> results = new List<Result>();
        for (Request r : requests) {
            results.add(buildResult(r, byKey));
        }
        return results;
    }

    /**
     * @description Programmatic single-postal lookup for Apex callers (org intake, etc.).
     */
    public static Result resolveSingle(String postalCode) {
        if (String.isBlank(postalCode)) {
            return null;
        }
        Request req = new Request();
        req.postalCode = postalCode;
        List<Result> results = resolve(new List<Request>{ req });
        return results.isEmpty() ? null : results[0];
    }

    private static Result buildResult(Request req, Map<String, Postal_Codes__c> byKey) {
        Result out = new Result();
        out.postalCodeAsEntered = req != null ? req.postalCode : null;
        out.normalizedPostalCode = normalize(out.postalCodeAsEntered);
        out.isMatchFound = false;
        out.isActiveNeighbourhood = false;

        if (String.isBlank(out.normalizedPostalCode)) {
            return out;
        }

        Postal_Codes__c pc = byKey.get(out.normalizedPostalCode);
        if (pc == null) {
            return out;
        }

        out.isMatchFound = true;
        out.postalCodeRecordId = pc.Id;

        // Prefer Neighbourhood_Account__c; fall back to Boundary_Account__c.
        Id activeNeighbourhoodId = null;
        if (pc.Neighbourhood_Account__c != null
                && pc.Neighbourhood_Account__r != null
                && 'Yes'.equalsIgnoreCase(pc.Neighbourhood_Account__r.Active__c)) {
            activeNeighbourhoodId = pc.Neighbourhood_Account__c;
        } else if (pc.Boundary_Account__c != null
                && pc.Boundary_Account__r != null
                && 'Yes'.equalsIgnoreCase(pc.Boundary_Account__r.Active__c)) {
            activeNeighbourhoodId = pc.Boundary_Account__c;
        }

        if (activeNeighbourhoodId != null) {
            out.isActiveNeighbourhood = true;
            out.neighbourhoodAccountId = activeNeighbourhoodId;
        }

        return out;
    }

    private static String normalize(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        return raw.toUpperCase().replaceAll('\\s+', '');
    }

    /* ------------------------------------------------------------------
     * Flow contract
     * ------------------------------------------------------------------ */

    public class Request {
        @InvocableVariable(required=true
            label='Postal Code'
            description='Postal code as entered by the user. Spaces and case are normalized.')
        public String postalCode;
    }

    public class Result {
        @InvocableVariable(label='Match Found'
            description='True if Postal_Codes__c contains a matching row (regardless of active status).')
        public Boolean isMatchFound;

        @InvocableVariable(label='Active Neighbourhood'
            description='True when the postal code resolves to an Account whose Active__c picklist equals Yes.')
        public Boolean isActiveNeighbourhood;

        @InvocableVariable(label='Neighbourhood Account Id'
            description='Id of the active neighbourhood Account, or null when no active match.')
        public Id neighbourhoodAccountId;

        @InvocableVariable(label='Postal Code Record Id'
            description='Id of the matched Postal_Codes__c row, or null when no match.')
        public Id postalCodeRecordId;

        @InvocableVariable(label='Postal Code As Entered')
        public String postalCodeAsEntered;

        @InvocableVariable(label='Normalized Postal Code'
            description='Uppercased, whitespace-stripped postal code used for lookup.')
        public String normalizedPostalCode;
    }
}
