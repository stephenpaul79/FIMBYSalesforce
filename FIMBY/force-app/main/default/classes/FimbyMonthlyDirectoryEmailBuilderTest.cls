@IsTest
private class FimbyMonthlyDirectoryEmailBuilderTest {

    private static final Integer BIG_BUDGET = 500000;

    @TestSetup
    static void setup() {
        List<Account> nhs = FimbyTestDataFactory.createNeighbourhoods(2, true);
        Account home = nhs[0];
        Account adjacent = nhs[1];
        home.Name = 'Home NH';
        home.Adjacent_Neighbourhood_Ids__c = String.valueOf(adjacent.Id);
        adjacent.Name = 'Adjacent NH';
        update nhs;

        Contact homeOwner = FimbyTestDataFactory.createNeighbourhoodContact(home.Id, true);
        Contact adjacentOwner = FimbyTestDataFactory.createNeighbourhoodContact(adjacent.Id, true);
        Contact lister = FimbyTestDataFactory.createNeighbourhoodContact(home.Id, true);

        insert new List<Library_Item__c>{
            item('Cordless Drill', 'Tools', 'Available', home.Id, homeOwner.Id, null, 'Neighbourhood'),
            item('Tent', 'Camping Gear', 'Currently Lent Out', home.Id, homeOwner.Id, null, 'Neighbourhood'),
            item('Mystery Box', null, 'Available', home.Id, homeOwner.Id, null, 'Neighbourhood'),
            item('Fish & <Chips> Fryer', 'Kitchen Supplies', 'Available', home.Id, homeOwner.Id, null, 'Neighbourhood'),
            item('Listed Ladder', 'Tools', 'Available', home.Id, homeOwner.Id, lister.Id, 'Neighbourhood'),
            item('Held Item', 'Tools', 'On Hold', home.Id, homeOwner.Id, null, 'Neighbourhood'),
            item('Shared Scope Wheelbarrow', 'Gardening', 'Available', adjacent.Id, adjacentOwner.Id, null, 'Adjacent'),
            item('Private Kayak', 'Sports Equipment', 'Available', adjacent.Id, adjacentOwner.Id, null, 'Neighbourhood')
        };
        Library_Item__c hidden = item('Hidden Item', 'Tools', 'Available', home.Id, homeOwner.Id, null, 'Neighbourhood');
        hidden.Moderation_Status__c = 'Hidden_By_Moderator';
        insert hidden;

        insert new List<Skill_Offer__c>{
            skill('Bike tune-ups', 'Auto & Bike Repair', 'Active', home.Id, homeOwner.Id),
            skill('Paused Skill', 'Tech Help', 'Paused', home.Id, homeOwner.Id)
        };
    }

    private static Library_Item__c item(
        String name, String category, String status, Id nhId, Id ownerId, Id listedById, String scope
    ) {
        return new Library_Item__c(
            Name = name, Category__c = category, Status__c = status,
            Neighbourhood__c = nhId, Owner_Contact__c = ownerId,
            Listed_By__c = listedById != null ? listedById : ownerId,
            Visibility_Scope__c = scope
        );
    }

    private static Skill_Offer__c skill(String name, String category, String status, Id nhId, Id ownerId) {
        return new Skill_Offer__c(
            Name = name, Skill_Category__c = category, Status__c = status,
            Neighbourhood__c = nhId, Owner_Contact__c = ownerId, Listed_By__c = ownerId,
            Moderation_Status__c = 'Visible'
        );
    }

    private static Account home() {
        return [SELECT Id FROM Account WHERE Name = 'Home NH' LIMIT 1];
    }

    private static Contact contactIn(String nhName, Integer idx) {
        return [
            SELECT Id FROM Contact WHERE Account.Name = :nhName ORDER BY CreatedDate ASC, Id ASC
        ][idx];
    }

    @IsTest
    static void render_listsVisibleRowsSortedAndEscaped() {
        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(home().Id);
        FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result =
            FimbyMonthlyDirectoryEmailBuilder.render(directory, null, null, BIG_BUDGET);
        Test.stopTest();

        String html = result.html;
        System.assert(html.contains('Items To Borrow') && html.contains('Skills On Offer'));
        System.assert(html.contains('Cordless Drill'));
        System.assert(html.contains('Tent</a> <span') && html.contains('on loan'),
            'Lent-out items carry the on-loan tag');
        System.assert(html.contains('Shared Scope Wheelbarrow'),
            'Adjacent items scoped Adjacent are visible');
        System.assert(!html.contains('Private Kayak'),
            'Adjacent items scoped Neighbourhood stay hidden without a share');
        System.assert(!html.contains('Held Item'), 'On Hold is out of scope');
        System.assert(!html.contains('Hidden Item'), 'Moderator-hidden items are excluded');
        System.assert(html.contains('Bike tune-ups') && !html.contains('Paused Skill'));
        System.assert(html.contains('Fish &amp; &lt;Chips&gt; Fryer'), 'Names are HTML-escaped');
        System.assert(html.indexOf('Kitchen Supplies') < html.indexOf('>Tools<'),
            'Categories sort alphabetically');
        System.assert(html.indexOf('>Tools<') < html.indexOf('>Other<'),
            'Blank categories render as Other and sort last');
        System.assert(html.indexOf('Cordless Drill') < html.indexOf('Listed Ladder'),
            'Rows sort by name within a category');
        System.assert(html.contains('Browse all Items in the Library'));
        System.assert(html.contains('Browse all Skills in the Library'));
        System.assert(html.contains('/library-list?filter=items'));
        System.assert(html.contains('/library-list?filter=skills'));
        System.assert(html.contains('/library-item/') && html.contains('/skill-offer/'));
        System.assert(html.contains('Add an item') && html.contains('Offer a skill'),
            'Opening invites neighbours to add to the Library');
        System.assert(html.contains('/library-item-post?type=skill'), 'Offer a skill opens the skill composer');
        System.assert(html.contains('Impact_Icons/tools.png'), 'Item categories use the Library tab icon');
        System.assert(html.contains('Impact_Icons/mechanic.png'), 'Skill categories use the skill icon');
        System.assert(html.contains('Impact_Icons/unknown.png'), 'Other falls back to the default icon');
        System.assert(html.indexOf('Add an item') < html.indexOf('Items To Borrow'),
            'The invitation opens the email');
        System.assertEquals(0, result.itemsOmitted);
        System.assertEquals(false, result.droppedInitials);
        System.assertEquals(false, result.isEmpty);
    }

    @IsTest
    static void render_adjacentSharerUnlocksNeighbourhoodScopedItem() {
        Contact adjacentOwner = contactIn('Adjacent NH', 0);

        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(home().Id);
        String html = FimbyMonthlyDirectoryEmailBuilder.render(
            directory, null, new Set<Id>{ adjacentOwner.Id }, BIG_BUDGET
        ).html;
        Test.stopTest();

        System.assert(directory.adjacentOwnerIds().contains(adjacentOwner.Id));
        System.assert(html.contains('Private Kayak'),
            'An adjacent owner who shares with the recipient makes their items visible');
    }

    @IsTest
    static void render_blockedOwnerOrListerHidesRows() {
        Contact homeOwner = contactIn('Home NH', 0);
        Contact lister = contactIn('Home NH', 1);

        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(home().Id);
        String listerBlocked = FimbyMonthlyDirectoryEmailBuilder.render(
            directory, new Set<Id>{ lister.Id }, null, BIG_BUDGET
        ).html;
        String ownerBlocked = FimbyMonthlyDirectoryEmailBuilder.render(
            directory, new Set<Id>{ homeOwner.Id }, null, BIG_BUDGET
        ).html;
        Test.stopTest();

        System.assert(!listerBlocked.contains('Listed Ladder'),
            'A blocked Listed_By hides the row even when the owner is not blocked');
        System.assert(listerBlocked.contains('Cordless Drill'));
        System.assert(!ownerBlocked.contains('Cordless Drill') && !ownerBlocked.contains('Bike tune-ups'),
            'A blocked owner hides their items and skills');
        System.assert(ownerBlocked.contains('No skills listed yet'),
            'An emptied section shows the warm empty line');
    }

    @IsTest
    static void render_tightBudgetDropsInitialsThenTrimsAcrossCategories() {
        Account nh = home();
        Contact homeOwner = contactIn('Home NH', 0);
        List<Library_Item__c> many = new List<Library_Item__c>();
        for (Integer i = 0; i < 60; i++) {
            many.add(item('Bulk Tool ' + String.valueOf(i).leftPad(2, '0'), 'Tools', 'Available',
                nh.Id, homeOwner.Id, null, 'Neighbourhood'));
        }
        insert many;

        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(nh.Id);
        Integer fullBytes = FimbyMonthlyDirectoryEmailBuilder.byteSize(
            FimbyMonthlyDirectoryEmailBuilder.render(directory, null, null, BIG_BUDGET).html
        );
        Integer budget = fullBytes / 2;
        FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result =
            FimbyMonthlyDirectoryEmailBuilder.render(directory, null, null, budget);
        Test.stopTest();

        System.assert(FimbyMonthlyDirectoryEmailBuilder.byteSize(result.html) <= budget,
            'Trimmed body must fit the budget');
        System.assert(result.droppedInitials, 'Initials are dropped before rows');
        System.assert(result.itemsOmitted > 0, 'Rows were trimmed');
        System.assert(result.html.contains('Browse ' + result.itemsOmitted + ' more Items in the Library'),
            'The closing link reports only what was left out');
        System.assert(result.html.contains('Fish &amp;') && result.html.contains('Tent'),
            'Round-robin keeps small categories while the big one is trimmed');
    }

    @IsTest
    static void render_emptyNeighbourhoodShowsWarmLines() {
        Account empty = new Account(Name = 'Empty NH');
        insert empty;

        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(empty.Id);
        FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result =
            FimbyMonthlyDirectoryEmailBuilder.render(directory, null, null, BIG_BUDGET);
        Test.stopTest();

        System.assert(directory.isEmpty());
        System.assertEquals(0, directory.totalCount());
        System.assert(result.isEmpty);
        System.assert(result.html.contains('No items listed yet'));
        System.assert(result.html.contains('No skills listed yet'));
        System.assert(FimbyMonthlyDirectoryEmailBuilder.loadDirectory(null).isEmpty());
    }

    @IsTest
    static void closingLinkText_usesSingularForOne() {
        System.assertEquals('Browse 1 more Item in the Library',
            FimbyMonthlyDirectoryEmailBuilder.closingLinkText('Item', 1));
        System.assertEquals('Browse 12 more Skills in the Library',
            FimbyMonthlyDirectoryEmailBuilder.closingLinkText('Skill', 12));
        System.assertEquals('Browse all Items in the Library',
            FimbyMonthlyDirectoryEmailBuilder.closingLinkText('Item', 0));
    }
}
