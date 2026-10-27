"""Bottom-sheet sizing, dragging and animation."""
import time
from Foundation import NSTimer
from oasa.config import PILL_H, TOP_INSET


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
        H = self.content.bounds().size.height
        lo, hi = self.peek_h(H) * 0.8, self.full_h(H)
        self.sheet_override = max(lo, min(hi, self.drag_start_h + dy))
        self.do_layout(reload=False)

    def sheet_drag_end(self, moved):
        H = self.content.bounds().size.height
        if not moved:
            to_full = not self.sheet_full
        else:
            to_full = self.sheet_h > (self.peek_h(H) + self.full_h(H)) / 2
        self.animate_sheet(to_full)

    def animate_sheet(self, to_full):
        H = self.content.bounds().size.height
        end = self.full_h(H) if to_full else self.peek_h(H)
        self.anim = {'t0': time.time(), 'start': self.sheet_h, 'end': end, 'full': to_full}
        if self.anim_timer is None:
            self.anim_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                1 / 60.0, self, 'animTick:', None, True)
