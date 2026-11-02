<p align="center"><img src="resources/icon.png" width="128" alt="BusMakro icon"></p>

# BusMakro

Athens buses, metro and tram, live, for **iPhone and Mac**, in Greek or English. Open it and it shows the stops around you. Tap one to see every line that stops there and when the next bus comes, with the buses moving on the map.

This branch (`swiftui`) is the native SwiftUI app, built with Apple Maps (MapKit). The original Python/AppKit Mac app lives on the [`main`](https://github.com/tassosmak/BusMakro/tree/main) branch.

[Privacy Policy](https://tassosmak.github.io/BusMakro/privacy.html) · [Support](https://github.com/tassosmak/BusMakro/issues)

## Features

### Buses
- **Stops near you.** The home screen lists the closest stops and shows them on the map. Pan the map and every stop in view appears; zoomed far out, the map shows only your favourites with a "Zoom in to see bus stops" hint, and the list stays on the stops around you.
- **Every line at a stop**, soonest first, with OASA's live prediction or the timetable time when no bus is out yet.
- **Live buses on the map**, gliding along the road between GPS fixes, with a heading arrow.
- **Line view** with four tabs:
  - **Arrivals:** approaching buses with a countdown and stops away. A green dot marks OASA's official prediction; `~` marks the app's own estimate. Long-press a bus for its number, delay and trip.
  - **Route:** every stop in order, with buses drawn between them.
  - **Nearby:** the line's stops closest to you.
  - **Timetable:** the departures for any day of the week (OASA has separate schedules for weekdays, Friday, Saturday, Sunday…).
- **Follow a bus** (⌖): the map follows it.
- **Bus alerts** (🔔): a notification when a bus is 1, 2, 3 or 5 stops from your stop, and a **Live Activity** on the Lock Screen and in the Dynamic Island.
- **Service alerts and strikes** from OASA's announcements.

### Metro and tram
- Metro lines M1–M3 and the tram drawn on the map, with stations you can tap for their next trains.
- **Metro map:** STASY's network map, zoomable.
- Timetables are built into the app from STASY's GTFS feed, so they work offline.

### Trip planner
- From where you are (or any place) to any address or stop, by bus, metro and tram with up to one change, using the live wait for the first leg.

### Favourites
- Favourite **stops and lines**, with a filter for stops, lines or both.
- **Nicknames** ("Home", "Work") and **reordering** by long press or drag.
- Favourite stops drawn on the map in their own colour, chosen in Settings.

### iPhone integrations
- **Siri and Shortcuts:** "Next buses at…", open a stop or line, search.
- **Spotlight:** favourite stops are searchable.
- **Home-screen quick actions** for your favourites, and `busmakro://` links.

### Comfort
- Recent stops as chips under the search bar; map layers (stops, buses, metro, tram) you can hide.
- Light, dark or system map style, 3D buildings.
- Works offline gracefully: says so, shows when the data was last updated, and recovers on its own.
- VoiceOver labels, Reduce Motion, and lighter animations in Low Power Mode.

## Building

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

```bash
cd swift/BusMakroApp && xcodegen
```

Then open `swift/BusMakroApp/BusMakro.xcodeproj`. One target builds for iPhone and Mac; a second target holds the Live Activity widget. Debug builds have a Debug menu in the side menu; Release builds leave it out.

The data side is a Swift package that builds with the command-line tools alone:

```bash
cd swift/BusMakroKit && swift run busmakro-check
```

It prints the stops near Syntagma with their lines and live buses. `busmakro-check approach 814` lists how many buses are heading to each stop of a line, and `busmakro-check plan` runs a sample trip.

The metro and tram data (`Rail.json`) is rebuilt from STASY's GTFS feed with `swift/tools/build_rail.py`.

## Project structure

| Folder | What's in it |
|---|---|
| `swift/BusMakroKit/` | Models, the OASA and live-bus clients, timetables, the stop index, metro/tram timetables, the trip planner, bus movement |
| `swift/BusMakroApp/Shared/` | The app: map, panel, line and stop screens, favourites, settings, Siri/Spotlight, alerts |
| `swift/BusMakroApp/Widgets/` | The Live Activity (Lock Screen and Dynamic Island) |
| `swift/BusMakroApp/Activity/` | What the app and the widget share about a Live Activity |
| `docs/` | The website: support page and privacy policy (GitHub Pages) |

## Where the data comes from

| Source | Used for |
|---|---|
| `telematics.oasa.gr/api/` | OASA: stops, lines at a stop, official arrival predictions, routes, timetables |
| `transit.haroldpoi.dev` | Live bus positions, speed, delay and trip ([athens-transit-rt](https://github.com/angelospk/athens-transit-rt)) |
| `angelospk.github.io/athens-transit-rt/static/v1` | Lines, route variants and road shapes |
| `oasa.gr` feeds | Service alerts and strike notices |
| STASY GTFS (data.gov.gr) | Metro and tram stations, lines and timetables, built into the app |
| Apple Maps (MapKit) | The map and place search |

## Privacy

BusMakro collects no personal data: no accounts, analytics, ads or tracking. Location is used only on the device. Read the [privacy policy](https://tassosmak.github.io/BusMakro/privacy.html).

## Credits

- **[athens-transit-rt](https://github.com/angelospk/athens-transit-rt)** by [@angelospk](https://github.com/angelospk) (MIT License): the live bus API and static line data. It is a Go port of **[athens-gtfs-realtime](https://github.com/foivospro/athens-gtfs-realtime)** by [@foivospro](https://github.com/foivospro).
- **[OASA](https://www.oasa.gr/)**: the bus data and official arrival predictions.
- **[STASY](https://www.stasy.gr/)**: the metro and tram timetables and the network map.

This is an unofficial project. It is not affiliated with or endorsed by OASA, OSY or STASY.
