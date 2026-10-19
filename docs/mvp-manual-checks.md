# MVP manual checks

Checks that need a real SimpleLogin account and the running app. Automated tests cover the logic; these cover the UI and system integration.

Tip: for expiry checks, temporarily shorten `AliasDuration.fiveMinutes.seconds` locally (don't commit it).

## Onboarding and settings

1. First launch shows onboarding.
2. A wrong key shows "The API key was rejected. Please sign in again." (the `APIError.unauthorized.userMessage` wording from the package).
3. A correct key shows name and email, then the final step. Done enables launch at login (check System Settings > General > Login Items) and shows the notification permission prompt.
4. After a relaunch, no onboarding appears, and Settings shows name and email.
5. Settings > Sign Out returns to onboarding.
6. Settings > Replace API Key… goes straight to the key step and closes after confirmation.
7. Copy a key in the browser and switch back: "Use key from clipboard" appears. It may trigger macOS 26's paste-privacy prompt; see concerns.
8. With ad-hoc signing, the Launch-at-login toggle may show "Could not change launch at login. …" instead of crashing.

## Menu: pinned and timed aliases

1. Pin a disabled test alias in the web app and open the menu. It appears as "○ alias@…" (on that first open, or on the second one if the refresh is still running).
2. "Enable for 5 Minutes":
   - The alias is enabled in the web app.
   - The menu bar icon switches to `envelope.badge.fill`.
   - The title shows "● … · 4:59 left".
3. The remaining time counts down. Check with the menu kept open, and again after reopening.
4. "Extend" ▸ "1 Hour": the remaining time jumps to about 1:00:00.
5. "Disable Now":
   - The alias is disabled in the web app.
   - It shows "○" right away.
   - The icon switches back.
6. Enable a pinned alias permanently in the web app and reopen the menu. It shows "●" with Disable Now and "Disable After …". "Disable After 5 Minutes" makes it timed, with no change in the web app.
7. Expiry: temporarily patch `AliasDuration.fiveMinutes.seconds` locally (e.g. 30) and don't commit it. After expiry, the alias is disabled in the web app and leaves the timed state.
8. Quit while an alias is timed. The alias is disabled in the web app.
9. "Copy Address" puts the email on the clipboard.
10. With Wi-Fi off, "Enable for …" shows "Could not reach SimpleLogin. Check your network connection." at the top of the menu. A later successful action removes it.
11. A timer started elsewhere for an alias that isn't pinned shows in the top section. You can create one by starting a timer, then unpinning the alias in the web app and reopening the menu.

## Notifications

1. Enable a pinned alias for 5 minutes and send a mail to it. Within about 15 s, a "Mail received" notification appears with "<alias> from <sender>".
2. Click the notification. The alias is disabled (the menu shows ○ and the icon goes back to normal).
3. Repeat, using the "Disable Now" button on the notification instead (hover the banner or open the notification's options).
4. Disable a timed alias from the menu while its "Mail received" notification is still in Notification Center. The notification disappears.
5. Quit the app while a "Mail received" notification is still in Notification Center, then click it. The app launches and the alias gets disabled.
6. Turn off Wi-Fi, let a shortened timer expire, and wait 2 minutes. One "Could not disable alias" notification appears. Turn Wi-Fi back on: the alias gets disabled and that notification is withdrawn.
7. Revoke the API key in the SimpleLogin web app while a timer runs, and let it expire. One "API key invalid" notification appears, and the menu shows "API key invalid – Re-enter Key…". Choose it, enter a valid key, and the menu item disappears while the pending disable runs.
8. Check that notification permission was requested at the end of onboarding: System Settings > Notifications > SimpleLogin for macOS.

## Creating aliases

1. "New Random Alias": the alias appears in the SimpleLogin web app on your default random-alias domain, it is in the clipboard, and an "Alias copied" banner appears.
2. "New Random Alias That Expires ▸ After 5 Minutes": the alias shows at the top of the menu in the timed section with a countdown, and is disabled after 5 minutes.
3. "New Alias…": the window opens in front, custom domains are listed first in the suffix picker, and "Disable after" defaults to Never. Creating on a custom domain copies the alias, shows the banner, and closes the window. The alias uses your default mailbox (check in the web app).
4. "New Alias…" with "Disable after 1 Hour": the alias appears in the timed section.
5. An invalid prefix (e.g. "ä!"): the server's error text appears inline in red and the window stays open.
6. Close and reopen the window: the form starts empty and the suffixes load again.

## All Aliases window

With a real account, from the menu bar: All Aliases…
1. The window opens in front. The list shows aliases with their notes, a pin icon on pinned ones, and the state on the right.
2. With more than 20 aliases, scrolling to the bottom loads more (a spinner appears briefly) with no duplicates.
3. Typing part of an alias's email in the search field finds it after a short pause. Clearing the field shows all aliases again.
4. Right-click a row and choose Pin. The pin icon appears, and the alias shows up in the menu bar menu's pinned section. Unpin removes it.
5. On a disabled, unpinned alias, choose "Enable for 5 Minutes". The row shows "5:00 left" counting down, and the menu shows the alias in the timed section at the top.
6. "Enable Permanently" on a disabled alias shows "Enabled", with no timer in the menu. "Disable" shows "Disabled". Both should match the SimpleLogin web app.
7. "Copy Address" puts the email on the clipboard.
8. Optional: with the network off, an action shows its error at the bottom of the window and as a single-line, shortened entry at the top of the menu.
