/**
 * @description Fans notification delivery out to the neighbours who actually hold a
 * login when the notification's Contact holds none of their own — elder supportees,
 * organization contacts, and parent-proxied children.
 *
 * Before this class existed, `User WHERE ContactId = :supportee` returned nothing for
 * those Contacts, so Push_Status__c and Email_Status__c were stamped null at insert and
 * the alert died in the bell. The in-app row was correct and completely silent.
 *
 * The in-app row stays singular and stays on the supportee: one Notification__c, one
 * inbox, one read state. What multiplies is *delivery*, and that lives in a compact JSON
 * ledger on Delivery_State__c rather than in child records, so a two-guardian household
 * costs one row instead of three.
 *
 * Push_Status__c / Email_Status__c remain the aggregate channel statuses the batch jobs
 * poll on. The aggregate deliberately stays Pending while ANY recipient is still
 * outstanding, which is what lets each recipient retry independently without a second
 * scheduler or a reaper job.
 */
public without sharing class FimbySupportedIdentityDelivery {

    public static final Integer LEDGER_VERSION = 1;

    public static final String PENDING       = 'Pending';
    public static final String PENDING_QUIET = 'Pending_Quiet';
    public static final String PROCESSING    = 'Processing';
    public static final String SENT          = 'Sent';
    public static final String FAILED        = 'Failed';
    public static final String SUPPRESSED    = 'Suppressed';
    public static final String PARTIAL       = 'Partial';

    /* =====================================================================
     * Ledger
     *
     * Keys are single characters because this is machine-only state that
     * never reaches a surface, and a two-guardian row is written on every
     * notification a child receives. Long text area caps at 131,072 chars,
     * so brevity here is about keeping the row cheap, not about squeezing
     * under a limit.
     *   v = ledger version   s = supportee Contact Id   r = recipients
     *   u = User Id   p = push state   e = email state   x = last error
     * ===================================================================== */

    public class Recipient {
        public String u;
        public String p;
        public String e;
        public String x;

        public Recipient() {}

        public Recipient(Id userId, String pushState, String emailState) {
            this.u = String.valueOf(userId);
            this.p = pushState;
            this.e = emailState;
        }
    }

    public class Ledger {
        public Integer v = LEDGER_VERSION;
        public String s;
        public List<Recipient> r = new List<Recipient>();

        public Ledger() {}

        public Ledger(Id supporteeContactId) {
            this.s = String.valueOf(supporteeContactId);
        }

        public Recipient forUser(Id userId) {
            String target = String.valueOf(userId);
            for (Recipient rec : r) {
                if (rec.u == target) {
                    return rec;
                }
            }
            return null;
        }

        public Set<Id> userIds() {
            Set<Id> ids = new Set<Id>();
            for (Recipient rec : r) {
                if (String.isNotBlank(rec.u)) {
                    try {
                        ids.add(Id.valueOf(rec.u));
                    } catch (Exception ignored) {
                        // A malformed Id in the ledger must not strand the whole row.
                    }
                }
            }
            return ids;
        }

        public String pushAggregate() {
            List<String> states = new List<String>();
            for (Recipient rec : r) {
                states.add(rec.p);
            }
            return aggregate(states);
        }

        public String emailAggregate() {
            List<String> states = new List<String>();
            for (Recipient rec : r) {
                states.add(rec.e);
            }
            return aggregate(states);
        }
    }

    /**
     * Rolls per-recipient states into the single channel status the batch jobs
     * query on. Outstanding work always wins, so the row keeps being picked up
     * until every recipient has resolved — that is the retry mechanism.
     * 'Partial' is terminal and means some recipients were reached and some
     * were not, which is a real outcome worth being able to report on rather
     * than flattening to Sent or Failed.
     */
    public static String aggregate(List<String> states) {
        Boolean anyPending = false, anyQuiet = false, anyProcessing = false;
        Boolean anySent = false, anyFailed = false, anySuppressed = false;

        for (String s : states) {
            if (s == PENDING)            { anyPending = true; }
            else if (s == PENDING_QUIET) { anyQuiet = true; }
            else if (s == PROCESSING)    { anyProcessing = true; }
            else if (s == SENT)          { anySent = true; }
            else if (s == FAILED)        { anyFailed = true; }
            else if (s == SUPPRESSED)    { anySuppressed = true; }
        }

        if (anyPending)    { return PENDING; }
        if (anyQuiet)      { return PENDING_QUIET; }
        if (anyProcessing) { return PROCESSING; }
        if (anySent && (anyFailed || anySuppressed)) { return PARTIAL; }
        if (anySent)       { return SENT; }
        if (anyFailed)     { return FAILED; }
        if (anySuppressed) { return SUPPRESSED; }
        return null;
    }

    public static String serializeLedger(Ledger l) {
        return (l == null || l.r.isEmpty()) ? null : JSON.serialize(l, true);
    }

    /**
     * Parses defensively via untyped deserialization: an unrecognized key or a
     * future ledger version must never throw inside a batch job and strand
     * every other notification in the cycle.
     */
    public static Ledger parseLedger(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(raw);
            if (!(parsed instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> root = (Map<String, Object>) parsed;
            Ledger l = new Ledger();
            l.v = root.get('v') instanceof Integer ? (Integer) root.get('v') : LEDGER_VERSION;
            l.s = root.get('s') == null ? null : String.valueOf(root.get('s'));

            Object recipientsRaw = root.get('r');
            if (recipientsRaw instanceof List<Object>) {
                for (Object entryRaw : (List<Object>) recipientsRaw) {
                    if (!(entryRaw instanceof Map<String, Object>)) {
                        continue;
                    }
                    Map<String, Object> entry = (Map<String, Object>) entryRaw;
                    if (entry.get('u') == null) {
                        continue;
                    }
                    Recipient rec = new Recipient();
                    rec.u = String.valueOf(entry.get('u'));
                    rec.p = entry.get('p') == null ? null : String.valueOf(entry.get('p'));
                    rec.e = entry.get('e') == null ? null : String.valueOf(entry.get('e'));
                    rec.x = entry.get('x') == null ? null : String.valueOf(entry.get('x'));
                    l.r.add(rec);
                }
            }
            return l.r.isEmpty() ? null : l;
        } catch (Exception e) {
            FimbyLogger.warn('FimbySupportedIdentityDelivery', 'parseLedger',
                'Unreadable delivery ledger: ' + e.getMessage());
            return null;
        }
    }

    /* =====================================================================
     * Helper resolution
     * ===================================================================== */

    /**
     * Maps each user-less Contact to the Contacts of every neighbour approved to
     * act for it. Covers both shapes of Support_Relationship__c: contact-backed
     * (elder supportees, proxied children) via Related_Contact__c, and
     * organization-backed (community group reps) via Related_Organization__c.
     *
     * Relationship_Type__c is deliberately not filtered. Every approved helper
     * is a legitimate delivery target regardless of why they hold the mandate.
     *
     * Every query here runs WITH SYSTEM_MODE. Working out who is approved to act
     * for whom is an authorization decision, so it must not vary with the running
     * user's field-level security — and the community profile cannot read arbitrary
     * Support_Relationship__c rows at all.
     */
    public static Map<Id, Set<Id>> resolveHelperContacts(Set<Id> supporteeContactIds) {
        Map<Id, Set<Id>> helpersBySupportee = new Map<Id, Set<Id>>();
        if (supporteeContactIds == null || supporteeContactIds.isEmpty()) {
            return helpersBySupportee;
        }

        for (Support_Relationship__c rel : [
            SELECT Contact__c, Related_Contact__c
            FROM Support_Relationship__c
            WHERE Related_Contact__c IN :supporteeContactIds
              AND Status__c = 'Approved'
              AND Contact__c != null
            WITH SYSTEM_MODE
        ]) {
            addHelper(helpersBySupportee, rel.Related_Contact__c, rel.Contact__c);
        }

        // Organization-backed: the mandate points at the Account, so the bridge
        // back to the org's Contact runs through Organization_Account__c.
        Map<Id, Set<Id>> orgContactsByAccount = new Map<Id, Set<Id>>();
        for (Contact c : [
            SELECT Id, Organization_Account__c
            FROM Contact
            WHERE Id IN :supporteeContactIds
              AND Is_Organization_Contact__c = true
              AND Organization_Account__c != null
            WITH SYSTEM_MODE
        ]) {
            if (!orgContactsByAccount.containsKey(c.Organization_Account__c)) {
                orgContactsByAccount.put(c.Organization_Account__c, new Set<Id>());
            }
            orgContactsByAccount.get(c.Organization_Account__c).add(c.Id);
        }

        if (!orgContactsByAccount.isEmpty()) {
            Set<Id> accountIds = orgContactsByAccount.keySet();
            for (Support_Relationship__c rel : [
                SELECT Contact__c, Related_Organization__c
                FROM Support_Relationship__c
                WHERE Related_Organization__c IN :accountIds
                  AND Status__c = 'Approved'
                  AND Contact__c != null
                WITH SYSTEM_MODE
            ]) {
                for (Id orgContactId : orgContactsByAccount.get(rel.Related_Organization__c)) {
                    addHelper(helpersBySupportee, orgContactId, rel.Contact__c);
                }
            }
        }

        return helpersBySupportee;
    }

    private static void addHelper(Map<Id, Set<Id>> acc, Id supporteeId, Id helperId) {
        if (supporteeId == null || helperId == null || supporteeId == helperId) {
            return;
        }
        if (!acc.containsKey(supporteeId)) {
            acc.put(supporteeId, new Set<Id>());
        }
        acc.get(supporteeId).add(helperId);
    }

    /**
     * Returns the Contacts in the set that have no active login of their own —
     * the ones whose notifications need to be fanned out to helpers.
     */
    public static Set<Id> unbackedContacts(Set<Id> contactIds, Map<Id, User> ownUserByContact) {
        Set<Id> unbacked = new Set<Id>();
        if (contactIds == null) {
            return unbacked;
        }
        for (Id contactId : contactIds) {
            if (contactId != null && (ownUserByContact == null || !ownUserByContact.containsKey(contactId))) {
                unbacked.add(contactId);
            }
        }
        return unbacked;
    }

    /* =====================================================================
     * Delivery targets
     * ===================================================================== */

    /**
     * One human, one inbox. A parent with two proxied children and their own
     * account is three separate Targets sharing one User, because each inbox
     * has its own unread count, its own deep links, and its own push card.
     */
    public class Target {
        public User u;
        public Id inboxContactId;
        public Boolean isProxy;

        public Target(User u, Id inboxContactId, Boolean isProxy) {
            this.u = u;
            this.inboxContactId = inboxContactId;
            this.isProxy = isProxy;
        }

        public Id userId() {
            return u == null ? null : u.Id;
        }

        /**
         * Stable per-inbox key. Used to keep push collapse Ids and delivery
         * bookkeeping distinct, so a child's card never replaces the parent's.
         */
        public String key() {
            return String.valueOf(userId()) + '|' + String.valueOf(inboxContactId);
        }
    }

    /**
     * Pure assembly step: given the Users already queried by the caller (each
     * batch job needs a different field list, so the queries stay with them),
     * produce the delivery targets per inbox Contact.
     */
    public static Map<Id, List<Target>> buildTargets(
        Set<Id> inboxContactIds,
        Map<Id, User> ownUserByContact,
        Map<Id, Set<Id>> helpersBySupportee,
        Map<Id, User> helperUserByContact
    ) {
        Map<Id, List<Target>> targetsByInbox = new Map<Id, List<Target>>();
        if (inboxContactIds == null || inboxContactIds.isEmpty()) {
            return targetsByInbox;
        }

        for (Id inboxContactId : inboxContactIds) {
            if (inboxContactId == null) {
                continue;
            }
            List<Target> targets = new List<Target>();

            User own = (ownUserByContact == null) ? null : ownUserByContact.get(inboxContactId);
            if (own != null) {
                targets.add(new Target(own, inboxContactId, false));
            } else if (helpersBySupportee != null && helpersBySupportee.containsKey(inboxContactId)) {
                Set<Id> seenUsers = new Set<Id>();
                for (Id helperContactId : helpersBySupportee.get(inboxContactId)) {
                    User helper = (helperUserByContact == null) ? null : helperUserByContact.get(helperContactId);
                    if (helper == null || seenUsers.contains(helper.Id)) {
                        continue;
                    }
                    seenUsers.add(helper.Id);
                    targets.add(new Target(helper, inboxContactId, true));
                }
            }

            if (!targets.isEmpty()) {
                targetsByInbox.put(inboxContactId, targets);
            }
        }
        return targetsByInbox;
    }

    /* =====================================================================
     * Identity-safe deep links
     * ===================================================================== */

    /**
     * Appends ?actAs=<supporteeContactId> so tapping a helper's push lands them
     * already looking through the right identity. Without it, a parent taps a
     * notification about their child and arrives as themselves — the record is
     * either invisible or, worse, they reply in the wrong voice.
     *
     * The parameter is advisory: the receiving route re-verifies the mandate
     * server-side before honouring it. An unrecognized query parameter is inert
     * on Experience Cloud routes, so this is safe to bake in ahead of that
     * verification landing.
     */
    public static String withActingIdentity(String actionUrl, Id supporteeContactId) {
        if (String.isBlank(actionUrl) || supporteeContactId == null) {
            return actionUrl;
        }
        if (actionUrl.contains('actAs=')) {
            return actionUrl;
        }

        // A fragment must stay at the very end of the URL or the browser keeps
        // it as part of the parameter value.
        String path = actionUrl;
        String fragment = '';
        Integer hashAt = actionUrl.indexOf('#');
        if (hashAt >= 0) {
            path = actionUrl.substring(0, hashAt);
            fragment = actionUrl.substring(hashAt);
        }

        String separator = path.contains('?') ? '&' : '?';
        return path + separator + 'actAs=' + supporteeContactId + fragment;
    }
}
