# Calendar — XTOS Licorice mini app (API 2.9)

Your Google Calendar (or any calendar with an iCal address), read-only, in **Day**, **Week**,
**Month** and **Agenda** views, and on the **lock screen**. A port of
[calendar.koplugin](https://github.com/omer-faruq/calendar.koplugin) for KOReader, laid out for
the X4 Pro's 480x800 screen. Needs Wi-Fi to sync; works offline afterwards.

## Adding a calendar

Google Calendar can't be reached with a login on the reader, but every calendar has a private
**secret address in iCal format**: in Google Calendar on the web, Settings → your calendar under
*Settings for my calendars* → *Integrate calendar* → **Secret address in iCal format** (it ends
in `/basic.ics`). Each calendar has its own address. Other services (Outlook, iCloud, Nextcloud)
offer a similar "publish" or "subscribe" address; `webcal://` works too.

- **On the reader**: More → **Add**, type the address, then a name.
- **Over USB** (easier for long addresses): put a `calendars.txt` into `XTApps/calendar/files/`
  on the SD card, one calendar a line:

  ```
  Personal|https://calendar.google.com/calendar/ical/.../basic.ics|on
  Work|https://calendar.google.com/calendar/ical/.../basic.ics|off
  ```

  A line with just the address also works (the host becomes its name). `off` hides it.

The address is a password to your calendar: don't share `calendars.txt`.

## Using it

- **Day / Week / Month / Agenda** tabs at the top; the last one used is remembered.
- **<** and **>**, a swipe, or the side buttons go to the previous or next day, week, month or
  agenda page; **Today** comes back.
- Tap a day in Week or Month to see it as a Day (Back returns); tap an event in Day or Agenda for
  its time, place, calendar and notes.
- Day shows all-day events on top and a timeline (7:00 to 21:00, wider when events need it), with
  overlapping events side by side and a line at the current time.
- **Sync** fetches every shown calendar now. Otherwise the app fetches a calendar when it is older
  than the sync interval (Settings, 1 to 24 h; 6 by default).

## Settings (More)

- Each calendar with its event count, size and last sync (or the error). Tap it to **Hide** /
  **Show**, **Rename** or **Delete** it (only from this list).
- **Week starts on** Monday or Sunday; **Sync when older than** 1, 3, 6, 12 or 24 h.
- **Lock screen**: Off, Agenda, Day, Week or Month (the firmware asks once; only one app can be
  the lock screen at a time). It shows today's date and that view. **Day** starts at the current
  hour and shows as many hours as fit, past midnight into the next day; the day's events that
  don't fit are listed on one line at the bottom ("+2 later today: 21:00 Gym, …"). The lock
  screen is redrawn every 15 minutes, and fetches the calendars again (at most once an hour) when
  they are older than the sync interval, if the reader lets it use Wi-Fi.

## Good to know

- Only events from two months back to about 13 months ahead are kept, plus every repeating
  event that hasn't ended, with titles, places and notes shortened, so the cache stays small.
  The **whole** iCal file still has to fit into the app's memory while it is read. A calendar
  with many years of history can be several megabytes and then fails to sync (the error says
  so); a separate calendar for what you want on the reader helps.
- Times in UTC are moved to the reader's time zone (from its clock). Times given with a time
  zone are shown as written, which is right when the calendar is in your own time zone.
- Repeats: daily, weekly (on given weekdays), monthly (on a day, "the last Friday", "the 2nd
  Tuesday"), yearly, with intervals, counts, end dates, skipped days and single changed or
  cancelled occurrences. Rarer rules show only their first occurrence.
- An event in two calendars (an invitation) shows once.

Files: `src/cal.lua` (dates, the iCal reader, repeats, the cache), `src/views.lua` (the four views,
shared with the lock screen), `src/main.lua` (on `tools/gamekit`), `src/lock/lock.lua` (the lock
screen; `bundle.py` joins it with `cal.lua` and `views.lua` into `lockscreen.lua`),
`test_calendar.py` (`python -I apps/calendar/test_calendar.py`).

License: **GNU AGPL v3** (`LICENSE`), like calendar.koplugin it comes from.
