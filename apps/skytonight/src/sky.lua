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
         planets = { mercury = 'Mercury', venus = 'Venus', mars = 'Mars', jupiter = 'Jupiter', saturn = 'Saturn' },
         zoom_out = 'Zoom out', brightest = 'Brightest', evenings = 'Evenings', card = 'Card', names = 'Names', lines = 'Lines', objects = 'Objects',
         months_long = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
                         'October', 'November', 'December' } },
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
         planets = { mercury = 'Merkür', venus = 'Venüs', mars = 'Mars', jupiter = 'Jüpiter', saturn = 'Satürn' },
         zoom_out = 'Uzaklaş', brightest = 'En parlak', evenings = 'Akşamları', card = 'Kart', names = 'Yazılar', lines = 'Çizgiler', objects = 'Cisimler',
         months_long = { 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül',
                         'Ekim', 'Kasım', 'Aralık' } },
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
         planets = { mercury = 'Merkur', venus = 'Venus', mars = 'Mars', jupiter = 'Jupiter', saturn = 'Saturn' },
         zoom_out = 'Übersicht', brightest = 'Hellste', evenings = 'Abends', card = 'Karte', names = 'Namen', lines = 'Linien', objects = 'Objekte',
         months_long = { 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September',
                         'Oktober', 'November', 'Dezember' } },
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
  if not (ok and type(s) == 'string') then return nil end
  return (s:gsub('\r', ''))                      -- settings.txt edited on a PC: Windows line ends
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

------------------------------------------------------------------ errors and the debug log

-- DEBUG (set by `bundle.py --debug`): each step is written to DEBUG_FILE as it happens, with the
-- milliseconds since start and the heap, so a step the host kills the app in is still on the card
-- (AppFiles/skytonight/debug.txt). An error at start is shown on the screen in full either way.
local DEBUG = false
local DEBUG_FILE = 'debug.txt'
local dbg_t0, dbg_log = nil, {}
local function dbg(msg)
  if not DEBUG then return end
  pcall(function()
    local ok, ms = pcall(function() return ctx.clock:millis() end)
    ms = (ok and math.type(ms) == 'integer') and ms or 0
    dbg_t0 = dbg_t0 or ms
    local okm, kb = pcall(function() return ctx.gc:count() // 1024 end)
    dbg_log[#dbg_log + 1] = tostring((ms - dbg_t0) & 0x7FFFFFFF) .. ' ms  ' .. (okm and tostring(kb) or '?') .. ' KB  ' .. tostring(msg)
    swrite(DEBUG_FILE, table.concat(dbg_log, '\n') .. '\n')
  end)
end

-- the error message with the call chain when the host has debug.traceback
local function trace(e)
  local ok, tb = pcall(function() return debug.traceback(tostring(e), 2) end)
  return (ok and type(tb) == 'string') and tb or tostring(e)
end

-- an error in full on the screen, cut into lines that fit
local function draw_error(g, title, msg, y)
  y = y or 40
  pcall(function() g:text(10, y, title) end)
  y = y + 30
  for raw in (msg .. '\n'):gmatch('([^\n]*)\n') do
    local line = raw:gsub('\t', '  ')
    while #line > 0 and y < H - 80 do
      local part = line:sub(1, 46)
      pcall(function() g:text(10, y, part) end)
      line = line:sub(47); y = y + 22
    end
  end
  return y
end

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
-- "ra dec rank ABBR en|tr|de" (ABBR: the IAU abbreviation); stars_named.txt "ra dec name"
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
  for ra, dec, rank, abbr, names in pread('names.txt'):gmatch('(%S+) (%S+) (%d) (%S+) ([^\n]+)') do
    local n = {}
    for part in (names .. '|'):gmatch('([^|]*)|') do n[#n + 1] = part end
    CNAMES[#CNAMES + 1] = { tonumber(ra), tonumber(dec), tonumber(rank), n, abbr }
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

-- the zoomed view (1.1.0): the chart ZOOM times larger in the band WIN_Y0..WIN_Y1, the chart point
-- (view.zx, view.zy) at its centre
local ZOOM = 2.5
local WIN_Y0, WIN_Y1 = 92, 500
-- the window's bottom: WIN_Y1 with the card under it, view.win_y1 (down to the buttons) without
local function win_y1(view) return view.win_y1 or WIN_Y1 end
local function win_cy(view) return (WIN_Y0 + win_y1(view)) // 2 end

local function to_screen(x, y, view)
  if not view.zoom then return x, y end
  return (x - view.zx) * view.zoom + CX, (y - view.zy) * view.zoom + win_cy(view)
end

-- a star's place on the screen and u, the sine of its altitude (up when u > 0)
local function radec_to_screen(ra, dec, view)
  local lat = view.place.lat
  local h, d = (A.gmst(view.s) + view.place.lon - ra) * rad, dec * rad
  local sl, cl = sin(lat * rad), cos(lat * rad)
  local sd, cd, ch = sin(d), cos(d), cos(h)
  local u = sd * sl + cd * cl * ch
  local k = R / (1 + u)
  local x, y = to_screen(CX + k * cd * sin(h), CY - k * (sd * cl - cd * sl * ch), view)
  return x, y, u
end

-- the other way: a point on the screen -> ra, dec (degrees), or nil outside the horizon
local function chart_to_radec(sx, sy, view)
  local x, y = sx, sy
  if view.zoom then x, y = (sx - CX) / view.zoom + view.zx, (sy - win_cy(view)) / view.zoom + view.zy end
  local X, Y = (x - CX) / R, (CY - y) / R
  local rho2 = X * X + Y * Y
  if rho2 > 1 then return nil end
  local u = (1 - rho2) / (1 + rho2)                 -- stereographic: rho^2 = (1 - u) / (1 + u)
  local xe, yn = X * (1 + u), Y * (1 + u)
  local lat = view.place.lat
  local sl, cl = sin(lat * rad), cos(lat * rad)
  local sd = u * sl + yn * cl
  local h = math.atan(xe, u * cl - yn * sl) / rad
  local dec = math.asin(math.max(-1, math.min(1, sd))) / rad
  return (A.gmst(view.s) + view.place.lon - h) % 360, dec
end

-- the IAU boundaries (bounds.txt "ABBR N ra dec ..."), read on the first use
local BOUNDS
local function load_bounds()
  if BOUNDS then return end
  BOUNDS = {}
  for ab, north, rest in pread('bounds.txt'):gmatch('(%S+) (%d) ([^\n]+)') do
    local xs, ys = {}, {}
    for a, b in rest:gmatch('(%S+) (%S+)') do xs[#xs + 1] = tonumber(a); ys[#ys + 1] = tonumber(b) end
    BOUNDS[#BOUNDS + 1] = { ab, north == '1', xs, ys }
  end
end

local function constellation_at(ra, dec)
  load_bounds()
  -- the meridian from the point up to the north pole crosses a polygon's edges an odd number of
  -- times when the point is inside (an even number for UMi, which holds the pole); each edge the
  -- short way round in RA, so 0/360 is no seam
  for _, b in ipairs(BOUNDS) do
    local xs, ys = b[3], b[4]
    local hit, n = b[2], #xs
    for i = 1, n do
      local j = i % n + 1
      local a1 = (xs[i] - ra + 180) % 360 - 180
      local a2 = (xs[j] - ra + 180) % 360 - 180
      if (a1 > 0) ~= (a2 > 0) and math.abs(a1 - a2) < 180 then
        if ys[i] + (ys[j] - ys[i]) * a1 / (a1 - a2) > dec then hit = not hit end
      end
    end
    if hit then return b[1] end
  end
  return nil
end

-- the cards (cards.txt "ABBR|story|stars|ids") and the deep-sky objects (objects.txt "ID type ra dec
-- mag ABBR|name|note"), read on the first zoom
-- In Turkish and German, cards_<lang>.txt (the same lines) gives the stories and objects_<lang>.txt
-- ("ID|name|note") the objects' names and notes; a line missing there stays English. Read again
-- when the language changes (the Place page's language button).
local CARDS, OBJECTS, OBJ_BY_ID, CARDS_LANG
local function load_cards()
  if CARDS and CARDS_LANG == LANG then return end
  CARDS, OBJECTS, OBJ_BY_ID, CARDS_LANG = {}, {}, {}, LANG
  for ab, st, sn, il in pread('cards.txt'):gmatch('([^|\n]+)|([^|\n]*)|([^|\n]*)|([^\n]*)') do
    local list = {}
    for id in il:gmatch('%S+') do list[#list + 1] = id end
    CARDS[ab] = { story = st, stars = sn, ids = list }
  end
  for id, ty, ra, dec, mag, ab, name, note in
      pread('objects.txt'):gmatch('(%S+) (%S+) (%S+) (%S+) (%S+) ([^|\n]+)|([^|\n]*)|([^\n]*)') do
    local o = { id = id, type = ty, ra = tonumber(ra), dec = tonumber(dec), mag = tonumber(mag), abbr = ab, name = name, note = note }
    OBJECTS[#OBJECTS + 1] = o
    OBJ_BY_ID[id] = o
  end
  if LANG ~= 'en' then
    for ab, st in pread('cards_' .. LANG .. '.txt'):gmatch('([^|\n]+)|([^|\n]*)|[^\n]*') do
      if CARDS[ab] and st ~= '' then CARDS[ab].story = st end
    end
    for id, name, note in pread('objects_' .. LANG .. '.txt'):gmatch('([^|\n]+)|([^|\n]*)|([^\n]*)') do
      local o = OBJ_BY_ID[id]
      if o then
        if name ~= '' then o.name = name end
        if note ~= '' then o.note = note end
      end
    end
  end
end

-- a segment cut to a rectangle (Liang-Barsky); nil when it misses it
local function clip_seg(x1, y1, x2, y2, x0, y0, xm, ym)
  local t0, t1 = 0, 1
  local dx, dy = x2 - x1, y2 - y1
  local ps = { -dx, dx, -dy, dy }
  local qs = { x1 - x0, xm - x1, y1 - y0, ym - y1 }
  for i = 1, 4 do
    local p, q = ps[i], qs[i]
    if p == 0 then
      if q < 0 then return nil end
    else
      local r = q / p
      if p < 0 then
        if r > t1 then return nil elseif r > t0 then t0 = r end
      else
        if r < t0 then return nil elseif r < t1 then t1 = r end
      end
    end
  end
  return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

-- a polygon ({x, y} points) cut to a rectangle (Sutherland-Hodgman), as a flat list
local function clip_poly(pts, x0, y0, xm, ym)
  local function cut(list, inside, cross)
    local out = {}
    for i = 1, #list do
      local p, q = list[i], list[i % #list + 1]
      local pin, qin = inside(p), inside(q)
      if pin then out[#out + 1] = p end
      if pin ~= qin then out[#out + 1] = cross(p, q) end
    end
    return out
  end
  local function at_x(x) return function(p, q) local t = (x - p[1]) / (q[1] - p[1]); return { x, p[2] + t * (q[2] - p[2]) } end end
  local function at_y(y) return function(p, q) local t = (y - p[2]) / (q[2] - p[2]); return { p[1] + t * (q[1] - p[1]), y } end end
  pts = cut(pts, function(p) return p[1] >= x0 end, at_x(x0))
  if #pts > 0 then pts = cut(pts, function(p) return p[1] <= xm end, at_x(xm)) end
  if #pts > 0 then pts = cut(pts, function(p) return p[2] >= y0 end, at_y(y0)) end
  if #pts > 0 then pts = cut(pts, function(p) return p[2] <= ym end, at_y(ym)) end
  local flat = {}
  for _, p in ipairs(pts) do flat[#flat + 1] = floor(p[1] + 0.5); flat[#flat + 1] = floor(p[2] + 0.5) end
  return flat
end

-- words of s in lines no wider than maxw
local function wrap(f, s, maxw)
  local out, line = {}, ''
  for word_ in s:gmatch('%S+') do
    local cand = line == '' and word_ or (line .. ' ' .. word_)
    if line ~= '' and text_w(f, cand) > maxw then out[#out + 1] = line; line = word_ else line = cand end
  end
  if line ~= '' then out[#out + 1] = line end
  return out
end

-- the month when a point of right ascension ra (degrees) is due south (north, in the south) at
-- 21:00: then the Sun's RA is ra - 9 h; the Sun's RA is 0 h on 21 March and gains 2 h a month
local function evening_month(ra)
  return (2 + floor(((ra / 15 - 9) % 24) / 2 + 0.5)) % 12 + 1
end

-- the card of constellation ab in y0..y1: its name, when to look, the story, the brightest stars,
-- the objects; what does not fit is left out from the end. c(k) counts the frame's commands.
local function draw_card(g, ab, y0, y1, c)
  load_cards()
  local name, ra
  for _, cn in ipairs(CNAMES) do
    if cn[5] == ab then name, ra = cn[4][NAME_COL[LANG]] or cn[4][1], cn[1]; break end
  end
  if not name then return end
  local f_name, f_text, f_obj = font_px(24), font_px(16), font_px(15)
  local lh_t, lh_o = f_text.line_height or 20, f_obj.line_height or 19
  local y = y0
  if c(2) then
    g:text(20, y, name, { font = f_name })
    g:text(W - 20, y + 6, word('evenings') .. ': ' .. WORDS[LANG].months_long[evening_month(ra)], { font = f_text, align = 'right' })
  end
  y = y + (f_name.line_height or 30) + 4
  local card = CARDS[ab]
  if not card then return end
  local lines = wrap(f_text, card.story, W - 40)
  if card.stars ~= '' then lines[#lines + 1] = word('brightest') .. ': ' .. card.stars end
  for _, l in ipairs(lines) do
    if y + lh_t > y1 or not c() then return end
    g:text(20, y, l, { font = f_text })
    y = y + lh_t
  end
  y = y + 4
  for _, id in ipairs(card.ids) do
    local o = OBJ_BY_ID[id]
    if o then                                       -- an object whole or not at all
      local ls = wrap(f_obj, o.id .. (o.name ~= o.id and (' ' .. o.name) or '') .. ': ' .. o.note, W - 40)
      if y + #ls * lh_o > y1 or not c(#ls) then return end
      for k, l in ipairs(ls) do
        g:text(k == 1 and 20 or 32, y, l, { font = f_obj })
        y = y + lh_o
      end
    end
  end
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
  dbg('draw_sky ' .. tostring(view.place and view.place.name) .. ' s=' .. tostring(view.s) .. ' off=' .. tostring(view.off))
  load_data()
  dbg('data: ' .. #STARS .. ' stars, ' .. #LINES .. ' lines, ' .. #CNAMES .. ' names')
  HOUR12 = view.hour12 and true or false
  local s, place, off = view.s, view.place, view.off
  local lat, lon = place.lat, place.lon
  local lst = A.gmst(s) + lon
  local n = 0
  local function c(k) n = n + (k or 1); return n <= MAX_CMDS end
  local white = { color = 0 }
  local sl, cl = sin(lat * rad), cos(lat * rad)
  -- zoomed (1.1.0): the chart Z times larger in the window WIN_Y0..WIN_Y1; DCX, DCY, DR: the
  -- horizon's circle on the screen
  local Z = view.zoom
  local WY1 = win_y1(view)                         -- the zoomed window's bottom
  local DCX, DCY = to_screen(CX, CY, view)
  local DR = Z and R * Z or R
  local function inwin(x, y, m)
    m = m or 0
    return x >= -m and x <= W + m and y >= WIN_Y0 - m and y <= WY1 + m
  end
  local function proj(alt, az) local x, y = project(alt, az); return to_screen(x, y, view) end
  -- a star's place on the chart and u, the sine of its altitude (above the horizon when u > 0):
  -- the stereographic projection straight from the direction vector, four sines per star
  local function xy(ra, dec)
    local h, d = (lst - ra) * rad, dec * rad
    local sd, cd, ch = sin(d), cos(d), cos(h)
    local u = sd * sl + cd * cl * ch
    local k = R / (1 + u)
    local x, y = CX + k * cd * sin(h), CY - k * (sd * cl - cd * sl * ch)
    if Z then x, y = to_screen(x, y, view) end
    return x, y, u
  end
  local function late()
    if not view.budget_ms then return false end
    local ok, ms = pcall(function() return ctx.clock:millis() end)
    return ok and type(ms) == 'number' and ((ms - view.start_ms) & 0x7FFFFFFF) > view.budget_ms
  end

  -- header: the place, the date and the time
  local f_big, f_mid, f_small, f_tiny = font_px(30), font_px(20), font_px(16), font_px(14)
  local function header()
    g:text(20, 16, place.name, { font = f_big })
    g:text(W - 20, 16, hhmm(s, off), { font = f_big, align = 'right' })
    local sub = date_text(s, off) .. (view.label and ('  ·  ' .. word(view.label)) or '')
    g:text(20, 58, sub, { font = f_mid })
    c(3)
  end
  if not Z then header() end                       -- zoomed: drawn last, over the chart's overflow

  if Z then
    -- the part of the black disc inside the window
    local pts = {}
    for k = 0, 63 do
      local a = k * (2 * math.pi / 64)
      pts[#pts + 1] = { DCX + DR * cos(a), DCY + DR * sin(a) }
    end
    local flat = clip_poly(pts, 0, WIN_Y0, W, WY1)
    if #flat >= 6 and c() then g:polygon(flat, { fill = true }) end
  else
    -- the sky: a black disc, the compass points around it
    g:circle(CX, CY, R, { fill = true })
    local fpt = font_px(18)
    for i, ang in ipairs({ 0, 90, 180, 270 }) do
      local x, y = CX - (R + 13) * sin(ang * rad), CY - (R + 13) * cos(ang * rad)
      g:text(floor(x), floor(y), WORDS[LANG].dirs[(i - 1) * 2 + 1], { font = fpt, align = 'center', valign = 'middle' })
    end
    c(5)
  end

  -- labels: kept apart from each other and inside the disc (and the window, zoomed)
  local boxes = {}
  local function label(x, y, s_, f, opts)
    if view.no_names then return false end         -- the app's menu: Names off
    local w, h = text_w(f, s_), f.line_height or 18
    local x0 = opts and opts.align == 'center' and x - w // 2 or x
    local y0 = y - h // 2
    if Z and (x0 < 4 or x0 + w > W - 4 or y0 < WIN_Y0 + 2 or y0 + h > WY1 - 2) then return false end
    local dy = y0 + h / 2 - DCY
    for _, ex in ipairs({ x0, x0 + w }) do
      local dx = ex - DCX
      if dx * dx + dy * dy > (DR - 6) * (DR - 6) then return false end
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
  dbg('figures (' .. n .. ' commands)')
  for _, pts in ipairs(view.no_lines and {} or LINES) do   -- the app's menu: Lines off, none
    local out, px, py, palt = {}, nil, nil, nil
    local function flush()
      if Z then                                   -- zoomed: each segment cut to the window
        local piece = {}
        local function emit()
          if #piece >= 4 and c() then g:polyline(piece, white) end
          piece = {}
        end
        for i = 1, #out - 3, 2 do
          local a, b, c2, d = clip_seg(out[i], out[i + 1], out[i + 2], out[i + 3], 0, WIN_Y0, W, WY1)
          if a then
            a, b, c2, d = floor(a), floor(b), floor(c2), floor(d)
            if #piece == 0 or piece[#piece - 1] ~= a or piece[#piece] ~= b then emit(); piece = { a, b } end
            piece[#piece + 1], piece[#piece + 2] = c2, d
          else
            emit()
          end
        end
        emit()
      elseif #out >= 4 and c() then
        g:polyline(out, white)
      end
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
          local ex, ey = px + (x - px) * t - DCX, py + (y - py) * t - DCY
          local d = sqrt(ex * ex + ey * ey)
          if d > 0 then ex, ey = DCX + ex * DR / d, DCY + ey * DR / d end
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

  -- zoomed on a constellation: its boundary, dashed (edges cut in steps of 1.5 degrees, as the
  -- boundaries follow lines of RA and Dec, which are curves on the chart)
  if Z and view.card and not view.win_y1 then      -- only with the card (hidden: nothing is picked)
    load_bounds()
    for _, b in ipairs(BOUNDS) do
      if b[1] == view.card then
        local xs, ys, m = b[3], b[4], #b[3]
        local dash = false
        for i = 1, m do
          local j = i % m + 1
          local dra = (xs[j] - xs[i] + 180) % 360 - 180
          local ddec = ys[j] - ys[i]
          local steps = math.max(1, floor(math.max(math.abs(dra) * cos(ys[i] * rad), math.abs(ddec)) / 1.5) + 1)
          local px, py, pu = xy(xs[i], ys[i])
          for k = 1, steps do
            local qx, qy, qu = xy(xs[i] + dra * k / steps, ys[i] + ddec * k / steps)
            dash = not dash
            if dash and pu > 0 and qu > 0 then
              local a, b2, c2, d2 = clip_seg(px, py, qx, qy, 0, WIN_Y0, W, WY1)
              if a and c() then g:line(floor(a), floor(b2), floor(c2), floor(d2), white) end
            end
            px, py, pu = qx, qy, qu
          end
        end
      end
    end
  end

  -- the sun, the moon and the planets first, so their labels win
  dbg('sun, moon, planets (' .. n .. ' commands)')
  local _, sra, sdec = A.sun(s)
  local salt, saz = A.horizon(sra, sdec, lst, lat)
  local _, _, mra, mdec, mpar = A.moon(s)
  local malt, maz = A.horizon(mra, mdec, lst, lat)
  malt = malt - mpar * cos(malt * rad)
  local lit, waxing, age = A.phase(s)
  local f_lab = font_px(15)
  local sx, sy = proj(salt, saz)
  if salt > 0 and (not Z or inwin(sx, sy, -20)) and c(10) then
    local x, y = sx, sy
    g:circle(floor(x), floor(y), 9, { fill = true, color = 0 })
    for k = 0, 7 do
      local a = k * 45 * rad
      g:line(floor(x + 12 * cos(a)), floor(y + 12 * sin(a)), floor(x + 17 * cos(a)), floor(y + 17 * sin(a)), white)
    end
    label(x + 20, y, word('sun'), f_lab)
  end
  local mx, my = proj(malt, maz)
  if malt > 0 and (not Z or inwin(mx, my, -12)) and c(3) then
    local x, y = mx, my
    moon_disc(g, floor(x), floor(y), 10, lit, waxing, lat < 0, true)
    label(x + 14, y, word('moon'), f_lab)
  end
  local up = {}
  for _, name in ipairs(A.PLANETS) do
    local _, _, pra, pdec = A.planet(name, s)
    local palt, paz = A.horizon(pra, pdec, lst, lat)
    local x, y = proj(palt, paz)
    if palt > 0 and (not Z or inwin(x, y, -10)) and c(2) then
      g:circle(floor(x), floor(y), 4, { fill = true, color = 0 })
      g:circle(floor(x), floor(y), 8, { color = 0 })
      label(x + 11, y, WORDS[LANG].planets[name], f_lab)
      up[#up + 1] = { name, palt, paz }
    end
  end

  -- zoomed: the deep-sky objects in the window, a symbol each and its catalogue number
  if Z and not view.no_objects then                 -- the app's menu: Objects off, none
    load_cards()
    for _, o in ipairs(OBJECTS) do
      local x, y, u = xy(o.ra, o.dec)
      if u > 0 and inwin(x, y, -10) and c(2) then
        x, y = floor(x), floor(y)
        if o.type == 'gx' then                      -- a galaxy: an oval
          local pts = {}
          for k = 0, 12 do
            local a = k * (2 * math.pi / 12)
            pts[#pts + 1] = floor(x + 10 * cos(a) + 0.5); pts[#pts + 1] = floor(y + 4 * sin(a) + 0.5)
          end
          g:polyline(pts, white)
          n = n - 1
        elseif o.type == 'nb' then                  -- a nebula: a square
          g:rect(x - 6, y - 6, 12, 12, white)
          n = n - 1
        elseif o.type == 'gc' then                  -- a globular cluster: a ball
          g:circle(x, y, 3, { fill = true, color = 0 })
          g:circle(x, y, 7, white)
        elseif o.type == 'pn' then                  -- a planetary nebula: a ring with a dot
          g:circle(x, y, 1, { fill = true, color = 0 })
          g:circle(x, y, 5, white)
        else                                        -- an open cluster: a wide circle
          g:circle(x, y, 9, white)
          n = n - 1
        end
        label(x + 12, y, o.id, f_tiny)
      end
    end
  end

  -- named stars, then constellation names (best known first)
  dbg('names (' .. n .. ' commands)')
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
  dbg('stars (' .. n .. ' commands)')
  local room = MAX_CMDS - 60
  if y_end < H then room = room - 10 end
  for i, st in ipairs(STARS) do
    if n >= room or (i % 32 == 0 and late()) then break end
    local x, y, u = xy(st[1], st[2])
    local free = u > 0 and (not Z or inwin(x, y, -3))
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

  -- zoomed: paper over whatever reached past the window, the header, the card under it
  if Z then
    if c(3) then
      g:rect(0, 0, W, WIN_Y0, { fill = true, color = 0 })
      g:rect(0, WY1, W, H - WY1, { fill = true, color = 0 })
      g:line(0, WY1, W, WY1)
    end
    header()
    if view.card and not view.win_y1 then draw_card(g, view.card, WY1 + 10, y_end - 6, c) end
    dbg('draw_sky zoomed done (' .. n .. ' commands)')
    return n
  end

  -- under the chart: the moon, then the night's times, then the planets that are up
  dbg('facts (' .. n .. ' commands)')
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
  dbg('draw_sky done (' .. n .. ' commands)')
  return n
end

if rawget(_G, '__TEST') then
  __TEST.sky = { draw_sky = draw_sky, radec_to_screen = radec_to_screen, chart_to_radec = chart_to_radec, constellation_at = constellation_at,
                 civil = civil, next_phase = next_phase, default_view = default_view, trace = trace, night_times = night_times, project = project,
                 load_place = load_place, WORDS = WORDS, set_lang = function(l) LANG = l end }
end
