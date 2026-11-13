-- xkcd pieces that need no screen: the JSON interface's addresses, a comic from its JSON, a PNG's
-- size from its header, fitting, the public resizer's address for pictures too big for the reader,
-- the saved-comic lines (cache.txt, lock.txt) and Random.
--
-- xkcd.com/info.0.json is the latest comic, xkcd.com/<n>/info.0.json any other: num, title, alt (the
-- text under the joke), img (a PNG on imgs.xkcd.com), year, month, day. There is no comic 404.

local X = {}

X.SITE = 'https://xkcd.com/'
X.MAX_SIDE = 1024               -- ctx.image:decode refuses a picture larger than this either way

-- percent-encoding without %w (which follows the C locale and may take bytes of UTF-8 letters)
function X.enc(s)
  return (tostring(s):gsub('[^A-Za-z0-9%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

function X.json_url(n) return n and (X.SITE .. n .. '/info.0.json') or (X.SITE .. 'info.0.json') end
function X.page_url(n) return X.SITE .. n .. '/' end

-- every picture through images.weserv.nl (the resizer the rss-opds Worker uses; no account), at
-- exactly the size it is shown: inside bw x bh, at most twice its own size (sw x sh, when known),
-- greyscale at full contrast. xkcd's lines are thin and grey at their edges; the reader's dithering
-- turned them into dotted lines, while this keeps them whole (checked 2026-11-13). Its own resampling
-- is better than the reader's, which only scales down.
function X.weserv_url(img, bw, bh, sw, sh)
  local w, h = bw, bh
  if sw and sh and sw > 0 and sh > 0 then w, h = math.min(bw, 2 * sw), math.min(bh, 2 * sh) end
  return 'https://images.weserv.nl/?url=' .. X.enc(img) .. '&w=' .. math.floor(w) .. '&h=' .. math.floor(h)
    .. '&fit=inside&output=png&filt=greyscale&con=100'
end

-- the decoded JSON as a comic; nil without a number. Interactive (shown as title, alt and a QR
-- code): no PNG or JPEG picture, or extra parts (scripts, frames) the reader cannot run.
function X.comic(d)
  if type(d) ~= 'table' then return nil end
  local num = tonumber(d.num)
  if not num then return nil end
  local img = type(d.img) == 'string' and d.img or ''
  local low = img:lower()
  local pic = low:match('%.png$') or low:match('%.jpe?g$')
  local y, m, dd = tonumber(d.year), tonumber(d.month), tonumber(d.day)
  return { num = math.floor(num), title = tostring(d.safe_title or d.title or ''), alt = tostring(d.alt or ''), img = img,
           date = (y and m and dd) and string.format('%04d-%02d-%02d', y, m, dd) or '',
           interactive = (not pic) or d.extra_parts ~= nil }
end

-- a PNG's width and height from its IHDR chunk; nil when it is not a PNG
function X.png_size(b)
  if type(b) ~= 'string' or #b < 24 or b:sub(1, 8) ~= '\137PNG\r\n\26\n' or b:sub(13, 16) ~= 'IHDR' then return nil end
  local w, h = string.unpack('>I4I4', b, 17)
  return w, h
end
-- what the bytes are: 'png', 'jpg' or nil
function X.ext(b)
  if type(b) ~= 'string' then return nil end
  if b:sub(1, 4) == '\137PNG' then return 'png' end
  if b:sub(1, 3) == '\255\216\255' then return 'jpg' end
  return nil
end

-- w x h made to fit aw x ah, keeping its shape; never larger than it is
function X.fit(w, h, aw, ah)
  local s = math.min(1, aw / w, ah / h)
  return math.floor(w * s), math.floor(h * s)
end
function X.landscape(w, h) return w > h end

-- one comic as a line of text (cache.txt, lock.txt), and back
local function clean(s) return (tostring(s or ''):gsub('[\t\r\n]+', ' ')) end
function X.line(c)
  return table.concat({ c.num, clean(c.title), clean(c.alt), clean(c.img), clean(c.date), c.interactive and '1' or '0' }, '\t')
end
function X.parse_line(s)
  local num, title, alt, img, date, inter = tostring(s or ''):match('^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([01])$')
  if not num then return nil end
  return { num = tonumber(num), title = title, alt = alt, img = img, date = date, interactive = inter == '1' }
end

-- a comic number from r in [0, 1): 1..latest, never 404 (there is none)
function X.random(latest, r)
  local n = math.min(latest, math.floor(r * latest) + 1)
  if n == 404 then n = latest > 404 and 405 or 403 end
  return n
end

return X
