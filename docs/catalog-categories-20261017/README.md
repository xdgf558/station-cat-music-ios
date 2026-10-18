# Catalog categories — selected design 2

The user selected the second displayed concept, the album gallery. `selected-design.png` is that exact reference. This implements the design in the existing native SwiftUI app, retaining the navy/purple Orbit background, brand mark, system typography and native tab bar.

The catalog adds All / Singles / Albums and a persistent category search field. Albums have square covers in two columns, followed by title, artist and visible song count. Accessibility text sizes use one column and a native category menu so long labels remain fully readable. An album opens a native second-level page with ordered songs; selecting a song still fetches the current public work detail before offering validated external listening destinations. It does not start audio or grant playback.

Published album membership is supplied by the paired website branch `codex/public-album-categories` through the existing public list/detail DTOs. No production data is modified. Singles means a verified empty album-membership array, while missing/null classification leaves the work in All and offers a refresh notice. Album search matches album title, artist and member song titles. The album count covers currently public members, and its artwork reuses the first visible ordered member's cover/cache; a separate legacy collection image is not fetched. Contradictory album versions or positions across source pages fail the refresh while retaining the last usable catalog and a retry message.

`platform-albums.json` is a synthetic Mock-only design/test dataset. Its album names and memberships are illustrative, not newly published catalog data. Four representative covers were copied unchanged from this workspace's website public cover derivatives, without any new network request:

| Asset | Source filename | Existing cover title |
| --- | --- | --- |
| CatalogSample1 | a0fc665622b39cc0d089c942c96de906164e3781f08de8968d4803d3e6ba2f86.jpg | 原来已经这么远 |
| CatalogSample2 | 9e34aab0a825f6f511efa37efb605b6f07e930acd2a6a01a0d3eec533b05b6aa.jpg | 改天是哪一天 |
| CatalogSample3 | 5eb2409fd3171c0cf22f8056c0a45f393e3aa97e58ca4323ce8e79040153ae6a.jpg | 这次坐在台下 |
| CatalogSample4 | 2c3799a1c3a1d7c58ede726f0b52748106c88bb3e37cf87a57d8c0309fb5db65.jpg | 把那年还给风 |

The sample artwork is selected only by the explicit catalog-categories fixture in a DEBUG simulator running Mock. Normal/live fallback and controlled HTTPS cover loading remain unchanged. All four shipped configuration flags stay closed. Build 0.1.0 (10) has matching four-language update notes and retains build 9's link notes in history.

Validation and actual screenshots are listed in `verification.json` and the root `design-qa.md`. Local Xcode 27.1 beta results do not replace the repository's stable Xcode 26.4.1 CI or real-device acceptance. No website deployment, phone installation, TestFlight upload or production activation is part of this change.
