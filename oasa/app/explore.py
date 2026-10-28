"""Home screen (stops near you, any line) and stop screen (every line serving a stop).

The app has three modes:
    'home'  stops near you              -> tap a stop
    'stop'  lines serving that stop     -> tap a line
    'line'  the single-line view (Arrivals / Route / Nearby tabs), stop preselected
"""
import json, threading
from oasa.api import get_closest_stops, get_stop_lines
from oasa.config import NEAR_MIN_ZOOM, NEAR_REFETCH_KM, TABS, WALK_M_PER_MIN
from oasa.debug import log
from oasa.eta import distance_km, fmt_dist
from oasa.i18n import line_label, name, t
from oasa.ui.menu import install_menu



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
        idx = next((i for i, ln in enumerate(self.lines) if ln['id'] == line_id), None)
        if idx is None:
            self.status.setStringValue_(t('no_route_for_line', line=line_label(line_id)))
            log(f'line {line_id} not in lines.json', 'WARN')
            return
        self.pending_stop = self.explore_stop['id'] if self.explore_stop else None
        self.line_menu.selectItemAtIndex_(idx + 1)  # item 0 is the 'browse a line' placeholder
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

    # ---- Language -----------------------------------------------------------------
    def stop_title(self, sid, stop):
        """Stop-menu title; the same function builds and looks up titles."""
        return f'{name(stop.get("name")) or t("unnamed_stop")} [{sid}]'

    def fill_line_menu(self):
        """(Re)build the line dropdown in the current language, keeping the selection."""
        keep = self.line_menu.indexOfSelectedItem() if self.line_menu.numberOfItems() else 0
        self.line_menu.removeAllItems()
        self.line_menu.addItemWithTitle_(t('browse_line'))
        for line in self.lines:
            self.line_menu.addItemWithTitle_(f'{line_label(line["id"])} — {name(line.get("name"), line.get("name_en"))}')
        self.line_menu.selectItemAtIndex_(keep if self.mode == 'line' and 0 <= keep < self.line_menu.numberOfItems() else 0)

    def apply_language(self):
        """Relabel everything after a language switch."""
        install_menu('Makro OASA', self)
        self.back_button.setTitle_(t('back'))
        self.locate_button.setTitle_(t('locate_me'))
        self.search.setPlaceholderString_(t('search_stop'))
        for i, key in enumerate(TABS):
            self.tabs.setLabel_forSegment_(t(key), i)
        self.fill_line_menu()
        if self.mode == 'line' and self.line_data:
            self.searchChanged_(self.search)
            if self.selected_stop_id:
                title = self.stop_title(self.selected_stop_id, self.line_data.get('stops', {}).get(self.selected_stop_id, {}))
                if title in self.stop_options:
                    self.stop_menu.selectItemWithTitle_(title)
            self.push_stops()
            self.render_arrivals(self.live)
        else:
            self.show_near_stops(selected=self.explore_stop['id'] if self.mode == 'stop' and self.explore_stop else None)
            self.rebuild_explore()
        if self.mode == 'home':
            self.status.setStringValue_(t('stops_in_area') if self.near_from_map else t('stops_near_you'))
        self.do_layout()

    # ---- Data -------------------------------------------------------------------
    def fetch_near_stops_async(self, lat, lon, from_map=False):
        """Stops around (lat, lon): your location, or the map centre after you pan (`from_map`)."""
        self.near_origin = (lat, lon)

        def work():
            try:
                self.results.put(('near_stops', (lat, lon), from_map, get_closest_stops(lat, lon)))
            except Exception as e:
                self.results.put(('error', t('err_nearby', msg=e)))
        threading.Thread(target=work, daemon=True).start()

    def fetch_stop_lines_async(self, sid):
        def work():
            try:
                self.results.put(('stop_lines', sid, get_stop_lines(sid)))
            except Exception as e:
                self.results.put(('error', t('err_lines_at_stop', msg=e)))
        threading.Thread(target=work, daemon=True).start()

    def on_map_moved(self, lat, lon, zoom):
        """Home screen: list the stops where the map is looking, once it has settled."""
        if self.mode != 'home' or zoom < NEAR_MIN_ZOOM:
            return
        o = self.near_origin
        if o and distance_km(o[0], o[1], lat, lon) < NEAR_REFETCH_KM:
            return  # barely moved (or our own fit around the stops)
        log(f'map moved (zoom {zoom:.1f}) -> stops in this area')
        self.fetch_near_stops_async(lat, lon, from_map=True)

    def on_near_stops(self, origin, from_map, stops):
        if origin != self.near_origin:
            return  # a newer request is on its way
        lat, lon = origin
        me = self.user_loc if self.user_loc and self.user_loc[2] == 'gps' else None
        self.near_stops = {}
        for s in stops:
            s['rank'] = distance_km(lat, lon, s['lat'], s['lon'])  # list order: closest to the map centre / you
            s['dist'] = distance_km(me[0], me[1], s['lat'], s['lon']) if me else s['rank']  # shown: from you
            self.near_stops[s['id']] = s
        self.near_from_map = from_map
        log(f'nearby stops: {len(stops)}{" (map area)" if from_map else ""}')
        if self.mode == 'home':
            self.show_near_stops(fit=not from_map)  # never move the map the user just moved
            self.rebuild_explore()
            self.status.setStringValue_(t('stops_in_area') if from_map
                                        else t('stops_near_you') if me else t('stops_near_centre'))
            self.do_layout()

    def on_stop_lines(self, sid, lines):
        if self.mode != 'stop' or not self.explore_stop or self.explore_stop['id'] != sid:
            return  # user moved on
        self.stop_lines = lines
        log(f'lines at stop {sid}: {len(lines)}')
        self.rebuild_explore()

    # ---- Views ------------------------------------------------------------------
    def show_near_stops(self, selected=None, fit=False):
        shown = list(self.near_stops.values())
        if self.explore_stop and self.explore_stop['id'] not in self.near_stops:
            shown.append(self.explore_stop)
        items = [{'id': s['id'], 'name': name(s['name'], s.get('name_en')), 'lat': s['lat'], 'lon': s['lon']} for s in shown]
        self.evaluate_js('window.setStops(' + json.dumps(items) + ',' + json.dumps(selected) + ','
                         + json.dumps(bool(fit)) + ',' + str(int(self.sheet_h)) + ');')

    def rebuild_explore(self):
        if self.mode == 'home':
            stops = sorted(self.near_stops.values(), key=lambda s: s['rank'])
            if stops:
                rows = [{'kind': 'near', 'sid': s['id'], 'name': name(s['name'], s.get('name_en')) or t('unnamed_stop'),
                         'closest': i == 0 and not self.near_from_map,
                         'dist_txt': fmt_dist(s['dist']),
                         'walk': t('walk', n=max(1, round(s['dist'] * 1000 / WALK_M_PER_MIN))),
                         'bus_id': None, 'eta_s': None, 't0': 0,
                         'next_txt': (name(s['street'], s.get('street_en')) + ' · ' if s['street'] else '')
                                     + t('stop_n', id=s['id'])}
                        for i, s in enumerate(stops)]
            else:
                rows = [{'message': t('finding_stops') if self.user_loc is None or self.loc_pending
                         else t('no_stops_nearby')}]
        else:
            if self.stop_lines is None:
                rows = [{'message': t('loading_lines_at_stop')}]
            elif not self.stop_lines:
                rows = [{'message': t('no_lines_at_stop')}]
            else:
                rows = []
                for ln in self.stop_lines:
                    etas, sched = ln['etas'], ln.get('sched')
                    row = {'kind': 'stopline', 'line': ln['line'], 'name': name(ln['name'], ln.get('name_en')), 'scheduled': False}
                    if etas:  # a bus is on the road: official live prediction
                        row['eta_txt'] = t('min', n=etas[0])
                        row['next_txt'] = (t('then', list=', '.join(t('min', n=m) for m in etas[1:3])) if len(etas) > 1
                                           else t('live'))
                    elif sched:  # not on the road yet: timetable + rough travel time
                        row['eta_txt'] = t('approx_min', n=sched['eta_min'])
                        row['next_txt'] = t('scheduled', depart=f'{sched["depart"]:%H:%M}', arrive=f'{sched["arrive"]:%H:%M}')
                        row['scheduled'] = True
                    else:
                        row['eta_txt'] = '—'
                        row['next_txt'] = t('no_more_today')
                    rows.append(row)
        self.explore_source.rows = rows
        self.explore_table.reloadData()

    def explore_heading_text(self):
        if self.mode == 'home':
            return t('h_stops_in_area') if self.near_from_map else t('h_stops_near_you')
        s = self.explore_stop or {}
        return t('h_stop', name=name(s.get('name', ''), s.get('name_en')), id=s.get('id', '')).upper()
