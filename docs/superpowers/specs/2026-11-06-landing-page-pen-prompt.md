# Ajour landing page: content brief for pen.dev

Design a single-page marketing website for **Ajour**, a free, open-source macOS menu bar app for SimpleLogin email aliases. This brief describes what the page says and in which order. The visual design is yours.

## About the product

- SimpleLogin gives people a separate email alias for every website. Many people keep the alias of a spammy website disabled.
- That turns into a chore when the site wants to email a login code. You have to:
  1. open the SimpleLogin dashboard;
  2. enable the alias;
  3. wait for the mail;
  4. remember to disable the alias again.
- Ajour does this from the Mac's menu bar in two clicks:
  1. You enable the alias for 5 minutes and log in.
  2. When the mail arrives, a notification offers to disable the alias again. If you ignore it, Ajour disables it when the time is up.

## Audience and tone

- **Audience:** Technical, privacy-minded people who hate spam. Most already use SimpleLogin (part of Proton). Don't explain what an email alias is.
- **Tone:** Funny and self-ironic. Ajour is a tiny app that does one small thing and is unreasonably proud of it. Spam and spammers get mocked. Clarity comes first, and the trust section and FAQ stay serious.
- **Goal:** Visitors leave smiling and download the app. The download is the only call to action.
- **Hard rules:**
  - All text is real text, not text baked into images.
  - No analytics, cookies, third-party fonts, or third-party scripts.
  - Use only openly licensed fonts, so the page can serve them itself.
  - Support light and dark appearance. The screenshots exist only in dark appearance, so they have to look right on both.

## Assets

- **App icon:** the macOS app icon.
- **Screenshots:** all five are in macOS dark appearance, on a blue gradient backdrop that is part of the image.
  - `menu.png` (1190×990): the menu with a Timers and a Pinned section. One alias has 47 minutes left and is selected, with its submenu open: Copy Address, Disable Now, Keep Enabled, Extend.
  - `all-aliases.png` (1264×1528): the All Aliases window with search, pinned aliases and remaining time.
  - `new-alias.png` (1064×772): the New Alias window with prefix, suffix and a live preview of the address.
  - `settings.png` (1064×1146): the Settings window with account, launch at login and about.
  - `onboarding.png` (1064×1172): the welcome step of the setup.

## Page content, top to bottom

### 1. Hero

- **Headline:** Let the login code in. Keep the spam out.
- **Subline:** Ajour turns a SimpleLogin alias on for a few minutes and off again, right from your Mac's menu bar. That's all it does, and it is unreasonably proud of it.
- **Primary button:** Download Ajour for Mac → `https://github.com/JonasDoebertin/ajour/releases/latest`
- **Small print next to the button:** Free and open source · macOS 26 or later · Signed and notarized
- **Visual:** the `menu.png` screenshot, ideally shown as if it hangs from a Mac menu bar.

### 2. The old way

- **Section title:** The old way, a tragedy in six acts
- **Acts, as a numbered sequence:**
  1. A website wants to email you a login code.
  2. Its alias is disabled, because this website has never sent you anything but spam.
  3. You open the SimpleLogin dashboard and scroll past 200 other aliases to find it.
  4. You enable it, go back, request the code again, and wait.
  5. The code arrives. You log in. You feel accomplished.
  6. You forget to disable the alias. Three weeks later, the newsletter finds you.
- **Closing line:** The end. Nobody claps.

### 3. The Ajour way

- **Section title:** The Ajour way
- **Steps, as a numbered sequence:**
  1. **Click the alias** in the menu bar.
  2. **Enable it for 5 minutes** and log in.
  3. **Disable it when the mail arrives.** A notification offers it right away. Ignore it, and Ajour disables the alias when the time is up.
- **Closing line:** That's it. That's the app.

### 4. Features

- **Section title:** Small app, surprisingly many opinions
- **Feature cards, each with a short title and one or two sentences:**
  - **Timers for aliases.** Turn any pinned alias on for 5 minutes, 1 hour, or 24 hours. The menu counts down and tells you when the alias turns off. Extend, keep, or end the timer early.
  - **Mail alerts with an off switch.** While a timer runs, Ajour checks the alias every 15 seconds. When mail arrives, the notification has a Disable Now button.
  - **No alias left behind.** If your Mac was asleep or Ajour wasn't running when a timer ended, the alias is disabled right after wake or at the next launch. Quitting Ajour disables timed aliases first.
  - **New aliases in one click.** Create a random alias and get it on your clipboard, optionally with an expiry date. Or pick your own prefix and one of your custom domains.
  - **Every alias, searchable.** The All Aliases window searches your whole account. Pin the ones you need to the menu.
  - **Out of your way.** Ajour lives in the menu bar, has no Dock icon, and can start at login. Every alias state has its own symbol and word, and VoiceOver reads them too.
- **Visual:** show `all-aliases.png`, `new-alias.png` and `settings.png` alongside the relevant cards.

### 5. Testimonials

- **Section title:** Reviews from the other side
- **Note under the title:** These people are made up. Their frustration is not.
- **Quotes, each shown with a one-out-of-five-stars rating:**
  - **"I used to reach 40,000 inboxes before breakfast. Now I reach an alias that was enabled for five minutes, two weeks ago."**
    Gary, Weekly Deals Newsletter. His unsubscribe link has been broken since 2014.
  - **"I had a once-in-a-lifetime business opportunity for this person. The alias was disabled before I got to the second paragraph."**
    A Prince with an urgent fund transfer.
  - **"We noticed you haven't opened our emails in a while. We are starting to think it's personal."**
    The re-engagement bot of a shop you bought one sock from.
  - **"Your package could not be delivered. Neither could my email."**
    Definitely a courier.

### 6. The serious part

- **Section title:** The serious part
- **Intro line:** We'll stop joking for a moment.
- **Facts, as a calm list:**
  - **An API key, never your password.** It is stored in your Keychain and nowhere else.
  - **One destination.** Ajour only talks to `app.simplelogin.io`.
  - **No analytics.** Ajour has no tracking and no third-party dependencies.
  - **Sandboxed.** The App Sandbox allows outgoing network connections and nothing else.
  - **Signed and notarized.** Releases carry a Developer ID and are notarized by Apple.
  - **Open source.** The code is on GitHub under the MIT license.
- **Honest limit:** SimpleLogin can't disable an alias on a schedule, so the timers run on your Mac. If your Mac sleeps through the end of a timer, the alias stays enabled until it wakes and Ajour is running.

### 7. FAQ

- **Section title:** Questions
- **Questions and answers:**
  - **Is Ajour made by SimpleLogin or Proton?**
    No. Ajour is an independent app built on SimpleLogin's public API. It is not affiliated with SimpleLogin or Proton AG.
  - **What does it cost?**
    Nothing. Ajour is free and open source under the MIT license.
  - **What do I need?**
    A Mac with macOS 26 or later and a SimpleLogin account. Ajour signs in with an API key that you create in SimpleLogin; the setup walks you through it.
  - **What happens if my Mac sleeps while a timer runs?**
    The alias is disabled as soon as your Mac wakes and Ajour is running.
  - **Does it work with a self-hosted SimpleLogin?**
    Not yet. It's planned.
  - **Can I install it with Homebrew?**
    Not yet. For now, download the zip, unzip it, and move Ajour to your Applications folder.

### 8. Footer

- **Repeat of the call to action:** Download Ajour for Mac → `https://github.com/JonasDoebertin/ajour/releases/latest`
- **Links:**
  - Source code on GitHub → `https://github.com/JonasDoebertin/ajour`
  - Report a bug or suggest an idea → `https://github.com/JonasDoebertin/ajour/issues`
- **Fine print:** MIT License · Ajour is an independent app and is not affiliated with SimpleLogin or Proton AG.
- **Legal links:**
  - Imprint → `https://dieserjonas.dev/imprint/`
  - Disclaimer → `https://dieserjonas.dev/disclaimer/`
  - Privacy → `https://dieserjonas.dev/privacy/`

## Page metadata

- **Title:** Ajour: SimpleLogin aliases from your Mac's menu bar
- **Description:** Enable a SimpleLogin alias for 5 minutes, get the login code, and let Ajour disable it again. A free, open-source menu bar app for macOS.
