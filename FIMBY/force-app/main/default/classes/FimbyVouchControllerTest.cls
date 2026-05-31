/**
 * @description Coverage + behaviour tests for FimbyVouchController.
 *              Tests use System.runAs against a portal-style FIMBY community user so
 *              identity resolves correctly.
 */
@isTest
private class FimbyVouchControllerTest {

    private static Account makeNeighbourhood(String name) {
        Account a = new Account(Name = name, Active__c = 'Yes');
        insert a;
        return a;
    }

    private static Contact makeContact(String first, String last, String email, Id accountId, String vouchedStatus) {
        Contact c = new Contact(
            FirstName = first,
            LastName  = last,
            Email     = email,
            AccountId = accountId,
            Vouched_Status__c = vouchedStatus
        );
        insert c;
        return c;
    }

    private static Vouch_Record__c makeVouchRecord(Id requesterId, Id referenceId, Id neighbourhoodId, String status) {
        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = requesterId,
            Reference_Contact__c = referenceId,
            Neighbourhood__c     = neighbourhoodId,
            Status__c            = status,
            Source__c            = 'Peer',
            Requested_Date__c    = System.now()
        );
        insert vr;
        return vr;
    }

    @isTest
    static void submitVoucherDetails_is_deprecated_shim() {
        Test.startTest();
        FimbyVouchController.SubmitResult r = FimbyVouchController.submitVoucherDetails(
            'Jane Doe', 'no-such-person@example.com', null
        );
        Test.stopTest();

        // The free-text variant has been replaced; the shim always returns undelivered with
        // a clear "reload the page" message so stale clients fail loudly.
        System.assertNotEquals(null, r, 'result returned');
        System.assertEquals(false, r.delivered, 'shim never delivers');
        System.assertNotEquals(null, r.message, 'shim returns a message');
    }

    @isTest
    static void declineVouch_with_blank_reason_throws() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('R', 'One', 'r1@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref', 'One', 'ref1@example.com', hood.Id, 'Vouched');
        Vouch_Record__c vr = makeVouchRecord(requester.Id, reference.Id, hood.Id, 'Pending');

        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.declineVouch(vr.Id, null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'should require a reason');
    }

    @isTest
    static void declineVouch_other_without_details_throws() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('R', 'Two', 'r2@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref', 'Two', 'ref2@example.com', hood.Id, 'Vouched');
        Vouch_Record__c vr = makeVouchRecord(requester.Id, reference.Id, hood.Id, 'Pending');

        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.declineVouch(vr.Id, 'Other', null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Other reason requires details');
    }

    @isTest
    static void approveVouch_with_null_id_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.approveVouch(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @isTest
    static void withdrawVouchRequest_non_pending_throws() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('R', 'Three', 'r3@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref', 'Three', 'ref3@example.com', hood.Id, 'Vouched');
        Vouch_Record__c vr = makeVouchRecord(requester.Id, reference.Id, hood.Id, 'Declined');

        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.withdrawVouchRequest(vr.Id);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'cannot withdraw non-pending request');
    }

    @isTest
    static void revokeVouch_non_approved_throws() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('R', 'Four', 'r4@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref', 'Four', 'ref4@example.com', hood.Id, 'Vouched');
        Vouch_Record__c vr = makeVouchRecord(requester.Id, reference.Id, hood.Id, 'Pending');

        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.revokeVouch(vr.Id, 'Safety_Trust_Concern', null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'can only revoke approved vouches');
    }

    @isTest
    static void revokeVouch_other_for_cause_without_details_throws() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('R', 'Five', 'r5@example.com', hood.Id, 'Vouched');
        Contact reference = makeContact('Ref', 'Five', 'ref5@example.com', hood.Id, 'Vouched');
        Vouch_Record__c vr = makeVouchRecord(requester.Id, reference.Id, hood.Id, 'Approved');

        Boolean thrown = false;
        Test.startTest();
        try {
            FimbyVouchController.revokeVouch(vr.Id, 'Other_For_Cause', null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'Other_For_Cause requires details');
    }

    @isTest
    static void getVouchingHistory_self_only_throws_for_other_contact() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact other = makeContact('Other', 'Person', 'other@example.com', hood.Id, 'Vouched');

        Boolean thrown = false;
        Test.startTest();
        try {
            // Passing some other contact's id (or null) when the running user has no acting identity
            FimbyVouchController.getVouchingHistory(other.Id);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, thrown, 'self-only guard');
    }

    @isTest
    static void wire_types_serializable() {
        FimbyVouchController.SubmitResult r = new FimbyVouchController.SubmitResult();
        r.delivered = true;
        r.message = 'ok';
        FimbyVouchController.VouchHistorySlot s = new FimbyVouchController.VouchHistorySlot();
        s.status = 'Approved';
        s.countsAgainst = false;
        System.assertEquals(true, r.delivered);
        System.assertEquals('Approved', s.status);
    }

    /* ==================================================================
     * Identity-aware tests using runAs against a real community user
     * ================================================================== */

    private static User makeUserWithContact(Contact c) {
        // Customer Community User is required to link User -> Contact in tests.
        return FimbyTestDataFactory.createCommunityUser(c.Id, 'Customer Community User - Mobile App', true);
    }

    @isTest
    static void approveVouch_full_lifecycle() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Req', 'Ester', 'req@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref', 'Erence', 'refer@example.com', hood.Id, 'Vouched');

        // Create the conversation that the controller would have created.
        Conversation__c conv = new Conversation__c(
            Participant_1__c = requester.Id,
            Participant_2__c = reference.Id,
            Context_Type__c = 'Vouch_Request',
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert conv;

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = requester.Id,
            Reference_Contact__c = reference.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Conversation__c = conv.Id,
            Requested_Date__c = System.now()
        );
        insert vr;

        User refUser = null;
        // Need a User whose ContactId is the reference, so isActingAsSelf = reference.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            refUser = makeUserWithContact(reference);
        }

        Test.startTest();
        System.runAs(refUser) {
            FimbyVouchController.approveVouch(vr.Id);
        }
        Test.stopTest();

        Vouch_Record__c after = [
            SELECT Status__c, Decided_Date__c FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertEquals('Approved', after.Status__c, 'should be approved');
        System.assertNotEquals(null, after.Decided_Date__c, 'decided date set');

        Contact afterReq = [SELECT Vouched_Status__c, Vouched_By_Contact__c, Vouched_Date__c FROM Contact WHERE Id = :requester.Id];
        System.assertEquals('Vouched', afterReq.Vouched_Status__c, 'vouchee marked Vouched');
        System.assertEquals(reference.Id, afterReq.Vouched_By_Contact__c, 'voucher cached');
        System.assertNotEquals(null, afterReq.Vouched_Date__c, 'vouched date set');

        Conversation__c afterConv = [SELECT Locked__c, Vouch_Outcome__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(true, afterConv.Locked__c, 'conversation locked');
        System.assertEquals('Approved', afterConv.Vouch_Outcome__c, 'outcome set');
    }

    @isTest
    static void declineVouch_with_concerning_reason_flags_signal() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Req2', 'Ester', 'req2@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Ref2', 'Erence', 'refer2@example.com', hood.Id, 'Vouched');

        Conversation__c conv = new Conversation__c(
            Participant_1__c = requester.Id,
            Participant_2__c = reference.Id,
            Context_Type__c = 'Vouch_Request',
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert conv;

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = requester.Id,
            Reference_Contact__c = reference.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Conversation__c = conv.Id,
            Requested_Date__c = System.now()
        );
        insert vr;

        User refUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            refUser = makeUserWithContact(reference);
        }

        Test.startTest();
        System.runAs(refUser) {
            FimbyVouchController.declineVouch(vr.Id, 'Concerning_Request', null);
        }
        Test.stopTest();

        Vouch_Record__c after = [
            SELECT Status__c, Decision_Reason__c, Counts_Toward_Requester_Signal__c
            FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertEquals('Declined', after.Status__c);
        System.assertEquals('Concerning_Request', after.Decision_Reason__c);
        System.assertEquals(true, after.Counts_Toward_Requester_Signal__c, 'concerning declines count');

        Contact afterReq = [SELECT Vouched_Status__c FROM Contact WHERE Id = :requester.Id];
        System.assertEquals('New', afterReq.Vouched_Status__c, 'requester back to settling-in');
    }

    @isTest
    static void withdrawVouchRequest_by_requester_succeeds() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Reqw', 'Ester', 'reqw@example.com', hood.Id, 'Vouch_Requested');
        Contact reference = makeContact('Refw', 'Erence', 'referw@example.com', hood.Id, 'Vouched');

        Conversation__c conv = new Conversation__c(
            Participant_1__c = requester.Id,
            Participant_2__c = reference.Id,
            Context_Type__c = 'Vouch_Request',
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert conv;

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = requester.Id,
            Reference_Contact__c = reference.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Conversation__c = conv.Id,
            Requested_Date__c = System.now()
        );
        insert vr;

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        System.runAs(reqUser) {
            FimbyVouchController.withdrawVouchRequest(vr.Id);
        }
        Test.stopTest();

        Vouch_Record__c after = [SELECT Status__c FROM Vouch_Record__c WHERE Id = :vr.Id];
        System.assertEquals('Withdrawn', after.Status__c);
    }

    @isTest
    static void revokeVouch_for_cause_resets_vouchee_and_counts() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact vouchee = makeContact('Voi', 'Chee', 'vchee@example.com', hood.Id, 'Vouched');
        Contact voucher = makeContact('Vou', 'Cher', 'vcher@example.com', hood.Id, 'Vouched');

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = vouchee.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Approved',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-5),
            Decided_Date__c = System.now().addDays(-4)
        );
        insert vr;

        Test.startTest();
        FimbyVouchController.revokeVouch(vr.Id, 'Safety_Trust_Concern', 'detail');
        Test.stopTest();

        Vouch_Record__c after = [
            SELECT Status__c, Revocation_Category__c, Counts_Toward_Voucher_Pause__c, Revoked_Date__c
            FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertEquals('Revoked', after.Status__c);
        System.assertEquals(true, after.Counts_Toward_Voucher_Pause__c, 'safety concern counts');
        System.assertNotEquals(null, after.Revoked_Date__c);

        Contact afterVouchee = [SELECT Vouched_Status__c, Vouched_By_Contact__c FROM Contact WHERE Id = :vouchee.Id];
        System.assertEquals('New', afterVouchee.Vouched_Status__c, 'vouchee reset');
        System.assertEquals(null, afterVouchee.Vouched_By_Contact__c, 'voucher cache cleared');
    }

    @isTest
    static void revokeVouch_admin_correction_does_not_count() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact vouchee = makeContact('Adm', 'Vouchee', 'adm@example.com', hood.Id, 'Vouched');
        Contact voucher = makeContact('Adm', 'Voucher', 'admv@example.com', hood.Id, 'Vouched');

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = vouchee.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Approved',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-2),
            Decided_Date__c = System.now().addDays(-1)
        );
        insert vr;

        Test.startTest();
        FimbyVouchController.revokeVouch(vr.Id, 'Admin_Correction', null);
        Test.stopTest();

        Vouch_Record__c after = [
            SELECT Counts_Toward_Voucher_Pause__c FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertEquals(false, after.Counts_Toward_Voucher_Pause__c, 'admin correction does not count');
    }

    @isTest
    static void overrideVouch_creates_record_and_marks_vouched() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact moderator = makeContact('Mod', 'Erator', 'mod@example.com', hood.Id, 'Vouched');
        Contact settling = makeContact('Set', 'Tling', 'set@example.com', hood.Id, 'New');

        User modUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            modUser = makeUserWithContact(moderator);
        }

        Test.startTest();
        Id vrId = null;
        System.runAs(modUser) {
            vrId = FimbyVouchController.overrideVouch(settling.Id);
        }
        Test.stopTest();

        Vouch_Record__c vr = [
            SELECT Status__c, Source__c, Requester_Contact__c, Reference_Contact__c
            FROM Vouch_Record__c WHERE Id = :vrId
        ];
        System.assertEquals('Approved', vr.Status__c);
        System.assertEquals('Moderator_Override', vr.Source__c);
        System.assertEquals(settling.Id, vr.Requester_Contact__c);
        System.assertEquals(moderator.Id, vr.Reference_Contact__c);

        Contact afterVouchee = [SELECT Vouched_Status__c, Vouched_By_Moderator__c FROM Contact WHERE Id = :settling.Id];
        System.assertEquals('Vouched', afterVouchee.Vouched_Status__c);
        System.assertEquals(true, afterVouchee.Vouched_By_Moderator__c);
    }

    /* ==================================================================
     * searchVouchers (typeahead) tests
     * ================================================================== */

    @isTest
    static void searchVouchers_min_chars_returns_empty() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Tip', 'Searcher', 'tip@example.com', hood.Id, 'New');

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        List<FimbyVouchController.VoucherOption> oneChar = null;
        List<FimbyVouchController.VoucherOption> emptyTerm = null;
        System.runAs(reqUser) {
            oneChar = FimbyVouchController.searchVouchers('a', 'peer');
            emptyTerm = FimbyVouchController.searchVouchers('', 'peer');
        }
        Test.stopTest();

        System.assertEquals(0, oneChar.size(), 'single character should not search');
        System.assertEquals(0, emptyTerm.size(), 'empty string should not search');
    }

    @isTest
    static void searchVouchers_peer_excludes_self_and_unvouched_and_disabled() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Sea', 'Requester', 'searchreq@example.com', hood.Id, 'New');
        Contact vouchedNeighbour = makeContact('Sea', 'Vouched', 'searchv@example.com', hood.Id, 'Vouched');
        Contact settlingNeighbour = makeContact('Sea', 'Settling', 'searchs@example.com', hood.Id, 'New');
        Contact pendingNeighbour = makeContact('Sea', 'Pending', 'searchp@example.com', hood.Id, 'Vouch_Requested');
        Contact pausedVoucher = makeContact('Sea', 'Paused', 'searchpause@example.com', hood.Id, 'Vouched');
        pausedVoucher.Vouching_Disabled__c = true;
        update pausedVoucher;

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        List<FimbyVouchController.VoucherOption> results = null;
        System.runAs(reqUser) {
            results = FimbyVouchController.searchVouchers('Sea', 'peer');
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (FimbyVouchController.VoucherOption opt : results) returnedIds.add(opt.id);

        System.assert(returnedIds.contains(vouchedNeighbour.Id), 'vouched neighbour should be found');
        System.assert(!returnedIds.contains(requester.Id), 'self excluded');
        System.assert(!returnedIds.contains(settlingNeighbour.Id), 'settling-in excluded');
        System.assert(!returnedIds.contains(pendingNeighbour.Id), 'vouch-requested excluded');
        System.assert(!returnedIds.contains(pausedVoucher.Id), 'paused voucher excluded');
    }

    @isTest
    static void searchVouchers_peer_excludes_other_neighbourhood() {
        Account hood = makeNeighbourhood('Strathcona');
        Account otherHood = makeNeighbourhood('Mount Pleasant');
        Contact requester = makeContact('Hood', 'Requester', 'hoodreq@example.com', hood.Id, 'New');
        Contact sameHood = makeContact('Hood', 'Same', 'hoodsame@example.com', hood.Id, 'Vouched');
        Contact otherHoodContact = makeContact('Hood', 'Other', 'hoodother@example.com', otherHood.Id, 'Vouched');

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        List<FimbyVouchController.VoucherOption> results = null;
        System.runAs(reqUser) {
            results = FimbyVouchController.searchVouchers('Hood', 'peer');
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (FimbyVouchController.VoucherOption opt : results) returnedIds.add(opt.id);
        System.assert(returnedIds.contains(sameHood.Id), 'same-neighbourhood result found');
        System.assert(!returnedIds.contains(otherHoodContact.Id), 'cross-neighbourhood contact excluded');
    }

    @isTest
    static void searchVouchers_peer_excludes_blocked_both_directions() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Blk', 'Requester', 'blkreq@example.com', hood.Id, 'New');
        Contact blockedByRequester = makeContact('Blk', 'Blocked', 'blkblk@example.com', hood.Id, 'Vouched');
        Contact blockerOfRequester = makeContact('Blk', 'Blocker', 'blkblr@example.com', hood.Id, 'Vouched');
        Contact unrelated = makeContact('Blk', 'Free', 'blkfree@example.com', hood.Id, 'Vouched');

        insert new Blocked_Contact__c(Blocker__c = requester.Id, Blocked__c = blockedByRequester.Id);
        insert new Blocked_Contact__c(Blocker__c = blockerOfRequester.Id, Blocked__c = requester.Id);

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        List<FimbyVouchController.VoucherOption> results = null;
        System.runAs(reqUser) {
            results = FimbyVouchController.searchVouchers('Blk', 'peer');
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (FimbyVouchController.VoucherOption opt : results) returnedIds.add(opt.id);
        System.assert(returnedIds.contains(unrelated.Id), 'unrelated vouched contact still returned');
        System.assert(!returnedIds.contains(blockedByRequester.Id), 'blocked-by-requester excluded');
        System.assert(!returnedIds.contains(blockerOfRequester.Id), 'blocker-of-requester excluded (bidirectional)');
    }

    @isTest
    static void searchVouchers_community_group_returns_only_eligible_orgs() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Cg', 'Requester', 'cgreq@example.com', hood.Id, 'New');

        Account eligibleOrg = new Account(
            Name = 'Cg Church Eligible',
            Active__c = 'Yes',
            Is_Approved_Community_Group__c = true
        );
        insert eligibleOrg;
        insert new Community_Group_Neighbourhood__c(
            Organization__c = eligibleOrg.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Active'
        );
        // Approved Community_Group_Rep is required — without it, no rep contact to route to.
        Contact rep = makeContact('Cg', 'Rep', 'cgrep@example.com', hood.Id, 'Vouched');
        insert new Support_Relationship__c(
            Contact__c = rep.Id,
            Related_Organization__c = eligibleOrg.Id,
            Neighbourhood__c = hood.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved'
        );

        // Same neighbourhood + approved, but no rep — should be excluded.
        Account orgWithoutRep = new Account(
            Name = 'Cg Church NoRep',
            Active__c = 'Yes',
            Is_Approved_Community_Group__c = true
        );
        insert orgWithoutRep;
        insert new Community_Group_Neighbourhood__c(
            Organization__c = orgWithoutRep.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Active'
        );

        // Not approved as a community group — should be excluded.
        Account unapprovedOrg = new Account(
            Name = 'Cg Group Unapproved',
            Active__c = 'Yes',
            Is_Approved_Community_Group__c = false
        );
        insert unapprovedOrg;
        insert new Community_Group_Neighbourhood__c(
            Organization__c = unapprovedOrg.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Active'
        );

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        List<FimbyVouchController.VoucherOption> results = null;
        System.runAs(reqUser) {
            results = FimbyVouchController.searchVouchers('Cg', 'community_group');
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (FimbyVouchController.VoucherOption opt : results) returnedIds.add(opt.id);
        System.assertEquals(1, results.size(), 'only the eligible org should be returned');
        System.assert(returnedIds.contains(eligibleOrg.Id), 'eligible org present');
        System.assert(!returnedIds.contains(orgWithoutRep.Id), 'org without rep excluded');
        System.assert(!returnedIds.contains(unapprovedOrg.Id), 'unapproved org excluded');
    }

    /* ==================================================================
     * submitVoucherRequest tests
     * ================================================================== */

    @isTest
    static void submitVoucherRequest_peer_happy_path_creates_records() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Sub', 'Mit', 'submit@example.com', hood.Id, 'New');
        Contact peer = makeContact('Sub', 'Voucher', 'subv@example.com', hood.Id, 'Vouched');

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult result = null;
        System.runAs(reqUser) {
            result = FimbyVouchController.submitVoucherRequest('peer', peer.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.delivered, 'peer submit should deliver');
        System.assertNotEquals(null, result.vouchRecordId, 'vouch record id returned');

        Vouch_Record__c vr = [
            SELECT Requester_Contact__c, Reference_Contact__c, Status__c, Source__c
            FROM Vouch_Record__c WHERE Id = :result.vouchRecordId
        ];
        System.assertEquals(requester.Id, vr.Requester_Contact__c);
        System.assertEquals(peer.Id, vr.Reference_Contact__c);
        System.assertEquals('Pending', vr.Status__c);
        System.assertEquals('Peer', vr.Source__c);
    }

    @isTest
    static void submitVoucherRequest_community_group_resolves_rep_and_creates_records() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Cg', 'Submitter', 'cgsub@example.com', hood.Id, 'New');
        Contact rep = makeContact('Cg', 'Rep2', 'cgrep2@example.com', hood.Id, 'Vouched');

        Account org = new Account(
            Name = 'Cg Submit Org',
            Active__c = 'Yes',
            Is_Approved_Community_Group__c = true
        );
        insert org;
        insert new Community_Group_Neighbourhood__c(
            Organization__c = org.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Active'
        );
        insert new Support_Relationship__c(
            Contact__c = rep.Id,
            Related_Organization__c = org.Id,
            Neighbourhood__c = hood.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved'
        );

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult result = null;
        System.runAs(reqUser) {
            result = FimbyVouchController.submitVoucherRequest('community_group', org.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.delivered, 'cg submit should deliver');
        Vouch_Record__c vr = [
            SELECT Reference_Contact__c, Reference_Organization__c, Source__c
            FROM Vouch_Record__c WHERE Id = :result.vouchRecordId
        ];
        System.assertEquals(rep.Id, vr.Reference_Contact__c, 'rep resolved as reference contact');
        System.assertEquals(org.Id, vr.Reference_Organization__c);
        System.assertEquals('Community_Group', vr.Source__c);
    }

    @isTest
    static void submitVoucherRequest_self_reference_rejected() {
        Account hood = makeNeighbourhood('Strathcona');
        // A vouched user attempting to vouch for themselves.
        Contact requester = makeContact('Self', 'Vouch', 'selfv@example.com', hood.Id, 'Vouched');

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult result = null;
        System.runAs(reqUser) {
            result = FimbyVouchController.submitVoucherRequest('peer', requester.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.delivered, 'self-vouch must be rejected');
    }

    @isTest
    static void submitVoucherRequest_blocked_voucher_rejected() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Bsub', 'Requester', 'bsub@example.com', hood.Id, 'New');
        Contact blockedVoucher = makeContact('Bsub', 'Voucher', 'bsubv@example.com', hood.Id, 'Vouched');
        insert new Blocked_Contact__c(Blocker__c = requester.Id, Blocked__c = blockedVoucher.Id);

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult result = null;
        System.runAs(reqUser) {
            result = FimbyVouchController.submitVoucherRequest('peer', blockedVoucher.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.delivered, 'blocked voucher cannot be submitted');
    }

    @isTest
    static void submitVoucherRequest_already_pending_rejected() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Pend', 'Requester', 'pendr@example.com', hood.Id, 'Vouch_Requested');
        Contact peer = makeContact('Pend', 'Voucher', 'pendv@example.com', hood.Id, 'Vouched');

        insert new Vouch_Record__c(
            Requester_Contact__c = requester.Id,
            Reference_Contact__c = peer.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Requested_Date__c = System.now()
        );

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult result = null;
        System.runAs(reqUser) {
            result = FimbyVouchController.submitVoucherRequest('peer', peer.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.delivered, 'already-pending should reject');
        System.assertEquals(true, result.alreadyHasPending, 'flag set');
    }

    @isTest
    static void submitVoucherRequest_missing_inputs_returns_undelivered() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact requester = makeContact('Bad', 'Inputs', 'bad@example.com', hood.Id, 'New');

        User reqUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            reqUser = makeUserWithContact(requester);
        }

        Test.startTest();
        FimbyVouchController.SubmitResult noType = null;
        FimbyVouchController.SubmitResult noId = null;
        System.runAs(reqUser) {
            noType = FimbyVouchController.submitVoucherRequest(null, requester.Id);
            noId = FimbyVouchController.submitVoucherRequest('peer', null);
        }
        Test.stopTest();

        System.assertEquals(false, noType.delivered, 'missing type rejected');
        System.assertEquals(false, noId.delivered, 'missing id rejected');
    }

    @isTest
    static void revokeVouch_below_threshold_does_not_pause_voucher() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact vouchee = makeContact('Be', 'Low', 'below@example.com', hood.Id, 'Vouched');
        Contact voucher = makeContact('Vou', 'Cher', 'belowv@example.com', hood.Id, 'Vouched');

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = vouchee.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Approved',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-5),
            Decided_Date__c = System.now().addDays(-4)
        );
        insert vr;

        Test.startTest();
        FimbyVouchController.revokeVouch(vr.Id, 'Safety_Trust_Concern', null);
        Test.stopTest();

        // Threshold default is 2 — a single counting revoke shouldn't auto-pause.
        Contact afterVoucher = [SELECT Vouching_Disabled__c FROM Contact WHERE Id = :voucher.Id];
        System.assertEquals(false, afterVoucher.Vouching_Disabled__c, 'one revoke is below threshold');
    }

    @isTest
    static void revokeVouch_at_threshold_pauses_voucher() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact voucher = makeContact('Th', 'Reshold', 'thresh@example.com', hood.Id, 'Vouched');
        Contact vouchee1 = makeContact('Th', 'One', 'thone@example.com', hood.Id, 'Vouched');
        Contact vouchee2 = makeContact('Th', 'Two', 'thtwo@example.com', hood.Id, 'Vouched');

        // First counting revocation already on record (within window).
        insert new Vouch_Record__c(
            Requester_Contact__c = vouchee1.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Revoked',
            Source__c = 'Peer',
            Counts_Toward_Voucher_Pause__c = true,
            Revocation_Category__c = 'Theft_Or_Misuse',
            Requested_Date__c = System.now().addDays(-100),
            Decided_Date__c = System.now().addDays(-99),
            Revoked_Date__c = System.now().addDays(-10)
        );

        // The second approved vouch about to be revoked.
        Vouch_Record__c vrSecond = new Vouch_Record__c(
            Requester_Contact__c = vouchee2.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Approved',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-5),
            Decided_Date__c = System.now().addDays(-4)
        );
        insert vrSecond;

        Test.startTest();
        FimbyVouchController.revokeVouch(vrSecond.Id, 'Repeated_No_Return', null);
        Test.stopTest();

        Contact afterVoucher = [SELECT Vouching_Disabled__c, Vouching_Disabled_Reason__c FROM Contact WHERE Id = :voucher.Id];
        System.assertEquals(true, afterVoucher.Vouching_Disabled__c, 'second counting revoke triggers auto-pause');
        System.assertEquals('Auto_Threshold', afterVoucher.Vouching_Disabled_Reason__c);
    }

    @isTest
    static void reEnableVoucher_clears_disabled_flags() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact voucher = makeContact('Re', 'Enable', 'reenable@example.com', hood.Id, 'Vouched');
        voucher.Vouching_Disabled__c = true;
        voucher.Vouching_Disabled_Reason__c = 'Auto_Threshold';
        voucher.Vouching_Paused_Date__c = System.now();
        update voucher;

        Test.startTest();
        FimbyVouchController.reEnableVoucher(voucher.Id);
        Test.stopTest();

        Contact after = [SELECT Vouching_Disabled__c, Vouching_Disabled_Reason__c FROM Contact WHERE Id = :voucher.Id];
        System.assertEquals(false, after.Vouching_Disabled__c);
        System.assertEquals(null, after.Vouching_Disabled_Reason__c);
    }

    @isTest
    static void reEnableVoucher_null_id_throws() {
        Boolean thrown = false;
        Test.startTest();
        try { FimbyVouchController.reEnableVoucher(null); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown);
    }

    @isTest
    static void getVouchingContextForContact_returns_state() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact me = makeContact('Pa', 'Nel', 'panel@example.com', hood.Id, 'Vouched');
        Contact other = makeContact('Other', 'Person', 'otherpanel@example.com', hood.Id, 'Vouched');
        me.Vouched_By_Contact__c = other.Id;
        me.Vouched_Date__c = System.now();
        update me;

        Test.startTest();
        FimbyVouchController.VouchingPanelContext ctx =
            FimbyVouchController.getVouchingContextForContact(me.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'context returned');
        System.assertEquals('Vouched', ctx.vouchedStatus);
        System.assertNotEquals(null, ctx.vouchedDate);
    }

    @isTest
    static void getVouchingContextForContact_null_id_returns_null() {
        Test.startTest();
        FimbyVouchController.VouchingPanelContext ctx =
            FimbyVouchController.getVouchingContextForContact(null);
        Test.stopTest();
        System.assertEquals(null, ctx);
    }

    @isTest
    static void getVouchContextForConversation_returns_context() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact req = makeContact('Conv', 'Req', 'convreq@example.com', hood.Id, 'Vouch_Requested');
        Contact ref = makeContact('Conv', 'Ref', 'convref@example.com', hood.Id, 'Vouched');

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = req.Id,
            Reference_Contact__c = ref.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Requested_Date__c = System.now()
        );
        insert vr;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = req.Id,
            Participant_2__c = ref.Id,
            Context_Type__c = 'Vouch_Request',
            Vouch_Record__c = vr.Id,
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        FimbyVouchController.VouchConversationContext ctx =
            FimbyVouchController.getVouchContextForConversation(conv.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctx);
        System.assertEquals('Pending', ctx.outcome);
        System.assertEquals(req.Id, ctx.requesterContactId);
        System.assertEquals(ref.Id, ctx.referenceContactId);
    }

    @isTest
    static void getVouchingHistory_returns_only_self_records() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact me = makeContact('Hist', 'Self', 'hist@example.com', hood.Id, 'Vouched');

        User meUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            meUser = makeUserWithContact(me);
        }

        // Insert one approved vouch where I'm the reference.
        Contact otherRequester = makeContact('Hist', 'Other', 'histo@example.com', hood.Id, 'Vouched');
        insert new Vouch_Record__c(
            Requester_Contact__c = otherRequester.Id,
            Reference_Contact__c = me.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Approved',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-3),
            Decided_Date__c = System.now().addDays(-2)
        );

        Test.startTest();
        List<FimbyVouchController.VouchHistorySlot> slots = null;
        System.runAs(meUser) {
            slots = FimbyVouchController.getVouchingHistory(me.Id);
        }
        Test.stopTest();

        System.assertEquals(1, slots.size(), 'one approved vouch returned');
        System.assertEquals('Approved', slots[0].status);
    }

    @isTest
    static void getVouchingHistory_excludes_exempted_revokes() {
        Account hood = makeNeighbourhood('Strathcona');
        Contact me = makeContact('Exempt', 'Self', 'exempt@example.com', hood.Id, 'Vouched');

        User meUser = null;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            meUser = makeUserWithContact(me);
        }

        Contact requester1 = makeContact('Exempt', 'R1', 'exemptr1@example.com', hood.Id, 'Vouched');
        Contact requester2 = makeContact('Exempt', 'R2', 'exemptr2@example.com', hood.Id, 'Vouched');

        // Counted revoke — should appear in the strip.
        Vouch_Record__c counted = new Vouch_Record__c(
            Requester_Contact__c = requester1.Id,
            Reference_Contact__c = me.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Revoked',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-10),
            Decided_Date__c = System.now().addDays(-9),
            Revoked_Date__c = System.now().addDays(-5),
            Counts_Toward_Voucher_Pause__c = true
        );
        // Exempted revoke — should be filtered out.
        Vouch_Record__c exempted = new Vouch_Record__c(
            Requester_Contact__c = requester2.Id,
            Reference_Contact__c = me.Id,
            Neighbourhood__c = hood.Id,
            Status__c = 'Revoked',
            Source__c = 'Peer',
            Requested_Date__c = System.now().addDays(-3),
            Decided_Date__c = System.now().addDays(-2),
            Revoked_Date__c = System.now().addDays(-1),
            Counts_Toward_Voucher_Pause__c = false
        );
        insert new List<Vouch_Record__c>{ counted, exempted };

        Test.startTest();
        List<FimbyVouchController.VouchHistorySlot> slots = null;
        System.runAs(meUser) {
            slots = FimbyVouchController.getVouchingHistory(me.Id);
        }
        Test.stopTest();

        System.assertEquals(1, slots.size(), 'Only the counted revoke should be returned; exempted is hidden.');
        System.assertEquals('Revoked', slots[0].status);
        System.assertEquals(true, slots[0].countsAgainst, 'Returned record should be the counted one');
    }
}
