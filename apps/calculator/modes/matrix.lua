-- Matrix for the Calculator (loaded only when opened): three matrices A, B and C up to 4 x 4,
-- typed cell by cell with the calculator keys, and det, inverse, transpose, rref (which solves
-- a linear system written as an augmented matrix), +, -, × and a number times a matrix. Exact in
-- decimal (22 digits); a leftover below 10^-15 from rounding counts as 0. A result can be stored
-- in A, B or C; a number result can be kept as Ans.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}

  local NAMES = { 'A', 'B', 'C' }
  local mats = {}
  local cur = 'A'
  local result, rtitle, msg = nil, nil, nil       -- result: a matrix or a decimal
  local loaded_state = false

  local function zero() return D.zero() end
  local function new(r, c)
    local m = { r = r, c = c, v = {} }
    for i = 1, r do m.v[i] = {}; for j = 1, c do m.v[i][j] = zero() end end
    return m
  end
  for _k, n in ipairs(NAMES) do mats[n] = new(2, 2) end

  local function save()
    local out = {}
    for _k, n in ipairs(NAMES) do
      local m, vals = mats[n], {}
      for i = 1, m.r do for j = 1, m.c do vals[#vals + 1] = D.format(m.v[i][j], 22) end end
      out[#out + 1] = n .. '=' .. m.r .. ',' .. m.c .. '|' .. table.concat(vals, ',')
    end
    api.write('matrix.txt', table.concat(out, '\n'))
  end

  local function load()
    local s = api.read('matrix.txt') or ''
    for n, rs, cs, vals in s:gmatch('(%u)=(%d),(%d)|([^\n]*)') do
      local r, c = tonumber(rs), tonumber(cs)
      if mats[n] and r >= 1 and r <= 4 and c >= 1 and c <= 4 then
        local m = new(r, c)
        local k = 0
        for p in vals:gmatch('[^,]+') do
          k = k + 1
          local i, j = (k - 1) // c + 1, (k - 1) % c + 1
          if i <= r then m.v[i][j] = D.parse(p) or zero() end
        end
        mats[n] = m
      end
    end
  end

  ------------------------------------------------------------------ arithmetic

  local function absd(v) return v.neg and D.neg(v) or v end
  local function tiny(v) return D.is_zero(v) or (#v.m + v.e) < -14 end
  local function copy(m)
    local o = new(m.r, m.c)
    for i = 1, m.r do for j = 1, m.c do o.v[i][j] = m.v[i][j] end end
    return o
  end
  local function clean(m)
    for i = 1, m.r do for j = 1, m.c do if tiny(m.v[i][j]) then m.v[i][j] = zero() end end end
    return m
  end

  -- row reduction in place; returns the determinant factor (sign and pivots) and the rank
  local function reduce(m, cols, full)
    local det, row = D.parse('1'), 1
    for c = 1, cols do
      if row > m.r then break end
      local p = row
      for i = row + 1, m.r do if D.cmp(absd(m.v[i][c]), absd(m.v[p][c])) > 0 then p = i end end
      if tiny(m.v[p][c]) then
        det = zero()
      else
        if p ~= row then m.v[p], m.v[row] = m.v[row], m.v[p]; det = D.neg(det) end
        local piv = m.v[row][c]
        det = D.mul(det, piv)
        if full then
          for j = 1, m.c do m.v[row][j] = D.div(m.v[row][j], piv) end
        end
        for i = (full and 1 or row + 1), m.r do
          if i ~= row and not tiny(m.v[i][c]) then
            local f = full and m.v[i][c] or D.div(m.v[i][c], piv)
            for j = 1, m.c do m.v[i][j] = D.sub(m.v[i][j], D.mul(f, m.v[row][j])) end
          end
        end
        row = row + 1
      end
    end
    return det, row - 1
  end

  local function det(a)
    if a.r ~= a.c then return nil, 'det needs a square matrix' end
    local d = reduce(copy(a), a.c, false)
    if tiny(d) then d = zero() end
    return d
  end

  local function inverse(a)
    if a.r ~= a.c then return nil, 'inverse needs a square matrix' end
    local n = a.r
    local m = new(n, 2 * n)
    for i = 1, n do
      for j = 1, n do m.v[i][j] = a.v[i][j] end
      m.v[i][n + i] = D.parse('1')
    end
    local _d, rank = reduce(m, n, true)
    if rank < n then return nil, 'the matrix has no inverse (det = 0)' end
    local o = new(n, n)
    for i = 1, n do for j = 1, n do o.v[i][j] = m.v[i][n + j] end end
    return clean(o)
  end

  local function transpose(a)
    local o = new(a.c, a.r)
    for i = 1, a.r do for j = 1, a.c do o.v[j][i] = a.v[i][j] end end
    return o
  end

  local function rref(a)
    local m = copy(a)
    reduce(m, m.c, true)
    return clean(m)
  end

  local function add(a, b, sign)
    if a.r ~= b.r or a.c ~= b.c then return nil, 'the sizes differ' end
    local o = new(a.r, a.c)
    for i = 1, a.r do for j = 1, a.c do
      o.v[i][j] = sign > 0 and D.add(a.v[i][j], b.v[i][j]) or D.sub(a.v[i][j], b.v[i][j])
    end end
    return o
  end

  local function mul(a, b)
    if a.c ~= b.r then return nil, 'columns of the first must equal rows of the second' end
    local o = new(a.r, b.c)
    for i = 1, a.r do for j = 1, b.c do
      local s = zero()
      for k = 1, a.c do s = D.add(s, D.mul(a.v[i][k], b.v[k][j])) end
      o.v[i][j] = s
    end end
    return o
  end

  local function scale(k, a)
    local o = new(a.r, a.c)
    for i = 1, a.r do for j = 1, a.c do o.v[i][j] = D.mul(k, a.v[i][j]) end end
    return o
  end

  ------------------------------------------------------------------ screen

  local CW, CH = (W - 24) // 4, 48
  local GRID_Y, RES_Y = 124, 470
  local TABS = U.row(66, { 'A', 'B', 'C', 'Size' }, 48)
  local OPS = { U.row(330, { 'det', 'inverse', 'transpose', 'rref' }), U.row(390, { '+', '-', '×', 'k ×' }) }
  local RES_BTNS = U.row(700, { 'Store', 'Clear' })

  local function cell_text(v, w)
    local f = kit.font('small')
    for d = 10, 2, -1 do
      local s = D.format(v, d)
      if kit.width(f, s) <= w then return s end
    end
    return D.format(v, 2)
  end

  local function draw_grid(gg, m, y0, h)
    for i = 1, m.r do
      for j = 1, m.c do
        local x, y = 12 + (j - 1) * CW, y0 + (i - 1) * h
        gg:rect(x, y, CW - 4, h - 4)
        U.rtext(gg, x + CW - 12, y + (h - 24) // 2, cell_text(m.v[i][j], CW - 20))
      end
    end
  end

  function M.open()
    if not loaded_state then load(); loaded_state = true end
  end

  function M.draw(gg)
    U.header(gg, 'Matrix', nil)
    local m = mats[cur]
    TABS[4].label = m.r .. ' x ' .. m.c
    U.draw_buttons(gg, TABS, { bold = function(b) return b.label == cur end })
    draw_grid(gg, m, GRID_Y, CH)
    for _k, r in ipairs(OPS) do U.draw_buttons(gg, r) end
    if result then
      U.note(gg, RES_Y - 20, rtitle or '', 1)
      if result.v then draw_grid(gg, result, RES_Y + 8, 44)
      else U.text(gg, 16, RES_Y + 10, (rtitle and '' or '') .. api.format(result), 'large') end
      U.draw_buttons(gg, RES_BTNS)
    end
    U.note(gg, 740, msg or ('Tap a cell of ' .. cur .. ' to change it.'))
  end

  local function show(v, title, e)
    if not v then msg, result = e, nil; return end
    result, rtitle, msg = v, title, nil
  end

  local function pick_other(op, fn)
    U.pick(cur .. ' ' .. op .. ' which?', NAMES, function(k) fn(NAMES[k]) end, 3)
  end

  function M.tap(x, y)
    if U.header_hit(x, y, nil) == 'calc' then api.close(); return end
    local m = mats[cur]
    local t = U.hit(TABS, x, y)
    if t then
      if t.label == 'A' or t.label == 'B' or t.label == 'C' then cur = t.label; msg = nil; return end
      U.pick('Rows of ' .. cur, { '1', '2', '3', '4' }, function(r)
        U.pick('Columns of ' .. cur, { '1', '2', '3', '4' }, function(c)
          local o = new(r, c)
          for i = 1, math.min(r, m.r) do for j = 1, math.min(c, m.c) do o.v[i][j] = m.v[i][j] end end
          mats[cur] = o
          save()
        end, 4)
      end, 4)
      return
    end
    if y >= GRID_Y and y < GRID_Y + m.r * CH and x >= 12 and x < 12 + m.c * CW then
      local i, j = (y - GRID_Y) // CH + 1, (x - 12) // CW + 1
      U.ask_value(cur .. '(' .. i .. ',' .. j .. ')', function(v)
        m.v[i][j] = v
        save()
      end, { tokens = { { t = 'num', s = (D.format(m.v[i][j], 22):gsub('e%+?', 'E')) } } })
      return
    end
    local b
    for _k, r in ipairs(OPS) do b = b or U.hit(r, x, y) end
    if b then
      pcall(function() ctx.budget:extend() end)
      local l = b.label
      if l == 'det' then local v, e = det(m); show(v, 'det(' .. cur .. ')', e)
      elseif l == 'inverse' then local v, e = inverse(m); show(v, cur .. ' inverse', e)
      elseif l == 'transpose' then show(transpose(m), cur .. ' transposed')
      elseif l == 'rref' then show(rref(m), 'rref(' .. cur .. ')')
      elseif l == '+' or l == '-' then
        pick_other(l, function(n) local v, e = add(m, mats[n], l == '+' and 1 or -1); show(v, cur .. ' ' .. l .. ' ' .. n, e) end)
      elseif l == '×' then
        pick_other('×', function(n) local v, e = mul(m, mats[n]); show(v, cur .. ' × ' .. n, e) end)
      else
        U.ask_value('k (times ' .. cur .. ')', function(k) show(scale(k, m), api.format(k) .. ' × ' .. cur) end)
      end
      return
    end
    if result then
      local r = U.hit(RES_BTNS, x, y)
      if r and r.label == 'Clear' then result, msg = nil, nil
      elseif r and r.label == 'Store' then
        if result.v then
          U.pick('Store the result in', NAMES, function(k) mats[NAMES[k]] = copy(result); save(); msg = 'Stored in ' .. NAMES[k] end, 3)
        else
          api.set_ans(result); msg = 'Kept as Ans'
        end
      end
    end
  end

  function M.back() return false end

  if rawget(_G, '__TEST') then
    M.test = { mats = mats, det = det, inverse = inverse, rref = rref, mul = mul, new = new,
               result = function() return result end, msg = function() return msg end, set = function(n, m) mats[n] = m end }
  end
  return M
end
