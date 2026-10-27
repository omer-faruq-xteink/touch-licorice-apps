-- Playing cards for the gamekit card games (FreeCell, Klondike): drawn, not printed (the fonts
-- may lack the suit signs). A card is 1..52: rank (c - 1) % 13 + 1 (1 = ace .. 13 = king), suit
-- (c - 1) // 13 (0 clubs, 1 diamonds, 2 hearts, 3 spades). A suit sign is one polyline outline
-- in a 0..10 box; clubs and spades get a few filled boxes so they read solid, diamonds and hearts
-- stay hollow. Few draw commands matter: the host draws at most about 1024 per screen.

local C = {}

C.RANKS = { 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K' }
function C.rank(c) return (c - 1) % 13 + 1 end
function C.suit(c) return (c - 1) // 13 end
function C.red(c) local s = (c - 1) // 13; return s == 1 or s == 2 end

local SUITS = {
  [0] = { { 5, 0, 6.8, 0.6, 7.4, 2.4, 6.6, 4.2, 8.6, 3.6, 10, 4.8, 10, 6.6, 8.6, 7.8, 6.4, 7.2, 6.8, 10, 3.2, 10, 3.6, 7.2,
            1.4, 7.8, 0, 6.6, 0, 4.8, 1.4, 3.6, 3.4, 4.2, 2.6, 2.4, 3.2, 0.6, 5, 0 },
          { { 3.6, 0.8, 6.4, 3.8 }, { 1.0, 4.6, 3.8, 7.0 }, { 6.2, 4.6, 9.0, 7.0 }, { 4.4, 3.8, 5.6, 9.8 } } },     -- clubs
  [1] = { { 5, 0, 9, 5, 5, 10, 1, 5, 5, 0 }, {} },                                                                -- diamonds
  [2] = { { 5, 2.5, 3.8, 0.6, 2, 0, 0.4, 1, 0, 3, 0.8, 5.2, 5, 10, 9.2, 5.2, 10, 3, 9.6, 1, 8, 0, 6.2, 0.6, 5, 2.5 }, {} },  -- hearts
  [3] = { { 5, 0, 8.6, 3.6, 10, 5.6, 9.6, 7.4, 8, 8.2, 6.2, 7.4, 6.6, 10, 3.4, 10, 3.8, 7.4, 2, 8.2, 0.4, 7.4, 0, 5.6,
            1.4, 3.6, 5, 0 },
          { { 3.8, 1.6, 6.2, 3.0 }, { 2.6, 3.0, 7.4, 4.6 }, { 1.2, 4.6, 8.8, 7.2 }, { 4.2, 7, 5.8, 9.8 } } },     -- spades
}

-- the sign of suit s with its 0..10 box at (x, y), `scale` pixels a unit
function C.suit_sign(gg, s, x, y, scale)
  local shape = SUITS[s]
  local pts = {}
  for i, v in ipairs(shape[1]) do pts[i] = math.floor((i % 2 == 1 and x or y) + v * scale + 0.5) end
  gg:polyline(pts)
  for _k, b in ipairs(shape[2]) do
    local x1, y1 = math.floor(x + b[1] * scale + 0.5), math.floor(y + b[2] * scale + 0.5)
    gg:rect(x1, y1, math.floor(x + b[3] * scale + 0.5) - x1, math.floor(y + b[4] * scale + 0.5) - y1, { fill = true })
  end
end

-- a card's face on a w x h card at (x, y): rank and a small sign at the top, a large sign when
-- the whole card shows
function C.face(gg, c, x, y, w, h, whole, font)
  gg:text(x + 4, y + 2, C.RANKS[C.rank(c)], { font = font })
  C.suit_sign(gg, C.suit(c), x + w - 24, y + 5, 2)
  if whole then C.suit_sign(gg, C.suit(c), x + (w - 32) // 2, y + h - 40, 3.2) end
end

return C
