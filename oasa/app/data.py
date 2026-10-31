"""Fetching line/live data and turning it into arrival rows."""
import json, threading, time
from urllib.parse import quote
from AppKit import NSColor
from oasa.api import attach_oasa, error_kind, get_json, official_eta_s
from oasa.config import API_BASE, REFRESH_SECONDS, STATIC_BASE
from oasa.debug import log
from oasa.eta import eta_seconds, route_distance_m
from oasa.i18n import name, t


class DataMixin:
    def push_stops(self, fit=False):
        self.evaluate_js('window.setStops(' + json.dumps(self.stop_payload()) + ','
                         + json.dumps(self.selected_stop_id) + ',' + json.dumps(bool(fit)) + ','
                         + str(int(self.sheet_h)) + ');')

    def push_route(self, vid):
        """Draw variant `vid`'s road shape on the map (None clears it). Only sent when it changes."""
        if vid == self.drawn_variant:
            return
        self.drawn_variant = vid
        shape = ((self.line_data or {}).get('variants', {}).get(vid) or {}).get('shape') if vid else None
        log(f'route line -> {vid} ({len(shape or [])} points)')
        self.evaluate_js('window.setRoute(' + json.dumps(shape or []) + ');')

    def push_buses(self, buses):
        self.evaluate_js('window.setBuses(' + json.dumps(buses) + ');')

    # ---- Network (background threads; results go through the queue) -----------
    def fetch_lines(self):
        try:
            self.results.put(('lines', get_json(STATIC_BASE + '/lines.json')))
        except Exception as e:
            self.results.put(('net_error', 'lines', error_kind(e), str(e)))

    def fetch_line(self, line_id):
        try:
            enc = quote(line_id, safe='')
            static = get_json(f'{STATIC_BASE}/lines/{enc}.json')
            live = get_json(f'{API_BASE}/v1/lines/{enc}')
            self.results.put(('line', line_id, static, attach_oasa(live, self.selected_stop_id)))
        except Exception as e:
            self.results.put(('net_error', 'line', error_kind(e), str(e)))

    def fetch_live(self, line_id):
        try:
            live = get_json(f'{API_BASE}/v1/lines/{quote(line_id, safe="")}')
            self.results.put(('live', line_id, attach_oasa(live, self.selected_stop_id)))
        except Exception as e:
            self.results.put(('net_error', 'live', error_kind(e), str(e)))

    def stop_payload(self):
        if not self.line_data:
            return []
        return [{'id': str(sid), 'name': name(s.get('name')) or t('unnamed_stop'), 'lat': s.get('lat'), 'lon': s.get('lon')}
                for sid, s in self.line_data.get('stops', {}).items()]

    # ---- Data -> rows -----------------------------------------------------------
    def approaching_for(self, sid):
        """Vehicles that will still reach stop `sid`, nearest first (list of arrival-row dicts)."""
        rows = []
        if not (sid and self.line_data):
            return rows
        stop = self.line_data.get('stops', {}).get(sid, {})
        if stop.get('lat') is None or stop.get('lon') is None:
            return rows
        variants = self.line_data.get('variants', {})
        now = time.time()
        for v in (self.live or {}).get('vehicles', []):
            route = variants.get(v.get('variant'), {}).get('stops', [])
            nxt = v.get('next_stop_id')
            if sid not in route or nxt not in route or route.index(sid) < route.index(nxt):
                continue  # stop not on this variant, or bus already passed it
            if v.get('lat') is None or v.get('lon') is None:
                continue
            dist_m = route_distance_m(v, route, sid, self.line_data.get('stops', {}))
            if dist_m is None:
                continue
            dist = dist_m / 1000
            bid = str(v.get('id', '?'))
            eta_s = official_eta_s(self.live, bid, sid, now)
            est = eta_s is None
            if est:  # no official prediction: fall back to our own estimate
                eta_s, _ = eta_seconds(v, dist_m, now)
            delay = v.get('delay_s')
            if delay is None:
                delay_txt, delay_col = t('no_delay_data'), NSColor.secondaryLabelColor()
            elif abs(delay) < 60:
                delay_txt, delay_col = t('on_time'), NSColor.systemGreenColor()
            else:
                delay_txt = t('min', n=f'{delay / 60:+.0f}')
                delay_col = NSColor.systemOrangeColor() if delay > 0 else NSColor.systemBlueColor()
            n_stops = route.index(sid) - route.index(nxt)
            rows.append({'kind': 'arrival', 'id': bid, 'distance': dist, 'eta_s': eta_s, 't0': now, 'estimated': est,
                         'watching': self.watches.get(bid, {}).get('stops'),
                         'delay': delay_txt, 'delay_color': delay_col,
                         'sub': (t('stops_away_1') if n_stops == 1 else t('stops_away', n=n_stops)) if n_stops
                                else t('next_stop_here'),
                         'title': t('bus_n', id=bid), 'trip': name(v.get('trip_label')) or t('trip_unavailable'),
                         'pinned': bid == self.pinned_id})
        rows.sort(key=lambda x: x['distance'])
        return rows

    def render_arrivals(self, live):
        self.live = live or {}
        vehicles = self.live.get('vehicles', [])
        ids = {str(v.get('id')) for v in vehicles}
        if self.pinned_id and self.pinned_id not in ids:
            self.pinned_id = None
            self.evaluate_js('window.setPinned(null,0);')
        rows = self.approaching_for(self.selected_stop_id)
        buses = []
        for v in vehicles:
            if v.get('lat') is None or v.get('lon') is None:
                continue
            h = v.get('heading', v.get('bearing'))
            buses.append({'id': v.get('id'), 'lat': v['lat'], 'lon': v['lon'],
                          'heading': h if isinstance(h, (int, float)) else None,
                          # for moving the marker along its road between fixes (see map.html)
                          'position_at': v.get('position_at'), 'speed': v.get('speed'),
                          'path': v.get('path'), 'path_beyond': v.get('path_beyond'),
                          'path_speeds': v.get('path_speeds')})
        log(f'arrivals: {len(vehicles)} vehicles on line, {len(rows)} approaching stop {self.selected_stop_id}')
        self.table_source.rows = self.alert_rows([self.current_line] if self.current_line else []) + (
            rows or [{'message': t('choose_stop') if not self.selected_stop_id else t('no_approaching')}])
        self.table.reloadData()
        self.bus_markers = buses
        self.push_buses(buses)
        self.rebuild_route()
        self.rebuild_nearby()

    # ---- Polling --------------------------------------------------------------
    def schedule_poll(self):
        # results arrive through MainQueue (no polling); the 1 s tick runs only when needed (update_timers)
        threading.Thread(target=self.auto_refresh_loop, daemon=True).start()

    def auto_refresh_loop(self):
        while True:
            time.sleep(REFRESH_SECONDS)
            self.results.put(('refresh_request',))  # handled on the main thread
