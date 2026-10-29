# Store status

What is in the [Xteink store](https://xtapp-ai.xteink.cc/store?view=creator), written by
`tools/store_status.py` from `store/apps.json` (edit that file, not this one).

## Releasing an update

1. Change the app, raise `version` in its `manifest.json`, run its tests, commit.
2. `python -I tools/store_export.py <app>` writes `dist/store/<app>/<app>.zip`. Keep the app's
   `app_id`: the store kept ours (checked on Mahjong's live package), and a new one would install
   as a different app without the saved data.
3. Studio: open the app's project (Studio project id below), More (...) > Import backup with the
   zip; the project keeps its id. Save.
4. Developer Center > the app > Release new version: a higher release version, release notes,
   new screenshots if the screens changed. Submit for review.
5. In `store/apps.json`: the new `release_version`, `status: "in review"`, `submitted`; after
   the review `status: "published"` and `live_version`. Run `tools/store_status.py`, commit.

## Apps

| app | store name | app_id | release | status | live | submitted | Studio project |
|---|---|---|---|---|---|---|---|
| `calculator` | Calculator | `calculator` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `8b27ba9e-0825-46f4-a8b1-dc6f545f1cc3` |
| `calendar` | Calendar | `calendar` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `ac2744ef-3e9d-494c-8ee4-3a9ca918932f` |
| `hackernews` | Hacker News | `hackernews` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `70abf652-40aa-4091-ac58-9dfa81e818a5` |
| `instapaper` | Instapaper | `instapaper` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `900b4ce0-352d-4960-98d6-2e8c46978cd9` |
| `mahjong` | Mahjong | `mahjong` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `3d8374a5-4b5a-403a-941f-caacaed40dd9` |
| `readwise` | Readwise | `readwise` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `9f9f4778-901e-4a18-b863-033d9384a44c` |
| `rss` | RSS | `rss` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `89ca4ab2-9fb9-4017-8d88-31973aa0cc7d` |
| `tasks` | Tasks | `tasks` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `547d9981-6d6c-43a4-878d-612452ce57f0` |
| `tbr` | TBR Planner | `tbr` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `fa00e2a6-b3c6-4be5-8005-23255a6a91ea` |
| `wallabag` | wallabag | `wallabag` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `e3ab6293-9ad8-4e80-a5b6-433447d65052` |
| `weather` | Weather | `weather` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `7d246638-873f-49ee-918b-80b6151ef871` |
| `wikipedia` | Wikipedia | `wikipedia` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `a7bacca0-d2fc-437d-a9f9-fae6d2b6efe6` |
| `game2048` | 2048 | `twentyfortyeight` | 0.1.0 | in review | - | 2026-10-29 | `d2ef365a-0cbc-486a-9188-f2a3588bc7ca` |
| `anki` | Anki | `anki` | 0.1.1 | in review | - | 2026-10-29 | `d5ba24db-e60d-4be6-a0d8-2ed2a7896d48` |
| `chess` | Chess puzzles | `chess` | 0.1.0 | in review | - | 2026-10-29 | `835f1944-5c56-492c-a83d-f0348e3844cd` |
| `dict` | Dictionary | `dict` | 0.1.0 | in review | - | 2026-10-29 | `2f18566f-7cf9-46ee-80bc-bf455514b984` |
| `freecell` | FreeCell | `freecell` | 0.1.0 | in review | - | 2026-10-29 | `17ff4ea4-603c-461c-87f2-ce8d6ea38524` |
| `klondike` | Klondike | `klondike` | 0.1.0 | in review | - | 2026-10-29 | `cb0f7994-54d7-41a6-963d-fc1fd466c3d6` |
| `knightstour` | Knight's Tour | `knightstour` | 0.1.0 | in review | - | 2026-10-29 | `34c4be95-b474-4ee7-8224-ead826489eb8` |
| `lightsout` | Lights Out | `lightsout` | 0.1.0 | in review | - | 2026-10-29 | `5cc3b0a4-112a-4124-8f3c-9799f92cf3eb` |
| `litclock` | Literary Clock | `litclock` | 0.1.0 | in review | - | 2026-10-29 | `d30ca88a-e863-448d-9b29-94c7e7676b0c` |
| `merchant` | Merchant | `merchant` | 2.0.2 | in review | - | 2026-10-29 | `42e7380e-eef7-40ee-aa93-1736c028bd0b` |
| `minesweeper` | Minesweeper | `minesweeper` | 0.1.0 | in review | - | 2026-10-29 | `0f0322cf-6f46-4bbf-9ca1-01175a6614a7` |
| `nonogram` | Nonograms | `nonogram` | 0.1.0 | in review | - | 2026-10-29 | `9bf0893d-da29-41a1-9fb2-9c9be3fdd561` |
| `notes` | Notes | `notes` | 1.1.0 | in review | 1.0.0 | 2026-10-30 | `10ee478f-e339-4bc9-a0d1-370a22228ec1` |
| `pegsolitaire` | Peg Solitaire | `pegsolitaire` | 0.1.0 | in review | - | 2026-10-29 | `6870b261-a98d-4f66-af51-be27150a7c30` |
| `skytonight` | Sky Tonight | `skytonight` | 1.0.0 | in review | - | 2026-10-29 | `f17ef4eb-59be-469b-9ad7-796b984cab58` |
| `slidepuzzle` | Slide Puzzle | `slidepuzzle` | 1.3.1 | in review | - | 2026-10-29 | `115c852b-a613-4070-adab-d4ec60954c63` |
| `sokoban` | Sokoban | `sokoban` | 0.1.0 | in review | - | 2026-10-29 | `be00b928-97d8-49c6-b97c-7852606ef8d8` |
| `sudoku` | Sudoku | `sudoku` | 0.1.0 | in review | - | 2026-10-29 | `9fdc3d51-738a-4331-a16f-e6509c7d2aeb` |
| `suguru` | Suguru | `suguru` | 0.1.0 | in review | - | 2026-10-29 | `2901167c-5036-4bdd-b439-d5a7a7ffea8f` |
| `wordclock` | Word Clock | `wordclock` | 0.1.0 | in review | - | 2026-10-29 | `cbe64711-6b8e-455e-8394-4a12e4435fbe` |

12 published, 20 in review or draft, 32 in all.
