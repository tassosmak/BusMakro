"""Home screen (favourites + stops near you), stop screen (every line at a stop) and search.

The app has four modes:
    'home'    favourite stops, then stops near you   -> tap a stop
    'stop'    lines serving that stop                -> tap a line
    'line'    the single-line view (Arrivals / Route / Nearby tabs), stop preselected
    'search'  results for the search field in the top bar (lines and stops); clearing it
              returns to the previous mode, whose state is kept
"""
import json, threading, time
from concurrent.futures import ThreadPoolExecutor
from oasa import alerts, favorites, stop_index
from oasa.api import error_kind, get_closest_stops, get_stop_buses, get_stop_lines
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
        self.show_home_stops(fit=True)
        self.rebuild_explore()
        self.do_layout()
        if self.home_tab == 1:
            self.fetch_favs_async()
        if self.user_loc is None and not self.loc_pending:
            self.start_location()

    def open_stop(self, sid, stop=None):
        """Show every line at stop `sid` (a nearby stop, or any stop passed in: favourite, search result)."""
        sid = str(sid)
        stop = stop or self.near_stops.get(sid) or (self.explore_stop if self.explore_stop and self.explore_stop['id'] == sid else None)
        if stop is None:
            log(f'open_stop: unknown stop {sid}', 'WARN')
            return
        log(f'mode -> stop {stop["name"]} [{sid}]')
        self.close_search()
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
        install_menu('BusMakro', self)
        self.back_button.setTitle_(t('back'))
        self.locate_button.setTitle_(t('locate_me'))
        self.search.setPlaceholderString_(t('search_stop'))
        self.find.setPlaceholderString_(t('search_bar'))
        self.update_focus_button()
        self.map_locate_btn.setToolTip_(t('m_locate'))
        self.fs_search_btn.setToolTip_(t('search_bar'))
        self.fs_refresh_btn.setToolTip_(t('m_refresh'))
        self.home_tabs.setLabel_forSegment_(t('tab_home_nearby'), 0)
        self.home_tabs.setLabel_forSegment_(t('tab_favourites'), 1)
        if self.update_info:
            self.update_button.setTitle_(t('update_available', v=self.update_info[0]))
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
        if self.mode != 'line':
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
                self.results.put(('net_error', 'nearby', error_kind(e), str(e)))
        threading.Thread(target=work, daemon=True).start()

    def fetch_stop_lines_async(self, sid):
        def work():
            try:
                lines = get_stop_lines(sid)
                self.results.put(('stop_lines', sid, lines, get_stop_buses(lines)))
            except Exception as e:
                self.results.put(('net_error', 'stop_lines', error_kind(e), str(e)))
        threading.Thread(target=work, daemon=True).start()

    def on_map_moved(self, lat, lon, zoom):
        """Home screen: list the stops where the map is looking, once it has settled."""
        if self.mode != 'home' or self.home_tab != 0 or zoom < NEAR_MIN_ZOOM:
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
        if self.mode == 'home' and self.home_tab == 0:
            self.show_near_stops(fit=not from_map)  # never move the map the user just moved
            self.rebuild_explore()
            self.status.setStringValue_(t('stops_in_area') if from_map
                                        else t('stops_near_you') if me else t('stops_near_centre'))
            self.do_layout()

    def on_stop_lines(self, sid, lines, buses):
        if self.mode != 'stop' or not self.explore_stop or self.explore_stop['id'] != sid:
            return  # user moved on
        self.stop_lines = lines
        self.stop_bus_line = {b['id']: b['line'] for b in buses}  # bus id -> its line (click opens it)
        log(f'lines at stop {sid}: {len(lines)}, {len(buses)} approaching buses on the map')
        self.rebuild_explore()
        self.push_buses(buses)  # the buses on their way here, labelled with their line

    # ---- Favourites -------------------------------------------------------------
    def fetch_favs_async(self):
        """Next live arrivals for every favourite stop (no timetable lookups: kept light)."""
        favs = favorites.load()
        if not favs:
            return

        def one(f):
            try:
                self.results.put(('fav_lines', f['id'], get_stop_lines(f['id'], with_schedule=False)))
            except Exception as e:
                log(f'favourite {f["id"]}: {e}', 'WARN')

        def work():
            with ThreadPoolExecutor(max_workers=4) as pool:
                list(pool.map(one, favs))
        threading.Thread(target=work, daemon=True).start()

    def on_fav_lines(self, sid, lines):
        self.fav_lines[sid] = lines
        if self.mode == 'home' and self.home_tab == 1:
            self.rebuild_explore()

    def set_home_tab(self, i):
        """Home screen tabs: 0 = stops nearby (follows the map), 1 = favourite stops."""
        self.home_tab = i
        self.home_tabs.setSelectedSegment_(i)
        log(f'home tab -> {"favourites" if i else "nearby"}')
        self.show_home_stops(fit=True)
        self.rebuild_explore()
        self.do_layout()
        if i == 1:
            self.fetch_favs_async()
        self.status.setStringValue_(t('tab_favourites') if i else
                                    t('stops_in_area') if self.near_from_map else t('stops_near_you'))

    def toggle_favorite(self):
        if not self.explore_stop:
            return
        now_fav = favorites.toggle(self.explore_stop)
        log(f'favourite {self.explore_stop["id"]} -> {now_fav}')
        if now_fav:
            self.fav_lines[self.explore_stop['id']] = self.stop_lines  # already known: no refetch needed
        self.update_tab_ui()

    def fav_rows(self):
        rows = []
        for f in favorites.load():
            lines = self.fav_lines.get(f['id'])
            if lines is None:
                nxt = t('fav_loading')
            else:
                live = sorted((ln for ln in lines if ln['etas']), key=lambda ln: ln['etas'][0])[:3]
                nxt = ('   '.join(f'{line_label(ln["line"])} {t("min", n=ln["etas"][0])}' for ln in live)
                       if live else t('fav_none_live'))
            rows.append({'kind': 'fav', 'sid': f['id'], 'stop': f,
                         'name': name(f.get('name'), f.get('name_en')) or t('unnamed_stop'), 'next_txt': nxt})
        return rows

    # ---- Search (the field in the top bar) -----------------------------------------
    def on_search_text(self, text):
        text = text.strip()
        if not text:
            if self.mode == 'search':
                self.end_search()
            return
        if self.mode != 'search':
            self.search_return = self.mode
            self.mode = 'search'
            log(f'mode -> search (from {self.search_return})')
        self.search_query = text
        self.rebuild_explore()
        self.do_layout()

    def end_search(self):
        """Search field cleared: back to where we were (its state was never touched)."""
        back, self.search_return = self.search_return or 'home', None
        log(f'search closed -> {back}')
        self.mode = back
        if back != 'line':
            self.rebuild_explore()
        self.do_layout()

    def close_search(self):
        """Leaving search for a result: clear the field without restoring the old mode."""
        self.find.setStringValue_('')
        self.search_return = None

    def search_rows(self):
        q = self.search_query
        qn = stop_index.normalize(q)
        lines = [ln for ln in self.lines
                 if stop_index.normalize(ln['id']).startswith(qn)
                 or qn in stop_index.normalize(name(ln.get('name'), ln.get('name_en')))][:8]
        rows = []
        if lines:
            rows.append({'kind': 'header', 'text': t('h_search_lines')})
            rows += [{'kind': 'stopline', 'line': ln['id'], 'name': name(ln.get('name'), ln.get('name_en')),
                      'eta_txt': '', 'next_txt': '', 'scheduled': False, 'search': True} for ln in lines]
        if self.stop_idx is None:
            rows.append({'message': t('index_loading')} if not self.net_error or self.net_error['what'] != 'index'
                        else self.retry_row())
        else:
            stops = stop_index.search(self.stop_idx, q)
            if stops:
                rows.append({'kind': 'header', 'text': t('h_search_stops')})
            me = self.user_loc if self.user_loc and self.user_loc[2] == 'gps' else None
            for sid, s in stops:
                d = distance_km(me[0], me[1], s['lat'], s['lon']) if me else None
                rows.append({'kind': 'near', 'sid': sid, 'search': True, 'closest': False,
                             'stop': {'id': sid, 'name': s['name'], 'lat': s['lat'], 'lon': s['lon']},
                             'name': name(s['name']) or t('unnamed_stop'),
                             'dist_txt': fmt_dist(d) if d is not None else '',
                             'walk': t('walk', n=max(1, round(d * 1000 / WALK_M_PER_MIN))) if d is not None else '',
                             'bus_id': None, 'eta_s': None, 't0': 0,
                             'next_txt': t('lines_list', list=', '.join(line_label(x) for x in s['lines'][:8]))})
        return rows or [{'message': t('no_results', q=q)}]

    def build_index_async(self):
        ids = [ln['id'] for ln in self.lines]

        def work():
            try:
                self.results.put(('stop_index', stop_index.build(ids)))
            except Exception as e:
                self.results.put(('net_error', 'index', error_kind(e), str(e)))
        threading.Thread(target=work, daemon=True).start()

    # ---- Service alerts (oasa.gr announcements) ------------------------------------
    def fetch_alerts_async(self):
        ids = [ln['id'] for ln in self.lines]
        self.alerts_at = time.time()

        def work():
            self.results.put(('alerts', alerts.fetch(ids)))  # never raises: a failed feed is just skipped
        threading.Thread(target=work, daemon=True).start()

    def on_alerts(self, found):
        self.alerts = found
        if self.mode in ('stop', 'home', 'search'):
            self.rebuild_explore()
        elif self.mode == 'line':
            self.render_arrivals(self.live)

    def alert_rows(self, line_ids):
        rows = []
        for a in alerts.for_lines(self.alerts, list(line_ids)):
            ls = sorted(a['lines'])
            lines_txt = t('alert_line' if len(ls) == 1 else 'alert_lines', list=', '.join(line_label(x) for x in ls[:6]))
            rows.append({'kind': 'alert', 'title': a['title'], 'link': a['link'],
                         'meta': t('alert_meta', date=f'{a["date"]:%d/%m}', lines=lines_txt)})
        return rows

    # ---- Network errors ------------------------------------------------------------
    def on_net_error(self, what, kind, detail):
        """Remember what failed (retried on click, ⌘R and every refresh) and say so in the UI."""
        log(f'network error ({what}, {kind}): {detail}', 'WARN')
        self.failed[what] = kind
        self.net_error = {'what': what, 'kind': kind}  # the latest one, for the message
        msg = t('err_' + kind)
        if what == 'live' and self.last_live_ok:
            self.status.setStringValue_(t('stale_data', msg=msg, time=f'{self.last_live_ok:%H:%M}'))
        else:
            self.status.setStringValue_(msg)
        if what == 'line' and self.mode == 'line':
            self.table_source.rows = [{'message': t('tap_retry', msg=msg)}]
            self.table.reloadData()
        if self.mode != 'line':
            self.rebuild_explore()

    def retry_row(self):
        return {'message': t('tap_retry', msg=t('err_' + self.net_error['kind'])), 'retry': True}

    def retry_failed(self):
        """Retry every request that failed (each one reports again if it fails again)."""
        failed, self.failed, self.net_error = self.failed, {}, None
        for what in failed:
            self.retry_one(what)
        if self.mode != 'line':
            self.rebuild_explore()

    def succeeded(self, what):
        """A request worked: forget its failure; clear the error once nothing is failing."""
        if self.failed.pop(what, None) is not None:
            log(f'back online ({what})')
        if not self.failed:
            self.net_error = None
        elif self.net_error and self.net_error['what'] == what:
            w = next(iter(self.failed))
            self.net_error = {'what': w, 'kind': self.failed[w]}

    def retry_one(self, what):
        log(f'retrying {what}')
        if what == 'nearby':
            if self.near_origin:
                self.fetch_near_stops_async(*self.near_origin, from_map=self.near_from_map)
            else:
                self.start_location()
        elif what == 'stop_lines' and self.explore_stop:
            self.fetch_stop_lines_async(self.explore_stop['id'])
        elif what == 'lines':
            threading.Thread(target=self.fetch_lines, daemon=True).start()
        elif what == 'line' and self.current_line:
            threading.Thread(target=self.fetch_line, args=(self.current_line,), daemon=True).start()
        elif what == 'live' and self.current_line:
            threading.Thread(target=self.fetch_live, args=(self.current_line,), daemon=True).start()
        elif what == 'index' and self.lines:
            self.build_index_async()

    # ---- Views ------------------------------------------------------------------
    def show_home_stops(self, fit=False):
        """Home map: the nearby stops, or the favourite stops on the Favourites tab."""
        if self.home_tab == 1:
            items = [{'id': f['id'], 'name': name(f.get('name'), f.get('name_en')), 'lat': f['lat'], 'lon': f['lon']}
                     for f in favorites.load()]
            self.evaluate_js('window.setStops(' + json.dumps(items) + ',null,' + json.dumps(bool(fit and items))
                             + ',' + str(int(self.sheet_h)) + ');')
        else:
            self.show_near_stops(fit=fit)

    def show_near_stops(self, selected=None, fit=False):
        shown = list(self.near_stops.values())
        if self.explore_stop and self.explore_stop['id'] not in self.near_stops:
            shown.append(self.explore_stop)
        items = [{'id': s['id'], 'name': name(s['name'], s.get('name_en')), 'lat': s['lat'], 'lon': s['lon']} for s in shown]
        self.evaluate_js('window.setStops(' + json.dumps(items) + ',' + json.dumps(selected) + ','
                         + json.dumps(bool(fit)) + ',' + str(int(self.sheet_h)) + ');')

    def rebuild_explore(self):
        err = self.net_error['what'] if self.net_error else None
        if self.mode == 'search':
            rows = self.search_rows()
        elif self.mode == 'home' and self.home_tab == 1:
            rows = self.fav_rows() or [{'message': t('no_favourites')}]
        elif self.mode == 'home':
            stops = sorted(self.near_stops.values(), key=lambda s: s['rank'])
            if err == 'nearby' and not stops:
                rows = [self.retry_row()]
            elif stops:
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
            if err == 'stop_lines' and self.stop_lines is None:
                rows = [self.retry_row()]
            elif self.stop_lines is None:
                rows = [{'message': t('loading_lines_at_stop')}]
            elif not self.stop_lines:
                rows = [{'message': t('no_lines_at_stop')}]
            else:
                rows = self.alert_rows(ln['line'] for ln in self.stop_lines)
                hit = {l for a in alerts.for_lines(self.alerts, [ln['line'] for ln in self.stop_lines]) for l in a['lines']}
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
                    if ln['line'] in hit:  # this line has a current OASA alert
                        row['next_txt'] = '⚠︎ ' + row['next_txt']
                    rows.append(row)
        self.explore_source.rows = rows
        self.explore_table.reloadData()

    def explore_heading_text(self):
        if self.mode == 'search':
            return ''
        if self.mode == 'home':
            if self.home_tab == 1:
                return t('h_favourites')
            return t('h_stops_in_area') if self.near_from_map else t('h_stops_near_you')
        s = self.explore_stop or {}
        return t('h_stop', name=name(s.get('name', ''), s.get('name_en')), id=s.get('id', '')).upper()
