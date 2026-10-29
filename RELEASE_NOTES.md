# BusMakro 1.0.0

The first release of **BusMakro**, a native macOS app for Athens buses, in Greek and English.

## What it does

- **Stops near you.** Opens on the stops around you, from every line. Pan the map and the list follows to that area.
- **Every line at a stop.** Tap a stop to see each line that stops there, soonest first:
  - **green:** a bus is on the road (OASA's official live prediction)
  - **orange `~N min`:** no bus out yet, estimated from today's timetable plus the travel time to your stop
- **Line view.** The route drawn along the roads, buses moving live, arrival countdowns, delay against the schedule, every stop on the route, and the line's stops nearest you. Pin a bus and the map follows it.
- **Ελληνικά / English.** The whole app in either language: **View → Language**. English names use OASA's official ones, or ELOT 743 transliteration.
- **Feels like a Mac app.** SF Pro Rounded numbers, light/dark map, keyboard shortcuts (⌘Q, ⌘R refresh, ⌘L locate, ⌘[ back…), and a window bar and traffic lights that only appear when you hover the top edge.

## Install

1. Download **`BusMakro-1.0.0-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications**.
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.0.0-macOS.zip`): `4952fdaa6b2f8c2ec254a0f32bcd0e44108de6006c3c488c7e1b680cc38c0381`

## Good to know

- Timetable estimates (orange) are a rough guide: they show when a bus *should* leave, not when it does.
- The app depends on public data services: OASA's telematics API and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.
