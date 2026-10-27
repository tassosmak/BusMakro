"""Build Makro OASA as a macOS .app bundle.

macOS only shows the location permission prompt for a real app bundle whose
Info.plist explains why it needs your location; a plain `python main.py` is
silently denied.

Development build (fast, runs the source in place; rebuild only when this file changes):
    python setup.py py2app -A
Standalone build (copies Python and all packages into the app):
    python setup.py py2app

The app ends up in dist/Makro OASA.app.
"""
from setuptools import setup

APP_NAME = 'Makro OASA'

setup(
    name=APP_NAME,
    app=['main.py'],
    data_files=[],
    options={'py2app': {
        'packages': ['oasa'],
        'includes': ['CoreLocation', 'WebKit'],
        'plist': {
            'CFBundleName': APP_NAME,
            'CFBundleDisplayName': APP_NAME,
            'CFBundleIdentifier': 'com.tassosmak.makro-oasa',
            'CFBundleShortVersionString': '1.0.0',
            'NSLocationWhenInUseUsageDescription': 'Makro OASA uses your location to show the bus stops nearest to you.',
            'NSLocationUsageDescription': 'Makro OASA uses your location to show the bus stops nearest to you.',
            'NSHighResolutionCapable': True,
        },
    }},
    setup_requires=['py2app'],
)
