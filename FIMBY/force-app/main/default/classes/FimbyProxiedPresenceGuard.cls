/**
 * @description Capability checks for parent-proxied presence — a child Contact whose
 *              profile is operated entirely by a 19+ parent or guardian.
 *
 *              A proxied child is a full neighbour in every direction that costs them
 *              nothing: they can be seen, posted for, messaged in context, and given
 *              an adult's contact details. What they can never do is disclose contact
 *              information outward, because a child Contact holds no contact data to
 *              disclose and creating that channel is precisely the risk this guard
 *              exists to remove.
 *
 *              Two properties matter more than convenience here:
 *
 *              - It FAILS CLOSED. An unrecognised relationship type is never treated
 *                as organization-backed, because that would misfile a child as an
 *                organization and hand them an organization's capabilities.
 *              - It reads in SYSTEM MODE. If this guard resolved proxied status under
 *                the running user's field-level security, revoking read on
 *                Is_Parent_Proxied__c would make every child look like an ordinary
 *                adult and silently open the outbound share path. A safety check must
 *                not be configurable by a permission edit.
 *
 *              `without sharing` for the same reason as FimbyBlockingHelper: the guard
 *              must see the true state of a Contact regardless of who is asking. Its
 *              queries are hard-scoped to Ids the caller already holds, so it discloses
 *              nothing beyond the boolean it was asked for.
 */
public without sharing class FimbyProxiedPresenceGuard {

    /** Relationship types whose supportee is a person (a Contact without a User). */
    public static final String TYPE_SUPPORT_PERSON = 'Support_Person';
    public static final String TYPE_PARENT_GUARDIAN = 'Parent_Guardian';
    /** Relationship types whose supportee is an organization. */
    public static final String TYPE_COMMUNITY_GROUP_REP = 'Community_Group_Rep';

    /**
     * Bind target for SOQL that lists the identities a person can act as. Kept beside
     * isContactBackedRelationship so a filter and a branch can never disagree about
     * which types are person-backed.
     */
    public static final Set<String> CONTACT_BACKED_TYPES = new Set<String>{
        TYPE_SUPPORT_PERSON, TYPE_PARENT_GUARDIAN
    };

    /**
     * Shown when someone acting as a child tries to share contact details outward.
     * Names the way out rather than the rule, so a guardian is not left guessing.
     */
    public static final String OUTBOUND_SHARE_REFUSAL =
        'A parent-managed profile has no contact details of its own to share. '
        + 'Switch back to yourself to share your own contact information.';

    /** The object-level phrasing, which an admin or import may also see. */
    public static final String OUTBOUND_SHARE_INVARIANT =
        'A parent-managed profile can receive shared contact information but can never share any outward.';

    /**
     * Shown when someone acting as a child tries to list an item or a skill. A listing
     * is an open invitation to strangers that outlives the moment it was posted, and its
     * coordination happens in a thread with no shared context to anchor it. A parent
     * lists under their own name instead; child coordination belongs on Ask and Offer
     * posts, whose response threads are contextual.
     */
    public static final String LISTING_REFUSAL =
        'A parent-managed profile cannot list items or skills. '
        + 'Switch back to yourself to add this under your own name.';

    /** Shown when a profile edit would put reachable contact details on a child. */
    public static final String CHILD_PII_REFUSAL =
        'A parent-managed profile does not store contact details. '
        + 'Switch back to yourself to update your own contact information.';

    /**
     * Contact fields that must stay blank on a proxied child. A child profile carries
     * a first name and an optional photo; anything here is a route to reach them
     * off-platform, which only their guardian may ever provide.
     */
    public static final Set<String> PROHIBITED_CHILD_PII_FIELDS = new Set<String>{
        'Email', 'Phone', 'MobilePhone', 'HomePhone', 'OtherPhone', 'Fax',
        'MailingStreet', 'MailingCity', 'MailingState',
        'MailingPostalCode', 'MailingCountry'
    };

    /** Transaction cache. Trigger and service paths both re-ask about the same Ids. */
    private static Map<Id, Boolean> proxiedCache = new Map<Id, Boolean>();

    /**
     * @description Whether the supportee of this relationship type is a person rather
     *              than an organization. Both Support_Person and Parent_Guardian are
     *              contact-backed: the related Contact has no User, approved helpers
     *              switch into that identity, and delivery fans out to every helper.
     * @param relationshipType The Support_Relationship__c.Relationship_Type__c value.
     * @return true for person-backed relationship types.
     */
    public static Boolean isContactBackedRelationship(String relationshipType) {
        return relationshipType == TYPE_SUPPORT_PERSON
            || relationshipType == TYPE_PARENT_GUARDIAN;
    }

    /**
     * @description Whether the supportee of this relationship type is an organization.
     *              Deliberately an allow-list rather than "not contact-backed", so a
     *              relationship type added later fails closed instead of inheriting
     *              organization behaviour by default.
     * @param relationshipType The Support_Relationship__c.Relationship_Type__c value.
     * @return true only for known organization-backed relationship types.
     */
    public static Boolean isOrganizationBackedRelationship(String relationshipType) {
        return relationshipType == TYPE_COMMUNITY_GROUP_REP;
    }

    /**
     * @description Resolves which of the given Contacts are parent-proxied, in one
     *              query. This is the primary API — trigger contexts must never call
     *              the singular form in a loop.
     * @param contactIds The Contacts to test.
     * @return The subset that is parent-proxied. Never null.
     */
    public static Set<Id> proxiedAmong(Set<Id> contactIds) {
        Set<Id> proxied = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return proxied;
        }

        Set<Id> unknown = new Set<Id>();
        for (Id contactId : contactIds) {
            if (contactId == null) {
                continue;
            }
            if (proxiedCache.containsKey(contactId)) {
                if (proxiedCache.get(contactId) == true) {
                    proxied.add(contactId);
                }
            } else {
                unknown.add(contactId);
            }
        }
        if (unknown.isEmpty()) {
            return proxied;
        }

        // System mode by design: the guard must not depend on the running user's FLS.
        for (Contact c : [
            SELECT Id, Is_Parent_Proxied__c
            FROM Contact
            WHERE Id IN :unknown
            WITH SYSTEM_MODE
        ]) {
            Boolean isProxied = (c.Is_Parent_Proxied__c == true);
            proxiedCache.put(c.Id, isProxied);
            unknown.remove(c.Id);
            if (isProxied) {
                proxied.add(c.Id);
            }
        }

        // Ids that returned no row are cached as not-proxied so a deleted or
        // out-of-scope Contact does not re-query on every subsequent check.
        for (Id missing : unknown) {
            proxiedCache.put(missing, false);
        }
        return proxied;
    }

    /**
     * @description Whether this Contact is a parent-managed child profile.
     * @param contactId The Contact to test.
     * @return true when the Contact is parent-proxied.
     */
    public static Boolean isProxied(Id contactId) {
        if (contactId == null) {
            return false;
        }
        return proxiedAmong(new Set<Id>{ contactId }).contains(contactId);
    }

    /**
     * @description Whether the running user is currently acting as a parent-managed
     *              child. Drives server-side refusals and the UI's decision to hide
     *              outbound share affordances.
     * @return true when the acting identity is a proxied child.
     */
    public static Boolean isActingAsProxiedChild() {
        Id actingAsId = FimbyIdentityRepository.getActingAsContactId();
        if (actingAsId == null) {
            return false;
        }
        return isProxied(actingAsId);
    }

    /**
     * @description Whether a Contact carries any of the PII that must stay blank on a
     *              proxied child. Used by the profile write path and by the setup
     *              wizard, so the invariant is stated once.
     * @param record The Contact being saved.
     * @return true when at least one prohibited field holds a value.
     */
    public static Boolean hasProhibitedChildPii(Contact record) {
        if (record == null) {
            return false;
        }
        // Populated-fields map rather than get(): a Contact queried without these
        // columns would make get() throw, and a safety check must never fail by
        // raising on the shape of its input.
        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        for (String fieldName : PROHIBITED_CHILD_PII_FIELDS) {
            Object value = populated.get(fieldName);
            if (value != null && String.valueOf(value).trim() != '') {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Clears the transaction cache. Tests flip Is_Parent_Proxied__c
     *              mid-transaction and must not read a stale answer.
     */
    @TestVisible
    private static void clearCache() {
        proxiedCache = new Map<Id, Boolean>();
    }
}
