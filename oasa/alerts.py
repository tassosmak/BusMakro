"""Service alerts from OASA's announcements (oasa.gr RSS feeds), matched to line numbers.

OASA's telematics API has no alerts, but oasa.gr posts each disruption as an announcement in
the "Alerts" category, naming the lines in the title ("…της λεωφορειακής γραμμής 046…",
"…of bus line X24…"). Line numbers are only read after the word for line(s), and only ones
that are real lines, so dates and street numbers aren't mistaken for lines.
"""
import html, re, time
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
import requests
from oasa.debug import log

FEEDS = ('https://www.oasa.gr/feed/', 'https://www.oasa.gr/en/feed/')
MAX_AGE_DAYS = 14
# the line list starts after "γραμμή/γραμμής/γραμμών/line(s)" and ends at a word that starts the rest
_AFTER = re.compile(r'(γραμμ\w*|lines?)\s+(.*)', re.I)
_STOP = re.compile(r'\s(λόγω|στον|στην|στο|στη|στις|από|για|due|on|in|from|at|during)\s', re.I)
_TOKEN = re.compile(r'[A-ZΑ-Ω]?\d{1,3}[A-ZΑ-Ω]?', re.I)
_LATIN = str.maketrans({'A': 'Α', 'B': 'Β', 'E': 'Ε', 'X': 'Χ', 'a': 'Α', 'b': 'Β', 'e': 'Ε', 'x': 'Χ'})


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
    """[{title, link, date, lines}] of recent alerts naming at least one known line, newest first."""
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
            if 'alerts' not in cats:
                continue
            title = html.unescape((it.findtext('title') or '').strip())
            link = (it.findtext('link') or '').strip()
            try:
                when = parsedate_to_datetime(it.findtext('pubDate'))
            except (TypeError, ValueError):
                continue
            if when.timestamp() < cutoff or link in seen:
                continue
            lines = lines_in(title, known)
            if lines:
                seen.add(link)
                out.append({'title': re.sub(r'\s+', ' ', title), 'link': link, 'date': when, 'lines': lines})
    out.sort(key=lambda a: a['date'], reverse=True)
    log(f'alerts: {len(out)} recent alerts for {len({l for a in out for l in a["lines"]})} lines')
    return out


def for_lines(alerts, line_ids):
    """The alerts that mention any of `line_ids`."""
    ids = set(line_ids)
    return [a for a in alerts or [] if a['lines'] & ids]
