"""First-launch welcome, in the style of Apple's own "Welcome to …" / "What's New" screens: the app
icon, a large title, a short list of features with SF Symbols in the accent colour, and one blue
Continue button. Everything eases in gently, top to bottom.

Shown once (NSUserDefaults 'onboarded'); Help → Show Welcome brings it back. Continue also asks
for location access (the system prompt), so the app can open on the stops near you.
The Objective-C callable (onboardNext_) lives on the app class in core.py."""
from AppKit import (
    NSAnimationContext, NSApplication, NSButton, NSColor, NSImage, NSImageSymbolConfiguration, NSImageView,
    NSMakeRect, NSTextAlignmentCenter, NSView, NSVisualEffectView,
)
from Foundation import NSUserDefaults
from oasa.debug import log
from oasa.i18n import t
from oasa.ui.motion import appear
from oasa.ui.widgets import label

_KEY = 'onboarded'
FEATURES = [('bus.fill', 'ob_f1', 'ob_f1_sub'),
            ('mappin.and.ellipse', 'ob_f2', 'ob_f2_sub'),
            ('star.fill', 'ob_f3', 'ob_f3_sub'),
            ('command', 'ob_f4', 'ob_f4_sub')]
COL_W, ROW_H = 380, 62


class OnboardingMixin:
    def maybe_onboard(self):
        if not NSUserDefaults.standardUserDefaults().boolForKey_(_KEY):
            self.show_onboarding()

    def show_onboarding(self):
        log('onboarding: start')
        self.ob = NSVisualEffectView.alloc().initWithFrame_(self.content.bounds())
        self.ob.setMaterial_(12)  # window background: plain, adapts to light and dark
        self.ob.setBlendingMode_(1); self.ob.setState_(1)
        self.ob.setAutoresizingMask_(2 | 16)
        self.content.addSubview_(self.ob)
        self.draw_onboarding()
        self.ob.setAlphaValue_(0.0)
        self.ob.animator().setAlphaValue_(1.0)

    def draw_onboarding(self, animate=True):
        for v in list(self.ob.subviews()):
            v.removeFromSuperview()
        b = self.content.bounds()
        W, H = b.size.width, b.size.height
        col = min(COL_W, W - 48)
        x0 = (W - col) / 2
        block_h = 96 + 18 + 40 + 30 + len(FEATURES) * ROW_H  # icon, gap, title, gap, rows
        y = H - max(70, (H - 140 - block_h) / 2)  # centred above the button
        k = 0
        icon = NSImageView.alloc().initWithFrame_(NSMakeRect((W - 96) / 2, y - 96, 96, 96))
        icon.setImage_(NSApplication.sharedApplication().applicationIconImage())
        self.ob.addSubview_(icon); animate and appear(icon, k); k += 1
        y -= 96 + 18
        title = label(t('ob_title'), 28, True)
        title.setAlignment_(NSTextAlignmentCenter)
        title.setFrame_(NSMakeRect(24, y - 36, W - 48, 36))
        self.ob.addSubview_(title); animate and appear(title, k); k += 2
        y -= 40 + 30
        for sym, head, body in FEATURES:
            row = NSView.alloc().initWithFrame_(NSMakeRect(x0, y - ROW_H, col, ROW_H))
            img = NSImage.imageWithSystemSymbolName_accessibilityDescription_(sym, None)
            iv = NSImageView.alloc().initWithFrame_(NSMakeRect(0, ROW_H - 40, 40, 34))
            if img is not None:
                iv.setImage_(img.imageWithSymbolConfiguration_(
                    NSImageSymbolConfiguration.configurationWithPointSize_weight_(26, 0.0)))
            iv.setContentTintColor_(NSColor.controlAccentColor())
            h = label(t(head), 13, True)
            h.setFrame_(NSMakeRect(56, ROW_H - 20, col - 56, 17))
            s = label(t(body), 12, color=NSColor.secondaryLabelColor())
            s.setMaximumNumberOfLines_(2); s.cell().setWraps_(True); s.setLineBreakMode_(0)
            s.setFrame_(NSMakeRect(56, ROW_H - 52, col - 56, 32))
            for v in (iv, h, s):
                row.addSubview_(v)
            self.ob.addSubview_(row); animate and appear(row, k); k += 1
            y -= ROW_H
        btn = NSButton.alloc().initWithFrame_(NSMakeRect((W - 220) / 2, 48, 220, 32))
        btn.setTitle_(t('ob_continue'))
        btn.setBezelStyle_(1); btn.setControlSize_(3)  # a large push button
        btn.setKeyEquivalent_('\r')  # the default button: blue, Return presses it
        btn.setTarget_(self); btn.setAction_('onboardNext:')
        self.ob.addSubview_(btn); animate and appear(btn, k + 1)

    def layout_onboarding(self):
        if getattr(self, 'ob', None) is not None:
            self.ob.setFrame_(self.content.bounds())
            self.draw_onboarding(animate=False)

    def onboard_next(self):
        log('onboarding: done')
        NSUserDefaults.standardUserDefaults().setBool_forKey_(True, _KEY)
        ob, self.ob = self.ob, None

        def changes(ctx):
            ctx.setDuration_(0.35)
            ob.animator().setAlphaValue_(0.0)
        NSAnimationContext.runAnimationGroup_completionHandler_(changes, lambda: ob.removeFromSuperview())
        if self.user_loc is None or self.user_loc[2] != 'gps':
            self.start_location()  # the system asks for permission now, over the map
