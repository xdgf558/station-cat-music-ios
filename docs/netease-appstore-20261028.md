# NetEase webpage listening — App Store candidate 1.0.6 (19)

The user authorized a new version, updated release notes and formal App Store submission on 2026-10-28 after the 1.0.5 (18) TestFlight upload. App Store Connect showed existing 1.0.3 (16) as available for distribution; a new 1.0.6 draft was created without withdrawing that version.

1.0.6 adds an explicit APPSTORE build marker for the same bounded webpage-listening implementation as the TestFlight candidate. Four checked-in configurations remain closed by default. Distribution validation requires production bundle identity, the approved public catalog origin and public links, with native authentication, native music, personal sync and production service activation disabled. APPSTORE and TESTFLIGHT validation modes cannot be combined.

The four-language release notes describe opening official NetEase webpages, keeping a committed page when an additional navigation is blocked, manual retry/external fallback, and stopping the temporary web session on close or background. Test-only wording was removed from the user-facing browser title and blocked-navigation message. Version history for 1.0.5 and 1.0.4 remains available.

This candidate does not promise full-song playback, account-free provider playback, background audio or offline downloads. The provider controls playback, sign-in, regional and network availability. Local fixture and simulator results do not establish actual third-party playback or provider privacy practices. The user's approval to proceed is not recorded as a detailed physical-device audio test.

Release evidence, signatures and upload receipts are kept in the ignored .build/appstore-20261028-v1.0.6-build19 directory. Source is frozen from the actual working files and described as containing uncommitted changes; older hosted CI is not reused as evidence for this candidate. Upload, Apple processing and formal review submission require distinct evidence. This document does not itself assert any of those later steps is complete.

Public privacy wording and Apple App Privacy answers require a NetEase WebView delta review before formal submission; the older external-link-only rationale is not reused as coverage. See docs/app-store/netease-1.0.6-privacy-delta.md.
