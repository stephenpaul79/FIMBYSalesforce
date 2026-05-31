/**
 * @description Helpers for Shared_Contact_Info__c share semantics, including when
 *              a transactional email should fire on re-share.
 */
public with sharing class FimbySharedContactInfoHelper {

    /**
     * @description True when the after state adds email, phone, address, or additional info
     *              that was not previously shared.
     */
    public static Boolean hasExpandedContactShare(
        Shared_Contact_Info__c before,
        Shared_Contact_Info__c after
    ) {
        if (before == null || after == null) {
            return false;
        }
        if (!hadEmail(before) && hadEmail(after)) {
            return true;
        }
        if (!hadPhone(before) && hadPhone(after)) {
            return true;
        }
        if (!hadAddress(before) && hadAddress(after)) {
            return true;
        }
        if (!hadAdditional(before) && hadAdditional(after)) {
            return true;
        }
        return false;
    }

    /**
     * @description Lending approvals replace the shared field set each time.
     */
    public static Shared_Contact_Info__c buildAfterStateReplace(
        Shared_Contact_Info__c before,
        Boolean shareEmail,
        Boolean sharePhone,
        Boolean shareAddress,
        String email,
        String phone,
        String street,
        String city,
        String state,
        String postalCode,
        String country,
        String additionalInfo
    ) {
        Shared_Contact_Info__c after = cloneSnapshot(before);
        after.Email__c = shareEmail ? email : null;
        after.Phone__c = sharePhone ? phone : null;
        after.Street__c = shareAddress ? street : null;
        after.City__c = shareAddress ? city : null;
        after.Province_State__c = shareAddress ? state : null;
        after.Postal_Code__c = shareAddress ? postalCode : null;
        after.Country__c = shareAddress ? country : null;
        after.Additional_Info__c = shareAddress ? additionalInfo : null;
        return after;
    }

    /**
     * @description Response-thread shares only overwrite fields included in this action.
     */
    public static Shared_Contact_Info__c buildAfterStateMerge(
        Shared_Contact_Info__c before,
        Boolean shareEmail,
        Boolean sharePhone,
        Boolean shareAddress,
        String email,
        String phone,
        String street,
        String city,
        String state,
        String postalCode,
        String country,
        String additionalInfo
    ) {
        Shared_Contact_Info__c after = cloneSnapshot(before);
        if (shareEmail && String.isNotBlank(email)) {
            after.Email__c = email;
        }
        if (sharePhone && String.isNotBlank(phone)) {
            after.Phone__c = phone;
        }
        if (shareAddress) {
            after.Street__c = street;
            after.City__c = city;
            after.Province_State__c = state;
            after.Postal_Code__c = postalCode;
            after.Country__c = country;
            after.Additional_Info__c = additionalInfo;
        }
        return after;
    }

    private static Shared_Contact_Info__c cloneSnapshot(Shared_Contact_Info__c source) {
        if (source == null) {
            return new Shared_Contact_Info__c();
        }
        return source.clone(false, false, false, false);
    }

    private static Boolean hadEmail(Shared_Contact_Info__c sci) {
        return String.isNotBlank(sci.Email__c);
    }

    private static Boolean hadPhone(Shared_Contact_Info__c sci) {
        return String.isNotBlank(sci.Phone__c);
    }

    private static Boolean hadAddress(Shared_Contact_Info__c sci) {
        return String.isNotBlank(sci.Street__c)
            || String.isNotBlank(sci.City__c)
            || String.isNotBlank(sci.Province_State__c)
            || String.isNotBlank(sci.Postal_Code__c)
            || String.isNotBlank(sci.Country__c);
    }

    private static Boolean hadAdditional(Shared_Contact_Info__c sci) {
        return String.isNotBlank(sci.Additional_Info__c);
    }
}
