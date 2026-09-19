/**
 * @description Coverage + behaviour tests for FimbyPostalResolver.
 */
@isTest
private class FimbyPostalResolverTest {

    private static Account makeActiveNeighbourhood(String name) {
        Account a = new Account(Name = name, Active__c = 'Yes');
        insert a;
        return a;
    }

    private static Account makeInactiveNeighbourhood(String name) {
        Account a = new Account(Name = name, Active__c = 'No');
        insert a;
        return a;
    }

    private static Postal_Codes__c makePostalCode(String code, Id neighbourhoodId, Id boundaryId) {
        Postal_Codes__c pc = new Postal_Codes__c(
            Name = code,
            Neighbourhood_Account__c = neighbourhoodId,
            Boundary_Account__c = boundaryId
        );
        insert pc;
        return pc;
    }

    @isTest
    static void resolves_active_neighbourhood_match() {
        Account hood = makeActiveNeighbourhood('Strathcona V6A');
        makePostalCode('V6A 1A1', hood.Id, null);

        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'v6a 1a1';

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'one result expected');
        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(true, r.isMatchFound, 'postal should match');
        System.assertEquals(true, r.isActiveNeighbourhood, 'neighbourhood should be active');
        System.assertEquals(hood.Id, r.neighbourhoodAccountId, 'should return neighbourhood id');
        System.assertEquals('V6A1A1', r.normalizedPostalCode, 'normalized should strip spaces + uppercase');
        System.assertEquals('V6A 1A1', r.formattedPostalCode, 'formatted should use canonical Canadian spacing');
    }

    @isTest
    static void resolves_mixed_case_and_hyphen_input() {
        Account hood = makeActiveNeighbourhood('Strathcona V6A');
        makePostalCode('V6A 1C5', hood.Id, null);

        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'V6a-1c5';

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(true, r.isMatchFound, 'hyphenated mixed-case input should match');
        System.assertEquals(true, r.isActiveNeighbourhood);
        System.assertEquals(hood.Id, r.neighbourhoodAccountId);
        System.assertEquals('V6A1C5', r.normalizedPostalCode);
        System.assertEquals('V6A 1C5', r.formattedPostalCode);
    }

    @isTest
    static void resolves_compact_lowercase_input_without_spaces() {
        Account hood = makeActiveNeighbourhood('Strathcona V6A');
        makePostalCode('V6A 1C5', hood.Id, null);

        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'v6a1c5';

        Test.startTest();
        FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle('v6a1c5');
        Test.stopTest();

        System.assertEquals(true, r.isMatchFound);
        System.assertEquals(hood.Id, r.neighbourhoodAccountId);
        System.assertEquals('V6A 1C5', r.formattedPostalCode);
    }

    @isTest
    static void resolves_inactive_neighbourhood_as_not_active() {
        Account hood = makeInactiveNeighbourhood('Future Neighbourhood');
        makePostalCode('V6B 2C3', hood.Id, null);

        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'V6B 2C3'; // V, B, C, 2, 3 all allowed

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(true, r.isMatchFound, 'postal row exists');
        System.assertEquals(false, r.isActiveNeighbourhood, 'inactive should be flagged');
        System.assertEquals(null, r.neighbourhoodAccountId, 'no active id returned');
    }

    @isTest
    static void no_match_returns_neither_match_nor_active() {
        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'Z9Z 9Z9';

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(false, r.isMatchFound);
        System.assertEquals(false, r.isActiveNeighbourhood);
        System.assertEquals(null, r.neighbourhoodAccountId);
        System.assertEquals('Z9Z9Z9', r.normalizedPostalCode);
    }

    @isTest
    static void falls_back_to_boundary_account_when_no_neighbourhood() {
        Account boundary = makeActiveNeighbourhood('Boundary Cell');
        makePostalCode('V6C 3E4', null, boundary.Id);

        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = 'V6C 3E4';

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(true, r.isActiveNeighbourhood, 'boundary fallback should resolve active');
        System.assertEquals(boundary.Id, r.neighbourhoodAccountId);
    }

    @isTest
    static void blank_input_returns_safe_empty_result() {
        FimbyPostalResolver.Request req = new FimbyPostalResolver.Request();
        req.postalCode = null;

        Test.startTest();
        List<FimbyPostalResolver.Result> results =
            FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>{ req });
        Test.stopTest();

        FimbyPostalResolver.Result r = results[0];
        System.assertEquals(false, r.isMatchFound);
        System.assertEquals(false, r.isActiveNeighbourhood);
    }

    @isTest
    static void bulk_request_returns_one_to_one_results() {
        Account hood = makeActiveNeighbourhood('Strathcona');
        makePostalCode('V6A 0A0', hood.Id, null);

        List<FimbyPostalResolver.Request> reqs = new List<FimbyPostalResolver.Request>();
        for (Integer i = 0; i < 3; i++) {
            FimbyPostalResolver.Request r = new FimbyPostalResolver.Request();
            r.postalCode = i == 0 ? 'V6A 0A0' : 'Z9Z 9Z9';
            reqs.add(r);
        }

        Test.startTest();
        List<FimbyPostalResolver.Result> results = FimbyPostalResolver.resolve(reqs);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'one result per request');
        System.assertEquals(true,  results[0].isMatchFound,  'first matches');
        System.assertEquals(false, results[1].isMatchFound, 'second misses');
        System.assertEquals(false, results[2].isMatchFound, 'third misses');
    }

    @isTest
    static void empty_input_returns_empty_list() {
        Test.startTest();
        List<FimbyPostalResolver.Result> r1 = FimbyPostalResolver.resolve(new List<FimbyPostalResolver.Request>());
        List<FimbyPostalResolver.Result> r2 = FimbyPostalResolver.resolve(null);
        Test.stopTest();

        System.assertEquals(0, r1.size(), 'empty input -> empty output');
        System.assertEquals(0, r2.size(), 'null input -> empty output');
    }

    @isTest
    static void resolveSingle_returns_match_for_active_neighbourhood() {
        Account hood = makeActiveNeighbourhood('Strathcona V6A');
        makePostalCode('V6A 1A1', hood.Id, null);

        Test.startTest();
        FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle('v6a 1a1');
        Test.stopTest();

        System.assertNotEquals(null, r);
        System.assertEquals(true, r.isMatchFound);
        System.assertEquals(hood.Id, r.neighbourhoodAccountId);
    }

    @isTest
    static void resolveSingle_blank_returns_null() {
        System.assertEquals(null, FimbyPostalResolver.resolveSingle(null));
        System.assertEquals(null, FimbyPostalResolver.resolveSingle(''));
    }

    @isTest
    static void derives_province_and_country_for_canadian_codes() {
        Map<String, String> expectedByPostal = new Map<String, String>{
            'V6A 1A1' => 'BC', 'T2P 1J9' => 'AB', 'S7K 1J5' => 'SK',
            'R3C 4T3' => 'MB', 'M5V 2T6' => 'ON', 'H2Y 1C6' => 'QC',
            'E1C 1E1' => 'NB', 'B3H 4R2' => 'NS', 'C1A 4K7' => 'PE',
            'A1C 5H7' => 'NL', 'Y1A 2C6' => 'YT'
        };

        Test.startTest();
        for (String postal : expectedByPostal.keySet()) {
            FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle(postal);
            System.assertEquals(expectedByPostal.get(postal), r.province,
                'wrong province derived for ' + postal);
            System.assertEquals('CA', r.country, 'Canadian shape should resolve country CA');
        }
        Test.stopTest();
    }

    @isTest
    static void distinguishes_nunavut_from_northwest_territories() {
        Test.startTest();
        FimbyPostalResolver.Result nunavut = FimbyPostalResolver.resolveSingle('X0A 0H0');
        FimbyPostalResolver.Result northwest = FimbyPostalResolver.resolveSingle('X1A 1A1');
        Test.stopTest();

        System.assertEquals('NU', nunavut.province, 'X0A belongs to Nunavut');
        System.assertEquals('NT', northwest.province, 'other X codes belong to NWT');
    }

    @isTest
    static void derives_state_and_country_for_us_zips() {
        Map<String, String> expectedByZip = new Map<String, String>{
            '98104' => 'WA', '97201' => 'OR', '90001' => 'CA', '10001' => 'NY',
            '60601' => 'IL', '73301' => 'TX', '73101' => 'OK', '88901' => 'NV',
            '88001' => 'NM', '79901' => 'TX', '96801' => 'HI', '99501' => 'AK',
            '02101' => 'MA', '33101' => 'FL', '00501' => 'NY'
        };

        Test.startTest();
        for (String zip : expectedByZip.keySet()) {
            FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle(zip);
            System.assertEquals(expectedByZip.get(zip), r.province,
                'wrong state derived for ' + zip);
            System.assertEquals('US', r.country, 'five-digit shape should resolve country US');
            System.assertEquals(zip, r.formattedPostalCode, 'five-digit ZIP formats unchanged');
        }
        Test.stopTest();
    }

    /**
     * Postal_Codes__c has a validation rule restricting Name to the Canadian
     * "X1X 1X1" shape, so no US row can exist to match against yet. Until that
     * is relaxed, a US ZIP derives country/state/format but never matches.
     */
    @isTest
    static void zip_plus_four_derives_without_matching_a_neighbourhood() {
        Test.startTest();
        FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle('98104-1234');
        Test.stopTest();

        System.assertEquals('98104-1234', r.formattedPostalCode, 'ZIP+4 keeps its hyphen for display');
        System.assertEquals('981041234', r.normalizedPostalCode, 'lookup key strips the hyphen');
        System.assertEquals('WA', r.province, 'state derives from the five-digit base');
        System.assertEquals('US', r.country);
        System.assertEquals(false, r.isMatchFound, 'no US row can exist while the format rule stands');
        System.assertEquals(false, r.isActiveNeighbourhood);
    }

    @isTest
    static void unmapped_canadian_letter_has_country_but_no_province() {
        Test.startTest();
        FimbyPostalResolver.Result r = FimbyPostalResolver.resolveSingle('Z9Z 9Z9');
        Test.stopTest();

        System.assertEquals('CA', r.country, 'shape is Canadian even though Z is unassigned');
        System.assertEquals(null, r.province, 'unassigned letter should not guess a province');
    }

    @isTest
    static void unrecognized_shape_derives_nothing() {
        Test.startTest();
        FimbyPostalResolver.Result garbage = FimbyPostalResolver.resolveSingle('NOT A CODE');
        FimbyPostalResolver.Result shortZip = FimbyPostalResolver.resolveSingle('1234');
        Test.stopTest();

        System.assertEquals(null, garbage.country, 'unrecognized shape has no country');
        System.assertEquals(null, garbage.province, 'unrecognized shape has no province');
        System.assertEquals(null, garbage.formattedPostalCode, 'unrecognized shape has no display format');
        System.assertEquals(null, shortZip.country, 'four digits is not a ZIP');
        System.assertEquals(null, shortZip.formattedPostalCode);
    }
}
