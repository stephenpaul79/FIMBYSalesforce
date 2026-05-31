/**
 * FimbyLoanedItemsController
 * Provides loaned items list data for the fimbyLoanedItemsList LWC component.
 */
public without sharing class FimbyLoanedItemsController {

    @AuraEnabled(cacheable=true)
    public static LoanedItemListResult getLoanedItemsList(
        String filterName,
        String searchTerm,
        String sortField,
        String sortDirection,
        Integer pageSize,
        Integer offset
    ) {
        LoanedItemListResult result = new LoanedItemListResult();
        
        Integer limitVal = (pageSize != null && pageSize > 0) ? Math.min(pageSize, 50) : 20;
        Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
        String sortDir = (sortDirection == 'DESC') ? 'DESC' : 'ASC';
        String sortFld = getSafeField(sortField);
        
        String query = 'SELECT Id, Name, List_Image__c, Library_Item__c, Library_Item__r.Name, ' +
                      'Loaned_To__c, Loaned_To__r.Name, Loan_Due_Date__c, Status__c, CreatedDate ' +
                      'FROM Loaned_Item__c';
        String countQuery = 'SELECT COUNT() FROM Loaned_Item__c';
        String whereClause = buildWhereClause(filterName, searchTerm);
        
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
    
    private static String buildWhereClause(String filterName, String searchTerm) {
        List<String> conditions = new List<String>();
        
        if (filterName == 'Active Loans') {
            conditions.add('Status__c = \'On Loan\'');
        } else if (filterName == 'Overdue') {
            conditions.add('Status__c = \'On Loan\'');
            conditions.add('Loan_Due_Date__c < TODAY');
        }
        
        if (String.isNotBlank(searchTerm)) {
            String safeSearch = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            conditions.add('(Name LIKE \'' + safeSearch + '\' OR Library_Item__r.Name LIKE \'' + safeSearch + '\')');
        }
        
        return String.join(conditions, ' AND ');
    }
    
    private static String getSafeField(String field) {
        if (field == 'LibraryItemName') return 'Library_Item__r.Name';
        if (field == 'LoanedToName') return 'Loaned_To__r.Name';
        Set<String> allowed = new Set<String>{'Name','Status__c','Loan_Due_Date__c','CreatedDate'};
        return allowed.contains(field) ? field : 'Name';
    }

    public class LoanedItemListResult {
        @AuraEnabled public List<Loaned_Item__c> records { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        
        public LoanedItemListResult() {
            this.records = new List<Loaned_Item__c>();
            this.totalCount = 0;
        }
    }
}