# Shortcuts and Spotlight Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Alias, Create Random Alias and Disable Alias as App Intents, available in Spotlight and Shortcuts, sharing `AppModel` with the menu.

**Architecture:** New throwing `AppModel` methods carry all behavior and never touch `lastError`; the menu keeps its methods. A small `AliasLookup` feeds the alias entity query. The intents in `Ajour/Intents/` only map parameters, call `AppModel` and build dialog text.

**Tech Stack:** Swift 6, App Intents (macOS 26), Swift Testing, XcodeGen, SimpleLoginKit.

**Spec:** `docs/superpowers/specs/2026-11-10-app-intents-design.md`

## Global Constraints

- English for all code, comments, docs and commit messages; commit messages describe intent, one logical change per commit.
- Self-documenting code over comments; comments only for a non-obvious why, in the style of `AppModel.swift`.
- Deployment target macOS 26.0, Swift 6 strict concurrency; `AppModel` is `@MainActor`.
- Durations: 5 Minutes, 1 Hour, 24 Hours (`AliasDuration`). Enable default 1 Hour. Create default Never.
- Error texts come from `AppModel.userMessage(for:)`.
- The installed `/Applications/Ajour.app` is never launched, and no action is triggered against it. Run the Debug build only with `-AjourDemo YES`.
- Build and test:
  1. `xcodegen generate`
  2. `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS" -derivedDataPath build/DerivedData`
  3. Package tests: `swift test --package-path Packages/SimpleLoginKit`

## Review Focus

1. **Action arrives before launch finishes:** a background launch delivers the action before `applicationDidFinishLaunching`. It must wait, and fail with "not ready" only after 10 seconds. Tests: Task 1.
2. **The system cancels the action mid-toggle:** the enable or creation still completes and its timer is saved. Tests: Task 1, Task 2.
3. **Enable during an expiry disable:** must fail as busy, not report "stays enabled". Tests: Task 1.
4. **Alias deleted after it was picked or saved:** the action says it no longer exists, and resolution drops it. Tests: Task 1, Task 3.
5. **Empty or whitespace search text in Spotlight:** shows the suggestions, sends no search request. Tests: Task 3.

---

### Task 1: Throwing enable for actions

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/API/APIError.swift`, `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Timers/TimerEngine.swift` (replace the private `isAliasGone` with the shared check)
- Modify: `Ajour/AppModel.swift`
- Test: the existing APIError or TimerEngine test file in `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/`
- Test: `AjourTests/ActionEnableTests.swift` (new; same setup as `AliasActionsTests`, with a `copied: [String]` recorder like `AliasCreationTests`)

**Interfaces:**
- Produces:
  - `extension APIError { public static func meansAliasIsGone(_ error: any Error) -> Bool }`: true for `.server(status: 404, _)` and `.server(status: 400, message: "Unknown error")`
  - `enum AliasEnableOutcome: Equatable { case enabled, extended, alreadyEnabled }`
  - `struct EnabledAlias: Equatable { let email: String; let outcome: AliasEnableOutcome }`
  - `func enableAndCopy(aliasID: Int, email: String, for duration: AliasDuration) async throws -> EnabledAlias`. `email` is the picked entity's, used only for busy and gone messages; the copied and returned email is the one read from SimpleLogin.
  - `func waitUntilLoaded(within limit: Duration = .seconds(10)) async throws`
  - New cases `AliasActionError.busy(email: String)`, `.gone(email: String)`, `.notReady`, with messages in `userMessage(for:)`:
    - "\(email) is busy. Try again in a moment."
    - "\(email) no longer exists."
    - "Ajour isn't ready yet. Try again in a moment."

Behavior:
1. Throw `busy` when `changes[aliasID] != nil` or `engine.disablingAliasIDs.contains(aliasID)`.
2. Otherwise hold the `.enabling` mark and count as an enable in flight (`whileEnabling`). Then read the alias. A 404, or a 400 "Unknown error", becomes `gone`, via `APIError.meansAliasIsGone`.
3. Then branch:
   - a record exists → `engine.enable` → `.extended`;
   - enabled with no record → `.alreadyEnabled`, with no engine call;
   - otherwise → `engine.enable` → `.enabled`.
4. Call `recordEnabled(true, aliasID:)`, then copy.
5. The whole body runs in an unstructured `Task` that the method awaits, so the caller's cancellation doesn't reach it.
6. `waitUntilLoaded` returns once `phase != .loading`, otherwise throws `notReady` after `limit`. It must not block the main actor; use `Observations` or a sleep loop.

The menu's `perform(on:)` and its methods keep their exact behavior. Extract the shared body if useful, but the throwing path must not read or write `lastError`.

- [ ] **Step 1: Write the failing tests**
  - Package: `meansAliasIsGoneForMissingAliases` (404, 400 "Unknown error" → true; 403, 400 with another message, `.transport` → false).
  - `enablingADisabledAliasStartsATimerAndCopies`:
    - enqueue `GET /api/aliases/7` (disabled) twice and `POST /api/aliases/7/toggle` (enabled);
    - expect outcome `.enabled`, `copied == ["shop@example.com"]`, a record expiring in 3600 s, `requestCount(toggle) == 1`.
  - `enablingATimedAliasExtendsWithoutToggling`:
    - record for 7, alias read enabled;
    - expect `.extended`, `expiresAt == now + 3600`, no toggle request, copied.
  - `enablingAPermanentlyEnabledAliasLeavesItUntimed`:
    - alias read enabled, no record;
    - expect `.alreadyEnabled`, `engine.record(for: 7) == nil`, no toggle, copied.
  - `enableFailsAsBusyWhileTheAliasChanges`:
    - start the menu's `disableNow(aliasID: 7)` with `holdNext` on the toggle;
    - `enableAndCopy` throws `AliasActionError.busy(email: "shop@example.com")`;
    - nothing copied.
  - `enableFailsAsBusyDuringAnExpiryDisable`:
    - expired record, `holdNext` on the toggle, start `tick()`, wait until held;
    - `enableAndCopy` throws `busy`;
    - after release, no record.
  - `enablingADeletedAliasSaysItIsGone`: alias read 404 → throws `.gone(email:)`, nothing copied.
  - `enableWithUnreadableTimersChangesNothing`:
    - `UnavailableTimerStore`;
    - throws `TimerEngineError.storeUnavailable`, no toggle, nothing copied.
  - `enableSignedOutFails`: no key → throws `TimerEngineError.notSignedIn`.
  - `enableLeavesTheMenuErrorAlone`:
    - set `lastError` through a failing menu `enable`;
    - a successful `enableAndCopy` keeps it unchanged;
    - a failing `enableAndCopy` on a fresh model leaves `lastError == nil`.
  - `cancellingTheCallerStillFinishesTheEnable`:
    - `holdNext` the toggle;
    - start `enableAndCopy` in a `Task`, wait until held, cancel that task, release;
    - wait for the task;
    - expect a record for 7 and the copy.
  - `waitingForLaunchReturnsOnceStarted`: `makeModel()` without start; call `waitUntilLoaded`, then `model.start()`; it returns.
  - `waitingForLaunchGivesUp`: `waitUntilLoaded(within: .milliseconds(50))` on an unstarted model throws `AliasActionError.notReady`.
  - `newActionErrorsHaveMessages`: the three texts above.

- [ ] **Step 2: Run the tests to make sure they fail**

  Run: `xcodebuild test … -only-testing:AjourTests/ActionEnableTests`.

  Expected: build failure, because `enableAndCopy` is not defined.

- [ ] **Step 3: Implement it in `Ajour/AppModel.swift`**

- [ ] **Step 4: Run the tests to make sure they pass**

  Run `swift test --package-path Packages/SimpleLoginKit`, `ActionEnableTests`, then the full suite.

  Expected: all pass, including `AliasActionsTests` unchanged.

- [ ] **Step 5: Commit, in two commits**
  - `git commit -m "Share how a deleted alias is recognized"` (package)
  - `git commit -m "Let actions outside the menu enable an alias and copy its address"` (`Ajour/AppModel.swift`, `AjourTests/ActionEnableTests.swift`)

### Task 2: Throwing create and disable for actions

**Files:**
- Modify: `Ajour/AppModel.swift`
- Test: `AjourTests/ActionCreateAndDisableTests.swift` (new)

**Interfaces:**
- Consumes: Task 1's `AliasActionError.busy` and the unstructured-task pattern.
- Produces:
  - `func createRandomAliasAndCopy(expiringAfter duration: AliasDuration?) async throws -> Alias`
  - `func disable(aliasID: Int, email: String) async throws`

Behavior:
- `createAlias` gets an `announcesCopy: Bool` parameter.
  - `createRandomAlias` (menu) and `createCustomAlias` (New Alias window) pass `true`.
  - `createRandomAliasAndCopy` passes `false` and doesn't touch `lastError`.
- `disable` throws `busy` only when `changes[aliasID] != nil`. A running expiry disable is joined through `engine.disableNow`. It holds the `.disabling` mark and doesn't touch `lastError`.
- Both run their body in an unstructured task, like Task 1.

- [ ] **Step 1: Write the failing tests**
  - `actionCreationCopiesWithoutAnnouncing`: `copied == ["random@example.com"]`, `announced == []`.
  - `menuCreationStillAnnounces`: `createRandomAlias(expiringAfter: nil)`; `announced == ["random@example.com"]`.
  - `actionCreationWithExpiryStartsTheTimerFirst`: `.oneHour`; record expires in 3600 s; copied.
  - `actionCreationLeavesTheMenuErrorAlone`: failure (no response queued) throws `APIError.transport`; `lastError == nil`.
  - `cancellingTheCallerStillFinishesTheCreation`:
    - `holdNext` on `POST /api/alias/random/new`, cancel, release;
    - expect the alias copied and, with `.fiveMinutes`, a record.
  - `disableTurnsOffATimedAlias`: record for 7; enqueue read (enabled) and toggle (disabled); no record left afterwards.
  - `disablingADisabledAliasSucceeds`: read disabled; no toggle; no error.
  - `disableJoinsARunningExpiryDisable`:
    - expired record, `holdNext` the toggle, `tick()` held;
    - `disable` started, release;
    - both finish; exactly one toggle request.
  - `disableFailsAsBusyDuringAMenuAction`:
    - menu `enable` held on its toggle;
    - `disable` throws `busy(email: "shop@example.com")`.

- [ ] **Step 2: Run them to make sure they fail.** Expected: build failure, missing methods.

- [ ] **Step 3: Implement both methods and the `announcesCopy` parameter**

- [ ] **Step 4: Run the full suite.** Expected: all pass, including `AliasCreationTests`.

- [ ] **Step 5: Commit**

  `git commit -m "Let actions outside the menu create and disable aliases"`

### Task 3: Alias lookup for the picker

**Files:**
- Create: `Ajour/Intents/AliasLookup.swift`
- Test: `AjourTests/AliasLookupTests.swift`

**Interfaces:**
- Consumes: `APIError.meansAliasIsGone` (Task 1).
- Produces:
  - `@MainActor struct AliasLookup` with:
    - `init(appModel: AppModel, sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`
    - `func suggestions() async throws -> [Alias]`: `appModel.pinned` once `pinnedLoaded`; otherwise `api.aliases(page: 0, filter: .pinned)`. Signed out → `TimerEngineError.notSignedIn`.
    - `func search(_ text: String) async throws -> [Alias]`: trimmed empty → `suggestions()`. Otherwise sleep 300 ms, `try Task.checkCancellation()`, then `api.aliases(page: 0, query: text)`.
    - `func aliases(ids: [Int]) async throws -> [Alias]`: pinned ones from `appModel.pinned`, the rest via `api.alias(id:)`. Gone IDs are dropped; other errors rethrow. The result keeps the order of `ids`.

- [ ] **Step 1: Write the failing tests**
  - App:
    - `suggestionsArePinnedAliasesOnceLoaded`: no extra request after `refreshPinned`.
    - `suggestionsLoadPinnedAliasesBeforeTheListHas`: one `GET /api/v2/aliases` with the `pinned` query item.
    - `searchSendsOneRequestAfterTheDelay`: sleep recorder gets `.milliseconds(300)`; one `POST /api/v2/aliases`.
    - `blankSearchShowsSuggestions`: `"  "` → pinned list; no POST.
    - `cancelledSearchSendsNothing`: sleep throws `CancellationError` → rethrows; no POST.
    - `resolvingUsesPinnedAliasesAndReadsTheRest`: ids `[9, 7]`, 7 pinned → one GET for 9; order `[9, 7]`.
    - `resolvingDropsDeletedAliases`: GET 9 → 404 → `[]`.
    - `resolvingFailsOnOtherErrors`: no response → throws `APIError.transport`.

- [ ] **Step 2: Run them to make sure they fail.** Expected: build failures.

- [ ] **Step 3: Implement `AliasLookup`**

- [ ] **Step 4: Run the app suite.** Expected: all pass.

- [ ] **Step 5: Commit**

  `git commit -m "Look up aliases for an action's alias picker"`

### Task 4: The intents, Spotlight registration and docs

**Files:**
- Create:
  - `Ajour/Intents/AliasEntity.swift`
  - `Ajour/Intents/ActionOptions.swift`
  - `Ajour/Intents/ActionDialog.swift`
  - `Ajour/Intents/AliasIntents.swift`
  - `Ajour/Intents/AjourShortcuts.swift`
- Modify: `Ajour/AppDelegate.swift`, `docs/mvp-manual-checks.md`, `README.md` (features list, if it has one)
- Test: `AjourTests/ActionDialogTests.swift`

**Interfaces:**
- Consumes:
  - `enableAndCopy`, `createRandomAliasAndCopy`, `disable`, `waitUntilLoaded` (Tasks 1, 2);
  - `AliasLookup` (Task 3).
- Produces:
  - `struct AliasEntity: AppEntity` with `id: Int`, `email: String`, `note: String?`, `init(_ alias: Alias)`. Display: title `email`, subtitle `note`. `defaultQuery = AliasEntityQuery()`.
  - `struct AliasEntityQuery: EntityStringQuery`, `@MainActor`, with `@Dependency var appModel: AppModel`. `suggestedEntities`, `entities(matching:)` and `entities(for:)` map `AliasLookup` results, after `waitUntilLoaded()`.
  - `enum EnableDuration: String, AppEnum`: `fiveMinutes`, `oneHour`, `twentyFourHours`, titles "5 Minutes", "1 Hour", "24 Hours", with `var aliasDuration: AliasDuration`.
  - `enum CreationExpiry: String, AppEnum`: `never`, `fiveMinutes`, `oneHour`, `twentyFourHours`, with `var aliasDuration: AliasDuration?`.
  - `enum ActionDialog` with these exact strings, where `d` is "5 minutes", "1 hour" or "24 hours":
    - `static func enabled(_ alias: EnabledAlias, duration: AliasDuration) -> String`:
      - `.enabled` → "\(email) is enabled for \(d) and copied."
      - `.extended` → "\(email) stays enabled for \(d) from now and is copied."
      - `.alreadyEnabled` → "\(email) is already enabled and copied. Ajour won't turn it off."
    - `static func created(email: String, expiringAfter: AliasDuration?) -> String`:
      - "\(email) is created and copied."
      - "\(email) is created for \(d) and copied."
    - `static func disabled(email: String) -> String`: "\(email) is disabled."
  - Intents `EnableAliasIntent` (parameters `alias: AliasEntity`, `duration: EnableDuration = .oneHour`), `CreateRandomAliasIntent` (`expiry: CreationExpiry = .never`) and `DisableAliasIntent` (`alias: AliasEntity`):
    - `@MainActor perform()` calls `waitUntilLoaded()` first.
    - Errors are rethrown as a `LocalizedError` whose description is `AppModel.userMessage(for:)`.
    - Enable and Create return `some IntentResult & ReturnsValue<String> & ProvidesDialog`, with the email as value. Disable returns `ProvidesDialog`.
    - `openAppWhenRun` stays false.
  - `struct AjourShortcuts: AppShortcutsProvider` with one App Shortcut per intent. Every phrase contains `\(.applicationName)`, for example "Enable alias in \(.applicationName)".
  - `AppDelegate.init`: `AppDependencyManager.shared.add(dependency: model)` right after `makeAppModel()`, skipped when `isHostingUnitTests`.

- [ ] **Step 1: Write the failing tests**
  - `ActionDialogTests`: every string above, for each duration.
  - `optionsMapToTheMenuDurations`:
    - `EnableDuration.allCases.map(\.aliasDuration) == AliasDuration.allCases`;
    - `CreationExpiry.never.aliasDuration == nil`.

- [ ] **Step 2: Run them to make sure they fail.** Expected: build failure.

- [ ] **Step 3: Implement the files above and the registration**

- [ ] **Step 4: Build and check the metadata**
  - Run the full test suite: everything passes.
  - In the build log of `xcodebuild build … -scheme Ajour`, look for the `ExtractAppIntentsMetadata` step for the app target.
  - Check that `build/DerivedData/Build/Products/Debug/Ajour.app/Contents/Resources/Metadata.appintents/extract.actionsdata` exists and names the three intents: `grep -c "EnableAliasIntent\|CreateRandomAliasIntent\|DisableAliasIntent"` returns at least 3.
  - If the step is missing, fix the XcodeGen settings until it runs.

- [ ] **Step 5: Update `docs/mvp-manual-checks.md`**

  Add a section "Shortcuts and Spotlight". It is run by the owner with an installed build, never with a Debug build next to the installed app. Steps:
  1. Spotlight "Enable alias in Ajour": pick a pinned alias, keep 1 Hour. The dialog appears, the address pastes, and the menu shows the timer.
  2. The same alias again: the dialog says "stays enabled for 1 hour from now".
  3. A permanently enabled alias: "already enabled", and the menu shows no timer.
  4. Typing in the picker finds an unpinned alias.
  5. "Create random alias in Ajour" with expiry 5 Minutes: the address pastes, the menu shows the timer, and no "copied" notification appears.
  6. "Disable alias in Ajour": the alias is off in the menu.
  7. A personal shortcut using Enable Alias, run from Raycast with a hotkey: the address pastes.
  8. Quit Ajour, run "Create random alias in Ajour": Ajour launches in the background and the action succeeds.
  9. Sign out, run Enable Alias: the error says "Not signed in. Set up your API key first."

- [ ] **Step 6: Commit**

  `git add Ajour/Intents Ajour/AppDelegate.swift AjourTests/ActionDialogTests.swift docs/mvp-manual-checks.md`

  `git commit -m "Offer alias actions in Shortcuts and Spotlight"`, with a body: the three actions, clipboard, the picker, closes #9.

### After the tasks

- Run the full suite and `swift test --package-path Packages/SimpleLoginKit` once more.
- Launch the Debug build with `-AjourDemo YES`. Check that the app starts and the menu works. Don't trigger intents from Spotlight; the installed app shares the bundle ID.
- Open the PR "Shortcuts and Spotlight actions" (closes #9). In the same PR, document the tag ruleset "Protect release tags" in `docs/ci.md`, as a separate commit: tags `v*` can only be created, moved or deleted by admins, who bypass the ruleset.
