/**
 * @description Invocable Apex resolver for postal-code lookups during sign-up.
 *
 * Used by the FIMBY_Sign_Up Screen Flow to decide between two branches:
 *   1. The postal code matches a Postal_Codes__c row AND the neighbourhood
 *      Account is active (Account.Active__c = 'Yes') -> continue to
 *      Create_Contact path (Vouched_Status__c defaults to 'New').
 *   2. No match, or matched neighbourhood is inactive -> waitlist Contact path.
 *
 * Runs in system context (without sharing) because it is called pre-login
 * by the public sign-up flow where the guest user lacks read access to
 * Postal_Codes__c or Account.Active__c.
 *
 * Returns the resolved Neighbourhood Account Id when found and active so
 * downstream flow elements can stamp Contact.AccountId without re-querying.
 *
 * Also derives country and province/state from the code itself so the sign-up
 * form does not have to ask for them as free text. Both Canadian postal codes
 * (A1A 1A1) and US ZIP codes (12345 / 12345-6789) are recognized; derivation
 * returns null for anything else rather than guessing.
 *
 * Public Apex callable from the Screen Flow. NOT exposed to LWCs.
 */
public without sharing class FimbyPostalResolver {

    private static final String COUNTRY_CANADA = 'CA';
    private static final String COUNTRY_US = 'US';

    private static final Map<String, String> PROVINCE_BY_POSTAL_LETTER = new Map<String, String>{
        'A' => 'NL', 'B' => 'NS', 'C' => 'PE', 'E' => 'NB',
        'G' => 'QC', 'H' => 'QC', 'J' => 'QC',
        'K' => 'ON', 'L' => 'ON', 'M' => 'ON', 'N' => 'ON', 'P' => 'ON',
        'R' => 'MB', 'S' => 'SK', 'T' => 'AB', 'V' => 'BC', 'Y' => 'YT'
    };

    // X is the only first letter shared by two territories; Nunavut owns these
    // three forward sortation areas and the Northwest Territories hold the rest.
    private static final Set<String> NUNAVUT_FSAS = new Set<String>{ 'X0A', 'X0B', 'X0C' };

    // US state by leading three ZIP digits. Ranges are inclusive and ordered
    // numerically; unassigned prefixes fall through and resolve to null.
    private static final List<ZipRange> US_STATE_BY_ZIP_PREFIX = new List<ZipRange>{
        new ZipRange(  5,   5, 'NY'), new ZipRange(  6,   7, 'PR'),
        new ZipRange(  8,   8, 'VI'), new ZipRange(  9,   9, 'PR'),
        new ZipRange( 10,  27, 'MA'), new ZipRange( 28,  29, 'RI'),
        new ZipRange( 30,  38, 'NH'), new ZipRange( 39,  49, 'ME'),
        new ZipRange( 50,  59, 'VT'), new ZipRange( 60,  69, 'CT'),
        new ZipRange( 70,  89, 'NJ'), new ZipRange( 90,  98, 'AE'),
        new ZipRange(100, 149, 'NY'), new ZipRange(150, 196, 'PA'),
        new ZipRange(197, 199, 'DE'), new ZipRange(200, 205, 'DC'),
        new ZipRange(206, 219, 'MD'), new ZipRange(220, 246, 'VA'),
        new ZipRange(247, 268, 'WV'), new ZipRange(270, 289, 'NC'),
        new ZipRange(290, 299, 'SC'), new ZipRange(300, 319, 'GA'),
        new ZipRange(320, 339, 'FL'), new ZipRange(340, 340, 'AA'),
        new ZipRange(341, 349, 'FL'), new ZipRange(350, 369, 'AL'),
        new ZipRange(370, 385, 'TN'), new ZipRange(386, 397, 'MS'),
        new ZipRange(398, 399, 'GA'), new ZipRange(400, 427, 'KY'),
        new ZipRange(430, 459, 'OH'), new ZipRange(460, 479, 'IN'),
        new ZipRange(480, 499, 'MI'), new ZipRange(500, 528, 'IA'),
        new ZipRange(530, 549, 'WI'), new ZipRange(550, 567, 'MN'),
        new ZipRange(569, 569, 'DC'), new ZipRange(570, 577, 'SD'),
        new ZipRange(580, 588, 'ND'), new ZipRange(590, 599, 'MT'),
        new ZipRange(600, 629, 'IL'), new ZipRange(630, 658, 'MO'),
        new ZipRange(660, 679, 'KS'), new ZipRange(680, 693, 'NE'),
        new ZipRange(700, 714, 'LA'), new ZipRange(716, 729, 'AR'),
        new ZipRange(730, 732, 'OK'), new ZipRange(733, 733, 'TX'),
        new ZipRange(734, 749, 'OK'), new ZipRange(750, 799, 'TX'),
        new ZipRange(800, 816, 'CO'), new ZipRange(820, 831, 'WY'),
        new ZipRange(832, 838, 'ID'), new ZipRange(840, 847, 'UT'),
        new ZipRange(850, 865, 'AZ'), new ZipRange(870, 884, 'NM'),
        new ZipRange(885, 885, 'TX'), new ZipRange(889, 898, 'NV'),
        new ZipRange(900, 961, 'CA'), new ZipRange(962, 966, 'AP'),
        new ZipRange(967, 968, 'HI'), new ZipRange(969, 969, 'GU'),
        new ZipRange(970, 979, 'OR'), new ZipRange(980, 994, 'WA'),
        new ZipRange(995, 999, 'AK')
    };

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

        Set<String> lookupKeys = new Set<String>();
        for (Request r : requests) {
            lookupKeys.addAll(lookupKeysFor(normalizeForLookup(r != null ? r.postalCode : null)));
        }

        Map<String, Postal_Codes__c> byKey = new Map<String, Postal_Codes__c>();
        if (!lookupKeys.isEmpty()) {
            for (Postal_Codes__c pc : [
                SELECT Id, Name, Postal_Code_No_Spaces__c,
                       Neighbourhood_Account__c,
                       Neighbourhood_Account__r.Active__c,
                       Boundary_Account__c,
                       Boundary_Account__r.Active__c
                FROM Postal_Codes__c
                WHERE Postal_Code_No_Spaces__c IN :lookupKeys
                   OR Name IN :lookupKeys
            ]) {
                if (String.isNotBlank(pc.Postal_Code_No_Spaces__c)) {
                    byKey.put(normalizeForLookup(pc.Postal_Code_No_Spaces__c), pc);
                }
                if (String.isNotBlank(pc.Name)) {
                    byKey.put(normalizeForLookup(pc.Name), pc);
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
        out.normalizedPostalCode = normalizeForLookup(out.postalCodeAsEntered);
        out.formattedPostalCode = formatPostalCode(out.normalizedPostalCode);
        out.country = deriveCountry(out.normalizedPostalCode);
        out.province = deriveProvince(out.normalizedPostalCode);
        out.isMatchFound = false;
        out.isActiveNeighbourhood = false;

        if (String.isBlank(out.normalizedPostalCode)) {
            return out;
        }

        Postal_Codes__c pc = matchPostalRow(out.normalizedPostalCode, byKey);
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

    private static Postal_Codes__c matchPostalRow(String compact, Map<String, Postal_Codes__c> byKey) {
        Postal_Codes__c pc = byKey.get(compact);
        if (pc != null) {
            return pc;
        }
        // ZIP+4 entries are stored against their five-digit base.
        String zipBase = usZipBase(compact);
        return zipBase == null ? null : byKey.get(zipBase);
    }

    /**
     * @description Every key a stored Postal_Codes__c row might use for this
     *              input: the compact form, the display format (Name), and the
     *              five-digit base of a ZIP+4.
     */
    private static Set<String> lookupKeysFor(String compact) {
        Set<String> keys = new Set<String>();
        if (String.isBlank(compact)) {
            return keys;
        }
        keys.add(compact);
        String formatted = formatPostalCode(compact);
        if (String.isNotBlank(formatted)) {
            keys.add(formatted);
        }
        String zipBase = usZipBase(compact);
        if (zipBase != null) {
            keys.add(zipBase);
        }
        return keys;
    }

    /**
     * @description Strips non-alphanumeric characters and uppercases letters so
     *              user input like "v6a-1c5", "V6A 1C5", or "V6a1c5" all resolve
     *              to the same lookup key (e.g. "V6A1C5").
     */
    private static String normalizeForLookup(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        return raw.toUpperCase().replaceAll('[^A-Z0-9]', '');
    }

    /**
     * @description Formats a recognized code for display: "V6A 1C5" for Canada,
     *              "98104" or "98104-1234" for the US. Returns null when the
     *              input matches neither shape.
     */
    private static String formatPostalCode(String compact) {
        if (isCanadianPostalCode(compact)) {
            return compact.substring(0, 3) + ' ' + compact.substring(3);
        }
        if (isUsZip(compact)) {
            return compact.length() == 9
                ? compact.substring(0, 5) + '-' + compact.substring(5)
                : compact;
        }
        return null;
    }

    private static String deriveCountry(String compact) {
        if (isCanadianPostalCode(compact)) {
            return COUNTRY_CANADA;
        }
        return isUsZip(compact) ? COUNTRY_US : null;
    }

    /**
     * @description Two-letter province code for Canadian postal codes, or state
     *              code for US ZIPs. Null when the code shape is unrecognized.
     */
    private static String deriveProvince(String compact) {
        if (isCanadianPostalCode(compact)) {
            return canadianProvince(compact);
        }
        return isUsZip(compact) ? usState(compact) : null;
    }

    private static String canadianProvince(String compact) {
        String firstLetter = compact.substring(0, 1);
        if (firstLetter == 'X') {
            return NUNAVUT_FSAS.contains(compact.substring(0, 3)) ? 'NU' : 'NT';
        }
        return PROVINCE_BY_POSTAL_LETTER.get(firstLetter);
    }

    private static String usState(String compact) {
        Integer prefix = Integer.valueOf(compact.substring(0, 3));
        for (ZipRange range : US_STATE_BY_ZIP_PREFIX) {
            if (prefix >= range.low && prefix <= range.high) {
                return range.state;
            }
        }
        return null;
    }

    private static Boolean isCanadianPostalCode(String compact) {
        return String.isNotBlank(compact)
            && Pattern.matches('[A-Z][0-9][A-Z][0-9][A-Z][0-9]', compact);
    }

    private static Boolean isUsZip(String compact) {
        return String.isNotBlank(compact)
            && (Pattern.matches('[0-9]{5}', compact) || Pattern.matches('[0-9]{9}', compact));
    }

    private static String usZipBase(String compact) {
        return (isUsZip(compact) && compact.length() == 9) ? compact.substring(0, 5) : null;
    }

    private class ZipRange {
        private final Integer low;
        private final Integer high;
        private final String state;

        private ZipRange(Integer low, Integer high, String state) {
            this.low = low;
            this.high = high;
            this.state = state;
        }
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
            description='Uppercased, non-alphanumeric-stripped postal code used for lookup.')
        public String normalizedPostalCode;

        @InvocableVariable(label='Formatted Postal Code'
            description='Display format: "V6A 1C5" in Canada, "98104" or "98104-1234" in the US. Null when unrecognized.')
        public String formattedPostalCode;

        @InvocableVariable(label='Province or State'
            description='Two-letter province code (Canada) or state code (US) derived from the postal code. Null when unrecognized.')
        public String province;

        @InvocableVariable(label='Country'
            description='Two-letter country code derived from the postal code shape: CA, US, or null.')
        public String country;
    }
}
