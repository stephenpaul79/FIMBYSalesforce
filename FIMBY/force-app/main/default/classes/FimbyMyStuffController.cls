/**
 * @description Controller for the "My Stuff" page — returns user-owned content: posts (needs/offers), stories, library items, and borrowed items.
 */
public with sharing class FimbyMyStuffController {

    /**
     * Return profile information for the acting-as contact.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, String> getMyProfile() {
        String contactId = FimbyIdentityRepository.getActingAsContactId();

        Map<String, String> profile = new Map<String, String>();
        if (String.isBlank(contactId)) {
            profile.put('name', UserInfo.getName());
            profile.put('neighbourhood', '');
            profile.put('imageUrl', '');
            return profile;
        }

        Contact c = [SELECT Id, Full_Name__c, Image_URL__c, Account.Name
                      FROM Contact WHERE Id = :contactId WITH SECURITY_ENFORCED LIMIT 1];

        profile.put('name', c.Full_Name__c != null ? c.Full_Name__c : UserInfo.getName());
        profile.put('neighbourhood', c.Account?.Name != null ? c.Account.Name : '');
        profile.put('imageUrl', c.Image_URL__c != null ? c.Image_URL__c : '');
        return profile;
    }

    /**
     * Aggregate counts for all sections — called once on page load.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> getMineSummary() {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        Map<String, Integer> counts = new Map<String, Integer>();

        if (String.isBlank(contactId)) {
            counts.put('postsCount', 0);
            counts.put('postsActiveCount', 0);
            counts.put('postsInactiveCount', 0);
            counts.put('storiesCount', 0);
            counts.put('libraryCount', 0);
            counts.put('libraryActiveCount', 0);
            counts.put('libraryAvailableCount', 0);
            counts.put('borrowedCount', 0);
            counts.put('skillsCount', 0);
            return counts;
        }

        Set<String> activeStatuses = new Set<String>{ 'Posted', 'Reply Received', 'Reply Accepted', 'Available', 'Shares Available', 'Pickup Ready' };

        List<Needs_Offers__c> allPosts = [
            SELECT Id, Status__c FROM Needs_Offers__c
            WHERE Posted_By__c = :contactId WITH SECURITY_ENFORCED
        ];
        Integer postsActive = 0;
        Integer postsInactive = 0;
        for (Needs_Offers__c p : allPosts) {
            if (activeStatuses.contains(p.Status__c)) {
                postsActive++;
            } else {
                postsInactive++;
            }
        }
        counts.put('postsCount', allPosts.size());
        counts.put('postsActiveCount', postsActive);
        counts.put('postsInactiveCount', postsInactive);

        counts.put('storiesCount',
            [SELECT COUNT() FROM Story__c WHERE Posted_By__c = :contactId WITH SECURITY_ENFORCED]);

        List<Library_Item__c> allLibItems = [
            SELECT Id, Status__c FROM Library_Item__c
            WHERE Owner_Contact__c = :contactId WITH SECURITY_ENFORCED
        ];
        Set<Id> libItemIds = new Set<Id>();
        for (Library_Item__c li : allLibItems) { libItemIds.add(li.Id); }

        Set<Id> loanedItemIds = new Set<Id>();
        if (!libItemIds.isEmpty()) {
            for (Loaned_Item__c loan : [
                SELECT Library_Item__c FROM Loaned_Item__c
                WHERE Library_Item__c IN :libItemIds
                AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true)
                WITH SECURITY_ENFORCED
            ]) {
                loanedItemIds.add(loan.Library_Item__c);
            }
        }

        Integer libActive = 0;
        Integer libAvailable = 0;
        for (Library_Item__c li : allLibItems) {
            if (loanedItemIds.contains(li.Id) || li.Status__c == 'On Loan') {
                libActive++;
            } else if (li.Status__c == 'Available') {
                libAvailable++;
            }
        }
        counts.put('libraryCount', allLibItems.size());
        counts.put('libraryActiveCount', libActive);
        counts.put('libraryAvailableCount', libAvailable);

        counts.put('borrowedCount',
            [SELECT COUNT() FROM Loaned_Item__c WHERE Loaned_To__c = :contactId AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true) WITH SECURITY_ENFORCED]);
        counts.put('contactsCount',
            new SharedContactHelper().countSharedContacts(contactId));

        counts.put('skillsCount', [
            SELECT COUNT() FROM Skill_Offer__c
            WHERE Owner_Contact__c = :contactId
              AND Status__c != :FimbyConstants.SKILL_REMOVED
            WITH SECURITY_ENFORCED
        ]);

        return counts;
    }

    /**
     * My Skills — newest first.
     */
    @AuraEnabled(cacheable=false)
    public static List<SkillOfferWrapper> getMySkills(Integer pageSize) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<SkillOfferWrapper>();
        }

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.myLibraryItemsLimit();
        List<Skill_Offer__c> skills = [
            SELECT Id, Name, Description_Text__c, Skill_Category__c, Status__c, Availability_Note__c, CreatedDate
            FROM Skill_Offer__c
            WHERE Owner_Contact__c = :contactId
              AND Status__c != :FimbyConstants.SKILL_REMOVED
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ];

        List<SkillOfferWrapper> wrappers = new List<SkillOfferWrapper>();
        for (Skill_Offer__c skill : skills) {
            SkillOfferWrapper w = new SkillOfferWrapper();
            w.Id = skill.Id;
            w.Name = skill.Name;
            w.description = skill.Description_Text__c;
            w.category = skill.Skill_Category__c;
            w.status = skill.Status__c;
            w.availabilityNote = skill.Availability_Note__c;
            w.CreatedDate = skill.CreatedDate;
            wrappers.add(w);
        }
        return wrappers;
    }

    /**
     * My Posts — newest first, paginated.
     */
    @AuraEnabled(cacheable=false)
    public static List<Needs_Offers__c> getMyPosts(Integer pageSize) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<Needs_Offers__c>();
        }

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.myPostsPageSize();

        return [
            SELECT Id, Name, Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c,
                   RecordType.Name, Category__c, Event_Type__c
            FROM Needs_Offers__c
            WHERE Posted_By__c = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY Posted_Date__c DESC
            LIMIT :limitSize
        ];
    }

    /**
     * My Stories — 10 most recent.
     */
    @AuraEnabled(cacheable=false)
    public static List<Story__c> getMyStories(Integer pageSize) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<Story__c>();
        }

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : 10;

        return [
            SELECT Id, Name, Message__c, Type__c, CreatedDate
            FROM Story__c
            WHERE Posted_By__c = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ];
    }

    /**
     * My Library Items — two-batch approach:
     * 1. ALL items with an active loan (no limit)
     * 2. Up to 10 available items (no active loan), newest first
     */
    @AuraEnabled(cacheable=false)
    public static List<LibraryItemWrapper> getMyLibraryItems(Integer pageSize) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<LibraryItemWrapper>();
        }

        Integer libLim = FimbySettings.myLibraryItemsLimit();
        List<Library_Item__c> allItems = [
            SELECT Id, Name, Description__c, Category__c, Status__c, CreatedDate
            FROM Library_Item__c
            WHERE Owner_Contact__c = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :libLim
        ];

        if (allItems.isEmpty()) {
            return new List<LibraryItemWrapper>();
        }

        // Build set of all item IDs for loan lookup
        Set<Id> allItemIds = new Set<Id>();
        for (Library_Item__c item : allItems) {
            allItemIds.add(item.Id);
        }

        // Get all active loans for these items (includes pending owner confirmation)
        Map<Id, Loaned_Item__c> activeLoans = new Map<Id, Loaned_Item__c>();
        for (Loaned_Item__c loan : [
            SELECT Id, Library_Item__c, Loaned_To__r.Full_Name__c, Loan_Due_Date__c
            FROM Loaned_Item__c
            WHERE Library_Item__c IN :allItemIds AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true)
            WITH SECURITY_ENFORCED
        ]) {
            activeLoans.put(loan.Library_Item__c, loan);
        }

        // Batch 1: All items with an active loan (no limit)
        List<LibraryItemWrapper> wrappers = new List<LibraryItemWrapper>();
        List<Library_Item__c> availableItems = new List<Library_Item__c>();

        for (Library_Item__c item : allItems) {
            Loaned_Item__c loan = activeLoans.get(item.Id);
            if (loan != null) {
                LibraryItemWrapper w = new LibraryItemWrapper();
                w.Id = item.Id;
                w.Name = item.Name;
                w.description = item.Description__c;
                w.category = item.Category__c;
                w.status = item.Status__c;
                w.CreatedDate = item.CreatedDate;
                w.loanedToName = loan.Loaned_To__r?.Full_Name__c;
                w.dueDate = loan.Loan_Due_Date__c;
                wrappers.add(w);
            } else {
                availableItems.add(item);
            }
        }

        // Batch 2: Up to 10 available items (newest first — already sorted)
        Integer availableLimit = (pageSize != null && pageSize > 0) ? pageSize : 10;
        Integer count = 0;
        for (Library_Item__c item : availableItems) {
            if (count >= availableLimit) break;
            LibraryItemWrapper w = new LibraryItemWrapper();
            w.Id = item.Id;
            w.Name = item.Name;
            w.description = item.Description__c;
            w.category = item.Category__c;
            w.status = item.Status__c;
            w.CreatedDate = item.CreatedDate;
            wrappers.add(w);
            count++;
        }

        return wrappers;
    }

    /**
     * My Borrowed Items — sorted by due date (overdue first).
     */
    @AuraEnabled(cacheable=false)
    public static List<BorrowedItemWrapper> getMyBorrowedItems() {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<BorrowedItemWrapper>();
        }

        Integer borrowLim = FimbySettings.borrowedItemsLimit();
        List<Loaned_Item__c> loans = [
            SELECT Id, Library_Item__r.Name, Library_Item__r.Id,
                   Library_Item__r.Category__c,
                   Library_Item__r.Owner_Contact__r.Full_Name__c,
                   Loan_Due_Date__c, Status__c
            FROM Loaned_Item__c
            WHERE Loaned_To__c = :contactId AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true)
            WITH SECURITY_ENFORCED
            ORDER BY Loan_Due_Date__c ASC NULLS LAST
            LIMIT :borrowLim
        ];

        List<BorrowedItemWrapper> wrappers = new List<BorrowedItemWrapper>();
        for (Loaned_Item__c loan : loans) {
            BorrowedItemWrapper w = new BorrowedItemWrapper();
            w.Id = loan.Id;
            w.itemId = loan.Library_Item__r?.Id;
            w.itemName = loan.Library_Item__r?.Name;
            w.ownerName = loan.Library_Item__r?.Owner_Contact__r?.Full_Name__c;
            w.category = loan.Library_Item__r?.Category__c;
            w.dueDate = loan.Loan_Due_Date__c;
            w.status = loan.Status__c;
            wrappers.add(w);
        }

        return wrappers;
    }

    /**
     * My Contacts — people who have shared contact info with me or I've shared with.
     * Deduplicates: if A shared to B and B shared to A, show one entry.
     */
    @AuraEnabled(cacheable=false)
    public static List<ContactCardWrapper> getMyContacts(String searchTerm) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return new List<ContactCardWrapper>();
        }
        return new SharedContactHelper().getContactCards(contactId, searchTerm);
    }

    /**
     * Get current user's contact details for pre-filling the share form.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getMyContactDetailsForSharing() {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) return new Map<String, Object>();
        return new SharedContactHelper().getContactDetailsForSharingInternal(contactId);
    }

    /**
     * Search neighbourhood contacts by name or email.
     * Returns contacts in the same Account (neighbourhood) as the current user,
     * excluding self and contacts already in My Contacts.
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> searchNeighbourhoodContacts(String searchTerm) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) return new List<Map<String, Object>>();
        return new SharedContactHelper().searchNeighbourhoodContactsInternal(contactId, searchTerm);
    }

    /**
     * Share contact info directly with a neighbour (no Response context).
     */
    @AuraEnabled
    public static Map<String, Object> shareContactInfoDirect(String shareDataJson) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Unable to resolve current user.');
        }
        return new SharedContactHelper().shareContactInfoDirectInternal(contactId, shareDataJson);
    }

    /**
     * Revoke a shared contact info record (sets Status__c = 'Revoked').
     * Only the sharer (Contact__c) can revoke their own record.
     */
    @AuraEnabled
    public static void revokeSharedContactInfo(Id sharedContactInfoId) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Unable to resolve current user.');
        }
        new SharedContactHelper().revokeInternal(contactId, sharedContactInfoId);
    }

    /**
     * Load a neighbour's profile for read-only display.
     * Returns all profile sections (About, Accessibility, Care) from the Contact,
     * but only returns contact info (email/phone/address) that the neighbour
     * has explicitly shared with the current user via Shared_Contact_Info__c.
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getNeighbourProfile(String neighbourContactId) {
        String myContactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(myContactId) || String.isBlank(neighbourContactId)) {
            throw new AuraHandledException('Unable to load neighbour profile.');
        }
        return new SharedContactHelper().getNeighbourProfileInternal(myContactId, neighbourContactId);
    }

    /**
     * Undo a revoke — restore Status__c to 'Active'.
     */
    @AuraEnabled
    public static void undoRevokeSharedContactInfo(Id sharedContactInfoId) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            throw new AuraHandledException('Unable to resolve current user.');
        }
        new SharedContactHelper().undoRevokeInternal(contactId, sharedContactInfoId);
    }

    /* ---------------------------------------------------------------
     * ARCHIVE METHODS — paginated queries with filters + total counts
     * --------------------------------------------------------------- */

    /**
     * Post Archive — paginated with optional filter by RecordType.
     */
    @AuraEnabled(cacheable=false)
    public static ArchiveResult getMyPostsArchive(Integer pageSize, Integer offset, String filterType) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        ArchiveResult result = new ArchiveResult();
        result.items = new List<Object>();
        result.totalCount = 0;

        if (String.isBlank(contactId)) return result;

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.archivePageSize();
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

        Set<String> activeStatuses = new Set<String>{
            'Posted', 'Reply Received', 'Reply Accepted', 'Available', 'Shares Available', 'Pickup Ready'
        };
        String baseQuery = 'SELECT Id, Name, Details__c, Type__c, Status__c, CreatedDate, Posted_Date__c, RecordType.Name, Category__c, Event_Type__c FROM Needs_Offers__c WHERE Posted_By__c = :contactId AND Status__c NOT IN :activeStatuses';
        String countQuery = 'SELECT COUNT() FROM Needs_Offers__c WHERE Posted_By__c = :contactId AND Status__c NOT IN :activeStatuses';

        if (String.isNotBlank(filterType) && filterType != 'All') {
            if (filterType == 'Event') {
                baseQuery += ' AND Type__c = \'Event\'';
                countQuery += ' AND Type__c = \'Event\'';
            } else if (filterType == 'Bulk_Buy') {
                baseQuery += ' AND RecordType.DeveloperName = \'Bulk_Buy\'';
                countQuery += ' AND RecordType.DeveloperName = \'Bulk_Buy\'';
            } else {
                baseQuery += ' AND RecordType.DeveloperName = :filterType AND Type__c != \'Event\'';
                countQuery += ' AND RecordType.DeveloperName = :filterType AND Type__c != \'Event\'';
            }
        }

        baseQuery += ' WITH SECURITY_ENFORCED ORDER BY Posted_Date__c DESC LIMIT :limitSize OFFSET :offsetVal';
        countQuery += ' WITH SECURITY_ENFORCED';

        result.totalCount = Database.countQuery(countQuery);
        result.items = Database.query(baseQuery);

        return result;
    }

    /**
     * Story Archive — paginated with optional filter by Type__c.
     * Excludes the most recent stories already shown on the MyStuffPage.
     */
    @AuraEnabled(cacheable=false)
    public static ArchiveResult getMyStoriesArchive(Integer pageSize, Integer offset, String filterType) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        ArchiveResult result = new ArchiveResult();
        result.items = new List<Object>();
        result.totalCount = 0;

        if (String.isBlank(contactId)) return result;

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.archivePageSize();
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

        // Exclude the most recent stories shown on the active MyStuffPage
        Integer recentLimit = 10;
        List<Story__c> recentStories = [
            SELECT Id FROM Story__c
            WHERE Posted_By__c = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :recentLimit
        ];
        Set<Id> recentIds = new Set<Id>();
        for (Story__c s : recentStories) {
            recentIds.add(s.Id);
        }

        String baseQuery = 'SELECT Id, Name, Message__c, Type__c, CreatedDate FROM Story__c WHERE Posted_By__c = :contactId AND Id NOT IN :recentIds';
        String countQuery = 'SELECT COUNT() FROM Story__c WHERE Posted_By__c = :contactId AND Id NOT IN :recentIds';

        if (String.isNotBlank(filterType) && filterType != 'All') {
            baseQuery += ' AND Type__c = :filterType';
            countQuery += ' AND Type__c = :filterType';
        }

        baseQuery += ' WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT :limitSize OFFSET :offsetVal';
        countQuery += ' WITH SECURITY_ENFORCED';

        result.totalCount = Database.countQuery(countQuery);
        result.items = Database.query(baseQuery);

        return result;
    }

    /**
     * Library Items Archive — only items no longer active (Unavailable/removed).
     * Active items (On Loan, Available) are shown on the MyStuffPage.
     */
    @AuraEnabled(cacheable=false)
    public static ArchiveResult getMyLibraryItemsArchive(Integer pageSize, Integer offset, String filterStatus) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        ArchiveResult result = new ArchiveResult();
        result.items = new List<Object>();
        result.totalCount = 0;

        if (String.isBlank(contactId)) return result;

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.archivePageSize();
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

        result.totalCount = [
            SELECT COUNT()
            FROM Library_Item__c
            WHERE Owner_Contact__c = :contactId AND Status__c = 'Unavailable'
            WITH SECURITY_ENFORCED
        ];

        List<Library_Item__c> items = [
            SELECT Id, Name, Description__c, Category__c, Status__c, CreatedDate
            FROM Library_Item__c
            WHERE Owner_Contact__c = :contactId AND Status__c = 'Unavailable'
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
            OFFSET :offsetVal
        ];

        List<LibraryItemWrapper> wrappers = new List<LibraryItemWrapper>();
        for (Library_Item__c item : items) {
            LibraryItemWrapper w = new LibraryItemWrapper();
            w.Id = item.Id;
            w.Name = item.Name;
            w.description = item.Description__c;
            w.category = item.Category__c;
            w.status = item.Status__c;
            w.CreatedDate = item.CreatedDate;
            wrappers.add(w);
        }
        result.items = wrappers;

        return result;
    }

    /**
     * Borrow History — queries Lending_History__c (completed/returned loans).
     * Active loans are shown on the MyStuffPage via Loaned_Item__c.
     */
    @AuraEnabled(cacheable=false)
    public static ArchiveResult getMyBorrowHistory(Integer pageSize, Integer offset, String filterStatus) {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        ArchiveResult result = new ArchiveResult();
        result.items = new List<Object>();
        result.totalCount = 0;

        if (String.isBlank(contactId)) return result;

        Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.archivePageSize();
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

        result.totalCount = [
            SELECT COUNT()
            FROM Lending_History__c
            WHERE Borrowed_By__c = :contactId
            WITH SECURITY_ENFORCED
        ];

        List<Lending_History__c> histories = [
            SELECT Id, Name, Library_Item__c, Library_Item__r.Category__c,
                   Lent_By__r.Full_Name__c, Start_Date__c, End_Date__c, CreatedDate
            FROM Lending_History__c
            WHERE Borrowed_By__c = :contactId
            WITH SECURITY_ENFORCED
            ORDER BY End_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :limitSize
            OFFSET :offsetVal
        ];

        List<BorrowedItemWrapper> wrappers = new List<BorrowedItemWrapper>();
        for (Lending_History__c h : histories) {
            BorrowedItemWrapper w = new BorrowedItemWrapper();
            w.Id = h.Id;
            w.itemId = h.Library_Item__c;
            w.itemName = h.Name;
            w.ownerName = h.Lent_By__r?.Full_Name__c;
            w.category = h.Library_Item__r?.Category__c;
            w.dueDate = null;
            w.status = 'Returned';
            w.returnedDate = h.End_Date__c;
            wrappers.add(w);
        }
        result.items = wrappers;

        return result;
    }

    /* ---------------------------------------------------------------
     * Wrapper classes — use clean property names (no __c suffix)
     * --------------------------------------------------------------- */
    public class ArchiveResult {
        @AuraEnabled public List<Object> items { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
    }

    public class LibraryItemWrapper {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime CreatedDate { get; set; }
        @AuraEnabled public String loanedToName { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
    }

    public class SkillOfferWrapper {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public String Name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String availabilityNote { get; set; }
        @AuraEnabled public Datetime CreatedDate { get; set; }
    }

    public class BorrowedItemWrapper {
        @AuraEnabled public Id Id { get; set; }
        @AuraEnabled public Id itemId { get; set; }
        @AuraEnabled public String itemName { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date returnedDate { get; set; }
    }

    /**
     * @description Without sharing helper — Shared_Contact_Info__c has Private external sharing, so community users need elevated access.
     */
    private without sharing class SharedContactHelper {

        /**
         * @description Returns contact details (email, phone, address) for pre-filling the share form.
         * @param contactId Contact Id whose details to retrieve
         * @return Map with email, phone, street, city, state, postalCode, country
         */
        public Map<String, Object> getContactDetailsForSharingInternal(String contactId) {
            Contact c = [
                SELECT Id, Name, Email, Phone, MailingStreet, MailingCity, MailingState,
                       MailingPostalCode, MailingCountry
                FROM Contact WHERE Id = :contactId LIMIT 1
            ];
            return new Map<String, Object>{
                'email' => c.Email,
                'phone' => c.Phone,
                'street' => c.MailingStreet,
                'city' => c.MailingCity,
                'state' => c.MailingState,
                'postalCode' => c.MailingPostalCode,
                'country' => c.MailingCountry
            };
        }

        /**
         * @description Counts shared contact info records where the contact is sharer or recipient.
         * @param contactId Contact Id to count for
         * @return Number of Shared_Contact_Info__c records
         */
        public Integer countSharedContacts(String contactId) {
            return [SELECT COUNT() FROM Shared_Contact_Info__c
                    WHERE Contact__c = :contactId OR Shared_To__c = :contactId];
        }

        /**
         * @description Returns deduplicated contact cards for people who have shared info with this contact or vice versa.
         * @param contactId Contact Id (acting-as)
         * @param searchTerm Optional filter by name
         * @return List of ContactCardWrapper
         */
        public List<ContactCardWrapper> getContactCards(String contactId, String searchTerm) {
            Integer sharedLim = FimbySettings.sharedContactsLimit();
            List<Shared_Contact_Info__c> shared = [
                SELECT Id, Contact__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                       Contact__r.Account.Name,
                       Shared_To__c, Shared_To__r.Name, Shared_To__r.FirstName, Shared_To__r.LastName,
                       Shared_To__r.Account.Name,
                       Email__c, Phone__c, Street__c, City__c, Province_State__c, Postal_Code__c,
                       Country__c, Additional_Info__c, Status__c, Origin__c, CreatedDate
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :contactId OR Shared_To__c = :contactId
                ORDER BY CreatedDate DESC
                LIMIT :sharedLim
            ];

            Map<Id, ContactCardWrapper> contactMap = new Map<Id, ContactCardWrapper>();
            for (Shared_Contact_Info__c sci : shared) {
                Id otherId;
                String otherName, otherFirstName, otherLastName, otherNeighbourhood;
                Boolean iShared = (sci.Contact__c == contactId);
                Boolean theyShared = (sci.Shared_To__c == contactId);

                if (iShared) {
                    otherId = sci.Shared_To__c;
                    otherName = sci.Shared_To__r?.Name;
                    otherFirstName = sci.Shared_To__r?.FirstName;
                    otherLastName = sci.Shared_To__r?.LastName;
                    otherNeighbourhood = sci.Shared_To__r?.Account?.Name;
                } else {
                    otherId = sci.Contact__c;
                    otherName = sci.Contact__r?.Name;
                    otherFirstName = sci.Contact__r?.FirstName;
                    otherLastName = sci.Contact__r?.LastName;
                    otherNeighbourhood = sci.Contact__r?.Account?.Name;
                }

                if (otherId == null) continue;

                if (String.isNotBlank(searchTerm)) {
                    String term = searchTerm.toLowerCase();
                    if (otherName == null || !otherName.toLowerCase().contains(term)) continue;
                }

                ContactCardWrapper w = contactMap.get(otherId);
                if (w == null) {
                    w = new ContactCardWrapper();
                    w.contactId = otherId;
                    w.name = otherName;
                    w.firstName = otherFirstName;
                    w.lastName = otherLastName;
                    w.neighbourhood = otherNeighbourhood;
                    w.connectedDate = sci.CreatedDate;
                    w.theySharedWithMe = false;
                    w.iSharedWithThem = false;
                    contactMap.put(otherId, w);
                }

                if (iShared) {
                    w.iSharedWithThem = true;
                    w.mySharedInfoId = sci.Id;
                    w.mySharedEmail = sci.Email__c;
                    w.mySharedPhone = sci.Phone__c;
                    w.mySharedStreet = sci.Street__c;
                    w.mySharedCity = sci.City__c;
                    w.mySharedProvinceState = sci.Province_State__c;
                    w.mySharedPostalCode = sci.Postal_Code__c;
                    w.mySharedCountry = sci.Country__c;
                    w.mySharedAdditionalInfo = sci.Additional_Info__c;
                    w.mySharedStatus = sci.Status__c;
                    w.isRevoked = (sci.Status__c == FimbyConstants.SHARED_CONTACT_REVOKED);
                    w.origin = sci.Origin__c;
                }
                if (theyShared) {
                    w.theySharedWithMe = true;
                    if (w.origin == null) w.origin = sci.Origin__c;
                }

                if (theyShared) {
                    w.email = sci.Email__c;
                    w.phone = sci.Phone__c;
                    w.street = sci.Street__c;
                    w.city = sci.City__c;
                    w.provinceState = sci.Province_State__c;
                    w.postalCode = sci.Postal_Code__c;
                } else if (w.theySharedWithMe != true) {
                    w.email = sci.Email__c;
                    w.phone = sci.Phone__c;
                    w.street = sci.Street__c;
                    w.city = sci.City__c;
                    w.provinceState = sci.Province_State__c;
                    w.postalCode = sci.Postal_Code__c;
                }
            }

            return contactMap.values();
        }

        /**
         * @description Searches contacts in the same neighbourhood, excluding those already in My Contacts.
         * @param myContactId Current user's contact Id
         * @param searchTerm Search string (min 2 chars)
         * @return List of maps with contactId, contactName, firstName, email, neighbourhood
         */
        public List<Map<String, Object>> searchNeighbourhoodContactsInternal(String myContactId, String searchTerm) {
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            Contact me = [SELECT Id, AccountId FROM Contact WHERE Id = :myContactId LIMIT 1];
            if (me.AccountId == null) return results;

            Set<Id> existingIds = new Set<Id>{ me.Id };
            // Only exclude contacts with an active outbound share (revoked shares can be re-shared)
            for (Shared_Contact_Info__c sci : [
                SELECT Shared_To__c FROM Shared_Contact_Info__c
                WHERE Contact__c = :myContactId
                  AND Status__c != :FimbyConstants.SHARED_CONTACT_REVOKED
            ]) {
                if (sci.Shared_To__c != null) existingIds.add(sci.Shared_To__c);
            }

            if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
                return results;
            }
            String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            List<Contact> neighbours = [
                SELECT Id, Name, FirstName, LastName, Email, Account.Name
                FROM Contact
                WHERE AccountId = :me.AccountId
                  AND Id NOT IN :existingIds
                  AND Is_Organization_Contact__c = false
                  AND (Name LIKE :term OR Email LIKE :term OR FirstName LIKE :term OR LastName LIKE :term)
                ORDER BY Name
                LIMIT 20
            ];

            for (Contact c : neighbours) {
                results.add(new Map<String, Object>{
                    'contactId' => c.Id,
                    'contactName' => c.Name,
                    'firstName' => c.FirstName,
                    'email' => c.Email,
                    'neighbourhood' => c.Account?.Name
                });
            }
            return results;
        }

        /**
         * @description Shares contact info with a recipient neighbour; creates or updates Shared_Contact_Info__c.
         * @param sharingContactId Contact Id doing the sharing
         * @param shareDataJson JSON with recipientContactId, shareEmail, sharePhone, shareAddress, and field values
         * @return Map with success, sharedContactInfoId, and message
         */
        public Map<String, Object> shareContactInfoDirectInternal(String sharingContactId, String shareDataJson) {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(shareDataJson);
            String recipientContactId = (String) data.get('recipientContactId');
            Boolean shareEmail = data.get('shareEmail') == true;
            Boolean sharePhone = data.get('sharePhone') == true;
            Boolean shareAddress = data.get('shareAddress') == true;
            String email = (String) data.get('email');
            String phone = (String) data.get('phone');
            String street = (String) data.get('street');
            String city = (String) data.get('city');
            String state = (String) data.get('state');
            String postalCode = (String) data.get('postalCode');
            String country = (String) data.get('country');
            String additionalInfo = (String) data.get('additionalInfo');

            if (String.isBlank(recipientContactId) || recipientContactId == sharingContactId) {
                throw new AuraHandledException('You cannot share contact info with yourself.');
            }
            if (!shareEmail && !sharePhone && !shareAddress) {
                throw new AuraHandledException('Select at least one type of contact info to share.');
            }

            Contact sharing = [SELECT Id, Name, FirstName, LastName FROM Contact WHERE Id = :sharingContactId LIMIT 1];
            Contact recipient = [SELECT Id, Name FROM Contact WHERE Id = :recipientContactId LIMIT 1];

            String sciName = sharing.FirstName + ' ' + sharing.LastName + ' - ' + String.valueOf(Date.today());

            List<Shared_Contact_Info__c> existing = [
                SELECT Id, Status__c, Additional_Info__c FROM Shared_Contact_Info__c
                WHERE Contact__c = :sharingContactId AND Shared_To__c = :recipientContactId
                LIMIT 1
            ];

            Shared_Contact_Info__c sci;
            if (existing.isEmpty()) {
                sci = new Shared_Contact_Info__c(
                    Name = sciName,
                    Contact__c = sharingContactId,
                    Shared_To__c = recipientContactId,
                    Origin__c = 'My Neighbours',
                    Status__c = FimbyConstants.SHARED_CONTACT_ACTIVE,
                    Email__c = shareEmail ? email : null,
                    Phone__c = sharePhone ? phone : null,
                    Street__c = shareAddress ? street : null,
                    City__c = shareAddress ? city : null,
                    Province_State__c = shareAddress ? state : null,
                    Postal_Code__c = shareAddress ? postalCode : null,
                    Country__c = shareAddress ? country : null,
                    Additional_Info__c = data.containsKey('additionalInfo')
                        ? (String) data.get('additionalInfo') : null
                );
                insert sci;
            } else {
                sci = existing[0];
                sci.Name = sciName;
                sci.Status__c = FimbyConstants.SHARED_CONTACT_ACTIVE;
                sci.Email__c = shareEmail ? email : null;
                sci.Phone__c = sharePhone ? phone : null;
                sci.Street__c = shareAddress ? street : null;
                sci.City__c = shareAddress ? city : null;
                sci.Province_State__c = shareAddress ? state : null;
                sci.Postal_Code__c = shareAddress ? postalCode : null;
                sci.Country__c = shareAddress ? country : null;
                if (data.containsKey('additionalInfo')) {
                    sci.Additional_Info__c = (String) data.get('additionalInfo');
                }
                update sci;
            }

            return new Map<String, Object>{
                'success' => true,
                'sharedContactInfoId' => sci.Id,
                'message' => 'Contact info shared with ' + recipient.Name
            };
        }

        /**
         * @description Loads a neighbour's profile with shared contact info; only returns contact details if explicitly shared.
         * @param myContactId Current user's contact Id
         * @param neighbourContactId Neighbour contact Id to load
         * @return Map with profile fields and shared contact info when applicable
         */
        public Map<String, Object> getNeighbourProfileInternal(String myContactId, String neighbourContactId) {
            if (!FimbyContactVisibility.canView((Id) myContactId, (Id) neighbourContactId)) {
                throw new AuraHandledException('Unable to load neighbour profile.');
            }

            Contact viewer = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :myContactId
                LIMIT 1
            ];

            Contact c = [
                SELECT Id, FirstName, LastName, Full_Name__c, Pronouns__c,
                       Image_URL__c, Image_Ratio__c, AccountId, Account.Name, CreatedDate,
                       Languages_Spoken__c, Accessibility_Notes__c, General_Availability__c,
                       About_Neighbourhood_Tenure__c, About_What_Brought_You__c,
                       About_Local_Place__c, About_Enjoys_Doing__c, About_Fun_Fact__c,
                       Care_Welcome_Support__c, Care_Unhelpful_Things__c,
                       Care_How_To_Ask__c, Care_Hard_Nos__c,
                       Care_Standing_Visible__c, Care_Updated_Date__c
                FROM Contact
                WHERE Id = :neighbourContactId
                LIMIT 1
            ];

            Boolean sameNeighbourhood = viewer.AccountId != null && viewer.AccountId == c.AccountId;
            Set<Id> blockedIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);
            Boolean isBlocked = blockedIds.contains((Id) neighbourContactId);
            Boolean showCareStanding = sameNeighbourhood
                && !isBlocked
                && c.Care_Standing_Visible__c == true;

            List<Shared_Contact_Info__c> sharedRecords = [
                SELECT Id, Email__c, Phone__c, Street__c, City__c,
                       Province_State__c, Postal_Code__c, Country__c, Status__c
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :neighbourContactId
                  AND Shared_To__c = :myContactId
                  AND Status__c != 'Revoked'
                LIMIT 1
            ];

            Map<String, Object> result = new Map<String, Object>{
                'contactId' => c.Id,
                'firstName' => c.FirstName,
                'lastName' => c.LastName,
                'fullName' => c.Full_Name__c,
                'pronouns' => c.Pronouns__c,
                'imageUrl' => c.Image_URL__c,
                'imageRatio' => c.Image_Ratio__c,
                'neighbourhood' => c.Account?.Name,
                'memberSince' => c.CreatedDate,
                'languagesSpoken' => c.Languages_Spoken__c,
                'accessibilityNotes' => c.Accessibility_Notes__c,
                'generalAvailability' => c.General_Availability__c,
                'aboutNeighbourhoodTenure' => c.About_Neighbourhood_Tenure__c,
                'aboutWhatBroughtYou' => c.About_What_Brought_You__c,
                'aboutLocalPlace' => c.About_Local_Place__c,
                'aboutEnjoysDoing' => c.About_Enjoys_Doing__c,
                'aboutFunFact' => c.About_Fun_Fact__c,
                'careStandingVisible' => showCareStanding,
                'careUpdatedDate' => showCareStanding ? c.Care_Updated_Date__c : null,
                'careWelcomeSupport' => showCareStanding ? c.Care_Welcome_Support__c : null,
                'careUnhelpfulThings' => showCareStanding ? c.Care_Unhelpful_Things__c : null,
                'careHowToAsk' => showCareStanding ? c.Care_How_To_Ask__c : null,
                'careHardNos' => showCareStanding ? c.Care_Hard_Nos__c : null
            };

            if (!sharedRecords.isEmpty()) {
                Shared_Contact_Info__c sci = sharedRecords[0];
                result.put('hasSharedContactInfo', true);
                result.put('sharedEmail', sci.Email__c);
                result.put('sharedPhone', sci.Phone__c);
                result.put('sharedStreet', sci.Street__c);
                result.put('sharedCity', sci.City__c);
                result.put('sharedProvinceState', sci.Province_State__c);
                result.put('sharedPostalCode', sci.Postal_Code__c);
                result.put('sharedCountry', sci.Country__c);
            } else {
                result.put('hasSharedContactInfo', false);
            }

            return result;
        }

        /**
         * @description Revokes a Shared_Contact_Info__c record (sets Status__c to Revoked). Only sharer can revoke.
         * @param myContactId Current user's contact Id (must match Contact__c)
         * @param sharedContactInfoId Id of the Shared_Contact_Info__c to revoke
         */
        public void revokeInternal(String myContactId, Id sharedContactInfoId) {
            Shared_Contact_Info__c sci = [
                SELECT Id, Contact__c, Status__c
                FROM Shared_Contact_Info__c
                WHERE Id = :sharedContactInfoId LIMIT 1
            ];
            if (sci.Contact__c != myContactId) {
                throw new AuraHandledException('You can only revoke sharing that you initiated.');
            }
            sci.Status__c = FimbyConstants.SHARED_CONTACT_REVOKED;
            update sci;
        }

        /**
         * @description Restores a revoked Shared_Contact_Info__c to Active status.
         * @param myContactId Current user's contact Id (must match Contact__c)
         * @param sharedContactInfoId Id of the Shared_Contact_Info__c to restore
         */
        public void undoRevokeInternal(String myContactId, Id sharedContactInfoId) {
            Shared_Contact_Info__c sci = [
                SELECT Id, Contact__c, Status__c
                FROM Shared_Contact_Info__c
                WHERE Id = :sharedContactInfoId LIMIT 1
            ];
            if (sci.Contact__c != myContactId) {
                throw new AuraHandledException('You can only restore sharing that you initiated.');
            }
            sci.Status__c = FimbyConstants.SHARED_CONTACT_ACTIVE;
            update sci;
        }
    }

    public class ContactCardWrapper {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String neighbourhood { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String provinceState { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public Datetime connectedDate { get; set; }
        @AuraEnabled public Boolean theySharedWithMe { get; set; }
        @AuraEnabled public Boolean iSharedWithThem { get; set; }
        @AuraEnabled public Id mySharedInfoId { get; set; }
        @AuraEnabled public String mySharedEmail { get; set; }
        @AuraEnabled public String mySharedPhone { get; set; }
        @AuraEnabled public String mySharedStreet { get; set; }
        @AuraEnabled public String mySharedCity { get; set; }
        @AuraEnabled public String mySharedProvinceState { get; set; }
        @AuraEnabled public String mySharedPostalCode { get; set; }
        @AuraEnabled public String mySharedCountry { get; set; }
        @AuraEnabled public String mySharedAdditionalInfo { get; set; }
        @AuraEnabled public String mySharedStatus { get; set; }
        @AuraEnabled public Boolean isRevoked { get; set; }
        @AuraEnabled public String origin { get; set; }
    }
}