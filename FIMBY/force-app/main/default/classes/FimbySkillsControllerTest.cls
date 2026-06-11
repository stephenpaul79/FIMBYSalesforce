@isTest
private class FimbySkillsControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);

        Contact otherContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, false);
        otherContact.Email = 'other.skill.' + DateTime.now().getTime() + '@fimby.test.com';
        insert otherContact;
    }

    private static User getTestUser() {
        List<User> users = [
            SELECT Id, ContactId FROM User
            WHERE IsActive = true
              AND ContactId IN (
                  SELECT Id FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com'
              )
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
        return users[0];
    }

    private static Contact getTestContact() {
        User testUser = getTestUser();
        return [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId LIMIT 1];
    }

    private static Contact getOtherContact() {
        return [
            SELECT Id, AccountId FROM Contact
            WHERE Email LIKE 'other.skill.%@fimby.test.com'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
    }

    @isTest
    static void testGetSkillCategoryPicklistValues() {
        Test.startTest();
        List<Map<String, String>> categories = FimbySkillsController.getSkillCategoryPicklistValues();
        Test.stopTest();
        System.assert(categories.size() >= 26, 'Should return skill categories');
    }

    @isTest
    static void testSaveSkillOffers_bulkInsert() {
        User testUser = getTestUser();
        List<Object> rows = new List<Object>{
            new Map<String, Object>{ 'category' => 'Tech Help', 'title' => '', 'description' => 'Wifi setup' },
            new Map<String, Object>{ 'category' => 'Cooking & Baking', 'description' => 'Meal prep' }
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbySkillsController.saveSkillOffers(JSON.serialize(rows));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(true, result.get('firstSkill'));
        List<String> savedIds = (List<String>) result.get('savedIds');
        System.assertEquals(2, savedIds.size());

        List<Skill_Offer__c> inserted = [
            SELECT Name, Description_Text__c, Owner_Contact__c, Listed_By__c, Neighbourhood__c, Status__c, Skill_Category__c
            FROM Skill_Offer__c WHERE Id IN :savedIds
            ORDER BY Skill_Category__c
        ];
        System.assertEquals(2, inserted.size());
        for (Skill_Offer__c s : inserted) {
            System.assertEquals(testUser.ContactId, s.Owner_Contact__c);
            System.assertEquals(testUser.ContactId, s.Listed_By__c);
            System.assertEquals(FimbyConstants.SKILL_ACTIVE, s.Status__c);
        }
        System.assertEquals('Wifi setup', inserted[0].Description_Text__c);
        System.assertEquals('Meal prep', inserted[1].Description_Text__c);
    }

    private static Skill_Offer__c insertOwnedSkill(User testUser, Contact c, String category) {
        Skill_Offer__c skill = new Skill_Offer__c(
            Name = category,
            Skill_Category__c = category,
            Owner_Contact__c = c.Id,
            Listed_By__c = c.Id,
            Neighbourhood__c = c.AccountId,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        System.runAs(testUser) {
            insert skill;
        }
        return skill;
    }

    @isTest
    static void testSaveSkillOffers_duplicateRejected() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        insertOwnedSkill(testUser, c, 'Tech Help');

        List<Object> rows = new List<Object>{
            new Map<String, Object>{ 'category' => 'Tech Help' }
        };

        Boolean duplicateBlocked = false;
        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbySkillsController.saveSkillOffers(JSON.serialize(rows));
            }
            System.assert(false, 'Expected duplicate guard');
        } catch (AuraHandledException e) {
            duplicateBlocked = true;
        }
        Test.stopTest();

        System.assert(duplicateBlocked, 'Duplicate category should throw AuraHandledException');
        System.assertEquals(1, [
            SELECT COUNT() FROM Skill_Offer__c
            WHERE Owner_Contact__c = :c.Id AND Skill_Category__c = 'Tech Help'
        ]);
    }

    @isTest
    static void testSaveSkillOffers_updateDualCheck() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        Skill_Offer__c skill = insertOwnedSkill(testUser, c, 'Yard & Outdoor Work');

        List<Object> rows = new List<Object>{
            new Map<String, Object>{
                'id' => skill.Id,
                'category' => 'Cleaning & Organizing',
                'title' => 'Custom title',
                'description' => 'Updated desc'
            }
        };

        Test.startTest();
        System.runAs(testUser) {
            FimbySkillsController.saveSkillOffers(JSON.serialize(rows));
        }
        Test.stopTest();

        skill = [SELECT Name, Description_Text__c, Skill_Category__c FROM Skill_Offer__c WHERE Id = :skill.Id];
        System.assertEquals('Custom title', skill.Name);
        System.assertEquals('Updated desc', skill.Description_Text__c);
        System.assertEquals('Yard & Outdoor Work', skill.Skill_Category__c, 'Category immutable on update');
    }

    @isTest
    static void testGetSkills_andSetSkillStatus() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        insertOwnedSkill(testUser, c, 'Pet Care');

        Test.startTest();
        List<Map<String, Object>> skills;
        System.runAs(testUser) {
            skills = FimbySkillsController.getSkills(0, 10);
        }
        Test.stopTest();
        System.assertEquals(1, skills.size());

        Skill_Offer__c skill = [SELECT Id FROM Skill_Offer__c LIMIT 1];
        System.runAs(testUser) {
            FimbySkillsController.setSkillStatus(skill.Id, FimbyConstants.SKILL_PAUSED);
            skills = FimbySkillsController.getSkills(0, 10);
        }
        skill = [SELECT Status__c FROM Skill_Offer__c WHERE Id = :skill.Id];
        System.assertEquals(FimbyConstants.SKILL_PAUSED, skill.Status__c);
        System.assertEquals(0, skills.size(), 'Paused skills hidden from browse');
    }

    @isTest
    static void testGetMyOfferedCategories() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        insertOwnedSkill(testUser, c, 'Legal Guidance');

        Test.startTest();
        List<Map<String, Object>> offered;
        System.runAs(testUser) {
            offered = FimbySkillsController.getMyOfferedCategories();
        }
        Test.stopTest();
        System.assertEquals(1, offered.size());
        System.assertEquals('Legal Guidance', offered[0].get('category'));
    }

    @isTest
    static void testRequestSkillHelp_createsContextConversation() {
        User testUser = getTestUser();
        Contact requester = getTestContact();
        Contact owner = getOtherContact();
        Skill_Offer__c skill = new Skill_Offer__c(
            Name = 'Tutoring & Lessons',
            Skill_Category__c = 'Tutoring & Lessons',
            Owner_Contact__c = owner.Id,
            Listed_By__c = owner.Id,
            Neighbourhood__c = owner.AccountId,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        insert skill;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = requester.Id,
            Shared_To__c = owner.Id,
            Status__c = 'Active'
        );
        insert sci;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbySkillsController.requestSkillHelp(skill.Id, 'Could you help with math?');
        }
        Test.stopTest();

        System.assertNotEquals(null, result.get('conversationId'));
        List<Conversation__c> convos = [
            SELECT Id, Context_Type__c, Related_Record_Id__c
            FROM Conversation__c
            WHERE Context_Type__c = :FimbyConstants.CTX_SKILL
              AND Related_Record_Id__c = :skill.Id
        ];
        System.assertEquals(1, convos.size());
    }

    @isTest
    static void testGetSkillOffer_ownerFlags() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        Skill_Offer__c skill = insertOwnedSkill(testUser, c, 'Tech Help');
        skill.Is_Standing__c = true;
        System.runAs(testUser) {
            update skill;
        }

        Test.startTest();
        Map<String, Object> detail;
        System.runAs(testUser) {
            detail = FimbySkillsController.getSkillOffer(skill.Id);
        }
        Test.stopTest();

        System.assertEquals(true, detail.get('isOwner'));
        System.assertEquals('Tech Help', detail.get('title'));
    }

    @isTest
    static void testGetSkillOffer_returnsDescriptionText() {
        User testUser = getTestUser();
        Contact c = getTestContact();
        Skill_Offer__c skill = new Skill_Offer__c(
            Name = 'House Cleaning',
            Skill_Category__c = 'Cleaning & Organizing',
            Description_Text__c = 'Evenings and weekends only.',
            Owner_Contact__c = c.Id,
            Listed_By__c = c.Id,
            Neighbourhood__c = c.AccountId,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        System.runAs(testUser) {
            insert skill;
        }

        Test.startTest();
        Map<String, Object> detail;
        System.runAs(testUser) {
            detail = FimbySkillsController.getSkillOffer(skill.Id);
        }
        Test.stopTest();

        System.assertEquals('Evenings and weekends only.', detail.get('description'));
    }
}
