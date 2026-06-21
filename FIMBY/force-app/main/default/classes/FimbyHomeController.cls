/**
 * @description Controller for the Home feed — stories, ask/offer items, library items, and unified feed. LWC-callable methods for FIMBY community.
 */
public with sharing class FimbyHomeController {

    /**
     * @description LWC-callable method that fetches stories for the home feed, scoped to user's neighbourhood.
     * @param offset Pagination offset
     * @param pageSize Number of items per page
     * @return StoriesResult with stories and hasMore flag
     */
    @AuraEnabled(cacheable=false)
    public static StoriesResult getStories(Integer offset, Integer pageSize) {
        return getStories(offset, pageSize, false);
    }

    /**
     * @description Fetches stories for the home feed; supports forceException for testing.
     * @param offset Pagination offset
     * @param pageSize Number of items per page
     * @param forceException When true, throws for test coverage
     * @return StoriesResult with stories and hasMore flag
     */
    public static StoriesResult getStories(Integer offset, Integer pageSize, Boolean forceException) {
        try {
            if (forceException) {
                throw new AuraHandledException('Test exception for getStories');
            }
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            Integer ttlDays = FimbySettings.storyFeedTtlDays();
            String ttlFilter = (ttlDays > 0) ? 'CreatedDate >= LAST_N_DAYS:' + ttlDays : '';

            String query = 'SELECT Id, Name, Message__c, Type__c, CreatedDate, ' +
                          'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, ' +
                          'Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c, ' +
                          'Posted_By__r.Organization_Account__r.Logo_URL__c, ' +
                          'Image_URL__c, Portal_Image__c, ' +
                          'Neighbourhood__c, Comment_Count__c ' +
                          'FROM Story__c ';

            List<String> wheres = new List<String>();
            if (String.isNotBlank(neighbourhoodAccountId)) {
                wheres.add('(Neighbourhood__c = :neighbourhoodAccountId' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Contact__c IN :sharedContactIds))');
            }
            if (String.isNotBlank(ttlFilter)) {
                wheres.add(ttlFilter);
            }
            wheres.add('(Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')');
            if (!wheres.isEmpty()) {
                query += 'WHERE ' + String.join(wheres, ' AND ') + ' ';
            }

            query += 'ORDER BY CreatedDate DESC ' +
                    'LIMIT :pageSize OFFSET :offset';

            List<Story__c> stories = Database.query(query);

            String countQuery = 'SELECT COUNT() FROM Story__c';
            if (!wheres.isEmpty()) {
                countQuery += ' WHERE ' + String.join(wheres, ' AND ');
            }
            Integer totalCount = Database.countQuery(countQuery);

            Boolean hasMore = (offset + pageSize) < totalCount;

            return new StoriesResult(stories, hasMore);

        } catch (Exception e) {
            FimbyLogger.error('FimbyHomeController', 'getStories', e);
            throw new AuraHandledException('Failed to load stories: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that fetches ask/offer items for the home feed.
     * @param offset Pagination offset
     * @param pageSize Number of items per page
     * @return List of Needs_Offers__c
     */
    @AuraEnabled(cacheable=false)
    public static List<Needs_Offers__c> getAskOfferItems(Integer offset, Integer pageSize) {
        return getAskOfferItems(offset, pageSize, false);
    }

    /**
     * @description Overload for getAskOfferItems with pageSize and forceException.
     * @param pageSize Number of items per page
     * @param forceException When true, throws for test coverage
     * @return List of Needs_Offers__c
     */
    public static List<Needs_Offers__c> getAskOfferItems(Integer pageSize, Boolean forceException) {
        return getAskOfferItems(0, pageSize, forceException);
    }

    /**
     * @description Fetches ask/offer items for the home feed; supports forceException for testing.
     * @param offset Pagination offset
     * @param pageSize Number of items per page
     * @param forceException When true, throws for test coverage
     * @return List of Needs_Offers__c
     */
    public static List<Needs_Offers__c> getAskOfferItems(Integer offset, Integer pageSize, Boolean forceException) {
        try {
            if (forceException) {
                throw new AuraHandledException('Test exception for getAskOfferItems');
            }
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String askOfferQuery = 'SELECT Id, Name, Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c, ' +
                          'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, ' +
                          'Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c, ' +
                          'Posted_By__r.Organization_Account__r.Logo_URL__c, ' +
                          'Contact__r.Full_Name__c, Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c, ' +
                          'Contact__r.Is_Organization_Contact__c, Contact__r.Organization_Account__c, ' +
                          'Contact__r.Organization_Account__r.Logo_URL__c, ' +
                          'Portal_Image__c, RecordType.Name, ' +
                          'Category__c, Neighbourhood__c ' +
                          'FROM Needs_Offers__c ' +
                          'WHERE Status__c IN (\'Posted\', \'Reply Received\', \'Reply Accepted\') ' +
                          'AND (Total_Available__c > 0 OR Total_Available__c = null) ' +
                          'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\') ';

            if (String.isNotBlank(neighbourhoodAccountId)) {
                askOfferQuery += 'AND (Neighbourhood__c = :neighbourhoodAccountId' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Posted_By__c IN :sharedContactIds)) ';
            }

            askOfferQuery += 'ORDER BY Posted_Date__c DESC LIMIT :pageSize OFFSET :offset';

            return Database.query(askOfferQuery);

        } catch (Exception e) {
            FimbyLogger.error('FimbyHomeController', 'getAskOfferItems', e);
            throw new AuraHandledException('Failed to load ask & offer items: ' + e.getMessage());
        }
    }

    /**
     * @description Fetches library items with a computed viewer contract per row.
     * Returns browseable statuses (Available, On Hold, Currently Lent Out) and
     * derives viewerState / CTA fields so the LWC does not parse raw ID strings.
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getLibraryItems(Integer offset, Integer pageSize) {
        return getLibraryItems(offset, pageSize, false);
    }

    public static List<Map<String, Object>> getLibraryItems(Integer pageSize, Boolean forceException) {
        return getLibraryItems(0, pageSize, forceException);
    }

    public static List<Map<String, Object>> getLibraryItems(Integer offset, Integer pageSize, Boolean forceException) {
        try {
            if (forceException) {
                throw new AuraHandledException('Test exception for getLibraryItems');
            }

            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String query = 'SELECT Id, Name, Description__c, Category__c, Status__c, CreatedDate, ' +
                          'Owner_Contact__c, Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c, ' +
                          'Owner_Contact__r.Is_Organization_Contact__c, Owner_Contact__r.Organization_Account__c, ' +
                          'Owner_Contact__r.Organization_Account__r.Logo_URL__c, ' +
                          'Image_URL__c, Portal_Image__c, ' +
                          'Expected_Return_Date__c, ' +
                          'Active_Requester_Ids__c, Active_Borrower_Id__c, Past_Borrower_Ids__c, ' +
                          'Neighbourhood__c ' +
                          'FROM Library_Item__c ' +
                          'WHERE Status__c IN (\'' +
                              String.escapeSingleQuotes(FimbyConstants.LIBRARY_AVAILABLE) + '\',\'' +
                              String.escapeSingleQuotes(FimbyConstants.LIBRARY_ON_HOLD) + '\',\'' +
                              String.escapeSingleQuotes(FimbyConstants.LIBRARY_LENT_OUT) + '\') ' +
                          'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\') ';

            if (String.isNotBlank(neighbourhoodAccountId)) {
                query += 'AND (Neighbourhood__c = :neighbourhoodAccountId' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                    ' OR (Neighbourhood__c IN :adjacentIds AND Owner_Contact__c IN :sharedContactIds)) ';
            }

            query += 'ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset';

            List<Library_Item__c> items = Database.query(query);
            List<Map<String, Object>> results = new List<Map<String, Object>>();

            for (Library_Item__c item : items) {
                results.add(buildLibraryBrowserRow(item, actingAsContactId));
            }
            return results;

        } catch (Exception e) {
            FimbyLogger.error('FimbyHomeController', 'getLibraryItems', e);
            throw new AuraHandledException('Failed to load library items: ' + e.getMessage());
        }
    }

    /**
     * Builds a single browser row with derived viewer state.
     * Canonical ownership rule: Owner_Contact__c == actingAsContactId
     */
    private static Map<String, Object> buildLibraryBrowserRow(Library_Item__c item, Id actingAsContactId) {
        String status = item.Status__c;
        Boolean isAvailable = status == FimbyConstants.LIBRARY_AVAILABLE;
        Boolean isOnHold = status == FimbyConstants.LIBRARY_ON_HOLD;
        Boolean isLentOut = status == FimbyConstants.LIBRARY_LENT_OUT;

        Boolean isOwner = actingAsContactId != null && item.Owner_Contact__c == actingAsContactId;
        Boolean isBorrower = containsContactId(item.Active_Borrower_Id__c, actingAsContactId);
        Boolean isWaitlisted = containsContactId(item.Active_Requester_Ids__c, actingAsContactId);
        Boolean isPastBorrower = containsContactId(item.Past_Borrower_Ids__c, actingAsContactId);

        // Viewer state priority cascade
        String viewerState;
        String primaryAction;
        String ctaLabel;
        String ctaPillClass;

        if (isOwner) {
            viewerState = FimbyConstants.LIB_VIEW_OWNER;
            primaryAction = 'view';
            ctaLabel = 'View Item';
            ctaPillClass = 'response-pill-responded';
        } else if (isBorrower) {
            viewerState = FimbyConstants.LIB_VIEW_BORROWED;
            primaryAction = 'view';
            ctaLabel = 'Borrowed';
            ctaPillClass = 'response-pill-reserved';
        } else if (isWaitlisted) {
            viewerState = FimbyConstants.LIB_VIEW_WAITLISTED;
            primaryAction = 'view';
            ctaLabel = 'On Waitlist';
            ctaPillClass = 'response-pill-responded';
        } else if (isPastBorrower && isAvailable) {
            viewerState = FimbyConstants.LIB_VIEW_PAST_BORROWER;
            primaryAction = 'borrow';
            ctaLabel = 'Borrow Again';
            ctaPillClass = '';
        } else if (isAvailable) {
            viewerState = FimbyConstants.LIB_VIEW_AVAILABLE;
            primaryAction = 'borrow';
            ctaLabel = 'Borrow';
            ctaPillClass = '';
        } else {
            viewerState = isOnHold ? FimbyConstants.LIB_VIEW_ON_HOLD : FimbyConstants.LIB_VIEW_ON_LOAN;
            primaryAction = 'joinWaitlist';
            ctaLabel = 'On Loan - Join Waitlist';
            ctaPillClass = '';
        }

        // Status pill
        String statusPillLabel;
        String statusPillClass;
        if (isAvailable) {
            statusPillLabel = 'Available';
            statusPillClass = 'alloc-pill-compact alloc-pill-available';
        } else if (isOnHold) {
            statusPillLabel = 'On Hold';
            statusPillClass = 'alloc-pill-compact alloc-pill-on-hold';
        } else {
            statusPillLabel = 'On Loan';
            statusPillClass = 'alloc-pill-compact alloc-pill-on-loan';
        }

        // Owner avatar
        String ownerName = item.Owner_Contact__r?.Full_Name__c;
        String ownerAvatar = item.Owner_Contact__r?.Display_Avatar_URL__c;
        Boolean isOrgContact = item.Owner_Contact__r?.Is_Organization_Contact__c == true;
        if (isOrgContact && item.Owner_Contact__r?.Organization_Account__r?.Logo_URL__c != null) {
            ownerAvatar = item.Owner_Contact__r.Organization_Account__r.Logo_URL__c;
        }

        Map<String, Object> row = new Map<String, Object>{
            'Id' => item.Id,
            'Name' => item.Name,
            'Description__c' => item.Description__c,
            'Category__c' => item.Category__c,
            'Status__c' => status,
            'CreatedDate' => item.CreatedDate,
            'Image_URL__c' => item.Image_URL__c,
            'ownerName' => ownerName,
            'ownerAvatar' => ownerAvatar,
            'ownerContactId' => item.Owner_Contact__c,
            'isOrgContact' => isOrgContact,
            'orgAccountId' => item.Owner_Contact__r?.Organization_Account__c,
            'expectedReturnDate' => item.Expected_Return_Date__c,
            'viewerState' => viewerState,
            'primaryAction' => primaryAction,
            'ctaLabel' => ctaLabel,
            'ctaPillClass' => ctaPillClass,
            'statusPillLabel' => statusPillLabel,
            'statusPillClass' => statusPillClass
        };
        return row;
    }

    private static Boolean containsContactId(String idString, Id contactId) {
        if (String.isBlank(idString) || contactId == null) return false;
        String contactId15 = String.valueOf(contactId).left(15);
        String contactId18 = String.valueOf(contactId);
        return idString.contains(contactId18) || idString.contains(contactId15);
    }

    /**
     * @description LWC-callable method that returns the Salesforce organization Id (for URLs, etc.).
     * @return Organization Id string
     */
    @AuraEnabled(cacheable=true)
    public static String getOrganizationId() {
        return UserInfo.getOrganizationId();
    }

    /**
     * Get unified feed with optional category/subType filtering.
     *
     * @param offset    Pagination offset
     * @param pageSize  Number of items per page
     * @param category  L1 filter: null/'all' = everything, 'story' = stories only, 'askOffer' = needs/offers only
     * @param subType   L2 filter: null/'All' = no sub-filter, or specific sub-type string
     *                  - For stories: 'Thank You', 'God Story', 'Prayer', 'Lament', 'Bio'
     *                  - For askOffer: 'Need', 'Offer', 'Event', 'Bulk Buy'
     */
    @AuraEnabled(cacheable=false)
    public static UnifiedFeedResult getUnifiedFeed(Integer offset, Integer pageSize, String category, String subType) {
        try {
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            Boolean isAllCategory = String.isBlank(category) || category == 'all';
            Boolean hasSubType = String.isNotBlank(subType) && subType != 'All';

            List<FimbyFeedItem> allItems = new List<FimbyFeedItem>();

            // Neighbourhood scope is capped at ~150 users; posts have a 1-3 week active life.
            // 150 per object is the practical ceiling and maps directly to the neighbourhood size limit.
            final Integer queryLimit = 150;

            /* -----------------------------------------------------------
             * Fetch Stories (when category is 'all' or 'story')
             * ----------------------------------------------------------- */
            if (isAllCategory || category == 'story') {
                Integer storyTtl = FimbySettings.storyFeedTtlDays();
                String storyQuery = 'SELECT Id, Name, Message__c, Type__c, CreatedDate, ' +
                                   'Posted_By__c, Contact__c, Comment_Count__c, ' +
                                   'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, ' +
                                   'Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c, ' +
                                   'Posted_By__r.Organization_Account__r.Logo_URL__c, ' +
                                   'Image_URL__c, Image_Ratio__c ' +
                                   'FROM Story__c ';

                List<String> storyWheres = new List<String>();
                if (String.isNotBlank(neighbourhoodAccountId)) {
                    storyWheres.add('(Neighbourhood__c = :neighbourhoodAccountId' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Contact__c IN :sharedContactIds))');
                }
                if (category == 'story' && hasSubType) {
                    storyWheres.add('Type__c = :subType');
                }
                if (storyTtl > 0) {
                    storyWheres.add('CreatedDate >= LAST_N_DAYS:' + storyTtl);
                }
                storyWheres.add('(Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')');
                if (!storyWheres.isEmpty()) {
                    storyQuery += 'WHERE ' + String.join(storyWheres, ' AND ') + ' ';
                }
                storyQuery += 'ORDER BY CreatedDate DESC LIMIT :queryLimit';

                List<Story__c> stories = Database.query(storyQuery);

                for (Story__c story : stories) {
                    FimbyFeedItem ufi = new FimbyFeedItem(story);
                    allItems.add(ufi);
                }
            }

            /* -----------------------------------------------------------
             * Fetch Needs/Offers (when category is 'all' or 'askOffer')
             * ----------------------------------------------------------- */
            if (isAllCategory || category == 'askOffer') {
                Set<Id> liveRecurringOccurrenceIds = new Set<Id>();
                String seriesParentQuery = 'SELECT Id, Current_Occurrence__c FROM Needs_Offers__c ' +
                    'WHERE Recurrence_Frequency__c != null AND Series_Parent__c = null';
                if (String.isNotBlank(neighbourhoodAccountId)) {
                    seriesParentQuery += ' AND Neighbourhood__c = :neighbourhoodAccountId';
                }
                for (Needs_Offers__c seriesParent : Database.query(seriesParentQuery)) {
                    liveRecurringOccurrenceIds.add(
                        seriesParent.Current_Occurrence__c != null
                            ? seriesParent.Current_Occurrence__c
                            : seriesParent.Id
                    );
                }

                String aoQuery = 'SELECT Id, Name, Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c, ' +
                                 'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, ' +
                                 'Posted_By__r.Is_Organization_Contact__c, Posted_By__r.Organization_Account__c, ' +
                                 'Posted_By__r.Organization_Account__r.Logo_URL__c, ' +
                                 'Contact__r.Full_Name__c, Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c, ' +
                                 'Contact__r.Is_Organization_Contact__c, Contact__r.Organization_Account__c, ' +
                                 'Contact__r.Organization_Account__r.Logo_URL__c, ' +
                                 'Image_1_URL__c, Image_1_Ratio__c, ' +
                                 'Image_2_URL__c, Image_2_Ratio__c, ' +
                                 'Image_3_URL__c, Image_3_Ratio__c, ' +
                                 'Image_4_URL__c, Image_4_Ratio__c, ' +
                                 'Total_Accepted__c, Total_Reserved__c, Total_Quantity__c, Owner_Shares__c, Total_Available__c, ' +
                                 'Active_Reserver_Ids__c, Is_Urgent__c, ' +
                                 'Event_Details__c, Location__c, Event_Type__c, Event_Link__c, ' +
                                 'Recurrence_Frequency__c, Series_Parent__c, Current_Occurrence__c, ' +
                                 'RecordType.Name, Category__c ' +
                                 'FROM Needs_Offers__c ' +
                                 'WHERE Status__c IN (\'Posted\', \'Reply Received\', \'Reply Accepted\', \'Available\') ' +
                                 'AND (Total_Available__c > 0 OR Total_Available__c = null) ' +
                                 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\') ' +
                                 'AND ((Recurrence_Frequency__c = null AND Series_Parent__c = null) OR Id IN :liveRecurringOccurrenceIds) ';

                if (String.isNotBlank(neighbourhoodAccountId)) {
                    aoQuery += 'AND (Neighbourhood__c = :neighbourhoodAccountId' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Posted_By__c IN :sharedContactIds)) ';
                }

                if (category == 'askOffer' && hasSubType) {
                    if (subType == FimbyConstants.RT_NEED || subType == FimbyConstants.RT_OFFER) {
                        aoQuery += 'AND RecordType.Name = :subType ';
                    } else if (subType == 'Services') {
                        aoQuery += 'AND Type__c LIKE \'%Services%\' ';
                    } else if (subType == 'Event') {
                        aoQuery += 'AND Type__c = \'Event\' ';
                    } else if (subType == 'Bulk Buy') {
                        aoQuery += 'AND RecordType.Name = :subType ';
                    }
                }

                aoQuery += 'ORDER BY Posted_Date__c DESC LIMIT :queryLimit';

                List<Needs_Offers__c> aoItems = Database.query(aoQuery);
                for (Needs_Offers__c item : aoItems) {
                    allItems.add(new FimbyFeedItem(item));
                }
            }

            /* -----------------------------------------------------------
             * Fetch Library Items — only in "all" view as "just listed"
             * announcements (items created in the last 7 days).
             * When a specific category filter is active, library items
             * are excluded entirely — the Library has its own nav.
             * ----------------------------------------------------------- */
            if (isAllCategory) {
                String libQuery = 'SELECT Id, Name, Description__c, Category__c, Status__c, CreatedDate, ' +
                                 'Owner_Contact__c, Listed_By__c, ' +
                                 'Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c, ' +
                                 'Owner_Contact__r.Is_Organization_Contact__c, Owner_Contact__r.Organization_Account__c, ' +
                                 'Owner_Contact__r.Organization_Account__r.Logo_URL__c, ' +
                                 'Image_URL__c, Image_Ratio__c ' +
                                 'FROM Library_Item__c ' +
                                 'WHERE Status__c = \'Available\' ' +
                                 'AND CreatedDate = LAST_N_DAYS:' + FimbySettings.libraryJustListedDays() + ' ' +
                                 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\') ';

                if (String.isNotBlank(neighbourhoodAccountId)) {
                    libQuery += 'AND (Neighbourhood__c = :neighbourhoodAccountId' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))' +
                        ' OR (Neighbourhood__c IN :adjacentIds AND Owner_Contact__c IN :sharedContactIds)) ';
                }
                libQuery += 'ORDER BY CreatedDate DESC LIMIT :queryLimit';

                List<Library_Item__c> libItems = Database.query(libQuery);
                for (Library_Item__c item : libItems) {
                    allItems.add(new FimbyFeedItem(item));
                }
            }

            allItems.sort();

            Id viewerContactId = FimbyIdentityRepository.getActingAsContactId();
            if (viewerContactId != null) {
                Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId);
                allItems = FimbyBlockingHelper.filterVisibleFeedItems(allItems, blockedContactIds);
            }

            // Apply pagination
            Integer totalCount = allItems.size();
            Integer startIndex = Math.min(offset, totalCount);
            Integer endIndex = Math.min(offset + pageSize, totalCount);

            List<FimbyFeedItem> pagedItems = new List<FimbyFeedItem>();
            for (Integer i = startIndex; i < endIndex; i++) {
                pagedItems.add(allItems.get(i));
            }

            Boolean hasMore = endIndex < totalCount;

            return new UnifiedFeedResult(pagedItems, hasMore, totalCount);

        } catch (Exception e) {
            FimbyLogger.error('FimbyHomeController', 'getUnifiedFeed', e);
            throw new AuraHandledException('Failed to load unified feed: ' + e.getMessage());
        }
    }

    /**
     * @description Backward-compatible overload; fetches unified feed without category/subType filter.
     * @param offset Pagination offset
     * @param pageSize Number of items per page
     * @return UnifiedFeedResult with items, hasMore, totalCount
     */
    public static UnifiedFeedResult getUnifiedFeed(Integer offset, Integer pageSize) {
        return getUnifiedFeed(offset, pageSize, null, null);
    }

    // Inner classes for return types
    public class StoriesResult {
        @AuraEnabled public List<Story__c> stories { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }

        public StoriesResult(List<Story__c> stories, Boolean hasMore) {
            this.stories = stories;
            this.hasMore = hasMore;
        }
    }

    public class AskOfferResult {
        @AuraEnabled public List<Needs_Offers__c> items { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }

        public AskOfferResult(List<Needs_Offers__c> items, Boolean hasMore) {
            this.items = items;
            this.hasMore = hasMore;
        }
    }

    public class LibraryResult {
        @AuraEnabled public List<Library_Item__c> items { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }

        public LibraryResult(List<Library_Item__c> items, Boolean hasMore) {
            this.items = items;
            this.hasMore = hasMore;
        }
    }

    public class UnifiedFeedResult {
        @AuraEnabled public List<FimbyFeedItem> items { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public String currentContactId { get; set; }
        @AuraEnabled public String actingAsContactId { get; set; }

        public UnifiedFeedResult(List<FimbyFeedItem> items, Boolean hasMore, Integer totalCount) {
            this.items = items;
            this.hasMore = hasMore;
            this.totalCount = totalCount;
            try {
                User u = FimbyIdentityRepository.getCurrentUser();
                this.currentContactId = u?.ContactId;
                this.actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            } catch (Exception e) {
                this.currentContactId = null;
                this.actingAsContactId = null;
            }
        }
    }
}