# Agent Job Relay — Demo App

**Three server-side agent jobs, one lossy network, and a phone that never shows a draft as the answer.**

This SwiftUI app runs [`AgentJobRelay`](https://github.com/rajatslakhina/agent-job-relay-kit) against a scripted agent backend. It submits three multi-phase research jobs. The foreground stream is made to drop, duplicate and reorder events, silent pushes carry only a cursor, and you can kill the "app" mid-run. Every card shows what the device believes next to what the server's log says, and a ledger that accounts for every delivery.

## Why this matters

Long-running agent work runs on a server. The iPhone that started it has to submit it **exactly once**, follow progress over channels that are all at-least-once and unordered, survive being killed, and never present a result as more certain than the server says it is. This app makes those guarantees visible instead of asserting them.

## What you see

**Screenshots: none exist.** This run never launched the app on a Simulator, so nothing is captured or described here; [Verification](#verification) explains why.

On launch the app auto-plays the **Flaky** stream (seed 2026). The relay runs in a library actor. The simulated server releases one event per job per tick, and ticks are paced at 700 ms, so a run takes about 13 seconds (18 ticks).

| Job | What it demonstrates |
|---|---|
| *on-device vs cloud inference cost* | Completes. Reordered and duplicated events are buffered and dropped, so the final answer is never overwritten by an older draft. |
| *SwiftData migration risks* | The agent **fails** mid-research. The provisional "findings" result turns **unconfirmed** (orange ?), and only the finished plan stays final. |
| *App Store review timelines* | Has a 5,000-token **budget**. The relay auto-cancels once spend crosses it, and the server's terminal event decides the outcome. At the demo's pacing and seed the job ends **Cancelled at 7,670 tokens**: the brake can only act on usage the device has already received. |

The summary card shows **Submit calls → jobs** (4 → 3: the first submit's response is deliberately lost and retried with the same idempotency key), backfill fetches, relaunches and auto-cancels. When the server finishes, it reads **"All 3 jobs match the server log"**, a check computed by an independent fold of the server log, not by the reducer under test.

Controls (to use **Cancel** or **Kill & relaunch** while jobs are still running, press them during the first ~13 seconds, or press **Reset**, which leaves the run paused, and advance with **Step**; launching with `-paused` does the same):

- **Clean / Flaky / Hostile**: change the stream's drop, duplicate and reorder rates. Changing it restarts the run.
- **Play / Pause / Step**: drive ticks.
- **Kill & relaunch**: throws away the relay and every in-flight stream event, rebuilds the relay from the persisted checkpoint, and resumes: pending submissions are retried with their original keys, cancels are re-sent, and every live job is caught up with a fetch.
- **Cancel** on a running job: the card shows *Cancelling…* until the server's terminal event arrives. If the job finished first, it shows *Finished before cancel*.

Launch arguments: `-profile clean|flaky|hostile`, `-seed <n>`, `-paused`.

## How to run it

1. `git clone https://github.com/rajatslakhina/agent-job-relay-demo-app.git`
2. Open `Demo.xcodeproj` in Xcode 16 or later. Xcode resolves `AgentJobRelay` from GitHub with the requirement **Up to Next Major from 1.0.0**. `Package.resolved` is not committed, so a fresh clone resolves the newest 1.x release.
3. Select the **Demo** scheme and any iOS 17+ Simulator.
4. Build & Run (⌘R).

## How it's put together

- `Demo.xcodeproj` references the library as an `XCRemoteSwiftPackageReference` to `https://github.com/rajatslakhina/agent-job-relay-kit.git` with an `upToNextMajorVersion` requirement. There is no local path and no branch tracking.
- `Demo/DemoConfiguration.swift` holds the run configuration (chaos profile, seed, autoplay, events per tick, tick interval) that the library's `RelaySimulation` takes as input.
- `Demo/RelayDemoModel.swift` is a `@MainActor @Observable` model that drives the simulation actor. Each async continuation re-checks a run ID after every `await`, so work still finishing on a run you reset can never overwrite the new run's snapshot or status line. Ordering between steps, kills and cancels within one run comes from the library: `RelaySimulation` serialises its operations with a FIFO lock, so a kill always lands between two whole steps.
- `Demo/RelayDashboardView.swift` contains the dashboard. Every collection view has an empty state.

## Verification

**The app has not been run on a Simulator.** Computer-use access to Xcode and Simulator on the build machine was granted for this run. The first screenshot showed Xcode with an unrelated project already open: someone else's live work, with a debug console running. The run's rule is not to click through someone else's open work, so it stopped there. The app was never launched, and no screenshots were taken.

What the code has been through instead:

- `DemoConfiguration.swift` and `RelayDemoModel.swift` were type-checked against the library with Swift 6.0.3 on Linux, with warnings as errors.
- `RelayDashboardView.swift` and `DemoApp.swift` import SwiftUI, so they cannot be compiled on Linux. They were reviewed by hand, including by an independent reviewer.
- The numbers quoted above (18 ticks, 4 → 3 submit calls → jobs, 7,670 tokens, convergence) come from running the library's `RelaySimulation` at this app's settings (1 event per tick, seed 2026) on Linux. That is the same code the app drives, but not the app itself.

**CI:** [GitHub Actions](https://github.com/rajatslakhina/agent-job-relay-demo-app/actions) runs one `macos-15` job on every push to `main`:

1. `xcodebuild -resolvePackageDependencies`, which resolved `AgentJobRelay` **v1.0.0** from GitHub through the `XCRemoteSwiftPackageReference`.
2. `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'`.

That job passed on the first push. So the remote package resolves, and all four app files, including the two SwiftUI files that were never compiled before, build against the released library. It proves the app **compiles for** the iOS Simulator. It does not prove the app **runs** there, which, as stated above, has not been checked.
