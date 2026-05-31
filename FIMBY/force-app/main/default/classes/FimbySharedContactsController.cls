/**
 * @description Provides shared contact info list data for the fimbySharedContactsList LWC.
 * Community users must see all shared contact records regardless of OWD/sharing rules
 * so the directory functions correctly across accounts (without sharing).
 */
public without sharing class FimbySharedContactsController {

    /**
     * @description LWC-callable method that returns a paginated list of Shared_Contact_Info__c records with search and sorting.
     * @param searchTerm Search string for Contact name or Email
     * @param sortField Field to sort by (ContactName, SharedToName, etc.)
     * @param sortDirection 'ASC' or 'DESC'
     * @param pageSize Page size (max 50)
     * @param offset Pagination offset
     * @return SharedContactListResult with records and totalCount
     */
    @AuraEnabled(cacheable=true)
    public static SharedContactListResult getSharedContactsList(
        String searchTerm,
        String sortField,
        String sortDirection,
        Integer pageSize,
        Integer offset
    ) {
        SharedContactListResult result = new SharedContactListResult();
        
        Integer limitVal = (pageSize != null && pageSize > 0) ? Math.min(pageSize, 50) : 20;
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
        String sortDir = (sortDirection == 'DESC') ? 'DESC' : 'ASC';
        String sortFld = getSafeField(sortField);
        
        String query = 'SELECT Id, Name, Contact__c, Contact__r.Name, Email__c, Phone__c, ' +
                      'Address__c, Shared_To__c, Shared_To__r.Name, CreatedDate ' +
                      'FROM Shared_Contact_Info__c';
        String countQuery = 'SELECT COUNT() FROM Shared_Contact_Info__c';
        String whereClause = buildWhereClause(searchTerm);
        
        if (String.isNotBlank(whereClause)) {
            query += ' WHERE ' + whereClause;
            countQuery += ' WHERE ' + whereClause;
        }
        
        query += ' ORDER BY ' + sortFld + ' ' + sortDir + ' NULLS LAST';
        query += ' LIMIT ' + limitVal + ' OFFSET ' + offsetVal;
        
        result.totalCount = Database.countQuery(countQuery);
        result.records = Database.query(query);
        
        return result;
    }
    
    private static String buildWhereClause(String searchTerm) {
        List<String> conditions = new List<String>();
        
        if (String.isNotBlank(searchTerm)) {
            String safeSearch = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            conditions.add('(Contact__r.Name LIKE \'' + safeSearch + '\' OR Email__c LIKE \'' + safeSearch + '\')');
        }
        
        return String.join(conditions, ' AND ');
    }
    
    private static String getSafeField(String field) {
        if (field == 'ContactName') return 'Contact__r.Name';
        if (field == 'SharedToName') return 'Shared_To__r.Name';
        Set<String> allowed = new Set<String>{'Name','Email__c','Phone__c','CreatedDate'};
        return allowed.contains(field) ? field : 'CreatedDate';
    }

    /**
     * @description Wrapper for shared contact list API response with records and total count.
     */
    public class SharedContactListResult {
        @AuraEnabled public List<Shared_Contact_Info__c> records { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        
        /**
         * @description Constructs an empty SharedContactListResult.
         */
        public SharedContactListResult() {
            this.records = new List<Shared_Contact_Info__c>();
            this.totalCount = 0;
        }
    }
}