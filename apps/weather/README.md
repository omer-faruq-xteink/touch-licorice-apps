# Weather — XTOS Licorice mini app (API 2.26)

The forecast from [Open-Meteo](https://open-meteo.com) (free, no account or key). Needs Wi-Fi.

- **Place**: type a city or town, pick it from the list.
- The screen: the temperature now (large), the sky, feels-like, humidity and wind; the next 12
  hours every second hour (time, sky, temperature, chance of rain); today and the next three days
  (low / high, chance of rain).
- **°F / °C** switches the unit. The forecast is kept, so the app opens at once; it is fetched
  again when over 30 minutes old, or on **Refresh**.
- **Lock** makes the forecast the lock screen (the firmware asks once; only one app can be the
  lock screen at a time) and asks how often it fetches a new forecast while the reader is locked:
  every 15 or 30 minutes, every hour, every 3 or 6 hours, or never (it then shows the forecast saved
  last). It says when the forecast was fetched ("updated 14:05"), and a new day always brings a
  new one. The button then shows the choice ("Lock 15 m", "Lock 3 h", "Lock only"); tap it
  to change it or to turn the lock screen off. The lock screen wakes at that interval, on the quarter
  hour or the hour (3 and 6 hours wake hourly, the longest the firmware allows), with Wi-Fi on for a few seconds when it fetches. Needs firmware 26111201 or later (API 2.26).

Files: `src/wx.lua` (the forecast cache, weather codes, icons and large digits), `src/main.lua` (on
`tools/gamekit`), `src/lock/lock.lua` (the lock screen; `bundle.py` joins it with `wx.lua` into
`lockscreen.lua`), `test_weather.py` (`python -I apps/weather/test_weather.py`).

Weather data by Open-Meteo.com (CC BY 4.0).
