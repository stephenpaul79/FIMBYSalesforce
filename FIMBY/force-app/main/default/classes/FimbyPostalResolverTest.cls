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
}
