$basePath = "c:\Users\srathjen\FIMBY\FIMBY\cms-import"

function Write-JsonFile($path, $jsonString) {
    [System.IO.File]::WriteAllText($path, $jsonString, [System.Text.UTF8Encoding]::new($false))
}

function New-ContentItem($packDir, $folderName, $contentKey, $type, $title, $urlName, $contentBodyJson, $cmsFolder, $apiName) {
    $safeApiName = $apiName -replace '-', '_'

    # A contentKey is supplied ONLY for items that already exist in the workspace,
    # so the import matches and UPDATES them. Net-new items pass an empty
    # contentKey: we omit it from _meta.json (and name the folder by apiName) so
    # Salesforce auto-generates a key and CREATES the item. Inventing a key for a
    # new item but reusing an existing apiName triggers an "API name already
    # exists" collision that rolls back the entire atomic import.
    $hasKey = -not [string]::IsNullOrWhiteSpace($contentKey)
    $dirName = if ($hasKey) { $contentKey } else { $safeApiName }

    $itemDir = Join-Path $packDir "$folderName\$dirName"
    New-Item -ItemType Directory -Path $itemDir -Force | Out-Null

    $contentJson = @"
{
  "type" : "$type",
  "title" : "$title",
  "contentBody" : $contentBodyJson,
  "urlName" : "$urlName"
}
"@
    Write-JsonFile (Join-Path $itemDir "content.json") $contentJson

    if ($hasKey) {
        $metaJson = @"
{
  "contentKey" : "$contentKey",
  "apiName" : "$safeApiName",
  "path" : "$cmsFolder",
  "taxonomyTerms" : [ ]
}
"@
    } else {
        $metaJson = @"
{
  "apiName" : "$safeApiName",
  "path" : "$cmsFolder",
  "taxonomyTerms" : [ ]
}
"@
    }
    Write-JsonFile (Join-Path $itemDir "_meta.json") $metaJson
}

# --- FAQ ITEMS ---
$faqPack = Join-Path $basePath "faq-pack"
Remove-Item $faqPack -Recurse -Force -ErrorAction SilentlyContinue

$faqFolder = "FIMBY FAQs"

# Source of truth for the in-app Help & Support FAQ. Categories below drive the
# accordion grouping in fimbyHelpSupportPage. sortOrder values are 3-digit and
# the ranges encode category order (010-040 Getting Started, 100-160 Posting &
# Sharing, 200-230 Lending Library, 300-320 Messaging, 400-440 Trust & Safety,
# 500-520 Acting for Others, 600-630 Privacy & Account). Answers use a plain
# hyphen (never en/em dashes) and contain no raw double-quotes.
$faqItems = @(
    @{ key = "MCFAQ001WHATISFIMBY"; title = "What is FIMBY?"; url = "what-is-fimby"; ck = "MC4HKSM5CABJFX3GEIJ6Y5GOTJ4U"; api = "what_is_fimby"; body = @'
{
    "question" : "What is FIMBY?",
    "answer" : "<p>FIMBY (<strong>Family In My Backyard</strong>) is a private neighbourhood platform that helps you connect with the people who live closest to you. Share what's happening through Shared Life, post asks and offers, borrow and lend through the neighbourhood library, message neighbours directly, and look out for one another. Only registered neighbours in your neighbourhood can see your activity.</p>",
    "sortOrder" : "010",
    "category" : "Getting Started"
  }
'@ }
    @{ key = "MCFAQ002GETSTARTED"; title = "How do I get started?"; url = "how-do-i-get-started"; body = @'
{
    "question" : "How do I get started?",
    "answer" : "<p>The quickest way to find your way around is the tour - tap <strong>Take the Tour</strong> at the top of this Help page any time. To move around the app, use the bar along the bottom: <strong>Home</strong>, <strong>Library</strong>, <strong>Messages</strong>, and <strong>My Stuff</strong>. The <strong>+</strong> button in the middle is how you create a new post. The menu in the top-right corner holds your <strong>Profile</strong>, <strong>Settings</strong>, and <strong>Help</strong>, and the bell shows your notifications.</p>",
    "sortOrder" : "020",
    "category" : "Getting Started"
  }
'@ }
    @{ key = "MCFAQ003PROFILE"; title = "How do I update my profile?"; url = "how-do-i-update-my-profile"; ck = "MCCXIW7YVGKBCDLG56DUWYD7VCWY"; api = "how_do_i_update_my_profile"; body = @'
{
    "question" : "How do I update my profile?",
    "answer" : "<p>Tap the <strong>menu</strong> in the top-right corner and choose <strong>Profile</strong>. From there you can edit your name, photo, pronouns, bio, and care preferences. You can update your profile any time.</p>",
    "sortOrder" : "030",
    "category" : "Getting Started"
  }
'@ }
    @{ key = "MCFAQ004NEIGHBOURHOOD"; title = "What is my neighbourhood, and who can see what I share?"; url = "what-is-my-neighbourhood"; ck = "MCD4UWHPUXJJFRHDEAODRWFDP4MU"; api = "who_can_see_my_profile_and_posts"; body = @'
{
    "question" : "What is my neighbourhood, and who can see what I share?",
    "answer" : "<p>FIMBY is organised by neighbourhood, and your neighbourhood is your trust boundary. Your profile, posts, stories, and library items are visible only to other registered neighbours in your neighbourhood - never to the public or to people outside it. Your contact details stay private until you choose to share them.</p>",
    "sortOrder" : "040",
    "category" : "Getting Started"
  }
'@ }
    @{ key = "MCFAQ005ASKSOFFERS"; title = "What are Asks and Offers?"; url = "what-are-asks-and-offers"; ck = "MCEIKZ7KXUH5AFZCEPA3ENR7INPI"; api = "what_are_asks_and_offers"; body = @'
{
    "question" : "What are Asks and Offers?",
    "answer" : "<p>Asks and Offers is your neighbourhood bulletin board. Post something you need (an <strong>ask</strong>) or something you would like to share (an <strong>offer</strong>) - goods, a helping hand, or an invitation. To create one, tap the <strong>+</strong> button in the bottom bar and choose <strong>Make an Ask</strong> or <strong>Make an Offer</strong>. Browse what neighbours have posted from the Home feed and respond to anything that interests you.</p>",
    "sortOrder" : "100",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ006BULKBUY"; title = "What is a Bulk Buy?"; url = "what-is-a-bulk-buy"; body = @'
{
    "question" : "What is a Bulk Buy?",
    "answer" : "<p>A Bulk Buy is a shared purchase that a neighbour coordinates - buying something in bulk and splitting it into shares. To start one, tap the <strong>+</strong> button and choose <strong>Bulk Buy</strong>. To join one, open the bulk buy and tap <strong>Reserve A Share</strong>; the organiser will confirm pickup details. FIMBY does not handle payments - money and pickup are arranged between neighbours.</p>",
    "sortOrder" : "110",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ007EVENTS"; title = "What are Events, and what's the difference between the types?"; url = "what-are-events"; body = @'
{
    "question" : "What are Events, and what's the difference between the types?",
    "answer" : "<p>Events are posts for things happening in your neighbourhood. There are three kinds:</p><ul><li><strong>Gathering</strong> - a smaller hosted get-together with limited spots. You RSVP, and the host accepts guests until it is full.</li><li><strong>Open Event</strong> - everyone is welcome and there is no limit. Tap I'm Going to let the host know.</li><li><strong>Community Event</strong> - something a neighbour is sharing that someone else is running. Tap I'm Interested. It is a heads-up, not a commitment.</li></ul><p>To post an event, tap the <strong>+</strong> button and choose <strong>Post an Event</strong>.</p>",
    "sortOrder" : "120",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ008RSVP"; title = "How do I RSVP or join an event?"; url = "how-do-i-rsvp"; body = @'
{
    "question" : "How do I RSVP or join an event?",
    "answer" : "<p>Open the event and tap its button. For a <strong>Gathering</strong>, tap <strong>RSVP</strong>. For an <strong>Open Event</strong>, tap <strong>I'm Going</strong>. For a <strong>Community Event</strong>, tap <strong>I'm Interested</strong>. Only Gatherings have limited spots - Open and Community Events are always open and never fill up. You can change your mind any time by tapping the same button again.</p>",
    "sortOrder" : "130",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ009SHAREDLIFE"; title = "What is Shared Life?"; url = "what-is-shared-life"; ck = "MC6JPLV54PPVB6LK7252D2VC2MOY"; api = "what_are_stories"; body = @'
{
    "question" : "What is Shared Life?",
    "answer" : "<p>Shared Life is where neighbours share what's happening in their lives. Tap the <strong>+</strong> button and choose <strong>Share in Shared Life</strong>, then pick the kind of post:</p><ul><li><strong>Thank You</strong> - express gratitude to someone</li><li><strong>God Story</strong> - share a faith experience</li><li><strong>Prayer Request</strong> - ask for prayer and support</li><li><strong>Introduction</strong> - introduce yourself to neighbours</li><li><strong>Support Needed</strong> - share a struggle and seek comfort</li><li><strong>Neighbourhood Moment</strong> - share a moment you noticed</li></ul><p>Shared Life posts appear in the Home feed for neighbours to read and respond to.</p>",
    "sortOrder" : "140",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ010COMMENT"; title = "How do I comment on or respond to a post?"; url = "how-do-i-comment-or-respond"; body = @'
{
    "question" : "How do I comment on or respond to a post?",
    "answer" : "<p>It depends on the post. On a Shared Life post, tap the <strong>comment</strong> icon to add a comment - you can mention a neighbour with an @ symbol. On an ask, offer, or event, tap its button to respond or RSVP. Once you respond, a private thread opens where you and the other neighbour can sort out the details.</p>",
    "sortOrder" : "150",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ011EDITDELETE"; title = "How do I edit or delete something I posted?"; url = "how-do-i-edit-or-delete"; body = @'
{
    "question" : "How do I edit or delete something I posted?",
    "answer" : "<p>Open your post or Shared Life story and look for the menu in the page header - it shows <strong>Edit</strong>, <strong>Photo</strong>, and <strong>Delete</strong> as buttons on a wide screen, or under the three-dot menu on a phone. Edit changes the details, Photo adds or swaps an image, and Delete removes it. These options only appear on content you created.</p>",
    "sortOrder" : "160",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ key = "MCFAQ012LIBRARY"; title = "How does the Library work?"; url = "how-does-the-library-work"; ck = "MC6L2RZAQCABBB3NQYHGGQVGOPFI"; api = "how_does_the_library_work"; body = @'
{
    "question" : "How does the Library work?",
    "answer" : "<p>The Library is your neighbourhood's shared shelf. Open the <strong>Library</strong> tab to browse what neighbours are sharing - filter by <strong>All</strong>, <strong>Items</strong>, or <strong>Skills</strong>, and narrow by category. Borrow what you need and lend what you have. To add your own, tap <strong>Lend an Item</strong> or <strong>Offer a Skill</strong>. Borrowing from the library needs a vouch from a neighbour first - see vouching below.</p>",
    "sortOrder" : "200",
    "category" : "Lending Library"
  }
'@ }
    @{ key = "MCFAQ013BORROW"; title = "How do I borrow an item?"; url = "how-do-i-borrow-an-item"; body = @'
{
    "question" : "How do I borrow an item?",
    "answer" : "<p>Open the item and tap <strong>Borrow</strong>, then <strong>Submit Request</strong>. The owner reviews it and, once they approve, shares pickup details with you. When you have collected it, tap <strong>I Have the Item</strong>. You can use <strong>Message Owner</strong> any time to coordinate. When you are done, tap <strong>Return Item</strong>.</p>",
    "sortOrder" : "210",
    "category" : "Lending Library"
  }
'@ }
    @{ key = "MCFAQ014LEND"; title = "How do I lend my things and approve requests?"; url = "how-do-i-lend-and-approve"; body = @'
{
    "question" : "How do I lend my things and approve requests?",
    "answer" : "<p>Add something with <strong>Lend an Item</strong> from the Library. When a neighbour asks to borrow it, tap <strong>Review</strong> to see the request, then <strong>Approve &amp; Share</strong> to approve and share pickup details. When they collect it, tap <strong>Mark as Picked Up</strong>, and when it comes back, tap <strong>Verify Return &amp; Condition</strong>. You can also set an item to auto-accept requests if you would rather not review each one.</p>",
    "sortOrder" : "220",
    "category" : "Lending Library"
  }
'@ }
    @{ key = "MCFAQ015RETURN"; title = "How do I return an item or ask for more time?"; url = "how-do-i-return-or-extend"; body = @'
{
    "question" : "How do I return an item or ask for more time?",
    "answer" : "<p>To return something you borrowed, open the item (or its message thread) and tap <strong>Return Item</strong>, then confirm. If you need it longer, tap <strong>Request Extension</strong> and suggest a new date - the owner can approve or decline. Owners confirm returns with <strong>Verify Return &amp; Condition</strong>.</p>",
    "sortOrder" : "230",
    "category" : "Lending Library"
  }
'@ }
    @{ key = "MCFAQ016MESSAGE"; title = "How do I message a neighbour?"; url = "how-do-i-message-a-neighbour"; ck = "MC4XSGKHEYDZG77GTNBHPSFPJ6DI"; api = "how_do_i_send_a_message"; body = @'
{
    "question" : "How do I message a neighbour?",
    "answer" : "<p>Open the <strong>Messages</strong> tab and tap <strong>New</strong>, then search for a neighbour and pick them to start a conversation. You can also message someone from their profile or from a post they made. All your conversations live in the Messages tab.</p>",
    "sortOrder" : "300",
    "category" : "Messaging"
  }
'@ }
    @{ key = "MCFAQ017GROUPCHAT"; title = "Can I start a group chat?"; url = "can-i-start-a-group-chat"; body = @'
{
    "question" : "Can I start a group chat?",
    "answer" : "<p>Group chats are available for <strong>Open Events</strong>. If you are hosting an Open Event, open it and tap <strong>Create Event Chat</strong> to start a group conversation with everyone who is going. For everyone else, one-to-one messages work great - just start a conversation from the Messages tab.</p>",
    "sortOrder" : "310",
    "category" : "Messaging"
  }
'@ }
    @{ key = "MCFAQ018THANKS"; title = "How do I thank someone?"; url = "how-do-i-thank-someone"; body = @'
{
    "question" : "How do I thank someone?",
    "answer" : "<p>When a neighbour helps you through an ask, offer, or a lend, open the response and tap <strong>Say Thanks</strong>, then write a note and tap <strong>Send Thanks</strong>. Your thank-you appears as a little celebration right inside that conversation, and the neighbour gets a notification.</p>",
    "sortOrder" : "320",
    "category" : "Messaging"
  }
'@ }
    @{ key = "MCFAQ019VOUCHING"; title = "What is vouching, and why does it matter?"; url = "what-is-vouching"; body = @'
{
    "question" : "What is vouching, and why does it matter?",
    "answer" : "<p>Vouching is how neighbours welcome one another into the trusted circle. A vouch is personal - one neighbour, or a community group representative, saying they know you and you are good. A vouch is what opens the lending library for you. To ask for one, tap <strong>Request a vouch</strong> (you will see this when you visit the library before being vouched, or from your profile), choose a neighbour or community group, and send the request. You need to be acting as yourself to give or request a vouch.</p>",
    "sortOrder" : "400",
    "category" : "Trust & Safety"
  }
'@ }
    @{ key = "MCFAQ020REPORT"; title = "How do I report content or a concern?"; url = "how-do-i-report"; ck = "MCBZKSRMX7MREHZH3ZO4IG7EES6I"; api = "how_do_i_report_a_problem"; body = @'
{
    "question" : "How do I report content or a concern?",
    "answer" : "<p>If something does not feel right, open the <strong>three-dot menu</strong> on the post or message and choose <strong>Report</strong>. Your report is private and reviewed by your neighbourhood team, usually within 24 hours. For anything urgent or safety-related, use the <strong>Email Safety Team</strong> button on this page. Reporting is separate from blocking.</p>",
    "sortOrder" : "410",
    "category" : "Trust & Safety"
  }
'@ }
    @{ key = "MCFAQ021BLOCK"; title = "How do I block someone?"; url = "how-do-i-block-someone"; body = @'
{
    "question" : "How do I block someone?",
    "answer" : "<p>You can block a neighbour from their profile - open the <strong>three-dot menu</strong> and choose <strong>Block</strong> - or from <strong>Settings</strong> under <strong>Blocked Contacts</strong> by tapping <strong>Block someone</strong>. Blocking is mutual: neither of you will see each other's posts, messages, or profile. You can unblock from the same Blocked Contacts list any time.</p>",
    "sortOrder" : "420",
    "category" : "Trust & Safety"
  }
'@ }
    @{ key = "MCFAQ022MODERATOR"; title = "Who is my neighbourhood moderator?"; url = "who-is-my-moderator"; body = @'
{
    "question" : "Who is my neighbourhood moderator?",
    "answer" : "<p>Your moderator is a neighbour who helps keep your neighbourhood safe and welcoming. If your neighbourhood has one, you will see them on this Help page under <strong>Your Neighbourhood Moderator</strong>, with a <strong>Message Your Moderator</strong> button so you can reach out about anything affecting the community.</p>",
    "sortOrder" : "430",
    "category" : "Trust & Safety"
  }
'@ }
    @{ key = "MCFAQ023GUIDELINES"; title = "What are the community guidelines?"; url = "what-are-community-guidelines"; body = @'
{
    "question" : "What are the community guidelines?",
    "answer" : "<p>The community guidelines explain how we treat each other on FIMBY, what is not allowed, and how reports are handled. You can read them any time from the <strong>Community Guidelines &amp; Safety</strong> section on this Help page.</p>",
    "sortOrder" : "440",
    "category" : "Trust & Safety"
  }
'@ }
    @{ key = "MCFAQ024ONBEHALF"; title = "Can I post or respond on behalf of someone else?"; url = "can-i-post-on-behalf"; body = @'
{
    "question" : "Can I post or respond on behalf of someone else?",
    "answer" : "<p>Yes, if you support a neighbour or represent a community group. Once a support connection is approved, you can switch into that person's or group's identity and act for them. When you do, FIMBY shows a green <strong>Posting as</strong> banner so it is always clear who you are acting for. To set this up, open <strong>Manage identities</strong> from the top-right menu and tap <strong>Set Up Connection</strong>, then choose <strong>Support a neighbour</strong> or <strong>Represent a community group</strong>. A neighbourhood moderator reviews the request. Note that vouching always has to be done as yourself.</p>",
    "sortOrder" : "500",
    "category" : "Acting for Others"
  }
'@ }
    @{ key = "MCFAQ025SWITCHID"; title = "How do I switch who I'm acting as?"; url = "how-do-i-switch-identity"; body = @'
{
    "question" : "How do I switch who I'm acting as?",
    "answer" : "<p>Open the menu in the top-right corner. Under your identities you will see yourself and anyone you support or represent - tap one to switch into it. While you are acting as someone else, a small chip appears next to the FIMBY logo; tap it any time to switch back to yourself. You manage all of this from <strong>Manage identities</strong>.</p>",
    "sortOrder" : "510",
    "category" : "Acting for Others"
  }
'@ }
    @{ key = "MCFAQ026ORGPROFILE"; title = "What is a community group profile?"; url = "what-is-a-community-group-profile"; body = @'
{
    "question" : "What is a community group profile?",
    "answer" : "<p>A community group profile is a page for a local organisation - a church, charity, or group - that neighbours can view and message. If you represent an approved group, you can switch into it and edit its profile: logo, description, website, and contact details. Approved groups show a verified badge.</p>",
    "sortOrder" : "520",
    "category" : "Acting for Others"
  }
'@ }
    @{ key = "MCFAQ027CONTACTINFO"; title = "How do I share my contact info with a neighbour?"; url = "how-do-i-share-contact-info"; body = @'
{
    "question" : "How do I share my contact info with a neighbour?",
    "answer" : "<p>Your contact details stay private until you choose to share them. When you are in a response or conversation with a neighbour, use <strong>Share Contact Info</strong> and tick exactly what you want to share - <strong>Email</strong>, <strong>Phone</strong>, or <strong>Address</strong>. You will see a preview before it is sent. You can also turn on <strong>Auto-Share Contact Info</strong> when you create an ask or offer so it is shared automatically with whoever responds.</p>",
    "sortOrder" : "600",
    "category" : "Privacy & Account"
  }
'@ }
    @{ key = "MCFAQ028NOTIFICATIONS"; title = "How do I change my notification settings?"; url = "how-do-i-change-notifications"; ck = "MC6GMGNDZ4XVD4TGYOEWQEASKGBI"; api = "how_do_i_change_notification_settings"; body = @'
{
    "question" : "How do I change my notification settings?",
    "answer" : "<p>Open <strong>Settings</strong> from the top-right menu and go to <strong>Notifications and Email</strong>. You can turn <strong>Push Notifications</strong> and <strong>Email Alerts</strong> on or off, set <strong>Quiet Hours</strong> so alerts wait until a quiet window ends, choose which kinds of updates reach you by push or email, and pick how often you get the <strong>Neighbourhood Digest</strong>. Important account and safety messages always come through.</p>",
    "sortOrder" : "610",
    "category" : "Privacy & Account"
  }
'@ }
    @{ key = "MCFAQ029CAREPREFS"; title = "What are care preferences?"; url = "what-are-care-preferences"; body = @'
{
    "question" : "What are care preferences?",
    "answer" : "<p>Care preferences are an optional way to let neighbours know how best to support you. You can set them during onboarding and edit them any time from your <strong>Profile</strong>. They are always optional, and you choose what to share.</p>",
    "sortOrder" : "620",
    "category" : "Privacy & Account"
  }
'@ }
    @{ key = "MCFAQ030DELETEACCOUNT"; title = "How do I delete or deactivate my account?"; url = "how-do-i-delete-my-account"; body = @'
{
    "question" : "How do I delete or deactivate my account?",
    "answer" : "<p>Open <strong>Settings</strong> from the top-right menu and scroll to <strong>Delete account</strong>. Deleting deactivates your login right away. Your data is kept for 30 days so you can restore your account if you change your mind, then it is permanently removed. You can also choose to skip the 30-day window and delete immediately.</p>",
    "sortOrder" : "630",
    "category" : "Privacy & Account"
  }
'@ }
)

$updateCount = 0
$createCount = 0
foreach ($faq in $faqItems) {
    # Items carrying a real workspace contentKey ($faq.ck) UPDATE in place and keep
    # their existing apiName ($faq.api). Items without a ck are net-new: no key,
    # apiName derived from the url slug.
    $ck = if ($faq.ContainsKey('ck')) { $faq.ck } else { '' }
    $api = if ($faq.ContainsKey('api')) { $faq.api } else { $faq.url }
    if ([string]::IsNullOrWhiteSpace($ck)) { $createCount++ } else { $updateCount++ }
    New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey $ck -type "fimby_faq_item" -title $faq.title -urlName $faq.url -apiName $api -cmsFolder $faqFolder -contentBodyJson $faq.body
}

Remove-Item "$basePath\fimby_faq_import.zip" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$faqPack\*" -DestinationPath "$basePath\fimby_faq_import.zip" -Force
Write-Host "Created fimby_faq_import.zip ($($faqItems.Count) FAQ items: $updateCount update, $createCount create)"

# --- ONBOARDING SLIDES ---
$obPack = Join-Path $basePath "onboarding-pack"
Remove-Item $obPack -Recurse -Force -ErrorAction SilentlyContinue

$obFolder = "FIMBY Onboarding"

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB001WELCOME0000000000000001" -type "fimby_onboarding_slide" -title "Welcome to FIMBY!" -urlName "welcome-to-fimby" -apiName "welcome-to-fimby" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Welcome to FIMBY!",
    "body" : "<p>FIMBY (<strong>Family In My Backyard</strong>) connects you with the people who live closest to you. Share stories, lend a hand, borrow what you need, and build real relationships with your neighbours.</p><p>Let us show you around so you can get the most out of your neighbourhood community.</p>",
    "pageOrder" : "010",
    "slideOrder" : "010",
    "pageTitle" : "Welcome"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB002STORIES0000000000000002" -type "fimby_onboarding_slide" -title "Your Neighbourhood Feed" -urlName "stories-feed" -apiName "stories-feed" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Your Neighbourhood Feed",
    "body" : "<p>The <strong>Stories</strong> tab is your neighbourhood's heartbeat. Here you will find:</p><ul><li>Updates and photos from neighbours</li><li>Local happenings and announcements</li><li>Conversations about life on your street</li></ul><p>Share a story of your own - introduce yourself, post a photo, or ask a question!</p>",
    "pageOrder" : "020",
    "slideOrder" : "010",
    "pageTitle" : "Stories"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB003AANDO10000000000000003" -type "fimby_onboarding_slide" -title "Asks and Offers" -urlName "asks-and-offers-overview" -apiName "asks-and-offers-overview" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Asks and Offers",
    "body" : "<p>Need something? Have something to share? The <strong>Asks and Offers</strong> board makes it easy to exchange goods, services, and event invitations with your neighbours.</p>",
    "pageOrder" : "030",
    "slideOrder" : "010",
    "pageTitle" : "Asks and Offers"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB004AANDO20000000000000004" -type "fimby_onboarding_slide" -title "Share Goods" -urlName "asks-and-offers-goods" -apiName "asks-and-offers-goods" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Share Goods",
    "body" : "<p>Post perishable or non-perishable items you would like to give away or that you are looking for. From extra garden produce to household items - one person's extra is another's treasure.</p>",
    "pageOrder" : "030",
    "slideOrder" : "020",
    "pageTitle" : "Asks and Offers"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB005AANDO30000000000000005" -type "fimby_onboarding_slide" -title "Offer or Request Help" -urlName "asks-and-offers-services" -apiName "asks-and-offers-services" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Offer or Request Help",
    "body" : "<p>Whether it is help moving furniture, a ride to an appointment, or tutoring - post a service ask or offer and connect with neighbours who can help.</p>",
    "pageOrder" : "030",
    "slideOrder" : "030",
    "pageTitle" : "Asks and Offers"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB006LIBRARY0000000000000006" -type "fimby_onboarding_slide" -title "The Neighbourhood Library" -urlName "library-feature" -apiName "library-feature" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "The Neighbourhood Library",
    "body" : "<p>Why buy when you can borrow? The <strong>Library</strong> is a shared lending shelf for your neighbourhood.</p><ul><li>Browse items your neighbours are willing to lend</li><li>Add your own items - tools, books, games, kitchen gear</li><li>Request to borrow with a single tap</li></ul><p>It saves money, reduces waste, and gives you a reason to meet the people next door.</p>",
    "pageOrder" : "040",
    "slideOrder" : "010",
    "pageTitle" : "Library"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB007MESSAGES000000000000007" -type "fimby_onboarding_slide" -title "Direct Messages" -urlName "messaging-feature" -apiName "messaging-feature" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Direct Messages",
    "body" : "<p>Have a private conversation with any neighbour using <strong>Messages</strong>. Coordinate a borrow, follow up on an offer, or just say hello.</p><p>Your messages are private - only you and the other person can see them.</p>",
    "pageOrder" : "050",
    "slideOrder" : "010",
    "pageTitle" : "Messages"
  }
'@

New-ContentItem -packDir $obPack -folderName $obFolder -contentKey "MCOB008ALLSET00000000000000008" -type "fimby_onboarding_slide" -title "Your Profile and Settings" -urlName "your-profile-and-settings" -apiName "your-profile-and-settings" -cmsFolder $obFolder -contentBodyJson @'
{
    "title" : "Your Profile and Settings",
    "body" : "<p>Make FIMBY yours! From the menu you can:</p><ul><li>Update your <strong>profile</strong> - photo, bio, and care preferences</li><li>Adjust <strong>notification settings</strong> so you only hear about what matters to you</li><li>Visit <strong>Help and Support</strong> any time you need a hand</li></ul><p>You are all set! Go explore your neighbourhood.</p>",
    "pageOrder" : "060",
    "slideOrder" : "010",
    "pageTitle" : "You're All Set!",
    "buttonLabel" : "Explore FIMBY",
    "buttonUrl" : "/"
  }
'@

Remove-Item "$basePath\fimby_onboarding_import.zip" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$obPack\*" -DestinationPath "$basePath\fimby_onboarding_import.zip" -Force
Write-Host "Created fimby_onboarding_import.zip (8 slides)"

# Verify a sample file has raw HTML
$firstFaq = $faqItems[0]
$firstDir = if ($firstFaq.ContainsKey('ck') -and -not [string]::IsNullOrWhiteSpace($firstFaq.ck)) { $firstFaq.ck } else { ($firstFaq.url -replace '-', '_') }
Write-Host "`nSample content.json (first FAQ):"
Get-Content "$faqPack\$faqFolder\$firstDir\content.json"
Write-Host "`nSample _meta.json (first FAQ - should include contentKey):"
Get-Content "$faqPack\$faqFolder\$firstDir\_meta.json"

# Cleanup export samples
Remove-Item "$basePath\export-sample" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$basePath\export-sample2" -Recurse -Force -ErrorAction SilentlyContinue
