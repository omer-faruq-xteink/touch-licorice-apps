"""Offline test of Tasks' Todoist and Google Tasks lists (lib/remote.lua) against fake servers:
the token files taken in from AppFiles/tasks and deleted, lists fetched (Todoist's cursor pages,
Google's token refresh and a 401 retried with a new token), sub-items and due dates, ticking,
unticking and adding sent to each service (several ticks go out together, an untick before the
send cancels the tick), changes kept while there is no Wi-Fi and sent later, a refused token, the
lock screen on a service's list, TickTick (a sign-in code traded on the reader, UTC dates as
local days, its repeat, complete, add and untick), several accounts (a second Google account that fails alone, then
syncs once fixed; one removed), and an app with local lists only never loading lib/remote.lua.

  python -I apps/tasks/test_remote.py
"""
import base64, json, os, re, sys, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
L = g.L
G = L.globals()
TOP, ROW_H = 96, 64

# ---------------------------------------------------------------- fake services
calls = []
online = [True]
TOKEN = 'tdTOKEN123'


def todoist_state():
    tasks = [{'id': 't1', 'content': 'Buy milk', 'project_id': 'p1', 'child_order': 1, 'checked': False,
              'due': {'date': '2026-11-09', 'is_recurring': False, 'string': 'today'}, 'parent_id': None},
             {'id': 't2', 'content': 'Water plants', 'project_id': 'p2', 'child_order': 0, 'checked': False,
              'due': {'date': '2026-11-10', 'is_recurring': True, 'string': 'every 4 days'}, 'parent_id': None},
             {'id': 't3', 'content': 'kitchen', 'project_id': 'p2', 'child_order': 0, 'checked': False, 'due': None, 'parent_id': 't2'}]
    tasks += [{'id': 'n%d' % k, 'content': 'note %d' % k, 'project_id': 'p2', 'child_order': k + 1, 'checked': False,
               'due': None, 'parent_id': None} for k in range(60)]
    return {'projects': [{'id': 'p2', 'name': 'Home', 'child_order': 1, 'inbox_project': False, 'is_archived': False},
                         {'id': 'p1', 'name': 'Inbox', 'child_order': 0, 'inbox_project': True, 'is_archived': False},
                         {'id': 'p9', 'name': 'Old', 'child_order': 2, 'is_archived': True}],
            'tasks': tasks, 'next': 100}


T = todoist_state()
GS = {'access': None, 'refreshes': 0, 'fail401': False,
      'tasks': [{'id': 'g1', 'title': 'Call the plumber', 'status': 'needsAction', 'position': '00000000000000000001'},
                {'id': 'g2', 'title': 'Pay rent', 'status': 'completed', 'position': '00000000000000000000',
                 'due': '2026-11-01T00:00:00.000Z'},
                {'id': 'g3', 'title': 'ask about the boiler', 'status': 'needsAction', 'position': '00000000000000000000',
                 'parent': 'g1'}]}


def page(items, cursor, n=50):
    start = int(cursor or 0)
    chunk = items[start:start + n]
    return {'results': chunk, 'next_cursor': str(start + n) if start + n < len(items) else None}


def todoist(method, path, q, body, h):
    if h.get('authorization') != 'Bearer ' + TOKEN:
        return 401, '{"error":"unauthorized"}'
    if method == 'GET' and path == '/projects':
        return 200, json.dumps(page(T['projects'], q.get('cursor'), int(q['limit'])))
    if method == 'GET' and path == '/tasks':
        assert int(q['limit']) <= 50
        return 200, json.dumps(page(T['tasks'], q.get('cursor'), int(q['limit'])))
    m = re.match(r'^/tasks/([^/]+)/(close|reopen)$', path)
    if method == 'POST' and m:
        t = next((x for x in T['tasks'] if x['id'] == m.group(1)), None)
        if not t:
            return 404, '{}'
        if m.group(2) == 'close':
            if t['due'] and t['due']['is_recurring']:
                t['due']['date'] = '2026-11-14'                 # the next date; stays active
            else:
                T['tasks'].remove(t)
        return 204, ''
    if method == 'POST' and path == '/tasks':
        d = json.loads(body)
        assert h.get('content-type') == 'application/json'
        t = {'id': 'new%d' % T['next'], 'content': d['content'], 'project_id': d['project_id'], 'child_order': 999,
             'checked': False, 'due': None, 'parent_id': None}
        T['next'] += 1
        T['tasks'].append(t)
        return 200, json.dumps(t)
    return 404, '{}'


GW = {'valid': False, 'access': None, 'n': 0}          # a second Google account: work


def google_work(method, path, q, body, h):
    if method == 'GET' and path == '/users/@me/lists':
        return 200, json.dumps({'items': [{'id': 'W1', 'title': 'Work'}]})
    if method == 'GET' and path == '/lists/W1/tasks':
        return 200, json.dumps({'items': [{'id': 'w1', 'title': 'Send the report', 'status': 'needsAction', 'position': '1'}]})
    return 404, '{}'


def google(method, path, q, body, h):
    if GW['access'] and h.get('authorization') == 'Bearer ' + GW['access']:
        return google_work(method, path, q, body, h)
    if h.get('authorization') != 'Bearer ' + str(GS['access']):
        return 401, '{"error":{"code":401}}'
    if GS['fail401']:
        GS['fail401'] = False
        GS['access'] = 'expired'
        return 401, '{"error":{"code":401}}'
    if method == 'GET' and path == '/users/@me/lists':
        assert 'items(id,title)' in q['fields']
        return 200, json.dumps({'items': [{'id': 'L1', 'title': 'My Tasks'}]})
    if method == 'GET' and path == '/lists/L1/tasks':
        assert q['showCompleted'] == 'true'
        if 'pageToken' not in q:
            return 200, json.dumps({'items': GS['tasks'][:2], 'nextPageToken': 'pg2'})
        return 200, json.dumps({'items': GS['tasks'][2:]})
    m = re.match(r'^/lists/L1/tasks/([^/]+)$', path)
    if method == 'PATCH' and m:
        d = json.loads(body)
        t = next(x for x in GS['tasks'] if x['id'] == m.group(1))
        t['status'] = d['status']
        if 'completed' in d:
            assert d['completed'] is None
        return 200, json.dumps(t)
    if method == 'POST' and path == '/lists/L1/tasks':
        d = json.loads(body)
        t = {'id': 'gn', 'title': d['title'], 'status': 'needsAction', 'position': '00000000000000000099'}
        GS['tasks'].append(t)
        return 200, json.dumps(t)
    return 404, '{}'


TT = {'token': None, 'codes': {'good-code'}, 'tasks': {
    'inbox': [{'id': 'ti1', 'projectId': 'inbox123', 'title': 'Inbox thing', 'status': 0, 'sortOrder': 0,
               'dueDate': '2026-11-11T21:00:00.000+0000', 'isAllDay': True}],
    'tp1': [{'id': 'tt1', 'projectId': 'tp1', 'title': 'Apples', 'status': 0, 'sortOrder': 1,
             'repeatFlag': 'RRULE:FREQ=WEEKLY;INTERVAL=2'},
            {'id': 'tt2', 'projectId': 'tp1', 'title': 'Pears', 'status': 0, 'sortOrder': 2}]}}


def ticktick(method, path, q, body, h):
    if h.get('authorization') != 'Bearer ' + str(TT['token']):
        return 401, '{"errorCode":"unauthorized"}'
    if method == 'GET' and path == '/project':
        return 200, json.dumps([{'id': 'tp1', 'name': 'Groceries', 'sortOrder': 0}, {'id': 'tp9', 'name': 'Old', 'closed': True}])
    m = re.match(r'^/project/([^/]+)/data$', path)
    if method == 'GET' and m:
        return 200, json.dumps({'project': {'id': m.group(1)}, 'tasks': [t for t in TT['tasks'].get(m.group(1), []) if t['status'] == 0]})
    m = re.match(r'^/project/([^/]+)/task/([^/]+)/complete$', path)
    if method == 'POST' and m:
        next(t for t in TT['tasks'][m.group(1)] if t['id'] == m.group(2))['status'] = 2
        return 200, ''
    m = re.match(r'^/task/([^/]+)$', path)
    if method == 'POST' and m:
        d = json.loads(body)
        assert d['id'] == m.group(1) and d['status'] == 0
        next(t for t in TT['tasks'][d['projectId']] if t['id'] == d['id'])['status'] = 0
        return 200, '{}'
    if method == 'POST' and path == '/task':
        d = json.loads(body)
        TT['tasks'][d['projectId']].append({'id': 'tn', 'projectId': d['projectId'], 'title': d['title'], 'status': 0, 'sortOrder': 9})
        return 200, '{}'
    return 404, '{}'


def fake_request(method, url, body, headers):
    h = {str(k).lower(): str(v) for k, v in headers.items()} if headers else {}
    method = method or 'GET'
    calls.append((method, url, body, h))
    if not online[0]:
        return None, None
    u = urllib.parse.urlparse(url)
    q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
    if u.netloc == 'api.todoist.com':
        return todoist(method, u.path.replace('/api/v1', ''), q, body, h)
    if u.netloc == 'oauth2.googleapis.com':
        f = {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}
        assert h['content-type'] == 'application/x-www-form-urlencoded'
        if f.get('refresh_token') == '1//work' and GW['valid']:
            GW['n'] += 1
            GW['access'] = 'work%d' % GW['n']
            return 200, json.dumps({'access_token': GW['access'], 'expires_in': 3599})
        if f.get('refresh_token') != '1//refresh' or f.get('client_secret') != 'GOCSPX-sec':
            return 400, '{"error":"invalid_grant","error_description":"Bad Request"}'
        GS['refreshes'] += 1
        GS['access'] = 'acc%d' % GS['refreshes']
        return 200, json.dumps({'access_token': GS['access'], 'expires_in': 3599, 'token_type': 'Bearer'})
    if u.netloc == 'ticktick.com' and u.path == '/oauth/token':
        f = {k: v[0] for k, v in urllib.parse.parse_qs(body).items()}
        assert h['authorization'] == 'Basic ' + base64.b64encode(b'ttid:ttsecret').decode(), h
        assert f['grant_type'] == 'authorization_code' and f['redirect_uri'] == 'http://localhost' and f['scope'] == 'tasks:read tasks:write'
        if f['code'] not in TT['codes']:
            return 400, '{"error":"invalid_grant","error_description":"Invalid authorization code"}'
        TT['codes'].discard(f['code'])
        TT['token'] = 'ttTOKEN'
        return 200, json.dumps({'access_token': 'ttTOKEN', 'token_type': 'bearer', 'expires_in': 15551999, 'scope': 'tasks:read tasks:write'})
    if u.netloc == 'api.ticktick.com':
        return ticktick(method, u.path.replace('/open/v1', ''), q, body, h)
    if u.netloc == 'tasks.googleapis.com':
        return google(method, u.path.replace('/tasks/v1', ''), q, body, h)
    return 404, '{}'


def to_py(t):
    if not hasattr(t, 'items'):
        return t
    keys = list(t.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [to_py(t[k]) for k in sorted(keys)]
    return {str(k): to_py(v) for k, v in t.items()} if keys else []


files = {}
G.py_request = fake_request
G.py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)
G.py_json_encode = lambda t: json.dumps(to_py(t))
G.py_files = files
G.py_b64 = lambda s: base64.b64encode(s.encode()).decode()
G.py_list = lambda: L.table_from([L.table_from({'name': k}) for k, v in files.items() if v])
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute(r'''
local function M(t)
  local out = {}
  for k, f in pairs(t) do out[k] = function(self, ...) return f(...) end end
  return out
end
net_pending, timers = {}, {}
ctx.net = M({ keep_wifi = function() end, request = function(opts, fn)
  local st, body = py_request(opts.method, opts.url, opts.body, opts.headers)
  net_pending[#net_pending + 1] = function()
    if st == nil then fn(ctx, { ok = false, err = 'no_network' })
    else fn(ctx, { ok = true, status = st, body = body, headers = {} }) end
  end
  return M({ cancel = function() end })
end })
ctx.json = M({ decode = function(s) return py_json_decode(s) end, encode = function(t) return py_json_encode(t) end })
ctx.files = M({ exists = function(n) return py_files[n] ~= nil end, read = function(n) return py_files[n] end,
                list = function() return py_list() end,
                remove = function(n) py_files[n] = nil; return true end })
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn end
ctx.base64 = M({ encode = function(s) return py_b64(s) end })
ctx.clock.now = function(self) return { epoch_sec = 1794200000, hour = 10, minute = 42, second = 0, valid = true } end
ctx.storage.remove = function(self, n) store[n] = nil end
ctx.lockscreen = { is_default = function() return true end, set_default = function() end, clear_default = function() end }
function flush()
  for _ = 1, 400 do
    local p = net_pending; net_pending = {}
    if #p == 0 then
      local t = timers; timers = {}
      if #t == 0 then return end
      for _, f in ipairs(t) do f() end
    else
      for _, f in ipairs(p) do f() end
    end
  end
end
''')
flush = G.flush


def typed(s):
    L.eval('inputs[#inputs]')(G.ctx, s)


def row(k): return TOP + (k - 1) * ROW_H + 30
def names(): return [str(l.name) for l in g.api.lists().values()]
def cur_items(): return [(str(it.text), bool(it.done)) for it in g.api.lists()[g.api.cur()]['items'].values()]
def tick_text(text):
    g.tap(30, row([i[0] for i in cur_items()].index(text) + 1))


def done_of(text):
    return dict(cur_items())[text]


def open_list(name):
    i = names().index(name) + 1
    while i > 9:
        g.L.execute("on_input(ctx, {type='pointer', phase='up', gesture='swipe_up', x=200, y=400})")
        i -= 9
    g.tap(200, row(i))


# ---------------------------------------------------------------- local only: lib/remote.lua not loaded
g.store['lists.txt'] = '# To do\n[ ] bread\n'
g.restart()
assert L.eval("package.loaded['lib.remote'] == nil") and g.api.remote() is None
assert 'Sync' in g.texts() and 'Sources' in g.texts()

# ---------------------------------------------------------------- set up through AppFiles
files['todoist.txt'] = TOKEN + '\n'
files['google.txt'] = 'client_id = 123.apps.googleusercontent.com\nclient_secret = GOCSPX-sec\nrefresh_token = 1//refresh\n'
files['Google-Work.txt'] = 'client_id = 9.apps.googleusercontent.com\nclient_secret = GOCSPX-w\nrefresh_token = 1//work\n'
g.restart()
assert not any(files.values()), files                    # taken in and deleted
acc = json.loads(g.store['remote_accounts.json'])
assert sorted(a['id'] for a in acc) == ['google', 'google-work', 'todoist'], acc
assert any(a.get('token') == TOKEN for a in acc) and any(a.get('g_refresh') == '1//work' and a.get('label') == 'work' for a in acc)
flush()
# the work account's refresh token is refused: it fails alone, the others sync
assert set(names()) == {'To do', 'Inbox', 'Home', 'My Tasks'} and names()[0] == 'To do', names()
assert names().index('Inbox') + 1 == names().index('Home')                # the inbox first, archived left out
t = g.texts()
assert 'Todoist, 1 to do, 0 done' in t and 'Google, 2 to do, 1 done' in t, t
assert 'Synced 10:42, 1 account failed (Sources)' in t, t
g.tap_label('Sources')
assert 'Google (work): sign-in refused (Bad Request)' in ' '.join(g.texts()), g.texts()
g.tap_label('Close')
# fixed: a new file for it, Read files
GW['valid'] = True
files['google-work.txt'] = 'client_id = 9.apps.googleusercontent.com\nclient_secret = GOCSPX-w\nrefresh_token = 1//work\n'
g.tap_label('Sources'); g.tap_label('Read files')
flush()
assert 'Work' in names() and 'Google (work), 1 to do, 0 done' in g.texts(), (names(), g.texts())
assert len(json.loads(g.store['remote_accounts.json'])) == 3
assert 'Synced 10:42' in g.texts()
assert 'p9' not in json.dumps(to_py(L.eval('__TEST.api.remote().lists()')))
# Todoist: cursor pages of 50, a sub-item under its parent, a repeating date
pages = [c for c in calls if '/api/v1/tasks?' in c[1]]
assert len(pages) % 2 == 0 and 'cursor=50' in pages[1][1] and 'cursor' not in pages[0][1], pages
open_list('Home')
items = cur_items()
assert len(items) == 62 and items[0] == ('Water plants', False) and items[1] == ('kitchen', False), items[:3]
home = g.api.lists()[g.api.cur()]
assert int(home['items'][2].depth) == 1
assert any('every 4 days, due' in s for s in g.texts()), g.texts()
# Google: the token fetched first, two pages, completed shown ticked, the sub-item under its parent
assert GS['refreshes'] == 1
g.key('back')
open_list('My Tasks')
assert cur_items() == [('Call the plumber', False), ('ask about the boiler', False), ('Pay rent', True)], cur_items()
assert int(g.api.lists()[g.api.cur()]['items'][2].depth) == 1
assert any('late 8 days' in s for s in g.texts()), g.texts()   # Pay rent, due 1 Nov

# ---------------------------------------------------------------- tick, untick, add
calls.clear()
tick_text('Call the plumber')
assert done_of('Call the plumber') is True
assert len(to_py(L.eval('__TEST.api.remote().test.pending()'))) == 1
flush()
patch = [c for c in calls if c[0] == 'PATCH']
assert len(patch) == 1 and patch[0][1].endswith('/lists/L1/tasks/g1') and json.loads(patch[0][2]) == {'status': 'completed'}
assert GS['tasks'][0]['status'] == 'completed' and done_of('Call the plumber') is True
assert [i[0] for i in cur_items()] == ['Pay rent', 'Call the plumber', 'ask about the boiler']   # done ones last
calls.clear()
tick_text('Call the plumber')
flush()
patch = [c for c in calls if c[0] == 'PATCH']
assert json.loads(patch[0][2]) == {'status': 'needsAction', 'completed': None} and GS['tasks'][0]['status'] == 'needsAction'
# tick, then untick before it is sent: nothing goes out
calls.clear()
tick_text('Call the plumber'); tick_text('Call the plumber')
flush()
assert not [c for c in calls if c[0] == 'PATCH'], calls
g.tap_label('Add'); typed('Buy stamps')
assert cur_items()[-1] == ('Buy stamps', False)
flush()
post = [c for c in calls if c[0] == 'POST' and c[1].endswith('/lists/L1/tasks')]
assert len(post) == 1 and json.loads(post[0][2]) == {'title': 'Buy stamps'}
# the item menu and Clear done say where to do the rest
g.tap(200, row(1))
assert 'From Google: tick it here' in ' '.join(g.texts()), g.texts()
g.tap_label('Close')
g.tap_label('Clear done')
assert 'Done items leave Google' in ' '.join(g.texts()), g.texts()
g.key('back')

# Todoist: close two at once (one repeats), add
open_list('Inbox')
calls.clear()
g.tap(30, row(1))                                         # Buy milk
g.key('back')
open_list('Home')
g.tap(30, row(1))                                         # Water plants (repeats)
g.tap_label('Add'); typed('Fix the shelf')
flush()
sent = [(c[0], urllib.parse.urlparse(c[1]).path) for c in calls if c[0] == 'POST']
assert ('POST', '/api/v1/tasks/t1/close') in sent and ('POST', '/api/v1/tasks/t2/close') in sent and ('POST', '/api/v1/tasks') in sent, sent
add = next(c for c in calls if c[0] == 'POST' and c[1].endswith('/api/v1/tasks'))
assert json.loads(add[2]) == {'content': 'Fix the shelf', 'project_id': 'p2'}
items = cur_items()
assert items[0] == ('Water plants', False) and ('Fix the shelf', False) in items     # back with its next date
assert any('every 4 days, due' in s and '14 Nov' in s for s in g.texts()), g.texts()
g.key('back')
assert 'Todoist, 0 to do, 0 done' in g.texts()            # Buy milk closed and gone

# ---------------------------------------------------------------- no Wi-Fi: kept, sent later
open_list('My Tasks')
online[0] = False
tick_text('Call the plumber')
flush()
assert len(to_py(L.eval('__TEST.api.remote().test.pending()'))) == 1 and done_of('Call the plumber') is True
assert 'remote_pending.json' in g.store and 'g1' in g.store['remote_pending.json']
g.key('back')
assert any('No Wi-Fi, 1 change waiting' in s for s in g.texts()), g.texts()
online[0] = True
g.restart()                                               # kept between visits; the open sends it
flush()
assert GS['tasks'][0]['status'] == 'completed' and len(to_py(L.eval('__TEST.api.remote().test.pending()'))) == 0

# Google: a 401 gets a new token and the request again
GS['fail401'] = True
before = GS['refreshes']
g.tap_label('Sync')
flush()
assert GS['refreshes'] == before + 1 and 'My Tasks' in names()

# ---------------------------------------------------------------- a service's list on the lock screen
open_list('Home')
g.tap_label('List')
g.tap_label('Lock screen')
lock = g.store['lock.txt']
assert lock.startswith('Home\n') and 'kitchen' in lock, lock
assert 'todoist:p2' in g.store['settings.txt']
g.key('back')

# ---------------------------------------------------------------- a token that is not accepted; Remove
TOKEN = 'changed'
g.tap_label('Sync')
flush()
assert 'Synced 10:42, 1 account failed (Sources)' in g.texts(), g.texts()
g.tap_label('Sources')
assert 'Todoist: the token was not accepted' in ' '.join(g.texts()), g.texts()
g.tap_label('Todoist token'); typed(' changed ')
flush()
assert 'Inbox' in names()
g.tap_label('Sources')
g.tap_label('Remove')
assert 'Remove which account?' in g.texts() and 'Google (work)' in g.texts()
g.tap_label('Todoist')
assert 'Inbox' not in names() and 'Home' not in names() and 'My Tasks' in names() and 'Work' in names()
assert len(json.loads(g.store['remote_accounts.json'])) == 2

# ---------------------------------------------------------------- TickTick: a code traded for a token on the reader
files['ticktick.txt'] = 'client_id = ttid\nclient_secret = ttsecret\ncode = bad-code\n'
g.tap_label('Sources'); g.tap_label('Read files')
flush()
g.tap_label('Sources')
t = ' '.join(g.texts())
assert 'TickTick: sign-in refused (Invalid authorization code)' in t, t
g.tap_label('Close')
g.tap_label('Sync'); flush()
g.tap_label('Sources')
assert 'TickTick: sign-in needed' in ' '.join(g.texts()), g.texts()       # the code is used up
g.tap_label('Close')
files['ticktick.txt'] = 'client_id = ttid\nclient_secret = ttsecret\ncode = good-code\n'
g.tap_label('Sources'); g.tap_label('Read files')
flush()
acc = json.loads(g.store['remote_accounts.json'])
tt = next(a for a in acc if a['src'] == 'ticktick')
assert tt['token'] == 'ttTOKEN' and 'tt_code' not in tt, tt
assert names()[-2:] == ['Inbox', 'Groceries'], names()                   # the Inbox first, closed projects left out
t = g.texts()
assert 'TickTick, 1 to do, 0 done' in t and 'TickTick, 2 to do, 0 done' in t, t
open_list('Inbox')
assert cur_items() == [('Inbox thing', False)]
assert any('due Thu 12 Nov' in x for x in g.texts()), g.texts()          # 21:00 UTC is the next day here
g.key('back')
open_list('Groceries')
assert any('every 2 weeks' in x for x in g.texts()), g.texts()
calls.clear()
tick_text('Apples')
flush()
done = [c for c in calls if c[0] == 'POST' and 'api.ticktick.com' in c[1]]
assert any(c[1].endswith('/project/tp1/task/tt1/complete') for c in done), done
assert 'Apples' not in [i[0] for i in cur_items()]                       # a completed task leaves, as in Todoist
g.tap_label('Add'); typed('Plums')
flush()
add = next(c for c in calls if c[1].endswith('/open/v1/task'))
assert json.loads(add[2]) == {'title': 'Plums', 'projectId': 'tp1'}
assert ('Plums', False) in cur_items()
# untick before it is sent: nothing goes out; an untick that is sent sets the status back (no reopen call)
calls.clear()
tick_text('Pears'); tick_text('Pears')
flush()
assert not [c for c in calls if 'complete' in c[1]], calls
op = L.eval("{ acc = 'ticktick', src = 'ticktick', op = 'reopen', list = 'tp1', item = 'tt2' }")
L.eval("function(op) local P = __TEST.api.remote().test.pending(); P[#P + 1] = op end")(op)
TT['tasks']['tp1'][1]['status'] = 2
g.tap_label('Sync') if 'Sync' in g.texts() else None
g.key('back'); g.tap_label('Sync')
flush()
re_ = [c for c in calls if c[1].endswith('/open/v1/task/tt2')]
assert re_ and json.loads(re_[0][2]) == {'id': 'tt2', 'projectId': 'tp1', 'status': 0}, calls
assert TT['tasks']['tp1'][1]['status'] == 0
g.no_err()
print('tasks remote tests passed')
