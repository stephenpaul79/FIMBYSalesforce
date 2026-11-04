@isTest
public class FimbyBulkBuyControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        Contact testContact = getTestContact();
        List<User> users = [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId = :testContact.Id AND IsActive = true
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
        return users[0];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static Needs_Offers__c createBulkBuyPost(Contact poster, Id neighbourhoodId) {
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Test Bulk Buy',
            Details__c = 'Test details',
            Full_Details__c = 'Full test details',
            Status__c = 'Available',
            Posted_By__c = poster.Id,
            Contact__c = poster.Id,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Owner_Shares__c = 2,
            Per_Response_Limit__c = 5,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;
        return post;
    }

    private static Response__c createReservation(Id postId, Id contactId, Decimal amount) {
        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = postId,
            Contact__c = contactId,
            Amount_Requested__c = amount,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;
        return resp;
    }

    private static Conversation__c createGroupConversation(Needs_Offers__c post) {
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Test Group',
            Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;
        return conv;
    }

    @isTest
    static void testCreateBulkBuyPost_Success() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'title' => 'Fresh Eggs Bulk Buy',
            'description' => 'Buying eggs in bulk from a local farm',
            'totalQuantity' => 20,
            'ownerShares' => 2,
            'unitLabel' => 'dozens',
            'availabilityRule' => 'Open_Until_Full_Or_Closed',
            'totalEstimatedCost' => 100.00,
            'autoLockDays' => '7',
            'perResponseLimit' => 5
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.createBulkBuyPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('recordId'), 'Should return a recordId');
        System.assertNotEquals(null, result.get('postUrl'), 'Should return a postUrl');

        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Contact__c, Posted_By__c, Giver_Recipient_Type__c, Organization__c
                                   FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals(testUser.ContactId, created.Contact__c, 'Contact__c should be the acting-as contact');
        System.assertEquals(testUser.ContactId, created.Posted_By__c, 'Posted_By__c should be the real contact');
        System.assertEquals('Self', created.Giver_Recipient_Type__c, 'Giver_Recipient_Type__c should always be Self');
        System.assertEquals(null, created.Organization__c, 'Organization should not be set');
    }

    @isTest
    static void testUpdateBulkBuyPost_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => post.Id,
            'title' => 'Updated Bulk Buy Title'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.updateBulkBuyPost(JSON.serialize(updateData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Needs_Offers__c updated = [SELECT Name FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Updated Bulk Buy Title', updated.Name, 'Title should be updated');
    }

    @isTest
    static void testUpdateBulkBuyPost_AvailabilityAndPickup() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);

        Datetime expiry = System.now().addDays(3);
        String expiryStr = expiry.format('yyyy-MM-dd') + 'T' + expiry.format('HH:mm');

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => post.Id,
            'availabilityRule' => 'Expires_At_Date',
            'expiryDateTime' => expiryStr,
            'autoLockDays' => '14'
        };

        Test.startTest();
        System.runAs(testUser) {
            FimbyBulkBuyController.updateBulkBuyPost(JSON.serialize(updateData));
        }
        Test.stopTest();

        Needs_Offers__c updated = [
            SELECT Availability_Rule__c, Expiry_DateTime__c, Auto_Lock_Days__c
            FROM Needs_Offers__c WHERE Id = :post.Id
        ];
        System.assertEquals('Expires_At_Date', updated.Availability_Rule__c);
        System.assertNotEquals(null, updated.Expiry_DateTime__c);
        System.assertEquals('14', updated.Auto_Lock_Days__c);
    }

    @isTest
    static void testUpdateBulkBuyPost_NotOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);

        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Person',
            AccountId = testContact.AccountId,
            Email = 'other@fimby.test.com'
        );
        insert otherContact;
        User otherUser = FimbyTestDataFactory.createCommunityUser(otherContact.Id, null, true);

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => post.Id,
            'title' => 'Should Not Update'
        };

        Test.startTest();
        Boolean caught = false;
        FimbyIdentityRepository.clearCache();
        System.runAs(otherUser) {
            try {
                FimbyBulkBuyController.updateBulkBuyPost(JSON.serialize(updateData));
            } catch (Exception e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Should throw AuraHandledException for non-owner');
    }

    @isTest
    static void testGetBulkBuyDetail_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.getBulkBuyDetail(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isOrganiser'), 'User should be the organiser');
        System.assertNotEquals(null, result.get('reservations'), 'Should return reservations list');
        System.assertNotEquals(null, result.get('contactId'), 'Should return contactId');
    }

    @isTest
    static void testGetBulkBuyDetail_ReservationRowsCarryAvatarIdentity() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 1);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.getBulkBuyDetail(post.Id);
        }
        Test.stopTest();

        List<Object> rows = (List<Object>) result.get('reservations');
        System.assert(!rows.isEmpty(), 'Should return the seeded reservation');
        Map<String, Object> row = (Map<String, Object>) rows[0];
        System.assertEquals(testContact.Id, row.get('contactId'), 'Row should carry the represented Contact Id');
        System.assert(row.containsKey('avatarUrl'), 'Row should carry avatarUrl');
        System.assertEquals(false, row.get('isOrgContact'), 'Person reserver is not an organisation');
    }

    @isTest
    static void testPutReservationIdentity_MaskedPersonNeverUsesRawPhoto() {
        Contact masked = (Contact) JSON.deserialize(
            '{"attributes":{"type":"Contact"},"Image_URL__c":"https://example.com/raw.jpg",'
            + '"Display_Avatar_URL__c":null,"Is_Organization_Contact__c":false}',
            Contact.class
        );
        Map<String, Object> row = new Map<String, Object>();
        FimbyBulkBuyController.putReservationIdentity(row, masked);
        System.assertEquals(null, row.get('avatarUrl'), 'Masked person must not expose the raw photo');
        System.assertEquals(false, row.get('isOrgContact'));
        System.assertEquals(null, row.get('orgAccountId'));
    }

    @isTest
    static void testPutReservationIdentity_OrganisationUsesLogoAndName() {
        Contact org = new Contact(Is_Organization_Contact__c = true);
        Account orgAccount = new Account(Name = 'The Life', Logo_URL__c = 'https://example.com/logo.png');
        org.putSObject('Organization_Account__r', orgAccount);
        Map<String, Object> row = new Map<String, Object>();
        FimbyBulkBuyController.putReservationIdentity(row, org);
        System.assertEquals('https://example.com/logo.png', row.get('avatarUrl'), 'Org logo takes precedence');
        System.assertEquals(true, row.get('isOrgContact'));
        System.assertEquals('The Life', row.get('orgName'));
    }

    @isTest
    static void testNotifyForPickup_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        post.Total_Quantity__c = 4;
        update post;
        createGroupConversation(post);
        createReservation(post.Id, testContact.Id, 2);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.notifyForPickup(
                post.Id, 'Come pick up your shares!', 'https://example.com/receipt.jpg'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Needs_Offers__c updated = [SELECT Status__c, Pickup_Notified__c, Name FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Pickup_Ready', updated.Status__c, 'Status should be Pickup_Ready');
        System.assertEquals(true, updated.Pickup_Notified__c, 'Pickup_Notified should be true');

        List<Notification__c> pickupNotifs = [
            SELECT Title__c, Body__c
            FROM Notification__c
            WHERE Related_Record_Id__c = :String.valueOf(post.Id)
              AND Type__c = :FimbyConstants.NOTIF_BULK_BUY_PICKUP
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, pickupNotifs.size(), 'Should notify reservers about pickup');
        System.assertEquals('Pickup is ready', pickupNotifs[0].Title__c);
        System.assertEquals(updated.Name, pickupNotifs[0].Body__c);
    }

    @isTest
    static void testCompleteBulkBuy_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        post.Status__c = 'Pickup_Ready';
        update post;
        createGroupConversation(post);
        createReservation(post.Id, testContact.Id, 2);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.completeBulkBuy(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Completed (Offer Accepted / Need Met)', updated.Status__c, 'Status should be Completed');
    }

    @isTest
    static void testCompleteBulkBuy_BlockedByFollowUp() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        post.Status__c = 'Pickup_Ready';
        update post;

        Contact reserver = new Contact(
            FirstName = 'Reserver',
            LastName = 'Test',
            AccountId = testContact.AccountId,
            Email = 'reserver@fimby.test.com'
        );
        insert reserver;

        Response__c resp = createReservation(post.Id, reserver.Id, 2);

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
            .getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = testContact.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'Pending',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now()
        );
        insert fu;

        Test.startTest();
        Boolean caught = false;
        System.runAs(testUser) {
            try {
                FimbyBulkBuyController.completeBulkBuy(post.Id);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Should throw when pending follow-ups exist');
    }

    @isTest
    static void testCancelBulkBuy_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createGroupConversation(post);
        Response__c resp = createReservation(post.Id, testContact.Id, 2);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.cancelBulkBuy(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Needs_Offers__c updatedPost = [SELECT Status__c, Name FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Cancelled', updatedPost.Status__c, 'Post status should be Cancelled');
        Response__c updatedResp = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('Cancelled', updatedResp.Status__c, 'Reservation status should be Cancelled');

        List<Notification__c> cancelNotifs = [
            SELECT Title__c, Body__c
            FROM Notification__c
            WHERE Related_Record_Id__c = :String.valueOf(post.Id)
              AND Type__c = :FimbyConstants.NOTIF_BULK_BUY_STATUS
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, cancelNotifs.size(), 'Should notify reservers about cancellation');
        System.assertEquals(
            updatedPost.Name + ' has been cancelled',
            cancelNotifs[0].Title__c,
            'Cancel title should be self-contained without an "Update on" wrapper'
        );
        System.assert(String.isBlank(cancelNotifs[0].Body__c),
            'Cancel body should be empty when title carries the message');
    }

    private static Boolean pickupRejected(User runner, Id postId) {
        Boolean caught = false;
        System.runAs(runner) {
            try {
                FimbyBulkBuyController.notifyForPickup(postId, '', null);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        return caught;
    }

    private static Boolean closeRejected(User runner, Id postId) {
        Boolean caught = false;
        System.runAs(runner) {
            try {
                FimbyBulkBuyController.closeReservations(postId);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        return caught;
    }

    private static void stampClosed(Needs_Offers__c post) {
        post.Reservations_Closed_Date__c = System.now().addMinutes(-5);
        update post;
    }

    @isTest
    static void testNotifyForPickup_ClosedPartialAllowed() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 2);
        stampClosed(post);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.notifyForPickup(post.Id, '', null);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Closed partial buy should go ahead with what is reserved');
        System.assertEquals('Pickup_Ready', [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id].Status__c);
    }

    @isTest
    static void testNotifyForPickup_OpenPartialRejected() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 2);

        Test.startTest();
        Boolean rejected = pickupRejected(testUser, post.Id);
        Test.stopTest();

        System.assert(rejected, 'Open partial buy must close reservations before pickup');
        System.assertEquals('Available', [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id].Status__c);
    }

    @isTest
    static void testNotifyForPickup_NoReserverRejected() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        stampClosed(post);

        Test.startTest();
        Boolean rejected = pickupRejected(testUser, post.Id);
        Test.stopTest();

        System.assert(rejected, 'Pickup needs at least one reserved share');
    }

    @isTest
    static void testNotifyForPickup_TerminalAndDuplicateRejected() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c cancelled = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(cancelled.Id, testContact.Id, 2);
        stampClosed(cancelled);
        cancelled.Status__c = 'Cancelled';
        update cancelled;

        Needs_Offers__c alreadyReady = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(alreadyReady.Id, testContact.Id, 2);
        alreadyReady.Status__c = 'Pickup_Ready';
        update alreadyReady;

        Test.startTest();
        Boolean terminalRejected = pickupRejected(testUser, cancelled.Id);
        Boolean duplicateRejected = pickupRejected(testUser, alreadyReady.Id);
        Test.stopTest();

        System.assert(terminalRejected, 'Cancelled buy cannot announce pickup');
        System.assert(duplicateRejected, 'Pickup cannot be announced twice');
    }

    @isTest
    static void testUpdateBulkBuyPost_ClosedAllocationEditRejected() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 2);
        stampClosed(post);

        Test.startTest();
        Boolean caught = false;
        System.runAs(testUser) {
            try {
                FimbyBulkBuyController.updateBulkBuyPost(JSON.serialize(new Map<String, Object>{
                    'recordId' => post.Id, 'totalQuantity' => 12
                }));
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Closed buy must not silently reopen through a quantity edit');
        System.assertEquals(10, [SELECT Total_Quantity__c FROM Needs_Offers__c WHERE Id = :post.Id].Total_Quantity__c);
    }

    @isTest
    static void testUpdateBulkBuyPost_ClosedDescriptiveEditAndCancelAllowed() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 2);
        stampClosed(post);

        Test.startTest();
        Map<String, Object> editResult;
        Map<String, Object> cancelResult;
        System.runAs(testUser) {
            editResult = FimbyBulkBuyController.updateBulkBuyPost(JSON.serialize(new Map<String, Object>{
                'recordId' => post.Id, 'title' => 'Renamed after closing', 'totalQuantity' => 10
            }));
            cancelResult = FimbyBulkBuyController.cancelBulkBuy(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, editResult.get('success'), 'Descriptive edits stay open after closure');
        System.assertEquals(true, cancelResult.get('success'), 'Organiser can still cancel the whole buy');
        Needs_Offers__c updated = [SELECT Name, Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Renamed after closing', updated.Name);
        System.assertEquals('Cancelled', updated.Status__c);
    }

    @isTest
    static void testChangesAllocation_ExpiryTolerance() {
        Datetime expiry = Datetime.newInstance(2030, 1, 15, 10, 30, 0);
        Needs_Offers__c post = new Needs_Offers__c(
            Total_Quantity__c = 10, Owner_Shares__c = 2, Per_Response_Limit__c = 5,
            Availability_Rule__c = 'Expires_At_Date', Expiry_DateTime__c = expiry
        );
        String sameMinute = expiry.format('yyyy-MM-dd') + 'T' + expiry.format('HH:mm');
        Datetime later = expiry.addHours(2);
        String laterMinute = later.format('yyyy-MM-dd') + 'T' + later.format('HH:mm');

        System.assertEquals(false, FimbyBulkBuyController.changesAllocation(post, new Map<String, Object>{
            'expiryDateTime' => sameMinute, 'ownerShares' => 2, 'perResponseLimit' => 5,
            'availabilityRule' => 'Expires_At_Date'
        }), 'Re-saving unchanged allocation is not a change');
        System.assertEquals(true, FimbyBulkBuyController.changesAllocation(post, new Map<String, Object>{
            'expiryDateTime' => laterMinute
        }), 'Moving the expiry is an allocation change');
        System.assertEquals(true, FimbyBulkBuyController.changesAllocation(post, new Map<String, Object>{
            'ownerShares' => 3
        }), 'Owner shares change is an allocation change');
        System.assertEquals(true, FimbyBulkBuyController.changesAllocation(post, new Map<String, Object>{
            'perResponseLimit' => 4
        }), 'Per-person limit change is an allocation change');
        System.assertEquals(true, FimbyBulkBuyController.changesAllocation(post, new Map<String, Object>{
            'availabilityRule' => 'Open_Until_Full_Or_Closed'
        }), 'Rule change is an allocation change');
    }

    @isTest
    static void testCloseReservations_OrganiserClosesPartialThenNotifiesPickup() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createGroupConversation(post);
        createReservation(post.Id, testContact.Id, 2);
        Integer notificationsBefore = [SELECT COUNT() FROM Notification__c];
        Integer messagesBefore = [SELECT COUNT() FROM Message__c];

        Test.startTest();
        Map<String, Object> closeResult;
        System.runAs(testUser) {
            closeResult = FimbyBulkBuyController.closeReservations(post.Id);
        }
        Integer notificationsAfterClose = [SELECT COUNT() FROM Notification__c];
        Integer messagesAfterClose = [SELECT COUNT() FROM Message__c];
        Map<String, Object> pickupResult;
        System.runAs(testUser) {
            pickupResult = FimbyBulkBuyController.notifyForPickup(post.Id, '', null);
        }
        Test.stopTest();

        System.assertEquals(true, closeResult.get('success'), 'Organiser should close reservations');
        System.assertEquals(notificationsBefore, notificationsAfterClose, 'Closing reservations notifies nobody');
        System.assertEquals(messagesBefore, messagesAfterClose, 'Closing reservations posts nothing to chat');
        System.assertEquals(true, pickupResult.get('success'), 'Closed partial buy can then notify for pickup');
        Needs_Offers__c updated = [SELECT Status__c, Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertNotEquals(null, updated.Reservations_Closed_Date__c, 'Closure should be stamped');
        System.assertEquals('Pickup_Ready', updated.Status__c);
    }

    @isTest
    static void testCloseReservations_NonOrganiserRejected() {
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(post.Id, testContact.Id, 2);

        Contact otherContact = new Contact(
            FirstName = 'Other', LastName = 'Neighbour',
            AccountId = testContact.AccountId, Email = 'other.close@fimby.example.com'
        );
        insert otherContact;
        User otherUser = FimbyTestDataFactory.createCommunityUser(otherContact.Id, null, true);

        Test.startTest();
        FimbyIdentityRepository.clearCache();
        Boolean rejected = closeRejected(otherUser, post.Id);
        Test.stopTest();

        System.assert(rejected, 'Only the organiser can close reservations');
        System.assertEquals(null,
            [SELECT Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id].Reservations_Closed_Date__c);
    }

    @isTest
    static void testCloseReservations_ActingAsRepresentedOrganiserAllowed() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact represented = new Contact(
            FirstName = 'Represented', LastName = 'Organiser',
            AccountId = testContact.AccountId, Email = 'represented.close@fimby.example.com'
        );
        Contact author = new Contact(
            FirstName = 'Original', LastName = 'Author',
            AccountId = testContact.AccountId, Email = 'author.close@fimby.example.com'
        );
        insert new List<Contact>{ represented, author };
        insert new Support_Relationship__c(
            Contact__c = testContact.Id,
            Related_Contact__c = represented.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = testContact.AccountId
        );
        update new Contact(Id = testContact.Id, Logged_In_As_Contact__c = represented.Id);

        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
        post.Posted_By__c = author.Id;
        post.Contact__c = represented.Id;
        update post;
        createReservation(post.Id, author.Id, 2);

        Test.startTest();
        FimbyIdentityRepository.clearCache();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyBulkBuyController.closeReservations(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Acting as the represented organiser should be allowed');
        System.assertNotEquals(null,
            [SELECT Reservations_Closed_Date__c FROM Needs_Offers__c WHERE Id = :post.Id].Reservations_Closed_Date__c);
    }

    @isTest
    static void testCloseReservations_AlreadyClosedEmptyAndTerminalRejected() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Needs_Offers__c alreadyClosed = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(alreadyClosed.Id, testContact.Id, 2);
        stampClosed(alreadyClosed);

        Needs_Offers__c empty = createBulkBuyPost(testContact, testContact.AccountId);

        Needs_Offers__c terminal = createBulkBuyPost(testContact, testContact.AccountId);
        createReservation(terminal.Id, testContact.Id, 2);
        terminal.Status__c = 'Pickup_Ready';
        update terminal;

        Test.startTest();
        Boolean closedRejected = closeRejected(testUser, alreadyClosed.Id);
        Boolean emptyRejected = closeRejected(testUser, empty.Id);
        Boolean terminalRejected = closeRejected(testUser, terminal.Id);
        Test.stopTest();

        System.assert(closedRejected, 'Already-closed buy cannot be closed again');
        System.assert(emptyRejected, 'A buy with no reservations has nothing to close');
        System.assert(terminalRejected, 'A buy past Available cannot be closed');
    }

    @isTest
    static void testGetMyBulkBuys_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        createBulkBuyPost(testContact, testContact.AccountId);

        Test.startTest();
        List<Map<String, Object>> results;
        System.runAs(testUser) {
            results = FimbyBulkBuyController.getMyBulkBuys();
        }
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Should return at least one bulk buy');
        System.assertEquals('organiser', results[0].get('role'), 'Role should be organiser');
    }
}
