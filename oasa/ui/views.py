"""AppKit helper classes: table data source, sheet drag handle, map message bridge."""
import objc
from AppKit import NSView
from Foundation import NSObject
from oasa.debug import log
from oasa.ui.widgets import make_row_view, row_height


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
