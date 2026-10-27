"""User location: CoreLocation with a map-centre fallback."""
import json, time
from Foundation import NSTimer
try:  # location (optional): pip install pyobjc-framework-CoreLocation
    import CoreLocation
    HAS_CL = True
except Exception:  # pragma: no cover
    CoreLocation = None
    HAS_CL = False
from oasa.config import AUTH_NOT_DETERMINED, LOC_PROMPT_TIMEOUT, LOC_TIMEOUT
from oasa.debug import log


class LocationMixin:
    def start_location(self):
        self.status.setStringValue_('Locating…')
        if not HAS_CL:
            self.use_map_center('pyobjc-framework-CoreLocation is not installed')
            return
        try:
            if self.loc_mgr is None:
                self.loc_mgr = CoreLocation.CLLocationManager.alloc().init()
                self.loc_mgr.setDelegate_(self)
                self.loc_mgr.setDesiredAccuracy_(CoreLocation.kCLLocationAccuracyHundredMeters)
            asking = self.loc_mgr.authorizationStatus() == AUTH_NOT_DETERMINED
            if hasattr(self.loc_mgr, 'requestWhenInUseAuthorization'):
                self.loc_mgr.requestWhenInUseAuthorization()
            self.loc_mgr.requestLocation()
            self.loc_pending = time.time()
            # Give the user time to answer the permission prompt the first time.
            wait = LOC_PROMPT_TIMEOUT if asking else LOC_TIMEOUT
            NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
                wait, self, 'locTimeout:', wait - 0.5, False)
            log('location requested')
        except Exception as e:
            log(f'location error: {e}', 'ERROR')
            self.use_map_center(str(e))

    def use_map_center(self, why):
        """Fallback when GPS is unavailable: treat the map centre as 'you are here'."""
        log(f'location fallback -> map centre ({why})', 'WARN')
        self.loc_pending = None
        if not self.map_ready:
            self.status.setStringValue_('Location unavailable')
            return

        def done(result, error):
            try:
                c = json.loads(str(result))
                self.set_user_location(c['lat'], c['lon'], 'map')
            except Exception as e:
                log(f'map centre fallback failed: {e}', 'ERROR')

        self.map.evaluateJavaScript_completionHandler_('window.getCenter()', done)

    def set_user_location(self, lat, lon, src):
        self.user_loc = (lat, lon, src)
        self.evaluate_js(f'window.setUser({lat},{lon});')
        self.rebuild_nearby()
        if src == 'gps':
            self.status.setStringValue_('Located you · showing nearest stops')
            self.evaluate_js(f'window.focusStop({lat},{lon},15,{int(self.sheet_h)});')
        else:
            self.status.setStringValue_('Location unavailable · using the map centre')
