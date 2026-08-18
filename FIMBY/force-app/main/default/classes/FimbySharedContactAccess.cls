/**
 * @description Single source of truth for reading Shared_Contact_Info__c consent.
 *
 *              A share row is one person's disclosure to one other person:
 *              Contact__c is the sharer, Shared_To__c is the recipient. The row is
 *              DIRECTIONAL. Sharing your details lets the recipient start a
 *              conversation with you; it grants you nothing in return. Callers must
 *              never re-introduce an (A to B) OR (B to A) permission query.
 *
 *              A share is also an EPISODE. Once revoked it is closed forever, and
 *              sharing again inserts a new row. Only the newest row per exact
 *              direction describes the present, so every read here is
 *              newest-row-wins: a newer Revoked row must never fall back to an
 *              older Active row.
 *
 *              `without sharing` is intentional and mirrors FimbyBlockingHelper:
 *              Shared_Contact_Info__c has Private external OWD, so a community user
 *              cannot see rows where they are the recipient. Every query below is
 *              hard-scoped to a Contact Id supplied by the caller's resolved
 *              identity, so this cannot enumerate other people's shares.
 */
public without sharing class FimbySharedContactAccess {

    private static final String SNAPSHOT_FIELDS =
        'Id, Contact__c, Shared_To__c, Status__c, Origin__c, CreatedDate, ' +
        'Email__c, Phone__c, First_Name__c, Last_Name__c, Street__c, City__c, ' +
        'Province_State__c, Postal_Code__c, Country__c, Additional_Info__c, ' +
        'Contact_Neighbourhood__c, Shared_To_Neighbourhood__c';

    /**
     * @description Returns the current episode for an exact sharer to recipient
     *              direction, whatever its status. Newest row wins.
     * @param sharerContactId The Contact who disclosed (Contact__c).
     * @param recipientContactId The Contact who received (Shared_To__c).
     * @return The newest matching row, or null when the pair has never shared.
     */
    public static Shared_Contact_Info__c findCurrentEpisode(Id sharerContactId, Id recipientContactId) {
        if (sharerContactId == null || recipientContactId == null) {
            return null;
        }
        List<Shared_Contact_Info__c> rows = Database.query(
            'SELECT ' + SNAPSHOT_FIELDS +
            ' FROM Shared_Contact_Info__c' +
            ' WHERE Contact__c = :sharerContactId' +
            ' AND Shared_To__c = :recipientContactId' +
            ' ORDER BY CreatedDate DESC, Id DESC' +
            ' LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Returns the current episode only when it is still open. A newer
     *              Revoked row closes the pair even if older Active rows survive as
     *              history, so this deliberately does NOT search for any Active row.
     * @param sharerContactId The Contact who disclosed (Contact__c).
     * @param recipientContactId The Contact who received (Shared_To__c).
     * @return The current Active episode, or null.
     */
    public static Shared_Contact_Info__c findActiveEpisode(Id sharerContactId, Id recipientContactId) {
        Shared_Contact_Info__c current = findCurrentEpisode(sharerContactId, recipientContactId);
        return isOpen(current) ? current : null;
    }

    /**
     * @description Convenience gate: is there a currently-open disclosure from the
     *              sharer to the recipient?
     * @param sharerContactId The Contact who disclosed.
     * @param recipientContactId The Contact who received.
     * @return true when an open episode exists in that exact direction.
     */
    public static Boolean hasActiveEpisode(Id sharerContactId, Id recipientContactId) {
        return findActiveEpisode(sharerContactId, recipientContactId) != null;
    }

    /**
     * @description Every Contact who currently has an OPEN share TO the given
     *              recipient. This is the canonical inbound permission set behind
     *              message pickers, search expansion, adjacent visibility, and counts.
     *              Inbound only by design.
     * @param recipientContactId The viewer's Contact Id.
     * @return Set of sharer Contact Ids with an open episode to the viewer.
     */
    public static Set<Id> getActiveIncomingSharerIds(Id recipientContactId) {
        Set<Id> sharerIds = new Set<Id>();
        if (recipientContactId == null) {
            return sharerIds;
        }
        Set<Id> closed = new Set<Id>();
        for (Shared_Contact_Info__c sci : [
            SELECT Contact__c, Status__c
            FROM Shared_Contact_Info__c
            WHERE Shared_To__c = :recipientContactId
            AND Contact__c != null
            ORDER BY CreatedDate DESC, Id DESC
        ]) {
            // First row seen per sharer is the current episode; later rows are history.
            if (sharerIds.contains(sci.Contact__c) || closed.contains(sci.Contact__c)) {
                continue;
            }
            if (isOpenStatus(sci.Status__c)) {
                sharerIds.add(sci.Contact__c);
            } else {
                closed.add(sci.Contact__c);
            }
        }
        return sharerIds;
    }

    /**
     * @description Restricts a candidate set to those with an open inbound share to
     *              the viewer. Used where a broader candidate list already exists
     *              (adjacent-neighbourhood visibility) and only needs gating.
     * @param recipientContactId The viewer's Contact Id.
     * @param candidateContactIds The candidate Contact Ids to gate.
     * @return The subset that currently shares with the viewer.
     */
    public static Set<Id> filterToActiveIncomingSharers(Id recipientContactId, Set<Id> candidateContactIds) {
        Set<Id> allowed = new Set<Id>();
        if (recipientContactId == null || candidateContactIds == null || candidateContactIds.isEmpty()) {
            return allowed;
        }
        for (Id sharerId : getActiveIncomingSharerIds(recipientContactId)) {
            if (candidateContactIds.contains(sharerId)) {
                allowed.add(sharerId);
            }
        }
        return allowed;
    }

    /**
     * @description The snapshot a recipient is currently entitled to see. Returns
     *              null once the episode is revoked, so a closed share can never
     *              keep rendering an email, phone, or address.
     * @param sharerContactId The Contact who disclosed.
     * @param recipientContactId The viewer.
     * @return The open snapshot row, or null.
     */
    public static Shared_Contact_Info__c getActiveInboundSnapshot(Id sharerContactId, Id recipientContactId) {
        return findActiveEpisode(sharerContactId, recipientContactId);
    }

    /**
     * @description Status check for a known episode Id, used by the send gate where
     *              the authorizing row was already resolved and bound to a thread.
     * @param sharedContactInfoId The episode Id.
     * @return true when that specific episode is still open.
     */
    public static Boolean isEpisodeActive(Id sharedContactInfoId) {
        if (sharedContactInfoId == null) {
            return false;
        }
        List<Shared_Contact_Info__c> rows = [
            SELECT Id, Status__c
            FROM Shared_Contact_Info__c
            WHERE Id = :sharedContactInfoId
            LIMIT 1
        ];
        return !rows.isEmpty() && isOpenStatus(rows[0].Status__c);
    }

    /**
     * @description Locks one episode so consent cannot change between the gate and
     *              the conversation insert. FOR UPDATE is Id-only, as required by SOQL.
     * @param sharedContactInfoId The episode to lock.
     * @return The locked row, or null when it no longer exists.
     */
    public static Shared_Contact_Info__c lockEpisode(Id sharedContactInfoId) {
        if (sharedContactInfoId == null) {
            return null;
        }
        List<Shared_Contact_Info__c> rows = [
            SELECT Id, Status__c
            FROM Shared_Contact_Info__c
            WHERE Id = :sharedContactInfoId
            FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Bulk variant of isEpisodeActive for thread-list rendering.
     * @param sharedContactInfoIds The episode Ids to test.
     * @return The subset that is still open.
     */
    public static Set<Id> filterActiveEpisodeIds(Set<Id> sharedContactInfoIds) {
        Set<Id> open = new Set<Id>();
        if (sharedContactInfoIds == null || sharedContactInfoIds.isEmpty()) {
            return open;
        }
        for (Shared_Contact_Info__c sci : [
            SELECT Id, Status__c
            FROM Shared_Contact_Info__c
            WHERE Id IN :sharedContactInfoIds
        ]) {
            if (isOpenStatus(sci.Status__c)) {
                open.add(sci.Id);
            }
        }
        return open;
    }

    /**
     * @description True when the row represents an open consent episode. Legacy rows
     *              created before Status__c was populated are treated as Active,
     *              matching every existing reader in the app.
     * @param sci The row to test.
     * @return true when open.
     */
    public static Boolean isOpen(Shared_Contact_Info__c sci) {
        return sci != null && isOpenStatus(sci.Status__c);
    }

    private static Boolean isOpenStatus(String status) {
        return status == null || status == FimbyConstants.SHARED_CONTACT_ACTIVE;
    }
}
