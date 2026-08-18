@IsTest
private class FimbyResponseAutoShareHelperTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact poster = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        poster.Email = 'poster.autoshare.helper@fimby.test.com';
        poster.Phone = '0400111222';
        update poster;
        FimbyTestDataFactory.createCommunityUser(poster.Id, null, true);
    }

    private static User getPosterUser() {
        Contact poster = [
            SELECT Id FROM Contact WHERE Email = 'poster.autoshare.helper@fimby.test.com' LIMIT 1
        ];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :poster.Id AND IsActive = true LIMIT 1];
    }

    private static Needs_Offers__c createPost(User posterUser) {
        Contact ownerContact = [
            SELECT Id, AccountId FROM Contact WHERE Id = :posterUser.ContactId LIMIT 1
        ];
        Id recordTypeId;
        try {
            recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
                .get('Offer').getRecordTypeId();
        } catch (Exception e) {
            recordTypeId = null;
        }
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Auto share helper post',
            Details__c = 'Testing auto share helper',
            Full_Details__c = 'Full auto share helper details',
            Contact__c = ownerContact.Id,
            Posted_By__c = ownerContact.Id,
            Neighbourhood__c = ownerContact.AccountId,
            Status__c = 'Posted',
            Giver_Recipient_Type__c = 'Self',
            Auto_Share_Contact_Info__c = true,
            Total_Quantity__c = 5,
            Per_Response_Limit__c = 5,
            End_Date__c = Date.today().addDays(7)
        );
        if (recordTypeId != null) {
            post.RecordTypeId = recordTypeId;
        }
        insert post;
        return post;
    }

    @IsTest
    static void acceptCreatesOneActiveEpisodeAndDoesNotUseFlow() {
        User posterUser = getPosterUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact responder = new Contact(
            FirstName = 'Auto',
            LastName = 'HelperResponder',
            AccountId = neighbourhood.Id,
            Email = 'autoshare.helper.responder@fimby.test.com'
        );
        insert responder;

        Needs_Offers__c post;
        Response__c resp;
        System.runAs(posterUser) {
            post = createPost(posterUser);
            resp = new Response__c(
                Name = 'Helper auto share',
                Need_Offer_Responded_To__c = post.Id,
                Contact__c = responder.Id,
                On_Behalf_Of_Contact__c = responder.Id,
                Status__c = 'Accepted',
                Amount_Requested__c = 1
            );
            insert resp;
        }

        Test.startTest();
        System.runAs(posterUser) {
            FimbyResponseAutoShareHelper.tryAutoShareOnAccept(resp.Id);
            FimbyResponseAutoShareHelper.tryAutoShareOnAccept(resp.Id);
        }
        Test.stopTest();

        List<Shared_Contact_Info__c> shares = [
            SELECT Id, Status__c, Contact__c, Shared_To__c, Origin__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c = :posterUser.ContactId AND Shared_To__c = :responder.Id
        ];
        System.assertEquals(1, shares.size(), 'Auto-share must create or reuse exactly one Active episode');
        System.assertEquals('Active', shares[0].Status__c);
        System.assertEquals('Response', shares[0].Origin__c);
    }

    @IsTest
    static void revokedEpisodeDoesNotBlockANewAutoShare() {
        User posterUser = getPosterUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact responder = new Contact(
            FirstName = 'Auto',
            LastName = 'HelperRevoked',
            AccountId = neighbourhood.Id,
            Email = 'autoshare.helper.revoked@fimby.test.com'
        );
        insert responder;

        Needs_Offers__c post;
        Response__c resp;
        System.runAs(posterUser) {
            post = createPost(posterUser);
            resp = new Response__c(
                Name = 'Helper auto share revoked',
                Need_Offer_Responded_To__c = post.Id,
                Contact__c = responder.Id,
                On_Behalf_Of_Contact__c = responder.Id,
                Status__c = 'Accepted',
                Amount_Requested__c = 1
            );
            insert resp;
        }

        System.runAs(posterUser) {
            FimbyResponseAutoShareHelper.tryAutoShareOnAccept(resp.Id);
        }
        Shared_Contact_Info__c first = [
            SELECT Id FROM Shared_Contact_Info__c
            WHERE Contact__c = :posterUser.ContactId AND Shared_To__c = :responder.Id
        ];
        first.Status__c = 'Revoked';
        update first;

        Test.startTest();
        System.runAs(posterUser) {
            FimbyResponseAutoShareHelper.tryAutoShareOnAccept(resp.Id);
        }
        Test.stopTest();

        List<Shared_Contact_Info__c> shares = [
            SELECT Id, Status__c FROM Shared_Contact_Info__c
            WHERE Contact__c = :posterUser.ContactId AND Shared_To__c = :responder.Id
            ORDER BY CreatedDate DESC, Id DESC
        ];
        System.assertEquals(2, shares.size(), 'A closed auto-share must not block a new episode');
        Shared_Contact_Info__c newest = shares[0];
        Shared_Contact_Info__c closed = [
            SELECT Status__c FROM Shared_Contact_Info__c WHERE Id = :first.Id
        ];
        System.assertNotEquals(first.Id, newest.Id, 'Share again must insert a new row');
        System.assertEquals('Active', newest.Status__c, 'Newest episode must be open');
        System.assertEquals('Revoked', closed.Status__c, 'Original episode must stay closed');
    }

    @IsTest
    static void nullAndDisabledAreNoOps() {
        FimbyResponseAutoShareHelper.tryAutoShareOnAccept(null);
        System.assertEquals(0, [SELECT COUNT() FROM Shared_Contact_Info__c]);
    }
}
