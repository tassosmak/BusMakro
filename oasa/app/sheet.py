"""Bottom-sheet sizing, dragging and animation, and the expand-map animation.

One animation drives both the sheet height and the top bar's fade/slide (`pill_alpha`),
so they move together: expanding the map slides the bar up and out while the sheet drops
to a thin strip; collapsing reverses it.
"""
import time
from Foundation import NSTimer
from oasa.config import FOCUS_SHEET_H, PILL_H, TOP_INSET
from oasa.debug import log
from oasa.i18n import t
from oasa.ui.widgets import set_symbol


class SheetMixin:
    # ---- Layout (mobile-style: floating top bar + bottom sheet over a full-bleed map)
    def peek_h(self, H):
        return min(400, max(340, H * 0.46))

    def full_h(self, H):
        return max(self.peek_h(H) + 40, H - TOP_INSET - PILL_H - 18)

    # ---- Sheet dragging / animation ------------------------------------------------
    def sheet_drag_begin(self):
        if self.anim_timer is not None:
            self.anim_timer.invalidate(); self.anim_timer = None; self.anim = None
        self.drag_start_h = self.sheet_h
        self.sheet_override = self.sheet_h

    def sheet_drag_move(self, dy):
        if self.map_focus and abs(dy) > 3:  # dragging the strip brings the panels back
            self.map_focus = False
            self.update_focus_button()
        H = self.content.bounds().size.height
        peek = self.peek_h(H)
        self.sheet_override = max(FOCUS_SHEET_H, min(self.full_h(H), self.drag_start_h + dy))
        # below the normal height the top bar fades out with the sheet, as in the expand animation
        self.pill_alpha = max(0.0, min(1.0, (self.sheet_override - FOCUS_SHEET_H) / (peek - FOCUS_SHEET_H)))
        self.do_layout(reload=False)

    def sheet_drag_end(self, moved, tap_toggles=True):
        """Snap to the nearest of strip (map expanded) / normal / full. A tap on the handle toggles full."""
        H = self.content.bounds().size.height
        if not moved:
            self.sheet_override = None  # a click, not a drag: leave the sheet as it was
            if tap_toggles and not self.map_focus:
                self.animate_sheet(not self.sheet_full)
            else:
                self.do_layout(reload=False)
            return
        peek, full, h = self.peek_h(H), self.full_h(H), self.sheet_h
        if h < (FOCUS_SHEET_H + peek) / 2:
            self.map_focus = True
            self.update_focus_button()
            self.animate_sheet(False, end=FOCUS_SHEET_H)
        else:
            self.animate_sheet(h > (peek + full) / 2)

    def animate_sheet(self, to_full, end=None):
        """Animate the sheet to full/peek (or to `end`), and the top bar to shown/hidden for the current focus."""
        H = self.content.bounds().size.height
        if end is None:
            end = self.full_h(H) if to_full else self.peek_h(H)
        self.anim = {'t0': time.time(), 'start': self.sheet_h, 'end': end, 'full': to_full,
                     'pill_from': self.pill_alpha, 'pill_to': 0.0 if self.map_focus else 1.0}
        if self.anim_timer is None:
            self.anim_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                1 / 60.0, self, 'animTick:', None, True)

    # ---- Expand map (like the recording: bar slides away, sheet drops to a strip) ------
    def toggle_map_focus(self):
        self.map_focus = not self.map_focus
        log(f'map focus -> {self.map_focus}')
        self.update_focus_button()
        if self.map_focus:
            self.animate_sheet(False, end=FOCUS_SHEET_H)
        else:
            self.animate_sheet(False)

    def update_focus_button(self):
        set_symbol(self.map_focus_btn, 'arrow.down.right.and.arrow.up.left' if self.map_focus
                   else 'arrow.up.left.and.arrow.down.right')
        self.map_focus_btn.setToolTip_(t('tip_collapse') if self.map_focus else t('tip_expand'))
