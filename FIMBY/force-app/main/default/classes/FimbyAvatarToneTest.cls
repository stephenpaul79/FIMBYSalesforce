@IsTest
private class FimbyAvatarToneTest {

    // Keep in sync with lwc/fimbyAvatarTone/__tests__/fimbyAvatarTone.test.js.
    @IsTest
    static void matchesJavaScriptFixtures() {
        System.assertEquals(3, FimbyAvatarTone.toneIndex('003OL00000tXhWNYA0', null, null, false), 'Amir 18-char');
        System.assertEquals(3, FimbyAvatarTone.toneIndex('003OL00000tXhWN', null, null, false), 'Amir 15-char');
        System.assertEquals(6, FimbyAvatarTone.toneIndex('003OL00000bwBSSYA2', null, null, false), 'Rosa');
        System.assertEquals(4, FimbyAvatarTone.toneIndex('003OL000011KH5uYAG', null, null, false), 'Maya');
        System.assertEquals(2, FimbyAvatarTone.toneIndex('003OL00000rBHooYAG', null, null, false), 'Sarah');
        System.assertEquals(1, FimbyAvatarTone.toneIndex('003OL00000xUb3OYAS', '001OL00000qGuI3YAK', 'The Life', true), 'Org contact wins');
        System.assertEquals(0, FimbyAvatarTone.toneIndex(null, '001OL00000qGuI3YAK', 'The Life', true), 'Org account fallback');
        System.assertEquals(6, FimbyAvatarTone.toneIndex(null, null, 'Sarah Chen', false), 'Name fallback');
    }

    @IsTest
    static void contactIdBeatsNameAndInvalidIdsFallBack() {
        System.assertEquals(6, FimbyAvatarTone.toneIndex('003OL00000bwBSSYA2', null, 'You', false), 'Never hashes You');
        System.assertEquals(6, FimbyAvatarTone.toneIndex('not-an-id', null, '  sarah   CHEN ', false), 'Invalid id uses normalized name');
        System.assertEquals('name:sarah chen', FimbyAvatarTone.toneKey('', null, ' Sarah  Chen ', false), 'Name key');
        System.assertEquals('name:the life', FimbyAvatarTone.toneKey(null, '001OL00000qGuI3YAK', 'The Life', false),
            'Account key only applies to organisations');
    }

    @IsTest
    static void toneHexUsesLightPalette() {
        System.assertEquals('#8A5936', FimbyAvatarTone.toneHex('003OL00000tXhWNYA0', null, null, false), 'Terracotta');
        System.assertEquals('#7D6234', FimbyAvatarTone.toneHex('003OL00000xUb3OYAS', null, null, true), 'Ochre');
        System.assertEquals(7, FimbyAvatarTone.TONE_HEX.size(), 'Seven earth tones');
    }

    @IsTest
    static void buildsInitials() {
        System.assertEquals('SC', FimbyAvatarTone.initials('Sarah Chen'), 'Two words');
        System.assertEquals('R', FimbyAvatarTone.initials('rosa'), 'One word');
        System.assertEquals('MA', FimbyAvatarTone.initials('Mary Anne Lee'), 'First two words');
        System.assertEquals('?', FimbyAvatarTone.initials('   '), 'Blank');
        System.assertEquals('?', FimbyAvatarTone.initials(null), 'Null');
        System.assertEquals('ÉÑ', FimbyAvatarTone.initials('élodie ñúñez'), 'Accents');
        System.assertEquals('OK', FimbyAvatarTone.initials('O\'Brien Kelly'), 'Apostrophe');
        System.assertEquals('陈美', FimbyAvatarTone.initials('陈 美'), 'CJK');
        System.assertEquals('𝒜𝒵', FimbyAvatarTone.initials('𝒜lex 𝒵ed'), 'Astral code points stay whole');
    }
}
