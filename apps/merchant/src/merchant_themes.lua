-- Theme definitions for the Merchant plugin.
--
-- A theme is pure flavour: the goods on the market, the places you travel
-- between, and every piece of narration the game shows. The rules in
-- merchant_game.lua never change — only the words and numbers' labels do.
-- Every theme uses the same six price bands so the game balance is identical
-- no matter which one is selected.
--
-- Template placeholders (%1, %2, ...) are filled by ffi/util's T(); the
-- comment next to each string says what goes in.

local _ = require("merchant_l10n")

local themes = {
    {
        id = "silkroad",
        name = _("Silk Road caravan"),
        money = _("%1 silver"), -- %1 = formatted amount
        market_title = _("Bazaar — buy low, sell high:"),
        travel_label = _("Travel"),
        travel_prompt = _("Set out for where?"),
        lender_label = _("Moneylender"),
        lender_title = _("Moneylender — you owe %1"), -- %1 = money
        bank_label = _("Guild bank"),
        bank_title = _("Guild bank — balance %1"), -- %1 = money
        weapon_label = _("Guards"),
        capacity_label = _("Load"),
        goods = {
            { name = _("Saffron"),      min = 15000, max = 29000 },
            { name = _("Silk"),         min = 5000,  max = 14000 },
            { name = _("Frankincense"), min = 1000,  max = 4400 },
            { name = _("Cinnamon"),     min = 300,   max = 900 },
            { name = _("Pepper"),       min = 90,    max = 250 },
            { name = _("Salt"),         min = 10,    max = 60 },
        },
        locations = {
            _("Constantinople"),
            _("Baghdad"),
            _("Samarkand"),
            _("Bukhara"),
            _("Kashgar"),
            _("Chang'an"),
        },
        surge_msg = _("Nobles are paying outrageous prices for %1!"), -- %1 = good
        glut_msg = _("A caravan has flooded the bazaar with cheap %1!"), -- %1 = good
        found_money_msg = _("You found a purse with %1 by the roadside!"), -- %1 = money
        robbed_msg = _("Pickpockets in the bazaar! Lost %1."), -- %1 = money
        found_goods_msg = _("You found %1 %2 abandoned by the trail!"), -- %1 = qty, %2 = good
        weapon_offer = _("A mercenary offers to guard your caravan for %1. Hire him?"), -- %1 = money
        weapon_bought = _("The mercenary joins your caravan."),
        capacity_offer = _("A drover offers extra camels (+%1 load) for %2. Buy them?"), -- %1 = slots, %2 = money
        capacity_bought = _("Your caravan can now carry %1 more."), -- %1 = slots
        no_room_msg = _("Your camels can't carry any more."),
        enemy_title = _("Bandits (%1) are raiding your caravan!\nHealth %2 · Guards %3"), -- %1 = count, %2 = health, %3 = weapons
        fight_label = _("Fight"),
        flee_label = _("Flee"),
        no_weapon_msg = _("You have no guards to fight them!"),
        hit_msg = _("Your guards struck one down!"),
        miss_msg = _("Your guards missed!"),
        win_msg = _("The bandits scatter — you seize %1 from their camp!"), -- %1 = money
        hurt_msg = _("They fought back! Health -%1 (%2 left)."), -- %1 = damage, %2 = health
        flee_ok_msg = _("You escaped through a mountain pass!"),
        flee_fail_msg = _("They caught up with you! Health -%1 (%2 left)."), -- %1 = damage, %2 = health
        busted_msg = _("The bandits overran your caravan."),
    },
    {
        id = "space",
        name = _("Star trader"),
        money = _("%1 cr"),
        market_title = _("Trade terminal — buy low, sell high:"),
        travel_label = _("Warp"),
        travel_prompt = _("Warp to where?"),
        lender_label = _("The Syndicate"),
        lender_title = _("The Syndicate — you owe %1"),
        bank_label = _("Galactic bank"),
        bank_title = _("Galactic bank — balance %1"),
        weapon_label = _("Turrets"),
        capacity_label = _("Cargo"),
        goods = {
            { name = _("Antimatter"),    min = 15000, max = 29000 },
            { name = _("Quantum cores"), min = 5000,  max = 14000 },
            { name = _("Med-nanites"),   min = 1000,  max = 4400 },
            { name = _("Robot parts"),   min = 300,   max = 900 },
            { name = _("Fuel cells"),    min = 90,    max = 250 },
            { name = _("Scrap alloy"),   min = 10,    max = 60 },
        },
        locations = {
            _("Terra Station"),
            _("Luna Port"),
            _("Mars Colony"),
            _("Ceres Belt"),
            _("Europa Dock"),
            _("Titan Refinery"),
        },
        surge_msg = _("A colony shortage — %1 sells at outrageous prices!"),
        glut_msg = _("A freighter dumped cheap %1 on the market!"),
        found_money_msg = _("You salvaged a credit chip worth %1!"),
        robbed_msg = _("A dock hustler scammed you! Lost %1."),
        found_goods_msg = _("You salvaged %1 %2 from drifting wreckage!"),
        weapon_offer = _("A shipwright offers a laser turret for %1. Install it?"),
        weapon_bought = _("Laser turret installed."),
        capacity_offer = _("A dockhand offers spare cargo pods (+%1 space) for %2. Buy them?"),
        capacity_bought = _("Your hold now fits %1 more."),
        no_room_msg = _("Your cargo hold is full."),
        enemy_title = _("Pirate ships (%1) are closing in!\nHull %2 · Turrets %3"),
        fight_label = _("Fight"),
        flee_label = _("Evade"),
        no_weapon_msg = _("You have no turrets to fight with!"),
        hit_msg = _("Direct hit — one pirate is down!"),
        miss_msg = _("Your shots went wide!"),
        win_msg = _("The pirates are destroyed — you salvage %1!"),
        hurt_msg = _("They returned fire! Hull -%1 (%2 left)."),
        flee_ok_msg = _("You lost them in an asteroid field!"),
        flee_fail_msg = _("They kept pace! Hull -%1 (%2 left)."),
        busted_msg = _("Your ship was destroyed by pirates."),
    },
    {
        id = "sea",
        name = _("Clipper captain"),
        money = _("$%1"),
        market_title = _("Harbor market — buy low, sell high:"),
        travel_label = _("Set sail"),
        travel_prompt = _("Set sail for where?"),
        lender_label = _("Moneylender"),
        lender_title = _("Moneylender — you owe %1"),
        bank_label = _("Bank"),
        bank_title = _("Bank — balance %1"),
        weapon_label = _("Cannons"),
        capacity_label = _("Hold"),
        goods = {
            { name = _("Porcelain"), min = 15000, max = 29000 },
            { name = _("Silk"),      min = 5000,  max = 14000 },
            { name = _("Tea"),       min = 1000,  max = 4400 },
            { name = _("Spices"),    min = 300,   max = 900 },
            { name = _("Rum"),       min = 90,    max = 250 },
            { name = _("Hemp"),      min = 10,    max = 60 },
        },
        locations = {
            _("Canton"),
            _("Singapore"),
            _("Batavia"),
            _("Bombay"),
            _("Manila"),
            _("Nagasaki"),
        },
        surge_msg = _("Merchants are bidding wildly for %1!"),
        glut_msg = _("The docks are flooded with cheap %1!"),
        found_money_msg = _("You found %1 washed up in a sea chest!"),
        robbed_msg = _("Dock thieves got into your cabin! Lost %1."),
        found_goods_msg = _("You fished %1 %2 out of the surf!"),
        weapon_offer = _("A gunsmith offers a ship's cannon for %1. Buy it?"),
        weapon_bought = _("The cannon is bolted to your deck."),
        capacity_offer = _("A shipwright offers to refit your hold (+%1 space) for %2. Do it?"),
        capacity_bought = _("Your hold now stows %1 more."),
        no_room_msg = _("Your hold is packed to the beams."),
        enemy_title = _("Pirate junks (%1) are bearing down on you!\nHull %2 · Cannons %3"),
        fight_label = _("Fight"),
        flee_label = _("Flee"),
        no_weapon_msg = _("You have no cannons to fight with!"),
        hit_msg = _("A broadside — one junk is sinking!"),
        miss_msg = _("Your broadside missed!"),
        win_msg = _("The pirates strike their colors — you seize %1 in booty!"),
        hurt_msg = _("They raked your decks! Hull -%1 (%2 left)."),
        flee_ok_msg = _("You slipped away into a fog bank!"),
        flee_fail_msg = _("They stayed on your tail! Hull -%1 (%2 left)."),
        busted_msg = _("Your ship was taken by pirates."),
    },
    {
        id = "antiques",
        name = _("Antique dealer"),
        money = _("$%1"),
        market_title = _("Today's finds — buy low, sell high:"),
        travel_label = _("Move on"),
        travel_prompt = _("Head to which quarter?"),
        lender_label = _("Pawnbroker"),
        lender_title = _("Pawnbroker — you owe %1"),
        bank_label = _("Bank"),
        bank_title = _("Bank — balance %1"),
        weapon_label = _("Experts"),
        capacity_label = _("Bag"),
        goods = {
            { name = _("Illuminated manuscripts"), min = 15000, max = 29000 },
            { name = _("Pocket watches"),          min = 5000,  max = 14000 },
            { name = _("Old etchings"),            min = 1000,  max = 4400 },
            { name = _("First editions"),          min = 300,   max = 900 },
            { name = _("Vintage maps"),            min = 90,    max = 250 },
            { name = _("Old postcards"),           min = 10,    max = 60 },
        },
        locations = {
            _("Grand Bazaar"),
            _("Old Town"),
            _("University Quarter"),
            _("Harbor District"),
            _("Riverside Market"),
            _("Flea Market"),
        },
        surge_msg = _("Collectors are in a frenzy over %1!"),
        glut_msg = _("An estate sale flooded the stalls with cheap %1!"),
        found_money_msg = _("You found %1 tucked inside an old book!"),
        robbed_msg = _("A pickpocket worked the market crowd! Lost %1."),
        found_goods_msg = _("You spotted %1 %2 in a junk pile!"),
        weapon_offer = _("A retired appraiser offers his expertise for %1. Hire him?"),
        weapon_bought = _("The appraiser joins your rounds."),
        capacity_offer = _("A leatherworker offers a bigger satchel (+%1 room) for %2. Buy it?"),
        capacity_bought = _("Your bag now holds %1 more."),
        no_room_msg = _("Your bag is stuffed full."),
        enemy_title = _("Forgers (%1) are trying to swindle you!\nNerve %2 · Experts %3"), -- a battle of wits
        fight_label = _("Call their bluff"),
        flee_label = _("Walk away"),
        no_weapon_msg = _("You have no expert to spot the fakes!"),
        hit_msg = _("Your expert exposed one of them!"),
        miss_msg = _("Their forgery fooled your expert!"),
        win_msg = _("The forgers flee — the crowd rewards you with %1 in trade!"),
        hurt_msg = _("They rattled you badly! Nerve -%1 (%2 left)."),
        flee_ok_msg = _("You slipped away into the crowd!"),
        flee_fail_msg = _("They followed you, jeering! Nerve -%1 (%2 left)."),
        busted_msg = _("The forgers ruined your reputation and your nerve."),
    },
}

local by_id = {}
for _, theme in ipairs(themes) do
    by_id[theme.id] = theme
end

local Themes = {
    list = themes,
    default_id = "silkroad",
}

-- Unknown or nil ids (e.g. from an old save) fall back to the default theme.
function Themes.get(id)
    return by_id[id] or by_id[Themes.default_id]
end

return Themes
