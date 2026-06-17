/**
 * @description Handles Story comment functionality backed by the FIMBY-native
 *              Story_Comment__c custom object (master-detail to Story__c).
 *              Replaces the previous Chatter FeedItem-based implementation.
 *              Used by fimbyCommentComposer and fimbyStoryDetail LWCs (and
 *              fimbyQuickResponseModal via FimbyQuickResponseController).
 *
 *              Stamping convention (matches Story__c, per fimby-architecture.mdc):
 *                Post Owner   = Posted_By__c = acting-as Contact (represented identity)
 *                Submitted By = Contact__c   = real Contact at the keyboard
 */
public with sharing class FimbyStoryCommentController {

    /**
     * @description Fetches Active, non-moderator-hidden comments for a Story,
     *              filtered by the viewer's bidirectional block set.
     *              Not cacheable: callers refresh imperatively after post / edit /
     *              delete / report, and any LDS cache would serve stale rows.
     * @param storyId Id of the Story__c.
     * @return List of comment DTOs (see CommentQueryHelper.toDto for shape).
     */
    @AuraEnabled
    public static List<Map<String, Object>> getStoryComments(String storyId) {
        FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
        Id viewerActingAsId = identity == null ? null : identity.actingAsContactId;
        StoryCommentAccessHelper accessHelper = new StoryCommentAccessHelper();
        if (accessHelper.resolveCommentableStory(storyId, viewerActingAsId) == null) {
            return new List<Map<String, Object>>();
        }
        return new CommentQueryHelper().queryComments(storyId, identity);
    }

    /**
     * @description Returns story context for the composer (title, image, owner).
     *              Unchanged from the FeedItem-era implementation.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStoryForComment(String recordId) {
        try {
            Id viewerActingAsId = FimbyIdentityRepository.getActingAsContactId();
            Story__c story = new StoryCommentAccessHelper().resolveCommentableStory(recordId, viewerActingAsId);
            if (story == null) {
                AuraHandledException ex = new AuraHandledException('Error getting story: Story not found.');
                ex.setMessage('Error getting story: Story not found.');
                throw ex;
            }

            return new Map<String, Object>{
                'success' => true,
                'story' => new Map<String, Object>{
                    'id' => story.Id,
                    'name' => story.Name,
                    'message' => story.Message__c,
                    'imageUrl' => story.Image_URL__c,
                    'ownerId' => story.OwnerId,
                    'ownerContactId' => story.Posted_By__c,
                    'ownerName' => story.Posted_By__r?.Full_Name__c
                }
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting story: ' + e.getMessage());
            ex.setMessage('Error getting story: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Searches Contacts in the current neighbourhood (plus
     *              adjacent-neighbourhood shared contacts) for @mention
     *              suggestions. Returns CONTACT Ids (FIMBY identity model)
     *              rather than User Ids (the legacy Chatter requirement).
     * @param searchTerm Optional name fragment to filter on.
     * @return List of mention DTOs: { id (Contact Id), name, neighbourhood }
     */
    @AuraEnabled
    public static List<Map<String, String>> searchContactsForMention(String searchTerm) {
        List<Map<String, String>> results = new List<Map<String, String>>();

        try {
            Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
            if (neighbourhoodId == null) {
                return results;
            }

            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            List<Contact> contacts;

            if (String.isBlank(searchTerm)) {
                contacts = [
                    SELECT Id, FirstName, LastName, Name, Account.Name
                    FROM Contact
                    WHERE (AccountId = :neighbourhoodId
                        OR (AccountId IN :adjacentIds AND Id IN :sharedContactIds))
                    ORDER BY LastName, FirstName
                    LIMIT 10
                ];
            } else {
                String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
                contacts = [
                    SELECT Id, FirstName, LastName, Name, Account.Name
                    FROM Contact
                    WHERE (Name LIKE :searchPattern OR FirstName LIKE :searchPattern OR LastName LIKE :searchPattern)
                      AND (AccountId = :neighbourhoodId
                        OR (AccountId IN :adjacentIds AND Id IN :sharedContactIds))
                    ORDER BY LastName, FirstName
                    LIMIT 10
                ];
            }

            for (Contact c : contacts) {
                String mentionName;
                if (String.isNotBlank(c.FirstName) && String.isNotBlank(c.LastName)) {
                    mentionName = c.FirstName + ' ' + c.LastName;
                } else if (String.isNotBlank(c.LastName)) {
                    mentionName = c.LastName;
                } else if (String.isNotBlank(c.FirstName)) {
                    mentionName = c.FirstName;
                } else {
                    mentionName = c.Name;
                }

                results.add(new Map<String, String>{
                    'id' => c.Id,
                    'name' => mentionName,
                    'neighbourhood' => c.Account?.Name
                });
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoryCommentController', 'searchContactsForMention', e);
        }

        return results;
    }

    /**
     * @description Inserts a new Story_Comment__c with dual identity stamping,
     *              updates Story__c.Last_Comment__c/Last_Comment_Contact__c so
     *              feed cards keep working, and fans out in-app notifications
     *              to (a) the story owner and (b) every @mentioned Contact.
     * @param commentData JSON string with: storyId, commentText, commentContactId,
     *                    and optional mentionContactIds (List<Id>).
     * @return Map with: success, message, storyUrl, commentId.
     */
    @AuraEnabled
    public static Map<String, Object> postStoryComment(String commentData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(commentData);

            String storyId = (String) data.get('storyId');
            String commentText = (String) data.get('commentText');
            String commentContactId = (String) data.get('commentContactId');
            List<Id> mentionContactIds = extractMentionContactIds(data.get('mentionContactIds'));

            if (String.isBlank(storyId) || String.isBlank(commentText)) {
                throw new AuraHandledException('Story id and comment text are required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.contact?.Id;
            Id actingAsContactId = String.isNotBlank(commentContactId)
                ? (Id) commentContactId
                : identity.actingAsContactId;
            if (actingAsContactId == null) {
                actingAsContactId = realContactId;
            }
            Id neighbourhoodId = identity.neighbourhoodId;

            StoryCommentAccessHelper accessHelper = new StoryCommentAccessHelper();
            Story__c story = accessHelper.resolveCommentableStory(storyId, actingAsContactId);
            if (story == null) {
                throw new AuraHandledException('This story is not available for comments.');
            }

            String commenterName = resolveCommenterName(actingAsContactId, identity);

            Story_Comment__c comment = new Story_Comment__c(
                Story__c = storyId,
                Body__c = commentText,
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = realContactId,
                Posted_By__c = actingAsContactId,
                Neighbourhood__c = neighbourhoodId,
                Edit_Count__c = 0
            );
            if (!mentionContactIds.isEmpty()) {
                comment.Mention_Contact_Ids__c = JSON.serialize(mentionContactIds);
            }
            accessHelper.insertComment(comment);

            String truncatedComment = commentText.length() > 255
                ? commentText.substring(0, 255)
                : commentText;
            new StoryUpdateHelper().updateStoryComment(storyId, truncatedComment, actingAsContactId);

            fanOutNotifications(story, comment.Id, truncatedComment, commenterName, actingAsContactId, mentionContactIds);

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Comment posted successfully',
                'storyUrl' => FimbySettings.getUrl('Story', storyId),
                'commentId' => comment.Id
            };

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoryCommentController', 'postStoryComment', e);
            AuraHandledException ex = new AuraHandledException('Error posting comment: ' + e.getMessage());
            ex.setMessage('Error posting comment: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Updates a comment Body__c on behalf of the original author.
     *              Validates author dual-check (real OR acting-as), captures
     *              the prior body in Body_Snapshot__c, increments Edit_Count__c,
     *              stamps Edited_Date__c. Field history on Body__c provides the
     *              full edit log.
     * @param commentData JSON string with: commentId, commentText, mentionContactIds.
     * @return Map with: success, message, commentId, editCount, editedDate.
     */
    @AuraEnabled
    public static Map<String, Object> updateStoryComment(String commentData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(commentData);

            String commentId = (String) data.get('commentId');
            String commentText = (String) data.get('commentText');
            List<Id> mentionContactIds = extractMentionContactIds(data.get('mentionContactIds'));

            if (String.isBlank(commentId) || String.isBlank(commentText)) {
                throw new AuraHandledException('Comment id and comment text are required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.contact?.Id;
            Id actingAsContactId = identity.actingAsContactId;

            Story_Comment__c existing = [
                SELECT Id, Body__c, Contact__c, Posted_By__c, Edit_Count__c, Status__c
                FROM Story_Comment__c
                WHERE Id = :commentId
                LIMIT 1
            ];

            if (!isAuthor(existing, realContactId, actingAsContactId)) {
                throw new AuraHandledException('You can only edit your own comments.');
            }
            if (existing.Status__c != 'Active') {
                throw new AuraHandledException('This comment can no longer be edited.');
            }

            String priorBody = existing.Body__c == null ? '' : existing.Body__c;
            String snapshot = priorBody.length() > 255 ? priorBody.substring(0, 255) : priorBody;

            existing.Body__c = commentText;
            existing.Body_Snapshot__c = snapshot;
            existing.Edit_Count__c = (existing.Edit_Count__c == null ? 0 : existing.Edit_Count__c) + 1;
            existing.Edited_Date__c = System.now();
            if (!mentionContactIds.isEmpty()) {
                existing.Mention_Contact_Ids__c = JSON.serialize(mentionContactIds);
            }
            update existing;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Comment updated',
                'commentId' => existing.Id,
                'editCount' => existing.Edit_Count__c,
                'editedDate' => existing.Edited_Date__c
            };

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoryCommentController', 'updateStoryComment', e);
            AuraHandledException ex = new AuraHandledException('Error updating comment: ' + e.getMessage());
            ex.setMessage('Error updating comment: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Author soft-delete. Sets Status__c = 'Hidden_By_Author' so
     *              the comment is filtered out of feeds without losing the
     *              moderation audit trail.
     * @param commentId Id of the comment to hide.
     * @return Map with: success, message, commentId.
     */
    @AuraEnabled
    public static Map<String, Object> softDeleteStoryComment(String commentId) {
        try {
            if (String.isBlank(commentId)) {
                throw new AuraHandledException('Comment id is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.contact?.Id;
            Id actingAsContactId = identity.actingAsContactId;

            Story_Comment__c existing = [
                SELECT Id, Contact__c, Posted_By__c, Status__c
                FROM Story_Comment__c
                WHERE Id = :commentId
                LIMIT 1
            ];

            if (!isAuthor(existing, realContactId, actingAsContactId)) {
                throw new AuraHandledException('You can only remove your own comments.');
            }

            existing.Status__c = 'Hidden_By_Author';
            update existing;

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Comment removed',
                'commentId' => existing.Id
            };

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyStoryCommentController', 'softDeleteStoryComment', e);
            AuraHandledException ex = new AuraHandledException('Error removing comment: ' + e.getMessage());
            ex.setMessage('Error removing comment: ' + e.getMessage());
            throw ex;
        }
    }

    private static Boolean isAuthor(Story_Comment__c comment, Id realContactId, Id actingAsContactId) {
        if (comment == null) {
            return false;
        }
        return (realContactId != null && comment.Contact__c == realContactId)
            || (actingAsContactId != null && comment.Posted_By__c == actingAsContactId);
    }

    private static List<Id> extractMentionContactIds(Object raw) {
        List<Id> ids = new List<Id>();
        if (raw == null) {
            return ids;
        }
        List<Object> rawList = (List<Object>) raw;
        for (Object o : rawList) {
            if (o == null) continue;
            String s = String.valueOf(o);
            if (String.isBlank(s)) continue;
            try {
                ids.add((Id) s);
            } catch (Exception ex) {
                // skip malformed ids silently
            }
        }
        return ids;
    }

    private static String resolveCommenterName(Id actingAsContactId, FimbyIdentityRepository.Identity identity) {
        if (identity != null && identity.actingAsContact != null
                && identity.actingAsContact.Id == actingAsContactId) {
            if (String.isNotBlank(identity.orgDisplayName)) {
                return identity.orgDisplayName;
            }
            return identity.actingAsContact.Name;
        }
        if (actingAsContactId != null) {
            List<Contact> rows = [
                SELECT Name FROM Contact WHERE Id = :actingAsContactId LIMIT 1
            ];
            if (!rows.isEmpty() && String.isNotBlank(rows[0].Name)) {
                return rows[0].Name;
            }
        }
        return 'A neighbour';
    }

    private static void fanOutNotifications(
        Story__c story,
        Id commentId,
        String truncatedComment,
        String commenterName,
        Id commenterContactId,
        List<Id> mentionContactIds
    ) {
        Set<Id> notified = new Set<Id>();
        String storyUrl = FimbySettings.getUrl('Story', story.Id);

        if (story.Posted_By__c != null && story.Posted_By__c != commenterContactId) {
            FimbyNotificationService.createNotification(
                story.Posted_By__c,
                FimbyConstants.NOTIF_COMMENT,
                commenterName + ' commented on your story',
                truncatedComment,
                story.Id,
                'Story__c',
                storyUrl,
                commenterName
            );
            notified.add(story.Posted_By__c);
        }

        for (Id mentioned : mentionContactIds) {
            if (mentioned == null) continue;
            if (mentioned == commenterContactId) continue;
            if (notified.contains(mentioned)) continue;
            FimbyNotificationService.createNotification(
                mentioned,
                FimbyConstants.NOTIF_COMMENT,
                commenterName + ' mentioned you in a comment',
                truncatedComment,
                story.Id,
                'Story__c',
                storyUrl,
                commenterName
            );
            notified.add(mentioned);
        }
    }

    /**
     * @description Queries comments without sharing so neighbours can read threads on
     *              stories visible in the feed even when Story__Share rows are missing.
     *              Callers must gate on StoryCommentAccessHelper first.
     */
    private without sharing class CommentQueryHelper {
        public List<Map<String, Object>> queryComments(
            String storyId,
            FimbyIdentityRepository.Identity identity
        ) {
            List<Map<String, Object>> comments = new List<Map<String, Object>>();

            try {
                Id viewerContactId = identity == null ? null : identity.actingAsContactId;
                Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId);

                Integer commentsLim = FimbySettings.storyCommentsLimit();

                List<Story_Comment__c> rows = [
                    SELECT Id, Body__c, CreatedDate, Status__c,
                           Edit_Count__c, Edited_Date__c, Mention_Contact_Ids__c,
                           Contact__c, Contact__r.Name, Contact__r.Full_Name__c,
                           Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                           Posted_By__c, Posted_By__r.Name, Posted_By__r.Full_Name__c,
                           Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c
                    FROM Story_Comment__c
                    WHERE Story__c = :storyId
                      AND Status__c = 'Active'
                      AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
                    ORDER BY CreatedDate DESC
                    LIMIT :commentsLim
                ];

                List<SObject> visibleRows = FimbyBlockingHelper.filterVisible(
                    rows, blockedContactIds, new List<String>{ 'Posted_By__c', 'Contact__c' }
                );
                for (SObject row : visibleRows) {
                    comments.add(toDto((Story_Comment__c) row, viewerContactId, identity?.contact?.Id));
                }
            } catch (Exception e) {
                FimbyLogger.error('FimbyStoryCommentController', 'queryComments', e);
            }

            return comments;
        }

        private Map<String, Object> toDto(Story_Comment__c row, Id viewerActingAsId, Id viewerRealId) {
            String authorName = row.Posted_By__r != null ? row.Posted_By__r.Full_Name__c : null;
            if (String.isBlank(authorName) && row.Contact__r != null) {
                authorName = row.Contact__r.Full_Name__c;
            }
            String authorPhoto = row.Posted_By__r != null ? row.Posted_By__r.Display_Avatar_URL__c : null;
            if (String.isBlank(authorPhoto) && row.Contact__r != null) {
                authorPhoto = row.Contact__r.Display_Avatar_URL__c;
            }
            Boolean isAuthorView =
                (viewerRealId != null && row.Contact__c == viewerRealId)
             || (viewerActingAsId != null && row.Posted_By__c == viewerActingAsId);

            return new Map<String, Object>{
                'id' => row.Id,
                'body' => row.Body__c,
                'createdDate' => row.CreatedDate,
                'authorId' => row.Posted_By__c,
                'authorName' => authorName,
                'authorPhotoUrl' => authorPhoto,
                'submittedById' => row.Contact__c,
                'editCount' => row.Edit_Count__c == null ? 0 : Integer.valueOf(row.Edit_Count__c),
                'editedDate' => row.Edited_Date__c,
                'isAuthor' => isAuthorView
            };
        }
    }

    /**
     * @description Helper to update the parent Story__c with the latest comment
     *              metadata. Runs without sharing so the comment author can
     *              update a story they may not own (matches the legacy
     *              SystemModeWithoutSharing flow behaviour).
     */
    private without sharing class StoryUpdateHelper {
        public void updateStoryComment(String storyId, String comment, Id contactId) {
            Story__c storyUpdate = new Story__c(
                Id = storyId,
                Last_Comment__c = comment,
                Last_Comment_Contact__c = contactId
            );
            update storyUpdate;
        }
    }

    /**
     * @description Neighbourhood + moderation gate for story comments, and insert
     *              without sharing so cross-user comments work when parent Story__c
     *              OWD does not grant read access to non-owners (ControlledByParent).
     */
    private without sharing class StoryCommentAccessHelper {
        public Story__c resolveCommentableStory(Id storyId, Id viewerActingAsContactId) {
            if (storyId == null) {
                return null;
            }

            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String query = 'SELECT Id, Name, Message__c, Image_URL__c, OwnerId, Posted_By__c, Posted_By__r.Name, Posted_By__r.Full_Name__c FROM Story__c WHERE Id = :storyId '
                + 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';

            if (String.isNotBlank(neighbourhoodAccountId)) {
                query += ' AND (Neighbourhood__c = :neighbourhoodAccountId'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Contact__c IN :sharedContactIds))';
            }

            query += ' LIMIT 1';

            List<Story__c> stories = Database.query(query);
            if (stories.isEmpty()) {
                return null;
            }

            Story__c story = stories[0];
            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks(viewerActingAsContactId);
            if (story.Posted_By__c != null && blockedContactIds.contains(story.Posted_By__c)) {
                return null;
            }
            return story;
        }

        public void insertComment(Story_Comment__c comment) {
            insert comment;
        }
    }
}
