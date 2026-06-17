/**
 * @description Regression net for bidirectional blocking across FIMBY's read surfaces.
 *
 * HONEST FRAMING (this is NOT a static guarantee):
 *   Apex cannot statically assert "every read surface routes content through the block
 *   filter." A brand-new surface added later can silently skip blocking and this test will
 *   not know to assert it. This class is therefore a regression net + a review forcing-
 *   function: it pins the surfaces we know about today so a future change that re-opens a
 *   blocked author on one of them fails here, and it documents the single shared gate every
 *   surface funnels through (FimbyBlockingHelper.getBidirectionalBlocks) so reviewers know
 *   where to wire any new surface.
 *
 *   Known content read surfaces and how they are covered here:
 *     - Digest email (FimbyDigestEmailBuilder)        -> exercised end-to-end (builder overload)
 *     - Profile activity (FimbyProfileActivityController) -> exercised end-to-end (runAs viewer)
 *     - Home feed (FimbyHomeController)                -> feed-author predicate exercised directly
 *     - Search (FimbySearchController)                 -> shared gate (SOSL not testable w/o fixed results)
 *     - Communication / Conversation thread lists      -> shared gate
 *     - Story comments (FimbyStoryCommentController)    -> shared gate
 *     - Skills (FimbySkillsController)                  -> shared gate
 *   The shared-gate assertion verifies getBidirectionalBlocks resolves the block from BOTH
 *   directions, which is the exact call each of those surfaces makes before filtering.
 */
@IsTest
private class FimbyBlockingCoverageTest {

    private static final String STORY_NAME = 'Coverage Author Story';
    private static final String ASK_NAME = 'Coverage Author Ask';
    private static final String LIBRARY_NAME = 'Coverage Author Library';

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);

        Contact viewer = new Contact(
            FirstName = 'Cov', LastName = 'Viewer',
            AccountId = nh.Id, Email = 'cov.viewer@fimby.test.com'
        );
        Contact author = new Contact(
            FirstName = 'Cov', LastName = 'Author',
            AccountId = nh.Id, Email = 'cov.author@fimby.test.com'
        );
        insert new List<Contact>{ viewer, author };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            FimbyTestDataFactory.createCommunityUser(viewer.Id, 'Customer Community User - Mobile App', true);
        }

        Id needRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        insert new Story__c(
            Name = STORY_NAME, Message__c = 'Blocked author shared life content.',
            Type__c = 'Thank You', Neighbourhood__c = nh.Id, Posted_By__c = author.Id
        );
        insert new Needs_Offers__c(
            Name = ASK_NAME, Details__c = 'Blocked author ask content.',
            Type__c = 'Goods - Unperishable', Status__c = 'Posted',
            Neighbourhood__c = nh.Id, Contact__c = author.Id, Posted_By__c = author.Id,
            RecordTypeId = needRt, Posted_Date__c = Datetime.now(),
            End_Date__c = Date.today().addDays(7)
        );
        insert new Library_Item__c(
            Name = LIBRARY_NAME, Description__c = 'Blocked author library content.',
            Category__c = 'Tools', Status__c = 'Available',
            Neighbourhood__c = nh.Id, Owner_Contact__c = author.Id
        );

        // One row encodes a bidirectional block: viewer hides author AND author hides viewer.
        insert new Blocked_Contact__c(Blocker__c = viewer.Id, Blocked__c = author.Id);
    }

    private static Contact viewerContact() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Viewer' LIMIT 1];
    }

    private static Contact authorContact() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Author' LIMIT 1];
    }

    private static User viewerUser() {
        List<User> users = [
            SELECT Id, ContactId FROM User
            WHERE ContactId = :viewerContact().Id AND IsActive = true
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community user for the viewer contact.');
        return users[0];
    }

    @IsTest
    static void sharedGate_resolvesBlockFromBothDirections() {
        Id viewerId = viewerContact().Id;
        Id authorId = authorContact().Id;

        Test.startTest();
        Set<Id> viewerBlocks = FimbyBlockingHelper.getBidirectionalBlocks(viewerId);
        Set<Id> authorBlocks = FimbyBlockingHelper.getBidirectionalBlocks(authorId);
        Test.stopTest();

        System.assert(viewerBlocks.contains(authorId),
            'The viewer (blocker) must hide the author. Every read surface funnels through this gate.');
        System.assert(authorBlocks.contains(viewerId),
            'Symmetry: the author (blocked) must also hide the viewer.');
    }

    @IsTest
    static void digest_excludesBlockedAuthorCards() {
        Account nh = [SELECT Id, Name FROM Account WHERE Id = :authorContact().AccountId LIMIT 1];
        Id authorId = authorContact().Id;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult unfiltered =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly', Date.today().addDays(-7), Date.today()
            );
        FimbyDigestEmailBuilder.DigestResult filtered =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly', Date.today().addDays(-7), Date.today(),
                new Set<Id>{ authorId }
            );
        Test.stopTest();

        System.assert(unfiltered.html.contains(STORY_NAME),
            'Sanity: the author content is present without a block.');
        System.assert(!filtered.html.contains(STORY_NAME),
            'Digest must hide the blocked author\'s story.');
        System.assert(!filtered.html.contains(ASK_NAME),
            'Digest must hide the blocked author\'s ask.');
        System.assert(!filtered.html.contains(LIBRARY_NAME),
            'Digest must hide the blocked author\'s library item.');
    }

    @IsTest
    static void profileActivity_hidesBlockedAuthorEndToEnd() {
        Id authorId = authorContact().Id;
        User viewer = viewerUser();

        Test.startTest();
        System.runAs(viewer) {
            FimbyProfileActivityController.ProfileActivityResult result =
                FimbyProfileActivityController.getProfileActivity(authorId, 0, 50);
            System.assertEquals(0, result.totalCount,
                'A blocked author\'s profile activity must be empty for the viewer.');
        }
        Test.stopTest();
    }

    @IsTest
    static void feedAuthorPredicates_flagBlockedAuthor() {
        Story__c story = [
            SELECT Id, Name, Message__c, Type__c, CreatedDate, Posted_By__c, Contact__c,
                   Comment_Count__c, Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c,
                   Posted_By__r.Display_Avatar_URL__c,
                   Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c,
                   Image_URL__c, Image_Ratio__c
            FROM Story__c WHERE Name = :STORY_NAME LIMIT 1
        ];
        FimbyFeedItem item = new FimbyFeedItem(story);
        Set<Id> blocked = new Set<Id>{ authorContact().Id };

        Test.startTest();
        // Home and ProfileActivity now share this per-item predicate via FimbyBlockingHelper
        // before rendering a card.
        System.assert(
            FimbyBlockingHelper.isBlockedFeedAuthor(item, blocked),
            'Feed surfaces must flag a card whose author is blocked.'
        );
        System.assert(
            !FimbyBlockingHelper.isBlockedFeedAuthor(item, new Set<Id>()),
            'No block set means the card is shown.'
        );
        Test.stopTest();
    }
}
