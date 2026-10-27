"""Makro OASA — native macOS AppKit GUI, mobile-style layout, with a MapLibre GL map.

Install in the project's conda environment:
    python -m pip install pyobjc-framework-Cocoa pyobjc-framework-WebKit pyobjc-framework-CoreLocation requests
Run:
    python main.py            # normal
    python main.py --debug    # debug info in the terminal and in the app
    MAKRO_DEBUG=1 python main.py"""
from AppKit import NSApplication, NSApplicationActivationPolicyRegular
from oasa.app.core import OasaNativeApp


def main():
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    delegate = OasaNativeApp.alloc().init()
    app.setDelegate_(delegate)
    app.run()


if __name__ == '__main__':
    main()
