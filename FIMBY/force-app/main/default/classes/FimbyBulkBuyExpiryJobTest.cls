@isTest
private class FimbyBulkBuyExpiryJobTest {

    private static final String RESERVER_EMAIL = 'expiryreserver@fimby.test.com';
    private static final String SECOND_RESERVER_EMAIL = 'expiryreserver2@fimby.test.com';

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        insert new List<Contact>{
            new Contact(FirstName = 'Rosa', LastName = 'Reserver', Email = RESERVER_EMAIL, AccountId = neighbourhood.Id),
            new Contact(FirstName = 'Marcus', LastName = 'Reserver', Email = SECOND_RESERVER_EMAIL, AccountId = neighbourhood.Id)
        };
    }

    private static Contact getOrganiser() {
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
    }

    private static Contact getReserver(String email) {
        return [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
    }

    private static Needs_Offers__c buildPost(Contact organiser, Datetime expiry, String rule) {
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get(FimbyConstants.RT_BULK_BUY).getRecordTypeId();
        return new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Costco olive oil',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Status__c = FimbyConstants.NEEDS_OFFERS_AVAILABLE,
            Posted_By__c = organiser.Id,
            Contact__c = organiser.Id,
            Neighbourhood__c = organiser.AccountId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Allocation_Unit_Label__c = 'bottles',
            Availability_Rule__c = rule,
            Expiry_DateTime__c = expiry,
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
    }

    private static Needs_Offers__c insertPost(Contact organiser, Datetime expiry) {
        Needs_Offers__c post = buildPost(organiser, expiry, 'Expires_At_Date');
        insert post;
        return post;
    }

    private static Conversation__c attachGroupChat(Needs_Offers__c post) {
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Bulk buy chat',
            Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active'
        );
        insert conv;
        update new Needs_Offers__c(Id = post.Id, Group_Conversation__c = conv.Id);
        return conv;
    }

    private static Response__c addResponse(Id postId, Id contactId, Decimal amount, String status) {
        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = postId,
            Contact__c = contactId,
            Amount_Requested__c = amount,
            Status__c = 'New'
        );
        insert resp;
        if (status != 'New') {
            resp.Status__c = status;
            update resp;
        }
        return resp;
    }

    @isTest
    static void reservedBuyClosesWindowAndNotifiesOnlyOrganiser() {
        Contact organiser = getOrganiser();
        Contact rosa = getReserver(RESERVER_EMAIL);
        Contact marcus = getReserver(SECOND_RESERVER_EMAIL);
        Needs_Offers__c post = insertPost(organiser, System.now().addHours(-1));
        Conversation__c conv = attachGroupChat(post);
        addResponse(post.Id, rosa.Id, 2, FimbyConstants.RESPONSE_RESERVED);
        addResponse(post.Id, marcus.Id, 3, FimbyConstants.RESPONSE_RESERVED);
        delete [SELECT Id FROM Notification__c];
        Integer messagesBefore = [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conv.Id];

        Test.startTest();
        new FimbyBulkBuyExpiryJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [
            SELECT Status__c, Closed_By__c, Reservations_Closed_Date__c, Display_Status__c
            FROM Needs_Offers__c WHERE Id = :post.Id
        ];
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_AVAILABLE, updated.Status__c, 'Buy with reservations stays Available');
        System.assertEquals(null, updated.Closed_By__c, 'Closing the window is not a lifecycle close');
        System.assertNotEquals(null, updated.Reservations_Closed_Date__c, 'Closure timestamp is stamped');
        System.assertEquals('Reservations Closed', updated.Display_Status__c, 'Display status reflects the closed window');

        List<Notification__c> notifs = [
            SELECT Contact__c, Type__c, Title__c, Body__c, Action_URL__c, Actor_Name__c, Actor_Contact__c
            FROM Notification__c
        ];
        System.assertEquals(1, notifs.size(), 'Exactly one notification: the organiser');
        Notification__c notif = notifs[0];
        System.assertEquals(organiser.Id, notif.Contact__c, 'Organiser is the sole recipient');
        System.assertEquals(FimbyConstants.NOTIF_BULK_BUY_STATUS, notif.Type__c, 'Bulk Buy status type');
        System.assertEquals('Reservations closed', notif.Title__c, 'Title copy');
        System.assertEquals(
            '5 shares are reserved by 2 neighbours. Buy when ready, then notify everyone for pickup, or cancel.',
            notif.Body__c, 'Body copy');
        System.assertEquals(FimbySettings.getUrl('Asks_Offers', String.valueOf(post.Id)), notif.Action_URL__c, 'Deep link to the post');
        System.assertEquals('FIMBY', notif.Actor_Name__c, 'System actor');
        System.assertEquals(null, notif.Actor_Contact__c, 'No actor Contact');

        Conversation__c chat = [SELECT Locked__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(false, chat.Locked__c, 'Chat stays open while reservations exist');
        System.assertEquals(messagesBefore, [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conv.Id],
            'No system message is posted to reservers');
    }

    @isTest
    static void singleReservationUsesSingularCopy() {
        Contact organiser = getOrganiser();
        Needs_Offers__c post = insertPost(organiser, System.now().addHours(-1));
        addResponse(post.Id, getReserver(RESERVER_EMAIL).Id, 1, FimbyConstants.RESPONSE_RESERVED);
        delete [SELECT Id FROM Notification__c];

        Test.startTest();
        FimbyBulkBuyExpiryJob.run();
        Test.stopTest();

        Notification__c notif = [SELECT Body__c FROM Notification__c LIMIT 1];
        System.assertEquals(
            '1 share is reserved by 1 neighbour. Buy when ready, then notify everyone for pickup, or cancel.',
            notif.Body__c, 'Singular copy');
    }

    @isTest
    static void emptyBuyExpiresQuietlyAndLocksLeftoverChat() {
        Contact organiser = getOrganiser();
        Needs_Offers__c post = insertPost(organiser, System.now().addHours(-1));
        Conversation__c conv = attachGroupChat(post);
        delete [SELECT Id FROM Notification__c];
        Integer messagesBefore = [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conv.Id];

        Test.startTest();
        new FimbyBulkBuyExpiryJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [
            SELECT Status__c, Closed_By__c, Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id
        ];
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_EXPIRED, updated.Status__c, 'Empty buy expires');
        System.assertEquals(FimbyConstants.CLOSED_BY_AUTO, updated.Closed_By__c, 'Closed by the job');
        System.assertEquals(null, updated.Reservations_Closed_Date__c, 'No closure stamp on an expired buy');
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c], 'Nobody is notified');
        System.assertEquals(true, [SELECT Locked__c FROM Conversation__c WHERE Id = :conv.Id].Locked__c,
            'Leftover chat is locked');
        System.assertEquals(messagesBefore, [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conv.Id],
            'No system message is posted');
    }

    @isTest
    static void nonReservedResponsesDoNotKeepTheBuyOpen() {
        Contact organiser = getOrganiser();
        Needs_Offers__c post = insertPost(organiser, System.now().addHours(-1));
        addResponse(post.Id, getReserver(RESERVER_EMAIL).Id, 2, 'New');
        addResponse(post.Id, getReserver(SECOND_RESERVER_EMAIL).Id, 2, FimbyConstants.RESPONSE_CANCELLED);
        delete [SELECT Id FROM Notification__c];

        Test.startTest();
        FimbyBulkBuyExpiryJob.run();
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c, Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_EXPIRED, updated.Status__c,
            'Only Reserved responses count as active reservations');
        System.assertEquals(null, updated.Reservations_Closed_Date__c, 'No closure stamp');
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c], 'Nobody is notified');
    }

    @isTest
    static void secondRunIsIdempotent() {
        Contact organiser = getOrganiser();
        Needs_Offers__c post = insertPost(organiser, System.now().addHours(-1));
        addResponse(post.Id, getReserver(RESERVER_EMAIL).Id, 2, FimbyConstants.RESPONSE_RESERVED);
        delete [SELECT Id FROM Notification__c];

        FimbyBulkBuyExpiryJob.run();
        Datetime firstStamp = [SELECT Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id].Reservations_Closed_Date__c;

        Test.startTest();
        FimbyBulkBuyExpiryJob.run();
        Test.stopTest();

        System.assertEquals(firstStamp,
            [SELECT Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id].Reservations_Closed_Date__c,
            'Closure timestamp is not overwritten');
        System.assertEquals(1, [SELECT COUNT() FROM Notification__c], 'Organiser is notified once');
    }

    @isTest
    static void futureAndUndatedBuysAreUntouched() {
        Contact organiser = getOrganiser();
        Needs_Offers__c future = insertPost(organiser, System.now().addDays(3));
        Needs_Offers__c undated = buildPost(organiser, null, 'Open_Until_Full_Or_Closed');
        insert undated;
        Needs_Offers__c cancelled = buildPost(organiser, System.now().addHours(-1), 'Expires_At_Date');
        cancelled.Status__c = FimbyConstants.NEEDS_OFFERS_CANCELLED;
        insert cancelled;

        Test.startTest();
        FimbyBulkBuyExpiryJob.run();
        Test.stopTest();

        Map<Id, Needs_Offers__c> rows = new Map<Id, Needs_Offers__c>([
            SELECT Status__c, Reservations_Closed_Date__c FROM Needs_Offers__c
            WHERE Id IN :new List<Id>{ future.Id, undated.Id, cancelled.Id }
        ]);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_AVAILABLE, rows.get(future.Id).Status__c, 'Future buy stays open');
        System.assertEquals(null, rows.get(future.Id).Reservations_Closed_Date__c, 'Future buy not stamped');
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_AVAILABLE, rows.get(undated.Id).Status__c, 'Undated buy stays open');
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_CANCELLED, rows.get(cancelled.Id).Status__c, 'Terminal buy untouched');
        System.assertEquals(null, rows.get(cancelled.Id).Reservations_Closed_Date__c, 'Terminal buy not stamped');
    }

    @isTest
    static void bulkRunHandlesMixedBranches() {
        Contact organiser = getOrganiser();
        Contact rosa = getReserver(RESERVER_EMAIL);
        List<Needs_Offers__c> posts = new List<Needs_Offers__c>();
        for (Integer i = 0; i < 6; i++) {
            posts.add(buildPost(organiser, System.now().addHours(-1 - i), 'Expires_At_Date'));
        }
        insert posts;
        List<Response__c> reservations = new List<Response__c>();
        for (Integer i = 0; i < 3; i++) {
            reservations.add(new Response__c(
                Need_Offer_Responded_To__c = posts[i].Id, Contact__c = rosa.Id,
                Amount_Requested__c = 1, Status__c = 'New'
            ));
        }
        insert reservations;
        for (Response__c r : reservations) {
            r.Status__c = FimbyConstants.RESPONSE_RESERVED;
        }
        update reservations;
        delete [SELECT Id FROM Notification__c];

        Test.startTest();
        FimbyBulkBuyExpiryJob.run();
        Test.stopTest();

        Integer closed = 0;
        Integer expired = 0;
        for (Needs_Offers__c p : [SELECT Status__c, Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id IN :posts]) {
            if (p.Reservations_Closed_Date__c != null && p.Status__c == FimbyConstants.NEEDS_OFFERS_AVAILABLE) {
                closed++;
            } else if (p.Status__c == FimbyConstants.NEEDS_OFFERS_EXPIRED) {
                expired++;
            }
        }
        System.assertEquals(3, closed, 'Reserved buys close their window');
        System.assertEquals(3, expired, 'Empty buys expire');
        System.assertEquals(3, [SELECT COUNT() FROM Notification__c WHERE Contact__c = :organiser.Id],
            'One organiser notice per closed buy');
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Contact__c = :rosa.Id],
            'Reservers are never notified');
    }
}
