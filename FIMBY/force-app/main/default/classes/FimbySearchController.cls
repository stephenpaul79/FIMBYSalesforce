/**
 * @description Full-text search across Story__c, Needs_Offers__c, Library_Item__c, Skill_Offer__c, and Contact.
 *              Content uses SOSL; people use a two-stage SOQL search (name-only vs expanded when contact info is shared).
 *              Bidirectional blocks suppress matching contacts and their content.
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
        Set<Id> blockedContactIds = String.isNotBlank(currentContactId)
            ? FimbyBlockingHelper.getBidirectionalBlocks((Id) currentContactId)
            : new Set<Id>();

        String sanitized = String.escapeSingleQuotes(searchTerm.trim());

        // Build RETURNING clauses based on filter (people handled separately via SOQL)
        String returningClause = buildReturningClause(filter, neighbourhoodAccountId);

        List<List<SObject>> soslResults = new List<List<SObject>>();
        if (String.isNotBlank(returningClause)) {
            String soslQuery = 'FIND \'' + sanitized + '*\' IN ALL FIELDS RETURNING ' + returningClause;
            soslResults = Search.query(soslQuery);
        }

        // Parse results into unified items and count by type
        List<SearchResultItem> allItems = new List<SearchResultItem>();
        Map<String, Integer> countsByType = new Map<String, Integer>{
            'stories' => 0,
            'askOffer' => 0,
            'library' => 0,
            'skills' => 0,
            'people' => 0
        };

        Integer resultSetIndex = 0;

        if (filter == 'all' || filter == 'stories') {
            List<Story__c> stories = (List<Story__c>) soslResults[resultSetIndex];
            List<SObject> visibleStories = FimbyBlockingHelper.filterVisible(
                stories, blockedContactIds, new List<String>{ 'Posted_By__c', 'Contact__c' }
            );
            countsByType.put('stories', visibleStories.size());
            for (SObject sObj : visibleStories) {
                allItems.add(buildStoryItem((Story__c) sObj));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'askOffer') {
            List<Needs_Offers__c> needsOffers = (List<Needs_Offers__c>) soslResults[resultSetIndex];
            List<SObject> visibleAskOffers = FimbyBlockingHelper.filterVisible(
                needsOffers, blockedContactIds, new List<String>{ 'Contact__c', 'Posted_By__c' }
            );
            countsByType.put('askOffer', visibleAskOffers.size());
            for (SObject no : visibleAskOffers) {
                allItems.add(buildAskOfferItem((Needs_Offers__c) no));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'library') {
            List<Library_Item__c> libraryItems = (List<Library_Item__c>) soslResults[resultSetIndex];
            List<SObject> visibleLibraryItems = FimbyBlockingHelper.filterVisible(
                libraryItems, blockedContactIds, new List<String>{ 'Owner_Contact__c', 'Listed_By__c' }
            );
            countsByType.put('library', visibleLibraryItems.size());
            for (SObject li : visibleLibraryItems) {
                allItems.add(buildLibraryItem((Library_Item__c) li));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'skills') {
            List<Skill_Offer__c> skillOffers = (List<Skill_Offer__c>) soslResults[resultSetIndex];
            List<SObject> visibleSkills = FimbyBlockingHelper.filterVisible(
                skillOffers, blockedContactIds, new List<String>{ 'Owner_Contact__c', 'Listed_By__c' }
            );
            countsByType.put('skills', visibleSkills.size());
            for (SObject sk : visibleSkills) {
                allItems.add(buildSkillItem((Skill_Offer__c) sk));
            }
            resultSetIndex++;
        }

        if (filter == 'all' || filter == 'people') {
            List<Contact> contacts = searchPeopleContacts(
                searchTerm.trim(),
                neighbourhoodAccountId,
                currentContactId,
                sharedContactIds,
                blockedContactIds
            );
            countsByType.put('people', contacts.size());
            for (Contact c : contacts) {
                SearchResultItem item = buildPeopleItem(c);
                Boolean isShared = sharedContactIds.contains(c.Id);
                item.hasSharedContact = isShared;
                if (!isShared) {
                    item.description = null;
                }
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
                'Contact__c, Posted_By__c, ' +
                'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                storyClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Posted_By__c');
            }
            storyClause += ' ORDER BY CreatedDate DESC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(storyClause);
        }

        if (filter == 'all' || filter == 'askOffer') {
            String aoClause = 'Needs_Offers__c(Id, Name, Details__c, Type__c, Status__c, RecordType.Name, ' +
                'Contact__c, Posted_By__c, ' +
                'Image_1_URL__c, Image_1_Ratio__c, Category__c, ' +
                'Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                aoClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Posted_By__c');
            }
            aoClause += ' ORDER BY CreatedDate DESC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(aoClause);
        }

        if (filter == 'all' || filter == 'library') {
            String libClause = 'Library_Item__c(Id, Name, Description__c, Category__c, Status__c, ' +
                'Owner_Contact__c, Listed_By__c, ' +
                'Image_URL__c, Image_Ratio__c, ' +
                'Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                libClause += ' WHERE ' + buildContentFilter(neighbourhoodAccountId, adjList, sharedList, 'Owner_Contact__c');
            }
            libClause += ' ORDER BY Name ASC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(libClause);
        }

        if (filter == 'all' || filter == 'skills') {
            String skillClause = 'Skill_Offer__c(Id, Name, Description_Text__c, Skill_Category__c, Status__c, ' +
                'Owner_Contact__c, Owner_Contact__r.Full_Name__c, Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c, ' +
                'Listed_By__c, CreatedDate';
            if (String.isNotBlank(neighbourhoodAccountId)) {
                String nId = String.escapeSingleQuotes(neighbourhoodAccountId);
                skillClause += ' WHERE Neighbourhood__c = \'' + nId + '\'';
                skillClause += ' AND Status__c = \'' + String.escapeSingleQuotes(FimbyConstants.SKILL_ACTIVE) + '\'';
                skillClause += ' AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';
            }
            skillClause += ' ORDER BY CreatedDate DESC LIMIT ' + FimbySettings.searchResultsLimit() + ')';
            clauses.add(skillClause);
        }

        if (clauses.isEmpty()) {
            return '';
        }

        return String.join(clauses, ', ');
    }

    // ============================================
    // People search — two-stage SOQL (not SOSL)
    // ============================================

    /**
     * @description Stage 1: neighbourhood contacts without shared info — Full_Name__c only.
     *              Stage 2: contacts with shared info — name + profile bio fields.
     *              Bidirectional blocks excluded in both stages.
     */
    private static List<Contact> searchPeopleContacts(
        String searchTerm,
        String neighbourhoodAccountId,
        String currentContactId,
        Set<Id> sharedContactIds,
        Set<Id> blockedContactIds
    ) {
        if (String.isBlank(neighbourhoodAccountId) || String.isBlank(searchTerm)) {
            return new List<Contact>();
        }

        String pattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        Integer limitVal = FimbySettings.searchContactsLimit();
        Id neighbourhoodId = (Id) neighbourhoodAccountId;

        Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
        Set<Id> adjacentSharedIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

        Set<Id> sharedIds = sharedContactIds != null ? sharedContactIds : new Set<Id>();
        Set<Id> blockedIds = blockedContactIds != null ? blockedContactIds : new Set<Id>();

        // Contacts whose shared-to-me contact-info snapshot matches the term
        // (email/phone/address etc.) — only info actually given to the searcher.
        Set<Id> snapshotMatchedIds = new SharedContactLookup()
            .getSnapshotMatchedContactIds(currentContactId, pattern);

        Map<Id, Contact> matchesById = new Map<Id, Contact>();

        // Stage 1 — name-only for contacts without shared info
        List<Contact> restrictedMatches = [
            SELECT Id, Name, Full_Name__c, Image_URL__c, Display_Avatar_URL__c, About_Enjoys_Doing__c,
                   About_Fun_Fact__c, About_Local_Place__c, Account.Name, Is_Organization_Contact__c, Organization_Account__c
            FROM Contact
            WHERE Is_Organization_Contact__c = false
              AND Id NOT IN :sharedIds
              AND Id NOT IN :blockedIds
              AND Full_Name__c LIKE :pattern
              AND (AccountId = :neighbourhoodId
                   OR (AccountId IN :adjacentIds AND Id IN :adjacentSharedIds))
            ORDER BY Name ASC
            LIMIT :limitVal
        ];
        matchesById.putAll(restrictedMatches);

        // Stage 2 — expanded profile fields when contact info is shared
        if (!sharedIds.isEmpty()) {
            List<Contact> expandedMatches = [
                SELECT Id, Name, Full_Name__c, Image_URL__c, Display_Avatar_URL__c, About_Enjoys_Doing__c,
                       About_Fun_Fact__c, About_Local_Place__c, Account.Name, Is_Organization_Contact__c, Organization_Account__c
                FROM Contact
                WHERE Is_Organization_Contact__c = false
                  AND Id IN :sharedIds
                  AND Id NOT IN :blockedIds
                  AND (Full_Name__c LIKE :pattern
                       OR Name LIKE :pattern
                       OR FirstName LIKE :pattern
                       OR LastName LIKE :pattern
                       OR About_Enjoys_Doing__c LIKE :pattern
                       OR About_Fun_Fact__c LIKE :pattern
                       OR About_Local_Place__c LIKE :pattern
                       OR Id IN :snapshotMatchedIds)
                  AND (AccountId = :neighbourhoodId
                       OR (AccountId IN :adjacentIds AND Id IN :adjacentSharedIds))
                ORDER BY Name ASC
                LIMIT :limitVal
            ];
            matchesById.putAll(expandedMatches);
        }

        List<Contact> ordered = new List<Contact>(matchesById.values());
        ordered.sort(new ContactNameComparator());
        if (ordered.size() > limitVal) {
            List<Contact> trimmed = new List<Contact>();
            for (Integer i = 0; i < limitVal; i++) {
                trimmed.add(ordered[i]);
            }
            return trimmed;
        }
        return ordered;
    }

    private class ContactNameComparator implements Comparator<Contact> {
        public Integer compare(Contact a, Contact b) {
            String nameA = a.Full_Name__c != null ? a.Full_Name__c : a.Name;
            String nameB = b.Full_Name__c != null ? b.Full_Name__c : b.Name;
            if (nameA == null && nameB == null) return 0;
            if (nameA == null) return 1;
            if (nameB == null) return -1;
            return nameA.compareTo(nameB);
        }
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
        item.postedByImageUrl = s.Posted_By__r?.Display_Avatar_URL__c;
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
        item.postedByImageUrl = no.Posted_By__r?.Display_Avatar_URL__c;
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
        item.postedByImageUrl = li.Owner_Contact__r?.Display_Avatar_URL__c;
        item.createdDate = li.CreatedDate;
        item.status = li.Status__c;
        item.hasSharedContact = null;
        return item;
    }

    private static SearchResultItem buildSkillItem(Skill_Offer__c sk) {
        SearchResultItem item = new SearchResultItem();
        item.recordId = sk.Id;
        item.resultType = 'skill';
        item.name = sk.Name;
        item.description = sk.Description_Text__c;
        item.subType = sk.Skill_Category__c;
        item.imageUrl = null;
        item.imageRatio = null;
        item.postedByName = sk.Owner_Contact__r?.Full_Name__c;
        item.postedByImageUrl = sk.Owner_Contact__r?.Display_Avatar_URL__c;
        item.createdDate = sk.CreatedDate;
        item.status = sk.Status__c;
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
        item.imageUrl = c.Display_Avatar_URL__c;
        item.imageRatio = null;
        item.postedByName = null;
        item.postedByImageUrl = null;
        item.createdDate = null;
        item.status = null;
        item.hasSharedContact = false;
        item.isOrgContact = c.Is_Organization_Contact__c == true;
        item.orgAccountId = c.Organization_Account__c;
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
            'skills' => 0,
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

        /**
         * @description Returns Contact Ids whose contact-info snapshot SHARED TO the
         *              given contact matches the search pattern. Only the to-me direction
         *              is searched, so a contact who merely received the searcher's info
         *              (without sharing their own) cannot be found by their details.
         * @param contactId The searcher's Contact Id.
         * @param pattern SOQL LIKE pattern (already wrapped in %% and escaped).
         * @return Set of Contact Ids with a matching shared snapshot.
         */
        public Set<Id> getSnapshotMatchedContactIds(String contactId, String pattern) {
            Set<Id> ids = new Set<Id>();
            if (String.isBlank(contactId) || String.isBlank(pattern)) return ids;

            for (Shared_Contact_Info__c sci : [
                SELECT Contact__c
                FROM Shared_Contact_Info__c
                WHERE Shared_To__c = :contactId
                AND Contact__c != null
                AND (Email__c LIKE :pattern
                     OR Phone__c LIKE :pattern
                     OR First_Name__c LIKE :pattern
                     OR Last_Name__c LIKE :pattern
                     OR Street__c LIKE :pattern
                     OR City__c LIKE :pattern
                     OR Postal_Code__c LIKE :pattern
                     OR Additional_Info__c LIKE :pattern)
            ]) {
                ids.add(sci.Contact__c);
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
        @AuraEnabled public Boolean isOrgContact { get; set; }
        @AuraEnabled public Id orgAccountId { get; set; }

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