# Ajour: Landing Page

Status: approved
Date: 2026-11-06
Issue: #43
Companion: `2026-11-06-landing-page-pen-prompt.md` (the content brief for pen.dev)

## Intent

Ajour has no home on the web besides the repository. A single page explains what Ajour does to people who find it through a search engine, an AI agent's recommendation, or a friend, and leads them to the download.

Visitors should leave smiling, having found the page funny, and eager to control their aliases from the menu bar from now on.

## Audience

- Technical people who care about privacy and hate spam.
- Most already use SimpleLogin, or know it through Proton. People who have never heard of SimpleLogin are not the audience, so the page doesn't explain what an alias is. It does make clear right away that Ajour works with SimpleLogin and doesn't replace it.

## Goals

- One action: download the latest release.
- The core contrast lands: the tedious way to let one email through a disabled alias against two clicks in the menu bar.
- Search engines and AI agents can read everything that matters: real text, not text in images, and an FAQ that answers the questions people type.
- The trust facts that this audience checks before installing anything are easy to find.

## Non-goals

- Promoting the page. That comes later.
- A custom domain for Ajour. The owner's GitHub user site has the custom domain `dieserjonas.dev`, so GitHub serves the project site at `https://dieserjonas.dev/ajour/`; that is the page's address for now (owner, 2026-11-06). A domain of its own comes later.
- More than one page, a blog, a changelog, or translations. The page is in English.
- A newsletter signup, contact form, or any other way to collect data.

## Anti-goals

- Testimonials that could be read as real. They must be obviously made up, attributed to spammers, bots and similar villains, and labeled as made up.
- Humor at the expense of the reader, of SimpleLogin or Proton, or of any group of people. The targets are spam, spammers, and Ajour's own modesty.
- Jokes about security, bugs, or the API key. The trust section is plain and serious.
- Claims the app doesn't back up. Every feature and fact on the page must match the README.
- Analytics, tracking, cookies, or requests to third parties, including web fonts, badges and scripts from CDNs. An app whose pitch is "no analytics" can't have a page that tracks. Plain links to GitHub are fine.
- The made-up testimonials in structured data. They must not show up as `Review` or `aggregateRating` markup, which search engines would treat as fake reviews.

## Tone

- Self-ironic: Ajour is a tiny app that does one small thing and is unreasonably proud of it.
- Mocking: spam and the people who send it.
- Clear first: the joke is in the phrasing, never in leaving out what the feature does.
- Serious: the trust section and the FAQ answers.

## Page structure

From top to bottom. The pen.dev prompt carries the draft copy for each section.

1. **Hero:** name, a one-line headline, a self-ironic subline, the download button with "free and open source, macOS 26 or later" next to it, and the menu screenshot.
2. **The old way:** the manual routine as an overly dramatic tragedy in numbered acts, ending with the forgotten alias that lets the newsletter back in.
3. **The Ajour way:** the same task in three steps, ending with "That's it. That's the app."
4. **Features:** the README's feature list, rewritten in the page's tone, with the remaining screenshots.
5. **Testimonials:** made-up one-star reviews from spammers and bots, under a heading and note that say they're made up.
6. **The serious part:** the privacy and security facts, no jokes.
7. **FAQ:** short, factual answers to the questions people search for.
8. **Footer:**
   - the download again;
   - GitHub;
   - the MIT license;
   - "not affiliated with SimpleLogin or Proton AG";
   - links to the owner's existing [imprint](https://dieserjonas.dev/imprint/), [disclaimer](https://dieserjonas.dev/disclaimer/) and [privacy statement](https://dieserjonas.dev/privacy/). The page has no legal text of its own (owner).

## Facts the page may use

Taken from the README; nothing beyond these.

- Timers of 5 minutes, 1 hour, or 24 hours on pinned aliases. The menu shows the countdown and the time the alias turns off. Timers can be extended, the alias kept on, or disabled early.
- Each alias shows its state with a symbol and a word; color is never the only cue; VoiceOver reads state and turn-off time.
- While a timer runs, Ajour checks the alias every 15 seconds and notifies about new mail, with a Disable Now button.
- If the Mac sleeps or Ajour isn't running when a timer ends, the alias is disabled right after wake or at the next launch. Quitting disables timed aliases first. Repeated failures are reported and retried.
- One click creates a random alias and copies it, optionally with an expiry. The New Alias window takes a custom prefix and offers custom domains first.
- The All Aliases window searches the whole account; aliases can be pinned, copied, enabled or disabled from there.
- Menu bar only, no Dock icon, can start at login.
- API key, never the password; stored only in the Keychain. Talks only to `app.simplelogin.io`. No analytics, no third-party dependencies. App Sandbox with outgoing connections as its only entitlement. Signed with a Developer ID and notarized by Apple. MIT licensed, free.
- Requires macOS 26 or later and a SimpleLogin account.
- Not yet: self-hosted SimpleLogin, Homebrew, automatic updates.

## Order of work

1. The owner designs the page in pen.dev from the companion prompt.
2. Once the owner approves the design, it becomes the page as described under "Left to the builder". Typography, colors and layout come from the design. Fonts must be openly licensed so the page can serve them itself.

## Screenshots

Decided by the owner after the design review (2026-11-06):

- **New screenshots:** The page uses new screenshots, not the README's. Each is on a transparent background and exists in a light and a dark version, and the page shows the one that matches its own appearance.
- **Hero:** The hero uses a transparent screenshot of the open menu as well. The menu bar and the blue desktop behind it are built in HTML and CSS.
- **macOS appearance:** The status menu follows the system appearance. The owner switches it between the light and the dark capture; the builder doesn't change system settings.
- **Location:** The page serves its own copies from `site/`. The README keeps its current screenshots.
- **Approved design:** pen.dev, `Ajour.pen`, frames "Landing Page — Light" and "Landing Page — Dark" (approved 2026-11-06). The hero's small print drops "Signed and notarized"; the serious part keeps it.

## Decided

- Hosting on GitHub Pages under the default address; custom domain later (owner).
- Self-ironic humor, satirical testimonials, serious trust section (owner).
- English, one page, the screenshots from `docs/images/` (builder's call, accepted by the owner).
- The download buttons download the latest version directly from `https://github.com/JonasDoebertin/ajour/releases/latest/download/Ajour.zip`; every release also carries its zip as `Ajour.zip` for that stable name (owner, 2026-11-06). Before that they linked to the release page, because the zip's name carries the version (builder's call).
- The prince in the testimonials has no nationality, so the joke stays on the scam and not on a country (builder's call).
- The testimonials show a one-star rating as plain visuals, never as structured data (builder's call).
- No guard against a future unsigned release behind the "latest" link. Every release since 0.3.1 is signed by the release workflow (builder's call).
- The Open Graph image is a 1200×630 PNG with the app icon and the headline, made from the approved design and committed (builder's call).
- Fonts: Besley (display, with italics), Atkinson Hyperlegible Next (body) and Atkinson Hyperlegible Mono (caption), all SIL OFL, instead of the design's Fraunces, Inter and JetBrains Mono, which have become the default look of generated pages (owner, 2026-11-06). The pen file uses the same fonts.
- No `robots.txt`: under a project path, crawlers only read the one at the host root.
- Enabling GitHub Pages and setting the repository's homepage change public settings. The builder asks the owner before doing either (builder's call).

## Left to the builder

- **Visual design:** pen.dev, from the companion prompt.
- **Turning the design into the page:**
  - Static HTML and CSS in a `site/` folder.
  - Fonts and images served from the repository.
  - Deployed by a GitHub Actions Pages workflow on pushes to `main` that touch `site/`.
- **Search and preview metadata:**
  - Title and meta description from the prompt.
  - Open Graph image.
  - `SoftwareApplication` and `FAQPage` structured data that match the visible text.
- **Updating the repository:** set its homepage to the page's address and link the page from the README.
