"""Distances, our own ETA estimate (fallback) and ETA/distance formatting."""
import math
from oasa.config import ETA_DEFAULT_SPEED, ETA_MAX_SPEED, ETA_MIN_SPEED


def distance_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def route_distance_m(v, route, sid, stops):
    """Distance in metres along the route: bus -> next stop -> ... -> stop `sid`."""
    nxt = v['next_stop_id']
    a = stops.get(nxt, {})
    if a.get('lat') is None:
        return None
    dist = distance_km(v['lat'], v['lon'], a['lat'], a['lon'])
    for prev, cur in zip(route[route.index(nxt):route.index(sid)], route[route.index(nxt) + 1:route.index(sid) + 1]):
        p, c = stops.get(prev, {}), stops.get(cur, {})
        if p.get('lat') is None or c.get('lat') is None:
            continue
        dist += distance_km(p['lat'], p['lon'], c['lat'], c['lon'])
    return dist * 1000

def eta_seconds(v, dist_m, now):
    """(eta_s, estimated) for a vehicle `dist_m` metres from the stop, measured from `now`.

    Uses the average of recent path speeds (smoother than the instantaneous speed),
    clamped to a realistic range, and subtracts the age of the GPS fix."""
    speeds = [s for s in (v.get('path_speeds') or []) if s is not None and s > 0]
    if speeds:
        speed, est = sum(speeds) / len(speeds), False
    elif v.get('speed') and v['speed'] > 0:
        speed, est = v['speed'], False
    else:
        speed, est = ETA_DEFAULT_SPEED, True
    speed = min(ETA_MAX_SPEED, max(ETA_MIN_SPEED, speed))
    age = max(0.0, now - v['position_at']) if v.get('position_at') else 0.0
    return max(0.0, dist_m / speed - age), est

def fmt_eta(seconds):
    s = max(0.0, seconds)
    if s < 20:
        return 'Due'
    m, sec = divmod(int(s), 60)
    return f'{m}:{sec:02d} min'

def fmt_dist(km):
    return f'{int(round(km * 100) * 10)} m' if km < 1 else f'{km:.1f} km'
