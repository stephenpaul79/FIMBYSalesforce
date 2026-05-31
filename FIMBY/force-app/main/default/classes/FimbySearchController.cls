/**
 * @description Full-text search across Story__c, Needs_Offers__c, Library_Item__c, and Contact using SOSL. Results scoped to neighbourhood; people results include hasSharedContact for privacy gating.
 */
public with sharing class FimbySearchController {

    private static final Integer MAX_PAGE_SIZE = 50;

    /**
     * @description LWC-callable method that performs full-text search across stories, ask/offer, library, and people.
     * @param searchTerm Search string (min 2 chars)
     * @param filterType all, stories, askOffer, library, or people
     * @param sortBy relevance, newest, or oldest
     * @param pageSize Items per page (capped at 50)
     * @param offset Pagination offset
     * @return SearchResult with items, totalCount, hasMore, countsByType
     */
    @AuraEnabled
    public static SearchResult search(
        String searchTerm,
        String filterType,
        String sortBy,
        Integer pageSize,
        Integer offset
    ) {
        try {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return emptyResult();
        }

        Integer limitVal = (pageSize != null && pageSize > 0) ? Math.min(pageSize, MAX_PAGE_SIZE) : FimbySettings.searchPageSize();
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
        String filter = String.isNotBlank(filterType) ? filterType : 'all';
        String sortOrder = String.isNotBlank(sortBy) ? sortBy : 'relevance';

        User currentUser = FimbyIdentityRepository.getCurrentUser();

        String neighbourhoodAccountId = null;
        String currentContactId = null;
        if (currentUser.ContactId != null) {
            currentContactId = currentUser.ContactId;
            neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
        }

        // Build the set of contact IDs with shared contact info for privacy gating
        // Uses inner class without sharing to ensure visibility of Shared_Contact_Info__c
        Set<Id> sharedContactIds = new SharedContactLookup().getSharedContactIds(currentContactId);

        String sanitized = String.escapeSingleQuotes(searchTerm.trim());

        // Build RETURNING clauses based on filter
        String returningClause = buildReturningClause(filter, neighbourhoodAccountId);

        String soslQuery = 'FIND \'' + sanitized + '*\' IN ALL FIELDS RETURNING ' + returningClause;

        List<List<SObject>> soslResults = Search.query(soslQuery);

        // Parse results into unified items and count by type
        List<SearchResultItem> allItems = new List<SearchResultItem>();
        Map<String, Integer> countsByType = new Map<String, Integer>{
            'stories' => 0,
            'askOffer' => 0,
            'library' => 0,
            'people' => 0
        };

        Integer resultSetIndex = 0;

        if (filter == 'all' || filter == 'stories') {
            List<Story__c> stories = (List<Story__c>) soslResults[resultSetIndex];
            countsByType.put('stories', stories.size());
            for (Story__c s : stories) {
                allItems.add(buildStoryItem(s));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'askOffer') {
            List<Needs_Offers__c> needsOffers = (List<Needs_Offers__c>) soslResults[resultSetIndex];
            countsByType.put('askOffer', needsOffers.size());
            for (Needs_Offers__c no : needsOffers) {
                allItems.add(buildAskOfferItem(no));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'library') {
            List<Library_Item__c> libraryItems = (List<Library_Item__c>) soslResults[resultSetIndex];
            countsByType.put('library', libraryItems.size());
            for (Library_Item__c li : libraryItems) {
                allItems.add(buildLibraryItem(li));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'people') {
            List<Contact> contacts = (List<Contact>) soslResults[resultSetIndex];
            countsByType.put('people', contacts.size());
            for (Contact c : contacts) {
                SearchResultItem item = buildPeopleItem(c);
                item.hasSharedContact = sharedContactIds.contains(c.Id);
                allItems.add(item);
            }
        }

        // Sort
        if (sortOrder == 'newest') {
            allItems.sort();
        } else if (sortOrder == 'oldest') {
            allItems.sort();
            List<SearchResultItem> reversed = new List<SearchResultItem>();
            for (Integer i = allItems.size() - 1; i >= 0; i--) {
                reversed.add(allItems.get(i));
            }
            allItems = reversed;
        }
        // 'relevance' keeps SOSL default ordering

        // Paginate
        Integer totalCount = allItems.size();
        Integer startIdx = Math.min(offsetVal, totalCount);
        Integer endIdx = Math.min(offsetVal + limitVal, totalCount);

        List<SearchResultItem> pagedItems = new List<SearchResultItem>();
        for (Integer i = startIdx; i < endIdx; i++) {
            pagedItems.add(allItems.get(i));
        }

        SearchResult result = new SearchResult();
        result.items = pagedItems;
        result.totalCount = totalCount;
        result.hasMore = endIdx < totalCount;
        result.countsByType = countsByType;

        return result;
        } catch (Exception e) {
            FimbyLogger.error('FimbySearchController', 'search', e);
            throw new AuraHandledException('Search failed: ' + e.getMessage());
        }
    }

    // ============================================
    // RETURNING clause builder
    // ============================================

    private static String buildReturningClause(String filter, String neighbourhoodAccountId) {
        List<String> clauses = new List<String>();

        String adjList = '';
        String sharedList = '';
        if (String.isNotBlank(neighbourhoodAccountId)) {
            adjList = buildAdjacentIdList();
            sharedList = buildSharedContactIdList();
        }

        if (filter == 'all' || filter == 'stories') {
            String storyClause = 'Story__c(Id, Name, Message__c, Type__c, Image_URL__c, Image_Ratio__c, ' +
                'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                storyClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Posted_By__c');
            }
            storyClause += ' ORDER BY CreatedDate DESC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(storyClause);
        }

        if (filter == 'all' || filter == 'askOffer') {
            String aoClause = 'Needs_Offers__c(Id, Name, Details__c, Type__c, Status__c, RecordType.Name, ' +
                'Image_1_URL__c, Image_1_Ratio__c, Category__c, ' +
                'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                aoClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Posted_By__c');
            }
            aoClause += ' ORDER BY CreatedDate DESC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(aoClause);
        }

        if (filter == 'all' || filter == 'library') {
            String libClause = 'Library_Item__c(Id, Name, Description__c, Category__c, Status__c, ' +
                'Image_URL__c, Image_Ratio__c, ' +
                'Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                libClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Owner_Contact__c');
            }
            libClause += ' ORDER BY Name ASC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(libClause);
        }

        if (filter == 'all' || filter == 'people') {
            String contactClause = 'Contact(Id, Name, Full_Name__c, Image_URL__c, ' +
                'About_Enjoys_Doing__c, Account.Name';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                contactClause += ' WHERE ' + buildContactFilter(neighbourhoodAccountId, adjList, sharedList);
            } else {
                contactClause += ' WHERE Is_Organization_Contact__c = false';
            }
            contactClause += ' ORDER BY Name ASC LIMIT ' + FimbySettings.searchContactsLimit() + ')';
            clauses.add(contactClause);
        }

        return String.join(clauses, ', ');
    }

    // ============================================
    // Adjacency helpers
    // ============================================

    private static String buildAdjacentIdList() {
        Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
        if (adjacentIds.isEmpty()) return '';
        List<String> escaped = new List<String>();
        for (Id adjId : adjacentIds) {
            escaped.add('\'' + String.escapeSingleQuotes(String.valueOf(adjId)) + '\'');
        }
        return String.join(escaped, ',');
    }

    private static String buildSharedContactIdList() {
        Set<Id> sharedIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();
        if (sharedIds.isEmpty()) return '';
        List<String> escaped = new List<String>();
        for (Id scId : sharedIds) {
            escaped.add('\'' + String.escapeSingleQuotes(String.valueOf(scId)) + '\'');
        }
        return String.join(escaped, ',');
    }

    private static String buildContentFilter(String neighbourhoodId, String adjList, String sharedList, String posterField) {
        String nId = String.escapeSingleQuotes(neighbourhoodId);
        String f = '(Neighbourhood__c = \'' + nId + '\'';
        if (String.isNotBlank(adjList)) {
            f += ' OR (Neighbourhood__c IN (' + adjList + ') AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))';
            if (String.isNotBlank(sharedList)) {
                f += ' OR (Neighbourhood__c IN (' + adjList + ') AND ' + posterField + ' IN (' + sharedList + '))';
            }
        }
        f += ') AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';
        return f;
    }

    private static String buildContactFilter(String neighbourhoodId, String adjList, String sharedList) {
        String nId = String.escapeSingleQuotes(neighbourhoodId);
        String f = '(AccountId = \'' + nId + '\'';
        if (String.isNotBlank(adjList) && String.isNotBlank(sharedList)) {
            f += ' OR (AccountId IN (' + adjList + ') AND Id IN (' + sharedList + '))';
        }
        f += ') AND Is_Organization_Contact__c = false';
        return f;
    }

    // ============================================
    // Item builders
    // ============================================

    private static SearchResultItem buildStoryItem(Story__c s) {
        SearchResultItem item = new SearchResultItem();
        item.recordId = s.Id;
        item.resultType = 'story';
        item.name = s.Name;
        item.description = s.Message__c;
        item.subType = s.Type__c;
        item.imageUrl = s.Image_URL__c;
        item.imageRatio = s.Image_Ratio__c;
        item.postedByName = s.Posted_By__r?.Full_Name__c;
        item.postedByImageUrl = s.Posted_By__r?.Image_URL__c;
        item.createdDate = s.CreatedDate;
        item.status = null;
        item.hasSharedContact = null;
        return item;
    }

    private static SearchResultItem buildAskOfferItem(Needs_Offers__c no) {
        SearchResultItem item = new SearchResultItem();
        item.recordId = no.Id;
        item.resultType = 'askOffer';
        item.name = no.Name;
        item.description = no.Details__c;
        item.subType = no.RecordType?.Name;
        item.imageUrl = no.Image_1_URL__c;
        item.imageRatio = no.Image_1_Ratio__c;
        item.postedByName = no.Posted_By__r?.Full_Name__c;
        item.postedByImageUrl = no.Posted_By__r?.Image_URL__c;
        item.createdDate = no.CreatedDate;
        item.status = no.Status__c;
        item.hasSharedContact = null;
        return item;
    }

    private static SearchResultItem buildLibraryItem(Library_Item__c li) {
        SearchResultItem item = new SearchResultItem();
        item.recordId = li.Id;
        item.resultType = 'library';
        item.name = li.Name;
        item.description = li.Description__c;
        item.subType = li.Category__c;
        item.imageUrl = li.Image_URL__c;
        item.imageRatio = li.Image_Ratio__c;
        item.postedByName = li.Owner_Contact__r?.Full_Name__c;
        item.postedByImageUrl = li.Owner_Contact__r?.Image_URL__c;
        item.createdDate = li.CreatedDate;
        item.status = li.Status__c;
        item.hasSharedContact = null;
        return item;
    }

    private static SearchResultItem buildPeopleItem(Contact c) {
        SearchResultItem item = new SearchResultItem();
        item.recordId = c.Id;
        item.resultType = 'people';
        item.name = c.Full_Name__c != null ? c.Full_Name__c : c.Name;
        item.description = c.About_Enjoys_Doing__c;
        item.subType = c.Account?.Name;
        item.imageUrl = c.Image_URL__c;
        item.imageRatio = null;
        item.postedByName = null;
        item.postedByImageUrl = null;
        item.createdDate = null;
        item.status = null;
        item.hasSharedContact = false;
        return item;
    }

    private static SearchResult emptyResult() {
        SearchResult result = new SearchResult();
        result.items = new List<SearchResultItem>();
        result.totalCount = 0;
        result.hasMore = false;
        result.countsByType = new Map<String, Integer>{
            'stories' => 0,
            'askOffer' => 0,
            'library' => 0,
            'people' => 0
        };
        return result;
    }

    /**
     * @description Without sharing helper for community user visibility of Shared_Contact_Info__c.
     */
    private without sharing class SharedContactLookup {
        /**
         * @description Returns Contact Ids with whom the given contact has shared contact info (either direction).
         * @param contactId Contact Id to look up
         * @return Set of Contact Ids
         */
        public Set<Id> getSharedContactIds(String contactId) {
            Set<Id> ids = new Set<Id>();
            if (String.isBlank(contactId)) return ids;

            for (Shared_Contact_Info__c sci : [
                SELECT Contact__c
                FROM Shared_Contact_Info__c
                WHERE Shared_To__c = :contactId
                AND Contact__c != null
            ]) {
                ids.add(sci.Contact__c);
            }
            for (Shared_Contact_Info__c sci : [
                SELECT Shared_To__c
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :contactId
                AND Shared_To__c != null
            ]) {
                ids.add(sci.Shared_To__c);
            }
            return ids;
        }
    }

    // ============================================
    // Wrapper classes
    // ============================================

    public class SearchResult {
        @AuraEnabled public List<SearchResultItem> items { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Map<String, Integer> countsByType { get; set; }
    }

    public class SearchResultItem implements Comparable {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String resultType { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String subType { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public String imageRatio { get; set; }
        @AuraEnabled public String postedByName { get; set; }
        @AuraEnabled public String postedByImageUrl { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean hasSharedContact { get; set; }

        public Integer compareTo(Object compareTo) {
            SearchResultItem other = (SearchResultItem) compareTo;
            if (this.createdDate == null && other.createdDate == null) return 0;
            if (this.createdDate == null) return 1;
            if (other.createdDate == null) return -1;
            if (this.createdDate > other.createdDate) return -1;
            if (this.createdDate < other.createdDate) return 1;
            return 0;
        }
    }
}