# Continuous integration and releases

GitHub Actions runs on the `xcode-27` runner image with Xcode 27.1, the version the app is developed with.

- **Pushes to `main` and pull requests:** run the SimpleLoginKit and app tests.
- **Builds for pull requests:** add the `build` label to a pull request. The workflow removes the label, builds the app, and comments with a download link. The build is kept for 14 days. To build a newer commit, add the label again.
- **Releases:** push a tag like `v1.2.3` that points to a commit on `main`. The release workflow tests, builds the app with version 1.2.3, and attaches `Ajour.zip` and `Ajour.dmg` to a draft release titled "Ajour 1.2.3" with generated notes. Both keep one name across releases, so `releases/latest/download/Ajour.zip` and `releases/latest/download/Ajour.dmg` always download the latest published version; the website and the README link to the disk image. Manual runs of the workflow keep both as artifacts named `Ajour-run<number>.zip` and `Ajour-run<number>.dmg`. Review the draft on GitHub and publish it. A tag whose release is already published fails right away: a published release keeps its files, so release a new version instead.

```sh
git tag v1.2.3 && git push origin v1.2.3
```

A repository ruleset, "Protect release tags", covers tags matching `v*`: it blocks creating, moving and deleting them for everyone except repository admins, who bypass it. So only an admin can push a release tag.

Releases are signed with the owner's Developer ID and notarized by Apple; the release workflow fails rather than attach a build that Gatekeeper would reject. The build action also re-signs Sparkle's helper tools with the Developer ID, so the notarized app can update itself. The disk image opens to a window with the app, a link to Applications and the background from `packaging/dmg/`. `scripts/build-dmg.sh` builds it with dmgbuild, pinned by hash in `packaging/dmg/requirements.txt`, without Finder; the release workflow then signs, notarizes and staples it like the app. The release workflow also attests the build provenance of the final `Ajour.zip` and `Ajour.dmg`, for tag runs only. Builds for pull requests stay ad-hoc signed, so macOS asks before opening one the first time: open it once, then allow it in System Settings > Privacy & Security.

## Website

The landing page at <https://ajour.email/> is the static site in `site/`: HTML and CSS, with its fonts and images in the same folder. Its only script, `clock.js`, shows the visitor's current date and time in the hero's menu bar.

- **Pull requests** that change `site/`, `scripts/check-site.py`, `scripts/clock.test.mjs`, `scripts/appcast.py`, `scripts/appcast_test.py`, or the workflow run the website check, the clock tests and the feed tests.
- **Pushes to `main`** that change them run the check and deploy `site/` and the feed to GitHub Pages. Pages uses "GitHub Actions" as its source in the repository settings, with `ajour.email` as its custom domain. The domain's DNS points to GitHub Pages: A and AAAA records for the apex and a CNAME from `www` to `jonasdoebertin.github.io`. The domain is verified in the owner's GitHub account, so no other account can claim it for a Pages site.

The deploy also builds `appcast.xml`, the feed Sparkle reads to find updates, from the latest published release: its `Ajour.zip` and its notes. Publishing a release redeploys the site, so the feed picks it up. The private key is the `SPARKLE_PRIVATE_KEY` secret of the `github-pages` environment. The deploy publishes a feed only after `gh attestation verify` confirms that the release workflow run for that release's tag built `Ajour.zip`. Installed versions find updates only through this feed, so the site never deploys without one: a missing key, no published release, no `Ajour.zip`, a failed provenance check, or any other problem fails the deploy, and the previous site and feed stay live.

Run the check locally:

```sh
python3 -I scripts/check-site.py site
python3 -I scripts/appcast_test.py
node --test scripts/clock.test.mjs
```

It fails on:

- a missing file;
- a URL that starts with `/`; relative URLs keep the page working under any path;
- anything loaded from another server, and any script other than a module from `site/`;
- rating markup, and FAQ data that doesn't match the page;
- an image without alt text or size;
- a download link, or the structured data's `downloadUrl`, that doesn't point to `releases/latest/download/Ajour.dmg`.

The screenshots on the page are transparent, in a light and a dark version. To retake them:

1. Turn on Reduce Transparency in System Settings > Accessibility > Display.
2. Run the script once with the Mac in Light and once in Dark, from a Debug build: `swift scripts/take-screenshots.swift <path to Debug Ajour.app> <output directory> transparent`.
3. Copy the results to `site/images/<name>-light.png` and `site/images/<name>-dark.png`.
