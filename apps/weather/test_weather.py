"""Offline test of Weather (gamekit harness with a stand-in network that answers like Open-Meteo's
forecast and geocoding APIs, and ctx.json): choosing a place, the forecast drawn and kept in
forecast.txt, °C/°F, a stale forecast fetched again on opening, errors shown, the lock screen
(the firmware's question, lockscreen.lua drawing the cache and asking again when it is old), and
the draw-command count.

  python -I apps/weather/test_weather.py
"""
import json, os, re, sys, time, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game, STUBS  # noqa: E402
from lupa import lua54  # noqa: E402

NOW = 1761566400          # 2025-10-27 12:00 UTC, a Monday
requests = []
mode = {'fail': False}


def forecast(q):
    f = q.get('temperature_unit') == 'fahrenheit'
    t = (lambda c: c * 9 / 5 + 32) if f else (lambda c: c)
    hours = [f'2025-10-27T{h:02d}:00' for h in range(24)] + [f'2025-10-28T{h:02d}:00' for h in range(24)]
    return {
        'current': {'time': '2025-10-27T12:15', 'temperature_2m': t(17.6), 'apparent_temperature': t(16.2),
                    'relative_humidity_2m': 71, 'weather_code': 61, 'wind_speed_10m': 14.4},
        'hourly': {'time': hours, 'temperature_2m': [t(10 + k % 9) for k in range(48)],
                   'precipitation_probability': [k * 2 for k in range(48)], 'weather_code': [k % 4 for k in range(48)]},
        'daily': {'time': ['2025-10-27', '2025-10-28', '2025-10-29', '2025-10-30'], 'weather_code': [61, 3, 0, 95],
                  'temperature_2m_min': [t(11.2), t(9.6), t(8), t(12)], 'temperature_2m_max': [t(18.4), t(15), t(16.5), t(19)],
                  'precipitation_probability_max': [80, 20, 0, 65]},
    }


def answer(url):
    u = urllib.parse.urlsplit(url)
    q = dict(urllib.parse.parse_qsl(u.query))
    if mode['fail']:
        return {'status': 503, 'body': 'busy'}
    if u.netloc.startswith('geocoding'):
        if q['name'] == 'Nowhere':
            return {'status': 200, 'body': json.dumps({'generationtime_ms': 0.5})}
        return {'status': 200, 'body': json.dumps({'results': [
            {'name': 'İzmir', 'latitude': 38.41, 'longitude': 27.13, 'country': 'Türkiye', 'admin1': 'İzmir'},
            {'name': 'Izmir', 'latitude': 40.1, 'longitude': 30.2, 'country': 'Türkiye'}]}, ensure_ascii=False)}
    return {'status': 200, 'body': json.dumps(forecast(q))}


def setup(L):
    def to_lua(v):
        if isinstance(v, dict):
            return L.table_from({k: to_lua(x) for k, x in v.items()})
        if isinstance(v, list):
            return L.table_from([to_lua(x) for x in v])
        return v

    def request(self, opts, fn):
        requests.append(opts['url'])
        L.globals().pending_resp = to_lua(answer(opts['url']))
        L.globals().pending_fn = fn
        return L.table_from({'cancel': lambda self: None})

    L.globals().ctx.net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
    L.globals().ctx.json = L.table_from({'decode': lambda self, s: to_lua(json.loads(s))})
    L.execute(f"now_sec = {NOW}; ctx.clock.now = function(self) local d = os.date('!*t', now_sec); return {{ epoch_sec = now_sec, valid = true, year = d.year, month = d.month, day = d.day, hour = d.hour, minute = d.min, second = d.sec }} end")
    L.execute("lock_calls = {}; ctx.lockscreen = { is_default = function(self) return lock_is end, "
              "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_is = true end, "
              "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_is = false end }")
    return L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r) end end')


g = Game(HERE)
answer_now = setup(g.L)
ctx = g.L.globals().ctx
A = lambda: g.api
def typed(s): g.L.eval('inputs[#inputs]')(ctx, s)
def later(s): g.L.execute(f'now_sec = now_sec + {s}')


# nothing chosen yet
t = g.texts()
assert 'Tap Place to choose where.' in t and requests == [], t
g.tap_label('Refresh')
assert 'Choose a place first.' in g.texts()

# a place: search, the list, a choice; the forecast follows
g.tap_label('Place'); typed('İzmir')
assert 'name=%C4%B0zmir' in requests[-1] and 'Looking for İzmir...' in g.texts()
answer_now()
assert str(A().screen()) == "places", (A().screen(), g.texts())
t = g.texts()
assert 'İzmir' in t and 'İzmir, Türkiye' in t and 'Türkiye' in t, t
g.tap(100, 90 + 20)
assert 'latitude=38.41' in requests[-1] and 'longitude=27.13' in requests[-1] and 'fahrenheit' not in requests[-1]
assert 'Getting the forecast...' in g.texts()
answer_now()
assert 'name=İzmir\nlat=38.41\nlon=27.13\nunit=C\nlock=false\nevery=60' == g.store['settings.txt']
f = g.store['forecast.txt']
assert 'now_t=18' in f and 'h0=12:00;' in f and 'd1=2025-10-28;3;10;15;20' in f, f
t = g.texts()
for s in ['İzmir', 'updated 12:00', '°C', 'Rain', 'feels 16°   humidity 71%   wind 14 km/h', 'Today', 'Tue', 'Wed', 'Thu',
          '11° / 18°', 'rain 80%', '12:00', '14:00', '22:00']:
    assert s in t, (s, t)
assert len([r for r in g.rects() if r.fill]) == 9            # the big digits: 1 and 8

# °F asks again in Fahrenheit
g.tap_label('°F')
assert 'temperature_unit=fahrenheit' in requests[-1]
answer_now()
assert 'unit=F' in g.store['settings.txt'] and 'now_t=64' in g.store['forecast.txt'] and '°F' in g.texts()
g.tap_label('°C'); answer_now()

# kept: opens at once; asks again only when old
n = len(requests)
g.restart()
assert len(requests) == n and 'İzmir' in g.texts()
later(31 * 60)
assert '  (old)' in ''.join(g.texts())
g.restart()
assert len(requests) == n + 1
answer_now()

# errors are shown, the old forecast kept
mode['fail'] = True
g.tap_label('Refresh'); answer_now()
assert 'Forecast failed: HTTP 503' in g.texts() and 'İzmir' in g.texts()
mode['fail'] = False
g.tap_label('Place'); typed('Nowhere'); answer_now()
assert 'No place by that name.' in g.texts()
g.tap_label('Back')
assert str(A().screen()) == 'main'

# the lock screen
# the lock screen: Lock asks how often it fetches a new forecast while locked
g.tap_label('Lock')
t = g.texts()
for s in ['Every 15 min', 'Every 30 min', 'Every hour', 'Every 3 hours', 'Every 6 hours', 'Never']:
    assert s in t, (s, t)
assert 'Lock screen off' not in t and list(g.L.eval('lock_calls').values()) == []
g.tap_label('Every 3 hours')
assert list(g.L.eval('lock_calls').values()) == ['set'] and 'lock=true\nevery=180' in g.store['settings.txt']
assert 'Lock 3 h' in g.texts() and 'Every hour' not in g.texts()
g.tap_label('Lock 3 h')
assert 'Lock screen off' in g.texts()
g.key('back')                                               # Back closes the list, nothing changes
assert 'Lock screen off' not in g.texts() and 'Lock 3 h' in g.texts()
g.tap_label('Lock 3 h'); g.tap_label('Never')
assert 'every=0' in g.store['settings.txt'] and 'Lock only' in g.texts()
assert list(g.L.eval('lock_calls').values()) == ['set']
g.tap_label('Lock only'); g.tap_label('Lock screen off')
assert list(g.L.eval('lock_calls').values()) == ['set', 'clear'] and 'lock=false' in g.store['settings.txt']
assert 'Lock' in g.texts()
g.tap_label('Lock'); g.tap_label('Every hour')
assert list(g.L.eval('lock_calls').values()) == ['set', 'clear', 'set'] and 'Lock 1 h' in g.texts()

# the lock screen fetches while locked (firmware 26111201, API 2.26: lockscreen "net": true gives the
# lock session ctx.net; ctx.lock:done() ends it). A timer wake holds its frame until the request is
# answered; the first session draws at once and again after the answer.
man = json.load(open(os.path.join(HERE, 'manifest.json'), encoding='utf-8'))
assert man['api'] == '2.26' and man['lockscreen'].get('net') is True and 'net' in man['permissions'], man
# 900: the shortest interval offered; the reader seems to allow the lock screen's network at most once
# per declared interval (timer wakes had none with 3600, Lock Probe's had it with 60)
assert man['lockscreen']['interval_sec'] == 900, man

L2 = lua54.LuaRuntime(unpack_returned_tuples=True)
L2.execute(STUBS)
answer2 = setup(L2)
for k in ('forecast.txt', 'settings.txt'):
    L2.globals().store[k] = g.store[k]
L2.execute(f"now_sec = {NOW + 31 * 60 + 10 * 60}")
L2.execute("done_calls, inval = 0, 0; ctx.invalidate = function() inval = inval + 1 end; "
           "ctx.lock = { reason = 'timer', net = true, done = function(self) done_calls = done_calls + 1 end, set_interval = function(self, s) wake = s; return s end }")
LOCK = open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read()
def session(reason='timer'):
    """a new lock session: the script loads afresh, then on_load"""
    L2.execute(f"ctx.lock.reason = '{reason}'; done_calls, inval = 0, 0")
    L2.execute(LOCK)
    L2.eval("function() on_load(ctx) end")()
draw2 = L2.eval("function() drawn, commands = {}, 0; on_draw(ctx, gg); local t = {} for _, d in ipairs(drawn) do t[#t + 1] = d.s end return t end")
done = lambda: int(L2.globals().done_calls)
def _upd(): return int(re.search(r'updated=(\d+)', L2.globals().store['forecast.txt']).group(1))
def age(): return int(L2.globals().now_sec) - _upd()
def stamp():
    """what the lock screen says about the forecast's time (the clock stub is UTC): the time it was
    fetched, 'yesterday' before it, or how many days ago"""
    upd, now = _upd(), int(L2.globals().now_sec)
    days = now // 86400 - upd // 86400
    hm = time.strftime('%H:%M', time.gmtime(upd))
    return 'updated ' + hm if days == 0 else ('updated yesterday ' + hm if days == 1 else f'updated {days} days ago')

# fresh: no request, the frame, then done
n = len(requests)
session()
assert len(requests) == n and done() == 0
t = list(draw2().values())
for s in ['İzmir', '°C', 'Rain', 'Today 11° / 18°   rain 80%', 'Tue', 'Wed', 'Thu', '10° / 15°']:
    assert s in t, (s, t)
assert int(L2.globals().commands) < 300, L2.globals().commands
assert stamp() in t and age() == 600, (stamp(), t)
assert done() == 1

# old, timer wake: asked in on_load, answered before the (held) frame, drawn fresh, then done
L2.execute("now_sec = now_sec + 2 * 3600")
session()
assert len(requests) == n + 1 and 'latitude=38.41' in requests[-1] and done() == 0
answer2()
assert 'updated=' + str(NOW + 31 * 60 + 10 * 60 + 2 * 3600) in L2.globals().store['forecast.txt']
assert int(L2.globals().inval) == 1
assert stamp() in list(draw2().values()) and age() == 0 and done() == 1

# old, first session: drawn at once with the old forecast (no done while asking), again when answered
L2.execute("now_sec = now_sec + 2 * 3600")
session('first')
assert len(requests) == n + 2
t = list(draw2().values())
assert stamp() in t and age() == 7200 and done() == 0, t
draw2()
assert len(requests) == n + 2 and done() == 0               # asked once, not on every draw
answer2()
assert stamp() in list(draw2().values()) and age() == 0 and done() == 1

# a failed answer: the old forecast stays, a frame, then done
L2.execute("now_sec = now_sec + 2 * 3600")
mode['fail'] = True
session()
answer2()
mode['fail'] = False
assert int(L2.globals().inval) == 1 and done() == 0
assert stamp() in list(draw2().values()) and age() == 7200 and done() == 1

# a reader whose lock screen has no network: no request, the age shown, no error
L2.execute("ctx.lock.net = false; saved_net = ctx.net; ctx.net = nil")
session()
assert len(requests) == n + 3
assert stamp() in list(draw2().values()) and age() == 7200 and done() == 1
# due but not fetched: try again a whole interval later, not at once (it woke every 30 s on the reader)
assert int(L2.globals().wake) == 3600, L2.globals().wake
assert 'lock.net false' in L2.globals().store['wakes.txt'].strip().split('\n')[-1], L2.globals().store['wakes.txt']
L2.execute("ctx.lock.net = true; ctx.net = saved_net")

# the interval chosen in the app: every 3 hours asks only once the forecast is 3 hours old; never, not at all
L2.globals().store['settings.txt'] = g.store['settings.txt'].replace('every=60', 'every=180')
session()
assert len(requests) == n + 3 and done() == 0
draw2()
assert done() == 1                                          # 2 h old: no request
L2.execute("now_sec = now_sec + 2 * 3600")
session()
assert len(requests) == n + 4
answer2()
assert stamp() in list(draw2().values()) and age() == 0 and done() == 1
# the next wake is the chosen interval itself, at most an hour (the reader aligns wakes to multiples of
# the interval, so a computed rest of it only brought early wakes); every session sets it, as the host
# goes back to the manifest's at each lock; a wake up to a minute early still fetches
wake = lambda: int(L2.globals().wake)
L2.globals().store['settings.txt'] = g.store['settings.txt']
L2.execute("now_sec = now_sec + 3600 - 30")                  # every hour, a wake 30 s early: fetched
session()
assert len(requests) == n + 5 and wake() == 3600
answer2(); draw2()
L2.execute("now_sec = now_sec + 20 * 60")                    # 20 min later (e.g. locked again): not yet
session()
assert len(requests) == n + 5 and wake() == 3600, wake()

# every 15 minutes
L2.globals().store['settings.txt'] = g.store['settings.txt'].replace('every=60', 'every=15')
L2.execute("now_sec = now_sec + 13 * 60")                    # fetched 33 min ago
session()
assert len(requests) == n + 6 and wake() == 900
answer2(); draw2()
L2.execute("now_sec = now_sec + 15 * 60 - 90")               # the next wake, 90 s early (seen: up to a minute): fetched
session()
assert len(requests) == n + 7 and wake() == 900
answer2(); draw2()
L2.execute("now_sec = now_sec + 10 * 60")                    # 10 min: not yet, due in 5
session()
assert len(requests) == n + 7 and wake() == 900

# a new day: every 6 hours wakes hourly (on the hour), so one comes just after midnight, and "Today"
# (yesterday by then) is fetched again
L2.globals().store['settings.txt'] = g.store['settings.txt'].replace('every=60', 'every=360')
L2.execute("now_sec = now_sec + 30 * 60")
session()
to_midnight = 86400 - int(L2.globals().now_sec) % 86400
assert len(requests) == n + 7 and 0 < to_midnight < 3600 and wake() == 3600, (wake(), to_midnight)
L2.execute(f"now_sec = now_sec + {to_midnight + 60}")
session()
assert len(requests) == n + 8, (len(requests), n)
answer2(); draw2()

L2.globals().store['settings.txt'] = g.store['settings.txt'].replace('every=60', 'every=0')
L2.execute("now_sec = now_sec + 5 * 3600")
session()
assert len(requests) == n + 8 and wake() == 3600
assert stamp() in list(draw2().values()) and age() >= 5 * 3600 and done() == 1
# every lock session leaves a line in wakes.txt (private storage, XTApps/weather/files/ over USB): the
# time, why it woke, the forecast's age, the interval, what it did, the next wake; and each answer
log = L2.globals().store['wakes.txt'].strip('\n').split('\n')
assert 0 < len(log) <= 20 and all(re.match(r'\d\d:\d\d ', l) for l in log), log
whole = '\n'.join(log)
for s in ['timer', 'first', 'fetch', 'not due', 'reply 200', 'reply HTTP 503', 'no network on the lock screen', 'never', 'next ']:
    assert s in whole, (s, whole)
for _k in range(25):
    session(); draw2()
log = L2.globals().store['wakes.txt'].strip('\n').split('\n')
assert len(log) == 20, len(log)                             # the last 20 only

# a timer wake that comes early and would end before the quarter it was woken for gets a second wake on
# it (Calendar: 14:59:37 then 15:00:01): it holds with ctx:after (it runs in a 2.26 lock session: Lock
# Probe 1.9) until 2 s past the quarter, and only then ends
L2.globals().store['settings.txt'] = g.store['settings.txt'].replace('every=60', 'every=15')
L2.execute("timers = {}; ctx.after = function(self, ms, fn) timers[#timers + 1] = { ms = ms, fn = fn }; return {} end; "
           "ctx.lock.interval_sec = 900; now_sec = (now_sec // 900 + 1) * 900 - 40")
session()
answer2(); draw2()
assert int(L2.eval('#timers')) == 1 and int(L2.eval('timers[1].ms')) == 42000 and done() == 0
L2.execute("now_sec = now_sec + 42; timers[1].fn(ctx)")
draw2()
assert done() == 1 and 'held' in L2.globals().store['wakes.txt'].strip().split('\n')[-2], L2.globals().store['wakes.txt']
L2.execute("timers = {}; now_sec = now_sec + 15 * 60")       # on time (2 s past the quarter): no hold
session(); answer2(); draw2()                                # due again: fetched, no hold
assert int(L2.eval('#timers')) == 0 and done() == 1

L3 = lua54.LuaRuntime(unpack_returned_tuples=True)          # nothing saved yet
L3.execute(STUBS)
L3.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
L3.eval("function() on_draw(ctx, gg) end")()
assert any('open the app once' in str(d.s) for d in L3.globals().drawn.values())

assert g.commands() < 500, g.commands()
g.no_err()
print('weather tests passed')
