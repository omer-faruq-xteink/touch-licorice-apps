-- Shared screen pieces of the Calculator's modes: the header with its Calc button, rows of
-- buttons, number formatting and a list picker. Loaded with the first mode opened, never by
-- Basic or Sci. require('modes.ui')(api) -> U.

return function(api)
  local kit, W = api.kit, api.W
  local U = {}

  U.CALC = { x = 12, y = 8, w = 90, h = 44 }

  -- "Calc" (back to the calculator), the title, and up to two buttons on the right
  function U.header(gg, title, right)
    kit.button(gg, U.CALC.x, U.CALC.y, U.CALC.w, U.CALC.h, 'Calc', { font = 'medium' })
    gg:text(116, 18, kit.short(title, right and #right > 0 and (right[2] and 8 or 14) or 22), { font = kit.font('medium') })
    for _k, b in ipairs(U.header_buttons(right)) do
      kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = 'medium' })
    end
    gg:line(12, 58, W - 12, 58)
  end

  function U.header_buttons(right)
    local out = {}
    local x = W - 12
    for k = #(right or {}), 1, -1 do
      x = x - 100
      out[#out + 1] = { x = x, y = 8, w = 100, h = 44, label = right[k] }
      x = x - 8
    end
    return out
  end

  -- "calc", a right button's label, or nil
  function U.header_hit(x, y, right)
    if U.inside(U.CALC, x, y) then return 'calc' end
    for _k, b in ipairs(U.header_buttons(right)) do
      if U.inside(b, x, y) then return b.label end
    end
    return nil
  end

  function U.inside(b, x, y) return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

  -- a row of equal buttons across the screen
  function U.row(y, labels, h)
    local n = #labels
    local gap = 8
    local bw = (W - 24 - (n - 1) * gap) // n
    local out = {}
    for k, l in ipairs(labels) do
      out[#out + 1] = { x = 12 + (k - 1) * (bw + gap), y = y, w = bw, h = h or 52, label = l }
    end
    return out
  end

  -- a label too wide for its button in the medium font is drawn in the small one
  function U.draw_buttons(gg, btns, opts)
    for _k, b in ipairs(btns) do
      local bold = opts and opts.bold and opts.bold(b)
      local fname = (opts and opts.font) or 'medium'
      if fname == 'medium' and kit.width(kit.font('medium'), b.label) > b.w - 12 then fname = 'small' end
      kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = fname, line_width = bold and 3 or 2 })
    end
  end

  -- a hint in the small font, wrapped to the screen's width (at most `most` lines)
  function U.note(gg, y, s, most)
    local lines = kit.wrap(s, 'small', W - 32)
    local lh = kit.line_h('small') + 2
    for k = 1, math.min(#lines, most or 2) do gg:text(16, y + (k - 1) * lh, lines[k], { font = kit.font('small') }) end
  end

  function U.hit(btns, x, y)
    for _k, b in ipairs(btns) do if U.inside(b, x, y) then return b end end
    return nil
  end

  function U.text(gg, x, y, s, fname) gg:text(x, y, s, { font = kit.font(fname or 'small') }) end

  function U.rtext(gg, right, y, s, fname)
    local f = kit.font(fname or 'small')
    gg:text(right - kit.width(f, s), y, s, { font = f })
  end

  -- a float for the screen: the digits a float carries here, "undefined" for nan and infinity
  function U.fmt(x, digits)
    if type(x) ~= 'number' then return '-' end
    if x ~= x or x == math.huge or x == -math.huge then return 'undefined' end
    if x == 0 then return '0' end
    local s = string.format('%.' .. (digits or api.FLOAT_DIGITS) .. 'g', x)
    s = s:gsub('e%+?(%-?)0*(%d)', 'e%1%2')
    return s
  end

  -- a decimal (or a float) in as many digits as fit in w pixels
  function U.fit(v, w, fname, most)
    local f = kit.font(fname or 'small')
    local s
    for d = most or 12, 3, -1 do
      s = type(v) == 'number' and U.fmt(v, math.min(d, api.FLOAT_DIGITS)) or api.D.format(v, d)
      if kit.width(f, s) <= w then return s end
    end
    return s
  end

  -- a list to choose from: options = { label, ... }, fn(index)
  function U.pick(title, options, fn, per_row)
    per_row = per_row or 2
    local rows = {}
    for k, l in ipairs(options) do
      local r = rows[(k - 1) // per_row + 1] or {}
      rows[(k - 1) // per_row + 1] = r
      r[#r + 1] = { l, function() kit.close(); fn(k) end }
    end
    rows[#rows + 1] = { { 'Cancel', function() kit.close() end } }
    kit.show({ title = title, rows = rows, cancel = kit.close })
  end

  -- tokens <-> one line of a file: "kind:text" joined by tabs
  function U.pack_tokens(toks)
    local out = {}
    for _k, t in ipairs(toks or {}) do out[#out + 1] = t.t .. ':' .. t.s end
    return table.concat(out, '\t')
  end
  function U.unpack_tokens(s)
    local toks = {}
    for part in (s or ''):gmatch('[^\t]+') do
      local t, v = part:match('^(%a+):(.*)$')
      if t then toks[#toks + 1] = { t = t, s = v } end
    end
    return toks
  end

  -- a decimal value typed with the calculator keys
  function U.ask_value(title, fn, opts)
    api.edit({ title = title, value = true, empty = opts and opts.empty, tokens = opts and opts.tokens,
               on_done = function(toks, v, ap) fn(v, ap, toks) end })
  end

  return U
end
