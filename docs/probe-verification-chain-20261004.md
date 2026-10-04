# Recovery and media verification chain — 2026-10-04

## Preserved failures

For reviewed head `e88d4c71`, foundation PR run `37128359464` failed twice. Attempt 1 passed A11–A13 but the initial parallel catalog/featured requests timed out (`-1001`); four featured assertions failed, while the other eleven media/system tests passed. The service log lacked request timing. Attempt 2 failed A11 recovery with HTTP 409. The first server result was recorded at 01:05:05.739 UTC, the recovery result at 01:07:13.489 UTC: 127.750 seconds, beyond the unchanged 120-second replay window.

The 122.736-second gap from crash `boundaryValidation` to recovery `recoveryRead` does **not** prove that process launch alone took that long. The previous driver did not timestamp launch/PID/startup observations, and STARTED had neither a timestamp nor measurements around its synchronous atomic write/force-sync. Node heartbeats continued during the gap, and the recovery request did not arrive until after it. No particular OS, filesystem or simulator cause has been established. The successful push run is retained as a separate result, not a replacement for either failure.

## Test-only changes

- Prepare both launch environments and output handles before CRASH. Defer log copies/deletions and progress printing until both hosts have completed, or the pair fails. Each host still launches once, recovery uses a different PID, and the driver independently confirms each host exited.
- Timestamp launch, PID observation, STARTED, boundary and actual exit with bounded allowlisted driver records. Add delegate/task-entry and evidence-write timings. The records contain fixed labels, numeric timestamps/PIDs and error categories, never credentials, URLs, headers or bodies. `ps` has a two-second deadline and fails closed.
- Ordinary diagnostics remain atomically written but no longer force-sync every line. Critical boundary, FINISHED and FAILED records are first written and synced in a private sibling file, then atomically published. A sync failure leaves the preceding evidence unchanged. In file-evidence mode there is no stdout flush barrier. Actual product Keychain/journal writes remain unchanged.
- Recovery exit timing starts only after FINISHED is visible, allowing the original cleanup step to finish before the five-second exit check. A visible boundary without actual host exit, missing startup/cleanup evidence, wrong PID or reported failure still fails.
- Media verification now retains bounded Node/Worker request timing through the existing diagnostic preload. Catalog/featured and fixture routes use fixed labels. XCTest failures remain authoritative; the featured success marker is emitted only if that test has no failed assertions.
- A new invocation invalidates only its own prior output files, so an early failure cannot retain an old passing summary or later-stage logs.

No product Core, backend code, server replay window, client request budget, production configuration, app version or backend pin changes. Recovery, media and library retain their individually reviewed fixture revisions; the separate production-local fixture stays pinned to `42e29f34`.

## Validation and limits

Local Xcode 27 beta 6 / iOS 26.5 is a development check, not the fixed stable-Xcode CI acceptance. NativeCrashBoundaryTests: 12 passed, 2 dedicated process probes skipped as designed; those three actual crash/recovery boundaries are exercised separately by the standalone driver. Final standalone A11/A12/A13 all passed, with server-request intervals 1.088 / 0.986 / 0.934 seconds. Python regressions: driver 41, evidence 14, preparation 7 and host diagnostics 3 passed. Node diagnostics 6 passed. These cover delayed archival, failure preservation, bounded process checks and field redaction, alongside real loopback checks.

The final commit must pass both foundation push and PR workflows, including recovery, media/auth rotation, library, configuration, Swift/UI, Keychain and auth recovery stages, plus the separate production-local workflow. Remote results are recorded in the PR after the actual run completes; local success alone does not close the chain.

This is simulator/local contract validation. Formal HTTPS/AASA CDN, signed physical-device link delivery, production resource re-verification and release approval remain separate. Production native services, subscriptions, account erasure activation and App Store release remain closed.
