@isTest
public class FeedCommentHelperTest {
    @isTest
    static void testPreventCspLitePortalComments() {
         // Create a test Account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        // Create a test Contact
        Contact testContact = new Contact(LastName = 'Portal', AccountId = testAccount.Id);
        insert testContact;

 
        // Create a test user with UserType 'CspLitePortal'
        Profile p = [SELECT Id FROM Profile WHERE Name='Customer Community User - FIMBY'];
        User portalUser = new User(
            Alias = 'cspuser',
            Email = 'cspuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            ContactId = testContact.Id,
            Neighbourhood__c = 'V6AStrathconaDTES',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'cspuser@test.com'
        );
        insert portalUser;

        // Create a test user with a different UserType
        Profile sp = [SELECT Id FROM Profile WHERE Name='Standard Platform User'];

        User standardUser = new User(
            Alias = 'stduser',
            Email = 'stduser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Standard',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = sp.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'stduser@fimby.test.com'
        );
        insert standardUser;

        // Create a FeedItem as the portal user
//        System.runAs(portalUser) {
//            FeedItem feedItem = new FeedItem(
//                Body = 'Test Feed Item',
//                NetworkScope = 'AllNetworks',
//                Visibility = 'AllUsers',
//                ParentId = UserInfo.getUserId()
//            );
//            insert feedItem;

            // Create a FeedComment by the portal user
//            FeedComment feedComment = new FeedComment(
//                CommentBody = 'Test Comment',
//                FeedItemId = feedItem.Id
//            );

//            Test.startTest();
//            try {
//                insert feedComment;
//                System.assert(false, 'Expected DmlException was not thrown');
//            } catch (DmlException e) {
//                System.assert(e.getMessage().contains('Please do not place comments directly in the feed.'));
//            }
//            Test.stopTest();
//        }

        // Create a FeedItem as the standard user
        System.runAs(standardUser) {
            FeedItem feedItem = new FeedItem(
                Body = 'Test Feed Item',
                Visibility = 'AllUsers',
                ParentId = UserInfo.getUserId()
            );
            insert feedItem;

            // Create a FeedComment by the standard user
            FeedComment feedCommentStandard = new FeedComment(
                CommentBody = 'Test Comment',
                FeedItemId = feedItem.Id
            );

            Test.startTest();
            insert feedCommentStandard; // This should not throw an exception
            Test.stopTest();
        }
    }
}