# Ajour UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the redesign from issue #21: brand assets, the state system, a richer native menu, and redesigned All Aliases, Onboarding, New Alias, Settings, and notifications.

**Architecture:** Shared design vocabulary lives in `Ajour/Design/`: palette colors from the asset catalog, `AliasStatus` (status words, turn-off time, VoiceOver label), `StateSymbol` (drawn state images), and `ProblemMessage` (title/detail split). The menu keeps its data-then-render split: `MenuEntry` gains headers, notices, symbols, and dedicated alias rows, and `MenuRenderer` styles them, including white text and symbols on the highlighted row. Window views are rebuilt in SwiftUI against models that gain the few new behaviors the design adds.

**Tech Stack:** Swift 6, AppKit (`NSMenu`, `NSStatusItem`), SwiftUI, Observation, Swift Testing, XcodeGen, asset catalogs.

**Spec:** `docs/superpowers/specs/2026-10-22-ui-redesign-design.md`. All UI copy, symbols, colors, and layouts come from it; reference images are in `docs/design/ui-redesign/`.

## Global Constraints

- macOS 26.0, Xcode 27.1, Swift language mode 6, strict concurrency. No third-party dependencies.
- Copy is exact as in the spec, including `…`, `·`, `›`, `“”`, and `’`. Copy in tests is asserted verbatim.
- System font and text styles; never Inter. Countdown text uses monospaced digits.
- Only the six palette colors are custom; everything else uses system colors and materials.
- Every task keeps both suites green: `swift test --package-path Packages/SimpleLoginKit` and `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS"`. Run `xcodegen generate` after adding or removing files.
- Visual checks run the Debug build in demo mode (`-AjourDemo YES`, `-AjourDemoSignedOut YES`) and compare with the matching image in `docs/design/ui-redesign/` in both appearances. Never use a real account for screenshots.
- Commit messages describe intent, in English, one line for small changes.

## Review Focus

1. **Highlight leaks:** moving the pointer from one alias row to another, or closing the menu while a row is highlighted, must leave no row with white text on the normal background. Test in Task 6.
2. **Timer crosses a boundary while the menu is open:** a row going from timed to disabled, or from `1:00:00` to `59:59`, must update without a stale symbol or status. Tests in Tasks 3 and 6.
3. **12-hour locales:** `off at 2:12 PM`, not a fixed 24-hour format, and the VoiceOver label in the same format. Tests in Task 3.
4. **Extended timers:** after Extend, time left exceeds the original length; the pie share must stay within 0…1 and grow back. Test in Task 3.
5. **Stats endpoint unavailable:** All Aliases must still show a subtitle (loaded count) and never "0 of 0" while results load. Test in Task 7.

---

## File Structure

```
Ajour/Assets.xcassets/                 AppIcon, AccentColor, AccentText, StateOn, StateTimed, StateOff, Danger, MenuBarGlyphIdle, MenuBarGlyphTimers
Ajour/Design/Palette.swift             NSColor and Color accessors for the palette
Ajour/Design/AliasStatus.swift         AliasActivity, AliasStatus: words, turn-off time, pie share, VoiceOver label
Ajour/Design/StateSymbol.swift         16 pt state images (normal and highlighted)
Ajour/Design/ProblemMessage.swift      title/detail split of messages
Ajour/Menu/MenuEntry.swift             headers, notices, symbols, alias rows
Ajour/Menu/MenuRenderer.swift          styling, highlight handling, accessibility labels
Ajour/Menu/StatusMenuController.swift  glyph images, highlight forwarding
Ajour/Views/StateSymbolView.swift      SwiftUI wrapper of StateSymbol for list rows
Ajour/Views/*.swift                    redesigned windows
Packages/SimpleLoginKit/.../MenuSections.swift   timed state carries end time and length
Packages/SimpleLoginKit/.../API/AccountAPI.swift stats endpoint
```

---

### Task 1: Brand assets, palette, and menu bar glyph

**Files:**
- Create: `Ajour/Assets.xcassets` (AppIcon, six color sets, two template image sets), `Ajour/Design/Palette.swift`
- Modify: `project.yml`, `Ajour/Menu/StatusMenuController.swift`
- Test: `AjourTests/PaletteTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum Palette {
      static let stateOn, stateTimed, stateOff, danger, accentText: NSColor   // NSColor(named:) from the asset catalog
      static func color(_ nsColor: NSColor) -> Color                           // SwiftUI bridge
  }
  ```
  Image names `MenuBarGlyphIdle`, `MenuBarGlyphTimers` (template, preserve vector data).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func paletteColorsDifferBetweenLightAndDark() {
    for color in [Palette.stateOn, Palette.stateTimed, Palette.stateOff, Palette.danger, Palette.accentText] {
        #expect(hex(color, in: .aqua) != hex(color, in: .darkAqua))
    }
    #expect(hex(Palette.stateTimed, in: .aqua) == "A15C00")
    #expect(hex(Palette.stateTimed, in: .darkAqua) == "F4B544")
}

@Test func menuBarGlyphsAreTemplateImages() {
    for name in ["MenuBarGlyphIdle", "MenuBarGlyphTimers"] {
        let image = try #require(NSImage(named: name))
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 23, height: 18))
    }
}
```
`hex(_:in:)` resolves the color under `NSAppearance(named:)` with `performAsCurrentDrawingAppearance` and returns the sRGB hex.

- [ ] **Step 2: Run the tests and see them fail** (no `Palette`, no assets).

- [ ] **Step 3: Create the asset catalog.**
  - Color sets with Any, Dark, and High Contrast variants using the spec's color table.
  - `AppIcon.appiconset` from `docs/design/ui-redesign/assets/app-icon-default-1024.png`, resized with `sips -z` to 16, 32, 64, 128, 256, 512, and 1024 px for the macOS slots.
  - `MenuBarGlyphIdle.imageset` and `MenuBarGlyphTimers.imageset` from the two PDFs, with "Render As: Template Image" and "Preserve Vector Data".
  - In `project.yml`, set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` on the Ajour target.

- [ ] **Step 4: Implement `Palette`**, then use the glyphs in `StatusMenuController.showIcon(hasActiveTimers:)` instead of the `envelope` symbols, keeping the accessibility description "Ajour".

- [ ] **Step 5: Run both suites; they pass.**

- [ ] **Step 6: Check visually.** Build Debug, run the demo, and compare the menu bar glyph with the "Menu Bar Glyph" section of `app-icon-and-glyph.webp`, with and without timers. Check the app icon in Finder.

- [ ] **Step 7: Commit:** "Give Ajour its app icon, menu bar glyph, and palette".

### Task 2: Timer end time and length in the menu model

**Files:**
- Modify: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/Menu/MenuSections.swift`, `Ajour/AllAliasesModel.swift` (`state(of:)`), and the tests that build `.timed` values
- Test: `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/MenuSectionsTests.swift`

**Interfaces:**
- Produces: `case timed(remaining: TimeInterval, endsAt: Date, length: TimeInterval)` in `AliasMenuState`, where `endsAt == record.expiresAt` and `length == record.expiresAt - record.enabledAt`.

- [ ] **Step 1: Write the failing test** `timedStateCarriesEndAndLength`: a record enabled at `now - 60` that expires at `now + 240` yields `.timed(remaining: 240, endsAt: now + 240, length: 300)`.
- [ ] **Step 2: Run it; it fails to compile.**
- [ ] **Step 3: Change the case** and `MenuSections.timedState`; update `AllAliasesModel.state(of:)` and every test that builds `.timed(remaining:)` (about 16 lines in 6 test files) to pass the end time and length.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Keep when a timer ends and how long it runs in the menu model".

### Task 3: Alias status vocabulary and busy activity

**Files:**
- Create: `Ajour/Design/AliasStatus.swift`
- Modify: `Ajour/AppModel.swift` (busy tracking)
- Test: `AjourTests/AliasStatusTests.swift`, `AjourTests/AliasActionsTests.swift`

**Interfaces:**
- Consumes: `AliasMenuState.timed(remaining:endsAt:length:)` (Task 2).
- Produces:
  ```swift
  enum AliasActivity: Equatable { case enabling, disabling, updating }   // words: "Enabling…", "Disabling…", "Updating…"
  struct AliasStatus: Equatable {
      enum Kind: Equatable { case enabled, disabled, timed(shareLeft: Double), busy }
      let kind: Kind
      let words: String            // "Enabled", "Disabled", "4:32 left", "Enabling…"
      let turnsOff: String?        // "off at 14:12"; only for timed, not busy
      var line: String             // words, plus " · " + turnsOff when present
      static func make(state: AliasMenuState, activity: AliasActivity?, reducesMotion: Bool = false,
                       locale: Locale = .current, timeZone: TimeZone = .current) -> AliasStatus
      static func accessibilityLabel(email: String, pinned: Bool, state: AliasMenuState, activity: AliasActivity?,
                                     locale: Locale = .current, timeZone: TimeZone = .current) -> String
  }
  // AppModel
  func activity(aliasID: Int) -> AliasActivity?
  func isBusy(aliasID: Int) -> Bool      // activity(aliasID:) != nil
  ```
  - Activities: `enable` and `enablePermanently` → `.enabling`; `disableNow` → `.disabling`; `disableAfter`, `setPinned`, `keepEnabled` → `.updating`. `perform(on:activity:)` replaces `busyAliasIDs` with `activities: [Int: AliasActivity]`.
  - Share left: `min(max(remaining / length, 0), 1)`; with `reducesMotion`, round the remaining time up to whole minutes first.

- [ ] **Step 1: Write the failing tests** (fixed `Locale`, `TimeZone(identifier: "Europe/Berlin")`):
  - `timedStatusShowsTimeLeftAndTurnOffTime`: remaining 272, endsAt 14:12 in `de_DE` gives `words == "4:32 left"`, `turnsOff == "off at 14:12"`, and `line == "4:32 left · off at 14:12"`.
  - `turnOffTimeFollowsTwelveHourLocales`: `en_US` gives `"off at 2:12 PM"`.
  - `timerOverAnHourUsesHours`: remaining 3600 gives `"1:00:00 left"`; remaining 3599 gives `"59:59 left"`.
  - `shareLeftStaysWithinBounds`: remaining 600 with length 300 (after Extend) gives `shareLeft == 1`; remaining 0 gives `0`.
  - `reducedMotionStepsThePieByMinutes`: remaining 61 with length 300 gives `shareLeft == 120.0 / 300`.
  - `busyAliasShowsItsActivity`: state `.disabled` with `.enabling` gives `kind == .busy`, `line == "Enabling…"`, and `turnsOff == nil`.
  - `voiceOverReadsTheWholeState`: `travel@alexmorgan.example`, pinned, remaining 2820 (47 min), endsAt 14:54 gives `"travel@alexmorgan.example, pinned, enabled, 47 minutes left, turns off at 14:54"`. Remaining 59 reads `"1 minute left"`. Unpinned and enabled reads `"github@alexmorgan.example, enabled"`. Disabled reads `"…, disabled"`; busy reads `"…, enabling"`.
  - In `AliasActionsTests`: `enablingMarksTheAliasAsEnabling` holds an enable request and expects `model.activity(aliasID: 7) == .enabling`, then `nil` after release (replacing the `isBusy` assertions).
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement `AliasStatus` and `AliasActivity`, and switch `AppModel` to `activities`.** Format the turn-off time with `endsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))`.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Describe alias states in words, with the time they turn off and what is changing".

### Task 4: State symbols and problem messages

**Files:**
- Create: `Ajour/Design/StateSymbol.swift`, `Ajour/Design/ProblemMessage.swift`, `Ajour/Views/StateSymbolView.swift`
- Test: `AjourTests/StateSymbolTests.swift`, `AjourTests/ProblemMessageTests.swift`

**Interfaces:**
- Consumes: `AliasStatus.Kind` (Task 3), `Palette` (Task 1).
- Produces:
  ```swift
  enum StateSymbol { static func image(for kind: AliasStatus.Kind, highlighted: Bool) -> NSImage }   // 16 × 16 pt, not a template
  struct StateSymbolView: View { let kind: AliasStatus.Kind }                                       // Image(nsImage:) of the normal variant
  struct ProblemMessage: Equatable { let title: String; let detail: String?; init(_ message: String) }
  ```
  - Draw shapes per the spec's state table with `NSImage(size:flipped:drawingHandler:)` so the colors resolve for the current appearance at draw time. The highlighted variant draws everything in white.
  - The pie starts at 12 o'clock and covers `shareLeft` of the circle, clockwise.

- [ ] **Step 1: Write the failing tests:**
  - `symbolsAreSixteenPoints`: every kind's image measures 16 × 16 pt and `isTemplate == false`.
  - `highlightedSymbolIsWhite`: rendering the highlighted `.enabled` image into a bitmap gives a white center pixel; the normal one doesn't.
  - `messageSplitsAfterTheFirstSentence`: `"Could not reach SimpleLogin. Check your network connection."` gives title `"Could not reach SimpleLogin."` and detail `"Check your network connection."`.
  - `singleSentenceIsAllTitle`: `"Timer data unreadable"` gives detail `nil`.
  - `decimalPointIsNoSentenceEnd`: `"Version 1.2 is required"` gives detail `nil`.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement `StateSymbol`, `StateSymbolView`, and `ProblemMessage`.**
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Draw the alias state symbols and split messages into title and detail".

### Task 5: Menu entries for the redesigned menu

**Files:**
- Modify: `Ajour/Menu/MenuEntry.swift`, `Ajour/AppModel.swift` (`menuState(at:)`, `lastErrorIsNetwork`)
- Test: `AjourTests/MenuEntryTests.swift`, `AjourTests/MenuTitleTests.swift` (delete; its cases move into `AliasStatusTests` and `MenuEntryTests`)

**Interfaces:**
- Consumes: `AliasStatus`, `AliasActivity` (Task 3), `ProblemMessage` (Task 4).
- Produces:
  ```swift
  struct MenuAliasRow: Equatable { let id: Int; let email: String; let status: AliasStatus; let accessibilityLabel: String }
  indirect enum MenuEntry: Equatable {
      case header(String)
      case notice(title: String, detail: String?, symbol: String)
      case action(String, MenuAction, symbol: String? = nil, shortcut: String = "", isEnabled: Bool = true)
      case submenu(String, [MenuEntry], symbol: String? = nil, isEnabled: Bool = true)
      case alias(MenuAliasRow, [MenuEntry])
      case separator
      func hasSameLayout(as other: MenuEntry) -> Bool
  }
  struct MenuState {   // replaces busyAliasIDs
      var activities: [Int: AliasActivity] = [:]
      var lastErrorIsNetwork = false
      var reducesMotion = false
      var locale: Locale = .current
      var timeZone: TimeZone = .current
  }
  ```
  - `hasSameLayout`: `.header` and `.notice` compare only their kind; `.alias` compares `id` and the child entries (the status may differ); the other cases compare as before.
  - `AppModel` sets `lastErrorIsNetwork` with `lastError` (true for `APIError.transport`). `menuState(at:)` passes `activities` and `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
  - Error and detail lines keep the 80-character truncation.

- [ ] **Step 1: Rewrite the tests** to the spec's "Menu bar menu" section:
  - `signedInListsTimersThenPinnedUnderHeaders`: titles `["Timers", <alias 9>, nil, "Pinned", <alias 7>, nil, "New Random Alias", "New Random Alias That Expires", "New Alias…", "All Aliases…", nil, "Settings…", nil, "Quit"]` with symbols `dice`, `timer`, `square.and.pencil`, `list.bullet`, `gearshape`, `power`.
  - `noPinnedAliasesExplainsPinning`: `.notice(title: "No pinned aliases yet", detail: "Open All Aliases, right-click an alias and choose Pin to keep it here.", symbol: "pin")` under `.header("Pinned")`.
  - `signedOutExplainsSetup`: `.notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key")`, `.action("Set Up…", .setUp, symbol: "person.badge.key")`, separator, `Quit`.
  - `networkProblemShowsTitleAndDetail`: the last error `"Could not reach SimpleLogin. Check your network connection."` with `lastErrorIsNetwork` gives `.notice(title: "Could not reach SimpleLogin.", detail: "Check your network connection.", symbol: "wifi.slash")`; without it, the symbol is `exclamationmark.triangle`.
  - Submenus per state as in the spec, e.g. timed: `Copy Address` (`doc.on.doc`), separator, `Disable Now` (`poweroff`), `Keep Enabled` (`infinity`), `.submenu("Extend", [.header("Extend By"), "5 Minutes", "1 Hour", "24 Hours"], symbol: "goforward.plus")`. Only the first duration item carries `timer`.
  - `expiringRandomAliasListsDurationsUnderAHeader`: `[.header("Expires After"), "5 Minutes", "1 Hour", "24 Hours"]`.
  - `busyAliasDisablesChangesButNotCopy` with activity `.enabling`: the row's status line reads `"Enabling…"`.
  - `aNewCountdownKeepsTheLayout` and `aStateChangeChangesTheLayout` for `.alias` rows.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement the entries.**
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Describe the redesigned menu with headers, notices, symbols, and alias rows".

### Task 6: Menu renderer styling and highlight

**Files:**
- Modify: `Ajour/Menu/MenuRenderer.swift`, `Ajour/Menu/StatusMenuController.swift`
- Test: `AjourTests/MenuRendererTests.swift`

**Interfaces:**
- Consumes: `MenuEntry` (Task 5), `StateSymbol` (Task 4).
- Produces:
  ```swift
  final class MenuRenderer: NSObject, NSMenuDelegate {
      func show(_ entries: [MenuEntry])
      func highlight(_ item: NSMenuItem?, in menu: NSMenu)   // also called from StatusMenuController.menu(_:willHighlight:)
      func resetHighlight()                                    // called from menuDidClose
  }
  ```
  - `.header` becomes `NSMenuItem.sectionHeader(title:)`.
  - `.action` and `.submenu` get `NSImage(systemSymbolName:accessibilityDescription:)` template images.
  - `.notice` is a disabled item with a two-line `attributedTitle`: the title in 13 pt semibold `labelColor`, the detail in 11 pt `secondaryLabelColor`, plus the symbol.
  - `.alias` gets a two-line `attributedTitle`: the address in 13 pt regular `labelColor`, the status `line` in 11 pt medium monospaced-digit system font in the kind's palette color (`stateOff` for busy). It also gets `StateSymbol.image(for:highlighted: false)`, the submenu, and `setAccessibilityLabel(row.accessibilityLabel)`.
  - Highlight restyles the item's title and symbol in white, and restores the previously highlighted item of that menu. The renderer is the delegate of every submenu it creates.
  - In-place updates (same layout) re-apply the title and image, highlighted if the item is the highlighted one.

- [ ] **Step 1: Write the failing tests:**
  - `aliasRowShowsAddressAndStatusLines`: the item's `attributedTitle.string == "travel@alexmorgan.example\n47:06 left · off at 14:54"`, and the second line's foreground color is `Palette.stateTimed`.
  - `headersBecomeSectionHeaders`: `.header("Pinned")` renders an item with `isSectionHeader == true`.
  - `actionsCarryTheirSymbol`: `.action("Quit", .quit, symbol: "power")` has a non-nil image with `isTemplate == true`.
  - `highlightingTurnsTheRowWhite`: after `highlight(item, in: menu)`, every foreground color in the title is white.
  - `movingTheHighlightRestoresThePreviousRow`: highlight A, then B: A's status line is `Palette.stateTimed` again.
  - `closingTheMenuRestoresTheHighlightedRow`: highlight A, then `resetHighlight()`: A is back to normal colors.
  - `aCountdownUpdatesTheHighlightedRowInPlace`: the same `NSMenuItem` stays, and its title is white with the new time.
  - `aTimerEndingRebuildsTheRow`: timed to disabled replaces the item, and the new item shows `"Disabled"`.
  - Keep the existing identity and action tests, adjusted to the new cases.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement**, and forward `menu(_:willHighlight:)` and `menuDidClose(_:)` from `StatusMenuController` to the renderer.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Check visually** against `menu/*.webp` and `menu/*-dark.webp`, hovering an alias row in each:
  - Signed in: the normal demo.
  - Signed out: `-AjourDemoSignedOut YES`.
  - Problems and no pinned aliases: temporary, uncommitted demo changes (an error answer from `DemoTransport`, no pinned aliases in `DemoAccount`).
- [ ] **Step 6: Commit:** "Style the menu with state symbols, status lines, and a white highlighted row".

### Task 7: Stats endpoint and the All Aliases model

**Files:**
- Create: `Packages/SimpleLoginKit/Sources/SimpleLoginKit/API/AccountAPI.swift`
- Modify: `Ajour/AllAliasesModel.swift`, `Ajour/Demo/DemoTransport.swift` (answer `GET /api/stats` with `nb_alias`)
- Test: `Packages/SimpleLoginKit/Tests/SimpleLoginKitTests/AccountAPITests.swift`, `AjourTests/AllAliasesModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AccountStats: Decodable, Equatable, Sendable { public let nbAlias: Int }
  extension SimpleLoginAPI { public func stats() async throws -> AccountStats }   // GET /api/stats
  // AllAliasesModel
  struct AliasSection: Identifiable, Equatable { let title: String; let aliases: [Alias]; var id: String { title } }
  var sections: [AliasSection]          // "Pinned" then "Other Aliases"; empty sections left out
  var subtitle: String
  func status(of alias: Alias) -> AliasStatus            // replaces stateLabel(for:)
  func accessibilityLabel(for alias: Alias) -> String
  var emptyState: EmptyState?           // enum EmptyState: Equatable { case noAliases, noMatches(query: String) }
  ```
  - `reload()` also loads `stats()`; a failure leaves the total `nil`.
  - Subtitle rules, in order:
    1. With a search: `"<loaded> of <total ?? loaded> aliases"`, shown only once the first page answered; before that, the subtitle without the search.
    2. While another page loads: `"<loaded> aliases loaded · loading more"`.
    3. Otherwise `"<total ?? loaded> aliases"`, plus `" · 1 timer running"` or `" · <n> timers running"` from `appModel.engine.records.count`.

- [ ] **Step 1: Write the failing tests:**
  - Package: `statsReadsTheAliasCount` decodes `{"nb_alias": 12, "nb_block": 3, "nb_forward": 40, "nb_reply": 2}` to `nbAlias == 12` from `GET /api/stats`.
  - `sectionsPutPinnedAliasesFirst`: rows with ids `[1 pinned, 2, 3 pinned]` give `[("Pinned", [1, 3]), ("Other Aliases", [2])]`.
  - `subtitleCountsAliasesAndTimers`: total 12 with 2 records gives `"12 aliases · 2 timers running"`; 1 record gives `"12 aliases · 1 timer running"`.
  - `subtitleFallsBackToLoadedCountWithoutStats`: a stats failure with 3 loaded gives `"3 aliases"`.
  - `subtitleShowsMatchesWhileSearching`: query `concert`, 0 results, total 12 gives `"0 of 12 aliases"` and `emptyState == .noMatches(query: "concert")`.
  - `subtitleShowsLoadingMore`: a held second page gives `"20 aliases loaded · loading more"`.
  - `searchSubtitleWaitsForResults`: while the first page of a search is held, the subtitle is the one without the search (`"12 aliases"`), never `"0 of 12 aliases"`.
  - Existing `stateLabel` assertions become `model.status(of:).words` with the same values.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement the endpoint, the model changes, and the demo answer.**
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Group All Aliases into pinned and other aliases and summarize them in a subtitle".

### Task 8: All Aliases view

**Files:**
- Modify: `Ajour/Views/AllAliasesView.swift`
- Verify: `docs/design/ui-redesign/all-aliases/*.webp`

**Interfaces:**
- Consumes: `AllAliasesModel` (Task 7), `StateSymbolView` (Task 4), `Palette` (Task 1).

- [ ] **Step 1: Rebuild the view** per the spec's "All Aliases" section.
  - The subtitle uses `.navigationSubtitle(model.subtitle)`. If the AppKit-hosted window doesn't show it, set `NSWindow.subtitle` through `WindowCoordinator` instead.
  - Sections use `Section` with plain headers. Rows use `StateSymbolView`, the address with a `pin` marker, the note, and status words on the right in the palette color; timed rows add `turnsOff` below in secondary text. Each row gets `.accessibilityElement(children: .combine)` and `.accessibilityLabel(model.accessibilityLabel(for:))`.
  - The right-click menu follows the spec, with the `Enable for`, `Extend`, and `Disable After` submenus and SF Symbols via `Label`. Changes are disabled while busy, `Copy Address` isn't.
  - Empty states use `ContentUnavailableView` with the spec's symbols and copy, and `New Alias…` opens the New Alias window (pass an `openNewAlias` closure from `AppDelegate`).
  - The error bar shows the fixed title `Could not load aliases.`, `model.errorMessage` as the detail, and `Try Again` calling `loadNextPage()`.
- [ ] **Step 2: Run both suites; they pass.**
- [ ] **Step 3: Check visually** against every `all-aliases/*.webp` state in both appearances, using the demo (empty and error states with a temporary demo change that is not committed).
- [ ] **Step 4: Commit:** "Redesign the All Aliases window around the state system".

### Task 9: Onboarding

**Files:**
- Modify: `Ajour/OnboardingModel.swift`, `Ajour/Views/OnboardingView.swift`
- Test: `AjourTests/OnboardingModelTests.swift`

**Interfaces:**
- Produces (on `OnboardingModel`):
  ```swift
  struct OnboardingProgress: Equatable { let step: Int; let total: Int }   // step is 1-based
  var progress: OnboardingProgress?      // nil while replacing a key
  var canGoBack: Bool                    // .enterKey (not replacing) and .confirm
  func goBack()                          // .enterKey → .explain, .confirm → .enterKey; clears errorMessage
  static func initials(of name: String) -> String
  ```
  - A rejected key (`APIError.unauthorized`) sets `errorMessage` to `"SimpleLogin did not accept this key. Check that you copied all of it, or create a new one."`. Other errors keep their message.

- [ ] **Step 1: Write the failing tests:**
  - `progressCountsFourSteps`: `.explain` gives `OnboardingProgress(step: 1, total: 4)`, then 2, 3, and 4 through the flow.
  - `replacingAKeyHidesProgressAndBack`: after `beginKeyReplacement()`, `progress == nil` and `canGoBack == false`.
  - `backReturnsToThePreviousStep`: from `.confirm`, `goBack()` gives `.enterKey`; again gives `.explain`.
  - `rejectedKeyExplainsWhatToCheck`: a 401 on `user_info` gives the spec's copy.
  - `initialsUseFirstAndLastName`: `"Alex Morgan"` gives `"AM"`, `"Alex"` gives `"A"`, `"  "` gives `"?"`.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement the model changes and rebuild the view** per the spec's "Onboarding" section.
  - The app icon via `Image(nsImage: NSApp.applicationIconImage)`.
  - Progress dots as four 6 pt capsules, the current one 16 pt wide in `AccentColor`, with `.accessibilityLabel("Step \(step) of \(total)")`.
  - The clipboard card without a timestamp. `Checking key…` while `isSubmitting`.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Check visually** against `onboarding/*.webp` in both appearances with `-AjourDemoSignedOut YES`.
- [ ] **Step 6: Commit:** "Redesign onboarding with progress, a way back, and clearer key errors".

### Task 10: New Alias

**Files:**
- Modify: `Ajour/NewAliasModel.swift`, `Ajour/Views/NewAliasView.swift`
- Test: `AjourTests/NewAliasModelTests.swift`

**Interfaces:**
- Produces (on `NewAliasModel`):
  ```swift
  var previewAddress: String?     // trimmed prefix + suffix.suffix; nil without a prefix or suffix
  var expiryNote: String?         // "off after 5 minutes" / "off after 1 hour" / "off after 24 hours"; nil for Never
  var customSuffixes: [AliasSuffix]
  var sharedSuffixes: [AliasSuffix]
  var submitTitle: String         // "Create", "Try Again" after a failed create, "Creating…" while creating
  ```
  - A failed create sets `errorMessage` to `"Could not create the alias. " + message`.

- [ ] **Step 1: Write the failing tests:**
  - `previewJoinsPrefixAndSuffix`: prefix `" concert-tickets "` and suffix `@alexmorgan.example` give `"concert-tickets@alexmorgan.example"`; an empty prefix gives `nil`.
  - `expiryNoteNamesTheDuration`: `.oneHour` gives `"off after 1 hour"`; `nil` gives `nil`.
  - `suffixesSplitIntoOwnAndShared`.
  - `failedCreateOffersTryAgain`: a server error `{"error":"SimpleLogin is not responding. Try again in a moment."}` gives that message prefixed with `"Could not create the alias. "` and `submitTitle == "Try Again"`.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement the model changes and rebuild the view** per the spec's "New Alias" section. The picker uses `Section("Your Domains")` and `Section("SimpleLogin Domains")`.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Check visually** against `new-alias/*.webp` in both appearances.
- [ ] **Step 6: Commit:** "Redesign New Alias with a live address preview and inline retry".

### Task 11: Settings

**Files:**
- Modify: `Ajour/SettingsModel.swift`, `Ajour/System/LaunchAtLogin.swift`, `Ajour/OnboardingModel.swift` (error copy), `Ajour/Views/SettingsView.swift`
- Test: `AjourTests/SettingsModelTests.swift`, `AjourTests/OnboardingModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct LaunchAtLoginControl {
      var isEnabled: () -> Bool
      var setEnabled: (Bool) throws -> Void
      var openSettings: () -> Void                              // .system: SMAppService.openSystemSettingsLoginItems()
      static func errorMessage(enabling: Bool) -> String        // the spec's add and remove copy
  }
  // SettingsModel
  func openLoginItems()
  ```

- [ ] **Step 1: Write the failing tests:**
  - `failedEnableExplainsWhereToAllowIt`: `setLaunchAtLogin(true)` with a throwing control gives `"Ajour could not be added to your login items. Allow it in System Settings › General › Login Items."`, and `launchAtLogin == false`.
  - `failedDisableExplainsWhereToRemoveIt`: the remove copy.
  - `openLoginItemsOpensSystemSettings`: the control's `openSettings` is called once.
  - Onboarding's finish error uses `errorMessage(enabling:)` too.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement**, and rebuild the view per the spec's "Settings" section, including the Sign Out alert (`.alert` with `role: .destructive`) and the About group with the app icon.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Check visually** against `settings/*.webp` in both appearances.
- [ ] **Step 6: Commit:** "Redesign Settings with a sign-out confirmation and a way to fix launch at login".

### Task 12: Notification copy

**Files:**
- Modify: `Ajour/System/NotificationController.swift`, `Ajour/AppDelegate.swift`
- Test: `AjourTests/NotificationContentTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct NotificationContent { /* existing */ var subtitle = "" }
  static func content(for arrival: MailArrival, turnsOffAt: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> NotificationContent
  func post(_ arrival: MailArrival, turnsOffAt: Date?)     // NotificationController
  ```
  - `AppDelegate` passes `model.engine.record(for: arrival.aliasID)?.expiresAt`.

- [ ] **Step 1: Write the failing tests:**
  - `mailReceivedSaysWhenTheAliasTurnsOff`: subtitle `"Alias turns off at 14:12"` (`de_DE`, Berlin), body `"quiet.harbor42@example.com from login@lounge-wifi.example"`.
  - `mailReceivedWithoutTimerHasNoSubtitle`.
  - `copiedNotificationNamesTheClipboard`: body `"travel@alexmorgan.example is on the clipboard."`.
  - `failingDisableAsksToCheckTheNetwork`: body `"signups@alexmorgan.example is still enabled. Check your network connection."`.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement**, setting `UNMutableNotificationContent.subtitle`.
- [ ] **Step 4: Run both suites; they pass.**
- [ ] **Step 5: Commit:** "Tell in notifications when the alias turns off".

### Task 13: Screenshots, docs, and the final check

**Files:**
- Modify: `scripts/take-screenshots.swift`, `README.md`, `docs/mvp-manual-checks.md`, `docs/images/*.png`

- [ ] **Step 1: Update the screenshot script.** Hover the alias whose title starts with `travel@` (titles no longer start with `●`). Add a Settings capture, and an appearance argument that passes `-AppleInterfaceStyle Dark` to the demo.
- [ ] **Step 2: Retake the README screenshots** and check them against the references.
- [ ] **Step 3: Update the README's feature list** where the redesign changes behavior (turn-off times, the menu's states). Update the manual checks for the new copy: the onboarding Back button, the Sign Out confirmation, Open Login Items, and the `off at` times.
- [ ] **Step 4: Run both suites, build Release, and run the VoiceOver spot check.**
  - Read an alias row in the menu with VoiceOver (⌘F5); it reads the spec's label.
  - Read the onboarding progress dots.
  - Turn on Reduce Motion and Increase Contrast, and check the pie and the colors.
- [ ] **Step 5: Create a follow-up issue** for the Dark app icon (Icon Composer). Then commit: "Refresh screenshots and docs for the redesign".
