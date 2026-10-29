"""What BusMakro learns from watching OASA's predictions over time (kept on this Mac only).

Every time the app reads a stop's arrivals (stop screen, favourites, menu bar) the
predictions are fed to `observe`. Following each bus from one reading to the next tells us:

  * when it really arrived (its prediction reached ~1 min, then it left the list), so every
    earlier prediction for it can be scored: actual - predicted  ->  `bias_s` (learned ETA)
  * when it vanished: OASA predicted it several minutes away, then it dropped out of the
    list without arriving  ->  `ghost_rate` ("ghost buses")

Conclusions are only drawn between readings less than GAP_S apart, so a closed laptop or a
stop that was viewed once never counts as a vanished bus.
"""
import json, os, statistics, threading, time
from oasa.debug import log

PATH = os.path.expanduser('~/Library/Application Support/BusMakro/history.json')
GAP_S = 150             # readings further apart than this are not compared
ARRIVED_MIN = 1         # a bus whose last prediction was <= this and then left the list arrived
VANISHED_MIN = 4        # one that left the list while still >= this far away vanished
MAX_SAMPLES = 60        # error samples kept per line and horizon
MIN_SAMPLES = 5         # before a learned correction is used
MIN_EVENTS = 8          # before a ghost rate is shown
BUCKETS = (5, 10, 20)   # prediction horizons (min): 0-5, 5-10, 10-20, 20+
SAVE_EVERY_S = 60

_lock = threading.Lock()
_data = None            # {'lines': {line: {'err': {bucket: [s...]}, 'arrived': n, 'vanished': n}}}
_open = {}              # stop id -> {'at': t, 'buses': {veh: {line, last_min, preds: [(t, arrival_t)]}}}
_saved_at = 0.0


def _bucket(minutes):
    for i, b in enumerate(BUCKETS):
        if minutes < b:
            return str(i)
    return str(len(BUCKETS))


def _load():
    global _data
    if _data is None:
        try:
            with open(PATH) as f:
                _data = json.load(f)
        except (OSError, ValueError):
            _data = None
        if not isinstance(_data, dict):
            _data = {}
        _data.setdefault('lines', {})
    return _data


def _save(force=False):
    global _saved_at
    if not force and time.time() - _saved_at < SAVE_EVERY_S:
        return
    _saved_at = time.time()
    try:
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        tmp = PATH + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(_data, f)
        os.replace(tmp, PATH)
    except OSError as e:
        log(f'history: save failed: {e}', 'WARN')


def _line(line):
    return _load()['lines'].setdefault(line, {'err': {}, 'arrived': 0, 'vanished': 0})


def observe(stop_id, arrivals, now=None):
    """Feed one reading of a stop: [(line, vehicle id, minutes)]."""
    now = now or time.time()
    sid = str(stop_id)
    with _lock:
        prev = _open.get(sid)
        seen = {}
        for line, veh, minutes in arrivals:
            if veh:
                seen[str(veh)] = (line, float(minutes))
        buses = {}
        if prev and now - prev['at'] <= GAP_S:
            for veh, b in prev['buses'].items():
                if veh in seen:
                    continue
                st = _line(b['line'])
                if b['last_min'] <= ARRIVED_MIN:  # arrived: score every prediction made for it
                    arrived_at = prev['at'] + b['last_min'] * 60
                    st['arrived'] += 1
                    for t_pred, predicted in b['preds']:
                        horizon = (arrived_at - t_pred) / 60
                        if horizon >= 0.5:
                            errs = st['err'].setdefault(_bucket(horizon), [])
                            errs.append(round(arrived_at - predicted))
                            del errs[:-MAX_SAMPLES]
                elif b['last_min'] >= VANISHED_MIN:
                    st['vanished'] += 1
                    log(f'history: bus {veh} (line {b["line"]}) vanished {b["last_min"]:.0f} min out at stop {sid}')
            keep = prev['buses']
        else:
            keep = {}
        for veh, (line, minutes) in seen.items():
            b = keep.get(veh) or {'line': line, 'preds': []}
            b['line'], b['last_min'] = line, minutes
            if not b['preds'] or now - b['preds'][-1][0] >= 55:  # about one scored prediction a minute
                b['preds'] = (b['preds'] + [(now, now + minutes * 60)])[-30:]
            buses[veh] = b
        _open[sid] = {'at': now, 'buses': buses}
        _save()


def bias_s(line, minutes):
    """Median seconds buses of `line` arrived later (+) or earlier (-) than OASA predicted at this
    horizon, or None while there are too few samples."""
    with _lock:
        errs = _load()['lines'].get(line, {}).get('err', {}).get(_bucket(minutes)) or []
    return statistics.median(errs) if len(errs) >= MIN_SAMPLES else None


def learned_min(line, minutes):
    """OASA's prediction corrected by what we have learned (never more than half of it, or 5 min)."""
    b = bias_s(line, minutes)
    if b is None or abs(b) < 60:
        return None
    shift = max(-min(minutes * 30, 300), min(min(minutes * 30, 300), b))
    return max(0, round(minutes + shift / 60))


def ghost_rate(line):
    """(share of predicted buses that vanished, events) or None while there are too few."""
    with _lock:
        st = _load()['lines'].get(line)
    if not st:
        return None
    n = st['arrived'] + st['vanished']
    return (st['vanished'] / n, n) if n >= MIN_EVENTS else None


def flush():
    with _lock:
        if _data is not None:
            _save(force=True)
