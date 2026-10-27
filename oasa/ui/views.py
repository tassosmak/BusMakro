"""AppKit helper classes: table data source, sheet drag handle, window drag bar, map message bridge."""
import objc
from AppKit import NSAnimationContext, NSColor, NSMakeRect, NSTrackingArea, NSView
from Foundation import NSObject
from oasa.debug import log
from oasa.ui.widgets import make_row_view, row_height

# NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
TRACK_OPTIONS = 0x01 | 0x80 | 0x200


class RowDataSource(NSObject):
    """Shared table data source/delegate for the three lists."""
    def init(self):
        self = objc.super(RowDataSource, self).init()
        if self is None:
            return None
        self.rows = []
        self.app = None
        return self

    def numberOfRowsInTableView_(self, table):
        return len(self.rows)

    def tableView_heightOfRow_(self, table, row):
        return row_height(self.rows[row])

    def tableView_viewForTableColumn_row_(self, table, column, row):
        return make_row_view(self.rows[row], column.width(), self.app)

    def tableView_shouldSelectRow_(self, table, row):
        return 'message' not in self.rows[row]

class DragHandle(NSView):
    """Top strip of the bottom sheet: drag (mouse or trackpad) to resize, click to toggle."""
    def acceptsFirstMouse_(self, event):
        return True

    def mouseDown_(self, event):
        self.start_y = event.locationInWindow().y
        self.moved = False
        self.app.sheet_drag_begin()

    def mouseDragged_(self, event):
        dy = event.locationInWindow().y - self.start_y
        if abs(dy) > 3:
            self.moved = True
        self.app.sheet_drag_move(dy)

    def mouseUp_(self, event):
        self.app.sheet_drag_end(self.moved)

class MapHandler(NSObject):
    def initWithApp_(self, app):
        self = objc.super(MapHandler, self).init()
        if self is not None:
            self.app = app
        return self

    def userContentController_didReceiveScriptMessage_(self, controller, message):
        body = message.body()
        try:
            kind = body.get('type')
        except Exception:
            return
        if kind == 'stop':
            self.app.select_stop(str(body.get('id')))
        elif kind == 'bus':
            self.app.toggle_pin(str(body.get('id')))
        elif kind == 'moved':
            self.app.on_map_moved(float(body.get('lat')), float(body.get('lon')), float(body.get('zoom')))
        elif kind == 'unpin':
            self.app.on_unpin()
        elif kind == 'error':
            msg = str(body.get('msg'))
            log('map error: ' + msg, 'ERROR')
            self.app.status.setStringValue_('Map: ' + msg[:90])
        elif kind == 'console':
            level = str(body.get('level'))
            log(f'JS {level}: {body.get("msg")}', 'ERROR' if level == 'error' else 'JS')
        elif kind == 'map':
            log('map: ' + str(body.get('msg')))

class WindowDragBar(NSView):
    """Thin strip along the top of the window: hidden until hovered, drag it to move the window.

    The window's traffic-light buttons fade in and out with it.

    The map fills the whole window (title bar included) and would otherwise swallow those drags.
    Double-click zooms the window, like a normal title bar."""
    def initWithFrame_(self, frame):
        self = objc.super(WindowDragBar, self).initWithFrame_(frame)
        if self is None:
            return None
        self.setWantsLayer_(True)
        self.layer().setBackgroundColor_(NSColor.windowBackgroundColor().colorWithAlphaComponent_(0.55).CGColor())
        self.setAlphaValue_(0.0)
        w, h = frame.size.width, frame.size.height
        grip = NSView.alloc().initWithFrame_(NSMakeRect(w / 2 - 18, h / 2 - 2, 36, 4))
        grip.setAutoresizingMask_(1 | 4 | 8 | 32)  # flexible margins on all sides: stays centred
        grip.setWantsLayer_(True)
        grip.layer().setBackgroundColor_(NSColor.tertiaryLabelColor().CGColor())
        grip.layer().setCornerRadius_(2)
        self.grip = grip
        self.addSubview_(grip)
        area = NSTrackingArea.alloc().initWithRect_options_owner_userInfo_(
            NSMakeRect(0, 0, 0, 0), TRACK_OPTIONS, self, None)
        self.addTrackingArea_(area)
        return self

    @objc.python_method
    def window_buttons(self):
        """The red/yellow/green buttons (close, minimize, zoom)."""
        w = self.window()
        return [b for b in (w.standardWindowButton_(i) for i in range(3)) if b is not None] if w else []

    @objc.python_method
    def fade(self, alpha, animate=True):
        """Show/hide the bar together with the window buttons (they stay clickable while faded)."""
        views = [self] + self.window_buttons()
        if not animate:
            for v in views:
                v.setAlphaValue_(alpha)
            return
        NSAnimationContext.beginGrouping()
        NSAnimationContext.currentContext().setDuration_(0.18)
        for v in views:
            v.animator().setAlphaValue_(alpha)
        NSAnimationContext.endGrouping()

    def mouseEntered_(self, event):
        self.fade(1.0)

    def mouseExited_(self, event):
        self.fade(0.0)

    def acceptsFirstMouse_(self, event):
        return True

    def mouseDown_(self, event):
        if event.clickCount() == 2:
            self.window().performZoom_(None)
        else:
            self.window().performWindowDragWithEvent_(event)
