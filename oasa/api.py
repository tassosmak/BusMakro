"""Network access: transit.haroldpoi.dev / static data and official OASA predictions."""
import time
from concurrent.futures import ThreadPoolExecutor
import requests
from oasa.config import NEAR_STOPS_LIMIT, OASA_API
from oasa.debug import log


def get_json(url):
    t0 = time.perf_counter()
    try:
        r = requests.get(url, timeout=20)
        r.raise_for_status()
        data = r.json()
        log(f'GET {url} -> {r.status_code} {len(r.content)}B {int((time.perf_counter() - t0) * 1000)}ms')
        return data
    except Exception as e:
        log(f'GET {url} FAILED after {int((time.perf_counter() - t0) * 1000)}ms: {e}', 'ERROR')
        raise

def get_oasa_arrivals(stop_id):
    """Official OASA predictions for a stop: {vehicle id: minutes}. Empty on failure.

    These are the same predictions the official/trusted apps show, and are far more
    accurate than anything we can estimate from a single GPS fix."""
    try:
        r = requests.post(OASA_API, params={'act': 'getStopArrivals', 'p1': stop_id},
                          headers={'User-Agent': 'Mozilla/5.0'}, timeout=10)
        r.raise_for_status()
        return {str(a['veh_code']): float(a['btime2']) for a in (r.json() or [])
                if a.get('veh_code') and a.get('btime2') is not None}
    except Exception:
        return {}

def attach_oasa(live, stop_id):
    """Tag a live response with official predictions for `stop_id` (fetched now)."""
    if live is not None and stop_id:
        live['oasa'] = {'stop': str(stop_id), 'at': time.time(), 'eta': get_oasa_arrivals(stop_id)}
    return live

def official_eta_s(live, vehicle_id, stop_id, now):
    """Seconds until `vehicle_id` reaches `stop_id` per OASA, or None if unknown."""
    o = (live or {}).get('oasa') or {}
    if o.get('stop') != str(stop_id):
        return None
    m = o.get('eta', {}).get(str(vehicle_id))
    return None if m is None else max(0.0, m * 60 - (now - o['at']))


def oasa_call(act, *args, **named):
    """POST to the OASA telematics API (it ignores GET). Raises on failure.

    Positional args are sent as p1, p2, …; keyword args keep their names (e.g. line_code)."""
    t0 = time.perf_counter()
    q = {'act': act}
    q.update({f'p{i}': v for i, v in enumerate(args, 1)})
    q.update(named)
    try:
        r = requests.post(OASA_API, params=q, headers={'User-Agent': 'Mozilla/5.0'}, timeout=15)
        r.raise_for_status()
        data = r.json() or []
        log(f'OASA {act} -> {r.status_code} {len(r.content)}B {int((time.perf_counter() - t0) * 1000)}ms')
        return data
    except Exception as e:
        log(f'OASA {act} FAILED after {int((time.perf_counter() - t0) * 1000)}ms: {e}', 'ERROR')
        raise


def get_closest_stops(lat, lon, limit=NEAR_STOPS_LIMIT):
    """Nearest stops of any line: [{id, name, lat, lon}], nearest first."""
    stops = []
    for s in oasa_call('getClosestStops', lat, lon)[:limit]:
        try:
            stops.append({'id': str(s['StopCode']), 'name': s.get('StopDescr') or s.get('StopDescrEng') or 'Unnamed stop',
                          'street': s.get('StopStreet') or '', 'lat': float(s['StopLat']), 'lon': float(s['StopLng'])})
        except (KeyError, TypeError, ValueError):
            continue
    return stops


def get_stop_lines(stop_id):
    """Every line serving a stop, with the next official arrivals (minutes), soonest first.

    [{line, name, line_code, route_codes, routes, etas, sched}]: one entry per line, its route
    variants merged. Lines with no bus on the road get `sched`, a timetable-based estimate
    (see oasa.schedule), or None when nothing more runs today."""
    routes = oasa_call('webRoutesForStop', stop_id)
    try:
        arrivals = oasa_call('getStopArrivals', stop_id)
    except Exception:
        arrivals = []  # lines are still worth showing without times
    by_route = {}
    for a in arrivals:
        try:
            by_route.setdefault(str(a['route_code']), []).append(int(a['btime2']))
        except (KeyError, TypeError, ValueError):
            continue
    lines = {}
    for r in routes:
        if str(r.get('hidden', '0')) == '1' or not r.get('LineID'):
            continue
        ln = lines.setdefault(r['LineID'], {'line': r['LineID'], 'name': r.get('RouteDescr') or r.get('LineDescr') or '',
                                            'line_code': str(r.get('LineCode') or ''), 'route_codes': [],
                                            'routes': [], 'etas': []})
        code = str(r.get('RouteCode'))
        if code not in ln['route_codes']:  # OASA repeats routes
            ln['route_codes'].append(code)
            ln['routes'].append((code, str(r.get('RouteType') or '1')))
            ln['etas'].extend(by_route.get(code, []))
    out = list(lines.values())
    for ln in out:
        ln['etas'] = sorted(set(ln['etas']))
        ln['sched'] = None
    idle = [ln for ln in out if not ln['etas'] and ln['line_code']]
    if idle:
        from oasa.schedule import scheduled_arrival  # imported here: schedule.py imports this module

        def estimate(ln):
            try:
                ln['sched'] = scheduled_arrival(ln['line_code'], ln['routes'], str(stop_id))
            except Exception as e:
                log(f'schedule for line {ln["line"]} failed: {e}', 'WARN')
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(estimate, idle))

    def sort_key(ln):
        if ln['etas']:
            return (0, ln['etas'][0], ln['line'])
        if ln['sched']:
            return (0, ln['sched']['eta_min'], ln['line'])
        return (1, 0, ln['line'])
    out.sort(key=sort_key)
    return out
