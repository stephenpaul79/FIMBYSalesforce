Account a = [SELECT Id, Name, Verification_Status__c, Is_Approved_Community_Group__c FROM Account WHERE Id = '001OL00000oKAfxYAG'];
System.debug('status=' + a.Verification_Status__c + ' approved=' + a.Is_Approved_Community_Group__c);
