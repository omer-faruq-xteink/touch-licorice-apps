# Store status

What is in the [Xteink store](https://xtapp-ai.xteink.cc/store?view=creator), written by
`tools/store_status.py` from `store/apps.json` (edit that file, not this one).

## Releasing an update

1. Change the app, raise `version` in its `manifest.json`, run its tests, commit.
2. `python -I tools/store_export.py <app>` writes `dist/store/<app>/<app>.zip`. Keep the app's
   `app_id`: the store kept ours (checked on Mahjong's live package), and a new one would install
   as a different app without the saved data.
3. Studio: the listing reads the package from the app's own project (Studio project id below), and
   Import backup always makes a NEW project (found on Anki, 2026-11-04). So open the app's project
   (My projects > the app > Studio) and either use More > Overwrite current project with the
   export (replaces the files and keeps the listing; Bookworm 1.1.0, 2026-11-08), or replace the
   changed files in the editor (index.lua, lockscreen.lua, manifest.json from the export or the
   pushed repo) and save each file. Then the top Save (the cloud copy). Data files only when they
   changed. A later cloud save may raise the manifest's version by itself (1.1.0 became 1.1.1):
   check manifest.json and set it back if it does.
4. Developer Center > the app > Release new version: a higher release version (the field comes
   filled with the old one: replace it), release notes, new screenshots if the screens changed.
   Orientation can come back empty (Sky Tonight 1.0.1): set it, or the submit does nothing.
   Save draft keeps the version and release notes but not the orientation, the reviewer note or
   changes to About / How to use (RSS 1.3.0, 2026-11-08): set those in the same visit, then
   Submit for review. The top Save in Studio offers "Submit this version", which leads here.
   The agreement box is not needed to submit.
5. In `store/apps.json`: the new `release_version`, `status: "in review"`, `submitted`; after
   the review `status: "published"` and `live_version`. Run `tools/store_status.py`, commit.

## Apps

| app | store name | app_id | release | status | live | submitted | Studio project |
|---|---|---|---|---|---|---|---|
| `game2048` | 2048 | `twentyfortyeight` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `d2ef365a-0cbc-486a-9188-f2a3588bc7ca` |
| `anki` | Anki | `anki` | 1.1.0 | published | 1.1.0 | 2026-11-04 | `d5ba24db-e60d-4be6-a0d8-2ed2a7896d48` |
| `backgammon` | Backgammon | `backgammon` | 1.0.0 | published | 1.0.0 | 2026-11-04 | `eca078ae-b008-4f88-bc03-92f201b1714c` |
| `bookworm` | Bookworm | `bookworm` | 1.1.0 | published | 1.1.0 | 2026-11-08 | `3c24e555-c442-42a7-bcc9-05ab60b1e975` |
| `calculator` | Calculator | `calculator` | 1.1.0 | published | 1.1.0 | 2026-11-09 | `8b27ba9e-0825-46f4-a8b1-dc6f545f1cc3` |
| `casefiles` | Case Files | `casefiles` | 1.0.0 | published | 1.0.0 | 2026-11-06 | `42efc232-ad42-47d2-8b09-71fe89051741` |
| `checkers` | Checkers | `checkers` | 1.0.0 | published | 1.0.0 | 2026-11-03 | `6cea5da4-eaf2-42fe-b5ea-35632a8f74b9` |
| `chessplay` | Chess | `chessplay` | 1.0.0 | published | 1.0.0 | 2026-11-03 | `eb70de48-11b6-4061-baca-04d77e071955` |
| `chess` | Chess puzzles | `chess` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `835f1944-5c56-492c-a83d-f0348e3844cd` |
| `cryptogram` | Cryptogram | `cryptogram` | 1.0.0 | published | 1.0.0 | 2026-10-31 | `9cf7c2da-b43d-4604-b2a8-20831b432999` |
| `delve` | Delve | `delve` | 1.0.0 | published | 1.0.0 | 2026-11-01 | `f48f0c06-c0cf-4cec-a8c9-8c0523c558e6` |
| `dict` | Dictionary | `dict` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `2f18566f-7cf9-46ee-80bc-bf455514b984` |
| `freecell` | FreeCell | `freecell` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `17ff4ea4-603c-461c-87f2-ce8d6ea38524` |
| `gamebook` | Gamebook | `gamebook` | 1.0.1 | published | 1.0.1 | 2026-11-03 | `89c08996-c25d-4eda-9977-a0b19f50e23d` |
| `tsumego` | Go problems | `tsumego` | 1.0.0 | published | 1.0.0 | 2026-10-31 | `a255a696-b673-481a-b444-b5ed661e84bc` |
| `hackernews` | Hacker News | `hackernews` | 1.2.0 | published | 1.2.0 | 2026-11-08 | `70abf652-40aa-4091-ac58-9dfa81e818a5` |
| `hashi` | Hashi | `hashi` | 1.0.1 | published | 1.0.1 | 2026-11-01 | `5bc739e3-198a-45ec-adec-c670eb0f2dae` |
| `instapaper` | Instapaper | `instapaper` | 1.2.0 | published | 1.2.0 | 2026-11-08 | `900b4ce0-352d-4960-98d6-2e8c46978cd9` |
| `kakuro` | Kakuro | `kakuro` | 1.0.1 | published | 1.0.1 | 2026-11-01 | `81dbbe6a-3f72-438f-9db8-5c105c5328f4` |
| `klondike` | Klondike | `klondike` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `cb0f7994-54d7-41a6-963d-fc1fd466c3d6` |
| `knightstour` | Knight's Tour | `knightstour` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `34c4be95-b474-4ee7-8224-ead826489eb8` |
| `lamplighter` | Lamplighter | `lamplighter` | 1.0.0 | published | 1.0.0 | 2026-11-06 | `735ff7d3-4a31-4246-8daa-2473307dbe83` |
| `lightsout` | Lights Out | `lightsout` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `5cc3b0a4-112a-4124-8f3c-9799f92cf3eb` |
| `litclock` | Literary Clock | `litclock` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `d30ca88a-e863-448d-9b29-94c7e7676b0c` |
| `mahjong` | Mahjong | `mahjong` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `3d8374a5-4b5a-403a-941f-caacaed40dd9` |
| `merchant` | Merchant | `merchant` | 2.0.2 | published | 2.0.2 | 2026-10-29 | `42e7380e-eef7-40ee-aa93-1736c028bd0b` |
| `minesweeper` | Minesweeper | `minesweeper` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `0f0322cf-6f46-4bbf-9ca1-01175a6614a7` |
| `nonogram` | Nonograms | `nonogram` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `9bf0893d-da29-41a1-9fb2-9c9be3fdd561` |
| `notebook` | Notebook | `notebook` | 1.0.1 | published | 1.0.1 | 2026-11-06 | `bfdb56a1-5848-4583-8085-63262ad00636` |
| `notes` | Notes | `notes` | 1.1.1 | published | 1.1.1 | 2026-11-03 | `10ee478f-e339-4bc9-a0d1-370a22228ec1` |
| `pegsolitaire` | Peg Solitaire | `pegsolitaire` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `6870b261-a98d-4f66-af51-be27150a7c30` |
| `queens` | Queens | `queens` | 1.0.0 | published | 1.0.0 | 2026-11-03 | `bf6810f5-1e65-4774-8cf2-4428f90b18d5` |
| `readwise` | Readwise | `readwise` | 1.2.0 | published | 1.2.0 | 2026-11-08 | `9f9f4778-901e-4a18-b863-033d9384a44c` |
| `rss` | RSS | `rss` | 1.3.0 | published | 1.3.0 | 2026-11-08 | `89ca4ab2-9fb9-4017-8d88-31973aa0cc7d` |
| `skytonight` | Sky Tonight | `skytonight` | 1.0.1 | published | 1.0.1 | 2026-11-04 | `f17ef4eb-59be-469b-9ad7-796b984cab58` |
| `slidepuzzle` | Slide Puzzle | `slidepuzzle` | 1.3.1 | published | 1.3.1 | 2026-10-29 | `115c852b-a613-4070-adab-d4ec60954c63` |
| `sokoban` | Sokoban | `sokoban` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `be00b928-97d8-49c6-b97c-7852606ef8d8` |
| `sudoku` | Sudoku | `sudoku` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `9fdc3d51-738a-4331-a16f-e6509c7d2aeb` |
| `suguru` | Suguru | `suguru` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `2901167c-5036-4bdd-b439-d5a7a7ffea8f` |
| `tarot` | Tarot | `tarot` | 1.0.0 | published | 1.0.0 | 2026-11-01 | `e505686d-eb7a-4648-a224-859c17aa76f2` |
| `tasks` | Tasks | `tasks` | 1.2.0 | published | 1.2.0 | 2026-11-09 | `547d9981-6d6c-43a4-878d-612452ce57f0` |
| `tbr` | TBR Planner | `tbr` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `fa00e2a6-b3c6-4be5-8005-23255a6a91ea` |
| `textadv` | Text adventures | `textadv` | 1.0.0 | published | 1.0.0 | 2026-10-31 | `09148091-fa75-4eed-94f4-4cdface99a69` |
| `wallabag` | wallabag | `wallabag` | 1.3.0 | published | 1.3.0 | 2026-11-08 | `e3ab6293-9ad8-4e80-a5b6-433447d65052` |
| `weather` | Weather | `weather` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `7d246638-873f-49ee-918b-80b6151ef871` |
| `wikipedia` | Wikipedia | `wikipedia` | 1.0.0 | published | 1.0.0 | 2026-10-29 | `a7bacca0-d2fc-437d-a9f9-fae6d2b6efe6` |
| `wordclock` | Word Clock | `wordclock` | 0.1.0 | published | 0.1.0 | 2026-10-29 | `cbe64711-6b8e-455e-8394-4a12e4435fbe` |
| `wordhive` | Word Hive | `wordhive` | 1.0.0 | published | 1.0.0 | 2026-10-31 | `7e35f8f2-a168-4c3c-b22a-492b83ef84ac` |
| `wordladder` | Word Ladder | `wordladder` | 1.0.1 | published | 1.0.1 | 2026-11-01 | `0975b389-101d-444e-9d66-ee8856c15112` |
| `calendar` | Calendar | `calendar` | 1.1.2 | in review | 1.1.1 | 2026-11-10 | `ac2744ef-3e9d-494c-8ee4-3a9ca918932f` |
| `timekeeper` | Timekeeper | `timekeeper` | 1.0.1 | in review | - | 2026-11-10 | `d80faaff-07e6-4c30-8d38-a15a1ee79e64` |

49 published, 2 in review or draft, 51 in all.
