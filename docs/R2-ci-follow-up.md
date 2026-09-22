# R2 CI follow-up — 2026-09-22

The failed iOS run [35740809464](https://github.com/xdgf558/station-cat-music-ios/actions/runs/35740809464) tested `77ba9b4`. A11–A13 passed. The subsequent media step failed in `build-for-testing`, before starting its media service or AVPlayer assertions. `M3-media-build.log` is retained locally; SHA-256: `4b19a68d40210cbabf6dc5bf1d9457cebeba79b1857aa72283d47760b09e771f`.

Pinned Xcode 26.4.1 reported these diagnostics on the `AuthFixtureTransport` actor declaration in `Tests/NativeAuthenticationTests.swift`:

```
'nonisolated' modifier cannot be applied to this declaration
'nonisolated' on an actor's synchronous initializer is invalid
```

That fixture previously relied on its synthesized zero-argument initializer. The R2 startup tests now also instantiate it from a separate file. The compatibility change supplies an ordinary explicit `init() {}` and retains all stored-property defaults and actor isolation. It does not add `nonisolated`, move the fixture to MainActor, disable strict concurrency, or change product authentication/playback/startup code. The precise compiler-internal cause is not claimed; the pinned CI build is the acceptance check for this targeted change.

Local Xcode 27 beta 6 compiled the test targets and passed all 15 authentication and 8 music-link initialization cases (23 total, zero failures). This does not substitute for Xcode 26.4.1: the latest PR CI must compile and complete media/system controls, real authentication rotation, M5, four configurations, ordinary tests, Keychain restart and recovery.

The paired website failure was a whole-file 120-second timeout over sequential persistent-D1 lifecycle tests. Its fix separates case and file budgets while retaining assertions and business time windows. Existing backend fixture manifests remain unchanged because neither follow-up changes the pinned fixture's runtime behavior. The original failed runs remain evidence; no merge, production activation or remote R2 rerun is implied here.
