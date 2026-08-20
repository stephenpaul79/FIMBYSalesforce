/**
 * @description Creates and confirms parent-managed (proxied) family profiles.
 *
 * A parent-managed profile is a Contact with a visible presence and no User. The
 * guardian always logs in as themselves and switches into the child, so every action
 * carries both identities. That is why this path is deliberately separate from the
 * paper-consent Support_Person flow in FimbySupportRelationshipController: the
 * supportee here cannot consent, so the guardian's attestation is the entire legal
 * basis and it must be captured, versioned, and echoed back.
 *
 * Three things make the auto-approval safe rather than merely convenient:
 *   1. The attestation is stamped with the version of the wording actually shown, so
 *      a record proves what was agreed to rather than that something was agreed to.
 *   2. A security receipt is sent to the guardian immediately. If an account is
 *      compromised, silently gaining a second identity would be the ideal attack;
 *      the receipt makes it loud.
 *   3. A passive Moderator_Task__c lands in the queue. Nobody is blocked waiting for
 *      it, but no profile is created without a human eventually seeing it.
 *
 * @see FimbyProxiedPresenceGuard for what a proxied child may and may not do.
 */
public with sharing class FimbyParentGuardianService {

    /** Under 19 matches Contact.Is_Minor__c, which is advisory-only for badges. */
    private static final Integer FIMBY_ADULT_AGE = 19;
    /** A birthdate older than this is a typo, not a child. */
    private static final Integer OLDEST_PLAUSIBLE_YEARS = 120;

    /**
     * AuraHandledException reports a generic "Script-thrown exception" from getMessage()
     * unless setMessage is also called, which would leave both the neighbour and any
     * test reading a message that says nothing. Every refusal here goes through this so
     * the reason survives to the client.
     */
    private static AuraHandledException refuse(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    public class FamilyMemberInput {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public Date birthdate { get; set; }
        @AuraEnabled public Boolean attested { get; set; }
    }

    public class FamilyMemberResult {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id relationshipId { get; set; }
        @AuraEnabled public String displayName { get; set; }
    }

    /**
     * @description Creates the child Contact and its approved Parent_Guardian
     *              relationship in one transaction, then fires the receipt and the
     *              passive review task.
     * @param input First name, birthdate, and the guardian's attestation checkbox.
     * @return The new Contact and relationship Ids, for the optional photo step.
     */
    @AuraEnabled
    public static FamilyMemberResult createFamilyMember(FamilyMemberInput input) {
        try {
            if (input == null) {
                throw refuse('Please tell us about the family member you\'re adding.');
            }
            if (String.isBlank(input.firstName)) {
                throw refuse('Please add a first name.');
            }
            if (input.birthdate == null) {
                throw refuse('Please add a date of birth so we know this is a young person.');
            }
            if (input.attested != true) {
                throw refuse(
                    'Please confirm you\'re the parent or guardian before we set this up.'
                );
            }

            Date today = Date.today();
            if (input.birthdate > today) {
                throw refuse('That date of birth is in the future. Please check it.');
            }
            if (input.birthdate.addYears(OLDEST_PLAUSIBLE_YEARS) < today) {
                throw refuse('That date of birth doesn\'t look right. Please check it.');
            }
            // A profile is parent-managed because the person is a minor. Letting an
            // adult be created this way would hand one neighbour a durable, silent
            // login-as over another with no consent record anywhere.
            if (input.birthdate.addYears(FIMBY_ADULT_AGE) <= today) {
                throw refuse(
                    'This person is 19 or older, so they set up their own FIMBY profile. '
                    + 'If they need help using it, add them as a support relationship instead.'
                );
            }

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw refuse('No Contact associated with current user');
            }

            Contact guardian = new GuardianReader().read(currentUser.ContactId);
            if (guardian.AccountId == null) {
                throw refuse(
                    'We couldn\'t work out your neighbourhood. Please contact support.'
                );
            }
            // A guardian is a neighbour in their own right. Someone already being acted
            // for cannot themselves take on a child.
            if (guardian.Is_Parent_Proxied__c == true) {
                throw refuse(
                    'A parent-managed profile can\'t add a family member. Switch back to yourself first.'
                );
            }

            Id neighbourhoodId = guardian.AccountId;
            String attestationVersion = FimbySettings.guardianAttestationVersion();

            Contact child = new Contact(
                FirstName = input.firstName.trim(),
                // Shares the guardian's family name so the child reads as a neighbour
                // rather than a bare first name, without asking for it twice.
                LastName = guardian.LastName,
                Birthdate = input.birthdate,
                AccountId = neighbourhoodId,
                Is_Parent_Proxied__c = true,
                Proxied_By_Contact__c = guardian.Id
            );

            Support_Relationship__c rel = new Support_Relationship__c(
                Relationship_Type__c = 'Parent_Guardian',
                Contact__c = guardian.Id,
                Neighbourhood__c = neighbourhoodId,
                Status__c = 'Approved',
                Consent_Method__c = 'Guardian',
                Approved_Date__c = Datetime.now(),
                Approved_By__c = guardian.Id,
                Guardian_Attested__c = true,
                Guardian_Attested_Date__c = Datetime.now(),
                Guardian_Attested_By_Contact__c = guardian.Id,
                Guardian_Attestation_Version__c = attestationVersion
            );

            new FamilyMemberWriter().create(child, rel);

            String childName = child.FirstName;
            FamilyMemberResult result = new FamilyMemberResult();
            result.contactId = child.Id;
            result.relationshipId = rel.Id;
            result.displayName = childName;

            // Both side effects are best-effort: a failed receipt or review task must
            // not roll back a profile the guardian has already been told is theirs.
            sendSecurityReceipt(guardian, childName, rel.Id);
            openPassiveReview(guardian, child.Id, childName, neighbourhoodId, rel.Id);

            return result;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbyParentGuardianService', 'createFamilyMember', e);
            throw refuse('We couldn\'t set up that profile: ' + e.getMessage());
        }
    }

    /**
     * @description Records that the guardian saw the receipt and confirmed the profile
     *              was theirs. The value matters more than the history: an unconfirmed
     *              relationship days later is the signal worth looking at.
     * @param relationshipId The Parent_Guardian relationship being confirmed.
     */
    @AuraEnabled
    public static void confirmGuardianEcho(Id relationshipId) {
        try {
            if (relationshipId == null) {
                throw refuse('Nothing to confirm.');
            }
            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw refuse('No Contact associated with current user');
            }

            List<Support_Relationship__c> rels = [
                SELECT Id, Contact__c, Guardian_Echo_Confirmed__c
                FROM Support_Relationship__c
                WHERE Id = :relationshipId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (rels.isEmpty() || rels[0].Contact__c != currentUser.ContactId) {
                throw refuse('That profile isn\'t yours to confirm.');
            }
            if (rels[0].Guardian_Echo_Confirmed__c == true) {
                return;
            }

            new FamilyMemberWriter().confirmEcho(relationshipId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbyParentGuardianService', 'confirmGuardianEcho', e, relationshipId);
            throw refuse('We couldn\'t record that confirmation.');
        }
    }

    /**
     * Gaining a second identity is exactly what a compromised account would want to do
     * quietly, so the guardian is told plainly and given somewhere to go.
     */
    private static void sendSecurityReceipt(Contact guardian, String childName, Id relationshipId) {
        try {
            FimbyNotificationService.createNotification(
                guardian.Id,
                'Relationship_Approved',
                childName + '\'s profile is ready',
                'You set up a parent-managed profile for ' + childName
                    + '. You\'ll be posting and replying as ' + childName
                    + ' whenever you switch to it. If you didn\'t do this, let us know right away.',
                relationshipId,
                'Support_Relationship__c',
                '/manage-identities',
                null
            );
        } catch (Exception e) {
            FimbyLogger.error('FimbyParentGuardianService', 'sendSecurityReceipt', e, relationshipId);
        }
    }

    private static void openPassiveReview(
        Contact guardian,
        Id childId,
        String childName,
        Id neighbourhoodId,
        Id relationshipId
    ) {
        try {
            FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
            req.neighbourhoodId = neighbourhoodId;
            req.category = 'Parent_Managed_Profile';
            req.priority = 'Standard';
            req.subjectContactId = guardian.Id;
            req.secondaryContactId = childId;
            req.relatedRecordId = String.valueOf(relationshipId);
            req.relatedRecordType = 'Support_Relationship__c';
            req.summary = guardian.Name + ' set up a parent-managed profile for ' + childName + '.';
            req.sourceType = 'Lifecycle_Request';
            req.sourceRecordId = String.valueOf(relationshipId);
            req.reporterContactId = guardian.Id;
            FimbyModeratorTaskService.createOrUpdateTask(req);
        } catch (Exception e) {
            FimbyLogger.error('FimbyParentGuardianService', 'openPassiveReview', e, relationshipId);
        }
    }

    /**
     * Reads the guardian's own record. `without sharing` because Is_Parent_Proxied__c
     * and AccountId decide whether the caller may create a profile at all — a sharing
     * gap would fail the check open rather than closed.
     */
    private without sharing class GuardianReader {
        public Contact read(Id contactId) {
            return [
                SELECT Id, Name, LastName, AccountId, Is_Parent_Proxied__c
                FROM Contact
                WHERE Id = :contactId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        }
    }

    /**
     * The child Contact and its relationship are written in system mode for the same
     * reason the paper-draft supportee is: a community user has no create permission on
     * Contact, and the record being created is precisely the one that will grant them
     * access to it.
     */
    private without sharing class FamilyMemberWriter {
        public void create(Contact child, Support_Relationship__c rel) {
            Database.insert(child, AccessLevel.SYSTEM_MODE);
            rel.Related_Contact__c = child.Id;
            Database.insert(rel, AccessLevel.SYSTEM_MODE);
        }

        public void confirmEcho(Id relationshipId) {
            Database.update(
                new Support_Relationship__c(
                    Id = relationshipId,
                    Guardian_Echo_Confirmed__c = true,
                    Guardian_Echo_Confirmed_Date__c = Datetime.now()
                ),
                AccessLevel.SYSTEM_MODE
            );
        }
    }
}
