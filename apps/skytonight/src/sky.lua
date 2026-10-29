-- Sky Tonight: shared by the app (index.lua) and the lock screen (lockscreen.lua); bundle.py puts
-- astro.lua, places.lua and this file in front of each. The sky over the chosen place as a round
-- chart (looking up: north at the top, east on the left, the horizon the rim): stars to
-- magnitude 4.5, the constellation figures and names, the moon and the planets; under it the
-- moon's phase and the night's times. By day it shows tonight, from an hour after dusk.

local W, H = 480, 800
local CX, CY, R = 240, 322, 206                 -- the chart: centre and the horizon's radius
local MAX_CMDS = 1000                            -- the host takes 1024 drawing commands a frame
local J = A.J2000

------------------------------------------------------------------ words

local LANG = 'en'
local WORDS = {
  en = { now = 'now', tonight = 'tonight', sunset = 'Sunset', dark = 'Dark', sunrise = 'Sunrise',
         rises = 'rises', sets = 'sets', lit = '%d%% lit', moon = 'Moon', full = 'Full moon', new = 'New moon', sun = 'Sun',
         none_up = 'No planets above the horizon', no_clock = 'The clock is not set.',
         set_clock = 'Set the time in the system settings.', place = 'Place', back = 'Back',
         coords = 'Coordinates', coords_title = 'Latitude, longitude (e.g. 41.01, 28.98)',
         lock_on = 'Lock: on', lock_off = 'Lock screen', tz_note = "Times in this device's time zone",
         phases = { 'New moon', 'Waxing crescent', 'First quarter', 'Waxing gibbous', 'Full moon',
                    'Waning gibbous', 'Last quarter', 'Waning crescent' },
         dirs = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' },
         days = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' },
         months = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' },
         planets = { mercury = 'Mercury', venus = 'Venus', mars = 'Mars', jupiter = 'Jupiter', saturn = 'Saturn' } },
  tr = { now = 'şimdi', tonight = 'bu gece', sunset = 'Gün batımı', dark = 'Karanlık', sunrise = 'Gün doğumu',
         rises = 'doğuş', sets = 'batış', lit = '%%%d aydınlık', moon = 'Ay', full = 'Dolunay', new = 'Yeni ay', sun = 'Güneş',
         none_up = 'Ufkun üstünde gezegen yok', no_clock = 'Saat ayarlı değil.',
         set_clock = 'Saati sistem ayarlarından kurun.', place = 'Yer', back = 'Geri',
         coords = 'Koordinat', coords_title = 'Enlem, boylam (ör. 41.01, 28.98)',
         lock_on = 'Kilit: açık', lock_off = 'Kilit ekranı', tz_note = 'Saatler cihazın saat diliminde',
         phases = { 'Yeni ay', 'Büyüyen hilal', 'İlk dördün', 'Büyüyen ay', 'Dolunay',
                    'Küçülen ay', 'Son dördün', 'Küçülen hilal' },
         dirs = { 'K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB' },
         days = { 'Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt' },
         months = { 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara' },
         planets = { mercury = 'Merkür', venus = 'Venüs', mars = 'Mars', jupiter = 'Jüpiter', saturn = 'Satürn' } },
  de = { now = 'jetzt', tonight = 'heute Nacht', sunset = 'Sonnenunterg.', dark = 'Dunkel', sunrise = 'Sonnenaufg.',
         rises = 'Aufgang', sets = 'Untergang', lit = '%d %% beleuchtet', moon = 'Mond', full = 'Vollmond', new = 'Neumond', sun = 'Sonne',
         none_up = 'Keine Planeten über dem Horizont', no_clock = 'Die Uhr ist nicht gestellt.',
         set_clock = 'Stellen Sie die Zeit in den Einstellungen.', place = 'Ort', back = 'Zurück',
         coords = 'Koordinaten', coords_title = 'Breite, Länge (z. B. 52.52, 13.40)',
         lock_on = 'Sperre: an', lock_off = 'Sperrbildschirm', tz_note = 'Zeiten in der Zeitzone des Geräts',
         phases = { 'Neumond', 'Zunehmende Sichel', 'Erstes Viertel', 'Zunehmender Mond', 'Vollmond',
                    'Abnehmender Mond', 'Letztes Viertel', 'Abnehmende Sichel' },
         dirs = { 'N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW' },
         days = { 'So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa' },
         months = { 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez' },
         planets = { mercury = 'Merkur', venus = 'Venus', mars = 'Mars', jupiter = 'Jupiter', saturn = 'Saturn' } },
}
local NAME_COL = { en = 1, tr = 2, de = 3 }       -- which of names.txt's three names
local LANGS = { 'en', 'tr', 'de' }
local LANG_NAMES = { en = 'English', tr = 'Türkçe', de = 'Deutsch' }
-- every letter outside ASCII the app can show, in any language: place names (İstanbul, São
-- Paulo, Reykjavík) appear whatever the language, so the font must have all of them
local SAMPLE = 'İŞĞÜÖÇışğüöçÄäßãíé°·'

local function word(k) return WORDS[LANG][k] or WORDS.en[k] end

------------------------------------------------------------------ settings

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end

-- settings.txt: "place=İstanbul\nlat=41.01\nlon=28.98\nlang=tr\n". The language is the one
-- picked on the Place page, else the system's (tr, de, else English).
local LANG_PICKED = nil
local function set_lang()
  local picked = (sread('settings.txt') or ''):match('lang=(%a+)')
  if picked and WORDS[picked] then LANG_PICKED, LANG = picked, picked; return end
  local ok, loc = pcall(function() return ctx.i18n.locale end)
  loc = (ok and type(loc) == 'string') and loc:sub(1, 2) or 'en'
  LANG = WORDS[loc] and loc or 'en'
end

-- with no place saved, a guess from the language and the time zone
local function load_place(offset_min)
  local s = sread('settings.txt') or ''
  local name, lat, lon = s:match('place=([^\n]*)'), tonumber(s:match('lat=([-%d.]+)')), tonumber(s:match('lon=([-%d.]+)'))
  if name and lat and lon then return { name = name, lat = lat, lon = lon } end
  if LANG == 'tr' then return find_place('İstanbul') end
  if LANG == 'de' then return find_place('Berlin') end
  local off = offset_min or 0
  local guess = GUESS_TZ[off] or GUESS_TZ[off - 60]           -- summer time is an hour ahead
  return find_place(guess or 'London')
end

local function save_settings(p)
  swrite('settings.txt', string.format('place=%s\nlat=%.2f\nlon=%.2f\n', p.name, p.lat, p.lon)
    .. (LANG_PICKED and ('lang=' .. LANG_PICKED .. '\n') or ''))
end
local save_place = save_settings

-- the next language (English, Türkçe, Deutsch), kept with the place
local function next_lang(p)
  for i, l in ipairs(LANGS) do
    if l == LANG then LANG = LANGS[i % #LANGS + 1]; break end
  end
  LANG_PICKED = LANG
  save_settings(p)
end

------------------------------------------------------------------ data

local STARS, LINES, CNAMES, SNAMES

local function pread(name)
  local ok, s = pcall(function() return ctx.package:read(name) end)
  return (ok and type(s) == 'string') and s or ''
end

-- stars.txt "ra dec mag", brightest first; lines.txt "ra dec ra dec ..."; names.txt
-- "ra dec rank en|tr|de"; stars_named.txt "ra dec name"
local function load_data()
  if STARS then return end
  STARS, LINES, CNAMES, SNAMES = {}, {}, {}, {}
  for ra, dec, mag in pread('stars.txt'):gmatch('(%S+) (%S+) (%S+)') do
    STARS[#STARS + 1] = { tonumber(ra), tonumber(dec), tonumber(mag) }
  end
  for line in pread('lines.txt'):gmatch('[^\n]+') do
    local pts = {}
    for v in line:gmatch('%S+') do pts[#pts + 1] = tonumber(v) end
    LINES[#LINES + 1] = pts
  end
  for ra, dec, rank, names in pread('names.txt'):gmatch('(%S+) (%S+) (%d) ([^\n]+)') do
    local n = {}
    for part in (names .. '|'):gmatch('([^|]*)|') do n[#n + 1] = part end
    CNAMES[#CNAMES + 1] = { tonumber(ra), tonumber(dec), tonumber(rank), n }
  end
  for ra, dec, name in pread('stars_named.txt'):gmatch('(%S+) (%S+) ([^\n]+)') do
    SNAMES[#SNAMES + 1] = { tonumber(ra), tonumber(dec), name }
  end
end

------------------------------------------------------------------ time

local function clock_now()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid and t.epoch_sec then return t end
  return nil
end

-- local wall-clock seconds for s (J2000 seconds) and back
local function to_local(s, off) return s + J + off end
local function from_local(l, off) return l - off - J end

-- year, month, day from days since 1970-01-01 (Howard Hinnant's civil_from_days, integers only)
local function civil(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

local HOUR12 = false
local function hhmm(s, off)
  if not s then return '-' end
  local l = to_local(s, off) % 86400
  local h, m = l // 3600, (l % 3600) // 60
  if HOUR12 then return string.format('%d:%02d %s', (h + 11) % 12 + 1, m, h < 12 and 'am' or 'pm') end
  return string.format('%02d:%02d', h, m)
end

local function date_text(s, off)
  local l = to_local(s, off)
  local dn = l // 86400
  local _, m, d = civil(dn)
  return string.format('%s %d %s', WORDS[LANG].days[(dn + 4) % 7 + 1], d, WORDS[LANG].months[m])
end

-- the moment the app opens on: now when the sun is 6 degrees down or more, else tonight from the
-- top of the hour after nautical dusk (the sun 12 degrees down; 23:00 where it never gets that
-- dark). Returns s and 'now' or 'tonight'.
local function default_view(t, place)
  local off = t.offset_minutes * 60
  local s_now = A.secs(t.epoch_sec)
  if A.body_alt('sun', s_now, place.lat, place.lon) < -6 then return s_now, 'now' end
  local l = to_local(s_now, off)
  local noon = from_local(l - l % 86400 + 43200, off)
  local _, dusk = A.crossings('sun', noon, place.lat, place.lon, -12)
  local target
  if dusk and dusk > s_now then
    local ld = to_local(dusk, off)
    target = ld - ld % 3600 + 3600
  else
    target = l - l % 86400 + 23 * 3600
    if target <= l then return s_now, 'now' end
  end
  return from_local(target, off), 'tonight'
end

-- the night around s, noon to noon: sunset, dark, sunrise; the moon's first rise in it and the
-- first set after that (or after noon when it was already up), looking 36 hours ahead
local function night_times(s, place, off)
  local l = to_local(s, off)
  local noon = from_local(l - (l - 43200) % 86400, off)
  local lat, lon = place.lat, place.lon
  local sunrise, sunset = A.crossings('sun', noon, lat, lon, -0.833)
  local _, dark = A.crossings('sun', noon, lat, lon, -12)
  local ev, mrise, mset = A.events('moon', noon, lat, lon, -0.833, 36), nil, nil
  for _, e in ipairs(ev) do
    if e[2] and e[1] < noon + 86400 then mrise = e[1]; break end
  end
  for _, e in ipairs(ev) do
    if not e[2] and e[1] > (mrise or noon) and (mrise or e[1] < noon + 86400) then mset = e[1]; break end
  end
  return { sunset = sunset, dark = dark, sunrise = sunrise, mrise = mrise, mset = mset }
end

-- the next time after s that the moon is `target` degrees from the sun along the ecliptic
-- (180 full, 0 new): the mean month for a first guess, then the moon's real speed, twice
local function next_phase(s, target)
  local function elong(x)
    local slon = A.sun(x)
    local mlon = A.moon(x)
    return A.rev(mlon - slon)
  end
  local d = A.rev(target - elong(s)) / 12.19
  local x = s + floor(d * 86400)
  for _ = 1, 3 do
    local diff = A.rev(target - elong(x) + 180) - 180
    x = x + floor(diff / 12.19 * 86400)
  end
  return x
end

------------------------------------------------------------------ drawing

-- a font of px pixels that has every letter this language needs (2.3.1): the user's font may
-- lack İ or Ş, and the host then picks one that has them
local font_cache = {}
local function font_px(px)
  local key = px
  if font_cache[key] then return font_cache[key] end
  local ok, f = pcall(function() return ctx.fonts:size(px, SAMPLE) end)
  if not ok or not f then ok, f = pcall(function() return ctx.fonts:size(px) end) end
  if not ok or not f then
    -- only on a host without fonts:size (before 2.3)
    -- xtapp-ignore: font-small
    f = (px >= 30 and ctx.fonts.large) or (px >= 22 and ctx.fonts.medium) or ctx.fonts.small
  end
  font_cache[key] = f
  return f
end

local function text_w(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 8
end

local rad = math.pi / 180
local sin, cos, tan, sqrt, floor = math.sin, math.cos, math.tan, math.sqrt, math.floor

-- stereographic: the zenith at the centre, the horizon at R; north up, east left
local function project(alt, az)
  local r = R * tan((90 - alt) * rad / 2)
  return CX - r * sin(az * rad), CY - r * cos(az * rad)
end

local function dir_word(az) return WORDS[LANG].dirs[floor((az + 22.5) / 45) % 8 + 1] end

-- the moon's disc at (x, y): dark disc, the lit part as a polygon. Waxing is lit on the right in
-- the northern hemisphere, on the left in the southern.
local function moon_disc(g, x, y, r, lit, waxing, south, on_black)
  local ink, paper = 15, 0
  g:circle(x, y, r, { fill = true, color = ink })
  if lit > 0.02 then
    local side = (waxing ~= south) and 1 or -1
    local k = 1 - 2 * lit                         -- the terminator's half-width over r: 1 new, -1 full
    local pts = {}
    local n = r >= 20 and 24 or 10
    for i = 0, n do
      local a = -90 + 180 * i / n
      pts[#pts + 1] = floor(x + side * r * cos(a * rad) + 0.5); pts[#pts + 1] = floor(y + r * sin(a * rad) + 0.5)
    end
    for i = n, 0, -1 do
      local a = -90 + 180 * i / n
      pts[#pts + 1] = floor(x + side * k * r * cos(a * rad) + 0.5); pts[#pts + 1] = floor(y + r * sin(a * rad) + 0.5)
    end
    g:polygon(pts, { fill = true, color = paper })
  end
  g:circle(x, y, r, { color = on_black and paper or ink, line_width = on_black and 1 or 2 })
end

-- the whole sky view: chart, header and the night's facts; y_end is where the buttons start.
-- view = { s, label, place, off, hour12, start_ms, budget_ms }: with a budget (the lock screen's
-- two seconds) the faint stars stop when time runs short. Returns the number of commands used.
local function draw_sky(g, view, y_end)
  load_data()
  HOUR12 = view.hour12 and true or false
  local s, place, off = view.s, view.place, view.off
  local lat, lon = place.lat, place.lon
  local lst = A.gmst(s) + lon
  local n = 0
  local function c(k) n = n + (k or 1); return n <= MAX_CMDS end
  local white = { color = 0 }
  local sl, cl = sin(lat * rad), cos(lat * rad)
  -- a star's place on the chart and u, the sine of its altitude (above the horizon when u > 0):
  -- the stereographic projection straight from the direction vector, four sines per star
  local function xy(ra, dec)
    local h, d = (lst - ra) * rad, dec * rad
    local sd, cd, ch = sin(d), cos(d), cos(h)
    local u = sd * sl + cd * cl * ch
    local k = R / (1 + u)
    return CX + k * cd * sin(h), CY - k * (sd * cl - cd * sl * ch), u
  end
  local function late()
    if not view.budget_ms then return false end
    local ok, ms = pcall(function() return ctx.clock:millis() end)
    return ok and type(ms) == 'number' and ((ms - view.start_ms) & 0x7FFFFFFF) > view.budget_ms
  end

  -- header: the place, the date and the time
  local f_big, f_mid, f_small, f_tiny = font_px(30), font_px(20), font_px(16), font_px(14)
  g:text(20, 16, place.name, { font = f_big })
  g:text(W - 20, 16, hhmm(s, off), { font = f_big, align = 'right' })
  local sub = date_text(s, off) .. (view.label and ('  ·  ' .. word(view.label)) or '')
  g:text(20, 58, sub, { font = f_mid })
  c(3)

  -- the sky: a black disc, the compass points around it
  g:circle(CX, CY, R, { fill = true })
  local fpt = font_px(18)
  for i, ang in ipairs({ 0, 90, 180, 270 }) do
    local x, y = CX - (R + 13) * sin(ang * rad), CY - (R + 13) * cos(ang * rad)
    g:text(floor(x), floor(y), WORDS[LANG].dirs[(i - 1) * 2 + 1], { font = fpt, align = 'center', valign = 'middle' })
  end
  c(5)

  -- labels: kept apart from each other and inside the disc
  local boxes = {}
  local function label(x, y, s_, f, opts)
    local w, h = text_w(f, s_), f.line_height or 18
    local x0 = opts and opts.align == 'center' and x - w // 2 or x
    local y0 = y - h // 2
    local dy = y0 + h / 2 - CY
    for _, ex in ipairs({ x0, x0 + w }) do
      local dx = ex - CX
      if dx * dx + dy * dy > (R - 6) * (R - 6) then return false end
    end
    local p = 8                                 -- a gap between labels
    for _, b in ipairs(boxes) do
      if x0 - p < b[1] + b[3] and b[1] < x0 + w + p and y0 < b[2] + b[4] and b[2] < y0 + h then return false end
    end
    if not c() then return false end
    boxes[#boxes + 1] = { x0, y0, w, h }
    g:text(floor(x0), floor(y0), s_, { font = f, color = 0 })
    return true
  end

  -- the constellation figures, cut at the horizon
  for _, pts in ipairs(LINES) do
    local out, px, py, palt = {}, nil, nil, nil
    local function flush()
      if #out >= 4 and c() then g:polyline(out, white) end
      out = {}
    end
    for i = 1, #pts - 1, 2 do
      local x, y, alt = xy(pts[i], pts[i + 1])
      if palt then
        if alt >= 0 and palt >= 0 then
          if #out == 0 then out[1], out[2] = floor(px), floor(py) end
          out[#out + 1], out[#out + 2] = floor(x), floor(y)
        elseif (alt >= 0) ~= (palt >= 0) and alt > -0.8 and palt > -0.8 then
          local t = palt / (palt - alt)               -- where the altitude passes 0, on the rim
          local ex, ey = px + (x - px) * t - CX, py + (y - py) * t - CY
          local d = sqrt(ex * ex + ey * ey)
          if d > 0 then ex, ey = CX + ex * R / d, CY + ey * R / d end
          if alt >= 0 then
            out[1], out[2] = floor(ex), floor(ey)
            out[3], out[4] = floor(x), floor(y)
          else
            if #out == 0 then out[1], out[2] = floor(px), floor(py) end
            out[#out + 1], out[#out + 2] = floor(ex), floor(ey)
            flush()
          end
        end
      end
      if #out >= 254 then flush() end
      px, py, palt = x, y, alt
    end
    flush()
  end

  -- the sun, the moon and the planets first, so their labels win
  local _, sra, sdec = A.sun(s)
  local salt, saz = A.horizon(sra, sdec, lst, lat)
  local _, _, mra, mdec, mpar = A.moon(s)
  local malt, maz = A.horizon(mra, mdec, lst, lat)
  malt = malt - mpar * cos(malt * rad)
  local lit, waxing, age = A.phase(s)
  local f_lab = font_px(15)
  if salt > 0 and c(10) then
    local x, y = project(salt, saz)
    g:circle(floor(x), floor(y), 9, { fill = true, color = 0 })
    for k = 0, 7 do
      local a = k * 45 * rad
      g:line(floor(x + 12 * cos(a)), floor(y + 12 * sin(a)), floor(x + 17 * cos(a)), floor(y + 17 * sin(a)), white)
    end
    label(x + 20, y, word('sun'), f_lab)
  end
  if malt > 0 and c(3) then
    local x, y = project(malt, maz)
    moon_disc(g, floor(x), floor(y), 10, lit, waxing, lat < 0, true)
    label(x + 14, y, word('moon'), f_lab)
  end
  local up = {}
  for _, name in ipairs(A.PLANETS) do
    local _, _, pra, pdec = A.planet(name, s)
    local palt, paz = A.horizon(pra, pdec, lst, lat)
    if palt > 0 and c(2) then
      local x, y = project(palt, paz)
      g:circle(floor(x), floor(y), 4, { fill = true, color = 0 })
      g:circle(floor(x), floor(y), 8, { color = 0 })
      label(x + 11, y, WORDS[LANG].planets[name], f_lab)
      up[#up + 1] = { name, palt, paz }
    end
  end

  -- named stars, then constellation names (best known first)
  for _, st in ipairs(SNAMES) do
    local x, y, u = xy(st[1], st[2])
    if u > 0.05 then
      label(x + 7, y, st[3], f_tiny)
    end
  end
  local col = NAME_COL[LANG]
  for rank = 1, 2 do
    for _, cn in ipairs(CNAMES) do
      if cn[3] == rank then
        local x, y, u = xy(cn[1], cn[2])
        if u > 0.14 then
          label(x, y + 14, cn[4][col] or cn[4][1], f_tiny, { align = 'center' })
        end
      end
    end
  end

  -- the stars, brightest first, as many as the frame has room for (the facts below need ~40)
  local room = MAX_CMDS - 60
  if y_end < H then room = room - 10 end
  for i, st in ipairs(STARS) do
    if n >= room or (i % 32 == 0 and late()) then break end
    local x, y, u = xy(st[1], st[2])
    local free = u > 0
    if free then                                -- no star on top of a label
      for _, b in ipairs(boxes) do
        if x >= b[1] - 2 and x < b[1] + b[3] + 2 and y >= b[2] and y < b[2] + b[4] then free = false; break end
      end
    end
    if free then
      x, y = floor(x), floor(y)
      local m = st[3]
      if m < 3.5 then
        g:circle(x, y, m < 0.5 and 5 or m < 1.5 and 4 or m < 2.5 and 3 or 2, { fill = true, color = 0 })
      else
        g:rect(x - 1, y - 1, 2, 2, { fill = true, color = 0 })
      end
      n = n + 1
    end
  end

  -- under the chart: the moon, then the night's times, then the planets that are up
  local y = CY + R + 26
  local nt = night_times(s, place, off)
  moon_disc(g, 46, y + 30, 26, lit, waxing, lat < 0, false)
  local phase = WORDS[LANG].phases[floor(age / 29.530589 * 8 + 0.5) % 8 + 1]
  g:text(86, y + 4, phase .. ', ' .. string.format(word('lit'), floor(lit * 100 + 0.5)), { font = f_mid })
  g:text(86, y + 34, word('rises') .. ' ' .. hhmm(nt.mrise, off) .. '   ' .. word('sets') .. ' ' .. hhmm(nt.mset, off), { font = f_small })
  y = y + 72
  g:line(20, y, W - 20, y)
  local cols = { { 'sunset', nt.sunset }, { 'dark', nt.dark }, { 'sunrise', nt.sunrise } }
  local cw = (W - 40) // 3
  local f_time = font_px(26)
  for i, cv in ipairs(cols) do
    local x = 20 + (i - 1) * cw
    g:text(x, y + 8, word(cv[1]), { font = f_small })
    g:text(x, y + 30, hhmm(cv[2], off), { font = f_time })
  end
  y = y + 70
  local parts = {}
  table.sort(up, function(a, b) return a[2] > b[2] end)
  for _, p in ipairs(up) do
    parts[#parts + 1] = string.format('%s %s %d°', WORDS[LANG].planets[p[1]], dir_word(p[3]), floor(p[2] + 0.5))
  end
  local ptxt = #parts > 0 and table.concat(parts, '  ·  ') or word('none_up')
  local fp = f_small
  if text_w(fp, ptxt) > W - 40 then fp = f_tiny end
  if y + 20 < y_end then g:text(20, y, ptxt, { font = fp }) end
  if y_end >= H then                            -- the lock screen has room for the next phases
    local full, new = next_phase(s, 180), next_phase(s, 0)
    local a = word('full') .. ' ' .. date_text(full, off)
    local b = word('new') .. ' ' .. date_text(new, off)
    if new < full then a, b = b, a end
    g:line(20, y + 36, W - 20, y + 36)
    local one = a .. '   ·   ' .. b
    if text_w(f_small, one) <= W - 40 then
      g:text(20, y + 48, one, { font = f_small })
    else                                        -- the user's font is wider: one per line
      g:text(20, y + 44, a, { font = f_small })
      g:text(20, y + 70, b, { font = f_small })
    end
  end
  c(16)
  return n
end

if rawget(_G, '__TEST') then
  __TEST.sky = { civil = civil, next_phase = next_phase, default_view = default_view, night_times = night_times, project = project,
                 load_place = load_place, WORDS = WORDS, set_lang = function(l) LANG = l end }
end
