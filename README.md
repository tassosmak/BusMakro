<p align="center"><img src="resources/icon.png" width="128" alt="BusMakro icon"></p>

# BusMakro

A native macOS app for tracking Athens (OASA) buses live, in Greek or English. Open it and it shows the stops around you; tap one to see every line that stops there and when the next bus comes.

It is built with Python and AppKit (via PyObjC) and has a phone-style layout: a full-window map with a floating top bar and a bottom sheet you can drag up and down.

## Download & install

1. Download **`BusMakro-<version>-macOS.zip`** from the [latest release](https://github.com/tassosmak/BusMakro/releases/latest).
2. Unzip it and drag **BusMakro** into your **Applications** folder.
3. **The first time you open it, macOS will block it**, because the app isn't signed with a paid Apple developer certificate:
   - **macOS 15 (Sequoia) and later:** open the app once, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   - **macOS 14 and earlier:** right-click (or Control-click) the app → **Open** → **Open**.

   You only need to do this once.
4. When it asks to use your location, click **Allow**, so it can show the stops near you. You can change this later in System Settings → Privacy & Security → Location Services.

**Requirements:** macOS 11 (Big Sur) or later, on an Apple Silicon Mac. The current build is arm64 only.

## Features

- **Stops near you on launch.** On the **Nearby** tab of the home screen, it finds your location and lists the closest stops of *any* line, also shown on the map. Pan the map elsewhere and the stops update to that area ("Stops in this area"); distances and walking times still count from you.
- **Every line at a stop.** Tap a stop (in the list or on the map) to see all the lines that stop there, soonest first. Lines with a bus on the road show the live OASA prediction in green. Lines with no bus out yet show a timetable estimate in orange (`~N min`, with the departure time from the terminus).
- **Buses on their way.** The stop screen also shows the buses heading to that stop on the map, each labelled with its line number. Click one to open its line with that bus followed.
- **Service alerts.** OASA's current disruption notices (from oasa.gr's announcements) appear as an orange ⚠︎ card on the stop screen and at the top of a line's arrivals, and affected lines get a ⚠︎ in the stop's list. Click a card to read the full notice.
- **Line view.** Tap a line to open it with that stop already selected. **‹ Back** steps back to the stop, then to the stops near you. You can also pick any line from the dropdown.
  - **Live map:** the route drawn along the roads (a blue line with an outline, for the selected variant), the line's stops, and its buses moving in real time, with a heading arrow on each bus. The map follows the system light/dark theme.
  - **Arrivals tab:** buses approaching the stop, with a live countdown, distance along the route and delay against the schedule ("On time", "+10 min").
  - **Route tab:** every stop on the line in order, with buses shown between the stops they're travelling between. If a line has several route variants, you can choose one.
  - **Nearby tab:** the line's stops closest to you, with walking times.
- **Menu bar countdown.** A 🚌 in the menu bar shows the soonest live bus at your favourite stops ("046 · 4′"); its menu lists every favourite with its next buses, and a click opens the stop. Closing the window keeps BusMakro there (*View → Show in Menu Bar* turns it off).
- **Strike radar.** Strikes and work stoppages announced by OASA appear as a red ⛔︎ card on top of the home and stop screens; other notices about the whole network in orange. Notices disappear once the days they are about have passed.
- **Bunching warning.** When two buses of a line arrive within 2 minutes of each other, the line says so, and how long the gap after them is ("2 together, then a 25 min gap").
- **Ghost buses.** BusMakro notices when buses OASA predicted vanish without ever arriving, and marks lines where that happens often ("👻 30% of buses vanish").
- **Learned arrival times.** It compares OASA's predictions with when buses actually arrived (kept only on your Mac) and, once it has enough samples for a line, corrects the time shown ("learned · OASA says 6 min").
- **3D buildings and map styles.** *View → 3D Buildings* (⌘3) tilts the map and raises the buildings; *View → Map Style* has Match System, Light, Dark and Night (with a glowing route).
- **Search.** The search field in the BusMakro bar finds lines (by number or name) and stops (by name, in Greek or Latin letters: "syntagma" finds ΣΥΝΤΑΓΜΑ), and shows which lines serve each stop. Clear it to go back to where you were.
- **Favourite stops.** Tap the round ☆ on a stop to save it. The **Favourites** tab on the home screen lists your saved stops with their next live arrivals and shows them on the map.
- **Works offline gracefully.** Without a connection the app says so ("No internet connection" or "Couldn't reach the bus service"). Click the message to retry, or just wait: it retries every 15 seconds and recovers on its own. In a line view, the last data stays on screen.
- **Update check.** On launch it asks GitHub whether a newer release exists, and shows an **Update** button in the bar if there is one. *BusMakro → Check for Updates…* checks by hand.
- **Follow a bus.** Pin a bus (⌖) and the map follows it.
- **Auto-refresh.** Data updates every 15 seconds; you can also refresh by hand.
- **Keyboard shortcuts.** ⌘Q quit, ⌘H hide, ⌘W close, ⌘M minimize, ⌘R refresh, ⌘L locate me, ⌘[ back, and ⌘C/⌘V/⌘A in the search field.
- **Expand the map.** The round expand button on the map (or dragging the panel down by its body) slides the top bar away and drops the panel to a slim strip, giving the map the whole window. The button again, or dragging the strip up, brings everything back. The round location button next to it finds you.
- **Full screen.** The top bar disappears, and its controls become round buttons on the sides: search on the left (the field grows out of the icon), refresh (and update, when there is one) on the right.
- **Window drag bar.** Hover over the top edge of the window and a bar fades in, together with the red/yellow/green window buttons (hidden otherwise): drag it to move the window, or double-click it to zoom.
- **Greek or English.** The whole app, including the menus, works in both. It starts in your Mac's language; switch it under **View → Language**. In English, stop and line names use OASA's official English names, or a standard (ELOT 743) transliteration where OASA has none.
- **Debug mode.** Writes a detailed log to the terminal and to an in-app overlay (🐞).

## Building from source

### Requirements

- macOS, with Python 3 in a conda environment (the project uses `oasa-gui`)
- These packages:

```bash
python -m pip install pyobjc-framework-Cocoa pyobjc-framework-WebKit pyobjc-framework-CoreLocation requests py2app
```

### Release build

```bash
/opt/anaconda3/envs/oasa-gui/bin/python tools/build_app.py
```

This creates `dist/BusMakro.app` and `dist/BusMakro-<version>-macOS.zip`. The app is fully standalone: it includes Python, every package and the shared libraries conda's Python needs (libffi, OpenSSL, zlib…). The script copies those libraries in, ad-hoc signs every library and the app, then zips it. The version number lives in `oasa/__init__.py` (`__version__`).

The icon is drawn by `tools/make_icon.py` (it writes `resources/icon.icns` and `resources/icon.png`).

### Development build

macOS only shows the location permission prompt for a real `.app` bundle, so for development, build an alias app once:

```bash
/opt/anaconda3/envs/oasa-gui/bin/python setup.py py2app -A
open "dist/BusMakro.app"
```

It runs the source files in place, so code changes take effect the next time you open it. You only need to rebuild if `setup.py` changes.

To see the debug log while running the app:

```bash
open --env BUSMAKRO_DEBUG=1 --stdout /dev/tty --stderr /dev/tty "dist/BusMakro.app"
```

### Directly with Python

```bash
/opt/anaconda3/envs/oasa-gui/bin/python main.py
/opt/anaconda3/envs/oasa-gui/bin/python main.py --debug
```

This works for everything except your location: macOS silently refuses location access to a bare `python` process, so the app falls back to the map centre.

You can also turn debug on by setting `BUSMAKRO_DEBUG=1`, or by setting `DEBUG_DEFAULT = True` in `oasa/debug.py`.

## Where the data comes from

| Source | Used for |
|---|---|
| `angelospk.github.io/athens-transit-rt/static/v1` | Static data: the list of lines, and each line's stops and route variants |
| `transit.haroldpoi.dev/v1/lines/<line>` | Live buses: position, speed, delay, trip label, next stop |
| `telematics.oasa.gr/api/` | OASA: closest stops (`getClosestStops`), lines at a stop (`webRoutesForStop`), official arrival predictions (`getStopArrivals`), today's timetable (`getDailySchedule`), each route's stops (`webGetStops`) |
| `oasa.gr/feed/`, `oasa.gr/en/feed/` | OASA announcements (RSS): service alerts, matched to lines by the numbers in their titles |
| CARTO basemaps + MapLibre GL | Map tiles and rendering |

The OASA API only answers **POST** requests; a GET returns an empty response. The CARTO key can be overridden with the `CARTO_KEY` environment variable.

## How arrival times (ETA) work

1. **Official prediction first.** The app asks OASA when each bus will reach the selected stop. These are the same predictions the official and other trusted apps show. OASA gives whole minutes, and the countdown runs down from the moment the prediction was fetched.
2. **Our own estimate as a fallback.** If OASA has no prediction for a bus, the app estimates one and marks it **"est."**:
   - **Distance:** measured along the route (bus → next stop → … → your stop), not in a straight line.
   - **Speed:** the average of the bus's recent speeds, kept between 2.5 and 11 m/s. If there's no speed data, it uses 4.5 m/s.
   - **GPS age:** the time since the GPS position was recorded is subtracted.

   You can tune these speeds in `oasa/config.py` (`ETA_DEFAULT_SPEED`, `ETA_MIN_SPEED`, `ETA_MAX_SPEED`).

Only buses that haven't yet passed the stop on their route variant are listed.

### Lines with no bus on the road yet

On the stop screen, a line with no live prediction gets a **timetable estimate**, shown in orange as `~N min`:

`next departure from the route's first stop (today's OASA timetable) + distance along the route to this stop ÷ 3.2 m/s`

3.2 m/s (about 11.5 km/h) is the real average pace measured on line 810, including stops and lights. It's only a rough guide: the timetable says when a bus *should* leave, not when it does, and traffic varies. A departure up to 3 minutes overdue still counts, because a bus often appears in tracking a little after leaving. If nothing more runs today, the line shows "No more buses today". You can tune both values in `oasa/config.py` (`SCHED_PACE_M_S`, `SCHED_DEPARTED_SLACK_MIN`).

## Project structure

```
main.py              Entry point: starts the macOS app
setup.py             py2app settings for "BusMakro.app" (version, icon, Info.plist with the location reason)
tools/
  build_app.py       Release build: py2app + bundled libraries + signing + zip
  make_icon.py       Draws the app icon
resources/           icon.icns (app icon), icon.png (README)
oasa/
  config.py          URLs, refresh rate, ETA settings, layout sizes
  debug.py           Debug flag and thread-safe logger
  api.py             HTTP helpers and the OASA calls (closest stops, lines at a stop, predictions)
  eta.py             Distances, the fallback ETA estimate, ETA/distance formatting
  schedule.py        Timetable-based ETA for lines with no bus on the road yet
  i18n.py            Greek/English text, place names and ELOT 743 transliteration
  favorites.py       Favourite stops (saved in the app's preferences)
  stop_index.py      Every stop of every line, for search (cached for a day in ~/Library/Caches/BusMakro)
  updates.py         Checks GitHub for a newer release
  alerts.py          OASA service alerts from oasa.gr's RSS feeds, matched to line numbers
  __init__.py        The version number (used by the app, the build and the update check)
  ui/
    widgets.py       Small AppKit helpers (labels, buttons, glass panels, fonts) and the list cards
    menu.py          The menu bar (keyboard shortcuts only work through menu items on macOS)
    views.py         Table data source, bottom-sheet drag handle, window drag bar, map → Python message bridge
    map.html         The MapLibre map page (route line, stops, animated buses, your location)
    map.py           Loads map.html
  app/
    core.py          OasaNativeApp: window setup, layout, and every method macOS calls
    explore.py       Home (stops near you) and stop (lines at a stop) screens, and navigating between them
    data.py          Fetching line data in the background and building arrival rows
    tabs.py          Route and Nearby tabs
    sheet.py         Bottom-sheet sizing, dragging and animation
    location.py      Your location (CoreLocation, falling back to the map centre)
```

### How the pieces fit together

- `OasaNativeApp` (in `app/core.py`) is the app delegate. It combines the `ExploreMixin`, `DataMixin`, `TabsMixin`, `SheetMixin` and `LocationMixin` classes from the other `app/` files.
- **Network requests run on background threads.** Their results go into a queue (`MainQueue`) that wakes the main thread (`checkResults_`) only when something arrives, and it updates the UI. While the window is hidden, refreshing, countdowns and the map's animation pause. AppKit must only be touched from the main thread.
- **The map is a web page in a `WKWebView`.** Python calls JavaScript functions on the page (`window.setStops`, `window.setBuses`, `window.setPinned`, …). The page sends clicks back through `MapHandler`.

### Adding code: where things go

PyObjC only registers methods called from Objective-C (button and menu actions, delegate callbacks, `NSTimer` targets) if they are defined **directly on `OasaNativeApp` in `core.py`**. Methods inherited from the mixin classes are not registered. In practice:

- A method whose name ends in `_` (for example `refresh_`, `tick_`, or a delegate method like `webView_didFinishNavigation_`) → put it in `app/core.py`.
- Any other helper method → put it in the mixin file for its area (`explore.py`, `data.py`, `tabs.py`, `sheet.py`, `location.py`).

## Credits

This app is built on other people's work. Thank you to:

- **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by [@angelospk](https://github.com/angelospk) (MIT License). It provides both the live bus API (`transit.haroldpoi.dev`) and the static line/stop data. It is a Go port of **[athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime)** by [@foivospro](https://github.com/foivospro).
- **[OASA](https://www.oasa.gr/)** (Athens Urban Transport Organisation): the source of all the bus data, including the official arrival predictions from its telematics API.
- **[MapLibre GL JS](https://maplibre.org/)** (BSD-3-Clause): map rendering.
- **[CARTO](https://carto.com/attributions)** basemaps, with map data © **[OpenStreetMap](https://www.openstreetmap.org/copyright)** contributors (ODbL). The map shows this attribution in its corner.
- **[PyObjC](https://pyobjc.readthedocs.io/)**: Python bindings for the macOS frameworks (AppKit, WebKit, CoreLocation).
- **[Requests](https://requests.readthedocs.io/)**: HTTP requests.
- **[py2app](https://py2app.readthedocs.io/)**: packaging the app.

This is an unofficial project. It is not affiliated with or endorsed by OASA.
