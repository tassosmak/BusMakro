"""Tabs: Route (stops along the line) and Nearby (closest stops)."""
import time
from oasa.config import TABS, WALK_M_PER_MIN
from oasa.debug import log
from oasa.eta import distance_km, fmt_dist, fmt_eta
from oasa import i18n


class TabsMixin:
    def update_tab_ui(self):
        line = self.mode == 'line'
        self.back_button.setHidden_(self.mode == 'home')
        self.explore_heading.setHidden_(line); self.explore_scroll.setHidden_(line)
        self.explore_heading.setStringValue_(self.explore_heading_text())
        self.tabs.setHidden_(not line)
        if not line:
            for v in (self.search, self.stop_menu, self.arr_scroll, self.route_scroll, self.near_scroll,
                      self.variant_menu, self.arrival_heading):
                v.setHidden_(True)
            self.locate_button.setHidden_(self.mode != 'home')
            return
        t = self.tab
        multi = t == 1 and len(self.variant_keys) > 1
        self.search.setHidden_(t != 0); self.stop_menu.setHidden_(t != 0)
        self.arr_scroll.setHidden_(t != 0); self.route_scroll.setHidden_(t != 1); self.near_scroll.setHidden_(t != 2)
        self.locate_button.setHidden_(t != 2)
        self.variant_menu.setHidden_(not multi)
        self.arrival_heading.setHidden_(multi)
        self.arrival_heading.setStringValue_(
            [i18n.t('h_approaching'), i18n.t('h_along_line', line=i18n.line_label(self.current_line or '')),
             i18n.t('h_nearest_on_line')][t])

    def set_tab(self, i):
        self.tab = i
        self.tabs.setSelectedSegment_(i)
        log(f'tab -> {TABS[i]}')
        if i == 1:
            self.rebuild_route()
        elif i == 2:
            self.rebuild_nearby()
            if self.user_loc is None and not self.loc_tried:
                self.loc_tried = True
                self.start_location()
        self.do_layout()
        if i == 1:
            self.scroll_route_to_selected()

    # ---- Route tab: ordered stops with buses in between --------------------------
    def pick_route_variant(self):
        variants = self.line_data.get('variants', {})
        if self.route_variant_user and self.route_variant in variants:
            return self.route_variant
        counts = {}
        for v in (self.live or {}).get('vehicles', []):
            counts[v.get('variant')] = counts.get(v.get('variant'), 0) + 1
        sel = self.selected_stop_id
        cands = [k for k, var in variants.items()
                 if sel is None or sel in [str(x) for x in var.get('stops', [])]] or list(variants.keys())
        best = max(cands, key=lambda k: counts.get(k, 0))
        self.route_variant = best
        return best

    def rebuild_route(self):
        ld = self.line_data
        if not ld or not ld.get('variants'):
            self.variant_keys = []
            self.push_route(None)
            self.route_source.rows = [{'message': i18n.t('no_route_data')}]
            self.route_table.reloadData()
            return
        variants, stops = ld['variants'], ld.get('stops', {})
        vid = self.pick_route_variant()
        self.push_route(vid)
        self.variant_keys = list(variants.keys())
        self.variant_menu.removeAllItems()
        for i, k in enumerate(self.variant_keys):
            st = [str(x) for x in variants[k].get('stops', [])]
            last = i18n.name(stops.get(st[-1], {}).get('name', '?')) if st else '?'
            self.variant_menu.addItemWithTitle_(f'{i + 1}. {k} → {last}')
        self.variant_menu.selectItemAtIndex_(self.variant_keys.index(vid))

        route = [str(x) for x in variants[vid].get('stops', [])]
        by_next = {}
        for v in (self.live or {}).get('vehicles', []):
            if v.get('variant') != vid or v.get('lat') is None or v.get('lon') is None:
                continue
            nxt = str(v.get('next_stop_id'))
            if nxt not in route:
                continue
            s = stops.get(nxt, {})
            d = distance_km(v['lat'], v['lon'], s['lat'], s['lon']) if s.get('lat') is not None and s.get('lon') is not None else 0.0
            by_next.setdefault(nxt, []).append((d, v))
        rows = []
        for i, sid in enumerate(route):
            for d, v in sorted(by_next.get(sid, []), key=lambda t: -t[0]):
                rows.append({'kind': 'bus', 'id': str(v.get('id', '?')),
                             'text': i18n.t('bus_to_next', id=v.get('id', '?'), dist=fmt_dist(d))})
            rows.append({'kind': 'stop', 'sid': sid, 'name': i18n.name(stops.get(sid, {}).get('name')) or i18n.t('unnamed_stop'),
                         'selected': sid == self.selected_stop_id, 'first': i == 0, 'last': i == len(route) - 1})
        self.route_source.rows = rows or [{'message': i18n.t('no_stops_route')}]
        self.route_table.reloadData()
        if self.tab == 1:
            self.update_tab_ui()

    def scroll_route_to_selected(self):
        rows = self.route_source.rows
        idx = next((i for i, r in enumerate(rows) if r.get('kind') == 'stop' and r.get('selected')), None)
        if idx is not None:
            self.route_table.scrollRowToVisible_(max(0, idx - 2))
            self.route_table.scrollRowToVisible_(min(len(rows) - 1, idx + 2))

    # ---- Nearby tab: nearest stops via CoreLocation (fallback: map centre) --------
    def rebuild_nearby(self):
        if not self.line_data:
            self.near_source.rows = [{'message': i18n.t('loading_line_short')}]
        elif self.user_loc is None:
            self.near_source.rows = [{'message': i18n.t('tap_locate')}]
        else:
            lat, lon, src = self.user_loc
            cand = []
            for sid, s in self.line_data.get('stops', {}).items():
                if s.get('lat') is None or s.get('lon') is None:
                    continue
                cand.append((distance_km(lat, lon, s['lat'], s['lon']), str(sid), s))
            cand.sort(key=lambda t: t[0])
            rows = []
            now = time.time()
            for i, (d, sid, s) in enumerate(cand[:6]):
                ap = self.approaching_for(sid)
                soon = min(ap, key=lambda r: r['eta_s']) if ap else None
                rows.append({'kind': 'near', 'sid': sid, 'name': i18n.name(s.get('name')) or i18n.t('unnamed_stop'),
                             'dist_txt': fmt_dist(d), 'closest': i == 0,
                             'walk': i18n.t('walk', n=max(1, round(d * 1000 / WALK_M_PER_MIN))),
                             'bus_id': soon['id'] if soon else None,
                             'eta_s': soon['eta_s'] if soon else None, 't0': now,
                             'next_txt': (i18n.t('bus_eta', id=soon['id'], eta=fmt_eta(soon['eta_s'])) if soon
                                          else i18n.t('no_approaching_bus'))})
            self.near_source.rows = rows or [{'message': i18n.t('no_stop_coords')}]
        self.near_table.reloadData()
