# Ajour: Follow-ups to Retries and Failed Disables

Status: approved design (the user asked to go ahead; every decision below is Claude's call unless marked otherwise)
Date: 2026-10-22
Scope: issues #31, #32, #33, #34
Builds on: `2026-10-22-disable-failures-design.md`

## Intent

Close the edge cases the review of #30 found around key changes and sign-out, so Ajour never stays silent about an alias it leaves enabled, never shows a misleading reason, and the sign-out alerts follow macOS keyboard conventions.

## Non-goals

- The longer wait before re-toggling (#35); it needs its own design.
- Any change to retry counts, delays, budgets, or the notification copy from #30.

## 1. An enable or "Disable After" cut off by a key change (#31)

Today `TimerEngine.enable` throws `TimerEngineError.accountChanged` when the key changed while the alias was being enabled, after trying (best effort) to disable it again. `AppModel` swallows the error, and "Disable After" does the same. That is right after a sign-out, because the sign-out alert already warned. After a key replacement, or when disabling again failed, the person must be told.

- **Disabled again:** `TimerEngine.enable` reports whether the alias was disabled again.
- **Silent case:** silent only when the person is signed out *and* the alias was disabled again.
- **Shown cases:** everything else shows a message in the menu (`lastError`), like other failed actions:
  - Enable, disabled again: `<email> was enabled for the previous account and has been disabled.`
  - Enable, could not be disabled again: `<email> was enabled for the previous account and could not be disabled.` This one is shown even after sign-out, because the alias stays enabled untracked.
  - "Disable After", after a key replacement: `<email> belongs to the previous account, so no timer was started.` This is silent after sign-out, because the alias is unchanged.
- The copy follows the existing messages for aliases created for a previous account.

## 2. Sign Out Anyway when the timer file can't be saved (#32)

- **Discard fails:** when discarding the timers fails because the timer file can't be written, sign-out stops, as today. The message must not say the file is unreadable:
  - Title: `Could Not Sign Out`
  - Message: `The timer file could not be saved. Sign-out is blocked to avoid losing track of enabled aliases.`
  - An unreadable timer file keeps its current message.
- **Restore fails:** when removing the API key fails, the timers are restored, as today. If saving the restored timers fails too, Ajour still tracks them while it runs; the restore already sets memory first. The person sees the timer-file message above instead of the Keychain message, because it is the more urgent problem.

## 3. A concurrent disable must not overwrite "key invalid" (#33)

- **Keep the state:** once HTTP 401 has marked the timers as "key invalid" for the current key, a disable attempt from another pass that ends later doesn't change that alias's state, whether it failed transiently or was refused. It reports nothing.
- **Withdraw stale notifications:** when the key becomes invalid, every "… Ajour keeps trying." notification is withdrawn. Their Try Again could do nothing, and the "API key invalid" notification and menu item take over.

## 4. Keyboard in the sign-out alerts (#34)

- **"Sign Out of Ajour?" confirmation:**
  - Return signs out: the person just chose Sign Out, as in the macOS log-out confirmation.
  - Escape cancels.
- **"An Alias Is Still Enabled" alert:**
  - Return and Escape both cancel. Neither key can sign out.
  - Sign Out Anyway stays destructive and needs a click (or Tab and Space).
- **Mechanism:** left to the builder (an `NSAlert` sheet, or a custom sheet that looks like an alert). Both keys must be verified on screen in demo mode.

## Constraints

- Swift 6 strict concurrency, macOS 26, Swift Testing, XcodeGen; copy exactly as above (straight apostrophes).
- Tests never wait for real retry delays.
