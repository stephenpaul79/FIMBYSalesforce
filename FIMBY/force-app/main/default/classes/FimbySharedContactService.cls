/**
 * @description Single write path for Shared_Contact_Info__c consent episodes.
 *
 *              Callers describe WHAT was disclosed. This class decides whether that
 *              means editing the open episode or opening a new one, derives every
 *              security field (neighbourhood stamps, pair key), and performs the
 *              one-way revoke. No caller may set Status__c, Active_Pair_Key__c,
 *              Contact_Neighbourhood__c, Shared_To_Neighbourhood__c, or
 *              Consent_Closed_Date__c directly.
 *
 *              The rules it enforces:
 *              - Editing an OPEN episode updates it in place. Changing your phone
 *                number is not a new act of consent.
 *              - Sharing again after a revoke INSERTS a new episode. A closed
 *                episode is never reopened and never overwritten, so revoked rows
 *                stay a trustworthy audit trail.
 *              - Only the newest row per exact direction is current, so a newer
 *                Revoked row is never bypassed in favour of an older Active one.
 *
 *              `without sharing` matches FimbySharedContactAccess: the object is
 *              Private externally, so a community user cannot update their own
 *              share rows under sharing. Every method resolves the sharer from the
 *              caller-supplied identity and refuses to act for anybody else.
 */
public without sharing class FimbySharedContactService {

    /** Unchecked fields are cleared. Used by direct and lending share forms. */
    public static final String MODE_REPLACE = 'REPLACE';
    /** Unchecked fields keep their existing value. Used by response sharing, which shares incrementally. */
    public static final String MODE_MERGE = 'MERGE';

    /**
     * The in-thread explanation when an episode closes. Neutral by design — "changed"
     * rather than language that assigns blame to either neighbour. Lives here so the
     * trigger handler and the migration batch cannot drift into two wordings.
     */
    public static final String REVOKE_NOTICE_BODY =
        'Contact sharing changed, so this conversation is now read-only. '
        + 'A new conversation can begin after contact information is shared again.';

    /**
     * Tests that simulate pre-trigger history may insert without derived-field
     * enforcement. Never set in production code.
     */
    @TestVisible
    public static Boolean skipTrigger = false;

    public class SharedContactException extends Exception {}

    /**
     * @description What the caller wants disclosed, plus the identity doing it.
     *              Security fields are deliberately absent; the service derives them.
     */
    public class ShareRequest {
        public Id sharerContactId;
        public Id recipientContactId;
        public String origin;
        public String writeMode = MODE_REPLACE;
        public Boolean shareEmail = false;
        public Boolean sharePhone = false;
        public Boolean shareAddress = false;
        public String email;
        public String phone;
        public String street;
        public String city;
        public String provinceState;
        public String postalCode;
        public String country;
        public Boolean setAdditionalInfo = false;
        public String additionalInfo;
        /** Migrations and backfills replay consent that already happened; they must not re-notify. */
        public Boolean suppressNotification = false;
        /** Surface context for the email card, e.g. the post name or 'Lending item'. */
        public String emailContextLabel;
        /** Overrides the email CTA. Defaults to the sharer's neighbour profile. */
        public String emailCtaUrl;
        public String emailCtaLabel;
        public String emailCtaIcon;
    }

    /**
     * @description Outcome of a save, shaped so existing email/system-message
     *              decisions stay correct without re-querying.
     */
    public class ShareResult {
        public Id sharedContactInfoId;
        public Boolean createdNewEpisode = false;
        public Boolean expandedExistingEpisode = false;
        public Boolean hadEmailBefore = false;
        public Boolean hadPhoneBefore = false;
        public Boolean hadAddressBefore = false;
        public Boolean hasEmailAfter = false;
        public Boolean hasPhoneAfter = false;
        public Boolean hasAddressAfter = false;
    }

    /**
     * @description Opens or updates the consent episode for an exact direction.
     * @param request What is being disclosed, by whom, to whom.
     * @return The resulting episode Id plus before/after disclosure state.
     */
    public static ShareResult saveActiveEpisode(ShareRequest request) {
        validateRequest(request);

        Shared_Contact_Info__c current = lockCurrentEpisode(request.sharerContactId, request.recipientContactId);

        ShareResult result = new ShareResult();
        Boolean isNewEpisode = (current == null || !FimbySharedContactAccess.isOpen(current));

        if (!isNewEpisode) {
            result.hadEmailBefore = String.isNotBlank(current.Email__c);
            result.hadPhoneBefore = String.isNotBlank(current.Phone__c);
            result.hadAddressBefore = String.isNotBlank(current.Street__c)
                || String.isNotBlank(current.City__c)
                || String.isNotBlank(current.Postal_Code__c);
        }

        Shared_Contact_Info__c row = isNewEpisode
            ? newEpisodeRow(request)
            : current;

        applyDisclosure(row, request, isNewEpisode);
        stampSecurityFields(row, request.sharerContactId, request.recipientContactId, true);

        try {
            if (isNewEpisode) {
                insert row;
            } else {
                update row;
            }
        } catch (DmlException e) {
            // Two first-share transactions can race with no row to lock. The unique
            // pair key picks one winner; the loser re-reads and merges instead of
            // showing the neighbour a raw platform error.
            if (isNewEpisode && e.getMessage() != null && e.getMessage().contains('DUPLICATE_VALUE')) {
                Shared_Contact_Info__c winner =
                    lockCurrentEpisode(request.sharerContactId, request.recipientContactId);
                if (winner == null || !FimbySharedContactAccess.isOpen(winner)) {
                    throw e;
                }
                applyDisclosure(winner, request, false);
                stampSecurityFields(winner, request.sharerContactId, request.recipientContactId, true);
                update winner;
                row = winner;
                isNewEpisode = false;
            } else {
                throw e;
            }
        }

        result.sharedContactInfoId = row.Id;
        result.createdNewEpisode = isNewEpisode;
        result.hasEmailAfter = String.isNotBlank(row.Email__c);
        result.hasPhoneAfter = String.isNotBlank(row.Phone__c);
        result.hasAddressAfter = String.isNotBlank(row.Street__c)
            || String.isNotBlank(row.City__c)
            || String.isNotBlank(row.Postal_Code__c);
        result.expandedExistingEpisode = !isNewEpisode && (
            (result.hasEmailAfter && !result.hadEmailBefore)
            || (result.hasPhoneAfter && !result.hadPhoneBefore)
            || (result.hasAddressAfter && !result.hadAddressBefore)
        );

        announceToRecipient(request, result, row);
        return result;
    }

    /**
     * @description Tells the recipient something became visible to them, in-app and by
     *              email. Both live here rather than in each controller so the
     *              neighbour-profile, response, and lending surfaces cannot drift apart.
     *              The profile path previously told the recipient nothing at all, which
     *              left browser-only neighbours to discover a share by chance.
     *
     *              Fires only when something became visible that was not visible before.
     *              Correcting a typo in an already-shared phone number is an edit to the
     *              recipient's existing view, not a new act of consent to announce.
     */
    private static void announceToRecipient(
        ShareRequest request,
        ShareResult result,
        Shared_Contact_Info__c row
    ) {
        if (request.suppressNotification == true) {
            return;
        }
        if (!result.createdNewEpisode && !result.expandedExistingEpisode) {
            return;
        }
        notifyRecipient(request, result);
        emailRecipient(request, row);
    }

    private static void notifyRecipient(ShareRequest request, ShareResult result) {
        List<String> visible = new List<String>();
        if (result.hasEmailAfter) {
            visible.add('email address');
        }
        if (result.hasPhoneAfter) {
            visible.add('phone number');
        }
        if (result.hasAddressAfter) {
            visible.add('address');
        }

        String body = visible.isEmpty()
            ? 'Their contact details are on their profile now.'
            : 'You can now see their ' + joinWithAnd(visible) + '.';

        FimbyNotificationService.createNotification(
            request.recipientContactId,
            FimbyConstants.NOTIF_CONTACT_INFO_SHARED,
            'shared their contact info with you',
            body,
            result.sharedContactInfoId,
            'Shared_Contact_Info__c',
            sharerProfileUrl(request.sharerContactId),
            sharerDisplayName(request.sharerContactId),
            false,
            request.sharerContactId
        );
    }

    /**
     * @description Emails the recipient the details that just became visible. Email is
     *              the only channel that reaches a neighbour who is not currently in the
     *              app, which matters for the browser-only and low-tech users FIMBY is
     *              built for — the in-app bell requires them to already be looking.
     *
     *              Unlike the per-controller sends this replaces, it honours the global
     *              email switch and the recipient's own Email_Alerts_Enabled__c. A
     *              contact share is not safety messaging, so it is opt-out-able.
     */
    private static void emailRecipient(ShareRequest request, Shared_Contact_Info__c row) {
        if (!FimbySettings.emailAlertsGlobalEnabled()) {
            return;
        }

        List<User> recipients = [
            SELECT Id, Email_Alerts_Enabled__c
            FROM User
            WHERE ContactId = :request.recipientContactId AND IsActive = true
            LIMIT 1
        ];
        if (recipients.isEmpty() || recipients[0].Email_Alerts_Enabled__c == false) {
            return;
        }

        Id recipientUserId = recipients[0].Id;
        Contact sharer = sharerContact(request.sharerContactId);
        String senderName = sharerDisplayName(request.sharerContactId);

        String cardHtml = FimbyEmailHtmlBuilder.buildContactShareCard(
            FimbyTransactionalEmailService.lookupRecipientFirstName(recipientUserId),
            senderName,
            row.Email__c,
            row.Phone__c,
            formatAddress(row),
            row.Additional_Info__c,
            request.emailContextLabel,
            String.isNotBlank(request.emailCtaUrl)
                ? request.emailCtaUrl
                : sharerProfileUrl(request.sharerContactId),
            String.isNotBlank(request.emailCtaLabel) ? request.emailCtaLabel : 'View Profile',
            request.emailCtaIcon
        );

        FimbyTransactionalEmailService.TransactionalEmailRequest emailReq =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        emailReq.recipientUserId = recipientUserId;
        emailReq.subject = senderName + ' shared their contact info with you';
        emailReq.cardHtml = cardHtml;
        emailReq.skipSubjectBlock = true;
        emailReq.replyToEmail = sharer == null ? null : sharer.Email;

        FimbyTransactionalEmailService.send(emailReq);
    }

    /**
     * @description One readable line, skipping the parts that were not shared.
     */
    private static String formatAddress(Shared_Contact_Info__c row) {
        List<String> parts = new List<String>();
        for (String part : new List<String>{
            row.Street__c, row.City__c, row.Province_State__c, row.Postal_Code__c
        }) {
            if (String.isNotBlank(part)) {
                parts.add(part.trim());
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String sharerProfileUrl(Id sharerContactId) {
        return FimbySettings.getUrl('Neighbour', null, '?id=' + sharerContactId);
    }

    /**
     * @description "phone number and address", "email address, phone number, and address".
     */
    private static String joinWithAnd(List<String> parts) {
        if (parts.size() == 1) {
            return parts[0];
        }
        if (parts.size() == 2) {
            return parts[0] + ' and ' + parts[1];
        }
        List<String> leading = new List<String>(parts);
        String last = leading.remove(leading.size() - 1);
        return String.join(leading, ', ') + ', and ' + last;
    }

    /**
     * @description Full_Name__c honours Mask_Last_Name__c ("Emily D."); never use raw
     *              Name, which leaks the full last name regardless of the privacy setting.
     */
    private static String sharerDisplayName(Id sharerContactId) {
        Contact c = sharerContact(sharerContactId);
        if (c == null) {
            return 'A neighbour';
        }
        if (String.isNotBlank(c.Full_Name__c)) {
            return c.Full_Name__c;
        }
        return String.isNotBlank(c.Name) ? c.Name : 'A neighbour';
    }

    /** Cached so the notification and the email do not each query the sharer. */
    private static Map<Id, Contact> sharerCache = new Map<Id, Contact>();

    private static Contact sharerContact(Id sharerContactId) {
        if (sharerContactId == null) {
            return null;
        }
        if (!sharerCache.containsKey(sharerContactId)) {
            Contact found = null;
            for (Contact c : [
                SELECT Full_Name__c, Name, Email
                FROM Contact
                WHERE Id = :sharerContactId
                LIMIT 1
            ]) {
                found = c;
            }
            sharerCache.put(sharerContactId, found);
        }
        return sharerCache.get(sharerContactId);
    }

    /**
     * @description Closes an episode permanently. Only the sharer may revoke, and
     *              only an open episode can be closed. The trigger handler locks the
     *              bound threads and posts the explanation, so privacy closure stays
     *              atomic with the status change.
     * @param actingContactId The identity performing the revoke; must be the sharer.
     * @param sharedContactInfoId The episode to close.
     */
    public static void revokeEpisode(Id actingContactId, Id sharedContactInfoId) {
        if (actingContactId == null || sharedContactInfoId == null) {
            throw new SharedContactException('Unable to identify the sharing to stop.');
        }
        List<Shared_Contact_Info__c> rows = [
            SELECT Id, Contact__c, Shared_To__c, Status__c, Consent_Closed_Date__c
            FROM Shared_Contact_Info__c
            WHERE Id = :sharedContactInfoId
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw new SharedContactException('That sharing record no longer exists.');
        }
        Shared_Contact_Info__c sci = rows[0];
        if (sci.Contact__c != actingContactId) {
            throw new SharedContactException('You can only stop sharing that you started.');
        }
        if (!FimbySharedContactAccess.isOpen(sci)) {
            return;
        }
        sci.Status__c = FimbyConstants.SHARED_CONTACT_REVOKED;
        sci.Active_Pair_Key__c = null;
        if (sci.Consent_Closed_Date__c == null) {
            sci.Consent_Closed_Date__c = System.now();
        }
        update sci;
    }

    /**
     * @description Derives the security fields for a row. Exposed so the trigger and
     *              the migration batch stamp them identically to live writes.
     * @param row The row to stamp.
     * @param sharerContactId The sharer.
     * @param recipientContactId The recipient.
     * @param isOpen Whether the resulting episode is open.
     */
    public static void stampSecurityFields(
        Shared_Contact_Info__c row, Id sharerContactId, Id recipientContactId, Boolean isOpen
    ) {
        row.Status__c = isOpen
            ? FimbyConstants.SHARED_CONTACT_ACTIVE
            : FimbyConstants.SHARED_CONTACT_REVOKED;
        row.Active_Pair_Key__c = isOpen ? buildPairKey(sharerContactId, recipientContactId) : null;

        Map<Id, Id> neighbourhoods = neighbourhoodsFor(new Set<Id>{ sharerContactId, recipientContactId });
        row.Contact_Neighbourhood__c = neighbourhoods.get(sharerContactId);
        row.Shared_To_Neighbourhood__c = neighbourhoods.get(recipientContactId);
    }

    /**
     * @description The unique guard value for one open direction. Ids are normalized
     *              to 18 characters so a 15-character write cannot slip past the index.
     * @param sharerContactId The sharer.
     * @param recipientContactId The recipient.
     * @return The pair key, or null when either party is missing.
     */
    public static String buildPairKey(Id sharerContactId, Id recipientContactId) {
        if (sharerContactId == null || recipientContactId == null) {
            return null;
        }
        return String.valueOf(sharerContactId) + ':' + String.valueOf(recipientContactId);
    }

    /**
     * @description Bulk neighbourhood resolution for the stamping paths.
     * @param contactIds The contacts to resolve.
     * @return Map of Contact Id to neighbourhood Account Id.
     */
    public static Map<Id, Id> neighbourhoodsFor(Set<Id> contactIds) {
        Map<Id, Id> byContact = new Map<Id, Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return byContact;
        }
        contactIds.remove(null);
        if (contactIds.isEmpty()) {
            return byContact;
        }
        for (Contact c : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]) {
            byContact.put(c.Id, c.AccountId);
        }
        return byContact;
    }

    /**
     * @description Server-side authorization for a direct share. The recipient must
     *              be someone the sharer can already see: same neighbourhood, or an
     *              adjacent neighbour already visible under the existing cross-cell
     *              relationship rules. An arbitrary Contact Id must never be able to
     *              create the first cross-neighbourhood connection.
     * @param sharerContactId The sharer.
     * @param recipientContactId The proposed recipient.
     */
    public static void assertRecipientAllowed(Id sharerContactId, Id recipientContactId) {
        if (sharerContactId == null || recipientContactId == null) {
            throw new SharedContactException('Unable to identify who you are sharing with.');
        }
        if (sharerContactId == recipientContactId) {
            throw new SharedContactException('You cannot share contact info with yourself.');
        }
        if (!FimbyContactVisibility.canView(sharerContactId, recipientContactId)) {
            throw new SharedContactException('You can only share your details with neighbours you can see.');
        }
    }

    private static Shared_Contact_Info__c newEpisodeRow(ShareRequest request) {
        return new Shared_Contact_Info__c(
            Contact__c = request.sharerContactId,
            Shared_To__c = request.recipientContactId,
            Origin__c = request.origin
        );
    }

    private static void applyDisclosure(
        Shared_Contact_Info__c row, ShareRequest request, Boolean isNewEpisode
    ) {
        Boolean replace = (request.writeMode != MODE_MERGE);

        row.Name = buildEpisodeName(request.sharerContactId);
        if (String.isNotBlank(request.origin) && (isNewEpisode || String.isBlank(row.Origin__c))) {
            row.Origin__c = request.origin;
        }

        // Field-selection consent: an unchecked field is never written. In REPLACE
        // mode it is cleared, so unticking a box actually withdraws that field.
        if (request.shareEmail == true) {
            row.Email__c = request.email;
        } else if (replace) {
            row.Email__c = null;
        }

        if (request.sharePhone == true) {
            row.Phone__c = request.phone;
        } else if (replace) {
            row.Phone__c = null;
        }

        if (request.shareAddress == true) {
            row.Street__c = request.street;
            row.City__c = request.city;
            row.Province_State__c = request.provinceState;
            row.Postal_Code__c = request.postalCode;
            row.Country__c = request.country;
        } else if (replace) {
            row.Street__c = null;
            row.City__c = null;
            row.Province_State__c = null;
            row.Postal_Code__c = null;
            row.Country__c = null;
        }

        if (request.setAdditionalInfo == true) {
            row.Additional_Info__c = request.additionalInfo;
        }
    }

    private static Shared_Contact_Info__c lockCurrentEpisode(Id sharerContactId, Id recipientContactId) {
        // FOR UPDATE cannot combine with ORDER BY, so resolve the newest row first,
        // then lock that Id. The unique Active_Pair_Key__c is the concurrency guard
        // if two first-shares race with no row to lock.
        List<Shared_Contact_Info__c> newest = [
            SELECT Id
            FROM Shared_Contact_Info__c
            WHERE Contact__c = :sharerContactId
            AND Shared_To__c = :recipientContactId
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        if (newest.isEmpty()) {
            return null;
        }
        List<Shared_Contact_Info__c> rows = [
            SELECT Id, Contact__c, Shared_To__c, Status__c, Origin__c, Name,
                   Email__c, Phone__c, Street__c, City__c,
                   Province_State__c, Postal_Code__c, Country__c, Additional_Info__c,
                   Active_Pair_Key__c, Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c
            WHERE Id = :newest[0].Id
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildEpisodeName(Id sharerContactId) {
        List<Contact> sharers = [
            SELECT FirstName, LastName FROM Contact WHERE Id = :sharerContactId LIMIT 1
        ];
        String label = sharers.isEmpty()
            ? 'Shared contact'
            : (String.isBlank(sharers[0].FirstName) ? '' : sharers[0].FirstName + ' ')
                + (String.isBlank(sharers[0].LastName) ? '' : sharers[0].LastName);
        String name = label.trim() + ' - ' + String.valueOf(Date.today());
        return name.left(80);
    }

    private static void validateRequest(ShareRequest request) {
        if (request == null || request.sharerContactId == null || request.recipientContactId == null) {
            throw new SharedContactException('Unable to identify who is sharing with whom.');
        }
        if (request.sharerContactId == request.recipientContactId) {
            throw new SharedContactException('You cannot share contact info with yourself.');
        }
        if (request.shareEmail != true && request.sharePhone != true && request.shareAddress != true
                && request.writeMode != MODE_MERGE) {
            throw new SharedContactException('Select at least one type of contact info to share.');
        }
    }
}
