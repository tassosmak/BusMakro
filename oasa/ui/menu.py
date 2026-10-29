"""The menu bar. On macOS keyboard shortcuts (⌘Q, ⌘W, ⌘C…) only work through menu items."""
from AppKit import NSApplication, NSMenu, NSMenuItem
from oasa.i18n import LANG_NAMES, LANGS, lang, t

CMD, SHIFT, OPT = 1 << 20, 1 << 17, 1 << 19   # NSEventModifierFlag Command / Shift / Option


def _item(menu, title, action, key='', target=None, mods=CMD):
    it = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, action, key)
    it.setKeyEquivalentModifierMask_(mods)
    if target is not None:
        it.setTarget_(target)
    menu.addItem_(it)
    return it


def _submenu(bar, title):
    top = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, None, '')
    menu = NSMenu.alloc().initWithTitle_(title)
    top.setSubmenu_(menu)
    bar.addItem_(top)
    return menu


def install_menu(app_name, delegate):
    """Build the standard menus. Items without a target go to the first responder (search field, window…)."""
    app = NSApplication.sharedApplication()
    bar = NSMenu.alloc().init()

    m = _submenu(bar, app_name)
    _item(m, t('m_about', app=app_name), 'orderFrontStandardAboutPanel:')
    _item(m, t('m_check_updates'), 'checkUpdates:', target=delegate)
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, t('m_hide', app=app_name), 'hide:', 'h')
    _item(m, t('m_hide_others'), 'hideOtherApplications:', 'h', mods=CMD | OPT)
    _item(m, t('m_show_all'), 'unhideAllApplications:')
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, t('m_quit', app=app_name), 'terminate:', 'q')

    m = _submenu(bar, t('m_edit'))  # makes ⌘C/⌘V/⌘A work in the stop search field
    _item(m, t('m_undo'), 'undo:', 'z')
    _item(m, t('m_redo'), 'redo:', 'z', mods=CMD | SHIFT)
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, t('m_cut'), 'cut:', 'x')
    _item(m, t('m_copy'), 'copy:', 'c')
    _item(m, t('m_paste'), 'paste:', 'v')
    _item(m, t('m_select_all'), 'selectAll:', 'a')

    m = _submenu(bar, t('m_view'))
    _item(m, t('m_refresh'), 'refresh:', 'r', target=delegate)
    _item(m, t('m_locate'), 'locateMe:', 'l', target=delegate)
    _item(m, t('m_back'), 'backClicked:', '[', target=delegate)
    m.addItem_(NSMenuItem.separatorItem())
    from Foundation import NSUserDefaults
    prefs = NSUserDefaults.standardUserDefaults()
    styles = NSMenu.alloc().initWithTitle_(t('m_map_style'))
    current = {'night': 'dark'}.get(prefs.stringForKey_('mapStyle') or 'system', prefs.stringForKey_('mapStyle') or 'system')
    for code in ('system', 'light', 'dark'):
        it = _item(styles, t('style_' + code), 'setMapStyle:', target=delegate)
        it.setRepresentedObject_(code)
        it.setState_(1 if code == current else 0)
    top = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(t('m_map_style'), None, '')
    top.setSubmenu_(styles)
    m.addItem_(top)
    _item(m, t('m_3d'), 'toggle3D:', '3', target=delegate).setState_(1 if prefs.boolForKey_('map3d') else 0)
    m.addItem_(NSMenuItem.separatorItem())
    it = _item(m, t('m_menubar'), 'toggleMenuBar:', target=delegate)
    it.setState_(1 if getattr(delegate, 'status_item', None) is not None or prefs.objectForKey_('menuBar') is None
                 or prefs.boolForKey_('menuBar') else 0)
    m.addItem_(NSMenuItem.separatorItem())
    langs = NSMenu.alloc().initWithTitle_(t('m_language'))
    for code in LANGS:
        it = _item(langs, LANG_NAMES[code], 'setLanguage:', target=delegate)
        it.setRepresentedObject_(code)
        it.setState_(1 if code == lang() else 0)  # checkmark on the current language
    top = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(t('m_language'), None, '')
    top.setSubmenu_(langs)
    m.addItem_(top)

    m = _submenu(bar, t('m_window'))
    _item(m, t('m_minimize'), 'performMiniaturize:', 'm')
    _item(m, t('m_zoom'), 'performZoom:')
    _item(m, t('m_close'), 'performClose:', 'w')
    app.setWindowsMenu_(m)

    app.setMainMenu_(bar)
