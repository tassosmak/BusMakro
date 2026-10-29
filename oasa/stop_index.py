"""Every stop of every line, for searching by name (OASA has no stop-name search).

Built from the static line files (one per line) in the background, then cached on disk
for a day in ~/Library/Caches/BusMakro/stop_index.json, so later launches load instantly.
Matching ignores accents and works in Greek or Latin letters ("syntagma" finds ΣΥΝΤΑΓΜΑ).
"""
import json, os, re, time
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote
from oasa.api import get_json
from oasa.config import STATIC_BASE
from oasa.debug import log
from oasa.i18n import transliterate

CACHE = os.path.expanduser('~/Library/Caches/BusMakro/stop_index.json')
MAX_AGE_S = 24 * 3600


def normalize(text):
    """Lower-case Latin letters and digits only: 'Πλ. Ελευθερίας' and 'pl eleftherias' match."""
    return re.sub(r'[^a-z0-9]+', ' ', transliterate(text or '').lower()).strip()


def _load_cache():
    try:
        if time.time() - os.path.getmtime(CACHE) < MAX_AGE_S:
            with open(CACHE, encoding='utf-8') as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    return None


def build(line_ids):
    """{stop id: {name, lat, lon, lines: [line ids]}} (from the cache when it is fresh)."""
    cached = _load_cache()
    if cached:
        log(f'stop index: {len(cached)} stops from cache')
        return cached
    stops = {}

    def one(lid):
        try:
            return lid, get_json(f'{STATIC_BASE}/lines/{quote(lid, safe="")}.json').get('stops', {})
        except Exception:
            return lid, None
    t0 = time.time()
    failed = 0
    with ThreadPoolExecutor(max_workers=8) as pool:
        for lid, line_stops in pool.map(one, line_ids):
            if line_stops is None:
                failed += 1
                continue
            for sid, s in line_stops.items():
                if s.get('lat') is None or s.get('lon') is None:
                    continue
                e = stops.setdefault(str(sid), {'name': s.get('name') or '', 'lat': s['lat'], 'lon': s['lon'], 'lines': []})
                if lid not in e['lines']:
                    e['lines'].append(lid)
    log(f'stop index: built {len(stops)} stops in {time.time() - t0:.1f}s ({failed} lines failed)')
    if not stops:
        raise ConnectionError('no line data could be downloaded')
    if failed > len(line_ids) * 0.05:
        return stops  # incomplete (bad connection?): use it now, but don't cache it for a day
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, 'w', encoding='utf-8') as f:
            json.dump(stops, f, ensure_ascii=False)
    except OSError as e:
        log(f'stop index: cache not written: {e}', 'WARN')
    return stops


def search(index, query, limit=20):
    """Stops whose name contains the query, best first: exact name, then word starts, then anywhere."""
    q = normalize(query)
    if not q or not index:
        return []
    exact, starts, contains = [], [], []
    for sid, s in index.items():
        n = s.get('_norm')
        if n is None:
            n = s['_norm'] = normalize(s['name'])
        if n == q:
            exact.append((sid, s))
        elif n.startswith(q) or f' {q}' in n:
            starts.append((sid, s))
        elif q in n or q == sid:
            contains.append((sid, s))
    key = lambda x: x[1]['name']
    return (sorted(exact, key=key) + sorted(starts, key=key) + sorted(contains, key=key))[:limit]
