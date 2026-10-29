"""The menu bar item: "🚌 046 · 4′", the soonest live bus at your favourite stops; its menu lists
them all. Fed by the favourites poll (every GLANCE_EVERY_S while it is shown)."""
import time
from AppKit import (
    NSStatusBar, NSMenu, NSMenuItem, NSImage,
)
from Foundation import NSUserDefaults
from oasa import favorites, history
from oasa.debug import log
from oasa.i18n import line_label, name, t

GLANCE_EVERY_S = 30
_MENUBAR_KEY = 'menuBar'


def _pref(key, default):
    d = NSUserDefaults.standardUserDefaults()
    return default if d.objectForKey_(key) is None else bool(d.boolForKey_(key))


def _set_pref(key, on):
    NSUserDefaults.standardUserDefaults().setBool_forKey_(bool(on), key)


class GlanceMixin:
    def setup_glance(self):
        if _pref(_MENUBAR_KEY, True):
            self.show_menu_bar(True)
        self.poll_glance()

    def glance_on(self):
        return self.status_item is not None

    def poll_glance(self):
        if self.glance_on():
            self.fetch_favs_async()

    def next_buses(self, sid):
        """[(line, minutes now)] of live buses at a favourite stop, soonest first (learned ETA applied)."""
        lines = self.fav_lines.get(sid)
        if lines is None:
            return None
        gone = (time.time() - self.fav_at.get(sid, time.time())) / 60
        out = []
        for ln in lines:
            for m in ln['etas'][:2]:
                learned = history.learned_min(ln['line'], m)
                left = (m if learned is None else learned) - gone
                if left > -0.5:
                    out.append((ln['line'], max(0, round(left))))
        return sorted(out, key=lambda x: x[1])

    def update_glance(self):
        self.update_menu_bar()

    # ---- Menu bar ---------------------------------------------------------------
    def show_menu_bar(self, on):
        _set_pref(_MENUBAR_KEY, on)
        if on and self.status_item is None:
            self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(-1)  # variable length
            img = NSImage.imageWithSystemSymbolName_accessibilityDescription_('bus.fill', 'BusMakro')
            if img is not None:
                img.setTemplate_(True)
                self.status_item.button().setImage_(img)
                self.status_item.button().setImagePosition_(2)  # image left of the title
            self.update_menu_bar()
            self.poll_glance()
        elif not on and self.status_item is not None:
            NSStatusBar.systemStatusBar().removeStatusItem_(self.status_item)
            self.status_item = None
        log(f'menu bar -> {on}')

    def update_menu_bar(self):
        if self.status_item is None:
            return
        favs = favorites.load()
        best = None
        menu = NSMenu.alloc().init()
        menu.setAutoenablesItems_(False)
        if not favs:
            it = menu.addItemWithTitle_action_keyEquivalent_(t('mb_no_favs'), None, '')
            it.setEnabled_(False)
        for f in favs:
            head = menu.addItemWithTitle_action_keyEquivalent_(name(f.get('name'), f.get('name_en')) or f['id'], 'menuBarStop:', '')
            head.setTarget_(self); head.setRepresentedObject_(f['id'])
            buses = self.next_buses(f['id'])
            if buses is None:
                rows = [t('mb_loading')]
            else:
                rows = [f'{line_label(line)}   {t("min", n=m)}' for line, m in buses[:4]] or [t('mb_none_live')]
                if buses and (best is None or buses[0][1] < best[1]):
                    best = buses[0]
            for r in rows:
                it = menu.addItemWithTitle_action_keyEquivalent_(r, 'menuBarStop:', '')
                it.setTarget_(self); it.setRepresentedObject_(f['id']); it.setIndentationLevel_(1)
            menu.addItem_(NSMenuItem.separatorItem())
        for title, action, key in ((t('mb_open'), 'menuBarOpen:', ''),
                                   (t('m_quit', app='BusMakro'), 'terminate:', 'q')):
            it = menu.addItemWithTitle_action_keyEquivalent_(title, action, key)
            if action != 'terminate:':
                it.setTarget_(self)
        self.status_item.setMenu_(menu)
        self.status_item.button().setTitle_(f' {line_label(best[0])} · {best[1]}′' if best else '')

    def open_from_glance(self, sid=None):
        from AppKit import NSApplication
        self.window.makeKeyAndOrderFront_(None)
        self.set_visible(True)
        NSApplication.sharedApplication().activateIgnoringOtherApps_(True)
        f = next((f for f in favorites.load() if f['id'] == sid), None) if sid else None
        if f:
            self.close_search()
            self.open_stop(f['id'], dict(f))
