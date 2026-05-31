/**
 * @description Provides contact list data for the fimbyContactsList LWC component.
 * Community users must see the full contact directory regardless of OWD/sharing rules
 * so search and filtering work across all accounts (without sharing).
 */
public without sharing class FimbyContactsController {

    /**
     * @description LWC-callable method that returns a paginated list of contacts with filtering, search, and sorting.
     * @param filterName Optional filter (e.g., 'All Strathcona / DTES Contacts')
     * @param searchTerm Search string for Name or Email
     * @param sortField Field to sort by (Name, Email, AccountName, etc.)
     * @param sortDirection 'ASC' or 'DESC'
     * @param pageSize Page size (max 50)
     * @param offset Pagination offset
     * @return ContactListResult with records and totalCount
     */
    @AuraEnabled(cacheable=true)
    public static ContactListResult getContactsList(
        String filterName,
        String searchTerm,
        String sortField,
        String sortDirection,
        Integer pageSize,
        Integer offset
    ) {
        ContactListResult result = new ContactListResult();
        
        // Set defaults
        Integer limitVal = (pageSize != null && pageSize > 0) ? Math.min(pageSize, 50) : 20;
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
        String sortDir = (sortDirection == 'DESC') ? 'DESC' : 'ASC';
        String sortFld = getSafeField(sortField);
        
        // Build query
        String query = 'SELECT Id, Name, FirstName, LastName, Email, Phone, AccountId, Account.Name FROM Contact';
        String countQuery = 'SELECT COUNT() FROM Contact';
        String whereClause = buildWhereClause(filterName, searchTerm);
        
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
            countQuery += ' WHERE ' + whereClause;
        }
        
        query += ' ORDER BY ' + sortFld + ' ' + sortDir + ' NULLS LAST';
        query += ' LIMIT ' + limitVal + ' OFFSET ' + offsetVal;
        
        // Execute queries
        result.totalCount = Database.countQuery(countQuery);
        result.records = Database.query(query);
        
        return result;
    }
    
    private static String buildWhereClause(String filterName, String searchTerm) {
        List<String> conditions = new List<String>();
        conditions.add('Is_Organization_Contact__c = false');
        
        if (filterName == 'All Strathcona / DTES Contacts') {
            conditions.add('(Account.Name LIKE \'%Strathcona%\' OR Account.Name LIKE \'%DTES%\')');
        }
        
        // Search conditions
        if (String.isNotBlank(searchTerm)) {
            String safeSearch = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            conditions.add('(Name LIKE \'' + safeSearch + '\' OR Email LIKE \'' + safeSearch + '\')');
        }
        
        return String.join(conditions, ' AND ');
    }
    
    private static String getSafeField(String field) {
        if (field == 'AccountName') return 'Account.Name';
        Set<String> allowed = new Set<String>{'Name','FirstName','LastName','Email','Phone','CreatedDate'};
        return allowed.contains(field) ? field : 'Name';
    }

    /**
     * @description Wrapper for contact list API response with records and total count.
     */
    public class ContactListResult {
        @AuraEnabled public List<Contact> records { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        
        /**
         * @description Constructs an empty ContactListResult.
         */
        public ContactListResult() {
            this.records = new List<Contact>();
            this.totalCount = 0;
        }
    }
}