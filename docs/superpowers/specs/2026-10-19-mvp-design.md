# Ajour: MVP Design

Status: draft, awaiting approval
Date: 2026-10-19
Scope: milestone "MVP" (issues #1–#7, adjusted as described in [Issue changes](#issue-changes))

## Intent

Jonas uses SimpleLogin aliases for websites that send a lot of spam. Those aliases are kept **disabled**. To log into such a website (which sends a login token by email), he has to log into the SimpleLogin web app, enable the alias, wait for the mail, log in to the website, and go back to disable the alias. Logging into SimpleLogin every single time is the main pain.

The app is a native macOS menu bar app that makes "enable this alias for a few minutes" a two-click action, watches for the incoming mail, and makes sure the alias is disabled again afterwards. It also makes creating new aliases quick.

### The core flow (in Jonas's words, condensed)

1. Open the website's login page.
2. In the menu bar, pick the alias from the pinned aliases and enable it for 5 minutes.
3. Log in on the website; the token mail is delivered.
4. Enter the token on the website.
5. A notification ("mail received, disable alias now?") appears because the app watched the alias's activity. Clicking it disables the alias immediately.
6. If the notification is ignored, the alias is disabled anyway after at most 5 minutes.

## Goals

- Sign in once, stay signed in.
- Enable a pinned alias for a fixed duration from the menu bar; the app reliably disables it again.
- Notify when mail arrives on a temporarily enabled alias, with a one-click "disable now".
- Show which aliases are temporarily enabled and how much time is left.
- Create a random alias in one click (copied to the clipboard), optionally with an expiry.
- Create a custom alias (own prefix, chosen domain) in a small window.
- Browse and search all aliases in a window, and pin/unpin them there.
- Run as a menu-bar-only app that starts at login.

## Non-goals (MVP)

- Sign-in via email/password + 2FA, Sign in with Proton, or FIDO. API key only.
- Configurable API URL / self-hosted SimpleLogin.
- Multiple accounts.
- Mailbox, custom domain, contact, or settings management.
- Global keyboard shortcut, Shortcuts/Spotlight actions, per-sender blocking, statistics, automatic notes, browser website detection (backlog issues #8–#13).
- Mac App Store distribution, payments, or any public release. The app is for Jonas only for now.

## Anti-goals

- **An alias silently stays enabled.** The whole point is that spam aliases end up disabled again. Any failure to disable (offline, server error, app not running) must be retried and, if it keeps failing, surfaced to the user. Never fail quietly.
- **Toggling the wrong way.** SimpleLogin's toggle endpoint flips state; blindly calling it can enable an alias that should be disabled. Every enable/disable must be state-aware.
- **The API key leaking.** It lives in the Keychain only: not in UserDefaults, logs, or crash output.

## Constraints

- Personal use first, but a later public release should not require a rewrite (low priority). Concretely: App Sandbox on, no private APIs, no hardcoded personal data.
- SimpleLogin has no server-side scheduling. Expiry is enforced by the app on the Mac.
- When the Mac sleeps, is off, or the app isn't running at expiry, the alias is disabled as soon as possible afterwards: directly after wake, or at app launch. (Decided by Jonas.)
- API: [SimpleLogin API docs](https://github.com/simple-login/app/blob/master/docs/api.md). Base URL `https://app.simplelogin.io`. Auth header `Authentication: <api key>`. `401` means the key is invalid. Error bodies are `{"error": "..."}` and may be shown to the user as-is.

## Behavior

### Onboarding (first launch, no key in Keychain)

A small window guides through setting up an API key:

1. Short explanation: the app needs a SimpleLogin API key and never sees the password.
2. Button opening `https://app.simplelogin.io/dashboard/api_key` in the default browser, with a hint: create a new key, name it e.g. "Mac", copy it.
3. A field to paste the key. When the window becomes active again and the clipboard holds something that looks like a key, the app offers to use it. It never submits automatically.
4. The key is validated immediately via `GET /api/user_info`; on success the app shows the account name and email for confirmation. On `401` or network errors it says clearly what went wrong.
5. Key goes to the Keychain, the window closes, the app lives in the menu bar from then on.

The final onboarding step includes a "Launch at login" checkbox, pre-checked. *(Claude's call.)*

### Menu bar menu

Classic macOS menu (not a popover). Structure:

```
[timed, unpinned alias · 0:42 left]  ▸  Copy Address / Disable Now / Extend
─────────────
[pinned alias 1]                     ▸  Copy Address
                                        ─────────────
                                        Enable for 5 Minutes
                                        Enable for 1 Hour
                                        Enable for 24 Hours
[pinned alias 2 · 3:12 left]         ▸  Copy Address
                                        ─────────────
                                        Disable Now
                                        Extend: 5 Minutes / 1 Hour / 24 Hours
─────────────
New Random Alias
New Random Alias That Expires        ▸  After 5 Minutes / After 1 Hour / After 24 Hours
New Alias…
All Aliases…
─────────────
Settings…
Quit
```

- **Temporarily enabled aliases that aren't pinned** (from random aliases with expiry, New Alias… with "Disable after", or the All Aliases window) get their own section at the top, driven by the local timer records. Pinned aliases with a timer stay in the pinned section and are not duplicated. *(Claude's call.)*
- **Pinned aliases** are SimpleLogin's own `pinned` flag (`GET /api/v2/aliases?pinned`, `PATCH /api/aliases/:id` with `pinned`). They sync with the web app. *(Claude's call: during the conversation the guess was local storage; the API turned out to support pinning natively, which is what "angepinnt" means in SimpleLogin anyway.)*
- Each pinned alias shows its state: disabled, enabled (permanently), or enabled with remaining time. Submenu content depends on state:
  - disabled → Copy Address, Enable for 5 min / 1 h / 24 h
  - timed → Copy Address, Disable Now, Extend (a new duration counted from now)
  - permanently enabled → Copy Address, Disable Now, Enable for … is replaced by "Disable after 5 min / 1 h / 24 h" *(Claude's call)*
- A menu item with a submenu cannot itself be clicked in macOS, hence the separate "New Random Alias" and "New Random Alias That Expires ▸" items.
- **Menu bar icon** changes (e.g. filled vs. outline) while at least one timed alias is active. *(Claude's call.)*
- Durations are fixed for the MVP: 5 minutes, 1 hour, 24 hours.
- The pinned list is refreshed when the menu opens (cached data shown immediately, updated in place).

### Timed enable

- Enabling: fetch the alias, call `POST /api/aliases/:id/toggle` only if it is currently disabled, then persist a timer record `{aliasID, email, enabledAt, expiresAt, lastNotifiedActivityTimestamp}`.
- "Disable after …" on a permanently enabled alias creates the same timer record (with `enabledAt` = now), so mail-arrival notifications apply too.
- Extend only changes `expiresAt` (new duration counted from now). `enabledAt` and `lastNotifiedActivityTimestamp` are kept, so already-notified mail isn't notified again.
- Expiry: fetch the alias, toggle only if currently enabled, then delete the timer record. If the alias was disabled meanwhile (e.g. via the web app), just drop the record.
- Timer records are persisted on disk so they survive app quit, crash, reboot, and sleep.
- On app launch and on `NSWorkspace.didWakeNotification`, every expired record is processed first.
- Right after wake the network may not be up yet. Failed disables are retried with backoff until they succeed. If still failing after ~2 minutes, show a notification ("Could not disable x@y, will keep trying"), and keep the record (and the active icon) until it succeeds.
- If Jonas manually disables a timed alias ("Disable Now", notification, or All Aliases window), the record is removed.
- Signing out first disables all timed aliases, then removes the key. *(Claude's call.)*
- **Quit** with timed aliases active: the app tries to disable them before terminating (bounded, ~5 seconds, no confirmation dialog). Whatever fails stays as a record and is handled at next launch. Crash or force-quit simply leave the records for next launch. *(Claude's call.)*
- **`401` after onboarding** (key revoked or deleted) is a permanent failure, not a retry case: stop retrying, keep the timer records, show a notification and a menu item "API key invalid – Re-enter Key…", and keep the active icon. Replacing the key works while records are pending; pending disables run right after a valid key is saved. *(Claude's call.)*

### Mail-arrival notification

- While an alias is timed-enabled, poll `GET /api/aliases/:id` about every 15 seconds and look at `latest_activity`. A new activity with `action == "forward"`, a timestamp at or after `enabledAt` (allow a few seconds of clock skew), and newer than `lastNotifiedActivityTimestamp` means mail arrived. Update `lastNotifiedActivityTimestamp` when notifying.
- Show a notification once per new activity: title "Mail received", body with alias email and sender (`latest_activity.contact.email`), action button **Disable Now**. Clicking the notification itself also disables the alias. (Jonas: "click the notification, alias gets disabled".)
- After disabling, polling for that alias stops. Polling also stops at expiry.
- Notification permission is requested at the end of onboarding.

### New Random Alias

- `POST /api/alias/random/new` (no body needed). It uses the default random-alias domain from the SimpleLogin account settings, which is what Jonas means by "default domain".
- The new alias is enabled. Its email is copied to the clipboard and a short confirmation is shown (notification).
- The "That Expires ▸" variant creates it the same way and immediately starts a timer record with the chosen duration (the full timed-enable behavior, including mail-arrival notifications, applies).

### New Alias… window

- Text field for the prefix, popup for the suffix/domain. Options come from `GET /api/v5/alias/options` (`suffixes[]` with `suffix`, `signed_suffix`, `is_custom`). Custom domains are listed first. `can_create == false` shows the reason and disables creation.
- Optional "Disable after" picker: Never (default) / 5 min / 1 h / 24 h. *(Claude's call, for consistency with random aliases.)*
- Create via `POST /api/v3/alias/custom/new` with `alias_prefix`, `signed_suffix`, and `mailbox_ids` = the default mailbox from `GET /api/v2/mailboxes`.
- On success: copy email to clipboard, close window. On error: show the API's error message inline.

### All Aliases… window

- List of all aliases, paginated from `GET /api/v2/aliases?page_id=n` (20 per page), loading more on scroll.
- Search field; searching uses the API's `query` (via `POST /api/v2/aliases`, debounced). No local database in the MVP. *(Claude's call.)*
- Each row: email, note (if any), enabled/disabled/timed state, pin indicator.
- Row actions (context menu and/or inline buttons): Pin/Unpin, Copy Address, Enable for 5 min / 1 h / 24 h, Enable/Disable permanently.

### Settings window

- Account: name and email from `GET /api/user_info`; Sign Out.
- Replace API key (re-runs the onboarding key step).
- Launch at login toggle (`SMAppService.mainApp`).

## Technical decisions (Claude's calls, all overridable)

- Swift 6 with strict concurrency; `LSUIElement = YES` (no Dock icon). The menu bar item is AppKit (`NSStatusItem`/`NSMenu`): `MenuBarExtra` rebuilds its whole menu on every change, which closes open submenus and rules out live countdowns. Windows are `NSWindow`s hosting SwiftUI views, because AppKit code can't use SwiftUI's `openWindow`.
- Deployment target: macOS 26 (the only Mac it runs on right now). Development: Xcode 27, Swift 6.4.
- No third-party dependencies: `URLSession` with async/await, `Codable`, Security framework for Keychain, `UserNotifications`, `ServiceManagement`.
- App Sandbox with the outgoing network client entitlement.
- Own thin API client. Don't depend on `simple-login/swift-package` (unmaintained since 2024, no license), but it and the iOS app are useful references for model shapes.
- Timer records stored as a small JSON file in Application Support.
- Core logic (API client, timer/expiry logic, activity detection) is testable without UI: injectable clock and HTTP layer, tests with Swift Testing.
- Signing with Jonas's Apple Development team for local use; no notarization for now.
- Name: **Ajour**, bundle identifier `de.dieserjonas.ajour`. The SimpleLogin name only appears descriptively ("Quick aliases for SimpleLogin"), never as the app name or in the icon, and the app states that it is not affiliated with SimpleLogin or Proton AG. Proton publishes its own "SimpleLogin for Safari", so "SimpleLogin for …" would read as an official product.

## Left to the builder

- Project layout (single app target vs. app + local Swift package).
- Exact icons, copy, and window layouts, within the structure above.
- Polling interval tuning and backoff details, within the behavior above.
- Heuristic for "clipboard looks like an API key".

## Issue changes

Issues #2, #4, #5, and #7 are fully covered by this document. After this design is approved, update GitHub issues accordingly (not part of the implementation plan):

- #1 → API key sign-in with guided onboarding; move email/password + 2FA, Sign in with Proton, and configurable API URL to a new backlog issue.
- #3 → "New Random Alias" (default domain, optional expiry) and "New Alias…" window; the custom-domain workaround from the issue body is no longer needed.
- #6 → "All Aliases" window with search and pin/unpin.
- New MVP issue: pinned aliases in the menu bar.
