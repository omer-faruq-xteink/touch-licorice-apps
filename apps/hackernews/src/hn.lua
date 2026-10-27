-- Hacker News pieces that need no screen: the addresses of the two public APIs, HN's comment
-- HTML as plain text, ages and domains, and word wrap that also breaks words too long for a line
-- (addresses).
--
-- A list is HN's own ranking (Firebase: topstories.json ... a few KB of ids), its stories' titles
-- and counts come 24 at a time from one Algolia search for exactly those ids (tags
-- "(story_1,story_2,...)", about 7 KB). A story and each comment come from Firebase's item/<id>.json,
-- whose "kids" are the replies in HN's order.

local N = {}

N.FIREBASE = 'https://hacker-news.firebaseio.com/v0/'
N.ALGOLIA = 'https://hn.algolia.com/api/v1/'
N.PER_PAGE = 24
local FIELDS = '&attributesToRetrieve=title,url,points,num_comments,author,created_at_i&attributesToHighlight=%5B%5D'
N.LISTS = { top = 'topstories', new = 'newstories', best = 'beststories', ask = 'askstories', show = 'showstories' }

-- percent-encoding without %w (which follows the C locale and may take bytes of UTF-8 letters)
function N.enc(s)
  return (tostring(s):gsub('[^A-Za-z0-9%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

function N.ids_url(tab) return N.FIREBASE .. N.LISTS[tab] .. '.json' end
function N.item_url(id) return N.FIREBASE .. 'item/' .. id .. '.json' end
-- the stories with these ids, in any order
function N.stories_url(ids)
  local tags = {}
  for k, id in ipairs(ids) do tags[k] = 'story_' .. id end
  return N.ALGOLIA .. 'search?tags=' .. N.enc('(' .. table.concat(tags, ',') .. ')') .. '&hitsPerPage=' .. #ids .. FIELDS
end
-- a search: stories by relevance, page from 0
function N.search_url(q, page)
  return N.ALGOLIA .. 'search?tags=story&query=' .. N.enc(q) .. '&hitsPerPage=' .. N.PER_PAGE .. '&page=' .. page .. FIELDS
end

-- ids as strings, read from the raw JSON: a list of ids (topstories.json), or an item's "kids"
-- (the reader's Lua may have 32-bit numbers, where a decoded id could come back rounded)
function N.ids(body)
  local t = {}
  for id in tostring(body or ''):gmatch('%d+') do t[#t + 1] = id end
  return t
end
function N.kids(body)
  return N.ids(tostring(body or ''):match('"kids"%s*:%s*%[([%d,%s]*)%]'))
end

-- an Algolia hit -> a story row
function N.story(h)
  return { id = tostring(h.objectID), title = tostring(h.title or '(untitled)'), url = h.url and tostring(h.url) or nil,
           points = tonumber(h.points) or 0, comments = tonumber(h.num_comments) or 0,
           by = tostring(h.author or ''), time = tonumber(h.created_at_i) or 0 }
end
-- one list row as a line of text, and back (list_<tab>.txt keeps the last list for opening offline)
function N.row_text(s)
  return table.concat({ s.id, (s.title:gsub('[\t\n]', ' ')), s.url or '', s.points, s.comments, s.by, s.time }, '\t')
end
function N.row_parse(line)
  local id, title, url, points, comments, by, time = line:match('^(%d+)\t([^\t]*)\t([^\t]*)\t(%d*)\t(%d*)\t([^\t]*)\t(%d*)$')
  if not id then return nil end
  return { id = id, title = title, url = url ~= '' and url or nil, points = tonumber(points) or 0,
           comments = tonumber(comments) or 0, by = by, time = tonumber(time) or 0 }
end

function N.domain(url)
  local d = url and url:match('^%a+://([^/:?#]+)')
  return d and (d:gsub('^www%.', '')) or nil
end

function N.ago(t, now)
  if not t or t <= 0 or not now or now <= 0 then return '' end
  local s = math.max(0, now - t)
  local function n(d) return math.floor(s / d) end       -- an integer also when t came as a float
  if s < 3600 then return math.max(1, n(60)) .. ' min ago' end
  if s < 86400 then return n(3600) .. ' h ago' end
  if s < 86400 * 365 then return n(86400) .. ' d ago' end
  return n(86400 * 365) .. ' y ago'
end

-- HN's HTML (comments, Ask HN texts): <p> paragraphs, <i>, <a>, <pre><code>, entities
local ENT = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', hellip = '...', mdash = '-', ndash = '-' }
local function entity(e)
  local n = e:match('^#[xX](%x+)$')
  n = n and tonumber(n, 16) or tonumber(e:match('^#(%d+)$') or '')
  if n then return (n > 0 and n < 0x110000) and utf8.char(n) or '' end
  return ENT[e] or ('&' .. e .. ';')
end
function N.text(html)
  local s = tostring(html or '')
  s = s:gsub('\r', ''):gsub('<pre><code>(.-)</code></pre>', function(code) return '\n\n' .. code:gsub('\n+$', '') .. '\n\n' end)
  s = s:gsub('<[pP]>', '\n\n'):gsub('<br%s*/?>', '\n'):gsub('<[^>]*>', '')
  s = s:gsub('&(#?%w+);', entity)
  s = s:gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
  return s
end

-- the bytes of s that fit in width w (whole UTF-8 characters, at least one)
local function fit(f, s, w)
  local best = nil
  pcall(function()
    for p in utf8.codes(s) do
      if p > 1 then
        if kit.width(f, s:sub(1, p - 1)) > w then break end
        best = p - 1
      end
    end
  end)
  return best or math.max(1, math.min(#s, w // 12))
end

-- word wrap in the given font: lines no wider than w; a word wider than a line is broken
function N.wrap(s, fname, w)
  local f, out = kit.font(fname), {}
  for para in (tostring(s) .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('[^ \t]+') do
      local cand = line == '' and word or (line .. ' ' .. word)
      if kit.width(f, cand) <= w then line = cand
      else
        if line ~= '' then out[#out + 1] = line end
        line = word
        while kit.width(f, line) > w do
          local n = fit(f, line, w)
          out[#out + 1] = line:sub(1, n)
          line = line:sub(n + 1)
        end
      end
    end
    out[#out + 1] = line
  end
  return out
end

return N
