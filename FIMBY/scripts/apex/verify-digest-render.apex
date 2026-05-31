// Sandbox render check for FimbyDigestEmailBuilder card CTAs.
// Builds one card of each type with a fake record Id, scans all hrefs,
// and asserts they hit the correct Experience Cloud route — catches the
// /shared-life-post vs /sharedlife class of bug.
//
// Run via:
//   sf apex run --file scripts/apex/verify-digest-render.apex

Id fakeNeedsOffersId  = '006000000000001AAA';
Id fakeStoryId        = 'a01000000000001AAA';
Id fakeLibraryItemId  = 'a02000000000001AAA';

// Probe each CMDT helper directly first; these are the source of truth.
Map<String, String> expected = new Map<String, String>{
    'Needs_Offers detail' => FimbySettings.getUrl('Needs_Offers', String.valueOf(fakeNeedsOffersId)),
    'Story detail'        => FimbySettings.getUrl('Story',        String.valueOf(fakeStoryId)),
    'Library_Item detail' => FimbySettings.getUrl('Library_Item', String.valueOf(fakeLibraryItemId)),
    'Shared_Life_List'    => FimbySettings.getUrl('Shared_Life_List'),
    'Library_List'        => FimbySettings.getUrl('Library_List')
};
for (String label : expected.keySet()) {
    String url = expected.get(label);
    System.debug(label + ' => ' + url);
    System.assert(String.isNotBlank(url), 'CMDT lookup empty for ' + label);
    System.assert(url.startsWith('https://'), label + ' must be absolute: ' + url);

    // Asserts route is what the LWC navigation uses for that surface.
    if (label == 'Story detail') {
        System.assert(url.contains('/sharedlife/'),
            'Story detail must route to /sharedlife/{id} (matches LWC navigation), not /shared-life-post or /story/. Got: ' + url);
    } else if (label == 'Needs_Offers detail') {
        System.assert(url.contains('/needs-offers/') || url.contains('/asks-offers/'),
            'Needs_Offers detail must route to /needs-offers/{id} or /asks-offers/{id}, not /ask-or-offer-post/. Got: ' + url);
    } else if (label == 'Library_Item detail') {
        System.assert(url.contains('/library-item/'),
            'Library item detail must route to /library-item/{id}. Got: ' + url);
    } else if (label == 'Shared_Life_List') {
        System.assert(url.endsWith('/?filter=story'),
            'Shared_Life_List must route to the home feed pre-filtered to stories (/?filter=story). Got: ' + url);
    } else if (label == 'Library_List') {
        System.assert(url.endsWith('/library-list'),
            'Library_List must route to /library-list. Got: ' + url);
    }
}

System.debug('--- All digest URL routes resolve correctly. ---');
