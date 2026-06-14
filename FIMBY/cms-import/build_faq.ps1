$basePath = "c:\Users\srathjen\FIMBY\FIMBY\cms-import"

function Write-JsonFile($path, $jsonString) {
    [System.IO.File]::WriteAllText($path, $jsonString, [System.Text.UTF8Encoding]::new($false))
}

# Every FAQ item already exists in the CMS workspace, so we ALWAYS write the
# real contentKey + existing apiName: the import then UPDATES in place instead
# of colliding on the api name. Answers are raw HTML (plain hyphens, no en/em
# dashes, no double-quotes - use single quotes for href attributes so the JSON
# string stays valid). In-app links are root-relative paths; fimbyHelpSupportPage
# intercepts anchor clicks in the answer and soft-navigates.
function New-FaqItem($contentKey, $title, $urlName, $apiName, $contentBodyJson) {
    $faqFolder = "FIMBY FAQs"
    $itemDir = Join-Path $script:faqPack "$faqFolder\$contentKey"
    New-Item -ItemType Directory -Path $itemDir -Force | Out-Null

    $contentJson = @"
{
  "type" : "fimby_faq_item",
  "title" : "$title",
  "contentBody" : $contentBodyJson,
  "urlName" : "$urlName"
}
"@
    Write-JsonFile (Join-Path $itemDir "content.json") $contentJson

    $metaJson = @"
{
  "contentKey" : "$contentKey",
  "apiName" : "$apiName",
  "path" : "$faqFolder",
  "taxonomyTerms" : [ ]
}
"@
    Write-JsonFile (Join-Path $itemDir "_meta.json") $metaJson
}

$script:faqPack = Join-Path $basePath "faq-pack"
Remove-Item $script:faqPack -Recurse -Force -ErrorAction SilentlyContinue

$faqItems = @(
    @{ ck = "MC4HKSM5CABJFX3GEIJ6Y5GOTJ4U"; api = "what_is_fimby"; url = "finding-your-way-around"; title = "How do I find my way around the app?"; body = @'
{
    "question" : "How do I find my way around the app?",
    "answer" : "<p>Everything is reachable from two places. The bar along the bottom has four tabs:</p><ul><li><strong>Home</strong> - your neighbourhood feed of shared life, asks, offers, and events (<a href='/'>open Home</a>)</li><li><strong>Library</strong> - items and skills neighbours are lending (<a href='/library-list'>open the Library</a>)</li><li><strong>Messages</strong> - your conversations (<a href='/messages'>open Messages</a>)</li><li><strong>My Stuff</strong> - your posts, borrowing, contacts, and more (<a href='/my-stuff'>open My Stuff</a>)</li></ul><p>The round <strong>+</strong> button in the middle of the bar is how you create anything new. The menu in the top-right corner holds your <a href='/profile'>Profile</a>, <a href='/settings'>Settings</a>, and Help, and the bell opens your <a href='/notifications'>notifications</a>.</p>",
    "sortOrder" : "010",
    "category" : "Getting Started"
  }
'@ }
    @{ ck = "MCI3AKQJIPZJHNJMX3JB6EABJVRU"; api = "how_do_i_get_started"; url = "how-do-i-get-started"; title = "I am new here - where do I start?"; body = @'
{
    "question" : "I am new here - where do I start?",
    "answer" : "<p>Welcome! A lovely first step is to introduce yourself: tap the <strong>+</strong> button, choose <strong>Share in Shared Life</strong>, and pick <strong>Introduction</strong> so neighbours can say hello (<a href='/shared-life-post'>start an introduction</a>).</p><p>From there, <a href='/profile'>fill in your profile</a> so people recognise you, browse the <a href='/library-list'>Library</a> to see what neighbours are sharing, and check <a href='/'>Home</a> for asks and offers you can help with. You can replay the guided tour any time using the <strong>Take the Tour</strong> button at the top of this page.</p>",
    "sortOrder" : "020",
    "category" : "Getting Started"
  }
'@ }
    @{ ck = "MCCXIW7YVGKBCDLG56DUWYD7VCWY"; api = "how_do_i_update_my_profile"; url = "how-do-i-update-my-profile"; title = "How do I update my profile?"; body = @'
{
    "question" : "How do I update my profile?",
    "answer" : "<p>Open the top-right menu and choose <strong>Profile</strong>, or <a href='/profile'>go straight there</a>. Your profile is edited in sections - each one has a small pencil. Tap a pencil, make your changes, and tap <strong>Save</strong>. You can update:</p><ul><li>Your <strong>photo</strong>, <strong>name</strong>, and <strong>pronouns</strong></li><li><strong>Contact information</strong> (kept private until you choose to share it)</li><li><strong>About You</strong> - a few optional prompts that help neighbours get to know you</li><li><strong>Accessibility and availability</strong></li><li>Your <strong>care preferences</strong></li></ul>",
    "sortOrder" : "030",
    "category" : "Getting Started"
  }
'@ }
    @{ ck = "MCD4UWHPUXJJFRHDEAODRWFDP4MU"; api = "who_can_see_my_profile_and_posts"; url = "what-is-my-neighbourhood"; title = "What is my neighbourhood, and who can see what I share?"; body = @'
{
    "question" : "What is my neighbourhood, and who can see what I share?",
    "answer" : "<p>FIMBY is organised by neighbourhood, and your neighbourhood is your trust boundary. Your profile, posts, shared life, and library items are visible only to other registered neighbours in your neighbourhood - never to the public or to anyone outside it.</p><p>Your contact details (email, phone, address) stay private until you decide to <a href='/shared-contacts'>share them</a> with a specific neighbour. You are always in control of who sees them.</p>",
    "sortOrder" : "040",
    "category" : "Getting Started"
  }
'@ }
    @{ ck = "MCEIKZ7KXUH5AFZCEPA3ENR7INPI"; api = "what_are_asks_and_offers"; url = "what-are-asks-and-offers"; title = "What are Asks and Offers?"; body = @'
{
    "question" : "What are Asks and Offers?",
    "answer" : "<p>Asks and Offers is your neighbourhood bulletin board. Tap the <strong>+</strong> button and choose <strong>Make an Ask</strong> (something you need) or <strong>Make an Offer</strong> (something to share) - <a href='/ask-or-offer-post?type=Need'>start an ask</a> or <a href='/ask-or-offer-post?type=Offer'>start an offer</a>.</p><p>Give it a title and description, and optionally add photos. Browse what neighbours have posted on <a href='/'>Home</a>, open any post, and tap <strong>Respond</strong> to reply. Responding opens a private thread where the two of you sort out the details.</p>",
    "sortOrder" : "100",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MC2FRRRGTIQJEVHJKNTUXVE5R5MQ"; api = "what_is_a_bulk_buy"; url = "what-is-a-bulk-buy"; title = "What is a Bulk Buy?"; body = @'
{
    "question" : "What is a Bulk Buy?",
    "answer" : "<p>A Bulk Buy is a shared purchase a neighbour coordinates - buying something in bulk and splitting it into shares. To start one, tap the <strong>+</strong> button and choose <strong>Bulk Buy</strong> (<a href='/ask-or-offer-post?type=BulkBuy'>start a bulk buy</a>).</p><p>To join one, open the post and tap <strong>Reserve A Share</strong>. The organiser confirms pickup details and notifies everyone when it is ready to collect.</p><p>FIMBY helps neighbours coordinate - it does not handle payments, refunds, or money disputes. Those are arranged directly between neighbours.</p>",
    "sortOrder" : "110",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MCKSHHUQCLUVCH7NE3B5H5ZHEKTE"; api = "what_are_events"; url = "what-are-events"; title = "What are Events, and what is the difference between the types?"; body = @'
{
    "question" : "What are Events, and what is the difference between the types?",
    "answer" : "<p>Events are posts for things happening nearby. Tap the <strong>+</strong> button and choose <strong>Post an Event</strong> (<a href='/ask-or-offer-post?type=Event'>post an event</a>), then pick a type:</p><ul><li><strong>Gathering</strong> - a smaller hosted get-together with limited spots. Guests <strong>RSVP</strong> and the host accepts them until it is full.</li><li><strong>Open Event</strong> - everyone is welcome and there is no limit. Neighbours tap <strong>I'm Going</strong>.</li><li><strong>Community Event</strong> - something a neighbour is sharing that someone else is running. Neighbours tap <strong>I'm Interested</strong>.</li></ul><p>Only Gatherings have limited spots - Open and Community Events never fill up.</p>",
    "sortOrder" : "120",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MCNR77UQ5B4ZBZ7KD6P3ZQ3MAF7E"; api = "how_do_i_rsvp"; url = "how-do-i-rsvp"; title = "How do I RSVP or join an event?"; body = @'
{
    "question" : "How do I RSVP or join an event?",
    "answer" : "<p>Open the event on <a href='/'>Home</a> and tap its button:</p><ul><li><strong>Gathering</strong> - tap <strong>RSVP</strong>. The host accepts guests until the spots run out.</li><li><strong>Open Event</strong> - tap <strong>I'm Going</strong> (you can note any guests you are bringing).</li><li><strong>Community Event</strong> - tap <strong>I'm Interested</strong>.</li></ul><p>You can change your mind any time by tapping the same button again to withdraw. For an Open Event, the host can also start an event group chat for everyone going.</p>",
    "sortOrder" : "130",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MC6JPLV54PPVB6LK7252D2VC2MOY"; api = "what_are_stories"; url = "what-is-shared-life"; title = "What is Shared Life?"; body = @'
{
    "question" : "What is Shared Life?",
    "answer" : "<p>Shared Life is where neighbours share what is happening in their lives. Tap the <strong>+</strong> button and choose <strong>Share in Shared Life</strong> (<a href='/shared-life-post'>share something</a>), then pick a type:</p><ul><li><strong>Thank You</strong> - express gratitude to someone</li><li><strong>God Story</strong> - share a faith experience</li><li><strong>Prayer Request</strong> - ask for prayer and support</li><li><strong>Introduction</strong> - introduce yourself to neighbours</li><li><strong>Support Needed</strong> - share a struggle and seek comfort</li><li><strong>Neighbourhood Moment</strong> - share a moment you noticed</li></ul><p>Your post appears in the <a href='/'>Home</a> feed for neighbours to read and respond to.</p>",
    "sortOrder" : "140",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MC3WM4PWD2B5A2PBKQ7FAUGAFNWU"; api = "how_do_i_comment_or_respond"; url = "how-do-i-comment-or-respond"; title = "How do I comment on or respond to a post?"; body = @'
{
    "question" : "How do I comment on or respond to a post?",
    "answer" : "<p>It depends on the post:</p><ul><li>On a <strong>Shared Life</strong> post, tap <strong>Comment</strong> to leave a note. Type <strong>@</strong> to mention a neighbour by name.</li><li>On an <strong>ask</strong> or <strong>offer</strong>, tap <strong>Respond</strong>. This opens a private thread where you and the poster work out the details.</li><li>On an <strong>event</strong>, tap <strong>RSVP</strong>, <strong>I'm Going</strong>, or <strong>I'm Interested</strong> depending on the type.</li></ul><p>You will find replies to your own posts in <a href='/messages'>Messages</a> and on the post itself.</p>",
    "sortOrder" : "150",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MC56MGNVV4YBD2FLJGPGR64CYLFI"; api = "how_do_i_edit_or_delete"; url = "how-do-i-edit-or-delete"; title = "How do I edit or delete something I posted?"; body = @'
{
    "question" : "How do I edit or delete something I posted?",
    "answer" : "<p>Open your own post or Shared Life story. In the header you will see <strong>Edit</strong>, <strong>Photo</strong>, and <strong>Delete</strong> - as buttons on a wide screen, or tucked under the three-dot menu on a phone.</p><ul><li><strong>Edit</strong> changes the title and details</li><li><strong>Photo</strong> adds, swaps, or removes images</li><li><strong>Delete</strong> removes it for good</li></ul><p>These options only appear on content you created. You can review everything you have posted under <a href='/my-stuff'>My Stuff</a>.</p>",
    "sortOrder" : "160",
    "category" : "Posting & Sharing"
  }
'@ }
    @{ ck = "MC6L2RZAQCABBB3NQYHGGQVGOPFI"; api = "how_does_the_library_work"; url = "how-does-the-library-work"; title = "How does the Library work?"; body = @'
{
    "question" : "How does the Library work?",
    "answer" : "<p>The <a href='/library-list'>Library</a> is your neighbourhood's shared shelf. Use the <strong>All</strong>, <strong>Items</strong>, and <strong>Skills</strong> filters at the top to browse what neighbours are sharing, and the <strong>Filter</strong> dropdown to narrow by category.</p><p>To add your own, tap the <strong>+</strong> button and choose <strong>Add an Item / Skill</strong>, then pick <strong>Lend an Item</strong> or <strong>Offer a Skill</strong> (<a href='/library-item-post'>add to the Library</a>).</p><p>Borrowing opens up once a neighbour vouches for you - see <strong>What is vouching?</strong> below. Until then you can still browse and add your own items.</p>",
    "sortOrder" : "200",
    "category" : "Lending Library"
  }
'@ }
    @{ ck = "MCYANOPLLZWFDY3KZ2VMJNHRWHZU"; api = "how_do_i_borrow_an_item"; url = "how-do-i-borrow-an-item"; title = "How do I borrow an item?"; body = @'
{
    "question" : "How do I borrow an item?",
    "answer" : "<p>Open the item in the <a href='/library-list'>Library</a> and tap <strong>Borrow</strong>, then <strong>Submit Request</strong>. (If the item is currently out, you will see <strong>Join Waitlist</strong> instead.)</p><p>The owner reviews your request and, once they approve, shares pickup details with you. When you have collected it, tap <strong>I Have the Item</strong> then <strong>Confirm Pickup</strong>. Use <strong>Message Owner</strong> any time to coordinate, and tap <strong>Return Item</strong> when you are finished.</p><p>The first time you borrow, a neighbour needs to vouch for you - tap <strong>Request a vouch</strong> when prompted. Track what you have borrowed under <a href='/my-stuff/my-borrowing'>My Stuff</a>.</p>",
    "sortOrder" : "210",
    "category" : "Lending Library"
  }
'@ }
    @{ ck = "MCIX2ZYEB4PJBUDPOJ7KIN3CGEUA"; api = "how_do_i_lend_and_approve"; url = "how-do-i-lend-and-approve"; title = "How do I lend my things and approve requests?"; body = @'
{
    "question" : "How do I lend my things and approve requests?",
    "answer" : "<p>Tap the <strong>+</strong> button, choose <strong>Add an Item / Skill</strong>, then <strong>Lend an Item</strong> (<a href='/library-item-post'>add an item</a>). When a neighbour asks to borrow it:</p><ul><li>Tap <strong>Review</strong> to see the request</li><li>Tap <strong>Approve &amp; Share</strong> to approve and share pickup details</li><li>When they collect it, tap <strong>Mark as Picked Up</strong></li><li>When it comes back, tap <strong>Verify Return &amp; Condition</strong></li></ul><p>Prefer not to review each request? Turn on <strong>Auto-Accept Requests</strong> when you add or edit the item. Your items live under <a href='/my-stuff/my-library-items'>My Stuff</a>.</p>",
    "sortOrder" : "220",
    "category" : "Lending Library"
  }
'@ }
    @{ ck = "MCUCZT2DIXNBH5TG52LRPCILA3D4"; api = "how_do_i_return_or_extend"; url = "how-do-i-return-or-extend"; title = "How do I return an item or ask for more time?"; body = @'
{
    "question" : "How do I return an item or ask for more time?",
    "answer" : "<p>To return something you borrowed, open the item (or its message thread) and tap <strong>Return Item</strong>, then <strong>Confirm Return</strong>.</p><p>Need it longer? Tap <strong>Request Extension</strong> and suggest a new due date - the owner can approve or decline. Owners confirm returns with <strong>Verify Return &amp; Condition</strong> and can say yes to more time with <strong>Approve Extension</strong>.</p><p>Your current and past loans are under <a href='/my-stuff/my-borrowing'>My Stuff</a>.</p>",
    "sortOrder" : "230",
    "category" : "Lending Library"
  }
'@ }
    @{ ck = "MC4XSGKHEYDZG77GTNBHPSFPJ6DI"; api = "how_do_i_send_a_message"; url = "how-do-i-message-a-neighbour"; title = "How do I message a neighbour?"; body = @'
{
    "question" : "How do I message a neighbour?",
    "answer" : "<p>Open <a href='/messages'>Messages</a> and tap <strong>New</strong> to search for someone and start a conversation. You can also tap <strong>Message</strong> on a neighbour's profile.</p><p>To keep everyone safe, you can message neighbours you have <strong>shared contact info</strong> with (in either direction), plus community groups in your neighbourhood. If you have not connected yet, share your details first - see <strong>How do I share my contact info?</strong> below.</p>",
    "sortOrder" : "300",
    "category" : "Messaging"
  }
'@ }
    @{ ck = "MCAFHHCEXBURHMVN3VCAYBEECICM"; api = "can_i_start_a_group_chat"; url = "can-i-start-a-group-chat"; title = "Can I start a group chat?"; body = @'
{
    "question" : "Can I start a group chat?",
    "answer" : "<p>Group chats are available for <strong>Open Events</strong>. If you are hosting one, open your event and choose <strong>Create Event Chat</strong> from the menu to start a group conversation with everyone going; after that it shows as <strong>Event Chat</strong>.</p><p>For everything else, one-to-one messages work great - start one from <a href='/messages'>Messages</a>.</p>",
    "sortOrder" : "310",
    "category" : "Messaging"
  }
'@ }
    @{ ck = "MCONDJR5CC4ZFAFFEZJ6JXSA6IOU"; api = "how_do_i_thank_someone"; url = "how-do-i-thank-someone"; title = "How do I thank someone?"; body = @'
{
    "question" : "How do I thank someone?",
    "answer" : "<p>When a neighbour helps you through an ask, offer, or a lend, open that response and tap <strong>Say Thanks</strong>, write a short note, and tap <strong>Send Thanks</strong>.</p><p>Your thank-you appears as a little celebration right inside the conversation, and the neighbour gets a notification. You will find your responses in <a href='/messages'>Messages</a>.</p>",
    "sortOrder" : "320",
    "category" : "Messaging"
  }
'@ }
    @{ ck = "MCKSD7A3TN5NEM7E57G4UAIXPWTE"; api = "what_is_vouching"; url = "what-is-vouching"; title = "What is vouching, and why does it matter?"; body = @'
{
    "question" : "What is vouching, and why does it matter?",
    "answer" : "<p>Vouching is how neighbours welcome one another into the trusted circle. A vouch is personal - one neighbour, or a community group representative, saying they know you and you belong here. A vouch is what opens the <a href='/library-list'>lending library</a> for you.</p><p>To ask for one, tap <strong>Request a vouch</strong> - you will see this on your <a href='/profile'>profile</a> and in the Library before you are vouched. Choose a <strong>Neighbour</strong> or a <strong>Community group</strong> and send the request; they can approve or decline privately.</p><p>You need to be acting as yourself to give or request a vouch.</p>",
    "sortOrder" : "400",
    "category" : "Trust & Safety"
  }
'@ }
    @{ ck = "MCBZKSRMX7MREHZH3ZO4IG7EES6I"; api = "how_do_i_report_a_problem"; url = "how-do-i-report"; title = "How do I report content or a concern?"; body = @'
{
    "question" : "How do I report content or a concern?",
    "answer" : "<p>If something does not feel right, open the <strong>three-dot menu</strong> on the post or message and choose <strong>Report</strong>. Pick a reason and add a note if you like.</p><p>Your report is private - the person is never told who flagged it - and a moderator reviews it within 24 hours. Reporting is separate from blocking. For anything urgent or safety-related, email <a href='mailto:safety@fimby.ca'>safety@fimby.ca</a>, and you can always read the <a href='/community-guidelines'>community guidelines</a>.</p>",
    "sortOrder" : "410",
    "category" : "Trust & Safety"
  }
'@ }
    @{ ck = "MCQ6IWF26C5FB2FHG3PS6EU5JWBQ"; api = "how_do_i_block_someone"; url = "how-do-i-block-someone"; title = "How do I block someone?"; body = @'
{
    "question" : "How do I block someone?",
    "answer" : "<p>You can block a neighbour from their <strong>profile</strong> - open the three-dot menu and choose <strong>Block</strong> - or from a conversation using <strong>Block or report</strong>. You can also go to <a href='/settings'>Settings</a>, open <strong>Blocked Contacts</strong>, and tap <strong>Block someone</strong>.</p><p>Blocking is mutual: neither of you will see each other's posts, messages, or profile. You can <strong>Unblock</strong> from the same Blocked Contacts list any time. You need to be acting as yourself to block or unblock.</p>",
    "sortOrder" : "420",
    "category" : "Trust & Safety"
  }
'@ }
    @{ ck = "MCZPZJDUWSXRANJGPLJN322VIE2A"; api = "who_is_my_moderator"; url = "who-is-my-moderator"; title = "Who is my neighbourhood moderator?"; body = @'
{
    "question" : "Who is my neighbourhood moderator?",
    "answer" : "<p>Your moderator is a neighbour who helps keep your neighbourhood safe and welcoming. They review reports and lend a hand with things that affect the community.</p><p>If your neighbourhood has one, you will see them on this Help page under <strong>Your Neighbourhood Moderator</strong>, with a <strong>Message Your Moderator</strong> button so you can reach out.</p>",
    "sortOrder" : "430",
    "category" : "Trust & Safety"
  }
'@ }
    @{ ck = "MCEHGBTCQS6RAILEUWAVLHUH2DSE"; api = "what_are_community_guidelines"; url = "what-are-community-guidelines"; title = "What are the community guidelines?"; body = @'
{
    "question" : "What are the community guidelines?",
    "answer" : "<p>The community guidelines explain how we treat each other on FIMBY, what is not allowed, and how reports are handled. They are worth a quick read so everyone knows what to expect.</p><p>Open them any time from the <strong>Community Guidelines &amp; Safety</strong> section on this page, or <a href='/community-guidelines'>read them here</a>.</p>",
    "sortOrder" : "440",
    "category" : "Trust & Safety"
  }
'@ }
    @{ ck = "MCEHQCVVEYS5EEZF63ZDPKGVYGEQ"; api = "can_i_post_on_behalf"; url = "can-i-post-on-behalf"; title = "Can I post or respond on behalf of someone else?"; body = @'
{
    "question" : "Can I post or respond on behalf of someone else?",
    "answer" : "<p>Yes, if you support a neighbour or represent a community group. Once a support connection is approved, you can switch into that person's or group's identity and act for them. Whenever you do, FIMBY shows a green <strong>Posting as</strong> banner so it is always clear who you are acting for.</p><p>To set this up, open <a href='/manage-identities'>Manage identities</a> from the top-right menu and tap <strong>New</strong>, then choose <strong>Support a neighbour</strong> or <strong>Represent a community group</strong>. A neighbourhood moderator reviews the request before it goes live. Vouching always has to be done as yourself.</p>",
    "sortOrder" : "500",
    "category" : "Acting for Others"
  }
'@ }
    @{ ck = "MCKGNHAAVKDNFVRO5CX7BE4WH7G4"; api = "how_do_i_switch_identity"; url = "how-do-i-switch-identity"; title = "How do I switch who I am acting as?"; body = @'
{
    "question" : "How do I switch who I am acting as?",
    "answer" : "<p>Open the menu in the top-right corner. Near the top you will see yourself and anyone you support or represent - tap one to switch into it.</p><p>While you are acting as someone else, a small chip with their name appears next to the FIMBY logo. Tap it any time to switch back to yourself. You manage all of your connections from <a href='/manage-identities'>Manage identities</a>.</p>",
    "sortOrder" : "510",
    "category" : "Acting for Others"
  }
'@ }
    @{ ck = "MCR2MCLDUN45C53JLUBFIX4BCW5I"; api = "what_is_a_community_group_profile"; url = "what-is-a-community-group-profile"; title = "What is a community group profile?"; body = @'
{
    "question" : "What is a community group profile?",
    "answer" : "<p>A community group profile is a page for a local organisation - a church, charity, or group - that neighbours can view and message. Approved groups show a verified badge.</p><p>If you represent an approved group, you can switch into it and edit its profile: logo, description, website, and contact details. Set up your connection from <a href='/manage-identities'>Manage identities</a>.</p>",
    "sortOrder" : "520",
    "category" : "Acting for Others"
  }
'@ }
    @{ ck = "MCNYYLKGDNYFESBEECFHKEUA3YVM"; api = "how_do_i_share_contact_info"; url = "how-do-i-share-contact-info"; title = "How do I share my contact info with a neighbour?"; body = @'
{
    "question" : "How do I share my contact info with a neighbour?",
    "answer" : "<p>Your email, phone, and address stay private until you choose to share them - and sharing is what lets the two of you message each other.</p><p>In a response or conversation, tap <strong>Share Contact Info</strong> and tick exactly what you want to share: <strong>Email</strong>, <strong>Phone</strong>, or <strong>Address</strong>. You will see the details before they are sent. You can also turn on <strong>Auto-Share Contact Info</strong> when you create an ask or offer so it is shared automatically with whoever responds.</p><p>See who you are connected with under <a href='/shared-contacts'>Shared Contacts</a>.</p>",
    "sortOrder" : "600",
    "category" : "Privacy & Account"
  }
'@ }
    @{ ck = "MC6GMGNDZ4XVD4TGYOEWQEASKGBI"; api = "how_do_i_change_notification_settings"; url = "how-do-i-change-notifications"; title = "How do I change my notification settings?"; body = @'
{
    "question" : "How do I change my notification settings?",
    "answer" : "<p>Open <a href='/settings'>Settings</a> from the top-right menu and go to <strong>Notifications &amp; Email</strong>. You can:</p><ul><li>Turn <strong>Push Notifications</strong> and <strong>Email Alerts</strong> on or off</li><li>Set <strong>Quiet Hours</strong> so alerts wait until a quiet window ends</li><li>Choose which categories reach you by push or email - Messages, Asks &amp; Offers, Events, Library, Shared Life, Reminders, and Bulk Buys</li><li>Pick how often you get the <strong>Neighbourhood Digest</strong> (Daily, Weekly, or Never)</li></ul><p>Important account and safety messages always come through.</p>",
    "sortOrder" : "610",
    "category" : "Privacy & Account"
  }
'@ }
    @{ ck = "MCZKBIVZG6RBAM7JVYHJJIYLI5Q4"; api = "what_are_care_preferences"; url = "what-are-care-preferences"; title = "What are care preferences?"; body = @'
{
    "question" : "What are care preferences?",
    "answer" : "<p>Care preferences are an optional way to let neighbours know how best to support you - what kind of help tends to be welcome, how you would like someone to reach out, and anything that can feel like too much.</p><p>You can set them during onboarding and edit them any time in your <a href='/profile'>profile</a>. They are always optional, kept off your profile by default, and you choose exactly what to share.</p>",
    "sortOrder" : "620",
    "category" : "Privacy & Account"
  }
'@ }
    @{ ck = "MCV3S6TUCGMJEATF3U5O2UKG36OU"; api = "how_do_i_delete_my_account"; url = "how-do-i-delete-my-account"; title = "How do I delete or deactivate my account?"; body = @'
{
    "question" : "How do I delete or deactivate my account?",
    "answer" : "<p>Open <a href='/settings'>Settings</a> from the top-right menu and scroll to <strong>Delete account</strong>, then tap <strong>Delete my account</strong>.</p><p>Deleting deactivates your login right away. Your data is kept for <strong>30 days</strong> so you can restore your account if you change your mind - we email you a restore link - and then it is permanently removed. If you prefer, you can tick the option to skip the 30-day window and delete immediately.</p><p>To change your username instead, email <a href='mailto:help@fimby.com'>help@fimby.com</a>.</p>",
    "sortOrder" : "630",
    "category" : "Privacy & Account"
  }
'@ }
)

foreach ($faq in $faqItems) {
    New-FaqItem -contentKey $faq.ck -title $faq.title -urlName $faq.url -apiName $faq.api -contentBodyJson $faq.body
}

Remove-Item "$basePath\fimby_faq_import.zip" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$script:faqPack\*" -DestinationPath "$basePath\fimby_faq_import.zip" -Force
Write-Host "Created fimby_faq_import.zip ($($faqItems.Count) FAQ items)"
