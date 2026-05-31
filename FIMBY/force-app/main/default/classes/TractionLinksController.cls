public with sharing class TractionLinksController {

    @AuraEnabled
    public static List<URL_Links__c> getLinks() {
        List<URL_Links__c> links = [SELECT Name, Link__c FROM URL_Links__c ORDER BY CreatedDate ASC];
        for (URL_Links__c url : links) {
            if (!url.Link__c.startsWith('https://')) {
                url.Link__c = 'https://' + url.Link__c;
            }
        }
        return links;
    }
}