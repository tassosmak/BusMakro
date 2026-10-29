# BusMakro 1.1.0

A big update: search, favourites, live buses on the stop screen, OASA service alerts, and a smoother, more Mac-like window.

## New

- **Search** in the BusMakro bar: find lines by number or name, and stops by name, in Greek or Latin letters ("syntagma" finds ΣΥΝΤΑΓΜΑ). Each stop shows the lines that serve it. Clear the search to go back to where you were.
- **Favourite stops.** Tap the round ☆ on a stop to save it. The new **Favourites** tab on the home screen lists your stops with their next live arrivals.
- **Buses on their way.** The stop screen now shows the buses heading to that stop on the map, labelled with their line number. Click one to open its line with that bus followed.
- **Service alerts.** OASA's current disruption notices appear as an orange ⚠︎ card on affected stops and lines. Click one to read the full notice on oasa.gr.
- **Expand the map.** A round button on the map (or dragging the panel down) slides the top bar away and shrinks the panel to a strip. Drag it back up, or tap again, to restore it.
- **Full screen.** The top bar turns into round buttons on the sides; the search field grows out of its icon.
- **Works offline gracefully.** Without a connection the app says so, retries every 15 seconds and recovers on its own.
- **Update check.** BusMakro tells you when a newer version is out (*BusMakro → Check for Updates…* checks by hand).

## Improved

- Buses move along the roads between updates, as the live-data service recommends. Buses that are standing, off their route or haven't reported recently are shown faded.
- A cleaner top bar (no status line) with neatly aligned buttons, and a round location button on the map.

## Known issue

- On a line's map, some buses that aren't followed can still move oddly at times. A fix is planned for a future update.

## Install

1. Download **`BusMakro-1.1.0-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications** (replace the old one if you have it).
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.1.0-macOS.zip`): `b1ac1e431144fc765d6bea346a13baf7ca8cc8ae062b2c8c4fc3710cb17c362e`

## Good to know

- Timetable estimates (orange `~N min`) and the movement of buses between updates are a guide; the live OASA predictions (green) are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.
