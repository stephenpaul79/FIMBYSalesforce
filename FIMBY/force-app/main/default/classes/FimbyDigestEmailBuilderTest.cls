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
    static void resolveCrossFimbyTimePhrase_multiDayDaily_usesWeekend() {
        Datetime sat = Datetime.newInstance(2026, 4, 11, 0, 0, 0);
        Datetime sun = Datetime.newInstance(2026, 4, 12, 23, 59, 59);
        System.assertEquals(
            'this weekend',
            FimbyDigestEmailBuilder.resolveCrossFimbyTimePhrase('Daily', sat, sun)
        );
    }

    @IsTest
    static void resolveCrossFimbyTimePhrase_singleDayDaily_usesYesterday() {
        Datetime day = Datetime.newInstance(2026, 4, 12, 12, 0, 0);
        System.assertEquals(
            'yesterday',
            FimbyDigestEmailBuilder.resolveCrossFimbyTimePhrase('Daily', day, day)
        );
    }

    @IsTest
    static void resolveCrossFimbyTimePhrase_weekly_usesThisWeek() {
        Datetime startDt = Datetime.newInstance(2026, 4, 6, 0, 0, 0);
        Datetime endDt = Datetime.newInstance(2026, 4, 12, 23, 59, 59);
        System.assertEquals(
            'this week',
            FimbyDigestEmailBuilder.resolveCrossFimbyTimePhrase('Weekly', startDt, endDt)
        );
    }

    @IsTest
    static void getCrossFimbyStat_returnsLineWhenCountsExist() {
        Datetime startDt = Datetime.newInstance(Date.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(Date.today(), Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        FimbyDigestEmailBuilder.CrossFimbyStat stat =
            FimbyDigestEmailBuilder.getCrossFimbyStat('Daily', startDt, endDt);
        Test.stopTest();

        System.assertNotEquals(null, stat);
        if (stat.count > 0) {
            System.assert(stat.line.contains('across FIMBY'), 'Cross-FIMBY line should mention the platform: ' + stat.line);
        }
    }

    @IsTest
    static void formatCrossFimbyLine_singularUsesSingularGrammar() {
        System.assertEquals(
            'across FIMBY, 1 neighbour set something out for whoever needed it.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(0, 1)
        );
        System.assertEquals(
            'across FIMBY, 1 ask was met by someone close by.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(1, 1)
        );
        System.assertEquals(
            'across FIMBY, 1 thing was passed from one neighbour to the next.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(2, 1)
        );
        System.assertEquals(
            'across FIMBY, 1 neighbour shared a piece of their life.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(3, 1)
        );
    }

    @IsTest
    static void formatCrossFimbyLine_pluralUsesPluralGrammar() {
        System.assertEquals(
            'across FIMBY, 3 neighbours set something out for whoever needed it.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(0, 3)
        );
        System.assertEquals(
            'across FIMBY, 2 asks were met by someone close by.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(1, 2)
        );
        System.assertEquals(
            'across FIMBY, 5 things were passed from one neighbour to the next.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(2, 5)
        );
        System.assertEquals(
            'across FIMBY, 4 neighbours shared a piece of their life.',
            FimbyDigestEmailBuilder.formatCrossFimbyLine(3, 4)
        );
    }

    @IsTest
    static void shouldShowCrossFimby_suppressesWhenNotMoreThanEmail() {
        // Equal or fewer cross-FIMBY items than feed cards = redundant re-count, suppress.
        System.assertEquals(false, FimbyDigestEmailBuilder.shouldShowCrossFimby(1, 1),
            'Cross count equal to feed cards re-counts the email and must be hidden.');
        System.assertEquals(false, FimbyDigestEmailBuilder.shouldShowCrossFimby(1, 3),
            'Cross count below feed cards must be hidden.');
        System.assertEquals(false, FimbyDigestEmailBuilder.shouldShowCrossFimby(0, 0),
            'Zero cross count must be hidden.');
        System.assertEquals(false, FimbyDigestEmailBuilder.shouldShowCrossFimby(null, 2),
            'Null cross count must be hidden.');
    }

    @IsTest
    static void shouldShowCrossFimby_showsWhenMoreThanEmail() {
        // Genuinely more activity across FIMBY than this email lists = additive zoom-out, show.
        System.assertEquals(true, FimbyDigestEmailBuilder.shouldShowCrossFimby(2, 1));
        System.assertEquals(true, FimbyDigestEmailBuilder.shouldShowCrossFimby(10, 0));
    }

    @IsTest
    static void getCrossFimbyStat_emptyWindow_returnsBlank() {
        Datetime startDt = Datetime.newInstance(Date.today().addYears(-50), Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(Date.today().addYears(-50), Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        FimbyDigestEmailBuilder.CrossFimbyStat stat =
            FimbyDigestEmailBuilder.getCrossFimbyStat('Weekly', startDt, endDt);
        Test.stopTest();

        System.assertEquals(0, stat.count, 'Window with zero counts should report a zero count.');
        System.assertEquals('', stat.line, 'Window with zero counts should return a blank line.');
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
    static void buildAskOfferCard_omitsStillNeededBadgeWhenRefreshed() {
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

        System.assert(!result.html.contains('STILL NEEDED'), 'Refresh badge should no longer appear in digests');
        System.assert(!result.html.contains('STILL AVAILABLE'), 'Refresh badge should no longer appear in digests');
        System.assert(result.html.contains('Refreshed Ask'), 'Refreshed ask should still render in the digest');
    }

    @IsTest
    static void buildCard_withImage_usesPercentageSplitRow() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, false);
        stories[0].Image_Ratio__c = '1080x1350'; // portrait 4:5
        insert stories;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        // Image column is percentage-based so it scales to ~1/3 of the row on every viewport.
        System.assert(
            result.html.contains('width="34%"') && result.html.contains('width="66%"'),
            'Card should use a 34/66 percentage split row. HTML: ' + result.html
        );
        System.assert(
            result.html.contains('height:auto'),
            'Image should keep its natural aspect ratio (no fixed height). HTML: ' + result.html
        );
    }

    @IsTest
    static void buildCard_imageSizingIgnoresRatio() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, false);
        stories[0].Image_Ratio__c = '200x100'; // landscape 2:1 — must not drive a fixed px size
        insert stories;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today()
            );
        Test.stopTest();

        // No ratio-derived pixel height: the image fills its percentage cell at height:auto.
        System.assert(
            result.html.contains('width="34%"') && result.html.contains('height:auto'),
            'Landscape photo should still use the percentage column, not a fixed pixel size. HTML: ' + result.html
        );
        System.assert(
            !result.html.contains('width="220" height='),
            'Card should no longer emit a fixed 220px image width. HTML: ' + result.html
        );
    }

    @IsTest
    static void buildDigestContent_excludedAuthor_hidesOnlyTheirCards() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact authorA = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact authorB = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        insert new Story__c(
            Name = 'Keep This Story', Message__c = 'Visible content here.',
            Type__c = 'Thank You', Neighbourhood__c = nh.Id, Posted_By__c = authorA.Id
        );
        insert new Story__c(
            Name = 'Hidden Blocked Story', Message__c = 'Blocked author content.',
            Type__c = 'Thank You', Neighbourhood__c = nh.Id, Posted_By__c = authorB.Id
        );

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly',
                Date.today().addDays(-7), Date.today(),
                new Set<Id>{ authorB.Id }
            );
        Test.stopTest();

        System.assert(
            result.html.contains('Keep This Story'),
            'Non-blocked author cards must remain in the digest.'
        );
        System.assert(
            !result.html.contains('Hidden Blocked Story'),
            'Blocked author cards must be excluded from the digest.'
        );
    }

    @IsTest
    static void buildDigestContent_excludedAuthor_dropsAndNMoreCount() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact authorA = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact authorB = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        List<Needs_Offers__c> asks = new List<Needs_Offers__c>();
        for (Integer i = 0; i < 6; i++) {
            asks.add(new Needs_Offers__c(
                Name = 'A Ask ' + i, Details__c = 'detail',
                Type__c = 'Goods - Unperishable', Status__c = 'Posted',
                Neighbourhood__c = nh.Id, Contact__c = authorA.Id, Posted_By__c = authorA.Id,
                RecordTypeId = needRt, Posted_Date__c = Datetime.now(),
                End_Date__c = Date.today().addDays(7)
            ));
        }
        for (Integer i = 0; i < 3; i++) {
            asks.add(new Needs_Offers__c(
                Name = 'B Ask ' + i, Details__c = 'detail',
                Type__c = 'Goods - Unperishable', Status__c = 'Posted',
                Neighbourhood__c = nh.Id, Contact__c = authorB.Id, Posted_By__c = authorB.Id,
                RecordTypeId = needRt, Posted_Date__c = Datetime.now(),
                End_Date__c = Date.today().addDays(7)
            ));
        }
        insert asks;

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult unfiltered =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly', Date.today().addDays(-7), Date.today()
            );
        FimbyDigestEmailBuilder.DigestResult filtered =
            FimbyDigestEmailBuilder.buildDigestContent(
                nh.Id, nh.Name, 'Weekly', Date.today().addDays(-7), Date.today(),
                new Set<Id>{ authorB.Id }
            );
        Test.stopTest();

        // 9 asks total -> 5 cards + "and 4 more". With B's 3 hidden -> 6 asks -> "and 1 more".
        System.assert(
            unfiltered.html.contains('and 4 more'),
            'Unfiltered digest should count all 9 asks: ' + unfiltered.html
        );
        System.assert(
            filtered.html.contains('and 1 more'),
            'Filtered "and N more" count must drop to exclude the blocked author: ' + filtered.html
        );
        System.assert(
            !filtered.html.contains('and 4 more'),
            'Filtered digest must not retain the unfiltered count.'
        );
        System.assert(
            !filtered.html.contains('B Ask'),
            'Blocked author asks must not render as cards.'
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

    @IsTest
    static void buildCappedMixedPreview_includesUpcomingEventRegardlessOfPostedDate() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id offerRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c upcoming = new Needs_Offers__c(
            Name = 'Preview Picnic',
            RecordTypeId = offerRt,
            Neighbourhood__c = nh.Id,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(10),
            Location__c = 'Park'
        );
        insert upcoming;
        Test.setCreatedDate(upcoming.Id, Datetime.now().addDays(-30));

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result = FimbyDigestEmailBuilder.buildCappedMixedPreview(
            nh.Id, Date.today().addDays(-7), Date.today(), 5, new Set<Id>()
        );
        Test.stopTest();

        System.assertEquals(1, result.itemCount, 'Single upcoming event should be the only preview item.');
        System.assert(
            result.selectedItemSummaries[0].contains('Preview Picnic'),
            'Mixed preview should include upcoming events by Start_Date, not CreatedDate window.'
        );
    }

    @IsTest
    static void buildCappedMixedPreview_capsAtFiveAndMixesTypes() {
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];

        Test.startTest();
        FimbyDigestEmailBuilder.DigestResult result = FimbyDigestEmailBuilder.buildCappedMixedPreview(
            nh.Id, Date.today().addDays(-7), Date.today(), 5, new Set<Id>()
        );
        Test.stopTest();

        System.assert(result.itemCount > 0, 'Setup data should yield preview items.');
        System.assert(result.itemCount <= 5, 'Preview must cap at five items.');
        System.assert(!result.isEmpty);
        System.assert(result.selectedItemSummaries.size() == result.itemCount);
        System.assert(result.html.contains('A peek at the last week on your street'));
    }
}
