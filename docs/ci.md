# Continuous integration and releases

GitHub Actions runs on the `xcode-27` runner image with Xcode 27.1, the version the app is developed with.

- **Pushes to `main` and pull requests:** run the SimpleLoginKit and app tests.
- **Builds for pull requests:** add the `build` label to a pull request. The workflow removes the label, builds the app, and comments with a download link. The build is kept for 14 days. To build a newer commit, add the label again.
- **Releases:** push a tag like `v1.2.3` that points to a commit on `main`. The release workflow tests, builds the app with version 1.2.3, and attaches `Ajour.zip` to a draft release titled "Ajour 1.2.3" with generated notes. The zip keeps one name across releases, so `releases/latest/download/Ajour.zip` always downloads the latest published version; the website and the README link to it. Manual runs of the workflow keep their zip as an artifact named `Ajour-run<number>`. Review the draft on GitHub and publish it.

```sh
git tag v1.2.3 && git push origin v1.2.3
```

Releases are signed with the owner's Developer ID and notarized by Apple; the release workflow fails rather than attach a build that Gatekeeper would reject. The build action also re-signs Sparkle's helper tools with the Developer ID, so the notarized app can update itself. It also attests the build provenance of the final `Ajour.zip`. Builds for pull requests stay ad-hoc signed, so macOS asks before opening one the first time: open it once, then allow it in System Settings > Privacy & Security.

## Website

The landing page at <https://ajour.email/> is the static site in `site/`: HTML and CSS, with its fonts and images in the same folder. Its only script, `clock.js`, shows the visitor's current date and time in the hero's menu bar.

- **Pull requests** that change `site/`, `scripts/check-site.py`, `scripts/clock.test.mjs`, `scripts/appcast.py`, `scripts/appcast_test.py`, or the workflow run the website check, the clock tests and the feed tests.
- **Pushes to `main`** that change them run the check and deploy `site/` and the feed to GitHub Pages. Pages uses "GitHub Actions" as its source in the repository settings, with `ajour.email` as its custom domain. The domain's DNS points to GitHub Pages: A and AAAA records for the apex and a CNAME from `www` to `jonasdoebertin.github.io`. The domain is verified in the owner's GitHub account, so no other account can claim it for a Pages site.

The deploy also builds `appcast.xml`, the feed Sparkle reads to find updates, from the latest published release: its `Ajour.zip` and its notes. Publishing a release redeploys the site, so the feed picks it up. The private key is the `SPARKLE_PRIVATE_KEY` secret of the `github-pages` environment. The release workflow attests the build provenance of `Ajour.zip`, and the deploy signs a feed only after `gh attestation verify` accepts the archive. No published release, no `Ajour.zip`, a release without Sparkle, or a missing key is skipped with a warning and the site deploys without a feed. Any other failure, including a failed provenance check, fails the deploy and the previous site stays live.

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
- a download link that doesn't point to `releases/latest/download/Ajour.zip`.

The screenshots on the page are transparent, in a light and a dark version. To retake them:

1. Turn on Reduce Transparency in System Settings > Accessibility > Display.
2. Run the script once with the Mac in Light and once in Dark, from a Debug build: `swift scripts/take-screenshots.swift <path to Debug Ajour.app> <output directory> transparent`.
3. Copy the results to `site/images/<name>-light.png` and `site/images/<name>-dark.png`.
