-- Bookworm's sleep screen: one session per wake (section 15). It brings the bookworm up to date
-- with the reading done before the reader went to sleep (and when it was: its night-owl count),
-- saves that (a lock-screen session does not save ctx.state by itself), and draws it asleep on an
-- open book, dreaming of the book being read; an egg rests, a hungry one hides. Nothing changes
-- between wakes but the date, so it wakes once an hour, the longest the host allows, set on every
-- session because the host goes back to the manifest's interval each time the reader locks.

local W = 480

local function draw(gg)
  local s = ctx.state.bw
  local now
  pcall(function() now = ctx.clock:now() end)
  local data = P.read_data(ctx.reader, now)
  if not s then
    s = P.new(data)
    ctx.state.bw = s
  end
  local view = P.update(s, data)
  pcall(function() ctx:save_state() end)
  gg:clear(0)
  local F = ctx.fonts or {}
  local title = s.name .. (s.hatched and ('  ·  ' .. view.stage_name) or '  ·  an egg')
  gg:text(24, 40, title, { font = F.large })
  if view.taste_name then gg:text(24, 84, view.taste_name, { font = F.small }) end
  local b = view.book
  local f = { title = b and L.short(b.title, 30) or nil, page = b and b.page }
  local dream
  if view.hunger == 'hiding' then
    A.hiding(gg, W // 2, 500)
    dream = '(hiding in a book until you read again)'
  elseif not s.hatched then
    A.open_book(gg, W // 2, 470, 300)
    A.egg(gg, W // 2, 474)
    dream = L.pick(L.DREAM_EGG, 0, f)
  else
    A.asleep(gg, view.stage_key, W // 2, 520, view.taste)
    local seed = (data.today or 0) + (data.hour or 0)
    dream = L.pick((view.hunger == 'hungry' or view.hunger == 'sulky') and L.DREAM_HUNGRY or L.DREAM, seed, f)
  end
  if s.hatched and view.hunger ~= 'hiding' then
    -- the dream in a thought bubble over its head
    A.dream(gg, 40, 190, W - 80, 100, A.head_x(view.stage_key, W // 2) - 10, 400, dream, F.medium)
  else
    gg:text_box(24, 600, W - 48, 90, dream, { font = F.medium, align = 'center' })
  end
  if view.reading then
    local m = (view.today_sec or 0) // 60
    gg:text_box(24, 700, W - 48, 30, 'today ' .. m .. ' min  ·  streak ' .. (view.streak or 0), { font = F.small, align = 'center' })
  end
end

function on_load(c)
  pcall(function() if ctx.lock then ctx.lock:set_interval(3600) end end)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(draw, gg)
  if not ok then pcall(function() gg:clear(0); gg:text(20, 380, 'Bookworm: ' .. tostring(e):sub(1, 40)) end) end
end
