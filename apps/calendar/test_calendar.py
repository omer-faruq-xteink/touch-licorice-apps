"""Offline test of Calendar (gamekit harness with a stand-in network that serves iCal files): adding
calendars in Settings, the iCal reader (UTC and TZID times, all-day spans, DURATION, folded lines,
HTML notes, alarms, cancelled and old events dropped), recurrence (weekly BYDAY with EXDATE and a
moved instance, daily COUNT, monthly last Friday and day 1, yearly), one event shared by two
calendars shown once, the four views and paging, the event box, the cache after a restart,
errors, the lock screen (the firmware's question and lockscreen.lua drawing each view) and the
draw-command count.

  python -I apps/calendar/test_calendar.py
"""
import calendar as pycal, gzip, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game, STUBS  # noqa: E402
from lupa import lua54  # noqa: E402

OFF = 3 * 3600                                     # the reader is at UTC+3
NOW = pycal.timegm((2026, 10, 27, 9, 0, 0))        # 2026-10-27 12:00 local, a Tuesday

PERSONAL = '\r\n'.join([
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Google Inc//Google Calendar 70.9054//EN', 'X-WR-TIMEZONE:Europe/Istanbul',
    'BEGIN:VTIMEZONE', 'TZID:Europe/Istanbul', 'BEGIN:STANDARD', 'TZOFFSETFROM:+0300', 'TZOFFSETTO:+0300',
    'DTSTART:19700101T000000', 'END:STANDARD', 'END:VTIMEZONE',
    # weekly on Monday and Wednesday, Wednesday 28 Oct skipped, Monday 26 Oct moved to 14:00
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20260105T100000', 'DTEND;TZID=Europe/Istanbul:20260105T110000',
    'RRULE:FREQ=WEEKLY;BYDAY=MO,WE', 'EXDATE;TZID=Europe/Istanbul:20261028T100000', 'UID:team@x', 'SUMMARY:Team meeting', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261026T140000', 'DTEND;TZID=Europe/Istanbul:20261026T150000',
    'RECURRENCE-ID;TZID=Europe/Istanbul:20261026T100000', 'UID:team@x', 'SUMMARY:Team meeting (moved)', 'END:VEVENT',
    # UTC times, a folded HTML description, an alarm with its own SUMMARY
    'BEGIN:VEVENT', 'DTSTART:20261027T110000Z', 'DTEND:20261027T120000Z', 'UID:dentist@x', 'SUMMARY:Dentist',
    'LOCATION:Clinic\\, 2nd floor', 'DESCRIPTION:Bring the <b>card</b>.<br>Ask about the\\nfilling &amp; the',
    '  x-ray.', 'BEGIN:VALARM', 'ACTION:DISPLAY', 'SUMMARY:Alarm notification', 'TRIGGER:-P0DT0H30M0S', 'END:VALARM',
    'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261027T143000', 'DTEND;TZID=Europe/Istanbul:20261027T153000',
    'UID:lunch@x', 'SUMMARY:Late lunch', 'DESCRIPTION;ALTREP="cid:part1.0001@example.org":with Bora', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261027T160000', 'DURATION:PT30M', 'UID:call@x', 'SUMMARY:Call', 'END:VEVENT',
    # two days all day: 29 and 30 October
    'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261029', 'DTEND;VALUE=DATE:20261031', 'UID:hol@x', 'SUMMARY:Holiday', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:19901102', 'DTEND;VALUE=DATE:19901103', 'RRULE:FREQ=YEARLY', 'UID:bday@x',
    'SUMMARY:Birthday Ana', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20260130T190000', 'DTEND;TZID=Europe/Istanbul:20260130T210000',
    'RRULE:FREQ=MONTHLY;BYDAY=-1FR', 'UID:book@x', 'SUMMARY:Book club', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20250101', 'RRULE:FREQ=MONTHLY;BYMONTHDAY=1', 'UID:rent@x', 'SUMMARY:Pay rent', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261026T090000', 'DTEND;TZID=Europe/Istanbul:20261026T091500',
    'RRULE:FREQ=DAILY;COUNT=5', 'UID:standup@x', 'SUMMARY:Standup', 'END:VEVENT',
    # dropped: long past, cancelled, a series that ended
    'BEGIN:VEVENT', 'DTSTART:20250101T100000Z', 'DTEND:20250101T110000Z', 'UID:old@x', 'SUMMARY:Old thing', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART:20261028T100000Z', 'DTEND:20261028T110000Z', 'UID:cx@x', 'STATUS:CANCELLED', 'SUMMARY:Called off', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART:20240101T100000Z', 'DTEND:20240101T110000Z', 'RRULE:FREQ=WEEKLY;UNTIL=20250101T000000Z',
    'UID:gone@x', 'SUMMARY:Ended series', 'END:VEVENT',
    'END:VCALENDAR', ''])

WORK = '\r\n'.join([
    'BEGIN:VCALENDAR', 'VERSION:2.0',
    'BEGIN:VEVENT', 'DTSTART:20261027T110000Z', 'DTEND:20261027T120000Z', 'UID:dentist@x', 'SUMMARY:Dentist', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261030T110000', 'DTEND;TZID=Europe/Istanbul:20261030T120000',
    'UID:review@x', 'SUMMARY:Quarterly review', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261027T220000', 'DTEND;TZID=Europe/Istanbul:20261027T230000',
    'UID:show@x', 'SUMMARY:Late show', 'END:VEVENT',
    'BEGIN:VEVENT', 'DTSTART;TZID=Europe/Istanbul:20261028T010000', 'DTEND;TZID=Europe/Istanbul:20261028T020000',
    'UID:night@x', 'SUMMARY:Night train', 'END:VEVENT',
    'END:VCALENDAR', ''])

URL1 = 'https://calendar.google.com/calendar/ical/me%40gmail.com/private-abc/basic.ics'
URL2 = 'webcal://example.org/work.ics'
requests = []
sent = []                                          # (url, headers) of every request
net = {'gzip': False, 'cut': False}


def answer(url, headers=None):
    gz = (headers or {}).get('Accept-Encoding') == 'gzip'
    if url == URL1 and net['cut']:
        body = PERSONAL[:len(PERSONAL) * 6 // 10]              # the reader took in only part of it
        return {'status': 200, 'body': gzip.compress(body.encode())[:400] if gz and net['gzip'] else body}
    if url == URL1 and gz and net['gzip']:
        return {'status': 200, 'body': gzip.compress(PERSONAL.encode())}
    if url.startswith('https://w.example/api/ics?url='):
        if (headers or {}).get('Authorization') != 'Basic dTpw':
            return {'status': 401, 'body': '{"error":"unauthorized"}'}
        return {'status': 200, 'body': WORK}
    if url.startswith('https://old.example/api/ics'):
        return {'status': 404, 'body': '{"error":"not found"}'}
    if url == URL1:
        return {'status': 200, 'body': PERSONAL}
    if url == 'https://example.org/work.ics':
        return {'status': 200, 'body': WORK}
    if url.endswith('/login'):
        return {'status': 200, 'body': '<html>Sign in</html>'}
    return {'status': 404, 'body': 'Not Found'}


def setup(L):
    def request(self, opts, fn):
        requests.append(opts['url'])
        hd = dict(opts['headers'].items()) if opts['headers'] else {}
        sent.append((opts['url'], hd))
        L.globals().pending_resp = L.table_from(answer(opts['url'], hd))
        L.globals().pending_fn = fn
        return L.table_from({'cancel': lambda self: None})

    L.globals().ctx.net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
    L.execute(f"now_sec = {NOW}; ctx.clock.now = function(self) local w = now_sec + {OFF}; "
              "return { epoch_sec = now_sec, hour = w % 86400 // 3600, minute = w % 3600 // 60, second = w % 60 } end")
    L.execute("lock_calls = {}; ctx.lockscreen = { is_default = function(self) return lock_is end, "
              "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_is = true end, "
              "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_is = false end }")
    return L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r) end; return f ~= nil end')


g = Game(HERE)
answer_now = setup(g.L)
g.restart()                              # on_load again, now with the clock and network
ctx = g.L.globals().ctx
A = lambda: g.api
def typed(s): g.L.eval('inputs[#inputs]')(ctx, s)
def ticks():
    for _ in range(200):                           # the reading goes on a piece per tick
        g.L.eval('on_tick')(ctx)
def answer_all():
    while True:
        ticks()
        if not answer_now():
            break
    ticks()
def texts(): return g.texts()
def has(s): return any(s in t for t in texts())

# ---- the date arithmetic against Python's
C = A().C
for y, m, d in ((1970, 1, 1), (2000, 2, 29), (2026, 10, 27), (2037, 12, 31), (1969, 12, 31), (1900, 3, 1)):
    days = C.days(y, m, d)
    assert days == (pycal.timegm((y, m, d, 0, 0, 0)) // 86400), (y, m, d, days)
    assert tuple(C.civil(days)) == (y, m, d), C.civil(days)
    assert C.wday(days) == (pycal.weekday(y, m, d) + 1) % 7
f = g.L.eval('ctx.fonts.small')
cut = C.fit(f, 'Çalışma günü ğüşıöç toplantısı', 100)
assert cut.endswith('…') and len(cut.encode()) > 0 and '�' not in cut, cut
assert C.month_len(2028, 2) == 29 and C.month_len(2026, 2) == 28 and C.month_len(2026, 12) == 31
e, off = C.clock()
assert e == NOW and off == OFF, (e, off)

# ---- nothing yet: the empty screen explains where calendars come from
assert has('No calendars yet.'), texts()
g.tap_label('Sync')
assert A().status() == 'No calendars: add one in Settings.'

# ---- add two calendars in Settings (webcal:// becomes https://)
g.tap_label('More')
assert A().screen() == 'settings' and has('None yet: tap Add.')
g.tap_label('Add'); typed(URL1); typed('Personal')
answer_all()
g.tap_label('Add'); typed(URL2); typed('')
answer_all()
cals = list(A().cals().values())
assert [str(c.name) for c in cals] == ['Personal', 'example.org'], [str(c.name) for c in cals]
assert str(cals[1].url) == 'https://example.org/work.ics'
assert requests == [URL1, 'https://example.org/work.ics'], requests
sums = sorted(str(ev.sum) for ev in cals[0].events.values())
assert sums == ['Birthday Ana', 'Book club', 'Call', 'Dentist', 'Holiday', 'Late lunch', 'Pay rent', 'Standup',
                'Team meeting', 'Team meeting (moved)'], sums
dentist = [ev for ev in cals[0].events.values() if ev.sum == 'Dentist'][0]
assert dentist.loc == 'Clinic, 2nd floor', dentist.loc
assert dentist.desc == 'Bring the card.\nAsk about the\nfilling & the x-ray.', repr(dentist.desc)
assert C.hm(dentist.s) == '14:00' and C.hm(dentist.e) == '15:00'
lunch = [ev for ev in cals[0].events.values() if ev.sum == 'Late lunch'][0]
assert lunch.desc == 'with Bora', lunch.desc
call = [ev for ev in cals[0].events.values() if ev.sum == 'Call'][0]
assert call.e - call.s == 1800
store = g.store
assert 'calendars.txt' in store and 'Personal|' + URL1 + '|on' in store['calendars.txt']
assert any(str(k).startswith('c') and str(k).endswith('.txt') and k != 'calendars.txt' for k in store.keys())
t = texts()
assert any('Personal' in s for s in t) and any('10 events' in s for s in t), t
assert 'Clock: Tue 27 Oct 12:00, UTC+3' in t, t
g.tap_label('Back')

# ---- the week (Monday first): the moved meeting, the skipped Wednesday, standups, all-day days
assert A().mode() == 'week'
t = texts()
assert '26 - 1 Nov 2026' not in t
assert any(s.startswith('26 Oct - 1 Nov') for s in t), t
assert '14:00 Team meeting (moved)' in t and '10:00 Team meeting' not in t, t
assert sum(s == '09:00 Standup' for s in t) == 5, t      # COUNT=5 from Monday
assert t.count('Holiday') == 2 and '19:00 Book club' not in t   # Friday is full: Holiday, Standup, review, book club
assert '01:00 Night train' in t
assert any(s.startswith('+') and 'more' in s for s in t), t
assert 'Pay rent' in t, t                                 # Sunday 1 Nov
assert g.commands() < 900, g.commands()

# ---- Day: today's timeline, the shared Dentist once, Late lunch beside it
g.tap_label('Day')
assert A().mode() == 'day' and has('Tuesday 27 October 2026')
t = texts()
assert t.count('14:00 Dentist') == 1, t                  # one hour is one line at this height
assert '14:30 Late lunch' in t and '16:00 Call' in t and '22:00 Late show' in t and '07' in t and '22' in t, t
hits = [h for h in A().hits().values() if h.it]
boxes = {str(h.it.sum): h for h in hits}
assert boxes['Dentist'].x != boxes['Late lunch'].x and boxes['Dentist'].w < 300, (boxes['Dentist'].x, boxes['Late lunch'].x)
assert g.commands() < 900
# the event box: place, notes; the alarm's SUMMARY is not the title
h = boxes['Dentist']
g.tap(h.x + 5, h.y + 5)
t = texts()
assert 'Dentist' in t and any('At Clinic, 2nd floor' in s for s in t) and any('Bring the card.' in s for s in t), t
assert any('Tue 27 Oct, 14:00 - 15:00' in s for s in t) and any('Calendar: Personal' in s for s in t), t
assert not any('Alarm' in s for s in t)
g.key('back')
assert not has('Close')
g.tap_label('>')
assert has('Wednesday 28 October 2026') and not has('Team meeting') and has('Standup')
g.key('left')
assert has('Tuesday 27 October 2026')

# ---- Month: November from a swipe, the birthday, the last Friday, a tap opens the day
g.tap_label('Month')
assert has('October 2026')
assert g.commands() < 900, g.commands()
g.L.eval("function() on_input(ctx, {type='pointer', phase='up', gesture='swipe_left', x=300, y=400}) end")()
assert has('November 2026') and has('Birthday ~') or has('Birthday…') or has('Birth…'), texts()
cell = [h for h in A().hits().values() if h.day == C.days(2026, 11, 27)][0]
g.tap(cell.x + 10, cell.y + 40)
assert A().mode() == 'day' and has('Friday 27 November 2026') and has('Book club'), texts()
g.key('back')
assert A().mode() == 'month' and has('November 2026')
g.tap_label('Today')
assert has('October 2026')

# ---- Agenda: days with events, paging forward and back
g.tap_label('Agenda')
t = texts()
assert any(s.startswith('Today, Tuesday 27 October') for s in t) and any(s.startswith('Tomorrow, Wednesday 28') for s in t), t
assert 'Dentist' in t and 'Clinic, 2nd floor' in t
page1 = t
g.tap_label('>')
assert texts() != page1 and A().ag.page == 2
g.tap_label('<')
assert texts() == page1
assert g.commands() < 900

# ---- restart: the views come from the cache, no new requests while fresh
n = len(requests)
g.restart()
assert A().mode() == 'agenda' and has('Dentist')
assert len(requests) == n, requests[n:]
# later than the sync interval: asked again on opening
g.L.execute(f'now_sec = {NOW + 7 * 3600}')
g.restart()
answer_all()
assert len(requests) == n + 2, requests[n:]
g.L.execute(f'now_sec = {NOW}')

# ---- errors: a wrong address, a page that is not iCal
g.tap_label('More')
g.tap_label('Add'); typed('https://calendar.google.com/x/login'); typed('Bad')
answer_all()
assert has('error: not an iCal address'), texts()
g.tap_label('Add'); typed('https://nowhere.example/cal.ics'); typed('Gone')
answer_all()
assert has('error: HTTP 404'), texts()
# delete both through their boxes
for name in ('Gone', 'Bad'):
    y = [s for s in g.draw() if str(s.s) == name][0].y
    g.tap(40, int(y) + 5)
    g.tap_label('Delete'); g.tap_label('Delete')
assert [str(c.name) for c in A().cals().values()] == ['Personal', 'example.org']
# hiding one calendar hides its events
y = [s for s in g.draw() if str(s.s) == 'example.org'][0].y
g.tap(40, int(y) + 5); g.tap_label('Hide')
assert has('example.org  (hidden)')
def friday():
    g.tap_label('Week'); g.draw()
    row = [h for h in A().hits().values() if h.day == C.days(2026, 10, 30)][0]
    g.tap(row.x + 100, row.y + 10)
    assert has('Friday 30 October 2026'), texts()
g.tap_label('Back'); friday()
assert not has('11:00 Quarterly review') and has('19:00 - 21:00') and has('Book club'), texts()
g.tap_label('More')
y = [s for s in g.draw() if str(s.s).startswith('example.org')][0].y
g.tap(40, int(y) + 5); g.tap_label('Show'); g.tap_label('Back'); friday()
assert has('11:00 Quarterly review'), texts()

# ---- the lock screen: Off -> Agenda asks the firmware once, -> Off clears it
g.tap_label('More')
g.tap_label('Lock screen: off')
assert list(g.L.eval('lock_calls').values()) == ['set'] and A().cfg.lock == 'agenda'
assert 'lock=agenda' in store['settings.txt']
g.tap_label('Week starts on: Monday')
assert A().cfg.ws == 0
g.tap_label('Week starts on: Sunday')


def lock_texts(lock, extra=''):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    for k, v in store.items():
        L.globals().store[k] = v
    L.globals().store['settings.txt'] = store['settings.txt'].replace('lock=agenda', 'lock=' + lock)
    setup(L)
    L.execute(extra)
    L.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
    L.execute('drawn, commands = {}, 0; on_draw(ctx, gg)')
    return [str(d.s) for d in L.globals().drawn.values()], int(L.globals().commands), L


for lock in ('agenda', 'day', 'week', 'month'):
    t, n, _L = lock_texts(lock)
    assert 'Tuesday' in t and '27 October 2026' in t, (lock, t)
    assert not any('lock error' in s for s in t), (lock, t)
    assert n < 900, (lock, n)
    if lock == 'agenda':
        assert 'Dentist' in t and any(s.startswith('Today, Tuesday') for s in t), t
        assert any(s.startswith('synced') for s in t), t
    if lock == 'day':
        # from 12:00 on, past midnight: tomorrow's 01:00 train shows under a date line
        assert '14:00 Dentist' in t and '14:30 Late lunch' in t and '22:00 Late show' in t, t
        assert '12' in t and '11' not in t and 'Wed 28 Oct' in t and '01:00 Night train' in t, t
        assert not any('later today' in s for s in t), t
        assert 'Earlier: 09:00 Standup' in t, t          # over already, but still there
    if lock == 'week':
        assert '14:00 Team meeting (moved)' in t, t
# at 08:00 the hours end before the evening: the rest of the day is one line at the bottom
t, n, _L = lock_texts('day', f'now_sec = {NOW - 4 * 3600}')
assert '08' in t and '07' not in t and '14:00 Dentist' in t, t
assert any(s.startswith('+1 later today: 22:00 Late show') for s in t), t
assert '22:00 Late show' not in t and not any('Night train' in s for s in t), t
assert not any(s.startswith('Earlier') for s in t), t
# an old cache: the lock screen fetches again (once) and draws the new data
t, n, L = lock_texts('agenda', f'now_sec = {NOW + 15 * 3600}')   # the caches are from NOW + 7 h
fetch = L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r) end; return f ~= nil end')
assert fetch() and fetch() and not fetch()
assert any(s.startswith('synced 8 h ago') for s in t), t
L.execute('drawn = {}; on_draw(ctx, gg)')
t2 = [str(d.s) for d in L.globals().drawn.values()]
assert any(s.startswith('synced 0 min ago') for s in t2) or any(s == 'synced 0 min ago' for s in t2), t2
assert not fetch()                       # not again within the hour

g.tap_label('Lock screen: Agenda')
g.tap_label('Lock screen: Day'); g.tap_label('Lock screen: Week'); g.tap_label('Lock screen: Month')
assert list(g.L.eval('lock_calls').values()) == ['set', 'clear'] and A().cfg.lock == 'off'

# ---- calendars.txt copied over USB: bare addresses and "off"
g.store['calendars.txt'] = '# mine\n' + URL1 + '\nWork|https://example.org/work.ics|off\n'
g.restart(); setup(g.L)
cs = list(A().cals().values())
assert [(str(c.name), bool(c.on)) for c in cs] == [('calendar.google.com', True), ('Work', False)]
g.no_err()

# ---- packed answers: gzip asked for and unpacked with the firmware's zlib
g.L.globals().py_unzip = lambda hx: gzip.decompress(bytes.fromhex(hx)).decode()   # lupa can't hand binary to Python
unzip = g.L.eval("function(self, b, ...) if select('#', ...) > 0 then error('one argument') end "
                 "return py_unzip((b:gsub('.', function(ch) return string.format('%02x', ch:byte()) end))) end")
ctx.base64 = g.L.table_from({'encode': lambda self, s: __import__('base64').b64encode(s.encode() if isinstance(s, str) else s).decode()})
store['calendars.txt'] = 'Personal|' + URL1 + '|on\n'
g.restart()
net['gzip'] = True
ctx.zlib = g.L.table_from({'decompress': unzip})
del sent[:]
g.tap_label('Sync'); answer_all()
assert sent[0][1].get('Accept-Encoding') == 'gzip', sent
c = list(A().cals().values())[0]
assert c.err is None and len(list(c.events.values())) == 10 and c.packed > 0, (c.err, c.packed)
assert store['sync_step.txt'] == 'done' and 'gz=ok' in store['settings.txt']
# the reader closed the app while unpacking: the next start says so, syncs nothing, drops gzip
store['sync_step.txt'] = 'unpack 1, 47 KB packed'
n = len(requests)
g.L.execute(f'now_sec = {NOW + 9 * 3600}')            # stale: would sync at once otherwise
g.restart()
assert len(requests) == n and A().cfg.plain and store['sync_step.txt'] == 'done', requests[n:]
assert A().status() == 'The last sync stopped at: unpack 1, 47 KB packed. Now without gzip.', A().status()
assert has('The last sync stopped at: unpack 1, 47 KB packed. Now withou~') or any('last sync stopped' in t for t in texts())
store['settings.txt'] = store['settings.txt'].replace('plain=1', 'plain=0')
g.L.execute(f'now_sec = {NOW}')
g.restart()
ctx.zlib = g.L.table_from({'decompress': unzip})
g.tap_label('More')
assert any('KB gzip)' in t for t in texts()), texts()
g.tap_label('Back')
# a reader whose zlib can't unpack it: asked once more as it is, and from then on
ctx.zlib = g.L.table_from({'decompress': lambda self, b, *m: None})
del sent[:]
g.tap_label('Sync'); answer_all()
assert [h.get('Accept-Encoding') for u, h in sent] == ['gzip', None], sent
assert A().cfg.plain and 'plain=1' in store['settings.txt'] and c.err is None
del sent[:]
g.tap_label('Sync'); answer_all()
assert [h.get('Accept-Encoding') for u, h in sent] == [None], sent

# ---- cut off: never used; the last whole copy stays, the reason is shown
before = store[A().C.cache_name(URL1)]
net['cut'] = True
g.L.execute(f'now_sec = {NOW + 60}')
g.tap_label('Sync'); answer_all()
c = list(A().cals().values())[0]
assert str(c.err).startswith('cut off after ') and c.err.endswith('KB: try the Worker (Settings)'), c.err
assert store[A().C.cache_name(URL1)] == before and len(list(c.events.values())) == 10
assert any(t.startswith('Personal: cut off after') for t in texts()), texts()
# the lock screen doesn't take a cut-off copy either
t, n, L = lock_texts('agenda', f'now_sec = {NOW + 15 * 3600}')
fetch = L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r) end; return f ~= nil end')
assert fetch() and store[A().C.cache_name(URL1)] == before
assert L.globals().store[A().C.cache_name(URL1)] == before

# a packed answer cut off: reported as cut, gzip stays on
g.store['settings.txt'] = store['settings.txt'].replace('plain=1', 'plain=0')
g.restart()
ctx.zlib = g.L.table_from({'decompress': unzip})
net['gzip'] = True
del sent[:]
g.tap_label('Sync'); answer_all()
c = list(A().cals().values())[0]
assert str(c.err).startswith('cut off after 0 KB packed') and not A().cfg.plain and len(sent) == 1, (c.err, sent)
assert store[A().C.cache_name(URL1)] == before
net['cut'] = False

# ---- a big calendar is read a piece per tick (the host stops a long callback), or per draw
filler = ''.join('\r\n'.join(['BEGIN:VEVENT', 'DTSTART:20200101T100000Z', 'DTEND:20200101T110000Z', 'UID:f%d' % k,
                              'SUMMARY:Old %d' % k, 'DESCRIPTION:' + 'x' * 300, 'END:VEVENT', '']) for k in range(500))
big = PERSONAL.replace('END:VCALENDAR', filler + 'END:VCALENDAR')
assert len(big) > 200000
net['cut'] = False
saved_personal = PERSONAL
PERSONAL = big
store['settings.txt'] = store['settings.txt'].replace('plain=0', 'plain=1')
g.restart()
g.L.execute(f'now_sec = {NOW + 9 * 3600}')
g.tap_label('Sync')
assert answer_now()
steps = 0
seen = []
while any(t.startswith('Reading Personal') for t in texts()):
    seen += [t for t in texts() if t.startswith('Reading Personal')]
    g.L.eval('on_tick')(ctx)
    steps += 1
    assert steps < 100
assert steps >= 12 and seen[0].endswith(' 0%') or seen[0].endswith('%'), (steps, seen[:3])
c = list(A().cals().values())[0]
assert c.err is None and len(list(c.events.values())) == 10 and c.bytes > 200000, (c.err, c.bytes)
# no ticks at all: each draw reads a piece
g.L.execute(f'now_sec = {NOW + 18 * 3600}')
g.tap_label('Sync')
assert answer_now()
for _ in range(100):
    if not any(t.startswith('Reading') for t in texts()):
        break
c = list(A().cals().values())[0]
assert c.err is None and c.updated == NOW + 18 * 3600 and store['sync_step.txt'] == 'done', (c.err, c.updated)
PERSONAL = saved_personal
g.L.execute(f'now_sec = {NOW}')

# ---- the Worker: host and login in Settings, /api/ics with Basic auth
g.tap_label('More')
g.tap_label('Worker: off (straight to the calendar)')
typed('https://w.example/'); typed('u:p')
answer_all()
assert A().cfg.host == 'w.example' and 'host=w.example' in store['settings.txt'] and 'auth=u:p' in store['settings.txt']
u, h = sent[-1]
assert u == 'https://w.example/api/ics?url=' + __import__('urllib.parse').parse.quote(URL1, safe='-._~') and h['Authorization'] == 'Basic dTpw', sent[-1]
c = list(A().cals().values())[0]
assert c.err is None and [str(e.sum) for e in c.events.values()] == ['Dentist', 'Quarterly review', 'Late show', 'Night train'], c.err
assert has('Worker: w.example')
g.tap_label('Worker: w.example'); typed('old.example'); typed('')
answer_all()
assert list(A().cals().values())[0].err == 'the Worker has no /api/ics yet: update it'
g.tap_label('Worker: old.example'); typed('')
assert A().cfg.host == '' and A().cfg.auth == '' and has('Worker: off (straight to the calendar)')
g.no_err()
print('calendar: all tests passed')
