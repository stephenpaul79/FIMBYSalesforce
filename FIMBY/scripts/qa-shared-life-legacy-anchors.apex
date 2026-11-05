// Legacy Shared Life QA anchors in Testhood (run as system BEFORE Prayer/Lament/God Story are deactivated).
// Used to verify retired types still render and edit cleanly after the type rework.
Id testhood = '001OL00000q3enmYAA';
Id sarah = '003OL00000pHdZEYA0';

List<Story__c> anchors = new List<Story__c>{
    new Story__c(
        Name = 'QA-SL-LEGACY Prayer anchor',
        Message__c = 'QA anchor saved under the retired Prayer type.',
        Type__c = 'Prayer',
        Neighbourhood__c = testhood, Posted_By__c = sarah, Contact__c = sarah,
        Moderation_Status__c = 'Visible', Visibility_Scope__c = 'Neighbourhood'
    ),
    new Story__c(
        Name = 'QA-SL-LEGACY Lament anchor',
        Message__c = 'QA anchor saved under the retired Lament type.',
        Type__c = 'Lament',
        Neighbourhood__c = testhood, Posted_By__c = sarah, Contact__c = sarah,
        Moderation_Status__c = 'Visible', Visibility_Scope__c = 'Neighbourhood'
    ),
    new Story__c(
        Name = 'QA-SL-LEGACY God Story anchor',
        Message__c = 'QA anchor saved under the retired God Story type, opted in to social sharing.',
        Type__c = 'God Story',
        Share_on_Social_Media__c = true,
        Neighbourhood__c = testhood, Posted_By__c = sarah, Contact__c = sarah,
        Moderation_Status__c = 'Visible', Visibility_Scope__c = 'Neighbourhood'
    )
};
insert anchors;
for (Story__c s : anchors) {
    System.debug('LEGACY_ANCHOR ' + s.Type__c + '=' + s.Id);
}
