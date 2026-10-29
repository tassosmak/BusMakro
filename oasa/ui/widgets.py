"""Small AppKit helpers and the list-row (card) views."""
import time
from AppKit import (
    NSMakeRect, NSColor, NSFont, NSFontWeightSemibold, NSButton, NSTextField, NSView,
    NSVisualEffectView, NSVisualEffectBlendingModeWithinWindow,
    NSVisualEffectStateActive, NSTextAlignmentRight, NSTextAlignmentCenter,
    NSFontDescriptorSystemDesignRounded, NSFontFeatureSettingsAttribute, NSImage, NSImageSymbolConfiguration,
    NSFontFeatureTypeIdentifierKey, NSFontFeatureSelectorIdentifierKey,
)
try:  # trackpad haptics (optional)
    from AppKit import NSHapticFeedbackManager
except Exception:  # pragma: no cover
    NSHapticFeedbackManager = None
from oasa.config import TIMES_PER_ROW, ALERT_ROW_H, BUS_ROW_H, LINE_ROW_H, MIN_X_MARGIN, NEAR_ROW_H, ROW_H, STOP_ROW_H, W_SIZABLE
from oasa.eta import fmt_eta
from oasa.i18n import line_label, t
from oasa.ui import motion

GLASS_MATERIAL = 15   # NSVisualEffectMaterialFullScreenUI: thinner, more see-through than Popover


def haptic():
    """Trackpad tick (no-op where unsupported)."""
    try:
        if NSHapticFeedbackManager is not None:
            NSHapticFeedbackManager.defaultPerformer().performFeedbackPattern_performanceTime_(2, 1)
    except Exception:
        pass

def sys_font(size, bold=False, rounded=False, tabular=False):
    """SF Pro, optionally SF Pro Rounded and/or with fixed-width digits (like Apple's Clock/Maps)."""
    font = NSFont.systemFontOfSize_weight_(size, NSFontWeightSemibold if bold else 0.0)
    desc = font.fontDescriptor()
    if rounded:
        desc = desc.fontDescriptorWithDesign_(NSFontDescriptorSystemDesignRounded) or desc
    if tabular:  # kNumberSpacingType / kMonospacedNumbersSelector: countdowns don't jitter
        desc = desc.fontDescriptorByAddingAttributes_({NSFontFeatureSettingsAttribute: [
            {NSFontFeatureTypeIdentifierKey: 6, NSFontFeatureSelectorIdentifierKey: 0}]})
    return NSFont.fontWithDescriptor_size_(desc, size) or font

def label(text, size=13, bold=False, color=None, rounded=False, tabular=False):
    v = NSTextField.labelWithString_(text)
    v.setFont_(sys_font(size, bold, rounded, tabular))
    v.setLineBreakMode_(4)  # truncate tail
    if color is not None:
        v.setTextColor_(color)
    return v

def button(title, target, action, bezel=1):
    b = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 120, 28))
    b.setTitle_(title); b.setTarget_(target); b.setAction_(action)
    b.setBezelStyle_(bezel)
    return b

def glass(frame, radius, cls=NSVisualEffectView):
    """Translucent rounded 'iOS-style' card."""
    v = cls.alloc().initWithFrame_(frame)
    v.setMaterial_(GLASS_MATERIAL)
    v.setBlendingMode_(NSVisualEffectBlendingModeWithinWindow)
    v.setState_(NSVisualEffectStateActive)
    v.setWantsLayer_(True)
    v.layer().setCornerRadius_(radius)
    v.layer().setMasksToBounds_(True)
    v.layer().setBorderWidth_(0.5)
    v.layer().setBorderColor_(NSColor.separatorColor().CGColor())
    return v

def float_button(symbol, target, action, size, tooltip=''):
    """Round translucent button with an SF Symbols icon (map controls). Returns (container, button)."""
    wrap = glass(NSMakeRect(0, 0, size, size), size / 2)
    b = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, size, size))
    b.setBordered_(False); b.setImagePosition_(1)  # image only
    b.setTarget_(target); b.setAction_(action); b.setToolTip_(tooltip)
    b.setAutoresizingMask_(W_SIZABLE | 16)
    set_symbol(b, symbol)
    wrap.addSubview_(b)
    return wrap, b

def set_symbol(btn, symbol, size=15):
    img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(symbol, None)
    if img is not None:
        btn.setImage_(img.imageWithSymbolConfiguration_(NSImageSymbolConfiguration.configurationWithPointSize_weight_(size, 0.3)))
        btn.setContentTintColor_(NSColor.labelColor())

def solid(frame, color, radius=0):
    v = NSView.alloc().initWithFrame_(frame)
    v.setWantsLayer_(True)
    v.layer().setBackgroundColor_(color.CGColor())
    if radius:
        v.layer().setCornerRadius_(radius)
    return v

# ---- Row views ----------------------------------------------------------------
def row_height(row):
    if 'message' in row:
        return 60.0
    if row.get('kind') == 'header':
        return 28.0
    if row.get('kind') == 'times':
        return 30.0
    return float({'stop': STOP_ROW_H, 'bus': BUS_ROW_H, 'near': NEAR_ROW_H, 'fav': NEAR_ROW_H, 'alert': ALERT_ROW_H,
                  'stopline': LINE_ROW_H}.get(row.get('kind'), ROW_H))

def card_base(width, h):
    root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
    cw = width - 12
    card = NSView.alloc().initWithFrame_(NSMakeRect(6, 3, cw, h - 6))
    card.setWantsLayer_(True); card.setAutoresizingMask_(W_SIZABLE)
    card.layer().setCornerRadius_(14)
    # frosted pane on the glass: a faint fill and a hairline edge instead of a flat grey box
    card.layer().setBackgroundColor_(NSColor.windowBackgroundColor().colorWithAlphaComponent_(0.32).CGColor())
    card.layer().setBorderWidth_(0.5)
    card.layer().setBorderColor_(NSColor.labelColor().colorWithAlphaComponent_(0.10).CGColor())
    root.addSubview_(card)
    return root, card, cw

def make_row_view(row, width, app):
    kind = row.get('kind', 'arrival')
    h = row_height(row)

    if 'message' in row:
        root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        msg = label(row['message'], 12, color=NSColor.secondaryLabelColor())
        msg.setFrame_(NSMakeRect(12, 18, width - 24, 18))
        msg.setAlignment_(NSTextAlignmentCenter); msg.setAutoresizingMask_(W_SIZABLE)
        root.addSubview_(msg)
        return root

    if kind in ('stop', 'bus'):
        root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        cx = 28
        first, last = row.get('first'), row.get('last')
        y0, y1 = 0, h
        if kind == 'stop':
            if first:
                y1 = h / 2
            if last:
                y0 = h / 2
        if y1 > y0 and not (first and last):
            root.addSubview_(solid(NSMakeRect(cx - 1, y0, 2, y1 - y0), NSColor.tertiaryLabelColor()))
        if kind == 'stop':
            sel = row.get('selected')
            if sel:
                root.addSubview_(solid(NSMakeRect(6, 3, width - 12, h - 6),
                                       NSColor.systemOrangeColor().colorWithAlphaComponent_(0.16), 10))
            d = 16 if sel else 10
            dot = solid(NSMakeRect(cx - d / 2, h / 2 - d / 2, d, d),
                        NSColor.systemOrangeColor() if sel else NSColor.systemBlueColor(), d / 2)
            dot.layer().setBorderWidth_(2); dot.layer().setBorderColor_(NSColor.whiteColor().CGColor())
            root.addSubview_(dot)
            name = label(row['name'], 13, bool(sel)); name.setFrame_(NSMakeRect(52, 22, width - 64, 18))
            sub = label(t('stop_n', id=row['sid']), 11, color=NSColor.secondaryLabelColor()); sub.setFrame_(NSMakeRect(52, 6, width - 64, 14))
            name.setAutoresizingMask_(W_SIZABLE); sub.setAutoresizingMask_(W_SIZABLE)
            root.addSubview_(name); root.addSubview_(sub)
        else:
            bubble = solid(NSMakeRect(cx - 11, 6, 22, 22), NSColor.systemGreenColor(), 11)
            root.addSubview_(bubble)
            ico = label('🚌', 12); ico.setFrame_(NSMakeRect(cx - 11, 7, 22, 16)); ico.setAlignment_(NSTextAlignmentCenter)
            root.addSubview_(ico)
            txt = label(row['text'], 12, True, NSColor.systemGreenColor()); txt.setFrame_(NSMakeRect(52, 9, width - 64, 16))
            txt.setAutoresizingMask_(W_SIZABLE)
            root.addSubview_(txt)
        return root

    if kind == 'alert':  # OASA service alert: ⚠︎, title (2 lines), date and lines
        root, card, cw = card_base(width, h)
        tint = NSColor.systemRedColor() if row.get('strike') else NSColor.systemOrangeColor()  # strikes in red
        card.layer().setBackgroundColor_(tint.colorWithAlphaComponent_(0.16 if row.get('strike') else 0.14).CGColor())
        icon = label('⛔︎' if row.get('strike') else '⚠︎', 18, True, tint); icon.setFrame_(NSMakeRect(12, h - 36, 24, 24))
        title = label(row['title'], 12, True); title.setFrame_(NSMakeRect(42, 22, cw - 54, 34))
        title.setMaximumNumberOfLines_(2); title.cell().setWraps_(True); title.cell().setTruncatesLastVisibleLine_(True)
        meta = label(row['meta'], 11, color=NSColor.secondaryLabelColor()); meta.setFrame_(NSMakeRect(42, 6, cw - 54, 15))
        title.setAutoresizingMask_(W_SIZABLE); meta.setAutoresizingMask_(W_SIZABLE)
        for v in (icon, title, meta):
            card.addSubview_(v)
        return root

    if kind == 'times':  # a row of timetable departures: past dimmed, the next one in a green pill
        root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        cell_w = (width - 16) / TIMES_PER_ROW  # fixed columns, so the times line up row to row
        for i, (txt, state) in enumerate(row['cells']):
            x = 8 + i * cell_w
            if state == 'next':
                root.addSubview_(solid(NSMakeRect(x + 4, 3, cell_w - 8, h - 6),
                                       NSColor.systemGreenColor().colorWithAlphaComponent_(0.22), (h - 6) / 2))
            col = (NSColor.tertiaryLabelColor() if state == 'past' else
                   NSColor.systemGreenColor() if state == 'next' else NSColor.labelColor())
            lab = label(txt, 14, state == 'next', col, rounded=True, tabular=True)
            lab.setFrame_(NSMakeRect(x, 6, cell_w, 18)); lab.setAlignment_(NSTextAlignmentCenter)
            root.addSubview_(lab)
        return root

    if kind == 'header':  # section title inside a list
        root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        txt = label(row['text'], 11, True, NSColor.secondaryLabelColor())
        txt.setFrame_(NSMakeRect(12, 4, width - 24, 16)); txt.setAutoresizingMask_(W_SIZABLE)
        root.addSubview_(txt)
        return root

    if kind == 'fav':  # favourite stop: ★, name, next live arrivals
        root, card, cw = card_base(width, h)
        star = label('★', 20, True, NSColor.systemYellowColor()); star.setFrame_(NSMakeRect(14, (h - 6) / 2 - 13, 28, 26))
        name = label(row['name'], 13, True); name.setFrame_(NSMakeRect(48, 36, cw - 60, 18))
        nxt = label(row['next_txt'], 12, color=NSColor.secondaryLabelColor(), tabular=True); nxt.setFrame_(NSMakeRect(48, 14, cw - 60, 18))
        name.setAutoresizingMask_(W_SIZABLE); nxt.setAutoresizingMask_(W_SIZABLE)
        for v in (star, name, nxt):
            card.addSubview_(v)
        return root

    if kind == 'stopline':
        root, card, cw = card_base(width, h)
        badge = solid(NSMakeRect(12, (h - 6) / 2 - 14, 58, 28), NSColor.systemBlueColor(), 8)
        num = label(line_label(row['line']), 15, True, NSColor.whiteColor(), rounded=True); num.setFrame_(NSMakeRect(0, 4, 58, 20))
        num.setAlignment_(NSTextAlignmentCenter)
        badge.addSubview_(num)
        name = label(row['name'], 13, True); name.setFrame_(NSMakeRect(82, 30, cw - 82 - 86, 18))
        nxt = label(row['next_txt'], 11, color=NSColor.secondaryLabelColor()); nxt.setFrame_(NSMakeRect(82, 11, cw - 82 - 86, 16))
        eta_col = (NSColor.secondaryLabelColor() if row['eta_txt'] == '—'
                   else NSColor.systemOrangeColor() if row.get('scheduled') else NSColor.systemGreenColor())
        eta = label(row['eta_txt'], 18, True, eta_col, rounded=True, tabular=True)
        eta.setFrame_(NSMakeRect(cw - 84, (h - 6) / 2 - 12, 72, 24)); eta.setAlignment_(NSTextAlignmentRight)
        name.setAutoresizingMask_(W_SIZABLE); nxt.setAutoresizingMask_(W_SIZABLE); eta.setAutoresizingMask_(MIN_X_MARGIN)
        for v in (badge, name, nxt, eta):
            card.addSubview_(v)
        if row.get('due'):  # arriving now: the card glows green
            card.layer().setBackgroundColor_(NSColor.systemGreenColor().colorWithAlphaComponent_(0.16).CGColor())
        if row.get('live'):  # official live time: a breathing dot on the badge's corner
            card.addSubview_(motion.pulse_dot(70, (h - 6) / 2 + 14, 7, fast=bool(row.get('due'))))
        key = ('stopline', row['line'], row['name'])
        prev = app.prev_eta.get(key) if app is not None else None
        if prev is not None and prev != row['eta_txt']:
            motion.roll(eta)  # the time changed since the last refresh: roll to the new one
        if app is not None:
            app.prev_eta[key] = row['eta_txt']
        return root

    if kind == 'near':  # stop name and street on the left, distance and walk on the right
        root, card, cw = card_base(width, h)
        right_w = 108
        name = label(row['name'], 13, True); name.setFrame_(NSMakeRect(14, 36, cw - 28 - right_w - 8, 18))
        nxt = label(row['next_txt'], 12, color=NSColor.secondaryLabelColor(), tabular=True)
        nxt.setFrame_(NSMakeRect(14, 14, cw - 28 - right_w - 8, 18))
        dist = label(row['dist_txt'], 20, True, rounded=True, tabular=True); dist.setFrame_(NSMakeRect(cw - 14 - right_w, 30, right_w, 26))
        walk = label(row['walk'], 11, color=NSColor.secondaryLabelColor()); walk.setFrame_(NSMakeRect(cw - 14 - right_w, 10, right_w, 16))
        if row.get('closest'):  # no tag: the nearest stop's distance is simply in the accent colour
            dist.setTextColor_(NSColor.systemOrangeColor())
        for v in (dist, walk):
            v.setAlignment_(NSTextAlignmentRight); v.setAutoresizingMask_(MIN_X_MARGIN)
        name.setAutoresizingMask_(W_SIZABLE); nxt.setAutoresizingMask_(W_SIZABLE)
        row['next_label'] = nxt
        for v in (name, nxt, dist, walk):
            card.addSubview_(v)
        return root

    # arrival card
    root, card, cw = card_base(width, h)
    if row.get('pinned'):
        card.layer().setBorderWidth_(1.5); card.layer().setBorderColor_(NSColor.systemOrangeColor().CGColor())
    left = row['eta_s'] - (time.time() - row['t0'])
    if left < 90:  # arriving now
        card.layer().setBackgroundColor_(NSColor.systemGreenColor().colorWithAlphaComponent_(0.16).CGColor())
    if not row.get('estimated'):
        card.addSubview_(motion.pulse_dot(cw - 14, h - 20, 6, fast=left < 90))
    eta = label(fmt_eta(row['eta_s'] - (time.time() - row['t0'])), 20, True, rounded=True, tabular=True); eta.setFrame_(NSMakeRect(14, 32, 112, 28))
    row['eta_label'] = eta
    sub = label(row['sub'], 11, color=NSColor.secondaryLabelColor()); sub.setFrame_(NSMakeRect(14, 10, 112, 16))
    title = label(row['title'], 13, True); title.setFrame_(NSMakeRect(134, 38, cw - 134 - 92, 18))
    trip = label(row['trip'], 12, color=NSColor.secondaryLabelColor()); trip.setFrame_(NSMakeRect(134, 14, cw - 134 - 46, 18))
    delay = label(row['delay'], 12, True, row['delay_color']); delay.setFrame_(NSMakeRect(cw - 92, 38, 80, 18))
    delay.setAlignment_(NSTextAlignmentRight)
    title.setAutoresizingMask_(W_SIZABLE); trip.setAutoresizingMask_(W_SIZABLE); delay.setAutoresizingMask_(MIN_X_MARGIN)
    pin = NSButton.alloc().initWithFrame_(NSMakeRect(cw - 38, 8, 30, 24))
    pin.setBordered_(False); pin.setFont_(NSFont.systemFontOfSize_(16))
    pin.setTitle_('📍' if row.get('pinned') else '⌖')
    pin.setToolTip_(t('follow_bus'))
    pin.setIdentifier_(row['id']); pin.setTarget_(app); pin.setAction_('pinBus:')
    pin.setAutoresizingMask_(MIN_X_MARGIN)
    for v in (eta, sub, title, trip, delay, pin):
        card.addSubview_(v)
    return root
