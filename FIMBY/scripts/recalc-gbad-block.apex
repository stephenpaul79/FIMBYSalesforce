FimbyBulkBuyController.recalculateBlockedFlagsForContacts(new Set<Id>{ '003OL00000bwBSSYA2' });
System.debug('blocked=' + [SELECT Is_Bulk_Buy_Blocked__c FROM Contact WHERE Id = '003OL00000bwBSSYA2'].Is_Bulk_Buy_Blocked__c);
