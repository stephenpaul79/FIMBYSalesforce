/**
 * @description Owns the vouching lifecycle: submit a vouch request, accept/decline/withdraw,
 *              revoke (moderator), and read the private voucher ledger.
 *
 * Source of truth: Vouch_Record__c. Conversation__c is created server-side so the
 * unsolicited-DM SCI restriction is bypassed only for this specific Vouch_Request
 * context; SCI still applies to every other conversation type.
 *
 * Public via @AuraEnabled to fimbyOnboardingModal step 7, fimbyVouchingRequiredModal,
 * fimbyConversationView (vouch banner), fimbyVouchDeclineModal, fimbyVouchingHistory,
 * and the moderator dashboard.
 */
public without sharing class FimbyVouchController {

    private static final String STATUS_PENDING   = 'Pending';
    private static final String STATUS_APPROVED  = 'Approved';
    private static final String STATUS_DECLINED  = 'Declined';
    private static final String STATUS_WITHDRAWN = 'Withdrawn';
    private static final String STATUS_REVOKED   = 'Revoked';

    private static final String SOURCE_PEER             = 'Peer';
    private static final String SOURCE_COMMUNITY_GROUP  = 'Community_Group';

    private static final String DECISION_OTHER          = 'Other';
    private static final String DECISION_CONCERNING     = 'Concerning_Request';

    private static final Set<String> COUNTING_REVOCATION_CATEGORIES = new Set<String>{
        'Safety_Trust_Concern',
        'Theft_Or_Misuse',
        'Repeated_No_Return',
        'Serious_Conduct_Issue',
        'Identity_Misrepresentation',
        'Other_For_Cause'
    };

    private static final Set<String> VOUCHEE_STATUS_VOUCHED  = new Set<String>{ 'Vouched' };
    private static final Set<String> VOUCHEE_STATUS_PENDING  = new Set<String>{ 'Vouch_Requested' };

    private static final String VOUCHER_TYPE_PEER             = 'peer';
    private static final String VOUCHER_TYPE_COMMUNITY_GROUP  = 'community_group';

    private static final Integer SEARCH_RESULT_LIMIT = 10;
    private static final Integer SEARCH_MIN_CHARS    = 2;

    /**
     * @description Vouching binds identity at the Contact level. Acting on behalf of another
     *              identity (Logged_In_As_Contact__c set) is not allowed for any vouch action
     *              (request/approve/decline/withdraw/revoke). Callers must switch back to their
     *              own identity before performing vouch actions.
     * @throws AuraHandledException with a user-facing message when the running user is
     *         currently acting as another identity.
     */
    private static void enforceOwnIdentityForVouching() {
        FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
        if (identity == null || identity.contact == null) {
            return;
        }
        Id realContactId = identity.contact.Id;
        Id actingAsId = identity.actingAsContactId;
        if (actingAsId != null && actingAsId != realContactId) {
            AuraHandledException ex = new AuraHandledException(
                'Vouching is tied to your own identity. Please switch back to yourself before continuing.'
            );
            ex.setMessage('Vouching is tied to your own identity. Please switch back to yourself before continuing.');
            throw ex;
        }
    }

    /* ==================================================================
     * 1. Search eligible vouchers (typeahead — fimbyVouchingRequiredModal)
     * ================================================================== */

    /**
     * @description Returns up to 10 eligible vouchers matching the search term.
     *              voucherType drives the data source:
     *                'peer'            => vouched neighbours in the same neighbourhood
     *                'community_group' => approved community groups linked to the neighbourhood
     *              All eligibility checks (block, paused, neighbourhood, etc.) run server-side.
     *              The same constraints are re-validated on submit — never trust the client.
     */
    @AuraEnabled(cacheable=true)
    public static List<VoucherOption> searchVouchers(String searchTerm, String voucherType) {
        List<VoucherOption> options = new List<VoucherOption>();

        String term = (searchTerm == null) ? '' : searchTerm.trim();
        if (term.length() < SEARCH_MIN_CHARS) {
            return options;
        }

        Id requesterContactId = FimbyIdentityRepository.getActingAsContactId();
        Id neighbourhoodId    = FimbyIdentityRepository.getNeighbourhoodId();
        if (requesterContactId == null || neighbourhoodId == null) {
            return options;
        }

        String pattern = '%' + term + '%';

        if (VOUCHER_TYPE_COMMUNITY_GROUP.equals(voucherType)) {
            return searchCommunityGroups(pattern, neighbourhoodId);
        }
        return searchPeers(pattern, neighbourhoodId, requesterContactId);
    }

    private static List<VoucherOption> searchPeers(String pattern, Id neighbourhoodId, Id requesterContactId) {
        List<VoucherOption> options = new List<VoucherOption>();
        Set<Id> excluded = blockedContactIdsBothDirections(requesterContactId);
        excluded.add(requesterContactId);

        for (Contact c : [
            SELECT Id, Name
            FROM Contact
            WHERE AccountId = :neighbourhoodId
              AND Id NOT IN :excluded
              AND Vouched_Status__c = 'Vouched'
              AND Vouching_Disabled__c != TRUE
              AND Is_Organization_Contact__c != TRUE
              AND Name LIKE :pattern
            ORDER BY Name ASC
            LIMIT :SEARCH_RESULT_LIMIT
        ]) {
            VoucherOption opt = new VoucherOption();
            opt.id = c.Id;
            opt.voucherType = VOUCHER_TYPE_PEER;
            opt.name = c.Name;
            opt.subtitle = 'Neighbour';
            options.add(opt);
        }
        return options;
    }

    private static List<VoucherOption> searchCommunityGroups(String pattern, Id neighbourhoodId) {
        List<VoucherOption> options = new List<VoucherOption>();

        // Step 1: orgs linked to this neighbourhood with an Active junction.
        Set<Id> orgIdsInHood = new Set<Id>();
        for (Community_Group_Neighbourhood__c link : [
            SELECT Organization__c
            FROM Community_Group_Neighbourhood__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c = 'Active'
        ]) {
            if (link.Organization__c != null) orgIdsInHood.add(link.Organization__c);
        }
        if (orgIdsInHood.isEmpty()) return options;

        // Step 2: orgs that have an Approved Community_Group_Rep — without one, the vouch has nowhere to route.
        Set<Id> orgIdsWithRep = new Set<Id>();
        for (Support_Relationship__c sr : [
            SELECT Related_Organization__c
            FROM Support_Relationship__c
            WHERE Related_Organization__c IN :orgIdsInHood
              AND Relationship_Type__c = 'Community_Group_Rep'
              AND Status__c = 'Approved'
        ]) {
            if (sr.Related_Organization__c != null) orgIdsWithRep.add(sr.Related_Organization__c);
        }
        if (orgIdsWithRep.isEmpty()) return options;

        // Step 3: name-match within the eligible set.
        for (Account a : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :orgIdsWithRep
              AND Active__c = 'Yes'
              AND Is_Approved_Community_Group__c = TRUE
              AND Name LIKE :pattern
            ORDER BY Name ASC
            LIMIT :SEARCH_RESULT_LIMIT
        ]) {
            VoucherOption opt = new VoucherOption();
            opt.id = a.Id;
            opt.voucherType = VOUCHER_TYPE_COMMUNITY_GROUP;
            opt.name = a.Name;
            opt.subtitle = 'Community group';
            options.add(opt);
        }
        return options;
    }

    private static Set<Id> blockedContactIdsBothDirections(Id contactId) {
        return FimbyBlockingHelper.getBidirectionalBlocks(contactId);
    }

    /* ==================================================================
     * 2. Submit a vouch request (called from onboarding step 7
     *    and from fimbyVouchingRequiredModal)
     * ================================================================== */

    /**
     * @description Submits a vouch request against a specific eligible voucher chosen
     *              from the typeahead picker. Re-validates eligibility server-side — the
     *              referenceId is never trusted on its own.
     * @param voucherType 'peer' or 'community_group'
     * @param referenceId Contact.Id (peer) or Account.Id (community group)
     */
    @AuraEnabled
    public static SubmitResult submitVoucherRequest(String voucherType, Id referenceId) {
        enforceOwnIdentityForVouching();
        SubmitResult result = new SubmitResult();

        Id requesterContactId = FimbyIdentityRepository.getActingAsContactId();
        if (requesterContactId == null) {
            result.delivered = false;
            result.message = 'You need to be signed in to request a vouch.';
            return result;
        }
        if (referenceId == null || String.isBlank(voucherType)) {
            result.delivered = false;
            result.message = 'Pick a neighbour or community group first.';
            return result;
        }

        if (hasPendingRequest(requesterContactId)) {
            result.delivered = false;
            result.alreadyHasPending = true;
            result.message = 'You already have a vouch request in flight. We will let you know when there is news.';
            return result;
        }

        Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
        Id referenceContactId = null;
        Id referenceOrgAccountId = null;

        if (VOUCHER_TYPE_COMMUNITY_GROUP.equals(voucherType)) {
            referenceOrgAccountId = validateCommunityGroup(referenceId, neighbourhoodId);
            if (referenceOrgAccountId != null) {
                referenceContactId = findCgRepContact(referenceOrgAccountId);
            }
        } else if (VOUCHER_TYPE_PEER.equals(voucherType)) {
            referenceContactId = validatePeer(referenceId, neighbourhoodId, requesterContactId);
        }

        if (referenceContactId == null) {
            result.delivered = false;
            result.message = 'That voucher is no longer available. Pick someone else.';
            return result;
        }

        Contact voucher = loadContactForVouchCheck(referenceContactId);
        if (voucher == null || voucher.Vouching_Disabled__c == true || !isVoucherAllowed(voucher)) {
            result.delivered = false;
            result.message = 'That voucher is no longer available. Pick someone else.';
            return result;
        }

        Id vouchRecordId = requestVouchInternal(requesterContactId, referenceContactId, referenceOrgAccountId, neighbourhoodId);

        result.delivered = true;
        result.vouchRecordId = vouchRecordId;
        result.message = 'Your vouch request has been sent. We will let you know when there is news.';
        return result;
    }

    /**
     * @description Deprecated free-text variant. Kept temporarily so any in-flight client
     *              that hasn't picked up the new payload fails loudly rather than creating
     *              stale records. Remove after one release cycle.
     */
    @AuraEnabled
    public static SubmitResult submitVoucherDetails(String fullName, String email, String organizationName) {
        SubmitResult result = new SubmitResult();
        result.delivered = false;
        result.message = 'Please reload the page to use the updated vouch request form.';
        return result;
    }

    /**
     * @description Re-validates a peer Contact.Id against all eligibility constraints.
     *              Returns the validated Contact.Id or null if any check fails.
     */
    private static Id validatePeer(Id contactId, Id neighbourhoodId, Id requesterContactId) {
        if (contactId == requesterContactId) return null;
        Set<Id> blocked = blockedContactIdsBothDirections(requesterContactId);
        if (blocked.contains(contactId)) return null;

        for (Contact c : [
            SELECT Id
            FROM Contact
            WHERE Id = :contactId
              AND AccountId = :neighbourhoodId
              AND Vouched_Status__c = 'Vouched'
              AND Vouching_Disabled__c != TRUE
              AND Is_Organization_Contact__c != TRUE
            LIMIT 1
        ]) {
            return c.Id;
        }
        return null;
    }

    /**
     * @description Re-validates a community group Account.Id against all eligibility constraints.
     *              Returns the validated Account.Id or null if any check fails.
     */
    private static Id validateCommunityGroup(Id accountId, Id neighbourhoodId) {
        // Must be linked to this neighbourhood via an Active junction.
        Integer linkCount = [
            SELECT COUNT()
            FROM Community_Group_Neighbourhood__c
            WHERE Organization__c = :accountId
              AND Neighbourhood__c = :neighbourhoodId
              AND Status__c = 'Active'
        ];
        if (linkCount == 0) return null;

        for (Account a : [
            SELECT Id
            FROM Account
            WHERE Id = :accountId
              AND Active__c = 'Yes'
              AND Is_Approved_Community_Group__c = TRUE
            LIMIT 1
        ]) {
            return a.Id;
        }
        return null;
    }

    /* ==================================================================
     * 3. Approve / decline / withdraw / revoke
     * ================================================================== */

    @AuraEnabled
    public static void approveVouch(Id vouchRecordId) {
        enforceOwnIdentityForVouching();
        if (vouchRecordId == null) {
            throw new AuraHandledException('Missing vouch record');
        }
        Vouch_Record__c vr = loadVouchRecord(vouchRecordId);
        ensureCanDecide(vr);

        vr.Status__c = STATUS_APPROVED;
        vr.Decided_Date__c = System.now();
        update vr;

        // Cache fields on the vouchee Contact.
        Contact vouchee = new Contact(
            Id = vr.Requester_Contact__c,
            Vouched_Status__c = 'Vouched',
            Vouched_By_Contact__c = vr.Reference_Contact__c,
            Vouched_By_Organization__c = vr.Reference_Organization__c,
            Vouched_Date__c = System.now(),
            Vouched_By_Moderator__c = false,
            Vouch_Source__c = vr.Source__c
        );
        update vouchee;

        // Lock conversation, mirror outcome.
        lockConversation(vr.Conversation__c, STATUS_APPROVED, FimbyIdentityRepository.getActingAsContactId());

        // System message in the now-read-only thread.
        insertSystemMessage(
            vr.Conversation__c,
            FimbyConstants.SYS_MSG_VOUCH_APPROVED,
            contactDisplayName(vr.Reference_Contact__c) + ' vouched for ' + contactDisplayName(vr.Requester_Contact__c) + '.'
        );

        // Notify the requester.
        FimbyNotificationService.createNotification(
            vr.Requester_Contact__c,
            FimbyConstants.NOTIF_VOUCH_APPROVED,
            'You have been welcomed in',
            contactDisplayName(vr.Reference_Contact__c) + ' vouched for you. The library is open.',
            vr.Id,
            'Vouch_Record__c',
            FimbySettings.getUrl('Library_List'),
            contactDisplayName(vr.Reference_Contact__c)
        );
    }

    @AuraEnabled
    public static void declineVouch(Id vouchRecordId, String reason, String details) {
        enforceOwnIdentityForVouching();
        if (vouchRecordId == null) {
            throw new AuraHandledException('Missing vouch record');
        }
        if (String.isBlank(reason)) {
            throw new AuraHandledException('A decline reason is required.');
        }
        if (DECISION_OTHER.equals(reason) && String.isBlank(details)) {
            throw new AuraHandledException('Please share a few words so the moderators can review.');
        }

        Vouch_Record__c vr = loadVouchRecord(vouchRecordId);
        ensureCanDecide(vr);

        vr.Status__c = STATUS_DECLINED;
        vr.Decided_Date__c = System.now();
        vr.Decision_Reason__c = reason;
        vr.Decision_Details__c = details;
        vr.Counts_Toward_Requester_Signal__c = DECISION_CONCERNING.equals(reason);
        update vr;

        // Vouchee returns to settling-in state (still can request from someone else).
        Contact vouchee = new Contact(
            Id = vr.Requester_Contact__c,
            Vouched_Status__c = 'New'
        );
        update vouchee;

        lockConversation(vr.Conversation__c, STATUS_DECLINED, FimbyIdentityRepository.getActingAsContactId());

        insertSystemMessage(
            vr.Conversation__c,
            FimbyConstants.SYS_MSG_VOUCH_DECLINED,
            contactDisplayName(vr.Reference_Contact__c) + ' declined.'
        );

        FimbyNotificationService.createNotification(
            vr.Requester_Contact__c,
            FimbyConstants.NOTIF_VOUCH_DECLINED,
            contactDisplayName(vr.Reference_Contact__c) + ' was not able to vouch',
            'You can ask someone else in your neighbourhood.',
            vr.Id,
            'Vouch_Record__c',
            FimbySettings.getUrl('Profile'),
            contactDisplayName(vr.Reference_Contact__c)
        );
    }

    @AuraEnabled
    public static void withdrawVouchRequest(Id vouchRecordId) {
        enforceOwnIdentityForVouching();
        if (vouchRecordId == null) {
            throw new AuraHandledException('Missing vouch record');
        }
        Vouch_Record__c vr = loadVouchRecord(vouchRecordId);
        if (vr.Requester_Contact__c != FimbyIdentityRepository.getActingAsContactId()) {
            throw new AuraHandledException('Only the requester can withdraw this request.');
        }
        if (!STATUS_PENDING.equals(vr.Status__c)) {
            throw new AuraHandledException('This request can no longer be withdrawn.');
        }

        vr.Status__c = STATUS_WITHDRAWN;
        vr.Decided_Date__c = System.now();
        update vr;

        Contact vouchee = new Contact(
            Id = vr.Requester_Contact__c,
            Vouched_Status__c = 'New'
        );
        update vouchee;

        lockConversation(vr.Conversation__c, STATUS_WITHDRAWN, vr.Requester_Contact__c);

        insertSystemMessage(
            vr.Conversation__c,
            FimbyConstants.SYS_MSG_VOUCH_WITHDRAWN,
            contactDisplayName(vr.Requester_Contact__c) + ' withdrew this request.'
        );
    }

    /**
     * @description Moderator revokes an approved vouch. Sets revocation category/details,
     *              resets the vouchee, increments voucher accountability counts (via DLRS),
     *              auto-pauses voucher if rolling-window threshold crossed, notifies voucher.
     */
    @AuraEnabled
    public static void revokeVouch(Id vouchRecordId, String revocationCategory, String details) {
        enforceOwnIdentityForVouching();
        if (vouchRecordId == null) {
            throw new AuraHandledException('Missing vouch record');
        }
        if (String.isBlank(revocationCategory)) {
            throw new AuraHandledException('A revocation category is required.');
        }
        if ('Other_For_Cause'.equals(revocationCategory) && String.isBlank(details)) {
            throw new AuraHandledException('Please share details for an Other (For Cause) revocation.');
        }

        Vouch_Record__c vr = loadVouchRecord(vouchRecordId);
        if (!STATUS_APPROVED.equals(vr.Status__c)) {
            throw new AuraHandledException('Only approved vouches can be revoked.');
        }

        Id moderatorContactId = FimbyIdentityRepository.getActingAsContactId();

        vr.Status__c = STATUS_REVOKED;
        vr.Revoked_Date__c = System.now();
        vr.Revocation_Category__c = revocationCategory;
        vr.Revocation_Details__c = details;
        vr.Revoked_By_Contact__c = moderatorContactId;
        vr.Counts_Toward_Voucher_Pause__c = COUNTING_REVOCATION_CATEGORIES.contains(revocationCategory);
        update vr;

        // Reset vouchee to settling-in.
        Contact vouchee = new Contact(
            Id = vr.Requester_Contact__c,
            Vouched_Status__c = 'New',
            Vouched_By_Contact__c = null,
            Vouched_By_Organization__c = null,
            Vouched_Date__c = null,
            Vouched_By_Moderator__c = false
        );
        update vouchee;

        // Stamp the conversation thread for audit; system message in the read-only thread.
        if (vr.Conversation__c != null) {
            try {
                update new Conversation__c(
                    Id = vr.Conversation__c,
                    Vouch_Revoked_Date__c = System.now()
                );
            } catch (Exception e) {
                FimbyLogger.error('FimbyVouchController', 'revokeVouch:updateConversation', e);
            }
        }
        insertSystemMessage(
            vr.Conversation__c,
            FimbyConstants.SYS_MSG_VOUCH_REVOKED,
            'A moderator revoked this vouch on ' + System.now().format() + '.'
        );

        // Notify the vouchee privately.
        FimbyNotificationService.createNotification(
            vr.Requester_Contact__c,
            FimbyConstants.NOTIF_VOUCH_REVOKED,
            'Your library access has changed',
            'You can reach out to a moderator if you have questions.',
            vr.Id,
            'Vouch_Record__c',
            FimbySettings.getUrl('Profile'),
            'Neighbourhood team'
        );

        // Voucher accountability (only counts when for-cause).
        if (vr.Counts_Toward_Voucher_Pause__c == true) {
            applyVoucherAccountability(vr.Reference_Contact__c);
        }
    }

    /* ==================================================================
     * 4. Override-vouch (moderator)
     * ================================================================== */

    @AuraEnabled
    public static Id overrideVouch(Id vouchedContactId) {
        enforceOwnIdentityForVouching();
        if (vouchedContactId == null) {
            throw new AuraHandledException('Missing contact');
        }
        Id moderatorContactId = FimbyIdentityRepository.getActingAsContactId();
        Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();

        // Withdraw any open request first so we maintain "one active request at a time".
        for (Vouch_Record__c open : [
            SELECT Id FROM Vouch_Record__c
            WHERE Requester_Contact__c = :vouchedContactId
              AND Status__c = :STATUS_PENDING
        ]) {
            open.Status__c = STATUS_WITHDRAWN;
            open.Decided_Date__c = System.now();
            update open;
        }

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = vouchedContactId,
            Reference_Contact__c = moderatorContactId,
            Neighbourhood__c     = neighbourhoodId,
            Status__c            = STATUS_APPROVED,
            Source__c            = 'Moderator_Override',
            Requested_Date__c    = System.now(),
            Decided_Date__c      = System.now()
        );
        insert vr;

        Contact vouchee = new Contact(
            Id = vouchedContactId,
            Vouched_Status__c = 'Vouched',
            Vouched_By_Contact__c = moderatorContactId,
            Vouched_Date__c = System.now(),
            Vouched_By_Moderator__c = true,
            Vouch_Source__c = 'Moderator_Override'
        );
        update vouchee;

        return vr.Id;
    }

    /* ==================================================================
     * 5. Read APIs
     * ================================================================== */

    /**
     * @description Loads vouching context for a Contact — used by the moderator welcome panel.
     *              Returns current state plus the active pending Vouch_Record__c (if any).
     */
    @AuraEnabled(cacheable=true)
    public static VouchingPanelContext getVouchingContextForContact(Id contactId) {
        if (contactId == null) return null;
        VouchingPanelContext out = new VouchingPanelContext();

        for (Contact c : [
            SELECT Id, Vouched_Status__c, Vouched_By_Contact__c, Vouched_By_Contact__r.Name,
                   Vouched_By_Organization__c, Vouched_By_Organization__r.Name,
                   Vouched_Date__c, Vouched_By_Moderator__c,
                   Vouching_Disabled__c, Vouching_Disabled_Reason__c
            FROM Contact WHERE Id = :contactId LIMIT 1
        ]) {
            out.contactId = c.Id;
            out.vouchedStatus = c.Vouched_Status__c;
            out.vouchedDate = c.Vouched_Date__c;
            out.vouchedByContactName = c.Vouched_By_Contact__r?.Name;
            out.vouchedByOrganizationName = c.Vouched_By_Organization__r?.Name;
            out.vouchedByModerator = c.Vouched_By_Moderator__c == true;
            out.vouchingDisabled = c.Vouching_Disabled__c == true;
            out.vouchingDisabledReason = c.Vouching_Disabled_Reason__c;
        }

        // Most recent pending request, if any.
        for (Vouch_Record__c vr : [
            SELECT Id, Status__c, Reference_Contact__c, Reference_Contact__r.Name,
                   Reference_Organization__c, Reference_Organization__r.Name, Requested_Date__c
            FROM Vouch_Record__c
            WHERE Requester_Contact__c = :contactId AND Status__c = :STATUS_PENDING
            ORDER BY Requested_Date__c DESC NULLS LAST
            LIMIT 1
        ]) {
            out.pendingVouchRecordId = vr.Id;
            out.pendingReferenceContactName = vr.Reference_Contact__r?.Name;
            out.pendingReferenceOrganizationName = vr.Reference_Organization__r?.Name;
            out.pendingRequestedDate = vr.Requested_Date__c;
        }

        return out;
    }

    /**
     * @description Moderator action: clears the auto-pause and re-enables vouching for this Contact.
     */
    @AuraEnabled
    public static void reEnableVoucher(Id voucherContactId) {
        enforceOwnIdentityForVouching();
        if (voucherContactId == null) {
            throw new AuraHandledException('Missing contact');
        }
        update new Contact(
            Id = voucherContactId,
            Vouching_Disabled__c = false,
            Vouching_Disabled_Reason__c = null,
            Vouching_Paused_Date__c = null
        );
    }

    /**
     * @description Loads vouch-banner context for a Conversation__c with Context_Type = Vouch_Request.
     *              Used by fimbyConversationView to render the accept/decline banner state.
     */
    @AuraEnabled
    public static VouchConversationContext getVouchContextForConversation(Id conversationId) {
        if (conversationId == null) return null;

        Conversation__c conv = null;
        for (Conversation__c c : [
            SELECT Id, Context_Type__c, Vouch_Record__c, Vouch_Outcome__c,
                   Vouch_Decided_Date__c, Vouch_Revoked_Date__c, Participant_1__c, Participant_2__c
            FROM Conversation__c WHERE Id = :conversationId LIMIT 1
        ]) {
            conv = c;
        }
        if (conv == null || !FimbyConstants.CTX_VOUCH_REQUEST.equals(conv.Context_Type__c)) {
            return null;
        }

        VouchConversationContext out = new VouchConversationContext();
        out.conversationId = conversationId;
        out.vouchRecordId = conv.Vouch_Record__c;
        out.outcome = conv.Vouch_Outcome__c;
        out.decidedDate = conv.Vouch_Decided_Date__c;
        out.revokedDate = conv.Vouch_Revoked_Date__c;

        Id myContactId = FimbyIdentityRepository.getActingAsContactId();

        if (conv.Vouch_Record__c != null) {
            for (Vouch_Record__c vr : [
                SELECT Id, Requester_Contact__c, Reference_Contact__c, Reference_Organization__c,
                       Requester_Contact__r.Name, Requester_Contact__r.FirstName,
                       Reference_Contact__r.Name, Reference_Contact__r.FirstName,
                       Reference_Organization__r.Name
                FROM Vouch_Record__c WHERE Id = :conv.Vouch_Record__c LIMIT 1
            ]) {
                out.requesterContactId   = vr.Requester_Contact__c;
                out.requesterName        = vr.Requester_Contact__r?.Name;
                out.requesterFirstName   = vr.Requester_Contact__r?.FirstName;
                out.referenceContactId   = vr.Reference_Contact__c;
                out.referenceName        = vr.Reference_Contact__r?.Name;
                out.referenceFirstName   = vr.Reference_Contact__r?.FirstName;
                out.organizationName     = vr.Reference_Organization__r?.Name;
                out.isRecipient          = (myContactId != null && myContactId == vr.Reference_Contact__c);
                out.isRequester          = (myContactId != null && myContactId == vr.Requester_Contact__c);
            }
        }
        return out;
    }

    /**
     * @description Self-only private vouching history strip. Returns last N approved/revoked
     *              vouch records where the current Contact is the reference (i.e. they vouched).
     *              Revoked vouches that don't count toward the voucher-pause threshold are
     *              excluded — they don't affect the user's standing, so they shouldn't take up
     *              a slot in the visible history.
     */
    @AuraEnabled(cacheable=true)
    public static List<VouchHistorySlot> getVouchingHistory(Id contactId) {
        Id selfId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null || selfId == null || contactId != selfId) {
            throw new AuraHandledException('You can only view your own vouching history.');
        }
        List<VouchHistorySlot> slots = new List<VouchHistorySlot>();
        for (Vouch_Record__c vr : [
            SELECT Id, Status__c, Counts_Toward_Voucher_Pause__c, Decided_Date__c, Revoked_Date__c
            FROM Vouch_Record__c
            WHERE Reference_Contact__c = :selfId
              AND (Status__c = :STATUS_APPROVED
                   OR (Status__c = :STATUS_REVOKED AND Counts_Toward_Voucher_Pause__c = true))
            ORDER BY Decided_Date__c DESC NULLS LAST
            LIMIT 5
        ]) {
            VouchHistorySlot s = new VouchHistorySlot();
            s.recordId = vr.Id;
            s.status = vr.Status__c;
            s.countsAgainst = vr.Counts_Toward_Voucher_Pause__c == true;
            s.decidedDate = vr.Decided_Date__c;
            s.revokedDate = vr.Revoked_Date__c;
            slots.add(s);
        }
        return slots;
    }

    /* ==================================================================
     * Helpers
     * ================================================================== */

    private static Boolean hasPendingRequest(Id requesterContactId) {
        Integer n = [
            SELECT COUNT() FROM Vouch_Record__c
            WHERE Requester_Contact__c = :requesterContactId AND Status__c = :STATUS_PENDING
        ];
        return n > 0;
    }

    private static Id findCgRepContact(Id orgAccountId) {
        // Look for an Approved Community_Group_Rep Support_Relationship pointing to this org.
        for (Support_Relationship__c sr : [
            SELECT Contact__c FROM Support_Relationship__c
            WHERE Related_Organization__c = :orgAccountId
              AND Relationship_Type__c = 'Community_Group_Rep'
              AND Status__c = 'Approved'
            LIMIT 1
        ]) {
            return sr.Contact__c;
        }
        return null;
    }

    private static Contact loadContactForVouchCheck(Id contactId) {
        for (Contact c : [
            SELECT Id, Vouching_Disabled__c, Vouched_Status__c, Is_Organization_Contact__c
            FROM Contact WHERE Id = :contactId LIMIT 1
        ]) {
            return c;
        }
        return null;
    }

    private static Boolean isVoucherAllowed(Contact voucher) {
        // Org Contacts (CG path) and Vouched peers can vouch.
        if (voucher.Is_Organization_Contact__c == true) return true;
        return VOUCHEE_STATUS_VOUCHED.contains(String.valueOf(voucher.Vouched_Status__c));
    }

    /**
     * @description Creates Vouch_Record__c plus server-side Conversation__c with
     *              Context_Type = Vouch_Request, bypassing the SCI check that
     *              FimbyConversationController.getOrCreateConversation enforces.
     */
    private static Id requestVouchInternal(
        Id requesterContactId,
        Id referenceContactId,
        Id referenceOrgAccountId,
        Id neighbourhoodId
    ) {
        String source = referenceOrgAccountId != null ? SOURCE_COMMUNITY_GROUP : SOURCE_PEER;

        // 1. Vouch record first so we have an id to link.
        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c    = requesterContactId,
            Reference_Contact__c    = referenceContactId,
            Reference_Organization__c = referenceOrgAccountId,
            Neighbourhood__c        = neighbourhoodId,
            Status__c               = STATUS_PENDING,
            Source__c               = source,
            Requested_Date__c       = System.now()
        );
        insert vr;

        // 2. Server-side conversation (bypasses SCI).
        Conversation__c conv = new Conversation__c(
            Participant_1__c  = requesterContactId,
            Participant_2__c  = referenceContactId,
            Context_Type__c   = FimbyConstants.CTX_VOUCH_REQUEST,
            Vouch_Record__c   = vr.Id,
            Vouch_Outcome__c  = STATUS_PENDING,
            Related_Record_Id__c = String.valueOf(vr.Id),
            Is_Group__c       = false,
            Locked__c         = false,
            Status__c         = 'Active',
            Last_Message_Date__c = System.now(),
            Last_Message_Preview__c = 'Vouch request'
        );
        insert conv;

        // 3. Link the vouch record back to the conversation.
        update new Vouch_Record__c(Id = vr.Id, Conversation__c = conv.Id);

        // 4. Mark the vouchee as Vouch_Requested.
        update new Contact(Id = requesterContactId, Vouched_Status__c = 'Vouch_Requested');

        // 5. System seed message.
        insertSystemMessage(
            conv.Id,
            FimbyConstants.SYS_MSG_VOUCH_REQUESTED,
            contactDisplayName(requesterContactId) + ' asked '
                + contactDisplayName(referenceContactId) + ' to vouch.'
        );

        // 6. Notify the recipient.
        FimbyNotificationService.createNotification(
            referenceContactId,
            FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED,
            contactDisplayName(requesterContactId) + ' would like you to vouch for them',
            'Vouching for them opens up the lending library so they can borrow from neighbours.',
            conv.Id,
            'Conversation__c',
            FimbySettings.getUrl('Conversation', String.valueOf(conv.Id)),
            contactDisplayName(requesterContactId)
        );

        return vr.Id;
    }

    private static void lockConversation(Id convId, String outcome, Id decidedByContactId) {
        if (convId == null) return;
        try {
            update new Conversation__c(
                Id = convId,
                Locked__c = true,
                Vouch_Outcome__c = outcome,
                Vouch_Decided_Date__c = System.now(),
                Vouch_Decided_By_Contact__c = decidedByContactId
            );
        } catch (Exception e) {
            FimbyLogger.error('FimbyVouchController', 'lockConversation', e);
        }
    }

    private static void insertSystemMessage(Id convId, String systemType, String body) {
        if (convId == null) return;
        try {
            insert new Message__c(
                Conversation__c        = convId,
                Body__c                = body,
                Is_System_Message__c   = true,
                System_Message_Type__c = systemType,
                Sent_Date__c           = System.now()
            );
            // Bump conversation summary so the thread surfaces in inboxes correctly.
            update new Conversation__c(
                Id = convId,
                Last_Message_Date__c    = System.now(),
                Last_Message_Preview__c = body.left(255)
            );
        } catch (Exception e) {
            FimbyLogger.error('FimbyVouchController', 'insertSystemMessage', e);
        }
    }

    private static Vouch_Record__c loadVouchRecord(Id vouchRecordId) {
        for (Vouch_Record__c vr : [
            SELECT Id, Status__c, Source__c,
                   Requester_Contact__c, Reference_Contact__c, Reference_Organization__c,
                   Neighbourhood__c, Conversation__c
            FROM Vouch_Record__c WHERE Id = :vouchRecordId LIMIT 1
        ]) {
            return vr;
        }
        throw new AuraHandledException('Vouch record not found.');
    }

    private static void ensureCanDecide(Vouch_Record__c vr) {
        if (!STATUS_PENDING.equals(vr.Status__c)) {
            throw new AuraHandledException('This request can no longer be decided.');
        }
        Id callerId = FimbyIdentityRepository.getActingAsContactId();
        if (callerId != vr.Reference_Contact__c) {
            throw new AuraHandledException('Only the person being asked can decide this vouch.');
        }
    }

    private static String contactDisplayName(Id contactId) {
        if (contactId == null) return 'A neighbour';
        for (Contact c : [SELECT Name FROM Contact WHERE Id = :contactId LIMIT 1]) {
            return String.isNotBlank(c.Name) ? c.Name : 'A neighbour';
        }
        return 'A neighbour';
    }

    /**
     * @description When a voucher's counting-revocation count crosses the threshold,
     *              auto-pause their ability to vouch and create a moderator review task.
     *              The DLRS rollup on the voucher Contact is what we read; the rollup
     *              update happens asynchronously, so we re-query the current value
     *              from Vouch_Record__c rows as a defence in depth.
     */
    private static void applyVoucherAccountability(Id voucherContactId) {
        if (voucherContactId == null) return;
        Integer threshold = FimbySettings.vouchingDisableThreshold();
        Datetime twelveMonthsAgo = System.now().addDays(-365);

        Integer recentCounting = [
            SELECT COUNT() FROM Vouch_Record__c
            WHERE Reference_Contact__c = :voucherContactId
              AND Status__c = :STATUS_REVOKED
              AND Counts_Toward_Voucher_Pause__c = true
              AND Revoked_Date__c >= :twelveMonthsAgo
        ];

        if (recentCounting < threshold) return;

        for (Contact voucher : [
            SELECT Id, Vouching_Disabled__c FROM Contact WHERE Id = :voucherContactId LIMIT 1
        ]) {
            if (voucher.Vouching_Disabled__c == true) return;
            voucher.Vouching_Disabled__c = true;
            voucher.Vouching_Disabled_Reason__c = 'Auto_Threshold';
            voucher.Vouching_Paused_Date__c = System.now();
            update voucher;

            // Private notification to the voucher.
            FimbyNotificationService.createNotification(
                voucher.Id,
                FimbyConstants.NOTIF_VOUCHER_PAUSED,
                'Your ability to vouch has been paused',
                'We will be in touch. Reach out to a moderator if you have questions.',
                voucher.Id,
                'Contact',
                FimbySettings.getUrl('Profile'),
                'Neighbourhood team'
            );

            // Dignified follow-up email — does not name the revoked vouchees.
            sendVoucherPauseEmail(voucher.Id, recentCounting);
        }
    }

    /**
     * @description Sends the privacy-conscious voucher-pause email via the existing
     *              FimbyTransactionalEmailService (FIMBY_Transactional template +
     *              placeholder injection). Does NOT name the revoked vouchees by default.
     */
    private static void sendVoucherPauseEmail(Id voucherContactId, Integer countingCount) {
        Id voucherUserId = null;
        for (User u : [SELECT Id FROM User WHERE ContactId = :voucherContactId AND IsActive = true LIMIT 1]) {
            voucherUserId = u.Id;
        }
        if (voucherUserId == null) return;

        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = voucherUserId;
        req.subject = 'A note about your vouching';
        req.introText = 'We wanted to let you know that ' + countingCount
            + ' people you vouched for in the past year have had their library access revoked for cause.';
        req.cardHtml =
            '<div style="padding:16px;background:#FAF7F2;border-radius:12px;">'
            + '<p style="margin:0 0 12px;font-size:15px;color:#261A11;">'
            + 'For now, your ability to vouch is paused while we take a closer look.'
            + ' This is a private record \u2014 nobody else sees it.'
            + '</p>'
            + '<p style="margin:0;font-size:14px;color:#4A3526;">'
            + 'If you have questions or want to talk through what happened, please reach out to a moderator.'
            + ' We are happy to walk through it with you.'
            + '</p>'
            + '</div>';
        req.ctaUrl = FimbySettings.getUrl('Profile');
        req.ctaLabel = 'Open your profile';

        try {
            FimbyTransactionalEmailService.send(req);
        } catch (Exception e) {
            FimbyLogger.error('FimbyVouchController', 'sendVoucherPauseEmail', e);
        }
    }

    /* ==================================================================
     * Wire types
     * ================================================================== */

    public class SubmitResult {
        @AuraEnabled public Boolean delivered;
        @AuraEnabled public Boolean alreadyHasPending;
        @AuraEnabled public Id vouchRecordId;
        @AuraEnabled public String message;

        public SubmitResult() {
            this.delivered = false;
            this.alreadyHasPending = false;
        }
    }

    public class VoucherOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String voucherType;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
    }

    public class VouchHistorySlot {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean countsAgainst;
        @AuraEnabled public Datetime decidedDate;
        @AuraEnabled public Datetime revokedDate;
    }

    public class VouchingPanelContext {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String vouchedStatus;
        @AuraEnabled public Datetime vouchedDate;
        @AuraEnabled public String vouchedByContactName;
        @AuraEnabled public String vouchedByOrganizationName;
        @AuraEnabled public Boolean vouchedByModerator;
        @AuraEnabled public Boolean vouchingDisabled;
        @AuraEnabled public String vouchingDisabledReason;
        @AuraEnabled public Id pendingVouchRecordId;
        @AuraEnabled public String pendingReferenceContactName;
        @AuraEnabled public String pendingReferenceOrganizationName;
        @AuraEnabled public Datetime pendingRequestedDate;
    }

    public class VouchConversationContext {
        @AuraEnabled public Id conversationId;
        @AuraEnabled public Id vouchRecordId;
        @AuraEnabled public String outcome;
        @AuraEnabled public Datetime decidedDate;
        @AuraEnabled public Datetime revokedDate;
        @AuraEnabled public Id requesterContactId;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String requesterFirstName;
        @AuraEnabled public Id referenceContactId;
        @AuraEnabled public String referenceName;
        @AuraEnabled public String referenceFirstName;
        @AuraEnabled public String organizationName;
        @AuraEnabled public Boolean isRecipient;
        @AuraEnabled public Boolean isRequester;
    }
}
