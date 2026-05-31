// Seed two more No_Follow_Through outcomes for Mobile Tester (G-bad), then recalc block flag.
Id mobileId = '003OL00000bwBSSYA2';
Id desktopId = '003OL00000pHdZEYA0';
Id nhId = '0015f00000DV5kUAAT';
Id bbRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();

for (Integer i = 1; i <= 2; i++) {
    Needs_Offers__c post = new Needs_Offers__c(
        RecordTypeId = bbRt,
        Name = 'QA-BB-GBAD-SEED-' + String.valueOf(i),
        Details__c = 'G-bad seed',
        Full_Details__c = 'G-bad seed',
        Status__c = 'Available',
        Posted_By__c = desktopId,
        Contact__c = desktopId,
        Neighbourhood__c = nhId,
        Giver_Recipient_Type__c = 'Self',
        Total_Quantity__c = 4,
        Owner_Shares__c = 0,
        Per_Response_Limit__c = 2,
        Allocation_Unit_Label__c = 'shares',
        Availability_Rule__c = 'Open_Until_Full_Or_Closed',
        Auto_Accept_Responses__c = true,
        Auto_Lock_Days__c = '7'
    );
    insert post;
    Response__c r = new Response__c(
        Need_Offer_Responded_To__c = post.Id,
        Contact__c = mobileId,
        On_Behalf_Of_Contact__c = mobileId,
        Amount_Requested__c = 1,
        Status__c = 'No_Follow_Through'
    );
    insert r;
}
FimbyBulkBuyController.recalculateBlockedFlagsForContacts(new Set<Id>{ mobileId });
System.debug('Is_Bulk_Buy_Blocked__c=' + [SELECT Is_Bulk_Buy_Blocked__c FROM Contact WHERE Id = :mobileId].Is_Bulk_Buy_Blocked__c);
