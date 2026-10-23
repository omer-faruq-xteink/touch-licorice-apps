# Third-party content

The app code in this repository is MIT licensed (see `LICENSE`). It bundles the following.

## Packer core — `tools/vendor/xtapp.py`, `tools/vendor/mksd.py`

From [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu), MIT License, Copyright (c) 2026
KFloyd.com. Full text in `tools/vendor/LICENSE-x4pro-emu`. The reverse engineering of the Licorice
package format, the device key wrap and the Lua host API documented there made all of this
possible.

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

## Not included

Nothing from Xteink's firmware is in this repository. The packer embeds only the *public* half of
the key the firmware uses to accept packages; the firmware image, flash dumps and any text
extracted from them are excluded by `.gitignore`.
