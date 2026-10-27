# Wikipedia — XTOS Licorice mini app (API 2.9)

Read Wikipedia on the reader over Wi-Fi.

- **Search** with the firmware keyboard, or a **Random article**. Results show a line of each
  article; tap one to read it.
- Articles come as plain text from the MediaWiki API (the TextExtracts extract), laid out with
  the system fonts, sections as headings; page with **Prev / Next**, a tap on the left or right
  part of the page, a swipe or the side buttons. **Text size**: medium, large, small. A long
  article comes in **parts** of about 20 000 characters: Next past a part's last page fetches the
  next part, Prev before its first page the one before (the reader gives an app about 1 MB, and
  its JSON decoder gives up on long answers, which the app then reads itself). Pictures, tables
  and links are not shown. **Read before** keeps an article's first part.
- **Language**: English, Simple English, Türkçe, Deutsch, Français, Español, Italiano,
  Nederlands, Português, Polski, Svenska, or any other Wikipedia's code (**Other**). The reader's
  fonts may not carry scripts other than Latin.
- **Read before**: the last 30 articles are kept on the reader and open without Wi-Fi.
- Wi-Fi is kept up while the app is in use (as in the RSS app) and let go when you leave it.

## Offline packs

A pack holds the opening sections of a set of articles, read without Wi-Fi. With one on the card
the app opens on a list of **sources**: Online and each pack (the last one chosen opens next
time; **Online and other packs** goes back to the list).

- **Ready-made:** the release's `wikipedia-en-vital.zip`, English Wikipedia's 10 000 "vital
  articles" (level 4): 7 MB zipped, 18 MB unzipped. Unzip it into `XTApps/wikipedia/files/` (USB mode).
- **Search** finds titles starting with what you type (letters in either case); **Random** and
  **Read before** work as online.
- **Make your own** on a computer: `python wiki2pack.py out` (the English vital articles), or
  `python wiki2pack.py out --lang tr --titles titles.txt --prefix wtr` for any language and a list
  of titles. It asks Wikipedia's API for 20 articles at a time and writes files of at most
  150 KB sorted by title; a pack may hold up to about 50 000 opening sections (the app's folder
  takes 128 MB and 512 files).

Wikipedia text is CC BY-SA 4.0.

Files: `src/main.lua` (on `tools/gamekit`), `wiki2pack.py`, `bundle.py`, `test_wikipedia.py`
(`python -I apps/wikipedia/test_wikipedia.py`).
