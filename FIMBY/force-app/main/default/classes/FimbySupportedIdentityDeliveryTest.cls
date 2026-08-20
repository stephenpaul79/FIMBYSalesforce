/**
 * @description Coverage for FimbySupportedIdentityDelivery — the resolver that lets a
 * notification on a login-less Contact reach the neighbours approved to act for them.
 *
 * The pure functions (aggregation, ledger round-trip, target assembly, deep links) are
 * asserted directly because they encode the rules that decide whether an alert is
 * retried, dropped, or delivered twice.
 */
@IsTest
private class FimbySupportedIdentityDeliveryTest {

    private static final String PENDING       = FimbySupportedIdentityDelivery.PENDING;
    private static final String PENDING_QUIET = FimbySupportedIdentityDelivery.PENDING_QUIET;
    private static final String PROCESSING    = FimbySupportedIdentityDelivery.PROCESSING;
    private static final String SENT          = FimbySupportedIdentityDelivery.SENT;
    private static final String FAILED        = FimbySupportedIdentityDelivery.FAILED;
    private static final String SUPPRESSED    = FimbySupportedIdentityDelivery.SUPPRESSED;
    private static final String PARTIAL       = FimbySupportedIdentityDelivery.PARTIAL;

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact helper = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(helper.Id, null, true);
    }

    private static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
    }

    private static User getHelperUser() {
        return [SELECT Id, ContactId FROM User WHERE ContactId != null AND IsActive = true LIMIT 1];
    }

    /* =================================================================
     * Aggregation — the rule that keeps retries alive
     * ================================================================= */

    /**
     * Outstanding work must win, because the aggregate is what the batch jobs poll on.
     * If one delivered recipient could flatten the row to Sent, the neighbour who was
     * not reached would never be retried.
     */
    @IsTest
    static void aggregateKeepsRowQueuedWhileAnyRecipientIsOutstanding() {
        System.assertEquals(PENDING,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, PENDING }),
            'A single outstanding recipient must keep the whole row Pending');

        System.assertEquals(PENDING,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ PENDING_QUIET, PENDING }),
            'Audible outstanding work outranks a quiet refresh');

        System.assertEquals(PENDING_QUIET,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, PENDING_QUIET }),
            'A pending quiet refresh still counts as outstanding');

        System.assertEquals(PROCESSING,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, PROCESSING }),
            'An in-flight email claim is outstanding');
    }

    @IsTest
    static void aggregateReportsTerminalOutcomesHonestly() {
        System.assertEquals(SENT,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, SENT }),
            'Everyone reached is Sent');

        System.assertEquals(FAILED,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ FAILED, FAILED }),
            'Nobody reached is Failed');

        System.assertEquals(PARTIAL,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, FAILED }),
            'Some reached and some not is Partial, not a flattened Sent');

        System.assertEquals(PARTIAL,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SENT, SUPPRESSED }),
            'A suppressed recipient alongside a delivered one is still Partial');

        System.assertEquals(SUPPRESSED,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ SUPPRESSED }),
            'Everyone opted out is Suppressed');

        System.assertEquals(null,
            FimbySupportedIdentityDelivery.aggregate(new List<String>{ null, null }),
            'No eligible channel state means the channel stays null');

        System.assertEquals(null,
            FimbySupportedIdentityDelivery.aggregate(new List<String>()),
            'An empty state list is not an error');
    }

    /* =================================================================
     * Ledger
     * ================================================================= */

    @IsTest
    static void ledgerSurvivesARoundTripThroughJson() {
        Id supporteeId = getHelperUser().ContactId;
        Id userA = getHelperUser().Id;
        Id userB = UserInfo.getUserId();

        FimbySupportedIdentityDelivery.Ledger ledger =
            new FimbySupportedIdentityDelivery.Ledger(supporteeId);
        // Deliberately mixed per channel: push still has outstanding work while email
        // has already finished with one delivered and one opted out.
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(userA, PENDING, SENT));
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(userB, SENT, SUPPRESSED));

        String raw = FimbySupportedIdentityDelivery.serializeLedger(ledger);
        System.assertNotEquals(null, raw, 'A populated ledger must serialize');

        FimbySupportedIdentityDelivery.Ledger reloaded =
            FimbySupportedIdentityDelivery.parseLedger(raw);

        System.assertNotEquals(null, reloaded, 'Round trip must return a ledger');
        System.assertEquals(String.valueOf(supporteeId), reloaded.s,
            'The supportee the row belongs to must survive');
        System.assertEquals(2, reloaded.r.size(), 'Both recipients must survive');
        System.assertEquals(new Set<Id>{ userA, userB }, reloaded.userIds());

        System.assertEquals(PENDING, reloaded.forUser(userA).p);
        System.assertEquals(SUPPRESSED, reloaded.forUser(userB).e);
        System.assertEquals(null, reloaded.forUser(supporteeId),
            'A user not in the ledger must resolve to null, not throw');

        System.assertEquals(PENDING, reloaded.pushAggregate(),
            'One pending recipient keeps the push aggregate queued');
        System.assertEquals(PARTIAL, reloaded.emailAggregate(),
            'Sent alongside Suppressed is a Partial email outcome');
    }

    @IsTest
    static void serializeReturnsNullWhenThereIsNothingToRecord() {
        System.assertEquals(null,
            FimbySupportedIdentityDelivery.serializeLedger(null),
            'A null ledger writes no JSON');
        System.assertEquals(null,
            FimbySupportedIdentityDelivery.serializeLedger(
                new FimbySupportedIdentityDelivery.Ledger(getHelperUser().ContactId)),
            'A ledger with no recipients writes no JSON rather than an empty shell');
    }

    /**
     * An unreadable ledger must never throw. These run inside batch jobs, where one
     * bad row would otherwise strand every other notification in the cycle.
     */
    @IsTest
    static void parseLedgerFailsSoftOnAnythingUnreadable() {
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger(null));
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger(''));
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger('not json at all'));
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger('[1,2,3]'),
            'A JSON array is the wrong shape and must be refused, not throw');
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger('{"v":1,"r":[]}'),
            'A ledger with no recipients is equivalent to no ledger');
        System.assertEquals(null, FimbySupportedIdentityDelivery.parseLedger('{"v":1,"r":[{"p":"Sent"}]}'),
            'A recipient with no user Id carries no delivery meaning');

        FimbySupportedIdentityDelivery.Ledger forwardCompatible =
            FimbySupportedIdentityDelivery.parseLedger(
                '{"v":99,"s":"003xxx","r":[{"u":"' + UserInfo.getUserId()
                + '","p":"Sent","somethingNew":true}],"futureKey":"ignored"}');
        System.assertNotEquals(null, forwardCompatible,
            'Unknown keys from a future ledger version must be ignored, not fatal');
        System.assertEquals(1, forwardCompatible.r.size());

        FimbySupportedIdentityDelivery.Ledger badId =
            FimbySupportedIdentityDelivery.parseLedger('{"v":1,"r":[{"u":"not-an-id","p":"Sent"}]}');
        System.assertNotEquals(null, badId, 'A malformed Id is kept as a row but yields no Id');
        System.assertEquals(0, badId.userIds().size(),
            'An unparseable user Id must be skipped rather than stranding the row');
    }

    /* =================================================================
     * Helper resolution
     * ================================================================= */

    @IsTest
    static void resolvesOnlyApprovedContactBackedHelpers() {
        User helperUser = getHelperUser();
        Account nh = getNeighbourhood();

        Contact supportee = new Contact(
            FirstName = 'Rosa', LastName = 'Supportee', AccountId = nh.Id);
        Contact otherSupportee = new Contact(
            FirstName = 'Joan', LastName = 'Pending', AccountId = nh.Id);
        insert new List<Contact>{ supportee, otherSupportee };

        insert new List<Support_Relationship__c>{
            new Support_Relationship__c(
                Contact__c = helperUser.ContactId,
                Related_Contact__c = supportee.Id,
                Relationship_Type__c = 'Support_Person',
                Status__c = 'Approved',
                Neighbourhood__c = nh.Id,
                Consent_Method__c = 'Written'
            ),
            new Support_Relationship__c(
                Contact__c = helperUser.ContactId,
                Related_Contact__c = otherSupportee.Id,
                Relationship_Type__c = 'Support_Person',
                Status__c = 'Draft',
                Neighbourhood__c = nh.Id,
                Consent_Method__c = 'Written'
            )
        };

        Test.startTest();
        Map<Id, Set<Id>> helpers = FimbySupportedIdentityDelivery.resolveHelperContacts(
            new Set<Id>{ supportee.Id, otherSupportee.Id });
        Test.stopTest();

        System.assert(helpers.containsKey(supportee.Id),
            'An approved relationship must resolve a delivery helper');
        System.assertEquals(new Set<Id>{ helperUser.ContactId }, helpers.get(supportee.Id));
        System.assert(!helpers.containsKey(otherSupportee.Id),
            'A Draft relationship confers no delivery mandate');
    }

    @IsTest
    static void resolveHelperContactsHandlesEmptyInput() {
        Test.startTest();
        System.assertEquals(0,
            FimbySupportedIdentityDelivery.resolveHelperContacts(null).size(),
            'Null input must not query or throw');
        System.assertEquals(0,
            FimbySupportedIdentityDelivery.resolveHelperContacts(new Set<Id>()).size(),
            'Empty input must not query or throw');
        Test.stopTest();
    }

    /**
     * Community group reps hold their mandate against the organization Account, so the
     * bridge back to the org's Contact runs through Organization_Account__c.
     */
    @IsTest
    static void resolvesOrganizationBackedRepresentatives() {
        User helperUser = getHelperUser();
        Account nh = getNeighbourhood();

        Account org = new Account(
            Name = 'Test Community Group',
            RecordTypeId = [SELECT Id FROM RecordType
                            WHERE SObjectType = 'Account'
                              AND DeveloperName = 'Organization' LIMIT 1].Id
        );
        insert org;

        Contact orgContact = new Contact(
            FirstName = 'Group', LastName = 'Contact', AccountId = nh.Id,
            Is_Organization_Contact__c = true, Organization_Account__c = org.Id);
        insert orgContact;

        insert new Support_Relationship__c(
            Contact__c = helperUser.ContactId,
            Related_Organization__c = org.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );

        Test.startTest();
        Map<Id, Set<Id>> helpers = FimbySupportedIdentityDelivery.resolveHelperContacts(
            new Set<Id>{ orgContact.Id });
        Test.stopTest();

        System.assert(helpers.containsKey(orgContact.Id),
            'An org contact must resolve its approved representatives');
        System.assertEquals(new Set<Id>{ helperUser.ContactId }, helpers.get(orgContact.Id));
    }

    /* =================================================================
     * Target assembly
     * ================================================================= */

    @IsTest
    static void unbackedContactsFindsTheContactsWithNoLogin() {
        Id withLogin = getHelperUser().ContactId;
        Id withoutLogin = UserInfo.getUserId();

        Set<Id> unbacked = FimbySupportedIdentityDelivery.unbackedContacts(
            new Set<Id>{ withLogin, withoutLogin, null },
            new Map<Id, User>{ withLogin => getHelperUser() }
        );

        System.assertEquals(new Set<Id>{ withoutLogin }, unbacked,
            'Only the Contact with no active User needs a helper fan-out');
        System.assertEquals(0,
            FimbySupportedIdentityDelivery.unbackedContacts(null, null).size(),
            'Null input is not an error');
    }

    @IsTest
    static void ownLoginAlwaysWinsOverHelperFanOut() {
        User own = getHelperUser();
        Id inbox = own.ContactId;

        Map<Id, List<FimbySupportedIdentityDelivery.Target>> targets =
            FimbySupportedIdentityDelivery.buildTargets(
                new Set<Id>{ inbox },
                new Map<Id, User>{ inbox => own },
                new Map<Id, Set<Id>>{ inbox => new Set<Id>{ UserInfo.getUserId() } },
                new Map<Id, User>{ UserInfo.getUserId() => new User(Id = UserInfo.getUserId()) }
            );

        System.assertEquals(1, targets.get(inbox).size(),
            'A Contact who can log in receives their own notifications and nobody else does');
        System.assertEquals(own.Id, targets.get(inbox)[0].userId());
        System.assertEquals(false, targets.get(inbox)[0].isProxy,
            'Delivery to the Contact themselves is not a proxy delivery');
    }

    @IsTest
    static void fansOutToEveryHelperAndDedupesSharedLogins() {
        User helperUser = getHelperUser();
        Id inbox = UserInfo.getUserId();
        Id helperContactA = helperUser.ContactId;
        Id helperContactB = inbox;

        // Both helper Contacts intentionally resolve to the SAME User, which is how a
        // duplicate relationship would otherwise double-ping one person's device.
        Map<Id, List<FimbySupportedIdentityDelivery.Target>> deduped =
            FimbySupportedIdentityDelivery.buildTargets(
                new Set<Id>{ inbox },
                new Map<Id, User>(),
                new Map<Id, Set<Id>>{ inbox => new Set<Id>{ helperContactA, helperContactB } },
                new Map<Id, User>{
                    helperContactA => helperUser,
                    helperContactB => helperUser
                }
            );

        System.assertEquals(1, deduped.get(inbox).size(),
            'Two mandates held by one login must produce one delivery, not two');
        System.assertEquals(true, deduped.get(inbox)[0].isProxy,
            'Delivering to a helper is a proxy delivery');
    }

    @IsTest
    static void inboxesStayDistinctSoOneCardNeverReplacesAnother() {
        User parent = getHelperUser();
        Id childInbox = UserInfo.getUserId();
        Id ownInbox = parent.ContactId;

        Map<Id, List<FimbySupportedIdentityDelivery.Target>> targets =
            FimbySupportedIdentityDelivery.buildTargets(
                new Set<Id>{ ownInbox, childInbox },
                new Map<Id, User>{ ownInbox => parent },
                new Map<Id, Set<Id>>{ childInbox => new Set<Id>{ ownInbox } },
                new Map<Id, User>{ ownInbox => parent }
            );

        String ownKey = targets.get(ownInbox)[0].key();
        String childKey = targets.get(childInbox)[0].key();

        System.assertNotEquals(ownKey, childKey,
            'One login serving two inboxes must key them separately, or the child\'s '
            + 'push card would collapse over the parent\'s');
    }

    @IsTest
    static void buildTargetsSkipsWhatItCannotDeliverTo() {
        Id orphan = UserInfo.getUserId();

        System.assertEquals(0,
            FimbySupportedIdentityDelivery.buildTargets(
                new Set<Id>{ orphan }, new Map<Id, User>(),
                new Map<Id, Set<Id>>(), new Map<Id, User>()
            ).size(),
            'A Contact with no login and no approved helper yields no delivery target');

        System.assertEquals(0,
            FimbySupportedIdentityDelivery.buildTargets(
                null, null, null, null).size(),
            'Null input is not an error');

        System.assertEquals(0,
            FimbySupportedIdentityDelivery.buildTargets(
                new Set<Id>{ orphan }, new Map<Id, User>(),
                new Map<Id, Set<Id>>{ orphan => new Set<Id>{ orphan } },
                new Map<Id, User>()
            ).size(),
            'A helper Contact with no active User cannot receive delivery');
    }

    /* =================================================================
     * Identity-safe deep links
     * ================================================================= */

    @IsTest
    static void actingIdentityIsBakedIntoDeepLinks() {
        Id child = getHelperUser().ContactId;

        System.assertEquals('/notifications?actAs=' + child,
            FimbySupportedIdentityDelivery.withActingIdentity('/notifications', child),
            'A plain path gains the acting identity');

        System.assertEquals('/library-item?id=abc&actAs=' + child,
            FimbySupportedIdentityDelivery.withActingIdentity('/library-item?id=abc', child),
            'An existing query string is appended to, not clobbered');

        System.assertEquals('/messages?actAs=' + child + '#thread-2',
            FimbySupportedIdentityDelivery.withActingIdentity('/messages#thread-2', child),
            'A fragment must stay at the end or it swallows the parameter value');
    }

    @IsTest
    static void deepLinksAreLeftAloneWhenThereIsNothingToAdd() {
        Id child = getHelperUser().ContactId;

        System.assertEquals('/already?actAs=003xyz',
            FimbySupportedIdentityDelivery.withActingIdentity('/already?actAs=003xyz', child),
            'An explicit acting identity is never overwritten');
        System.assertEquals(null,
            FimbySupportedIdentityDelivery.withActingIdentity(null, child),
            'No URL means nothing to decorate');
        System.assertEquals('/notifications',
            FimbySupportedIdentityDelivery.withActingIdentity('/notifications', null),
            'No acting identity means the URL is untouched');
    }
}
