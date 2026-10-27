"""The app delegate: window setup, layout and every Objective-C callable method.

Methods called from Objective-C (actions, delegates, timers) must live on this
NSObject class itself; PyObjC does not register them from mixins."""
import json, os, queue, sys, threading, time
from datetime import datetime
from AppKit import (
    NSApplication, NSWindow, NSWindowStyleMaskTitled, NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable, NSWindowStyleMaskResizable,
    NSWindowStyleMaskFullSizeContentView, NSBackingStoreBuffered, NSMakeRect, NSColor, NSFont,
    NSPopUpButton, NSSearchField, NSTextView, NSScrollView, NSTableView, NSTableColumn, NSView,
    NSSegmentedControl,
)
from Foundation import NSObject, NSURL, NSMakeSize
from WebKit import WKWebView, WKWebViewConfiguration, WKUserContentController
try:  # location (optional): pip install pyobjc-framework-CoreLocation
    import CoreLocation
    HAS_CL = True
except Exception:  # pragma: no cover
    CoreLocation = None
    HAS_CL = False
from oasa.app.data import DataMixin
from oasa.app.location import LocationMixin
from oasa.app.sheet import SheetMixin
from oasa.app.tabs import TabsMixin
from oasa.config import AUTH_GRANTED, AUTH_NOT_DETERMINED, CARTO_KEY, PILL_H, TABS, TOP_INSET, W_SIZABLE
from oasa.debug import DEBUG, DEBUG_LINES, _debug_lock, _debug_seq, log
from oasa.eta import fmt_eta
from oasa.ui.map import HTML_MAP
from oasa.ui.views import DragHandle, MapHandler, RowDataSource
from oasa.ui.widgets import button, glass, haptic, label, line_id_of, solid


class OasaNativeApp(NSObject, SheetMixin, DataMixin, TabsMixin, LocationMixin):
    def applicationDidFinishLaunching_(self, notification):
        self.results = queue.Queue()
        self.lines = []
        self.line_data = None
        self.live = {}
        self.stop_options = {}
        self.selected_stop_id = None
        self.current_line = None
        self.map_ready = False
        self.sheet_full = False
        self.sheet_override = None
        self.sheet_h = 360
        self.anim = None
        self.anim_timer = None
        self.drag_start_h = 360
        self.bus_markers = []
        self.debug_seen = -1
        self.tab = 0
        self.pinned_id = None
        self.route_variant = None
        self.route_variant_user = False
        self.variant_keys = []
        self.user_loc = None
        self.loc_mgr = None
        self.loc_pending = None
        self.loc_tried = False
        log(f'DEBUG on · python {sys.version.split()[0]} · pid {os.getpid()} · CoreLocation {"yes" if HAS_CL else "no"}')

        style = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                 | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView)
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 440, 880), style, NSBackingStoreBuffered, False)
        self.window.setTitle_('Makro OASA'); self.window.setTitlebarAppearsTransparent_(True)
        self.window.setTitleVisibility_(1)
        self.window.setMinSize_((360, 640)); self.window.center(); self.window.setDelegate_(self)
        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 440, 880))
        self.window.setContentView_(content); self.content = content

        # --- Map (full-bleed) ---
        config = WKWebViewConfiguration.alloc().init()
        controller = WKUserContentController.alloc().init()
        self.map_handler = MapHandler.alloc().initWithApp_(self)
        controller.addScriptMessageHandler_name_(self.map_handler, 'oasa')
        config.setUserContentController_(controller)
        self.map = WKWebView.alloc().initWithFrame_configuration_(NSMakeRect(0, 0, 440, 880), config)
        self.map.setNavigationDelegate_(self)
        content.addSubview_(self.map)
        self.map.loadHTMLString_baseURL_(HTML_MAP.replace('__CARTO_KEY__', CARTO_KEY),
                                         NSURL.URLWithString_('https://localhost/'))

        # --- Floating top bar ---
        self.pill = glass(NSMakeRect(0, 0, 420, PILL_H), 18)
        self.title = label('Makro OASA', 15, True)
        self.status = label('Loading transit data…', 11, color=NSColor.secondaryLabelColor())
        self.refresh_button = button('↻', self, 'refresh:', 7)  # circular
        for v in (self.title, self.status, self.refresh_button):
            self.pill.addSubview_(v)
        if DEBUG:
            self.debug_button = button('🐞', self, 'toggleDebug:', 7)
            self.pill.addSubview_(self.debug_button)
        content.addSubview_(self.pill)

        # --- Bottom sheet ---
        self.sheet = glass(NSMakeRect(0, 0, 420, 360), 22)
        self.handle = DragHandle.alloc().initWithFrame_(NSMakeRect(0, 0, 420, 30))
        self.handle.app = self
        self.handle_pill = solid(NSMakeRect(0, 0, 40, 5), NSColor.tertiaryLabelColor(), 2.5)
        self.handle.addSubview_(self.handle_pill)

        self.line_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 28))
        self.line_menu.setTarget_(self); self.line_menu.setAction_('lineChanged:')
        self.tabs = NSSegmentedControl.segmentedControlWithLabels_trackingMode_target_action_(TABS, 0, self, 'tabChanged:')
        self.tabs.setSelectedSegment_(0)
        self.search = NSSearchField.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 26))
        self.search.setPlaceholderString_('Search stop name…')
        self.search.setSendsSearchStringImmediately_(True)
        self.search.setTarget_(self); self.search.setAction_('searchChanged:')
        self.stop_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 28))
        self.stop_menu.setTarget_(self); self.stop_menu.setAction_('stopChanged:')
        self.variant_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 26))
        self.variant_menu.setTarget_(self); self.variant_menu.setAction_('variantChanged:')
        self.arrival_heading = label('APPROACHING BUSES', 11, True, NSColor.secondaryLabelColor())
        self.locate_button = button('📍 Locate me', self, 'locateMe:', 1)
        self.locate_button.setControlSize_(1); self.locate_button.setFont_(NSFont.systemFontOfSize_(11))

        self.table_source = RowDataSource.alloc().init(); self.table_source.app = self
        self.route_source = RowDataSource.alloc().init(); self.route_source.app = self
        self.near_source = RowDataSource.alloc().init(); self.near_source.app = self
        self.arr_scroll, self.table, self.table_col = self.make_table(self.table_source, None)
        self.route_scroll, self.route_table, self.route_col = self.make_table(self.route_source, 'routeClicked:')
        self.near_scroll, self.near_table, self.near_col = self.make_table(self.near_source, 'nearbyClicked:')

        for v in (self.handle, self.line_menu, self.tabs, self.search, self.stop_menu, self.variant_menu,
                  self.arrival_heading, self.locate_button, self.arr_scroll, self.route_scroll, self.near_scroll):
            self.sheet.addSubview_(v)
        content.addSubview_(self.sheet)

        # --- Debug overlay (only when DEBUG) ---
        if DEBUG:
            self.debug_panel = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 420, 190))
            self.debug_panel.setWantsLayer_(True)
            self.debug_panel.layer().setCornerRadius_(12)
            self.debug_panel.layer().setBackgroundColor_(NSColor.blackColor().colorWithAlphaComponent_(0.78).CGColor())
            self.debug_stats = label('', 10, True, NSColor.systemGreenColor())
            self.debug_stats.setFont_(NSFont.monospacedSystemFontOfSize_weight_(10, 0.4))
            self.debug_text = NSTextView.alloc().initWithFrame_(NSMakeRect(0, 0, 400, 150))
            self.debug_text.setEditable_(False); self.debug_text.setDrawsBackground_(False)
            self.debug_text.setTextColor_(NSColor.whiteColor())
            self.debug_text.setFont_(NSFont.monospacedSystemFontOfSize_weight_(10, 0.0))
            self.debug_text.setVerticallyResizable_(True); self.debug_text.setHorizontallyResizable_(False)
            self.debug_text.setAutoresizingMask_(W_SIZABLE)
            self.debug_text.textContainer().setWidthTracksTextView_(True)
            self.debug_scroll = NSScrollView.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 100))
            self.debug_scroll.setHasVerticalScroller_(True); self.debug_scroll.setDrawsBackground_(False)
            self.debug_scroll.setDocumentView_(self.debug_text)
            self.debug_panel.addSubview_(self.debug_stats); self.debug_panel.addSubview_(self.debug_scroll)
            content.addSubview_(self.debug_panel)

        self.do_layout()
        self.window.makeKeyAndOrderFront_(None)
        NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
        threading.Thread(target=self.fetch_lines, daemon=True).start()
        self.schedule_poll()

    def applicationShouldTerminateAfterLastWindowClosed_(self, app):
        return True

    def make_table(self, source, action):
        table = NSTableView.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 100))
        col = NSTableColumn.alloc().initWithIdentifier_('c')
        col.setWidth_(400); col.setEditable_(False)
        table.addTableColumn_(col)
        table.setHeaderView_(None)
        if hasattr(table, 'setStyle_'):
            table.setStyle_(1)  # full-width: no side inset, so cards stay centred
        table.setBackgroundColor_(NSColor.clearColor())
        table.setSelectionHighlightStyle_(-1)
        table.setIntercellSpacing_(NSMakeSize(0, 0))
        table.setColumnAutoresizingStyle_(1)
        table.setDataSource_(source); table.setDelegate_(source)
        if action:
            table.setTarget_(self); table.setAction_(action)
        scroll = NSScrollView.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 100))
        scroll.setHasVerticalScroller_(True); scroll.setAutohidesScrollers_(True)
        scroll.setDrawsBackground_(False)
        scroll.setDocumentView_(table)
        return scroll, table, col

    def do_layout(self, reload=True):
        self.update_tab_ui()
        b = self.content.bounds()
        W, H = b.size.width, b.size.height
        self.map.setFrame_(NSMakeRect(0, 0, W, H))
        pw = min(W - 20, 480); px = (W - pw) / 2

        pill_y = H - TOP_INSET - PILL_H
        self.pill.setFrame_(NSMakeRect(px, pill_y, pw, PILL_H))
        self.title.setFrame_(NSMakeRect(16, 27, pw - 110, 20))
        self.status.setFrame_(NSMakeRect(16, 8, pw - 110, 16))
        self.refresh_button.setFrame_(NSMakeRect(pw - 44, 10, 32, 32))
        if DEBUG:
            self.debug_button.setFrame_(NSMakeRect(pw - 80, 10, 32, 32))

        if self.sheet_override is not None:
            sh = self.sheet_override
        else:
            sh = self.full_h(H) if self.sheet_full else self.peek_h(H)
        self.sheet_h = sh
        self.sheet.setFrame_(NSMakeRect(px, 10, pw, sh))
        self.handle.setFrame_(NSMakeRect(0, sh - 30, pw, 30))
        self.handle_pill.setFrame_(NSMakeRect(pw / 2 - 20, 14, 40, 5))

        y = sh - 34
        self.line_menu.setFrame_(NSMakeRect(12, y - 28, pw - 24, 28)); y -= 36
        self.tabs.setFrame_(NSMakeRect(12, y - 24, pw - 24, 24)); y -= 32
        if self.tab == 0:
            self.search.setFrame_(NSMakeRect(12, y - 26, pw - 24, 26)); y -= 32
            self.stop_menu.setFrame_(NSMakeRect(12, y - 28, pw - 24, 28)); y -= 36
        if self.tab == 1 and len(self.variant_keys) > 1:
            self.variant_menu.setFrame_(NSMakeRect(12, y - 26, pw - 24, 26)); y -= 32
        else:
            self.arrival_heading.setFrame_(NSMakeRect(16, y - 18, pw - 32, 16))
            self.locate_button.setFrame_(NSMakeRect(pw - 134, y - 22, 122, 22))
            y -= 26
        area = NSMakeRect(6, 6, pw - 12, max(40, y - 6))
        for scroll, col, table in ((self.arr_scroll, self.table_col, self.table),
                                   (self.route_scroll, self.route_col, self.route_table),
                                   (self.near_scroll, self.near_col, self.near_table)):
            scroll.setFrame_(area)
            col.setWidth_(scroll.contentSize().width)  # exact visible width, so cards stay centred
            if reload:
                table.reloadData()

        if DEBUG:
            dh = 190
            self.debug_panel.setFrame_(NSMakeRect(px, pill_y - 8 - dh, pw, dh))
            self.debug_stats.setFrame_(NSMakeRect(10, dh - 22, pw - 20, 16))
            self.debug_scroll.setFrame_(NSMakeRect(6, 6, pw - 12, dh - 30))

    def windowDidResize_(self, notification):
        self.do_layout()

    def animTick_(self, timer):
        a = self.anim
        if not a:
            timer.invalidate(); self.anim_timer = None
            return
        t = min(1.0, (time.time() - a['t0']) / 0.25)
        e = 1 - (1 - t) ** 3
        self.sheet_override = a['start'] + (a['end'] - a['start']) * e
        self.do_layout(reload=False)
        if t >= 1.0:
            timer.invalidate(); self.anim_timer = None; self.anim = None
            self.sheet_full = a['full']; self.sheet_override = None
            log(f'sheet -> {"full" if self.sheet_full else "peek"}')
            self.do_layout()
            haptic()

    def toggleDebug_(self, sender):
        if DEBUG:
            self.debug_panel.setHidden_(not self.debug_panel.isHidden())

    # ---- WKNavigationDelegate -------------------------------------------------
    def webView_didFinishNavigation_(self, webview, navigation):
        self.map_ready = True
        log('webview: page loaded')
        if self.line_data:
            self.push_stops(fit=True)
            self.push_buses(self.bus_markers)
        if self.user_loc:
            self.evaluate_js(f'window.setUser({self.user_loc[0]},{self.user_loc[1]});')

    def webView_didFailNavigation_withError_(self, webview, navigation, error):
        log(f'webview: navigation failed: {error}', 'ERROR')

    def webView_didFailProvisionalNavigation_withError_(self, webview, navigation, error):
        log(f'webview: provisional navigation failed: {error}', 'ERROR')

    # ---- JS bridge ------------------------------------------------------------
    def evaluate_js(self, code):
        if not self.map_ready:
            log('evaluate_js skipped (map not ready)', 'WARN')
            return
        if DEBUG:
            self.map.evaluateJavaScript_completionHandler_(
                code, lambda result, error: log(f'JS eval error: {error}', 'ERROR') if error else None)
        else:
            self.map.evaluateJavaScript_completionHandler_(code, None)

    # ---- Actions --------------------------------------------------------------
    def lineChanged_(self, sender):
        line_id = line_id_of(sender.titleOfSelectedItem())
        if line_id:
            log(f'line selected: {line_id}')
            self.current_line = line_id
            self.selected_stop_id = None
            self.route_variant = None; self.route_variant_user = False
            self.pinned_id = None
            self.status.setStringValue_(f'Loading line {line_id}…')
            threading.Thread(target=self.fetch_line, args=(line_id,), daemon=True).start()

    def stopChanged_(self, sender):
        sid = self.stop_options.get(str(sender.titleOfSelectedItem() or ''))
        if sid:
            self.select_stop(sid)

    def searchChanged_(self, sender):
        if self.line_data is None:
            return
        term = str(sender.stringValue() or '').casefold()
        self.stop_menu.removeAllItems(); self.stop_options = {}
        stops = self.line_data.get('stops', {})
        for sid, s in sorted(stops.items(), key=lambda x: str(x[1].get('name', '')).casefold()):
            title = f'{s.get("name", "Unnamed stop")} [{sid}]'
            if term and term not in title.casefold():
                continue
            self.stop_menu.addItemWithTitle_(title)
            self.stop_options[title] = str(sid)
        log(f'search "{term}" -> {len(self.stop_options)} stops')

    def tabChanged_(self, sender):
        self.set_tab(int(sender.selectedSegment()))

    def variantChanged_(self, sender):
        idx = int(sender.indexOfSelectedItem())
        if 0 <= idx < len(self.variant_keys):
            self.route_variant = self.variant_keys[idx]
            self.route_variant_user = True
            self.rebuild_route()
            self.scroll_route_to_selected()

    def select_stop(self, sid):
        if not self.line_data:
            return
        sid = str(sid)
        stop = self.line_data.get('stops', {}).get(sid)
        if not stop:
            log(f'select_stop: unknown stop {sid}', 'WARN')
            return
        log(f'stop selected: {stop.get("name")} [{sid}]')
        self.selected_stop_id = sid
        self.route_variant_user = False
        self.push_stops()
        if stop.get('lat') is not None and stop.get('lon') is not None:
            self.evaluate_js(f'window.focusStop({float(stop["lat"])},{float(stop["lon"])},16,{int(self.sheet_h)});')
        self.render_arrivals(self.live)
        if self.current_line:  # get official predictions for the new stop
            threading.Thread(target=self.fetch_live, args=(self.current_line,), daemon=True).start()
        title = f'{stop.get("name", "Unnamed stop")} [{sid}]'
        if title in self.stop_options:
            self.stop_menu.selectItemWithTitle_(title)
        if self.tab == 1:
            self.do_layout()
            self.scroll_route_to_selected()

    def refresh_(self, sender):
        if self.line_menu.numberOfItems() == 0:
            return
        line = line_id_of(self.line_menu.titleOfSelectedItem())
        log(f'manual refresh: {line}')
        threading.Thread(target=self.fetch_live, args=(line,), daemon=True).start()

    # ---- Pin / follow a bus ---------------------------------------------------
    def pinBus_(self, sender):
        self.toggle_pin(str(sender.identifier()))

    def toggle_pin(self, bid):
        self.pinned_id = None if self.pinned_id == bid else bid
        log(f'pin -> {self.pinned_id}')
        self.evaluate_js(f'window.setPinned({json.dumps(self.pinned_id)},{int(self.sheet_h)});')
        haptic()
        self.render_arrivals(self.live)

    def on_unpin(self):
        log('pin released (map dragged)')
        self.pinned_id = None
        self.render_arrivals(self.live)

    def routeClicked_(self, sender):
        r = int(sender.clickedRow())
        rows = self.route_source.rows
        if 0 <= r < len(rows) and rows[r].get('kind') == 'stop':
            haptic()
            self.select_stop(rows[r]['sid'])

    def nearbyClicked_(self, sender):
        r = int(sender.clickedRow())
        rows = self.near_source.rows
        if 0 <= r < len(rows) and rows[r].get('kind') == 'near':
            haptic()
            self.select_stop(rows[r]['sid'])
            self.set_tab(0)

    def locateMe_(self, sender):
        self.start_location()

    def locationManager_didUpdateLocations_(self, manager, locations):
        try:
            c = locations[-1].coordinate()
            self.loc_pending = None
            log(f'location: {c.latitude:.5f}, {c.longitude:.5f}')
            self.set_user_location(c.latitude, c.longitude, 'gps')
        except Exception as e:
            log(f'location parse error: {e}', 'ERROR')

    def locationManager_didFailWithError_(self, manager, error):
        log(f'location failed: {error}', 'WARN')
        if manager.authorizationStatus() == AUTH_NOT_DETERMINED:
            return  # permission prompt still open: retried from the authorization callback
        if self.loc_pending:
            self.use_map_center(str(error))

    def locationManagerDidChangeAuthorization_(self, manager):
        status = manager.authorizationStatus()
        log(f'location authorization: {status}')
        if not self.loc_pending:
            return
        if status in AUTH_GRANTED:
            manager.requestLocation()
        elif status != AUTH_NOT_DETERMINED:
            self.use_map_center('location permission denied')

    def locTimeout_(self, timer):
        if self.loc_pending and time.time() - self.loc_pending >= timer.userInfo():
            self.use_map_center('timed out')

    def tick_(self, timer):
        """Once a second: live ETA countdowns between data refreshes."""
        now = time.time()
        for r in self.table_source.rows:
            lab = r.get('eta_label')
            if lab is not None and r.get('eta_s') is not None:
                lab.setStringValue_(fmt_eta(r['eta_s'] - (now - r['t0'])))
        for r in self.near_source.rows:
            lab = r.get('next_label')
            if lab is not None and r.get('eta_s') is not None:
                lab.setStringValue_(f'Bus {r["bus_id"]} · {fmt_eta(r["eta_s"] - (now - r["t0"]))}')

    def update_debug_panel(self):
        veh = len((self.live or {}).get('vehicles', []))
        self.debug_stats.setStringValue_(
            f'line {self.current_line} · stop {self.selected_stop_id} · veh {veh} · tab {TABS[self.tab]} · '
            f'pin {self.pinned_id} · map {"ready" if self.map_ready else "loading"} · q{self.results.qsize()}')
        with _debug_lock:
            seq = _debug_seq[0]
            if seq == self.debug_seen:
                return
            self.debug_seen = seq
            text = '\n'.join(DEBUG_LINES)
        self.debug_text.setString_(text)
        self.debug_text.scrollToEndOfDocument_(None)

    def checkResults_(self, timer):
        # All AppKit controls are updated on the main thread.
        while True:
            try:
                item = self.results.get_nowait()
            except queue.Empty:
                break
            kind = item[0]
            if kind == 'refresh_request':
                if self.line_menu.numberOfItems():
                    line = line_id_of(self.line_menu.titleOfSelectedItem())
                    log(f'auto refresh: {line}')
                    threading.Thread(target=self.fetch_live, args=(line,), daemon=True).start()
            elif kind == 'error':
                self.status.setStringValue_('Error: ' + item[1][:120])
            elif kind == 'lines':
                self.lines = item[1].get('lines', [])
                log(f'lines loaded: {len(self.lines)}')
                self.line_menu.removeAllItems()
                for line in self.lines:
                    self.line_menu.addItemWithTitle_(f'{line["id"]} — {line.get("name", "")}')
                idx = next((i for i in range(self.line_menu.numberOfItems())
                            if self.line_menu.itemTitleAtIndex_(i).startswith('810 —')), 0)
                if self.line_menu.numberOfItems():
                    self.line_menu.selectItemAtIndex_(idx)
                    self.lineChanged_(self.line_menu)
            elif kind == 'line':
                _, line_id, static, live = item
                if line_id != self.current_line:
                    log(f'dropped stale line response {line_id} (current {self.current_line})', 'WARN')
                    continue
                self.line_data, self.live = static, live
                self.selected_stop_id = None
                self.search.setStringValue_('')
                self.searchChanged_(self.search)
                self.push_stops(fit=True)
                self.render_arrivals(self.live)
                self.do_layout()
                self.status.setStringValue_(f'Line {line_id} · {len(self.live.get("vehicles", []))} live buses')
            elif kind == 'live':
                _, line_id, live = item
                if line_id != self.current_line:
                    log(f'dropped stale live response {line_id} (current {self.current_line})', 'WARN')
                    continue
                self.render_arrivals(live)
                self.status.setStringValue_(f'Line {line_id} · Updated {datetime.now().astimezone():%H:%M:%S}')
        if DEBUG:
            self.update_debug_panel()
