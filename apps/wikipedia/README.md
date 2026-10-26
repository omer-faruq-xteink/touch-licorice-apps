# Wikipedia — XTOS Licorice mini app (API 2.9)

Read Wikipedia on the reader over Wi-Fi.

- **Search** with the firmware keyboard, or a **Random article**. Results show a line of each
  article; tap one to read it.
- Articles come as plain text from the MediaWiki API (the TextExtracts extract), laid out with
  the system fonts, sections as headings; page with **Prev / Next**, a tap on the left or right
  part of the page, a swipe or the side buttons. **Text size**: medium, large, small. Very long
  articles are cut after about 60 000 characters. Pictures, tables and links are not shown.
- **Language**: English, Simple English, Türkçe, Deutsch, Français, Español, Italiano,
  Nederlands, Português, Polski, Svenska, or any other Wikipedia's code (**Other**). The reader's
  fonts may not carry scripts other than Latin.
- **Read before**: the last 30 articles are kept on the reader and open without Wi-Fi.
- Wi-Fi is kept up while the app is in use (as in the RSS app) and let go when you leave it.

Files: `src/main.lua` (on `tools/gamekit`), `bundle.py`, `test_wikipedia.py`
(`python -I apps/wikipedia/test_wikipedia.py`).
