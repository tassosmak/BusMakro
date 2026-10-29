# BusMakro 1.2.0

BusMakro gets smarter about Athens buses, lives in your menu bar, feels alive, and is far kinder to your battery.

## New

- **Menu bar countdown.** A 🚌 in the menu bar shows the next live bus at your favourite stops ("046 · 4′"). Its menu lists each favourite with its next buses; click one to open it. Closing the window keeps BusMakro in the menu bar (*View → Show in Menu Bar* turns it off).
- **Strike radar.** Strikes and work stoppages announced by OASA show as a red ⛔︎ card at the top of the home and stop screens, and notices about the whole network in orange. Notices disappear once their dates have passed.
- **Bunching warning.** When two buses of a line arrive together, you see it, and how long the gap after them is: "2 together, then a 25 min gap".
- **Ghost buses.** BusMakro notices when predicted buses vanish without arriving, and marks lines where it happens often ("👻 30% of buses vanish").
- **Learned arrival times.** BusMakro compares OASA's predictions with when buses really arrived and corrects the times it shows once it has enough data for a line ("learned · OASA says 6 min"). This history stays on your Mac, and it takes a few days of use to kick in.
- **3D buildings** (*View → 3D Buildings*, ⌘3) and **map styles** (*View → Map Style*: Match System, Light, Dark, Night).

## Improved

- **Motion.** Lists ease in, arrival times roll to their new value, live times have a gently pulsing dot, buses arriving now glow green, and buses on the map ripple when they report a new position.
- **Lighter glass.** The top bar and panel are more see-through, and the cards are frosted panes instead of grey boxes.
- **Battery.** Idle CPU use dropped from about 14% to under 1%, and to almost nothing while the window is hidden: no more constant polling, and refreshing and animations pause when you can't see them. Data refreshes right away when the window comes back or the Mac wakes.
- Expired alerts no longer show up.

## Known issue

- On a line's map, some buses that aren't followed can still move oddly at times. A fix is planned.

## Install

1. Download **`BusMakro-1.2.0-macOS.zip`** below, unzip it, and move **BusMakro** to **Applications** (replace the old one if you have it).
2. **First launch:** the app isn't notarized by Apple, so macOS blocks it the first time.
   - **macOS 15 (Sequoia) and later:** open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click the app → **Open** → **Open**.
3. Allow location access when asked, so it can show the stops near you.

**Requirements:** macOS 11 or later, **Apple Silicon** (M1 or newer). Intel Macs aren't supported in this build.

**SHA-256** (`BusMakro-1.2.0-macOS.zip`): `de104704f384c83ae57643be260c76171f2ef4b60accabadedcd6de0529c9ff6`

## Good to know

- Timetable estimates (orange `~N min`), learned times and the movement of buses between updates are a guide; the live OASA predictions are the official times.
- The app depends on public data services: OASA (telematics API and oasa.gr announcements) and [athens-transit-rt](https://github.com/angelospk/athens-transit-rt). If one of them is down, parts of the app will be empty.
- This is an unofficial app, not affiliated with or endorsed by OASA.

## Thanks

Data from **OASA** and **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by @angelospk (a port of [athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime) by @foivospro). Maps by **MapLibre GL JS** and **CARTO**, map data © **OpenStreetMap** contributors. Built with **PyObjC**, **Requests** and **py2app**.
