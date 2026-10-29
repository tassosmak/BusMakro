# BusMakro 1.3.0

A new look, full timetables, and buses that finally move the way they should.

## New

- **Timetable tab.** Every line now has a fourth tab with today's departures from each end of the line: past times dimmed, the next one highlighted, scrolled straight to now.
- **New top bar.** Just a floating glass search field with round buttons beside it. Click into it and it grows over the buttons; clear the search and they come back.

## Fixed

- **Buses no longer wander.** Buses you aren't following used to run ahead of their real position and then slide back when a new GPS fix arrived (about one update in four). They now drive only to their next stop and wait there, and never reverse a short way. Checked against recorded live data: backward slides dropped from 72 to 6 in 272 updates.
- **Locate Me stays on you** instead of sometimes zooming out to the whole city.
- The search field's icon no longer overlaps the text.

## Improved

- **Less memory in the background.** After 3 minutes hidden, BusMakro drops the map entirely (the menu bar keeps working) and rebuilds it where you left it when you come back.
- **Pausing when hidden is reliable now:** hiding the app (⌘H), minimising and closing are noticed directly.
- **Cleaner panel:** the menu, tabs and every card line up on one edge; the line menu is smaller with corners that follow the panel's.
- **Cleaner map:** the zoom and ⓘ buttons are gone (zoom with the trackpad); the map credit is a faint line under the search field.

## Install

1. Download **`BusMakro-1.3.0-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications** (replace the old one if you have it).
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.3.0-macOS.zip`): `b84a4294cdae89e98f79e4f086534e38c5b4d1ef448e5f25a1985f503824e181`

## Good to know

- Timetable estimates (orange `~N min`), learned times and the movement of buses between updates are a guide; the live OASA predictions are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.

## Good to know

- Timetable estimates (orange `~N min`), learned times and the movement of buses between updates are a guide; the live OASA predictions are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.

## Also new since 1.1.0

Menu bar countdown, strike radar, bunching warnings, ghost buses, learned arrival times, 3D buildings, motion, lighter glass and a big battery improvement. See the [1.2.0 notes](https://github.com/tassosmak/BusMakro/releases/tag/v1.2.0).
