# Calendar — XTOS Licorice mini app (API 2.9)

Your Google Calendar (or any calendar with an iCal address), read-only, and **My calendar** for
events you add on the reader, in **Day**, **Week**, **Month** and **Agenda** views, and on the
**lock screen**. A port of
[calendar.koplugin](https://github.com/omer-faruq/calendar.koplugin) for KOReader, laid out for
the X4 Pro's 480x800 screen. Needs Wi-Fi to sync; works offline afterwards. Without any
calendar added it is still a calendar: the four views show from the start, and + adds events
to My calendar.

## Adding a calendar

Google Calendar can't be reached with a login on the reader, but every calendar has a private
**secret address in iCal format**: in Google Calendar on the web, Settings → your calendar under
*Settings for my calendars* → *Integrate calendar* → **Secret address in iCal format** (it ends
in `/basic.ics`). Each calendar has its own address. Other services (Outlook, Nextcloud) offer a
similar "publish" or "subscribe" address; `webcal://` works too, and an address that moves
elsewhere is followed. **Apple (iCloud)** gives no address for a private calendar: in Calendar on
the iPhone or Mac, share the calendar as a **Public Calendar** and use the link it shows
(`webcal://pNN-caldav.icloud.com/published/2/…`); anyone with that link can see the calendar.

- **On the reader**: More → **Add**, type the address, then a name.
- **Over USB** (easier for long addresses): put a `calendars.txt` into `XTApps/calendar/files/`
  on the SD card, one calendar a line:

  ```
  Personal|https://calendar.google.com/calendar/ical/.../basic.ics|on
  Work|https://calendar.google.com/calendar/ical/.../basic.ics|off
  ```

  A line with just the address also works (the host becomes its name). `off` hides it.

Google's public holiday calendars work the same way, for example Turkey's:

```
Holidays|https://calendar.google.com/calendar/ical/tr.turkish%23holiday%40group.v.calendar.google.com/public/basic.ics|on
```

(other countries: `en.usa`, `en.uk`, `de.german`, … in place of `tr.turkish`). Apple has its own:

```
Tatiller|https://calendars.icloud.com/holidays/tr_tr.ics|on
```

(`us_en`, `gb_en`, `de_de`, … in place of `tr_tr`).

The secret address of your own calendar is a password to it: don't share `calendars.txt`.

## My calendar: events added on the reader

**+** (right of the date) adds an event to **My calendar**, which lives on the reader: no account,
no Wi-Fi. A form asks for the title, the date (< and >, or tap it to type 2026-11-05 or
05.11.2026), the start (half-hour steps, or type 9:30; empty means all day), the length, whether it
repeats (every day, week, month or year), a place and notes. Tap one of its events for **Edit** and
**Delete** (a repeating one: this one, or all of them).

Its events are an ordinary iCalendar file, `AppFiles/calendar/My calendar.ics` on the SD card,
written after every change: copy it to a computer or phone and import it into any calendar program.
The app reads the file again every time it starts, so you can also edit it elsewhere or put an
exported `.ics` there under that name (repeat rules, skipped days and notes are kept; alarms and
guests are not). Uninstalling the app leaves the file on the card. My calendar is shown with the
others, can be hidden or renamed in More, and is never synced.

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
- **Clock**: the date, time and UTC offset the app uses (from the reader's clock); if events
  sit at the wrong hours, check the reader's time zone.
- **Week starts on** Monday or Sunday; **Sync when older than** 1, 3, 6, 12 or 24 h.
- **Lock screen**: Off, Agenda, Day, Week or Month (the firmware asks once; only one app can be
  the lock screen at a time). It shows today's date and that view. **Day** starts at the current
  hour and shows as many hours as fit, past midnight into the next day; the day's events that
  are over are listed on one line above the hours ("Earlier: 09:00 Standup"), those that don't
  fit on one line at the bottom ("+2 later today: 21:00 Gym, …"). The lock
  screen is redrawn every 15 minutes, and fetches the calendars again (at most once an hour) when
  they are older than the sync interval, if the reader lets it use Wi-Fi.

## Good to know

- Only events from two months back to about 13 months ahead are kept, plus every repeating
  event that hasn't ended, with titles, places and notes shortened, so the cache stays small.
- Google's iCal file holds the calendar's whole history, in a different order on every
  download, and the reader takes in only 128 KB of an answer. The app asks for it packed
  (gzip, about a quarter of the size; Settings shows both sizes), unpacks it and reads it a
  piece at a time ("Reading … %"). A file that still arrives **cut off is never used** — it
  would miss events at random — the last whole copy stays and the calendar says "cut off
  after N KB". A separate calendar for what you want on the reader helps then.
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
