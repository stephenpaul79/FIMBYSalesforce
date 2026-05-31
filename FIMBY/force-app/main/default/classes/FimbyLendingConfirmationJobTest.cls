@isTest
public class FimbyLendingConfirmationJobTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static Library_Item__c createTestLibraryItem(Contact ownerContact) {
        Library_Item__c item = new Library_Item__c(
            Name = 'Test Lending Item',
            Description__c = 'Test item for confirmation job',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = ownerContact.Id,
            Neighbourhood__c = ownerContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;
        return item;
    }

    @isTest
    static void testExpiresStaleRequestingConfirmation() {
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testContact);

        Lending_Request__c staleReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(-10),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert staleReq;

        Test.startTest();
        FimbyLendingConfirmationJob.testCutoffOverride = Datetime.now().addDays(1);
        new FimbyLendingConfirmationJob().execute(null);
        Test.stopTest();

        Lending_Request__c updated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :staleReq.Id
        ];
        System.assertEquals('Cancelled', updated.Status__c,
            'Stale Requesting Confirmation request should be cancelled');
    }

    @isTest
    static void testPromotesNextWaitlisted() {
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testContact);

        Lending_Request__c staleReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(-10),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert staleReq;

        Lending_Request__c waitlistedReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(-8),
            of_Days_Needed__c = 5,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert waitlistedReq;

        Test.startTest();
        FimbyLendingConfirmationJob.testCutoffOverride = Datetime.now().addDays(1);
        new FimbyLendingConfirmationJob().execute(null);
        Test.stopTest();

        Lending_Request__c staleUpdated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :staleReq.Id
        ];
        Lending_Request__c waitlistedUpdated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :waitlistedReq.Id
        ];
        System.assertEquals('Cancelled', staleUpdated.Status__c,
            'Stale request should be cancelled');
        System.assertEquals('Requesting Confirmation', waitlistedUpdated.Status__c,
            'Next waitlisted should be promoted');
    }

    @isTest
    static void testNoStaleRequests_NoOp() {
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testContact);

        Lending_Request__c freshReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert freshReq;

        Test.startTest();
        new FimbyLendingConfirmationJob().execute(null);
        Test.stopTest();

        Lending_Request__c unchanged = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :freshReq.Id
        ];
        System.assertEquals('Requesting Confirmation', unchanged.Status__c,
            'Fresh request should not be expired');
    }

    @isTest
    static void testNoPromotionWhenNoWaitlisted() {
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testContact);

        Lending_Request__c staleReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(-10),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert staleReq;

        Test.startTest();
        FimbyLendingConfirmationJob.testCutoffOverride = Datetime.now().addDays(1);
        new FimbyLendingConfirmationJob().execute(null);
        Test.stopTest();

        Lending_Request__c updated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :staleReq.Id
        ];
        System.assertEquals('Cancelled', updated.Status__c,
            'Request should be cancelled even with no waitlist behind it');
    }

    @isTest
    static void testNullRequestedBy() {
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testContact);

        Lending_Request__c staleReq = new Lending_Request__c(
            Library_Item__c = item.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(-10),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert staleReq;

        Test.startTest();
        FimbyLendingConfirmationJob.testCutoffOverride = Datetime.now().addDays(1);
        new FimbyLendingConfirmationJob().execute(null);
        Test.stopTest();

        Lending_Request__c updated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :staleReq.Id
        ];
        System.assertEquals('Cancelled', updated.Status__c,
            'Request with null Requested_By should still be cancelled');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Lending Confirmation Expiry',
            '0 0 7 * * ?',
            new FimbyLendingConfirmationJob()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}
