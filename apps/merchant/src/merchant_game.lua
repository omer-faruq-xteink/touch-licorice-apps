-- Game model and rules for the Merchant plugin.
--
-- This module is pure logic: it knows nothing about KOReader widgets. The UI in
-- main.lua drives it by calling methods and reading the resulting state. Where a
-- turn produces things worth telling the player, the method appends short
-- strings to a `messages` list and/or sets `self.pending` to an interactive
-- event the UI must resolve (an enemy encounter or a market offer).
--
-- All flavour — goods, places, narration — comes from the theme table
-- (see merchant_themes.lua); the rules below are the same for every theme.

local Themes = require("merchant_themes")
local _ = require("merchant_l10n")
local T = require("ffi/util").template

local START_CASH = 2000
local START_DEBT = 5500
local START_CAPACITY = 100
local MAX_DAYS = 30
local DEBT_INTEREST = 1.10 -- the lender compounds 10% a day
local BANK_INTEREST = 1.05 -- the bank pays 5% a day

-- Group digits into thousands: 12345 -> "12,345".
local function formatNumber(n)
    n = math.floor(tonumber(n) or 0)
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    out = out:gsub("^,", "")
    return sign .. out
end

local MerchantGame = {}
MerchantGame.__index = MerchantGame

MerchantGame.MAX_DAYS = MAX_DAYS

function MerchantGame.format(n) return formatNumber(n) end

function MerchantGame:getGoods() return self.theme.goods end
function MerchantGame:getLocations() return self.theme.locations end

-- Format an amount in the theme's currency: 12345 -> "12,345 silver".
function MerchantGame:money(n)
    return T(self.theme.money, formatNumber(n))
end

function MerchantGame:new(theme)
    local game = setmetatable({}, self)
    game:newGame(theme)
    return game
end

function MerchantGame:newGame(theme)
    math.randomseed(os.time())
    self.theme = theme or self.theme or Themes.get(nil)
    self.day = 1
    self.cash = START_CASH
    self.debt = START_DEBT
    self.bank = 0
    self.weapons = 0
    self.health = 100
    self.capacity = START_CAPACITY
    self.location = self.theme.locations[1]
    self.inventory = {}
    for i = 1, #self.theme.goods do
        self.inventory[i] = 0
    end
    self.game_over = false
    self.pending = nil
    local messages = {}
    self:generatePrices(messages)
    self.last_messages = messages
end

-- ---------------------------------------------------------------- inventory --

function MerchantGame:spaceUsed()
    local n = 0
    for i = 1, #self.theme.goods do
        n = n + (self.inventory[i] or 0)
    end
    return n
end

function MerchantGame:spaceLeft()
    return self.capacity - self:spaceUsed()
end

function MerchantGame:netWorth()
    return self.cash + self.bank - self.debt
end

-- ------------------------------------------------------------------- prices --

-- Roll a fresh market for the current location. Not every good is on sale every
-- day; we guarantee at least three so there is always something to trade. With
-- some chance one good gets a dramatic price swing the player can exploit.
function MerchantGame:generatePrices(messages)
    local goods = self.theme.goods
    self.prices = {}
    local available = {}
    for i, good in ipairs(goods) do
        if math.random() < 0.70 then
            self.prices[i] = math.random(good.min, good.max)
            available[#available + 1] = i
        end
    end
    while #available < 3 do
        local i = math.random(#goods)
        if not self.prices[i] then
            self.prices[i] = math.random(goods[i].min, goods[i].max)
            available[#available + 1] = i
        end
    end
    if messages and #available > 0 and math.random() < 0.45 then
        local i = available[math.random(#available)]
        local good = goods[i]
        if math.random() < 0.5 then
            self.prices[i] = math.floor(self.prices[i] * (3 + math.random() * 2))
            messages[#messages + 1] = T(self.theme.surge_msg, good.name)
        else
            self.prices[i] = math.max(1, math.floor(good.min / 2))
            messages[#messages + 1] = T(self.theme.glut_msg, good.name)
        end
    end
end

function MerchantGame:hasPrice(i)
    return self.prices[i] ~= nil
end

-- -------------------------------------------------------------------- travel --

-- Move to another location. A day passes: interest accrues, a new market is
-- rolled, and random events fire. Returns the list of messages to show;
-- interactive events are left on self.pending for the UI to resolve.
function MerchantGame:travel(dest)
    if self.game_over then
        return {}
    end
    self.location = dest
    self.day = self.day + 1
    self.debt = math.floor(self.debt * DEBT_INTEREST)
    if self.bank > 0 then
        self.bank = math.floor(self.bank * BANK_INTEREST)
    end
    local messages = {}
    self:generatePrices(messages)
    self:rollEvents(messages)
    if self.day > MAX_DAYS then
        self.game_over = true
    end
    self.last_messages = messages
    return messages
end

function MerchantGame:rollEvents(messages)
    local goods = self.theme.goods
    local r = math.random()
    if r < 0.12 then
        local amt = math.random(2, 20) * 100
        self.cash = self.cash + amt
        messages[#messages + 1] = T(self.theme.found_money_msg, self:money(amt))
    elseif r < 0.22 and self.cash > 0 then
        local loss = math.floor(self.cash * (0.05 + math.random() * 0.2))
        if loss > 0 then
            self.cash = self.cash - loss
            messages[#messages + 1] = T(self.theme.robbed_msg, self:money(loss))
        end
    end

    if math.random() < 0.10 and self:spaceLeft() > 0 then
        local i = math.random(#goods)
        local qty = math.min(self:spaceLeft(), math.random(2, 8))
        self.inventory[i] = self.inventory[i] + qty
        messages[#messages + 1] = T(self.theme.found_goods_msg, qty, goods[i].name)
    end

    if not self.pending then
        local o = math.random()
        if o < 0.08 then
            self.pending = { type = "weapon", price = math.random(3, 8) * 100 }
        elseif o < 0.14 then
            self.pending = { type = "capacity", price = math.random(2, 5) * 100, slots = math.random(20, 60) }
        elseif o < 0.27 and self:spaceUsed() > 0 then
            self.pending = { type = "enemy", count = math.random(2, 6) }
        end
    end
end

-- ------------------------------------------------------------------ trading --

function MerchantGame:maxBuy(i)
    local price = self.prices[i]
    if not price or price <= 0 then
        return 0
    end
    return math.max(0, math.min(math.floor(self.cash / price), self:spaceLeft()))
end

function MerchantGame:buy(i, qty)
    local price = self.prices[i]
    if not price then
        return false, _("That isn't sold here.")
    end
    qty = math.floor(qty or 0)
    if qty <= 0 then
        return false
    end
    local cost = price * qty
    if cost > self.cash then
        return false, _("You can't afford that many.")
    end
    if qty > self:spaceLeft() then
        return false, self.theme.no_room_msg
    end
    self.cash = self.cash - cost
    self.inventory[i] = self.inventory[i] + qty
    return true
end

function MerchantGame:sell(i, qty)
    local price = self.prices[i]
    if not price then
        return false, _("Nobody here is buying that.")
    end
    qty = math.floor(qty or 0)
    if qty <= 0 then
        return false
    end
    if qty > (self.inventory[i] or 0) then
        return false, _("You don't have that many.")
    end
    self.cash = self.cash + price * qty
    self.inventory[i] = self.inventory[i] - qty
    return true
end

-- -------------------------------------------------------------- loan & bank --

function MerchantGame:payDebt(amt)
    amt = math.min(math.floor(amt or 0), self.cash, self.debt)
    if amt <= 0 then
        return false
    end
    self.cash = self.cash - amt
    self.debt = self.debt - amt
    return true
end

function MerchantGame:borrow(amt)
    amt = math.floor(amt or 0)
    if amt <= 0 then
        return false
    end
    self.cash = self.cash + amt
    self.debt = self.debt + amt
    return true
end

function MerchantGame:deposit(amt)
    amt = math.min(math.floor(amt or 0), self.cash)
    if amt <= 0 then
        return false
    end
    self.cash = self.cash - amt
    self.bank = self.bank + amt
    return true
end

function MerchantGame:withdraw(amt)
    amt = math.min(math.floor(amt or 0), self.bank)
    if amt <= 0 then
        return false
    end
    self.bank = self.bank - amt
    self.cash = self.cash + amt
    return true
end

-- ------------------------------------------------------------ market offers --

function MerchantGame:acceptOffer()
    local p = self.pending
    if not p then
        return false, _("There's nothing to buy.")
    end
    if p.type == "weapon" then
        if self.cash < p.price then
            return false, _("You can't afford it.")
        end
        self.cash = self.cash - p.price
        self.weapons = self.weapons + 1
        self.pending = nil
        return true, self.theme.weapon_bought
    elseif p.type == "capacity" then
        if self.cash < p.price then
            return false, _("You can't afford it.")
        end
        self.cash = self.cash - p.price
        self.capacity = self.capacity + p.slots
        self.pending = nil
        return true, T(self.theme.capacity_bought, p.slots)
    end
    return false
end

function MerchantGame:declineOffer()
    self.pending = nil
end

-- ---------------------------------------------------------- enemy encounter --

-- Both fight and flee return { messages = {...}, ended = bool, dead = bool }.

function MerchantGame:fight()
    local p = self.pending
    if not p or p.type ~= "enemy" then
        return { messages = {} }
    end
    local res = { messages = {} }
    if self.weapons <= 0 then
        res.messages[#res.messages + 1] = self.theme.no_weapon_msg
        return res
    end
    if math.random() < 0.55 then
        p.count = p.count - 1
        res.messages[#res.messages + 1] = self.theme.hit_msg
    else
        res.messages[#res.messages + 1] = self.theme.miss_msg
    end
    if p.count <= 0 then
        local bounty = math.random(5, 25) * 1000
        self.cash = self.cash + bounty
        res.messages[#res.messages + 1] = T(self.theme.win_msg, self:money(bounty))
        res.ended = true
        self.pending = nil
        return res
    end
    local dmg = math.min(25, math.random(3, 8) * p.count)
    self.health = self.health - dmg
    res.messages[#res.messages + 1] = T(self.theme.hurt_msg, dmg, math.max(0, self.health))
    if self.health <= 0 then
        self.health = 0
        res.dead = true
        self.game_over = true
        self.pending = nil
    end
    return res
end

function MerchantGame:flee()
    local p = self.pending
    if not p or p.type ~= "enemy" then
        return { messages = {} }
    end
    local res = { messages = {} }
    if math.random() < 0.65 then
        res.messages[#res.messages + 1] = self.theme.flee_ok_msg
        res.ended = true
        self.pending = nil
    else
        local dmg = math.random(5, 20)
        self.health = self.health - dmg
        res.messages[#res.messages + 1] = T(self.theme.flee_fail_msg, dmg, math.max(0, self.health))
        if self.health <= 0 then
            self.health = 0
            res.dead = true
            self.game_over = true
            self.pending = nil
        end
    end
    return res
end

-- --------------------------------------------------------------- persistence --

function MerchantGame:serialize()
    local goods = self.theme.goods
    local inv = {}
    for i = 1, #goods do
        inv[i] = self.inventory[i] or 0
    end
    local prices = {}
    for i = 1, #goods do
        prices[i] = self.prices[i]
    end
    return {
        theme = self.theme.id,
        day = self.day,
        cash = self.cash,
        debt = self.debt,
        bank = self.bank,
        weapons = self.weapons,
        health = self.health,
        capacity = self.capacity,
        location = self.location,
        inventory = inv,
        prices = prices,
        pending = self.pending,
        game_over = self.game_over,
    }
end

function MerchantGame:load(state)
    if type(state) ~= "table" or not state.day or not state.inventory then
        return false
    end
    self.theme = Themes.get(state.theme)
    local goods = self.theme.goods
    self.day = state.day
    self.cash = state.cash or START_CASH
    self.debt = state.debt or START_DEBT
    self.bank = state.bank or 0
    self.weapons = state.weapons or 0
    self.health = state.health or 100
    self.capacity = state.capacity or START_CAPACITY
    self.location = state.location or self.theme.locations[1]
    self.inventory = {}
    for i = 1, #goods do
        self.inventory[i] = state.inventory[i] or 0
    end
    self.prices = {}
    if type(state.prices) == "table" then
        for i = 1, #goods do
            self.prices[i] = state.prices[i]
        end
    else
        self:generatePrices()
    end
    self.pending = state.pending
    self.game_over = state.game_over or false
    self.last_messages = {}
    return true
end

return MerchantGame
