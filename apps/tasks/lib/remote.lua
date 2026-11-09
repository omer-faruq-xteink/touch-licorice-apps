-- Todoist and Google Tasks lists for Tasks (loaded with require only when an account is set up or
-- Sources is opened: an app with local lists only never loads this file).
--
-- Each project (Todoist) or task list (Google) shows as a list of its own, after the local ones,
-- marked with its account. On the reader you can tick and untick an item and add one; everything
-- else (renaming, deleting, dates) stays in the service's own apps. A change is sent at once and
-- kept in a queue while there is no Wi-Fi; a sync sends the queue first, then fetches every list
-- again. An account that fails (a token no longer accepted) keeps its lists as they were and does
-- not stop the others.
--
-- Accounts come from files the user puts in AppFiles/tasks/, taken into the app's private storage
-- and deleted from the card: todoist.txt or todoist-NAME.txt (the API token), google.txt or
-- google-NAME.txt (client_id, client_secret, refresh_token); NAME tells two accounts of one
-- service apart ("Google (work)"). A Todoist token can also be typed in Sources.
-- Todoist: REST API v1 (https://api.todoist.com/api/v1), a personal API token.
-- TickTick: its Open API (https://api.ticktick.com/open/v1) with the user's own app from
-- developer.ticktick.com: ticktick.txt holds an access token (got on a computer with curl), or the
-- app's client_id and client_secret and a sign-in code, which the reader trades for a token when
-- it opens (the code lasts only minutes). The API has no "reopen": unticking updates the task's
-- status, which TickTick may refuse. Its dates come in UTC and are turned into local days.
-- Google Tasks: Google's device sign-in does not cover Tasks, so the user signs in once on a
-- computer (own OAuth client in Google Cloud, OAuth Playground); the app trades the refresh token
-- for short-lived access tokens at oauth2.googleapis.com. Unticking uses PATCH (firmware 2.18).
--
-- Files in private storage: remote_accounts.json (the accounts and their tokens), remote.json (the
-- lists as last fetched), remote_pending.json (changes not sent yet).
-- require('lib.remote')(env) -> R;  env = { kit, changed = fn() }

return function(env)
  local kit = env.kit
  local R = {}

  local TODOIST = 'https://api.todoist.com/api/v1'
  local GTASKS = 'https://tasks.googleapis.com/tasks/v1'
  local GTOKEN = 'https://oauth2.googleapis.com/token'
  local TICKTICK = 'https://api.ticktick.com/open/v1'
  local TTOKEN = 'https://ticktick.com/oauth/token'
  local TT_REDIRECT = 'http://localhost'
  local NAMES = { todoist = 'Todoist', google = 'Google', ticktick = 'TickTick' }

  local accounts = {}       -- { { id, src, label, token | g_id, g_secret, g_refresh, g_access, g_exp } }
  local rlists = {}         -- { { acc, src, rid, name, items = { { text, done, rid, depth, due, rec } } } }
  local pending = {}        -- { { acc, src, op = close|reopen|add, list, item, text } }
  local errors = {}         -- account id -> what went wrong in the last sync
  local busy = false
  local status = nil        -- the line shown under the title on the list of lists
  local queue = {}          -- the running sync: { { fn, acc } }
  local flush_timer = false

  ------------------------------------------------------------------ helpers

  local function json_enc(v) local ok, s = pcall(function() return ctx.json:encode(v) end); return ok and s or nil end
  local function json_dec(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(function() return ctx.json:decode(s) end)
    return ok and v or nil
  end
  local function str(v) return type(v) == 'string' and v or (type(v) == 'number' and tostring(math.tointeger(v) or v)) or nil end

  local function urlenc(s)
    return (tostring(s):gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
  end

  local function now_sec()
    local ok, t = pcall(function() return ctx.clock:now() end)
    if ok and type(t) == 'table' and tonumber(t.epoch_sec) then return math.floor(tonumber(t.epoch_sec)), t end
    return 0, nil
  end

  local function clock_label()
    local _s, t = now_sec()
    if t and tonumber(t.hour) then return string.format('%02d:%02d', tonumber(t.hour), tonumber(t.minute) or 0) end
    return 'now'
  end

  local function kv(s)
    local t = {}
    for line in ((s or '') .. '\n'):gmatch('([^\n]*)\n') do
      local k, v = line:gsub('\r', ''):match('^%s*([%w_]+)%s*[=:]%s*(.-)%s*$')
      if k then t[k:lower()] = v end
    end
    return t
  end

  local function account(id)
    for _k, a in ipairs(accounts) do if a.id == id then return a end end
    return nil
  end

  -- "Todoist", "Google (work)"
  function R.label(x)
    local a = type(x) == 'table' and account(x.acc or x.id) or account(x)
    if not a then return NAMES[type(x) == 'table' and x.src or ''] or '?' end
    return NAMES[a.src] .. (a.label and (' (' .. a.label .. ')') or '')
  end

  ------------------------------------------------------------------ storage

  local FIELDS = { 'id', 'src', 'label', 'token', 'g_id', 'g_secret', 'g_refresh', 'g_access', 'g_exp',
                   'tt_id', 'tt_secret', 'tt_code', 'tt_refresh' }

  local function save_accounts()
    local out = {}
    for _k, a in ipairs(accounts) do
      local o = {}
      for _j, f in ipairs(FIELDS) do if a[f] then o[f] = tostring(a[f]) end end
      out[#out + 1] = o
    end
    kit.write('remote_accounts.json', json_enc(out) or '[]')
  end

  local function save_lists()
    kit.write('remote.json', json_enc(rlists) or '[]')
    kit.write('remote_pending.json', #pending > 0 and (json_enc(pending) or '[]') or '[]')
  end

  function R.load()
    accounts = {}
    local acc = json_dec(kit.read('remote_accounts.json'))
    for _k, x in ipairs(type(acc) == 'table' and acc or {}) do
      if type(x) == 'table' and str(x.id) and NAMES[x.src] then
        local a = {}
        for _j, f in ipairs(FIELDS) do a[f] = str(x[f]) end
        accounts[#accounts + 1] = a
      end
    end
    local l = json_dec(kit.read('remote.json'))
    rlists = {}
    for _k, x in ipairs(type(l) == 'table' and l or {}) do
      if type(x) == 'table' and x.src and x.name and account(str(x.acc)) then
        local items = {}
        for _j, it in ipairs(type(x.items) == 'table' and x.items or {}) do
          if type(it) == 'table' and type(it.text) == 'string' then
            items[#items + 1] = { text = it.text, done = it.done == true, rid = str(it.rid), depth = tonumber(it.depth) or 0,
                                  due = str(it.due), rec = str(it.rec) }
          end
        end
        rlists[#rlists + 1] = { acc = str(x.acc), src = x.src, rid = str(x.rid), name = x.name, items = items }
      end
    end
    local p = json_dec(kit.read('remote_pending.json'))
    pending = {}
    for _k, op in ipairs(type(p) == 'table' and p or {}) do
      if type(op) == 'table' and op.op and account(str(op.acc)) then pending[#pending + 1] = op end
    end
  end

  local function ready(a)
    if a.src == 'todoist' then return (a.token or '') ~= '' end
    if a.src == 'ticktick' then return (a.token or '') ~= '' or ((a.tt_code or '') ~= '' and (a.tt_id or '') ~= '') end
    return (a.g_refresh or '') ~= '' and (a.g_id or '') ~= ''
  end

  function R.configured(src)
    for _k, a in ipairs(accounts) do if ready(a) and (not src or a.src == src) then return true end end
    return false
  end

  function R.accounts() return accounts end
  function R.ready(a) return ready(a) end
  function R.lists() return rlists end
  function R.status() return status end
  function R.error(id) return errors[id] end
  function R.busy() return busy end
  function R.waiting() return #pending end

  -- an account file's name: todoist.txt, Google-Work.txt -> src, label
  local function account_file(name)
    local base, rest = name:lower():match('^(%a+)(.-)%.txt$')
    if not base or not NAMES[base] then return nil end
    if rest == '' then return base, nil end
    local label = rest:match('^[%-_ ]+(.+)$')
    if not label or not label:match('^[%w%-_ ]+$') then return nil end
    return base, label
  end
  R.account_file = account_file

  local function set_account(src, label, fields)
    local id = src .. (label and ('-' .. label) or '')
    local a = account(id)
    if not a then
      a = { id = id, src = src, label = label }
      accounts[#accounts + 1] = a
    end
    for k, v in pairs(fields) do a[k] = v end
    errors[id] = nil
    return a
  end

  -- every account file in AppFiles/tasks: taken in and deleted. Returns a message or nil.
  function R.import_files()
    if not ctx.files then return nil end
    local names = {}
    local ok, list = pcall(function() return ctx.files:list() end)
    if ok and type(list) == 'table' then
      for _k, f in ipairs(list) do if type(f) == 'table' and type(f.name) == 'string' then names[#names + 1] = f.name end end
    end
    if #names == 0 then names = { 'todoist.txt', 'google.txt' } end
    local said = {}
    for _k, name in ipairs(names) do
      local src, label = account_file(name)
      local okr, s = pcall(function() if src and ctx.files:exists(name) then return ctx.files:read(name, 0, 8192) end end)
      if okr and type(s) == 'string' then
        pcall(function() ctx.files:remove(name) end)
        local v = kv(s)
        local lbl = NAMES[src] .. (label and (' (' .. label .. ')') or '')
        if src == 'todoist' then
          local token = v.token or v.todoist or s:match('^%s*(%w+)%s*$')
          if token and token ~= '' then set_account(src, label, { token = token }); said[#said + 1] = lbl .. ' set up'
          else said[#said + 1] = name .. ': no token in it' end
        elseif src == 'ticktick' then
          local token = v.access_token or v.token or s:match('^%s*([%w%-]+)%s*$')
          if token and token ~= '' and not v.code then
            set_account(src, label, { token = token, tt_id = v.client_id, tt_secret = v.client_secret,
                                      tt_refresh = v.refresh_token, tt_code = nil })
            said[#said + 1] = lbl .. ' set up'
          elseif v.client_id and v.client_secret and v.code then
            set_account(src, label, { token = nil, tt_id = v.client_id, tt_secret = v.client_secret, tt_code = v.code })
            said[#said + 1] = lbl .. ': signing in'
          else
            said[#said + 1] = name .. ' needs access_token, or client_id, client_secret and code'
          end
        elseif v.client_id and v.client_secret and v.refresh_token then
          set_account(src, label, { g_id = v.client_id, g_secret = v.client_secret, g_refresh = v.refresh_token,
                                    g_access = nil, g_exp = nil })
          said[#said + 1] = lbl .. ' set up'
        else
          said[#said + 1] = name .. ' needs client_id, client_secret and refresh_token'
        end
      end
    end
    if #said == 0 then return nil end
    save_accounts()
    return table.concat(said, '; ')
  end

  function R.set_todoist(token)
    set_account('todoist', nil, { token = token })
    save_accounts()
  end

  -- forget an account: its tokens, its lists and its waiting changes
  function R.remove(id)
    local ka, kl, kp = {}, {}, {}
    for _k, a in ipairs(accounts) do if a.id ~= id then ka[#ka + 1] = a end end
    for _k, l in ipairs(rlists) do if l.acc ~= id then kl[#kl + 1] = l end end
    for _k, op in ipairs(pending) do if op.acc ~= id then kp[#kp + 1] = op end end
    accounts, rlists, pending = ka, kl, kp
    errors[id] = nil
    save_accounts()
    save_lists()
    env.changed()
  end

  ------------------------------------------------------------------ requests

  local fresh, got = {}, {}

  local function finish(msg)
    busy, queue = false, {}
    status = msg
    save_lists()
    env.changed()
    kit.refresh()
  end

  local function run_next()
    local q = table.remove(queue, 1)
    if not q then return end
    q.fn()
  end

  -- an account went wrong: its error kept, the rest of its requests skipped, the others go on
  local function fail(a, msg)
    errors[a.id] = msg
    local keep = {}
    for _k, q in ipairs(queue) do if q.acc ~= a.id then keep[#keep + 1] = q end end
    queue = keep
    run_next()
  end

  -- one request at a time; on_done(res) returns false when it has moved the queue on itself
  local function send(spec, on_done)
    local ok, job, err = pcall(function()
      return ctx.net:request(spec, function(c, res)
        local ok2, e = pcall(function()
          pcall(function() ctx.budget:extend() end)
          if on_done(res) ~= false then run_next() end
        end)
        if not ok2 then finish('Sync error: ' .. tostring(e)) end
      end)
    end)
    if not ok or not job then
      if ok and err == 'busy' then
        pcall(function() ctx:after(1500, function() send(spec, on_done) end) end)
        return
      end
      finish('Sync error: ' .. tostring(ok and err or job))
    end
  end

  -- no answer at all: without Wi-Fi every account would wait in vain, so the sync stops
  local function offline(res)
    if res and res.ok then return false end
    local e = res and res.err or 'no answer'
    finish((e == 'no_network' and 'No Wi-Fi' or ('Network: ' .. tostring(e))) ..
           (#pending > 0 and (', ' .. #pending .. ' change' .. (#pending == 1 and '' or 's') .. ' waiting') or ''))
    return true
  end

  local function headers(a, json)
    local h = { authorization = 'Bearer ' .. (a.src == 'google' and (a.g_access or '') or (a.token or '')) }
    if json then h['content-type'] = 'application/json' end
    return h
  end

  -- a fresh Google access token first when the one kept is missing or about to end
  local function google_token(a, then_fn)
    local now = now_sec()
    if a.g_access and tonumber(a.g_exp) and now > 0 and now < tonumber(a.g_exp) - 60 then then_fn(); return end
    local body = 'client_id=' .. urlenc(a.g_id or '') .. '&client_secret=' .. urlenc(a.g_secret or '') ..
                 '&refresh_token=' .. urlenc(a.g_refresh or '') .. '&grant_type=refresh_token'
    send({ url = GTOKEN, method = 'POST', headers = { ['content-type'] = 'application/x-www-form-urlencoded' }, body = body }, function(res)
      if offline(res) then return false end
      local d = json_dec(res.body)
      if res.status ~= 200 or type(d) ~= 'table' or type(d.access_token) ~= 'string' then
        local why = type(d) == 'table' and (str(d.error_description) or str(d.error)) or ('HTTP ' .. tostring(res.status))
        fail(a, 'sign-in refused (' .. tostring(why) .. ')')
        return false
      end
      a.g_access = d.access_token
      a.g_exp = tostring((now > 0 and now or 0) + (tonumber(d.expires_in) or 3600))
      save_accounts()
      then_fn()
      return false          -- then_fn sent its own request
    end)
  end

  -- TickTick: a sign-in code (or a refresh token after a 401) traded for an access token first
  local function ticktick_token(a, then_fn, refresh)
    local grant
    if refresh and (a.tt_refresh or '') ~= '' then
      grant = 'grant_type=refresh_token&refresh_token=' .. urlenc(a.tt_refresh)
    elseif not refresh and (a.token or '') == '' and (a.tt_code or '') ~= '' then
      grant = 'grant_type=authorization_code&code=' .. urlenc(a.tt_code) .. '&redirect_uri=' .. urlenc(TT_REDIRECT)
    else
      if refresh then fail(a, 'the token was not accepted (it may have run out: see the README)') return end
      then_fn()
      return
    end
    local ok, basic = pcall(function() return ctx.base64:encode((a.tt_id or '') .. ':' .. (a.tt_secret or '')) end)
    send({ url = TTOKEN, method = 'POST', body = grant .. '&scope=' .. urlenc('tasks:read tasks:write'),
           headers = { ['content-type'] = 'application/x-www-form-urlencoded', authorization = 'Basic ' .. (ok and basic or '') } }, function(res)
      if offline(res) then return false end
      local d = json_dec(res.body)
      a.tt_code = nil
      if res.status ~= 200 or type(d) ~= 'table' or type(d.access_token) ~= 'string' then
        save_accounts()
        local why = type(d) == 'table' and (str(d.error_description) or str(d.error)) or ('HTTP ' .. tostring(res.status))
        fail(a, 'sign-in refused (' .. tostring(why) .. '): a code lasts only minutes')
        return false
      end
      a.token = d.access_token
      if str(d.refresh_token) then a.tt_refresh = str(d.refresh_token) end
      save_accounts()
      then_fn()
      return false
    end)
  end

  ------------------------------------------------------------------ the queue of changes

  local function find(acc, list_rid, item_rid)
    for _k, l in ipairs(rlists) do
      if l.acc == acc and l.rid == list_rid then
        if not item_rid then return l end
        for _j, it in ipairs(l.items) do if it.rid == item_rid then return l, it end end
        return l
      end
    end
    return nil
  end

  -- the changes still waiting, laid over freshly fetched lists
  local function apply_pending()
    for _k, op in ipairs(pending) do
      local l, it = find(op.acc, op.list, op.item)
      if l then
        if op.op == 'add' then l.items[#l.items + 1] = { text = op.text, done = false, depth = 0 }
        elseif it then it.done = op.op == 'close' end
      end
    end
  end

  local function op_request(a, op)
    if a.src == 'ticktick' then
      if op.op == 'add' then
        return { url = TICKTICK .. '/task', method = 'POST', headers = headers(a, true),
                 body = json_enc({ title = op.text, projectId = op.list }) }
      end
      if op.op == 'close' then
        return { url = TICKTICK .. '/project/' .. urlenc(op.list) .. '/task/' .. urlenc(op.item) .. '/complete',
                 method = 'POST', headers = headers(a, false), body = '' }
      end
      return { url = TICKTICK .. '/task/' .. urlenc(op.item), method = 'POST', headers = headers(a, true),
               body = json_enc({ id = op.item, projectId = op.list, status = 0 }) }
    end
    if a.src == 'todoist' then
      if op.op == 'add' then
        return { url = TODOIST .. '/tasks', method = 'POST', headers = headers(a, true),
                 body = json_enc({ content = op.text, project_id = op.list }) }
      end
      return { url = TODOIST .. '/tasks/' .. urlenc(op.item) .. '/' .. op.op, method = 'POST', headers = headers(a, false), body = '' }
    end
    local base = GTASKS .. '/lists/' .. urlenc(op.list) .. '/tasks'
    if op.op == 'add' then
      return { url = base, method = 'POST', headers = headers(a, true), body = json_enc({ title = op.text }) }
    end
    local body = op.op == 'close' and '{"status":"completed"}' or '{"status":"needsAction","completed":null}'
    return { url = base .. '/' .. urlenc(op.item), method = 'PATCH', headers = headers(a, true), body = body }
  end

  -- the waiting changes in order; one the service refuses (404: deleted there) is dropped
  local function queue_ops(a)
    for _k, op in ipairs(pending) do
      if op.acc == a.id then
        queue[#queue + 1] = { acc = a.id, fn = function()
          local function go()
            send(op_request(a, op), function(res)
              if offline(res) then return false end
              if res.status == 401 or res.status == 403 then
                if a.src == 'google' and not op.retried then
                  op.retried, a.g_access = true, nil
                  table.insert(queue, 1, { acc = a.id, fn = function() google_token(a, go) end })
                  return
                end
                if a.src == 'ticktick' and not op.retried and (a.tt_refresh or '') ~= '' then
                  op.retried = true
                  table.insert(queue, 1, { acc = a.id, fn = function() ticktick_token(a, go, true) end })
                  return
                end
                fail(a, 'the token was not accepted')
                return false
              end
              for i, p in ipairs(pending) do if p == op then table.remove(pending, i); break end end
              op.retried = nil
              save_lists()
              if res.status >= 400 and res.status ~= 429 then errors[a.id] = 'refused a change (HTTP ' .. res.status .. ')' end
            end)
          end
          if a.src == 'google' then google_token(a, go)
          elseif a.src == 'ticktick' then ticktick_token(a, go)
          else go() end
        end }
      end
    end
  end

  ------------------------------------------------------------------ fetching

  -- items in order with each one's sub-items under it (depth 1, deeper ones as 2); done_last: the
  -- completed top-level items (with theirs) after the open ones, as Google Tasks shows them
  local function tree(raw, key_of, done_last)
    table.sort(raw, function(x, y)
      if done_last and x.done ~= y.done and not x.parent and not y.parent then return y.done end
      return key_of(x) < key_of(y)
    end)
    local kids, tops = {}, {}
    local ids = {}
    for _k, t in ipairs(raw) do ids[t.rid] = true end
    for _k, t in ipairs(raw) do
      if t.parent and ids[t.parent] then
        kids[t.parent] = kids[t.parent] or {}
        table.insert(kids[t.parent], t)
      else tops[#tops + 1] = t end
    end
    local out = {}
    local function add(t, depth)
      out[#out + 1] = { text = t.text, done = t.done, rid = t.rid, depth = math.min(depth, 2), due = t.due, rec = t.rec }
      for _k, c in ipairs(kids[t.rid] or {}) do add(c, depth + 1) end
    end
    for _k, t in ipairs(tops) do add(t, 0) end
    return out
  end

  local function todoist_due(d)
    if type(d) ~= 'table' then return nil, nil end
    local date = str(d.date)
    return date and date:sub(1, 10) or nil, (d.is_recurring == true) and str(d.string) or nil
  end

  local function queue_todoist(a)
    local projects, tasks = {}, {}
    local function page(path, sink, cursor, done_fn)
      local url = TODOIST .. path .. '?limit=50' .. (cursor and ('&cursor=' .. urlenc(cursor)) or '')
      send({ url = url, headers = headers(a, false) }, function(res)
        if offline(res) then return false end
        if res.status == 401 or res.status == 403 then fail(a, 'the token was not accepted') return false end
        local d = json_dec(res.body)
        if res.status ~= 200 or type(d) ~= 'table' then fail(a, 'HTTP ' .. tostring(res.status)) return false end
        for _k, x in ipairs(type(d.results) == 'table' and d.results or {}) do sink[#sink + 1] = x end
        local nxt = str(d.next_cursor)
        if nxt and nxt ~= '' and #sink < 2000 then
          table.insert(queue, 1, { acc = a.id, fn = function() page(path, sink, nxt, done_fn) end })
        else
          done_fn()
        end
      end)
    end
    queue[#queue + 1] = { acc = a.id, fn = function() page('/projects', projects, nil, function() end) end }
    queue[#queue + 1] = { acc = a.id, fn = function()
      page('/tasks', tasks, nil, function()
        local by = {}
        for _k, t in ipairs(tasks) do
          local pid = str(t.project_id)
          if pid and type(t.content) == 'string' then
            by[pid] = by[pid] or {}
            local due, rec = todoist_due(t.due)
            table.insert(by[pid], { text = t.content, done = t.checked == true, rid = str(t.id), parent = str(t.parent_id),
                                    order = tonumber(t.child_order) or 0, due = due, rec = rec })
          end
        end
        local ps = {}
        for _k, p in ipairs(projects) do if p.is_archived ~= true and type(p.name) == 'string' then ps[#ps + 1] = p end end
        table.sort(ps, function(x, y)
          if (x.inbox_project == true) ~= (y.inbox_project == true) then return x.inbox_project == true end
          return (tonumber(x.child_order) or 0) < (tonumber(y.child_order) or 0)
        end)
        for _k, p in ipairs(ps) do
          local pid = str(p.id)
          fresh[#fresh + 1] = { acc = a.id, src = 'todoist', rid = pid, name = p.name,
                                items = tree(by[pid] or {}, function(t) return t.order end) }
        end
        got[a.id] = true
      end)
    end }
  end

  -- local time: the clock's wall time against its epoch (as main.lua's local_day)
  local function utc_offset()
    local e, t = now_sec()
    if not t or not tonumber(t.hour) then return 0 end
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    return math.floor(off / 900 + 0.5) * 900
  end

  local function days_from_civil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m > 2 and m - 3 or m + 9) + 2) // 5 + d - 1
    return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
  end
  local function civil(z)
    z = z + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local m = mp < 10 and mp + 3 or mp - 9
    return yoe + era * 400 + (m <= 2 and 1 or 0), m, doy - (153 * mp + 2) // 5 + 1
  end

  -- "2026-11-11T21:00:00.000+0000" -> the local day "2026-11-12"
  local function ticktick_day(s, offset)
    local y, mo, d, h, mi, sg, hh, mm = (s or ''):match('^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)[%.%d]*([%+%-]%d%d):?(%d%d)')
    if not y then return nil end
    local tz = tonumber(hh) * 3600 + (hh:sub(1, 1) == '-' and -1 or 1) * tonumber(mm) * 60
    local sec = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(sg) - tz
    local ly, lm, ld = civil((sec + offset) // 86400)
    return string.format('%04d-%02d-%02d', ly, lm, ld)
  end

  -- "RRULE:FREQ=WEEKLY;INTERVAL=2" -> "every 2 weeks"
  local function ticktick_repeat(r)
    local f = (r or ''):match('FREQ=(%u+)')
    local unit = ({ DAILY = 'day', WEEKLY = 'week', MONTHLY = 'month', YEARLY = 'year' })[f or '']
    if not unit then return f and 'repeats' or nil end
    local n = tonumber((r:match('INTERVAL=(%d+)'))) or 1
    return n == 1 and ('every ' .. unit) or ('every ' .. n .. ' ' .. unit .. 's')
  end

  local function queue_ticktick(a)
    local projects = {}
    local offset = utc_offset()
    local function api(url, then_fn, quiet, retried)
      send({ url = url, headers = headers(a, false) }, function(res)
        if offline(res) then return false end
        if (res.status == 401 or res.status == 403) and not retried and (a.tt_refresh or '') ~= '' then
          table.insert(queue, 1, { acc = a.id, fn = function() ticktick_token(a, function() api(url, then_fn, quiet, true) end, true) end })
          return
        end
        local d = json_dec(res.body)
        if res.status ~= 200 or type(d) ~= 'table' then
          if quiet then return end              -- an Inbox the API does not give: left out
          fail(a, (res.status == 401 or res.status == 403) and 'the token was not accepted (it may have run out: see the README)'
                  or ('HTTP ' .. tostring(res.status)))
          return false
        end
        then_fn(d)
      end)
    end
    queue[#queue + 1] = { acc = a.id, fn = function()
      ticktick_token(a, function()
        api(TICKTICK .. '/project', function(d)
          projects[#projects + 1] = { id = 'inbox', name = 'Inbox' }
          for _k, p in ipairs(d) do
            if type(p) == 'table' and str(p.id) and type(p.name) == 'string' and p.closed ~= true then
              projects[#projects + 1] = { id = str(p.id), name = p.name, order = tonumber(p.sortOrder) or 0 }
            end
          end
          -- each project's open tasks, then the lists put together
          table.insert(queue, 1, { acc = a.id, fn = function()
            for _k, p in ipairs(projects) do
              if p.items then fresh[#fresh + 1] = { acc = a.id, src = 'ticktick', rid = p.id, name = p.name, items = p.items } end
            end
            got[a.id] = true
            run_next()
          end })
          for i = #projects, 1, -1 do
            local p = projects[i]
            table.insert(queue, 1, { acc = a.id, fn = function()
              api(TICKTICK .. '/project/' .. urlenc(p.id) .. '/data', function(pd)
                local raw = {}
                for _k, t in ipairs(type(pd.tasks) == 'table' and pd.tasks or {}) do
                  if type(t) == 'table' and type(t.title) == 'string' and t.title:match('%S') then
                    raw[#raw + 1] = { text = t.title, done = tonumber(t.status) == 2, rid = str(t.id), parent = str(t.parentId),
                                      order = tonumber(t.sortOrder) or 0, due = ticktick_day(str(t.dueDate), offset),
                                      rec = ticktick_repeat(str(t.repeatFlag)) }
                  end
                end
                p.items = tree(raw, function(t) return t.order end)
              end, p.id == 'inbox')
            end })
          end
        end)
      end)
    end }
  end

  local function queue_google(a)
    local glists = {}
    local function api(url, then_fn, retried)
      send({ url = url, headers = headers(a, false) }, function(res)
        if offline(res) then return false end
        if res.status == 401 and not retried then
          a.g_access = nil
          table.insert(queue, 1, { acc = a.id, fn = function() google_token(a, function() api(url, then_fn, true) end) end })
          return
        end
        local d = json_dec(res.body)
        if res.status ~= 200 or type(d) ~= 'table' then
          fail(a, (res.status == 401 or res.status == 403) and 'the token was not accepted' or ('HTTP ' .. tostring(res.status)))
          return false
        end
        then_fn(d)
      end)
    end
    local function list_page(token)
      api(GTASKS .. '/users/@me/lists?maxResults=100&fields=' .. urlenc('items(id,title),nextPageToken') ..
          (token and ('&pageToken=' .. urlenc(token)) or ''), function(d)
        for _k, x in ipairs(type(d.items) == 'table' and d.items or {}) do
          if str(x.id) then glists[#glists + 1] = { id = str(x.id), title = str(x.title) or 'Tasks' } end
        end
        local nxt = str(d.nextPageToken)
        if nxt then table.insert(queue, 1, { acc = a.id, fn = function() list_page(nxt) end }); return end
        -- then every list's tasks, then the lists put together (all before what was queued after)
        table.insert(queue, 1, { acc = a.id, fn = function()
          for _k, gl in ipairs(glists) do
            fresh[#fresh + 1] = { acc = a.id, src = 'google', rid = gl.id, name = gl.title, items = gl.items or {} }
          end
          got[a.id] = true
          run_next()
        end })
        for i = #glists, 1, -1 do
          local gl = glists[i]
          local items = {}
          local function task_page(tok)
            api(GTASKS .. '/lists/' .. urlenc(gl.id) .. '/tasks?maxResults=100&showCompleted=true&showHidden=false&fields=' ..
                urlenc('items(id,title,status,parent,position,due),nextPageToken') .. (tok and ('&pageToken=' .. urlenc(tok)) or ''), function(t)
              for _k, x in ipairs(type(t.items) == 'table' and t.items or {}) do
                local title = str(x.title)
                if title and title:match('%S') then
                  items[#items + 1] = { text = title, done = x.status == 'completed', rid = str(x.id), parent = str(x.parent),
                                        order = str(x.position) or '', due = str(x.due) and str(x.due):sub(1, 10) or nil }
                end
              end
              local n2 = str(t.nextPageToken)
              if n2 and #items < 2000 then table.insert(queue, 1, { acc = a.id, fn = function() task_page(n2) end }); return end
              gl.items = tree(items, function(it) return it.order end, true)
            end)
          end
          table.insert(queue, 1, { acc = a.id, fn = function() task_page(nil) end })
        end
      end)
    end
    queue[#queue + 1] = { acc = a.id, fn = function() google_token(a, function() list_page(nil) end) end }
  end

  -- send the waiting changes, then fetch every list again; account by account
  function R.sync()
    if busy or not R.configured() then return end
    if not ctx.net then status = 'No network access'; return end
    busy, queue, fresh, got, errors = true, {}, {}, {}, {}
    status = 'Syncing...'
    pcall(function() ctx.net:keep_wifi(60000) end)
    for _k, a in ipairs(accounts) do
      if ready(a) then
        queue_ops(a)
        if a.src == 'todoist' then queue_todoist(a)
        elseif a.src == 'ticktick' then queue_ticktick(a)
        else queue_google(a) end
      end
    end
    queue[#queue + 1] = { fn = function()
      -- an account that failed keeps its old lists
      for _k, l in ipairs(rlists) do
        if not got[l.acc] and account(l.acc) then fresh[#fresh + 1] = l end
      end
      -- in the order of the accounts
      local order = {}
      for i, a in ipairs(accounts) do order[a.id] = i end
      local idx = {}
      for i, l in ipairs(fresh) do idx[l] = i end
      table.sort(fresh, function(x, y)
        local ox, oy = order[x.acc] or 99, order[y.acc] or 99
        if ox ~= oy then return ox < oy end
        return idx[x] < idx[y]
      end)
      rlists = fresh
      apply_pending()
      local failed = 0
      for _k in pairs(errors) do failed = failed + 1 end
      finish('Synced ' .. clock_label() .. (#pending > 0 and (', ' .. #pending .. ' waiting') or '') ..
             (failed > 0 and (', ' .. failed .. ' account' .. (failed == 1 and '' or 's') .. ' failed (Sources)') or ''))
    end }
    run_next()
  end

  -- a change made on the reader: shown at once, sent a moment later (several ticks go together)
  local function push(op)
    pending[#pending + 1] = op
    save_lists()
    env.changed()
    if flush_timer then return end
    flush_timer = true
    pcall(function() ctx:after(2500, function() flush_timer = false; R.sync() end) end)
  end

  function R.tick(l, it)
    if not it.rid then return end            -- an item added here and not synced yet
    it.done = not it.done
    -- untick before the tick was sent: the two cancel out
    for i, op in ipairs(pending) do
      if op.acc == l.acc and op.item == it.rid and (op.op == 'close' or op.op == 'reopen') then
        table.remove(pending, i)
        save_lists()
        env.changed()
        return
      end
    end
    push({ acc = l.acc, src = l.src, op = it.done and 'close' or 'reopen', list = l.rid, item = it.rid })
  end

  function R.add(l, text)
    l.items[#l.items + 1] = { text = text, done = false, depth = 0 }
    push({ acc = l.acc, src = l.src, op = 'add', list = l.rid, text = text })
  end

  if rawget(_G, '__TEST') then
    R.test = { accounts = function() return accounts end, pending = function() return pending end, urlenc = urlenc,
               errors = function() return errors end }
  end
  return R
end
