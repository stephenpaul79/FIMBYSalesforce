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
    static void duplicateContactEmailStillCreatesUser() {
        String email = uniqueEmail();
        insertContact(email);
        Contact second = insertContact(email);

        Test.startTest();
        FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(second.Id) });
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM User WHERE ContactId = :second.Id], 'Shared Contact email must not block.');
        Assert.areEqual(0, FimbyCommunityUserProvisionHandler.alertsQueued);
    }

    private static User insertHolderUser(Id contactId, String username, String nickname, Boolean isActive) {
        User holder = FimbyTestDataFactory.createCommunityUser(contactId, null, false);
        if (username != null) {
            holder.Username = username;
        }
        if (nickname != null) {
            holder.CommunityNickname = nickname;
        }
        insert holder;
        if (!isActive) {
            update new User(Id = holder.Id, IsActive = false);
        }
        return holder;
    }

    private static void runHandler(Id contactId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyCommunityUserProvisionHandler.handle(new List<Community_User_Provision_Event__e>{ eventFor(contactId) });
        }
    }

    @IsTest
    static void inactiveUsernameHolderIsRenamed() {
        String email = uniqueEmail();
        Contact oldContact = insertContact(uniqueEmail());
        Contact newContact = insertContact(email);
        User holder;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            holder = insertHolderUser(oldContact.Id, email, null, false);
        }

        Test.startTest();
        runHandler(newContact.Id);
        Test.stopTest();

        Assert.areEqual(email + '.inactive', [SELECT Username FROM User WHERE Id = :holder.Id].Username);
        Assert.areEqual(email, [SELECT Username FROM User WHERE ContactId = :newContact.Id].Username);
        Assert.areEqual(0, FimbyCommunityUserProvisionHandler.alertsQueued);
    }

    @IsTest
    static void activeUsernameHolderBlocksAndAlerts() {
        String email = uniqueEmail();
        Contact oldContact = insertContact(uniqueEmail());
        Contact newContact = insertContact(email);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertHolderUser(oldContact.Id, email, null, true);
        }

        Test.startTest();
        runHandler(newContact.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE ContactId = :newContact.Id]);
        Assert.areEqual(1, FimbyCommunityUserProvisionHandler.alertsQueued);
    }

    @IsTest
    static void inactiveNicknameHolderIsRenamed() {
        FimbyCommunityUserProvisionHandler.nicknameSuffixOverride = '7777';
        Contact oldContact = insertContact(uniqueEmail());
        Contact newContact = insertContact(uniqueEmail());
        User holder;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            holder = insertHolderUser(oldContact.Id, null, 'Priya N7777', false);
        }

        Test.startTest();
        runHandler(newContact.Id);
        Test.stopTest();

        Assert.areEqual('Priya N7777_inactive', [SELECT CommunityNickname FROM User WHERE Id = :holder.Id].CommunityNickname);
        Assert.areEqual('Priya N7777', [SELECT CommunityNickname FROM User WHERE ContactId = :newContact.Id].CommunityNickname);
    }

    @IsTest
    static void activeNicknameHolderBlocksAndAlerts() {
        FimbyCommunityUserProvisionHandler.nicknameSuffixOverride = '8888';
        Contact oldContact = insertContact(uniqueEmail());
        Contact newContact = insertContact(uniqueEmail());
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertHolderUser(oldContact.Id, null, 'Priya N8888', true);
        }

        Test.startTest();
        runHandler(newContact.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE ContactId = :newContact.Id]);
        Assert.areEqual(1, FimbyCommunityUserProvisionHandler.alertsQueued);
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
