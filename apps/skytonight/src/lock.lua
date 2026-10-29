-- Lock-screen entry: one frame per session, woken every 15 minutes (the manifest's interval_sec):
-- the sky now while it is dark, tonight's sky by day.

local view

function on_load(c)
  local ok, ms = pcall(function() return ctx.clock:millis() end)
  local start = (ok and type(ms) == 'number') and ms or nil
  pcall(function()
    set_lang()
    local t = clock_now()
    if not t then return end
    local place = load_place(t.offset_minutes)
    local s, label = default_view(t, place)
    view = { s = s, label = label, place = place, off = t.offset_minutes * 60, hour12 = t.hour12,
             start_ms = start, budget_ms = start and 1500 or nil }
  end)
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not view then
      g:text(W // 2, H // 2, 'Sky Tonight: ' .. word('no_clock'), { font = font_px(24), align = 'center' })
      return
    end
    draw_sky(g, view, H)
  end)
  if not ok then pcall(function() g:text(10, H - 30, 'lock error: ' .. tostring(e):sub(1, 40)) end) end
end
