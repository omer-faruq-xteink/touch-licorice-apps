# Tasks — XTOS Licorice mini app (API 2.9)

Lists of things to do, ticked off with a tap, and your Todoist, Google Tasks and TickTick lists.

- **Lists**: New list; tap one to open it. A long press on a list: Rename, Delete, Lock screen.
- **Items**: tap the box to tick it (ticked items are struck through), tap the text for Edit,
  Delete, Up and Down (a long press opens the same menu). Add types a new item with the
  firmware keyboard; **Clear done** removes the ticked items after asking.
- **Repeat** (in an item's menu): Every day, Every week, Every 2 weeks, Every month, or Other
  ("3 days", "2 weeks", "6 months"). A ticked repeating item keeps the day and comes back (un-ticked)
  when it is due again, counted from that day; months are calendar months (31 Jan + 1 month =
  28 or 29 Feb). Under it: "every 4 days, next Thu 5 Nov" while ticked, "due today" or
  "late 2 days" while open. **Clear done** leaves repeating items in place.
- **Prev** and **Next** (under the rows) turn the page when there are more lists or items than fit; swipes and the side buttons do too.
- **Lock screen**: any one list (List → Lock screen): the date and that list's open items in the
  large font. The firmware asks once to make the app the lock screen; it shows the list as it was
  when you last changed it, and a ticked repeating item appears on it again on the day it is due.
  Only one app can be the lock screen at a time (Notes, Anki, Weather).
- Everything is kept in one plain text file, `XTApps/tasks/files/lists.txt`, which you can also
  write or edit on a computer:

  ```
  # Shopping
  [ ] bread
  [x] milk

  # Home
  [x] Water plants {every 4 days, done 2026-11-01}
  [ ] Change the water filter {every 3 months, done 2026-08-10}
  ```

## Todoist, Google Tasks and TickTick

Optional: your lists from **Todoist**, **Google Tasks** and **TickTick** can show after your own (Sources on the
list of lists). On the reader you **tick, untick and add** items; renaming, deleting and dates stay
in their own apps. Changes wait while there is no Wi-Fi, and **Sync** fetches the lists again.

### How it works

Each Todoist or TickTick project and Google Tasks list shows as a list of its own, marked with its service. A
change is sent a moment after you make it (several go together); while there is no Wi-Fi it waits,
and is sent on the next sync. Opening the app syncs too. Sub-items are drawn further in, and an
item with a date shows "due today", "late 2 days" or its date (and Todoist's repeat, such as "every
4 days"; a ticked repeating Todoist task comes back with its next date). In Google Tasks the done
items come after the open ones, as in Google's app. Any of these lists can be the lock screen. The
app needs Wi-Fi only for these lists, and loads their code only once one is set up. Unticking a
Google task needs firmware 26110201 or later (API 2.18).

**Several accounts** of one service (personal and work) each get a file of their own,
`todoist-NAME.txt`, `google-NAME.txt` or `ticktick-NAME.txt`; NAME marks their lists ("Google (work)"). An account that
fails (a token no longer accepted) keeps its lists as they were and does not stop the others; the
list of lists says "1 account failed", and Sources shows what went wrong. Sources → Remove
forgets an account and its lists (nothing changes in the service).

### Setting up Todoist

Copy your API token (Todoist on the web: Settings → Integrations → Developer → API token). Type it
in Sources → Todoist token, or put it in a file `todoist.txt` in `AppFiles/tasks/` on the reader's
card (just the token, or `token = ...`); the app takes it in and deletes the file.

### Setting up Google Tasks

Google does not let a device without a browser sign in to Tasks (its device sign-in leaves the
Tasks permission out), so you sign in once on a computer and give the app a long-lived refresh
token:

1. In [Google Cloud](https://console.cloud.google.com/) create a project, and enable the **Google
   Tasks API** (APIs & Services → Library).
2. Set up the **OAuth consent screen** (External), add yourself as a test user, then **Publish
   app** (In production): tokens of an app left in Testing stop working after 7 days. Google's
   verification is not needed for your own use.
3. Credentials → Create credentials → **OAuth client ID**, type **Web application**, with the
   authorized redirect URI `https://developers.google.com/oauthplayground`. Keep its client ID and
   client secret.
4. In the [OAuth Playground](https://developers.google.com/oauthplayground), gear icon → **Use your
   own OAuth credentials** (paste them), then authorize the scope
   `https://www.googleapis.com/auth/tasks` and **Exchange authorization code for tokens**. Copy the
   **refresh token**.
5. Put a file `google.txt` in `AppFiles/tasks/`:

   ```
   client_id = 1234-abc.apps.googleusercontent.com
   client_secret = GOCSPX-...
   refresh_token = 1//0g...
   ```

The app takes the file into its own storage and deletes it from the card when it opens (or with
Sources → Read files). For a second account, use another name: `google-work.txt`.

### Setting up TickTick

TickTick's API needs an app of your own, made once on a computer:

1. Sign in at [developer.ticktick.com](https://developer.ticktick.com/) with your TickTick account,
   **Manage Apps** → **+ App Name**. Set its **OAuth redirect URL** to `http://localhost` and keep
   its **Client ID** and **Client Secret**.
2. Open this address in the computer's browser, with your Client ID in it, and allow access:

   ```
   https://ticktick.com/oauth/authorize?scope=tasks:read%20tasks:write&client_id=YOUR_CLIENT_ID&state=x&redirect_uri=http://localhost&response_type=code
   ```

   The browser then goes to `http://localhost/?code=...` (the page itself does not load): copy the
   **code** from the address bar.
3. Within a few minutes (a code does not last), either put a file `ticktick.txt` in
   `AppFiles/tasks/` and open Tasks, which trades the code for a token itself:

   ```
   client_id = ...
   client_secret = ...
   code = ...
   ```

   or trade it on the computer and put only the token in the file (`access_token = ...`):

   ```
   curl -u YOUR_CLIENT_ID:YOUR_CLIENT_SECRET -d "code=THE_CODE&grant_type=authorization_code&scope=tasks:read tasks:write&redirect_uri=http://localhost" https://ticktick.com/oauth/token
   ```

TickTick's token lasts months, not forever; when it runs out, Sources says the token was not
accepted, and steps 2 and 3 give a new one. TickTick's API has no "reopen": unticking an item sets
its status back, which TickTick may refuse; a ticked item leaves the list on the next sync, as in
Todoist. The Inbox comes first; dates come in UTC and are shown as your local day.

## Files

`src/main.lua` (on `tools/gamekit`), `lib/remote.lua` (Todoist, Google Tasks and TickTick, loaded
with `require` only when one is set up), `lockscreen.lua`, `bundle.py`, `test_tasks.py` and
`test_remote.py` (against fake Todoist, Google and TickTick servers): `python -I apps/tasks/test_tasks.py`.
