# Ajour: Menu Notices and Accessibility Checks

Status: approved design (the user asked to go ahead; every decision below is Claude's call unless marked otherwise)
Date: 2026-10-23
Scope: issues #27, #25, #26, #29
Builds on: `2026-10-22-ui-redesign-design.md`, `2026-10-22-disable-failures-design.md`, `2026-10-22-signout-followups-design.md`

## Intent

Finish the redesign from #24. Problems and empty states in the menu look as clear as in the design. Ajour works for people who use VoiceOver, Reduce Motion, or Increase Contrast. The agent can check everything except listening with VoiceOver and turning the system settings on, so it fixes what it can see and leaves the person a short checklist for the rest.

## Non-goals

- Changing any copy, color value, symbol, or layout the redesign defined, other than the notices.
- New screenshots for the README (#28) and the Dark app icon (#22).
- Changing system settings on the Mac this is built on. VoiceOver, Reduce Motion, Increase Contrast, appearance, and Full Keyboard Access stay as they are. The person checks with them turned on.

## Anti-goals

- A notice that can be selected, highlighted, or clicked. A notice is information, not an action.
- A fix that makes VoiceOver read less than today. Every notice and row must still be reached and read in full.

## 1. Notices at full contrast (#27)

Today every `MenuEntry.notice` is a disabled `NSMenuItem` with an attributed title, and AppKit dims it. Notices are:
- the error notice from `lastError`;
- `Timer data unreadable`;
- `Not set up`;
- `No pinned aliases yet`.

- **Look:** each notice matches the design (`docs/design/ui-redesign/menu/problems.webp`, `no-pinned-aliases.webp`, `signed-out.webp`, and their dark versions), at full contrast:
  - Symbol in the same column as the other items' images. Danger notices draw it in `Danger`; plain notices draw it like the symbols of enabled items.
  - Title: 13 pt semibold, `labelColor`.
  - Detail: 11 pt, `secondaryLabelColor`, below the title.
- **Wrapping:** title and detail wrap between words within a fixed width, so a long detail takes a second line as in `no-pinned-aliases.webp` instead of widening the menu. The width is roughly that of the menu's alias rows in the design; the builder picks the value and checks it on screen. The 80-character split and the `…` truncation in `MenuEntry` stay as they are.
- **Not selectable:** hovering doesn't highlight a notice, the keyboard skips it as it does today, and clicking it does nothing.
- **Full text:** the tooltip and the VoiceOver label carry `fullText` when there is one, otherwise the title and detail. This settles the open tooltip question from #37.
- **Mechanism:** a custom item view (`NSMenuItem.view`) is the expected route. The builder picks the details, as long as it updates in place like today (`MenuRenderer.show` keeps items when the layout is the same).

## 2. VoiceOver (#25)

The issue lists what to listen for. The builder checks each place in the accessibility tree of the running app, in demo mode:
- menu alias rows;
- menu notices, after section 1;
- All Aliases rows and their context menu;
- New Alias: the address preview and the expiry note;
- Settings account rows;
- Onboarding progress dots.

The builder reads what VoiceOver would read: role, title, label/description, value, and help.

- **Read twice:** any element whose text appears twice, for example an alias row with both a two-line title and a label, gets one source of text. For menu alias rows, VoiceOver must read the label (`travel@…, pinned, enabled, 47 minutes left, turns off at 14:54`) and not also the visible title.
- **Read incompletely or unreachable:** any element that is skipped or loses part of its text is fixed.
- **What's left for the person:** a new "Accessibility" section in `docs/mvp-manual-checks.md` lists, per place, what VoiceOver should say, so the person can listen once.
- **Tests:** where the fix is testable data (an accessibility label the renderer sets, a label a model computes), unit tests pin it.

## 3. Reduce Motion and Increase Contrast (#26)

- **Appearances:** without changing system settings, the builder renders the app in the four appearances by forcing `NSApp.appearance` in a temporary, uncommitted change: Aqua, Dark Aqua, and both high-contrast variants. Screenshots go to /tmp only. The builder checks these against the color table in `2026-10-22-ui-redesign-design.md`:
  - menu, normal and highlighted rows, including the stuck symbol, `Not disabled · retrying`, and `Can't disable with this key`;
  - the notices from section 1;
  - All Aliases;
  - New Alias;
  - the "An Alias Is Still Enabled" sheet.

  This also covers the light-appearance check that #37 left open.
- **Reduce Motion:** the builder forces `reducesMotion` the same temporary way and checks that the pie steps once per minute in the menu and in All Aliases while the text keeps counting.
- **Live switches:** the builder checks in code that the menu and open windows follow an appearance or contrast change without reopening:
  - menu items are rebuilt or redrawn;
  - `StateSymbolView` reads the environment;
  - the menu's state symbols take the current appearance at draw time.

  Anything that doesn't is fixed.
- **What's left for the person:** the "Accessibility" section in `docs/mvp-manual-checks.md` also lists the Reduce Motion and Increase Contrast checks with the real system settings.

## 4. Rename the app's `AliasActivity` (#29)

- Rename `Ajour/Design/AliasStatus.swift`'s `AliasActivity` (enabling, disabling, updating) to `AliasChange`. Its doc comment says it is a change to an alias that is still running.
- Update every use in the app and the tests, and drop the `Ajour.` module prefix in the tests.
- SimpleLoginKit's `AliasActivity` stays.
- Rename related members where they carry the old word (`activities`, `activity(aliasID:)`, the `activity:` parameters) to `changes` / `change`. No behavior change.

## Closing the issues

- The PR closes #27 and #29.
- #25 and #26 stay open until the person has listened and looked with the real settings. The PR links them, and a comment on each points to the new checklist.

## Constraints

- Swift 6 strict concurrency, macOS 26, Swift Testing, XcodeGen. Run `xcodegen generate` after adding or removing files.
- On-screen checks use the Debug build with `-AjourDemo YES` only, never the installed app or a real account. Temporary code changes for checks are reverted before committing.
- No changes to macOS system settings.
