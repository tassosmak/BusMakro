"""Service alerts from OASA's announcements (oasa.gr RSS feeds), matched to line numbers.

OASA's telematics API has no alerts, but oasa.gr posts each disruption as an announcement in
the "Alerts" category, naming the lines in the title ("…της λεωφορειακής γραμμής 046…",
"…of bus line X24…"). Line numbers are only read after the word for line(s), and only ones
that are real lines, so dates and street numbers aren't mistaken for lines.
"""
import html, re, time
import xml.etree.ElementTree as ET
from datetime import date, timedelta
from email.utils import parsedate_to_datetime
import requests
from oasa.debug import log

FEEDS = ('https://www.oasa.gr/feed/', 'https://www.oasa.gr/en/feed/')
MAX_AGE_DAYS = 14
# the line list starts after "γραμμή/γραμμής/γραμμών/line(s)" and ends at a word that starts the rest
_AFTER = re.compile(r'(γραμμ\w*|lines?)\s+(.*)', re.I)
_STOP = re.compile(r'\s(λόγω|στον|στην|στο|στη|στις|από|για|due|on|in|from|at|during)\s', re.I)
_TOKEN = re.compile(r'[A-ZΑ-Ω]?\d{1,3}[A-ZΑ-Ω]?', re.I)
# strike radar: work stoppages / strikes, announced days ahead (any category, no line needed)
_STRIKE = re.compile(r'στάσ\w* εργασίας|απεργ\w*|strike|work stoppage', re.I)
NETWORK_MAX_AGE_DAYS = 3   # a whole-network notice that names no date is dropped this long after posting
# dates named in a title ("28ης Οκτωβρίου", "September 13 & 14", "29/10"): a notice whose dates have all passed is old
_MONTHS = {m: i for i, ms in enumerate((
    ('ιαν', 'jan'), ('φεβ', 'feb'), ('μαρ', 'mar'), ('απρ', 'apr'), ('μαΐ', 'μαι', 'may'), ('ιουν', 'jun'),
    ('ιουλ', 'jul'), ('αυγ', 'aug'), ('σεπ', 'sep'), ('οκτ', 'oct'), ('νοε', 'nov'), ('δεκ', 'dec')), 1) for m in ms}
_DAY_MONTH = re.compile(r'(\d{1,2})(?:η|ης|st|nd|rd|th)?\s+([A-Za-zΑ-Ωα-ωάέήίόύώΐϊ]{3,})', re.I)
_MONTH_DAY = re.compile(r'([A-Za-z]{3,})\s+(\d{1,2})(?:\s*(?:&|and|-|και)\s*(\d{1,2}))?', re.I)
_NUMERIC = re.compile(r'\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?\b')
_LATIN = str.maketrans({'A': 'Α', 'B': 'Β', 'E': 'Ε', 'X': 'Χ', 'a': 'Α', 'b': 'Β', 'e': 'Ε', 'x': 'Χ'})


def _month(word):
    w = word.lower()
    return next((n for k, n in _MONTHS.items() if w.startswith(k)), None)


def dates_in(title, posted):
    """The days a notice is about, read from its title (the year is the one after it was posted)."""
    found = []
    for d, w in _DAY_MONTH.findall(title):
        if _month(w):
            found.append((_month(w), int(d)))
    for w, d1, d2 in _MONTH_DAY.findall(title):
        if _month(w):
            found += [(_month(w), int(d)) for d in (d1, d2) if d]
    for d, m, _ in _NUMERIC.findall(title):
        if 1 <= int(m) <= 12:
            found.append((int(m), int(d)))
    out = []
    for m, d in found:
        try:
            day = posted.date().replace(month=m, day=d)
        except ValueError:
            continue
        if day < posted.date() - timedelta(days=60):  # "5 January" posted in December
            day = day.replace(year=day.year + 1)
        out.append(day)
    return out


def lines_in(title, known):
    """Line ids named in an announcement title (only ids in `known`)."""
    m = _AFTER.search(title or '')
    if not m:
        return set()
    part = _STOP.split(' ' + m.group(2) + ' ', maxsplit=1)[0]
    found = set()
    for tok in _TOKEN.findall(part):
        for cand in (tok, tok.upper().translate(_LATIN), tok.upper()):
            if cand in known:
                found.add(cand)
                break
    return found


def fetch(known_lines):
    """[{title, link, date, lines, strike}] newest first: recent alerts naming at least one known line,
    plus network-wide notices (no lines; `strike` True for strikes and work stoppages)."""
    known = set(known_lines)
    out, seen = [], set()
    cutoff = time.time() - MAX_AGE_DAYS * 86400
    for url in FEEDS:
        try:
            r = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'}, timeout=15)
            r.raise_for_status()
            root = ET.fromstring(r.content)
        except Exception as e:
            log(f'alerts: {url} failed: {e}', 'WARN')
            continue
        for it in root.iter('item'):
            cats = {(c.text or '').strip().lower() for c in it.findall('category')}
            title = html.unescape((it.findtext('title') or '').strip())
            strike = bool(_STRIKE.search(title))
            if 'alerts' not in cats and not strike:
                continue
            link = (it.findtext('link') or '').strip()
            try:
                when = parsedate_to_datetime(it.findtext('pubDate'))
            except (TypeError, ValueError):
                continue
            if when.timestamp() < cutoff or link in seen:
                continue
            lines = lines_in(title, known)
            days = dates_in(title, when)
            if days and max(days) < date.today():
                continue  # every day it is about has passed
            network = not lines and (strike or not _AFTER.search(title)) and (
                bool(days) or when.timestamp() >= time.time() - NETWORK_MAX_AGE_DAYS * 86400)
            if lines or network:
                seen.add(link)
                out.append({'title': re.sub(r'\s+', ' ', title), 'link': link, 'date': when, 'lines': lines,
                            'strike': strike})
    out.sort(key=lambda a: a['date'], reverse=True)
    log(f'alerts: {len(out)} recent alerts for {len({l for a in out for l in a["lines"]})} lines')
    return out


def for_lines(alerts, line_ids):
    """The alerts that mention any of `line_ids`."""
    ids = set(line_ids)
    return [a for a in alerts or [] if a['lines'] & ids]


def network(alerts):
    """Notices about the whole network (strikes first), not tied to a line."""
    return sorted((a for a in alerts or [] if not a['lines']), key=lambda a: (not a['strike'], -a['date'].timestamp()))
