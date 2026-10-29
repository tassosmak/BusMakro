"""Recently opened stops (newest first), kept in NSUserDefaults ('recents') like the favourites."""
from Foundation import NSUserDefaults
from oasa.favorites import _FIELDS

_KEY = 'recents'
MAX = 6


def load():
    out = []
    for d in NSUserDefaults.standardUserDefaults().arrayForKey_(_KEY) or []:
        try:
            out.append({k: (float(d[k]) if k in ('lat', 'lon') else str(d.get(k) or '')) for k in _FIELDS if k in d})
        except (KeyError, TypeError, ValueError):
            continue
    return [r for r in out if r.get('id') and 'lat' in r and 'lon' in r]


def add(stop):
    """Put `stop` first (once)."""
    sid = str(stop['id'])
    entry = {k: stop.get(k) or ('' if k not in ('lat', 'lon') else 0.0) for k in _FIELDS}
    entry['id'] = sid
    rest = [r for r in load() if r['id'] != sid]
    NSUserDefaults.standardUserDefaults().setObject_forKey_(([entry] + rest)[:MAX], _KEY)
