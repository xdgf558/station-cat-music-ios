# Startup showcase — Cat Halo

The user selected the first displayed startup concept on 2026-09-24. Visual reference: `previews/startup/selected-reference.png`. This is an app-owned SwiftUI startup view, not a timed advertisement or replacement for iOS launch-screen infrastructure.

The bundled `StartupBackground` JPEG is 853 × 1844 and about 225 KiB. It was derived with built-in ImageGen from the selected concept, preserving the navy planet, cat with headphones, and orbital halo while removing all UI text and loading dots. Prompt: remove only the brand/title, Chinese tagline and bottom loading UI; preserve the original composition and all artwork. Original output: `exec-58174641-4d85-46c8-94dc-430b0127349b.png`. Native SwiftUI renders live branding, four-language copy, loading dots and recovery controls. No image download is required at launch.

Initialization still owns account restore, account-scope coordination, concurrent catalog/featured requests and pending cold-launch links. A successful or empty catalog/featured response admits the app. If both fail, retry starts a fresh initialization; an explicit secondary action permits entry to the app and local settings without claiming music is playable offline. A resolved music link can enter directly; no link or startup path automatically plays audio. Later catalog refreshes never reintroduce the launch screen. There is no minimum dwell time or invented percentage. The transition uses a 0.3-second opacity animation and respects Reduce Motion. Large Dynamic Type uses a scrollable layout.

Simulator-only DEBUG Mock fixtures (`STATION_STARTUP_PREVIEW=slow|failure`) exercise visible loading and failure. They cannot activate networking or affect Staging/Production; the five-second synthetic delay is for screenshots only and is absent on physical devices.

## Validation

46 selected logic tests and four existing navigation/UI cases passed in the first run; three startup UI tests passed after correcting the initial identifier and accessibility-layout issues. Final screenshots and comparison are under `docs/previews/startup/`. Signed Staging device build succeeded. See `design-qa.md` for the iteration history and precise validation boundaries.
