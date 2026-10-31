"""macOS notifications (UserNotifications). Needs the app bundle; outside one it only logs."""
from oasa.debug import log
try:
    import UserNotifications as UN
except Exception:  # pragma: no cover - pyobjc-framework-UserNotifications missing
    UN = None
_asked = False


def _center():
    if UN is None:
        return None
    try:
        return UN.UNUserNotificationCenter.currentNotificationCenter()
    except Exception as e:  # no bundle identifier (run without the .app)
        log(f'notifications unavailable: {e}', 'WARN')
        return None


def ask_permission(done=None):
    """Ask once (the system shows its prompt the first time only); done(granted) when answered."""
    global _asked
    c = _center()
    if c is None or _asked:
        return
    _asked = True

    def answered(granted, error):
        log(f'notifications allowed: {bool(granted)}')
        if done:
            done(bool(granted))
    c.requestAuthorizationWithOptions_completionHandler_(UN.UNAuthorizationOptionAlert | UN.UNAuthorizationOptionSound, answered)


def post(ident, title, body):
    c = _center()
    if c is None:
        log(f'notification (not shown): {title} · {body}')
        return
    content = UN.UNMutableNotificationContent.alloc().init()
    content.setTitle_(title); content.setBody_(body)
    content.setSound_(UN.UNNotificationSound.defaultSound())
    req = UN.UNNotificationRequest.requestWithIdentifier_content_trigger_(ident, content, None)  # now
    c.addNotificationRequest_withCompletionHandler_(req, lambda error: error and log(f'notification failed: {error}', 'WARN'))
    log(f'notification: {title} · {body}')


def status(callback):
    """callback('allowed' | 'denied' | 'not_asked'), possibly on another thread."""
    c = _center()
    if c is None:
        callback('denied')
        return
    c.getNotificationSettingsWithCompletionHandler_(
        lambda st: callback({2: 'allowed', 3: 'allowed', 4: 'allowed', 1: 'denied'}.get(st.authorizationStatus(), 'not_asked')))


def open_settings():
    """System Settings → Notifications, on BusMakro's page when macOS supports that."""
    from AppKit import NSWorkspace
    from Foundation import NSURL
    NSWorkspace.sharedWorkspace().openURL_(NSURL.URLWithString_(
        'x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.tassosmak.busmakro'))
