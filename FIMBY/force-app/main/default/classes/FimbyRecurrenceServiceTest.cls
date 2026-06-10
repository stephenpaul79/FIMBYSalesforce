@isTest
private class FimbyRecurrenceServiceTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            [SELECT Id FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1].Id,
            null,
            true
        );
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Username LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Map<String, Object> recurringEventPayload() {
        String startIso = String.valueOf(Date.today()) + 'T10:00';
        return new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Weekly Coffee',
            'description' => 'Neighbourhood coffee meetup',
            'type' => 'Event',
            'endDate' => String.valueOf(Date.today().addDays(30)),
            'eventStart' => startIso,
            'location' => 'Corner Cafe',
            'eventType' => 'Open_Event',
            'recurrenceEnabled' => true,
            'recurrenceFrequency' => 'Week',
            'recurrenceInterval' => 1,
            'recurrenceEndMode' => 'After_N',
            'recurrenceMaxOccurrences' => 2,
            'reinvitePriorAttendees' => false
        };
    }

    @isTest
    static void testDailyRecurrenceRejected() {
        User testUser = getTestUser();
        Map<String, Object> payload = recurringEventPayload();
        payload.put('recurrenceFrequency', 'Day');

        Boolean threw = false;
        System.runAs(testUser) {
            try {
                FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw, 'Daily recurrence should be rejected');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Needs_Offers__c WHERE Name = 'Weekly Coffee'],
            'No post should be created when daily recurrence is rejected'
        );
    }

    @isTest
    static void testCreateRecurringEventSetsSeriesParent() {
        User testUser = getTestUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        Needs_Offers__c parent = [
            SELECT Recurrence_Frequency__c, Recurrence_Interval__c, Recurrence_End_Mode__c,
                   Recurrence_Max_Occurrences__c, Current_Occurrence__c, Next_Occurrence_Date__c,
                   Series_Ended__c, Series_Parent__c
            FROM Needs_Offers__c
            WHERE Id = :(String) result.get('recordId')
        ];
        System.assertEquals('Week', parent.Recurrence_Frequency__c);
        System.assertEquals(1, parent.Recurrence_Interval__c.intValue());
        System.assertEquals('After_N', parent.Recurrence_End_Mode__c);
        System.assertEquals(2, parent.Recurrence_Max_Occurrences__c.intValue());
        System.assertEquals(null, parent.Current_Occurrence__c);
        System.assertNotEquals(null, parent.Next_Occurrence_Date__c);
        System.assertEquals(false, parent.Series_Ended__c);
        System.assertEquals(null, parent.Series_Parent__c);
    }

    @isTest
    static void testProcessDueSeriesSpawnsChildWithCleanRsvpList() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(
                Id = parentId,
                Next_Occurrence_Date__c = Date.today()
            );
        }

        Test.startTest();
        Integer spawned;
        System.runAs(testUser) {
            spawned = FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        System.assertEquals(1, spawned);
        List<Needs_Offers__c> children = [
            SELECT Id, Series_Parent__c, Total_Quantity__c, Event_Type__c
            FROM Needs_Offers__c
            WHERE Series_Parent__c = :parentId
        ];
        System.assertEquals(1, children.size());
        System.assertEquals('Open_Event', children[0].Event_Type__c);
        System.assertEquals(null, children[0].Total_Quantity__c);

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Response__c WHERE Need_Offer_Responded_To__c = :children[0].Id]
        );

        Needs_Offers__c parent = [
            SELECT Current_Occurrence__c, Series_Ended__c, Next_Occurrence_Date__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals(children[0].Id, parent.Current_Occurrence__c);
        System.assertEquals(true, parent.Series_Ended__c, 'After_N=2 should end once parent plus one spawn reaches total');
        System.assertEquals(null, parent.Next_Occurrence_Date__c, 'Next occurrence should clear when series ends');
    }

    @isTest
    static void testTotalOccurrencesFormulaIncludesParent() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
        }

        Needs_Offers__c beforeSpawn = [
            SELECT Series_Total_Occurrences__c, Occurrence_Count__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals(
            1,
            beforeSpawn.Series_Total_Occurrences__c.intValue(),
            'Parent alone should count as occurrence 1'
        );

        System.runAs(testUser) {
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
        }

        Needs_Offers__c afterSpawn = [
            SELECT Series_Total_Occurrences__c, Occurrence_Count__c, Series_Ended__c,
                   Next_Occurrence_Date__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        Integer spawned = afterSpawn.Occurrence_Count__c != null
            ? afterSpawn.Occurrence_Count__c.intValue() : 0;
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId],
            'After_N=2 should allow exactly one spawned child'
        );
        System.assertEquals(
            spawned + 1,
            afterSpawn.Series_Total_Occurrences__c.intValue(),
            'Total occurrences should always be spawned children plus parent'
        );
        System.assertEquals(true, afterSpawn.Series_Ended__c);
        System.assertEquals(null, afterSpawn.Next_Occurrence_Date__c);
    }

    @isTest
    static void testAfterNCompleteSeriesEndsOnNextJobWithoutExtraSpawn() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(
                Id = parentId,
                Next_Occurrence_Date__c = Date.today(),
                Recurrence_End_Mode__c = 'After_N',
                Recurrence_Max_Occurrences__c = 2
            );
            FimbyRecurrenceService.processDueSeries(10);
        }

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId],
            'First spawn should create the only child'
        );

        update new Needs_Offers__c(
            Id = parentId,
            Series_Ended__c = false,
            Recurrence_Frequency__c = 'Week',
            Recurrence_Interval__c = 1,
            Recurrence_End_Mode__c = 'After_N',
            Recurrence_Max_Occurrences__c = 2,
            Next_Occurrence_Date__c = Date.today()
        );

        Test.startTest();
        Integer spawnedAgain;
        System.runAs(testUser) {
            spawnedAgain = FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        System.assertEquals(0, spawnedAgain, 'Series already at max should not spawn again');
        Needs_Offers__c parent = [
            SELECT Series_Ended__c, Next_Occurrence_Date__c, Recurrence_Frequency__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals(true, parent.Series_Ended__c);
        System.assertEquals(null, parent.Next_Occurrence_Date__c);
        System.assertEquals(null, parent.Recurrence_Frequency__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId],
            'Still only one spawned child'
        );
    }

    @isTest
    static void testDateMathMonthEndEdgeCase() {
        Date jan31 = Date.newInstance(2026, 1, 31);
        Date feb = FimbyRecurrenceDateMath.advanceDate(jan31, 'Month', 1);
        System.assertEquals(28, feb.day());
        System.assertEquals(2, feb.month());
        Date nextYear = FimbyRecurrenceDateMath.advanceDate(jan31, 'Year', 1);
        System.assertEquals(2027, nextYear.year());
        System.assertEquals(Date.today().addDays(3), FimbyRecurrenceDateMath.advanceDate(Date.today(), 'Day', 3));
        System.assertEquals(2, FimbyRecurrenceDateMath.daysBetweenInclusive(Date.today(), Date.today().addDays(2)));
    }

    @isTest
    static void testReinviteSendsNotificationWhenEnabled() {
        User testUser = getTestUser();
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 2];
        Contact attendee = contacts.size() > 1 ? contacts[1] : contacts[0];
        Id parentId;

        Map<String, Object> payload = recurringEventPayload();
        payload.put('reinvitePriorAttendees', true);
        payload.put('recurrenceEndMode', 'Never');
        payload.put('recurrenceMaxOccurrences', null);

        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            parentId = (String) result.get('recordId');
            Needs_Offers__c parent = [SELECT Contact__c FROM Needs_Offers__c WHERE Id = :parentId];
            insert new Response__c(
                Name = 'Prior RSVP',
                Need_Offer_Responded_To__c = parentId,
                Contact__c = attendee.Id,
                On_Behalf_Of_Contact__c = attendee.Id,
                Reply_To_Contact__c = parent.Contact__c,
                Status__c = 'Accepted',
                Amount_Requested__c = 1
            );
            update new Needs_Offers__c(
                Id = parentId,
                Next_Occurrence_Date__c = Date.today(),
                Reinvite_Prior_Attendees__c = true
            );
        }

        System.assertEquals('Deferred', FimbyRecurrenceSpawnStrategyStubs.deferredLabel());
        System.assertEquals(2, FimbyRecurrenceSpawnStrategyStubs.deferredStrategyCount());

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM Notification__c
             WHERE Type__c = :FimbyConstants.NOTIF_EVENT_SERIES_NEW_OCCURRENCE
             AND Contact__c = :attendee.Id] > 0,
            'Prior attendee should receive opt-in re-invite notification'
        );
    }

    @isTest
    static void testDeleteThisEventOnlyKeepsSeries() {
        User testUser = getTestUser();
        Id parentId;
        Id childId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
            childId = [
                SELECT Id FROM Needs_Offers__c WHERE Series_Parent__c = :parentId LIMIT 1
            ].Id;
            update new Needs_Offers__c(
                Id = parentId,
                Series_Ended__c = false,
                Recurrence_Frequency__c = 'Week',
                Recurrence_Interval__c = 1,
                Recurrence_End_Mode__c = 'Never',
                Next_Occurrence_Date__c = Date.today().addDays(7)
            );
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.deleteSeriesMember(childId, FimbyRecurrenceService.DELETE_THIS_EVENT);
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :childId]);
        Needs_Offers__c parent = [
            SELECT Series_Ended__c, Recurrence_Frequency__c, Current_Occurrence__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals('Week', parent.Recurrence_Frequency__c);
        System.assertEquals(false, parent.Series_Ended__c);
        System.assertEquals(null, parent.Current_Occurrence__c);
    }

    @isTest
    static void testRecurrenceJobExecute() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            update new Needs_Offers__c(
                Id = (String) result.get('recordId'),
                Next_Occurrence_Date__c = Date.today(),
                Recurrence_End_Mode__c = 'Never',
                Recurrence_Max_Occurrences__c = null
            );
        }

        FimbyRecurrenceJob.testMaxRows = 5;

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceJob job = new FimbyRecurrenceJob();
            job.execute(null);
        }
        Test.stopTest();

        FimbyRecurrenceJob.testMaxRows = null;

        System.assert(
            [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c != null] > 0,
            'Job should spawn at least one child occurrence'
        );
    }

    @isTest
    static void testEndSeriesAfterMaxOccurrences() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(
                Id = parentId,
                Next_Occurrence_Date__c = Date.today(),
                Recurrence_End_Mode__c = 'After_N',
                Recurrence_Max_Occurrences__c = 1
            );
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.processDueSeries(10);
            FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        Needs_Offers__c parent = [
            SELECT Series_Ended__c FROM Needs_Offers__c WHERE Id = :parentId
        ];
        System.assertEquals(true, parent.Series_Ended__c);
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId]);
    }

    @isTest
    static void testEndOnDatePreventsSpawn() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> payload = recurringEventPayload();
            payload.put('recurrenceEndMode', 'On_Date');
            payload.put('recurrenceEndDate', String.valueOf(Date.today().addDays(-1)));
            payload.put('recurrenceMaxOccurrences', null);
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(
                Id = parentId,
                Next_Occurrence_Date__c = Date.today()
            );
        }

        Test.startTest();
        Integer spawned;
        System.runAs(testUser) {
            spawned = FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        System.assertEquals(0, spawned);
        Needs_Offers__c parent = [
            SELECT Series_Ended__c FROM Needs_Offers__c WHERE Id = :parentId
        ];
        System.assertEquals(true, parent.Series_Ended__c);
    }

    @isTest
    static void testGatheringSpawnPreservesCapacity() {
        User testUser = getTestUser();
        Id parentId;
        Map<String, Object> payload = recurringEventPayload();
        payload.put('eventType', 'Gathering');
        payload.put('quantity', 12);
        payload.put('recurrenceEndMode', 'Never');
        payload.put('recurrenceMaxOccurrences', null);

        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.processDueSeries(10);
        }
        Test.stopTest();

        Needs_Offers__c child = [
            SELECT Total_Quantity__c, Event_Type__c
            FROM Needs_Offers__c
            WHERE Series_Parent__c = :parentId
            LIMIT 1
        ];
        System.assertEquals('Gathering', child.Event_Type__c);
        System.assertEquals(12, child.Total_Quantity__c.intValue());
    }

    @isTest
    static void testDisableRecurrenceEndsSeries() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
        }

        Map<String, Object> updatePayload = new Map<String, Object>{
            'recordId' => parentId,
            'title' => 'No longer repeating',
            'recurrenceEnabled' => false
        };

        Test.startTest();
        System.runAs(testUser) {
            FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updatePayload));
        }
        Test.stopTest();

        Needs_Offers__c parent = [
            SELECT Series_Ended__c, Recurrence_Frequency__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals(true, parent.Series_Ended__c);
        System.assertEquals(null, parent.Recurrence_Frequency__c);
    }

    @isTest
    static void testApplyRecurrenceOnUpdateThisAndFuture() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
        }

        Map<String, Object> updatePayload = new Map<String, Object>{
            'recordId' => parentId,
            'title' => 'Updated Weekly Coffee',
            'recurrenceEnabled' => true,
            'recurrenceFrequency' => 'Month',
            'recurrenceInterval' => 1,
            'recurrenceEndMode' => 'Never',
            'recurrenceScope' => 'thisAndFuture'
        };

        Test.startTest();
        System.runAs(testUser) {
            FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updatePayload));
        }
        Test.stopTest();

        Needs_Offers__c parent = [
            SELECT Recurrence_Frequency__c, Name FROM Needs_Offers__c WHERE Id = :parentId
        ];
        System.assertEquals('Month', parent.Recurrence_Frequency__c);
        System.assertEquals('Updated Weekly Coffee', parent.Name);
    }

    @isTest
    static void testDeleteThisAndFollowingStopsSeries() {
        User testUser = getTestUser();
        Id parentId;
        Id childId;
        System.runAs(testUser) {
            Map<String, Object> payload = recurringEventPayload();
            payload.put('recurrenceEndMode', 'Never');
            payload.put('recurrenceMaxOccurrences', null);
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
            childId = [SELECT Id FROM Needs_Offers__c WHERE Series_Parent__c = :parentId LIMIT 1].Id;
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.deleteSeriesMember(childId, FimbyRecurrenceService.DELETE_THIS_AND_FOLLOWING);
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :childId]);
        Needs_Offers__c parent = [
            SELECT Series_Ended__c, Recurrence_Frequency__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        System.assertEquals(true, parent.Series_Ended__c);
        System.assertEquals(null, parent.Recurrence_Frequency__c);
    }

    @isTest
    static void testDeleteOnlySeriesParentWithNoChildren() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.deleteSeriesMember(parentId, FimbyRecurrenceService.DELETE_THIS_EVENT);
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :parentId]);
    }

    @isTest
    static void testEditChildOccurrenceThisOnlyKeepsParentRule() {
        User testUser = getTestUser();
        Id parentId;
        Id childId;
        System.runAs(testUser) {
            Map<String, Object> payload = recurringEventPayload();
            payload.put('recurrenceEndMode', 'Never');
            payload.put('recurrenceMaxOccurrences', null);
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(payload));
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
            childId = [SELECT Id FROM Needs_Offers__c WHERE Series_Parent__c = :parentId LIMIT 1].Id;
        }

        Map<String, Object> updatePayload = new Map<String, Object>{
            'recordId' => childId,
            'title' => 'One-off title tweak',
            'recurrenceEnabled' => true,
            'recurrenceFrequency' => 'Month',
            'recurrenceInterval' => 2,
            'recurrenceEndMode' => 'Never',
            'recurrenceScope' => 'thisOnly'
        };

        Test.startTest();
        System.runAs(testUser) {
            FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updatePayload));
        }
        Test.stopTest();

        Needs_Offers__c parent = [
            SELECT Recurrence_Frequency__c, Recurrence_Interval__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
        ];
        Needs_Offers__c child = [
            SELECT Recurrence_Frequency__c, Name
            FROM Needs_Offers__c
            WHERE Id = :childId
        ];
        System.assertEquals('Week', parent.Recurrence_Frequency__c);
        System.assertEquals(1, parent.Recurrence_Interval__c.intValue());
        System.assertEquals('Month', child.Recurrence_Frequency__c);
        System.assertEquals('One-off title tweak', child.Name);
    }

    @isTest
    static void testComputeNextSpawnDateWeekInterval() {
        Date base = Date.newInstance(2026, 6, 1);
        Date next = FimbyRecurrenceService.computeNextSpawnDate(base, 'Week', 2);
        System.assertEquals(base.addDays(14), next);
        System.assertEquals(true, FimbyRecurrenceService.isSeriesMember(
            new Needs_Offers__c(Recurrence_Frequency__c = 'Week')
        ));
        System.assertEquals(false, FimbyRecurrenceService.isSeriesMember(
            new Needs_Offers__c(Series_Parent__c = null, Recurrence_Frequency__c = null)
        ));
        Id fakeParent = 'a0y000000000001AAA';
        System.assertEquals(
            fakeParent,
            FimbyRecurrenceService.resolveSeriesParentId(
                new Needs_Offers__c(Id = fakeParent, Series_Parent__c = null)
            )
        );
    }

    @isTest
    static void testDeleteThisAndFollowingFromParentDeletesAll() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.deleteSeriesMember(
                parentId,
                FimbyRecurrenceService.DELETE_THIS_AND_FOLLOWING
            );
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :parentId]);
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId]);
    }

    @isTest
    static void testDeleteAllEventsRemovesSeries() {
        User testUser = getTestUser();
        Id parentId;
        System.runAs(testUser) {
            Map<String, Object> result = FimbyAskOfferController.createNeedsOffersPost(
                JSON.serialize(recurringEventPayload())
            );
            parentId = (String) result.get('recordId');
            update new Needs_Offers__c(Id = parentId, Next_Occurrence_Date__c = Date.today());
            FimbyRecurrenceService.processDueSeries(10);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyRecurrenceService.deleteSeriesMember(parentId, FimbyRecurrenceService.DELETE_ALL_EVENTS);
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :parentId]);
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Series_Parent__c = :parentId]);
    }

    @isTest
    static void testCopyTemplateFieldsNullGuards() {
        FimbyRecurrenceService.copyTemplateFieldsToOccurrence(null, null);
        FimbyRecurrenceService.copyTemplateFieldsToOccurrence(
            new Needs_Offers__c(Name = 'Parent'),
            null
        );
        System.assertEquals(null, FimbyRecurrenceService.resolveSeriesParentId(null));
    }
}
