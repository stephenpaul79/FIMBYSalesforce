$basePath = "c:\Users\srathjen\FIMBY\FIMBY\cms-import"

function New-ContentItem($packDir, $folderName, $contentKey, $type, $title, $urlName, $contentBody, $cmsFolder) {
    $itemDir = Join-Path $packDir "$folderName\$contentKey"
    New-Item -ItemType Directory -Path $itemDir -Force | Out-Null

    $content = @{
        type = $type
        title = $title
        contentBody = $contentBody
        urlName = $urlName
    }
    $content | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $itemDir "content.json") -Encoding UTF8

    $meta = @{
        contentKey = $contentKey
        apiName = $urlName
        path = $cmsFolder
        taxonomyTerms = @()
    }
    $meta | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $itemDir "_meta.json") -Encoding UTF8
}

# --- FAQ ITEMS ---
$faqPack = Join-Path $basePath "faq-pack"
Remove-Item $faqPack -Recurse -Force -ErrorAction SilentlyContinue

$faqFolder = "FIMBY FAQs"
$faqItems = @(
    @{
        key = "MCFAQ001WHATISFIMBY00000000001"
        title = "What is FIMBY?"
        url = "what-is-fimby"
        body = @{
            question = "What is FIMBY?"
            answer = "<p>FIMBY (<strong>Family In My Backyard</strong>) is a neighbourhood platform that helps you connect with your neighbours through shared stories, asks and offers, a lending library, and direct messaging. It was built to make it easy for people living near each other to share life, lend a hand, and look out for one another.</p>"
            sortOrder = "010"
            category = "Getting Started"
        }
    },
    @{
        key = "MCFAQ002UPDATEPROFILE000000002"
        title = "How do I update my profile?"
        url = "how-do-i-update-my-profile"
        body = @{
            question = "How do I update my profile?"
            answer = "<p>Tap the <strong>menu icon</strong> in the top-right corner and select <strong>Profile</strong>. From there you can edit your name, photo, pronouns, bio, and care preferences. You can also update your profile at any time from the My Stuff tab.</p>"
            sortOrder = "020"
            category = "Getting Started"
        }
    },
    @{
        key = "MCFAQ003ASKSANDOFFERS0000000003"
        title = "What are Asks and Offers?"
        url = "what-are-asks-and-offers"
        body = @{
            question = "What are Asks and Offers?"
            answer = "<p>Asks and Offers is a bulletin board where neighbours can post things they need (asks) or things they want to share (offers). This includes:</p><ul><li><strong>Goods</strong> - perishable and non-perishable items</li><li><strong>Services</strong> - free or paid help</li><li><strong>Events</strong> - neighbourhood gatherings and activities</li></ul><p>Browse what your neighbours have posted, or create your own listing from the Create button.</p>"
            sortOrder = "030"
            category = "Features"
        }
    },
    @{
        key = "MCFAQ004LIBRARYWORKS00000000004"
        title = "How does the Library work?"
        url = "how-does-the-library-work"
        body = @{
            question = "How does the Library work?"
            answer = "<p>The Library lets you share items you are willing to lend to neighbours - tools, books, games, and more. You can:</p><ul><li><strong>Browse</strong> items available in your neighbourhood</li><li><strong>Add your own items</strong> for others to borrow</li><li><strong>Request to borrow</strong> something you need</li></ul><p>It is like a neighbourhood sharing shelf, managed right from the app.</p>"
            sortOrder = "040"
            category = "Features"
        }
    },
    @{
        key = "MCFAQ005WHOCANSEE000000000005"
        title = "Who can see my profile and posts?"
        url = "who-can-see-my-profile-and-posts"
        body = @{
            question = "Who can see my profile and posts?"
            answer = "<p>Your profile and posts are visible only to <strong>other members in your neighbourhood</strong>. FIMBY is a private community - only registered neighbours can access the platform. Your information is never shared outside your neighbourhood group.</p>"
            sortOrder = "050"
            category = "Privacy"
        }
    },
    @{
        key = "MCFAQ006NOTIFICATIONS0000000006"
        title = "How do I change my notification settings?"
        url = "how-do-i-change-my-notification-settings"
        body = @{
            question = "How do I change my notification settings?"
            answer = "<p>Go to <strong>Settings</strong> (via the menu in the top-right corner) and scroll to the <strong>Notifications</strong> section. You can toggle:</p><ul><li>Push notifications on or off</li><li>Email summary preferences</li><li>Which types of updates you want to receive (messages, stories, asks and offers, library items)</li></ul>"
            sortOrder = "060"
            category = "Account"
        }
    },
    @{
        key = "MCFAQ007SENDMESSAGE000000000007"
        title = "How do I send a message to a neighbour?"
        url = "how-do-i-send-a-message"
        body = @{
            question = "How do I send a message to a neighbour?"
            answer = "<p>You can message any neighbour directly from their profile or from any post they have made. Tap their name or avatar, then select <strong>Message</strong>. All your conversations are in the <strong>Messages</strong> tab, accessible from the bottom navigation bar.</p>"
            sortOrder = "070"
            category = "Features"
        }
    },
    @{
        key = "MCFAQ008WHATSTORIES0000000000008"
        title = "What are Stories?"
        url = "what-are-stories"
        body = @{
            question = "What are Stories?"
            answer = "<p>Stories are short posts you share with your neighbourhood - updates, photos, thoughts, or things happening on your street. Think of it as a neighbourhood bulletin board where everyone can share what matters to them. Stories appear in the main feed for all neighbours to see and respond to.</p>"
            sortOrder = "080"
            category = "Features"
        }
    },
    @{
        key = "MCFAQ009REPORTPROBLEM000000009"
        title = "How do I report a problem or concern?"
        url = "how-do-i-report-a-problem"
        body = @{
            question = "How do I report a problem or concern?"
            answer = "<p>If you see content that is inappropriate or experience an issue with the app, tap the <strong>three-dot menu</strong> on any post and select <strong>Report</strong>. For general app feedback or support, visit this Help page and use the contact options below. Our team reviews all reports promptly.</p>"
            sortOrder = "090"
            category = "Account"
        }
    }
)

foreach ($faq in $faqItems) {
    New-ContentItem -packDir $faqPack -folderName $faqFolder -contentKey $faq.key -type "fimby_faq_item" -title $faq.title -urlName $faq.url -contentBody $faq.body -cmsFolder $faqFolder
}

Compress-Archive -Path "$faqPack\*" -DestinationPath "$basePath\fimby_faq_import.zip" -Force
Write-Host "Created fimby_faq_import.zip with $($faqItems.Count) items"

# --- ONBOARDING SLIDES ---
$obPack = Join-Path $basePath "onboarding-pack"
Remove-Item $obPack -Recurse -Force -ErrorAction SilentlyContinue

$obFolder = "FIMBY Onboarding"
$obSlides = @(
    @{
        key = "MCOB001WELCOME0000000000000001"
        title = "Welcome to FIMBY!"
        url = "welcome-to-fimby"
        body = @{
            title = "Welcome to FIMBY!"
            body = "<p>FIMBY (<strong>Family In My Backyard</strong>) connects you with the people who live closest to you. Share stories, lend a hand, borrow what you need, and build real relationships with your neighbours.</p><p>Let us show you around so you can get the most out of your neighbourhood community.</p>"
            pageOrder = "010"
            slideOrder = "010"
            pageTitle = "Welcome"
        }
    },
    @{
        key = "MCOB002STORIES0000000000000002"
        title = "Your Neighbourhood Feed"
        url = "stories-feed"
        body = @{
            title = "Your Neighbourhood Feed"
            body = "<p>The <strong>Stories</strong> tab is your neighbourhood's heartbeat. Here you will find:</p><ul><li>Updates and photos from neighbours</li><li>Local happenings and announcements</li><li>Conversations about life on your street</li></ul><p>Share a story of your own - introduce yourself, post a photo, or ask a question!</p>"
            pageOrder = "020"
            slideOrder = "010"
            pageTitle = "Stories"
        }
    },
    @{
        key = "MCOB003AANDO10000000000000003"
        title = "Asks and Offers"
        url = "asks-and-offers-overview"
        body = @{
            title = "Asks and Offers"
            body = "<p>Need something? Have something to share? The <strong>Asks and Offers</strong> board makes it easy to exchange goods, services, and event invitations with your neighbours.</p>"
            pageOrder = "030"
            slideOrder = "010"
            pageTitle = "Asks and Offers"
        }
    },
    @{
        key = "MCOB004AANDO20000000000000004"
        title = "Share Goods"
        url = "asks-and-offers-goods"
        body = @{
            title = "Share Goods"
            body = "<p>Post perishable or non-perishable items you would like to give away or that you are looking for. From extra garden produce to household items - one person's extra is another's treasure.</p>"
            pageOrder = "030"
            slideOrder = "020"
            pageTitle = "Asks and Offers"
        }
    },
    @{
        key = "MCOB005AANDO30000000000000005"
        title = "Offer or Request Help"
        url = "asks-and-offers-services"
        body = @{
            title = "Offer or Request Help"
            body = "<p>Whether it is help moving furniture, a ride to an appointment, or tutoring - post a service ask or offer and connect with neighbours who can help.</p>"
            pageOrder = "030"
            slideOrder = "030"
            pageTitle = "Asks and Offers"
        }
    },
    @{
        key = "MCOB006LIBRARY0000000000000006"
        title = "The Neighbourhood Library"
        url = "library-feature"
        body = @{
            title = "The Neighbourhood Library"
            body = "<p>Why buy when you can borrow? The <strong>Library</strong> is a shared lending shelf for your neighbourhood.</p><ul><li>Browse items your neighbours are willing to lend</li><li>Add your own items - tools, books, games, kitchen gear</li><li>Request to borrow with a single tap</li></ul><p>It saves money, reduces waste, and gives you a reason to meet the people next door.</p>"
            pageOrder = "040"
            slideOrder = "010"
            pageTitle = "Library"
        }
    },
    @{
        key = "MCOB007MESSAGES000000000000007"
        title = "Direct Messages"
        url = "messaging-feature"
        body = @{
            title = "Direct Messages"
            body = "<p>Have a private conversation with any neighbour using <strong>Messages</strong>. Coordinate a borrow, follow up on an offer, or just say hello.</p><p>Your messages are private - only you and the other person can see them.</p>"
            pageOrder = "050"
            slideOrder = "010"
            pageTitle = "Messages"
        }
    },
    @{
        key = "MCOB008ALLSET00000000000000008"
        title = "Your Profile and Settings"
        url = "your-profile-and-settings"
        body = @{
            title = "Your Profile and Settings"
            body = "<p>Make FIMBY yours! From the menu you can:</p><ul><li>Update your <strong>profile</strong> - photo, bio, and care preferences</li><li>Adjust <strong>notification settings</strong> so you only hear about what matters to you</li><li>Visit <strong>Help and Support</strong> any time you need a hand</li></ul><p>You are all set! Go explore your neighbourhood.</p>"
            pageOrder = "060"
            slideOrder = "010"
            pageTitle = "You're All Set!"
            buttonLabel = "Explore FIMBY"
            buttonUrl = "/"
        }
    }
)

foreach ($slide in $obSlides) {
    New-ContentItem -packDir $obPack -folderName $obFolder -contentKey $slide.key -type "fimby_onboarding_slide" -title $slide.title -urlName $slide.url -contentBody $slide.body -cmsFolder $obFolder
}

Compress-Archive -Path "$obPack\*" -DestinationPath "$basePath\fimby_onboarding_import.zip" -Force
Write-Host "Created fimby_onboarding_import.zip with $($obSlides.Count) items"

# Show structure of FAQ pack as verification
Write-Host "`nFAQ pack structure:"
Get-ChildItem "$faqPack" -Recurse | ForEach-Object { Write-Host "  $($_.FullName.Replace($faqPack, ''))" }

Write-Host "`nSample content.json:"
Get-Content "$faqPack\$faqFolder\MCFAQ001WHATISFIMBY00000000001\content.json"
Write-Host "`nSample _meta.json:"
Get-Content "$faqPack\$faqFolder\MCFAQ001WHATISFIMBY00000000001\_meta.json"
