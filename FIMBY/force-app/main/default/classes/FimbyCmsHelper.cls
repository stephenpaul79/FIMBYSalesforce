/**
 * @description Retrieves CMS content via ConnectApi.ManagedContentDelivery for the current Experience Cloud site.
 * ConnectApi calls cannot execute in Apex test context — @TestVisible mock hooks are provided.
 */
public with sharing class FimbyCmsHelper {

    @TestVisible
    private static List<Map<String, String>> mockSlides = null;
    @TestVisible
    private static List<Map<String, Object>> mockRawBodies = null;

    private static final List<String> TEXT_FIELDS = new List<String>{
        'title', 'body', 'pageOrder', 'slideOrder', 'pageTitle', 'buttonLabel', 'buttonUrl'
    };

    /**
     * @description Fetches CMS slides for the given content type FQN, mapped to flattened string maps.
     * @param contentTypeFQN Fully qualified content type name
     * @return List of slide maps with title, body, heroImage, etc.
     */
    public static List<Map<String, String>> fetchSlides(String contentTypeFQN) {
        if (Test.isRunningTest() && mockSlides != null) {
            return mockSlides;
        }
        List<Map<String, Object>> rawBodies = getRawBodies(contentTypeFQN);
        List<Map<String, String>> slides = mapBodiesToSlides(rawBodies);
        sortSlides(slides);
        return slides;
    }

    private static List<Map<String, Object>> getRawBodies(String contentTypeFQN) {
        if (Test.isRunningTest() && mockRawBodies != null) {
            return mockRawBodies;
        }
        String siteId = Site.getSiteId();
        if (siteId == null) {
            return new List<Map<String, Object>>();
        }
        return queryContentBodies(siteId, contentTypeFQN);
    }

    private static List<Map<String, Object>> queryContentBodies(String sId, String fqn) {
        ConnectApi.ManagedContentDeliveryDocumentCollection resCol =
            ConnectApi.ManagedContentDelivery.getManagedContentsForSite(
                sId, null, null, fqn, UserInfo.getLanguage(),
                null, null, true, 0, true, false, null, 25, true);
        List<Map<String, Object>> bodies = new List<Map<String, Object>>();
        if (resCol == null || resCol.contents == null) { return bodies; }
        for (ConnectApi.AbstractManagedContentDeliveryDocument d : resCol.contents) {
            ConnectApi.ManagedContentDeliveryDocument doc = (ConnectApi.ManagedContentDeliveryDocument) d;
            Map<String, Object> body = (Map<String, Object>) ConnectApi.ConnectUtilities.unwrapApexWrapper(doc.contentBody);
            body.put('_contentKey', doc.contentKey);
            Object hero = body.get('heroImage');
            if (hero != null) {
                Map<String, Object> m = (Map<String, Object>) ConnectApi.ConnectUtilities.unwrapApexWrapper(hero);
                body.put('_heroImageUrl', extractMediaUrl(m));
            }
            bodies.add(body);
        }
        return bodies;
    }

    @TestVisible
    private static List<Map<String, String>> mapBodiesToSlides(List<Map<String, Object>> rawBodies) {
        List<Map<String, String>> slides = new List<Map<String, String>>();
        if (rawBodies == null || rawBodies.isEmpty()) {
            return slides;
        }
        for (Map<String, Object> body : rawBodies) {
            Map<String, String> slide = new Map<String, String>();
            slide.put('contentKey', body.containsKey('_contentKey') ? String.valueOf(body.get('_contentKey')) : '');
            for (String fieldName : TEXT_FIELDS) {
                slide.put(fieldName, extractText(body, fieldName));
            }
            if (body.containsKey('_heroImageUrl')) {
                slide.put('heroImage', String.valueOf(body.get('_heroImageUrl')));
            }
            slides.add(slide);
        }
        return slides;
    }

    @TestVisible
    private static void sortSlides(List<Map<String, String>> slides) {
        if (slides == null || slides.size() < 2) {
            return;
        }
        for (Integer i = 0; i < slides.size() - 1; i++) {
            for (Integer j = i + 1; j < slides.size(); j++) {
                String aPage = slides[i].containsKey('pageOrder') ? slides[i].get('pageOrder') : '999';
                String bPage = slides[j].containsKey('pageOrder') ? slides[j].get('pageOrder') : '999';
                Integer cmp = aPage.compareTo(bPage);
                if (cmp == 0) {
                    String aSlide = slides[i].containsKey('slideOrder') ? slides[i].get('slideOrder') : '999';
                    String bSlide = slides[j].containsKey('slideOrder') ? slides[j].get('slideOrder') : '999';
                    cmp = aSlide.compareTo(bSlide);
                }
                if (cmp > 0) {
                    Map<String, String> tmp = slides[i];
                    slides[i] = slides[j];
                    slides[j] = tmp;
                }
            }
        }
    }

    @TestVisible
    private static String extractText(Map<String, Object> body, String fieldName) {
        Object node = body.get(fieldName);
        if (node == null) {
            return '';
        }
        if (node instanceof String) {
            return (String) node;
        }
        try {
            Map<String, Object> nodeMap = (Map<String, Object>) node;
            return nodeMap.containsKey('value') ? String.valueOf(nodeMap.get('value')) : '';
        } catch (Exception e) {
            return String.valueOf(node);
        }
    }

    @TestVisible
    private static String extractMediaUrl(Map<String, Object> media) {
        if (media == null) {
            return '';
        }
        if (media.containsKey('url') && media.get('url') != null) {
            return String.valueOf(media.get('url'));
        }
        if (media.containsKey('unauthenticatedUrl') && media.get('unauthenticatedUrl') != null) {
            return String.valueOf(media.get('unauthenticatedUrl'));
        }
        return '';
    }
}
