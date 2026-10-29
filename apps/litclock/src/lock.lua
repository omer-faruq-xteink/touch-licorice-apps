-- Lock-screen entry: one frame per session (the manifest's interval_sec of 60 wakes it on every
-- minute); the quote for the current minute, the digital time below it if the setting says so.

local quote, t, settings

function on_load(c)
  pcall(function()
    settings = load_settings()
    t = now()
    if t then quote = pick(quotes_at(t.hour, t.minute), t, 0) end
  end)
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not t then
      g:text(W // 2, H // 2, 'Literary Clock: the clock is not set.', { font = font_px(24), align = 'center' })
      return
    end
    draw_quote(g, quote, t, settings and settings.timeline, 40, H - 60)
  end)
  if not ok then pcall(function() g:text(10, H - 30, 'lock error: ' .. tostring(e):sub(1, 40)) end) end
end
