"""Check GitHub for a newer BusMakro release."""
import re
import requests
from oasa import __version__
from oasa.debug import log

LATEST_URL = 'https://api.github.com/repos/tassosmak/BusMakro/releases/latest'


def _parse(v):
    return tuple(int(x) for x in re.findall(r'\d+', v or '')[:3]) or (0,)


def check():
    """(newer version, release page URL), or None when this is the latest. Raises on network errors."""
    r = requests.get(LATEST_URL, headers={'Accept': 'application/vnd.github+json'}, timeout=10)
    r.raise_for_status()
    data = r.json()
    latest = str(data.get('tag_name') or '').lstrip('v')
    log(f'update check: running {__version__}, latest {latest}')
    if _parse(latest) > _parse(__version__):
        return latest, data.get('html_url') or 'https://github.com/tassosmak/BusMakro/releases/latest'
    return None
