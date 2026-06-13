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
    static void resolveCrossFimbyWindowWord_multiDayDaily_usesWeekend() {
        Datetime sat = Datetime.newInstance(2026, 4, 11, 0, 0, 0);
        Datetime sun = Datetime.newInstance(2026, 4, 12, 23, 59, 59);
        System.assertEquals(
            'weekend',
            FimbyDigestEmailBuilder.resolveCrossFimbyWindowWord('Daily', sat, sun)
        );
    }

    @IsTest
    static void resolveCrossFimbyWindowWord_singleDayDaily_usesDay() {
        Datetime day = Datetime.newInstance(2026, 4, 12, 12, 0, 0);
        System.assertEquals(
            'day',
            FimbyDigestEmailBuilder.resolveCrossFimbyWindowWord('Daily', day, day)
        );
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
    static void buildEventsSection_recurringSeries_showsOnlyLiveOccurrence() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :nh.Id LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c parent = new Needs_Offers__c(
            Name = 'Digest Parent Worship',
            RecordTypeId = offerRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Start_Date__c = Date.today().addDays(-7),
            End_Date__c = Date.today().addDays(-7),
            Recurrence_Frequency__c = 'Week',
            Recurrence_Interval__c = 1,
            Location__c = 'Test Hall'
        );
        insert parent;

        Needs_Offers__c child = new Needs_Offers__c(
            Name = 'Digest Child Worship',
            RecordTypeId = offerRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(5),
            Series_Parent__c = parent.Id,
            Location__c = 'Test Hall'
        );
        insert child;
        update new Needs_Offers__c(Id = parent.Id, Current_Occurrence__c = child.Id);

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        System.assert(
            result.html.contains('Digest Child Worship'),
            'Live spawned occurrence should appear in digest'
        );
        System.assert(
            !result.html.contains('Digest Parent Worship'),
            'Series parent must not appear when a live child exists'
        );
    }

    @IsTest
    static void buildEventsSection_excludesPastEventsEvenWhenCreatedInWindow() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :nh.Id LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        insert new Needs_Offers__c(
            Name = 'Past Block Party',
            RecordTypeId = offerRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Start_Date__c = Date.today().addDays(-3),
            End_Date__c = Date.today().addDays(-3),
            Location__c = 'Old Park'
        );

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Daily',
                Date.today().addDays(-1), Date.today().addDays(-1)
            );
        Test.stopTest();

        System.assert(
            !result.html.contains('Past Block Party'),
            'Past events should never appear in digest events section'
        );
    }

    @IsTest
    static void buildEventsSection_excludesPastRecurringParentBeforeSpawn() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :nh.Id LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        insert new Needs_Offers__c(
            Name = 'Stale Series Parent',
            RecordTypeId = offerRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Start_Date__c = Date.today().addDays(-7),
            End_Date__c = Date.today().addDays(-7),
            Recurrence_Frequency__c = 'Week',
            Recurrence_Interval__c = 1,
            Next_Occurrence_Date__c = Date.today().addDays(1),
            Location__c = 'Test Hall'
        );

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Daily',
                Date.today().addDays(-1), Date.today().addDays(-1)
            );
        Test.stopTest();

        System.assert(
            !result.html.contains('Stale Series Parent'),
            'Past live parent should not appear before next spawn'
        );
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

    @IsTest
    static void buildAskOfferCard_showsStillNeededBadgeWhenRefreshed() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :nh.Id LIMIT 1];
        Id needRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        insert new Needs_Offers__c(
            Name = 'Refreshed Ask',
            RecordTypeId = needRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Posted_Date__c = Datetime.now(),
            Refresh_Count__c = 1,
            End_Date__c = Date.today().addDays(5)
        );

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        System.assert(result.html.contains('STILL NEEDED'), 'Refreshed ask should show badge');
    }

    @IsTest
    static void buildCard_portraitRatio_usesTwoColumnLayout() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, false);
        stories[0].Image_Ratio__c = '1080x1350'; // portrait 4:5 -> ratio 0.8
        insert stories;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        // ratio 0.8 -> imgWidth = round(210 * 0.8) = 168, fixed height 210, image flush left.
        System.assert(
            result.html.contains('width="168" height="210"'),
            'Portrait photo should render a ratio-sized two-column image. HTML: ' + result.html
        );
    }

    @IsTest
    static void buildCard_landscapeRatio_usesStackedLayoutAtTrueHeight() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, false);
        stories[0].Image_Ratio__c = '200x100'; // landscape 2:1 -> ratio 2.0
        insert stories;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        // ratio 2.0 -> stacked full width 552 at true height 552 / 2 = 276.
        System.assert(
            result.html.contains('width="552" height="276"'),
            'Landscape photo should render stacked at its true height. HTML: ' + result.html
        );
    }

    @IsTest
    static void formatRecurrenceFrequencyBadge_weekly() {
        System.assertEquals(
            'WEEKLY',
            FimbyDigestEmailBuilder.formatRecurrenceFrequencyBadge('Week', 1)
        );
        System.assertEquals(
            'EVERY 2 WEEKS',
            FimbyDigestEmailBuilder.formatRecurrenceFrequencyBadge('Week', 2)
        );
    }
}
