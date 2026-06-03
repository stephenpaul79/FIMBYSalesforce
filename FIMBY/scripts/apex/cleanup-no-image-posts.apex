/**
 * Delete Needs_Offers__c / Story__c with no primary image and all related data.
 * Delete order mirrors FimbyTestDataCleanup (children before parents).
 *
 * Dry run:  sf apex run --file scripts/apex/cleanup-no-image-posts.apex
 * Delete:    set EXECUTE_DELETE = true, then run the same command.
 */
Boolean EXECUTE_DELETE = false;
Boolean INCLUDE_BULK_BUY = true;
Boolean INCLUDE_STORIES = true;
Boolean QA_ONLY = false;
Datetime CREATED_ON_OR_AFTER = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);

String noImgNeedsSoql =
    'SELECT Id, Group_Conversation__c FROM Needs_Offers__c' +
    ' WHERE Image_1_URL__c = null AND CreatedDate >= :CREATED_ON_OR_AFTER';
if (!INCLUDE_BULK_BUY) {
    noImgNeedsSoql += ' AND RecordType.Name IN (\'Need\', \'Offer\')';
}
if (QA_ONLY) {
    noImgNeedsSoql += ' AND Name LIKE \'QA%\'';
}

List<Needs_Offers__c> needsToDelete = Database.query(noImgNeedsSoql);
Set<Id> needIds = new Map<Id, Needs_Offers__c>(needsToDelete).keySet();

List<Story__c> storiesToDelete = new List<Story__c>();
if (INCLUDE_STORIES) {
    String storySoql =
        'SELECT Id FROM Story__c WHERE Image_URL__c = null' +
        ' AND CreatedDate >= :CREATED_ON_OR_AFTER';
    if (QA_ONLY) {
        storySoql += ' AND Name LIKE \'QA%\'';
    }
    storiesToDelete = Database.query(storySoql);
}
Set<Id> storyIds = new Map<Id, Story__c>(storiesToDelete).keySet();

List<Response__c> responses = needIds.isEmpty()
    ? new List<Response__c>()
    : [
          SELECT Id
          FROM Response__c
          WHERE Need_Offer_Responded_To__c IN :needIds
      ];
Set<Id> responseIds = new Map<Id, Response__c>(responses).keySet();

List<Bulk_Buy_Follow_Up__c> followUps = needIds.isEmpty()
    ? new List<Bulk_Buy_Follow_Up__c>()
    : [
          SELECT Id, Checkin_Conversation__c
          FROM Bulk_Buy_Follow_Up__c
          WHERE Bulk_Buy__c IN :needIds OR Reservation__c IN :responseIds
      ];

Set<Id> conversationIds = new Set<Id>();
for (Needs_Offers__c post : needsToDelete) {
    if (post.Group_Conversation__c != null) {
        conversationIds.add(post.Group_Conversation__c);
    }
}
for (Bulk_Buy_Follow_Up__c fu : followUps) {
    if (fu.Checkin_Conversation__c != null) {
        conversationIds.add(fu.Checkin_Conversation__c);
    }
}

Set<String> notificationRecordIdStrs = new Set<String>();
for (Id idVal : needIds) {
    notificationRecordIdStrs.add((String) idVal);
}
for (Id idVal : storyIds) {
    notificationRecordIdStrs.add((String) idVal);
}
for (Id idVal : responseIds) {
    notificationRecordIdStrs.add((String) idVal);
}
for (Id idVal : conversationIds) {
    notificationRecordIdStrs.add((String) idVal);
}

System.debug('NEEDS_OFFERS_NO_IMAGE=' + needsToDelete.size());
System.debug('STORIES_NO_IMAGE=' + storiesToDelete.size());
System.debug('RESPONSES=' + responses.size());
System.debug(
    'RESPONSE_MESSAGES=' +
        (responseIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Response_Message__c WHERE Response__c IN :responseIds])
);
System.debug('BULK_BUY_FOLLOW_UPS=' + followUps.size());
System.debug(
    'SHARED_CONTACT_INFO=' +
        (responseIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Shared_Contact_Info__c WHERE Response__c IN :responseIds])
);
System.debug(
    'RESPONSE_CONTACT_INFO=' +
        (responseIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Response_Contact_Info__c WHERE Response__c IN :responseIds])
);
System.debug(
    'NOTIFICATIONS=' +
        (notificationRecordIdStrs.isEmpty()
            ? 0
            : [
                  SELECT COUNT()
                  FROM Notification__c
                  WHERE Related_Record_Id__c IN :notificationRecordIdStrs
              ])
);
System.debug('CONVERSATIONS=' + conversationIds.size());
System.debug(
    'CONVERSATION_MEMBERS=' +
        (conversationIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Conversation_Member__c WHERE Conversation__c IN :conversationIds])
);
System.debug(
    'DM_MESSAGES=' +
        (conversationIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Message__c WHERE Conversation__c IN :conversationIds])
);
System.debug(
    'STORY_COMMENTS_CASCADE=' +
        (storyIds.isEmpty() ? 0 : [SELECT COUNT() FROM Story_Comment__c WHERE Story__c IN :storyIds])
);

if (!EXECUTE_DELETE) {
    System.debug('DRY_RUN=true — set EXECUTE_DELETE=true to delete.');
} else {
    if (!notificationRecordIdStrs.isEmpty()) {
        delete [
            SELECT Id
            FROM Notification__c
            WHERE Related_Record_Id__c IN :notificationRecordIdStrs
        ];
    }
    if (!responseIds.isEmpty()) {
        delete [SELECT Id FROM Response_Message__c WHERE Response__c IN :responseIds];
        delete [SELECT Id FROM Shared_Contact_Info__c WHERE Response__c IN :responseIds];
        delete [SELECT Id FROM Response_Contact_Info__c WHERE Response__c IN :responseIds];
    }
    if (!followUps.isEmpty()) {
        delete followUps;
    }
    if (!responses.isEmpty()) {
        delete responses;
    }
    if (!needsToDelete.isEmpty()) {
        delete needsToDelete;
    }
    if (!storiesToDelete.isEmpty()) {
        delete storiesToDelete;
    }
    if (!conversationIds.isEmpty()) {
        delete [SELECT Id FROM Conversation_Member__c WHERE Conversation__c IN :conversationIds];
        delete [SELECT Id FROM Message__c WHERE Conversation__c IN :conversationIds];
        delete [SELECT Id FROM Conversation__c WHERE Id IN :conversationIds];
    }
    System.debug('DELETE_COMPLETE=true');
}
