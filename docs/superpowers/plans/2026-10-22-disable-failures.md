# Retries and Failed Disables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retry every SimpleLogin request on short hiccups, show and report failed timer disables right away with their reason, and let sign-out explain what blocks it and proceed anyway (issues #16, #17, #18, #23).

**Architecture:**
- **Retries:** a `RetryPolicy` in SimpleLoginKit drives the request retries in `SimpleLoginAPI` and the read-then-toggle retries in `AliasSwitch`. `TimerEngine` and `AppModel` take the policy as a parameter, so tests run with `.once` or a zero delay.
- **Failure state:** `TimerEngine` keeps the failure state, now with a `DisableProblem` reason. It reports at once, except during a quiet period after wake or launch, and remembers refusals in the timer file.
- **Display:** the menu, All Aliases, notifications and sign-out read that state through `AliasMenuState`'s two new cases and the engine's new outcomes.

**Tech Stack:** Swift 6, SwiftUI, AppKit, UserNotifications, Observation, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-22-disable-failures-design.md`. All copy, delays, counts and budgets come from it.

## Global Constraints

- macOS 26.0, Xcode 27.1, Swift language mode 6, strict concurrency. No third-party dependencies.
- Copy is exact as in the spec (straight apostrophes, `…`, `·`). Copy in tests is asserted verbatim.
- Retry policy: 3 tries in total, 2 seconds apart (`RetryPolicy.standard`).
- Background delays after a failed expiry disable: 5, 10, 20, 40, 60, then 120 seconds.
- The quiet period after wake lasts 120 seconds.
- Sign-out budget is 30 seconds; quit keeps 5 seconds.
- The API key is never logged or put into any message.
- Every task keeps both suites green: `swift test --package-path Packages/SimpleLoginKit` and `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS"`. Run `xcodegen generate` after adding or removing files.
- Tests never wait for real retry delays: they use `RetryPolicy.once` or `RetryPolicy(attempts: 3, delay: .zero)`.
- Commit messages describe intent, in English, one line for small changes.

## Review Focus

1. **Launch before the network is up:** an app launched at login with expired timers must not notify within the first 2 minutes. The spec names wake only; launch gets the same quiet period (plan's call). Test in Task 5.
2. **Pinned alias whose disable fails:** it must show the failed state in the Pinned section, not only under Timers. Test in Task 6.
3. **Try Again after things moved on:** Try Again from a notification or menu, after the alias was meanwhile disabled, extended, or kept enabled, must do nothing. Tests in Tasks 3 and 7.
4. **Quit while a request waits between tries:** the 5-second quit budget must still end the work, and the wait must not outlive it. Tests in Tasks 1 and 4.
5. **Old timer files:** a timer file written before this change, without the new field, must still load. Test in Task 3.

---

## File Structure

```
Packages/SimpleLoginKit/Sources/SimpleLoginKit/
  API/RetryPolicy.swift          new: RetryPolicy
  API/SimpleLoginAPI.swift       retries per request, unsent-error classification
  API/APIError.swift             isTransient
  API/AliasAPI.swift             toggle and creates marked as not repeatable
  Toggling/AliasSwitch.swift     read-again-and-toggle retries
  Timers/DisableProblem.swift    new: DisableProblem
  Timers/TimerEngine.swift       reporting, quiet period, retryNow, disabling set, sign-out outcome, discardAll
  Timers/TimerRecord.swift       refusalReportedAt
  Menu/MenuSections.swift        AliasMenuState.disableFailing/.disableRefused, state(of:failure:now:)
Ajour/
  AppModel.swift                 retry/signOutBudget parameters, quiet period, retryDisable, activities, sign-out
  Design/AliasStatus.swift       stuck kind, words, VoiceOver
  Design/StateSymbol.swift       stuck symbol
  Menu/MenuEntry.swift           retryDisable action, rows for the new states
  Menu/StatusMenuController.swift
  AllAliasesModel.swift, Views/AllAliasesView.swift
  System/NotificationController.swift
  SettingsModel.swift, Views/SettingsView.swift
  AppDelegate.swift              wiring
docs/mvp-manual-checks.md
```

---

### Task 1: Retry requests in SimpleLoginAPI

**Files:**
- Create: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/API/RetryPolicy.swift`
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/API/SimpleLoginAPI.swift`, `API/APIError.swift`, `API/AliasAPI.swift`
- Modify: `Ajour/AppModel.swift` (init parameter only)
- Modify (tests): `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/Support/StubTransport.swift`, `SimpleLoginAPITests.swift`, other package tests that expect a single failing request. Also every `AppModel(` construction in `AjourTests/` passes `retry: .once`.

**Interfaces:**
- Produces:
  ```swift
  public struct RetryPolicy: Equatable, Sendable {
      public let attempts: Int
      public let delay: Duration
      public init(attempts: Int, delay: Duration)
      public static let standard: RetryPolicy  // 3 attempts, 2 s
      public static let once: RetryPolicy      // 1 attempt, .zero
  }
  SimpleLoginAPI.init(apiKey: String, baseURL: URL = defaultBaseURL,
                      transport: any HTTPTransport = URLSessionTransport(),
                      retry: RetryPolicy = .standard)
  extension APIError { public var isTransient: Bool }
  // AppModel.init gains `retry: RetryPolicy = .standard`, passed to every SimpleLoginAPI it creates.
  ```

**Rules:**
- **Transient:**
  - `URLError`s, except `.cancelled`;
  - HTTP 429;
  - HTTP 500–599.
- **Never sent:** `.notConnectedToInternet`, `.cannotFindHost`, `.cannotConnectToHost`, `.dnsLookupFailed`.
- **Retry scope:**
  - Repeatable requests are retried on every transient failure. These are every `GET`, the search `POST`, and `setPinned`.
  - `toggle`, `createRandomAlias` and `createCustomAlias` are retried only when the failure was never sent.
- Between tries, wait `retry.delay` with `Task.sleep`. When the task is cancelled, stop and rethrow the last error.
- Classify the `URLError` before it is mapped to `APIError.transport`. `isTransient` is true for `.transport` and for `.server` with status 429 or 500–599.

- [ ] **Step 1: Add `StubTransport.enqueue(error: URLError)` and write the failing tests in `SimpleLoginAPITests.swift`**

Use `let quick = RetryPolicy(attempts: 3, delay: .zero)`.
```swift
@Test func aTransientFailureIsRetriedUntilItSucceeds() // .timedOut, 503, then 200 user_info → succeeds; stub.requests.count == 3
@Test func aRequestIsTriedAtMostThreeTimes()           // 4 × 503 → throws .server(status: 503, …); requests.count == 3
@Test(arguments: [400, 401, 403, 404]) func rejectionsAreNotRetried(status: Int) // requests.count == 1
@Test func rateLimitingIsRetried()                     // 429 then 200 → requests.count == 2
@Test(arguments: [URLError.Code.timedOut, .networkConnectionLost])
func aToggleIsNotRepeatedAfterItMayHaveArrived(code: URLError.Code) // toggle throws; requests.count == 1
@Test func aToggleAnsweredWithAServerErrorIsNotRepeated()           // 502 → requests.count == 1
@Test(arguments: [URLError.Code.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
func aToggleThatNeverLeftIsRetried(code: URLError.Code)             // error then 200 → requests.count == 2
@Test func aNewRandomAliasIsNotRepeatedAfterATimeout()              // .timedOut → requests.count == 1
@Test func cancellingDuringTheWaitStopsRetrying() // delay .seconds(10), 3 × 503; cancel after first request → throws; requests.count == 1
@Test func theStandardPolicyTriesThreeTimesTwoSecondsApart() // #expect(RetryPolicy.standard == RetryPolicy(attempts: 3, delay: .seconds(2)))
@Test func transientErrorsAreNetworkFailuresRateLimitsAndServerErrors()
// .transport, .server(429), .server(500), .server(503) → true; .unauthorized, .server(403), .server(404), .decoding → false
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SimpleLoginKit --filter SimpleLoginAPITests`
Expected: compile failure on `RetryPolicy` / `enqueue(error:)`.

- [ ] **Step 3: Implement `RetryPolicy`, the retry loop in `SimpleLoginAPI.send`, and `isTransient`**

Give `send` a `repeatable: Bool = true` parameter. `toggle` and both creates pass `false`.

- [ ] **Step 4: Thread the policy through `AppModel` and make existing tests explicit**

- Add `retry: RetryPolicy = .standard` to `AppModel.init`. Use it at both `SimpleLoginAPI(...)` sites (`AppModel.swift:120`, `:151`).
- In `AjourTests`, pass `retry: .once` to every `AppModel(` construction (`grep -rn "AppModel(" AjourTests`).
- In package tests that expect one failed request, pass `retry: .once`.

- [ ] **Step 5: Run both suites**

Expected: all green. Test durations are unchanged, so no real waits slipped in.

- [ ] **Step 6: Commit**

```bash
git commit -m "Retry SimpleLogin requests that fail for a moment"
```

---

### Task 2: Retry switching an alias without toggling twice

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Toggling/AliasSwitch.swift`, `Timers/TimerEngine.swift` (init parameter only), `Ajour/AppModel.swift`
- Modify (tests): `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/Support/FakeAliasAPI.swift`, `AliasSwitchTests.swift`, `TimerEngineTests.swift` (`makeEngine` passes `retry: .once`)

**Interfaces:**
- Consumes: `RetryPolicy`, `APIError.isTransient` (Task 1).
- Produces:
  - `AliasSwitch.init(api: any AliasAPI, retry: RetryPolicy = .standard)`.
  - `TimerEngine.init(store: any TimerStore, now: @escaping @Sendable () -> Date = Date.init, retry: RetryPolicy = .standard)`. The engine passes `retry` to every `AliasSwitch` it creates.
  - `AppModel` passes its `retry` to `TimerEngine` and to its own `AliasSwitch(api:retry:)` calls.

**Rule:**
1. Read the alias. If it is already in the wanted state, return it.
2. Otherwise toggle it.
3. If the toggle throws a transient `APIError` and fewer than `retry.attempts` toggles were sent, wait `retry.delay` and go back to step 1.
4. Any other error, or a read error, is thrown. Reads are already retried by `SimpleLoginAPI`.

- [ ] **Step 1: Extend `FakeAliasAPI` and write the failing tests**

- `FakeAliasAPI` gains `toggleErrors: [Error]`, popped by `toggle` before it flips.
- It also gains `toggleErrorsAfterApplying: [Error]`, popped after the flip and thrown anyway.

Tests use `AliasSwitch(api: api, retry: RetryPolicy(attempts: 3, delay: .zero))`.
```swift
@Test func aToggleThatFailedAfterArrivingIsNotRepeated()
// alias 1 enabled; toggleErrorsAfterApplying = [APIError.transport("timed out")]
// ensureDisabled → returns enabled == false; toggleCalls.count == 1; aliases[1]?.enabled == false
@Test func aToggleThatFailedIsRetriedAfterReadingAgain()
// toggleErrors = [APIError.server(status: 503, message: nil)] → disabled; aliasCalls.count == 2; toggleCalls.count == 1
@Test func atMostThreeTogglesAreSent()
// toggleErrors = 3 × APIError.transport("offline") → throws .transport; aliasCalls.count == 3
@Test func aRejectedToggleIsNotRetried()
// toggleErrors = [APIError.server(status: 403, message: nil)] → throws; aliasCalls.count == 1
@Test func anExpiryDisableSurvivesTwoFailedToggles()   // in TimerEngineTests
// engine with retry: RetryPolicy(attempts: 3, delay: .zero); toggleErrors = 2 × transport; processDue → [.disabled(…)]
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SimpleLoginKit --filter "AliasSwitchTests|TimerEngineTests"`

- [ ] **Step 3: Implement the loop in `AliasSwitch.ensure(enabled:aliasID:)`, then add the engine and `AppModel` parameters**

- [ ] **Step 4: Run both suites.** Expected: all green.

- [ ] **Step 5: Commit**

```bash
git commit -m "Retry switching an alias by reading its state again first"
```

---

### Task 3: Report failed expiry disables right away, with their reason

**Files:**
- Create: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Timers/DisableProblem.swift`
- Modify: `Timers/TimerEngine.swift`, `Timers/TimerRecord.swift`
- Modify (to compile only): `Ajour/System/NotificationController.swift`, which matches `.disableKeepsFailing(let aliasID, let email, _)`. The copy follows in Task 7.
- Test: `TimerEngineTests.swift`, `TimerStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum DisableProblem: Equatable, Sendable {
      case unreachable, notResponding(status: Int), keyRejected, refused, other
      public init(error: any Error)
      // .transport / URLError → .unreachable; .server(429 or 500..<600) → .notResponding(status)
      // .unauthorized → .keyRejected; .server(403) → .refused; else .other
  }
  public enum DisableFailure { case transient(problem: DisableProblem, attempts: Int, nextRetryAt: Date, reported: Bool); case unauthorized; case forbidden }
  public enum TimerEvent { case disabled(aliasID:email:); case disableKeepsFailing(aliasID: Int, email: String, problem: DisableProblem); case disableForbidden(aliasID:email:); case unauthorized }
  TimerEngine.failureReportsResumeAt: Date?            // public var; no reports before this date
  TimerEngine.disablingAliasIDs: Set<Int>              // public private(set), observable; aliases with a disable in flight
  TimerEngine.retryNow(aliasID: Int)                   // a transient failure becomes due now; anything else: no-op
  TimerRecord.refusalReportedAt: Date?                 // Codable, optional, so old files decode
  ```

**Rules:**
- Remove `failureReportDelay` and `firstFailedAt`. Set `retryDelays = [5, 10, 20, 40, 60, 120]`.
- A transient failure is reported on its first failed attempt, unless `now < failureReportsResumeAt`. In that case it is reported on the first failed attempt at or after that date. It is reported once per episode, as today.
- **Refusals** (`markForbidden`):
  - Report only when the record's `refusalReportedAt` is nil.
  - Then set it to `now` and save.
  - The refused state itself (`failures[aliasID] = .forbidden`) is set either way.
- `disablingAliasIDs` mirrors the keys of `disablesInFlight`. It is updated where an attempt starts and ends.

- [ ] **Step 1: Write the failing tests**

Rewrite `transientFailureKeepsRecordAndBacksOff`, `backoffCapsAtSixtySeconds` and `persistentFailureReportedOnceAfter120Seconds` to the new rules, then add the new tests.
```swift
@Test func aFailedExpiryDisableIsReportedRightAwayWithItsReason()
// errors = [APIError.transport("offline")]; advance 300 → processDue == [.disableKeepsFailing(aliasID: 1, email: "one@example.com", problem: .unreachable)]
// failures[1] == .transient(problem: .unreachable, attempts: 1, nextRetryAt: expiry + 5, reported: true)
@Test func aFailingDisableIsReportedOnlyOnce()           // 100 errors, loop to expiry + 200 → exactly 1 report, at expiry
@Test func backoffCapsAtTwoMinutes()                     // delays == [5, 10, 20, 40, 60, 120, 120]
@Test func aServerErrorIsReportedWithItsStatus()         // .server(status: 503, …) → problem == .notResponding(status: 503)
@Test func failuresDuringTheQuietPeriodAreReportedAfterIt()
// failureReportsResumeAt = expiry + 120; 100 errors; loop to expiry + 200 → 1 report at expiry + 135
@Test func retryNowMakesAFailedDisableDueRightAway()     // after failure: retryNow(aliasID: 1) → nextDueDate() == clock.now; processDue → .disabled
@Test func retryNowWithoutAFailureChangesNothing()      // running timer, retryNow → nextDueDate() == expiry
@Test func aRefusalIsReportedOncePerTimerEvenAfterRelaunch()
// refused → event; new TimerEngine on the same store → processDue: no event, failures[1] == .forbidden; store.records[0].refusalReportedAt == expiry
@Test func aRefusalAfterAKeyChangeStaysSilent()          // refused, resumeAfterKeyChange(), refused again → no second event
@Test func anAliasIsDisablingWhileItsDisableRuns()       // GatedAliasAPI: during processDue disablingAliasIDs == [1]; after: []
@Test func disableProblemsFollowTheError()               // table for DisableProblem(error:)
@Test func aTimerFileWithoutRefusalStillLoads()          // TimerStoreTests: JSON without the key → refusalReportedAt == nil
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SimpleLoginKit --filter "TimerEngineTests|TimerStoreTests"`

- [ ] **Step 3: Implement `DisableProblem` and the engine changes, and fix the `NotificationController` pattern**

- [ ] **Step 4: Run both suites.** Expected: all green.

- [ ] **Step 5: Commit**

```bash
git commit -m "Report failed timer disables right away and refusals once per timer"
```

---

### Task 4: Let the engine explain what stays enabled and forget timers on request

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Timers/TimerEngine.swift`
- Modify (to compile only): `Ajour/AppModel.swift`. `disableEverything()` returns `engine.disableAll(within:) == .allDisabled`; sign-out reasons come in Task 8.
- Test: `TimerEngineTests.swift`

**Interfaces:**
- Consumes: `DisableProblem` (Task 3).
- Produces:
  ```swift
  public enum DisableAllOutcome: Equatable, Sendable {
      case allDisabled
      case stillEnabled([Int: DisableProblem])   // by alias ID, every record left
      case timerDataUnreadable
  }
  TimerEngine.disableAll(within budget: Duration) async -> DisableAllOutcome
  TimerEngine.discardAll() throws                // drops every record and failure, saves; throws .storeUnavailable on loadError
  TimerEngineError.accountChanged                // new case
  ```

**Rules:**
- **Problems in `disableAll`:**
  - Each record left after `disableAll` gets its problem from its attempt's outcome: `.unauthorized` → `.keyRejected`, `.forbidden` → `.refused`, `.failed(error)` → `DisableProblem(error:)`.
  - A cancelled attempt, or one that never finished within the budget, → `.unreachable`.
  - With no API, every record → `.unreachable`.
- **`enable(aliasID:for:)`:**
  - Capture `keyGeneration` before switching.
  - If it changed by the time the alias is enabled, start no timer. Disable the alias with the same switch (best effort) and throw `.accountChanged`.

- [ ] **Step 1: Write the failing tests** (update the existing `disableAll` tests to the new return type)

```swift
@Test func disableAllReportsWhyAliasesStayEnabled()     // errors transport → .stillEnabled([1: .unreachable])
@Test func disableAllReportsARefusedAlias()             // 403 → .stillEnabled([1: .refused])
@Test func disableAllReportsARejectedKey()              // 401 → .stillEnabled([1: .keyRejected])
@Test func disableAllCountsAnUnfinishedDisableAsUnreachable() // GatedAliasAPI, budget .milliseconds(50) → .stillEnabled([1: .unreachable])
@Test func disableAllWithUnreadableTimerData()          // → .timerDataUnreadable
@Test func discardAllForgetsEveryTimer()                // records and failures empty, store.records empty, aliases untouched
@Test func anEnableFinishingAfterSignOutStartsNoTimerAndDisablesTheAliasAgain()
// GatedAliasAPI: start enable(aliasID: 1, …); waitUntilHolding(1); engine.api = nil; open
// → throws TimerEngineError.accountChanged; records.isEmpty; api.aliases[1]?.enabled == false
```

- [ ] **Step 2: Run them and see them fail.** `swift test --package-path Packages/SimpleLoginKit --filter TimerEngineTests`

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run both suites.** Expected: all green.

- [ ] **Step 5: Commit**

```bash
git commit -m "Let the timer engine say why aliases stay enabled and drop timers on request"
```

---

### Task 5: Quiet period, Try Again, and "Disabling…" in the app model

**Files:**
- Modify: `Ajour/AppModel.swift`
- Test: `AjourTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `failureReportsResumeAt`, `retryNow(aliasID:)`, `disablingAliasIDs` (Task 3).
- Produces:
  - `AppModel.retryDisable(aliasID: Int) async`: calls `engine.retryNow(aliasID:)`, then `await tick()`.
  - `AppModel.didWake()`: sets `engine.failureReportsResumeAt = now + 120 s`, then schedules a tick. The wake observer calls it.
  - `start()` also sets `failureReportsResumeAt = now + 120 s` (Review Focus 1).
  - `activity(aliasID:)` and `menuState(at:).activities` include `.disabling` for every ID in `engine.disablingAliasIDs` that has no own activity.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func wakingDefersFailureReportsForTwoMinutes()    // didWake() → engine.failureReportsResumeAt == clock.now + 120
@Test func startingDefersFailureReportsForTwoMinutes()  // start() → same
@Test func anAliasBeingDisabledAtExpiryShowsDisabling()
// expired record 7; transport.holdNext("/api/aliases/7", …); tick in a Task; wait until held
// → model.activity(aliasID: 7) == .disabling; menuState(at:).activities[7] == .disabling; release; afterwards nil
@Test func tryAgainStartsTheNextDisableRightAway()
// expired record 7; tick fails (nothing queued); enqueue alias 7 enabled + toggle disabled; await retryDisable(aliasID: 7)
// → timerStore.records.isEmpty
```

- [ ] **Step 2: Run them and see them fail.**

Run: `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS" -only-testing:AjourTests/AppModelTests`

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run both suites.** Expected: all green.

- [ ] **Step 5: Commit**

```bash
git commit -m "Hold back failure reports after wake and launch, and show disables at expiry"
```

---

### Task 6: Show failed and refused disables as their own state

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Menu/MenuSections.swift`
- Modify: `Ajour/Design/AliasStatus.swift`, `Ajour/Design/StateSymbol.swift`
- Modify: `Ajour/Menu/MenuEntry.swift`, `Ajour/Menu/StatusMenuController.swift`
- Modify: `Ajour/AppModel.swift`, `Ajour/AllAliasesModel.swift`, `Ajour/Views/AllAliasesView.swift`, `Ajour/AppDelegate.swift`
- Test: `MenuSectionsTests.swift`, `AjourTests/AliasStatusTests.swift`, `StateSymbolTests.swift`, `MenuEntryTests.swift`, `AllAliasesModelTests.swift`

**Interfaces:**
- Consumes: `DisableFailure` and `engine.failures` (Task 3), `AppModel.retryDisable(aliasID:)` (Task 5).
- Produces:
  ```swift
  public enum AliasMenuState { case disabled, enabled, timed(…), disableFailing, disableRefused }
  MenuSections.make(pinned: [Alias], records: [TimerRecord], failures: [Int: DisableFailure], now: Date) -> MenuSections
  public static func MenuSections.state(of record: TimerRecord, failure: DisableFailure?, now: Date) -> AliasMenuState
  // .transient → .disableFailing; .forbidden → .disableRefused; .unauthorized or nil → .timed
  AliasStatus.Kind.stuck
  MenuAction.retryDisable(aliasID: Int)
  AllAliasesModel.retryDisable(_ alias: Alias) async
  AllAliasesModel.onReplaceAPIKey: () -> Void      // set by AppDelegate: onboarding.beginKeyReplacement(); windows.show(.onboarding)
  ```

**Copy and look** (from the spec):
- `.disableFailing`:
  - kind `.stuck`, words `Not disabled · retrying`, no turn-off time;
  - VoiceOver `<email>, not disabled, Ajour keeps trying`.
- `.disableRefused`:
  - kind `.stuck`, words `Can't disable with this key`;
  - VoiceOver `<email>, can't be disabled with the current API key`.
- With `pinned`, VoiceOver inserts `pinned` after the address as today. An activity still wins over both states.
- **Stuck symbol:**
  - the 14 pt ring with an exclamation mark inside: a vertical bar above the center and a dot below it;
  - tint `Palette.danger`, white when highlighted.
- **Menu submenu, after Copy Address and the separator:**
  - `.disableFailing`: `Try Again` (`arrow.clockwise`, `.retryDisable`), `Keep Enabled` (`infinity`), `Extend` submenu as for timed rows.
  - `.disableRefused`: `Keep Enabled` (`infinity`), `Replace API Key…` (`key`, `.reEnterAPIKey`).
  - All entries are disabled while the alias is busy.
- **All Aliases context menu:** the same entries, built from `AllAliasesModel.state(of:)`, which now uses `MenuSections.state(of:failure:now:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// MenuSectionsTests
@Test func aFailingDisableShowsAsFailing()        // record + .transient → timedUnpinned[0].state == .disableFailing
@Test func aRefusedDisableShowsAsRefused()        // + .forbidden → .disableRefused
@Test func aRejectedKeyKeepsTheTimedState()       // + .unauthorized → .timed(…)
@Test func aPinnedAliasShowsAFailedDisable()      // pinned alias with record + .transient → pinned[0].state == .disableFailing
// AliasStatusTests
@Test func aFailingDisableSaysItKeepsTrying()     // line == "Not disabled · retrying"; kind == .stuck
@Test func aRefusedDisableNamesTheKey()           // line == "Can't disable with this key"
@Test func voiceOverReadsFailedAndRefusedDisables()
// "shop@example.com, not disabled, Ajour keeps trying" / "shop@example.com, pinned, can't be disabled with the current API key"
@Test func anActivityWinsOverAFailedDisable()     // activity .disabling → kind .busy, "Disabling…"
// StateSymbolTests
@Test func stuckSymbolIsDangerColoredWithAnExclamationMark() // bar pixel above center filled in danger; pixel left of center inside the ring clear
// MenuEntryTests
@Test func aFailingAliasOffersTryAgainKeepOrExtend()  // titles ["Copy Address", separator, "Try Again", "Keep Enabled", "Extend"]
@Test func aRefusedAliasOffersKeepOrReplacingTheKey() // ["Copy Address", separator, "Keep Enabled", "Replace API Key…"]
// AllAliasesModelTests
@Test func anAliasWhoseDisableFailsShowsAsFailing()   // engine failure for a listed alias → state(of:) == .disableFailing
```

- [ ] **Step 2: Run them and see them fail.** Run both suites (filters: `MenuSectionsTests`; `-only-testing:AjourTests/AliasStatusTests` etc.).

- [ ] **Step 3: Implement**

- Pass `engine.failures` from `AppModel.menuSections` and `menuState(at:)`.
- Handle `.retryDisable` in `StatusMenuController.perform`.
- Add the two context-menu cases in `AliasRowActions`.
- Wire `onReplaceAPIKey` in `AppDelegate` after `windows` exists.

- [ ] **Step 4: Visual check**

1. Run the Debug build in demo mode. Temporarily make one demo alias fail in `DemoTransport` (not committed).
2. Confirm the stuck symbol and status line in light, dark, and a highlighted row.

- [ ] **Step 5: Run both suites.** Expected: all green.

- [ ] **Step 6: Commit**

```bash
git commit -m "Show failed and refused timer disables in the menu and All Aliases"
```

---

### Task 7: Notifications with the reason and Try Again

**Files:**
- Modify: `Ajour/System/NotificationController.swift`, `Ajour/AppDelegate.swift`, `docs/mvp-manual-checks.md`
- Test: `AjourTests/NotificationContentTests.swift`, `NotificationControllerTests.swift`

**Interfaces:**
- Consumes: `TimerEvent.disableKeepsFailing(aliasID:email:problem:)` (Task 3), `AppModel.retryDisable(aliasID:)` (Task 5).
- Produces:
  ```swift
  NotificationIdentifier.disableFailedCategory = "DISABLE_FAILED"
  NotificationIdentifier.tryAgainAction = "TRY_AGAIN"
  NotificationResponseRouter.aliasToRetry(categoryIdentifier:actionIdentifier:userInfo:) -> Int?  // TRY_AGAIN or the default action in DISABLE_FAILED
  NotificationController.init(center:onDisableRequested:onRetryRequested: @escaping (Int) -> Void)
  ```

**Copy:**
- **Failing:**
  - identifier `disable-failing-<id>`, title `Could not disable alias`, category `DISABLE_FAILED`, `aliasID` set;
  - body `<email> is still enabled. <reason> Ajour keeps trying.`
  - Reason by `DisableProblem`:
    - `.unreachable`: `SimpleLogin can't be reached.`
    - `.notResponding(s)`: `SimpleLogin isn't responding (error <s>).`
    - anything else: `SimpleLogin reported an error.`
- **Refused:**
  - identifier `disable-forbidden-<id>`, title `Could not disable alias`, no category, `aliasID` set;
  - body `The current API key can't change <email>, so it stays enabled. Keep it enabled or use a different key from the menu.`
- `activate()` registers both categories. `DISABLE_FAILED` has one action, `Try Again`.

- [ ] **Step 1: Write the failing tests** (replace `failingDisableAsksToCheckTheNetwork`, `persistentDisableFailureSaysTheAliasIsStillEnabled`, `forbiddenDisableSaysTheCurrentKeyCannotDisableTheAlias`)

```swift
@Test func aFailingDisableNamesTheReasonAndKeepsTrying()  // .unreachable body verbatim
@Test func aServerErrorNamesItsStatus()                     // .notResponding(503) → "… SimpleLogin isn't responding (error 503). Ajour keeps trying."
@Test func anUnexpectedErrorIsNamedGenerally()              // .other → "… SimpleLogin reported an error. Ajour keeps trying."
@Test func aFailingDisableOffersTryAgain()                  // categoryIdentifier == "DISABLE_FAILED"
@Test func aRefusedDisableExplainsTheWayOut()               // refused body verbatim, categoryIdentifier == ""
@Test func tryAgainRetriesTheAlias()                        // router: DISABLE_FAILED + TRY_AGAIN → aliasID
@Test func clickingAFailedDisableRetriesTheAlias()          // DISABLE_FAILED + default action → aliasID
@Test func tryAgainDisablesNothingElse()                    // aliasToDisable for DISABLE_FAILED == nil; aliasToRetry for MAIL_RECEIVED == nil
@Test func activatingRegistersTryAgain()                    // controller test: categories contain DISABLE_FAILED with action "TRY_AGAIN" titled "Try Again"
@Test func aTryAgainResponseIsForwarded()                   // handleResponse(DISABLE_FAILED, TRY_AGAIN, [aliasID: 7]) → onRetryRequested(7)
```

- [ ] **Step 2: Run them and see them fail.** `-only-testing:AjourTests/NotificationContentTests -only-testing:AjourTests/NotificationControllerTests`

- [ ] **Step 3: Implement**

`handleResponse` routes to retry or disable. `AppDelegate` passes `onRetryRequested: { aliasID in Task { await model.retryDisable(aliasID: aliasID) } }`.

- [ ] **Step 4: Update `docs/mvp-manual-checks.md`**

- Replace check 6 under its current heading. New wording: "Turn off Wi-Fi and let a shortened timer expire. Within seconds, one "Could not disable alias" notification names the reason and offers Try Again. The row reads "Not disabled · retrying". Turn Wi-Fi back on and click Try Again: the alias gets disabled, and the notification and row update."
- Add a check: "Sleep the Mac past a timer's end with Wi-Fi off, wake it, and turn Wi-Fi on within 2 minutes: no notification appears, and the alias gets disabled."

- [ ] **Step 5: Run both suites.** Expected: all green.

- [ ] **Step 6: Commit**

```bash
git commit -m "Name the reason in failed-disable notifications and offer Try Again"
```

---

### Task 8: Sign-out that explains what stays enabled and can proceed anyway

**Files:**
- Modify: `Ajour/AppModel.swift`, `Ajour/SettingsModel.swift`, `Ajour/Views/SettingsView.swift`, `docs/mvp-manual-checks.md`
- Test: `AjourTests/AppModelTests.swift`, `SettingsModelTests.swift`

**Interfaces:**
- Consumes: `DisableAllOutcome`, `discardAll()`, `TimerEngineError.accountChanged` (Task 4).
- Produces:
  ```swift
  struct StillEnabledAlias: Equatable { let email: String; let problem: DisableProblem }
  enum SignOutError: Error, Equatable {
      case aliasesStillEnabled([StillEnabledAlias], pendingEnables: Int)  // aliases sorted by email
      case timerDataUnreadable
      var title: String
      var userMessage: String
  }
  AppModel.init(…, signOutBudget: Duration = .seconds(30))  // disableBudget (5 s) stays for quit
  AppModel.signOut() async throws                            // waits for enables, disables, within signOutBudget
  AppModel.signOutAnyway() async throws                      // engine.discardAll(), delete key, signed out
  SettingsModel.blockedSignOut: SignOutError?                 // drives the new alert
  SettingsModel.signOutAnyway() async
  ```

**Rules:**
- **Pending enables:** `pendingEnables` is the count of enables and creations still in flight at the deadline (`enablesInFlight`).
- **`disableAfter` guard:** `disableAfter` checks `session` before `startTimer`. If the session changed, it starts no timer and throws `TimerEngineError.accountChanged`.
- **Alert title:**
  - total 1: `An Alias Is Still Enabled`;
  - otherwise: `<n> Aliases Are Still Enabled`.
  - The total counts listed aliases plus `pendingEnables`.
- **Alert message:**
  - One line per alias, `<email>: <reason>`, where the reason is:
    - `.unreachable`: `SimpleLogin can't be reached`
    - `.notResponding`: `SimpleLogin isn't responding`
    - `.refused`: `the API key can't change it`
    - `.keyRejected`: `the API key was rejected`
    - `.other`: `SimpleLogin reported an error`
  - Then, when `pendingEnables > 0`, a line `1 alias being enabled or created right now` or `<n> aliases being enabled or created right now`.
  - Then a blank line and `If you sign out anyway, it stays enabled.` (total 1) or `If you sign out anyway, these aliases stay enabled.`
- **Settings:**
  - Sign Out reads `Signing Out…` while `isSigningOut`.
  - The new alert has `Sign Out Anyway` (destructive) and `Cancel` (cancel role).
  - `timerDataUnreadable` and Keychain failures keep the existing "Could Not Sign Out" alert.

- [ ] **Step 1: Write the failing tests** (replace `signOutKeepsTheKeyWhenTimedAliasesStayEnabled`, `signOutErrorsExplainWhySignOutIsBlocked`, `aBlockedSignOutExplainsWhy`)

```swift
// AppModelTests
@Test func signOutNamesEachAliasThatStaysEnabledAndWhy()
// record 7, nothing queued → throws .aliasesStillEnabled([StillEnabledAlias(email: <record email>, problem: .unreachable)], pendingEnables: 0); key kept
@Test func aRefusedAliasBlocksSignOutWithItsReason()       // alias 7 enabled, toggle 403 → problem .refused
@Test func signOutWaitsForASlowEnableBeyondFiveSeconds()
// signOutBudget .seconds(10), disableBudget .milliseconds(100); hold the enable's read; start signOut; after 300 ms release
// → the enabled alias is disabled (toggle requested) and signOut succeeds
@Test func signOutCountsEnablesThatDidNotFinish()          // signOutBudget .milliseconds(200), held enable → pendingEnables == 1
@Test func signOutAnywayDiscardsEveryTimerAndRemovesTheKey() // records empty, key nil, phase .signedOut
@Test func disableAfterFinishingAfterSignOutStartsNoTimer()  // hold read, signOutAnyway, release → no record, throws handled
@Test func signOutErrorsExplainWhichAliasesStayEnabled()
// title/userMessage verbatim for: one unreachable alias; two aliases (.refused, .keyRejected) + 1 pending; timerDataUnreadable unchanged
// e.g. "a@example.com: SimpleLogin can't be reached\n\nIf you sign out anyway, it stays enabled."
// SettingsModelTests
@Test func aBlockedSignOutOffersSigningOutAnyway()        // blockedSignOut != nil, signOutError == nil, still signed in
@Test func signingOutAnywaySignsOut()                     // signOutAnyway() → phase .signedOut, blockedSignOut == nil
```

- [ ] **Step 2: Run them and see them fail.** `-only-testing:AjourTests/AppModelTests -only-testing:AjourTests/SettingsModelTests`

- [ ] **Step 3: Implement**

`disableEverything(within budget: Duration) -> DisableAllOutcome` is shared by quit (`disableBudget`) and sign-out (`signOutBudget`).

- [ ] **Step 4: Update `docs/mvp-manual-checks.md` check 7 under its current heading and add a check**

- The existing check stays as it is.
- Add: "With Wi-Fi off and a running timer, Sign Out shows "An Alias Is Still Enabled" naming the alias and "SimpleLogin can't be reached". Cancel keeps you signed in. Sign Out Anyway returns to onboarding, and the alias stays enabled in the web app."

- [ ] **Step 5: Visual check** of both alerts and the `Signing Out…` button in demo mode, light and dark.

- [ ] **Step 6: Run both suites.** Expected: all green.

- [ ] **Step 7: Commit**

```bash
git commit -m "Explain which aliases block sign-out and allow signing out anyway"
```
