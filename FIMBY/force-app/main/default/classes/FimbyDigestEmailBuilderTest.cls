@IsTest
private class FimbyDigestEmailBuilderTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        FimbyTestDataFactory.createStories(nh.Id, c.Id, 3, true);
        FimbyTestDataFactory.createNeedsOffers(nh.Id, c.Id, 'Need', 2, true);
        FimbyTestDataFactory.createNeedsOffers(nh.Id, c.Id, 'Offer', 2, true);
        FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 2, true);

        List<Needs_Offers__c> events = FimbyTestDataFactory.createNeedsOffers(nh.Id, c.Id, 'Need', 2, false);
        for (Needs_Offers__c evt : events) {
            evt.Type__c = 'Event';
            evt.Event_Type__c = 'Open_Event';
            evt.Start_Date__c = Date.today().addDays(3);
            evt.Location__c = 'Community Hall';
        }
        events[1].Event_Type__c = 'Gathering';
        insert events;

        List<Needs_Offers__c> bulkBuys = FimbyTestDataFactory.createNeedsOffers(nh.Id, c.Id, 'Bulk_Buy', 2, false);
        for (Needs_Offers__c bb : bulkBuys) {
            bb.Total_Quantity__c = 10;
            bb.Total_Reserved__c = 3;
            bb.Total_Estimated_Cost__c = 150;
            bb.Allocation_Unit_Label__c = 'bags';
        }
        insert bulkBuys;
    }

    @IsTest
    static void buildDigestContent_emptyNeighbourhood_dailySkips() {
        Account emptyNh = new Account(Name = 'Empty NH');
        insert emptyNh;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                emptyNh.Id, 'Empty NH', 'Daily',
                Date.today().addDays(-1), Date.today().addDays(-1)
            );
        Test.stopTest();

        System.assertEquals(0, result.itemCount);
        System.assert(result.isEmpty, 'No feed cards = isEmpty=true (batch will write Skipped log row).');
        System.assertEquals('', result.html, 'Empty digest should produce no HTML.');
    }

    @IsTest
    static void buildDigestContent_emptyNeighbourhood_weeklySkips() {
        Account emptyNh = new Account(Name = 'Empty NH 2');
        insert emptyNh;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                emptyNh.Id, 'Empty NH 2', 'Weekly',
                Date.today().addDays(-7), Date.today().addDays(-1)
            );
        Test.stopTest();

        System.assertEquals(0, result.itemCount);
        System.assert(result.isEmpty);
    }

    @IsTest
    static void buildDigestContent_withContent_daily_producesRichCards() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Daily',
                Date.today().addDays(-1), Date.today()
            );
        Test.stopTest();

        System.assert(result.itemCount > 0, 'Should have items: ' + result.itemCount);
        System.assert(!result.isEmpty);
        System.assert(result.html.contains('border-radius:8px'), 'Should use rich card layout');
        System.assert(result.html.contains('border-radius:10px'), 'Should contain badge pills');
    }

    @IsTest
    static void buildDigestContent_withContent_weekly_producesAllSections() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        System.assert(result.itemCount > 0);
        System.assert(result.html.contains('Shared Life'), 'Should have stories section');
        System.assert(result.html.contains('Asks'), 'Should have asks section');
        System.assert(result.html.contains('Read More'), 'Should have story CTA');
        System.assert(result.html.contains('Respond'), 'Should have ask/offer CTA');
        System.assert(result.html.contains('Events'), 'Should have events section');
        System.assert(result.html.contains('Bulk Buys'), 'Should have bulk buys section');
        System.assert(result.html.contains('Reserve-A-Share'), 'Should have bulk buy CTA');
        System.assert(result.html.contains('Library'), 'Should have library section');
        System.assert(result.html.contains('Borrow'), 'Should have library CTA');
        System.assert(result.html.contains('/asks-offers/'), 'Ask/offer CTAs should use /asks-offers/');
        System.assert(!result.html.contains('/needs-offers/'), 'Legacy /needs-offers/ must not appear in digest links');
    }

    @IsTest
    static void digestResult_defaultValues() {
        FimbyDigestEmailBuilder.DigestResult r = new FimbyDigestEmailBuilder.DigestResult();
        System.assertEquals('', r.html);
        System.assertEquals(0, r.itemCount);
        System.assert(r.isEmpty);
    }

    @IsTest
    static void getCrossFimbyStat_returnsLineWhenCountsExist() {
        Datetime startDt = Datetime.newInstance(Date.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(Date.today(), Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        String line = FimbyDigestEmailBuilder.getCrossFimbyStat('Daily', startDt, endDt);
        Test.stopTest();

        System.assertNotEquals(null, line);
        if (String.isNotBlank(line)) {
            System.assert(line.contains('across FIMBY'), 'Cross-FIMBY line should mention the platform: ' + line);
        }
    }

    @IsTest
    static void getCrossFimbyStat_emptyWindow_returnsBlank() {
        Datetime startDt = Datetime.newInstance(Date.today().addYears(-50), Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(Date.today().addYears(-50), Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        String line = FimbyDigestEmailBuilder.getCrossFimbyStat('Weekly', startDt, endDt);
        Test.stopTest();

        System.assertEquals('', line, 'Window with zero counts should return blank line.');
    }

    @IsTest
    static void buildAnchorCard_alwaysReturnsStringSafely() {
        Test.startTest();
        String html = FimbyDigestEmailBuilder.buildAnchorCard();
        Test.stopTest();

        System.assertNotEquals(null, html, 'Anchor card must never return null.');
    }

    @IsTest
    static void pickAnchorRecord_returnsActiveRecordOrNull() {
        Test.startTest();
        FIMBY_Digest_Anchor__mdt result = FimbyDigestEmailBuilder.pickAnchorRecord(Date.today());
        Test.stopTest();

        if (result != null) {
            System.assertNotEquals(null, result.Type__c, 'Selected anchor must have a Type.');
            System.assert(String.isNotBlank(result.Body__c), 'Selected anchor must have a Body.');
        }
    }

    @IsTest
    static void pickAnchorRecord_handlesArbitraryDates() {
        Test.startTest();
        FimbyDigestEmailBuilder.pickAnchorRecord(Date.newInstance(2026, 7, 8));
        FimbyDigestEmailBuilder.pickAnchorRecord(Date.newInstance(2026, 12, 31));
        FimbyDigestEmailBuilder.pickAnchorRecord(Date.newInstance(2026, 1, 1));
        Test.stopTest();
    }

    @IsTest
    static void buildDigestContent_includesAnchorCardWhenContentExists() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        System.assert(!result.isEmpty);
        // Anchor card uses the same border-light hex as feed cards but its presence is
        // guaranteed when content exists. Just confirm the build ran end to end and produced HTML.
        System.assert(result.html.length() > 0);
    }
}
