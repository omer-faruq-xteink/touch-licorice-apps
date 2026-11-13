# Sky Tonight 1.1.0: zoom, pan and constellation cards

## Intent
The Xteink team asked that tapping a region of the sky show "a more detailed introduction to the
galaxies". The user's reading: tap a part of the chart, it zooms in there, and a card tells what is
in that part of the sky (the constellation, its bright stars, objects worth finding). Zoom out goes
back; while zoomed, a swipe pans. English first (cards and object notes); Turkish and German later.

## Goals
- Tap on the full chart: zoom in around the tapped point and show the card of the constellation
  under the finger.
- In the zoomed view: drag (finger down, move, up) pans; a tap selects the constellation under the
  finger (card changes, view does not move); **Zoom out** returns to the full chart.
- The card: constellation name, one or two sentences on the name and its story, its brightest
  stars (names), when it is best seen in the evening (computed), up to three notable objects with
  one sentence each.
- Deep-sky objects (galaxies, nebulae, clusters visible to the eye or binoculars, about 30-40) are
  drawn in the zoomed view with a symbol and a short label (M31, M42...).

## Non-goals
- No change to the lock screen.
- No zoom levels beyond one (fixed factor), no pinch.
- No Turkish/German card text in this version (the app's UI words and constellation names stay
  translated; the card's text is English in every language until translated).
- No new stars (the catalogue stays at magnitude 4.5).

## Anti-goals
- The full chart and the -1 h / +1 h / Now behaviour must not change or get slower.
- A frame must stay under the host's limits (on_draw 1500 ms with budget:extend, 1024 commands).
- No copied text: every card sentence is written for this app.

## Approach (chosen: A)
- **A. Magnify the existing chart (chosen).** Same stereographic chart (zenith at the centre,
  horizon at the rim, north up, east left), drawn ZOOM times larger around a centre point in chart
  coordinates; whatever falls outside the visible area is clipped. Horizon rim, directions and
  figures stay as in the full view, so the user keeps their bearings. Reuses draw_sky with a zoom
  and a centre.
- B. A star-atlas projection centred on the region (true shapes near the horizon): new projection
  and labels, and loses the horizon and directions while zoomed. Not chosen.
- C. Render a large picture once and slide it: the reader's memory does not allow it, and the card
  would redraw anyway. Dropped.

## Decisions
- Zoom factor 2.5 (user's call open to change after a device look). Builder's note: the visible
  window is the chart's 412 px disc area (CX 240, CY 322, R 206) showing a 165 px-wide part of the
  full chart.
- Which constellation was tapped: the IAU constellation boundaries (d3-celestial's
  constellations.bounds.json, BSD like the figures already used; the NOTICE already carries the
  licence), converted by make_data.py to a compact data file; point-in-polygon in RA/Dec (J2000) of
  the tapped chart point (inverse stereographic + the sidereal time).
- Pan: from the pointer's down and up positions; a move over 20 px is a pan by the drag vector
  divided by the zoom, else a tap. The centre is kept so the visible area stays on the disc.
- Time steps while zoomed (-1 h / +1 h / Now): the view re-centres on the selected constellation's
  name point if it is above the horizon, else stays.
- Card replaces the facts block (moon, times, planets) while zoomed; buttons while zoomed:
  Zoom out, -1 h, +1 h (Place hidden).
- "Best seen" is computed: the month when the constellation's name point crosses the meridian at
  about 21:00 local solar time ("evenings in November"), so no per-hemisphere text is needed.
- Data files (package data, read with ctx.package on first zoom, not at start):
  `cards.txt` (abbr, name, story, stars, objects ids), `objects.txt` (id, type, ra, dec, mag,
  name, one sentence), `bounds.txt` (abbr and the polygon).
- Version 1.1.0, API stays 2.9 unless a newer feature is needed; then the newest API may be
  declared (the user, 2026-11-13: asking users to update the firmware is fine); README, release notes (v0.24.0), store export.

- Cards for all 88 constellations, in English (the user: "start with English"). If a card is
  missing anyway, the card shows the name and the computed lines (stars from the catalogue's names,
  best season) without a story.
- Boundary data (my call): d3-celestial's constellations.bounds.json is fetched by hand once and
  passed to make_data.py like its other inputs (not committed; NOTICE already covers d3-celestial).
- Clipping (my call): the API has no clip rectangle, so the zoomed chart is drawn first, items far
  outside the visible window are skipped in code, and then the header and card areas are painted
  paper-white over the overflow before their own content is drawn.
- Back (my call): while zoomed, Back zooms out; on the full chart it returns false (the host asks
  to exit), as in the other apps.
- Pointer (my call): a pan is applied on finger up (no live drag on e-ink); taps outside the
  visible chart, or below the horizon, do nothing; selecting a constellation never moves the view.

## Left to the builder
- Object symbols (e.g. ellipse for galaxies, dotted circle for clusters, square for nebulae).
- Card layout and line wrapping within the facts area; text length so a card fits.
- How the bounds polygons are stored and searched (bounding box first).
- Whether stars outside the clip are skipped early to stay inside the command budget.
