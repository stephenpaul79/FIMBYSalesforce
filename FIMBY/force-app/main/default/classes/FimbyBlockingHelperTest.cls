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

    @isTest
    static void isBlockedHandlesNullsAndMembership() {
        List<Contact> peeps = getContacts();
        Set<Id> blocked = new Set<Id>{ peeps[1].Id };

        System.assert(FimbyBlockingHelper.isBlocked(blocked, peeps[1].Id), 'Member is blocked');
        System.assert(!FimbyBlockingHelper.isBlocked(blocked, peeps[0].Id), 'Non-member is not blocked');
        System.assert(!FimbyBlockingHelper.isBlocked(null, peeps[1].Id), 'Null set is not blocked');
        System.assert(!FimbyBlockingHelper.isBlocked(blocked, null), 'Null candidate is not blocked');
    }

    @isTest
    static void areBlockedDetectsEitherDirection() {
        List<Contact> peeps = getContacts();
        insert new Blocked_Contact__c(Blocker__c = peeps[0].Id, Blocked__c = peeps[1].Id);

        Test.startTest();
        System.assert(FimbyBlockingHelper.areBlocked(peeps[0].Id, peeps[1].Id), 'Blocker → blocked direction');
        System.assert(FimbyBlockingHelper.areBlocked(peeps[1].Id, peeps[0].Id), 'Reverse direction also true');
        System.assert(!FimbyBlockingHelper.areBlocked(peeps[0].Id, peeps[2].Id), 'Unrelated pair not blocked');
        System.assert(!FimbyBlockingHelper.areBlocked(null, peeps[1].Id), 'Null arg not blocked');
        Test.stopTest();
    }

    @isTest
    static void isBlockedFeedAuthorChecksBothStampFields() {
        List<Contact> peeps = getContacts();
        Set<Id> blocked = new Set<Id>{ peeps[1].Id };

        FimbyFeedItem ownerBlocked = new FimbyFeedItem();
        ownerBlocked.ownerContactId = peeps[1].Id;
        FimbyFeedItem authorBlocked = new FimbyFeedItem();
        authorBlocked.realAuthorContactId = peeps[1].Id;
        FimbyFeedItem clean = new FimbyFeedItem();
        clean.ownerContactId = peeps[0].Id;
        clean.realAuthorContactId = peeps[0].Id;

        System.assert(FimbyBlockingHelper.isBlockedFeedAuthor(ownerBlocked, blocked), 'Blocked owner is hidden');
        System.assert(FimbyBlockingHelper.isBlockedFeedAuthor(authorBlocked, blocked), 'Blocked real author is hidden');
        System.assert(!FimbyBlockingHelper.isBlockedFeedAuthor(clean, blocked), 'Unblocked card is shown');
        System.assert(!FimbyBlockingHelper.isBlockedFeedAuthor(null, blocked), 'Null item is not blocked');
        System.assert(!FimbyBlockingHelper.isBlockedFeedAuthor(ownerBlocked, new Set<Id>()), 'Empty set hides nothing');
    }

    @isTest
    static void filterVisibleFeedItemsDropsBlockedAuthors() {
        List<Contact> peeps = getContacts();
        Set<Id> blocked = new Set<Id>{ peeps[1].Id };

        FimbyFeedItem hidden = new FimbyFeedItem();
        hidden.ownerContactId = peeps[1].Id;
        FimbyFeedItem shown = new FimbyFeedItem();
        shown.ownerContactId = peeps[0].Id;

        List<FimbyFeedItem> result =
            FimbyBlockingHelper.filterVisibleFeedItems(new List<FimbyFeedItem>{ hidden, shown }, blocked);

        System.assertEquals(1, result.size(), 'Only the unblocked card remains');
        System.assertEquals(peeps[0].Id, result[0].ownerContactId, 'The unblocked card is the one kept');

        List<FimbyFeedItem> passthrough =
            FimbyBlockingHelper.filterVisibleFeedItems(new List<FimbyFeedItem>{ hidden }, new Set<Id>());
        System.assertEquals(1, passthrough.size(), 'Empty block set filters nothing');
    }

    @isTest
    static void filterVisibleReadsSObjectAuthorFields() {
        List<Contact> peeps = getContacts();
        Set<Id> blocked = new Set<Id>{ peeps[1].Id };

        Story_Comment__c blockedByOwner = new Story_Comment__c(Posted_By__c = peeps[1].Id, Contact__c = peeps[0].Id);
        Story_Comment__c blockedByAuthor = new Story_Comment__c(Posted_By__c = peeps[0].Id, Contact__c = peeps[1].Id);
        Story_Comment__c clean = new Story_Comment__c(Posted_By__c = peeps[0].Id, Contact__c = peeps[0].Id);

        List<String> fields = new List<String>{ 'Posted_By__c', 'Contact__c' };
        List<SObject> result = FimbyBlockingHelper.filterVisible(
            new List<SObject>{ blockedByOwner, blockedByAuthor, clean }, blocked, fields
        );

        System.assertEquals(1, result.size(), 'Both blocked-author rows are dropped');
        System.assertEquals(peeps[0].Id, ((Story_Comment__c) result[0]).Posted_By__c, 'The clean row remains');

        List<SObject> passthrough = FimbyBlockingHelper.filterVisible(
            new List<SObject>{ blockedByOwner }, new Set<Id>(), fields
        );
        System.assertEquals(1, passthrough.size(), 'Empty block set filters nothing');
    }
}
