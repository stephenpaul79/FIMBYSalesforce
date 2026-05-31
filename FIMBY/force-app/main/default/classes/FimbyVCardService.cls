/**
 * @description Apex REST endpoint that serves a vCard (.vcf) file for shared contact info.
 * URL: /services/apexrest/fimby/vcard?contactId={ContactId}
 * The contactId param is the ID of the person who shared their info with the current user.
 * The endpoint verifies the caller is an authorised recipient before returning any data.
 * All vCard fields are sourced from Shared_Contact_Info__c — the Contact object is never exposed.
 */
@RestResource(urlMapping='/fimby/vcard/*')
global with sharing class FimbyVCardService {

    /**
     * @description REST GET handler that returns a vCard (.vcf) for shared contact info.
     * Expects contactId query param; verifies caller is an authorised recipient via Shared_Contact_Info__c.
     */
    @HttpGet
    global static void getVCard() {
        RestResponse res = RestContext.response;
        try {
        String contactId = RestContext.request.params.get('contactId');

        if (String.isBlank(contactId)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Missing contactId parameter');
            return;
        }

        String myContactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(myContactId)) {
            res.statusCode = 403;
            res.responseBody = Blob.valueOf('Unable to resolve current user');
            return;
        }

        Shared_Contact_Info__c sci = new VCardHelper().findSharedRecord(contactId, myContactId);
        if (sci == null) {
            res.statusCode = 404;
            res.responseBody = Blob.valueOf('No shared contact info found');
            return;
        }

        String crlf = '\r\n';
        String fn = safe(sci.First_Name__c);
        String ln = safe(sci.Last_Name__c);
        String fullName = (fn + ' ' + ln).trim();

        String v =
            'BEGIN:VCARD' + crlf +
            'VERSION:3.0' + crlf +
            'N:' + ln + ';' + fn + ';;;' + crlf +
            'FN:' + fullName + crlf;

        if (String.isNotBlank(sci.Email__c)) {
            v += 'EMAIL;TYPE=INTERNET:' + sci.Email__c + crlf;
        }
        if (String.isNotBlank(sci.Phone__c)) {
            v += 'TEL;TYPE=CELL:' + sci.Phone__c + crlf;
        }
        if (hasAddress(sci)) {
            // ADR: PO Box ; Extended ; Street ; City ; Region ; Postal ; Country
            v += 'ADR;TYPE=HOME:;;' +
                safe(sci.Street__c) + ';' +
                safe(sci.City__c) + ';' +
                safe(sci.Province_State__c) + ';' +
                safe(sci.Postal_Code__c) + ';' +
                safe(sci.Country__c) + crlf;
        }

        v += 'END:VCARD' + crlf;

        String fileName = String.isNotBlank(fullName) ?
            fullName.replaceAll('[^a-zA-Z0-9]', '_') + '.vcf' : 'contact.vcf';

        res.addHeader('Content-Type', 'text/vcard; charset=utf-8');
        res.addHeader('Content-Disposition', 'inline; filename="' + fileName + '"');
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(v);
        } catch (Exception e) {
            FimbyLogger.error('FimbyVCardService', 'getVCard', e);
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('Internal server error');
        }
    }

    private static String safe(String val) {
        return val == null ? '' : val.trim();
    }

    private static Boolean hasAddress(Shared_Contact_Info__c sci) {
        return String.isNotBlank(sci.Street__c) ||
               String.isNotBlank(sci.City__c) ||
               String.isNotBlank(sci.Province_State__c) ||
               String.isNotBlank(sci.Postal_Code__c);
    }

    /**
     * @description Without-sharing helper — Shared_Contact_Info__c has Private external OWD,
     * so community users need elevated access to read the record.
     */
    private without sharing class VCardHelper {
        /**
         * @description Finds Shared_Contact_Info__c where sharer shared to recipient and status is not Revoked.
         * @param sharerContactId Contact who shared (Contact__c)
         * @param recipientContactId Contact who received (Shared_To__c)
         * @return The Shared_Contact_Info__c record or null if none found
         */
        public Shared_Contact_Info__c findSharedRecord(String sharerContactId, String recipientContactId) {
            List<Shared_Contact_Info__c> records = [
                SELECT Id, First_Name__c, Last_Name__c,
                       Email__c, Phone__c,
                       Street__c, City__c, Province_State__c, Postal_Code__c, Country__c
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :sharerContactId
                  AND Shared_To__c = :recipientContactId
                  AND Status__c != 'Revoked'
                LIMIT 1
            ];
            return records.isEmpty() ? null : records[0];
        }
    }
}
