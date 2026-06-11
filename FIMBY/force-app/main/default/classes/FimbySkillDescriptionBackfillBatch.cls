/**
 * @description One-time backfill: copies legacy Description__c into Description_Text__c for existing skill offers.
 */
global without sharing class FimbySkillDescriptionBackfillBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Description__c, Description_Text__c
            FROM Skill_Offer__c
            WHERE Description_Text__c = null
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Skill_Offer__c> scope) {
        List<Skill_Offer__c> toUpdate = new List<Skill_Offer__c>();
        for (Skill_Offer__c skill : scope) {
            if (String.isBlank(skill.Description__c)) {
                continue;
            }
            skill.Description_Text__c = skill.Description__c.left(255);
            toUpdate.add(skill);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    global void finish(Database.BatchableContext bc) {}
}
