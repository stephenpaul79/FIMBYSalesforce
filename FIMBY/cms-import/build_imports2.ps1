$basePath = "c:\Users\srathjen\FIMBY\FIMBY\cms-import"

function Write-JsonFile($path, $jsonString) {
    [System.IO.File]::WriteAllText($path, $jsonString, [System.Text.UTF8Encoding]::new($false))
}

function New-ContentItem($packDir, $folderName, $contentKey, $type, $title, $urlName, $contentBodyJson, $cmsFolder, $apiName) {
    $safeApiName = $apiName -replace '-', '_'

    $itemDir = Join-Path $packDir "$folderName\$contentKey"
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

    $metaJson = @"
{
  "apiName" : "$safeApiName",
  "path" : "$cmsFolder",
  "taxonomyTerms" : [ ]
}
"@
    Write-JsonFile (Join-Path $itemDir "_meta.json") $metaJson
}

# --- FAQ ITEMS ---
$faqPack = Join-Path $basePath "faq-pack"
Remove-Item $faqPack -Recurse -Force -ErrorAction SilentlyContinue

$faqFolder = "FIMBY FAQs"

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ001WHATISFIMBY00000000001" -type "fimby_faq_item" -title "What is FIMBY?" -urlName "what-is-fimby" -apiName "what-is-fimby" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "What is FIMBY?",
    "answer" : "<p>FIMBY (<strong>Family In My Backyard</strong>) is a neighbourhood platform that helps you connect with your neighbours through shared stories, asks and offers, a lending library, and direct messaging. It was built to make it easy for people living near each other to share life, lend a hand, and look out for one another.</p>",
    "sortOrder" : "010",
    "category" : "Getting Started"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ002UPDATEPROFILE000000002" -type "fimby_faq_item" -title "How do I update my profile?" -urlName "how-do-i-update-my-profile" -apiName "how-do-i-update-my-profile" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "How do I update my profile?",
    "answer" : "<p>Tap the <strong>menu icon</strong> in the top-right corner and select <strong>Profile</strong>. From there you can edit your name, photo, pronouns, bio, and care preferences. You can also update your profile at any time from the My Stuff tab.</p>",
    "sortOrder" : "020",
    "category" : "Getting Started"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ003ASKSANDOFFERS0000000003" -type "fimby_faq_item" -title "What are Asks and Offers?" -urlName "what-are-asks-and-offers" -apiName "what-are-asks-and-offers" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "What are Asks and Offers?",
    "answer" : "<p>Asks and Offers is a bulletin board where neighbours can post things they need (asks) or things they want to share (offers). This includes:</p><ul><li><strong>Goods</strong> - perishable and non-perishable items</li><li><strong>Services</strong> - free or paid help</li><li><strong>Events</strong> - neighbourhood gatherings and activities</li></ul><p>Browse what your neighbours have posted, or create your own listing from the Create button.</p>",
    "sortOrder" : "030",
    "category" : "Features"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ004LIBRARYWORKS00000000004" -type "fimby_faq_item" -title "How does the Library work?" -urlName "how-does-the-library-work" -apiName "how-does-the-library-work" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "How does the Library work?",
    "answer" : "<p>The Library lets you share items you are willing to lend to neighbours - tools, books, games, and more. You can:</p><ul><li><strong>Browse</strong> items available in your neighbourhood</li><li><strong>Add your own items</strong> for others to borrow</li><li><strong>Request to borrow</strong> something you need</li></ul><p>It is like a neighbourhood sharing shelf, managed right from the app.</p>",
    "sortOrder" : "040",
    "category" : "Features"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ005WHOCANSEE000000000005" -type "fimby_faq_item" -title "Who can see my profile and posts?" -urlName "who-can-see-my-profile-and-posts" -apiName "who-can-see-my-profile-and-posts" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "Who can see my profile and posts?",
    "answer" : "<p>Your profile and posts are visible only to <strong>other members in your neighbourhood</strong>. FIMBY is a private community - only registered neighbours can access the platform. Your information is never shared outside your neighbourhood group.</p>",
    "sortOrder" : "050",
    "category" : "Privacy"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ006NOTIFICATIONS0000000006" -type "fimby_faq_item" -title "How do I change my notification settings?" -urlName "how-do-i-change-my-notification-settings" -apiName "how-do-i-change-notification-settings" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "How do I change my notification settings?",
    "answer" : "<p>Go to <strong>Settings</strong> (via the menu in the top-right corner) and scroll to the <strong>Notifications</strong> section. You can toggle:</p><ul><li>Push notifications on or off</li><li>Email summary preferences</li><li>Which types of updates you want to receive (messages, stories, asks and offers, library items)</li></ul>",
    "sortOrder" : "060",
    "category" : "Account"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ007SENDMESSAGE000000000007" -type "fimby_faq_item" -title "How do I send a message to a neighbour?" -urlName "how-do-i-send-a-message" -apiName "how-do-i-send-a-message" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "How do I send a message to a neighbour?",
    "answer" : "<p>You can message any neighbour directly from their profile or from any post they have made. Tap their name or avatar, then select <strong>Message</strong>. All your conversations are in the <strong>Messages</strong> tab, accessible from the bottom navigation bar.</p>",
    "sortOrder" : "070",
    "category" : "Features"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ008WHATSTORIES0000000000008" -type "fimby_faq_item" -title "What are Stories?" -urlName "what-are-stories" -apiName "what-are-stories" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "What are Stories?",
    "answer" : "<p>Stories are short posts you share with your neighbourhood - updates, photos, thoughts, or things happening on your street. Think of it as a neighbourhood bulletin board where everyone can share what matters to them. Stories appear in the main feed for all neighbours to see and respond to.</p>",
    "sortOrder" : "080",
    "category" : "Features"
  }
'@

New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey "MCFAQ009REPORTPROBLEM000000009" -type "fimby_faq_item" -title "How do I report a problem or concern?" -urlName "how-do-i-report-a-problem" -apiName "how-do-i-report-a-problem" -cmsFolder $faqFolder -contentBodyJson @'
{
    "question" : "How do I report a problem or concern?",
    "answer" : "<p>If you see content that is inappropriate or experience an issue with the app, tap the <strong>three-dot menu</strong> on any post and select <strong>Report</strong>. For general app feedback or support, visit this Help page and use the contact options below. Our team reviews all reports promptly.</p>",
    "sortOrder" : "090",
    "category" : "Account"
  }
'@

Remove-Item "$basePath\fimby_faq_import.zip" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$faqPack\*" -DestinationPath "$basePath\fimby_faq_import.zip" -Force
Write-Host "Created fimby_faq_import.zip (9 FAQ items)"

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
Write-Host "`nSample content.json (FAQ #1):"
Get-Content "$faqPack\$faqFolder\MCFAQ001WHATISFIMBY00000000001\content.json"

# Cleanup export samples
Remove-Item "$basePath\export-sample" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$basePath\export-sample2" -Recurse -Force -ErrorAction SilentlyContinue
