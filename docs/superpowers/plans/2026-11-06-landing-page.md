# Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved pen.dev landing page as a static site on GitHub Pages at `https://dieserjonas.dev/ajour/` (the owner's user site has that custom domain, so GitHub serves the project site there).

**Architecture:**
- The page is hand-written semantic HTML and one CSS file in `site/`, with no JavaScript. Light and dark follow `prefers-color-scheme`.
- Screenshots are new transparent captures in a light and a dark version, swapped with `<picture>`.
- The "Ajour way" illustrations, menu bar icons and the Open Graph image are exported from the pen.dev design. Fonts are self-hosted.
- A stdlib-only Python check guards the page's rules, and a Pages workflow runs it and deploys `site/`.

**Tech Stack:** HTML, CSS, Swift (screenshot script), Python 3 stdlib (check), GitHub Actions Pages, pen.dev MCP (`mcp__pencil__execute`).

**Spec:**
- `docs/superpowers/specs/2026-11-06-landing-page-design.md`
- copy: `docs/superpowers/specs/2026-11-06-landing-page-pen-prompt.md`
- Design: `file:///Users/jonas/.pencil/documents/ce6f3bd8-1bc0-49f2-af78-d4daae6064d5/Ajour.pen`, frames `qUSbX` "Landing Page — Light" and `Z4XbS0` "Landing Page — Dark", each 1440 wide.

## Global Constraints

- The copy is word for word from the content brief, except the hero small print, which reads `Free and open source · macOS 26 or later`.
- Download links go to `https://github.com/JonasDoebertin/ajour/releases/latest`.
- **No third-party requests:**
  - No analytics, cookies or JavaScript.
  - No third-party fonts, scripts, styles or images.
  - Plain `<a>` links to GitHub and `dieserjonas.dev` are fine.
- The page lives under `/ajour/`, so every local URL is relative. No URL starts with `/`.
- The made-up testimonials are never in structured data. JSON-LD has no `Review` and no `aggregateRating`.
- The fonts are Besley (display), Atkinson Hyperlegible Next (body) and Atkinson Hyperlegible Mono (caption), all under the SIL OFL and served from `site/fonts/` with their license files. (Changed from Fraunces, Inter and JetBrains Mono after the build; see the spec.)
- Colors, sizes and spacing come from the design's `web-*` variables and frames, read with `Get(..., {resolveVariables: true})`. The design is 1440 wide, and below 900 px every section is one column.
- The builder never changes macOS system settings and only launches the Debug build in demo mode. The owner switches the system appearance for the screenshots.
- Enabling GitHub Pages and setting the repository homepage need the owner's go-ahead first.
- `actionlint` passes; its existing warning about the `xcode-27` label is known.
- Work happens on the `landing-page` branch and merges via PR with a green `test` check and the owner's approval.

## Review Focus

- **Phone width (390 px):** no horizontal scrolling. The hero desktop scales down, sections stack, and text stays at least 16 px. *Test:* Task 3, Step 6.
- **Dark appearance:** every screenshot and illustration switches to its dark file, and no light-only asset shows on a dark page. *Test:* Task 3, Step 6.
- **Served under `/ajour/`:** a root-relative URL breaks once deployed. *Test:* the check script rejects URLs starting with `/` (Task 3, Step 1).
- **A missing or misnamed asset** such as a font, image or icon. *Test:* the check script resolves every local reference (Task 3, Step 1).
- **Keyboard and screen readers:**
  - Links and buttons show a visible focus ring.
  - Every image has alt text. Purely decorative ones use `alt=""`.
  - There is exactly one `h1`.

  *Test:* the check script plus Task 3, Step 6.

---

### Task 1: Transparent screenshots in light and dark

**Files:**
- Modify: `scripts/take-screenshots.swift`
- Create: `site/images/{menu,all-aliases,new-alias,settings}-{light,dark}.png`

**Interfaces:**
- Produces: the eight PNGs above. Each has an alpha channel and a transparent background, and none has a window shadow, because CSS adds shadows. `menu-*.png` shows the main menu with the `travel@` submenu open (Copy Address, Disable Now, Keep Enabled, Extend), both menus composited at their on-screen positions.

- [ ] **Step 1: Add a `transparent` option to the script.**
  - **Usage:** `swift scripts/take-screenshots.swift <app> <output directory> [dark] [transparent]`. Options after the output directory can come in any order. Update the usage line and the header comment to match.
  - **Windows:** with `transparent`, `captureWindow` passes `-o` to `screencapture` to leave out the shadow.
  - **Menus:**
    - `captureMenu` skips `Backdrop`.
    - It captures each menu window (layer ≥ pop-up menu level) with `screencapture -x -o -l <id>` into a temporary file.
    - It composites the files with CoreGraphics onto a transparent canvas the size of the union of their bounds, at the screen's backing scale, and writes `menu.png`.
  - **Unchanged:** without the option, the script behaves exactly as before, and the README screenshots still come from it.
- [ ] **Step 2: Build the Debug app.**
  ```sh
  xcodegen generate
  xcodebuild build -project Ajour.xcodeproj -scheme Ajour -configuration Debug -derivedDataPath build/DerivedData
  ```
  Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Light capture.**
  - Ask the owner to switch macOS to Light and to keep their hands off the Mac while the script runs.
  - Run `swift scripts/take-screenshots.swift build/DerivedData/Build/Products/Debug/Ajour.app build/screenshots/light transparent`.
  - Expected: `saved menu.png`, `all-aliases.png`, `new-alias.png` and `settings.png`.
- [ ] **Step 4: Dark capture.**
  - Ask the owner to switch macOS to Dark.
  - Run the same command into `build/screenshots/dark`.
  - Ask the owner to switch back to their usual appearance.
- [ ] **Step 5: Check the captures.**
  - `sips -g hasAlpha build/screenshots/*/*.png` reports `yes` for every file.
  - Read each PNG. Checks:
    - corners and the space around the menus are transparent;
    - the menus are readable, not blank or black;
    - the light set is light and the dark set is dark.
  - If the menu windows capture blank or opaque, stop and report to the owner instead of falling back to a backdrop.
- [ ] **Step 6: Copy the files to their page names.** Copy them as `site/images/<name>-light.png` and `-dark.png`. Each file should be under 800 KB. If one is larger, run `pngquant --quality 80-95` (`brew install pngquant`, ask first) and check it again.
- [ ] **Step 7: Commit**: `git add scripts/take-screenshots.swift site/images/*-light.png site/images/*-dark.png && git commit -m "Capture transparent light and dark screenshots for the website"`

### Task 2: Design exports, icons and fonts

**Files:**
- Create:
  - `site/images/step-{1,2,3}-{light,dark}.png`
  - `site/images/menubar-{status,battery,wifi}.svg`
  - `site/images/caption-arrow.svg`
- Create:
  - `site/images/app-icon.png` (256 px)
  - `site/favicon.png` (64 px)
  - `site/apple-touch-icon.png` (180 px)
  - `site/og-image.png` (1200×630)
- Create: `site/fonts/*.woff2` and `site/fonts/LICENSE-{Fraunces,Inter,JetBrainsMono}.txt`

**Interfaces:**
- Produces: exactly these file names. Task 3 references them.

- [ ] **Step 1: Export the step illustrations.** In pen.dev, export them as PNG at scale 2 into a scratch directory, then rename to the file names below:
  - light, from `qUSbX`:
    - `UEZcU` → `step-1-light.png`
    - `dbxxs` → `step-2-light.png`
    - `eX2sm` → `step-3-light.png`
  - dark, from `Z4XbS0`:
    - `sfNfp` → `step-1-dark.png`
    - `GBnWl` → `step-2-dark.png`
    - `ZeAVd` → `step-3-dark.png`

  Check that each file has alpha and that its background is transparent around the shape.
- [ ] **Step 2: Export the hero's menu bar parts from `qUSbX` as SVG.**
  - `pnxJ7` (status item) → `menubar-status.svg`
  - `FPChC` → `menubar-battery.svg`
  - `GHlrH` → `menubar-wifi.svg`
  - `nvJjQ` → `caption-arrow.svg`

  Then remove any hard-coded background from the SVGs, except the status item's highlight pill.
- [ ] **Step 3: Make the icons.** Make them from `Ajour/Assets.xcassets/AppIcon.appiconset/`:
  - `cp icon_128x128@2x.png site/images/app-icon.png`
  - `cp icon_32x32@2x.png site/favicon.png`
  - `sips -z 180 180 icon_256x256@1x.png --out site/apple-touch-icon.png`
- [ ] **Step 4: Make the Open Graph image.**
  - Add a top-level frame "Open Graph" of 1200×630 to the pen file, next to the landing pages, with `placeholder: true` while working. It holds:
    - the `web-stage` background;
    - the app icon;
    - the headline in two lines as in the footer, "Let the login code in." and the italic "Keep the spam out.";
    - "Ajour for Mac" in Inter.
  - Export it at scale 1 to `site/og-image.png` and clear the placeholder.
- [ ] **Step 5: Get the fonts.**
  - In a new scratch directory, run `npm pack @fontsource-variable/fraunces @fontsource-variable/inter @fontsource-variable/jetbrains-mono` and unpack.
  - Copy the `latin` woff2 files to `site/fonts/`:
    - Fraunces normal and italic, with the weight axis and the optical size axis if the package has it;
    - Inter normal;
    - JetBrains Mono normal.
  - Copy each package's `LICENSE` as `LICENSE-<Family>.txt`.
- [ ] **Step 6: Commit**: `git add site && git commit -m "Add the website's images, icons and fonts"`

### Task 3: The page

**Files:**
- Create:
  - `scripts/check-site.py`
  - `site/index.html`
  - `site/style.css`
  - `site/sitemap.xml`

**Interfaces:**
- Consumes: the assets from Tasks 1 and 2, by file name.
- Produces: `python3 -I scripts/check-site.py site`. It exits 0 and prints `site OK` when the page passes, and otherwise prints one line per problem and exits 1. Task 4's workflow runs it.

- [ ] **Step 1: Write `scripts/check-site.py`.** It uses the stdlib only (`html.parser`, `json`, `pathlib`, `re`), takes the site directory as its argument, and checks:
  - **References:** `index.html` exists. Every local `src`, `srcset` entry, `<link href>` and CSS `url()` in `site/**/*.css` resolves to a file under the site directory.
  - **Relative URLs:** no `src`, `srcset`, `href` or CSS `url()` starts with `/`.
  - **No external loads:**
    - No `src` or `srcset` and no `<link href>` starts with `http`, except `<link rel="canonical">`.
    - No CSS file contains `@import` or `url(http`.
    - There is no `<script>` other than `type="application/ld+json"`.
  - **Structured data:**
    - Every JSON-LD block parses and contains neither `Review` nor `aggregateRating`.
    - The `FAQPage` question names each appear in the page's visible text.
  - **Images and headings:** exactly one `<h1>`. Every `<img>` has an `alt` attribute and `width` and `height`.
  - **Download links:** every `<a>` whose text contains `Download Ajour` has `href="https://github.com/JonasDoebertin/ajour/releases/latest"`, and there are at least two of them.
- [ ] **Step 2: Run the check and see it fail.** Run `python3 -I scripts/check-site.py site`. Expected: exit 1 with `index.html is missing`.
- [ ] **Step 3: Write `site/index.html`.**
  - **Head:**
    - `lang="en"`, the charset and viewport meta tags, and `<meta name="color-scheme" content="light dark">`.
    - `<title>Ajour: SimpleLogin aliases from your Mac's menu bar</title>` and the meta description from the brief.
    - A canonical link to `https://dieserjonas.dev/ajour/`.
    - Open Graph and Twitter tags (`summary_large_image`), with the absolute URL to `og-image.png`.
    - The favicon and the apple-touch-icon.
    - The CSP meta tag: `default-src 'self'; script-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`.
  - **JSON-LD** (two blocks):
    - `SoftwareApplication` with:
      - `name` Ajour;
      - `operatingSystem` "macOS 26 or later";
      - `applicationCategory` "UtilitiesApplication";
      - `offers` with price 0 and `priceCurrency` USD;
      - `downloadUrl` set to the latest release;
      - `license` set to the MIT license URL;
      - `isAccessibleForFree: true`;
      - `url` set to the canonical page.
    - `FAQPage` with the six questions and answers, word for word.
  - **Body:** one `<header>` (nav), one `<main>` with one `<section>` per design section, each with an `id`, and one `<footer>`.
    - **Headings:** The hero headline is the `h1`; section titles are `h2`; step, feature and FAQ titles are `h3`.
    - **Hero desktop:** a `div` with the blue gradient and a menu bar with the status icon, battery, Wi-Fi and a clock. The clock reads 5 minutes before the "off at" time of the 4-minute timer in the new `menu-*.png`. Below it is the menu screenshot, positioned under the status icon.
    - **Light and dark images:** each is a `<picture>` with `<source media="(prefers-color-scheme: dark)" srcset="images/<name>-dark.png">` and an `<img src="images/<name>-light.png">`.
    - **Image sizes:** `width` and `height` are the CSS size at 1x, which is half the PNG's pixels.
    - **Testimonials:**
      - Each is a `<figure>` with a `<blockquote>` and a `<figcaption>`.
      - The stars are decorative (`aria-hidden="true"`) next to the visible text "1 out of 5".
      - There is no rating markup.
    - **"The serious part":** a `<dl>`. The label "Honest limit" gets a period like the others.
    - **FAQ:** one `<h3>` and one `<p>` per question, always visible, not collapsible.
- [ ] **Step 4: Write `site/style.css`.**
  - **Fonts:** `@font-face` for the three families, with `font-display: swap`.
  - **Colors:** custom properties for the `web-*` colors. The light values sit on `:root`, and the dark values in `@media (prefers-color-scheme: dark)`.
  - **Layout:** a 1200 px content column with 120 px side padding at 1440 px. The layout of each section follows its frame in the design: two columns in the hero, the old way as a dark stage with acts, three step columns, the asymmetric features, the two-column testimonials, and serious part and FAQ with the title on the left.
  - **Below 900 px:**
    - One column with a 20 px side gutter.
    - Images above their text, and the hero desktop below the CTA at full width.
    - Headline sizes scaled down: h1 about 44 px, h2 about 36 px.
  - **Shadows:** done with `filter: drop-shadow()` on the transparent screenshots and illustrations.
  - **Focus:** `:focus-visible` gets a 2 px outline in `web-accent`.
  - **Motion:** none.
- [ ] **Step 5: Add `sitemap.xml`. Then run the check and fix it until it passes.**
  - `sitemap.xml` lists the canonical URL. There is no `robots.txt`: under a project path, crawlers only read the one at the host root.
  - Run `python3 -I scripts/check-site.py site`. Expected: `site OK` and exit 0.
- [ ] **Step 6: Check the page in a browser.**
  - Open `file://$PWD/site/index.html` with Playwright, at 1440×900 and at 390×844, each in light and dark (`browser_emulate_media` colorScheme).
  - For each of the four combinations:
    - take a full-page screenshot and compare it section by section with the exported design frames (`qUSbX` / `Z4XbS0`);
    - `document.documentElement.scrollWidth <= innerWidth`;
    - in dark, every `img.currentSrc` that has a dark variant ends in `-dark.png`;
    - tabbing to the download button shows the focus ring.
  - Fix and repeat until all four pass.
- [ ] **Step 7: Commit**: `git add scripts/check-site.py site && git commit -m "Build the landing page from the approved design"`

### Task 4: Deploy and docs

**Files:**
- Create: `.github/workflows/pages.yml`
- Modify:
  - `docs/ci.md`
  - `README.md`

**Interfaces:**
- Consumes: `python3 -I scripts/check-site.py site` from Task 3.

- [ ] **Step 1: Write `.github/workflows/pages.yml`.**
  - **Triggers:** `push` to `main` and `pull_request`, both with `paths: [site/**, scripts/check-site.py, .github/workflows/pages.yml]`, plus `workflow_dispatch`.
  - **Job `check`** (`ubuntu-latest`): `actions/checkout@v7` and the check script.
  - **Job `deploy`:**
    - Needs `check`. Runs only on `github.event_name != 'pull_request' && github.ref == 'refs/heads/main'`.
    - Permissions `pages: write` and `id-token: write`, top-level `contents: read`.
    - `environment: { name: github-pages, url: ${{ steps.deployment.outputs.page_url }} }`.
    - `concurrency: { group: pages, cancel-in-progress: false }`.
    - Steps: `actions/checkout@v7`, `actions/configure-pages@v6`, `actions/upload-pages-artifact@v5` with `path: site`, `actions/deploy-pages@v5` (id `deployment`).
- [ ] **Step 2: Run `actionlint`.** Expected: no findings in `pages.yml`.
- [ ] **Step 3: Update `docs/ci.md`.**
  - Add a "Website" section: what deploys, when, from where, how to run the check locally, and that Pages uses "GitHub Actions" as its source.
  - Replace the outdated paragraph that calls builds ad-hoc signed. It should say that releases are signed with a Developer ID and notarized, and that pull request builds stay ad-hoc signed.
- [ ] **Step 4: Update `README.md`.**
  - Add a "Website" link to `https://dieserjonas.dev/ajour/` in the centered intro.
  - Fix the menu screenshot's alt text to match the image: 47 minutes left, turning off at 15:41.
- [ ] **Step 5: Commit, push, open the PR.**
  - Commit: `git commit -m "Deploy the landing page to GitHub Pages"`.
  - Push `landing-page`, then open a PR that closes #43 and link it with `link_pull_request`.
  - Expected: the `test` and `check` jobs pass.
- [ ] **Step 6: Get the owner's go-ahead and enable Pages.**
  - Ask the owner. On a yes, run `gh api -X POST repos/JonasDoebertin/ajour/pages -f build_type=workflow`.
  - Expected: `gh api repos/JonasDoebertin/ajour/pages --jq .build_type` prints `workflow`.
- [ ] **Step 7: Merge and set the homepage.**
  - The owner approves the merge. Then run `gh pr merge --merge --delete-branch`.
  - Wait for the `pages.yml` run on `main`. Expected: it succeeds, and `curl -sI https://dieserjonas.dev/ajour/` returns `200`.
  - Run `gh repo edit JonasDoebertin/ajour --homepage https://dieserjonas.dev/ajour/`. Ask first, as in Step 6.
