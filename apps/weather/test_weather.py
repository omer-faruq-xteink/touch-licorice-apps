"""Offline test of Weather (gamekit harness with a stand-in network that answers like Open-Meteo's
forecast and geocoding APIs, and ctx.json): choosing a place, the forecast drawn and kept in
forecast.txt, °C/°F, a stale forecast fetched again on opening, errors shown, the lock screen
(the firmware's question, lockscreen.lua drawing the cache and asking again when it is old), and
the draw-command count.

  python -I apps/weather/test_weather.py
"""
import json, os, sys, urllib.parse
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
    L.execute(f"now_sec = {NOW}; ctx.clock.now = function(self) return {{ epoch_sec = now_sec, hour = 12 + (now_sec - {NOW}) // 3600, minute = 0, second = 0 }} end")
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
assert 'name=İzmir\nlat=38.41\nlon=27.13\nunit=C\nlock=false' == g.store['settings.txt']
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
g.tap_label('Lock')
assert list(g.L.eval('lock_calls').values()) == ['set'] and 'lock=true' in g.store['settings.txt']
assert 'Lock off' in g.texts()
g.tap_label('Lock off')
assert list(g.L.eval('lock_calls').values()) == ['set', 'clear']
g.tap_label('Lock')

L2 = lua54.LuaRuntime(unpack_returned_tuples=True)
L2.execute(STUBS)
answer2 = setup(L2)
for k in ('forecast.txt', 'settings.txt'):
    L2.globals().store[k] = g.store[k]
L2.execute(f"now_sec = {NOW + 31 * 60 + 10 * 60}")
L2.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
draw2 = L2.eval("function() drawn, commands = {}, 0; on_draw(ctx, gg); local t = {} for _, d in ipairs(drawn) do t[#t + 1] = d.s end return t end")
t = list(draw2().values())
for s in ['İzmir', '°C', 'Rain', 'Today 11° / 18°   rain 80%', 'Tue', 'Wed', 'Thu', '10° / 15°', 'updated 10 min ago']:
    assert s in t, (s, t)
assert int(L2.globals().commands) < 300, L2.globals().commands
n = len(requests)
draw2()
assert len(requests) == n                                  # fresh: no question
L2.execute(f"now_sec = now_sec + 2 * 3600")
t = list(draw2().values())
assert 'updated 130 min ago' in t or 'updated 2 h ago' in t, t
assert len(requests) == n + 1
draw2()
assert len(requests) == n + 1                              # asked once, not on every draw
answer2()
assert 'updated=' + str(NOW + 31 * 60 + 10 * 60 + 2 * 3600) in L2.globals().store['forecast.txt']
assert 'updated 0 min ago' in list(draw2().values())
L3 = lua54.LuaRuntime(unpack_returned_tuples=True)          # nothing saved yet
L3.execute(STUBS)
L3.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
L3.eval("function() on_draw(ctx, gg) end")()
assert any('open the app once' in str(d.s) for d in L3.globals().drawn.values())

assert g.commands() < 500, g.commands()
g.no_err()
print('weather tests passed')
