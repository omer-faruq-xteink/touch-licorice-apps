-- feeds.lua: RSS, Atom and OPML read as text, and HTML turned into the article text the layout
-- uses. No network, no screen: main.lua fetches, stores and draws.
--
--   F.parse_feed(body)          -> { title, link, items = { {id, title, link, date, summary, content} } }
--   F.is_feed(body), F.is_opml(body), F.discover(html, base) -> feed addresses a page names
--   F.parse_opml(text)          -> { title, feeds = { {title, url, site, path} } }  path: folder names, outermost first
--   F.write_opml(title, feeds)  -> the OPML text
--   F.date(s)                   -> seconds since 1970 (UTC), or nil
--   F.html_to_text(html, max, imgs, base), F.excerpt(html, n), F.absolute(src, base)
--   F.hash(s)                   -> 8 hex digits, for file names

local F = {}

------------------------------------------------------------------ text

local NAMED = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', ensp = ' ', emsp = ' ',
  thinsp = ' ', mdash = '\226\128\148', ndash = '\226\128\147', hellip = '\226\128\166',
  lsquo = '\226\128\152', rsquo = '\226\128\153', ldquo = '\226\128\156', rdquo = '\226\128\157',
  laquo = '\194\171', raquo = '\194\187', copy = '\194\169', reg = '\194\174', trade = '\226\132\162',
  middot = '\194\183', bull = '\226\128\162', euro = '\226\130\172', pound = '\194\163', deg = '\194\176',
  times = '\195\151', shy = '', zwj = '', zwnj = '' }

function F.decode_entities(t)
  return (t:gsub('&(#?[%w]+);', function(b)
    if b:sub(1, 1) == '#' then
      local hex = b:sub(2, 2) == 'x' or b:sub(2, 2) == 'X'
      local code = hex and tonumber(b:sub(3), 16) or tonumber(b:sub(2))
      if not code or code <= 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then return '' end
      if code < 0x20 and code ~= 9 and code ~= 10 and code ~= 13 then return '' end
      if code == 0xA0 then return ' ' end
      local ok, ch = pcall(utf8.char, code)
      return ok and ch or ''
    end
    return NAMED[b] or NAMED[b:lower()]
  end))
end

function F.url_encode(s)
  return (tostring(s):gsub('[^%w%-%._~]', function(ch) return string.format('%%%02X', ch:byte()) end))
end

-- a hash of an address, as 8 hex digits (file names may only hold [a-z0-9._-]); the arithmetic
-- stays within 31 bits, so it is the same on the reader's 32-bit integers
function F.hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) & 0x7fffffff end
  return string.format('%08x', h)
end

function F.absolute(src, base)
  src = tostring(src or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if src == '' or src:match('^data:') or src:match('^javascript:') then return nil end
  if src:match('^https?://') then return src end
  if src:sub(1, 2) == '//' then return 'https:' .. src end
  local origin = tostring(base or ''):match('^(https?://[^/]+)')
  if not origin then return nil end
  if src:sub(1, 1) == '/' then return origin .. src end
  local dir = tostring(base):match('^(https?://.*/)') or (origin .. '/')
  return dir .. src
end

-- Pictures: an article's <img> become "[[img:N]]" paragraphs and entries {n, w, h, src} in imgs,
-- src being a greyscale JPEG from the free images.weserv.nl resizer (the reader fetches it). With
-- width and height in the HTML the picture keeps that shape, fitted to the screen; without them it
-- fits a 456 x 342 box. Icons and tracking pixels are left out. (As in the wallabag app.)
local IMG_W, IMG_H, TINY_IMG, MAX_IMAGES = 456, 640, 80, 12

local function attr(tag, name)
  local v = tag:match('[%s]' .. name .. '%s*=%s*"([^"]*)"') or tag:match('[%s]' .. name .. "%s*=%s*'([^']*)'")
    or tag:match('[%s]' .. name .. '%s*=%s*([^%s>"\']+)')
  return v and F.decode_entities(v) or nil
end
F.attr = attr

local function picture(tag, base)
  local src = attr(tag, 'data%-src') or attr(tag, 'data%-original') or attr(tag, 'data%-lazy%-src')
  local plain = attr(tag, 'src')
  if not src and plain and not plain:match('^data:') then src = plain end
  if not src then
    local set = attr(tag, 'srcset') or attr(tag, 'data%-srcset')
    src = set and set:match('^%s*([^%s,]+)')
  end
  src = F.absolute(src, base)
  if not src then return nil end
  local w = tonumber((attr(tag, 'width') or ''):match('^%s*(%d+)%s*$'))
  local h = tonumber((attr(tag, 'height') or ''):match('^%s*(%d+)%s*$'))
  if (w and w <= 2) or (h and h <= 2) then return nil end
  if w and h and w <= TINY_IMG and h <= TINY_IMG then return nil end
  if w and h then
    if w > IMG_W then h = (h * IMG_W + w // 2) // w; w = IMG_W end
    if h > IMG_H then w = (w * IMG_H + h // 2) // h; h = IMG_H end
    w, h = math.max(w, 16), math.max(h, 16)
  else
    w, h = IMG_W, 342
  end
  return { w = w, h = h, src = 'https://images.weserv.nl/?url=' .. F.url_encode(src) .. '&w=' .. w .. '&h=' .. h
    .. '&fit=contain&cbg=white&output=jpg&q=70&filt=greyscale' }
end

-- HTML -> text with the markers the layout styles: paragraphs split by a blank line, "# "
-- headings, "> " quotes, "• " list items. Source line breaks are spaces, as in a browser.
local DROP = { script = true, style = true, svg = true, iframe = true, noscript = true, template = true, head = true }
local BLOCK_END = { p = true, div = true, li = true, blockquote = true, pre = true, tr = true, figure = true,
  figcaption = true, dd = true, dt = true, section = true, article = true, header = true, footer = true,
  table = true, ul = true, ol = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true }

function F.html_to_text(html, max, imgs, base)
  local src = tostring(html or ''):gsub('<!%-%-.-%-%->', ' ')
  local out, i, n, skip = {}, 1, #src, nil
  while i <= n do
    local a = src:find('<', i, true)
    if not a then
      if not skip then out[#out + 1] = (src:sub(i):gsub('[\r\n\t]', ' ')) end
      break
    end
    if not skip and a > i then out[#out + 1] = (src:sub(i, a - 1):gsub('[\r\n\t]', ' ')) end
    local b = src:find('>', a, true)
    if not b then break end
    local tag = src:sub(a + 1, b - 1)
    local close, name = tag:match('^(/?)%s*([%a][%w]*)')
    name = name and name:lower()
    if skip then
      if close == '/' and name == skip then skip = nil end
    elseif name then
      if close == '' and DROP[name] and not tag:match('/%s*$') then skip = name
      elseif name == 'br' then out[#out + 1] = '\n'
      elseif close == '' and name:match('^h[1-6]$') then out[#out + 1] = '\n\n# '
      elseif close == '' and name == 'blockquote' then out[#out + 1] = '\n\n> '
      elseif close == '' and name == 'hr' then out[#out + 1] = '\n\n* * *\n\n'
      elseif close == '' and name == 'li' then out[#out + 1] = '\n\226\128\162 '
      elseif close == '' and (name == 'p' or name == 'div') then out[#out + 1] = '\n\n'
      elseif close == '' and name == 'img' and imgs and #imgs < MAX_IMAGES then
        local pic = picture(' ' .. tag:sub(4), base)
        if pic then imgs[#imgs + 1] = pic; pic.n = #imgs; out[#out + 1] = '\n\n[[img:' .. #imgs .. ']]\n\n' end
      elseif close == '/' and BLOCK_END[name] then out[#out + 1] = '\n\n' end
    end
    i = b + 1
  end
  local t = F.decode_entities(table.concat(out))
  t = t:gsub('\194\160', ' '):gsub('[ \t\f\v]+', ' '):gsub(' *\n *', '\n')
  for _ = 1, 2 do t = t:gsub('\n# *\n', '\n'):gsub('\n> *\n', '\n'):gsub('\n\226\128\162 *\n', '\n') end
  t = t:gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
  if max and #t > max then
    local cut = t:sub(1, max)
    local sp = cut:match('^.*() ')
    if sp and sp > max * 0.8 then cut = cut:sub(1, sp - 1) end
    cut = cut:gsub('[\192-\255][\128-\191]*$', '')
    t = cut .. '\226\128\166'
  end
  return t
end

-- a short plain summary: the text on one line, at most n bytes, ending on a whole character
function F.excerpt(html, n)
  local t = F.html_to_text(html or '', (n or 400) * 2):gsub('%[%[img:%d+%]%]', ''):gsub('[#>]%s', ''):gsub('%s+', ' ')
  t = t:gsub('^%s+', ''):gsub('%s+$', '')
  n = n or 400
  if #t > n then
    t = t:sub(1, n):gsub('[\192-\255][\128-\191]*$', '')
    local sp = t:match('^.*() ')
    if sp and sp > n * 0.7 then t = t:sub(1, sp - 1) end
    t = t .. '\226\128\166'
  end
  return t
end

------------------------------------------------------------------ dates

local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }
local ZONES = { ut = 0, utc = 0, gmt = 0, z = 0, est = -300, edt = -240, cst = -360, cdt = -300, mst = -420,
  mdt = -360, pst = -480, pdt = -420, cet = 60, cest = 120, bst = 60 }

-- days since 1970-01-01 of a calendar date (Howard Hinnant's days_from_civil)
local function days(y, m, d)
  y = (m <= 2) and (y - 1) or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function zone_minutes(z)
  if not z or z == '' then return 0 end
  local sign, hh, mm = z:match('^([%+%-])(%d%d):?(%d%d)$')
  if sign then
    local m = tonumber(hh) * 60 + tonumber(mm)
    return sign == '-' and -m or m
  end
  return ZONES[z:lower()] or 0
end

-- RFC 822 ("Wed, 30 Oct 2026 16:00:00 +0000") or ISO 8601 ("2026-10-30T16:00:00+03:00")
function F.date(s)
  if type(s) ~= 'string' then return nil end
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  local d, mon, y, hh, mi, ss, z = s:match('(%d%d?)%s+(%a%a%a)%a*%.?%s+(%d%d%d?%d?)%s+(%d%d?):(%d%d):?(%d*)%s*([%+%-]?%w*:?%w*)')
  if d then
    local m = MONTHS[mon:lower()]
    if not m then return nil end
    y = tonumber(y); if y < 100 then y = y + 2000 end
    return days(y, m, tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mi) * 60 + (tonumber(ss) or 0) - zone_minutes(z) * 60
  end
  local yy, mm, dd, rest = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$')
  if yy then
    local h2, m2, s2 = rest:match('^[Tt ](%d%d):(%d%d):?(%d*)')
    local zz = rest:match('([Zz])$') or rest:match('([%+%-]%d%d:?%d%d)$')
    return days(tonumber(yy), tonumber(mm), tonumber(dd)) * 86400 + (tonumber(h2) or 0) * 3600
      + (tonumber(m2) or 0) * 60 + (tonumber(s2) or 0) - zone_minutes(zz) * 60
  end
  return nil
end

-- seconds since 1970 -> "2026-10-30 16:00", shifted by the reader's offset from UTC in minutes
-- (Howard Hinnant's civil_from_days)
function F.format_date(t, offset_min)
  if not t then return '' end
  t = t + (offset_min or 0) * 60
  local z = t // 86400 + 719468
  local secs = t % 86400
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp + (mp < 10 and 3 or -9)
  if m <= 2 then y = y + 1 end
  return string.format('%04d-%02d-%02d %02d:%02d', y, m, d, secs // 3600, secs % 3600 // 60)
end

------------------------------------------------------------------ feeds

-- the text inside an element: CDATA unwrapped, tags kept (they are HTML), entities decoded once
local function inner(s)
  if not s then return nil end
  if s:find('<![CDATA[', 1, true) then
    s = s:gsub('<!%[CDATA%[(.-)%]%]>', function(c) return (c:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')) end)
  end
  return F.decode_entities(s)
end

-- the first <name ...>...</name> in block (any namespace prefix written as in the feed)
local function element(block, name)
  local _, b = block:find('<' .. name .. '[%s>]')
  if not b then return nil end
  if block:sub(b, b) ~= '>' then
    local e = block:find('>', b, true)
    if not e then return nil end
    if block:sub(e - 1, e - 1) == '/' then return '' end
    b = e
  end
  local c = block:find('</' .. name .. '%s*>', b + 1)
  if not c then return nil end
  return block:sub(b + 1, c - 1)
end

-- an element as plain text: a CDATA section is literal text ("First <post>" stays so); outside it
-- tags are markup and go, and entities are decoded
local function plain(s)
  if not s then return nil end
  local lit = {}
  s = s:gsub('<!%[CDATA%[(.-)%]%]>', function(c) lit[#lit + 1] = c; return '\1' .. #lit .. '\1' end)
  s = F.decode_entities((s:gsub('<[^>]*>', '')))
  s = s:gsub('\1(%d+)\1', function(k) return lit[tonumber(k)] end)
  return (s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

local function atom_link(block)
  local first
  for tag in block:gmatch('<link%s[^>]*>') do
    local rel = attr(' ' .. tag:sub(6), 'rel')
    local href = attr(' ' .. tag:sub(6), 'href')
    if href then
      if not rel or rel == 'alternate' then return href end
      first = first or href
    end
  end
  return first
end

function F.is_feed(body)
  local head = (body or ''):sub(1, 2048)
  return head:find('<rss[%s>]') or head:find('<feed[%s>]') or head:find('<rdf:RDF[%s>]') or head:find('<channel[%s>]')
end
function F.is_opml(body) return (body or ''):sub(1, 2048):find('<opml[%s>]') ~= nil end

-- Only whole items count, so a feed cut short (the reader keeps 128 KB of an answer) still gives
-- its newest items. kind: 'rss' (and RSS 1.0 / RDF) or 'atom'.
function F.parse_feed(body)
  if type(body) ~= 'string' or not F.is_feed(body) then return nil, 'not a feed' end
  local atom = body:sub(1, 2048):find('<feed[%s>]') ~= nil
  local open, close = atom and '<entry[%s>]' or '<item[%s>]', atom and '</entry>' or '</item>'
  local first = body:find(open) or #body + 1
  local head = body:sub(1, first - 1)
  local feed = { title = plain(element(head, 'title')) or '', items = {} }
  feed.link = atom and atom_link(head) or plain(element(head, 'link'))
  local pos = 1
  while true do
    local a = body:find(open, pos)
    if not a then break end
    local b = body:find(close, a, true)
    if not b then break end                       -- the last one was cut off
    local block = body:sub(a, b - 1)
    pos = b + #close
    local it = { title = plain(element(block, 'title')) or '' }
    if atom then
      it.link = atom_link(block)
      it.id = plain(element(block, 'id'))
      it.date = F.date(plain(element(block, 'published')) or plain(element(block, 'updated')))
      it.summary = inner(element(block, 'summary'))
      it.content = inner(element(block, 'content'))
    else
      it.link = plain(element(block, 'link'))
      if not it.link or it.link == '' then
        local g = block:match('<guid[^>]-isPermaLink%s*=%s*["\']true["\'][^>]*>(.-)</guid>')
        it.link = plain(g)
      end
      it.id = plain(element(block, 'guid'))
      it.date = F.date(plain(element(block, 'pubDate')) or plain(element(block, 'dc:date')))
      it.summary = inner(element(block, 'description'))
      it.content = inner(element(block, 'content:encoded'))
    end
    if it.link then it.link = F.absolute(it.link, feed.link) or it.link end
    if not it.id or it.id == '' then it.id = it.link or it.title end
    if it.id and it.id ~= '' then feed.items[#feed.items + 1] = it end
  end
  return feed
end

-- feed addresses named by a page's <link rel="alternate" type="application/rss+xml" ...>
function F.discover(html, base)
  local out = {}
  for tag in tostring(html or ''):sub(1, 131072):gmatch('<link%s[^>]*>') do
    local t = ' ' .. tag:sub(6)
    local rel, ty, href = (attr(t, 'rel') or ''):lower(), (attr(t, 'type') or ''):lower(), attr(t, 'href')
    if href and rel:find('alternate', 1, true) and (ty:find('rss', 1, true) or ty:find('atom', 1, true)) then
      local u = F.absolute(href, base)
      if u then out[#out + 1] = { url = u, title = attr(t, 'title') } end
    end
  end
  return out
end

------------------------------------------------------------------ OPML

function F.parse_opml(text)
  text = tostring(text or '')
  local out = { title = plain(element(text, 'title')) or '', feeds = {} }
  local open = {}                -- the outlines around this one: a folder name, or false for a feed
  local pos = 1
  local function path()
    local p = {}
    for _, n in ipairs(open) do if n then p[#p + 1] = n end end
    return p
  end
  while true do
    local a, b, tag = text:find('<(/?outline[^>]*)>', pos)
    if not a then break end
    pos = b + 1
    if tag:sub(1, 1) == '/' then
      table.remove(open)
    else
      local t = ' ' .. tag:sub(8)
      local url = attr(t, 'xmlUrl') or attr(t, 'xmlurl')
      local name = attr(t, 'title') or attr(t, 'text') or ''
      if url then
        out.feeds[#out.feeds + 1] = { title = name ~= '' and name or url, url = url, site = attr(t, 'htmlUrl'), path = path() }
      end
      if not tag:match('/%s*$') then open[#open + 1] = (not url) and name or false end
    end
  end
  return out
end

local function xml(s)
  return (tostring(s or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

-- folders kept, nested as in f.path: a folder's feeds first, then its folders, in the order met
function F.write_opml(title, feeds)
  local out = { '<?xml version="1.0" encoding="UTF-8"?>', '<opml version="2.0">', '  <head>',
    '    <title>' .. xml(title) .. '</title>', '  </head>', '  <body>' }
  local root = { feeds = {}, kids = {}, by = {} }
  for _, f in ipairs(feeds) do
    local node = root
    for _, name in ipairs(f.path or {}) do
      if not node.by[name] then
        local k = { name = name, feeds = {}, kids = {}, by = {} }
        node.by[name] = k; node.kids[#node.kids + 1] = k
      end
      node = node.by[name]
    end
    node.feeds[#node.feeds + 1] = f
  end
  local function put(node, ind)
    for _, f in ipairs(node.feeds) do
      out[#out + 1] = ind .. '<outline type="rss" text="' .. xml(f.title) .. '" title="' .. xml(f.title) .. '" xmlUrl="' .. xml(f.url) .. '"'
        .. (f.site and f.site ~= '' and (' htmlUrl="' .. xml(f.site) .. '"') or '') .. '/>'
    end
    for _, k in ipairs(node.kids) do
      out[#out + 1] = ind .. '<outline text="' .. xml(k.name) .. '" title="' .. xml(k.name) .. '">'
      put(k, ind .. '  ')
      out[#out + 1] = ind .. '</outline>'
    end
  end
  put(root, '    ')
  out[#out + 1] = '  </body>'
  out[#out + 1] = '</opml>'
  return table.concat(out, '\n') .. '\n'
end

return F
