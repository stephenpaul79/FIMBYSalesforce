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
    static void testNotifyForPickup_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c post = createBulkBuyPost(testContact, testContact.AccountId);
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
