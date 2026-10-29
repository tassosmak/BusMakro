"""Small Core Animation effects: rows easing in, numbers rolling to a new value, pulsing dots.

Core Animation classes come from QuartzCore, which AppKit already loads, so they are looked up
by name instead of needing the pyobjc Quartz package."""
import objc
from AppKit import NSColor, NSMakeRect, NSView
from Foundation import NSBundle

CABasicAnimation = objc.lookUpClass('CABasicAnimation')
CAAnimationGroup = objc.lookUpClass('CAAnimationGroup')
CATransition = objc.lookUpClass('CATransition')
CALayer = objc.lookUpClass('CALayer')
CAMediaTimingFunction = objc.lookUpClass('CAMediaTimingFunction')
_qc = {}
objc.loadBundleFunctions(NSBundle.bundleWithIdentifier_('com.apple.QuartzCore'), _qc, [('CACurrentMediaTime', b'd')])
now = _qc['CACurrentMediaTime']

APPEAR_S = 0.38       # a row easing in
APPEAR_STAGGER = 0.035
ROLL_S = 0.32         # a number rolling to its new value


def _ease(name='easeOut'):
    return CAMediaTimingFunction.functionWithName_(name)


def _basic(key, a, b, dur):
    an = CABasicAnimation.animationWithKeyPath_(key)
    an.setFromValue_(a); an.setToValue_(b); an.setDuration_(dur)
    return an


def appear(view, index=0):
    """Fade the view in while it slides up a little; rows further down start slightly later."""
    view.setWantsLayer_(True)
    layer = view.layer()
    g = CAAnimationGroup.animation()
    g.setAnimations_([_basic('opacity', 0.0, 1.0, APPEAR_S), _basic('transform.translation.y', -10.0, 0.0, APPEAR_S),
                      _basic('transform.scale', 0.97, 1.0, APPEAR_S)])
    g.setDuration_(APPEAR_S)
    g.setBeginTime_(now() + min(index, 12) * APPEAR_STAGGER)
    g.setFillMode_('backwards')  # invisible until its turn comes
    g.setTimingFunction_(_ease())
    layer.addAnimation_forKey_(g, 'appear')


def roll(label, up=True):
    """Push the label's next text in from below (counting down) or above."""
    label.setWantsLayer_(True)
    tr = CATransition.animation()
    tr.setType_('push'); tr.setSubtype_('fromBottom' if up else 'fromTop')
    tr.setDuration_(ROLL_S); tr.setTimingFunction_(_ease('easeInEaseOut'))
    label.layer().addAnimation_forKey_(tr, 'roll')


def set_rolling(label, text, up=True):
    if label.stringValue() != text:
        roll(label, up)
        label.setStringValue_(text)


def pulse_dot(x, y, size, color=None, fast=False):
    """A small dot with a soft ring breathing out of it: "this is live"."""
    color = color or NSColor.systemGreenColor()
    pad = size * 1.6  # room for the ring to grow into, so it's never clipped to a square
    half = size / 2 + pad
    box = NSView.alloc().initWithFrame_(NSMakeRect(x - half, y - half, half * 2, half * 2))
    box.setWantsLayer_(True)
    box.layer().setMasksToBounds_(False); box.layer().setBackgroundColor_(None)
    # plain layers (not views): AppKit can't redraw them into a square backing behind the animation
    ring, dot = CALayer.layer(), CALayer.layer()
    for lyr in (ring, dot):
        lyr.setBounds_(((0, 0), (size, size))); lyr.setPosition_((half, half))
        lyr.setCornerRadius_(size / 2); lyr.setBackgroundColor_(color.CGColor())
        box.layer().addSublayer_(lyr)
    period = 1.1 if fast else 2.0
    g = CAAnimationGroup.animation()
    g.setAnimations_([_basic('transform.scale', 1.0, 2.6, period), _basic('opacity', 0.55, 0.0, period)])
    g.setDuration_(period); g.setRepeatCount_(1e9); g.setTimingFunction_(_ease())
    ring.addAnimation_forKey_(g, 'pulse')
    if fast:  # due now: the dot itself throbs too
        b = _basic('opacity', 1.0, 0.45, period / 2)
        b.setAutoreverses_(True); b.setRepeatCount_(1e9)
        dot.addAnimation_forKey_(b, 'throb')
    return box
