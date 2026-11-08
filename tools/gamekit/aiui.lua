-- The optional AI questions' screens for the reading apps built like RSS (RSS, Instapaper,
-- Readwise, wallabag): Settings → AI (aiset), the Service list (aiprov), your own buttons
-- (aibtns), the ready questions (aimenu) and the conversation (chat). ai.lua does the requests and answers; this does the
-- screens, drawn with the app's own helpers, which the app hands over in E:
--
--   cfg, save(), note(s), refresh(), submit(opts, label, timeout_ms, fn(resp, err)), keep_wifi(),
--   wrap(out, text, font_name, width, indent) (the app's wrap_para), style() ({ head, body, meta }),
--   bar(gg, labels), bar_hit(x, n), cell(i, y0, row_h, h), fit(s, font, w), short(s, n),
--   draw_status(gg), busy(), status() (the status line's text), dims() (W, H, TOP),
--   get_screen(), set_screen(s), article() ({ id, title, feed, date, url, text } of the article
--   open, or nil while it loads), folder (e.g. 'AppFiles/rss'), what (e.g. 'an article').
--
-- The app's article bar shows an AI button only when M.on(); Settings shows an AI cell
-- (M.value(), M.open_settings()). Its draw / tap / Back / paging pass to M while M.handles(screen).
-- Off (or not set up), nothing of it shows anywhere.

local A = require('ai')
local U = {}

function U.new(E)
  local M = {}
  local cfg = E.cfg
  local chat = { id = nil, msgs = {}, lines = {}, starts = { 1 }, page = 1, pages = 1, waiting = false }
  local SCREENS = { chat = true, aimenu = true, aiset = true, aiprov = true, aibtns = true }
  local web = false                                -- the web search switch: off for each new article
  local function dec(s) return ctx.json:decode(s) end
  local function enc(v) return ctx.json:encode(v) end
  local function F() return ctx.fonts end
  local function J()
    local extra, err = A.extra(cfg.aiextra, dec)
    if err then return nil, err end
    return { encode = enc, extra = extra, null = ctx.json.null }
  end

  function M.on() return A.ready(cfg) end
  function M.handles(s) return SCREENS[s] == true end
  function M.chat() return chat end

  -- an answer's text: headings, list items and paragraphs as in an article
  local function text_lines(out, text, S, W)
    for raw in (text .. '\n\n'):gmatch('(.-)\n\n') do
      local para = raw:gsub('^\n+', ''):gsub('\n+$', '')
      if para ~= '' then
        for line in (para .. '\n'):gmatch('([^\n]*)\n') do
          if line:sub(1, 2) == '# ' then E.wrap(out, line:sub(3), S.head, W - 24, 0)
          elseif line:sub(1, 4) == '• ' then E.wrap(out, line, S.body, W - 40, 16)
          elseif line ~= '' then E.wrap(out, line, S.body, W - 24, 0) end
        end
        out[#out + 1] = { s = '', f = 'small', h = 10, x = 0 }
      end
    end
  end

  -- to_last: show the page where the last message starts (a new question or answer)
  function M.layout(to_last)
    local W, H, TOP = E.dims()
    if E.reset then E.reset() end                    -- the app's measure cache
    local S, out, last_at = E.style(), {}, 1
    for _, m in ipairs(chat.msgs) do
      if m.role == 'user' then
        last_at = #out + 1                         -- a new answer opens at its question
        E.wrap(out, '» ' .. (m.label or m.text), S.meta, W - 48, 24)
        out[#out + 1] = { s = '', f = 'small', h = 12, x = 0 }
      else
        text_lines(out, A.plain(m.text), S, W)
        out[#out + 1] = { s = '', f = 'small', h = 6, x = 0, rule = true }
        out[#out + 1] = { s = '', f = 'small', h = 10, x = 0 }
      end
    end
    if chat.waiting then E.wrap(out, type(chat.waiting) == 'string' and chat.waiting or ('Asking ' .. A.prov(cfg).name .. '…'), 'small', W - 24, 0) end
    chat.lines, chat.starts = out, { 1 }
    local avail, used = H - TOP - 40, 0
    for i, ln in ipairs(out) do
      if used + ln.h > avail and used > 0 then chat.starts[#chat.starts + 1] = i; used = 0 end
      used = used + ln.h
    end
    -- a last page holding only an answer's closing rule and gaps is dropped (it showed empty)
    while #chat.starts > 1 do
      local blank = true
      for i = chat.starts[#chat.starts], #out do if out[i].s ~= '' then blank = false; break end end
      if not blank then break end
      for i = #out, chat.starts[#chat.starts], -1 do out[i] = nil end   -- its lines go too
      chat.starts[#chat.starts] = nil
    end
    chat.pages = #chat.starts
    if to_last then
      chat.page = 1
      for p, first in ipairs(chat.starts) do if first <= last_at then chat.page = p end end
    end
    chat.page = math.max(1, math.min(chat.page, chat.pages))
  end
  -- the screen turned: the conversation laid out again
  function M.relayout() if #chat.lines > 0 then M.layout(false) end end

  -- the AI button: the ready questions, or the conversation once there is one
  function M.open()
    local a = E.article()
    if not a then E.note('wait for the article'); return end
    if chat.id ~= a.id then chat = { id = a.id, msgs = {}, lines = {}, starts = { 1 }, page = 1, pages = 1, waiting = false }; web = false end
    A.buttons(true)                                  -- ai_buttons.txt may have changed over USB
    if #chat.msgs > 0 then M.layout(false); E.set_screen('chat') else E.set_screen('aimenu') end
  end

  -- a question: a ready one (label), or your own; with a web search while the switch is on, where
  -- the service has one (DeepSeek's comes first and goes along with the question)
  function M.ask(prompt, label)
    if chat.waiting then E.note('still waiting for the answer'); return end
    local c = chat
    local a = E.article() or {}
    local j, jerr = J()
    if not j then E.note(jerr); return end
    local web = web and A.web_ok(cfg)
    j.web = web and not A.web_first(cfg)
    c.msgs[#c.msgs + 1] = { role = 'user', text = prompt, label = (label or prompt) .. (web and ' (web search)' or '') }
    local name = A.prov(cfg).name
    local function fail(why)
      c.waiting = false
      if #c.msgs > 0 and c.msgs[#c.msgs].role == 'user' then table.remove(c.msgs) end   -- it can be asked again
      E.note('AI: ' .. E.short(why or 'no answer', 60))
      if c ~= chat then return end
      if #c.msgs == 0 and E.get_screen() == 'chat' then E.set_screen('aimenu') end
      M.layout(false)
    end
    local function send()
      local opts, err = A.request(cfg, { title = a.title, feed = a.feed, date = a.date, url = a.url, text = a.text, what = E.what }, c.msgs, j)
      if not opts then fail(err); return end
      c.waiting = 'Asking ' .. name .. (j.web and ', searching the web…' or '…')
      if c == chat then M.layout(true) end
      E.submit(opts, 'asking ' .. name .. '…', 60000, function(resp, nerr)
        local text, why
        if nerr then why = nerr else text, why = A.answer(cfg, resp, dec) end
        if not text then fail(why); return end
        c.waiting = false
        c.msgs[#c.msgs + 1] = { role = 'assistant', text = text }
        E.note('')
        if c == chat then M.layout(true) end
      end)
    end
    E.set_screen('chat')
    E.keep_wifi()
    if web and A.web_first(cfg) then
      -- DeepSeek: the model writes the search query, the app searches, the results go with the question
      local art = { title = a.title, feed = a.feed, date = a.date, url = a.url, text = a.text, what = E.what }   -- as send() gives it
      local function search(query)
        local opts, err = A.search_request(cfg, query, enc, prompt)
        if not opts then fail(err); return end
        c.waiting = 'Searching the web…'
        if c == chat then M.layout(true) end
        E.submit(opts, 'searching the web…', 30000, function(resp, nerr)
          local found, why
          if nerr then why = nerr else found, why = A.search_text(resp, dec) end
          if not found then fail(why); return end
          c.msgs[#c.msgs].text = prompt .. '\n\n' .. found
          send()
        end)
      end
      local qopts = A.query_request(cfg, art, c.msgs, j)
      c.waiting = 'Choosing what to search…'
      M.layout(true)
      if not qopts then search(A.query_text(cfg, nil, dec, art, prompt)); return end
      E.submit(qopts, 'choosing what to search…', 30000, function(resp, nerr)
        search(A.query_text(cfg, not nerr and resp or nil, dec, art, prompt))
      end)
    else
      c.waiting = true
      M.layout(true)
      send()
    end
  end

  -- your own question
  function M.ask_own()
    local ok, e = pcall(function()
      local title = (#chat.msgs > 0 and 'Ask more' or 'Ask about this article') .. ((web and A.web_ok(cfg)) and ' (with a web search)' or '')
      ctx.input:text({ title = title, text = '', max_bytes = 256 }, function(c, v)
        if type(v) == 'string' and v:match('%S') then M.ask((v:gsub('^%s+', ''):gsub('%s+$', ''))) end
        E.refresh()
      end)
    end)
    if not ok then E.note('edit ! ' .. E.short(e, 30)) end
  end

  local function items() return A.items(cfg, #chat.msgs > 0, nil, nil, web) end
  function M.web() return web end

  -- the connection test on the AI page: a one-word question, the answer in the status line
  function M.test()
    local j, jerr = J()
    if not j then E.note(jerr); return end
    local opts, err = A.request(cfg, A.TEST_ART, A.TEST_MSGS, j)
    if not opts then E.note('AI: ' .. tostring(err)); return end
    E.keep_wifi()
    E.submit(opts, 'testing ' .. A.prov(cfg).name .. '…', 60000, function(resp, nerr)
      local text, why
      if nerr then why = nerr else text, why = A.answer(cfg, resp, dec) end
      E.note(text and ('works: "' .. E.short(text, 30) .. '"') or ('AI: ' .. E.short(why or 'no answer', 60)))
    end)
  end

  -- ai.txt in the app's folder (USB): its settings are taken in and the file is deleted, so a
  -- long key need not be typed and does not stay on the card
  function M.import()
    local ok, s = pcall(function()
      if not (ctx.files and ctx.files:exists('ai.txt')) then return nil end
      return ctx.files:read('ai.txt', 0, 4096)
    end)
    if not (ok and A.take(cfg, s)) then return false end
    E.save()
    pcall(function() ctx.files:remove('ai.txt') end)
    E.note('AI settings taken from ai.txt (file deleted)')
    return true
  end

  -- Settings' AI cell: its value, and what a tap on it does
  function M.value() return M.on() and A.prov(cfg).name or (cfg.aion and 'not set up yet' or 'off') end
  function M.open_settings() M.import(); A.buttons(true); E.set_screen('aiset') end

  -- My buttons: a tap edits one as "Label | question" (emptied: deleted); Add a button adds one
  function M.edit_button(i)
    local list = {}
    for k, b in ipairs(A.buttons()) do list[k] = b end
    local cur = list[i]
    local ok, err = pcall(function()
      ctx.input:text({ title = cur and 'Label | question (empty: delete)' or 'New button: Label | question', text = cur and (cur.label .. ' | ' .. cur.q) or '',
                       max_bytes = 256 }, function(c, v)
        if type(v) == 'string' then
          local b = A.parse_button(v)
          if cur and not b then table.remove(list, i)
          elseif b and cur then list[i] = b
          elseif b and #list < A.BUTTONS_MAX then list[#list + 1] = b end
          if b or cur then
            local saved = A.save_buttons(list)
            if not saved then E.note('could not write ' .. A.BUTTONS_FILE) end
          end
        end
        E.refresh()
      end)
    end)
    if not ok then E.note('edit ! ' .. E.short(err, 30)) end
  end

  function M.edit(i)
    local s = A.SET[i]
    if not s then return end
    local k = s[1]
    if k == 'aion' then local m = A.toggle(cfg); E.save(); if m then E.note(m) end; return end
    if k == 'aiprov' then E.set_screen('aiprov'); return end
    if k == 'aitest' then M.test(); return end
    if k == 'aibtn' then A.buttons(true); E.set_screen('aibtns'); return end
    local title, start = A.field(cfg, k)
    local ok, err = pcall(function()
      ctx.input:text({ title = title, text = start, max_bytes = 256 }, function(c, v)
        if type(v) == 'string' then
          local stored, why = A.store(cfg, k, v, dec)
          if stored then E.save() else E.note(why) end
        end
        E.refresh()
      end)
    end)
    if not ok then E.note('edit ! ' .. E.short(err, 30)) end
  end

  -- the Service list: Ollama and Other ask for their address at once
  function M.choose(id)
    local need = A.choose(cfg, id)
    E.save()
    E.set_screen('aiset')
    if need then for i, s in ipairs(A.SET) do if s[1] == 'aiurl' then M.edit(i) end end end
  end

  ---------------------------------------------------------------- layout

  -- the AI page's cells: in portrait a short one shares its row with the next short one; in
  -- landscape every cell is a half; { x, row, w } each and the rows used
  local function grid()
    local W, H = E.dims()
    local out, row, col = {}, 0, 0
    local n = W > H and 3 or 2                     -- landscape: three columns
    local cw = (W - 32 - (n - 1) * 16) // n
    for i, s in ipairs(A.SET) do
      if W > H or A.HALF[s[1]] then
        if col == n then row, col = row + 1, 0 end
        out[i] = { 16 + col * (cw + 16), row, cw }
        col = col + 1
      else
        if col > 0 then row, col = row + 1, 0 end
        out[i] = { 16, row, W - 32 }
        row = row + 1
      end
    end
    return out, row + (col > 0 and 1 or 0)
  end
  local function set_rect(i)
    local _, _, TOP = E.dims()
    local r = grid()[i]
    return r[1], TOP + 20 + r[2] * 96, r[3], 96
  end
  local function prov_rect(i) local _, _, TOP = E.dims(); return E.cell(i, TOP + 16, 64, 54) end
  -- the ready questions: two a row (three in landscape), then your question, the web search and
  -- Start over in a new row of the same cells
  local function menu_cells()
    local W, H, TOP = E.dims()
    local n = W > H and 3 or 2
    local rh = W > H and 50 or 64
    local cw = (W - 32 - (n - 1) * 12) // n
    local out, col, y, prev = {}, 0, W > H and TOP + 50 or TOP + 80, nil
    for _, it in ipairs(items()) do
      if it[2] == 'web' then                        -- the switch, across the top
        out[#out + 1] = { x = 16, y = y, w = W - 32, h = rh - 10, item = it }; y = y + rh
      else
        local group = it[2] == 'ask' and 'ask' or 'tail'
        if prev and group ~= prev and col > 0 then col, y = 0, y + rh end
        out[#out + 1] = { x = 16 + col * (cw + 12), y = y, w = cw, h = rh - 10, item = it }
        col = col + 1
        if col == n then col, y = 0, y + rh end
        prev = group
      end
    end
    return out
  end
  local function btn_rect(i) local _, _, TOP = E.dims(); return E.cell(i, TOP + 56, 70, 58) end

  ---------------------------------------------------------------- drawing

  local function draw_set(gg)
    local W, H, TOP = E.dims()
    local f = F()
    E.bar(gg, { 'Back' })
    for i, s in ipairs(A.SET) do
      local x, y, w = set_rect(i)
      gg:text(x, y, E.fit(s[2], f and f.small, w), { font = f and f.small })
      gg:rect(x, y + 24, w, 48)
      gg:text(x + 12, y + 36, E.fit(A.value(cfg, s[1]), f and f.medium, w - 24), { font = f and f.medium })
    end
    if W <= H then
      local _, rows = grid()
      local y = TOP + 20 + rows * 96
      local path = (ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or E.folder
      for _, l in ipairs({ 'Off: no AI button anywhere. On: one in articles.', 'A long key: put ai.txt in ' .. path .. '/',
        'with lines service=deepseek, key=..., model=...;', 'the app takes it in and deletes the file.' }) do
        gg:text(16, y, l, { font = f and f.small }); y = y + 22
      end
    end
    E.draw_status(gg)
  end

  local function draw_prov(gg)
    local f = F()
    E.bar(gg, { 'Back' })
    local cur = A.prov(cfg).id
    for i, P in ipairs(A.PROVIDERS) do
      local x, y, w, h = prov_rect(i)
      gg:rect(x, y, w, h)
      if P.id == cur then gg:rect(x + 3, y + 3, w - 6, h - 6) end
      gg:text(x + 20, y + 14, E.fit(P.label, f and f.medium, w - 40), { font = f and f.medium })
    end
    E.draw_status(gg)
  end

  local function draw_menu(gg)
    local W, H, TOP = E.dims()
    local f = F()
    local a = E.article()
    E.bar(gg, { 'Back' })
    gg:text(16, TOP + 10, 'Ask ' .. A.prov(cfg).name, { font = f and f.large })
    if W <= H then gg:text(16, TOP + 46, E.fit(a and a.title or '', f and f.small, W - 32), { font = f and f.small }) end
    for _, c in ipairs(menu_cells()) do
      gg:rect(c.x, c.y, c.w, c.h)
      if c.item[2] == 'web' and web then gg:rect(c.x + 3, c.y + 3, c.w - 6, c.h - 6) end   -- on: a double frame
      gg:text(c.x + 12, c.y + (c.h - 24) // 2, E.fit(c.item[1], f and f.medium, c.w - 24), { font = f and f.medium })
    end
    E.draw_status(gg)
  end

  local function draw_btns(gg)
    local W, H, TOP = E.dims()
    local f = F()
    E.bar(gg, { 'Back' })
    gg:text(16, TOP + 10, 'My buttons', { font = f and f.large })
    local list = A.buttons()
    local n = #list + (#list < A.BUTTONS_MAX and 1 or 0)
    for i = 1, n do
      local x, y, w, h = btn_rect(i)
      gg:rect(x, y, w, h)
      local b = list[i]
      if b then
        gg:text(x + 12, y + 6, E.fit(b.label, f and f.medium, w - 24), { font = f and f.medium })
        gg:text(x + 12, y + 32, E.fit(b.q, f and f.small, w - 24), { font = f and f.small })
      else
        gg:text(x + 12, y + 16, 'Add a button', { font = f and f.medium })
      end
    end
    if W <= H then
      local _, y = btn_rect(n + 1)
      local path = (ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or E.folder
      for _, l in ipairs({ 'They come after the ready questions. Tap one to', 'change it; empty it to delete it. Also in',
        path .. '/' .. A.BUTTONS_FILE .. ' (USB):', 'one "Label | question" a line.' }) do
        gg:text(16, y + 4, l, { font = f and f.small }); y = y + 22
      end
    end
    E.draw_status(gg)
  end

  local function draw_chat(gg)
    local W, H, TOP = E.dims()
    local f = F()
    E.bar(gg, A.chat_bar(cfg))
    local first = chat.starts[chat.page] or 1
    local last = chat.starts[chat.page + 1] and (chat.starts[chat.page + 1] - 1) or #chat.lines
    local y = TOP + 4
    for i = first, last do
      local ln = chat.lines[i]
      if not ln then break end
      if ln.rule then gg:line(12, y + 2, W - 12, y + 2)
      elseif ln.s ~= '' then gg:text(12 + ln.x, y, ln.s, { font = f and f[ln.f] }) end
      y = y + ln.h
    end
    if chat.pages > 1 and (E.status() or '') == '' and not E.busy() then
      gg:text(W - 70, H - 26, chat.page .. '/' .. chat.pages, { font = f and f.small })
    end
    E.draw_status(gg)
  end

  function M.draw(gg)
    local s = E.get_screen()
    if s == 'aiset' then draw_set(gg)
    elseif s == 'aiprov' then draw_prov(gg)
    elseif s == 'aimenu' then draw_menu(gg)
    elseif s == 'aibtns' then draw_btns(gg)
    elseif s == 'chat' then draw_chat(gg) end
  end

  ---------------------------------------------------------------- input

  function M.page(delta)
    local p = chat.page + delta
    if p >= 1 and p <= chat.pages then chat.page = p end
  end

  -- Back: the conversation and the ready questions to the article (the questions to the
  -- conversation when there is one), the AI page to Settings, the Service list to the AI page
  function M.back()
    local s = E.get_screen()
    if s == 'chat' then E.set_screen('article')
    elseif s == 'aimenu' then E.set_screen(#chat.msgs > 0 and 'chat' or 'article')
    elseif s == 'aiset' then E.set_screen('settings')
    elseif s == 'aiprov' or s == 'aibtns' then E.set_screen('aiset') end
  end

  function M.tap(x, y)
    local W = E.dims()
    local s = E.get_screen()
    if s == 'chat' then
      if y < 46 then
        local bar = A.chat_bar(cfg)
        local b = bar[E.bar_hit(x, #bar) or 0]
        if b == 'Back' then M.back() elseif b == 'Prev' then M.page(-1) elseif b == 'Next' then M.page(1)
        elseif b == 'More' then E.set_screen('aimenu') end
        return
      end
      if x < W / 3 then M.page(-1) else M.page(1) end
    elseif s == 'aimenu' then
      if y < 46 then M.back(); return end
      for _, c in ipairs(menu_cells()) do
        local m = c.item
        if x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h then
          if m[2] == 'ask' then M.ask(m[3], m[1])
          elseif m[2] == 'own' then M.ask_own()
          elseif m[2] == 'web' then
            web = not web
            E.note(web and 'web search on for the next questions' or 'web search off')
          elseif m[2] == 'new' then
            if chat.waiting then E.note('still waiting for the answer') else chat.msgs = {}; M.layout(false); E.note('') end
          end
          return
        end
      end
    elseif s == 'aibtns' then
      if y < 46 then M.back(); return end
      local list = A.buttons()
      for i = 1, #list + (#list < A.BUTTONS_MAX and 1 or 0) do
        local bx, by, bw, bh = btn_rect(i)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then M.edit_button(i); return end
      end
    elseif s == 'aiprov' then
      if y < 46 then M.back(); return end
      for i, P in ipairs(A.PROVIDERS) do
        local px, py, pw, ph = prov_rect(i)
        if x >= px and x < px + pw and y >= py and y < py + ph then M.choose(P.id); return end
      end
    elseif s == 'aiset' then
      if y < 46 then M.back(); return end
      for i = 1, #A.SET do
        local sx, sy, sw = set_rect(i)
        if x >= sx and x < sx + sw and y >= sy + 24 and y < sy + 72 then M.edit(i); return end
      end
    end
  end

  return M
end

return U
