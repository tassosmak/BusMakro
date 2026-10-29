"""Favourite stops, kept in NSUserDefaults ('favorites') as a list of small dicts."""
from Foundation import NSUserDefaults

_KEY = 'favorites'
_FIELDS = ('id', 'name', 'name_en', 'street', 'street_en', 'lat', 'lon')


def load():
    raw = NSUserDefaults.standardUserDefaults().arrayForKey_(_KEY) or []
    out = []
    for d in raw:
        try:
            out.append({k: (float(d[k]) if k in ('lat', 'lon') else str(d.get(k) or '')) for k in _FIELDS if k in d})
        except (KeyError, TypeError, ValueError):
            continue
    return [f for f in out if f.get('id') and 'lat' in f and 'lon' in f]


def _save(favs):
    NSUserDefaults.standardUserDefaults().setObject_forKey_(favs, _KEY)


def is_favorite(stop_id):
    return any(f['id'] == str(stop_id) for f in load())


def toggle(stop):
    """Add or remove `stop`; returns True if it is now a favourite."""
    favs = load()
    sid = str(stop['id'])
    if any(f['id'] == sid for f in favs):
        _save([f for f in favs if f['id'] != sid])
        return False
    favs.append({k: stop.get(k) or ('' if k not in ('lat', 'lon') else 0.0) for k in _FIELDS})
    favs[-1]['id'] = sid
    _save(favs)
    return True
