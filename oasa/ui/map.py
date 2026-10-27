"""The MapLibre GL map page shown in the WKWebView (see map.html)."""
import os



_HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(_HERE, 'map.html'), encoding='utf-8') as _f:
    HTML_MAP = _f.read()
