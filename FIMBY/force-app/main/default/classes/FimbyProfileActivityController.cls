/**
 * @description Active content feed for neighbour and org profile pages.
 */
public with sharing class FimbyProfileActivityController {

    private static final Integer QUERY_LIMIT = 150;
    private static final Set<String> ACTIVE_AO_STATUSES = new Set<String>{
        'Posted', 'Reply Received', 'Reply Accepted', 'Available'
    };
    private static final Set<String> ACTIVE_LIBRARY_STATUSES = new Set<String>{
        FimbyConstants.LIBRARY_AVAILABLE,
        FimbyConstants.LIBRARY_ON_HOLD,
        FimbyConstants.LIBRARY_LENT_OUT
    };

    /**
     * @description Returns active, moderation-visible content owned by profileContactId.
     * @param profileContactId Post Owner contact (neighbour or org organization contact)
     * @param offset Pagination offset
     * @param pageSize Items per page
     */
    @AuraEnabled(cacheable=false)
    public static ProfileActivityResult getProfileActivity(
        Id profileContactId,
        Integer offset,
        Integer pageSize
    ) {
        try {
            ProfileActivityResult empty = new ProfileActivityResult(
                new List<FimbyFeedItem>(), false, 0
            );

            if (profileContactId == null) {
                return empty;
            }

            Id viewerContactId = FimbyIdentityRepository.getActingAsContactId();
            if (viewerContactId == null || !FimbyContactVisibility.canView(viewerContactId, profileContactId)) {
                return empty;
            }

            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
            Integer limitVal = (pageSize != null && pageSize > 0)
                ? Math.min(pageSize, 50)
                : FimbySettings.searchPageSize();

            List<FimbyFeedItem> allItems = new List<FimbyFeedItem>();
            Date today = Date.today();

            allItems.addAll(queryStories(profileContactId));
            allItems.addAll(queryNeedsOffers(profileContactId, today));
            allItems.addAll(queryLibraryItems(profileContactId));

            allItems.sort();
            allItems = filterBlockedAuthors(allItems, viewerContactId);

            Integer totalCount = allItems.size();
            Integer startIndex = Math.min(offsetVal, totalCount);
            Integer endIndex = Math.min(offsetVal + limitVal, totalCount);

            List<FimbyFeedItem> pagedItems = new List<FimbyFeedItem>();
            for (Integer i = startIndex; i < endIndex; i++) {
                pagedItems.add(allItems[i]);
            }

            return new ProfileActivityResult(pagedItems, endIndex < totalCount, totalCount);
        } catch (Exception e) {
            FimbyLogger.error('FimbyProfileActivityController', 'getProfileActivity', e);
            throw new AuraHandledException('Failed to load profile activity: ' + e.getMessage());
        }
    }

    private static List<FimbyFeedItem> queryStories(Id profileContactId) {
        List<Story__c> stories = [
            SELECT Id, Name, Message__c, Type__c, CreatedDate,
                   Posted_By__c, Contact__c, Comment_Count__c,
                   Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c,
                   Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c,
                   Posted_By__r.Organization_Account__r.Logo_URL__c,
                   Image_URL__c, Image_Ratio__c
            FROM Story__c
            WHERE Posted_By__c = :profileContactId
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :QUERY_LIMIT
        ];

        List<FimbyFeedItem> items = new List<FimbyFeedItem>();
        for (Story__c story : stories) {
            items.add(new FimbyFeedItem(story));
        }
        return items;
    }

    private static List<FimbyFeedItem> queryNeedsOffers(Id profileContactId, Date today) {
        Set<Id> liveRecurringOccurrenceIds = new Set<Id>();
        for (Needs_Offers__c seriesParent : [
            SELECT Id, Current_Occurrence__c
            FROM Needs_Offers__c
            WHERE Recurrence_Frequency__c != null
              AND Series_Parent__c = null
              AND Contact__c = :profileContactId
            WITH SECURITY_ENFORCED
            LIMIT :QUERY_LIMIT
        ]) {
            liveRecurringOccurrenceIds.add(
                seriesParent.Current_Occurrence__c != null
                    ? seriesParent.Current_Occurrence__c
                    : seriesParent.Id
            );
        }

        List<Needs_Offers__c> aoItems = [
            SELECT Id, Name, Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c,
                   Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c,
                   Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c,
                   Posted_By__r.Organization_Account__r.Logo_URL__c,
                   Contact__r.Full_Name__c, Contact__r.Image_URL__c,
                   Contact__r.Is_Organization_Contact__c, Contact__r.Organization_Account__c,
                   Contact__r.Organization_Account__r.Logo_URL__c,
                   Image_1_URL__c, Image_1_Ratio__c,
                   Image_2_URL__c, Image_2_Ratio__c,
                   Image_3_URL__c, Image_3_Ratio__c,
                   Image_4_URL__c, Image_4_Ratio__c,
                   Total_Accepted__c, Total_Reserved__c, Total_Quantity__c, Owner_Shares__c,
                   Total_Available__c, Active_Reserver_Ids__c, Is_Urgent__c,
                   Event_Details__c, Location__c, Event_Type__c, Event_Link__c,
                   Start_Date__c, End_Date__c,
                   Recurrence_Frequency__c, Series_Parent__c, Current_Occurrence__c,
                   RecordType.Name, Category__c, Contact__c, Posted_By__c
            FROM Needs_Offers__c
            WHERE Contact__c = :profileContactId
              AND Status__c IN :ACTIVE_AO_STATUSES
              AND (Total_Available__c > 0 OR Total_Available__c = null)
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
              AND ((Recurrence_Frequency__c = null AND Series_Parent__c = null)
                   OR Id IN :liveRecurringOccurrenceIds)
              AND (Type__c != 'Event'
                   OR End_Date__c >= :today
                   OR (End_Date__c = null AND Start_Date__c >= :today))
            WITH SECURITY_ENFORCED
            ORDER BY Posted_Date__c DESC
            LIMIT :QUERY_LIMIT
        ];

        List<FimbyFeedItem> items = new List<FimbyFeedItem>();
        for (Needs_Offers__c item : aoItems) {
            items.add(new FimbyFeedItem(item));
        }
        return items;
    }

    private static List<FimbyFeedItem> queryLibraryItems(Id profileContactId) {
        List<Library_Item__c> libItems = [
            SELECT Id, Name, Description__c, Category__c, Status__c, CreatedDate,
                   Owner_Contact__c, Listed_By__c,
                   Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c,
                   Owner_Contact__r.Is_Organization_Contact__c, Owner_Contact__r.Organization_Account__c,
                   Owner_Contact__r.Organization_Account__r.Logo_URL__c,
                   Image_URL__c, Image_Ratio__c
            FROM Library_Item__c
            WHERE Owner_Contact__c = :profileContactId
              AND Status__c IN :ACTIVE_LIBRARY_STATUSES
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :QUERY_LIMIT
        ];

        List<FimbyFeedItem> items = new List<FimbyFeedItem>();
        for (Library_Item__c item : libItems) {
            items.add(new FimbyFeedItem(item));
        }
        return items;
    }

    private static List<FimbyFeedItem> filterBlockedAuthors(
        List<FimbyFeedItem> allItems,
        Id viewerContactId
    ) {
        Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId);
        return FimbyBlockingHelper.filterVisibleFeedItems(allItems, blockedContactIds);
    }

    public class ProfileActivityResult {
        @AuraEnabled public List<FimbyFeedItem> items { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }

        public ProfileActivityResult(List<FimbyFeedItem> items, Boolean hasMore, Integer totalCount) {
            this.items = items;
            this.hasMore = hasMore;
            this.totalCount = totalCount;
        }
    }
}
