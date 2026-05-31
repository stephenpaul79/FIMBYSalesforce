/**
 * @description Visualforce backing controller for FimbyAuthorizedSupporterForm.page.
 * Reads the Support_Relationship__c by Id (URL param) and exposes the supporter,
 * supportee, and current TOS version/effective-date for the printable consent form.
 *
 * Modeled on Washington State DSHS 20-339. The form has three discrete consent
 * blocks (designation, data-sharing, TOS). Block C wording references the live
 * TOS version + effective date pulled from FIMBY_App_Settings__mdt at render
 * time, so the supporter cannot accidentally distribute a stale form.
 */
public with sharing class FimbyAuthorizedSupporterFormController {

    public Id srId { get; set; }
    public Support_Relationship__c sr { get; private set; }
    public Contact supporter { get; private set; }
    public Contact supportee { get; private set; }
    public String tosVersion { get; private set; }
    public Date tosEffectiveDate { get; private set; }
    public String renderedDate { get; private set; }
    public Boolean hasError { get; private set; }
    public String errorMessage { get; private set; }

    public FimbyAuthorizedSupporterFormController() {
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
            SELECT Id, Name, Status__c, Notes__c, Supportee_Relationship__c,
                   Contact__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                   Contact__r.MailingStreet, Contact__r.MailingCity, Contact__r.MailingPostalCode,
                   Contact__r.MailingState, Contact__r.Phone, Contact__r.Email,
                   Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.FirstName,
                   Related_Contact__r.LastName, Related_Contact__r.Birthdate,
                   Related_Contact__r.MailingStreet, Related_Contact__r.MailingCity,
                   Related_Contact__r.MailingPostalCode, Related_Contact__r.MailingState,
                   Related_Contact__r.Phone, Related_Contact__r.Email,
                   Neighbourhood__c, Neighbourhood__r.Name
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
        tosVersion = FimbySettings.tosCurrentVersion();
        tosEffectiveDate = FimbySettings.tosEffectiveDate();
    }

    public String getSupporterFullAddress() {
        return formatAddress(
            supporter?.MailingStreet, supporter?.MailingCity,
            supporter?.MailingState, supporter?.MailingPostalCode);
    }

    public String getSupporteeFullAddress() {
        return formatAddress(
            supportee?.MailingStreet, supportee?.MailingCity,
            supportee?.MailingState, supportee?.MailingPostalCode);
    }

    public String getTosEffectiveLabel() {
        return tosEffectiveDate == null ? '' : tosEffectiveDate.format();
    }

    public String getSupporteeBirthdateLabel() {
        return supportee?.Birthdate == null ? '' : supportee.Birthdate.format();
    }

    private String formatAddress(String street, String city, String state, String postal) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) parts.add(street);
        List<String> cityState = new List<String>();
        if (String.isNotBlank(city)) cityState.add(city);
        if (String.isNotBlank(state)) cityState.add(state);
        if (!cityState.isEmpty()) parts.add(String.join(cityState, ', '));
        if (String.isNotBlank(postal)) parts.add(postal);
        return String.join(parts, ' · ');
    }
}
