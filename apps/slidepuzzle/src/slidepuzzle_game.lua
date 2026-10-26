--[[
    slidepuzzle_game.lua
    Pure logic for the NxN classic sliding tile puzzle.

    Grid cells contain integer tile numbers 1..N*N-1 and a single 0 that
    represents the empty cell. The solved configuration is tile (r-1)*N+c
    at row r and column c, with the empty cell in the bottom-right corner.

    The module does not touch any UI code so it can be unit-tested on its
    own and reused from the board widget / screen.
--]]

local MIN_SIZE = 3
local MAX_SIZE = 7

local Game = {}
Game.__index = Game

-- Factory -----------------------------------------------------------------

function Game:new(size)
    size = tonumber(size) or MIN_SIZE
    if size < MIN_SIZE then size = MIN_SIZE end
    if size > MAX_SIZE then size = MAX_SIZE end
    local instance = {
        size = size,
        grid = {},
        empty_r = size,
        empty_c = size,
        moves = 0,
        elapsed = 0, -- accumulated playing seconds (does not include current live tick)
        started = false,
        won = true,
    }
    setmetatable(instance, self)
    instance:resetToSolved()
    return instance
end

function Game.getMinSize() return MIN_SIZE end
function Game.getMaxSize() return MAX_SIZE end

-- Internal helpers --------------------------------------------------------

function Game:resetToSolved()
    local n = self.size
    local grid = {}
    local value = 1
    for r = 1, n do
        grid[r] = {}
        for c = 1, n do
            if r == n and c == n then
                grid[r][c] = 0
            else
                grid[r][c] = value
                value = value + 1
            end
        end
    end
    self.grid = grid
    self.empty_r = n
    self.empty_c = n
    self.moves = 0
    self.elapsed = 0
    self.started = false
    self.won = true
end

-- Swap the empty cell with the neighbour at (nr, nc). Caller must ensure
-- adjacency. Returns true when the swap happened.
function Game:_swapWithEmpty(nr, nc)
    local n = self.size
    if nr < 1 or nr > n or nc < 1 or nc > n then
        return false
    end
    self.grid[self.empty_r][self.empty_c] = self.grid[nr][nc]
    self.grid[nr][nc] = 0
    self.empty_r = nr
    self.empty_c = nc
    return true
end

-- Shuffling ---------------------------------------------------------------

-- Perform a number of random valid neighbour swaps starting from the
-- solved state. Using only valid moves guarantees that the resulting
-- board is solvable regardless of N. The last applied direction is
-- tracked so we avoid immediately reversing it (which would produce
-- shorter, less interesting scrambles).
function Game:shuffle()
    self:resetToSolved()
    local n = self.size
    local shuffle_moves = 60 + n * n * 20
    local dirs = {
        { -1,  0 }, -- up
        {  1,  0 }, -- down
        {  0, -1 }, -- left
        {  0,  1 }, -- right
    }
    local opposite = { [1] = 2, [2] = 1, [3] = 4, [4] = 3 }
    local last_dir = 0
    for _ = 1, shuffle_moves do
        local candidates = {}
        for idx, d in ipairs(dirs) do
            if idx ~= opposite[last_dir] then
                local nr = self.empty_r + d[1]
                local nc = self.empty_c + d[2]
                if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                    candidates[#candidates + 1] = idx
                end
            end
        end
        if #candidates == 0 then
            break
        end
        local pick = candidates[math.random(#candidates)]
        local d = dirs[pick]
        self:_swapWithEmpty(self.empty_r + d[1], self.empty_c + d[2])
        last_dir = pick
    end
    -- If by coincidence we ended up solved again, nudge one more move.
    if self:checkSolved() then
        local d = dirs[math.random(#dirs)]
        local nr = self.empty_r + d[1]
        local nc = self.empty_c + d[2]
        if nr < 1 or nr > n or nc < 1 or nc > n then
            d = { -d[1], -d[2] }
            nr = self.empty_r + d[1]
            nc = self.empty_c + d[2]
        end
        self:_swapWithEmpty(nr, nc)
    end
    self.moves = 0
    self.elapsed = 0
    self.started = false
    self.won = false
end

-- Move API ----------------------------------------------------------------

-- Tap-style move: tile at (row, col) slides into the empty cell when the
-- two are orthogonally adjacent. Returns true on success.
function Game:moveTileAt(row, col)
    if self.won then return false end
    local n = self.size
    if row < 1 or row > n or col < 1 or col > n then
        return false
    end
    if self.grid[row][col] == 0 then
        return false
    end
    local dr = math.abs(row - self.empty_r)
    local dc = math.abs(col - self.empty_c)
    if (dr == 1 and dc == 0) or (dr == 0 and dc == 1) then
        local prev_empty_r, prev_empty_c = self.empty_r, self.empty_c
        self:_swapWithEmpty(row, col)
        -- after swap the former empty position now holds the tile.
        self.moves = self.moves + 1
        self.started = true
        self.won = self:checkSolved()
        return true, prev_empty_r, prev_empty_c
    end
    return false
end

-- Swipe-style move. "direction" is the direction the player swiped /
-- wants a tile to move. Interpreted as the neighbour of the empty cell
-- on the opposite side being pushed into the empty cell. For example a
-- swipe "left" moves the tile that is to the right of the empty cell
-- one step to the left.
function Game:slide(direction)
    if self.won then return false end
    local nr, nc = self.empty_r, self.empty_c
    if direction == "left" then
        nc = nc + 1
    elseif direction == "right" then
        nc = nc - 1
    elseif direction == "up" then
        nr = nr + 1
    elseif direction == "down" then
        nr = nr - 1
    else
        return false
    end
    return self:moveTileAt(nr, nc)
end

-- Query helpers -----------------------------------------------------------

function Game:checkSolved()
    local n = self.size
    local expected = 1
    for r = 1, n do
        for c = 1, n do
            if r == n and c == n then
                if self.grid[r][c] ~= 0 then return false end
            else
                if self.grid[r][c] ~= expected then return false end
                expected = expected + 1
            end
        end
    end
    return true
end

function Game:getGrid()  return self.grid end
function Game:getSize()  return self.size end
function Game:getMoves() return self.moves end
function Game:getEmpty() return self.empty_r, self.empty_c end
function Game:isWon()    return self.won end
function Game:hasStarted() return self.started end
function Game:getElapsed() return self.elapsed end

function Game:addElapsed(delta)
    if type(delta) == "number" and delta > 0 then
        self.elapsed = self.elapsed + delta
    end
end

-- Serialisation -----------------------------------------------------------

function Game:serialize()
    local copy = {}
    local n = self.size
    for r = 1, n do
        copy[r] = {}
        for c = 1, n do
            copy[r][c] = self.grid[r][c]
        end
    end
    return {
        size = n,
        grid = copy,
        empty_r = self.empty_r,
        empty_c = self.empty_c,
        moves = self.moves,
        elapsed = self.elapsed,
        started = self.started,
        won = self.won,
    }
end

-- Build a Game instance from a previously serialised table. On any
-- structural problem a freshly shuffled game of the requested size is
-- returned so the UI never ends up with a broken board.
function Game.deserialize(data, fallback_size)
    local size = tonumber(data and data.size) or fallback_size or MIN_SIZE
    if size < MIN_SIZE then size = MIN_SIZE end
    if size > MAX_SIZE then size = MAX_SIZE end
    local game = Game:new(size)
    if type(data) ~= "table" or type(data.grid) ~= "table" then
        game:shuffle()
        return game
    end
    local n = game.size
    local seen = {}
    local empty_r, empty_c
    for r = 1, n do
        if type(data.grid[r]) ~= "table" then
            game:shuffle()
            return game
        end
        for c = 1, n do
            local v = tonumber(data.grid[r][c])
            if v == nil or v < 0 or v > n * n - 1 or seen[v] then
                game:shuffle()
                return game
            end
            seen[v] = true
            game.grid[r][c] = v
            if v == 0 then
                empty_r, empty_c = r, c
            end
        end
    end
    if not empty_r then
        game:shuffle()
        return game
    end
    game.empty_r = empty_r
    game.empty_c = empty_c
    game.moves = tonumber(data.moves) or 0
    game.elapsed = tonumber(data.elapsed) or 0
    game.started = data.started == true
    game.won = game:checkSolved()
    return game
end

return Game
