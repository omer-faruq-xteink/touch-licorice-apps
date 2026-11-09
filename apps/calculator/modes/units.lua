-- Units for the Calculator (loaded only when opened): a value in one unit, shown in every unit of
-- its kind at once. Exact in decimal: each unit is a factor to the kind's base unit (by the
-- definitions: an inch is 0.0254 m, a pound 0.45359237 kg, a US gallon 3.785411784 L), and
-- temperatures are converted through kelvin. Tap a line to make it the value you type in.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}

  local function d(s) return D.parse(s) end
  local KINDS = {
    { 'Length', { { 'mm', '0.001' }, { 'cm', '0.01' }, { 'm', '1' }, { 'km', '1000' }, { 'in', '0.0254' }, { 'ft', '0.3048' },
                  { 'yd', '0.9144' }, { 'mi', '1609.344' }, { 'nautical mi', '1852' } } },
    { 'Mass', { { 'mg', '0.000001' }, { 'g', '0.001' }, { 'kg', '1' }, { 't', '1000' }, { 'oz', '0.028349523125' },
                { 'lb', '0.45359237' }, { 'stone', '6.35029318' } } },
    { 'Temperature', { { '°C' }, { '°F' }, { 'K' } } },
    { 'Area', { { 'mm²', '0.000001' }, { 'cm²', '0.0001' }, { 'm²', '1' }, { 'ha', '10000' }, { 'km²', '1000000' },
                { 'in²', '0.00064516' }, { 'ft²', '0.09290304' }, { 'yd²', '0.83612736' }, { 'acre', '4046.8564224' },
                { 'mi²', '2589988.110336' } } },
    { 'Volume', { { 'mL', '0.001' }, { 'L', '1' }, { 'm³', '1000' }, { 'tsp (US)', '0.00492892159375' },
                  { 'tbsp (US)', '0.01478676478125' }, { 'fl oz (US)', '0.0295735295625' }, { 'cup (US)', '0.2365882365' },
                  { 'pint (US)', '0.473176473' }, { 'gal (US)', '3.785411784' }, { 'gal (UK)', '4.54609' } } },
    { 'Speed', { { 'm/s', '1' }, { 'km/h', '0.27777777777777777777778' }, { 'mph', '0.44704' },
                 { 'knot', '0.51444444444444444444444' }, { 'ft/s', '0.3048' } } },
    { 'Time', { { 'ms', '0.001' }, { 's', '1' }, { 'min', '60' }, { 'h', '3600' }, { 'day', '86400' },
                { 'week', '604800' }, { 'year (365 d)', '31536000' } } },
    { 'Data', { { 'bit', '0.125' }, { 'byte', '1' }, { 'KB', '1000' }, { 'MB', '1000000' }, { 'GB', '1000000000' },
                { 'TB', '1000000000000' }, { 'KiB', '1024' }, { 'MiB', '1048576' }, { 'GiB', '1073741824' },
                { 'TiB', '1099511627776' } } },
    { 'Energy', { { 'J', '1' }, { 'kJ', '1000' }, { 'cal', '4.184' }, { 'kcal', '4184' }, { 'Wh', '3600' },
                  { 'kWh', '3600000' }, { 'BTU', '1055.05585262' }, { 'eV', '1.602176634e-19' } } },
    { 'Pressure', { { 'Pa', '1' }, { 'hPa', '100' }, { 'kPa', '1000' }, { 'bar', '100000' }, { 'atm', '101325' },
                    { 'psi', '6894.757293168' }, { 'mmHg', '133.322387415' } } },
    { 'Angle', { { 'degree', '1' }, { 'radian' }, { 'grad', '0.9' }, { 'turn', '360' }, { 'arcmin', '0.016666666666666666666667' },
                 { 'arcsec', '0.00027777777777777777777778' } } },
  }
  for _k, kind in ipairs(KINDS) do
    for _j, u in ipairs(kind[2]) do if u[2] then u[3] = d(u[2]) end end
  end
  -- a radian is 180/pi degrees
  KINDS[11][2][2][3] = D.div(d('180'), api.PI)

  local kind, from = 1, 3
  local value = d('1')
  local msg = nil
  local loaded_state = false

  local K273 = d('273.15')
  local function to_base(k, u, v)
    if KINDS[k][1] ~= 'Temperature' then return D.mul(v, KINDS[k][2][u][3]) end
    if u == 1 then return D.add(v, K273) end
    if u == 2 then return D.add(D.div(D.mul(D.sub(v, d('32')), d('5')), d('9')), K273) end
    return v
  end
  local function from_base(k, u, v)
    if KINDS[k][1] ~= 'Temperature' then return D.div(v, KINDS[k][2][u][3]) end
    if u == 1 then return D.sub(v, K273) end
    if u == 2 then return D.add(D.div(D.mul(D.sub(v, K273), d('9')), d('5')), d('32')) end
    return v
  end

  local function save()
    api.write('units.txt', 'kind=' .. kind .. '\nfrom=' .. from .. '\nvalue=' .. D.format(value, 22))
  end
  local function load()
    local s = api.read('units.txt') or ''
    local k, f = tonumber(s:match('kind=(%d+)')), tonumber(s:match('from=(%d+)'))
    if k and KINDS[k] then
      kind = k
      if f and KINDS[k][2][f] then from = f end
    end
    value = D.parse(s:match('value=([^\n]+)') or '1') or d('1')
  end

  local TOP = U.row(66, { 'Kind', 'Unit', 'Value' }, 48)
  local LIST_Y, LINE_H = 196, 46

  function M.open()
    if not loaded_state then load(); loaded_state = true end
  end

  function M.draw(gg)
    U.header(gg, 'Units: ' .. KINDS[kind][1], nil)
    U.draw_buttons(gg, TOP)
    local u = KINDS[kind][2][from]
    U.text(gg, 16, 128, U.fit(value, W - 140, 'medium') .. ' ' .. u[1] .. ' is', 'medium')
    gg:line(12, LIST_Y - 10, W - 12, LIST_Y - 10)
    local base = to_base(kind, from, value)
    for j, unit in ipairs(KINDS[kind][2]) do
      local y = LIST_Y + (j - 1) * LINE_H
      local v = from_base(kind, j, base)
      U.text(gg, 20, y + 8, unit[1], 'medium')
      local s = U.fit(v, W - 200, j == from and 'large' or 'medium')
      U.rtext(gg, W - 20, y + 8, s, j == from and 'large' or 'medium')
    end
    U.note(gg, 740, msg or 'Tap a line to type its value instead.')
  end

  function M.tap(x, y)
    if U.header_hit(x, y, nil) == 'calc' then api.close(); return end
    msg = nil
    local b = U.hit(TOP, x, y)
    if b then
      if b.label == 'Kind' then
        local names = {}
        for k, kd in ipairs(KINDS) do names[k] = kd[1] end
        U.pick('Kind', names, function(k)
          if k ~= kind then
            kind = k
            from = math.min(#KINDS[k][2], k == 3 and 1 or 2)
          end
          save()
        end)
      elseif b.label == 'Unit' then
        local names = {}
        for j, u in ipairs(KINDS[kind][2]) do names[j] = u[1] end
        U.pick('Type the value in', names, function(j)
          value = from_base(kind, j, to_base(kind, from, value))
          from = j
          save()
        end, 3)
      else
        U.ask_value(KINDS[kind][2][from][1], function(v) value = v; save() end)
      end
      return
    end
    local j = (y - LIST_Y) // LINE_H + 1
    if y >= LIST_Y and KINDS[kind][2][j] then
      value = from_base(kind, j, to_base(kind, from, value))
      from = j
      save()
    end
  end

  function M.back() return false end

  if rawget(_G, '__TEST') then
    M.test = { convert = function(k, a, b, v) return D.format(from_base(k, b, to_base(k, a, v)), 16) end, KINDS = KINDS }
  end
  return M
end
