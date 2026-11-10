# Shortcuts and Spotlight actions design

Issue: #9. Status: draft for owner approval.

## Intent

Someone signing up for a website wants an address without opening the menu. They type "Enable Alias" in Spotlight or press a hotkey in Raycast, pick one of their pinned aliases, and the address is on the clipboard, ready to paste, while Ajour turns the alias off again later. Or they ask for a fresh random alias the same way.

The actions do what the menu does, through the same timers and the same messages, so the menu always shows what an action changed.

## Goals

- Three actions, available in Spotlight and the Shortcuts app without any setup: Enable Alias, Create Random Alias and Disable Alias.
- Enable Alias and Create Random Alias end with the address on the clipboard and return it as their result, so a shortcut can pass it on.
- The alias picker suggests the pinned aliases and searches all aliases when someone types.
- Every failure ends the action with a message that says what went wrong, in the menu's words.

## Non-goals

- A Raycast extension. It gets its own issue. Raycast can already run a personal shortcut that uses these actions.
- A global keyboard shortcut inside Ajour (#8, closed in favor of this). The Shortcuts app and Raycast assign hotkeys.
- Custom aliases, other domains or mailboxes. The issue mentions "a random alias on domain Y"; a random alias uses the account's default domain and mailbox, like the menu's.
- Siri phrases beyond the ones App Shortcuts need, and widgets or Control Center controls.
- Copying the address when an alias is enabled from the menu. The menu stays as it is.

## Anti-goals

- An action that leaves an alias enabled without a timer when it was meant to expire, including when the system cancels the action halfway.
- An action that turns a permanently enabled alias into a timed one.
- An action that reports success while the alias is in a different state than reported.
- A second copy of the toggle, timer or creation logic next to the menu's.
- An action's failure or success changing the menu's error notice.

## Decisions

### Where the actions appear

- The actions are App Intents in the app target and run in the Ajour process, so they share `AppModel`, its timers and its notifications with the menu. If Ajour isn't running, macOS launches it in the background.
- An App Shortcuts provider registers all three, which makes them available in Spotlight and in the Shortcuts app's Ajour section without setup. Each phrase contains the `\(.applicationName)` token, for example "Enable alias in \(.applicationName)". Phrases don't name an alias, so Spotlight asks for one.
- The actions open no window themselves. One exception stays as it is: when Ajour has no API key, it opens onboarding at launch, also when macOS launched it for an action. That is the setup the action's error asks for.

### Reaching the app model

- `AppDelegate.init` registers the `AppModel` with the App Intents dependency manager right after creating it, before launch finishes, because an action can arrive right after a background launch. Unit test hosts skip the registration, like they skip the other launch work.
- Actions and queries are `@MainActor` where they touch `AppModel`. The alias entity is a `Sendable` value with the ID, email and note, and holds no reference to the model.
- Before it starts, an action waits until `AppModel` has left the loading phase, which happens when launch finishes. If that takes longer than 10 seconds, it fails with "Ajour isn't ready yet. Try again in a moment."
- The new `AppModel` methods run their work in a task of their own and await it, so cancelling the action never stops an enable, a creation or a disable halfway. A cancelled action simply reports nothing; the alias ends up in the same state as if it had finished.

### The alias parameter

- Suggestions are the pinned aliases in the menu's order, from `AppModel.pinned`. Until the pinned list has loaded, the query reads the first page of pinned aliases from SimpleLogin itself.
- Typing searches all aliases with SimpleLogin's alias search, first page only, the request the All Aliases window uses. Like that window, the query waits 300 ms and gives up if it was cancelled meanwhile, so fast typing in Spotlight sends one request instead of one per key.
- Resolving saved alias IDs uses the pinned list where it has them and reads the rest from SimpleLogin. An alias deleted on the server (SimpleLogin answers 404, or 400 "Unknown error") is left out of the result instead of failing, so a saved shortcut asks for an alias again. Other errors fail the resolution.
- The email and note shown in the picker may be slightly old; every action reads the alias's current state itself before it changes anything.

### Enable Alias (alias, duration)

- Duration: 5 Minutes, 1 Hour or 24 Hours, the menu's durations. Default 1 Hour, so a shortcut or Spotlight run doesn't have to ask.
- A new `AppModel` method reads the alias from SimpleLogin and then decides:
  - **Disabled:** enables it and starts a timer through `TimerEngine.enable`, like the menu's enable.
  - **Enabled with a running timer:** sets the timer to end the duration from now through `TimerEngine.enable`, like the menu's Extend. No toggle request.
  - **Enabled without a timer:** changes nothing. `TimerEngine.enable` would start a timer here, so the method never calls it for such an alias.
- The method holds the alias's busy mark from the read to the end, like every menu action, so neither a menu action nor a second action can change the alias in between. It also counts as an enable in flight, so quitting and signing out wait for it.
- The timer is saved before the address is copied, as for a new alias. If timer data is unreadable, the action fails before anything changes and nothing is copied.
- Then it copies the address, returns it and confirms in a dialog:
  - "<email> is enabled for 1 hour and copied."
  - "<email> stays enabled for 1 hour from now and is copied." (timer extended)
  - "<email> is already enabled and copied. Ajour won't turn it off." (no timer)

### Create Random Alias (expiry)

- Expiry: Never, 5 Minutes, 1 Hour or 24 Hours. Default Never, like the menu's "Create Random Alias". Expiry and duration are two separate App Enums mapped to `AliasDuration?` and `AliasDuration`.
- Uses the menu's creation path, which starts the timer before it copies, and disables a new alias whose timer can't start or that was created for an account that was signed out meanwhile.
- The creation path gets a parameter that leaves out the "copied" notification; actions use it, because their dialog replaces it. The menu and the New Alias window keep the notification.
- Returns the address and confirms: "<email> is created and copied." or "<email> is created for 1 hour and copied."

### Disable Alias (alias)

- Disables the alias now through `TimerEngine.disableNow`, like the menu's "Disable Now", and ends its timer. An alias that is already disabled counts as success. An alias whose expiry disable is already running joins that attempt and succeeds when it does.
- Copies nothing. Confirms: "<email> is disabled."

### Busy aliases

- An alias is busy while it has a busy mark from a menu action or an action, or while its expiry disable runs.
- Enable Alias fails on a busy alias with "<email> is busy. Try again in a moment." This prevents extending a timer whose expiry disable is about to turn the alias off.
- Disable Alias fails only on a busy mark; a running expiry disable is joined, see above.
- The menu keeps ignoring a second action on a busy alias without a message.

### Errors

- All messages come from `AppModel.userMessage(for:)`, so an action and the menu say the same thing: signed out ("Not signed in. Set up your API key first."), a rejected key, network and API errors, unreadable timer data, and account changes during an action. Busy, not ready and "<email> no longer exists." (an alias deleted on the server after it was picked) are new cases there.
- `AppModel` gets throwing versions of its enable, create random and disable work, extracted from `perform(on:)` and `createRandomAlias`. They never touch `lastError`. The menu's methods call them and keep setting and clearing `lastError` exactly as today.

### Side effects that stay

- Timers that an action starts behave like the menu's: they show in the menu, post the expiry and mail notifications, and are disabled at quit and sign-out.
- An action's change shows in the menu and in an open All Aliases window, through the same records of enabled changes the menu's actions write.

### Tests and checks

- Unit tests with the existing test transports cover:
  - the enable outcomes (disabled, timed, permanently enabled), busy, signed out, unreadable timer data, and that nothing is copied on failure;
  - creation with and without expiry, and that actions post no "copied" notification while the menu still does;
  - disable, already disabled, joining a running expiry disable;
  - that the menu's methods keep their `lastError` behavior and the throwing versions leave it alone;
  - the entity query: suggestions before and after the pinned list loads, search, resolving IDs including a deleted alias;
  - the dialog texts.
- The intents stay thin: they map parameters, call `AppModel` and build the dialog.
- The build log shows the App Intents metadata extraction for the app target. If the XcodeGen project doesn't run it, the builder adds what it needs.
- `docs/mvp-manual-checks.md` gets steps for each action from Spotlight and from the Shortcuts app, for a hotkey shortcut run from Raycast, and for an action while Ajour isn't running. The owner runs them with an installed build. A Debug build has the same bundle ID as the installed app, so Spotlight may list either; automated checks never trigger actions in the installed app.

### Raycast issue

A new issue, "Raycast extension", describes a native extension for later: list pinned aliases, enable with a duration, create random, copy. It notes that Raycast can already run a personal shortcut built on these actions.

## Left to the builder

- File and type names, and whether the intents live in one file or several.
- The exact App Shortcut phrases and SF Symbols.
- How waiting for the loading phase is built, as long as it never blocks the main actor.
