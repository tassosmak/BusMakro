"""Small AppKit helpers and the list-row (card) views."""
import time
from AppKit import (
    NSMakeRect, NSColor, NSFont, NSFontWeightSemibold, NSButton, NSTextField, NSView,
    NSVisualEffectView, NSVisualEffectMaterialPopover, NSVisualEffectBlendingModeWithinWindow,
    NSVisualEffectStateActive, NSTextAlignmentRight, NSTextAlignmentCenter,
)
try:  # trackpad haptics (optional)
    from AppKit import NSHapticFeedbackManager
except Exception:  # pragma: no cover
    NSHapticFeedbackManager = None
from oasa.config import BUS_ROW_H, MIN_X_MARGIN, NEAR_ROW_H, ROW_H, STOP_ROW_H, W_SIZABLE
from oasa.eta import fmt_eta


def haptic():
    """Trackpad tick (no-op where unsupported)."""
    try:
        if NSHapticFeedbackManager is not None:
            NSHapticFeedbackManager.defaultPerformer().performFeedbackPattern_performanceTime_(2, 1)
    except Exception:
        pass

def label(text, size=13, bold=False, color=None):
    v = NSTextField.labelWithString_(text)
    v.setFont_(NSFont.systemFontOfSize_weight_(size, NSFontWeightSemibold) if bold else NSFont.systemFontOfSize_(size))
    v.setLineBreakMode_(4)  # truncate tail
    if color is not None:
        v.setTextColor_(color)
    return v

def button(title, target, action, bezel=1):
    b = NSButton.alloc().initWithFrame_(NSMakeRect(0, 0, 120, 28))
    b.setTitle_(title); b.setTarget_(target); b.setAction_(action)
    b.setBezelStyle_(bezel)
    return b

def glass(frame, radius):
    """Translucent rounded 'iOS-style' card."""
    v = NSVisualEffectView.alloc().initWithFrame_(frame)
    v.setMaterial_(NSVisualEffectMaterialPopover)
    v.setBlendingMode_(NSVisualEffectBlendingModeWithinWindow)
    v.setState_(NSVisualEffectStateActive)
    v.setWantsLayer_(True)
    v.layer().setCornerRadius_(radius)
    v.layer().setMasksToBounds_(True)
    v.layer().setBorderWidth_(0.5)
    v.layer().setBorderColor_(NSColor.separatorColor().CGColor())
    return v

def solid(frame, color, radius=0):
    v = NSView.alloc().initWithFrame_(frame)
    v.setWantsLayer_(True)
    v.layer().setBackgroundColor_(color.CGColor())
    if radius:
        v.layer().setCornerRadius_(radius)
    return v

def line_id_of(title):
    return str(title or '').split(' — ', 1)[0].strip()

# ---- Row views ----------------------------------------------------------------
def row_height(row):
    if 'message' in row:
        return 60.0
    return float({'stop': STOP_ROW_H, 'bus': BUS_ROW_H, 'near': NEAR_ROW_H}.get(row.get('kind'), ROW_H))

def card_base(width, h):
    root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
    cw = width - 12
    card = NSView.alloc().initWithFrame_(NSMakeRect(6, 3, cw, h - 6))
    card.setWantsLayer_(True); card.setAutoresizingMask_(W_SIZABLE)
    card.layer().setCornerRadius_(14)
    card.layer().setBackgroundColor_(NSColor.labelColor().colorWithAlphaComponent_(0.07).CGColor())
    root.addSubview_(card)
    return root, card, cw

def make_row_view(row, width, app):
    kind = row.get('kind', 'arrival')
    h = row_height(row)

    if 'message' in row:
        root = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, h))
        t = label(row['message'], 12, color=NSColor.secondaryLabelColor())
        t.setFrame_(NSMakeRect(12, 18, width - 24, 18))
        t.setAlignment_(NSTextAlignmentCenter); t.setAutoresizingMask_(W_SIZABLE)
        root.addSubview_(t)
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
            sub = label(f'Stop {row["sid"]}', 11, color=NSColor.secondaryLabelColor()); sub.setFrame_(NSMakeRect(52, 6, width - 64, 14))
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

    if kind == 'near':
        root, card, cw = card_base(width, h)
        dist = label(row['dist_txt'], 20, True); dist.setFrame_(NSMakeRect(14, 30, 108, 26))
        walk = label(row['walk'], 11, color=NSColor.secondaryLabelColor()); walk.setFrame_(NSMakeRect(14, 10, 108, 16))
        name_w = cw - 134 - (86 if row.get('closest') else 12)
        name = label(row['name'], 13, True); name.setFrame_(NSMakeRect(134, 36, name_w, 18)); name.setAutoresizingMask_(W_SIZABLE)
        nxt = label(row['next_txt'], 12, color=NSColor.secondaryLabelColor()); nxt.setFrame_(NSMakeRect(134, 14, cw - 146, 18))
        nxt.setAutoresizingMask_(W_SIZABLE)
        row['next_label'] = nxt
        for v in (dist, walk, name, nxt):
            card.addSubview_(v)
        if row.get('closest'):
            tag = label('CLOSEST', 9, True, NSColor.systemOrangeColor()); tag.setFrame_(NSMakeRect(cw - 78, 40, 66, 12))
            tag.setAlignment_(NSTextAlignmentRight); tag.setAutoresizingMask_(MIN_X_MARGIN)
            card.addSubview_(tag)
        return root

    # arrival card
    root, card, cw = card_base(width, h)
    if row.get('pinned'):
        card.layer().setBorderWidth_(1.5); card.layer().setBorderColor_(NSColor.systemOrangeColor().CGColor())
    eta = label(fmt_eta(row['eta_s'] - (time.time() - row['t0'])), 20, True); eta.setFrame_(NSMakeRect(14, 32, 112, 28))
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
    pin.setToolTip_('Follow this bus on the map')
    pin.setIdentifier_(row['id']); pin.setTarget_(app); pin.setAction_('pinBus:')
    pin.setAutoresizingMask_(MIN_X_MARGIN)
    for v in (eta, sub, title, trip, delay, pin):
        card.addSubview_(v)
    return root
