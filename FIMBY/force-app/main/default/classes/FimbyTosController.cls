/**
 * @description Controller for the Terms of Service / Community Group Agreement
 * acceptance surfaces. Reads the current TOS / CGA version + effective date from
 * FIMBY_App_Settings__mdt (so legal can bump the version without a code deploy)
 * and writes acceptance stamps onto Contact (TOS + age attestation) or Account (CGA).
 *
 * Both TOS-acceptance paths (Login Flow checkbox via fimbyTosFlowScreen, and the
 * paper-form approval path via recordPaperAcceptance) also stamp age attestation
 * in the same DML — the consent the user gave is "I have read the Terms AND I am
 * 19 or older", so the two stamps live or die together.
 *
 * Used by:
 *   - Fimby_Tos_Acceptance_Login_Flow + fimbyTosFlowScreen LWC (Surface 2)
 *   - fimbyManageIdentities CGA block (Surface 3)
 *   - FimbySupportRelationshipTriggerHandler on paper-form approval (Surface 4),
 *     via recordPaperAcceptance — not @AuraEnabled, idempotent.
 */
public with sharing class FimbyTosController {

    private static final String SOURCE_LOGIN_FLOW = 'Login Flow';
    private static final String SOURCE_PAPER_FORM = 'Support Relationship Paper Form';

    // ---- CMD reads (cacheable so LWC can wire them) ----

    @AuraEnabled(cacheable=true)
    public static String getCurrentTosVersion() {
        return FimbySettings.tosCurrentVersion();
    }

    @AuraEnabled(cacheable=true)
    public static Date getCurrentTosEffectiveDate() {
        return FimbySettings.tosEffectiveDate();
    }

    @AuraEnabled(cacheable=true)
    public static String getCurrentCgaVersion() {
        return FimbySettings.cgaCurrentVersion();
    }

    @AuraEnabled(cacheable=true)
    public static Date getCurrentCgaEffectiveDate() {
        return FimbySettings.cgaEffectiveDate();
    }

    /**
     * @description Records the running user's acceptance of the current TOS on
     * their own Contact. Called from the Login Flow once fimbyTosFlowScreen
     * returns accepted = true. Always writes the live current version, even
     * if the LWC passed a stale version (the canonical source is CMD).
     * @param version Version string the user just acknowledged. Compared to the
     *                current CMD value; if mismatched, the live value is used.
     * @param source 'Login Flow' is the only valid value here. Paper-form
     *               acceptances flow through recordPaperAcceptance instead.
     */
    @AuraEnabled
    public static void acceptTos(String version, String source) {
        try {
            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            String live = FimbySettings.tosCurrentVersion();
            String versionToWrite = String.isNotBlank(live) ? live : version;
            String sourceToWrite = SOURCE_LOGIN_FLOW;
            if (String.isNotBlank(source)) {
                sourceToWrite = source;
            }

            new TosAcceptanceWriter().write(
                currentUser.ContactId,
                versionToWrite,
                sourceToWrite,
                null
            );
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error recording TOS acceptance: ' + e.getMessage());
        }
    }

    /**
     * @description Records CGA acceptance on the Organization Account. Called
     * from fimbyManageIdentities when a user creates or claims an org. The
     * "Accepted By" lookup always points to the realContactId (the human at
     * the keyboard), not the represented identity, per the architecture rule.
     * @param accountId Organization Account being created or claimed.
     * @param version Version string the user just acknowledged. Compared to
     *                the current CMD value; live value wins on mismatch.
     */
    @AuraEnabled
    public static void acceptCga(Id accountId, String version) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account Id is required to record CGA acceptance.');
            }
            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            String live = FimbySettings.cgaCurrentVersion();
            String versionToWrite = String.isNotBlank(live) ? live : version;

            new CgaAcceptanceWriter().write(
                accountId,
                versionToWrite,
                currentUser.ContactId
            );
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error recording CGA acceptance: ' + e.getMessage());
        }
    }

    /**
     * @description Idempotent helper used by FimbySupportRelationshipTriggerHandler
     * when a paper-form Support_Relationship__c is approved. Stamps the supportee
     * Contact's Tos_* fields. Null-checks Tos_Accepted_Date__c first so a
     * trigger re-fire never overwrites an earlier acceptance.
     * Not @AuraEnabled — only invoked from server-side trigger context.
     * @param contactId Supportee Contact whose acceptance is being recorded.
     * @param signedDate Date the supportee physically signed the paper form.
     *                   Promoted to a DateTime at midnight UTC for the stamp.
     * @param version Version string from the printed form.
     * @param contentDocId ContentDocumentId of the uploaded scan; stored on
     *                     Tos_Acceptance_Form_Id__c for audit.
     */
    public static void recordPaperAcceptance(
        Id contactId,
        Date signedDate,
        String version,
        Id contentDocId
    ) {
        if (contactId == null) return;

        new TosAcceptanceWriter().writePaper(
            contactId,
            signedDate,
            version,
            contentDocId
        );
    }

    /**
     * @description Inner without-sharing helper that performs the actual
     * Contact DML for TOS acceptance. Isolated so that customer-community
     * users can update their own Tos_* fields even if their CRUD permissions
     * are restricted.
     */
    private without sharing class TosAcceptanceWriter {
        public void write(Id contactId, String version, String source, Id formId) {
            // Stamp TOS + age attestation in one DML — the user just confirmed
            // both halves of the combined "I have read the Terms AND I am 19 or
            // older" checkbox in fimbyTosFlowScreen. Age source mirrors the TOS
            // source value so the two stay aligned. Age_Attestation_Date__c is
            // a DateTime (matches the FIMBY_Sign_Up flow's stamp shape).
            DateTime nowStamp = System.now();
            Contact c = new Contact(
                Id = contactId,
                Tos_Accepted_Date__c = nowStamp,
                Tos_Version_Accepted__c = version,
                Tos_Acceptance_Source__c = source,
                Tos_Acceptance_Form_Id__c = formId,
                Tos_Reacceptance_Required__c = false,
                Age_Attestation_Confirmed__c = true,
                Age_Attestation_Date__c = nowStamp,
                Age_Attestation_Source__c = source
            );
            update c;
        }

        public void writePaper(Id contactId, Date signedDate, String version, Id contentDocId) {
            List<Contact> existing = [
                SELECT Id, Tos_Accepted_Date__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            if (existing.isEmpty()) return;
            if (existing[0].Tos_Accepted_Date__c != null) {
                return;
            }

            DateTime stamp;
            if (signedDate != null) {
                stamp = DateTime.newInstanceGmt(
                    signedDate.year(), signedDate.month(), signedDate.day(),
                    0, 0, 0
                );
            } else {
                stamp = System.now();
            }

            String contentDocIdStr = (contentDocId != null) ? String.valueOf(contentDocId) : null;

            // Stamp TOS + age attestation in one DML. The supportee initialed
            // Block C of the paper form, which now includes a "I am 19 or
            // older" line — see FimbyAuthorizedSupporterForm.page Block C.
            // Idempotent guard above prevents this from overwriting an earlier
            // stamp on trigger re-fire. Age stamp uses the same DateTime as
            // Tos_Accepted_Date__c so the two fields tell a consistent story.
            Contact c = new Contact(
                Id = contactId,
                Tos_Accepted_Date__c = stamp,
                Tos_Version_Accepted__c = version,
                Tos_Acceptance_Source__c = SOURCE_PAPER_FORM,
                Tos_Acceptance_Form_Id__c = contentDocIdStr,
                Tos_Reacceptance_Required__c = false,
                Age_Attestation_Confirmed__c = true,
                Age_Attestation_Date__c = stamp,
                Age_Attestation_Source__c = SOURCE_PAPER_FORM
            );
            update c;
        }
    }

    /**
     * @description Inner without-sharing helper for the Account-side CGA
     * stamp. Same isolation pattern as TosAcceptanceWriter.
     */
    private without sharing class CgaAcceptanceWriter {
        public void write(Id accountId, String version, Id realContactId) {
            Account a = new Account(
                Id = accountId,
                CGA_Accepted_Date__c = System.now(),
                CGA_Version__c = version,
                CGA_Accepted_By__c = realContactId
            );
            update a;

            // CG auto-vouch: the org's primary Organization Contact is implicitly
            // vouched once the CGA is accepted (the organization itself vouched
            // for them via the CGA acceptance, which is a stronger vetting path
            // than peer vouching).
            try {
                Account orgWithContact = [
                    SELECT Id, Organization_Contact__c FROM Account
                    WHERE Id = :accountId AND Organization_Contact__c != null
                    LIMIT 1
                ];
                if (orgWithContact.Organization_Contact__c != null) {
                    update new Contact(
                        Id = orgWithContact.Organization_Contact__c,
                        Vouched_Status__c = 'Vouched',
                        Vouched_By_Organization__c = accountId,
                        Vouched_Date__c = System.now(),
                        Vouched_By_Moderator__c = false,
                        Vouch_Source__c = 'Community_Group_Auto'
                    );
                }
            } catch (Exception e) {
                FimbyLogger.error('FimbyTosController.CgaAcceptanceWriter', 'autoVouch', e);
            }
        }
    }
}
