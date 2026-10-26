// QA seed for the mobile header consolidation runbook (Testhood only, insert-only, no cleanup).
// Run: sf apex run --file scripts/apex/qa-seed-mobile-header.apex
String tag = '[QA seed 2026-10-26 mobile header]';

Map<String, Id> contactByLogin = new Map<String, Id>();
for (User u : [
    SELECT Username, ContactId FROM User
    WHERE Username IN ('sarah@fimby.com', 'marcus@fimby.com', 'amir@fimby.com') AND IsActive = true
]) {
    contactByLogin.put(u.Username, u.ContactId);
}
Id sarahId = contactByLogin.get('sarah@fimby.com');
Id marcusId = contactByLogin.get('marcus@fimby.com');
Id amirId = contactByLogin.get('amir@fimby.com');
if (sarahId == null || marcusId == null || amirId == null) {
    throw new IllegalArgumentException('Missing persona Contact(s): ' + contactByLogin);
}

Contact sarah = [SELECT AccountId, Account.Name FROM Contact WHERE Id = :sarahId];
if (sarah.Account.Name != 'Testhood') {
    throw new IllegalArgumentException('Sarah is not in Testhood: ' + sarah.Account.Name);
}
Id testhoodId = sarah.AccountId;

Map<String, Schema.RecordTypeInfo> postTypes = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName();
Id needRt = postTypes.get('Need').getRecordTypeId();
Id offerRt = postTypes.get('Offer').getRecordTypeId();
Id bulkRt = postTypes.get('Bulk_Buy').getRecordTypeId();

String longPostTitle = 'Looking for someone to help move a very heavy oak bookshelf up two flights QA';
String longItemName = 'Extra-long extension ladder with stabiliser arms and a padded tool tray QA';

List<String> archivedStatuses = new List<String>{ 'Completed (Offer Accepted / Need Met)', 'Cancelled', 'Expired' };
List<Needs_Offers__c> posts = new List<Needs_Offers__c>();
Datetime now = Datetime.now();

// 25 archived posts, newer than the active ones below so they would have crowded out My Posts before the fix
for (Integer i = 0; i < 25; i++) {
    Integer kind = Math.mod(i, 4);
    Needs_Offers__c p = new Needs_Offers__c(
        Name = (i < 2) ? longPostTitle + ' ' + i : 'QA archived post ' + (i + 1),
        Details__c = tag,
        Status__c = archivedStatuses[Math.mod(i, 3)],
        Category__c = (kind == 3) ? null : 'Tools',
        Neighbourhood__c = testhoodId,
        Contact__c = sarahId,
        Posted_By__c = sarahId,
        Giver_Recipient_Type__c = 'Self',
        Posted_Date__c = now.addHours(-(i + 1))
    );
    if (kind == 0) {
        p.RecordTypeId = needRt;
        p.Type__c = 'Goods - Unperishable';
    } else if (kind == 1) {
        p.RecordTypeId = offerRt;
        p.Type__c = 'Services - Free';
    } else if (kind == 2) {
        p.RecordTypeId = offerRt;
        p.Type__c = 'Event';
        p.Event_Type__c = 'Gathering';
    } else {
        p.RecordTypeId = bulkRt;
        p.Full_Details__c = tag;
        p.Total_Quantity__c = 10;
        p.Allocation_Unit_Label__c = 'shares';
        p.Availability_Rule__c = 'Open_Until_Full_Or_Closed';
        p.Auto_Accept_Responses__c = true;
        p.Auto_Lock_Days__c = '7';
    }
    posts.add(p);
}

// 5 active posts, older than all 25 archived ones: 2 pickup-ready bulk buys + 3 asks/offers
for (Integer i = 0; i < 2; i++) {
    posts.add(new Needs_Offers__c(
        RecordTypeId = bulkRt,
        Name = 'QA pickup-ready bulk buy ' + (i + 1),
        Details__c = tag,
        Full_Details__c = tag,
        Status__c = 'Pickup_Ready',
        Neighbourhood__c = testhoodId,
        Contact__c = sarahId,
        Posted_By__c = sarahId,
        Giver_Recipient_Type__c = 'Self',
        Total_Quantity__c = 10,
        Allocation_Unit_Label__c = 'shares',
        Availability_Rule__c = 'Open_Until_Full_Or_Closed',
        Auto_Accept_Responses__c = true,
        Auto_Lock_Days__c = '7',
        Posted_Date__c = now.addDays(-3).addHours(-i)
    ));
}
List<String> activeStatuses = new List<String>{ 'Posted', 'Reply Received', 'Posted' };
for (Integer i = 0; i < 3; i++) {
    posts.add(new Needs_Offers__c(
        RecordTypeId = (i == 1) ? offerRt : needRt,
        Type__c = 'Goods - Unperishable',
        Name = 'QA active post ' + (i + 1),
        Details__c = tag,
        Status__c = activeStatuses[i],
        Category__c = 'Tools',
        Neighbourhood__c = testhoodId,
        Contact__c = sarahId,
        Posted_By__c = sarahId,
        Giver_Recipient_Type__c = 'Self',
        Posted_Date__c = now.addDays(-4).addHours(-i)
    ));
}
insert posts;

// 30 stories (archive = everything beyond the newest 10)
List<String> storyTypes = new List<String>{ 'Thank You', 'God Story', 'Prayer', 'Bio', 'Lament', 'Neighbourhood Moment' };
List<Story__c> stories = new List<Story__c>();
for (Integer i = 0; i < 30; i++) {
    stories.add(new Story__c(
        Name = 'QA story ' + (i + 1),
        Message__c = tag,
        Type__c = storyTypes[Math.mod(i, storyTypes.size())],
        Neighbourhood__c = testhoodId,
        Posted_By__c = sarahId,
        Contact__c = sarahId,
        Share_with_Neighbours__c = false
    ));
}
insert stories;

// Library: 25 Unavailable items for Sarah's archive, 1 Currently Lent Out (no Loaned_Item__c),
// and 6 Available items owned by Marcus/Amir that also anchor Sarah's borrow history
List<String> categories = new List<String>{ 'Tools', 'Books', 'Gardening', 'Kitchen Supplies', 'Camping Gear', 'Bikes' };
List<Library_Item__c> items = new List<Library_Item__c>();
for (Integer i = 0; i < 25; i++) {
    items.add(new Library_Item__c(
        Name = (i < 2) ? longItemName + ' ' + i : 'QA archived item ' + (i + 1),
        Description__c = tag,
        Category__c = categories[Math.mod(i, categories.size())],
        Status__c = 'Unavailable',
        Neighbourhood__c = testhoodId,
        Owner_Contact__c = sarahId,
        Listed_By__c = sarahId
    ));
}
items.add(new Library_Item__c(
    Name = 'QA lent-out wheelbarrow',
    Description__c = tag,
    Category__c = 'Gardening',
    Status__c = 'Currently Lent Out',
    Neighbourhood__c = testhoodId,
    Owner_Contact__c = sarahId,
    Listed_By__c = sarahId
));
List<Library_Item__c> lenderItems = new List<Library_Item__c>();
for (Integer i = 0; i < 6; i++) {
    Id owner = Math.mod(i, 2) == 0 ? marcusId : amirId;
    lenderItems.add(new Library_Item__c(
        Name = (i == 0) ? longItemName + ' lend' : 'QA neighbour item ' + (i + 1),
        Description__c = tag,
        Category__c = categories[i],
        Status__c = 'Available',
        Neighbourhood__c = testhoodId,
        Owner_Contact__c = owner,
        Listed_By__c = owner
    ));
}
items.addAll(lenderItems);
insert items;

// 25 past borrows by Sarah from Marcus/Amir
List<Lending_History__c> history = new List<Lending_History__c>();
for (Integer i = 0; i < 25; i++) {
    Library_Item__c item = lenderItems[Math.mod(i, lenderItems.size())];
    history.add(new Lending_History__c(
        Name = 'QA borrow ' + (i + 1),
        Borrowed_By__c = sarahId,
        Lent_By__c = item.Owner_Contact__c,
        Library_Item__c = item.Id,
        Start_Date__c = Date.today().addDays(-(i * 7 + 10)),
        End_Date__c = Date.today().addDays(-(i * 7 + 3))
    ));
}
insert history;

System.debug(LoggingLevel.INFO, 'QA seed done: ' + posts.size() + ' posts, ' + stories.size() + ' stories, '
    + items.size() + ' library items, ' + history.size() + ' lending history rows.');
