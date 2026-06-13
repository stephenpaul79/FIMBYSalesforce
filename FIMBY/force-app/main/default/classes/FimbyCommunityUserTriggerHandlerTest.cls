@IsTest
private class FimbyCommunityUserTriggerHandlerTest {

    @IsTest
    static void insertCommunityUser_stampsFirstNameFromContact() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        c.FirstName = 'Marcus';
        c.LastName = 'Neighbour';
        c.Email = 'marcus@fimby.test.com';
        update c;

        Profile communityProfile = [
            SELECT Id
            FROM Profile
            WHERE UserLicense.Name = 'Customer Community'
            LIMIT 1
        ];

        String uniqueUserName = 'marcus' + DateTime.now().getTime() + '@fimby.test.com';
        User u = new User(
            Alias = 'marcus01',
            Email = 'wrong@fimby.test.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'FIMBY',
            LastName = 'Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_CA',
            ProfileId = communityProfile.Id,
            TimeZoneSidKey = 'America/Vancouver',
            UserName = uniqueUserName,
            ContactId = c.Id,
            IsActive = true
        );

        insert u;

        User inserted = [
            SELECT FirstName, LastName, Email
            FROM User
            WHERE Id = :u.Id
        ];
        System.assertEquals('Marcus', inserted.FirstName,
            'Community user FirstName should mirror the linked Contact, not the admin default');
        System.assertEquals('Neighbour', inserted.LastName);
        System.assertEquals('marcus@fimby.test.com', inserted.Email);
    }

    @IsTest
    static void updateCommunityUser_reappliesContactIdentity() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        c.FirstName = 'Marcus';
        update c;

        User u = FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
        u.FirstName = 'FIMBY';
        update u;

        User updated = [SELECT FirstName FROM User WHERE Id = :u.Id];
        System.assertEquals('Marcus', updated.FirstName,
            'Before-update trigger should restore Contact first name on community users');
    }

    @IsTest
    static void newActiveCommunityUser_createsWelcomeTask() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        User thisUser = new User(Id = UserInfo.getUserId());

        Test.startTest();
        System.runAs(thisUser) {
            FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
        }
        Test.stopTest();

        System.assertEquals(1, countSignupTasks(nh.Id, c.Id),
            'Activating a community user should queue exactly one welcome task');
    }

    @IsTest
    static void activationUpdate_createsWelcomeTask() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        User thisUser = new User(Id = UserInfo.getUserId());

        User u = FimbyTestDataFactory.createCommunityUser(c.Id, null, false);
        u.IsActive = false;
        System.runAs(thisUser) {
            insert u;
        }

        Test.startTest();
        System.runAs(thisUser) {
            u.IsActive = true;
            update u;
        }
        Test.stopTest();

        System.assertEquals(1, countSignupTasks(nh.Id, c.Id),
            'Reactivating an inactive community user should queue a welcome task');
    }

    @IsTest
    static void existingWelcomeTask_isNotDuplicated() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        insert new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'New_Signup',
            Priority__c = 'Standard',
            Status__c = 'Resolved',
            Subject_Contact__c = c.Id,
            Summary__c = 'Already welcomed',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':New_Signup:Contact:' + c.Id
        );

        Test.startTest();
        System.enqueueJob(new FimbyWelcomeTaskQueueable(new Set<Id>{ c.Id }));
        Test.stopTest();

        System.assertEquals(1, countSignupTasks(nh.Id, c.Id),
            'A neighbour with an existing welcome task should not be welcomed again');
    }

    @IsTest
    static void emptyContactSet_createsNoTask() {
        Integer before = [SELECT COUNT() FROM Moderator_Task__c WHERE Category__c = 'New_Signup'];

        Test.startTest();
        System.enqueueJob(new FimbyWelcomeTaskQueueable(new Set<Id>()));
        Test.stopTest();

        System.assertEquals(before, [
            SELECT COUNT() FROM Moderator_Task__c WHERE Category__c = 'New_Signup'
        ], 'An empty contact set should never create a welcome task');
    }

    private static Integer countSignupTasks(Id neighbourhoodId, Id contactId) {
        return [
            SELECT COUNT()
            FROM Moderator_Task__c
            WHERE Category__c = 'New_Signup'
              AND Subject_Contact__c = :contactId
              AND Neighbourhood__c = :neighbourhoodId
        ];
    }
}
