"""Home screen (stops near you, any line) and stop screen (every line serving a stop).

The app has three modes:
    'home'  stops near you              -> tap a stop
    'stop'  lines serving that stop     -> tap a line
    'line'  the single-line view (Arrivals / Route / Nearby tabs), stop preselected
"""
import json, threading
from oasa.api import get_closest_stops, get_stop_lines
from oasa.config import WALK_M_PER_MIN
from oasa.debug import log
from oasa.eta import distance_km, fmt_dist

NO_LINE = 'Browse a line…'


class ExploreMixin:
    # ---- Navigation -------------------------------------------------------------
    def go_home(self):
        log('mode -> home')
        self.mode = 'home'
        self.leave_line()
        self.explore_stop = None
        self.show_near_stops(fit=True)
        self.rebuild_explore()
        self.do_layout()
        if self.user_loc is None and not self.loc_pending:
            self.start_location()

    def open_stop(self, sid):
        sid = str(sid)
        stop = self.near_stops.get(sid) or (self.explore_stop if self.explore_stop and self.explore_stop['id'] == sid else None)
        if stop is None:
            log(f'open_stop: unknown stop {sid}', 'WARN')
            return
        log(f'mode -> stop {stop["name"]} [{sid}]')
        self.mode = 'stop'
        self.leave_line()
        self.explore_stop = stop
        self.stop_lines = None
        self.show_near_stops(selected=sid)
        self.evaluate_js(f'window.focusStop({stop["lat"]},{stop["lon"]},16,{int(self.sheet_h)});')
        self.rebuild_explore()
        self.do_layout()
        self.fetch_stop_lines_async(sid)

    def open_line_at_stop(self, line_id):
        """Switch to the single-line view of `line_id`, with the current stop selected."""
        title = next((self.line_menu.itemTitleAtIndex_(i) for i in range(self.line_menu.numberOfItems())
                      if self.line_menu.itemTitleAtIndex_(i).startswith(f'{line_id} —')), None)
        if title is None:
            self.status.setStringValue_(f'No route data for line {line_id}')
            log(f'line {line_id} not in lines.json', 'WARN')
            return
        self.pending_stop = self.explore_stop['id'] if self.explore_stop else None
        self.line_menu.selectItemWithTitle_(title)
        self.lineChanged_(self.line_menu)

    def go_back(self):
        if self.mode == 'line' and self.explore_stop:
            self.open_stop(self.explore_stop['id'])
        else:
            self.go_home()

    def leave_line(self):
        """Drop the single-line state so the map only shows explore stops."""
        self.current_line = None
        self.line_data = None
        self.live = {}
        self.selected_stop_id = None
        self.pinned_id = None
        self.bus_markers = []
        self.push_buses([])
        self.push_route(None)
        self.evaluate_js('window.setPinned(null,0);')
        if self.line_menu.numberOfItems():
            self.line_menu.selectItemAtIndex_(0)

    # ---- Data -------------------------------------------------------------------
    def fetch_near_stops_async(self, lat, lon):
        def work():
            try:
                self.results.put(('near_stops', (lat, lon), get_closest_stops(lat, lon)))
            except Exception as e:
                self.results.put(('error', f'Nearby stops: {e}'))
        threading.Thread(target=work, daemon=True).start()

    def fetch_stop_lines_async(self, sid):
        def work():
            try:
                self.results.put(('stop_lines', sid, get_stop_lines(sid)))
            except Exception as e:
                self.results.put(('error', f'Lines at stop: {e}'))
        threading.Thread(target=work, daemon=True).start()

    def on_near_stops(self, origin, stops):
        lat, lon = origin
        self.near_stops = {}
        for s in stops:
            s['dist'] = distance_km(lat, lon, s['lat'], s['lon'])
            self.near_stops[s['id']] = s
        log(f'nearby stops: {len(stops)}')
        if self.mode == 'home':
            self.show_near_stops(fit=True)
            self.rebuild_explore()
            src = self.user_loc[2] if self.user_loc else 'map'
            self.status.setStringValue_('Stops near you' if src == 'gps' else 'Stops near the map centre')

    def on_stop_lines(self, sid, lines):
        if self.mode != 'stop' or not self.explore_stop or self.explore_stop['id'] != sid:
            return  # user moved on
        self.stop_lines = lines
        log(f'lines at stop {sid}: {len(lines)}')
        self.rebuild_explore()

    # ---- Views ------------------------------------------------------------------
    def show_near_stops(self, selected=None, fit=False):
        items = [{'id': s['id'], 'name': s['name'], 'lat': s['lat'], 'lon': s['lon']} for s in self.near_stops.values()]
        if self.explore_stop and self.explore_stop['id'] not in self.near_stops:
            items.append({k: self.explore_stop[k] for k in ('id', 'name', 'lat', 'lon')})
        self.evaluate_js('window.setStops(' + json.dumps(items) + ',' + json.dumps(selected) + ','
                         + json.dumps(bool(fit)) + ',' + str(int(self.sheet_h)) + ');')

    def rebuild_explore(self):
        if self.mode == 'home':
            stops = sorted(self.near_stops.values(), key=lambda s: s['dist'])
            if stops:
                rows = [{'kind': 'near', 'sid': s['id'], 'name': s['name'], 'closest': i == 0,
                         'dist_txt': fmt_dist(s['dist']),
                         'walk': f'~{max(1, round(s["dist"] * 1000 / WALK_M_PER_MIN))} min walk',
                         'bus_id': None, 'eta_s': None, 't0': 0,
                         'next_txt': (s['street'] + ' · ' if s['street'] else '') + f'Stop {s["id"]}'}
                        for i, s in enumerate(stops)]
            else:
                rows = [{'message': 'Finding stops near you…' if self.user_loc is None or self.loc_pending
                         else 'No stops found nearby.'}]
        else:
            if self.stop_lines is None:
                rows = [{'message': 'Loading lines at this stop…'}]
            elif not self.stop_lines:
                rows = [{'message': 'No lines found for this stop.'}]
            else:
                rows = []
                for ln in self.stop_lines:
                    etas, sched = ln['etas'], ln.get('sched')
                    row = {'kind': 'stopline', 'line': ln['line'], 'name': ln['name'], 'scheduled': False}
                    if etas:  # a bus is on the road: official live prediction
                        row['eta_txt'] = f'{etas[0]} min'
                        row['next_txt'] = ('Then ' + ', '.join(f'{m} min' for m in etas[1:3]) if len(etas) > 1
                                           else 'Live')
                    elif sched:  # not on the road yet: timetable + rough travel time
                        row['eta_txt'] = f'~{sched["eta_min"]} min'
                        row['next_txt'] = (f'Scheduled · leaves the terminus {sched["depart"]:%H:%M}, '
                                           f'here ~{sched["arrive"]:%H:%M}')
                        row['scheduled'] = True
                    else:
                        row['eta_txt'] = '—'
                        row['next_txt'] = 'No more buses today'
                    rows.append(row)
        self.explore_source.rows = rows
        self.explore_table.reloadData()

    def explore_heading_text(self):
        if self.mode == 'home':
            return 'STOPS NEAR YOU'
        s = self.explore_stop or {}
        return f'{s.get("name", "")} · STOP {s.get("id", "")}'.upper()
