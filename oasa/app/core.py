"""The app delegate: window setup, layout and every Objective-C callable method.

Methods called from Objective-C (actions, delegates, timers) must live on this
NSObject class itself; PyObjC does not register them from mixins."""
import json, os, queue, sys, threading, time
from datetime import datetime
from AppKit import (
    NSApplication, NSWindow, NSWindowStyleMaskTitled, NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable, NSWindowStyleMaskResizable,
    NSWindowStyleMaskFullSizeContentView, NSBackingStoreBuffered, NSMakeRect, NSColor, NSFont,
    NSPopUpButton, NSSearchField, NSTextField, NSImageView, NSImage, NSButton, NSTextView, NSScrollView, NSTableView, NSTableColumn, NSView,
    NSSegmentedControl,
)
from Foundation import NSObject, NSURL, NSMakeSize
from AppKit import NSAnimationContext, NSWorkspace
from WebKit import WKWebView, WKWebViewConfiguration, WKUserContentController
try:  # location (optional): pip install pyobjc-framework-CoreLocation
    import CoreLocation
    HAS_CL = True
except Exception:  # pragma: no cover
    CoreLocation = None
    HAS_CL = False
from oasa.app.data import DataMixin
from oasa.app.explore import ExploreMixin
from oasa.app.glance import GLANCE_EVERY_S, GlanceMixin
from oasa.app.palette import PaletteMixin
from oasa.app.onboarding import OnboardingMixin
from oasa.app.settings import SettingsMixin, show_recents
from oasa.app.location import LocationMixin
from oasa.app.sheet import SheetMixin
from oasa.app.tabs import TabsMixin
from oasa.config import CHIP_H, MAP_FREE_AFTER_S, LINE_MENU_H, SHEET_GAP, ALERTS_EVERY_S, ANIM_S, AUTH_GRANTED, AUTH_NOT_DETERMINED, CARTO_KEY, DRAG_BAR_H, FLOAT_BTN, FOCUS_SHEET_H, PILL_H, TABS, TOP_INSET, W_SIZABLE
from oasa.debug import DEBUG, DEBUG_LINES, _debug_lock, _debug_seq, log
from oasa.eta import fmt_eta
from oasa.ui.map import HTML_MAP
from oasa.ui.menu import install_menu
from oasa.ui.motion import roll
from oasa.ui.views import DragHandle, MapHandler, RowDataSource, SheetView, WindowDragBar
from oasa import __version__, i18n, updates
from oasa.i18n import line_label, t
from oasa.ui.widgets import button, float_button, glass, haptic, label, solid


class MainQueue(queue.Queue):
    """A queue whose put() also asks the main thread to drain it: no polling timer needed."""
    def __init__(self, app):
        super().__init__()
        self.app = app

    def put(self, item, block=True, timeout=None):
        super().put(item, block, timeout)
        self.app.performSelectorOnMainThread_withObject_waitUntilDone_('checkResults:', None, False)


class OasaNativeApp(NSObject, SheetMixin, DataMixin, TabsMixin, LocationMixin, ExploreMixin, GlanceMixin, PaletteMixin, OnboardingMixin, SettingsMixin):
    def applicationDidFinishLaunching_(self, notification):
        self.results = MainQueue(self)   # worker threads -> main thread (wakes it only when something arrives)
        self.visible = True         # window on screen (not minimised, hidden, closed or covered)
        self.tick_timer = None      # 1 s countdowns: only while visible on the line view
        self.last_refresh = time.time()
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
        self.mode = 'home'          # 'home' (stops near you) | 'stop' (lines at a stop) | 'line'
        self.near_stops = {}
        self.near_origin = None     # where the current nearby-stops list was searched from
        self.near_from_map = False  # True: searched around the map centre after a pan
        self.explore_stop = None
        self.stop_lines = None
        self.pending_stop = None    # stop to select once a line opened from a stop has loaded
        self.drawn_variant = None   # route variant whose shape is on the map
        self.timetable = None       # (line id, today's timetable) for the Timetable tab
        self.prev_eta = {}          # row -> last ETA text shown (a change rolls to the new value)
        self.fav_at = {}            # favourite stop id -> when its lines were fetched
        self.status_item = None     # menu bar item (oasa/app/glance.py)
        self.fav_lines = {}         # favourite stop id -> its lines with live ETAs (None = not loaded yet)
        self.search_query = ''
        self.search_return = None   # mode to go back to when the search field is cleared
        self.stop_idx = None        # every stop, for search (oasa/stop_index.py)
        self.net_error = None       # {'what', 'kind'} of the latest failure (for the message)
        self.failed = {}            # every failed request: what -> 'offline' | 'service'; all retried
        self.last_live_ok = None    # when line data last arrived (shown when offline)
        self.update_info = None     # (version, url) of a newer release on GitHub
        self.home_tab = 0           # home screen: 0 = stops nearby, 1 = favourites
        self.stop_bus_line = {}     # stop screen: approaching bus id -> its line
        self.alerts = []            # OASA service alerts (oasa/alerts.py)
        self.alerts_at = 0          # when they were last fetched
        self.pending_pin = None     # bus to pin once the line opened from it has loaded
        self.map_focus = False      # map expanded: top bar hidden, sheet down to a strip
        self.fullscreen = False     # macOS full screen: bar replaced by round side buttons
        self.pill_alpha = 1.0       # top bar visibility (animated with the sheet)
        self.find_open = False      # full screen: floating search field shown
        self.find_animating = False # it is growing out of / shrinking into its icon
        self.top_inset_sent = None  # last top inset told to the map page
        log(f'DEBUG on · python {sys.version.split()[0]} · pid {os.getpid()} · CoreLocation {"yes" if HAS_CL else "no"}')

        style = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                 | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView)
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 440, 880), style, NSBackingStoreBuffered, False)
        self.window.setTitle_('BusMakro'); self.window.setTitlebarAppearsTransparent_(True)
        self.window.setTitleVisibility_(1)
        self.window.setMinSize_((360, 640)); self.window.center(); self.window.setDelegate_(self)
        self.window.setReleasedWhenClosed_(False)  # closing keeps BusMakro in the menu bar
        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 440, 880))
        self.window.setContentView_(content); self.content = content

        # --- Map (full-bleed) ---
        self.map = None
        self.map_camera = None      # where the map was looking when it was freed
        self.free_timer = None
        self.make_map()

        # --- Window drag strip along the very top (fades in on hover) ---
        self.drag_bar = WindowDragBar.alloc().initWithFrame_(NSMakeRect(0, 852, 440, DRAG_BAR_H))
        content.addSubview_(self.drag_bar)

        # --- Round floating map buttons (ride on top of the sheet) ---
        self.map_focus_wrap, self.map_focus_btn = float_button(
            'arrow.up.left.and.arrow.down.right', self, 'toggleMapFocus:', FLOAT_BTN, t('tip_expand'))
        self.map_locate_wrap, self.map_locate_btn = float_button('location', self, 'locateMe:', FLOAT_BTN, t('m_locate'))
        # --- Full screen: the bar's controls as round buttons on the sides, plus a floating search field ---
        self.fs_search_wrap, self.fs_search_btn = float_button('magnifyingglass', self, 'toggleFindFloat:', FLOAT_BTN, t('search_bar'))
        self.fs_refresh_wrap, self.fs_refresh_btn = float_button('arrow.clockwise', self, 'refresh:', FLOAT_BTN, t('m_refresh'))
        self.fs_update_wrap, self.fs_update_btn = float_button('arrow.down.circle', self, 'openUpdate:', FLOAT_BTN)
        self.fs_wraps = [self.fs_search_wrap, self.fs_refresh_wrap, self.fs_update_wrap]
        if DEBUG:
            self.fs_debug_wrap, _ = float_button('ladybug', self, 'toggleDebug:', FLOAT_BTN, 'Debug')
            self.fs_wraps.append(self.fs_debug_wrap)
        self.find_float = glass(NSMakeRect(0, 0, 300, FLOAT_BTN), FLOAT_BTN / 2)
        for v in [self.map_focus_wrap, self.map_locate_wrap, self.find_float] + self.fs_wraps:
            content.addSubview_(v)

        # --- Top bar: a floating glass search capsule with round buttons beside it (no panel behind) ---
        self.pill = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 420, PILL_H))  # plain holder, see-through
        self.status = label(t('finding_stops'), 11, color=NSColor.secondaryLabelColor())  # not shown; kept for messages
        self.find_wrap = glass(NSMakeRect(0, 0, 300, PILL_H), PILL_H / 2)
        # a plain text field with our own magnifier and clear button (a borderless NSSearchField draws
        # its icon on top of the text)
        self.find = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 18))
        self.find.setPlaceholderString_(t('search_bar'))
        self.find.setTarget_(self); self.find.setAction_('findChanged:')
        self.find.setDelegate_(self)  # typing, editing begins/ends: results update, the capsule grows and back
        self.find.setFont_(NSFont.systemFontOfSize_(13))
        self.find.setBezeled_(False); self.find.setBordered_(False); self.find.setDrawsBackground_(False)
        self.find.setFocusRingType_(1); self.find.cell().setScrollable_(True); self.find.cell().setUsesSingleLineMode_(True)
        self.find_icon = NSImageView.alloc().initWithFrame_(NSMakeRect(0, 0, 16, 16))
        self.find_icon.setImage_(NSImage.imageWithSystemSymbolName_accessibilityDescription_('magnifyingglass', None))
        self.find_icon.setContentTintColor_(NSColor.secondaryLabelColor())
        self.find_clear = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 18, 18))
        self.find_clear.setBordered_(False); self.find_clear.setImagePosition_(1)
        self.find_clear.setImage_(NSImage.imageWithSystemSymbolName_accessibilityDescription_('xmark.circle.fill', None))
        self.find_clear.setContentTintColor_(NSColor.tertiaryLabelColor())
        self.find_clear.setTarget_(self); self.find_clear.setAction_('clearFind:'); self.find_clear.setHidden_(True)
        for v in (self.find_icon, self.find, self.find_clear):
            self.find_wrap.addSubview_(v)
        self.refresh_wrap, self.refresh_button = float_button('arrow.clockwise', self, 'refresh:', PILL_H, t('m_refresh'))
        self.update_wrap, self.update_button = float_button('arrow.down.circle', self, 'openUpdate:', PILL_H)
        self.update_wrap.setHidden_(True)
        self.bar_buttons = [self.refresh_wrap, self.update_wrap]
        if DEBUG:
            self.debug_wrap, self.debug_button = float_button('ladybug', self, 'toggleDebug:', PILL_H, 'Debug')
            self.bar_buttons.append(self.debug_wrap)
        self.find_expanded = False  # searching: the capsule covers the buttons until the search is cleared
        for v in [self.find_wrap] + self.bar_buttons:
            self.pill.addSubview_(v)
        content.addSubview_(self.pill)
        self.chips = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 420, CHIP_H))  # recent stops, under the bar
        content.addSubview_(self.chips)
        self.chip_buttons = []

        # --- Bottom sheet ---
        self.sheet = glass(NSMakeRect(0, 0, 420, 360), 22, SheetView)
        self.sheet.app = self
        self.handle = DragHandle.alloc().initWithFrame_(NSMakeRect(0, 0, 420, 30))
        self.handle.app = self
        self.handle_pill = solid(NSMakeRect(0, 0, 40, 5), NSColor.tertiaryLabelColor(), 2.5)
        self.handle.addSubview_(self.handle_pill)

        self.back_button = button(t('back'), self, 'backClicked:', 1)
        self.explore_heading = label(t('h_stops_near_you'), 11, True, NSColor.secondaryLabelColor())
        self.line_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 28))
        self.line_menu.setTarget_(self); self.line_menu.setAction_('lineChanged:')
        # a smaller, borderless menu in a rounded field whose corners follow the sheet's (concentric)
        self.line_menu.setControlSize_(1); self.line_menu.setFont_(NSFont.systemFontOfSize_(12))
        self.line_menu.setBordered_(False); self.line_menu.setWantsLayer_(True)
        self.line_menu.layer().setCornerRadius_(22 - SHEET_GAP)  # sheet radius minus the inset
        self.line_menu.layer().setBackgroundColor_(NSColor.labelColor().colorWithAlphaComponent_(0.10).CGColor())
        self.tabs = NSSegmentedControl.segmentedControlWithLabels_trackingMode_target_action_([t(k) for k in TABS], 0, self, 'tabChanged:')
        self.tabs.setSelectedSegment_(0)
        self.search = NSSearchField.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 26))
        self.search.setPlaceholderString_(t('search_stop'))
        self.search.setSendsSearchStringImmediately_(True)
        self.search.setTarget_(self); self.search.setAction_('searchChanged:')
        self.stop_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 28))
        self.stop_menu.setTarget_(self); self.stop_menu.setAction_('stopChanged:')
        self.variant_menu = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 26))
        self.variant_menu.setTarget_(self); self.variant_menu.setAction_('variantChanged:')
        self.arrival_heading = label(t('h_approaching'), 11, True, NSColor.secondaryLabelColor())
        self.fav_button = button('☆', self, 'toggleFavorite:', 7)  # circular, icon only (tooltip says what)
        self.fav_button.setFont_(NSFont.systemFontOfSize_(15))
        self.home_tabs = NSSegmentedControl.segmentedControlWithLabels_trackingMode_target_action_(
            [t('tab_home_nearby'), t('tab_favourites')], 0, self, 'homeTabChanged:')
        self.home_tabs.setSelectedSegment_(0)
        self.locate_button = button(t('locate_me'), self, 'locateMe:', 1)
        self.locate_button.setControlSize_(1); self.locate_button.setFont_(NSFont.systemFontOfSize_(11))

        self.table_source = RowDataSource.alloc().init(); self.table_source.app = self
        self.route_source = RowDataSource.alloc().init(); self.route_source.app = self
        self.near_source = RowDataSource.alloc().init(); self.near_source.app = self
        self.tt_source = RowDataSource.alloc().init(); self.tt_source.app = self
        self.explore_source = RowDataSource.alloc().init(); self.explore_source.app = self
        self.arr_scroll, self.table, self.table_col = self.make_table(self.table_source, 'arrivalsClicked:')
        self.route_scroll, self.route_table, self.route_col = self.make_table(self.route_source, 'routeClicked:')
        self.near_scroll, self.near_table, self.near_col = self.make_table(self.near_source, 'nearbyClicked:')
        self.tt_scroll, self.tt_table, self.tt_col = self.make_table(self.tt_source, None)
        self.explore_scroll, self.explore_table, self.explore_col = self.make_table(self.explore_source, 'exploreClicked:')
        self.explore_source.rows = [{'message': t('finding_stops')}]

        for v in (self.handle, self.back_button, self.fav_button, self.home_tabs, self.explore_heading, self.explore_scroll, self.line_menu, self.tabs, self.search, self.stop_menu, self.variant_menu,
                  self.arrival_heading, self.locate_button, self.arr_scroll, self.route_scroll, self.near_scroll, self.tt_scroll):
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

        self.build_palette()
        self.do_layout()
        self.rebuild_chips()
        install_menu('BusMakro', self)
        self.drag_bar.fade(0.0, animate=False)  # traffic lights start hidden, like the bar
        self.window.makeKeyAndOrderFront_(None)
        self.window.makeFirstResponder_(None)  # don't start with the cursor in the search field
        self.ob = None
        self.maybe_onboard()
        NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
        threading.Thread(target=self.fetch_lines, daemon=True).start()
        threading.Thread(target=self.check_updates, args=(False,), daemon=True).start()
        self.schedule_poll()
        self.setup_glance()
        from Foundation import NSTimer
        NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(15, self, 'glanceTick:', None, True).setTolerance_(5)
        NSWorkspace.sharedWorkspace().notificationCenter().addObserver_selector_name_object_(
            self, 'systemDidWake:', 'NSWorkspaceDidWakeNotification', None)

    def applicationShouldTerminateAfterLastWindowClosed_(self, app):
        return self.status_item is None  # with the menu bar item, closing the window keeps it running

    def applicationShouldHandleReopen_hasVisibleWindows_(self, app, visible):
        self.window.makeKeyAndOrderFront_(None)  # Dock icon click brings the window back
        self.set_visible(True)
        return True

    def applicationWillTerminate_(self, notification):
        from oasa import history
        history.flush()

    def glanceTick_(self, timer):
        """Menu bar: count down every 15 s, refetch every GLANCE_EVERY_S."""
        if time.time() - getattr(self, 'glance_fetched', 0) >= GLANCE_EVERY_S:
            self.glance_fetched = time.time()
            self.poll_glance()
        self.update_glance()

    def menuBarStop_(self, sender):
        self.open_from_glance(sender.representedObject())

    def menuBarOpen_(self, sender):
        self.open_from_glance()

    def toggleMenuBar_(self, sender):
        self.show_menu_bar(self.status_item is None)
        sender.setState_(1 if self.status_item else 0)

    def setMapStyle_(self, sender):
        from Foundation import NSUserDefaults
        style = sender.representedObject()
        NSUserDefaults.standardUserDefaults().setObject_forKey_(style, 'mapStyle')
        for it in sender.menu().itemArray():
            it.setState_(1 if it.representedObject() == style else 0)
        self.apply_map_prefs()

    def toggle3D_(self, sender):
        from Foundation import NSUserDefaults
        d = NSUserDefaults.standardUserDefaults()
        d.setBool_forKey_(not d.boolForKey_('map3d'), 'map3d')
        sender.setState_(1 if d.boolForKey_('map3d') else 0)
        self.apply_map_prefs()

    def apply_map_prefs(self):
        from Foundation import NSUserDefaults
        d = NSUserDefaults.standardUserDefaults()
        self.evaluate_js(f"window.setMapStyle({json.dumps(d.stringForKey_('mapStyle') or 'system')});"
                         f"window.set3D({json.dumps(bool(d.boolForKey_('map3d')))});")

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

    def rebuild_chips(self):
        """Recent stops as small glass capsules under the search bar (home screen)."""
        from oasa import recents
        for b in self.chip_buttons:
            b.removeFromSuperview()
        self.chip_buttons = []
        self.recent_stops = recents.load() if show_recents() else []  # Settings can turn the chips off
        for i, r in enumerate(self.recent_stops):
            text = i18n.name(r.get('name'), r.get('name_en')) or r['id']
            text = text if len(text) <= 22 else text[:21] + '…'
            lab = label(text, 11, True)
            w = min(190, lab.fittingSize().width + 34)
            wrap = glass(NSMakeRect(0, 0, w, CHIP_H), CHIP_H / 2)
            btn = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, w, CHIP_H))
            btn.setBordered_(False); btn.setTitle_('')
            btn.setTarget_(self); btn.setAction_('recentClicked:'); btn.setTag_(i)
            ico = NSImageView.alloc().initWithFrame_(NSMakeRect(10, (CHIP_H - 12) / 2, 12, 12))
            ico.setImage_(NSImage.imageWithSystemSymbolName_accessibilityDescription_('clock.arrow.circlepath', None))
            ico.setContentTintColor_(NSColor.secondaryLabelColor())
            lab.setFrame_(NSMakeRect(26, (CHIP_H - 15) / 2, w - 32, 15))
            for v in (ico, lab, btn):
                wrap.addSubview_(v)
            self.chips.addSubview_(wrap)
            self.chip_buttons.append(wrap)
        self.do_layout(reload=False)

    def onboardNext_(self, sender):
        self.onboard_next()

    def showSettings_(self, sender):
        self.show_settings()

    def settingChanged_(self, sender):
        self.setting_changed(sender)

    def clearRecents_(self, sender):
        self.clear_recents()

    def showWelcome_(self, sender):
        if self.ob is None:
            self.show_onboarding()

    def showPalette_(self, sender):
        self.show_palette()

    def paletteRowClicked_(self, sender):
        self.palette_open_item(int(sender.tag()))

    def paletteBackdrop_(self, sender):
        self.hide_palette()

    def recentClicked_(self, sender):
        i = int(sender.tag())
        if 0 <= i < len(self.recent_stops):
            haptic()
            self.open_stop(self.recent_stops[i]['id'], dict(self.recent_stops[i]))

    def make_map(self):
        """Create the map's web view (again, after it was freed) underneath everything else."""
        config = WKWebViewConfiguration.alloc().init()
        controller = WKUserContentController.alloc().init()
        self.map_handler = MapHandler.alloc().initWithApp_(self)
        controller.addScriptMessageHandler_name_(self.map_handler, 'oasa')
        config.setUserContentController_(controller)
        self.map = WKWebView.alloc().initWithFrame_configuration_(self.content.bounds(), config)
        self.map.setNavigationDelegate_(self)
        self.content.addSubview_positioned_relativeTo_(self.map, -1, None)  # NSWindowBelow: under the panels
        self.map.loadHTMLString_baseURL_(HTML_MAP.replace('__CARTO_KEY__', CARTO_KEY),
                                         NSURL.URLWithString_('https://localhost/'))

    def freeMap_(self, timer):
        """Hidden for a while: drop the whole map page (WebKit frees its process, ~170 MB). It is rebuilt,
        at the same spot, when the window comes back."""
        self.free_timer = None
        if self.visible or self.map is None:
            return

        def done(result, error):
            try:
                self.map_camera = json.loads(str(result))
            except Exception:
                self.map_camera = None
            if self.visible or self.map is None:
                return
            log('map freed while hidden')
            self.map_ready = False
            self.top_inset_sent = None
            self.map.setNavigationDelegate_(None)
            self.map.configuration().userContentController().removeScriptMessageHandlerForName_('oasa')
            self.map.removeFromSuperview()
            self.map = None
        self.map.evaluateJavaScript_completionHandler_('window.getCamera()', done)

    def do_layout(self, reload=True):
        self.update_tab_ui()
        self.update_timers()
        b = self.content.bounds()
        W, H = b.size.width, b.size.height
        if self.map is not None:
            self.map.setFrame_(NSMakeRect(0, 0, W, H))
        self.drag_bar.setFrame_(NSMakeRect(0, H - DRAG_BAR_H, W, DRAG_BAR_H))
        pw = min(W - 20, 480); px = (W - pw) / 2

        top = 16 if self.fullscreen else TOP_INSET            # no title bar in full screen
        pill_y = H - top - PILL_H + (1 - self.pill_alpha) * 40  # slides up as it fades out
        self.pill.setFrame_(NSMakeRect(px, pill_y, pw, PILL_H))
        self.pill.setAlphaValue_(self.pill_alpha)
        self.pill.setHidden_(self.fullscreen or self.pill_alpha < 0.01)
        chips_on = (self.mode == 'home' and not self.fullscreen and bool(self.chip_buttons)
                    and not self.find_expanded and self.pill_alpha > 0.01)
        self.chips.setHidden_(not chips_on)
        self.chips.setAlphaValue_(self.pill_alpha)
        self.chips.setFrame_(NSMakeRect(px, pill_y - 8 - CHIP_H, pw, CHIP_H))
        x = 0
        for b in self.chip_buttons:  # as many as fit, left to right
            w = b.frame().size.width
            b.setHidden_(x + w > pw)
            b.setFrameOrigin_((x, 0)); x += w + 6
        self.layout_bar(pw)
        self.drag_bar.setHidden_(self.fullscreen)

        # full screen: round buttons on the sides instead of the bar
        fb, fy = FLOAT_BTN, H - 16 - FLOAT_BTN
        for v in self.fs_wraps:
            v.setHidden_(not self.fullscreen)
        self.fs_update_wrap.setHidden_(not (self.fullscreen and self.update_info))
        self.fs_search_wrap.setFrame_(NSMakeRect(16, fy, fb, fb))
        start, final = self.find_rects()
        if not self.find_animating:  # mid-animation the animator owns its frame
            self.find_float.setHidden_(not (self.fullscreen and self.find_open))
            self.find_float.setFrame_(final if self.find_open else start)
        if self.fullscreen:
            self.find.setFrame_(NSMakeRect(14, (fb - 18) / 2, final.size.width - 28, 18))
        x = W - 16 - fb
        for v in [self.fs_refresh_wrap] + ([self.fs_update_wrap] if self.update_info else []) + self.fs_wraps[3:]:
            v.setFrame_(NSMakeRect(x, fy, fb, fb)); x -= fb + 8

        # tell the map how much room the top controls take (fits and zoom buttons stay clear of them)
        inset = int(16 + fb + 8 if self.fullscreen else top + (PILL_H + (CHIP_H + 8 if not self.chips.isHidden() else 0)) * self.pill_alpha + 10)
        if inset != self.top_inset_sent and self.map_ready:
            self.top_inset_sent = inset
            self.evaluate_js(f'window.setTopInset({inset});')

        if self.sheet_override is not None:
            sh = self.sheet_override
        elif self.map_focus:
            sh = FOCUS_SHEET_H
        else:
            sh = self.full_h(H) if self.sheet_full else self.peek_h(H)
        self.sheet_h = sh
        self.sheet.setFrame_(NSMakeRect(px, 10, pw, sh))
        bx, by = px + pw - FLOAT_BTN - 6, 10 + sh + 12
        self.map_locate_wrap.setFrame_(NSMakeRect(bx, by, FLOAT_BTN, FLOAT_BTN))
        self.map_focus_wrap.setFrame_(NSMakeRect(bx, by + FLOAT_BTN + 10, FLOAT_BTN, FLOAT_BTN))
        crowded = by + 2 * FLOAT_BTN + 10 > H - (TOP_INSET + PILL_H) * self.pill_alpha - 12  # sheet almost full
        self.map_locate_wrap.setHidden_(crowded); self.map_focus_wrap.setHidden_(crowded)
        self.handle.setFrame_(NSMakeRect(0, sh - 30, pw, 30))
        # the same gap above the handle, between it and the menu, and (in the slim strip) below the menu
        self.handle_pill.setFrame_(NSMakeRect(pw / 2 - 20, 30 - SHEET_GAP - 5, 40, 5))

        y = sh - 2 * SHEET_GAP - 5
        back_w = 0 if self.mode in ('home', 'search') else 78
        self.back_button.setFrame_(NSMakeRect(SHEET_GAP - 3, y - LINE_MENU_H / 2 - 14, back_w - 6, 28))  # bezel has 3 pt of air
        self.line_menu.setFrame_(NSMakeRect(SHEET_GAP + back_w, y - LINE_MENU_H, pw - 2 * SHEET_GAP - back_w, LINE_MENU_H))
        y -= LINE_MENU_H + 12
        if self.mode == 'home':
            self.home_tabs.setFrame_(NSMakeRect(SHEET_GAP, y - 24, pw - 2 * SHEET_GAP, 24)); y -= 32
        if self.mode != 'line':
            self.explore_heading.setFrame_(NSMakeRect(16, y - 18, pw - 32 - (130 if self.mode in ('home', 'stop') else 0), 16))
            self.locate_button.setFrame_(NSMakeRect(pw - SHEET_GAP - 122, y - 22, 122, 22))
            self.fav_button.setFrame_(NSMakeRect(pw - SHEET_GAP - 30, y - 26, 30, 30))
            if self.mode != 'home':  # home: the tabs already say what the list is
                y -= 26
            self.explore_scroll.setFrame_(self.list_frame(pw, y))
            self.explore_col.setWidth_(self.list_col_w(pw))
            if reload:
                self.explore_table.reloadData()
            y = sh - 34 - 36  # line-mode controls are hidden; keep their frames sane
        self.tabs.setFrame_(NSMakeRect(SHEET_GAP, y - 24, pw - 2 * SHEET_GAP, 24)); y -= 32
        if self.tab == 0:
            self.search.setFrame_(NSMakeRect(SHEET_GAP, y - 26, pw - 2 * SHEET_GAP, 26)); y -= 32
            self.stop_menu.setFrame_(NSMakeRect(SHEET_GAP, y - 28, pw - 2 * SHEET_GAP, 28)); y -= 36
        if self.tab == 1 and len(self.variant_keys) > 1:
            self.variant_menu.setFrame_(NSMakeRect(SHEET_GAP, y - 26, pw - 2 * SHEET_GAP, 26)); y -= 32
        else:
            self.arrival_heading.setFrame_(NSMakeRect(16, y - 18, pw - 32, 16))
            if self.mode == 'line':
                self.locate_button.setFrame_(NSMakeRect(pw - 134, y - 22, 122, 22))
            y -= 26
        area = self.list_frame(pw, y)
        for scroll, col, table in ((self.arr_scroll, self.table_col, self.table),
                                   (self.route_scroll, self.route_col, self.route_table),
                                   (self.near_scroll, self.near_col, self.near_table),
                                   (self.tt_scroll, self.tt_col, self.tt_table)):
            scroll.setFrame_(area)
            col.setWidth_(self.list_col_w(pw))
            if reload:
                table.reloadData()

        # While the sheet is dragged/animated small, hide whatever no longer fits instead of letting it
        # overlap (everything is laid out from the top down; update_tab_ui re-shows it next time).
        for v in (self.home_tabs, self.explore_heading, self.fav_button, self.tabs, self.search, self.stop_menu,
                  self.variant_menu, self.arrival_heading, self.back_button, self.line_menu):
            if not v.isHidden() and v.frame().origin.y < 4:
                v.setHidden_(True)
        for v in (self.explore_scroll, self.arr_scroll, self.route_scroll, self.near_scroll, self.tt_scroll):
            if not v.isHidden() and v.frame().size.height < 40:
                v.setHidden_(True)

        if DEBUG:
            dh = 190
            self.debug_panel.setFrame_(NSMakeRect(px, pill_y - 8 - dh, pw, dh))
            self.debug_stats.setFrame_(NSMakeRect(10, dh - 22, pw - 20, 16))
            self.debug_scroll.setFrame_(NSMakeRect(6, 6, pw - 12, dh - 30))

    # Lists: the table draws each row 6 pt in and each card is 6 pt inside its row, so the scroll view
    # starts 12 pt left of where the cards should; this lines the cards up with the menu and tabs above.
    LIST_PAD = 12

    def list_frame(self, pw, top):
        return NSMakeRect(SHEET_GAP - self.LIST_PAD, 6, pw - 2 * (SHEET_GAP - self.LIST_PAD) - 6, max(1, top - 6))

    def list_col_w(self, pw):
        return pw - 2 * SHEET_GAP + 12  # card width = column - 12

    def bar_frames(self, pw):
        """Top bar: (search capsule frame, [(button, frame)]) collapsed, and the capsule frame expanded."""
        shown = [b for b in self.bar_buttons if not b.isHidden() or (b is self.update_wrap and self.update_info)]
        x, frames = pw, []
        for b in shown:  # right to left: refresh, update, debug
            x -= PILL_H
            frames.append((b, NSMakeRect(x, 0, PILL_H, PILL_H)))
            x -= 8
        return NSMakeRect(0, 0, x, PILL_H), frames, NSMakeRect(0, 0, pw, PILL_H)

    def layout_bar(self, pw, animate=False):
        collapsed, buttons, expanded = self.bar_frames(pw)
        target = expanded if self.find_expanded else collapsed
        w = target.size.width
        self.find_icon.setFrame_(NSMakeRect(14, (PILL_H - 16) / 2, 16, 16))
        self.find_clear.setFrame_(NSMakeRect(w - 30, (PILL_H - 18) / 2, 18, 18))
        self.find_clear.setAutoresizingMask_(1)  # stays at the right edge while the capsule grows
        if not self.fullscreen:
            self.find.setFrame_(NSMakeRect(38, (PILL_H - 18) / 2, max(10, w - 38 - 34), 18))
            self.find.setAutoresizingMask_(2)
        if animate:
            def changes(ctx):
                ctx.setDuration_(0.28); ctx.setAllowsImplicitAnimation_(True)
                self.find_wrap.animator().setFrame_(target)
                for b, fr in buttons:
                    b.animator().setAlphaValue_(0.0 if self.find_expanded else 1.0)
            for b, fr in buttons:
                b.setFrame_(fr)
            NSAnimationContext.runAnimationGroup_completionHandler_(changes, None)
        else:
            self.find_wrap.setFrame_(target)
            for b, fr in buttons:
                b.setFrame_(fr); b.setAlphaValue_(0.0 if self.find_expanded else 1.0)

    def set_find_expanded(self, on):
        if on == self.find_expanded or self.fullscreen:
            return
        self.find_expanded = on
        self.layout_bar(self.pill.frame().size.width, animate=True)

    def controlTextDidChange_(self, notification):
        if notification.object() is self.pal_field:
            self.update_palette()
        if notification.object() is self.find:
            self.find_clear.setHidden_(not str(self.find.stringValue() or ''))
            self.findChanged_(self.find)

    def control_textView_doCommandBySelector_(self, control, textview, selector):
        if control is self.pal_field:  # palette keys: ↑ ↓ move, ⏎ open, Esc close
            if selector == 'moveDown:':
                self.palette_move(1)
            elif selector == 'moveUp:':
                self.palette_move(-1)
            elif selector == 'insertNewline:':
                self.palette_open_item(self.pal_sel)
            elif selector == 'cancelOperation:':
                self.hide_palette()
            else:
                return False
            return True
        if control is self.find and selector == 'cancelOperation:':  # Esc clears the search
            self.clearFind_(None)
            return True
        return False

    def clearFind_(self, sender):
        self.find.setStringValue_('')
        self.find_clear.setHidden_(True)
        self.findChanged_(self.find)
        self.window.makeFirstResponder_(None)
        self.set_find_expanded(False)

    def controlTextDidBeginEditing_(self, notification):
        if notification.object() is self.find:
            self.set_find_expanded(True)

    def controlTextDidEndEditing_(self, notification):
        if notification.object() is not self.find:
            return
        self.set_find_expanded(bool(str(self.find.stringValue() or '').strip()))  # stays wide while a search is on

    def windowDidResize_(self, notification):
        self.do_layout()
        if self.palette_open():
            self.layout_palette()
        self.layout_onboarding()

    def animTick_(self, timer):
        a = self.anim
        if not a:
            timer.invalidate(); self.anim_timer = None
            return
        t = min(1.0, (time.time() - a['t0']) / ANIM_S)
        e = 1 - (1 - t) ** 3
        self.sheet_override = a['start'] + (a['end'] - a['start']) * e
        self.pill_alpha = a['pill_from'] + (a['pill_to'] - a['pill_from']) * e
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
        self.apply_map_prefs()
        if self.map_camera:  # rebuilt after being freed: back to where it was looking
            self.evaluate_js(f'window.setCamera({json.dumps(self.map_camera)});')
            self.map_camera = None
            self.do_layout(reload=False)  # resends the top inset
            if self.mode == 'home':
                self.show_home_stops()
            elif self.mode == 'stop' and self.explore_stop:
                self.show_near_stops(selected=self.explore_stop['id'])
                self.fetch_stop_lines_async(self.explore_stop['id'])  # its buses on the map
            if self.line_data:
                self.push_stops(fit=False)
                self.push_buses(self.bus_markers)
                vid, self.drawn_variant = self.drawn_variant, None
                self.push_route(vid)
            if self.user_loc:
                self.evaluate_js(f'window.setUser({self.user_loc[0]},{self.user_loc[1]});')
            return
        if self.line_data:
            self.push_stops(fit=True)
            self.push_buses(self.bus_markers)
            vid, self.drawn_variant = self.drawn_variant, None
            self.push_route(vid)
        if self.user_loc:
            self.evaluate_js(f'window.setUser({self.user_loc[0]},{self.user_loc[1]});')
        if self.mode == 'home' and self.user_loc is None and not self.loc_tried:
            self.loc_tried = True
            self.start_location()

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
        if sender.indexOfSelectedItem() <= 0:  # 'Browse a line…' placeholder
            if self.mode == 'line':
                self.go_home()
            return
        idx = int(sender.indexOfSelectedItem()) - 1  # item 0 is the placeholder
        line_id = self.lines[idx]['id'] if 0 <= idx < len(self.lines) else None
        if line_id:
            if self.mode != 'line':
                log('mode -> line')
            self.mode = 'line'
            self.do_layout()
            log(f'line selected: {line_id}')
            self.current_line = line_id
            self.selected_stop_id = None
            self.route_variant = None; self.route_variant_user = False
            self.pinned_id = None
            self.status.setStringValue_(t('loading_line', line=line_label(line_id)))
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
            title = self.stop_title(sid, s)
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
        if self.mode != 'line':
            self.open_stop(sid)
            return
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
        title = self.stop_title(sid, stop)
        if title in self.stop_options:
            self.stop_menu.selectItemWithTitle_(title)
        if self.tab == 1:
            self.do_layout()
            self.scroll_route_to_selected()

    def refresh_(self, sender):
        log(f'manual refresh ({self.mode})')
        self.refresh_current()

    def refresh_current(self):
        if self.net_error:  # something failed: retry it (and refresh the rest next time)
            self.retry_failed()
            return
        if self.mode == 'home' and self.home_tab == 1:
            self.fetch_favs_async()
        elif self.mode == 'line' and self.current_line:
            threading.Thread(target=self.fetch_live, args=(self.current_line,), daemon=True).start()
            if self.tab == 3:
                self.rebuild_timetable()  # moves the "next" highlight along
        elif self.mode == 'stop' and self.explore_stop:
            self.fetch_stop_lines_async(self.explore_stop['id'])

    def setLanguage_(self, sender):
        code = str(sender.representedObject())
        if code != i18n.lang():
            log(f'language -> {code}')
            i18n.set_lang(code)
            self.apply_language()

    def findChanged_(self, sender):
        self.on_search_text(str(sender.stringValue() or ''))

    def toggleMapFocus_(self, sender):
        haptic()
        self.toggle_map_focus()

    def find_rects(self):
        """Full-screen search: (start, final) frames. It starts as the round icon and stretches out to the right."""
        b = self.content.bounds()
        W, H, fb = b.size.width, b.size.height, FLOAT_BTN
        fy = H - 16 - fb
        fw = min(340, W - 2 * (16 + fb + 8) - 120)
        return NSMakeRect(16, fy, fb, fb), NSMakeRect(16 + fb + 8, fy, fw, fb)

    def toggleFindFloat_(self, sender):
        """Grow the search field out of the search icon, or shrink it back into it."""
        opening = not self.find_open
        start, final = self.find_rects()
        self.find_open = opening
        self.find_animating = True
        f = self.find_float
        if opening:
            f.setFrame_(start); f.setAlphaValue_(0.0); f.setHidden_(False)

        def changes(ctx):
            ctx.setDuration_(0.28)
            ctx.setAllowsImplicitAnimation_(True)
            f.animator().setFrame_(final if opening else start)
            f.animator().setAlphaValue_(1.0 if opening else 0.0)

        def done():
            self.find_animating = False
            if opening:
                self.window.makeFirstResponder_(self.find)
            else:
                f.setHidden_(True)
                f.setAlphaValue_(1.0)
        NSAnimationContext.runAnimationGroup_completionHandler_(changes, done)

    def windowWillEnterFullScreen_(self, notification):
        log('full screen -> on')
        self.fullscreen = True
        self.find.removeFromSuperview(); self.find_float.addSubview_(self.find)
        self.find.setAutoresizingMask_(0)  # fixed width: the growing capsule reveals it (it clips its contents)
        self.find_open = bool(str(self.find.stringValue() or ''))  # keep an active search visible
        self.do_layout()

    def windowWillExitFullScreen_(self, notification):
        log('full screen -> off')
        self.fullscreen = False
        self.find.removeFromSuperview(); self.find_wrap.addSubview_(self.find)
        self.find_open = False
        self.do_layout()

    def arrivalsClicked_(self, sender):
        r = int(sender.clickedRow())
        rows = self.table_source.rows
        if 0 <= r < len(rows) and rows[r].get('kind') == 'alert':
            self.open_link(rows[r]['link'])

    def open_link(self, url):
        log(f'open {url}')
        NSWorkspace.sharedWorkspace().openURL_(NSURL.URLWithString_(url))

    def homeTabChanged_(self, sender):
        haptic()
        self.set_home_tab(int(sender.selectedSegment()))

    def toggleFavorite_(self, sender):
        haptic()
        self.toggle_favorite()

    def openUpdate_(self, sender):
        if self.update_info:
            NSWorkspace.sharedWorkspace().openURL_(NSURL.URLWithString_(self.update_info[1]))

    def checkUpdates_(self, sender):
        threading.Thread(target=self.check_updates, args=(True,), daemon=True).start()

    def check_updates(self, manual):
        try:
            self.results.put(('update', updates.check(), manual))
        except Exception as e:
            log(f'update check failed: {e}', 'WARN')
            if manual:
                self.results.put(('update_failed',))

    def backClicked_(self, sender):
        haptic()
        self.go_back()

    def exploreClicked_(self, sender):
        r = int(sender.clickedRow())
        rows = self.explore_source.rows
        if not 0 <= r < len(rows):
            return
        row = rows[r]
        kind = row.get('kind')
        if kind == 'alert':
            self.open_link(row['link'])
        elif row.get('retry'):
            self.retry_failed()
        elif kind in ('near', 'fav'):
            haptic(); self.open_stop(row['sid'], row.get('stop'))
        elif kind == 'stopline':
            haptic()
            if row.get('search'):  # a line from the search results: open it on its own
                self.close_search()
                self.explore_stop = None
            self.open_line_at_stop(row['line'])

    # ---- Pin / follow a bus ---------------------------------------------------
    def pinBus_(self, sender):
        self.toggle_pin(str(sender.identifier()))

    def toggle_pin(self, bid):
        if self.mode == 'stop' and bid in self.stop_bus_line:  # a bus on the stop screen: open its line
            self.pending_pin = bid
            self.open_line_at_stop(self.stop_bus_line[bid])
            return
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

    def update_timers(self):
        """Run the 1 s countdown tick only while its countdowns are on screen."""
        want = self.visible and self.mode in ('line', 'search', 'home')
        want = want and any(r.get('eta_s') is not None for r in self.table_source.rows + self.near_source.rows)
        if want and self.tick_timer is None:
            from Foundation import NSTimer
            self.tick_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(1.0, self, 'tick:', None, True)
            self.tick_timer.setTolerance_(0.1)
        elif not want and self.tick_timer is not None:
            self.tick_timer.invalidate()
            self.tick_timer = None

    # The window leaves or returns to the screen. Occlusion covers being covered, but isn't always sent,
    # so hiding the app, minimising and closing report it too.
    def windowDidChangeOcclusionState_(self, notification):
        self.set_visible(bool(self.window.occlusionState() & 2))  # NSWindowOcclusionStateVisible

    def applicationDidHide_(self, notification):
        self.set_visible(False)

    def applicationDidUnhide_(self, notification):
        self.set_visible(True)

    def windowDidMiniaturize_(self, notification):
        self.set_visible(False)

    def windowDidDeminiaturize_(self, notification):
        self.set_visible(True)

    def windowWillClose_(self, notification):
        self.set_visible(False)

    def windowDidBecomeKey_(self, notification):
        self.set_visible(True)

    def set_visible(self, vis):
        """Minimised, hidden, closed or covered: pause everything; back on screen: catch up at once."""
        if vis == self.visible:
            return
        self.visible = vis
        log(f'window {"visible" if vis else "hidden"}: {"resuming" if vis else "pausing"}')
        self.evaluate_js(f'window.setPaused({json.dumps(not vis)});')
        self.update_timers()
        from Foundation import NSTimer
        if self.free_timer is not None:
            self.free_timer.invalidate(); self.free_timer = None
        if not vis:
            self.free_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                MAP_FREE_AFTER_S, self, 'freeMap:', None, False)
        elif self.map is None:
            log('window back: rebuilding the map')
            self.make_map()
        if vis and time.time() - self.last_refresh > 10:
            self.last_refresh = time.time()
            self.refresh_current()

    def systemDidWake_(self, notification):
        log('mac woke up: refreshing')
        self.last_refresh = time.time()
        if self.visible:
            self.refresh_current()
        self.poll_glance()

    def tick_(self, timer):
        """Once a second: live ETA countdowns between data refreshes."""
        now = time.time()
        for r in self.table_source.rows:
            lab = r.get('eta_label')
            if lab is not None and r.get('eta_s') is not None:
                left = r['eta_s'] - (now - r['t0'])
                m = int(max(0, left) // 60)
                if r.get('shown_m', m) != m:
                    roll(lab)  # the minute ticked over
                r['shown_m'] = m
                lab.setStringValue_(fmt_eta(left))
        for r in self.near_source.rows:
            lab = r.get('next_label')
            if lab is not None and r.get('eta_s') is not None:
                lab.setStringValue_(t('bus_eta', id=r['bus_id'], eta=fmt_eta(r['eta_s'] - (now - r['t0']))))

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
            what = {'near_stops': 'nearby', 'stop_lines': 'stop_lines', 'lines': 'lines', 'line': 'line',
                    'live': 'live', 'stop_index': 'index'}.get(kind)
            if what:
                self.succeeded(what)
            if kind == 'refresh_request':
                if not self.visible:
                    continue  # hidden: nothing to show (the menu bar polls favourites itself)
                self.last_refresh = time.time()
                self.refresh_current()
                if self.lines and time.time() - self.alerts_at > ALERTS_EVERY_S:
                    self.fetch_alerts_async()
            elif kind == 'alerts':
                self.on_alerts(item[1])
            elif kind == 'timetable':
                self.on_timetable(item[1], item[2])
            elif kind == 'net_error':
                self.on_net_error(item[1], item[2], item[3])
            elif kind == 'fav_lines':
                self.on_fav_lines(item[1], item[2])
            elif kind == 'stop_index':
                self.stop_idx = item[1]
                if self.mode == 'search':
                    self.rebuild_explore()
            elif kind == 'update':
                info, manual = item[1], item[2]
                if info:
                    self.update_info = info
                    self.update_button.setToolTip_(t('update_available', v=info[0]))
                    self.update_wrap.setHidden_(False)
                    self.fs_update_btn.setToolTip_(t('update_available', v=info[0]))
                    self.do_layout(reload=False)
                elif manual:
                    self.status.setStringValue_(t('up_to_date', v=__version__))
            elif kind == 'update_failed':
                self.status.setStringValue_(t('update_failed'))
            elif kind == 'near_stops':
                self.on_near_stops(item[1], item[2], item[3])
            elif kind == 'stop_lines':
                self.on_stop_lines(item[1], item[2], item[3])
            elif kind == 'error':
                self.status.setStringValue_(t('error', msg=item[1][:120]))
            elif kind == 'lines':
                self.lines = item[1].get('lines', [])
                log(f'lines loaded: {len(self.lines)}')
                self.fill_line_menu()
                if self.stop_idx is None:
                    self.build_index_async()
                self.fetch_alerts_async()
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
                self.last_live_ok = datetime.now()
                if self.tab == 3:
                    self.fetch_timetable_async()
                self.do_layout()
                self.status.setStringValue_(t('line_live', line=line_label(line_id), n=len(self.live.get('vehicles', []))))
                if self.pending_pin:
                    bid, self.pending_pin = self.pending_pin, None
                    if any(str(v.get('id')) == bid for v in self.live.get('vehicles', [])):
                        self.pinned_id = None
                        self.toggle_pin(bid)
                if self.pending_stop:
                    sid, self.pending_stop = self.pending_stop, None
                    if sid in self.line_data.get('stops', {}):
                        self.select_stop(sid)
                    else:
                        log(f'stop {sid} not on line {line_id}', 'WARN')
            elif kind == 'live':
                _, line_id, live = item
                if line_id != self.current_line:
                    log(f'dropped stale live response {line_id} (current {self.current_line})', 'WARN')
                    continue
                self.render_arrivals(live)
                self.last_live_ok = datetime.now()
                self.status.setStringValue_(t('line_updated', line=line_label(line_id), time=f'{datetime.now().astimezone():%H:%M:%S}'))
        if DEBUG:
            self.update_debug_panel()
