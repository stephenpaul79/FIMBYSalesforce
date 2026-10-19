@IsTest
private class FimbyFeedItemTest {

    @IsTest
    static void outcomeLabel_matchesPostKind() {
        System.assertEquals('Answered', FimbyFeedItem.outcomeLabel('Goods - Unperishable', FimbyConstants.RT_NEED));
        System.assertEquals('Received', FimbyFeedItem.outcomeLabel('Goods - Unperishable', FimbyConstants.RT_OFFER));
        System.assertEquals('Happened', FimbyFeedItem.outcomeLabel('Event', FimbyConstants.RT_NEED));
        System.assertEquals('Purchased', FimbyFeedItem.outcomeLabel(null, 'Bulk Buy'));
    }

    @IsTest
    static void constructor_carriesLifecycleFields() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact owner = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
        Datetime closedAt = Datetime.now().addDays(-1);
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Ladder', Details__c = 'Need a ladder', Type__c = 'Goods - Unperishable',
            Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED, Closed_Date__c = closedAt,
            Neighbourhood__c = nh.Id, Contact__c = owner.Id, Posted_By__c = owner.Id, RecordTypeId = needRtId
        );
        insert post;

        List<Needs_Offers__c> rows = [
            SELECT Id, Name, Details__c, Full_Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c,
                   Closed_Date__c, Total_Accepted__c, Total_Reserved__c, Total_Quantity__c, Owner_Shares__c,
                   Total_Available__c, Active_Reserver_Ids__c, Is_Urgent__c,
                   Image_1_URL__c, Image_1_Ratio__c, Image_2_URL__c, Image_2_Ratio__c,
                   Image_3_URL__c, Image_3_Ratio__c, Image_4_URL__c, Image_4_Ratio__c,
                   Event_Details__c, Location__c, Event_Type__c, Event_Link__c,
                   Recurrence_Frequency__c, Series_Parent__c, Current_Occurrence__c,
                   RecordType.Name, Category__c, Contact__c, Posted_By__c,
                   Contact__r.Full_Name__c, Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                   Contact__r.Is_Organization_Contact__c, Contact__r.Organization_Account__c,
                   Contact__r.Organization_Account__r.Logo_URL__c,
                   Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c,
                   Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c,
                   Posted_By__r.Organization_Account__r.Logo_URL__c
            FROM Needs_Offers__c WHERE Id = :post.Id
        ];

        Test.startTest();
        FimbyFeedItem.primeProxiedOwners(rows);
        FimbyFeedItem item = new FimbyFeedItem(rows[0]);
        FimbyFeedItem.applyEngagement(new List<FimbyFeedItem>{ item }, owner.Id);
        Test.stopTest();

        System.assertEquals(FimbyConstants.NEEDS_OFFERS_COMPLETED, item.status);
        System.assertEquals(closedAt, item.closedDate);
        System.assertEquals('Answered', item.closedOutcome);
        System.assertEquals(0, item.replyCount);
        System.assertEquals(false, item.viewerHasActiveResponse);
    }

    @IsTest
    static void constructor_toleratesRowsWithoutLifecycleFields() {
        Needs_Offers__c bare = new Needs_Offers__c(Name = 'Bare', Type__c = 'Goods - Unperishable');

        FimbyFeedItem item = new FimbyFeedItem(bare);

        System.assertEquals(null, item.closedDate);
        System.assertEquals(null, item.closedOutcome);
        FimbyFeedItem.applyEngagement(new List<FimbyFeedItem>(), null);
        FimbyFeedItem.applyEngagement(null, null);
    }
}
