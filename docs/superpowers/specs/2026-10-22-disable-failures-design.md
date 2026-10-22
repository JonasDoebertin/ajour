# Ajour: Retries and Failed Disables

Status: approved design
Date: 2026-10-22
Scope: issues #16, #17, #18, #23

## Intent

Ajour's promise is that an alias with a timer turns off again. When that fails, the person must find out right away and why, must be able to act, and must not be nagged. Short network hiccups should not surface at all.

Today, a failed disable at expiry is retried silently with growing delays, the row shows `0:00 left` as if nothing were wrong (#23), and a notification without a reason or button comes after 2 minutes. A disable that SimpleLogin refuses (HTTP 403) notifies again on every launch and looks like a normal timer in the menu (#18). Sign-out blames the connection whatever the cause (#17) and gives up waiting for a slow enable after 5 seconds, leaving that alias enabled untracked (#16). No other request is retried.

## Goals

- Every request to SimpleLogin survives a short hiccup: it is tried up to three times, a few seconds apart, before it counts as failed.
- A timer whose alias can't be disabled says so right away, with the reason, in a notification and in the alias's row.
- Ajour keeps trying in the background and cleans up after itself when it succeeds.
- A refused disable is reported once and then stays quiet in the menu, with ways out.
- Sign-out tells the truth about what blocks it and lets the person sign out anyway.

## Non-goals

- Changing how a rejected key (HTTP 401) is handled. It keeps its notification and the "API key invalid – Re-enter Key…" menu item.
- Changing quit. It keeps its 5-second budget; what stays enabled is disabled on the next launch.
- Changing sign-out when the timer file is unreadable. It stays blocked.
- Demo-mode states for failures, and new screenshots.

## Anti-goals

- A request that changes something must never be applied twice by a retry. A repeated toggle would turn the alias back on; a repeated create would make a second alias.
- No repeated notifications for the same failure, and none for a failure the person can't fix by waiting.

## Retrying requests

1. A request is tried up to **three times** in total, **2 seconds** apart. The wait is cancelled with the task. Each try keeps the existing 15-second request timeout (`AppModel.sessionConfiguration()`), so a request that keeps timing out fails after about 50 seconds.
2. Only **transient** failures are retried: no network or a dropped connection, a timeout, HTTP 5xx, and HTTP 429. Every other answer (401, 403, 404, other 4xx, an undecodable response) fails at once.
3. **Requests that only read** (`GET`, the alias search `POST`) and **the pin change** (`PATCH`, which sets a value) are retried on every transient failure.
4. **Requests that change something relative to the current state** are the toggle and the creation of random and custom aliases. They are retried only when the failure shows the request never reached the server: no internet connection, host not found, can't connect, DNS failure. A timeout, a dropped connection, or a 5xx after sending may mean the change happened, so they fail at once. *(Claude's call. In the conversation I said a create would first check whether the first attempt went through. SimpleLogin offers no way to find a random alias created by a lost request, so the rule is "retry only what certainly wasn't sent" instead.)*
5. **Switching an alias on or off** (`AliasSwitch`) reads the alias, then toggles it if needed. When the toggle fails in a way that may have reached the server, the switch reads the alias again: if it is now in the wanted state, it has succeeded. Otherwise it toggles again. At most three toggles are sent in total.
6. The retries live in the SimpleLoginKit package (`SimpleLoginAPI` and `AliasSwitch`), so every caller gets them without change. The delay is injectable so tests don't wait.
7. While the attempts run, the alias row shows its busy state (`Enabling…`, `Disabling…`, `Updating…`) as today. When all attempts fail, the error appears where the action was started, as today.

## Failed disables at expiry

### When attempts fail for a transient reason

1. When a timer ends, its row shows `Disabling…` with the busy symbol while the disable runs, in the menu and in All Aliases. This fixes #23. The same applies to every later background attempt and to "Try Again".
2. When all three quick attempts fail, a notification is posted **right away**. The 2-minute wait before reporting goes away, except after wake: during the first **2 minutes after the Mac wakes**, failures aren't reported, because the network is often not back yet. Ajour keeps trying silently and reports only if the disable still fails once those 2 minutes are over. The row shows its state (below) during that time as usual.
3. Ajour keeps trying in the background, with delays of 5, 10, 20, 40, 60 and then 120 seconds between attempts, staying at 120 seconds until it succeeds. Each background attempt again makes up to three quick tries.
4. The notification is posted once per failure episode. Further failed attempts don't post again. An episode ends when the alias is disabled, its timer is extended or kept enabled, or the app quits.
5. When the disable succeeds, the notification is withdrawn (as today for disabled aliases).

**Notification**

- Title: `Could not disable alias`
- Body: `<email> is still enabled. <reason> Ajour keeps trying.`
- Reasons:
  - No connection or a timeout: `SimpleLogin can't be reached.`
  - HTTP 5xx or 429: `SimpleLogin isn't responding (error <status>).`
  - Anything else: `SimpleLogin reported an error.`
- Action: **Try Again**. It dismisses the notification and starts the next attempt right away instead of waiting for the next delay. Clicking the notification itself does the same. *(Claude's call: the click doing the same as the button matches the mail notification, where both disable.)*
- *(Claude's call: the reason texts above.)*

**Menu row and All Aliases row between attempts**

- Symbol: a new **Stuck** symbol, the 14 pt ring with an exclamation mark inside, in `Danger`. *(Claude's call.)*
- Status line: `Not disabled · retrying` in `Danger`.
- VoiceOver: `<email>, not disabled, Ajour keeps trying`.
- Submenu (menu) and context menu (All Aliases): Copy Address, then **Try Again** (`arrow.clockwise`), **Keep Enabled**, and **Extend**. Keep Enabled and Extend end the episode as they do today. *(Claude's call: Try Again replaces Disable Now here, because the alias is already being disabled.)*

### When SimpleLogin refuses the disable (HTTP 403)

1. A notification is posted **once per timer**, also across launches. The timer record remembers that it was reported, in the timer file. After a key change the alias is tried again; a second refusal of the same timer stays silent. *(Claude's call: once per timer, not once per key.)*
2. No automatic retries with the same key (as today). There is no Try Again, because the same key gets the same answer.
3. Notification:
   - Title: `Could not disable alias`
   - Body: `The current API key can't change <email>, so it stays enabled. Keep it enabled or use a different key from the menu.`
   - No action button. A click opens nothing. *(Claude's call.)*
4. Row in the menu and All Aliases:
   - Symbol: Stuck, in `Danger`.
   - Status line: `Can't disable with this key`.
   - VoiceOver: `<email>, can't be disabled with the current API key`.
   - Submenu and context menu: Copy Address, then **Keep Enabled** (drops the timer, the alias stays enabled) and **Replace API Key…** (opens the existing key replacement, `MenuAction.reEnterAPIKey`).
5. The row stays in the menu until one of those happens. The menu bar glyph keeps showing running timers while it does. No badge and no other reminder.

### Rows unchanged

A row whose disable fails because the key is invalid (401) keeps today's behavior: the timer stays, the menu shows the "API key invalid" problem.

## Signing out

1. After the confirmation, the Sign Out button shows a spinner and is disabled (as today) and reads `Signing Out…`.
2. Ajour first waits for enables and alias creations still running, then disables every alias with a timer, each with its quick attempts. The whole sign-out may take **at most 30 seconds**. What isn't done then counts as failed. Quit keeps its 5 seconds. *(Claude's call: the 30 seconds.)* This fixes #16: a slow enable no longer gets skipped after 5 seconds.
3. When aliases stay enabled, an alert lists them, each with its reason (#17):
   - Title: `An Alias Is Still Enabled` or `<n> Aliases Are Still Enabled`
   - Message: one line per alias, `<email>: <reason>`:
     - `SimpleLogin can't be reached` or `SimpleLogin isn't responding`
     - `the API key can't change it`
     - For enables and creations that haven't finished within the 30 seconds, one line without an address, because a new alias has none yet: `1 alias being enabled or created right now` or `<n> aliases being enabled or created right now`
     - `the API key was rejected`, for HTTP 401
     - `SimpleLogin reported an error`, for anything else
     - A disable cut off by the 30 seconds counts as `SimpleLogin can't be reached`.
     *(Claude's call: the last three.)*
   - Then: `If you sign out anyway, it stays enabled.` for one alias, `If you sign out anyway, these aliases stay enabled.` for more.
   - Buttons: **Sign Out Anyway** (destructive) and **Cancel** (default).
4. **Sign Out Anyway** discards every remaining timer, including one saved by an enable that finished while the alert was open, removes the key, and signs out. A later sign-in doesn't disable those aliases. *(Claude's call.)*
5. An enable, creation, or "Disable After" that finishes after the sign-out doesn't save a timer. If the alias was meant to expire, Ajour disables it again with the key it was enabled with, like an alias created for a previous account today. *(Claude's call. Otherwise an alias the person never saw in the alert would stay enabled.)*
6. **Cancel** leaves everything as it was. The timers keep running, failed ones keep retrying.

## Constraints

- Swift 6 strict concurrency, macOS 26, XcodeGen; tests with Swift Testing. SimpleLoginKit keeps its own tests.
- All copy in English, exactly as written in this document (straight apostrophes, as in the app's other messages, and the ellipsis character `…`).
- The API key is never logged or shown, also not in error reasons.
- The Stuck symbol is drawn like the other state symbols (`StateSymbol`), follows light, dark and Increase Contrast, and turns white in a highlighted menu row.

## Left to the builder

- Type and API shapes: how the retry policy is expressed per request, how a failure carries its reason to the notification, the menu and sign-out, and how the timer record stores "reported".
- Whether retry waits use `Task.sleep` or an injected clock, as long as tests run without real waiting.
- Exact placement of the Stuck symbol's exclamation mark, within the ring's 14 pt.
- Test coverage for each rule above, especially: no double toggle, no double create, the 403 notification surviving a relaunch exactly once, and sign-out with a late enable.
