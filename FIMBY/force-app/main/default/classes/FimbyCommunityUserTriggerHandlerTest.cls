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
}
