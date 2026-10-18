# Standalone recovery probe launch acknowledgement

The original reviewed iOS head `dab6f73` passed push run [39081373614](https://github.com/xdgf558/station-cat-music-ios/actions/runs/39081373614), but PR run [39081422004](https://github.com/xdgf558/station-cat-music-ios/actions/runs/39081422004) failed at the A11 process-boundary step. Neither outcome substitutes for the other.

The failed artifact was downloaded and checked against its GitHub SHA-256: `25f97c2be14e8fb21db1e4ca676b5bdc7c7f2f0db6119578a8964028936e8c46`. It shows two hosts for the same CRASH invocation:

- PID 8505 entered the scenario and reached the durable A11 boundary at `1792282329741` ms.
- The launcher reported PID 8510. The driver correctly rejected the boundary belonging to PID 8505 instead of accepting evidence from a different process.
- PID 8510 subsequently entered the same CRASH scenario and repeated setup/refresh. Failure diagnostics show two requests (200, then 401) and a revoked fixture session. RECOVER did not start.

The driver issues one `simctl launch`, with no scenario retry. These records establish a second app process before launch completion was safely coordinated; they do not establish an internal CoreSimulator cause or a product authentication regression. A fast deliberate `_exit` before the launch command returns is the race this fix prevents.

## Change

The standalone probe now waits before fixture preparation, Keychain cleanup, authentication or refresh. Only after `simctl` exits successfully with a complete PID line does the driver atomically publish a one-use permit for that unique run, stage, mode and PID. The app checks the exact identity and exclusively claims the permit before starting the scenario. A second host, reused ticket, failed launch, partial PID line or missing acknowledgement cannot start authentication work.

Both CRASH and RECOVER use this protocol. The app's wait has a continuous-clock 60-second limit and the existing driver deadline still applies. There is no scenario relaunch/retry and no extension or replacement of the backend's real 120-second replay window. Boundary/FINISHED, different-PID and actual-process-exit checks remain mandatory. Permit files contain no credentials, are removed after the pair, and never enter a product target. Product Core, catalog UI, backend fixtures, configuration flags and build 10 release notes are unchanged by this increment.

## Validation

- Python driver regressions: 56/56 passed, including a delayed launcher that would relaunch a prematurely exiting host, failed/incomplete launches, pre-acknowledgement execution and stale/consumed tickets.
- Swift `NativeCrashBoundaryTests`: 15 passed, 2 dedicated process-only cases skipped as designed. New cases exercise waiting for the driver's publication, wrong PID/stage/mode, incomplete/oversized records, one-use claims and timeout without a claim.
- Local source guards, Python compilation and `git diff --check` passed. The Swift run used local Xcode 27.1 beta and `.build/catalog-launch-permit-20261018.xcresult`; it is not stable hosted CI acceptance.
- The new head still requires the complete stable CI run, including real A11–A13 execution. Website #232 at `4539e86` completed hosted CI run `39081326055` successfully and needs no source change for this fix.

No merge, website deployment, phone installation, upload or service activation is performed by this repair.
