/**
 * @description Centralises the repeated "who is the current user?" query pattern
 * found across 14+ controllers. Caches identity data for the duration of a
 * single transaction so the same SOQL is never run twice in the same request.
 */
public with sharing class FimbyIdentityRepository {

    private static User cachedUser;
    private static Contact cachedContact;
    private static Id cachedActingAsId;
    private static Contact cachedActingAsContact;

    /**
     * @description Wrapper holding the fully-resolved identity context.
     */
    public class Identity {
        public User currentUser;
        public Contact contact;
        public Contact actingAsContact;
        public Id actingAsContactId;
        public Id neighbourhoodId;
        public Boolean isOrgContact;
        public String orgDisplayName;
        public String orgAvatarUrl;
    }

    /**
     * @description Returns the running platform User with their ContactId and
     *              commonly-needed related Contact fields. Result is cached.
     * @return User record for the current running user
     */
    public static User getCurrentUser() {
        if (cachedUser != null) {
            return cachedUser;
        }
        cachedUser = [
            SELECT Id, ContactId, User_ID_18_Digits__c,
                   Contact.AccountId, Contact.Account.Name,
                   Contact.Account.Adjacent_Neighbourhood_Ids__c,
                   Contact.Logged_In_As_Contact__c,
                   Contact.Logged_In_As_Neighbourhood__c,
                   Contact.Name, Contact.FirstName, Contact.LastName,
                   Contact.Image_URL__c,
                   Contact.Is_Organization_Contact__c,
                   Contact.Organization_Account__c,
                   Contact.Organization_Account__r.Name,
                   Contact.Organization_Account__r.Logo_URL__c,
                   Contact.Tos_Reacceptance_Required__c,
                   Contact.Tos_Accepted_Date__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return cachedUser;
    }

    /**
     * @description Resolves the "acting as" Contact Id using the
     *              Logged_In_As_Contact__c Lookup override. If set and the
     *              backing Support_Relationship__c is still Approved, that
     *              value is returned; otherwise the Contact's own Id is
     *              returned and stale overrides are lazily cleared.
     * @return Id of the Contact the user is acting as
     */
    public static Id getActingAsContactId() {
        if (cachedActingAsId != null) {
            return cachedActingAsId;
        }
        User u = getCurrentUser();
        if (u.ContactId == null) {
            return null;
        }
        if (u.Contact.Logged_In_As_Contact__c != null) {
            if (hasApprovedRelationship(u.ContactId, u.Contact.Logged_In_As_Contact__c)) {
                cachedActingAsId = u.Contact.Logged_In_As_Contact__c;
            } else {
                clearIdentityOverride(u.ContactId);
                cachedActingAsId = u.ContactId;
            }
        } else {
            cachedActingAsId = u.ContactId;
        }
        return cachedActingAsId;
    }

    /**
     * @description Checks whether an approved Support_Relationship__c exists
     *              linking the helper to the target identity.
     */
    private static Boolean hasApprovedRelationship(Id helperContactId, Id targetContactId) {
        List<Support_Relationship__c> rels = [
            SELECT Id FROM Support_Relationship__c
            WHERE Contact__c = :helperContactId
              AND Related_Contact__c = :targetContactId
              AND Status__c = 'Approved'
            LIMIT 1
        ];
        if (!rels.isEmpty()) {
            return true;
        }
        List<Contact> orgContacts = [
            SELECT Organization_Account__c FROM Contact
            WHERE Id = :targetContactId AND Is_Organization_Contact__c = true
            LIMIT 1
        ];
        if (!orgContacts.isEmpty() && orgContacts[0].Organization_Account__c != null) {
            Id orgAccountId = orgContacts[0].Organization_Account__c;
            List<Support_Relationship__c> orgRels = [
                SELECT Id FROM Support_Relationship__c
                WHERE Contact__c = :helperContactId
                  AND Related_Organization__c = :orgAccountId
                  AND Status__c = 'Approved'
                LIMIT 1
            ];
            return !orgRels.isEmpty();
        }
        return false;
    }

    /**
     * @description Lazily clears stale identity override fields when the
     *              backing relationship is no longer approved.
     */
    private static void clearIdentityOverride(Id contactId) {
        try {
            Contact c = new Contact(
                Id = contactId,
                Logged_In_As_Contact__c = null,
                Logged_In_As_Neighbourhood__c = null
            );
            update c;
        } catch (Exception e) {
            FimbyLogger.error('FimbyIdentityRepository', 'clearIdentityOverride', e);
        }
    }

    /**
     * @description Returns the current user's Contact record with all
     *              commonly-needed fields. Uses the cached User query.
     * @return Contact record for the current user
     */
    public static Contact getCurrentContact() {
        if (cachedContact != null) {
            return cachedContact;
        }
        User u = getCurrentUser();
        if (u.ContactId == null) {
            return null;
        }
        cachedContact = u.Contact;
        return cachedContact;
    }

    /**
     * @description Returns the neighbourhood (Account) Id for the current
     *              user's active identity context. Checks the neighbourhood
     *              override first (set during identity switching), then falls
     *              back to the Contact's own AccountId.
     * @return Id of the neighbourhood Account for the active identity
     */
    public static Id getNeighbourhoodId() {
        User u = getCurrentUser();
        if (u.ContactId == null) {
            return null;
        }
        if (u.Contact.Logged_In_As_Neighbourhood__c != null) {
            return u.Contact.Logged_In_As_Neighbourhood__c;
        }
        return u.Contact.AccountId;
    }

    /**
     * @description Builds the org-aware display name: "ORG NAME (FirstName)"
     *              when both parts are available, otherwise whichever is non-blank.
     */
    public static String buildOrgDisplayName(String orgName, String realFirstName) {
        if (String.isBlank(orgName)) return realFirstName;
        if (String.isBlank(realFirstName)) return orgName;
        return orgName + ' (' + realFirstName + ')';
    }

    /**
     * @description Resolves the acting-as Contact record with org fields.
     *              When acting as self, returns the real contact. When acting
     *              as another identity, queries the acting-as Contact once and caches it.
     */
    public static Contact resolveActingAsContact() {
        if (cachedActingAsContact != null) {
            return cachedActingAsContact;
        }
        Contact realContact = getCurrentContact();
        Id actingAsId = getActingAsContactId();

        if (actingAsId == null || actingAsId == realContact?.Id) {
            cachedActingAsContact = realContact;
        } else {
            cachedActingAsContact = [
                SELECT Id, Name, FirstName, LastName, AccountId, Account.Name,
                       Image_URL__c, Is_Organization_Contact__c,
                       Organization_Account__c,
                       Organization_Account__r.Name,
                       Organization_Account__r.Logo_URL__c
                FROM Contact
                WHERE Id = :actingAsId
                LIMIT 1
            ];
        }
        return cachedActingAsContact;
    }

    /**
     * @description Returns a full Identity wrapper with user, contact,
     *              acting-as contact, and pre-computed org display fields.
     * @return Identity wrapper with all resolved identity fields
     */
    public static Identity getIdentity() {
        Identity ident = new Identity();
        ident.currentUser = getCurrentUser();
        ident.contact = getCurrentContact();
        ident.actingAsContactId = getActingAsContactId();
        ident.neighbourhoodId = getNeighbourhoodId();
        ident.actingAsContact = resolveActingAsContact();

        ident.isOrgContact = ident.actingAsContact?.Is_Organization_Contact__c == true;
        if (ident.isOrgContact) {
            ident.orgDisplayName = buildOrgDisplayName(
                ident.actingAsContact.Organization_Account__r?.Name,
                ident.contact?.FirstName
            );
            ident.orgAvatarUrl = ident.actingAsContact.Organization_Account__r?.Logo_URL__c;
        } else {
            ident.orgDisplayName = ident.actingAsContact?.Name;
            ident.orgAvatarUrl = ident.actingAsContact?.Image_URL__c;
        }

        return ident;
    }

    /**
     * @description Clears the cached identity data. Useful in test contexts
     *              where System.runAs changes the running user mid-transaction.
     */
    public static void clearCache() {
        cachedUser = null;
        cachedContact = null;
        cachedActingAsId = null;
        cachedActingAsContact = null;
    }
}
