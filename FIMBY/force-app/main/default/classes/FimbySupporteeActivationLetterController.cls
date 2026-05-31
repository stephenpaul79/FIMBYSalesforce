/**
 * @description Visualforce backing controller for FimbySupporteeActivationLetter.page.
 * After a paper-form Support_Relationship__c is approved, an admin generates this
 * postal letter and mails it to the supportee. It is part of the multi-layer
 * anti-fraud / anti-coercion safety net: even if the supportee never used the
 * phone or email channels, they receive a physical letter at their address with
 * the FIMBY help phone/email and a reminder that they can revoke at any time.
 */
public with sharing class FimbySupporteeActivationLetterController {

    public Id srId { get; set; }
    public Support_Relationship__c sr { get; private set; }
    public Contact supporter { get; private set; }
    public Contact supportee { get; private set; }
    public String renderedDate { get; private set; }
    public Boolean hasError { get; private set; }
    public String errorMessage { get; private set; }

    public FimbySupporteeActivationLetterController() {
        hasError = false;
        renderedDate = Date.today().format();

        try {
            String paramId = ApexPages.currentPage().getParameters().get('id');
            if (String.isBlank(paramId)) paramId = ApexPages.currentPage().getParameters().get('srId');
            if (String.isBlank(paramId)) {
                hasError = true;
                errorMessage = 'No support relationship id provided.';
                return;
            }
            srId = Id.valueOf(paramId);
            loadAll();
        } catch (Exception e) {
            hasError = true;
            errorMessage = 'Could not load this support relationship: ' + e.getMessage();
        }
    }

    private void loadAll() {
        List<Support_Relationship__c> rels = [
            SELECT Id, Name, Status__c, Approved_Date__c,
                   Contact__c, Contact__r.Name,
                   Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.FirstName,
                   Related_Contact__r.LastName, Related_Contact__r.MailingStreet,
                   Related_Contact__r.MailingCity, Related_Contact__r.MailingState,
                   Related_Contact__r.MailingPostalCode,
                   Neighbourhood__r.Name
            FROM Support_Relationship__c
            WHERE Id = :srId
            LIMIT 1
        ];
        if (rels.isEmpty()) {
            hasError = true;
            errorMessage = 'Support relationship not found.';
            return;
        }
        sr = rels[0];
        supporter = sr.Contact__r;
        supportee = sr.Related_Contact__r;
    }

    public String getSupporteeAddressBlock() {
        List<String> lines = new List<String>();
        if (supportee == null) return '';
        if (String.isNotBlank(supportee.Name)) lines.add(supportee.Name);
        if (String.isNotBlank(supportee.MailingStreet)) lines.add(supportee.MailingStreet);
        List<String> cityState = new List<String>();
        if (String.isNotBlank(supportee.MailingCity)) cityState.add(supportee.MailingCity);
        if (String.isNotBlank(supportee.MailingState)) cityState.add(supportee.MailingState);
        if (String.isNotBlank(supportee.MailingPostalCode)) cityState.add(supportee.MailingPostalCode);
        if (!cityState.isEmpty()) lines.add(String.join(cityState, ', '));
        return String.join(lines, '\n');
    }

    public String getApprovedDateLabel() {
        return sr?.Approved_Date__c == null ? '' : sr.Approved_Date__c.date().format();
    }
}
