# Auto-updates design

Issue: #40. Status: draft for owner approval.

## Intent

Ajour should find, download and install new versions itself, so nobody has to check GitHub Releases by hand. Someone who has Ajour running in the menu bar for weeks gets a classic "an update is available" notice and can install it with an automatic restart, or let Ajour install updates on its own. Running timers survive the restart: an alias with 3 minutes left still has about 3 minutes left afterwards and is disabled on time.

The audience loves privacy. Every new network contact is said out loud on the website and in the README.

## Goals

- Sparkle 2 as the updater, added as a Swift package.
- An update notice that fits a menu bar app: a macOS notification and a menu item, not a window that pops up in the background.
- "Check for Updates…" in the menu and in Settings.
- One setting, "Install updates automatically", on by default, offered once in onboarding and kept in Settings.
- Automatic installs restart Ajour only at a quiet moment (see "When an automatic update restarts Ajour").
- Timers survive an update restart. A normal quit keeps disabling timed aliases, as today.
- Only published GitHub releases reach the feed. Drafts never reach anyone.
- The release notes in the update window are the release notes GitHub generates for the release.
- Website and README say that Ajour checks for updates and where it connects.

## Non-goals

- The DMG (#41). It comes next, as its own change. Updates use `Ajour.zip`, which already exists, and keep using it after the DMG ships.
- Homebrew (#36). A cask can later set `auto_updates true`.
- Hand-written release notes. Later, maybe.
- Beta or prerelease channels.
- Delta updates.

## Anti-goals

- An update restart that disables, forgets or shortens a running timer, or reports a login-code mail twice or not at all.
- An update restart while someone is in the middle of a login: a timer started minutes ago, a menu or window open.
- A draft release, or an unsigned or wrongly signed archive, reaching anyone.
- Any data beyond what an update check needs leaving the Mac. Sparkle's system profiling stays off.
- Debug builds and demo mode offering to replace themselves with the release build.

## Decisions

### Update notice

- When a scheduled check finds an update and automatic installs are off, Ajour posts a macOS notification ("Ajour <version> is available") through Sparkle's gentle reminders for background apps, and shows "Update Available…" in the menu. Clicking either opens Sparkle's standard update window with the release notes, "Install Update", "Remind Me Later" and "Skip This Version".
- A check the person starts with "Check for Updates…" shows Sparkle's window right away.
- When an update is downloaded and waits for a quiet moment, the menu shows "Restart to Update". Choosing it installs and restarts at once.
- Quitting Ajour while an update waits installs it on quit. That quit is a normal quit and disables timed aliases.

### When an automatic update restarts Ajour

With automatic installs on, Sparkle downloads the update in the background. Ajour then installs and restarts at the first moment when:

- no timer was started in the last 10 minutes,
- no Ajour window is open and the menu is not open, and
- the menu and every window have been closed for at least a minute. AppKit runs the action chosen in the menu after the menu closed, so an alias that is just being enabled or disabled has no timer or record to show for it yet.

Turning automatic installs off while an update waits stops the automatic restart. "Restart to Update" and installing on quit still work.

The remaining time of a timer doesn't matter, because timers survive the restart. What matters is whether someone is using Ajour right now: a fresh timer means they may be waiting for a login code.

Ajour checks the condition when the update is ready and once a minute while it waits.

### Timers across an update restart

Ajour already keeps every timer in `timers.json` with `enabledAt`, `expiresAt` and `lastNotifiedActivityTimestamp`, and reads it at launch. `MailArrivalDetector` compares against these stored values, so a mail that arrives during the restart is still reported once afterwards.

Today `applicationShouldTerminate` disables all timed aliases before quitting (`AppModel.prepareForTermination`). When Sparkle quits Ajour to install an update and relaunch it, Ajour still does everything else in that step:
- it waits for enables in flight, so their timers are saved;
- it stops the tick loop, the activity poll and the wake observer.

It skips only the disabling and leaves the timers in the file. Every other quit stays as it is.

If the relaunch fails, the aliases stay enabled until Ajour runs again, at the latest at the next login when "Launch at login" is on. This is the same honest limit as a Mac that sleeps through the end of a timer. The owner accepted it.

### Settings and onboarding

- Settings gets an "Updates" group with "Check for Updates…" and the checkbox "Install updates automatically". Like the menu, the button reads "Restart to Update" while a downloaded update waits, and it is disabled while Sparkle can't start a check, for example during a background download.
- The onboarding finish step gets the same checkbox under "Launch at login", starting from the current setting, which is on by default. Onboarding keeps its four steps.
- Ajour checks for updates once a day either way. The checkbox decides whether Ajour installs updates itself or only announces them. People updating from a version without Sparkle never see onboarding again; for them the default (on) applies silently.

### Feed and signing

- The appcast lives at `https://ajour.email/appcast.xml`, next to the website. It has one item: GitHub's latest release (published, not a draft, not a prerelease). Publishing releases out of order is not supported.
- The Pages workflow builds it, signs it and deploys it with the site:
  - on every site deploy from `main`, so a deploy never drops it;
  - when a release is published: a workflow on `release: published` starts the Pages workflow on `main` (`workflow_dispatch`), because the `github-pages` environment deploys only from `main`.
- The item points to that release's `Ajour.zip` (`https://github.com/JonasDoebertin/ajour/releases/download/<tag>/Ajour.zip`). It carries:
  - Sparkle's EdDSA signature and the length of that file;
  - `sparkle:version` = `CFBundleVersion` and `sparkle:shortVersionString` = `CFBundleShortVersionString`, both read from the `Info.plist` inside the published zip, not from workflow run data;
  - `sparkle:minimumSystemVersion` = 26.0;
  - the release notes as they are when the feed is built, converted to HTML. Edits to the draft's notes before publishing are included.
- The EdDSA private key is an environment secret of `github-pages` and used only by the Pages deploy job. EdDSA signatures are deterministic, so signing again on every deploy gives the same signature. The public key goes into `Info.plist` as `SUPublicEDKey`.
- Guards against a broken key:
  - CI fails when `SUPublicEDKey` is missing or a placeholder.
  - The Pages job verifies the signature it just made against the `SUPublicEDKey` in the published app before it deploys. It fails instead of publishing a feed the installed apps can't verify.
- The release keeps a single asset, `Ajour.zip`. No extra signature file is attached.
- The EdDSA signature is what proves an update comes from the owner. With `SUVerifyUpdateBeforeExtraction`, Sparkle also checks that the new app's code signature is valid, but not that it belongs to the same Developer ID team.

### Sandbox

Ajour stays in the App Sandbox. Following Sparkle's sandboxing guide: `SUEnableInstallerLauncherService` in `Info.plist` and the mach-lookup temporary exceptions for the installer services. Ajour already has `com.apple.security.network.client`, so it doesn't need Sparkle's downloader service.

### Debug builds and demo mode

The updater doesn't start in Debug builds or demo mode. The menu and Settings hide the update items there.

### Privacy copy

- Website, "The serious part":
  - "One destination." becomes "Two destinations. Ajour talks to app.simplelogin.io, and checks ajour.email for updates. Updates download from GitHub."
  - "No analytics." says that Sparkle, the updater, is the only third-party code, and that an update check sends no system information.
- README "Privacy and security": the same statements, replacing "only talks to `app.simplelogin.io`" and "no third-party dependencies".
- README "Install": Ajour updates itself from then on.
- `docs/ci.md`: how the appcast is built, which secret holds the key, and that only published releases reach it.

## Owner tasks

- Generate the EdDSA key pair with Sparkle's `generate_keys` before the first release with Sparkle. Then:
  - keep a backup of the private key somewhere safe, because losing it means existing installs can't verify new updates;
  - store the private key as the `github-pages` environment secret;
  - hand over the public key, which isn't secret, so it can go into `Info.plist`.

  The private key never appears in chat, logs or the repo. End-to-end tests use throwaway keys that are never committed.
- Publish releases as today. Publishing is what puts a release into the feed.

## Left to the builder

- How the appcast XML is written (a one-item feed doesn't need `generate_appcast`) and how the Markdown notes become HTML.
- The Sparkle version and how it's added through `project.yml`.
- How "the menu is open" and "a window is open" are observed.
- How the quiet-moment rule is structured; it should be a pure function with unit tests (fresh timer, old timer, no timers, window open, menu open).
- How to test an update end to end before the first real release with Sparkle, for example against a local appcast and two locally signed builds.
- Steps for `docs/mvp-manual-checks.md`: notice, manual install, automatic install at a quiet moment, timer survival, mail notification after the restart.
