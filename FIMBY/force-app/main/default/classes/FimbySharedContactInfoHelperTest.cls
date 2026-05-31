@isTest
private class FimbySharedContactInfoHelperTest {

    @isTest
    static void testHasExpandedContactShare_NewPhone() {
        Shared_Contact_Info__c before = new Shared_Contact_Info__c(
            Email__c = 'a@test.com'
        );
        Shared_Contact_Info__c after = before.clone(false, false, false, false);
        after.Phone__c = '555-1234';

        System.assertEquals(
            true,
            FimbySharedContactInfoHelper.hasExpandedContactShare(before, after),
            'Adding phone should count as expanded share'
        );
    }

    @isTest
    static void testHasExpandedContactShare_SameFields() {
        Shared_Contact_Info__c before = new Shared_Contact_Info__c(
            Email__c = 'a@test.com',
            Phone__c = '555-1234'
        );
        Shared_Contact_Info__c after = before.clone(false, false, false, false);

        System.assertEquals(
            false,
            FimbySharedContactInfoHelper.hasExpandedContactShare(before, after),
            'Unchanged share should not count as expanded'
        );
    }

    @isTest
    static void testBuildAfterStateReplace_AddsAddress() {
        Shared_Contact_Info__c before = new Shared_Contact_Info__c(
            Email__c = 'a@test.com'
        );
        Shared_Contact_Info__c after = FimbySharedContactInfoHelper.buildAfterStateReplace(
            before,
            true,
            false,
            true,
            'a@test.com',
            null,
            '123 Main',
            'Vancouver',
            'BC',
            'V6B 1A1',
            'Canada',
            'Buzz 42'
        );

        System.assertEquals(true, FimbySharedContactInfoHelper.hasExpandedContactShare(before, after));
        System.assertEquals('123 Main', after.Street__c);
    }
}
