-- Sky Tonight: the places to pick from, A to Z: name, latitude, longitude (degrees, east and north
-- positive). GUESS_TZ picks the first place for a time zone (standard offset in minutes) when no
-- place is saved yet; Turkish and German systems start in İstanbul and Berlin.

local PLACES = {
  { 'Adana', 37.00, 35.32 }, { 'Amsterdam', 52.37, 4.90 }, { 'Ankara', 39.93, 32.86 },
  { 'Antalya', 36.90, 30.70 }, { 'Athens', 37.98, 23.73 }, { 'Auckland', -36.85, 174.76 },
  { 'Baku', 40.41, 49.87 }, { 'Beijing', 39.90, 116.40 }, { 'Berlin', 52.52, 13.40 },
  { 'Brussels', 50.85, 4.35 }, { 'Bucharest', 44.43, 26.10 }, { 'Budapest', 47.50, 19.04 },
  { 'Buenos Aires', -34.60, -58.38 }, { 'Bursa', 40.19, 29.06 }, { 'Cairo', 30.04, 31.24 },
  { 'Chicago', 41.88, -87.63 }, { 'Cologne', 50.94, 6.96 }, { 'Copenhagen', 55.68, 12.57 },
  { 'Delhi', 28.61, 77.21 }, { 'Denver', 39.74, -104.99 }, { 'Diyarbakır', 37.91, 40.24 },
  { 'Dubai', 25.20, 55.27 }, { 'Dublin', 53.35, -6.26 }, { 'Erzurum', 39.90, 41.27 },
  { 'Eskişehir', 39.78, 30.52 }, { 'Frankfurt', 50.11, 8.68 }, { 'Gaziantep', 37.07, 37.38 },
  { 'Hamburg', 53.55, 9.99 }, { 'Helsinki', 60.17, 24.94 }, { 'Hong Kong', 22.32, 114.17 },
  { 'İstanbul', 41.01, 28.98 }, { 'İzmir', 38.42, 27.14 }, { 'Johannesburg', -26.20, 28.05 },
  { 'Karachi', 24.86, 67.01 }, { 'Kayseri', 38.73, 35.48 }, { 'Konya', 37.87, 32.48 },
  { 'Kyiv', 50.45, 30.52 }, { 'Lagos', 6.52, 3.38 }, { 'Lisbon', 38.72, -9.14 },
  { 'London', 51.51, -0.13 }, { 'Los Angeles', 34.05, -118.24 }, { 'Madrid', 40.42, -3.70 },
  { 'Melbourne', -37.81, 144.96 }, { 'Mexico City', 19.43, -99.13 }, { 'Milan', 45.46, 9.19 },
  { 'Moscow', 55.76, 37.62 }, { 'Munich', 48.14, 11.58 }, { 'Nairobi', -1.29, 36.82 },
  { 'New York', 40.71, -74.01 }, { 'Nicosia', 35.17, 33.36 }, { 'Oslo', 59.91, 10.75 },
  { 'Paris', 48.86, 2.35 }, { 'Prague', 50.08, 14.44 }, { 'Reykjavík', 64.15, -21.94 },
  { 'Riyadh', 24.71, 46.68 }, { 'Rome', 41.90, 12.50 }, { 'Samsun', 41.29, 36.33 },
  { 'San Francisco', 37.77, -122.42 }, { 'São Paulo', -23.55, -46.63 }, { 'Seoul', 37.57, 126.98 },
  { 'Shanghai', 31.23, 121.47 }, { 'Singapore', 1.35, 103.82 }, { 'Sofia', 42.70, 23.32 },
  { 'Stockholm', 59.33, 18.07 }, { 'Sydney', -33.87, 151.21 }, { 'Tbilisi', 41.72, 44.79 },
  { 'Tehran', 35.69, 51.39 }, { 'Tokyo', 35.68, 139.69 }, { 'Toronto', 43.65, -79.38 },
  { 'Trabzon', 41.00, 39.72 }, { 'Van', 38.50, 43.38 }, { 'Vancouver', 49.28, -123.12 },
  { 'Vienna', 48.21, 16.37 }, { 'Warsaw', 52.23, 21.01 }, { 'Washington', 38.91, -77.04 },
  { 'Zurich', 47.38, 8.54 },
}

local GUESS_TZ = {
  [0] = 'London', [60] = 'Paris', [120] = 'Athens', [180] = 'İstanbul', [210] = 'Tehran',
  [240] = 'Dubai', [300] = 'Karachi', [330] = 'Delhi', [480] = 'Beijing', [540] = 'Tokyo',
  [600] = 'Sydney', [720] = 'Auckland', [-180] = 'São Paulo', [-300] = 'New York',
  [-360] = 'Chicago', [-420] = 'Denver', [-480] = 'Los Angeles',
}

local function find_place(name)
  for _, p in ipairs(PLACES) do
    if p[1] == name then return { name = p[1], lat = p[2], lon = p[3] } end
  end
  return nil
end
