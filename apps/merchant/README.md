# Merchant — XTOS Licorice mini app (API 2.9)

A turn-based trading game, ported from the KOReader plugin
[merchant.koplugin](https://github.com/omer-faruq/merchant.koplugin): buy low, sell high across six
trading posts, fend off raiders, pay off the moneylender and build the biggest fortune in 30 days.
Four settings with the same rules: **Silk Road caravan**, **Star trader**, **Clipper captain**,
**Antique dealer**.

## How to play

- The board shows the day, where you are, your cash, bank and debt, health, guards and load, and
  the market: each good with today's price here (`(none)` = not traded here) and how many you hold.
- **Tap a good** to buy or sell it. The amount box starts at the most you can; **-/+** steps,
  **1/4**, **1/2**, **Max**, or **Type** an exact number with the firmware keyboard.
- **Travel** (the theme names it: Travel, Warp, Set sail, ...) moves you on; each trip is a day,
  prices change and things happen on the way: found money or goods, thieves, offers of guards or
  more room (**Buy** / **No thanks**), raiders (**Fight** with guards, or flee).
- The **moneylender**: you start 5,500 in debt at 10 % a day; pay back or borrow. The **bank**
  pays 5 % a day.
- After 30 days your net worth (cash + bank - debt) is scored against your best for that theme.
  **Scores** lists the best of each theme.
- **Settings**: **Theme** (takes effect with the next new game) and **Language**: English, Deutsch,
  Español, Français, Italiano, Português, Türkçe (the plugin's translations). The game is saved
  after every move; leaving and coming back continues it.

## Files

- `src/merchant_game.lua`, `src/merchant_themes.lua`, `src/merchant_l10n/*.lua` — the game rules,
  themes and translations, unchanged from merchant.koplugin v2.0.1 (commit 8745245).
- `src/ui.lua` — the device screen.
- `bundle.py` — puts them into `index.lua` (the device has no `require` for package files);
  `build_all.py` runs it. Edit `src/`, not `index.lua`.
- `test_merchant.py` — plays through the screen offline: `python -I apps/merchant/test_merchant.py`.

## License

Merchant is licensed under the **GNU AGPL v3** (`LICENSE` in this folder), like the KOReader plugin
it comes from; the rest of this repository is MIT.
