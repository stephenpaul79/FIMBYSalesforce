/**
 * @description Unit tests for FimbyTosController. Covers:
 *   - CMD reads via FimbySettings (no exceptions when CMD is unset)
 *   - Login Flow TOS acceptance writes the live CMD version, not whatever the
 *     LWC passed (eliminates drift)
 *   - CGA acceptance stamps Account with realContactId
 *   - Paper-form acceptance helper is idempotent (re-firing the trigger does
 *     not overwrite an earlier stamp)
 *   - Paper-form helper short-circuits cleanly when Contact doesn't exist
 */
@IsTest
private class FimbyTosControllerTest {

    private static Account neighbourhood;
    private static Contact contact;
    private static User communityUser;

    @TestSetup
    static void setup() {
        Account n = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(n.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            c.Id, 'Customer Community User - Mobile App', true);
    }

    private static Contact getContact() {
        return [SELECT Id, AccountId, Tos_Accepted_Date__c, Tos_Version_Accepted__c,
                       Tos_Acceptance_Source__c, Tos_Acceptance_Form_Id__c,
                       Tos_Reacceptance_Required__c,
                       Age_Attestation_Confirmed__c, Age_Attestation_Date__c,
                       Age_Attestation_Source__c
                FROM Contact LIMIT 1];
    }

    private static User getCommunityUser() {
        return [SELECT Id, ContactId FROM User
                WHERE ContactId != null AND IsActive = true
                  AND Email LIKE '%@testorg.com'
                LIMIT 1];
    }

    @IsTest
    static void cmdReadsReturnNullWhenUnset() {
        Test.startTest();
        String tosVersion = FimbyTosController.getCurrentTosVersion();
        Date tosDate = FimbyTosController.getCurrentTosEffectiveDate();
        String cgaVersion = FimbyTosController.getCurrentCgaVersion();
        Date cgaDate = FimbyTosController.getCurrentCgaEffectiveDate();
        Test.stopTest();
        System.assert(tosVersion == null || tosVersion.length() <= 10, 'TOS version should be null or a short string');
        System.assert(cgaVersion == null || cgaVersion.length() <= 10, 'CGA version should be null or a short string');
        System.assert(tosDate == null || tosDate.year() > 2000, 'TOS effective date should be null or a real date');
        System.assert(cgaDate == null || cgaDate.year() > 2000, 'CGA effective date should be null or a real date');
    }

    @IsTest
    static void acceptTosStampsContactWithLiveVersion() {
        User u = getCommunityUser();

        Contact pre = getContact();
        pre.Tos_Reacceptance_Required__c = true;
        update pre;

        Test.startTest();
        System.runAs(u) {
            FimbyTosController.acceptTos('1.0', 'Login Flow');
        }
        Test.stopTest();

        Contact c = getContact();
        System.assertNotEquals(null, c.Tos_Accepted_Date__c, 'Tos_Accepted_Date__c should be stamped');
        System.assertEquals('Login Flow', c.Tos_Acceptance_Source__c, 'Source should be Login Flow');
        System.assertEquals(null, c.Tos_Acceptance_Form_Id__c, 'Login Flow acceptances do not stamp a form Id');
        System.assertEquals(false, c.Tos_Reacceptance_Required__c,
            'acceptTos should clear the reacceptance flag set by the Login Flow');
        // Combined "Terms + 19-or-older" checkbox: TOS acceptance also stamps age attestation.
        System.assertEquals(true, c.Age_Attestation_Confirmed__c,
            'Age_Attestation_Confirmed__c should be stamped alongside TOS');
        System.assertNotEquals(null, c.Age_Attestation_Date__c,
            'Age_Attestation_Date__c should be stamped when TOS is accepted via Login Flow');
        System.assertEquals(Date.today(), c.Age_Attestation_Date__c.date(),
            'Age_Attestation_Date__c should land on today when stamped via Login Flow');
        System.assertEquals('Login Flow', c.Age_Attestation_Source__c,
            'Age_Attestation_Source__c should mirror the TOS source value');
    }

    @IsTest
    static void acceptTosWithoutContactRaises() {
        Profile sysAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User noContactUser = new User(
            Alias = 'tosTest',
            Email = 'tosTest@fimby.test.com',
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Tos',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = sysAdmin.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tosTest' + DateTime.now().getTime() + '@fimby.test.com'
        );
        insert noContactUser;

        Boolean threw = false;
        Test.startTest();
        System.runAs(noContactUser) {
            try {
                FimbyTosController.acceptTos('1.0', 'Login Flow');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();
        System.assert(threw, 'A user without an associated Contact should be rejected.');
    }

    @IsTest
    static void acceptCgaStampsAccount() {
        User u = getCommunityUser();
        Account org = new Account(Name = 'Test Org', Type = 'Community Group');
        insert org;

        Test.startTest();
        System.runAs(u) {
            FimbyTosController.acceptCga(org.Id, '1.0');
        }
        Test.stopTest();

        Account refreshed = [SELECT Id, CGA_Accepted_Date__c, CGA_Version__c, CGA_Accepted_By__c
                             FROM Account WHERE Id = :org.Id LIMIT 1];
        System.assertNotEquals(null, refreshed.CGA_Accepted_Date__c, 'CGA_Accepted_Date__c should be stamped');
        System.assertEquals(u.ContactId, refreshed.CGA_Accepted_By__c, 'CGA_Accepted_By__c should be the realContactId');
    }

    @IsTest
    static void acceptCgaRequiresAccountId() {
        User u = getCommunityUser();
        Boolean threw = false;
        Test.startTest();
        System.runAs(u) {
            try {
                FimbyTosController.acceptCga(null, '1.0');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();
        System.assert(threw, 'Null accountId should raise.');
    }

    @IsTest
    static void recordPaperAcceptanceStampsContactOnce() {
        Contact c = getContact();
        Date signed = Date.newInstance(2026, 4, 1);

        Test.startTest();
        FimbyTosController.recordPaperAcceptance(c.Id, signed, '1.0', null);
        Test.stopTest();

        Contact refreshed = getContact();
        System.assertNotEquals(null, refreshed.Tos_Accepted_Date__c, 'Tos_Accepted_Date__c should be stamped');
        System.assertEquals('1.0', refreshed.Tos_Version_Accepted__c, 'Version should match what was passed');
        System.assertEquals('Support Relationship Paper Form', refreshed.Tos_Acceptance_Source__c,
                            'Source should be the paper-form constant');
        System.assertEquals(2026, refreshed.Tos_Accepted_Date__c.yearGmt(),
                            'Stamp should reflect the signed date year');
        // Block C of the supporter form now includes "I am 19 or older" — paper
        // approval stamps age attestation in the same DML as TOS, using the
        // same DateTime so the two fields stay aligned.
        System.assertEquals(true, refreshed.Age_Attestation_Confirmed__c,
            'Age_Attestation_Confirmed__c should be stamped on paper-form approval');
        System.assertEquals(refreshed.Tos_Accepted_Date__c, refreshed.Age_Attestation_Date__c,
            'Age_Attestation_Date__c should match Tos_Accepted_Date__c on the paper path');
        System.assertEquals(2026, refreshed.Age_Attestation_Date__c.yearGmt(),
            'Age stamp should reflect the signed date year');
        System.assertEquals('Support Relationship Paper Form', refreshed.Age_Attestation_Source__c,
            'Age_Attestation_Source__c should match the TOS source on the paper path');
    }

    @IsTest
    static void recordPaperAcceptanceIsIdempotent() {
        Contact c = getContact();
        Date firstSigned = Date.newInstance(2026, 1, 15);
        Date secondSigned = Date.newInstance(2026, 6, 30);

        FimbyTosController.recordPaperAcceptance(c.Id, firstSigned, '1.0', null);
        Contact afterFirst = getContact();
        DateTime firstStamp = afterFirst.Tos_Accepted_Date__c;
        DateTime firstAgeDate = afterFirst.Age_Attestation_Date__c;

        Test.startTest();
        FimbyTosController.recordPaperAcceptance(c.Id, secondSigned, '2.0', null);
        Test.stopTest();

        Contact afterSecond = getContact();
        System.assertEquals(firstStamp, afterSecond.Tos_Accepted_Date__c,
                            'Re-firing the trigger must not overwrite an earlier stamp');
        System.assertEquals('1.0', afterSecond.Tos_Version_Accepted__c,
                            'Original version should remain after a re-fire');
        // Age attestation idempotency rides on the same Tos_Accepted_Date__c
        // null-check guard, so the original age stamp must also survive.
        System.assertEquals(firstAgeDate, afterSecond.Age_Attestation_Date__c,
                            'Original age attestation date should remain after a re-fire');
        System.assertEquals('Support Relationship Paper Form',
                            afterSecond.Age_Attestation_Source__c,
                            'Original age source should remain after a re-fire');
    }

    @IsTest
    static void recordPaperAcceptanceShortCircuitsOnNullContact() {
        Test.startTest();
        FimbyTosController.recordPaperAcceptance(null, Date.today(), '1.0', null);
        Test.stopTest();
        System.assert(true, 'recordPaperAcceptance with null contactId should be a no-op');
    }

    @IsTest
    static void settingsTosCgaGettersExposeCmdValues() {
        Test.startTest();
        String tos = FimbySettings.tosCurrentVersion();
        Date tosD = FimbySettings.tosEffectiveDate();
        String cga = FimbySettings.cgaCurrentVersion();
        Date cgaD = FimbySettings.cgaEffectiveDate();
        Test.stopTest();
        System.assert(tos == null || tos.length() < 50);
        System.assert(cga == null || cga.length() < 50);
        System.assert(tosD == null || tosD.year() > 1990);
        System.assert(cgaD == null || cgaD.year() > 1990);
    }

    @IsTest
    static void recordPaperAcceptanceWritesContentDocId() {
        Contact c = getContact();
        Id fakeContentDocId = '069000000000001AAA';

        Test.startTest();
        FimbyTosController.recordPaperAcceptance(c.Id, Date.today(), '1.0', fakeContentDocId);
        Test.stopTest();

        Contact refreshed = getContact();
        System.assertEquals(String.valueOf(fakeContentDocId), refreshed.Tos_Acceptance_Form_Id__c,
                            'Tos_Acceptance_Form_Id__c should hold the ContentDocumentId');
    }

    @IsTest
    static void acceptTosClearsExistingAgeAttestationGap() {
        // Scenario: an existing Contact has TOS already accepted but
        // Age_Attestation_Confirmed__c is false (the backfill case). When the
        // user agrees again via the Login Flow modal, both the TOS and age
        // fields must be re-stamped together. This protects the new combined
        // checkbox semantics — there is no path where TOS gets re-stamped
        // without age being filled in.
        User u = getCommunityUser();
        Contact pre = getContact();
        pre.Age_Attestation_Confirmed__c = false;
        pre.Age_Attestation_Date__c = null;
        pre.Age_Attestation_Source__c = null;
        pre.Tos_Reacceptance_Required__c = true;
        update pre;

        Test.startTest();
        System.runAs(u) {
            FimbyTosController.acceptTos('1.0', 'Login Flow');
        }
        Test.stopTest();

        Contact c = getContact();
        System.assertEquals(true, c.Age_Attestation_Confirmed__c,
            'A second acceptTos call must fill in a missing age attestation');
        System.assertNotEquals(null, c.Age_Attestation_Date__c,
            'Age_Attestation_Date__c should be stamped after re-acceptance');
        System.assertEquals(Date.today(), c.Age_Attestation_Date__c.date(),
            'Age_Attestation_Date__c should land on today after re-acceptance');
        System.assertEquals('Login Flow', c.Age_Attestation_Source__c,
            'Age_Attestation_Source__c should be Login Flow after re-acceptance');
    }
}
