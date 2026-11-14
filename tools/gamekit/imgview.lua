-- imgview: an article picture on the whole screen, and zoomed, shared by the reading apps (RSS,
-- Instapaper, Readwise, wallabag). The apps show pictures through the free images.weserv.nl
-- resizer at the article's width; here the same original is asked again at the screen's size, so
-- the lettering of a screenshot stays sharp. A wide picture on a portrait screen comes turned a
-- quarter (clockwise): read it with the reader on its side, it then fills the screen's long side.
--
-- Zoom: a double tap (or Zoom in) shows the part around that place at 2x, then 4x; a drag moves
-- it, the arrow keys by half a screen; Zoom out goes back a step and Back to the whole picture.
-- Each part is asked from the resizer cut from the original (precrop) at the screen's size: sharp
-- at any zoom, and always under the 131072 bytes a response may hold.
--
--   IV.source(src)                    the original address inside a resizer URL, or nil
--   IV.meta_url(orig)                 the resizer's JSON about the original (its width and height)
--   IV.full_url(orig, iw, ih, bw, bh) the copy for a bw x bh box, turned when that helps; url, turned
--   IV.part(iw, ih, BW, BH, z, cx, cy) the part of the original shown at zoom z around (cx, cy),
--                                     for a BW x BH box in the original's orientation: x, y, w, h
--   v = IV.new(host)                  host: get(url, accept, cb(body, err)), decode(bytes, max_w, max_h)
--                                     -> img | nil, err, json(s) -> table, refresh(), fail(msg)
--   v:open(src, n, total, W, H) -> true | false     v:close()     v:is_open()
--   v:draw(gg, W, H, fonts)   v:pointer(ev) (an "up")   v:key(k) -> handled   v:bar_rect(W, H)
local IV = {}
IV.HEAD = 30                 -- the heading line over the picture
IV.BAR = 50                  -- the Zoom out / Zoom in buttons under it
IV.MAX_ZOOM = 4
local BASE = 'https://images.weserv.nl/?url='
local TAIL = '&output=jpg&q=75&filt=greyscale'

local function dec(s)
  return (s:gsub('+', ' '):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end
local function enc(s)
  return (s:gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function IV.source(src)
  src = tostring(src or '')
  if not src:match('^https?://images%.weserv%.nl/') then return nil end
  local u = src:match('[?&]url=([^&]+)')
  return u and dec(u) or nil
end

function IV.meta_url(orig) return BASE .. enc(orig) .. '&output=json' end

function IV.full_url(orig, iw, ih, bw, bh)
  local turned = bw < bh and iw > ih
  local w, h = bw, bh
  if turned then w, h = bh, bw end           -- the resizer fits first, then turns
  return BASE .. enc(orig) .. '&w=' .. w .. '&h=' .. h .. '&fit=inside' .. (turned and '&ro=90' or '') .. TAIL, turned
end

function IV.part(iw, ih, BW, BH, z, cx, cy)
  local s = math.min(BW / iw, BH / ih) * z
  local w = math.min(iw, math.ceil(BW / s))
  local h = math.min(ih, math.ceil(BH / s))
  local x = math.floor(clamp(cx - w / 2, 0, iw - w))
  local y = math.floor(clamp(cy - h / 2, 0, ih - h))
  return x, y, w, h
end

local V = {}
V.__index = V

function IV.new(host) return setmetatable({ host = host, seq = 0 }, V) end

function V:is_open() return self.cur ~= nil end

local function free(img) if img then pcall(function() img:release() end) end end

function V:close()
  local c = self.cur
  self.cur = nil
  self.seq = self.seq + 1                    -- answers still on their way are dropped
  if c then free(c.img); free(c.zimg) end
end

-- give up with a reason the app shows
function V:fail(seq, msg)
  if seq ~= self.seq then return end
  self:close()
  self.host.fail(msg)
  self.host.refresh()
end

function V:open(src, n, total, W, H)
  self:close()
  local orig = IV.source(src)
  if not orig then self.host.fail('This picture cannot be shown full screen.'); return false end
  local bw, bh = W, H - IV.HEAD - IV.BAR
  self.cur = { n = n, total = total, orig = orig, bw = bw, bh = bh, z = 1, zseq = 0 }
  local seq = self.seq
  self.host.get(IV.meta_url(orig), 'application/json', function(body, err)
    if seq ~= self.seq then return end
    if not body then return self:fail(seq, 'Full screen failed: ' .. tostring(err)) end
    local ok, d = pcall(self.host.json, body)
    local iw = ok and type(d) == 'table' and tonumber(d.width)
    local ih = ok and type(d) == 'table' and tonumber(d.height)
    if not (iw and ih and iw > 0 and ih > 0) then return self:fail(seq, 'Full screen failed: no size') end
    local url, turned = IV.full_url(orig, iw, ih, bw, bh)
    local c = self.cur
    c.iw, c.ih, c.turned = iw, ih, turned
    c.BW, c.BH = bw, bh                      -- the box in the original's orientation
    if turned then c.BW, c.BH = bh, bw end
    c.cx, c.cy = iw / 2, ih / 2
    self.host.get(url, 'image/jpeg', function(bytes, err2)
      if seq ~= self.seq then return end
      if not bytes then return self:fail(seq, 'Full screen failed: ' .. tostring(err2)) end
      local okd, img, err3 = pcall(self.host.decode, bytes, bw, bh)
      if not (okd and img) then return self:fail(seq, 'Full screen failed: ' .. tostring(okd and err3 or img)) end
      c.img = img
      self.host.refresh()
    end)
  end)
  self.host.refresh()
  return true
end

-- the picture on screen: the zoomed part, or the whole one; with where it is drawn
local function shown(c, W, H)
  local img = (c.z > 1 and c.zimg) or c.img
  if not img then return nil end
  local iw, ih = tonumber(img.width) or c.bw, tonumber(img.height) or c.bh
  return img, math.max(0, (W - iw) // 2), IV.HEAD + math.max(0, (H - IV.HEAD - IV.BAR - ih) // 2), iw, ih
end

-- the part of the original the picture on screen covers
local function covered(c)
  if c.z > 1 and c.zimg and c.zpart then return table.unpack(c.zpart) end
  return 0, 0, c.iw, c.ih
end

-- ask the part for zoom z around the original's (cx, cy); the picture on screen stays meanwhile
function V:zoom_to(z, cx, cy)
  local c = self.cur
  if not (c and c.img and c.iw) then return end
  c.z, c.msg = z, nil
  if z <= 1 then
    c.zseq = c.zseq + 1
    free(c.zimg); c.zimg, c.zpart = nil, nil
    c.cx, c.cy = c.iw / 2, c.ih / 2
    self.host.refresh()
    return
  end
  local x, y, w, h = IV.part(c.iw, c.ih, c.BW, c.BH, z, cx, cy)
  c.cx, c.cy = x + w / 2, y + h / 2
  c.zseq = c.zseq + 1
  local zseq, seq = c.zseq, self.seq
  c.msg = 'Loading...'
  local url = BASE .. enc(c.orig) .. '&cx=' .. x .. '&cy=' .. y .. '&cw=' .. w .. '&ch=' .. h .. '&precrop&w=' .. c.BW
    .. '&h=' .. c.BH .. '&fit=inside' .. (c.turned and '&ro=90' or '') .. TAIL
  self.host.get(url, 'image/jpeg', function(bytes, err)
    if seq ~= self.seq or c.zseq ~= zseq then return end
    local okd, img = false, nil
    if bytes then okd, img = pcall(self.host.decode, bytes, c.bw, c.bh) end
    if not (okd and img) then
      c.msg = 'Zoom failed'
      if not c.zimg then c.z = 1 end         -- nothing zoomed to show: the whole picture again
      self.host.refresh()
      return
    end
    free(c.zimg)
    c.zimg, c.zpart, c.msg = img, { x, y, w, h }, nil
    self.host.refresh()
  end)
  self.host.refresh()
end

-- the original's point under the screen's (x, y)
local function at(c, x, y, W, H)
  local img, ox, oy, dw, dh = shown(c, W, H)
  if not img then return c.cx, c.cy end
  local u = clamp((x - ox) / dw, 0, 1)
  local v = clamp((y - oy) / dh, 0, 1)
  local rx, ry, rw, rh = covered(c)
  if c.turned then return rx + v * rw, ry + (1 - u) * rh end   -- turned clockwise
  return rx + u * rw, ry + v * rh
end

-- the picture follows a finger that moved (dx, dy) on the screen
function V:pan(dx, dy)
  local c = self.cur
  if not (c and c.z > 1 and c.iw) then return end
  local s = math.min(c.BW / c.iw, c.BH / c.ih) * c.z
  local cx, cy
  if c.turned then cx, cy = c.cx - dy / s, c.cy + dx / s
  else cx, cy = c.cx - dx / s, c.cy - dy / s end
  self:zoom_to(c.z, cx, cy)
end

function V:bar_rect(W, H) return 0, H - IV.BAR, W, IV.BAR end

function V:pointer(ev)
  local c = self.cur
  if not (c and type(ev) == 'table' and ev.phase == 'up') then return end
  local W, H = c.bw, c.bh + IV.HEAD + IV.BAR
  local x, y = tonumber(ev.x) or 0, tonumber(ev.y) or 0
  local dx, dy = x - (tonumber(ev.down_x) or x), y - (tonumber(ev.down_y) or y)
  if dx * dx + dy * dy > 400 then self:pan(dx, dy); return end
  if y >= H - IV.BAR then
    if x < W / 2 then
      if c.z > 1 then self:zoom_to(c.z // 2, c.cx, c.cy) end
    elseif c.z < IV.MAX_ZOOM then self:zoom_to(c.z * 2, c.cx, c.cy) end
    return
  end
  if ev.gesture == 'double_tap' and c.z < IV.MAX_ZOOM then
    local ax, ay = at(c, x, y, W, H)
    self:zoom_to(c.z * 2, ax, ay)
  end
end

function V:key(k)
  local c = self.cur
  if not c then return false end
  if k == 'back' then
    if c.z > 1 or c.zimg then self:zoom_to(1); return true end
    return false
  end
  if c.z <= 1 then return true end
  if k == 'right' then self:pan(-c.bw // 2, 0)
  elseif k == 'left' then self:pan(c.bw // 2, 0)
  elseif k == 'down' then self:pan(0, -c.bh // 2)
  elseif k == 'up' then self:pan(0, c.bh // 2) end
  return true
end

function V:draw(gg, W, H, fonts)
  local c = self.cur
  if not c then return end
  local sm = fonts and fonts.small
  local head = 'Image ' .. c.n .. ' of ' .. c.total .. (c.turned and ' (turned)' or '')
  if c.z > 1 then head = head .. '  ' .. c.z .. 'x' end
  gg:text(8, 4, head, { font = sm })
  gg:text(W - 140, 4, c.msg or 'Back: return', { font = sm })
  gg:line(0, IV.HEAD - 3, W, IV.HEAD - 3)
  local bx, by, bw = V.bar_rect(self, W, H)
  gg:line(0, by, W, by)
  gg:rect(bx + 8, by + 6, bw // 2 - 12, IV.BAR - 10)
  gg:rect(bw // 2 + 4, by + 6, bw // 2 - 12, IV.BAR - 10)
  gg:text(bx + 24, by + 16, 'Zoom out', { font = sm })
  gg:text(bw // 2 + 20, by + 16, 'Zoom in', { font = sm })
  local img, ox, oy = shown(c, W, H)
  if not img then
    gg:text(16, IV.HEAD + 20, 'Loading full screen...', { font = fonts and fonts.medium })
    return
  end
  gg:image(img, ox, oy)
end

return IV
