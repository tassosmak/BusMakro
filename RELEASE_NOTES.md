# BusMakro 1.4.0

Get told when your bus is close, jump anywhere with ⌘K, and a proper welcome.

## New

- **Bus alerts.** In a line's arrivals, click 🔔 on a bus and choose 1, 2, 3 or 5 stops: you get a notification when it's that close to your stop, even if you've moved on to another screen. Each bus now also shows how many stops away it is.
- **⌘K quick switcher.** Press ⌘K, type a line or a stop, press Return. Empty, it lists your recent and favourite stops.
- **Recent stops.** Your last stops appear as small chips under the search bar, one click away.
- **Welcome screen.** A short introduction on first launch, with buttons to allow location and notifications (*Help → Show Welcome* shows it again).
- **Settings (⌘,).** Language, menu bar, recent stops, map style and 3D buildings in one place. *BusMakro → Clear Recent Stops* empties the chips.

## Improved

- **Clock times for buses not on the road yet:** lines with only a timetable estimate now show when the bus should arrive (`10:55`) instead of `~25 min`.
- **Stop cards:** the stop's name on the left, distance and walk on the right; the nearest stop's distance is orange. The home tab is now called *Nearby Stops*.

## Install

1. Download **`BusMakro-1.4.0-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications** (replace the old one if you have it).
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.4.0-macOS.zip`): `92b9d17b3831b8de89e69b241fd0bd1bff7e809021c153a53eff4ab6ffc98d2b`

## Good to know

- Timetable estimates (orange clock times such as `10:55`), learned times and the movement of buses between updates are a guide; the live OASA predictions are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.
