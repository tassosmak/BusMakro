"""Network access: transit.haroldpoi.dev / static data and official OASA predictions."""
import time
import requests
from oasa.config import OASA_API
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
