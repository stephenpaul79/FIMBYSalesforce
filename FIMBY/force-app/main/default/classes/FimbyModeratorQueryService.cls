public without sharing class FimbyModeratorQueryService {

    public static Map<String, Object> getDashboardSummary(Id neighbourhoodId) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Category__c cat, COUNT(Id) cnt
            FROM Moderator_Task__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c IN ('New', 'In_Progress', 'Awaiting_Info')
            GROUP BY Category__c
        ]) {
            counts.put((String) ar.get('cat'), ((Decimal) ar.get('cnt')).intValue());
        }

        Integer urgentCount = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c IN ('New', 'In_Progress', 'Awaiting_Info')
              AND Priority__c = 'Urgent'
        ];

        Integer escalatedCount = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c = 'Escalated'
        ];

        return new Map<String, Object>{
            'categoryCounts' => counts,
            'urgentCount' => urgentCount,
            'escalatedCount' => escalatedCount,
            'totalCount' => sumCounts(counts) + escalatedCount
        };
    }

    public static List<Moderator_Task__c> getTasksByCategory(
        Id neighbourhoodId, String category, Integer pageSize, Integer offset
    ) {
        String query = 'SELECT Id, Name, Category__c, Priority__c, Status__c, Summary__c, '
            + 'Report_Count__c, Latest_Reported_Date__c, Latest_Report_Reason__c, '
            + 'Subject_Contact__c, Subject_Contact__r.Name, Subject_Contact__r.Image_URL__c, '
            + 'Secondary_Contact__c, Secondary_Contact__r.Name, Secondary_Contact__r.Image_URL__c, '
            + 'Related_Record_Id__c, Related_Record_Type__c, '
            + 'Severity_Mix__c, Claimed_Date__c, OwnerId, '
            + 'Escalated_To__c, Escalated_To__r.Name, Escalated_Date__c, Escalation_Reason__c, '
            + 'Hours_Open__c, Is_Overdue__c, '
            + 'CreatedDate '
            + 'FROM Moderator_Task__c '
            + 'WHERE Neighbourhood__c = :neighbourhoodId '
            + 'AND Status__c IN (\'New\', \'In_Progress\', \'Awaiting_Info\')';

        if (String.isNotBlank(category) && category != 'All') {
            query += ' AND Category__c = :category';
        }

        // Order by oldest-first within priority — surfaces SLA-overdue tasks at the top
        // so moderators meet the public 24-hour response commitment.
        query += ' ORDER BY Priority__c DESC, CreatedDate ASC '
               + 'LIMIT :pageSize OFFSET :offset';

        return Database.query(query);
    }

    private static final Set<String> CLOSED_TASK_CATEGORIES = new Set<String>{
        'Content_Report', 'Blocked_Contact', 'Support_Relationship_Approval', 'Organization_Approval',
        'Support_Person_Concern', 'Bulk_Buy_Escalation', 'Feedback_Triage', 'New_Signup'
    };

    private static final Set<String> CLOSED_TASK_STATUS_FILTERS = new Set<String>{
        'All', 'Resolved', 'Dismissed'
    };

    public static Map<String, Object> getClosedTasks(
        Id neighbourhoodId, String category, String statusFilter,
        Integer pageSize, Integer offset
    ) {
        if (String.isBlank(category)) {
            category = 'All';
        }
        if (String.isBlank(statusFilter)) {
            statusFilter = 'All';
        }
        if (category != 'All' && !CLOSED_TASK_CATEGORIES.contains(category)) {
            throw new AuraHandledException('Invalid category filter.');
        }
        if (!CLOSED_TASK_STATUS_FILTERS.contains(statusFilter)) {
            throw new AuraHandledException('Invalid status filter.');
        }

        List<String> statusList = new List<String>{ 'Resolved', 'Dismissed' };
        if (statusFilter == 'Resolved') {
            statusList = new List<String>{ 'Resolved' };
        } else if (statusFilter == 'Dismissed') {
            statusList = new List<String>{ 'Dismissed' };
        }

        String countSoql = 'SELECT COUNT() FROM Moderator_Task__c '
            + 'WHERE Neighbourhood__c = :neighbourhoodId AND Status__c IN :statusList';
        if (category != 'All') {
            countSoql += ' AND Category__c = :category';
        }
        Integer totalCount = Database.countQuery(countSoql);

        String query = 'SELECT Id, Name, Category__c, Priority__c, Status__c, Summary__c, '
            + 'Report_Count__c, Subject_Contact__c, Subject_Contact__r.Name, '
            + 'Resolved_Date__c, Resolved_By__c, Resolved_By__r.Name, '
            + 'Decision_Reason_Code__c, Enforcement_Level__c, CreatedDate '
            + 'FROM Moderator_Task__c '
            + 'WHERE Neighbourhood__c = :neighbourhoodId '
            + 'AND Status__c IN :statusList';
        if (category != 'All') {
            query += ' AND Category__c = :category';
        }
        query += ' ORDER BY Resolved_Date__c DESC NULLS LAST, CreatedDate DESC '
               + 'LIMIT :pageSize OFFSET :offset';

        return new Map<String, Object>{
            'items' => Database.query(query),
            'totalCount' => totalCount
        };
    }

    public static List<Moderator_Task__c> getEscalatedTasks(Id neighbourhoodId, Integer pageSize, Integer offset) {
        return [
            SELECT Id, Name, Category__c, Priority__c, Status__c, Summary__c,
                   Escalated_To__c, Escalated_To__r.Name, Escalated_Date__c,
                   Escalation_Reason__c, Resolved_Date__c, Resolved_By__c,
                   Subject_Contact__c, Subject_Contact__r.Name, CreatedDate
            FROM Moderator_Task__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c = 'Escalated'
            ORDER BY Escalated_Date__c DESC
            LIMIT :pageSize OFFSET :offset
        ];
    }

    public static Map<String, Object> getTaskPageBootstrap(Id taskId) {
        List<Moderator_Task__c> tasks = [
            SELECT Id, Name, Category__c, Priority__c, Status__c, Summary__c,
                   Enforcement_Level__c, Claimed_Date__c,
                   Report_Count__c, Subject_Contact__c, Subject_Contact__r.Name,
                   Secondary_Contact__c, Secondary_Contact__r.Name,
                   Related_Record_Id__c, Related_Record_Type__c,
                   Neighbourhood__c, CreatedDate,
                   Resolved_Date__c, Resolved_By__c, Resolved_By__r.Name,
                   Decision_Reason_Code__c, Notes__c
            FROM Moderator_Task__c
            WHERE Id = :taskId
            LIMIT 1
        ];
        if (tasks.isEmpty()) {
            throw new AuraHandledException('Moderator task not found.');
        }
        Moderator_Task__c task = tasks[0];
        return new Map<String, Object>{
            'task' => task,
            'taskId' => task.Id,
            'category' => task.Category__c,
            'priority' => task.Priority__c,
            'status' => task.Status__c,
            'enforcementLevel' => task.Enforcement_Level__c,
            'claimedDate' => String.valueOf(task.Claimed_Date__c),
            'summary' => task.Summary__c,
            'neighbourhoodId' => task.Neighbourhood__c,
            'createdDate' => String.valueOf(task.CreatedDate)
        };
    }

    public static Map<String, Object> getContentReviewData(String recordId, String recordType, Id taskId) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('recordType', recordType);
        result.put('recordId', recordId);

        if (taskId != null) {
            List<Moderator_Task__c> tasks = [
                SELECT Secondary_Contact__c, Secondary_Contact__r.Name,
                       Secondary_Contact__r.Image_URL__c
                FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
            ];
            if (!tasks.isEmpty() && tasks[0].Secondary_Contact__c != null) {
                result.put('reporterContactId', tasks[0].Secondary_Contact__c);
                result.put('reporterName', tasks[0].Secondary_Contact__r.Name);
                result.put('reporterPhotoUrl', tasks[0].Secondary_Contact__r.Image_URL__c);
            }
        }

        if (recordType == 'Needs_Offers__c') {
            List<Needs_Offers__c> records = [
                SELECT Id, Name, Details__c, Type__c, Status__c, RecordType.Name,
                       Contact__c, Contact__r.Name, Contact__r.Image_URL__c,
                       Posted_By__c, Posted_By__r.Name,
                       Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c,
                       Hidden_Reason_Code__c, Flag_Inappropriate_Content__c,
                       Image_1_URL__c, Image_2_URL__c, Image_3_URL__c, Image_4_URL__c,
                       CreatedDate, Neighbourhood__c
                FROM Needs_Offers__c WHERE Id = :recordId LIMIT 1
            ];
            if (!records.isEmpty()) {
                Needs_Offers__c r = records[0];
                result.put('contentTitle', r.Name);
                result.put('contentBody', r.Details__c);
                result.put('authorName', r.Contact__r != null ? r.Contact__r.Name : '');
                result.put('authorPhotoUrl', r.Contact__r != null ? r.Contact__r.Image_URL__c : null);
                result.put('authorContactId', r.Contact__c);
                result.put('postDate', String.valueOf(r.CreatedDate));
                result.put('moderationStatus', r.Moderation_Status__c);
                result.put('imageUrls', buildImageList(new List<String>{
                    r.Image_1_URL__c, r.Image_2_URL__c, r.Image_3_URL__c, r.Image_4_URL__c
                }));
                String ct;
                if (r.Type__c == 'Event') {
                    ct = 'Event';
                } else if (r.RecordType != null && r.RecordType.Name == 'Need') {
                    ct = 'Ask';
                } else if (r.RecordType != null && r.RecordType.Name == 'Offer') {
                    ct = 'Offer';
                } else if (r.RecordType != null && r.RecordType.Name == 'Bulk_Buy') {
                    ct = 'Bulk Buy';
                } else {
                    ct = 'Ask or Offer';
                }
                result.put('contentType', ct);
            }
        } else if (recordType == 'Response__c') {
            List<Response__c> records = [
                SELECT Id, Name, Response__c, Status__c,
                       Contact__c, Contact__r.Name, Contact__r.Image_URL__c,
                       Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c,
                       Hidden_Reason_Code__c, CreatedDate
                FROM Response__c WHERE Id = :recordId LIMIT 1
            ];
            if (!records.isEmpty()) {
                Response__c r = records[0];
                result.put('contentTitle', r.Name);
                result.put('contentBody', r.Response__c);
                result.put('authorName', r.Contact__r != null ? r.Contact__r.Name : '');
                result.put('authorPhotoUrl', r.Contact__r != null ? r.Contact__r.Image_URL__c : null);
                result.put('authorContactId', r.Contact__c);
                result.put('postDate', String.valueOf(r.CreatedDate));
                result.put('moderationStatus', r.Moderation_Status__c);
                result.put('imageUrls', new List<String>());
                result.put('contentType', 'Response');
            }
        } else if (recordType == 'Story__c') {
            List<Story__c> records = [
                SELECT Id, Name, Message__c, Type__c,
                       Posted_By__c, Posted_By__r.Name, Posted_By__r.Image_URL__c,
                       Contact__c, Contact__r.Name,
                       Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c,
                       Hidden_Reason_Code__c, Image_URL__c, CreatedDate
                FROM Story__c WHERE Id = :recordId LIMIT 1
            ];
            if (!records.isEmpty()) {
                Story__c r = records[0];
                result.put('contentTitle', r.Name);
                result.put('contentBody', r.Message__c);
                result.put('authorName', r.Posted_By__r != null ? r.Posted_By__r.Name : '');
                result.put('authorPhotoUrl', r.Posted_By__r != null ? r.Posted_By__r.Image_URL__c : null);
                result.put('authorContactId', r.Posted_By__c);
                result.put('postDate', String.valueOf(r.CreatedDate));
                result.put('moderationStatus', r.Moderation_Status__c);
                result.put('imageUrls', buildImageList(new List<String>{ r.Image_URL__c }));
                result.put('contentType', 'Shared Life');
            }
        } else if (recordType == 'Library_Item__c') {
            List<Library_Item__c> records = [
                SELECT Id, Name, Description__c, Status__c,
                       Owner_Contact__c, Owner_Contact__r.Name, Owner_Contact__r.Image_URL__c,
                       Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c,
                       Hidden_Reason_Code__c, Image_URL__c, CreatedDate
                FROM Library_Item__c WHERE Id = :recordId LIMIT 1
            ];
            if (!records.isEmpty()) {
                Library_Item__c r = records[0];
                result.put('contentTitle', r.Name);
                result.put('contentBody', r.Description__c);
                result.put('authorName', r.Owner_Contact__r != null ? r.Owner_Contact__r.Name : '');
                result.put('authorPhotoUrl', r.Owner_Contact__r != null ? r.Owner_Contact__r.Image_URL__c : null);
                result.put('authorContactId', r.Owner_Contact__c);
                result.put('postDate', String.valueOf(r.CreatedDate));
                result.put('moderationStatus', r.Moderation_Status__c);
                result.put('imageUrls', buildImageList(new List<String>{ r.Image_URL__c }));
                result.put('contentType', 'Library Item');
            }
        } else if (recordType == 'Story_Comment__c') {
            List<Story_Comment__c> records = [
                SELECT Id, Body__c, Status__c, Edit_Count__c, Edited_Date__c,
                       Story__c, Story__r.Name,
                       Posted_By__c, Posted_By__r.Name, Posted_By__r.Image_URL__c,
                       Contact__c, Contact__r.Name,
                       Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c,
                       Hidden_Reason_Code__c, CreatedDate
                FROM Story_Comment__c WHERE Id = :recordId LIMIT 1
            ];
            if (!records.isEmpty()) {
                Story_Comment__c r = records[0];
                String parentName = r.Story__r != null ? r.Story__r.Name : '';
                result.put('contentTitle', String.isNotBlank(parentName)
                    ? 'Comment on: ' + parentName
                    : 'Comment');
                result.put('contentBody', r.Body__c);
                result.put('authorName', r.Posted_By__r != null ? r.Posted_By__r.Name : '');
                result.put('authorPhotoUrl', r.Posted_By__r != null ? r.Posted_By__r.Image_URL__c : null);
                result.put('authorContactId', r.Posted_By__c);
                result.put('postDate', String.valueOf(r.CreatedDate));
                result.put('moderationStatus', r.Moderation_Status__c);
                result.put('imageUrls', new List<String>());
                result.put('contentType', 'Comment');
            }
        }

        if (taskId != null) {
            List<Moderator_Task_Evidence__c> evidence = [
                SELECT Id, Source_Type__c, Reporter__c, Reporter__r.Name,
                       Reported_Date__c, Reason_Code__c, Details__c
                FROM Moderator_Task_Evidence__c
                WHERE Moderator_Task__c = :taskId
                ORDER BY Reported_Date__c DESC
            ];
            result.put('evidenceItems', buildEvidenceTimelineItems(evidence));
        }

        return result;
    }

    public static Map<String, Object> getNeighbourhoodHealthData(Id neighbourhoodId) {
        List<Map<String, Object>> overdueLoans = new List<Map<String, Object>>();
        for (Library_Item__c item : getOverdueLoans(neighbourhoodId)) {
            if (item.Loaned_Items__r == null) {
                continue;
            }
            for (Loaned_Item__c loan : item.Loaned_Items__r) {
                Integer daysOverdue = 0;
                if (loan.Loan_Due_Date__c != null) {
                    daysOverdue = loan.Loan_Due_Date__c.daysBetween(Date.today());
                }
                overdueLoans.add(new Map<String, Object>{
                    'id' => loan.Id,
                    'itemId' => item.Id,
                    'itemName' => item.Name,
                    'itemLink' => '/library-item/' + item.Id,
                    'borrowerId' => loan.Loaned_To__c,
                    'borrowerName' => loan.Loaned_To__r != null ? loan.Loaned_To__r.Name : '',
                    'ownerId' => item.Owner_Contact__c,
                    'ownerName' => item.Owner_Contact__r != null ? item.Owner_Contact__r.Name : '',
                    'daysOverdue' => daysOverdue,
                    'dueDate' => loan.Loan_Due_Date__c != null ? String.valueOf(loan.Loan_Due_Date__c) : ''
                });
            }
        }

        List<Map<String, Object>> stalePosts = new List<Map<String, Object>>();
        for (Needs_Offers__c post : getStaleExpiredPosts(neighbourhoodId)) {
            stalePosts.add(new Map<String, Object>{
                'id' => post.Id,
                'postId' => post.Id,
                'title' => post.Name,
                'postLink' => '/ask-or-offer-post?recordId=' + post.Id,
                'type' => post.Type__c,
                'authorId' => post.Posted_By__c,
                'authorName' => post.Posted_By__r != null ? post.Posted_By__r.Name : '',
                'expiredDate' => String.valueOf(post.CreatedDate)
            });
        }

        List<Map<String, Object>> inactiveMembers = new List<Map<String, Object>>();
        Date today = Date.today();
        for (Contact member : getInactiveMembers(neighbourhoodId)) {
            Integer daysInactive = 60;
            if (member.LastActivityDate != null) {
                daysInactive = member.LastActivityDate.daysBetween(today);
            } else if (member.CreatedDate != null) {
                daysInactive = member.CreatedDate.date().daysBetween(today);
            }
            inactiveMembers.add(new Map<String, Object>{
                'id' => member.Id,
                'contactId' => member.Id,
                'name' => member.Name,
                'lastActivity' => member.LastActivityDate != null
                    ? String.valueOf(member.LastActivityDate)
                    : 'No activity recorded',
                'daysInactive' => daysInactive,
                'memberSince' => String.valueOf(member.CreatedDate.date())
            });
        }

        return new Map<String, Object>{
            'overdueLoans' => overdueLoans,
            'stalePosts' => stalePosts,
            'inactiveMembers' => inactiveMembers
        };
    }

    private static List<String> buildImageList(List<String> candidates) {
        List<String> urls = new List<String>();
        for (String s : candidates) {
            if (String.isNotBlank(s)) {
                urls.add(s);
            }
        }
        return urls;
    }

    public static Map<String, Object> getFollowUpReviewData(Id followUpId) {
        Bulk_Buy_Follow_Up__c fu = [
            SELECT Id, Name, Status__c, Reason_Subtype__c, Report_Message__c,
                   Reporter__c, Reporter__r.Name, Reporter__r.Image_URL__c,
                   Reported_User__c, Reported_User__r.Name, Reported_User__r.Image_URL__c,
                   Bulk_Buy__c, Bulk_Buy__r.Name, Bulk_Buy__r.Id,
                   Bulk_Buy__r.Contact__c, Bulk_Buy__r.Contact__r.Name,
                   Bulk_Buy__r.Contact__r.Image_URL__c,
                   Checkin_Conversation__c, Resolution_Notes__c, CreatedDate
            FROM Bulk_Buy_Follow_Up__c
            WHERE Id = :followUpId LIMIT 1
        ];

        Map<String, Object> result = new Map<String, Object>();
        result.put('followUpId', fu.Id);
        result.put('bulkBuyName', fu.Bulk_Buy__r != null ? fu.Bulk_Buy__r.Name : '');
        result.put('bulkBuyId', fu.Bulk_Buy__c);
        result.put('organiserName', fu.Bulk_Buy__r != null && fu.Bulk_Buy__r.Contact__r != null
            ? fu.Bulk_Buy__r.Contact__r.Name : '');
        result.put('organiserPhotoUrl', fu.Bulk_Buy__r != null && fu.Bulk_Buy__r.Contact__r != null
            ? fu.Bulk_Buy__r.Contact__r.Image_URL__c : null);
        result.put('reportedUserName', fu.Reported_User__r != null ? fu.Reported_User__r.Name : '');
        result.put('reportedUserPhotoUrl', fu.Reported_User__r != null ? fu.Reported_User__r.Image_URL__c : null);
        result.put('reportedUserId', fu.Reported_User__c);
        result.put('reporterName', fu.Reporter__r != null ? fu.Reporter__r.Name : '');
        result.put('reporterPhotoUrl', fu.Reporter__r != null ? fu.Reporter__r.Image_URL__c : null);
        result.put('organiserContactId', fu.Bulk_Buy__r != null ? fu.Bulk_Buy__r.Contact__c : null);
        result.put('reporterContactId', fu.Reporter__c);
        result.put('reasonSubtype', fu.Reason_Subtype__c);
        result.put('reportMessage', fu.Report_Message__c);
        result.put('followUpStatus', fu.Status__c);
        result.put('contentType', 'Bulk Buy');

        Boolean isBlocked = false;
        String blockReason = '';
        if (fu.Reported_User__c != null) {
            List<Blocked_Contact__c> blocks = [
                SELECT Id, Report_Details__c FROM Blocked_Contact__c
                WHERE Blocked__c = :fu.Reported_User__c AND Blocker__c = :fu.Reporter__c
                LIMIT 1
            ];
            if (!blocks.isEmpty()) {
                isBlocked = true;
                blockReason = blocks[0].Report_Details__c;
            }
        }
        result.put('isBlocked', isBlocked);
        result.put('blockReason', blockReason);

        List<Map<String, Object>> timeline = new List<Map<String, Object>>();
        if (fu.Reported_User__c != null && fu.Bulk_Buy__c != null) {
            for (Bulk_Buy_Follow_Up__c entry : [
                SELECT Id, Status__c, Resolution_Notes__c, CreatedDate
                FROM Bulk_Buy_Follow_Up__c
                WHERE Reported_User__c = :fu.Reported_User__c
                  AND Bulk_Buy__c = :fu.Bulk_Buy__c
                ORDER BY CreatedDate ASC
            ]) {
                timeline.add(new Map<String, Object>{
                    'status' => entry.Status__c,
                    'notes' => entry.Resolution_Notes__c,
                    'date' => String.valueOf(entry.CreatedDate)
                });
            }
        }
        result.put('followUpTimeline', timeline);

        return result;
    }

    public static Map<String, Object> getBlockReviewData(Id blockedContactId) {
        List<Blocked_Contact__c> blocks = [
            SELECT Id, Blocker__c, Blocker__r.Name, Blocker__r.Image_URL__c,
                   Blocked__c, Blocked__r.Name, Blocked__r.Image_URL__c,
                   Reported__c, Report_Details__c, CreatedDate
            FROM Blocked_Contact__c
            WHERE Id = :blockedContactId
            LIMIT 1
        ];

        if (blocks.isEmpty()) {
            return new Map<String, Object>{
                'blockerName' => '',
                'blockerPhotoUrl' => null,
                'blockerContactId' => null,
                'blockedName' => '',
                'blockedPhotoUrl' => null,
                'blockedContactId' => null,
                'date' => '',
                'reason' => 'The original block record is no longer available.',
                'reportDetails' => null,
                'otherBlocks' => new List<Map<String, Object>>(),
                'otherBlockCount' => 0,
                'recordMissing' => true
            };
        }

        Blocked_Contact__c bc = blocks[0];

        Map<String, Object> result = new Map<String, Object>();
        result.put('blockerName', bc.Blocker__r != null ? bc.Blocker__r.Name : '');
        result.put('blockerPhotoUrl', bc.Blocker__r != null ? bc.Blocker__r.Image_URL__c : null);
        result.put('blockerContactId', bc.Blocker__c);
        result.put('blockedName', bc.Blocked__r != null ? bc.Blocked__r.Name : '');
        result.put('blockedPhotoUrl', bc.Blocked__r != null ? bc.Blocked__r.Image_URL__c : null);
        result.put('blockedContactId', bc.Blocked__c);
        result.put('date', String.valueOf(bc.CreatedDate));
        result.put('reason', bc.Reported__c ? 'This block was reported to the neighbourhood team.' : 'Direct block only.');
        result.put('reportDetails', bc.Report_Details__c);

        List<Blocked_Contact__c> others = [
            SELECT Id, Blocker__r.Name, Blocked__r.Name, CreatedDate
            FROM Blocked_Contact__c
            WHERE (Blocker__c = :bc.Blocker__c OR Blocked__c = :bc.Blocker__c
                OR Blocker__c = :bc.Blocked__c OR Blocked__c = :bc.Blocked__c)
              AND Id != :blockedContactId
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];

        List<Map<String, Object>> otherBlocks = new List<Map<String, Object>>();
        for (Blocked_Contact__c ob : others) {
            otherBlocks.add(new Map<String, Object>{
                'id' => ob.Id,
                'blockerName' => ob.Blocker__r != null ? ob.Blocker__r.Name : '',
                'blockedName' => ob.Blocked__r != null ? ob.Blocked__r.Name : '',
                'date' => String.valueOf(ob.CreatedDate)
            });
        }
        result.put('otherBlocks', otherBlocks);
        result.put('otherBlockCount', others.size());

        return result;
    }

    public static Map<String, Object> getFeedbackReviewData(Id feedbackId) {
        Feedback__c fb = [
            SELECT Id, Name, Type__c, Details__c, Status__c,
                   Posted_By__c, Posted_By__r.Name, Posted_By__r.Image_URL__c,
                   Image_URL__c, Related_Record_ID__c, Related_Record_Link__c,
                   Triage_Status__c, CreatedDate
            FROM Feedback__c
            WHERE Id = :feedbackId LIMIT 1
        ];
        return new Map<String, Object>{
            'feedbackId' => fb.Id,
            'type' => fb.Type__c,
            'title' => fb.Name,
            'description' => fb.Details__c,
            'submitterName' => fb.Posted_By__r != null ? fb.Posted_By__r.Name : '',
            'submitterPhotoUrl' => fb.Posted_By__r != null ? fb.Posted_By__r.Image_URL__c : null,
            'submitterContactId' => fb.Posted_By__c,
            'screenshotUrl' => fb.Image_URL__c,
            'relatedRecordId' => fb.Related_Record_ID__c,
            'relatedRecordLink' => fb.Related_Record_Link__c,
            'triageStatus' => fb.Triage_Status__c,
            'date' => String.valueOf(fb.CreatedDate)
        };
    }

    public static Map<String, Object> getSupportReviewData(Id supportRelationshipId) {
        Support_Relationship__c sr = [
            SELECT Id, Name, Status__c, Relationship_Type__c,
                   Contact__c, Contact__r.Name, Contact__r.Image_URL__c,
                   Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.Image_URL__c,
                   Related_Organization__c, Related_Organization__r.Name,
                   Related_Organization__r.Verification_Status__c,
                   Related_Organization__r.Is_Approved_Community_Group__c,
                   Requester_Org_Role__c,
                   Consent_Method__c, Authorization_Image_URL__c, Notes__c,
                   Neighbourhood__c, CreatedDate
            FROM Support_Relationship__c
            WHERE Id = :supportRelationshipId LIMIT 1
        ];
        Integer priorRevocations = [
            SELECT COUNT() FROM Support_Relationship__c
            WHERE Contact__c = :sr.Contact__c
              AND Id != :sr.Id
              AND Status__c = 'Revoked'
        ];
        String subjectName = sr.Related_Contact__r != null ? sr.Related_Contact__r.Name : '';
        String subjectPhoto = sr.Related_Contact__r != null ? sr.Related_Contact__r.Image_URL__c : null;
        Id subjectContactId = sr.Related_Contact__c;
        if (sr.Relationship_Type__c == 'Community_Group_Rep' && sr.Related_Organization__c != null) {
            subjectName = sr.Related_Organization__r.Name;
            subjectContactId = null;
        }
        return new Map<String, Object>{
            'supportRelationshipId' => sr.Id,
            'helperName' => sr.Contact__r != null ? sr.Contact__r.Name : '',
            'helperPhotoUrl' => sr.Contact__r != null ? sr.Contact__r.Image_URL__c : null,
            'helperContactId' => sr.Contact__c,
            'subjectName' => subjectName,
            'subjectPhotoUrl' => subjectPhoto,
            'subjectContactId' => subjectContactId,
            'relationshipType' => sr.Relationship_Type__c,
            'requesterOrgRole' => sr.Requester_Org_Role__c,
            'orgVerificationStatus' => sr.Related_Organization__r?.Verification_Status__c,
            'orgVerified' => FimbyModeratorActionService.isOrganizationVerifiedForRepApproval(
                sr.Related_Organization__r?.Verification_Status__c
            ),
            'consentMethod' => sr.Consent_Method__c,
            'authorizationImageUrl' => sr.Authorization_Image_URL__c,
            'notes' => sr.Notes__c,
            'submissionDate' => String.valueOf(sr.CreatedDate),
            'hasPriorRevocation' => priorRevocations > 0
        };
    }

    public static Map<String, Object> getOrganizationReviewData(Id accountId, Id taskId) {
        Account acct = [
            SELECT Id, Name, Type, Phone, Org_Email__c, Website, Description,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   Is_Registered_Charity__c, Charity_Verification_URL__c,
                   Charity_Registration_Number__c, Verification_Method__c,
                   Verification_Status__c, Verification_Document_URL__c,
                   Submitted_By__c, Submitted_By__r.Name,
                   Submitted_By__r.Image_URL__c, Submitted_Date__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        String orgEmail = null;
        if (taskId != null) {
            List<Moderator_Task_Evidence__c> evidenceRows = [
                SELECT Details__c
                FROM Moderator_Task_Evidence__c
                WHERE Moderator_Task__c = :taskId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!evidenceRows.isEmpty() && String.isNotBlank(evidenceRows[0].Details__c)) {
                for (String line : evidenceRows[0].Details__c.split('\n')) {
                    if (line.startsWith('Org email: ')) {
                        orgEmail = line.substring('Org email: '.length()).trim();
                    }
                }
            }
        }

        List<Support_Relationship__c> pendingReps = [
            SELECT Id, Status__c, Requester_Org_Role__c, Authorization_Image_URL__c,
                   Notes__c, Consent_Method__c,
                   Contact__c, Contact__r.Name, Contact__r.Image_URL__c
            FROM Support_Relationship__c
            WHERE Related_Organization__c = :accountId
              AND Relationship_Type__c = 'Community_Group_Rep'
              AND Status__c = 'Pending'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        Support_Relationship__c pendingRep = pendingReps.isEmpty() ? null : pendingReps[0];

        Id repTaskId = null;
        if (pendingRep != null) {
            List<Moderator_Task__c> repTasks = [
                SELECT Id
                FROM Moderator_Task__c
                WHERE Category__c = 'Support_Relationship_Approval'
                  AND Related_Record_Id__c = :String.valueOf(pendingRep.Id)
                  AND Status__c IN ('New', 'In_Progress', 'Awaiting_Info', 'Escalated')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!repTasks.isEmpty()) {
                repTaskId = repTasks[0].Id;
            }
        }

        List<String> verificationDocIds = collectVerificationDocVersionIds(accountId, pendingRep?.Id);
        List<Map<String, String>> verificationDocs = buildVerificationDocs(acct, verificationDocIds);

        return new Map<String, Object>{
            'accountId' => acct.Id,
            'orgName' => acct.Name,
            'orgType' => acct.Type,
            'orgPhone' => acct.Phone,
            'orgEmail' => String.isNotBlank(acct.Org_Email__c) ? acct.Org_Email__c : orgEmail,
            'orgWebsite' => acct.Website,
            'orgDescription' => acct.Description,
            'billingStreet' => acct.BillingStreet,
            'billingCity' => acct.BillingCity,
            'billingState' => acct.BillingState,
            'billingPostalCode' => acct.BillingPostalCode,
            'billingCountry' => acct.BillingCountry,
            'isRegisteredCharity' => acct.Is_Registered_Charity__c == true,
            'charityVerificationUrl' => acct.Charity_Verification_URL__c,
            'charityRegistrationNumber' => acct.Charity_Registration_Number__c,
            'verificationMethods' => acct.Verification_Method__c,
            'verificationStatus' => acct.Verification_Status__c,
            'orgVerified' => acct.Verification_Status__c == 'Verified',
            'requesterName' => pendingRep?.Contact__r?.Name ?? acct.Submitted_By__r?.Name,
            'requesterPhotoUrl' => pendingRep?.Contact__r?.Image_URL__c ?? acct.Submitted_By__r?.Image_URL__c,
            'requesterContactId' => pendingRep?.Contact__c ?? acct.Submitted_By__c,
            'submittedDate' => acct.Submitted_Date__c != null ? String.valueOf(acct.Submitted_Date__c) : null,
            'pendingSupportRelationshipId' => pendingRep?.Id,
            'pendingRepTaskId' => repTaskId,
            'requesterOrgRole' => pendingRep?.Requester_Org_Role__c,
            'consentMethod' => pendingRep?.Consent_Method__c,
            'authorizationImageUrl' => pendingRep?.Authorization_Image_URL__c,
            'repNotes' => pendingRep?.Notes__c,
            'repPending' => pendingRep != null,
            'verificationContentVersionIds' => verificationDocIds,
            'verificationDocs' => verificationDocs
        };
    }

    private static List<String> collectVerificationDocVersionIds(Id accountId, Id legacyRepId) {
        List<String> versionIds = queryContentVersionIdsForEntity(accountId);
        // Legacy: docs uploaded before we linked verification files to the org Account.
        if (versionIds.isEmpty() && legacyRepId != null) {
            versionIds = queryContentVersionIdsForEntity(legacyRepId);
        }
        return versionIds;
    }

    private static List<String> queryContentVersionIdsForEntity(Id linkedEntityId) {
        List<String> versionIds = new List<String>();
        if (linkedEntityId == null) {
            return versionIds;
        }
        for (ContentDocumentLink link : [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedEntityId
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 5
        ]) {
            if (link.ContentDocument?.LatestPublishedVersionId != null) {
                versionIds.add(link.ContentDocument.LatestPublishedVersionId);
            }
        }
        return versionIds;
    }

    private static List<Map<String, String>> buildVerificationDocs(
        Account acct, List<String> versionIds
    ) {
        if (String.isNotBlank(acct.Verification_Document_URL__c)) {
            String docUrl = acct.Verification_Document_URL__c;
            return new List<Map<String, String>>{
                new Map<String, String>{
                    'label' => 'Verification document',
                    'url' => docUrl,
                    'fileExtension' => docUrl.toLowerCase().contains('original_pdf') ? 'pdf' : null
                }
            };
        }
        return buildVerificationDocLinks(versionIds);
    }

    private static List<Map<String, String>> buildVerificationDocLinks(List<String> versionIds) {
        List<Map<String, String>> docs = new List<Map<String, String>>();
        if (versionIds == null || versionIds.isEmpty()) {
            return docs;
        }
        Set<Id> versionIdSet = new Set<Id>();
        for (String versionId : versionIds) {
            if (String.isNotBlank(versionId)) {
                versionIdSet.add((Id) versionId);
            }
        }
        if (versionIdSet.isEmpty()) {
            return docs;
        }

        Map<Id, ContentDistribution> distByVersionId = new Map<Id, ContentDistribution>();
        for (ContentDistribution cd : [
            SELECT Id, ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId IN :versionIdSet
        ]) {
            distByVersionId.put(cd.ContentVersionId, cd);
        }

        for (ContentVersion cv : [
            SELECT Id, Title, FileExtension, ContentBodyId, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIdSet
            ORDER BY CreatedDate DESC
        ]) {
            ContentDistribution cd = distByVersionId.get(cv.Id);
            if (cd == null && !Test.isRunningTest()) {
                cd = findContentDistribution(cv);
                if (cd == null) {
                    cd = ensureContentDistribution(cv);
                }
                if (cd != null) {
                    distByVersionId.put(cv.Id, cd);
                }
            }
            if (cd == null) {
                continue;
            }

            String label = cv.Title;
            if (String.isNotBlank(cv.FileExtension) && !label.endsWithIgnoreCase('.' + cv.FileExtension)) {
                label += '.' + cv.FileExtension;
            }
            String viewUrl = resolveVerificationDocUrl(cv, cd);
            if (String.isBlank(viewUrl)) {
                continue;
            }
            docs.add(new Map<String, String>{
                'label' => label,
                'url' => viewUrl,
                'fileExtension' => cv.FileExtension
            });
        }
        return docs;
    }

    private static ContentDistribution findContentDistribution(ContentVersion cv) {
        List<ContentDistribution> byVersion = [
            SELECT Id, ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!byVersion.isEmpty()) {
            return byVersion[0];
        }

        Set<Id> siblingVersionIds = new Map<Id, ContentVersion>([
            SELECT Id FROM ContentVersion WHERE ContentDocumentId = :cv.ContentDocumentId
        ]).keySet();
        if (siblingVersionIds.isEmpty()) {
            return null;
        }

        List<ContentDistribution> byDocument = [
            SELECT Id, ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId IN :siblingVersionIds
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return byDocument.isEmpty() ? null : byDocument[0];
    }

    private static String resolveVerificationDocUrl(ContentVersion cv, ContentDistribution cd) {
        if (cd == null || String.isBlank(cd.DistributionPublicUrl)) {
            return null;
        }
        try {
            return buildFileDownloadUrl(cv, cd);
        } catch (Exception e) {
            return cd.DistributionPublicUrl;
        }
    }

    private static ContentDistribution ensureContentDistribution(ContentVersion cv) {
        ContentDistribution cd = new ContentDistribution(
            Name = cv.Title,
            ContentVersionId = cv.Id,
            PreferencesAllowOriginalDownload = true,
            PreferencesLinkLatestVersion = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesAllowViewInBrowser = true
        );
        insert cd;
        return [
            SELECT Id, ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :cd.Id
            LIMIT 1
        ];
    }

    private static String buildFileDownloadUrl(ContentVersion cv, ContentDistribution cd) {
        String ext = String.isNotBlank(cv.FileExtension) ? cv.FileExtension : 'Jpg';
        String versionId15 = String.valueOf(cv.Id).substring(0, 15);
        String contentBodyId15 = cv.ContentBodyId != null
            ? String.valueOf(cv.ContentBodyId).substring(0, 15)
            : versionId15;
        String baseUrl = cd.DistributionPublicUrl.substringBefore('/sfc');
        baseUrl = baseUrl.replace('my.salesforce', 'file.force');
        String ending = cd.DistributionPublicUrl.substringAfterLast('/a/');

        return baseUrl
            + FimbySettings.getUrl('File_Download') + '?rendition=ORIGINAL_' + ext
            + '&versionId=' + versionId15
            + '&operationContext=DELIVERY&contentId=' + contentBodyId15
            + '&page=0&d=/a/' + ending
            + '&oid=';
    }

    public static Map<String, Object> getSupportConcernData(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id, Summary__c, Priority__c, Status__c,
                   Subject_Contact__c, Subject_Contact__r.Name, Subject_Contact__r.Image_URL__c,
                   Secondary_Contact__c, Secondary_Contact__r.Name, Secondary_Contact__r.Image_URL__c,
                   Related_Record_Id__c, Related_Record_Type__c,
                   Report_Count__c, CreatedDate
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];

        List<Moderator_Task_Evidence__c> evidence = [
            SELECT Id, Source_Type__c, Reporter__c, Reporter__r.Name,
                   Reported_Date__c, Reason_Code__c, Details__c
            FROM Moderator_Task_Evidence__c
            WHERE Moderator_Task__c = :taskId
            ORDER BY Reported_Date__c DESC
        ];

        return new Map<String, Object>{
            'task' => task,
            'helperName' => task.Secondary_Contact__r != null ? task.Secondary_Contact__r.Name : '',
            'helperPhotoUrl' => task.Secondary_Contact__r != null ? task.Secondary_Contact__r.Image_URL__c : null,
            'helperContactId' => task.Secondary_Contact__c,
            'subjectName' => task.Subject_Contact__r != null ? task.Subject_Contact__r.Name : '',
            'subjectPhotoUrl' => task.Subject_Contact__r != null ? task.Subject_Contact__r.Image_URL__c : null,
            'subjectContactId' => task.Subject_Contact__c,
            'activeRelationship' => String.isNotBlank(task.Related_Record_Id__c)
                ? 'Active support relationship under review'
                : '',
            'concernSummary' => task.Summary__c,
            'helperRecentActivity' => buildConcernActivity(evidence),
            'evidenceItems' => buildEvidenceTimelineItems(evidence)
        };
    }

    public static Map<String, Object> getEscalationDetail(Id taskId) {
        Moderator_Task__c task = [
            SELECT Id, Name, Category__c, Priority__c, Status__c, Summary__c,
                   Escalated_To__c, Escalated_To__r.Name, Escalated_Date__c,
                   Escalation_Reason__c, Notes__c,
                   Resolved_Date__c, Resolved_By__c, Resolved_By__r.Name,
                   Subject_Contact__c, Subject_Contact__r.Name, CreatedDate
            FROM Moderator_Task__c WHERE Id = :taskId LIMIT 1
        ];
        return new Map<String, Object>{
            'task' => task,
            'originalCategory' => task.Category__c != null ? task.Category__c.replace('_', ' ') : '',
            'summary' => task.Summary__c,
            'escalationReason' => task.Escalation_Reason__c,
            'escalatedToName' => task.Escalated_To__r != null ? task.Escalated_To__r.Name : '',
            'escalatedToContactId' => task.Escalated_To__c,
            'escalatedDate' => String.valueOf(task.Escalated_Date__c),
            'isResolved' => task.Resolved_Date__c != null,
            'resolutionDate' => String.valueOf(task.Resolved_Date__c),
            'resolutionNotes' => task.Notes__c
        };
    }

    public static Map<String, Object> getWelcomeReviewData(Id contactId) {
        Contact contact = [
            SELECT Id, FirstName, Name, Pronouns__c, Image_URL__c, CreatedDate,
                   Why_do_you_want_to_join_FIMBY__c, Onboarding_Profile_Completed__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        String firstName = String.isNotBlank(contact.FirstName) ? contact.FirstName : contact.Name;
        String welcomeTemplate = 'Hi ' + firstName
            + ', welcome to FIMBY. I\'m one of the neighbourhood moderators and wanted to say hello. '
            + 'If you need a hand finding your way around or have any questions, you can message me here.';
        return new Map<String, Object>{
            'contactId' => contact.Id,
            'contactName' => contact.Name,
            'pronouns' => contact.Pronouns__c,
            'contactPhotoUrl' => contact.Image_URL__c,
            'signupDate' => String.valueOf(contact.CreatedDate),
            'joinReason' => contact.Why_do_you_want_to_join_FIMBY__c,
            'onboardingComplete' => contact.Onboarding_Profile_Completed__c,
            'welcomeTemplate' => welcomeTemplate
        };
    }

    private static List<Map<String, Object>> buildConcernActivity(List<Moderator_Task_Evidence__c> evidence) {
        List<Map<String, Object>> activity = new List<Map<String, Object>>();
        for (Moderator_Task_Evidence__c item : evidence) {
            activity.add(new Map<String, Object>{
                'id' => item.Id,
                'type' => item.Source_Type__c,
                'summary' => String.isNotBlank(item.Details__c) ? item.Details__c : item.Reason_Code__c,
                'date' => String.valueOf(item.Reported_Date__c)
            });
        }
        return activity;
    }

    private static List<Map<String, Object>> buildEvidenceTimelineItems(List<Moderator_Task_Evidence__c> evidence) {
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Moderator_Task_Evidence__c item : evidence) {
            Map<String, Object> row = new Map<String, Object>{
                'Id' => item.Id,
                'Source_Type__c' => item.Source_Type__c,
                'Reported_Date__c' => String.valueOf(item.Reported_Date__c),
                'Reason_Code__c' => item.Reason_Code__c,
                'Details__c' => item.Details__c
            };
            if (item.Reporter__r != null) {
                row.put('Reporter__r', new Map<String, Object>{ 'Name' => item.Reporter__r.Name });
            }
            items.add(row);
        }
        return items;
    }

    public static Map<String, Object> getReporterFilingStats(Id reporterContactId, Id neighbourhoodId, Id excludeTaskId) {
        Integer reportsLast90 = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Secondary_Contact__c = :reporterContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND CreatedDate = LAST_N_DAYS:90
              AND Id != :excludeTaskId
        ];
        Integer reportsTotal = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Secondary_Contact__c = :reporterContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND Id != :excludeTaskId
        ];
        return new Map<String, Object>{
            'reportsLast90Days' => reportsLast90,
            'reportsTotal' => reportsTotal
        };
    }

    public static Map<String, Object> getSubjectHistory(Id subjectContactId, Id neighbourhoodId, Id excludeTaskId) {
        Integer totalReports = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Subject_Contact__c = :subjectContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND Id != :excludeTaskId
        ];
        Integer checkIns = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Subject_Contact__c = :subjectContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND Enforcement_Level__c = 'Check_In'
              AND Id != :excludeTaskId
        ];
        Integer concerns = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Subject_Contact__c = :subjectContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND Enforcement_Level__c = 'Recorded_Concern'
              AND Id != :excludeTaskId
        ];
        Integer blockIncidents = [
            SELECT COUNT() FROM Blocked_Contact__c
            WHERE Blocker__c = :subjectContactId OR Blocked__c = :subjectContactId
        ];

        List<Moderator_Task__c> recentCases = [
            SELECT Id, Category__c, Summary__c, Status__c,
                   Enforcement_Level__c, CreatedDate, Resolved_Date__c
            FROM Moderator_Task__c
            WHERE Subject_Contact__c = :subjectContactId
              AND Neighbourhood__c = :neighbourhoodId
              AND Id != :excludeTaskId
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        Contact subject = [
            SELECT Id, Name, Image_URL__c, Pronouns__c, CreatedDate, AccountId,
                   Account.Name
            FROM Contact WHERE Id = :subjectContactId LIMIT 1
        ];

        return new Map<String, Object>{
            'subject' => subject,
            'totalReports' => totalReports,
            'checkIns' => checkIns,
            'recordedConcerns' => concerns,
            'blockIncidents' => blockIncidents,
            'recentCases' => recentCases
        };
    }

    public static List<Library_Item__c> getOverdueLoans(Id neighbourhoodId) {
        return [
            SELECT Id, Name, Owner_Contact__c, Owner_Contact__r.Name,
                   (SELECT Id, Loaned_To__c, Loaned_To__r.Name, Loan_Due_Date__c
                    FROM Loaned_Items__r
                    WHERE Status__c = 'Active' AND Loan_Due_Date__c < TODAY)
            FROM Library_Item__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Id IN (SELECT Library_Item__c FROM Loaned_Item__c
                         WHERE Status__c = 'Active' AND Loan_Due_Date__c < TODAY)
            LIMIT 20
        ];
    }

    public static List<Needs_Offers__c> getStaleExpiredPosts(Id neighbourhoodId) {
        return [
            SELECT Id, Name, Type__c, Posted_By__c, Posted_By__r.Name,
                   Status__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c IN ('Expired', 'Completed')
              AND CreatedDate = LAST_N_DAYS:14
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }

    public static List<Contact> getInactiveMembers(Id neighbourhoodId) {
        Datetime cutoff = Datetime.now().addDays(-60);
        Set<Id> activeContactIds = new Set<Id>();

        for (AggregateResult ar : [
            SELECT Contact__c cId FROM Needs_Offers__c
            WHERE Neighbourhood__c = :neighbourhoodId AND CreatedDate >= :cutoff
              AND Contact__c != null
            GROUP BY Contact__c
        ]) {
            activeContactIds.add((Id) ar.get('cId'));
        }

        return [
            SELECT Id, Name, Image_URL__c, CreatedDate, LastActivityDate
            FROM Contact
            WHERE AccountId = :neighbourhoodId
              AND Id NOT IN :activeContactIds
              AND Status__c = 'Active User'
            ORDER BY LastActivityDate ASC NULLS FIRST
            LIMIT 20
        ];
    }

    public static Map<String, Object> getModeratorHeaderData(Id contactId) {
        List<Moderator_Assignment__c> assignments = [
            SELECT Id, Neighbourhood__c, Neighbourhood__r.Name
            FROM Moderator_Assignment__c
            WHERE Contact__c = :contactId AND Status__c = 'Active'
        ];

        if (assignments.isEmpty()) {
            return new Map<String, Object>{
                'isModerator' => false,
                'taskCount' => 0,
                'neighbourhoodNames' => new List<String>()
            };
        }

        Set<Id> nhIds = new Set<Id>();
        List<String> nhNames = new List<String>();
        for (Moderator_Assignment__c ma : assignments) {
            nhIds.add(ma.Neighbourhood__c);
            nhNames.add(ma.Neighbourhood__r.Name);
        }

        Integer taskCount = [
            SELECT COUNT() FROM Moderator_Task__c
            WHERE Neighbourhood__c IN :nhIds
              AND Status__c IN ('New', 'In_Progress', 'Awaiting_Info')
        ];

        return new Map<String, Object>{
            'isModerator' => true,
            'taskCount' => taskCount,
            'neighbourhoodNames' => nhNames
        };
    }

    public static List<Moderator_Assignment__c> getModeratorAssignments(Id contactId) {
        return [
            SELECT Id, Neighbourhood__c, Neighbourhood__r.Name, Role__c, Status__c
            FROM Moderator_Assignment__c
            WHERE Contact__c = :contactId AND Status__c = 'Active'
        ];
    }

    public static Boolean isModeratorForNeighbourhood(Id contactId, Id neighbourhoodId) {
        return [
            SELECT COUNT() FROM Moderator_Assignment__c
            WHERE Contact__c = :contactId AND Neighbourhood__c = :neighbourhoodId AND Status__c = 'Active'
        ] > 0;
    }

    private static Integer sumCounts(Map<String, Integer> counts) {
        Integer total = 0;
        for (Integer c : counts.values()) { total += c; }
        return total;
    }
}
