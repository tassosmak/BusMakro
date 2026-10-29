"""Settings window (BusMakro → Settings…, ⌘,): a handful of choices, nothing more.

    General   language · show in menu bar · show recent stops (+ clear them)
    Map       style (match system / light / dark) · 3D buildings

Every control acts at once, and the menus are rebuilt so their checkmarks agree.
The Objective-C callable (settingChanged_) lives on the app class in core.py."""
from AppKit import (
    NSBackingStoreBuffered, NSButton, NSColor, NSMakeRect, NSPopUpButton, NSView, NSWindow,
)
from Foundation import NSUserDefaults
from oasa import i18n, recents
from oasa.debug import log
from oasa.i18n import t
from oasa.ui.menu import install_menu
from oasa.ui.widgets import label

ROW, PAD = 32, 24   # row height, the window's side margin (section titles and labels start there)
STYLES = ('system', 'light', 'dark')
TAG_LANG, TAG_MENUBAR, TAG_RECENTS, TAG_CLEAR, TAG_STYLE, TAG_3D = range(6)


def _caps(text):
    import unicodedata
    return ''.join(ch for ch in unicodedata.normalize('NFD', text.upper()) if unicodedata.category(ch) != 'Mn')


def show_recents():
    d = NSUserDefaults.standardUserDefaults()
    return True if d.objectForKey_('showRecents') is None else bool(d.boolForKey_('showRecents'))


class SettingsMixin:
    def show_settings(self):
        if getattr(self, 'settings_win', None) is None:
            self.settings_win = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                NSMakeRect(0, 0, 440, 300), 1 | 2, NSBackingStoreBuffered, False)  # titled, closable
            self.settings_win.setReleasedWhenClosed_(False)
            self.settings_win.center()
        self.settings_win.setTitle_(t('set_title'))
        self.draw_settings()
        self.settings_win.makeKeyAndOrderFront_(None)

    def draw_settings(self):
        d = NSUserDefaults.standardUserDefaults()
        rows = []  # (section title) or (label, control)

        def popup(items, selected, tag):
            p = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 200, 26))
            for title, value in items:
                p.addItemWithTitle_(title); p.lastItem().setRepresentedObject_(value)
            p.selectItemAtIndex_([v for _, v in items].index(selected))
            p.setTarget_(self); p.setAction_('settingChanged:'); p.setTag_(tag)
            return p

        def check(title, on, tag):
            c = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 260, 22))
            c.setButtonType_(3); c.setTitle_(title); c.setState_(1 if on else 0)  # a checkbox
            c.setTarget_(self); c.setAction_('settingChanged:'); c.setTag_(tag)
            return c

        clear = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 170, 26))
        clear.setBezelStyle_(1); clear.setTitle_(t('m_clear_recents'))
        clear.setTarget_(self); clear.setAction_('settingChanged:'); clear.setTag_(TAG_CLEAR)
        clear.setEnabled_(bool(recents.load()))
        rows += [t('set_general'),
                 (t('m_language'), popup([(i18n.LANG_NAMES[c], c) for c in i18n.LANGS], i18n.lang(), TAG_LANG)),
                 ('', check(t('m_menubar'), self.status_item is not None, TAG_MENUBAR)),
                 ('', check(t('set_show_recents'), show_recents(), TAG_RECENTS)),
                 ('', clear),
                 t('set_map'),
                 (t('m_map_style'), popup([(t('style_' + s), s) for s in STYLES],
                                          {'night': 'dark'}.get(d.stringForKey_('mapStyle') or 'system', d.stringForKey_('mapStyle') or 'system'),
                                          TAG_STYLE)),
                 ('', check(t('m_3d'), bool(d.boolForKey_('map3d')), TAG_3D))]
        for r in rows:  # every control at its natural size, so no title is cut off
            if not isinstance(r, str):
                r[1].sizeToFit()
                if isinstance(r[1], NSPopUpButton):
                    f = r[1].frame(); r[1].setFrameSize_((max(200, f.size.width), f.size.height))
        # labels start on the section titles' edge; the controls follow right after the longest label
        labels = [label(r[0] + ':', 13) for r in rows if not isinstance(r, str) and r[0]]
        left = PAD + max(l.fittingSize().width for l in labels) + 10
        width = left + max(r[1].frame().size.width for r in rows if not isinstance(r, str)) + PAD
        h = 20 + sum(30 if isinstance(r, str) else ROW for r in rows)
        content = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        y = h - 14
        for r in rows:
            if isinstance(r, str):  # section title (Greek capitals drop their accents, as Greek typography does)
                lab = label(_caps(r), 11, True, NSColor.secondaryLabelColor())
                lab.setFrame_(NSMakeRect(PAD, y - 22, width - 2 * PAD, 15)); content.addSubview_(lab)
                y -= 30
                continue
            text, ctl = r
            mid = y - ROW / 2  # label and control share this centre line
            f = ctl.frame()
            ctl.setFrameOrigin_((left, round(mid - f.size.height / 2)))
            # menus, checkboxes and buttons draw their visible edge a different few points inside
            # their frame: line up what you see, not the frames
            inset = ctl.alignmentRectForFrame_(ctl.frame()).origin.x - ctl.frame().origin.x
            ctl.setFrameOrigin_((left - inset, ctl.frame().origin.y))
            content.addSubview_(ctl)
            if text:
                lab = label(text + ':', 13)
                lab.sizeToFit()
                lh = lab.frame().size.height
                lab.setFrame_(NSMakeRect(PAD, round(mid - lh / 2) + 1, left - PAD - 6, lh)); content.addSubview_(lab)
            y -= ROW
        self.settings_win.setContentView_(content)
        self.settings_win.setContentSize_((width, h))

    def setting_changed(self, sender):
        tag = int(sender.tag())
        d = NSUserDefaults.standardUserDefaults()
        if tag == TAG_LANG:
            code = str(sender.selectedItem().representedObject())
            if code != i18n.lang():
                i18n.set_lang(code)
                self.apply_language()
                self.settings_win.setTitle_(t('set_title'))
        elif tag == TAG_MENUBAR:
            self.show_menu_bar(bool(sender.state()))
        elif tag == TAG_RECENTS:
            d.setBool_forKey_(bool(sender.state()), 'showRecents')
            self.rebuild_chips()
        elif tag == TAG_CLEAR:
            self.clear_recents()
        elif tag == TAG_STYLE:
            d.setObject_forKey_(str(sender.selectedItem().representedObject()), 'mapStyle')
            self.apply_map_prefs()
        elif tag == TAG_3D:
            d.setBool_forKey_(bool(sender.state()), 'map3d')
            self.apply_map_prefs()
        log(f'setting {tag} changed')
        install_menu('BusMakro', self)  # keep the menus' checkmarks in step
        self.draw_settings()

    def clear_recents(self):
        recents.clear()
        self.rebuild_chips()
        if getattr(self, 'settings_win', None) is not None and self.settings_win.isVisible():
            self.draw_settings()
        log('recent stops cleared')
