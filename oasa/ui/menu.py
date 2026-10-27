"""The menu bar. On macOS keyboard shortcuts (⌘Q, ⌘W, ⌘C…) only work through menu items."""
from AppKit import NSApplication, NSMenu, NSMenuItem

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
    _item(m, f'About {app_name}', 'orderFrontStandardAboutPanel:')
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, f'Hide {app_name}', 'hide:', 'h')
    _item(m, 'Hide Others', 'hideOtherApplications:', 'h', mods=CMD | OPT)
    _item(m, 'Show All', 'unhideAllApplications:')
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, f'Quit {app_name}', 'terminate:', 'q')

    m = _submenu(bar, 'Edit')  # makes ⌘C/⌘V/⌘A work in the stop search field
    _item(m, 'Undo', 'undo:', 'z')
    _item(m, 'Redo', 'redo:', 'z', mods=CMD | SHIFT)
    m.addItem_(NSMenuItem.separatorItem())
    _item(m, 'Cut', 'cut:', 'x')
    _item(m, 'Copy', 'copy:', 'c')
    _item(m, 'Paste', 'paste:', 'v')
    _item(m, 'Select All', 'selectAll:', 'a')

    m = _submenu(bar, 'View')
    _item(m, 'Refresh', 'refresh:', 'r', target=delegate)
    _item(m, 'Locate Me', 'locateMe:', 'l', target=delegate)
    _item(m, 'Back', 'backClicked:', '[', target=delegate)

    m = _submenu(bar, 'Window')
    _item(m, 'Minimize', 'performMiniaturize:', 'm')
    _item(m, 'Zoom', 'performZoom:')
    _item(m, 'Close', 'performClose:', 'w')
    app.setWindowsMenu_(m)

    app.setMainMenu_(bar)
