-- Lock-screen entry: one frame per session; the manifest's interval_sec of 60 wakes it on every
-- minute, so the minute dots move and the words change every five minutes.

local t, lang

function on_load(c)
  pcall(function() t = now(); lang = load_lang() end)
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not t then
      g:text(W // 2, H // 2, 'Word Clock: the clock is not set.', { font = font_px(24), align = 'center' })
      return
    end
    draw_clock(g, lang or 'en', t.hour, t.minute, 30, H - 20)
  end)
  if not ok then pcall(function() g:text(10, H - 30, 'lock error: ' .. tostring(e):sub(1, 40)) end) end
end
