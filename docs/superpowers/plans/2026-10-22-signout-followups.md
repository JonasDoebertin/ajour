# Follow-ups to Retries and Failed Disables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the edge cases from the review of #30: keep "key invalid" against concurrent passes (#33), explain enables cut off by a key change (#31), name timer-file save failures at sign-out (#32), and make Return and Escape behave in the sign-out alerts (#34).

**Architecture:** Small, independent changes in `TimerEngine` (SimpleLoginKit), `AppModel`, `SettingsModel`, and `SettingsView`. The engine reports more precisely, and the app maps the new cases to copy.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-22-signout-followups-design.md`. All copy comes from it.

## Global Constraints

- macOS 26.0, Xcode 27.1, Swift language mode 6, strict concurrency. No third-party dependencies.
- Copy is exact as in the spec (straight apostrophes). Copy in tests is asserted verbatim.
- Every task keeps both suites green: `swift test --package-path Packages/SimpleLoginKit` and `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS"`. Run `xcodegen generate` after adding or removing files.
- Tests never wait for real retry delays. Package engine tests build engines with `retry: .once`, and `AppModel` tests pass `retry: .once`.
- TDD: write the failing test first and record a real RED run.
- Commit messages describe intent, in English.

## Review Focus

1. **A 401 and a refusal ending in the same moment:** the alias stays "key invalid" and no refusal notification is posted. Test in Task 1.
2. **Sign-out followed by a sign-in with another key while an enable is still running:** the enable's outcome must use the state at the moment it ends (signed in again → show the message). Test in Task 2.
3. **Restoring after a failed key removal, when the timer file is also unwritable:** timers stay tracked in memory, and the timer-file message wins. Test in Task 3.

---

### Task 1: Keep "key invalid" against concurrent disables (#33)

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Timers/TimerEngine.swift` (`registerTransientFailure`, `markForbidden`, `markAllUnauthorized`)
- Test: `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/TimerEngineTests.swift`

**Interfaces:**
- Produces: no new API. When an alias's failure is `.unauthorized`, `registerTransientFailure` and `markForbidden` leave it unchanged and report nothing.
- Produces: `markAllUnauthorized` calls `onDisableRetriesStopped(aliasID)` for every alias whose failure was `.transient` before it is set to `.unauthorized`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aTransientFailureEndingAfterTheKeyBecameInvalidKeepsTheInvalidState()
// two expired aliases; alias 1's pass gets 401 while alias 2's attempt (from another pass, e.g. retryNow + processDue) is held,
// then alias 2's attempt fails with .transport → failures[2] == .unauthorized; no .disableKeepsFailing(aliasID: 2, …) event
@Test func aRefusalEndingAfterTheKeyBecameInvalidKeepsTheInvalidState()
// same, alias 2's attempt ends with 403 → failures[2] == .unauthorized; no .disableForbidden(aliasID: 2, …) event; refusalReportedAt stays nil
@Test func theKeyBecomingInvalidStopsRetryNotifications()
// alias 1 fails transiently (reported); next attempt gets 401 → onDisableRetriesStopped received [1]
```

- [ ] **Step 2: Run them and see them fail.** `swift test --package-path Packages/SimpleLoginKit --filter TimerEngineTests`
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Commit**

```bash
git commit -m "Keep the invalid-key state when another disable ends later"
```

---

### Task 2: Explain enables and timers cut off by a key change (#31)

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Timers/TimerEngine.swift` (`TimerEngineError`, `enable`)
- Modify: `Ajour/AppModel.swift` (`AliasActionError`, `disableAfter`, `perform(on:activity:_:)`, `userMessage(for:)`)
- Test: `TimerEngineTests.swift`, `AjourTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  TimerEngineError.accountChanged(email: String, disabledAgain: Bool)   // replaces the bare .accountChanged
  AliasActionError.timerNotStartedForPreviousAccount(email: String)     // thrown by AppModel.disableAfter after a session change
  ```
- **Rules in `perform`:** whether "signed out" is decided at the moment the action ends (`api == nil`).
  - `.accountChanged(_, disabledAgain: true)` while signed out: silent.
  - `.timerNotStartedForPreviousAccount` while signed out: silent.
  - Everything else goes through `fail(with:)`.
- **Copy (`userMessage(for:)`):**
  - `.accountChanged(email, true)` → `<email> was enabled for the previous account and has been disabled.`
  - `.accountChanged(email, false)` → `<email> was enabled for the previous account and could not be disabled.`
  - `.timerNotStartedForPreviousAccount(email)` → `<email> belongs to the previous account, so no timer was started.`

- [ ] **Step 1: Write the failing tests** (update existing tests that match the bare `.accountChanged`)

```swift
// TimerEngineTests
@Test func anEnableFinishingAfterSignOutStartsNoTimerAndDisablesTheAliasAgain()  // now throws .accountChanged(email: "one@example.com", disabledAgain: true)
@Test func anEnableWhoseAliasCannotBeDisabledAgainSaysSo()
// gated read; api = nil meanwhile; the re-disable fails (toggleErrors) → .accountChanged(email: "one@example.com", disabledAgain: false)
// AppModelTests
@Test func anEnableCutOffByAKeyReplacementSaysTheAliasWasDisabled()
// hold the enable's read; signIn with a second key; release → lastError == "<email> was enabled for the previous account and has been disabled."
@Test func anEnableCutOffBySignOutThatCouldNotDisableAgainSaysSo()
// hold; signOutAnyway; release; re-disable fails → lastError == "<email> was enabled for the previous account and could not be disabled."
@Test func anEnableFinishingAfterSignOutShowsNoError()                // existing, stays silent
@Test func disableAfterCutOffByAKeyReplacementSaysNoTimerStarted()
// → lastError == "<email> belongs to the previous account, so no timer was started."; no record
@Test func disableAfterFinishingAfterSignOutStartsNoTimer()            // existing, stays silent
```

- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Commit**

```bash
git commit -m "Explain when a key change cuts off an enable or a new timer"
```

---

### Task 3: Name timer-file save failures at sign-out (#32)

**Files:**
- Modify: `Ajour/AppModel.swift` (`SignOutError`, `signOutAnyway`), `Ajour/SettingsModel.swift` (`performSignOut`)
- Test: `AjourTests/AppModelTests.swift`, `SettingsModelTests.swift`

**Interfaces:**
- Produces: `SignOutError.timersNotSaved`.
  - title: `Could Not Sign Out`
  - userMessage: `The timer file could not be saved. Sign-out is blocked to avoid losing track of enabled aliases.`
- **Rules in `signOutAnyway`:**
  - `discardAll()` throwing `TimerEngineError.storeUnavailable` → `.timerDataUnreadable`; any other error → `.timersNotSaved`.
  - When `removeAccount()` fails and `restore(_:)` also throws → `.timersNotSaved`. Otherwise rethrow the key-removal error, as today.
- `SettingsModel` routes `.timersNotSaved` to `signOutError`, like `.timerDataUnreadable`.

- [ ] **Step 1: Write the failing tests** (rename or adjust the existing test that expects `.timerDataUnreadable` for a save failure)

```swift
@Test func signOutAnywayNamesAnUnsavableTimerFile()          // store fails to save → throws .timersNotSaved; key kept; records kept
@Test func aFailedRestoreAfterAFailedKeyRemovalNamesTheTimerFile()
// key store fails to delete, store fails to save on restore only → throws .timersNotSaved; engine.records.count == 1; still signed in
@Test func signOutErrorsExplainAnUnsavableTimerFile()        // title and userMessage verbatim
// SettingsModelTests
@Test func anUnsavableTimerFileDuringSignOutAnywayIsExplained() // signOutError == the message above; blockedSignOut == nil
```

- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.** If the test store can't fail only on a later save, give `InMemoryTimerStore` (AjourTests/Support) a way to fail from the n-th save on.
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Commit**

```bash
git commit -m "Say when sign-out stops because the timer file can't be saved"
```

---

### Task 4: Return and Escape in the sign-out alerts (#34)

**Files:**
- Modify: `Ajour/Views/SettingsView.swift`; create a small presenter or view under `Ajour/Views/` if needed
- Test: a new `AjourTests/SignOutAlertTests.swift`, if the chosen mechanism has testable configuration (e.g. an `NSAlert` factory: button order, `keyEquivalent`, `hasDestructiveAction`)

**Interfaces:**
- **"Sign Out of Ajour?":**
  - Return triggers Sign Out.
  - Escape triggers Cancel.
  - The copy is unchanged.
- **"An Alias Is Still Enabled" / "<n> Aliases Are Still Enabled":**
  - Return and Escape both trigger Cancel.
  - Sign Out Anyway is destructive, needs a click, and calls `settings.signOutAnyway()`.
  - Title and message come from `SignOutError.title` / `.userMessage`.
- **Mechanism:** your choice. An `NSAlert` run as a sheet on the Settings window is the first candidate. Verify that Escape really reaches Cancel when Cancel is also the Return button. If it doesn't, use a custom sheet with `.keyboardShortcut(.defaultAction)` on Cancel and `.onExitCommand` for Escape, styled like an alert.

- [ ] **Step 1: Write the failing tests** for whatever configuration is testable (button titles, order, key equivalents, destructive flag).
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Verify on screen in demo mode**
  1. Use the Debug build with `-AjourDemo YES` only, never the installed app or a real account. Make a temporary, uncommitted demo change so one timed alias fails to disable.
  2. For each alert, press Return and Escape and confirm the result: confirmation → Return signs out and Escape cancels; still-enabled alert → both cancel.
  3. Save screenshots to /tmp only. Revert the demo change and quit the app.
- [ ] **Step 5: Run both suites.** Expected: all green.
- [ ] **Step 6: Commit**

```bash
git commit -m "Let Return and Escape answer the sign-out alerts safely"
```
