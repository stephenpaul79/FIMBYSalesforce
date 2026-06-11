@isTest
private class FimbySkillDescriptionBackfillBatchTest {

    @isTest
    static void testBackfillCopiesLegacyDescription() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact owner = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        Skill_Offer__c skill = new Skill_Offer__c(
            Name = 'Gardening',
            Skill_Category__c = 'Yard & Outdoor Work',
            Description__c = 'Happy to help with weeding on weekends.',
            Owner_Contact__c = owner.Id,
            Listed_By__c = owner.Id,
            Neighbourhood__c = neighbourhood.Id,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        insert skill;

        Test.startTest();
        Database.executeBatch(new FimbySkillDescriptionBackfillBatch(), 200);
        Test.stopTest();

        skill = [
            SELECT Description_Text__c
            FROM Skill_Offer__c
            WHERE Id = :skill.Id
        ];
        System.assertEquals('Happy to help with weeding on weekends.', skill.Description_Text__c);
    }
}
