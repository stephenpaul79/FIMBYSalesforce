@IsTest
private class FimbyCmsHelperTest {

    @IsTest
    static void testFetchSlidesNoSiteContext() {
        Test.startTest();
        List<Map<String, String>> slides = FimbyCmsHelper.fetchSlides('fimby_onboarding_slide');
        Test.stopTest();
        System.assertNotEquals(null, slides);
        System.assertEquals(0, slides.size());
    }

    @IsTest
    static void testFetchSlidesWithMockSlides() {
        FimbyCmsHelper.mockSlides = new List<Map<String, String>>{
            new Map<String, String>{ 'contentKey' => 'k1', 'title' => 'Welcome' }
        };
        Test.startTest();
        List<Map<String, String>> result = FimbyCmsHelper.fetchSlides('fimby_onboarding_slide');
        Test.stopTest();
        System.assertEquals(1, result.size());
        System.assertEquals('Welcome', result[0].get('title'));
        FimbyCmsHelper.mockSlides = null;
    }

    @IsTest
    static void testFetchSlidesEndToEndViaMockRawBodies() {
        FimbyCmsHelper.mockRawBodies = new List<Map<String, Object>>{
            new Map<String, Object>{
                '_contentKey' => 'ck-1', 'title' => 'Second', 'pageOrder' => '020', 'slideOrder' => '010'
            },
            new Map<String, Object>{
                '_contentKey' => 'ck-2', 'title' => 'First', 'pageOrder' => '010', 'slideOrder' => '010',
                '_heroImageUrl' => 'https://example.com/hero.png'
            }
        };
        Test.startTest();
        List<Map<String, String>> result = FimbyCmsHelper.fetchSlides('fimby_onboarding_slide');
        Test.stopTest();
        System.assertEquals(2, result.size());
        System.assertEquals('First', result[0].get('title'), 'Should be sorted by pageOrder');
        System.assertEquals('Second', result[1].get('title'));
        System.assertEquals('https://example.com/hero.png', result[0].get('heroImage'));
        FimbyCmsHelper.mockRawBodies = null;
    }

    @IsTest
    static void testMapBodiesToSlidesStringValues() {
        List<Map<String, Object>> bodies = new List<Map<String, Object>>{
            new Map<String, Object>{
                '_contentKey' => 'ck-1', 'title' => 'Hello', 'body' => '<p>World</p>',
                'pageOrder' => '010', 'slideOrder' => '010', 'pageTitle' => 'Intro',
                'buttonLabel' => 'Go', 'buttonUrl' => '/s/', '_heroImageUrl' => 'https://img.png'
            }
        };
        List<Map<String, String>> slides = FimbyCmsHelper.mapBodiesToSlides(bodies);
        System.assertEquals(1, slides.size());
        System.assertEquals('Hello', slides[0].get('title'));
        System.assertEquals('<p>World</p>', slides[0].get('body'));
        System.assertEquals('Go', slides[0].get('buttonLabel'));
        System.assertEquals('https://img.png', slides[0].get('heroImage'));
    }

    @IsTest
    static void testMapBodiesToSlidesMapValues() {
        List<Map<String, Object>> bodies = new List<Map<String, Object>>{
            new Map<String, Object>{
                '_contentKey' => 'ck-2',
                'title' => new Map<String, Object>{ 'value' => 'Map Title' },
                'body' => new Map<String, Object>{ 'value' => '<p>Map Body</p>' },
                'pageOrder' => new Map<String, Object>{ 'value' => '020' },
                'slideOrder' => new Map<String, Object>{ 'value' => '010' },
                'pageTitle' => new Map<String, Object>{ 'value' => 'Page' },
                'buttonLabel' => new Map<String, Object>{ 'value' => 'Click' },
                'buttonUrl' => new Map<String, Object>{ 'value' => '/s/feed' }
            }
        };
        List<Map<String, String>> slides = FimbyCmsHelper.mapBodiesToSlides(bodies);
        System.assertEquals('Map Title', slides[0].get('title'));
        System.assertEquals('020', slides[0].get('pageOrder'));
        System.assertEquals('Click', slides[0].get('buttonLabel'));
    }

    @IsTest
    static void testMapBodiesToSlidesNullAndEmpty() {
        System.assertEquals(0, FimbyCmsHelper.mapBodiesToSlides(null).size());
        System.assertEquals(0, FimbyCmsHelper.mapBodiesToSlides(new List<Map<String, Object>>()).size());
    }

    @IsTest
    static void testMapBodiesToSlidesMissingContentKey() {
        List<Map<String, Object>> bodies = new List<Map<String, Object>>{
            new Map<String, Object>{ 'title' => 'No Key' }
        };
        List<Map<String, String>> slides = FimbyCmsHelper.mapBodiesToSlides(bodies);
        System.assertEquals('', slides[0].get('contentKey'));
        System.assertEquals('No Key', slides[0].get('title'));
    }

    @IsTest
    static void testSortSlidesOrdering() {
        List<Map<String, String>> slides = new List<Map<String, String>>{
            new Map<String, String>{ 'title' => 'C', 'pageOrder' => '030', 'slideOrder' => '010' },
            new Map<String, String>{ 'title' => 'A', 'pageOrder' => '010', 'slideOrder' => '010' },
            new Map<String, String>{ 'title' => 'B', 'pageOrder' => '020', 'slideOrder' => '010' }
        };
        FimbyCmsHelper.sortSlides(slides);
        System.assertEquals('A', slides[0].get('title'));
        System.assertEquals('B', slides[1].get('title'));
        System.assertEquals('C', slides[2].get('title'));
    }

    @IsTest
    static void testSortSlidesSamePageDifferentSlide() {
        List<Map<String, String>> slides = new List<Map<String, String>>{
            new Map<String, String>{ 'title' => 'Second', 'pageOrder' => '010', 'slideOrder' => '020' },
            new Map<String, String>{ 'title' => 'First', 'pageOrder' => '010', 'slideOrder' => '010' }
        };
        FimbyCmsHelper.sortSlides(slides);
        System.assertEquals('First', slides[0].get('title'));
        System.assertEquals('Second', slides[1].get('title'));
    }

    @IsTest
    static void testSortSlidesNullAndSingle() {
        FimbyCmsHelper.sortSlides(null);
        List<Map<String, String>> single = new List<Map<String, String>>{
            new Map<String, String>{ 'title' => 'Only' }
        };
        FimbyCmsHelper.sortSlides(single);
        System.assertEquals('Only', single[0].get('title'));
    }

    @IsTest
    static void testExtractTextNull() {
        System.assertEquals('', FimbyCmsHelper.extractText(new Map<String, Object>(), 'missing'));
    }

    @IsTest
    static void testExtractTextString() {
        System.assertEquals('Hello', FimbyCmsHelper.extractText(
            new Map<String, Object>{ 'f' => 'Hello' }, 'f'));
    }

    @IsTest
    static void testExtractTextMapWithValue() {
        System.assertEquals('Val', FimbyCmsHelper.extractText(
            new Map<String, Object>{ 'f' => new Map<String, Object>{ 'value' => 'Val' } }, 'f'));
    }

    @IsTest
    static void testExtractTextMapWithoutValue() {
        System.assertEquals('', FimbyCmsHelper.extractText(
            new Map<String, Object>{ 'f' => new Map<String, Object>{ 'other' => 'x' } }, 'f'));
    }

    @IsTest
    static void testExtractTextNumericFallback() {
        System.assertEquals('42', FimbyCmsHelper.extractText(
            new Map<String, Object>{ 'f' => 42 }, 'f'));
    }

    @IsTest
    static void testExtractMediaUrlWithUrl() {
        System.assertEquals('https://img.png', FimbyCmsHelper.extractMediaUrl(
            new Map<String, Object>{ 'url' => 'https://img.png' }));
    }

    @IsTest
    static void testExtractMediaUrlWithUnauthenticated() {
        System.assertEquals('https://unauth.png', FimbyCmsHelper.extractMediaUrl(
            new Map<String, Object>{ 'unauthenticatedUrl' => 'https://unauth.png' }));
    }

    @IsTest
    static void testExtractMediaUrlNull() {
        System.assertEquals('', FimbyCmsHelper.extractMediaUrl(null));
    }

    @IsTest
    static void testExtractMediaUrlEmpty() {
        System.assertEquals('', FimbyCmsHelper.extractMediaUrl(new Map<String, Object>()));
    }
}
