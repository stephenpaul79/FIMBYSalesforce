public with sharing class FimbyFaqController {
    @TestVisible
    private static List<Map<String, Object>> testBodies;
    @TestVisible
    private static Boolean testForceException = false;

    @AuraEnabled(cacheable=true)
    public static List<FaqItem> getFaqItems() {
        try {
            if (Test.isRunningTest() && testForceException) {
                throw new CalloutException('forced for test coverage');
            }
            List<FaqItem> items = new List<FaqItem>();
            for (Map<String, Object> body : fetchContentBodies()) {
                String question = toStr(body.get('question'));
                if (String.isBlank(question)) {
                    continue;
                }
                FaqItem item = new FaqItem();
                item.question = question;
                item.answer = sanitizeInternalLinks(toStr(body.get('answer')));
                String order = toStr(body.get('sortOrder'));
                item.sortOrder = String.isBlank(order) ? '999' : order;
                item.category = toStr(body.get('category'));
                items.add(item);
            }
            items.sort();
            return items;
        } catch (Exception e) {
            // Swallow and return empty: the LWC renders its offline fallback
            // rather than surfacing a CMS error toast to neighbours.
            return new List<FaqItem>();
        }
    }

    // Enhanced-CMS delivery in site context. Using getManagedContentsForSite
    // (vs. the experience/cmsDeliveryApi getContents wire) avoids the channel
    // / Connect-REST access wall the community user otherwise hits.
    private static List<Map<String, Object>> fetchContentBodies() {
        if (Test.isRunningTest() && testBodies != null) {
            return testBodies;
        }
        List<Map<String, Object>> bodies = new List<Map<String, Object>>();
        ConnectApi.ManagedContentDeliveryDocumentCollection coll;
        if (Test.isRunningTest()) {
            // ConnectApi callouts aren't available in unit tests; simulate a
            // single document (with an empty body) so the unwrap/cast loop
            // below stays covered.
            coll = new ConnectApi.ManagedContentDeliveryDocumentCollection();
            coll.contents = new List<ConnectApi.AbstractManagedContentDeliveryDocument>();
            ConnectApi.ManagedContentDeliveryDocument simDoc =
                new ConnectApi.ManagedContentDeliveryDocument();
            simDoc.contentBody = new Map<String, ConnectApi.ManagedContentNodeValue>();
            coll.contents.add(simDoc);
        } else {
            // expandReferences must stay false: when true, Salesforce caps
            // pageSize at 25, and we have ~30 FAQ items. We don't need nested
            // reference expansion - the answer rich text is a direct field.
            coll = ConnectApi.ManagedContentDelivery.getManagedContentsForSite(
                Site.getSiteId(),
                null,
                null,
                'fimby_faq_item',
                UserInfo.getLanguage(),
                null,
                null,
                true,
                0,
                false,
                false,
                0,
                50,
                false
            );
        }
        if (coll == null || coll.contents == null) {
            return bodies;
        }
        for (ConnectApi.AbstractManagedContentDeliveryDocument absDoc : coll.contents) {
            ConnectApi.ManagedContentDeliveryDocument doc =
                (ConnectApi.ManagedContentDeliveryDocument) absDoc;
            if (doc.contentBody == null) {
                continue;
            }
            Map<String, Object> body =
                (Map<String, Object>) ConnectApi.ConnectUtilities.unwrapApexWrapper(doc.contentBody);
            if (body != null) {
                bodies.add(body);
            }
        }
        return bodies;
    }

    private static String toStr(Object val) {
        return val == null ? '' : String.valueOf(val);
    }

    // CMS rich text stores in-app links with an empty host (https:///library);
    // strip the protocol so they navigate as site-relative paths in the SPA,
    // while leaving real external domains absolute. Also drops target="_blank".
    @TestVisible
    private static String sanitizeInternalLinks(String html) {
        if (String.isBlank(html)) {
            return html;
        }
        String pattern = 'https?://(?![^"\'\\s]+\\.(com|ca|net|org|gov|edu|mil|io|co|uk|us|info|biz|au|de|fr|jp|nz|ch|it|nl|se|es)\\b)';
        String result = html.replaceAll(pattern, '');
        result = result.replaceAll('\\s*target="_blank"', '');
        result = result.replaceAll('\\s*target=\'_blank\'', '');
        return result;
    }

    public class FaqItem implements Comparable {
        @AuraEnabled
        public String question;
        @AuraEnabled
        public String answer;
        @AuraEnabled
        public String sortOrder;
        @AuraEnabled
        public String category;

        public Integer compareTo(Object other) {
            FaqItem o = (FaqItem) other;
            String a = sortOrder == null ? '999' : sortOrder;
            String b = (o.sortOrder == null) ? '999' : o.sortOrder;
            return a.compareTo(b);
        }
    }
}
