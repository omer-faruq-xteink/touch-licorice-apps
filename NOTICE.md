# Third-party content

The app code in this repository is MIT licensed (see `LICENSE`). It bundles the following.

## Packer core — `tools/vendor/xtapp.py`, `tools/vendor/mksd.py`

From [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu), MIT License, Copyright (c) 2026
KFloyd.com. Full text in `tools/vendor/LICENSE-x4pro-emu`. The reverse engineering of the Licorice
package format, the device key wrap and the Lua host API documented there made all of this
possible.

## Merchant — `apps/merchant/`

The game rules, themes and translations (`apps/merchant/src/merchant_*.lua`) come from
[merchant.koplugin](https://github.com/omer-faruq/merchant.koplugin) v2.0.1 by the same author and
are, like the whole Merchant app, licensed under the **GNU AGPL v3** (`apps/merchant/LICENSE`),
not MIT.

## Slide Puzzle — `apps/slidepuzzle/`

The game rules and translations (`apps/slidepuzzle/src/slidepuzzle_*.lua`) come from
[slidepuzzle.koplugin](https://github.com/omer-faruq/slidepuzzle.koplugin) v1.3.0 by the same
author and are, like the whole Slide Puzzle app, licensed under the **GNU GPL v3**
(`apps/slidepuzzle/LICENSE`), not MIT.

## Sudoku puzzles — `apps/sudoku/data/`

From the [sudoku-exchange puzzle bank](https://github.com/grantm/sudoku-exchange-puzzle-bank) by
Grant McLean, released into the public domain (CC0-style notice in `apps/sudoku/PUZZLES-LICENSE.txt`).
600 puzzles per difficulty are included unchanged.

## Sokoban level packs — `apps/sokoban/data/`

| pack | author | source |
|---|---|---|
| Microban (155), Sasquatch (50) | David W. Skinner | sokobano.de, published with the author's permission |
| LOMA (100), Microcosmos (40), Minicosmos (40) | Aymeric du Peloux | sokobano.de, published with the author's permission |

The packs are included as published; where the source file carried the author's notice it is kept
inside the file. Do not add copyrighted commercial level sets (for example the original Thinking
Rabbit levels) to a redistributed build.

## WordNet — release asset `dict-wordnet-en.zip`

The English–English dictionary shipped with releases is Princeton University's **WordNet**, taken
from the StarDict conversion `dictd_www.dict.org_wn` (Hu Zheng, 2005) and re-cut into the text
shards the Dictionary app reads. WordNet is free to use and redistribute under its own license,
whose text is included in the zip as `LICENSE-WORDNET.txt` and requires this notice:
"WordNet ® Princeton University". The data is not in the git repository, only in releases.

## Anki built-in deck — `apps/anki/data/`

Word choice by frequency from **wordfreq** by Robyn Speer (https://github.com/rspeer/wordfreq),
whose data is licensed CC BY-SA 4.0; senses, example sentences and similar words from **WordNet
3.0**, Princeton University ("WordNet ® Princeton University", licence in
`apps/anki/LICENSE-WORDNET.txt`). The deck files are therefore shared under CC BY-SA 4.0 as well.

## Chess puzzles — `apps/chess/data/`

Puzzles from the Lichess puzzle database, https://database.lichess.org/#puzzles, released under
CC0 (public domain) by lichess.org; chosen by `apps/chess/make_banks.py`.

## Not included

Nothing from Xteink's firmware is in this repository. The packer embeds only the *public* half of
the key the firmware uses to accept packages; the firmware image, flash dumps and any text
extracted from them are excluded by `.gitignore`.
