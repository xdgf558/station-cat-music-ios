# Song notebook - 1.0.3 (16)

2026-10-22 (Asia/Singapore). The user selected **concept 3, the topic index**, for a local song notebook and asked to include the previously merged YouTube and Douyin clip features in the same next update. This development candidate builds on iOS main `2e3aad4b03d178e3057983af7df5723b234a6113`. It does not replace, sign, upload or resubmit the rejected App Store candidate **1.0 (13)**. The earlier 1.0.1 (14) and 1.0.2 (15) development entries remain in update history; neither is represented as a publicly distributed release.

## What changes

The notebook gives a user a complete local writing flow: create a note from a song or from My notebook, edit their own title and text, optionally associate a published work, organize notes into user-created topics, search by title/text, and read or edit saved writing offline. The selected topic-index direction uses the existing dark navy and lavender visual language, a search field, topic filters, note rows and a clear create action. Screenshots or design examples used during development are fixtures, not real user notes, published lyrics or evidence of Apple acceptance.

Deleting a topic moves its notes to Uncategorized. Deleting a note or clearing the notebook is a separate confirmed action. An editor that predates a clear/delete cannot silently restore the removed writing. A failed disk write must show a failure, keep the previous saved file and retain the unsaved editor text so the user can decide what to do. Notes are authoritative user writing, not an evictable cover cache, and are not erased by a cover-cache cleanup.

The persisted note contains the user's title and text, its identifier, dates, optional topic identifier and optional work ID/slug. It does not automatically copy server lyrics, creative stories, artwork, platform URLs or campaign parameters. Work association is a reference rather than an offline copy of a work. Reopening the linked work still goes through current online publication/identity checks; it does not revive a stale listening URL. Notes without a linked work remain useful when a catalog cannot be loaded. This feature does not turn notes or browsing into a playback history.

The initial store bounds each scope to 500 notes and 30 topics; note titles are limited to 120 characters, note text to 8,000 and topic names to 40. Atomic JSON files are separated by environment/account scope, have a 4 MiB per-file budget and a 16 MiB aggregate budget, and use iOS file protection. Storage is excluded from system backup. User writing has no automatic expiry or LRU eviction. Existing favorites, browsing history, settings and legacy files are separate stores; migration must not discard them.

## Included clip features and website dependency

This candidate includes the previously reviewed YouTube and Douyin implementations, with their existing click-to-load, fresh publication checks, temporary WebView storage, lifecycle teardown and external fallback behavior. The song cover remains labelled as a cover, not as a provider-fetched thumbnail. Browsing a song or opening its Clips tab does not load a provider player. External music-platform listening remains unchanged; this update does not add native full-song playback, offline music downloads, account login or subscriptions.

The required companion source is website [PR #235](https://github.com/xdgf558/caption-ai-landing-site/pull/235), reviewed head `a043e40a176509ec74baa32b9a39f6256718054b`, merged as `eb83a535ed5ec8b303ba50f80d54886d3aa155a7`. It includes `include=youtube,douyin` support; an old server rejects that request. **Publish the reviewed website interface before distributing this client.** Keep the deployed image variants and effective privacy overlays when preparing the website package; an empty-private-novel test build is not a production package. Historical auth, media and personal-library dependency manifests remain unchanged.

No real Shorts or Douyin links were supplied for this batch, so production clips remain empty. Local fixtures can verify rendering and lifecycle behavior but cannot establish real video/audio playback, provider restrictions, geographic access, account requirements or a production HTTPS path. Provider-ready or document-load callbacks are not actual play-count evidence.

All four committed configurations continue to keep public entry points and native services disabled, with public origins unset. A separately signed release configuration must be inspected before delivery. Merging this change does not deploy the website, enable services, install on a phone, upload TestFlight, alter Apple questionnaire answers or submit App Store review.

## Validation and delivery record

The local result bundle `.build/notebook-1.0.3-final-tests.xcresult` completed **50 passing tests** before the subsequent bottom `safeAreaInset` layout adjustment:

| Coverage | Passed |
| --- | ---: |
| Notebook store | 15 |
| Notebook AppModel integration | 5 |
| YouTube core | 6 |
| Douyin core | 14 |
| Douyin API | 3 |
| Notebook UI | 3 |
| Notebook-to-work handoff UI | 2 |
| Existing clip UI | 2 |
| Total | 50 |

This is 43 core cases and 7 UI cases. The notebook coverage includes local persistence, offline reopening, scope and stale-editor checks, storage boundaries, and keeping authoritative writing separate from presentation caches. The AppModel error case uses invalid input; it must not be described as a separately injected AppModel-level disk-write failure. The completed scope/clear cases also must not be enlarged into a claim of testing every possible in-flight actor interleaving.

The subsequent `.build/notebook-layout-final3.xcresult` passed all **four notebook UI cases** after the safe-area layout and accessibility identifier correction. The final opaque action-region background was rebuilt and checked by the Chinese topic/link/delete flow in `.build/notebook-final-display.xcresult` (**1/1 passed**). Finally, `.build/notebook-ipad-fullscreen.xcresult` passed **2/2 cases** on iPad Air 11-inch (M3): the Chinese notebook flow and the existing personal-hub/version-notes flow. These are focused follow-up runs, not additional unique test counts to add to the earlier 50.

Actual iPhone screenshots and full-screen iPad compatibility screenshots were inspected. The final app still uses its existing iPhone device family; no new native iPad support is claimed. The screenshot helper now captures `XCUIScreen.main` to avoid cropping a compatibility window with app-coordinate bounds. See [design QA](design-qa.md) and [validation manifest](validation.json) for results, source hashes and remaining evidence limits.

The 11 Python guards passed. Contract validation passed for 26 operations, 67 positive examples and 21 negative examples. The actual local Mock app bundle was checked as **1.0.3 (16)**, with matching English, Simplified Chinese, Traditional Chinese and Japanese update resources. This check concerns the local Mock bundle, not a distribution-signed package.

These checks used local **Xcode 27.1 (27A9275)** and **iOS Simulator 26.4.1**. They do not replace the repository-pinned **Xcode 26.4.1** hosted CI. Fixture player tests do not establish a real YouTube/Douyin HTTPS playback path, video audio, regional/account availability or actual provider data handling. No physical iPhone, distribution signature, TestFlight delivery, Apple review or VoiceOver speech acceptance is claimed by these results. The local iPad compatibility checks target the same model as Apple's 1.0 review, but do not replace Apple or physical-device verification.

The new native writing utility responds to the 4.2 concern but cannot guarantee an approval. The separate 5.2.1 artwork provenance response remains necessary.

Version/build and complete four-language update notes are kept together as **1.0.3 (16)**, dated 2026-10-22. Before distribution, inspect the actual signed package's Info.plist and bundled localization resources again; finish the [combined privacy readiness review](privacy-readiness.md), publish the matching policy and save the evidence-based Apple answers through the authorized release workflow.
