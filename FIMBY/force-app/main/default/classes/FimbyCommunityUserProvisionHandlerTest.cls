@IsTest
private class FimbyCommunityUserProvisionHandlerTest {
    private static Integer emailCounter = 0;

    @TestSetup
    static void setup() {
        FimbyTestDataFactory.createNeighbourhood(true);
    }

    private static Id getNeighbourhoodId() {
        return [SELECT Id FROM Account WHERE Name LIKE 'Test Neighbourhood%' LIMIT 1].Id;
    }

    private static String uniqueEmail() {
        emailCounter++;
        return 'provision' + DateTime.now().getTime() + emailCounter + '@fimby.test.com';
    }

    private static Contact insertContact(String email) {
        Contact c = new Contact(
            FirstName = 'Priya',
            LastName = 'Neighbour',
            Email = email,
            AccountId = getNeighbourhoodId()
        );
        insert c;
        return c;
    }

    private static Community_User_Provision_Event__e eventFor(Id contactId) {
        return new Community_User_Provision_Event__e(Contact_Id__c = contactId);
    }

    @IsTest
    static void publishedEventCreatesCommunityUser() {
        String email = uniqueEmail();
        Contact c = insertContact(email);

        Test.startTest();
        EventBus.publish(eventFor(c.Id));
        Test.stopTest();

        List<User> users = [SELECT Username, Email, Profile.Name, IsActive FROM User WHERE ContactId = :c.Id];
        Assert.areEqual(1, users.size(), 'A community User should be created for the Contact.');
        Assert.areEqual(email.toLowerCase(), users[0].Username, 'Username should equal the Contact email.');
        Assert.areEqual(email.toLowerCase(), users[0].Email, 'Email should equal the Contact email.');
        Assert.areEqual(FimbyCommunityUserProvisionHandler.PROFILE_NAME, users[0].Profile.Name);
        Assert.isTrue(users[0].IsActive);
    }

    @IsTest
    static void successDoesNotAlertAdmins() {
        Contact c = insertContact(uniqueEmail());

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(c.Id) });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM User WHERE ContactId = :c.Id]);
        Assert.areEqual(0, FimbyCommunityUserProvisionHandler.alertsQueued, 'No alert expected on success.');
    }

    @IsTest
    static void duplicateContactEmailSkipsUserAndAlerts() {
        String email = uniqueEmail();
        insertContact(email);
        Contact second = insertContact(email);

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(second.Id) });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE ContactId = :second.Id], 'No User when the email is shared.');
        Assert.areEqual(1, FimbyCommunityUserProvisionHandler.alertsQueued, 'Admins should be alerted.');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Id = :second.Id], 'Contact must remain.');
    }

    @IsTest
    static void existingUserIsSkippedSilently() {
        Contact c = insertContact(uniqueEmail());
        FimbyTestDataFactory.createCommunityUser(c.Id, null, true);

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(c.Id) });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM User WHERE ContactId = :c.Id]);
        Assert.areEqual(0, FimbyCommunityUserProvisionHandler.alertsQueued);
    }

    @IsTest
    static void missingEmailAlerts() {
        Contact c = insertContact(null);

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(c.Id) });
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE ContactId = :c.Id]);
        Assert.areEqual(1, FimbyCommunityUserProvisionHandler.alertsQueued);
    }

    @IsTest
    static void invalidAndUnknownIdsAlert() {
        Contact c = insertContact(uniqueEmail());
        Id deletedId = c.Id;
        delete c;

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{
            new Community_User_Provision_Event__e(Contact_Id__c = 'not-an-id'),
            eventFor(deletedId)
        });
        Test.stopTest();

        Assert.areEqual(1, FimbyCommunityUserProvisionHandler.alertsQueued, 'One summary alert per batch.');
    }
}
