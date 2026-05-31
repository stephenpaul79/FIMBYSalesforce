@isTest
private class FimbyBlockingHelperTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> peeps = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
        FimbyTestDataFactory.createCommunityUser(peeps[0].Id, null, true);
    }

    private static List<Contact> getContacts() {
        return [SELECT Id FROM Contact WHERE AccountId != null ORDER BY CreatedDate ASC];
    }

    @isTest
    static void returnsEmptyForNullInput() {
        Test.startTest();
        Set<Id> result = FimbyBlockingHelper.getBidirectionalBlocks(null);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'Null input should return empty set');
    }

    @isTest
    static void returnsEmptyWhenNoBlocks() {
        List<Contact> peeps = getContacts();
        Test.startTest();
        Set<Id> result = FimbyBlockingHelper.getBidirectionalBlocks(peeps[0].Id);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'No blocks → empty set');
    }

    @isTest
    static void includesBothDirectionsAndExcludesSelf() {
        List<Contact> peeps = getContacts();
        Contact me = peeps[0];
        Contact iBlocked = peeps[1];
        Contact blockedMe = peeps[2];

        insert new List<Blocked_Contact__c>{
            new Blocked_Contact__c(Blocker__c = me.Id,        Blocked__c = iBlocked.Id),
            new Blocked_Contact__c(Blocker__c = blockedMe.Id, Blocked__c = me.Id)
        };

        Test.startTest();
        Set<Id> result = FimbyBlockingHelper.getBidirectionalBlocks(me.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Both directions included');
        System.assert(result.contains(iBlocked.Id),  'People I blocked are included');
        System.assert(result.contains(blockedMe.Id), 'People who blocked me are included');
        System.assert(!result.contains(me.Id),       'Self should never appear in the set');
    }
}
