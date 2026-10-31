"""⌘K quick switcher: a floating palette over the window to jump to any line or stop by keyboard.

Empty, it lists your recent and favourite stops; typing searches lines (number or name) and every
stop (Greek or Latin letters). ↑/↓ move, ⏎ opens, Esc or a click outside closes it.
The Objective-C callables (paletteRowClicked_, paletteBackdrop_) live on the app class in core.py."""
from AppKit import NSButton, NSTextAlignmentCenter, NSColor, NSFont, NSImage, NSImageView, NSMakeRect, NSTextField, NSView
from oasa import favorites, recents, stop_index
from oasa.debug import log
from oasa.i18n import line_label, name, t
from oasa.ui import motion
from oasa.ui.widgets import glass, label, solid

PAL_W, FIELD_H, ROW_H, MAX_ROWS = 520, 48, 44, 8


class PaletteMixin:
    def build_palette(self):
        self.pal_items = []
        self.pal_sel = 0
        # a see-through backdrop over everything: clicking it closes the palette
        self.pal_backdrop = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 100, 100))
        self.pal_backdrop.setBordered_(False); self.pal_backdrop.setTitle_('')
        self.pal_backdrop.setTarget_(self); self.pal_backdrop.setAction_('paletteBackdrop:')
        self.pal_backdrop.setWantsLayer_(True)
        self.pal_backdrop.layer().setBackgroundColor_(NSColor.blackColor().colorWithAlphaComponent_(0.25).CGColor())
        self.pal = glass(NSMakeRect(0, 0, PAL_W, FIELD_H), 16)
        self.pal_icon = ico = NSImageView.alloc().initWithFrame_(NSMakeRect(16, (FIELD_H - 18) / 2, 18, 18))
        ico.setImage_(NSImage.imageWithSystemSymbolName_accessibilityDescription_('magnifyingglass', None))
        ico.setContentTintColor_(NSColor.secondaryLabelColor())
        ico.setAutoresizingMask_(8)  # stays at the top while the palette grows
        self.pal_field = NSTextField.alloc().initWithFrame_(NSMakeRect(44, (FIELD_H - 22) / 2, PAL_W - 60, 22))
        self.pal_field.setBezeled_(False); self.pal_field.setBordered_(False); self.pal_field.setDrawsBackground_(False)
        self.pal_field.setFocusRingType_(1); self.pal_field.setFont_(NSFont.systemFontOfSize_(17))
        self.pal_field.setPlaceholderString_(t('pal_placeholder'))
        self.pal_field.setDelegate_(self); self.pal_field.setAutoresizingMask_(8 | 2)
        self.pal_rows = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, PAL_W, 0))
        for v in (ico, self.pal_field, self.pal_rows):
            self.pal.addSubview_(v)
        for v in (self.pal_backdrop, self.pal):
            v.setHidden_(True)
            self.content.addSubview_(v)

    def palette_open(self):
        return not self.pal.isHidden()

    def show_palette(self):
        if self.palette_open():
            self.window.makeFirstResponder_(self.pal_field)
            return
        log('palette open')
        self.pal_field.setStringValue_('')
        self.pal_field.setPlaceholderString_(t('pal_placeholder'))
        for v in (self.pal_backdrop, self.pal):
            v.removeFromSuperview(); self.content.addSubview_(v)  # on top of everything
            v.setHidden_(False)
        self.update_palette()
        motion.appear(self.pal)
        self.window.makeFirstResponder_(self.pal_field)

    def hide_palette(self):
        for v in (self.pal_backdrop, self.pal):
            v.setHidden_(True)
        self.window.makeFirstResponder_(None)

    def palette_results(self, q):
        q = q.strip()
        if not q:  # recent and favourite stops, so ⌘K ⏎ goes straight back to the last one
            seen, out = set(), []
            for kind, lst in (('recent', recents.load()), ('fav', favorites.load())):
                for s in lst:
                    if s['id'] not in seen:
                        seen.add(s['id'])
                        out.append({'kind': 'stop', 'tag': kind, 'stop': s,
                                    'title': name(s.get('name'), s.get('name_en')) or s['id'],
                                    'sub': t('stop_n', id=s['id'])})
            return out[:MAX_ROWS]
        qn = stop_index.normalize(q)
        out = []
        for ln in self.lines:
            lid = stop_index.normalize(ln['id'])
            if lid.startswith(qn) or (len(qn) > 2 and qn in stop_index.normalize(name(ln.get('name'), ln.get('name_en')))):
                out.append({'kind': 'line', 'line': ln['id'], 'title': name(ln.get('name'), ln.get('name_en')),
                            'exact': lid == qn})
        out.sort(key=lambda r: not r['exact'])
        out = out[:4]
        if self.stop_idx:
            for sid, s in stop_index.search(self.stop_idx, q)[:MAX_ROWS - len(out)]:
                out.append({'kind': 'stop', 'tag': '', 'stop': {'id': sid, 'name': s['name'], 'lat': s['lat'], 'lon': s['lon']},
                            'title': name(s['name']) or sid,
                            'sub': t('lines_list', list=', '.join(line_label(x) for x in s['lines'][:6]))})
        return out

    def update_palette(self):
        self.pal_items = self.palette_results(str(self.pal_field.stringValue() or ''))
        self.pal_sel = 0
        self.draw_palette()

    def draw_palette(self):
        for v in list(self.pal_rows.subviews()):
            v.removeFromSuperview()
        items = self.pal_items
        PW = self.palette_width()  # the panel's real width: rows were drawn for 520 and ran past a narrow window
        n = len(items) if items else 1
        rows_h = n * ROW_H + 8
        for i, it in enumerate(items):
            y = rows_h - 4 - (i + 1) * ROW_H
            row = NSView.alloc().initWithFrame_(NSMakeRect(6, y, PW - 12, ROW_H))
            if i == self.pal_sel:
                row.addSubview_(solid(NSMakeRect(0, 2, PW - 12, ROW_H - 4),
                                      NSColor.controlAccentColor().colorWithAlphaComponent_(0.28), 10))
            if it['kind'] == 'line':
                badge = solid(NSMakeRect(10, (ROW_H - 24) / 2, 50, 24), NSColor.systemBlueColor(), 7)
                num = label(line_label(it['line']), 13, True, NSColor.whiteColor(), rounded=True)
                num.setFrame_(NSMakeRect(0, 4, 50, 16)); num.setAlignment_(NSTextAlignmentCenter)
                badge.addSubview_(num); row.addSubview_(badge)
                title = label(it['title'], 13, True); title.setFrame_(NSMakeRect(72, (ROW_H - 17) / 2, PW - 100, 17))
                row.addSubview_(title)
            else:
                sym = {'recent': 'clock.arrow.circlepath', 'fav': 'star.fill'}.get(it['tag'], 'mappin.circle.fill')
                ico = NSImageView.alloc().initWithFrame_(NSMakeRect(24, (ROW_H - 18) / 2, 18, 18))
                ico.setImage_(NSImage.imageWithSystemSymbolName_accessibilityDescription_(sym, None))
                ico.setContentTintColor_(NSColor.systemYellowColor() if it['tag'] == 'fav' else NSColor.secondaryLabelColor())
                title = label(it['title'], 13, True); title.setFrame_(NSMakeRect(72, 22, PW - 100, 17))
                sub = label(it['sub'], 11, color=NSColor.secondaryLabelColor()); sub.setFrame_(NSMakeRect(72, 6, PW - 100, 14))
                for v in (ico, title, sub):
                    row.addSubview_(v)
            hit = NSButton.alloc().initWithFrame_(row.bounds())
            hit.setBordered_(False); hit.setTitle_(''); hit.setTransparent_(True)
            hit.setTarget_(self); hit.setAction_('paletteRowClicked:'); hit.setTag_(i)
            row.addSubview_(hit)
            self.pal_rows.addSubview_(row)
        if not items:
            msg = label(t('pal_empty') if str(self.pal_field.stringValue() or '').strip() else t('pal_hint'),
                        12, color=NSColor.secondaryLabelColor())
            msg.setFrame_(NSMakeRect(20, (rows_h - 16) / 2, PW - 40, 16)); msg.setAlignment_(NSTextAlignmentCenter)
            self.pal_rows.addSubview_(msg)
        self.pal_rows.setFrame_(NSMakeRect(0, 0, PW, rows_h))
        self.layout_palette()

    def palette_width(self):
        return min(PAL_W, self.content.bounds().size.width - 32)

    def layout_palette(self):
        b = self.content.bounds()
        W, H = b.size.width, b.size.height
        w = self.palette_width()
        h = FIELD_H + self.pal_rows.frame().size.height
        self.pal_backdrop.setFrame_(b)
        self.pal.setFrame_(NSMakeRect((W - w) / 2, H - 70 - h, w, h))
        # the field row is always the top FIELD_H points (placed here, after the panel's height is known:
        # placing it before, on a palette left tall from last time, put it at the bottom over the rows)
        self.pal_icon.setFrame_(NSMakeRect(16, h - FIELD_H + (FIELD_H - 18) / 2, 18, 18))
        self.pal_field.setFrame_(NSMakeRect(44, h - FIELD_H + (FIELD_H - 22) / 2, w - 60, 22))
        self.pal_rows.setFrame_(NSMakeRect(0, 0, w, self.pal_rows.frame().size.height))

    def palette_move(self, d):
        if self.pal_items:
            self.pal_sel = (self.pal_sel + d) % len(self.pal_items)
            self.draw_palette()

    def palette_open_item(self, i):
        if not (0 <= i < len(self.pal_items)):
            return
        it = self.pal_items[i]
        self.hide_palette()
        log(f'palette -> {it["kind"]} {it.get("line") or it["stop"]["id"]}')
        if it['kind'] == 'line':
            idx = next((k for k, ln in enumerate(self.lines) if ln['id'] == it['line']), None)
            if idx is not None:
                self.close_search()
                self.line_menu.selectItemAtIndex_(idx + 1)  # item 0 is the 'browse a line' placeholder
                self.lineChanged_(self.line_menu)
        else:
            self.open_stop(it['stop']['id'], dict(it['stop']))
