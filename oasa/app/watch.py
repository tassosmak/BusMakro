"""Bus alerts: "notify me when this bus is N stops from my stop".

A 🔔 on each approaching bus in the line view offers 1, 2, 3 or 5 stops. The watch keeps running
after you leave the line (its own poll every WATCH_EVERY_S), posts one notification when the bus is
that close, and ends then, or quietly when the bus passes the stop or stops reporting.
The Objective-C callables (watchBus_, watchStops_) live on the app class in core.py."""
import threading, time
from urllib.parse import quote
from AppKit import NSMenu, NSMenuItem
from oasa import notify
from oasa.api import get_json
from oasa.config import API_BASE
from oasa.debug import log
from oasa.i18n import line_label, name, t

WATCH_EVERY_S = 20
CHOICES = (1, 2, 3, 5)
LOST_AFTER_S = 600   # a watched bus missing this long is dropped


def stops_away(vehicle, variants, sid):
    """Stops between the bus and `sid` (0 = the stop is its next one), or None if it isn't coming."""
    route = [str(s) for s in variants.get(vehicle.get('variant'), {}).get('stops', [])]
    nxt = str(vehicle.get('next_stop_id'))
    if sid not in route or nxt not in route or route.index(sid) < route.index(nxt):
        return None
    return route.index(sid) - route.index(nxt)


class WatchMixin:
    def watch_menu(self, sender):
        """The 🔔's menu: notify at 1/2/3/5 stops away, or stop watching."""
        bid = str(sender.identifier())
        menu = NSMenu.alloc().init()
        head = menu.addItemWithTitle_action_keyEquivalent_(t('watch_head'), None, '')
        head.setEnabled_(False)
        cur = self.watches.get(bid, {}).get('stops')
        for n in CHOICES:
            it = menu.addItemWithTitle_action_keyEquivalent_(t('watch_n', n=n) if n > 1 else t('watch_1'), 'watchStops:', '')
            it.setTarget_(self); it.setRepresentedObject_(f'{bid}|{n}'); it.setState_(1 if cur == n else 0)
        if bid in self.watches:
            menu.addItem_(NSMenuItem.separatorItem())
            it = menu.addItemWithTitle_action_keyEquivalent_(t('watch_cancel'), 'watchStops:', '')
            it.setTarget_(self); it.setRepresentedObject_(f'{bid}|0')
        menu.popUpMenuPositioningItem_atLocation_inView_(None, (0, sender.frame().size.height + 4), sender)

    def set_watch(self, bid, n):
        if n == 0:
            self.watches.pop(bid, None)
            log(f'watch {bid} cancelled')
        else:
            stop = self.line_data.get('stops', {}).get(self.selected_stop_id, {}) if self.line_data else {}
            self.watches[bid] = {'line': self.current_line, 'stop': self.selected_stop_id, 'stops': n,
                                 'stop_name': name(stop.get('name')) or self.selected_stop_id,
                                 'variants': self.line_data.get('variants', {}), 'seen': time.time()}
            log(f'watch {bid}: line {self.current_line}, {n} stops before {self.selected_stop_id}')
            notify.ask_permission()
            self.check_watches(self.live)  # it may already be that close
            self.start_watch_loop()
        self.render_arrivals(self.live)

    def check_watches(self, live, line=None):
        """Compare the watched buses in a fresh line response; notify (once) when one is close enough."""
        line = line or self.current_line
        now = time.time()
        by_id = {str(v.get('id')): v for v in (live or {}).get('vehicles', [])}
        for bid, w in list(self.watches.items()):
            if w['line'] != line:
                continue
            v = by_id.get(bid)
            if v is None:
                if now - w['seen'] > LOST_AFTER_S:
                    log(f'watch {bid}: bus lost, dropped', 'WARN')
                    self.watches.pop(bid, None)
                continue
            w['seen'] = now
            n = stops_away(v, w['variants'], w['stop'])
            if n is None:  # passed the stop (or turned off the route): nothing more to say
                log(f'watch {bid}: no longer heading to {w["stop"]}, dropped')
                self.watches.pop(bid, None)
            elif n <= w['stops']:
                body = (t('watch_body_now', stop=w['stop_name'], id=bid) if n == 0 else
                        t('watch_body', when=t('watch_body_1') if n == 1 else t('watch_body_n', n=n), stop=w['stop_name'], id=bid))
                notify.post(f'watch-{bid}', t('watch_title', line=line_label(line)), body)
                self.watches.pop(bid, None)

    def start_watch_loop(self):
        if getattr(self, 'watch_thread', None) is not None:
            return

        def loop():
            while self.watches:
                time.sleep(WATCH_EVERY_S)
                for line in {w['line'] for w in list(self.watches.values())}:
                    try:
                        live = get_json(f'{API_BASE}/v1/lines/{quote(line, safe="")}')
                        self.results.put(('watch_live', line, live))
                    except Exception as e:
                        log(f'watch poll {line}: {e}', 'WARN')
            self.watch_thread = None
        self.watch_thread = threading.Thread(target=loop, daemon=True)
        self.watch_thread.start()
