"""Build BusMakro as a macOS .app bundle.

macOS only shows the location permission prompt for a real app bundle whose
Info.plist explains why it needs your location; a plain `python main.py` is
silently denied.

Development build (fast, runs the source in place; rebuild only when this file changes):
    python setup.py py2app -A
Standalone release build (also bundles conda's shared libraries, signs and zips):
    python tools/build_app.py

The app ends up in dist/BusMakro.app.
"""
from setuptools import setup
from oasa import __version__ as VERSION

APP_NAME = 'BusMakro'

setup(
    name=APP_NAME,
    app=['main.py'],
    data_files=[],
    version=VERSION,
    options={'py2app': {
        'iconfile': 'resources/icon.icns',
        'packages': ['oasa', 'requests', 'certifi'],
        'includes': ['CoreLocation', 'WebKit'],
        'excludes': ['tkinter', 'setuptools', 'pip', 'pytest'],
        'plist': {
            'CFBundleName': APP_NAME,
            'CFBundleDisplayName': APP_NAME,
            'CFBundleIdentifier': 'com.tassosmak.busmakro',
            'CFBundleShortVersionString': VERSION,
            'CFBundleVersion': VERSION,
            'CFBundleDevelopmentRegion': 'en',
            'CFBundleLocalizations': ['en', 'el'],
            'LSMinimumSystemVersion': '11.0',
            'LSApplicationCategoryType': 'public.app-category.travel',
            'NSHumanReadableCopyright': 'Unofficial app. Data: OASA, athens-transit-rt. Map: CARTO, OpenStreetMap contributors.',
            'NSLocationWhenInUseUsageDescription': 'BusMakro uses your location to show the bus stops nearest to you.',
            'NSLocationUsageDescription': 'BusMakro uses your location to show the bus stops nearest to you.',
            'NSHighResolutionCapable': True,
        },
    }},
    setup_requires=['py2app'],
)
