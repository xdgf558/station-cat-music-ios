# Public song Universal Links activation — 2026-10-17

Scope: the user authorized enabling external song links and updating the connected
iPhone. This is a public catalog navigation release, not native account, audio,
personal-sync, subscription, TestFlight-upload or App Store authorization.

## Website and Apple association

- Production website source: `35b0f13440b2fced74d728bf6efeee0dc9bff22d` (merged website #231).
- Worker version: `5c5767c7-c464-4f2f-a6f0-ecd91860de25`, 100% traffic.
- Previous/rollback version: `52424335-fd65-4488-a49c-1b2f1249dd57`.
- The Worker bundle and all 432 assets are byte-identical to the previous deployment.
  No empty-serial build was produced or deployed.
- The only added variables are `STATION_PUBLIC_APP_LINKS_ENABLED=true` and
  `STATION_PUBLIC_APP_LINKS_PROFILE=station-cat-music-platform-links-v1`.
- Resource identities, nine secret bindings, worker-first assets, domain, schedules,
  observability and all other variables were checked before and after deployment.
  There were no migrations or business-data writes.
- Production AASA and the Apple CDN both returned HTTP 200 and matched the reviewed
  profile exactly at 2026-10-17 12:37 UTC. Only `applinks` is claimed, for
  `2AM5S7BM2N.org.stationcat.music`; the file contains 27 components.
- Post-deployment checks: 43 website/asset checks (including 12 asset hashes) and
  19 catalog/bookmark/association checks passed. Wrangler types and dry run passed.

The same reviewed parsing restrictions remain in force: exact HTTPS origin,
supported paths and bounded campaign parameters, no credential-bearing URLs,
no encoded aliases, no external-platform forwarding of campaign parameters and
no authorization or automatic playback from a link.

## iPhone package

- Version `0.1.0 (9)`, production bundle `org.stationcat.music`.
- Apple development signature, Team `2AM5S7BM2N`, with the connected device present
  in the provisioning profile. The signed entitlement contains exactly
  `applinks:wwwstationcat.org`.
- Public metadata and public links were enabled explicitly for this candidate.
  All four committed build configurations still default to closed services.
- Native auth/music/sync/production activation remain `NO`; auth origin and native
  activation profile remain empty. The Production app has no background-audio
  declaration or ATS exception.
- Four-language release notes were regenerated and checked against the bundled
  resources; the build 8 notes remain in the previous-updates section.
- Installation of build 9 was confirmed through CoreDevice. The existing staging
  bundle remains installed at build 8; its metadata and data-container identity
  were unchanged. These separate apps do not share local favorites or old audio.
- Eleven Python release/association checks passed. Production app and the opt-in
  UI acceptance runner compiled with local Xcode 27.1. This does not replace a
  stable remote CI run or distribution-signing validation.
- The version/update-notes navigation test passed on Simulator (one test,
  14.705 seconds). It verified the displayed build 9 and new Chinese notes;
  the package inspection separately checked all four localization resources.

## Device verification

`PublicUniversalLinkUITests` is explicitly opt-in. It opens URLs with
`XCUIDevice.shared.system.open`, rather than injecting an AppModel call or an
app-specific URL event. It alternates two public songs across the root,
Traditional Chinese, Simplified Chinese, English and Japanese paths, in cold and
warm states, with bounded campaign parameters. A separate test checks the actual
version and release-notes page. No platform listening button is pressed.

The first execution waited for the locked phone. After the user unlocked it,
the runner started but timed out enabling UI automation, before running a test.
Both the initial execution and one fresh retry failed to initialize UI automation
(`Timed out while enabling automation mode`), before any song assertions ran.
Both result bundles were retained. CoreDevice confirmed that build 9 launches
successfully.

The user then confirmed the manual iPhone check: long-pressing the public song
link in Notes opened Station Cat Music at **把晚安往后放**, with
`utm_source=acceptance` present. The tested path was
`/music/tracks/track-4de70272-3d5a-405d-bcca-efd7aa2a9e13/`.
This is user-reported physical-device acceptance of that path and campaign query,
not a claim that the ten-case cold/warm multilingual automation suite passed.
Those broader device cases remain unexecuted.

The privileged macOS `swcutil` check was not performed because noninteractive
sudo required an administrator password. No administrator credentials were
requested or collected.

## Remaining release boundaries

No TestFlight build was uploaded. The installed candidate is development-signed,
not a distribution acceptance result. Each third-party source app may handle
links differently; OS-level dispatch is not proof of WeChat/Douyin browser
behavior. App Store privacy answers and publication remain separate tasks.
