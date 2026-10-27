# Weather — XTOS Licorice mini app (API 2.9)

The forecast from [Open-Meteo](https://open-meteo.com) (free, no account or key). Needs Wi-Fi.

- **Place**: type a city or town, pick it from the list.
- The screen: the temperature now (large), the sky, feels-like, humidity and wind; the next 12
  hours every second hour (time, sky, temperature, chance of rain); today and the next three days
  (low / high, chance of rain).
- **°F / °C** switches the unit. The forecast is kept, so the app opens at once; it is fetched
  again when over 30 minutes old, or on **Refresh**.
- **Lock** makes the forecast the lock screen (the firmware asks once; only one app can be the
  lock screen at a time). It shows the forecast saved last and its age; when that is over an
  hour old it asks Open-Meteo again, if the reader lets the lock screen use Wi-Fi.

Files: `src/wx.lua` (the forecast cache, weather codes, icons and large digits), `src/main.lua` (on
`tools/gamekit`), `src/lock/lock.lua` (the lock screen; `bundle.py` joins it with `wx.lua` into
`lockscreen.lua`), `test_weather.py` (`python -I apps/weather/test_weather.py`).

Weather data by Open-Meteo.com (CC BY 4.0).
