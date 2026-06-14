@IsTest
private class FimbyFaqControllerTest {
    @IsTest
    static void mapsAndSortsItemsByOrder() {
        FimbyFaqController.testBodies = new List<Map<String, Object>>{
            new Map<String, Object>{
                'question' => 'Second question',
                'answer' => '<p>Body two</p>',
                'sortOrder' => '200',
                'category' => 'Messaging'
            },
            new Map<String, Object>{
                'question' => 'First question',
                'answer' => '<p>Body one</p>',
                'sortOrder' => '010',
                'category' => 'Getting Started'
            }
        };

        Test.startTest();
        List<FimbyFaqController.FaqItem> items = FimbyFaqController.getFaqItems();
        Test.stopTest();

        System.assertEquals(2, items.size(), 'Both items should map.');
        System.assertEquals('First question', items[0].question, 'Lowest sortOrder should be first.');
        System.assertEquals('Getting Started', items[0].category, 'Category should map.');
        System.assertEquals('Second question', items[1].question, 'Higher sortOrder should follow.');
    }

    @IsTest
    static void skipsBlankQuestionsAndDefaultsSortOrder() {
        FimbyFaqController.testBodies = new List<Map<String, Object>>{
            new Map<String, Object>{ 'question' => '', 'answer' => 'no question' },
            new Map<String, Object>{ 'question' => 'Has question', 'answer' => 'ok' }
        };

        List<FimbyFaqController.FaqItem> items = FimbyFaqController.getFaqItems();

        System.assertEquals(1, items.size(), 'Blank-question rows are skipped.');
        System.assertEquals('999', items[0].sortOrder, 'Missing sortOrder defaults to 999.');
        System.assertEquals('', items[0].category, 'Missing category becomes empty string.');
    }

    @IsTest
    static void stripsInternalLinksKeepsExternal() {
        String html =
            '<a href="https:///library-list" target="_blank">Library</a>' +
            '<a href=\'https:///messages\'>Messages</a>' +
            '<a href="https://www.fimby.com">FIMBY</a>';

        String result = FimbyFaqController.sanitizeInternalLinks(html);

        System.assert(result.contains('href="/library-list"'), 'Internal double-quoted link should be site-relative: ' + result);
        System.assert(result.contains('href=\'/messages\''), 'Internal single-quoted link should be site-relative: ' + result);
        System.assert(result.contains('https://www.fimby.com'), 'External link should stay absolute: ' + result);
        System.assert(!result.contains('target="_blank"'), 'target="_blank" should be removed: ' + result);
    }

    @IsTest
    static void blankHtmlIsReturnedUnchanged() {
        System.assertEquals(null, FimbyFaqController.sanitizeInternalLinks(null), 'Null passes through.');
        System.assertEquals('', FimbyFaqController.sanitizeInternalLinks(''), 'Empty passes through.');
    }

    @IsTest
    static void exceptionReturnsEmptyList() {
        FimbyFaqController.testForceException = true;

        List<FimbyFaqController.FaqItem> items = FimbyFaqController.getFaqItems();

        System.assertEquals(0, items.size(), 'Errors yield an empty list so the LWC shows its fallback.');
    }

    @IsTest
    static void noTestBodiesReturnsEmptyList() {
        List<FimbyFaqController.FaqItem> items = FimbyFaqController.getFaqItems();
        System.assertEquals(0, items.size(), 'No content yields an empty list.');
    }
}
