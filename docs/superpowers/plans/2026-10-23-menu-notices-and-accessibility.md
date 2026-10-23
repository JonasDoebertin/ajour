# Menu Notices and Accessibility Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show menu notices at full contrast (#27), fix what VoiceOver, Increase Contrast, and Reduce Motion would get wrong (#25, #26), and rename the app's `AliasActivity` (#29).

**Architecture:**
- `MenuRenderer` gives notice items a custom view (`MenuNoticeView`) instead of a dimmed attributed title.
- The accessibility passes inspect the running demo app and fix what they find, then leave a checklist for the person.
- The rename is mechanical.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-23-menu-notices-and-accessibility-design.md`

## Global Constraints

- macOS 26.0, Xcode 27.1, Swift language mode 6, strict concurrency. No third-party dependencies.
- Every task keeps both suites green:
  - `swift test --package-path Packages/SimpleLoginKit`
  - `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS"`
- Run `xcodegen generate` after adding or removing files.
- TDD for testable behavior: write the failing test first and record a real RED run.
- On-screen checks:
  - Use the Debug build launched with `-AjourDemo YES` only, never the installed app or a real account.
  - Temporary code changes for checks stay uncommitted and are reverted.
  - Screenshots go to /tmp only.
  - Quit the demo app afterwards.
- Never change macOS system settings: VoiceOver, Reduce Motion, Increase Contrast, appearance, Full Keyboard Access.
- No copy, color value, or symbol changes beyond what the spec names.
- Commit messages describe intent, in English.

## Review Focus

1. **A notice under the pointer when the menu rebuilds or a countdown ticks:** it never shows a highlight and never turns white. Test in Task 2.
2. **A long server message without spaces** (a URL or token): it wraps inside the notice width and doesn't widen the menu. Test in Task 2.
3. **A notice updated in place from a two-line detail to a short one:** its height shrinks and doesn't leave a gap. Test in Task 2.
4. **VoiceOver reaching notices once they are view items:** disabled view items may be skipped by VoiceOver. Checked in Task 3's tree inspection; if they are skipped, Task 3 fixes it.
5. **A contrast or appearance change while the menu or a window is open:** symbols and colors follow without reopening. Checked in Task 4.

---

### Task 1: Rename the app's `AliasActivity` to `AliasChange` (#29)

**Files:**
- Modify: `Ajour/Design/AliasStatus.swift`, `Ajour/AppModel.swift`, `Ajour/Menu/MenuEntry.swift`, and any other app file that uses the type or its members (`grep -rn "AliasActivity\|activities\|activity" Ajour AjourTests`)
- Test: `AjourTests/AliasStatusTests.swift`, `AjourTests/MenuEntryTests.swift`, and other tests that use it

**Interfaces:**
- Produces:
  ```swift
  /// A change to an alias that is still running.
  enum AliasChange: Equatable { case enabling, disabling, updating }   // `words` unchanged
  AppModel.change(aliasID: Int) -> AliasChange?                          // was activity(aliasID:)
  MenuState.changes: [Int: AliasChange]                                  // was activities
  // `activity:` parameters on AliasStatus.make / accessibilityLabel and AppModel.perform become `change:`
  ```
- SimpleLoginKit's `AliasActivity` (an alias's latest mail activity) stays as it is.
- Only rename members that mean the in-flight change. Leave names that refer to SimpleLoginKit's mail activity (`latestActivity`, `forwardActivity`) untouched.

- [ ] **Step 1: Rename.** Update tests in the same commit; drop every `Ajour.` module prefix that only existed to pick the app's `AliasActivity`. This is a pure rename, so the suites are the test.
- [ ] **Step 2: Run both suites.** Expected: all green, same test counts as before (Ajour 362, SimpleLoginKit 189).
- [ ] **Step 3: Commit**

```bash
git commit -m "Name the app's in-flight alias change so it no longer shadows SimpleLoginKit's activity"
```

---

### Task 2: Notices at full contrast (#27)

**Files:**
- Create: `Ajour/Menu/MenuNoticeView.swift`
- Modify: `Ajour/Menu/MenuRenderer.swift` (`makeItem`, `showContent(of:in:)`, remove `noticeTitle`)
- Test: `AjourTests/MenuRendererTests.swift` (adapt the notice tests to the view)

**Interfaces:**
- Produces:
  ```swift
  @MainActor final class MenuNoticeView: NSView {
      static let maximumTextWidth: CGFloat          // the wrap width; pick it to match no-pinned-aliases.webp
      init()
      func show(title: String, detail: String?, symbol: String, tone: MenuTone, fullText: String?)
      var title: String { get }                     // what the title label shows
      var detail: String? { get }                   // nil hides the detail label
      var titleColor: NSColor { get }               // .labelColor
      var detailColor: NSColor { get }              // .secondaryLabelColor
      var symbolImage: NSImage? { get }             // danger → Palette.danger palette color; plain → labelColor
  }
  ```
- **Rules:**
  - `show` sets the frame height to fit the wrapped text. It is called again for in-place updates, so the item keeps the same view.
  - The view's `toolTip` and accessibility label are `fullText ?? [title, detail].compactMap { $0 }.joined(separator: "\n")`.
  - The view is one accessibility element with role `.staticText`.
  - The `NSMenuItem` stays `isEnabled = false`.
  - The view draws no highlight and ignores clicks.
  - Title: 13 pt semibold. Detail: 11 pt regular. Both wrap by word, and by character for words longer than the line.
  - The symbol sits in the column of other items' images. Text starts where other items' titles start.
  - Align against an action item on screen.

- [ ] **Step 1: Write the failing tests** (replace the attributed-title assertions in the existing notice tests)

```swift
@Test func noticesUseAFullContrastViewThatCannotBeChosen() throws
// show [.notice(title: "Not set up", detail: "Add a SimpleLogin API key to manage your aliases.", symbol: "key")]
// item.view is MenuNoticeView; view.title == "Not set up"; view.detail == "Add a SimpleLogin API key to manage your aliases."
// view.titleColor == .labelColor; view.detailColor == .secondaryLabelColor; item.isEnabled == false
@Test func dangerNoticesDrawTheirSymbolInTheDangerColor() throws          // existing, now reads view.symbolImage
@Test func aNoticeOffersItsFullTextAsTooltipAndSpokenLabel() throws       // view.toolTip == message; view.accessibilityLabel() == message
@Test func aNoticeWithoutFullTextSpeaksTitleAndDetail() throws
// view.accessibilityLabel() == "No pinned aliases yet\nOpen All Aliases, right-click an alias and choose Pin to keep it here."
// view.isAccessibilityElement() == true; view.accessibilityRole() == .staticText
@Test func aNoticeUpdatedInPlaceDropsTheFullTextItNoLongerHas() throws    // existing, on the view
@Test func aChangedNoticeUpdatesTheSameItem() throws                      // existing; also `item.view === viewBefore`
@Test func aLongDetailWrapsInsteadOfWideningTheMenu() throws
// detail of 200 chars with spaces → view.frame.width <= MenuNoticeView.maximumTextWidth + (symbol column + insets);
// view.frame.height > height of the same notice with a one-word detail
@Test func aLongWordWrapsInsideTheNotice() throws
// detail = String(repeating: "x", count: 200) → same width bound as above
@Test func aNoticeShrinksWhenItsDetailGetsShorter() throws
// show long detail, then short detail in place → second height < first height
@Test func aNoticeIsNeverHighlighted() throws
// renderer.highlight(noticeItem, in: menu) and a countdown update in place → view.title color stays .labelColor, nothing turns white
```

- [ ] **Step 2: Run them and see them fail.** `xcodebuild test -project Ajour.xcodeproj -scheme Ajour -destination "platform=macOS" -only-testing:AjourTests/MenuRendererTests`
- [ ] **Step 3: Implement** `MenuNoticeView` and use it for `.notice` in `MenuRenderer`. Run `xcodegen generate`.
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Verify on screen in demo mode.**
  - Make a temporary change so the demo menu shows these notices:
    - a long error with `fullText`;
    - `Timer data unreadable`;
    - `No pinned aliases yet`;
    - `Not set up`, which may take a second run.
  - Compare with `docs/design/ui-redesign/menu/problems*.webp`, `no-pinned-aliases*.webp`, and `signed-out*.webp`, in the current appearance:
    - alignment with action items;
    - wrapping of the pinned hint into two lines;
    - full contrast;
    - no hover highlight;
    - the tooltip appears on hover.
  - Revert the change.
- [ ] **Step 6: Commit**

```bash
git commit -m "Show menu notices at full contrast without making them selectable"
```

---

### Task 3: VoiceOver pass (#25)

**Files:**
- Modify: whatever the inspection shows needs fixing. Likely candidates:
  - `Ajour/Menu/MenuRenderer.swift` (alias rows)
  - `Ajour/Views/AllAliasesView.swift`
  - `Ajour/Views/NewAliasView.swift`
  - `Ajour/Views/SettingsView.swift`
  - `Ajour/Views/OnboardingView.swift`
- Modify: `docs/mvp-manual-checks.md` (new `## Accessibility` section, `### VoiceOver` subsection)
- Test: the matching test files, for fixes that are testable data

**Interfaces:**
- Consumes: `MenuNoticeView` from Task 2 (accessibility label and role).
- **Method:**
  - With the demo app running, read the accessibility tree of each place the spec lists. Use the AX API from a script in /tmp (`AXUIElementCopyAttributeValue`: role, title, description, value, help, children), or Accessibility Inspector.
  - Grant nothing new. If the terminal lacks accessibility access, say so in the report and inspect in code instead.
  - Record, per element, the text VoiceOver would read.
- **Fix rules (from the spec):**
  - Text read twice gets one source.
  - Menu alias rows read only `MenuAliasRow.accessibilityLabel`, not also the visible title.
  - Nothing may be skipped or read incompletely.
  - Notices (now view items) must be reachable. If AppKit hides a disabled item's view from accessibility, fix it without making the item selectable.
- **Checklist:**
  - Under `## Accessibility` › `### VoiceOver`, give one numbered line per place with the exact phrase VoiceOver should read, in the style of the existing sections.
  - Mark anything the tree inspection couldn't settle as "listen for".

- [ ] **Step 1: Inspect and write down findings** in the report (not the repo).
- [ ] **Step 2: For each fix with testable data, write the failing test first and record RED.** Example shape:

```swift
@Test func aliasRowsSpeakOnlyTheirLabel() throws
// rendered alias item: whatever attribute VoiceOver reads first carries row.accessibilityLabel, and the visible title isn't exposed as a second text
```

- [ ] **Step 3: Implement the fixes.**
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Re-inspect the fixed places in demo mode** and confirm the tree now matches the checklist.
- [ ] **Step 6: Commit** (fixes and checklist may be separate commits)

```bash
git commit -m "Let VoiceOver read each menu row and window control once and in full"
git commit -m "List what VoiceOver should read in the manual checks"
```

---

### Task 4: Appearance, Increase Contrast, and Reduce Motion pass (#26)

**Files:**
- Modify: whatever the pass shows needs fixing (likely `Ajour/Menu/MenuRenderer.swift`, `Ajour/Design/StateSymbol.swift`, `Ajour/Menu/MenuNoticeView.swift`, `Ajour/Menu/StatusMenuController.swift`)
- Modify: `docs/mvp-manual-checks.md` (`## Accessibility` › `### Reduce Motion and Increase Contrast`)
- Test: matching test files, for testable fixes

**Interfaces:**
- **Method:**
  - With a temporary, uncommitted change, force `NSApp.appearance` to each of `.aqua`, `.darkAqua`, `.accessibilityHighContrastAqua`, and `.accessibilityHighContrastDarkAqua` in the demo app.
  - Screenshot these to /tmp:
    - the menu: normal and highlighted rows, a timed row, a stuck row with `Not disabled · retrying`, a refused row with `Can't disable with this key`, and the notices;
    - All Aliases;
    - New Alias;
    - the "An Alias Is Still Enabled" sheet.
  - Compare colors with the color table in `docs/superpowers/specs/2026-10-22-ui-redesign-design.md`.
  - Force `reducesMotion` the same temporary way and check that the pie steps once per minute while the text keeps counting, in the menu and in All Aliases.
- **Code check for live switches:** whether the open menu and open windows follow an appearance or contrast change without reopening:
  - `StateSymbol.image` without an appearance draws for the current drawing appearance;
  - `MenuNoticeView` symbol colors;
  - `Palette` colors in SwiftUI;
  - the status item glyph.

  Fix what doesn't.

- [ ] **Step 1: Run the pass and write down findings** in the report.
- [ ] **Step 2: For testable fixes, write the failing test first and record RED** (e.g. a symbol image resolving a different color under `.accessibilityHighContrastDarkAqua` than under `.darkAqua`).
- [ ] **Step 3: Implement the fixes.**
- [ ] **Step 4: Run both suites.** Expected: all green.
- [ ] **Step 5: Add the checklist** with the real system settings.
  - **Reduce Motion:** the pie steps per minute in the menu and in All Aliases.
  - **Increase Contrast, light and dark, with a window open while switching:**
    - status lines;
    - state symbols, including stuck;
    - the danger color;
    - the accent;
    - the notices;
    - the still-enabled sheet.
- [ ] **Step 6: Commit**

```bash
git commit -m "Keep colors and symbols right in every appearance and contrast setting"
git commit -m "List the Reduce Motion and Increase Contrast checks"
```
