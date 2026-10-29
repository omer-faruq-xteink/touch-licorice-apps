-- Merchant for XTOS Licorice, API 2.9: the device screen for the game in merchant_game.lua.
-- The rules, the four themes and the translations come unchanged from merchant.koplugin
-- (KOReader); bundle.py puts them and this file into index.lua.
--
-- One board (day, place, money, health, the market) with buttons; everything else is a box over
-- it: a good's Buy / Sell, an amount chooser, travel, lender, bank, events, settings, game over.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H = 480, 800
local L10n = require('merchant_l10n')
local T = require('ffi/util').template
local Themes, MerchantGame, game
local settings = { lang = 'en', theme = 'silkroad' }
local best = {}             -- theme id -> best net worth
local modal = nil           -- { title, lines = {..}, rows = { { {label, fn, enabled}, .. }, .. }, cancel }
local status = ''
local ERR = nil

local LANGS = { { 'en', 'English' }, { 'de', 'Deutsch' }, { 'es', 'Español' }, { 'fr', 'Français' },
  { 'it', 'Italiano' }, { 'pt', 'Português' }, { 'tr', 'Türkçe' } }

-- strings this screen adds to the plugin's; the plugin's dictionaries cover the rest
local EXTRA = {
  tr = { ['Settings'] = 'Ayarlar', ['Scores'] = 'Skorlar', ['Language: %1'] = 'Dil: %1', ['OK'] = 'Tamam',
    ['Type'] = 'Yaz', ['Cash %1'] = 'Nakit %1', ['Bank %1 · Debt %2'] = 'Banka %1 · Borç %2',
    ['Day %1 / %2'] = 'Gün %1 / %2', ['you hold %1'] = 'elinde %1', ['Best scores'] = 'En iyi skorlar',
    ['none yet'] = 'henüz yok', ['Max'] = 'Tümü', ['Amount'] = 'Miktar',
    ['Tap a good to buy or sell it.'] = 'Almak ya da satmak için bir mala dokun.' },
}
local function _(s)
  local e = EXTRA[settings.lang]
  if e and e[s] then return e[s] end
  return L10n(s)
end

-- drop the last character, a whole UTF-8 sequence (the translations are not ASCII)
local function drop_last(s) return (s:gsub('[%z\1-\127\192-\255][\128-\191]*$', '')) end
-- at most n bytes, never cutting a character in two
local function short(s, n)
  s = tostring(s)
  if #s <= n then return s end
  local t = s:sub(1, n)
  while #t > n - 1 or (#t > 0 and t:sub(-1):byte() >= 128 and not utf8.len(t)) do t = drop_last(t) end
  return t .. '~'
end
local function refresh() pcall(function() ctx:invalidate() end) end
local function fmt(n) return MerchantGame.format(n) end

------------------------------------------------------------------ storage

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function write(name, s) pcall(function() ctx.storage:write(name, s) end) end

local function kv(s)
  local t = {}
  for k, v in (s or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = (v:gsub('%s+$', '')) end
  return t
end

-- the game as key=value lines: no JSON encoder needed, and a missing price stays missing
local function save()
  if not game then return end
  local st = game:serialize()
  local inv, pr = {}, {}
  for i = 1, #game.theme.goods do
    inv[i] = tostring(math.floor(st.inventory[i] or 0))
    pr[i] = st.prices[i] and tostring(math.floor(st.prices[i])) or ''
  end
  local p = ''
  if type(st.pending) == 'table' then
    local parts = {}
    for k, v in pairs(st.pending) do parts[#parts + 1] = k .. ':' .. tostring(v) end
    table.sort(parts)
    p = table.concat(parts, ';')
  end
  local loc_i = 1
  for i, l in ipairs(game.theme.locations) do if l == st.location then loc_i = i end end
  write('game.txt', table.concat({
    'theme=' .. st.theme, 'day=' .. st.day, 'cash=' .. math.floor(st.cash), 'debt=' .. math.floor(st.debt),
    'bank=' .. math.floor(st.bank), 'weapons=' .. st.weapons, 'health=' .. st.health, 'capacity=' .. st.capacity,
    'location=' .. loc_i, 'inventory=' .. table.concat(inv, ','), 'prices=' .. table.concat(pr, ','),
    'pending=' .. p, 'game_over=' .. (st.game_over and '1' or '0'),
  }, '\n'))
end

local function load_saved()
  local t = kv(read('game.txt'))
  if not t.day then return false end
  local theme = Themes.get(t.theme)
  local function list(s)
    local out, i = {}, 0
    for v in ((s or '') .. ','):gmatch('([^,]*),') do i = i + 1; out[i] = tonumber(v) end
    return out
  end
  local pending = nil
  if t.pending and t.pending ~= '' then
    pending = {}
    for k, v in t.pending:gmatch('([%w_]+):([^;]*)') do pending[k] = tonumber(v) or v end
  end
  local inv = list(t.inventory)
  for i = 1, #theme.goods do inv[i] = inv[i] or 0 end
  return game:load({
    theme = theme.id, day = tonumber(t.day), cash = tonumber(t.cash), debt = tonumber(t.debt),
    bank = tonumber(t.bank), weapons = tonumber(t.weapons), health = tonumber(t.health),
    capacity = tonumber(t.capacity), location = theme.locations[tonumber(t.location) or 1],
    inventory = inv, prices = list(t.prices), pending = pending, game_over = t.game_over == '1',
  })
end

local function save_settings() write('settings.txt', 'lang=' .. settings.lang .. '\ntheme=' .. settings.theme) end
local function save_best()
  local lines = {}
  for id, v in pairs(best) do lines[#lines + 1] = id .. '=' .. math.floor(v) end
  table.sort(lines)
  write('scores.txt', table.concat(lines, '\n'))
end
local function record_score(net)
  local id = game.theme.id
  if not best[id] or net > best[id] then best[id] = net; save_best() end
  return best[id]
end

-- the game modules hold their translated strings from when they were loaded: a new language
-- reloads them and carries the game over (the place by its position in the list)
local function load_modules()
  L10n.set(settings.lang)
  Themes = require('merchant_themes')
  MerchantGame = require('merchant_game')
end
local function switch_language(lang)
  local st = game and game:serialize()
  local loc_i = 1
  if game then for i, l in ipairs(game.theme.locations) do if l == game.location then loc_i = i end end end
  settings.lang = lang
  save_settings()
  __unload('merchant_')
  load_modules()
  local ng = MerchantGame:new(Themes.get(settings.theme))
  if st then
    st.location = Themes.get(st.theme).locations[loc_i]
    ng:load(st)
  end
  game = ng
  save()
end

------------------------------------------------------------------ text

local function font(name) return ctx.fonts and ctx.fonts[name] end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end
local function line_h(name)
  local ok, h = pcall(function() return font(name).line_height end)
  return (ok and tonumber(h)) or (name == 'large' and 30 or name == 'small' and 20 or 24)
end

-- word-wrap s (with \n breaks) to width in a font
local function wrap(s, fname, maxw)
  local f, out = font(fname), {}
  for para in (tostring(s) .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    -- split on ASCII spaces only: with some C libraries %s also matches byte 0xA0, the second
    -- byte of "à" (C3 A0), and would cut the letter in two
    for word in para:gmatch('[^ \t]+') do
      local cand = line == '' and word or (line .. ' ' .. word)
      if line ~= '' and width(f, cand) > maxw then out[#out + 1] = line; line = word else line = cand end
    end
    out[#out + 1] = line
  end
  return out
end

------------------------------------------------------------------ boxes

local BOX_X, BOX_W, ROW_H, GAP = 20, W - 40, 56, 10

-- lay a box out: its text lines, then rows of buttons; returns lines, buttons, y, h
local function layout_modal(m)
  local lines = {}
  if m.title then for _k, l in ipairs(wrap(m.title, 'medium', BOX_W - 40)) do lines[#lines + 1] = { l, 'medium' } end end
  for _k, s in ipairs(m.lines or {}) do
    for _k, l in ipairs(wrap(s, m.big and 'large' or 'small', BOX_W - 40)) do lines[#lines + 1] = { l, m.big and 'large' or 'small' } end
  end
  local th = 0
  for _k, l in ipairs(lines) do th = th + line_h(l[2]) + 4 end
  local h = 20 + th + 14 + #m.rows * (ROW_H + GAP) + 10
  -- under the board's top lines (day, place, money) when it fits, else as high as needed
  local y = math.max(150, math.floor((H - h) / 2))
  if y + h > H - 30 then y = math.max(10, H - 30 - h) end
  local btns, by = {}, y + 20 + th + 14
  for _k, row in ipairs(m.rows) do
    local n = #row
    local bw = math.floor((BOX_W - 40 - (n - 1) * GAP) / n)
    for k, btn in ipairs(row) do
      btns[#btns + 1] = { x = BOX_X + 20 + (k - 1) * (bw + GAP), y = by, w = bw, h = ROW_H, b = btn }
    end
    by = by + ROW_H + GAP
  end
  return lines, btns, y, h
end

local function draw_modal(gg)
  local lines, btns, y, h = layout_modal(modal)
  gg:rect(BOX_X, y, BOX_W, h)
  gg:rect(BOX_X + 3, y + 3, BOX_W - 6, h - 6)
  local ty = y + 20
  for _k, l in ipairs(lines) do gg:text(BOX_X + 20, ty, l[1], { font = font(l[2]) }); ty = ty + line_h(l[2]) + 4 end
  for _k, bt in ipairs(btns) do
    local enabled = bt.b[3] ~= false
    gg:rect(bt.x, bt.y, bt.w, bt.h, { line_width = enabled and 2 or 1 })
    local f = font('medium')
    local label = tostring(bt.b[1])
    while #label > 1 and width(f, label) > bt.w - 12 do label = drop_last(label) end
    local tx = bt.x + math.floor((bt.w - width(f, label)) / 2)
    gg:text(tx, bt.y + 15, enabled and label or ('(' .. label .. ')'), { font = f })
  end
end

local function show(m) modal = m; refresh() end
local function close_modal() modal = nil end

-- a message box; then() runs after OK
local function info(lines, after)
  if type(lines) == 'string' then lines = { lines } end
  if not lines or #lines == 0 then if after then after() end return end
  show({ lines = lines, rows = { { { _('OK'), function() close_modal(); if after then after() end end } } },
    cancel = function() close_modal(); if after then after() end end })
end

-- amount chooser: value from 1 to max, steps by a tenth of the size and its tenth, quarters,
-- the maximum, or typed with the firmware keyboard; apply(v) on OK
local function choose_amount(title, max, apply, money, ok_label)
  max = math.floor(max or 0)
  if max < 1 then info(_('Nothing to do here right now.')); return end
  local v = max
  local digits = #tostring(max)
  local small = math.max(1, math.floor(10 ^ math.max(0, digits - 2)))
  local big = small * 10
  local m
  local function set(x) v = math.max(1, math.min(max, math.floor(x))); m.lines[2] = money and game:money(v) or fmt(v) end
  m = {
    title = title, lines = { T(_('Up to %1'), money and game:money(max) or fmt(max)), '' }, big = false,
    rows = {
      { { '-' .. fmt(big), function() set(v - big) end }, { '-' .. fmt(small), function() set(v - small) end },
        { '+' .. fmt(small), function() set(v + small) end }, { '+' .. fmt(big), function() set(v + big) end } },
      { { '1/4', function() set(max / 4) end }, { '1/2', function() set(max / 2) end },
        { _('Max'), function() set(max) end }, { _('Type'), function()
          pcall(function()
            ctx.input:text({ title = title, text = tostring(v) }, function(c, s)
              local n = tonumber((tostring(s or ''):gsub('[^%d]', '')))
              if n then set(n) end
              refresh()
            end)
          end)
        end } },
      { { ok_label or title, function() close_modal(); apply(v); save() end }, { _('Cancel'), close_modal } },
    },
    cancel = close_modal,
  }
  set(v)
  show(m)
end

------------------------------------------------------------------ turns and events

local game_over_box, handle_pending

local function check_over(dead)
  if game.game_over or dead then game_over_box(dead) end
end

handle_pending = function()
  local p = game.pending
  if not p then check_over(); return end
  local th = game.theme
  if p.type == 'enemy' then
    show({
      lines = { T(th.enemy_title, p.count, game.health, game.weapons) },
      rows = { { { th.fight_label, function()
                   close_modal()
                   local res = game:fight(); save()
                   info(res.messages, function() if res.dead then check_over(true) elseif not res.ended then handle_pending() else check_over() end end)
                 end, game.weapons > 0 },
                 { th.flee_label, function()
                   close_modal()
                   local res = game:flee(); save()
                   info(res.messages, function() if res.dead then check_over(true) elseif not res.ended then handle_pending() else check_over() end end)
                 end } } },
    })
  else
    local prompt = p.type == 'weapon' and T(th.weapon_offer, game:money(p.price)) or T(th.capacity_offer, p.slots, game:money(p.price))
    show({
      lines = { prompt },
      rows = { { { _('Buy'), function()
                   close_modal()
                   local _ok, msg = game:acceptOffer(); save()
                   info(msg and { msg } or {}, check_over)
                 end },
                 { _('No thanks'), function() close_modal(); game:declineOffer(); save(); check_over() end } } },
    })
  end
end

game_over_box = function(dead)
  local net = game:netWorth()
  local high = record_score(net)
  local headline = dead and game.theme.busted_msg or _('30 days are up.')
  show({
    lines = { T(_('%1\n\nFinal net worth: %2\nBest ever: %3'), headline, game:money(net), game:money(high)) },
    rows = { { { _('New game'), function() close_modal(); game:newGame(Themes.get(settings.theme)); save() end } } },
  })
end

local function travel_to(dest)
  close_modal()
  local messages = game:travel(dest)
  save()
  info(messages, handle_pending)
end

------------------------------------------------------------------ actions

local function trade(i)
  local good = game:getGoods()[i]
  local price = game.prices[i]
  local held = game.inventory[i] or 0
  local can_buy = game:hasPrice(i) and game:maxBuy(i) > 0
  local can_sell = game:hasPrice(i) and held > 0
  show({
    title = good.name,
    lines = {
      price and T(_('%1 each · cash %2 · room %3'), game:money(price), game:money(game.cash), game:spaceLeft()) or _('(no buyers)'),
      held > 0 and T(_('you hold %1'), held) or nil,
    },
    rows = {
      { { _('Buy'), function()
          close_modal()
          choose_amount(T(_('Buy %1'), good.name), game:maxBuy(i), function(v)
            local ok, err = game:buy(i, v); if not ok then status = err or _('Couldn\'t buy.') end
          end, false, _('Buy'))
        end, can_buy },
        { _('Sell'), function()
          close_modal()
          choose_amount(T(_('Sell %1'), good.name), held, function(v)
            local ok, err = game:sell(i, v); if not ok then status = err or _('Couldn\'t sell.') end
          end, false, _('Sell'))
        end, can_sell } },
      { { _('Cancel'), close_modal } },
    },
    cancel = close_modal,
  })
end

local function travel_box()
  local rows = {}
  for _k, loc in ipairs(game:getLocations()) do
    if loc ~= game.location then rows[#rows + 1] = { { loc, function() travel_to(loc) end } } end
  end
  rows[#rows + 1] = { { _('Stay'), close_modal } }
  show({ title = game.theme.travel_prompt, rows = rows, cancel = close_modal })
end

local function lender_box()
  show({
    title = T(game.theme.lender_title, game:money(game.debt)),
    rows = {
      { { _('Pay back'), function()
          close_modal(); choose_amount(_('Pay back'), math.min(game.cash, game.debt), function(v) game:payDebt(v) end, true)
        end, game.debt > 0 and game.cash > 0 },
        { _('Borrow'), function()
          close_modal(); choose_amount(_('Borrow'), math.max(1000, game.cash * 2 + 1000), function(v) game:borrow(v) end, true)
        end } },
      { { _('Cancel'), close_modal } },
    },
    cancel = close_modal,
  })
end

local function bank_box()
  show({
    title = T(game.theme.bank_title, game:money(game.bank)),
    rows = {
      { { _('Deposit'), function()
          close_modal(); choose_amount(_('Deposit'), game.cash, function(v) game:deposit(v) end, true)
        end, game.cash > 0 },
        { _('Withdraw'), function()
          close_modal(); choose_amount(_('Withdraw'), game.bank, function(v) game:withdraw(v) end, true)
        end, game.bank > 0 } },
      { { _('Cancel'), close_modal } },
    },
    cancel = close_modal,
  })
end

local function lang_name(code) for _k, l in ipairs(LANGS) do if l[1] == code then return l[2] end end return code end

local settings_box
settings_box = function()
  local theme = Themes.get(settings.theme)
  show({
    title = _('Settings'),
    lines = { _('The new theme starts with your next new game; the current run keeps its theme.') },
    rows = {
      { { T(_('Theme: %1'), theme.name), function()
          local list, nxt = Themes.list, 1
          for k, t in ipairs(list) do if t.id == settings.theme then nxt = k % #list + 1 end end
          settings.theme = list[nxt].id
          save_settings()
          settings_box()
        end } },
      { { T(_('Language: %1'), lang_name(settings.lang)), function()
          local nxt = 1
          for k, l in ipairs(LANGS) do if l[1] == settings.lang then nxt = k % #LANGS + 1 end end
          switch_language(LANGS[nxt][1])
          settings_box()
        end } },
      { { _('Close'), close_modal } },
    },
    cancel = close_modal,
  })
end

local function scores_box()
  local lines = {}
  for _k, t in ipairs(Themes.list) do
    lines[#lines + 1] = t.name .. ': ' .. (best[t.id] and T(t.money, fmt(best[t.id])) or _('none yet'))
  end
  show({ title = _('Best scores'), lines = lines, rows = { { { _('Close'), close_modal } } }, cancel = close_modal })
end

local function new_game_box()
  show({
    title = _('Start a new game? Current progress is lost.'),
    rows = { { { _('New game'), function() close_modal(); game:newGame(Themes.get(settings.theme)); save() end },
               { _('Cancel'), close_modal } } },
    cancel = close_modal,
  })
end

------------------------------------------------------------------ board

local MARKET_Y, ROW, BTN_Y = 186, 72, 632

local function bottom_buttons()
  local th = game.theme
  return {
    { th.travel_label, travel_box }, { th.lender_label, lender_box }, { th.bank_label, bank_box },
    { _('New game'), new_game_box }, { _('Settings'), function() settings_box() end }, { _('Scores'), scores_box },
  }
end
local function button_rect(k)
  local bw = math.floor((W - 16 - 2 * 8) / 3)
  local r, c = (k - 1) // 3, (k - 1) % 3
  return 8 + c * (bw + 8), BTN_Y + r * 68, bw, 58
end

local function draw_board(gg, top_only)
  local th = game.theme
  gg:text(16, 10, short(game.location, 30), { font = font('large') })
  local day = T(_('Day %1 / %2'), math.min(game.day, MerchantGame.MAX_DAYS), MerchantGame.MAX_DAYS)
  gg:text(W - 16 - width(font('medium'), day), 14, day, { font = font('medium') })
  gg:text(16, 52, T(_('Cash %1'), game:money(game.cash)), { font = font('medium') })
  gg:text(16, 84, short(T(_('Bank %1 · Debt %2'), game:money(game.bank), game:money(game.debt)), 48), { font = font('small') })
  gg:text(16, 110, short(T(_('Health %1     %2 %3     %4 %5/%6'), game.health, th.weapon_label, game.weapons,
    th.capacity_label, game:spaceUsed(), game.capacity), 48), { font = font('small') })
  gg:line(0, 142, W, 142)
  if top_only then return end      -- a box is open: it takes the rest of the screen
  gg:text(16, 152, short(th.market_title, 48), { font = font('small') })
  for i, good in ipairs(game:getGoods()) do
    local y = MARKET_Y + (i - 1) * ROW
    local price = game.prices[i]
    local ps = price and game:money(price) or _('(none)')
    gg:text(16, y + 6, short(good.name, 22), { font = font('medium') })
    gg:text(W - 16 - width(font('medium'), ps), y + 6, ps, { font = font('medium') })
    local held = game.inventory[i] or 0
    if held > 0 then gg:text(16, y + 36, T(_('you hold %1'), held), { font = font('small') }) end
    gg:line(16, y + ROW - 4, W - 16, y + ROW - 4)
  end
  for k, b in ipairs(bottom_buttons()) do
    local x, y, bw, bh = button_rect(k)
    gg:rect(x, y, bw, bh)
    local f = font('small')
    local label = tostring(b[1])
    while #label > 1 and width(f, label) > bw - 10 do label = drop_last(label) end
    gg:text(x + math.floor((bw - width(f, label)) / 2), y + 18, label, { font = f })
  end
  local s = status ~= '' and status or _('Tap a good to buy or sell it.')
  gg:text(16, H - 26, short(s, 52), { font = font('small') })
  if ERR then gg:text(16, H - 48, short('ERR ' .. ERR, 52), { font = font('small') }) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    draw_board(gg, modal ~= nil)
    if modal then draw_modal(gg) end
  end)
  if not ok then pcall(function() gg:text(8, H - 70, short('draw ERR ' .. tostring(e), 46)) end) end
end

local KEY_GAP_MS = 250
local last_key, last_key_ms = nil, nil
local function key_accepted(ev)
  local ph = ev.phase or ev.action or ev.state
  if ph == 'up' or ph == 'release' or ph == 'released' or ev.pressed == false or ev.down == false then return false end
  local now = tonumber(ev.time_ms)
  if not now then local ok, m = pcall(function() return ctx.clock:millis() end); now = ok and tonumber(m) or nil end
  if now and last_key == ev.key and last_key_ms and now - last_key_ms >= 0 and now - last_key_ms < KEY_GAP_MS then return false end
  last_key, last_key_ms = ev.key, now
  return true
end

local function tap(x, y)
  if modal then
    local _l, btns, my, mh = layout_modal(modal)
    for _k, bt in ipairs(btns) do
      if x >= bt.x and x < bt.x + bt.w and y >= bt.y and y < bt.y + bt.h then
        if bt.b[3] ~= false then bt.b[2]() end
        return
      end
    end
    if (y < my or y > my + mh or x < BOX_X or x > BOX_X + BOX_W) and modal.cancel then modal.cancel() end
    return
  end
  status = ''
  for k, b in ipairs(bottom_buttons()) do
    local bx, by, bw, bh = button_rect(k)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then b[2](); return end
  end
  if y >= MARKET_Y and y < MARKET_Y + #game:getGoods() * ROW then trade(math.floor((y - MARKET_Y) / ROW) + 1) end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and key_accepted(ev) and ev.key == 'back' and modal and modal.cancel then modal.cancel() end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_load(c)
  local s = kv(read('settings.txt'))
  if s.lang then settings.lang = s.lang end
  if s.theme then settings.theme = s.theme end
  for id, v in pairs(kv(read('scores.txt'))) do best[id] = tonumber(v) end
  load_modules()
  game = MerchantGame:new(Themes.get(settings.theme))
  if not load_saved() then game:newGame(Themes.get(settings.theme)); save() end
  if game.game_over then game_over_box() elseif game.pending then handle_pending() end
end

function on_leave() save() end
