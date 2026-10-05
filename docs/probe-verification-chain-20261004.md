# Recovery and media verification chain — 2026-10-04

## Preserved failures

For reviewed head `e88d4c71`, foundation PR run `37128359464` failed twice. Attempt 1 passed A11–A13 but the initial parallel catalog/featured requests timed out (`-1001`); four featured assertions failed, while the other eleven media/system tests passed. The service log lacked request timing. Attempt 2 failed A11 recovery with HTTP 409. The first server result was recorded at 01:05:05.739 UTC, the recovery result at 01:07:13.489 UTC: 127.750 seconds, beyond the unchanged 120-second replay window.

The 122.736-second gap from crash `boundaryValidation` to recovery `recoveryRead` does **not** prove that process launch alone took that long. The previous driver did not timestamp launch/PID/startup observations, and STARTED had neither a timestamp nor measurements around its synchronous atomic write/force-sync. Node heartbeats continued during the gap, and the recovery request did not arrive until after it. No particular OS, filesystem or simulator cause has been established. The successful push run is retained as a separate result, not a replacement for either failure.

## Follow-up run at `359122d`

Both foundation runs failed before recovery launch. PR run `37172747313` hit the new two-second `ps` deadline while the probe was still alive. Delegate entry took 29.664 seconds after launch; recorded log writes took at most 37 ms. Push run `37172744454` exhausted the existing 35-second held-commit observer; the Worker refresh completed after approximately 41.943 seconds. Node heartbeats continued, so neither result establishes an entire-host freeze. The fixed deadlines correctly remained failures, not passes.

Production-local runs `37172747201` / `37172744452` also failed at the capabilities stage. The previous `fixture_assertion` category conflated input, boundary, response and assertion failures; it does not identify a wrong capability value. Their other 32 tests passed. The production driver did not call the new M2/M3 diagnostics. Local fixed-backend config returned HTTP 200 with the expected capability flags; that is a control check, not an explanation for CI. Both failure types remain recorded for follow-up verification.

## Follow-up run at `24686d7`

Both foundation workflows completed successfully (`37179020246` PR / `37179019315` push). Their A11/A12/A13 intervals were 6.284 / 1.714 / 1.656 seconds and 74.406 / 3.393 / 2.117 seconds. All six crash/recovery pairs had distinct PIDs and kqueue NOTE_EXIT confirmations, with one recovery launch per scenario. Both runs completed the media, real five-minute authentication rotation, library/privacy restart, four-configuration, Swift/UI, Keychain and auth-recovery stages. Routine Swift/UI suites each had 229 passes and 26 intentional skips; dedicated media probes each passed 12/12 without skips.

Production-local PR `37179020249` passed, but push `37179019310` returned outer bridge HTTP 408 at `capability_request`; 32 of 33 tests passed. This confirms an expired bridge request, not a capability-value mismatch. The service started before the simulator's cold boot; the first test ran over four minutes later. Diagnostic initialization traffic also consumed its 256 KiB budget before that request, so the exact Worker wait is not established by this artifact. The driver now finishes simulator boot before initializing the service, and unlabelled initialization traffic is counted in aggregate to preserve later request timing. The five-second bridge limit and all existing assertions remain unchanged. This addresses a concrete startup overlap; its effect must still be verified in the next complete remote run.

## Test-only changes

- Prepare both launch environments and output handles before CRASH. Defer log copies/deletions and progress printing until both hosts have completed, or the pair fails. Each host still launches once, recovery uses a different PID, and the driver independently confirms each host exited.
- Timestamp launch, PID observation, STARTED, boundary and actual exit with bounded allowlisted driver records. Add delegate/task-entry and evidence-write timings. The records contain fixed labels, numeric timestamps/PIDs and error categories, never credentials, URLs, headers or bodies. macOS observes real process exit through a persistent, nonblocking kqueue NOTE_EXIT filter instead of launching `ps` on every polling iteration. Only NOTE_EXIT or an absent PID during registration confirms exit; permissions, unknown events and other errors fail closed. Linux driver regressions read the kernel `/proc` record. The original scenario and post-FINISHED deadlines remain unchanged.
- Ordinary diagnostics remain atomically written but no longer force-sync every line. Critical boundary, FINISHED and FAILED records are first written and synced in a private sibling file, then atomically published. A sync failure leaves the preceding evidence unchanged. In file-evidence mode there is no stdout flush barrier. Actual product Keychain/journal writes remain unchanged.
- Recovery exit timing starts only after FINISHED is visible, allowing the original cleanup step to finish before the five-second exit check. A visible boundary without actual host exit, missing startup/cleanup evidence, wrong PID or reported failure still fails.
- Media verification now retains bounded Node/Worker request timing through the existing diagnostic preload. Catalog/featured and fixture routes use fixed labels. XCTest failures remain authoritative; the featured success marker is emitted only if that test has no failed assertions.
- The independent production-local bridge distinguishes request, decode and capability-assert phases and reports only fixed response categories/status/boolean validation results. A per-run UUID links its bounded runtime timing to the test artifacts, including failures. The existing bridge/request deadlines and capability assertions are unchanged.
- A new invocation invalidates only its own prior output files, so an early failure cannot retain an old passing summary or later-stage logs.

No product Core, backend code, server replay window, client request budget, production configuration, app version or backend pin changes. Recovery, media and library retain their individually reviewed fixture revisions; the separate production-local fixture stays pinned to `42e29f34`.

## Validation and limits

Local Xcode 27 beta 6 / iOS 26.5 is a development check, not the fixed stable-Xcode CI acceptance. NativeCrashBoundaryTests: 12 passed, 2 dedicated process probes skipped as designed; those three actual crash/recovery boundaries are exercised separately by the standalone driver. The follow-up standalone A11/A12/A13 all passed, with server-request intervals 0.800 / 0.528 / 0.535 seconds; all six hosts were confirmed through kqueue NOTE_EXIT with distinct crash/recovery PIDs. The separate production-local suite passed all 33 tests against the unchanged backend pin. Python regressions: driver 49, evidence 14, preparation 7, host diagnostics 3 and production runner 17 passed. Node runtime/transport diagnostics 9 passed. These cover delayed archival, failure preservation, bounded process checks and field redaction, alongside real loopback checks.

The final commit must pass both foundation push and PR workflows, including recovery, media/auth rotation, library, configuration, Swift/UI, Keychain and auth recovery stages, plus the separate production-local workflow. Remote results are recorded in the PR after the actual run completes; local success alone does not close the chain.

This is simulator/local contract validation. Formal HTTPS/AASA CDN, signed physical-device link delivery, production resource re-verification and release approval remain separate. Production native services, subscriptions, account erasure activation and App Store release remain closed.

## Process observer reference

The process observer uses the macOS process filter and exit notification described by [Apple kevent(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kevent.2.html) through [Python select.kqueue/kevent](https://docs.python.org/3/library/select.html). It does not infer exit from missing logs or a successful launch command.
