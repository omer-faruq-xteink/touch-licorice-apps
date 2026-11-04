-- Lock-screen entry: one frame per session, woken every 15 minutes (the manifest's interval_sec):
-- the sky now while it is dark, tonight's sky by day.

local view
local load_err = nil
DEBUG_FILE = 'debug_lock.txt'

function on_load(c)
  local ok, ms = pcall(function() return ctx.clock:millis() end)
  local start = (ok and type(ms) == 'number') and ms or nil
  local okl, e = xpcall(function()
    set_lang()
    dbg('lock start: lang ' .. LANG)
    local t = clock_now()
    if not t then return end
    local place = load_place(t.offset_minutes)
    local s, label = default_view(t, place)
    view = { s = s, label = label, place = place, off = t.offset_minutes * 60, hour12 = t.hour12,
             start_ms = start, budget_ms = start and 1500 or nil }
    dbg('lock view: ' .. tostring(place and place.name) .. ' ' .. tostring(s) .. ' ' .. tostring(label))
  end, trace)
  if not okl then load_err = tostring(e); dbg('LOCK ERROR ' .. load_err) end
end

function on_draw(c, g)
  if not g then return end
  local ok, e = xpcall(function()
    g:clear(0)
    if load_err then draw_error(g, 'Sky Tonight lock screen error:', load_err, 80); return end
    if not view then
      g:text(W // 2, H // 2, 'Sky Tonight: ' .. word('no_clock'), { font = font_px(24), align = 'center' })
      return
    end
    draw_sky(g, view, H)
  end, trace)
  if not ok then
    dbg('LOCK DRAW ERROR ' .. tostring(e))
    g:clear(0)
    draw_error(g, 'Sky Tonight lock screen error:', tostring(e), 80)
  else dbg('lock draw done') end
end
