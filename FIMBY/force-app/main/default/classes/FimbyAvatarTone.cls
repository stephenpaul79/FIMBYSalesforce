/**
 * Server-side twin of the c/fimbyAvatarTone LWC helper. Email avatars must land on
 * the same earth tone and initials a neighbour sees in the app, so the key format,
 * hash and palette order here must stay identical to the JavaScript version.
 */
public with sharing class FimbyAvatarTone {

    public static final List<String> TONE_HEX = new List<String>{
        '#476B4C', // sage
        '#7D6234', // ochre
        '#4E6878', // slate
        '#8A5936', // terracotta
        '#625A76', // dusty violet
        '#566744', // moss
        '#6B5E50'  // driftwood
    };

    private static final Long MODULUS = 2147483647L;
    private static final Pattern SALESFORCE_ID = Pattern.compile('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$');

    public static Integer toneIndex(String contactId, String organizationAccountId, String name, Boolean isOrganization) {
        String key = toneKey(contactId, organizationAccountId, name, isOrganization);
        Long hash = 0L;
        for (Integer i = 0; i < key.length(); i++) {
            hash = Math.mod(hash * 31L + key.charAt(i), MODULUS);
        }
        return Math.mod(hash, (Long) TONE_HEX.size()).intValue();
    }

    public static String toneHex(String contactId, String organizationAccountId, String name, Boolean isOrganization) {
        return TONE_HEX[toneIndex(contactId, organizationAccountId, name, isOrganization)];
    }

    public static String initials(String name) {
        String trimmed = name == null ? '' : name.trim();
        if (String.isBlank(trimmed)) {
            return '?';
        }
        List<String> words = trimmed.split('\\s+');
        String result = '';
        for (Integer i = 0; i < Math.min(2, words.size()); i++) {
            String word = words[i];
            if (String.isEmpty(word)) {
                continue;
            }
            Boolean isSurrogatePair = word.codePointAt(0) > 65535 && word.length() > 1;
            result += word.substring(0, isSurrogatePair ? 2 : 1);
        }
        return String.isEmpty(result) ? '?' : result.toUpperCase();
    }

    @TestVisible
    private static String toneKey(String contactId, String organizationAccountId, String name, Boolean isOrganization) {
        String contactKey = normalizeId(contactId);
        if (contactKey != null) {
            return 'contact:' + contactKey;
        }
        String accountKey = normalizeId(organizationAccountId);
        if (isOrganization == true && accountKey != null) {
            return 'account:' + accountKey;
        }
        String normalizedName = name == null ? '' : name.trim().replaceAll('\\s+', ' ').toLowerCase();
        return 'name:' + normalizedName;
    }

    private static String normalizeId(String value) {
        String trimmed = value == null ? '' : value.trim();
        if (String.isEmpty(trimmed) || !SALESFORCE_ID.matcher(trimmed).matches()) {
            return null;
        }
        return trimmed.substring(0, 15);
    }
}
