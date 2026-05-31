# Custom Index Request Guide

## When to File

File a Salesforce Support case requesting custom indexes when:

- Any object in the table below crosses **~50K records**
- Error logs show `QUERY_TIMEOUT` or `NON_SELECTIVE_QUERY` exceptions
- Experience Cloud page loads exceed 3 seconds due to SOQL waits

Salesforce Support requires demonstrated need (query performance data, table sizes). This is not actionable at small data volumes.

## Indexes to Request

| Object                             | Field API Name               |
| ---------------------------------- | ---------------------------- |
| `Needs_Offers__c`                  | `Neighbourhood__c`           |
| `Response__c`                      | `Neighbourhood__c`           |
| `Response__c`                      | `Need_Offer_Responded_To__c` |
| `Story__c`                         | `Neighbourhood__c`           |
| `Library_Item__c`                  | `Neighbourhood__c`           |
| `Lending_Request__c`               | `Neighbourhood__c`           |
| `Lending_History__c`               | `Neighbourhood__c`           |
| `Loaned_Item__c`                   | `Neighbourhood__c`           |
| `Feedback__c`                      | `Neighbourhood__c`           |
| `Support_Relationship__c`          | `Neighbourhood__c`           |
| `Community_Group_Neighbourhood__c` | `Neighbourhood__c`           |
| `Neighbourhood_Health_Snapshot__c` | `Neighbourhood__c`           |
| `Bulk_Buy_Follow_Up__c`            | `Bulk_Buy__c`                |

## How to File

1. Open a Salesforce Support case (Help & Training portal)
2. Category: **Performance** > **Custom Index Request**
3. Provide:
   - Object API name and field API name from the table above
   - Current record count for that object
   - A sample SOQL query that uses the field in its WHERE clause
   - Evidence of slow performance (error logs, page load times)
4. Salesforce will evaluate and enable the index — no code deployment required

## Notes

- Standard lookup fields get auto-indexed, but custom indexes requested through Support are maintained more aggressively and work with non-selective filters
- These indexes have zero impact on existing functionality — they only improve query plan selection
- Request indexes incrementally as objects grow; no need to file all at once
