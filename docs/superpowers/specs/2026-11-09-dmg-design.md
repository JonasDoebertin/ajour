# DMG design

Issue: #41. Status: draft for owner approval.

## Intent

Installing Ajour should be one drag. Someone who downloads Ajour from the website opens a disk image, sees Ajour on the left, the Applications folder on the right and a small arrow between them, and drags the app across. Today they get a zip, unzip it and have to know where to put the app.

The window looks like Ajour without becoming an installer screen: a calm petrol background in the website's palette, a dotted arrow that echoes the app icon, no text.

## Goals

- Every release has `Ajour.dmg` next to `Ajour.zip`.
- The disk image opens to a fixed window with the owner's background, the app and an Applications link, and is signed, notarized and stapled like the app.
- The website's download buttons and the README point to the disk image.
- The disk image is built in CI without driving Finder.

## Non-goals

- Replacing the zip. Sparkle downloads updates as `Ajour.zip` and installed versions expect it there. The zip stays exactly as it is, including its provenance attestation and the update feed.
- Disk images for pull request builds. They stay ad-hoc signed zips.
- Homebrew (#36). It can later use either file.
- A versioned file name. See "File name".

## Anti-goals

- A download button that points to a disk image no published release has yet.
- A disk image whose app isn't stapled, so the first launch needs a network check.
- Building the image by scripting Finder through AppleScript, which fails on runners without a logged-in session.
- Names below the icons that are hard to read in Light or Dark Mode.

## Decisions

### The window

- Volume name "Ajour".
- Window content 640 × 400 pt, icon view, icon size 128, no toolbar, sidebar, path bar or status bar.
- Ajour.app centered at x 160, y 190; a link to `/Applications` centered at x 480, y 190 (points from the top left of the content area). Finder shows the link as "Applications", localized as "Programme" on a German Mac.
- Background: `background.png` (640 × 400) and `background@2x.png` (1280 × 800), designed by the owner in pen.dev and committed to the repo. They are at `/Users/jonas/.pencil/documents/ce6f3bd8-1bc0-49f2-af78-d4daae6064d5/dmg/` and go into a new folder for packaging assets, separate from `site/`.
- The background is a muted petrol (#298278) whose band behind the names (y 255–290) keeps black and white 13 pt text at about 4.5:1. Finder doesn't switch DMG backgrounds with the appearance, but it switches the label color, so the label positions must not move.
- Files that support the layout (background, any volume icon) are hidden in the window.

### File name

`Ajour.dmg`, not `Ajour-<version>.dmg` as the issue suggested. `releases/latest/download/Ajour.dmg` then always downloads the newest version, the way the website links the zip today. The release title already carries the version.

### Building, signing and notarizing

- The release workflow builds the app, notarizes and staples it as today, and zips the stapled app as today.
- It then puts the stapled app into the disk image, signs the image with the Developer ID (with a secure timestamp), notarizes the image, staples the ticket to it and checks that Gatekeeper accepts it. A failure at any step fails the release, as for the app.
- Tag runs attach `Ajour.dmg` to the draft release next to `Ajour.zip`. A rerun replaces both on a draft. A published release keeps both, as today.
- Tag runs attest the build provenance of both files.
- Manual runs keep the disk image as a workflow artifact, like the zip (`Ajour-run<number>.dmg`).

### Website and README

They switch to the disk image in a separate pull request, merged only after the first release with `Ajour.dmg` is published. Until then, every link keeps pointing to the zip.

- All download links on the website and in the README point to `https://github.com/JonasDoebertin/ajour/releases/latest/download/Ajour.dmg`, including the `downloadUrl` in the page's structured data.
- `scripts/check-site.py` requires that link instead of the zip link.
- The Homebrew FAQ answer becomes: "Not yet. For now, download Ajour, open the disk image and drag Ajour to Applications." The structured FAQ data matches it.
- README "Install": download `Ajour.dmg`, open it, drag Ajour to Applications.
- `docs/ci.md` describes the disk image in the release section.

### Manual checks

`docs/mvp-manual-checks.md` gets steps for the disk image: it opens to the designed window in Light and in Dark Mode with readable names, the drag installs Ajour, the installed app opens without a Gatekeeper warning, and `spctl` accepts the image.

## Left to the builder

- The tool that writes the disk image and its window layout, as long as it doesn't drive Finder and works on the `xcode-27` runner. A third-party tool is pinned to an exact version, with a hash where the installer supports it, because it runs in the job that holds the signing keychain.
- The image format and compression, and how the 1x and 2x backgrounds become one image Finder uses on both kinds of displays.
- The folder name for the packaging assets.
- Whether the disk image gets the app icon as its volume icon.
- Whether the app's notarization and the image's notarization stay two submissions or become one, as long as both the app inside the image and the zip carry a stapled ticket.
