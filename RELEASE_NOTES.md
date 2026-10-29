# BusMakro 1.2.1

A small update: a lighter app and a nicer dark map.

## Improved

- **Uses less memory.** The map now keeps a limited number of map tiles in memory, and 3D buildings are only drawn at street level: about 300 MB in total instead of about 490 MB.
- **Dark map = night look.** The dark map style now always has the glowing route and the deep blue 3D buildings. *View → Map Style* is simply Match System, Light and Dark.

## Known issue

- On a line's map, some buses that aren't followed can still move oddly at times. A fix is planned.

## Install

1. Download **`BusMakro-1.2.1-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications** (replace the old one if you have it).
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.2.1-macOS.zip`): `5016d3350ed9db60f22c8164d5311bede92a81eec6ac09c900358095f0777052`

## Good to know

- Timetable estimates (orange `~N min`), learned times and the movement of buses between updates are a guide; the live OASA predictions are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.

## Also new since 1.1.0

Menu bar countdown, strike radar, bunching warnings, ghost buses, learned arrival times, 3D buildings, motion, lighter glass and a big battery improvement. See the [1.2.0 notes](https://github.com/tassosmak/BusMakro/releases/tag/v1.2.0).
