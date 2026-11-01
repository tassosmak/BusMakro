# BusMakro for iPhone and Mac (SwiftUI) — early work

The start of the SwiftUI rewrite, with Apple Maps (MapKit). The Python Mac app keeps working
meanwhile.

- `BusMakroKit/` — the shared data side: models, the OASA telematics client and the live-bus
  client (athens-transit-rt), distances. Builds with the command-line tools:
  `swift run busmakro-check` prints the stops near Syntagma, their lines and live buses.
- `BusMakroApp/` — the app: a map of the stops near where you look, and the lines at a stop.
  Needs the full **Xcode**: `brew install xcodegen`, then `xcodegen` in this folder, and open
  `BusMakro.xcodeproj` (one target for iPhone and Mac).
