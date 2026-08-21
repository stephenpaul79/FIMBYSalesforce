/**
 * @description Tests the shared predicates on FimbyConstants. The post-owner helpers
 *              guard the Needs_Offers__c field-semantics trap where Contact__c is the
 *              represented identity and Posted_By__c is the real author.
 */
@IsTest
private class FimbyConstantsTest {

    private static Id fakeContact(Integer seed) {
        return Id.valueOf('003000000000' + String.valueOf(seed).leftPad(3, '0') + 'AAA');
    }

    @IsTest
    static void postOwnerContactId_prefersRepresentedIdentity() {
        Id child = fakeContact(1);
        Id guardian = fakeContact(2);
        Needs_Offers__c post = new Needs_Offers__c(Contact__c = child, Posted_By__c = guardian);

        System.assertEquals(
            child,
            FimbyConstants.postOwnerContactId(post),
            'A post typed by a guardian belongs to the represented identity'
        );
    }

    @IsTest
    static void postOwnerContactId_fallsBackToRealAuthor() {
        Id author = fakeContact(3);
        Needs_Offers__c legacy = new Needs_Offers__c(Posted_By__c = author);

        System.assertEquals(
            author,
            FimbyConstants.postOwnerContactId(legacy),
            'Legacy rows with no Contact__c fall back to the author'
        );
    }

    @IsTest
    static void postOwnerContactId_nullPostReturnsNull() {
        System.assertEquals(null, FimbyConstants.postOwnerContactId(null), 'Null post yields null owner');
    }

    @IsTest
    static void isPostOwner_acceptsEitherPath() {
        Id child = fakeContact(4);
        Id guardian = fakeContact(5);
        Id stranger = fakeContact(6);
        Needs_Offers__c post = new Needs_Offers__c(Contact__c = child, Posted_By__c = guardian);

        System.assert(
            FimbyConstants.isPostOwner(post, guardian, guardian),
            'The guardian who typed it keeps access as themselves'
        );
        System.assert(
            FimbyConstants.isPostOwner(post, child, guardian),
            'The guardian acting as the child is still the poster'
        );
        System.assert(
            !FimbyConstants.isPostOwner(post, stranger, stranger),
            'An unrelated neighbour is not the poster'
        );
        System.assert(!FimbyConstants.isPostOwner(null, child, guardian), 'Null post is never owned');
    }

    @IsTest
    static void isSharingGatedConversationContext_coversDirectAndSkill() {
        System.assert(FimbyConstants.isSharingGatedConversationContext(null), 'Null context is gated');
        System.assert(FimbyConstants.isSharingGatedConversationContext(FimbyConstants.CTX_DIRECT), 'Direct is gated');
        System.assert(FimbyConstants.isSharingGatedConversationContext(FimbyConstants.CTX_SKILL), 'Skill is gated');
        System.assert(
            !FimbyConstants.isSharingGatedConversationContext(FimbyConstants.CTX_EVENT),
            'Contextual threads carry their own authorization'
        );
    }
}
