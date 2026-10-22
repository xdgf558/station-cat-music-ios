# Topic-index notebook — design QA

2026-10-22 · development candidate 1.0.3 (16).

## Reference and implementation

The selected reference is concept **3, 主题索引**, confirmed by the user. Its source image SHA-256 is `3f4aa0380d7e2fe893e0f9d20c6bae2fb88cea536e666e94ac02e16d8c155baa`. The implementation uses the existing SwiftUI navigation, Orbit background, navy panels and lavender accent. It preserves the large heading, search, horizontal topic filters, illustrated note rows and prominent create action.

Native system navigation and sheets replace the illustration's custom back/tab controls. Notes without a linked, currently available work show a notebook symbol rather than an invented cover. Topic names and note text shown in test screenshots are deliberately authored fixtures, not production content or user data. Real interface screenshots are exported from XCTest result bundles; no generated mockup is presented as a device capture.

## Flows inspected

- Create and edit personal writing; close an unchanged editor; keep or discard an unsaved draft.
- Link a published fixture work, choose a topic, filter by that topic, then delete the topic without deleting its notes.
- Search saved text; terminate and reopen with catalog failure; read and edit persisted local writing.
- Cancel a clear, confirm a clear, and reopen to verify that cleared notes stay removed.
- Open a notebook editor from a loaded fixture clip, tear down the player, return to the song and require another explicit player load.
- Four interface languages at the largest accessibility text category, with scrollable content and reachable editor actions.

These checks inspect the accessibility tree and actual screenshots. They are not a VoiceOver speech or physical-device acceptance claim.

## Findings resolved

| Finding | Resolution and evidence |
| --- | --- |
| The original in-scroll create action could sit under the floating tab bar. | A bottom safe-area action region reserves space above the system tabs. The list scrolls separately. Its background is opaque so hidden row text does not show through the controls. |
| A page-wide accessibility identifier replaced both inset button identifiers. | The page marker now belongs to the heading only. The actual failure hierarchy showed both buttons named `notebookPage`; after the correction, all four notebook UI cases passed. The decorative page background is hidden from accessibility. |
| The initial discard confirmation did not expose the expected keep-editing control in the tested presentation. | Native alerts expose keep-editing and discard choices. The test retains the typed text after choosing keep-editing, then explicitly discards it. |

## Result bundles and scope

`.build/notebook-1.0.3-final-tests.xcresult` contains 43 passing core tests and seven passing UI tests before the final action-region changes. `.build/notebook-layout-final3.xcresult` contains the subsequent four passing notebook UI cases, including the populated Chinese topic-index capture and all four maximum-text-size presentations. The final opaque background is captured in `.build/notebook-final-display.xcresult` (1/1 passed). `.build/notebook-ipad-fullscreen.xcresult` passed 2/2 focused cases, including the personal-hub/version-notes flow. Full-screen iPad captures confirm that the previous app-coordinate crop was a screenshot issue; the actual compatibility window contains the controls. Details and hashes are in [validation.json](validation.json).

The local toolchain is Xcode 27.1 (27A9275), with iOS/iPadOS Simulator 26.4.1. This does not replace the pinned Xcode 26.4.1 CI. The Chinese topic-picker run emitted a non-failing UIKit `_UIReparentingView` hierarchy warning; the tested picker, save, filter and delete operations completed. Preserve the warning with the raw result rather than claiming an entirely warning-free run.

The iPad check targets iPad Air 11-inch (M3), using the app's existing iPhone compatibility presentation. This work does not change the supported device family or claim a new native iPad layout. There is no distribution-signed build, physical-phone installation, real third-party video test, deployment or Apple resubmission in this development record.

## Final visual disposition

No P0–P2 visual or interaction blocker was observed in the inspected iPhone screenshots, four-language maximum-text-size flows, or the focused iPad compatibility flows. The third row can extend below the visible list area on iPhone, and the shorter iPhone compatibility viewport on iPad shows fewer rows; both remain scrollable above the fixed actions. This is a local design disposition, not a hosted-CI, VoiceOver-speech, physical-device or App Store approval.
