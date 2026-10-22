# MVP manual checks

Checks that need a real SimpleLogin account and the running app. Automated tests cover the logic; these cover the UI and system integration.

Tip: for expiry checks, temporarily shorten `AliasDuration.fiveMinutes.seconds` locally (don't commit it).

The bundle identifier changed to `de.dieserjonas.ajour`, so an API key saved by an earlier build (Keychain service `de.doebertin.simplelogin-macos`) is not found. Enter it once during onboarding, then delete the old item in Keychain Access.

## Onboarding and settings

1. First launch shows onboarding.
2. The progress dots read "Step 1 of 4" through "Step 4 of 4" as you go.
3. A wrong key shows "SimpleLogin did not accept this key. Check that you copied all of it, or create a new one." inline under the field.
4. A correct key shows name and email, then the final step. Done enables launch at login (check System Settings > General > Login Items) and shows the notification permission prompt.
5. Back returns from the key step to the welcome step and from "Signed In" to the key step. The welcome and final steps have no Back button.
6. After a relaunch, no onboarding appears, and Settings shows name and email.
7. Settings > Sign Out asks "Sign Out of Ajour?" with the sentence that Ajour disables aliases with a running timer and removes the API key. Cancel keeps you signed in. Sign Out returns to onboarding, and a running timer's alias is disabled in the web app.
8. Settings > Replace API Key… goes straight to the key step, with no progress dots and no Back button, and closes after confirmation.
9. "Settings…" in the menu, and ⌘, while an Ajour window is in front, both open Settings in front.
10. Settings > About shows the tagline and that Ajour is not affiliated with SimpleLogin or Proton AG.
11. Copy a key in the browser and switch back: the "API key on clipboard" card with "Use Key from Clipboard" appears. It may trigger macOS 26's paste-privacy prompt; see concerns.
12. With ad-hoc signing, the Launch-at-login toggle may show "Ajour could not be added to your login items. Allow it in System Settings › General › Login Items." with an "Open Login Items…" button instead of crashing. The button opens System Settings > General > Login Items.

## Menu: pinned and timed aliases

1. Pin a disabled test alias in the web app and open the menu. It appears under "Pinned" with the disabled symbol and the word "Disabled" under its address, at the latest a moment after the menu opens.
2. "Enable for 5 Minutes":
   - The alias is enabled in the web app.
   - The menu bar icon switches to the glyph with the timer dot.
   - The row moves under "Timers" and shows "4:59 left · off at HH:MM" under the address, with the timer symbol.
3. The remaining time counts down while the menu is open, also while that alias's submenu is open. The submenu stays open.
4. "Extend" ▸ "1 Hour": the remaining time jumps to about 1:00:00, and the turn-off time moves with it.
5. "Disable Now":
   - The alias is disabled in the web app.
   - It shows "Disabled" right away.
   - The icon switches back.
6. Enable a pinned alias permanently in the web app and reopen the menu. It shows "Enabled" with Disable Now and "Disable After …". "Disable After 5 Minutes" makes it timed, with no change in the web app.
7. Expiry: temporarily patch `AliasDuration.fiveMinutes.seconds` locally (e.g. 30) and don't commit it. After expiry, the alias is disabled in the web app and leaves the timed state.
8. Quit while an alias is timed. The alias is disabled in the web app.
9. "Copy Address" puts the email on the clipboard.
10. With Wi-Fi off, "Enable for …" shows "Could not reach SimpleLogin." with "Check your network connection." beneath it at the top of the menu. A later successful action removes it.
11. A timer started elsewhere for an alias that isn't pinned shows under "Timers" at the top. You can create one by starting a timer, then unpinning the alias in the web app and reopening the menu.

## Notifications

1. Enable a pinned alias for 5 minutes and send a mail to it. Within about 15 s, a "Mail received" notification appears with "<alias> from <sender>" and "Alias turns off at HH:MM".
2. Click the notification. The alias is disabled (the menu shows "Disabled" and the icon goes back to normal).
3. Repeat, using the "Disable Now" button on the notification instead (hover the banner or open the notification's options).
4. Disable a timed alias from the menu while its "Mail received" notification is still in Notification Center. The notification disappears.
5. Quit the app while a "Mail received" notification is still in Notification Center, then click it. The app launches and the alias gets disabled.
6. Turn off Wi-Fi, let a shortened timer expire, and wait 2 minutes. One "Could not disable alias" notification appears. Turn Wi-Fi back on: the alias gets disabled and that notification is withdrawn.
7. Revoke the API key in the SimpleLogin web app while a timer runs, and let it expire. One "API key invalid" notification appears, and the menu shows "API key invalid – Re-enter Key…". Choose it, enter a valid key, and the menu item disappears while the pending disable runs.
8. Check that notification permission was requested at the end of onboarding: System Settings > Notifications > Ajour.

## Creating aliases

1. "New Random Alias": the alias appears in the SimpleLogin web app on your default random-alias domain, it is in the clipboard, and an "Alias copied" banner appears.
2. "New Random Alias That Expires ▸ After 5 Minutes": the alias shows under "Timers" at the top of the menu with a countdown and its turn-off time, and is disabled after 5 minutes.
3. "New Alias…": the window opens in front, custom domains are listed first in the suffix picker, and "Disable after" defaults to Never. Creating on a custom domain copies the alias, shows the banner, and closes the window. The alias uses your default mailbox (check in the web app).
4. "New Alias…" with "Disable after 1 Hour": the alias appears under "Timers".
5. An invalid prefix (e.g. "ä!"): the server's error text appears inline in red and the window stays open.
6. Close and reopen the window: the form starts empty and the suffixes load again.

## All Aliases window

With a real account, from the menu bar: All Aliases…
1. The window opens in front. The subtitle counts aliases and running timers. The list groups aliases under "Pinned" and "Other Aliases", with their notes, a pin icon on pinned ones, and the state on the right.
2. With more than 20 aliases, scrolling to the bottom loads more (a spinner appears briefly) with no duplicates.
3. Typing part of an alias's email in the search field finds it after a short pause. Clearing the field shows all aliases again.
4. Right-click a row and choose Pin. The pin icon appears, and the alias shows up in the menu bar menu's pinned section. Unpin removes it.
5. On a disabled, unpinned alias, choose "Enable for 5 Minutes". The row shows "5:00 left" counting down with "off at HH:MM" beneath it, and the menu shows the alias under "Timers" at the top.
6. "Enable Permanently" on a disabled alias shows "Enabled", with no timer in the menu. "Disable" shows "Disabled". Both should match the SimpleLogin web app.
7. "Copy Address" puts the email on the clipboard.
8. Optional: with the network off, an action shows its error at the bottom of the window and as a single-line, shortened entry at the top of the menu.
