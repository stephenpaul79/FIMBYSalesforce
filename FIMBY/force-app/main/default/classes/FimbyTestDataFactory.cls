@isTest
public class FimbyTestDataFactory {

    // Static counter to ensure unique values across test methods
    private static Integer counter = 1;

    /**
     * @description Creates test Account records representing neighbourhoods
     * @param count Number of accounts to create
     * @param doInsert Whether to insert the records
     * @return List<Account> List of created Account records
     */
    public static List<Account> createNeighbourhoods(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();

        // Get the Boundary Account record type ID
        Id boundaryRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Boundary Account').getRecordTypeId();

        for (Integer i = 0; i < count; i++) {
            Account acc = new Account(
                Name = 'Test Neighbourhood ' + (counter + i),
                Type = 'Neighbourhood',
                RecordTypeId = boundaryRecordTypeId
            );
            accounts.add(acc);
        }

        if (doInsert) {
            insert accounts;
        }

        counter += count;
        return accounts;
    }

    /**
     * @description Creates a single test neighbourhood
     * @param doInsert Whether to insert the record
     * @return Account The created Account record
     */
    public static Account createNeighbourhood(Boolean doInsert) {
        return createNeighbourhoods(1, doInsert)[0];
    }

    /**
     * @description Creates test Contact records linked to neighbourhoods
     * @param neighbourhoodId The Account Id to link contacts to
     * @param count Number of contacts to create
     * @param doInsert Whether to insert the records
     * @return List<Contact> List of created Contact records
     */
    public static List<Contact> createNeighbourhoodContacts(Id neighbourhoodId, Integer count, Boolean doInsert) {
        List<Contact> contacts = new List<Contact>();

        for (Integer i = 0; i < count; i++) {
            Contact con = new Contact(
                FirstName = 'Test' + (counter + i),
                LastName = 'Resident' + (counter + i),
                Email = 'testuser' + (counter + i) + '@fimby.test.com',
                AccountId = neighbourhoodId,
                Image_URL__c = 'https://example.com/avatar' + (counter + i) + '.jpg'
            );
            contacts.add(con);
        }

        if (doInsert) {
            insert contacts;
        }

        counter += count;
        return contacts;
    }

    /**
     * @description Creates a single test contact
     * @param neighbourhoodId The Account Id to link contact to
     * @param doInsert Whether to insert the record
     * @return Contact The created Contact record
     */
    public static Contact createNeighbourhoodContact(Id neighbourhoodId, Boolean doInsert) {
        return createNeighbourhoodContacts(neighbourhoodId, 1, doInsert)[0];
    }

    /**
     * @description Creates test Community User records linked to contacts
     * @param contactId The Contact Id to link user to
     * @param profileName The profile to assign (defaults to 'Customer Community User')
     * @param doInsert Whether to insert the record
     * @return User The created User record
     */
    public static User createCommunityUser(Id contactId, String profileName, Boolean doInsert) {
        if (String.isBlank(profileName)) {
            profileName = 'Customer Community User - Mobile App';
        }

        String uniqueUserName = 'fimbyuser' + DateTime.now().getTime() + Math.round(Math.random() * 10000) + '@testorg.com';
        String uniqueAlias = 'fu' + Math.round(Math.random() * 100000);
        if (uniqueAlias.length() > 8) {
            uniqueAlias = uniqueAlias.substring(0, 8);
        }

        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];

        User u = new User(
            Alias = uniqueAlias,
            Email = 'fimbyuser' + counter + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Test',
            LastName = 'FimbyUser' + counter,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = uniqueUserName,
            ContactId = contactId,
            IsActive = true
        );

        if (doInsert) {
            insert u;
        }

        counter++;
        return u;
    }

    /**
     * @description Creates test Story__c records
     * @param neighbourhoodId The neighbourhood Account Id
     * @param postedByContactId The contact who posted the story
     * @param count Number of stories to create
     * @param doInsert Whether to insert the records
     * @return List<Story__c> List of created Story records
     */
    public static List<Story__c> createStories(Id neighbourhoodId, Id postedByContactId, Integer count, Boolean doInsert) {
        List<Story__c> stories = new List<Story__c>();

        List<String> storyTypes = new List<String>{'Thank You', 'God Story', 'Prayer', 'Bio', 'Lament'};

        for (Integer i = 0; i < count; i++) {
            Story__c story = new Story__c(
                Name = 'Test Story ' + (counter + i),
                Message__c = 'This is a test story message for story number ' + (counter + i) + '. It contains some sample content for testing purposes.',
                Type__c = storyTypes[Math.mod(i, storyTypes.size())],
                Neighbourhood__c = neighbourhoodId,
                Posted_By__c = postedByContactId,
                Image_URL__c = 'https://example.com/story' + (counter + i) + '.jpg'
                // Portal_Image__c is a formula field - automatically calculated
            );
            stories.add(story);
        }

        if (doInsert) {
            insert stories;
        }

        counter += count;
        return stories;
    }

    /**
     * @description Creates test Needs_Offers__c records (Ask & Offer items)
     * @param neighbourhoodId The neighbourhood Account Id
     * @param postedByContactId The contact who posted the item
     * @param count Number of items to create
     * @param doInsert Whether to insert the records
     * @return List<Needs_Offers__c> List of created ask & offer items
     */
    public static List<Needs_Offers__c> createAskOfferItems(Id neighbourhoodId, Id postedByContactId, Integer count, Boolean doInsert) {
        List<Needs_Offers__c> items = new List<Needs_Offers__c>();

        List<String> categories = new List<String>{'Tools', 'Household Items', 'Gardening', 'Electronics', 'Books'};
        List<String> types = new List<String>{'Goods - Unperishable', 'Goods - Perishable', 'Services - Free', 'Services - Paid', 'Event'};

        for (Integer i = 0; i < count; i++) {
            Needs_Offers__c item = new Needs_Offers__c(
                Name = 'Test Marketplace Item ' + (counter + i),
                Details__c = 'This is a test marketplace item description for item number ' + (counter + i) + '.',
                Type__c = types[Math.mod(i, types.size())],
                Category__c = categories[Math.mod(i, categories.size())],
                Status__c = 'Posted',
                Neighbourhood__c = neighbourhoodId,
                Posted_By__c = postedByContactId,
                Contact__c = postedByContactId // Required by validation rule: either Contact__c OR Organization__c must be populated
                // Portal_Image__c is a formula field - automatically calculated from Image_1_URL__c
            );
            items.add(item);
        }

        if (doInsert) {
            insert items;
        }

        counter += count;
        return items;
    }

    /**
     * @description Creates Needs_Offers__c with explicit record type
     * @param neighbourhoodId The neighbourhood Account Id
     * @param contactId The contact who posted
     * @param recordTypeDeveloperName 'Need', 'Offer', or 'Bulk_Buy'
     * @param count Number of items to create
     * @param doInsert Whether to insert the records
     * @return List<Needs_Offers__c>
     */
    public static List<Needs_Offers__c> createNeedsOffers(
        Id neighbourhoodId, Id contactId, String recordTypeDeveloperName,
        Integer count, Boolean doInsert
    ) {
        Id rtId = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName()
            .get(recordTypeDeveloperName).getRecordTypeId();

        List<Needs_Offers__c> items = new List<Needs_Offers__c>();
        for (Integer i = 0; i < count; i++) {
            items.add(new Needs_Offers__c(
                Name = 'Test ' + recordTypeDeveloperName + ' ' + (counter + i),
                Details__c = 'Test details for ' + recordTypeDeveloperName + ' item ' + (counter + i) + '.',
                Type__c = 'Goods - Unperishable',
                Status__c = 'Posted',
                Neighbourhood__c = neighbourhoodId,
                Contact__c = contactId,
                Posted_By__c = contactId,
                RecordTypeId = rtId
            ));
        }
        if (doInsert) { insert items; }
        counter += count;
        return items;
    }

    /**
     * @description Creates test Notification__c records for a contact
     * @param contactId The contact to notify
     * @param notifType Notification type
     * @param emailStatus Email_Status__c value (null, 'Pending', etc.)
     * @param count Number to create
     * @param doInsert Whether to insert
     * @return List<Notification__c>
     */
    public static List<Notification__c> createNotifications(
        Id contactId, String notifType, String emailStatus,
        Integer count, Boolean doInsert
    ) {
        List<Notification__c> notifs = new List<Notification__c>();
        for (Integer i = 0; i < count; i++) {
            notifs.add(new Notification__c(
                Contact__c = contactId,
                Title__c = 'Test ' + notifType + ' ' + (counter + i),
                Body__c = 'Test body for notification ' + (counter + i),
                Type__c = notifType,
                Email_Status__c = emailStatus
            ));
        }
        if (doInsert) { insert notifs; }
        counter += count;
        return notifs;
    }

    /**
     * @description Creates test Library_Item__c records
     * @param neighbourhoodId The neighbourhood Account Id
     * @param ownerContactId The contact who owns the library item
     * @param count Number of items to create
     * @param doInsert Whether to insert the records
     * @return List<Library_Item__c> List of created library items
     */
    public static List<Library_Item__c> createLibraryItems(Id neighbourhoodId, Id ownerContactId, Integer count, Boolean doInsert) {
        List<Library_Item__c> items = new List<Library_Item__c>();

        List<String> categories = new List<String>{'Books', 'Tools', 'Games & Toys', 'Electronics', 'Sports Equipment'};

        for (Integer i = 0; i < count; i++) {
            Library_Item__c item = new Library_Item__c(
                Name = 'Test Library Item ' + (counter + i),
                Description__c = 'This is a test library item description for item number ' + (counter + i) + '.',
                Category__c = categories[Math.mod(i, categories.size())],
                Status__c = 'Available',
                Neighbourhood__c = neighbourhoodId,
                Owner_Contact__c = ownerContactId,
                Image_URL__c = 'https://example.com/library' + (counter + i) + '.jpg'
                // Portal_Image__c is a formula field - automatically calculated from Image_URL__c
            );
            items.add(item);
        }

        if (doInsert) {
            insert items;
        }

        counter += count;
        return items;
    }

    /**
     * @description Creates a complete test setup with neighbourhood, contact, user, and sample data
     * This is a convenience method for setting up a full test scenario
     * @return FimbyTestDataSetup A wrapper containing all created test data
     */
    public static FimbyTestDataSetup createCompleteTestSetup() {
        FimbyTestDataSetup setup = new FimbyTestDataSetup();

        // Create neighbourhood
        setup.neighbourhood = createNeighbourhood(true);

        // Create contact
        setup.contact = createNeighbourhoodContact(setup.neighbourhood.Id, true);

        // Create community user
        setup.communityUser = createCommunityUser(setup.contact.Id, 'Customer Community User', true);

        // Create sample data
        setup.stories = createStories(setup.neighbourhood.Id, setup.contact.Id, 3, true);
        setup.askOfferItems = createAskOfferItems(setup.neighbourhood.Id, setup.contact.Id, 3, true);
        setup.libraryItems = createLibraryItems(setup.neighbourhood.Id, setup.contact.Id, 3, true);

        return setup;
    }

    /**
     * @description Wrapper class to hold a complete test data setup
     */
    public class FimbyTestDataSetup {
        public Account neighbourhood;
        public Contact contact;
        public User communityUser;
        public List<Story__c> stories;
        public List<Needs_Offers__c> askOfferItems;
        public List<Library_Item__c> libraryItems;
    }
}