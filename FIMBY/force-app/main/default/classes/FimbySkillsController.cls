/**
 * @description Skills offered in the neighbourhood library. Dual-stamped, neighbourhood-scoped.
 */
public with sharing class FimbySkillsController {

    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        FimbyConstants.SKILL_ACTIVE,
        FimbyConstants.SKILL_PAUSED,
        FimbyConstants.SKILL_REMOVED
    };

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSkillCategoryPicklistValues() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry entry : Skill_Offer__c.Skill_Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getSkills(Integer offset, Integer pageSize) {
        try {
            Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
            if (neighbourhoodId == null) {
                return new List<Map<String, Object>>();
            }

            Integer lim = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.searchPageSize();
            Integer off = (offset != null && offset >= 0) ? offset : 0;

            List<Skill_Offer__c> skills = new SkillsQueryHelper().queryActiveSkills(neighbourhoodId, lim, off);

            Id viewerContactId = FimbyIdentityRepository.getActingAsContactId();
            Set<Id> blockedIds = viewerContactId != null
                ? FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId)
                : new Set<Id>();

            List<Map<String, Object>> results = new List<Map<String, Object>>();
            for (Skill_Offer__c skill : skills) {
                if (!blockedIds.isEmpty()
                    && (blockedIds.contains(skill.Owner_Contact__c) || blockedIds.contains(skill.Listed_By__c))) {
                    continue;
                }
                results.add(buildSkillRow(skill));
            }
            return results;
        } catch (Exception e) {
            FimbyLogger.error('FimbySkillsController', 'getSkills', e);
            throw new AuraHandledException('Failed to load skills: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSkillOffer(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Record ID is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Skill_Offer__c skill = new SkillsQueryHelper().getSkillForView(recordId, identity.neighbourhoodId);
            if (skill == null) {
                throw new AuraHandledException('Skill not found.');
            }
            Boolean isOwner = isOwnerDualCheck(skill, realContactId, actingAsContactId);

            Map<String, Object> result = buildSkillRow(skill);
            result.put('isOwner', isOwner);
            result.put('isStanding', skill.Is_Standing__c == true);
            result.put('availabilityNote', skill.Availability_Note__c);
            result.put('listedByName', skill.Listed_By__r?.Full_Name__c);
            result.put('moderationStatus', skill.Moderation_Status__c);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbySkillsController', 'getSkillOffer', e);
            throw new AuraHandledException('Failed to load skill: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getMyOfferedCategories() {
        Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
        if (actingAsContactId == null) {
            return new List<Map<String, Object>>();
        }

        List<Skill_Offer__c> existing = new SkillsQueryHelper().queryOwnedActiveSkills(actingAsContactId);

        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Skill_Offer__c skill : existing) {
            results.add(new Map<String, Object>{
                'id' => skill.Id,
                'category' => skill.Skill_Category__c,
                'title' => skill.Name,
                'description' => skill.Description_Text__c,
                'availabilityNote' => skill.Availability_Note__c,
                'status' => skill.Status__c
            });
        }
        return results;
    }

    @AuraEnabled
    public static Map<String, Object> saveSkillOffers(String skillsJson) {
        try {
            if (String.isBlank(skillsJson)) {
                throw new AuraHandledException('No skills to save.');
            }

            List<Object> rawRows = (List<Object>) JSON.deserializeUntyped(skillsJson);
            if (rawRows == null || rawRows.isEmpty()) {
                throw new AuraHandledException('No skills to save.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;
            Id neighbourhoodId = identity.neighbourhoodId;

            SkillsQueryHelper queryHelper = new SkillsQueryHelper();
            Set<String> existingCategories = new Set<String>();
            for (Skill_Offer__c existing : queryHelper.queryOwnedActiveSkills(actingAsContactId)) {
                existingCategories.add(existing.Skill_Category__c);
            }

            Integer priorSkillCount = queryHelper.countOwnedSkills(actingAsContactId);

            List<Skill_Offer__c> toInsert = new List<Skill_Offer__c>();
            List<Skill_Offer__c> toUpdate = new List<Skill_Offer__c>();
            Set<String> batchInsertCategories = new Set<String>();

            for (Object raw : rawRows) {
                Map<String, Object> row = (Map<String, Object>) raw;
                String category = (String) row.get('category');
                if (String.isBlank(category)) {
                    continue;
                }

                String title = (String) row.get('title');
                if (String.isBlank(title)) {
                    title = category;
                }

                String recordId = (String) row.get('id');
                if (String.isNotBlank(recordId)) {
                    Skill_Offer__c existing = queryOwnedSkill(recordId, realContactId, actingAsContactId);
                    existing.Name = title;
                    if (row.containsKey('description')) {
                        existing.Description_Text__c = (String) row.get('description');
                    }
                    if (row.containsKey('availabilityNote')) {
                        existing.Availability_Note__c = (String) row.get('availabilityNote');
                    }
                    toUpdate.add(existing);
                } else {
                    if (existingCategories.contains(category) || batchInsertCategories.contains(category)) {
                        throw new AuraHandledException(
                            'You already offer help in ' + category + '. Edit your existing skill instead.'
                        );
                    }
                    batchInsertCategories.add(category);
                    toInsert.add(new Skill_Offer__c(
                        Name = title,
                        Skill_Category__c = category,
                        Description_Text__c = (String) row.get('description'),
                        Availability_Note__c = (String) row.get('availabilityNote'),
                        Owner_Contact__c = actingAsContactId,
                        Listed_By__c = realContactId,
                        Neighbourhood__c = neighbourhoodId,
                        Status__c = FimbyConstants.SKILL_ACTIVE,
                        Is_Standing__c = true,
                        Moderation_Status__c = 'Visible'
                    ));
                }
            }

            SkillsOwnerDmlHelper dmlHelper = new SkillsOwnerDmlHelper();
            if (!toInsert.isEmpty()) {
                dmlHelper.insertSkills(toInsert);
            }
            if (!toUpdate.isEmpty()) {
                dmlHelper.updateSkills(toUpdate);
            }

            List<String> savedIds = new List<String>();
            for (Skill_Offer__c s : toInsert) {
                savedIds.add(s.Id);
            }
            for (Skill_Offer__c s : toUpdate) {
                savedIds.add(s.Id);
            }

            Boolean firstSkill = priorSkillCount == 0 && !toInsert.isEmpty();

            return new Map<String, Object>{
                'success' => true,
                'savedIds' => savedIds,
                'firstSkill' => firstSkill,
                'message' => 'Skills saved successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbySkillsController', 'saveSkillOffers', e);
            throw new AuraHandledException('Failed to save skills: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> setSkillStatus(Id recordId, String status) {
        try {
            if (recordId == null || String.isBlank(status) || !ALLOWED_STATUSES.contains(status)) {
                throw new AuraHandledException('Invalid status request.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Skill_Offer__c skill = queryOwnedSkill(
                recordId,
                identity.currentUser.ContactId,
                identity.actingAsContactId
            );
            skill.Status__c = status;
            new SkillsOwnerDmlHelper().updateSkills(new List<Skill_Offer__c>{ skill });

            return new Map<String, Object>{
                'success' => true,
                'recordId' => skill.Id,
                'status' => status
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbySkillsController', 'setSkillStatus', e);
            throw new AuraHandledException('Failed to update skill status: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> requestSkillHelp(Id skillOfferId, String note) {
        try {
            if (skillOfferId == null) {
                throw new AuraHandledException('Skill ID is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id actingAsContactId = identity.actingAsContactId;

            Skill_Offer__c skill = new SkillsQueryHelper().getSkillForRequest(skillOfferId, identity.neighbourhoodId);
            if (skill == null) {
                throw new AuraHandledException('Skill not found.');
            }
            if (skill.Status__c != FimbyConstants.SKILL_ACTIVE
                || skill.Moderation_Status__c == 'Hidden_By_Moderator') {
                throw new AuraHandledException('This skill is not available right now.');
            }
            if (skill.Owner_Contact__c == actingAsContactId) {
                throw new AuraHandledException('You cannot request help from your own skill offer.');
            }

            Set<Id> blockedIds = FimbyBlockingHelper.getBidirectionalBlocks(actingAsContactId);
            if (blockedIds.contains(skill.Owner_Contact__c)) {
                throw new AuraHandledException('You are not connected to this neighbour.');
            }

            Id ownerContactId = skill.Owner_Contact__c;
            FimbyConversationController.prepareDirectConversation(String.valueOf(ownerContactId));

            List<Conversation__c> existing = [
                SELECT Id
                FROM Conversation__c
                WHERE Context_Type__c = :FimbyConstants.CTX_SKILL
                  AND Related_Record_Id__c = :skillOfferId
                  AND ((Participant_1__c = :actingAsContactId AND Participant_2__c = :ownerContactId)
                    OR (Participant_1__c = :ownerContactId AND Participant_2__c = :actingAsContactId))
                LIMIT 1
            ];

            Id conversationId;
            Boolean isNew = false;
            if (!existing.isEmpty()) {
                conversationId = existing[0].Id;
            } else {
                Conversation__c newConv = new Conversation__c(
                    Participant_1__c = actingAsContactId,
                    Participant_2__c = ownerContactId,
                    Status__c = FimbyConstants.CONVERSATION_ACTIVE,
                    Context_Type__c = FimbyConstants.CTX_SKILL,
                    Related_Record_Id__c = String.valueOf(skillOfferId),
                    Participant_1_Unread_Count__c = 0,
                    Participant_2_Unread_Count__c = 0,
                    Participant_1_Archived__c = false,
                    Participant_2_Archived__c = false
                );
                insert newConv;
                conversationId = newConv.Id;
                isNew = true;
            }

            String messageBody = String.isNotBlank(note) ? note.trim()
                : 'Hi! I saw your skill offer and wondered if you could help.';
            Map<String, Object> sendResult = FimbyMessageController.sendMessage(conversationId, messageBody);
            sendResult.put('conversationId', conversationId);
            sendResult.put('isNew', isNew);
            return sendResult;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbySkillsController', 'requestSkillHelp', e);
            throw new AuraHandledException('Failed to start conversation: ' + e.getMessage());
        }
    }

    private static Skill_Offer__c queryOwnedSkill(Id recordId, Id realContactId, Id actingAsContactId) {
        Skill_Offer__c skill = new SkillsQueryHelper().getSkillById(recordId);
        if (skill == null) {
            throw new AuraHandledException('Skill not found.');
        }
        if (!isOwnerDualCheck(skill, realContactId, actingAsContactId)) {
            throw new AuraHandledException('You can only edit skills you posted.');
        }
        return skill;
    }

    private without sharing class SkillsQueryHelper {
        public List<Skill_Offer__c> queryActiveSkills(Id neighbourhoodId, Integer lim, Integer off) {
            return [
                SELECT Id, Name, Description_Text__c, Skill_Category__c, Availability_Note__c,
                       Status__c, CreatedDate,
                       Owner_Contact__c, Owner_Contact__r.Full_Name__c,
                       Owner_Contact__r.Image_URL__c,
                       Owner_Contact__r.Is_Organization_Contact__c,
                       Owner_Contact__r.Organization_Account__c,
                       Owner_Contact__r.Organization_Account__r.Logo_URL__c,
                       Listed_By__c
                FROM Skill_Offer__c
                WHERE Status__c = :FimbyConstants.SKILL_ACTIVE
                  AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
                  AND Neighbourhood__c = :neighbourhoodId
                ORDER BY CreatedDate DESC
                LIMIT :lim OFFSET :off
            ];
        }

        public Skill_Offer__c getSkillForView(Id recordId, Id neighbourhoodId) {
            List<Skill_Offer__c> rows = [
                SELECT Id, Name, Description_Text__c, Skill_Category__c, Availability_Note__c,
                       Status__c, Is_Standing__c, CreatedDate,
                       Owner_Contact__c, Owner_Contact__r.Full_Name__c,
                       Owner_Contact__r.Image_URL__c,
                       Owner_Contact__r.Is_Organization_Contact__c,
                       Owner_Contact__r.Organization_Account__c,
                       Owner_Contact__r.Organization_Account__r.Logo_URL__c,
                       Listed_By__c, Listed_By__r.Full_Name__c,
                       Moderation_Status__c, Neighbourhood__c
                FROM Skill_Offer__c
                WHERE Id = :recordId AND Neighbourhood__c = :neighbourhoodId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public Skill_Offer__c getSkillForRequest(Id skillOfferId, Id neighbourhoodId) {
            List<Skill_Offer__c> rows = [
                SELECT Id, Name, Owner_Contact__c, Status__c, Moderation_Status__c, Neighbourhood__c
                FROM Skill_Offer__c
                WHERE Id = :skillOfferId AND Neighbourhood__c = :neighbourhoodId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public Skill_Offer__c getSkillById(Id recordId) {
            List<Skill_Offer__c> rows = [
                SELECT Id, Name, Description_Text__c, Skill_Category__c, Availability_Note__c, Status__c,
                       Owner_Contact__c, Listed_By__c
                FROM Skill_Offer__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public List<Skill_Offer__c> queryOwnedActiveSkills(Id ownerContactId) {
            return [
                SELECT Id, Skill_Category__c, Name, Description_Text__c, Availability_Note__c, Status__c
                FROM Skill_Offer__c
                WHERE Owner_Contact__c = :ownerContactId
                  AND Status__c IN (:FimbyConstants.SKILL_ACTIVE, :FimbyConstants.SKILL_PAUSED)
            ];
        }

        public Integer countOwnedSkills(Id ownerContactId) {
            return [
                SELECT COUNT()
                FROM Skill_Offer__c
                WHERE Owner_Contact__c = :ownerContactId
            ];
        }
    }

    private without sharing class SkillsOwnerDmlHelper {
        public void insertSkills(List<Skill_Offer__c> skills) {
            insert skills;
        }

        public void updateSkills(List<Skill_Offer__c> skills) {
            update skills;
        }
    }

    private static Boolean isOwnerDualCheck(Skill_Offer__c skill, Id realContactId, Id actingAsContactId) {
        return skill.Listed_By__c == realContactId || skill.Owner_Contact__c == actingAsContactId;
    }

    private static Map<String, Object> buildSkillRow(Skill_Offer__c skill) {
        String displayName = skill.Owner_Contact__r?.Full_Name__c;
        String avatarUrl = skill.Owner_Contact__r?.Image_URL__c;
        if (skill.Owner_Contact__r?.Is_Organization_Contact__c == true
            && skill.Owner_Contact__r?.Organization_Account__r?.Logo_URL__c != null) {
            avatarUrl = skill.Owner_Contact__r.Organization_Account__r.Logo_URL__c;
        }

        return new Map<String, Object>{
            'id' => skill.Id,
            'title' => skill.Name,
            'description' => skill.Description_Text__c,
            'category' => skill.Skill_Category__c,
            'availabilityNote' => skill.Availability_Note__c,
            'status' => skill.Status__c,
            'createdDate' => skill.CreatedDate,
            'ownerContactId' => skill.Owner_Contact__c,
            'ownerName' => displayName,
            'ownerImageUrl' => avatarUrl,
            'isOrganization' => skill.Owner_Contact__r?.Is_Organization_Contact__c == true
        };
    }
}
