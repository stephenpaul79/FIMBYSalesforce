@IsTest
private class FimbyOnboardingWelcomeEmailQueueableTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createCommunityUser(c.Id, 'Customer Community User - Mobile App', true);
        FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, true);
    }

    private static User getTestUser() {
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :nh.Id LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    @IsTest
    static void execute_sendsOnceAndStampsGuard() {
        User testUser = getTestUser();
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Test.startTest();
        System.enqueueJob(new FimbyOnboardingWelcomeEmailQueueable(
            testUser.ContactId, testUser.Id, nh.Id
        ));
        Test.stopTest();

        Contact updated = [
            SELECT Welcome_Email_Sent_Date__c
            FROM Contact WHERE Id = :testUser.ContactId
        ];
        System.assertNotEquals(null, updated.Welcome_Email_Sent_Date__c,
            'Guard stamp should be set after send.');
        System.assertEquals(1, FimbyTransactionalEmailService.testSendInvocationCount,
            'Welcome email should send exactly once.');
        System.assert(
            String.isNotBlank(FimbyTransactionalEmailService.testLastCardHtml),
            'Card HTML should be populated.'
        );
        System.assert(
            FimbyTransactionalEmailService.testLastCardHtml.contains('Staying in the loop'),
            'Educational digest card should be present.'
        );
        System.assert(
            FimbyTransactionalEmailService.testLastSubject.startsWith('Welcome to FIMBY,'),
            'Envelope subject should greet by name.'
        );
        System.assertEquals(
            FimbyOnboardingWelcomeEmailBuilder.HEADER_TITLE,
            FimbyTransactionalEmailService.testLastHeaderTitle,
            'Header title should differ from envelope subject.'
        );
    }

    @IsTest
    static void execute_skipsWhenAlreadySent() {
        User testUser = getTestUser();
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        update new Contact(
            Id = testUser.ContactId,
            Welcome_Email_Sent_Date__c = DateTime.now().addDays(-1)
        );
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Test.startTest();
        System.enqueueJob(new FimbyOnboardingWelcomeEmailQueueable(
            testUser.ContactId, testUser.Id, nh.Id
        ));
        Test.stopTest();

        System.assertEquals(0, FimbyTransactionalEmailService.testSendInvocationCount,
            'Second send should be blocked by guard.');
    }

    @IsTest
    static void builder_includesMiniDigestWhenContentExists() {
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        User testUser = getTestUser();

        FimbyDigestEmailBuilder.DigestResult preview = FimbyDigestEmailBuilder.buildCappedMixedPreview(
            nh.Id, Date.today().addDays(-7), Date.today(), 5, new Set<Id>()
        );
        String html = FimbyOnboardingWelcomeEmailBuilder.buildFullBodyHtml(
            'Sarah', 'Test Neighbourhood 1', preview
        );

        System.assert(html.contains('Staying in the loop'), 'Digest education card expected.');
        System.assert(html.contains('You&rsquo;re onboarded and ready to go'), 'Intro paragraph expected.');
        System.assert(html.contains('A doorbell, not a slot machine'), 'Quiet-hours card expected.');
        System.assert(html.contains('Adjustments welcome'), 'Quiet-hours settings hint expected.');
        System.assert(html.contains('panda-sleeping.png'), 'Sleeping panda image expected.');
        if (!preview.isEmpty) {
            System.assert(html.contains('A peek at the last week on your street'),
                'Mini-digest section should append when items exist.');
        }
    }
}
