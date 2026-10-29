"""Timetable-based ETA for lines with no bus on the road yet (a rough estimate).

next departure from the route's first stop (OASA daily timetable)
  + distance along the route to this stop / a realistic bus pace (incl. stops and lights)
"""
import threading
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from oasa.api import oasa_call
from oasa.config import SCHED_DEPARTED_SLACK_MIN, SCHED_PACE_M_S
from oasa.debug import log
from oasa.eta import distance_km

ATHENS = ZoneInfo('Europe/Athens')
_lock = threading.Lock()
_route_stops = {}   # route code -> [(stop code, lat, lon)] in order (never changes)
_schedules = {}     # (line code, date) -> {'go': [datetime], 'come': [datetime]}


def route_stops(route_code):
    with _lock:
        if route_code in _route_stops:
            return _route_stops[route_code]
    stops = []
    for s in sorted(oasa_call('webGetStops', route_code), key=lambda s: int(s.get('RouteStopOrder') or 0)):
        try:
            stops.append((str(s['StopCode']), float(s['StopLat']), float(s['StopLng'])))
        except (KeyError, TypeError, ValueError):
            continue
    with _lock:
        _route_stops[route_code] = stops
    return stops


def departures(line_code, today):
    """Today's departures from each end: 'go' from the line's start, 'come' from its end."""
    key = (line_code, today)
    with _lock:
        if key in _schedules:
            return _schedules[key]
    data = oasa_call('getDailySchedule', line_code=line_code) or {}

    def times(rows, field):
        out = set()
        for r in rows or []:
            v = r.get(field)
            if v:
                t = datetime.strptime(v, '%Y-%m-%d %H:%M:%S').time()
                out.add(datetime.combine(today, t, ATHENS))
        return sorted(out)

    # In a 'go' row, sde_start1 is the outbound trip; in a 'come' row, sde_start2 is the return trip.
    sched = {'go': times(data.get('go'), 'sde_start1'), 'come': times(data.get('come'), 'sde_start2')}
    with _lock:
        _schedules[key] = sched
    return sched


def travel_minutes(route_code, stop_code):
    """Minutes from the route's first stop to `stop_code`, or None if the stop isn't on the route."""
    stops = route_stops(route_code)
    dist = 0.0
    for i, (code, lat, lon) in enumerate(stops):
        if i:
            dist += distance_km(stops[i - 1][1], stops[i - 1][2], lat, lon)
        if code == stop_code:
            return dist * 1000 / SCHED_PACE_M_S / 60
    return None


def scheduled_arrival(line_code, routes, stop_code, now=None):
    """Next timetabled arrival of a line at a stop.

    `routes` is [(route code, route type)], where type '1' is outbound (go) and '2' is the return (come).
    Returns {'eta_min', 'depart', 'arrive'} for the soonest one, or None if none are left today."""
    now = now or datetime.now(ATHENS)
    sched = departures(line_code, now.date())
    best = None
    for code, rtype in routes:
        try:
            travel = travel_minutes(code, stop_code)
        except Exception as e:
            log(f'schedule: stops of route {code} failed: {e}', 'WARN')
            continue
        if travel is None:
            continue
        for dep in sched['come' if str(rtype) == '2' else 'go']:
            # A bus that should already have left but isn't live yet usually just hasn't started tracking.
            if dep < now - timedelta(minutes=SCHED_DEPARTED_SLACK_MIN):
                continue
            arrive = max(dep + timedelta(minutes=travel), now)
            if best is None or arrive < best['arrive']:
                best = {'depart': dep, 'arrive': arrive}
            break  # departures are sorted: the first usable one is this route's soonest
    if best:
        best['eta_min'] = max(0, round((best['arrive'] - now).total_seconds() / 60))
    return best


def line_timetable(line_id, now=None):
    """Today's whole timetable of a line: [{'name', 'name_en', 'go': [datetime], 'come': [datetime]}],
    one per OASA variant of the line, the busiest first (variants with no trips today are left out)."""
    from oasa.api import get_line_codes
    now = now or datetime.now(ATHENS)
    out = []
    for code, name, name_en in get_line_codes().get(line_id, []):
        d = departures(code, now.date())
        if d['go'] or d['come']:
            out.append({'name': name, 'name_en': name_en, 'go': d['go'], 'come': d['come']})
    return sorted(out, key=lambda v: -(len(v['go']) + len(v['come'])))
