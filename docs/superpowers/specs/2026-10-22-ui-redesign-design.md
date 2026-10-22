# Ajour: UI Redesign

Status: approved design, implementation planned
Date: 2026-10-22
Scope: issue #21
Source: the pen.dev document `Ajour.pen`. Every state is exported to [`docs/design/ui-redesign/`](../../design/ui-redesign/) in light and dark (`<state>.webp`, `<state>-dark.webp`); the style guide is `style-guide.webp`. When this text and an image disagree, this text wins.

## Intent

Give Ajour a recognizable, polished look that still feels native to macOS 26, and make an alias's state readable at a glance. The brand idea is openwork ("Ajour"): small openings that let light through. An alias is one of those openings: closed by default, open for a moment, closed again.

## Design language

- System font (SF Pro) and system text styles; the canvas shows Inter as a stand-in. Countdowns use monospaced digits.
- Backgrounds, text, separators, menus, fields, and controls use system colors and materials. Only the brand and state colors below are custom.
- Type scale: Display 24 bold, Title 20 bold, Headline 15 bold (window titles, names), Body 13 regular (menus, rows, forms), Body Emphasis 13 semibold (problems, labels), Status 12 medium with monospaced digits, Caption 11 regular (notes, subtitles), Section Header 11 semibold.
- Spacing on a 4 pt grid. Windows: 24 pt side margins, 16 pt between groups, 12 pt inside rows. Corner radii: field 8, form group 12, row highlight 7; controls are capsules.

### Colors

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast | Use |
|---|---|---|---|---|---|
| `AccentColor` | `#0B766B` | `#0F8073` | `#075E55` | `#13998A` | Prominent buttons, switches, focus |
| `AccentText` | `#0B766B` | `#4CCFBD` | `#075E55` | `#7FE3D4` | Accent-colored text and symbols |
| `StateOn` | `#0A7A5E` | `#4ED8B0` | `#075E48` | `#7FE8C8` | Enabled |
| `StateTimed` | `#A15C00` | `#F4B544` | `#7E4700` | `#FFCB70` | Timer running |
| `StateOff` | `#6A6A70` | `#A0A0A8` | `#4F4F55` | `#C2C2C8` | Disabled, busy |
| `Danger` | `#C42B1C` | `#FF7B6B` | `#9E1F12` | `#FF9F93` | Errors, Sign Out |

The Increase Contrast columns follow the style guide's rule ("state colors darken by one step in Light and lighten in Dark"); the design gives the rule, not the values.

### State system

Every alias state has its own symbol shape and its own words; color reinforces them but never carries meaning alone. The same symbol, color, and words appear in the menu and in All Aliases.

| State | Symbol (16 pt) | Color | Status words |
|---|---|---|---|
| Enabled | 14 pt ring (inner radius 76 %) with a 6 pt dot in the center | `StateOn` | `Enabled` |
| Timed | 14 pt ring with an 8 pt pie showing the share of the timer left, starting at 12 o'clock and shrinking clockwise | `StateTimed` | `4:32 left` and `off at 14:12` |
| Disabled | 14 pt ring with a diagonal slash (1.6 pt, round caps) | `StateOff` | `Disabled` |
| Busy | three quarters of the 14 pt ring | `StateOff` | `Enabling…`, `Disabling…`, `Updating…` |

- Time left uses `m:ss` under an hour and `h:mm:ss` from an hour on (the existing `RemainingTime.format`). The pie's share is time left divided by the timer's whole length (turn-off time minus enable time).
- `off at <time>` uses the system's short time format, so it reads `off at 14:12` in a 24-hour locale and `off at 2:12 PM` in a 12-hour one.
- In a highlighted menu row, every symbol and text turns white.

### SF Symbols

| Symbol | Used for |
|---|---|
| `pin`, `pin.slash` | Pin, Unpin, pinned marker |
| `doc.on.doc` | Copy Address |
| `timer` | Enable for…, New Random Alias That Expires, onboarding feature "Open an alias for a moment" |
| `poweroff` | Disable Now, Disable |
| `checkmark.circle` | Enable Permanently, "Key accepted" |
| `infinity` | Keep Enabled |
| `goforward.plus` | Extend |
| `dice` | New Random Alias |
| `square.and.pencil` | New Alias… |
| `list.bullet` | All Aliases… |
| `gearshape` | Settings… |
| `power` | Quit |
| `magnifyingglass` | Search, No Matching Aliases |
| `envelope.open` | No Aliases |
| `wifi.slash` | Network problem |
| `key` | API key invalid, "Not set up" |
| `exclamationmark.triangle` | Timer data unreadable, other problems, error bar |
| `exclamationmark.circle` | Inline errors |
| `person.badge.key` | Set Up… |
| `doc.on.clipboard` | Use Key from Clipboard |
| `arrow.up.right` | Open SimpleLogin |
| `at` | Address preview |
| `bell` | Onboarding feature "Know when mail arrives" |
| `lock` | Onboarding feature "It closes on its own" |
| `info.circle` | Disclaimer |

## Surfaces

### App icon and menu bar glyph

- App icon: an envelope whose flap seam is a row of small openings; the center one is lit. `docs/design/ui-redesign/assets/app-icon-default-1024.png` is the Default appearance on the macOS 26 grid (824 pt body on a 1024 pt canvas). `app-icon-dark-1024.png` is the Dark appearance.
- Menu bar glyph: a template image, 23 × 18 pt, 1.5 pt strokes, vector PDF: `assets/menu-bar-glyph-idle.pdf` while no timer runs, `assets/menu-bar-glyph-timers.pdf` while timers run (a true cutout badge, not a colored dot).

### Menu bar menu

A native `NSMenu`. Countdowns update in place every second while it is open.

Order, top to bottom, each group followed by a separator:

1. Problems, each a non-interactive row with a symbol, a semibold title, and an optional secondary detail line:
   - The last error, split into title and detail (see "Problem messages"). Symbol `wifi.slash` for a network error, otherwise `exclamationmark.triangle`.
   - `API key invalid – Re-enter Key…` (symbol `key`), an action that opens key replacement.
   - `Timer data unreadable` (symbol `exclamationmark.triangle`).
2. Signed out only: a non-interactive row, symbol `key`, title `Not set up`, detail `Add a SimpleLogin API key to manage your aliases.`, then `Set Up…` (symbol `person.badge.key`).
3. Signed in only:
   - Section header `Timers` with the timed aliases that aren't pinned, if any.
   - Section header `Pinned` with the pinned aliases. With none, a non-interactive row: title `No pinned aliases yet`, detail `Open All Aliases, right-click an alias and choose Pin to keep it here.`, symbol `pin`.
   - Alias rows: state symbol, address on the first line, status on the second (Caption weight medium, monospaced digits, state color): `Enabled`, `Disabled`, `4:32 left · off at 14:12`, or the busy words. Each opens a submenu.
   - `New Random Alias` (`dice`), `New Random Alias That Expires` (`timer`) with a submenu, `New Alias…` (`square.and.pencil`), `All Aliases…` (`list.bullet`).
   - `Settings…` (`gearshape`, ⌘,).
4. `Quit` (`power`, ⌘Q).

Alias submenus (`Copy Address` with `doc.on.doc`, a separator, then):

- Disabled: `Enable for 5 Minutes` (`timer`), `Enable for 1 Hour`, `Enable for 24 Hours`.
- Timed: `Disable Now` (`poweroff`), `Keep Enabled` (`infinity`), `Extend` (`goforward.plus`) with a submenu: section header `Extend By`, then `5 Minutes`, `1 Hour`, `24 Hours`.
- Enabled: `Disable Now` (`poweroff`), `Disable After 5 Minutes` (`timer`), `Disable After 1 Hour`, `Disable After 24 Hours`.
- Busy: the same items, all but `Copy Address` disabled.

`New Random Alias That Expires` submenu: section header `Expires After`, then `5 Minutes`, `1 Hour`, `24 Hours`.

Only the first item of a duration group carries a symbol; the others leave the symbol column empty.

### All Aliases

- Resizable window, 520 × 600 pt by default; title `All Aliases` with a subtitle; the search field (`Search aliases`) in the toolbar.
- Subtitle: `12 aliases · 2 timers running` (the timer part only when timers run; `1 timer running` for one). While another page loads: `12 aliases loaded · loading more`. While searching: `0 of 12 aliases` (matches loaded of all aliases). The total comes from `GET /api/stats` (`nb_alias`); without it, the number of loaded aliases stands in.
- Sections `Pinned` (pinned aliases) and `Other Aliases` (the rest), each in the order the API returns.
- Row: state symbol; address with a `pin` marker when pinned; the note below in secondary text; on the right the status words in the state color, and for timed rows `off at 14:54` below in secondary text.
- Right-click menu (symbols as in the table): `Pin` or `Unpin`, `Copy Address`, separator, then by state:
  - Disabled: `Enable for` submenu (`5 Minutes`, `1 Hour`, `24 Hours`), `Enable Permanently`.
  - Timed: `Keep Enabled`, `Extend` submenu (`5 Minutes`, `1 Hour`, `24 Hours`), separator, `Disable`.
  - Enabled: `Disable After` submenu (`5 Minutes`, `1 Hour`, `24 Hours`), separator, `Disable`.
  - Busy: the same items disabled, except `Copy Address`.
- States:
  - Loading more: a spinner and `Loading more aliases…` below the last row.
  - No aliases: `envelope.open`, `No Aliases`, `Aliases you create in SimpleLogin or with Ajour show up here.`, and a `New Alias…` button that opens New Alias.
  - No matches: `magnifyingglass`, `No Matching Aliases`, `No address or note contains “<search>”. Check the spelling or try another search.`
  - Error: a bar at the bottom with `exclamationmark.triangle`, the title `Could not load aliases.`, the detail from the error's message, and a `Try Again` button.

### Onboarding

One 420 pt window that sizes to its content, four steps, progress dots below the content (one lit dot per step reached; VoiceOver reads `Step 2 of 4`). Replacing a key shows only the key step and the confirmation, without progress dots and without Back on the key step.

1. Welcome: the app icon (64 pt), `Welcome to Ajour`, `Quick aliases for SimpleLogin.`, three features in a group: `Open an alias for a moment` / `Enable it for 5 minutes, 1 hour or 24 hours.` (`timer`), `Know when mail arrives` / `Disable it right from the notification.` (`bell`), `It closes on its own` / `When the time is up, the alias turns off again.` (`lock`). Then `Ajour needs a SimpleLogin API key to enable and disable your aliases. It never sees your password.` Button `Continue`.
2. Key: `Add Your API Key`, `In SimpleLogin, open API Keys, create a key named “Ajour” and paste it below.`, button `Open SimpleLogin` with `arrow.up.right`, a labeled secure field `API Key` with placeholder `Paste key`.
   - Clipboard: a card with `doc.on.clipboard`, `API key on clipboard`, and a `Use Key from Clipboard` button.
   - Rejected key: `exclamationmark.circle` and `SimpleLogin did not accept this key. Check that you copied all of it, or create a new one.` in `Danger`. Other errors show their message the same way.
   - Checking: a small spinner and `Checking key…`; Continue disabled.
   - Buttons `Back` and `Continue`.
3. Signed in: `Signed In`, `Ajour can now manage the aliases of this account.`, a circle with the name's initials (`AM`), the name and email, and `Key accepted` with `checkmark.circle` in `StateOn`. Buttons `Back` (back to the key step) and `Continue`.
4. All set: `You’re All Set`, `Ajour lives in the menu bar. Click the envelope to open an alias for a moment.`, checkbox `Launch at login`, button `Done`.

### New Alias

420 pt wide, sizes to its content. A grouped form: `Prefix` (text field, placeholder `shop`), `Suffix` (picker with the sections `Your Domains` for custom domains and `SimpleLogin Domains` for the rest), `Disable after` (`Never`, `5 Minutes`, `1 Hour`, `24 Hours`). Below the group, the preview: `at` and the full address in semibold, and when an expiry is chosen `off after 1 hour` (`off after 5 minutes`, `off after 24 hours`) in secondary text. Button `Create`.

- Loading suffixes: `Loading suffixes…` with a small spinner in the Suffix row, `The address preview appears once suffixes are loaded.` in place of the preview, Create disabled.
- Error: `exclamationmark.circle` and `Could not create the alias. <message>` in `Danger` above the button; the button reads `Try Again`.
- Creating: the button reads `Creating…` with a small spinner and is disabled.

### Settings

A 420 pt grouped form with three groups:

- `Account`: `Name`, `Email`, then `Replace API Key…` and `Sign Out` (text in `Danger`). Sign Out asks first: alert `Sign Out of Ajour?`, message `Ajour disables aliases with a running timer, then removes the API key from this Mac.`, buttons `Sign Out` (destructive) and `Cancel`.
- `General`: switch `Launch at login`. When adding fails: `exclamationmark.circle` and `Ajour could not be added to your login items. Allow it in System Settings › General › Login Items.` in `Danger`, the switch reverts, and an `Open Login Items…` button opens that System Settings pane. When removing fails: `Ajour could not be removed from your login items. Remove it in System Settings › General › Login Items.`
- `About`: the app icon (32 pt), `Ajour` (Headline), `Quick aliases for SimpleLogin.`, then `info.circle` and `Ajour is an independent app and is not affiliated with SimpleLogin or Proton AG.` in secondary text.

### Notifications

- Mail received: title `Mail received`, subtitle `Alias turns off at 14:12` (left out when the alias has no timer), body `<alias> from <sender>`, action `Disable Now`.
- Alias copied: title `Alias copied`, body `<alias> is on the clipboard.`
- Disabling keeps failing: title `Could not disable alias`, body `<alias> is still enabled. Check your network connection.`
- Disable forbidden and API key invalid keep their current copy.

## Problem messages

Messages shown as a title with a detail split after the first sentence: everything up to and including the first `.` followed by a space is the title, the rest is the detail. A message without such a break is all title. Example: `Could not reach SimpleLogin. Check your network connection.` becomes `Could not reach SimpleLogin.` and `Check your network connection.`. The menu keeps truncating long text to 80 characters per line.

## Accessibility and motion

- Never color alone: every state pairs a symbol shape with words; problems pair a symbol with a sentence.
- Reduce Motion: the timer pie steps once per minute; the countdown text still updates every second.
- VoiceOver: alias rows read `travel@alexmorgan.example, pinned, enabled, 47 minutes left, turns off at 14:54` (parts that don't apply are left out: `pinned` only for pinned aliases; time left and turn-off time only for timed ones, in whole minutes rounded up, `1 minute left` for one; busy rows read the busy words instead of the state). Progress dots read `Step 2 of 4`.
- Increase Contrast uses the contrast columns of the color table.
- Reduce Transparency and separators follow the system.

## Decisions beyond the design

- The clipboard card drops "Copied 1 minute ago": macOS doesn't record when something was copied.
- The Increase Contrast color values, the Sign Out confirmation, the copy for failing to remove the login item, the `Expires After` submenu, the enabled alias's right-click menu, and the busy words are defined here; the design doesn't show them.
- The Dark app icon needs a layered icon from Apple's Icon Composer; it is a follow-up. This redesign ships the Default icon.
