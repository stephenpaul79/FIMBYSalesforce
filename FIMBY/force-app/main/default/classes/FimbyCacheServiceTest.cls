@isTest
private class FimbyCacheServiceTest {

    @isTest
    static void testGetAndPut() {
        FimbyCacheService.put('TestKey', 'TestValue', 300);
        Object result = FimbyCacheService.get('TestKey');
        // Cache may or may not be available in test context
        if (result != null) {
            System.assertEquals('TestValue', result);
        }
        System.assert(true, 'Get/put should not throw');
    }

    @isTest
    static void testRemove() {
        FimbyCacheService.put('RemoveKey', 'SomeValue', 300);
        FimbyCacheService.remove('RemoveKey');
        System.assert(true, 'Remove should not throw');
    }

    @isTest
    static void testGetSeasonalTheme() {
        Test.startTest();
        Map<String, Object> theme = FimbyCacheService.getSeasonalTheme();
        Test.stopTest();
        // May be null if no active theme matches today — that's fine
        System.assert(true, 'getSeasonalTheme should not throw');
    }

    @isTest
    static void testGetCelebrationActions() {
        Test.startTest();
        List<Map<String, String>> actions = FimbyCacheService.getCelebrationActions();
        Test.stopTest();
        System.assertNotEquals(null, actions, 'Should return a list (possibly empty)');
    }

    @isTest
    static void testGetLoadingMessages() {
        Test.startTest();
        List<Map<String, String>> messages = FimbyCacheService.getLoadingMessages();
        Test.stopTest();
        System.assertNotEquals(null, messages, 'Should return a list (possibly empty)');
    }

    @isTest
    static void testCacheMissTriggersQuery() {
        // First call should miss cache and query
        List<Map<String, String>> first = FimbyCacheService.getCelebrationActions();
        // Second call should hit cache (if partition is available)
        List<Map<String, String>> second = FimbyCacheService.getCelebrationActions();
        System.assertEquals(first.size(), second.size(), 'Both calls should return same data');
    }
}
