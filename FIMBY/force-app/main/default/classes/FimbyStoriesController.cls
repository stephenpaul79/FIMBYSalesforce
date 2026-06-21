/**
 * @description Handles Story__c feed retrieval, creation, like, share, and category picklist for community stories.
 */
public with sharing class FimbyStoriesController {
    
    /**
     * @description LWC-callable cacheable method that retrieves paginated stories for the user's neighbourhood, optionally filtered by category.
     * @param pageSize Number of records per page
     * @param offset Number of records to skip
     * @param category Story type filter (or 'All' for no filter)
     * @return StoriesResult with stories list and hasMore flag
     */
    @AuraEnabled(cacheable=true)
    public static StoriesResult getStories(Integer pageSize, Integer offset, String category) {
        try {
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String query = 'SELECT Id, Name, Message__c, Image_URL__c, CreatedDate, ' +
                          'CreatedBy.Name, CreatedBy.Id, Type__c, Neighbourhood__c, ' +
                          'Comment_Count__c ' +
                          'FROM Story__c ';

            List<String> whereConditions = new List<String>();
            
            if (String.isNotBlank(neighbourhoodAccountId)) {
                whereConditions.add('(Neighbourhood__c = :neighbourhoodAccountId' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Contact__c IN :sharedContactIds))');
            }
            
            if (String.isNotBlank(category) && category != 'All') {
                whereConditions.add('Type__c = :category');
            }

            whereConditions.add('(Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')');
            
            if (!whereConditions.isEmpty()) {
                query += 'WHERE ' + String.join(whereConditions, ' AND ') + ' ';
            }

            query += 'ORDER BY CreatedDate DESC ' +
                    'LIMIT :pageSize OFFSET :offset';

            List<Story__c> stories = Database.query(query);

            // Check if there are more records
            String countQuery = 'SELECT COUNT() FROM Story__c ';
            if (!whereConditions.isEmpty()) {
                countQuery += 'WHERE ' + String.join(whereConditions, ' AND ');
            }
            
            Integer totalCount = Database.countQuery(countQuery);
            Boolean hasMore = (offset + pageSize) < totalCount;

            return new StoriesResult(stories, hasMore);

        } catch (Exception e) {
            FimbyLogger.error('FimbyStoriesController', 'getStories', e);
            throw new AuraHandledException('Error retrieving stories: ' + e.getMessage());
        }
    }
    
    /**
     * @description LWC-callable cacheable method that returns total story count, optionally filtered by category.
     * @param category Story type filter (or 'All' for no filter)
     * @return Total number of matching stories
     */
    @AuraEnabled(cacheable=true)
    public static Integer getStoriesCount(String category) {
        String query = 'SELECT COUNT() FROM Story__c ';
        
        List<String> conditions = new List<String>();
        if (String.isNotBlank(category) && category != 'All') {
            conditions.add('Type__c = :category');
        }
        conditions.add('(Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')');
        query += 'WHERE ' + String.join(conditions, ' AND ');
        
        return Database.countQuery(query);
    }
    
    /**
     * @description LWC-callable method that creates a new Story__c for the acting-as contact's neighbourhood.
     * @param title Story title
     * @param content Story message/content
     * @param category Story type
     * @param location Optional location
     * @param imageUrl Optional image URL
     * @param shareOnSocial Whether to share on social media
     * @return Id of the created Story__c record
     */
    @AuraEnabled
    public static Id createStory(String title, String content, String category, String location, String imageUrl, Boolean shareOnSocial) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;
            Id neighbourhoodAccountId = identity.neighbourhoodId;
            
            Story__c newStory = new Story__c(
                Name = title,
                Message__c = content,
                Type__c = category,
                Neighbourhood__c = neighbourhoodAccountId,
                Posted_By__c = actingAsContactId,
                Contact__c = realContactId,
                Image_URL__c = imageUrl,
                Share_on_Social_Media__c = Boolean.valueOf(shareOnSocial)
            );
            newStory.Visibility_Scope__c = 'Neighbourhood';
            
            Database.insert(newStory, true);
            return newStory.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating story: ' + e.getMessage());
        }
    }

    /**
     * @description Reuses the acting-as identity's existing profile photo as a story's
     * image, sparing the author a redundant upload during the intro-post flow. Copies the
     * Contact's Image_URL__c / Image_Ratio__c onto the story; no file is duplicated, so
     * clearing either record's image later only nulls its own field.
     * @param storyId Id of the Story__c the running user just created
     */
    @AuraEnabled
    public static void useProfilePhotoForStory(Id storyId) {
        try {
            if (storyId == null) {
                throw new AuraHandledException('Story not found.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            StoryUpdateHelper helper = new StoryUpdateHelper();
            Story__c story = helper.queryStory(storyId);
            if (story == null) {
                throw new AuraHandledException('Story not found.');
            }
            if (story.Contact__c != realContactId && story.Posted_By__c != actingAsContactId) {
                throw new AuraHandledException('You can only update stories you created.');
            }

            Contact avatarContact = helper.queryContactAvatar(actingAsContactId);
            if (avatarContact == null || String.isBlank(avatarContact.Image_URL__c)) {
                throw new AuraHandledException('No profile photo found to reuse.');
            }

            story.Image_URL__c = avatarContact.Image_URL__c;
            story.Image_Ratio__c = avatarContact.Image_Ratio__c;
            helper.updateStory(story);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoriesController', 'useProfilePhotoForStory', e);
            AuraHandledException ex = new AuraHandledException('Error reusing profile photo: ' + e.getMessage());
            ex.setMessage('Error reusing profile photo: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description LWC-callable method that updates an existing Story__c for the author.
     * @param storyData JSON with recordId, title, content, category, shareOnSocial
     * @return Map with success flag and recordId
     */
    @AuraEnabled
    public static Map<String, Object> updateStory(String storyData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(storyData);
            String recordId = (String) data.get('recordId');
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Story__c story = new StoryUpdateHelper().queryStory(recordId);
            if (story == null) {
                throw new AuraHandledException('Story not found.');
            }

            if (story.Contact__c != realContactId && story.Posted_By__c != actingAsContactId) {
                throw new AuraHandledException('You can only edit stories you created.');
            }

            if (data.containsKey('title')) {
                story.Name = (String) data.get('title');
            }
            if (data.containsKey('content')) {
                story.Message__c = (String) data.get('content');
            }
            if (data.containsKey('category')) {
                story.Type__c = (String) data.get('category');
            }
            if (data.containsKey('shareOnSocial')) {
                story.Share_on_Social_Media__c = data.get('shareOnSocial') == true;
            }

            new StoryUpdateHelper().updateStory(story);

            return new Map<String, Object>{
                'success' => true,
                'recordId' => story.Id,
                'message' => 'Story updated successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoriesController', 'updateStory', e);
            AuraHandledException ex = new AuraHandledException('Error updating story: ' + e.getMessage());
            ex.setMessage('Error updating story: ' + e.getMessage());
            throw ex;
        }
    }
    
    /**
     * @description LWC-callable method that records a like on a story (placeholder for Like__c or counter implementation).
     * @param storyId Id of the Story__c to like
     */
    @AuraEnabled
    public static void likeStory(Id storyId) {
        try {
            // Implementation for liking a story
            // This could involve creating a Like__c record or updating a counter
        } catch (Exception e) {
            throw new AuraHandledException('Error liking story: ' + e.getMessage());
        }
    }
    
    /**
     * @description LWC-callable method that records a share of a story (placeholder for Share__c or notification implementation).
     * @param storyId Id of the Story__c to share
     * @param shareMethod Share method (e.g., copy link, social)
     */
    @AuraEnabled
    public static void shareStory(Id storyId, String shareMethod) {
        try {
            // Implementation for sharing a story
            // This could involve creating a Share__c record or sending notifications
        } catch (Exception e) {
            throw new AuraHandledException('Error sharing story: ' + e.getMessage());
        }
    }
    
    /**
     * @description LWC-callable cacheable method that returns Story__c.Type__c picklist values plus 'All'.
     * @return List of category labels (All plus active picklist values)
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getStoryCategories() {
        List<String> categories = new List<String>();
        categories.add('All');
        
        Schema.DescribeFieldResult fieldResult = Story__c.Type__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistValues) {
            if (entry.isActive()) {
                categories.add(entry.getLabel());
            }
        }
        
        return categories;
    }

    /**
     * @description LWC-callable cacheable method that returns a single Story__c record only if it is visible
     * to the requesting user under the same neighbourhood + privacy + moderation rules as the feed list.
     * Hidden, under-review, cross-neighbourhood, or privacy-restricted stories return a stub indicating the
     * story is no longer available. Replaces the previous UI API `getRecord` wire on the detail page, which
     * ignored Moderation_Status__c and let hidden stories be opened by direct link or notification deep-link.
     * @param storyId Id of the Story__c to load
     * @return StoryDetailResult with either the populated story or a removed stub
     */
    /**
     * @description Author delete for community users who lack UI API delete on Story__c.
     * Dual-check: real author (Contact__c) or represented identity (Posted_By__c).
     */
    @AuraEnabled
    public static Map<String, Object> deleteStory(Id storyId) {
        if (storyId == null) {
            throw new AuraHandledException('This story is no longer available.');
        }
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;
            new StoryDeleteHelper().deleteAuthorizedStory(storyId, realContactId, actingAsContactId);
            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoriesController', 'deleteStory', e);
            throw new AuraHandledException('We could not remove your story. Try again in a moment.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static StoryDetailResult getStoryDetail(Id storyId) {
        if (storyId == null) {
            return new StoryDetailResult(true, 'This story is no longer available.');
        }

        try {
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String query = 'SELECT Id, Name, Message__c, Type__c, Image_URL__c, Image_Ratio__c, '
                + 'Posted_By__c, Posted_By__r.Name, Posted_By__r.Full_Name__c, '
                + ' Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, '
                + 'Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c, '
                + 'Contact__c, Neighbourhood__c, Visibility_Scope__c, '
                + 'Moderation_Status__c, CreatedDate, OwnerId, Comment_Count__c '
                + 'FROM Story__c WHERE Id = :storyId '
                + 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';

            // Mirror listStories: only apply neighbourhood filter when context is resolvable.
            if (String.isNotBlank(neighbourhoodAccountId)) {
                query += ' AND (Neighbourhood__c = :neighbourhoodAccountId'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Contact__c IN :sharedContactIds))';
            }

            query += ' LIMIT 1';

            List<Story__c> stories = Database.query(query);

            if (stories.isEmpty()) {
                return new StoryDetailResult(true, 'This story is no longer available.');
            }
            return new StoryDetailResult(stories[0]);

        } catch (Exception e) {
            FimbyLogger.error('FimbyStoriesController', 'getStoryDetail', e);
            throw new AuraHandledException('Error retrieving story: ' + e.getMessage());
        }
    }

    /**
     * @description Inner class for paginated story results.
     */
    public class StoriesResult {
        @AuraEnabled public List<Story__c> stories { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }

        /**
         * @description Constructs a StoriesResult with story list and hasMore flag.
         * @param stories List of Story__c records
         * @param hasMore Whether more records exist beyond this page
         */
        public StoriesResult(List<Story__c> stories, Boolean hasMore) {
            this.stories = stories;
            this.hasMore = hasMore;
        }
    }

    /**
     * @description Inner class for single-story detail responses. When `removed` is true, the LWC should
     * render a "no longer available" state instead of the story body. The `story` field is null in that
     * case to ensure no field data leaks through the wire.
     */
    public class StoryDetailResult {
        @AuraEnabled public Boolean removed { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Story__c story { get; set; }

        public StoryDetailResult(Story__c story) {
            this.removed = false;
            this.message = null;
            this.story = story;
        }

        public StoryDetailResult(Boolean removed, String message) {
            this.removed = removed;
            this.message = message;
            this.story = null;
        }
    }

    private without sharing class StoryUpdateHelper {
        public Story__c queryStory(Id storyId) {
            List<Story__c> rows = [
                SELECT Id, Posted_By__c, Contact__c, Name, Message__c, Type__c, Share_on_Social_Media__c
                FROM Story__c
                WHERE Id = :storyId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public Contact queryContactAvatar(Id contactId) {
            if (contactId == null) {
                return null;
            }
            List<Contact> rows = [
                SELECT Id, Image_URL__c, Image_Ratio__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public void updateStory(Story__c story) {
            update story;
        }
    }

    private without sharing class StoryDeleteHelper {
        public void deleteAuthorizedStory(Id storyId, Id realContactId, Id actingAsContactId) {
            List<Story__c> rows = [
                SELECT Id, Posted_By__c, Contact__c
                FROM Story__c
                WHERE Id = :storyId
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('This story is no longer available.');
            }
            Story__c story = rows[0];
            Boolean canDelete = story.Contact__c == realContactId
                || story.Posted_By__c == actingAsContactId;
            if (!canDelete) {
                throw new AuraHandledException('You can only remove your own stories.');
            }
            delete story;
        }
    }
}