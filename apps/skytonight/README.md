# Sky Tonight — XTOS Licorice mini app (API 2.9)

The night sky over your city, worked out on the device with no network: a round chart of the sky
as you see it looking up (north at the top, east on the left, the horizon the rim) with the stars
to magnitude 4.5, the constellation figures and names, the moon in its phase and the planets.
Under the chart: the moon's phase, how much of it is lit, when it rises and sets; sunset, dark
(the sun 12 degrees down) and sunrise; the planets that are up, with direction and height.

- **When**: at night the app opens on the sky now; by day on tonight, from the hour after dark.
  **-1 h** / **+1 h** (and the page keys) step through the night; **Now** / **tonight** swap.
- **Place**: 76 cities, A to Z, or **Coordinates** to type a latitude and longitude. Times are in
  the device's time zone. With nothing saved it starts in İstanbul (Turkish system), Berlin
  (German), else a city from the time zone.
- **Zoom**: tap the chart to see that part of the sky 2.5 times larger, with a card about the
  constellation you tapped: what it shows and its story, its brightest stars, the month it is best
  seen in the evening, and the galaxies, nebulae and star clusters worth finding in it (40, from
  the Andromeda Galaxy to the Magellanic Clouds, drawn on the zoomed chart with their catalogue
  numbers; its boundary is dashed). Drag to move around, tap another constellation for its card,
  **-1 h** / **+1 h** follow it through the night, **Card** hides the card for a taller chart, just the sky with
  no outline or picking (kept for next time), **Zoom out** or Back for the whole sky. Which constellation a point is in comes
  from the official IAU boundaries. The cards are in English, Turkish and German, like the app.
- **☰** (under the time): **Names** (constellations, stars, objects), **Lines** (the figures) and
  **Objects** (the zoomed chart's galaxy ovals, cluster circles and nebula squares), each on or off, for the whole sky and the zoomed one; kept for next time. The lock screen
  keeps both.
- **Lock screen** (on the Place page): the sky on the lock screen, redrawn every 15 minutes; the
  next new and full moon at the bottom.
- English, Türkçe and Deutsch (constellation names too): the system language at first, then the
  language button on the Place page, which the lock screen follows.

On a computer the place can also be set in `settings.txt` in the app's folder on the SD card
(`XTApps/skytonight/files/`, the store's app: `AppFiles/<app id>/`), any name you like:

```text
place=Home
lat=48.14
lon=11.58
lang=de
```

Latitude north and longitude east are positive (south and west negative); `lang` (en, tr, de) is
optional.

## How it is worked out

Everything is computed on the device each time, in `src/astro.lua`: the sun and the moon with the
Astronomical Almanac's low-precision formulae (the sun to about 0.01 degrees, the moon to about
0.3), the planets with JPL's approximate Keplerian elements (E. M. Standish; a few arcminutes,
1800-2050), the sidereal time from the IAU formula. The reader's numbers are 32-bit integers and
single-precision floats, so time is kept as whole seconds since 2000 and split into days and
seconds before the sidereal time, which turns once a day, is taken from it. Rise and set times
come from a half-hour scan of the altitude with two secant steps (under a minute off). The chart
is a stereographic projection straight from each star's direction vector.

`test_sky.py` checks this against known events: the full and new moons of 2026 (four of them
eclipses), the oppositions of Saturn, Jupiter and Mars and Venus's greatest elongation, Polaris
at the observer's latitude, sunrise and sunset in four cities against NOAA's solar calculator,
the midnight sun, the next new and full moon, and the sidereal time redone in single floats. It
also runs the app and the lock screen on a stand-in host (the 1024-command frame, the buttons,
places) and, with a folder argument, draws each frame to a PNG.

## Files

`make_data.py` (writes `data/`: `stars.txt` 904 stars, `lines.txt` the constellation figures,
`names.txt` 89 constellation names with their IAU abbreviations in three languages,
`stars_named.txt` the 30 star names the chart shows, `bounds.txt` the IAU constellation boundaries;
written by hand: `cards.txt` the 88 constellation cards, `objects.txt` the 40 deep-sky objects,
`cards_tr.txt`, `cards_de.txt`, `objects_tr.txt`, `objects_de.txt` their Turkish and German), `src/astro.lua`, `src/places.lua`, `src/sky.lua` (settings, words, the chart),
`src/app.lua`, `src/lock.lua`, `bundle.py` (makes `index.lua` and `lockscreen.lua`),
`test_sky.py` (`python -I apps/skytonight/test_sky.py [PNG_DIR]`), `test_data.py` (every point of
the sky in exactly one constellation, each object inside the constellation it is listed under, a
card for each).

The first frame opens five font sizes and draws up to 900 stars, which can take longer than the
1.5 s the host gives `on_draw` (a German reader closed the app at 1.52 s), so the app calls
`ctx.budget:extend()` in its callbacks. The lock screen cannot extend its 2 s and stops drawing the
faint stars after 1.5 s instead. An error at start is shown in full on the screen.
`python -I apps/skytonight/bundle.py --debug OUT.xtapp` packs a build that logs each step, with
the time and the heap, to `debug.txt` (the lock screen: `debug_lock.txt`) in the app's folder.

## Data and credits

- Stars: the Yale Bright Star Catalogue, 5th edition (NASA HEASARC `heasarc_bsc5p`), public domain.
- Constellation figures, names and boundaries: [d3-celestial](https://github.com/ofrohn/d3-celestial)
  (`constellations.lines.json`, `constellations.json`, `constellations.bounds.json`), Copyright (c) 2015, Olaf Frohn, BSD
  3-clause licence; the full notice is in `data/NOTICE.txt`, which is packed with the app.
