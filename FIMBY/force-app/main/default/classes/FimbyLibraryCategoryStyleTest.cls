@IsTest
private class FimbyLibraryCategoryStyleTest {

    @IsTest
    static void knownCategories_matchLibraryTabConfig() {
        System.assertEquals('tools.png', FimbyLibraryCategoryStyle.itemIcon('Tools'));
        System.assertEquals('#555048', FimbyLibraryCategoryStyle.itemColor('Tools'));
        System.assertEquals('sewing.png', FimbyLibraryCategoryStyle.skillIcon('Sewing & Mending'));
        System.assertEquals('#6A5278', FimbyLibraryCategoryStyle.skillColor('Sewing & Mending'));
    }

    @IsTest
    static void unknownOrBlankCategories_fallBack() {
        System.assertEquals('unknown.png', FimbyLibraryCategoryStyle.itemIcon(null));
        System.assertEquals('#736B5C', FimbyLibraryCategoryStyle.itemColor('Not A Category'));
        System.assertEquals('help.png', FimbyLibraryCategoryStyle.skillIcon(''));
        System.assertEquals('#736B5C', FimbyLibraryCategoryStyle.skillColor('Not A Category'));
    }
}
