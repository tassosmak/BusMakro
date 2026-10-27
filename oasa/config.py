"""Endpoints, refresh rate, ETA tuning and layout constants."""
import os


API_BASE = "https://transit.haroldpoi.dev"

STATIC_BASE = "https://angelospk.github.io/athens-transit-rt/static/v1"

REFRESH_SECONDS = 15

# CARTO basemap key (override with the CARTO_KEY environment variable).
CARTO_KEY = os.environ.get('CARTO_KEY', 'cb1_4v3t_1_dd094c601707cc4b025a0b28')

# Autoresizing masks
W_SIZABLE, H_SIZABLE = 2, 16

MIN_X_MARGIN, MIN_Y_MARGIN, MAX_Y_MARGIN = 1, 8, 32

ROW_H = 78          # arrival card

STOP_ROW_H = 46     # route: stop

BUS_ROW_H = 34      # route: bus between stops

NEAR_ROW_H = 70     # nearby card

LINE_ROW_H = 64     # a line serving the selected stop

NEAR_STOPS_LIMIT = 12   # stops listed on the home screen

TOP_INSET = 34      # room for the traffic-light buttons

PILL_H = 52

WALK_M_PER_MIN = 80.0

TABS = ['Arrivals', 'Route', 'Nearby']

OASA_API = "https://telematics.oasa.gr/api/"

# Bus ETA tuning: typical Athens bus pace incl. stops/lights is ~4-5 m/s.
ETA_DEFAULT_SPEED = 4.5   # m/s, used when there is no usable speed data

ETA_MIN_SPEED = 2.5       # m/s, so a bus idling at a light doesn't read as 20+ min

ETA_MAX_SPEED = 11.0      # m/s

# Location
LOC_TIMEOUT = 8.0           # s to wait for a fix once permission is granted
LOC_PROMPT_TIMEOUT = 30.0   # s to wait the first time, while the permission prompt is open
AUTH_NOT_DETERMINED = 0     # CLAuthorizationStatus values
AUTH_GRANTED = (3, 4)       # authorizedAlways / authorizedWhenInUse

# Timetable estimate for lines with no bus on the road yet (oasa/schedule.py)
SCHED_PACE_M_S = 3.2            # real average bus pace incl. stops/lights (measured on line 810)
SCHED_DEPARTED_SLACK_MIN = 3    # still count a departure this many minutes late as "about to leave"

# Home screen: stops follow the map
NEAR_MIN_ZOOM = 13.0     # below this the map shows too much area to list "nearby" stops
NEAR_REFETCH_KM = 0.4    # refetch only after the map centre moved at least this far
