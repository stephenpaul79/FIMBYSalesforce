/**
 * @description Keeps the no-orphan invariant for parent-managed profiles: a child
 * profile must never outlive its last Approved Parent_Guardian mandate.
 *
 * The order of operations matters more than it looks. A pre-delete check cannot work,
 * because Salesforce hands the deactivation batch its Contacts in chunks and two
 * guardians of the same child can land in different chunks — each one would see the
 * other still standing and conclude the child was safe. So the caller captures
 * candidate children while the mandates still exist, deletes its own chunk's
 * mandates, and only then asks who is left. Whichever chunk removes the final mandate
 * is the one that sees zero survivors, no matter how the chunks were split.
 *
 * Declared without sharing because one guardian has no visibility of another
 * guardian's master-detail relationship row, and the whole point of this class is to
 * reason about mandates the running user cannot see.
 *
 * Deliberately has no @AuraEnabled methods. The only client-facing surface is
 * FimbyProfileController.getManagedProfilesAtRisk, which resolves the guardian Contact
 * server-side rather than accepting one from the browser.
 *
 * @see FimbyAccountDeactivationBatch for the scrub-time caller.
 * @see FimbyParentGuardianService for the guardian-initiated removal of one profile.
 */
public without sharing class FimbyManagedProfileCascadeService {

    public class CascadeException extends Exception {}

    private static final String STATUS_APPROVED = 'Approved';

    /** Used when a child Contact has no first name to put in confirmation copy. */
    private static final String UNNAMED_PROFILE_LABEL = 'A family member';

    /**
     * Forces resolveAfterGuardianRemoval to throw, so a test can prove the batch rolls
     * the whole chunk back rather than scrubbing a guardian whose child never got
     * flagged. There is no natural way to fail this step on demand.
     */
    @TestVisible
    private static Boolean throwOnResolveForTest = false;

    /**
     * @description The outcome of a single resolve pass, so the batch can merge
     * orphans into its own cleanup set and log what it did.
     */
    public class CascadeResult {
        /** Children whose last Approved mandate is gone; flagged for erasure. */
        public Set<Id> orphanIds = new Set<Id>();
        /** Children that kept a guardian but needed a new display parent. */
        public Set<Id> repairedChildIds = new Set<Id>();
    }

    /**
     * @description One parent-managed profile that would be erased if a given
     * guardian left. Properties are @AuraEnabled so the profile controller can hand
     * them straight to the Settings modal.
     */
    public class ManagedProfileRisk {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String firstName { get; set; }
    }

    /**
     * @description Parent-managed children currently held up by any of these adults.
     *
     * Must be called BEFORE the caller deletes its mandates, since it reads the very
     * rows the caller is about to remove.
     *
     * @param departingContactIds Adult Contacts whose mandates are about to go.
     * @return Distinct child Contact Ids still flagged Is_Parent_Proxied__c.
     */
    public static Set<Id> candidateChildrenOf(Set<Id> departingContactIds) {
        Set<Id> children = new Set<Id>();
        if (departingContactIds == null || departingContactIds.isEmpty()) {
            return children;
        }

        for (Support_Relationship__c rel : [
            SELECT Related_Contact__c
            FROM Support_Relationship__c
            WHERE Contact__c IN :departingContactIds
              AND Status__c = :STATUS_APPROVED
              AND Relationship_Type__c = :FimbyProxiedPresenceGuard.TYPE_PARENT_GUARDIAN
              AND Related_Contact__c != NULL
              AND Related_Contact__r.Is_Parent_Proxied__c = true
            WITH SYSTEM_MODE
        ]) {
            children.add(rel.Related_Contact__c);
        }
        return children;
    }

    /**
     * @description Decides what happened to each candidate now that the caller's
     * mandates are gone: orphaned and flagged for erasure, or still held by someone
     * and possibly needing a new display parent.
     *
     * Throws rather than swallowing a DML failure. The caller removes guardian
     * mandates before calling this, so a silent failure here is exactly the orphan
     * state this class exists to prevent — better to roll the whole chunk back.
     *
     * @param candidateChildIds Output of candidateChildrenOf, captured pre-delete.
     * @return Orphaned and repaired child Ids.
     */
    public static CascadeResult resolveAfterGuardianRemoval(Set<Id> candidateChildIds) {
        if (throwOnResolveForTest) {
            throw new CascadeException('Forced cascade failure for test.');
        }

        CascadeResult result = new CascadeResult();
        if (candidateChildIds == null || candidateChildIds.isEmpty()) {
            return result;
        }

        // A candidate that is no longer proxied was already scrubbed (or was never a
        // real managed profile), so it is not ours to erase.
        Map<Id, Contact> childById = new Map<Id, Contact>([
            SELECT Id, Proxied_By_Contact__c
            FROM Contact
            WHERE Id IN :candidateChildIds
              AND Is_Parent_Proxied__c = true
            WITH SYSTEM_MODE
        ]);
        if (childById.isEmpty()) {
            return result;
        }

        Map<Id, Set<Id>> guardiansByChild = new Map<Id, Set<Id>>();
        Map<Id, Id> replacementParentByChild = new Map<Id, Id>();

        // Oldest mandate first, then lowest Id, so the replacement display parent is
        // deterministic and a re-run cannot pick a different adult.
        for (Support_Relationship__c rel : [
            SELECT Contact__c, Related_Contact__c
            FROM Support_Relationship__c
            WHERE Related_Contact__c IN :childById.keySet()
              AND Status__c = :STATUS_APPROVED
              AND Relationship_Type__c = :FimbyProxiedPresenceGuard.TYPE_PARENT_GUARDIAN
              AND Contact__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!guardiansByChild.containsKey(rel.Related_Contact__c)) {
                guardiansByChild.put(rel.Related_Contact__c, new Set<Id>());
                replacementParentByChild.put(rel.Related_Contact__c, rel.Contact__c);
            }
            guardiansByChild.get(rel.Related_Contact__c).add(rel.Contact__c);
        }

        Set<Id> orphanIds = new Set<Id>();
        List<Contact> repairs = new List<Contact>();

        for (Id childId : childById.keySet()) {
            Set<Id> guardians = guardiansByChild.get(childId);
            if (guardians == null || guardians.isEmpty()) {
                orphanIds.add(childId);
                continue;
            }
            // Only touch the display parent when it stopped pointing at someone who
            // is actually still a guardian; an untouched pointer stays untouched.
            Id displayParent = childById.get(childId).Proxied_By_Contact__c;
            if (displayParent == null || !guardians.contains(displayParent)) {
                repairs.add(new Contact(
                    Id = childId,
                    Proxied_By_Contact__c = replacementParentByChild.get(childId)
                ));
            }
        }

        if (!repairs.isEmpty()) {
            Database.update(repairs, AccessLevel.SYSTEM_MODE);
            for (Contact repaired : repairs) {
                result.repairedChildIds.add(repaired.Id);
            }
        }

        if (!orphanIds.isEmpty()) {
            FimbyParentGuardianService.eraseOrphanedProfiles(orphanIds);
            result.orphanIds.addAll(orphanIds);
        }

        return result;
    }

    /**
     * @description Parent-managed profiles that would be erased if this guardian
     * deleted their account. Read-only; drives confirmation copy only.
     *
     * A co-guardian who is themselves already leaving does not count as a dependable
     * remaining guardian. That makes this deliberately more pessimistic than the
     * batch, which only counts adults it is actually scrubbing: if that co-guardian
     * restores within their grace window the child survives and this warning turns
     * out to have been cautious. Over-warning is the right direction — a surprise
     * warning costs a moment of concern, a missing one costs a child's profile with
     * no notice at all.
     *
     * @param guardianContactId The departing guardian, resolved server-side.
     * @return Child Id and first name per at-risk profile; empty when none.
     */
    public static List<ManagedProfileRisk> atRiskIfGuardianDeparts(Id guardianContactId) {
        List<ManagedProfileRisk> risks = new List<ManagedProfileRisk>();
        if (guardianContactId == null) {
            return risks;
        }

        Set<Id> childIds = candidateChildrenOf(new Set<Id>{ guardianContactId });
        if (childIds.isEmpty()) {
            return risks;
        }

        Map<Id, Set<Id>> dependableByChild = new Map<Id, Set<Id>>();
        for (Support_Relationship__c rel : [
            SELECT Contact__c, Related_Contact__c,
                   Contact__r.Deactivation_Requested__c, Contact__r.Grace_Started_At__c
            FROM Support_Relationship__c
            WHERE Related_Contact__c IN :childIds
              AND Contact__c != :guardianContactId
              AND Contact__c != NULL
              AND Status__c = :STATUS_APPROVED
              AND Relationship_Type__c = :FimbyProxiedPresenceGuard.TYPE_PARENT_GUARDIAN
            WITH SYSTEM_MODE
        ]) {
            Boolean alreadyLeaving = rel.Contact__r.Deactivation_Requested__c == true
                || rel.Contact__r.Grace_Started_At__c != null;
            if (alreadyLeaving) {
                continue;
            }
            if (!dependableByChild.containsKey(rel.Related_Contact__c)) {
                dependableByChild.put(rel.Related_Contact__c, new Set<Id>());
            }
            dependableByChild.get(rel.Related_Contact__c).add(rel.Contact__c);
        }

        Set<Id> exposedIds = new Set<Id>();
        for (Id childId : childIds) {
            Set<Id> dependable = dependableByChild.get(childId);
            if (dependable == null || dependable.isEmpty()) {
                exposedIds.add(childId);
            }
        }
        if (exposedIds.isEmpty()) {
            return risks;
        }

        for (Contact child : [
            SELECT Id, FirstName
            FROM Contact
            WHERE Id IN :exposedIds
            WITH SYSTEM_MODE
            ORDER BY FirstName ASC NULLS LAST, Id ASC
        ]) {
            ManagedProfileRisk risk = new ManagedProfileRisk();
            risk.contactId = child.Id;
            risk.firstName = String.isBlank(child.FirstName)
                ? UNNAMED_PROFILE_LABEL
                : child.FirstName;
            risks.add(risk);
        }
        return risks;
    }
}
